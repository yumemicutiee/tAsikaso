import { z } from "zod";

// What Claude returns. Kept free of min/max rules on purpose: structured
// outputs only guarantee the shape, and normalize.ts tidies the values.

export const Concept = z.object({
  term: z.string(),
  explanation: z.string(),
});
export type Concept = z.infer<typeof Concept>;

export const Card = z.object({
  front: z.string(),
  back: z.string(),
});
export type Card = z.infer<typeof Card>;

export const QuestionType = z.enum([
  "multiple_choice",
  "true_false",
  "fill_blank",
  "typed",
]);
export type QuestionType = z.infer<typeof QuestionType>;

export const QuizQuestion = z.object({
  type: QuestionType,
  /** The question. For fill_blank it contains one blank written as ____. */
  prompt: z.string(),
  /** 4 choices for multiple_choice, ["True", "False"] for true_false, else []. */
  options: z.array(z.string()),
  /** Index of the correct option, or -1 for fill_blank and typed. */
  answerIndex: z.number().int(),
  /** The correct answer as text, for every type. */
  answer: z.string(),
  /** Other correct ways to say it (typed and fill_blank). */
  acceptable: z.array(z.string()),
  explanation: z.string(),
  /** Index of the flashcard the question comes from, or -1. */
  cardIndex: z.number().int(),
});
export type QuizQuestion = z.infer<typeof QuizQuestion>;

export const StudyKit = z.object({
  title: z.string(),
  summary: z.string(),
  /** The notes typed up cleanly, in the simple line format prompts.ts asks for. */
  notes: z.string(),
  concepts: z.array(Concept),
  cards: z.array(Card),
  quiz: z.array(QuizQuestion),
});
export type StudyKit = z.infer<typeof StudyKit>;

export const Quiz = z.object({
  questions: z.array(QuizQuestion),
});
export type Quiz = z.infer<typeof Quiz>;

export const AnswerCheck = z.object({
  verdict: z.enum(["correct", "partly", "wrong"]),
  /** One friendly sentence; names the right answer when the student missed it. */
  feedback: z.string(),
});
export type AnswerCheck = z.infer<typeof AnswerCheck>;

// What the app sends.

export const StudyKitRequest = z.object({
  text: z.string().trim().min(20).max(120_000),
  title: z.string().trim().max(200).optional(),
  maxCards: z.number().int().min(1).max(60).optional(),
  quizCount: z.number().int().min(0).max(40).optional(),
});
export type StudyKitRequest = z.infer<typeof StudyKitRequest>;

export const QuizRequest = z.object({
  title: z.string().trim().max(200).optional(),
  cards: z.array(Card).min(1).max(200),
  concepts: z.array(Concept).max(50).optional(),
  count: z.number().int().min(1).max(40).optional(),
  types: z.array(QuestionType).min(1).optional(),
});
export type QuizRequest = z.infer<typeof QuizRequest>;

export const CheckAnswerRequest = z.object({
  question: z.string().trim().min(1).max(2000),
  answer: z.string().trim().min(1).max(2000),
  acceptable: z.array(z.string().max(500)).max(20).optional(),
  userAnswer: z.string().trim().min(1).max(2000),
});
export type CheckAnswerRequest = z.infer<typeof CheckAnswerRequest>;
