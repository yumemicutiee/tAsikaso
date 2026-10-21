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

const SAMPLE = `Cell Biology - Lecture 3
Mitochondria - the powerhouse of the cell; makes ATP through cellular respiration
Ribosome: makes proteins. found free in cytoplasm or on rough ER
Q: What is osmosis?
A: movement of water across a semi permeable membrane from low solute conc. to high solute conc
Diffusion = movement of particles from high to low concentration, no energy needed
Active transport -> needs ATP, moves against the gradient
Nucleus - holds DNA, controls the cell
Prokaryote vs Eukaryote: no nucleus vs has a nucleus
Why is the cell membrane called a fluid mosaic? because the phospholipids move and proteins float in them`;

const file = process.argv[2];
const text = file ? readFileSync(file, "utf8") : SAMPLE;
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
  `\n${result.model}: ${result.inputTokens} in, ${result.outputTokens} out, ${(result.ms / 1000).toFixed(1)} s`,
);
