import type { Card, Concept, QuestionType, QuizQuestion, StudyKit } from "./schemas.js";

// Tidies what the model returned so the app can rely on it: trimmed text,
// no empty or duplicate cards, every question playable.

const clean = (s: string) => s.replace(/\s+/g, " ").trim();

/** Keeps the line structure (headings and bullets), trims each line. */
function cleanNotes(s: string): string {
  return s
    .split("\n")
    .map((l) => l.replace(/[ \t]+$/g, "").replace(/^[ \t]+/, ""))
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/**
 * Cleans [cards] and keeps at most [max]. [map] says where each input card
 * ended up (its new index, or -1 if it was dropped), so a question's
 * cardIndex can follow its card.
 */
export function normalizeCardsMapped(
  cards: Card[],
  max: number,
): { cards: Card[]; map: number[] } {
  const seen = new Map<string, number>();
  const out: Card[] = [];
  const map: number[] = [];
  for (const c of cards) {
    const front = clean(c.front);
    const back = clean(c.back);
    const key = front.toLowerCase();
    if (!front || !back) {
      map.push(-1);
    } else if (seen.has(key)) {
      // A duplicate: questions about it point at the card that was kept.
      map.push(seen.get(key)!);
    } else if (out.length >= max) {
      map.push(-1);
    } else {
      seen.set(key, out.length);
      map.push(out.length);
      out.push({ front, back });
    }
  }
  return { cards: out, map };
}

export function normalizeCards(cards: Card[], max: number): Card[] {
  return normalizeCardsMapped(cards, max).cards;
}

export function normalizeConcepts(concepts: Concept[]): Concept[] {
  const seen = new Set<string>();
  const out: Concept[] = [];
  for (const c of concepts) {
    const term = clean(c.term);
    const explanation = clean(c.explanation);
    if (!term || !explanation) continue;
    const key = term.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ term, explanation });
  }
  return out;
}

const BLANK = /_{3,}/;

const TRUE_WORDS = new Set(["true", "tama", "totoo", "t", "yes", "oo"]);
const FALSE_WORDS = new Set(["false", "mali", "f", "no", "hindi"]);

/** true / false for a word such as "True", "Mali." or "F"; null if it's neither. */
function truthOf(s: string | undefined): boolean | null {
  const word = clean(s ?? "").toLowerCase().replace(/[.!]+$/, "");
  if (TRUE_WORDS.has(word)) return true;
  if (FALSE_WORDS.has(word)) return false;
  return null;
}

/**
 * Returns the question made playable, or null if it can't be. A choice
 * question's answer is found from its answer text when that names an
 * option, else from answerIndex (following the option through the clean-up);
 * a fill_blank without a blank becomes a typed question.
 */
export function normalizeQuestion(
  q: QuizQuestion,
  cardCount: number,
): QuizQuestion | null {
  const prompt = clean(q.prompt);
  const answer = clean(q.answer);
  const explanation = clean(q.explanation);
  const acceptable = [...new Set(q.acceptable.map(clean).filter(Boolean))];
  const cardIndex =
    Number.isInteger(q.cardIndex) && q.cardIndex >= 0 && q.cardIndex < cardCount
      ? q.cardIndex
      : -1;
  if (!prompt) return null;

  switch (q.type) {
    case "multiple_choice": {
      // Clean and de-duplicate the options, remembering where each one went,
      // so dropping an empty or repeated option doesn't shift the answer.
      const options: string[] = [];
      const moved: number[] = [];
      for (const raw of q.options) {
        const o = clean(raw);
        if (!o) {
          moved.push(-1);
          continue;
        }
        let at = options.findIndex((x) => x.toLowerCase() === o.toLowerCase());
        if (at < 0) {
          at = options.length;
          options.push(o);
        }
        moved.push(at);
      }
      if (options.length < 3) return null;
      const byText = answer
        ? options.findIndex((o) => o.toLowerCase() === answer.toLowerCase())
        : -1;
      const byIndex =
        Number.isInteger(q.answerIndex) && q.answerIndex >= 0 && q.answerIndex < moved.length
          ? moved[q.answerIndex]!
          : -1;
      const answerIndex = byText >= 0 ? byText : byIndex;
      if (answerIndex < 0) return null;
      return {
        type: "multiple_choice",
        prompt,
        options,
        answerIndex,
        answer: options[answerIndex]!,
        acceptable: [],
        explanation,
        cardIndex,
      };
    }
    case "true_false": {
      const isTrue = truthOf(answer) ?? truthOf(q.options[q.answerIndex]);
      if (isTrue === null) return null;
      return {
        type: "true_false",
        prompt,
        options: ["True", "False"],
        answerIndex: isTrue ? 0 : 1,
        answer: isTrue ? "True" : "False",
        acceptable: [],
        explanation,
        cardIndex,
      };
    }
    case "fill_blank": {
      if (!answer) return null;
      if (!BLANK.test(prompt)) {
        return {
          type: "typed",
          prompt,
          options: [],
          answerIndex: -1,
          answer,
          acceptable,
          explanation,
          cardIndex,
        };
      }
      return {
        type: "fill_blank",
        prompt: prompt.replace(BLANK, "____"),
        options: [],
        answerIndex: -1,
        answer,
        acceptable,
        explanation,
        cardIndex,
      };
    }
    case "typed": {
      if (!answer) return null;
      return {
        type: "typed",
        prompt,
        options: [],
        answerIndex: -1,
        answer,
        acceptable,
        explanation,
        cardIndex,
      };
    }
  }
}

export interface QuestionOptions {
  /** Question types the student asked for; others are dropped. */
  allowed?: readonly QuestionType[];
  /** Where each card the model saw ended up (see normalizeCardsMapped). */
  cardMap?: readonly number[];
}

export function normalizeQuestions(
  questions: QuizQuestion[],
  cardCount: number,
  max: number,
  opts: QuestionOptions = {},
): QuizQuestion[] {
  const seen = new Set<string>();
  const out: QuizQuestion[] = [];
  for (const raw of questions) {
    if (out.length >= max) break;
    const cardIndex = opts.cardMap
      ? (opts.cardMap[raw.cardIndex] ?? -1)
      : raw.cardIndex;
    const q = normalizeQuestion({ ...raw, cardIndex }, cardCount);
    if (!q) continue;
    if (opts.allowed && !opts.allowed.includes(q.type)) continue;
    const key = q.prompt.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(q);
  }
  return out;
}

export function normalizeKit(
  kit: StudyKit,
  opts: { maxCards: number; quizCount: number; fallbackTitle?: string },
): StudyKit {
  const { cards, map } = normalizeCardsMapped(kit.cards, opts.maxCards);
  return {
    title: clean(kit.title) || clean(opts.fallbackTitle ?? "") || "Notes",
    summary: clean(kit.summary),
    notes: cleanNotes(kit.notes),
    concepts: normalizeConcepts(kit.concepts),
    cards,
    quiz: normalizeQuestions(kit.quiz, cards.length, opts.quizCount, { cardMap: map }),
  };
}
