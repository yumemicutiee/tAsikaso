import Anthropic from "@anthropic-ai/sdk";
import express, {
  type NextFunction,
  type Request,
  type Response,
} from "express";
import { z } from "zod";

import {
  checkAnswer,
  EFFORT,
  generateQuiz,
  generateStudyKit,
  type Generated,
  MODEL,
  RefusedError,
  TooLongError,
} from "./claude.js";
import {
  CheckAnswerRequest,
  QuizRequest,
  StudyKitRequest,
} from "./schemas.js";

/** An error with the HTTP status and a short code the app can switch on. */
export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "HttpError";
  }
}

export interface AppOptions {
  /** Clients must send `Authorization: Bearer <token>`. Empty = open. */
  appToken?: string;
  /** Requests allowed per client IP in each 10-minute window. */
  rateLimit?: number;
  /** Behind Render, Railway, nginx etc. the client IP is in X-Forwarded-For. */
  trustProxy?: boolean;
}

export function createApp(options: AppOptions = {}) {
  const app = express();
  app.disable("x-powered-by");
  if (options.trustProxy) app.set("trust proxy", 1);

  // The Flutter web build runs on another origin.
  app.use((req, res, next) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    if (req.method === "OPTIONS") {
      res.status(204).end();
      return;
    }
    next();
  });

  app.use(express.json({ limit: "2mb" }));

  app.get("/health", (_req, res) => {
    res.json({ ok: true, model: MODEL, effort: EFFORT });
  });

  app.use(requireToken(options.appToken ?? ""));
  app.use(rateLimiter(options.rateLimit ?? 30));

  app.post("/v1/study-kit", handle(StudyKitRequest, generateStudyKit, "kit"));
  app.post("/v1/quiz", handle(QuizRequest, generateQuiz, "quiz"));
  app.post("/v1/check-answer", handle(CheckAnswerRequest, checkAnswer, "check"));

  app.use((_req, res) => {
    res.status(404).json(errorBody("not_found", "No such endpoint."));
  });
  app.use(errorHandler);
  return app;
}

/** Validates the body with [schema], runs [work], and replies with its result under [key]. */
function handle<I, O>(
  schema: z.ZodType<I>,
  work: (input: I) => Promise<Generated<O>>,
  key: string,
) {
  return async (req: Request, res: Response, next: NextFunction) => {
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      const issue = parsed.error.issues[0];
      const where = issue?.path.length ? `${issue.path.join(".")}: ` : "";
      next(new HttpError(400, "bad_request", where + (issue?.message ?? "Bad request.")));
      return;
    }
    try {
      const result = await work(parsed.data);
      console.log(
        `${req.path} ${result.model} in=${result.inputTokens} out=${result.outputTokens} ${result.ms}ms`,
      );
      res.json({
        [key]: result.data,
        model: result.model,
        usage: { input: result.inputTokens, output: result.outputTokens },
      });
    } catch (e) {
      next(e);
    }
  };
}

function requireToken(token: string) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!token) {
      next();
      return;
    }
    const header = req.header("authorization") ?? "";
    const given = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
    if (given !== token) {
      next(new HttpError(401, "unauthorized", "This app isn't allowed to use the server."));
      return;
    }
    next();
  };
}

/** A small in-memory limiter: fine for one server; use a shared store for several. */
function rateLimiter(limit: number) {
  const windowMs = 10 * 60 * 1000;
  const hits = new Map<string, number[]>();
  return (req: Request, _res: Response, next: NextFunction) => {
    const now = Date.now();
    const key = req.ip ?? "unknown";
    const recent = (hits.get(key) ?? []).filter((t) => now - t < windowMs);
    if (recent.length >= limit) {
      hits.set(key, recent);
      next(
        new HttpError(
          429,
          "rate_limited",
          "Too many requests from this device. Please wait a few minutes.",
        ),
      );
      return;
    }
    recent.push(now);
    hits.set(key, recent);
    if (hits.size > 10_000) {
      // Forget quiet clients so the map can't grow forever.
      for (const [k, v] of hits) {
        if (v.every((t) => now - t >= windowMs)) hits.delete(k);
      }
    }
    next();
  };
}

function errorBody(code: string, message: string) {
  return { error: { code, message } };
}

function errorHandler(
  err: unknown,
  _req: Request,
  res: Response,
  _next: NextFunction,
) {
  const reply = (status: number, code: string, message: string) =>
    res.status(status).json(errorBody(code, message));

  if (err instanceof HttpError) return reply(err.status, err.code, err.message);
  if (err instanceof RefusedError) {
    return reply(422, "declined", "Claude couldn't work with these notes.");
  }
  if (err instanceof TooLongError) {
    return reply(413, "too_long", "These notes are too long for one go. Try fewer pages.");
  }
  if (err instanceof SyntaxError && "status" in err) {
    // express.json couldn't parse the body
    return reply(400, "bad_request", "The request body isn't valid JSON.");
  }
  if (err instanceof Anthropic.AuthenticationError) {
    console.error("Claude rejected the API key:", err.message);
    return reply(500, "server_key", "The server's Claude API key is missing or wrong.");
  }
  if (err instanceof Anthropic.RateLimitError) {
    return reply(429, "busy", "The study server is busy. Please try again in a minute.");
  }
  if (err instanceof Anthropic.APIConnectionError) {
    console.error("Could not reach Claude:", err.message);
    return reply(502, "upstream", "The server couldn't reach Claude. Please try again.");
  }
  if (err instanceof Anthropic.APIError) {
    console.error(`Claude error ${err.status}:`, err.message);
    return reply(502, "upstream", "Claude returned an error. Please try again.");
  }
  console.error(err);
  return reply(500, "internal", "Something went wrong on the server.");
}
