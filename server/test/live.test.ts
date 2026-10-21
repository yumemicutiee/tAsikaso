import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { test } from "node:test";

// One real study kit from Claude. Costs a few cents, so it only runs when
// asked:   LIVE_CLAUDE=1 npm test        (PowerShell: $env:LIVE_CLAUDE=1; npm test)
// The key comes from the environment or server/.env.

if (process.env.LIVE_CLAUDE === "1" && existsSync(".env")) process.loadEnvFile(".env");

const live = process.env.LIVE_CLAUDE === "1" && Boolean(process.env.ANTHROPIC_API_KEY);

test(
  "live: Claude makes a playable study kit from sample notes",
  {
    skip: live ? false : "set LIVE_CLAUDE=1 and ANTHROPIC_API_KEY to call Claude",
    timeout: 5 * 60 * 1000,
  },
  async () => {
    const { generateStudyKit, MODEL, EFFORT } = await import("../src/claude.js");
    const { SAMPLE_NOTES } = await import("../scripts/sample-notes.js");

    const result = await generateStudyKit({ text: SAMPLE_NOTES, maxCards: 8, quizCount: 6 });
    const kit = result.data;

    assert.ok(kit.title.length > 0, "title");
    assert.ok(kit.notes.trim().length > 0, "notes");
    assert.ok(kit.cards.length > 0, "cards");
    for (const c of kit.cards) assert.ok(c.front && c.back, "card has both sides");
    assert.ok(kit.quiz.length > 0, "quiz");
    for (const q of kit.quiz) {
      assert.ok(q.prompt, "question has a prompt");
      assert.ok(q.answer, "question has an answer");
      if (q.type === "multiple_choice" || q.type === "true_false") {
        assert.ok(q.answerIndex >= 0 && q.answerIndex < q.options.length, "answerIndex is an option");
        assert.equal(q.options[q.answerIndex], q.answer);
      } else {
        assert.equal(q.answerIndex, -1);
      }
      if (q.type === "fill_blank") assert.match(q.prompt, /____/);
      assert.ok(q.cardIndex >= -1 && q.cardIndex < kit.cards.length, "cardIndex in range");
    }

    console.log(
      `live: ${MODEL} (effort ${EFFORT}) answered with ${result.model}` +
        `${result.fallback ? " after a refusal fallback" : ""}: ` +
        `${result.inputTokens} tokens in, ${result.outputTokens} out, ` +
        `about $${result.costUsd.toFixed(4)}, ${(result.ms / 1000).toFixed(1)} s; ` +
        `${kit.cards.length} cards, ${kit.quiz.length} questions`,
    );
  },
);
