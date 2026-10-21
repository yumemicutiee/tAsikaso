// Runs one study kit straight through Claude (no HTTP), to check the key
// and see what comes back:
//
//   npm run try                  # built-in sample notes
//   npm run try -- notes.txt     # your own OCR text
//
// Needs ANTHROPIC_API_KEY in .env or the environment.

import { existsSync, readFileSync } from "node:fs";

if (existsSync(".env")) process.loadEnvFile(".env");

const { generateStudyKit, MODEL, EFFORT } = await import("../src/claude.js");
const { SAMPLE_NOTES } = await import("./sample-notes.js");

const file = process.argv[2];
const text = file ? readFileSync(file, "utf8") : SAMPLE_NOTES;
console.log(`Model ${MODEL}, effort ${EFFORT}. ${text.length} characters of notes...\n`);

const result = await generateStudyKit({ text, maxCards: 12, quizCount: 8 });
const kit = result.data;

console.log(`# ${kit.title}\n${kit.summary}\n`);
console.log("Notes:\n" + kit.notes + "\n");
console.log("Concepts:");
for (const c of kit.concepts) console.log(`- ${c.term}: ${c.explanation}`);
console.log("\nCards:");
for (const c of kit.cards) console.log(`- ${c.front}\n    ${c.back}`);
console.log("\nQuiz:");
for (const q of kit.quiz) {
  console.log(`- [${q.type}] ${q.prompt}`);
  if (q.options.length) console.log(`    ${q.options.join(" | ")}`);
  console.log(`    answer: ${q.answer}`);
}
console.log(
  `\n${result.model}${result.fallback ? " (refusal fallback)" : ""}: ` +
    `${result.inputTokens} tokens in, ${result.outputTokens} out, ` +
    `about $${result.costUsd.toFixed(4)}, ${(result.ms / 1000).toFixed(1)} s`,
);
