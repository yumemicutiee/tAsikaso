import { createHash, randomUUID, timingSafeEqual } from "node:crypto";

import Anthropic from "@anthropic-ai/sdk";
import express, {
  type NextFunction,
  type Request,
  type Response,
} from "express";
import type { z } from "zod";

import {
  BadOutputError,
  type CallOptions,
  type CallUsage,
  CHECK_EFFORT,
  checkAnswer,
  ClaudeCallError,
  EFFORT,
  generateQuiz,
  generateStudyKit,
  type Generated,
  MODEL,
  RefusedError,
  TooLongError,
} from "./claude.js";
import { DEFAULTS } from "./config.js";
import { type Admission, DailyLedger, type RequestKind } from "./ledger.js";
import { jsonLogger, type Logger } from "./log.js";
import {
  type AnswerCheck,
  CheckAnswerRequest,
  type Quiz,
  QuizRequest,
  type StudyKit,
  StudyKitRequest,
} from "./schemas.js";

/** An error with the HTTP status and a short code the app can switch on. */
export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly headers: Record<string, string> = {},
  ) {
    super(message);
    this.name = "HttpError";
  }
}

type Work<I, O> = (input: I, call: CallOptions) => Promise<Generated<O>>;

/** The Claude calls behind the three POST routes; tests swap in fakes. */
export interface Generators {
  studyKit: Work<StudyKitRequest, StudyKit>;
  quiz: Work<QuizRequest, Quiz>;
  checkAnswer: Work<CheckAnswerRequest, AnswerCheck>;
}

export interface AppOptions {
  /** Clients must send `Authorization: Bearer <token>`. Empty = open. */
  appToken?: string;
  /** Requests allowed per client IP in each 10-minute window. */
  rateLimit?: number;
  /**
   * Behind Render, Railway, nginx etc. the client IP is in X-Forwarded-For:
   * the number of proxies in front of the server (true = 1).
   */
  trustProxy?: boolean | number;
  /** Study kits + quizzes per client per day (0 = no limit). */
  dailyLimit?: number;
  /** Answer checks per client per day (0 = no limit). */
  dailyCheckLimit?: number;
  /** Estimated Claude spend per day for the whole server, in dollars (0 = no cap). */
  dailyBudgetUsd?: number;
  /** Where the day starts for the daily limits. */
  timeZone?: string;
  /** /health also reports the model and effort. */
  healthDetails?: boolean;
  generators?: Partial<Generators>;
  log?: Logger;
  /** For tests: the clock the daily limits use. */
  now?: () => number;
}

/** What one request did, for its log line. */
interface RequestContext {
  id: string;
  started: number;
  usage?: CallUsage;
  code?: string;
  /** The client hung up before the answer was ready. */
  clientGone: boolean;
  /** A Claude call is running; its handler writes the log line. */
  pending: boolean;
  logged: boolean;
}

const ctxOf = (res: Response) => res.locals.ctx as RequestContext;

export function createApp(options: AppOptions = {}) {
  const log = options.log ?? jsonLogger;
  const ledger = new DailyLedger({
    timeZone: options.timeZone ?? DEFAULTS.timeZone,
    dailyLimit: options.dailyLimit ?? DEFAULTS.dailyLimit,
    dailyCheckLimit: options.dailyCheckLimit ?? DEFAULTS.dailyCheckLimit,
    budgetUsd: options.dailyBudgetUsd ?? DEFAULTS.dailyBudgetUsd,
    now: options.now,
  });
  const generators: Generators = {
    studyKit: generateStudyKit,
    quiz: generateQuiz,
    checkAnswer,
    ...options.generators,
  };

  const app = express();
  app.disable("x-powered-by");
  // A hop count, never `true`: that would believe whatever X-Forwarded-For
  // a client sends and let it dodge the per-client limits.
  const hops = options.trustProxy === true ? 1 : Number(options.trustProxy ?? 0);
  if (hops > 0) app.set("trust proxy", hops);

  app.use(requestContext(log));

  // The Flutter web build runs on another origin.
  app.use((req, res, next) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Request-Id");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.setHeader("Access-Control-Expose-Headers", "X-Request-Id, Retry-After");
    if (req.method === "OPTIONS") {
      res.status(204).end();
      return;
    }
    next();
  });

  app.use(express.json({ limit: "2mb" }));

  app.get("/health", (_req, res) => {
    res.json(
      options.healthDetails
        ? { ok: true, model: MODEL, effort: EFFORT, checkEffort: CHECK_EFFORT }
        : { ok: true },
    );
  });

  app.use(requireToken(options.appToken ?? ""));

  app.get("/v1/usage", (req, res) => {
    const report = ledger.report(clientKey(req));
    // The address the limits are counted for, so you can check TRUST_PROXY:
    // two phones on different networks should see different addresses.
    res.json({ ...report, you: { ...report.you, address: clientKey(req) } });
  });

  app.use(rateLimiter(options.rateLimit ?? DEFAULTS.rateLimit));

  /**
   * Validates the body with [schema], checks the daily limits, runs [work]
   * and replies with its result under [key]. If the client hangs up first,
   * the Claude call is aborted and nothing is written.
   */
  function handle<I, O>(
    schema: z.ZodType<I>,
    work: Work<I, O>,
    key: string,
    kind: RequestKind,
  ) {
    return async (req: Request, res: Response, next: NextFunction) => {
      const ctx = ctxOf(res);
      const parsed = schema.safeParse(req.body);
      if (!parsed.success) {
        const issue = parsed.error.issues[0];
        const where = issue?.path.length ? `${issue.path.join(".")}: ` : "";
        next(new HttpError(400, "bad_request", where + (issue?.message ?? "Bad request.")));
        return;
      }
      const admission = ledger.admit(clientKey(req), kind, req.path);
      if (!admission.ok) {
        next(refusal(admission, ledger.secondsToMidnight()));
        return;
      }

      const controller = new AbortController();
      const onClose = () => {
        if (!res.writableFinished) controller.abort();
      };
      res.on("close", onClose);
      // Gone already (hung up between sending the body and this point)?
      if (req.socket.destroyed) controller.abort();
      ctx.pending = true;
      try {
        const result = await work(parsed.data, { signal: controller.signal });
        ctx.usage = usageFields(result);
        ledger.record(result);
        if (controller.signal.aborted) {
          ctx.clientGone = true;
          return;
        }
        res.json({
          [key]: result.data,
          model: result.model,
          usage: { input: result.inputTokens, output: result.outputTokens },
        });
      } catch (e) {
        if (e instanceof ClaudeCallError && e.usage) {
          ctx.usage = e.usage;
          ledger.record(e.usage);
        }
        if (controller.signal.aborted) {
          ctx.clientGone = true;
          return;
        }
        next(e);
      } finally {
        res.off("close", onClose);
        ctx.pending = false;
        // The connection is already closed, so no 'close' event is coming to log it.
        if (ctx.clientGone) writeLog(log, req, res, ctx);
      }
    };
  }

  app.post("/v1/study-kit", handle(StudyKitRequest, generators.studyKit, "kit", "study"));
  app.post("/v1/quiz", handle(QuizRequest, generators.quiz, "quiz", "study"));
  app.post("/v1/check-answer", handle(CheckAnswerRequest, generators.checkAnswer, "check", "check"));

  app.use((_req, _res, next) => {
    next(new HttpError(404, "not_found", "No such endpoint."));
  });
  app.use(errorHandler(log));
  return app;
}

/** The client the limits are counted for: its IP address. */
function clientKey(req: Request): string {
  return req.ip ?? req.socket.remoteAddress ?? "unknown";
}

const REQUEST_ID = /^[\w.:-]{1,128}$/;

/** Gives each request an id (the caller's X-Request-Id if it's sensible) and logs it once it's done. */
function requestContext(log: Logger) {
  return (req: Request, res: Response, next: NextFunction) => {
    const incoming = req.header("x-request-id");
    const ctx: RequestContext = {
      id: incoming && REQUEST_ID.test(incoming) ? incoming : randomUUID(),
      started: Date.now(),
      clientGone: false,
      pending: false,
      logged: false,
    };
    res.locals.ctx = ctx;
    res.setHeader("X-Request-Id", ctx.id);
    res.on("close", () => {
      if (!ctx.pending) writeLog(log, req, res, ctx);
    });
    next();
  };
}

function writeLog(log: Logger, req: Request, res: Response, ctx: RequestContext) {
  if (ctx.logged) return;
  ctx.logged = true;
  // Health checks from the host come every few seconds; they'd drown the rest.
  if (req.method === "OPTIONS" || (req.path === "/health" && res.statusCode < 400)) return;
  const gone = ctx.clientGone || !res.writableFinished;
  const u = ctx.usage;
  log(gone ? "warn" : "info", gone ? "client gone" : "request", {
    requestId: ctx.id,
    method: req.method,
    route: req.path.slice(0, 200),
    status: gone ? 499 : res.statusCode,
    ...(gone ? { code: "cancelled" } : ctx.code ? { code: ctx.code } : {}),
    ms: Date.now() - ctx.started,
    client: createHash("sha256").update(clientKey(req)).digest("hex").slice(0, 12),
    ...(u
      ? {
          model: u.model,
          inputTokens: u.inputTokens,
          outputTokens: u.outputTokens,
          costUsd: Math.round(u.costUsd * 1_000_000) / 1_000_000,
          fallback: u.fallback,
          ...(u.estimated ? { estimated: true } : {}),
        }
      : {}),
  });
}

function usageFields(u: CallUsage): CallUsage {
  return {
    model: u.model,
    inputTokens: u.inputTokens,
    outputTokens: u.outputTokens,
    costUsd: u.costUsd,
    fallback: u.fallback,
    estimated: u.estimated,
  };
}

function sha256(s: string): Buffer {
  return createHash("sha256").update(s).digest();
}

function requireToken(token: string) {
  const expected = sha256(token);
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!token) {
      next();
      return;
    }
    const header = req.header("authorization") ?? "";
    const given = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
    // Compare digests in constant time, so the token can't be guessed from timings.
    if (!given || !timingSafeEqual(sha256(given), expected)) {
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
    const key = clientKey(req);
    const recent = (hits.get(key) ?? []).filter((t) => now - t < windowMs);
    if (recent.length >= limit) {
      hits.set(key, recent);
      const wait = Math.max(1, Math.ceil((windowMs - (now - recent[0]!)) / 1000));
      next(
        new HttpError(
          429,
          "rate_limited",
          "Too many requests from this device. Please wait a few minutes.",
          { "Retry-After": String(wait) },
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

function refusal(a: Exclude<Admission, { ok: true }>, secondsToMidnight: number): HttpError {
  const headers = { "Retry-After": String(secondsToMidnight) };
  if (a.reason === "budget") {
    return new HttpError(
      503,
      "budget",
      "The study server has reached today's limit. Try again tomorrow.",
      headers,
    );
  }
  const what =
    (a.kind === "study" ? "Smart Study request" : "answer check") + (a.limit === 1 ? "" : "s");
  return new HttpError(
    429,
    "daily_limit",
    `You've reached today's limit of ${a.limit} ${what}. Try again tomorrow.`,
    headers,
  );
}

function retryAfter(err: InstanceType<typeof Anthropic.APIError>): string {
  const v = Number(err.headers?.get?.("retry-after"));
  return String(Number.isFinite(v) && v >= 1 ? Math.min(Math.ceil(v), 600) : 30);
}

/** What the app is told about [err]; `detail` is only logged. */
export function describeError(
  err: unknown,
  route: string,
): { error: HttpError; detail?: Record<string, unknown> } {
  const fail = (status: number, code: string, message: string, headers?: Record<string, string>) =>
    new HttpError(status, code, message, headers);
  const what =
    route === "/v1/quiz" ? "these cards" : route === "/v1/check-answer" ? "this answer" : "these notes";

  if (err instanceof HttpError) return { error: err };
  if (err instanceof RefusedError) {
    return {
      error: fail(422, "declined", `Claude couldn't work with ${what}.`),
      detail: { explanation: err.explanation },
    };
  }
  if (err instanceof TooLongError) {
    const message =
      route === "/v1/quiz"
        ? "That quiz is too big to make in one go. Try fewer questions or cards."
        : route === "/v1/check-answer"
          ? "That answer is too long to check."
          : "These notes are too long for one go. Try fewer pages.";
    return { error: fail(413, "too_long", message) };
  }
  if (err instanceof BadOutputError) {
    return {
      error: fail(502, "bad_output", "Claude's answer came back incomplete. Please try again."),
      detail: { detail: err.message },
    };
  }
  if (err instanceof ClaudeCallError) {
    return {
      error: fail(502, "upstream", "Claude had a problem with this request. Please try again."),
      detail: { detail: err.message },
    };
  }

  // express.json couldn't read the body. (SDK errors have a `type` too.)
  const bodyType =
    err instanceof Anthropic.AnthropicError ? undefined : (err as { type?: unknown } | null)?.type;
  if (bodyType === "entity.too.large") {
    return { error: fail(413, "too_long", "These notes are too long for one go. Try fewer pages.") };
  }
  if (bodyType === "entity.parse.failed") {
    return { error: fail(400, "bad_request", "The request body isn't valid JSON.") };
  }
  const bodyStatus = (err as { status?: unknown } | null)?.status;
  if (
    typeof bodyType === "string" &&
    typeof bodyStatus === "number" &&
    bodyStatus >= 400 &&
    bodyStatus < 500
  ) {
    // Unsupported encoding or charset, or the upload was cut off.
    return { error: fail(400, "bad_request", "The request body couldn't be read.") };
  }

  if (err instanceof Anthropic.APIError) {
    const detail = {
      anthropicStatus: err.status ?? null,
      anthropicType: err.type ?? null,
      anthropicRequestId: err.requestID ?? null,
      detail: err.message,
    };
    if (err instanceof Anthropic.AuthenticationError) {
      return {
        error: fail(500, "server_key", "The server's Claude API key is missing or wrong."),
        detail,
      };
    }
    if (
      err.type === "billing_error" ||
      err instanceof Anthropic.PermissionDeniedError ||
      err instanceof Anthropic.NotFoundError
    ) {
      return {
        error: fail(500, "server_setup", "The study server's Claude account isn't set up right. Please try again later."),
        detail,
      };
    }
    if (
      err instanceof Anthropic.RateLimitError ||
      err.status === 529 ||
      err.type === "overloaded_error" ||
      err.type === "rate_limit_error"
    ) {
      return {
        error: fail(503, "busy", "The study server is busy right now. Please try again in a minute.", {
          "Retry-After": retryAfter(err),
        }),
        detail,
      };
    }
    if (
      err instanceof Anthropic.APIConnectionTimeoutError ||
      err.status === 504 ||
      err.type === "timeout_error"
    ) {
      return {
        error: fail(504, "timeout", "Claude took too long to answer. Please try again."),
        detail,
      };
    }
    if (err instanceof Anthropic.APIConnectionError) {
      return {
        error: fail(502, "upstream", "The server couldn't reach Claude. Please try again."),
        detail,
      };
    }
    return {
      error: fail(502, "upstream", "Claude had a problem with this request. Please try again."),
      detail,
    };
  }
  if (err instanceof Anthropic.AnthropicError) {
    return {
      error: fail(502, "upstream", "Claude had a problem with this request. Please try again."),
      detail: { detail: err.message },
    };
  }
  return {
    error: fail(500, "internal", "Something went wrong on the server."),
    detail: { detail: err instanceof Error ? (err.stack ?? err.message) : String(err) },
  };
}

function errorHandler(log: Logger) {
  return (err: unknown, req: Request, res: Response, _next: NextFunction) => {
    const ctx = ctxOf(res);
    const { error, detail } = describeError(err, req.path);
    ctx.code = error.code;
    if (detail) {
      log(error.status >= 500 ? "error" : "warn", "request failed", {
        requestId: ctx.id,
        route: req.path.slice(0, 200),
        code: error.code,
        ...detail,
      });
    }
    if (res.headersSent) {
      res.end();
      return;
    }
    for (const [name, value] of Object.entries(error.headers)) res.setHeader(name, value);
    res.status(error.status).json({
      error: { code: error.code, message: error.message, requestId: ctx.id },
    });
  };
}
