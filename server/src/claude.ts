import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import type { z } from "zod";

import { normalizeKit, normalizeQuestions } from "./normalize.js";
import { costUsd } from "./pricing.js";
import {
  CHECK_ANSWER_SYSTEM,
  checkAnswerUser,
  QUIZ_SYSTEM,
  quizUser,
  STUDY_KIT_SYSTEM,
  studyKitUser,
} from "./prompts.js";
import {
  AnswerCheck,
  type CheckAnswerRequest,
  Quiz,
  type QuizRequest,
  StudyKit,
  type StudyKitRequest,
} from "./schemas.js";

type Effort = "low" | "medium" | "high" | "xhigh" | "max";

const EFFORTS: readonly Effort[] = ["low", "medium", "high", "xhigh", "max"];

function effortFromEnv(name: string, fallback: Effort): Effort {
  const v = process.env[name]?.trim();
  if (!v) return fallback;
  if ((EFFORTS as readonly string[]).includes(v)) return v as Effort;
  console.warn(`${name}="${v}" isn't one of ${EFFORTS.join(", ")}; using ${fallback}.`);
  return fallback;
}

/** Claude Opus 5.5 at high effort, as planned; both can be changed in .env. */
export const MODEL = process.env.CLAUDE_MODEL?.trim() || "claude-opus-5-5";
export const EFFORT = effortFromEnv("CLAUDE_EFFORT", "high");
/** Marking one typed answer is quick work and the student is waiting. */
export const CHECK_EFFORT = effortFromEnv("CLAUDE_CHECK_EFFORT", "low");

export const DEFAULT_MAX_CARDS = 30;
export const DEFAULT_QUIZ_COUNT = 12;

/**
 * Output ceilings, thinking included. A study kit streams, so a high
 * ceiling costs nothing unless it's used and long notes don't run out.
 */
export const MAX_TOKENS = {
  studyKit: 64_000,
  quiz: 16_000,
  checkAnswer: 4_000,
} as const;

/** Rough output speed, used only to estimate what an abandoned call cost. */
const EST_OUTPUT_TOKENS_PER_SECOND = 50;

let defaultClient: Anthropic | undefined;
/** Reads ANTHROPIC_API_KEY from the environment the first time it's needed. */
function getClient(): Anthropic {
  defaultClient ??= new Anthropic();
  return defaultClient;
}

export interface CallOptions {
  /** Aborts the Claude call, e.g. when the app has hung up. */
  signal?: AbortSignal;
  /** Another client (tests point one at a fake server). */
  client?: Anthropic;
}

/** What one Claude call used and cost. */
export interface CallUsage {
  /** The model that produced the answer (a fallback model if one served it). */
  model: string;
  /** Tokens billed across every attempt, a declined one included. */
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
  /** A refusal fallback served the answer. */
  fallback: boolean;
  /** The call was abandoned, so the numbers are an estimate. */
  estimated: boolean;
}

export interface Generated<T> extends CallUsage {
  data: T;
  ms: number;
}

/** A failure after Claude ran; [usage] says what it cost. */
export class ClaudeCallError extends Error {
  constructor(
    message: string,
    readonly usage?: CallUsage,
  ) {
    super(message);
    this.name = "ClaudeCallError";
  }
}

/** Claude declined the request (its safety classifiers), even after fallbacks. */
export class RefusedError extends ClaudeCallError {
  constructor(
    readonly explanation: string | null,
    usage?: CallUsage,
  ) {
    super(explanation ?? "Claude declined this request.", usage);
    this.name = "RefusedError";
  }
}

/** The answer didn't fit in max_tokens (or the context window). */
export class TooLongError extends ClaudeCallError {
  constructor(usage?: CallUsage) {
    super("The answer didn't fit in the output limit.", usage);
    this.name = "TooLongError";
  }
}

/** Claude's answer wasn't the JSON asked for (empty, cut short or the wrong shape). */
export class BadOutputError extends ClaudeCallError {
  constructor(detail: string, usage?: CallUsage) {
    super(`Claude's answer wasn't usable JSON: ${detail}`, usage);
    this.name = "BadOutputError";
  }
}

/** The call was aborted because the client went away. */
export class ClientGoneError extends ClaudeCallError {
  constructor(usage: CallUsage) {
    super("The client went away; the Claude call was stopped.", usage);
    this.name = "ClientGoneError";
  }
}

type Message = Anthropic.Beta.BetaMessage;

const formats = new WeakMap<z.ZodType, { type: "json_schema"; schema: Record<string, unknown> }>();

/**
 * The JSON schema for [schema], without the SDK's own parser: the SDK would
 * parse the text as soon as the stream ends and throw on a cut-short answer
 * before we can see that the stop reason was max_tokens or a refusal.
 */
function formatFor(schema: z.ZodType) {
  let format = formats.get(schema);
  if (!format) {
    const { type, schema: json } = betaZodOutputFormat(schema);
    format = { type, schema: json };
    formats.set(schema, format);
  }
  return format;
}

/**
 * One structured call: adaptive thinking, the given effort, JSON that matches
 * [schema], and Anthropic's default refusal fallbacks so a declined request
 * is retried on another model server-side. Streams so long answers don't
 * hit HTTP timeouts.
 */
async function generate<S extends z.ZodType>(
  schema: S,
  opts: { system: string; user: string; effort: Effort; maxTokens: number },
  call: CallOptions = {},
): Promise<Generated<z.infer<S>>> {
  const started = Date.now();
  if (call.signal?.aborted) {
    throw new ClientGoneError({
      model: MODEL,
      inputTokens: 0,
      outputTokens: 0,
      costUsd: 0,
      fallback: false,
      estimated: true,
    });
  }
  const client = call.client ?? getClient();
  const stream = client.beta.messages.stream(
    {
      model: MODEL,
      max_tokens: opts.maxTokens,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      thinking: { type: "adaptive" },
      output_config: {
        effort: opts.effort,
        format: formatFor(schema),
      },
      system: opts.system,
      messages: [{ role: "user", content: opts.user }],
    },
    { signal: call.signal },
  );

  let message: Message;
  try {
    message = await stream.finalMessage();
  } catch (e) {
    if (call.signal?.aborted || e instanceof Anthropic.APIUserAbortError) {
      throw new ClientGoneError(estimateAbandoned(stream.currentMessage, opts, started));
    }
    throw e;
  }

  const usage = usageOf(message);
  if (message.stop_reason === "refusal") {
    throw new RefusedError(message.stop_details?.explanation ?? null, usage);
  }
  if (
    message.stop_reason === "max_tokens" ||
    message.stop_reason === "model_context_window_exceeded"
  ) {
    throw new TooLongError(usage);
  }

  const text = answerText(message);
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new BadOutputError(text.trim() ? "not valid JSON" : "empty answer", usage);
  }
  const parsed = schema.safeParse(json);
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    throw new BadOutputError(
      `${issue?.path.join(".") || "answer"}: ${issue?.message ?? "wrong shape"}`,
      usage,
    );
  }
  return { ...usage, data: parsed.data as z.infer<S>, ms: Date.now() - started };
}

/**
 * The answer's text. After a mid-answer fallback the content holds the
 * declined model's partial text, a `fallback` block, then the full answer;
 * only what follows the last `fallback` block is the answer.
 */
export function answerText(message: Pick<Message, "content">): string {
  const blocks = message.content;
  let start = 0;
  blocks.forEach((b, i) => {
    if (b.type === "fallback") start = i + 1;
  });
  return blocks
    .slice(start)
    .map((b) => (b.type === "text" ? b.text : ""))
    .join("");
}

/**
 * Tokens and dollars for [message]. `usage.iterations` lists every attempt
 * with its own model (a declined attempt and the fallback that served the
 * answer bill separately); top-level `usage` covers only the last one.
 */
export function usageOf(message: Pick<Message, "model" | "usage">): CallUsage {
  const iterations = message.usage.iterations ?? [];
  let inputTokens = 0;
  let outputTokens = 0;
  let cost = 0;
  if (iterations.length) {
    for (const it of iterations) {
      const model = ("model" in it && it.model) || MODEL;
      inputTokens += it.input_tokens;
      outputTokens += it.output_tokens;
      cost += costUsd(model, {
        input: it.input_tokens,
        output: it.output_tokens,
        cacheRead: it.cache_read_input_tokens ?? 0,
        cacheWrite: it.cache_creation_input_tokens ?? 0,
      });
    }
  } else {
    const u = message.usage;
    inputTokens = u.input_tokens;
    outputTokens = u.output_tokens;
    cost = costUsd(message.model, {
      input: u.input_tokens,
      output: u.output_tokens,
      cacheRead: u.cache_read_input_tokens ?? 0,
      cacheWrite: u.cache_creation_input_tokens ?? 0,
    });
  }
  return {
    model: message.model,
    inputTokens,
    outputTokens,
    costUsd: cost,
    fallback: iterations.some((it) => it.type === "fallback_message"),
    estimated: false,
  };
}

/**
 * A stopped stream never gets its final usage, but Anthropic bills what was
 * generated before the stop. Estimate it from what had arrived and how long
 * the call ran, so abandoned requests still count against the daily cap.
 */
function estimateAbandoned(
  snapshot: Message | undefined,
  opts: { system: string; user: string; maxTokens: number },
  started: number,
): CallUsage {
  const seconds = (Date.now() - started) / 1000;
  const model = snapshot?.model ?? MODEL;
  const inputTokens =
    snapshot?.usage.input_tokens ?? Math.ceil((opts.system.length + opts.user.length) / 3);
  const outputTokens = Math.max(
    snapshot?.usage.output_tokens ?? 0,
    Math.min(opts.maxTokens, Math.round(seconds * EST_OUTPUT_TOKENS_PER_SECOND)),
  );
  return {
    model,
    inputTokens,
    outputTokens,
    costUsd: costUsd(model, { input: inputTokens, output: outputTokens }),
    fallback: false,
    estimated: true,
  };
}

/** Clean notes, key concepts, flashcards and a quiz from OCR text. */
export async function generateStudyKit(
  req: StudyKitRequest,
  call?: CallOptions,
): Promise<Generated<StudyKit>> {
  const maxCards = req.maxCards ?? DEFAULT_MAX_CARDS;
  const quizCount = req.quizCount ?? DEFAULT_QUIZ_COUNT;
  const result = await generate(
    StudyKit,
    {
      system: STUDY_KIT_SYSTEM,
      user: studyKitUser({ text: req.text, title: req.title, maxCards, quizCount }),
      effort: EFFORT,
      maxTokens: MAX_TOKENS.studyKit,
    },
    call,
  );
  return {
    ...result,
    data: normalizeKit(result.data, {
      maxCards,
      quizCount,
      fallbackTitle: req.title,
    }),
  };
}

/** A quiz from an existing set of flashcards. */
export async function generateQuiz(
  req: QuizRequest,
  call?: CallOptions,
): Promise<Generated<Quiz>> {
  const count = req.count ?? Math.min(DEFAULT_QUIZ_COUNT, req.cards.length * 2);
  const types = req.types ?? ["multiple_choice", "true_false", "fill_blank", "typed"];
  const result = await generate(
    Quiz,
    {
      system: QUIZ_SYSTEM,
      user: quizUser({
        title: req.title,
        cards: req.cards,
        concepts: req.concepts,
        count,
        types: [...new Set(types)],
      }),
      effort: EFFORT,
      maxTokens: MAX_TOKENS.quiz,
    },
    call,
  );
  return {
    ...result,
    data: {
      questions: normalizeQuestions(result.data.questions, req.cards.length, count, {
        allowed: types,
      }),
    },
  };
}

/** Marks a typed answer by meaning. */
export function checkAnswer(
  req: CheckAnswerRequest,
  call?: CallOptions,
): Promise<Generated<AnswerCheck>> {
  return generate(
    AnswerCheck,
    {
      system: CHECK_ANSWER_SYSTEM,
      user: checkAnswerUser(req),
      effort: CHECK_EFFORT,
      maxTokens: MAX_TOKENS.checkAnswer,
    },
    call,
  );
}
