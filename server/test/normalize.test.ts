import assert from "node:assert/strict";
import { test } from "node:test";

import {
  normalizeCards,
  normalizeKit,
  normalizeQuestion,
  normalizeQuestions,
} from "../src/normalize.js";
import type { QuizQuestion } from "../src/schemas.js";

const base: QuizQuestion = {
  type: "typed",
  prompt: "What makes ATP?",
  options: [],
  answerIndex: -1,
  answer: "Mitochondria",
  acceptable: ["the mitochondrion"],
  explanation: "They run cellular respiration.",
  cardIndex: 0,
};

test("cards: trims, drops empties and duplicates, caps the count", () => {
  const cards = normalizeCards(
    [
      { front: "  Osmosis ", back: " Water  moves " },
      { front: "osmosis", back: "again" },
      { front: "", back: "no front" },
      { front: "Diffusion", back: "" },
      { front: "ATP", back: "Energy" },
      { front: "Nucleus", back: "Holds DNA" },
    ],
    2,
  );
  assert.deepEqual(cards, [
    { front: "Osmosis", back: "Water moves" },
    { front: "ATP", back: "Energy" },
  ]);
});

test("multiple choice: a wrong answerIndex is repaired from the answer text", () => {
  const q = normalizeQuestion(
    {
      ...base,
      type: "multiple_choice",
      options: ["Ribosome", "Mitochondria", "Nucleus", "Golgi"],
      answerIndex: 9,
      answer: "mitochondria",
    },
    3,
  );
  assert.equal(q?.answerIndex, 1);
  assert.equal(q?.answer, "Mitochondria");
});

test("multiple choice: dropped when the answer isn't an option", () => {
  const q = normalizeQuestion(
    {
      ...base,
      type: "multiple_choice",
      options: ["Ribosome", "Nucleus", "Golgi", "Lysosome"],
      answerIndex: -1,
      answer: "Mitochondria",
    },
    3,
  );
  assert.equal(q, null);
});

test("true/false: options are fixed and the answer is read from text", () => {
  const q = normalizeQuestion(
    { ...base, type: "true_false", options: [], answerIndex: 5, answer: "Mali" },
    3,
  );
  assert.deepEqual(q?.options, ["True", "False"]);
  assert.equal(q?.answerIndex, 1);
  assert.equal(q?.answer, "False");
});

test("fill in the blank: the blank is normalised, or the question becomes typed", () => {
  const withBlank = normalizeQuestion(
    { ...base, type: "fill_blank", prompt: "The ______ makes ATP." },
    3,
  );
  assert.equal(withBlank?.type, "fill_blank");
  assert.equal(withBlank?.prompt, "The ____ makes ATP.");

  const without = normalizeQuestion(
    { ...base, type: "fill_blank", prompt: "Which organelle makes ATP?" },
    3,
  );
  assert.equal(without?.type, "typed");
});

test("cardIndex outside the set becomes -1", () => {
  const q = normalizeQuestion({ ...base, cardIndex: 7 }, 3);
  assert.equal(q?.cardIndex, -1);
});

test("questions: duplicates by prompt are dropped and the count is capped", () => {
  const out = normalizeQuestions(
    [base, { ...base, prompt: "what makes atp?" }, { ...base, prompt: "Other?" }],
    3,
    5,
  );
  assert.equal(out.length, 2);
});

test("multiple choice: dropping an empty or repeated option doesn't shift the answer", () => {
  const q = normalizeQuestion(
    {
      ...base,
      type: "multiple_choice",
      options: ["Ribosome", "", "ribosome", "Mitochondria", "Nucleus"],
      answerIndex: 3,
      answer: "",
    },
    3,
  );
  assert.deepEqual(q?.options, ["Ribosome", "Mitochondria", "Nucleus"]);
  assert.equal(q?.answerIndex, 1);
  assert.equal(q?.answer, "Mitochondria");
});

test("multiple choice: the answer text wins over a miscounted answerIndex", () => {
  const q = normalizeQuestion(
    {
      ...base,
      type: "multiple_choice",
      options: ["Ribosome", "Mitochondria", "Nucleus", "Golgi"],
      answerIndex: 2, // counted from 1
      answer: "Mitochondria",
    },
    3,
  );
  assert.equal(q?.answerIndex, 1);
});

test("true/false: punctuation and Filipino answers are understood", () => {
  for (const [answer, index] of [
    ["True.", 0],
    ["Totoo", 0],
    ["mali!", 1],
  ] as const) {
    const q = normalizeQuestion({ ...base, type: "true_false", answer, answerIndex: -1 }, 3);
    assert.equal(q?.answerIndex, index, answer);
  }
  const byIndex = normalizeQuestion(
    { ...base, type: "true_false", options: ["True", "False"], answer: "?", answerIndex: 1 },
    3,
  );
  assert.equal(byIndex?.answer, "False");
});

test("a limit of 0 gives no cards and no questions", () => {
  assert.deepEqual(normalizeCards([{ front: "Q", back: "A" }], 0), []);
  assert.deepEqual(normalizeQuestions([base], 3, 0), []);
});

test("questions: types the student didn't ask for are dropped", () => {
  const out = normalizeQuestions(
    [base, { ...base, type: "true_false", prompt: "ATP is energy.", answer: "True" }],
    3,
    5,
    { allowed: ["true_false"] },
  );
  assert.deepEqual(
    out.map((q) => q.type),
    ["true_false"],
  );
});

test("kit: a question still points at its card after cards are dropped", () => {
  const kit = normalizeKit(
    {
      title: "Cells",
      summary: "",
      notes: "",
      concepts: [],
      cards: [
        { front: "", back: "empty" }, // dropped
        { front: "Osmosis", back: "Water moves" },
        { front: "osmosis", back: "duplicate" }, // merged into the one above
        { front: "ATP", back: "Energy" },
        { front: "Extra", back: "over the limit" }, // past maxCards
      ],
      quiz: [
        { ...base, prompt: "About ATP?", cardIndex: 3 },
        { ...base, prompt: "About the duplicate?", cardIndex: 2 },
        { ...base, prompt: "About the extra?", cardIndex: 4 },
        { ...base, prompt: "About the empty one?", cardIndex: 0 },
      ],
    },
    { maxCards: 2, quizCount: 10 },
  );
  assert.deepEqual(
    kit.cards.map((c) => c.front),
    ["Osmosis", "ATP"],
  );
  assert.deepEqual(
    kit.quiz.map((q) => [q.prompt, q.cardIndex]),
    [
      ["About ATP?", 1],
      ["About the duplicate?", 0],
      ["About the extra?", -1],
      ["About the empty one?", -1],
    ],
  );
});

test("kit: falls back to the student's title and tidies the notes", () => {
  const kit = normalizeKit(
    {
      title: "  ",
      summary: " About  cells ",
      notes: "# Cells  \n\n\n\n- one \n   - two",
      concepts: [{ term: "ATP", explanation: "Energy" }, { term: "atp", explanation: "dup" }],
      cards: [{ front: "Q", back: "A" }],
      quiz: [base],
    },
    { maxCards: 10, quizCount: 10, fallbackTitle: "Bio 101" },
  );
  assert.equal(kit.title, "Bio 101");
  assert.equal(kit.summary, "About cells");
  assert.equal(kit.notes, "# Cells\n\n- one\n- two");
  assert.equal(kit.concepts.length, 1);
  assert.equal(kit.quiz.length, 1);
});
