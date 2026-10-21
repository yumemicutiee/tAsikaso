import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import type { z } from "zod";

import { normalizeKit, normalizeQuestions } from "./normalize.js";
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
  const v = process.env[name];
  return (EFFORTS as readonly string[]).includes(v ?? "")
    ? (v as Effort)
    : fallback;
}

/** Claude Opus 5.5 at high effort, as planned; both can be changed in .env. */
export const MODEL = process.env.CLAUDE_MODEL ?? "claude-opus-5-5";
export const EFFORT = effortFromEnv("CLAUDE_EFFORT", "high");
/** Marking one typed answer is quick work and the student is waiting. */
export const CHECK_EFFORT = effortFromEnv("CLAUDE_CHECK_EFFORT", "low");

export const DEFAULT_MAX_CARDS = 30;
export const DEFAULT_QUIZ_COUNT = 12;

// Reads ANTHROPIC_API_KEY from the environment.
const client = new Anthropic();

/** Claude declined the request (its safety classifiers), even after fallbacks. */
export class RefusedError extends Error {
  constructor(readonly explanation: string | null) {
    super(explanation ?? "Claude declined this request.");
    this.name = "RefusedError";
  }
}

/** The answer didn't fit in max_tokens. */
export class TooLongError extends Error {
  constructor() {
    super("The notes are too long to process in one go.");
    this.name = "TooLongError";
  }
}

export interface Generated<T> {
  data: T;
  model: string;
  inputTokens: number;
  outputTokens: number;
  ms: number;
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
): Promise<Generated<z.infer<S>>> {
  const started = Date.now();
  const stream = client.beta.messages.stream({
    model: MODEL,
    max_tokens: opts.maxTokens,
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    thinking: { type: "adaptive" },
    output_config: {
      effort: opts.effort,
      format: betaZodOutputFormat(schema),
    },
    system: opts.system,
    messages: [{ role: "user", content: opts.user }],
  });
  const message = await stream.finalMessage();

  if (message.stop_reason === "refusal") {
    throw new RefusedError(message.stop_details?.explanation ?? null);
  }
  if (message.stop_reason === "max_tokens") {
    throw new TooLongError();
  }
  const parsed = message.parsed_output;
  if (parsed == null) {
    // The SDK couldn't parse it; parse the text ourselves so the error says why.
    const text = message.content
      .filter((b) => b.type === "text")
      .map((b) => b.text)
      .join("");
    return finish(schema.parse(JSON.parse(text)) as z.infer<S>);
  }
  return finish(parsed as z.infer<S>);

  function finish(data: z.infer<S>): Generated<z.infer<S>> {
    return {
      data,
      model: message.model,
      inputTokens: message.usage.input_tokens,
      outputTokens: message.usage.output_tokens,
      ms: Date.now() - started,
    };
  }
}

/** Clean notes, key concepts, flashcards and a quiz from OCR text. */
export async function generateStudyKit(
  req: StudyKitRequest,
): Promise<Generated<StudyKit>> {
  const maxCards = req.maxCards ?? DEFAULT_MAX_CARDS;
  const quizCount = req.quizCount ?? DEFAULT_QUIZ_COUNT;
  const result = await generate(StudyKit, {
    system: STUDY_KIT_SYSTEM,
    user: studyKitUser({ text: req.text, title: req.title, maxCards, quizCount }),
    effort: EFFORT,
    maxTokens: 32_000,
  });
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
export async function generateQuiz(req: QuizRequest): Promise<Generated<Quiz>> {
  const count = req.count ?? Math.min(DEFAULT_QUIZ_COUNT, req.cards.length * 2);
  const types = req.types ?? [
    "multiple_choice",
    "true_false",
    "fill_blank",
    "typed",
  ];
  const result = await generate(Quiz, {
    system: QUIZ_SYSTEM,
    user: quizUser({
      title: req.title,
      cards: req.cards,
      concepts: req.concepts,
      count,
      types,
    }),
    effort: EFFORT,
    maxTokens: 16_000,
  });
  return {
    ...result,
    data: {
      questions: normalizeQuestions(
        result.data.questions,
        req.cards.length,
        count,
      ),
    },
  };
}

/** Marks a typed answer by meaning. */
export function checkAnswer(
  req: CheckAnswerRequest,
): Promise<Generated<AnswerCheck>> {
  return generate(AnswerCheck, {
    system: CHECK_ANSWER_SYSTEM,
    user: checkAnswerUser(req),
    effort: CHECK_EFFORT,
    maxTokens: 2_000,
  });
}
