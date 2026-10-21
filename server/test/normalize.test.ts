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
