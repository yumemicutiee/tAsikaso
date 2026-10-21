import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { after, before, test } from "node:test";

import Anthropic from "@anthropic-ai/sdk";

import { createApp, describeError } from "../src/app.js";
import {
  BadOutputError,
  checkAnswer,
  ClientGoneError,
  generateQuiz,
  generateStudyKit,
  MAX_TOKENS,
  RefusedError,
  TooLongError,
} from "../src/claude.js";
import { FakeAnthropic, messageEvents } from "./fake-anthropic.js";

// The Claude calls, through the real SDK, against a fake Anthropic API.

let fake: FakeAnthropic;
let client: Anthropic;

before(async () => {
  fake = await new FakeAnthropic().start();
  client = fake.client();
});
after(() => fake.close());

const NOTES = "Mitochondria make ATP. Ribosomes make proteins. Osmosis moves water.";

const KIT = {
  title: "Cells",
  summary: "Organelles and transport.",
  notes: "# Cells\n\n- Mitochondria make ATP",
  concepts: [{ term: "ATP", explanation: "The cell's energy." }],
  cards: [
    { front: "What makes ATP?", back: "Mitochondria" },
    { front: "What makes proteins?", back: "Ribosomes" },
  ],
  quiz: [
    {
      type: "multiple_choice",
      prompt: "Which organelle makes ATP?",
      options: ["Ribosome", "Mitochondria", "Nucleus", "Golgi"],
      answerIndex: 1,
      answer: "Mitochondria",
      acceptable: [],
      explanation: "Cellular respiration.",
      cardIndex: 0,
    },
  ],
};

test("a study kit: the request, the parsed kit, tokens and cost", async () => {
  fake.reply({
    sse: messageEvents({
      content: [{ type: "text", text: JSON.stringify(KIT) }],
      inputTokens: 2000,
      outputTokens: 10_000,
    }),
  });
  const result = await generateStudyKit({ text: NOTES, maxCards: 10, quizCount: 5 }, { client });

  const seen = fake.requests.at(-1)!;
  assert.equal(seen.body.model, "claude-opus-5-5");
  assert.equal(seen.body.max_tokens, MAX_TOKENS.studyKit);
  assert.equal(seen.body.max_tokens, 64_000);
  assert.equal(seen.body.stream, true);
  assert.equal(seen.body.fallbacks, "default");
  assert.deepEqual(seen.body.thinking, { type: "adaptive" });
  assert.equal(seen.body.output_config.effort, "high");
  assert.equal(seen.body.output_config.format.type, "json_schema");
  assert.match(String(seen.headers["anthropic-beta"]), /server-side-fallback-2026-07-01/);
  assert.match(seen.body.messages[0].content, /<notes>\nMitochondria/);

  assert.equal(result.data.title, "Cells");
  assert.equal(result.data.cards.length, 2);
  assert.equal(result.data.quiz[0]?.answerIndex, 1);
  assert.equal(result.model, "claude-opus-5-5");
  assert.equal(result.inputTokens, 2000);
  assert.equal(result.outputTokens, 10_000);
  // $4 per million in, $20 per million out.
  assert.ok(Math.abs(result.costUsd - (2000 * 4 + 10_000 * 20) / 1e6) < 1e-9);
  assert.equal(result.fallback, false);
  assert.equal(result.estimated, false);
});

test("quiz and answer checks use their own output limits and effort", async () => {
  fake.reply(
    {
      sse: messageEvents({
        content: [{ type: "text", text: JSON.stringify({ questions: KIT.quiz }) }],
      }),
    },
    {
      sse: messageEvents({
        content: [{ type: "text", text: JSON.stringify({ verdict: "correct", feedback: "Yes!" }) }],
      }),
    },
  );
  const quiz = await generateQuiz({ cards: KIT.cards, count: 3, types: ["multiple_choice"] }, { client });
  assert.equal(fake.requests.at(-1)!.body.max_tokens, 16_000);
  assert.equal(quiz.data.questions.length, 1);

  const check = await checkAnswer(
    { question: "What makes ATP?", answer: "Mitochondria", userAnswer: "mitochondria" },
    { client },
  );
  const seen = fake.requests.at(-1)!;
  assert.equal(seen.body.max_tokens, MAX_TOKENS.checkAnswer);
  assert.equal(seen.body.output_config.effort, "low");
  assert.equal(check.data.verdict, "correct");
});

test("a quiz drops question types the student didn't ask for", async () => {
  const typed = { ...KIT.quiz[0], type: "typed", options: [], answerIndex: -1, prompt: "What makes ATP?" };
  fake.reply({
    sse: messageEvents({
      content: [{ type: "text", text: JSON.stringify({ questions: [...KIT.quiz, typed] }) }],
    }),
  });
  const quiz = await generateQuiz({ cards: KIT.cards, types: ["multiple_choice"] }, { client });
  assert.deepEqual(
    quiz.data.questions.map((q) => q.type),
    ["multiple_choice"],
  );
});

test("hitting max_tokens is TooLongError with the cost, not a JSON parse failure", async () => {
  fake.reply({
    sse: messageEvents({
      content: [{ type: "text", text: JSON.stringify(KIT).slice(0, 80) }],
      stopReason: "max_tokens",
      outputTokens: 64_000,
    }),
  });
  const err = await generateStudyKit({ text: NOTES }, { client }).catch((e: unknown) => e);
  assert.ok(err instanceof TooLongError, String(err));
  assert.equal(err.usage?.outputTokens, 64_000);
  assert.ok((err.usage?.costUsd ?? 0) > 1.2);
  assert.equal(describeError(err, "/v1/study-kit").error.status, 413);
});

test("a refusal is RefusedError, even when some text came first", async () => {
  fake.reply({
    sse: messageEvents({
      content: [{ type: "text", text: '{"title": "Ce' }],
      stopReason: "refusal",
      stopDetails: { type: "refusal", category: null, explanation: "Declined." },
    }),
  });
  const err = await generateStudyKit({ text: NOTES }, { client }).catch((e: unknown) => e);
  assert.ok(err instanceof RefusedError, String(err));
  assert.equal(err.explanation, "Declined.");
  assert.ok(err.usage);
  assert.equal(describeError(err, "/v1/study-kit").error.code, "declined");
});

test("empty, broken or wrongly shaped JSON is BadOutputError (502), not a crash", async () => {
  for (const text of ["", "{not json", JSON.stringify({ verdict: "maybe", feedback: 3 })]) {
    fake.reply({ sse: messageEvents({ content: text ? [{ type: "text", text }] : [] }) });
    const err = await checkAnswer(
      { question: "Q?", answer: "A", userAnswer: "B" },
      { client },
    ).catch((e: unknown) => e);
    assert.ok(err instanceof BadOutputError, `${JSON.stringify(text)}: ${String(err)}`);
    const { error } = describeError(err, "/v1/check-answer");
    assert.equal(error.status, 502);
    assert.equal(error.code, "bad_output");
  }
});

test("after a refusal fallback only the fallback model's answer is used, and both attempts are costed", async () => {
  fake.reply({
    sse: messageEvents({
      content: [
        { type: "text", text: '{"verdict": "wro' },
        { type: "fallback", from: "claude-opus-5-5", to: "claude-opus-5" },
        { type: "text", text: JSON.stringify({ verdict: "partly", feedback: "Almost." }) },
      ],
      iterations: [
        {
          type: "message",
          model: "claude-opus-5-5",
          input_tokens: 100,
          output_tokens: 50,
          cache_read_input_tokens: 0,
          cache_creation_input_tokens: 0,
          cache_creation: null,
        },
        {
          type: "fallback_message",
          model: "claude-opus-5",
          input_tokens: 120,
          output_tokens: 200,
          cache_read_input_tokens: 0,
          cache_creation_input_tokens: 0,
          cache_creation: null,
        },
      ],
    }),
  });
  const result = await checkAnswer({ question: "Q?", answer: "A", userAnswer: "B" }, { client });
  assert.equal(result.data.verdict, "partly");
  assert.equal(result.fallback, true);
  assert.equal(result.model, "claude-opus-5");
  assert.equal(result.inputTokens, 220);
  assert.equal(result.outputTokens, 250);
  const expected = (100 * 4 + 50 * 20) / 1e6 + (120 * 5 + 200 * 25) / 1e6;
  assert.ok(Math.abs(result.costUsd - expected) < 1e-9);
});

test("Anthropic overloaded (529) and a mid-stream overload are 'busy' (503)", async () => {
  fake.reply(
    { status: 529, body: { type: "error", error: { type: "overloaded_error", message: "Overloaded" } } },
    {
      sse: messageEvents({ content: [] }).slice(0, 1),
      errorEvent: { type: "error", error: { type: "overloaded_error", message: "Overloaded" } },
    },
  );
  for (let i = 0; i < 2; i++) {
    const err = await checkAnswer({ question: "Q?", answer: "A", userAnswer: "B" }, { client }).catch(
      (e: unknown) => e,
    );
    assert.ok(err instanceof Anthropic.APIError, String(err));
    const { error } = describeError(err, "/v1/check-answer");
    assert.equal(error.status, 503);
    assert.equal(error.code, "busy");
    assert.ok(error.headers["Retry-After"]);
  }
});

test("end to end: the app hanging up closes the server's stream to Anthropic", async () => {
  const logs: Array<Record<string, unknown>> = [];
  const app = createApp({
    appToken: "t",
    log: (level, msg, fields) => logs.push({ level, msg, ...fields }),
    generators: { studyKit: (input, call) => generateStudyKit(input, { ...call, client }) },
  });
  const server = await new Promise<Server>((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });
  try {
    const { port } = server.address() as AddressInfo;
    fake.reply({ sse: messageEvents({ content: [], inputTokens: 2000 }).slice(0, 1), hang: true });
    const anthropicClosed = fake.nextAbort();
    const controller = new AbortController();
    const pending = fetch(`http://127.0.0.1:${port}/v1/study-kit`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: "Bearer t", "x-request-id": "gone" },
      body: JSON.stringify({ text: NOTES }),
      signal: controller.signal,
    });
    setTimeout(() => controller.abort(), 150);
    await assert.rejects(pending);
    await anthropicClosed;
    for (let i = 0; i < 100 && !logs.some((l) => l.requestId === "gone"); i++) {
      await new Promise((r) => setTimeout(r, 10));
    }
    const line = logs.find((l) => l.requestId === "gone");
    assert.equal(line?.status, 499);
    assert.equal(line?.estimated, true);
    assert.equal(line?.inputTokens, 2000);
  } finally {
    server.closeAllConnections();
    server.close();
  }
});

test("aborting stops the HTTP call to Anthropic and estimates what it cost", async () => {
  // The fake sends message_start and then keeps the stream open, like Claude thinking.
  fake.reply({ sse: messageEvents({ content: [], inputTokens: 3000 }).slice(0, 1), hang: true });
  const controller = new AbortController();
  const aborted = fake.nextAbort();
  const pending = generateStudyKit({ text: NOTES }, { client, signal: controller.signal });
  setTimeout(() => controller.abort(), 100);
  const err = await pending.catch((e: unknown) => e);
  assert.ok(err instanceof ClientGoneError, String(err));
  assert.equal(err.usage?.estimated, true);
  assert.equal(err.usage?.inputTokens, 3000);
  assert.ok((err.usage?.costUsd ?? 0) > 0);
  await aborted; // the fake API saw the connection close
  assert.ok(fake.aborted >= 1);
});
