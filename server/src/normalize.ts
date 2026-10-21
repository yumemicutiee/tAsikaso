import type { Card, Concept, QuizQuestion, StudyKit } from "./schemas.js";

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

export function normalizeCards(cards: Card[], max: number): Card[] {
  const seen = new Set<string>();
  const out: Card[] = [];
  for (const c of cards) {
    const front = clean(c.front);
    const back = clean(c.back);
    if (!front || !back) continue;
    const key = front.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ front, back });
    if (out.length >= max) break;
  }
  return out;
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

/**
 * Returns the question made playable, or null if it can't be. A choice
 * question whose answerIndex is off is repaired from the answer text; a
 * fill_blank without a blank becomes a typed question.
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
      const options = [...new Set(q.options.map(clean).filter(Boolean))];
      if (options.length < 3) return null;
      let answerIndex = q.answerIndex;
      if (answerIndex < 0 || answerIndex >= options.length) {
        answerIndex = options.findIndex(
          (o) => o.toLowerCase() === answer.toLowerCase(),
        );
      }
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
      const text = (answer || q.options[q.answerIndex] || "").toLowerCase();
      const isTrue =
        text === "true" || text === "tama" || text === "t" || text === "yes";
      const isFalse =
        text === "false" || text === "mali" || text === "f" || text === "no";
      if (!isTrue && !isFalse) return null;
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

export function normalizeQuestions(
  questions: QuizQuestion[],
  cardCount: number,
  max: number,
): QuizQuestion[] {
  const seen = new Set<string>();
  const out: QuizQuestion[] = [];
  for (const raw of questions) {
    const q = normalizeQuestion(raw, cardCount);
    if (!q) continue;
    const key = q.prompt.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(q);
    if (out.length >= max) break;
  }
  return out;
}

export function normalizeKit(
  kit: StudyKit,
  opts: { maxCards: number; quizCount: number; fallbackTitle?: string },
): StudyKit {
  const cards = normalizeCards(kit.cards, opts.maxCards);
  return {
    title: clean(kit.title) || clean(opts.fallbackTitle ?? "") || "Notes",
    summary: clean(kit.summary),
    notes: cleanNotes(kit.notes),
    concepts: normalizeConcepts(kit.concepts),
    cards,
    quiz: normalizeQuestions(kit.quiz, cards.length, opts.quizCount),
  };
}
