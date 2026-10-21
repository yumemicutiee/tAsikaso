import assert from "node:assert/strict";
import type { Server } from "node:http";
import { after, test } from "node:test";

import Anthropic from "@anthropic-ai/sdk";

import { type AppOptions, createApp, type Generators } from "../src/app.js";
import {
  BadOutputError,
  type CallUsage,
  type Generated,
  RefusedError,
  TooLongError,
} from "../src/claude.js";
import type { LogFields } from "../src/log.js";
import type { StudyKit } from "../src/schemas.js";

// The HTTP layer with fake Claude calls: no key, no network.

const servers: Server[] = [];
after(() => {
  for (const s of servers) {
    s.closeAllConnections();
    s.close();
  }
});

interface LogLine extends LogFields {
  level: string;
  msg: string;
}

async function start(options: AppOptions = {}) {
  const logs: LogLine[] = [];
  const app = createApp({
    appToken: "secret",
    log: (level, msg, fields = {}) => logs.push({ level, msg, ...fields }),
    ...options,
  });
  const server = await new Promise<Server>((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });
  servers.push(server);
  const address = server.address();
  assert.ok(address && typeof address === "object");
  const base = `http://127.0.0.1:${address.port}`;
  const post = (path: string, body: unknown, token: string | null = "secret", init: RequestInit = {}) =>
    fetch(base + path, {
      method: "POST",
      ...init,
      headers: {
        "content-type": "application/json",
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...(init.headers as Record<string, string> | undefined),
      },
      body: typeof body === "string" ? body : JSON.stringify(body),
    });
  const get = (path: string, token: string | null = "secret") =>
    fetch(base + path, { headers: token ? { authorization: `Bearer ${token}` } : {} });
  /** Waits until a log line for [requestId] has been written. */
  const logFor = async (requestId: string) => {
    for (let i = 0; i < 100; i++) {
      const line = logs.find((l) => l.requestId === requestId && l.msg !== "request failed");
      if (line) return line;
      await new Promise((r) => setTimeout(r, 10));
    }
    throw new Error(`no log line for ${requestId}`);
  };
  return { base, post, get, logs, logFor };
}

const NOTES = "x".repeat(40);
const KIT: StudyKit = {
  title: "T",
  summary: "S",
  notes: "# T",
  concepts: [],
  cards: [{ front: "Q", back: "A" }],
  quiz: [],
};

function usage(costUsd = 0.25, extra: Partial<CallUsage> = {}): CallUsage {
  return {
    model: "claude-opus-5-5",
    inputTokens: 2500,
    outputTokens: 12_000,
    costUsd,
    fallback: false,
    estimated: false,
    ...extra,
  };
}

function kitResult(costUsd = 0.25): Generated<StudyKit> {
  return { ...usage(costUsd), data: KIT, ms: 5 };
}

const fakes = (over: Partial<Generators> = {}): Partial<Generators> => ({
  studyKit: async () => kitResult(),
  quiz: async () => ({ ...usage(0.05), data: { questions: [] }, ms: 5 }),
  checkAnswer: async () => ({
    ...usage(0.002),
    data: { verdict: "correct", feedback: "Yes." },
    ms: 5,
  }),
  ...over,
});

type ErrorBody = { error: { code: string; message: string; requestId: string } };

test("health is just {ok:true}, needs no token, and isn't logged", async () => {
  const { get, logs } = await start({ generators: fakes() });
  const res = await get("/health", null);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true });
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(logs.filter((l) => l.route === "/health").length, 0);
});

test("health shows the model and effort with HEALTH_DETAILS", async () => {
  const { get } = await start({ generators: fakes(), healthDetails: true });
  const json = (await (await get("/health", null)).json()) as Record<string, unknown>;
  assert.equal(json.ok, true);
  assert.equal(json.model, "claude-opus-5-5");
  assert.equal(json.effort, "high");
});

test("a study kit keeps the reply shape the app reads, and logs one line with tokens and cost", async () => {
  const { post, logFor } = await start({ generators: fakes() });
  const res = await post("/v1/study-kit", { text: NOTES });
  assert.equal(res.status, 200);
  const json = (await res.json()) as Record<string, unknown>;
  assert.deepEqual(json, {
    kit: KIT,
    model: "claude-opus-5-5",
    usage: { input: 2500, output: 12_000 },
  });
  const id = res.headers.get("x-request-id");
  assert.ok(id && /^[0-9a-f-]{36}$/.test(id));
  const line = await logFor(id);
  assert.equal(line.level, "info");
  assert.equal(line.route, "/v1/study-kit");
  assert.equal(line.status, 200);
  assert.equal(line.model, "claude-opus-5-5");
  assert.equal(line.inputTokens, 2500);
  assert.equal(line.outputTokens, 12_000);
  assert.equal(line.costUsd, 0.25);
  assert.equal(line.fallback, false);
  assert.equal(typeof line.ms, "number");
});

test("an incoming X-Request-Id is kept and appears in error bodies; a strange one is replaced", async () => {
  const { post } = await start({ generators: fakes() });
  const res = await post("/v1/study-kit", { text: "short" }, "secret", {
    headers: { "x-request-id": "app-123.abc" },
  });
  assert.equal(res.status, 400);
  assert.equal(res.headers.get("x-request-id"), "app-123.abc");
  const json = (await res.json()) as ErrorBody;
  assert.equal(json.error.code, "bad_request");
  assert.match(json.error.message, /text/);
  assert.equal(json.error.requestId, "app-123.abc");

  const odd = await post("/v1/study-kit", { text: NOTES }, "secret", {
    headers: { "x-request-id": "has spaces and\ttabs" },
  });
  assert.notEqual(odd.headers.get("x-request-id"), "has spaces and\ttabs");
});

test("a missing or wrong token is refused", async () => {
  const { post, get } = await start({ generators: fakes() });
  assert.equal((await post("/v1/study-kit", { text: NOTES }, null)).status, 401);
  const wrong = await post("/v1/study-kit", { text: NOTES }, "nope");
  assert.equal(wrong.status, 401);
  assert.equal(((await wrong.json()) as ErrorBody).error.code, "unauthorized");
  assert.equal((await get("/v1/usage", null)).status, 401);
});

test("unknown paths are 404 JSON", async () => {
  const { get } = await start({ generators: fakes() });
  const res = await get("/nothing");
  assert.equal(res.status, 404);
  assert.equal(((await res.json()) as ErrorBody).error.code, "not_found");
});

test("broken JSON is a 400 and a body over 2 MB is too_long, not a 500", async () => {
  const { post } = await start({ generators: fakes() });
  const broken = await post("/v1/study-kit", "{not json");
  assert.equal(broken.status, 400);
  assert.equal(((await broken.json()) as ErrorBody).error.code, "bad_request");
  const huge = await post("/v1/study-kit", { text: "x".repeat(2_200_000) });
  assert.equal(huge.status, 413);
  assert.equal(((await huge.json()) as ErrorBody).error.code, "too_long");
});

test("maxCards 0 (type up the notes only) is accepted", async () => {
  let seen: unknown;
  const { post } = await start({
    generators: fakes({
      studyKit: async (input) => {
        seen = input;
        return kitResult();
      },
    }),
  });
  const res = await post("/v1/study-kit", { text: NOTES, maxCards: 0, quizCount: 0 });
  assert.equal(res.status, 200);
  assert.deepEqual(seen, { text: NOTES, maxCards: 0, quizCount: 0 });
});

test("a quiz with too much card text is refused before Claude is called", async () => {
  let called = false;
  const { post } = await start({
    generators: fakes({
      quiz: async () => {
        called = true;
        return { ...usage(), data: { questions: [] }, ms: 1 };
      },
    }),
  });
  const cards = Array.from({ length: 100 }, () => ({ front: "f".repeat(1500), back: "b".repeat(1500) }));
  const res = await post("/v1/quiz", { cards });
  assert.equal(res.status, 400);
  assert.match(((await res.json()) as ErrorBody).error.message, /cards/);
  assert.equal(called, false);
});

test("the daily limit: per client, separate for answer checks, bad requests don't count", async () => {
  const { post } = await start({ generators: fakes(), dailyLimit: 2, dailyCheckLimit: 1 });
  assert.equal((await post("/v1/study-kit", { text: "short" })).status, 400);
  assert.equal((await post("/v1/study-kit", { text: NOTES })).status, 200);
  assert.equal((await post("/v1/quiz", { cards: [{ front: "Q", back: "A" }] })).status, 200);
  const third = await post("/v1/study-kit", { text: NOTES });
  assert.equal(third.status, 429);
  const json = (await third.json()) as ErrorBody;
  assert.equal(json.error.code, "daily_limit");
  assert.equal(json.error.message, "You've reached today's limit of 2 Smart Study requests. Try again tomorrow.");
  assert.ok(Number(third.headers.get("retry-after")) > 0);

  const check = { question: "Q?", answer: "A", userAnswer: "A" };
  assert.equal((await post("/v1/check-answer", check)).status, 200);
  const secondCheck = await post("/v1/check-answer", check);
  assert.equal(secondCheck.status, 429);
  assert.equal(
    ((await secondCheck.json()) as ErrorBody).error.message,
    "You've reached today's limit of 1 answer check. Try again tomorrow.",
  );
});

test("the daily budget: once today's estimated spend reaches it, requests get 503 budget", async () => {
  const { post, get } = await start({
    generators: fakes({ studyKit: async () => kitResult(0.006) }),
    dailyBudgetUsd: 0.01,
  });
  assert.equal((await post("/v1/study-kit", { text: NOTES })).status, 200);
  assert.equal((await post("/v1/study-kit", { text: NOTES })).status, 200);
  const res = await post("/v1/study-kit", { text: NOTES });
  assert.equal(res.status, 503);
  const json = (await res.json()) as ErrorBody;
  assert.equal(json.error.code, "budget");
  assert.equal(json.error.message, "The study server has reached today's limit. Try again tomorrow.");

  const report = (await (await get("/v1/usage")).json()) as Record<string, any>;
  assert.equal(report.requests, 2);
  assert.equal(report.byRoute["/v1/study-kit"], 2);
  assert.equal(report.spentUsd, 0.012);
  assert.equal(report.budgetUsd, 0.01);
  assert.equal(report.remainingUsd, 0);
  assert.equal(report.refused.budget, 1);
  assert.equal(report.timeZone, "Asia/Manila");
  assert.match(report.day, /^\d{4}-\d{2}-\d{2}$/);
});

test("what failed calls cost still counts against the budget", async () => {
  const { post, get } = await start({
    generators: fakes({
      studyKit: async () => {
        throw new TooLongError(usage(1.3));
      },
    }),
    dailyBudgetUsd: 1,
  });
  const res = await post("/v1/study-kit", { text: NOTES });
  assert.equal(res.status, 413);
  assert.equal(((await (await get("/v1/usage")).json()) as { spentUsd: number }).spentUsd, 1.3);
  assert.equal((await post("/v1/study-kit", { text: NOTES })).status, 503);
});

test("the day starts again at midnight in the configured time zone", async () => {
  // 23:59 on 21 October in Manila (UTC+8) is 15:59 UTC.
  let now = Date.parse("2026-10-21T15:59:00Z");
  const { post, get } = await start({
    generators: fakes(),
    dailyLimit: 1,
    timeZone: "Asia/Manila",
    now: () => now,
  });
  assert.equal((await post("/v1/study-kit", { text: NOTES })).status, 200);
  assert.equal((await post("/v1/study-kit", { text: NOTES })).status, 429);
  const before = (await (await get("/v1/usage")).json()) as { day: string; resetsInSeconds: number };
  assert.equal(before.day, "2026-10-21");
  assert.equal(before.resetsInSeconds, 60);
  now += 2 * 60 * 1000; // 00:01 on the 22nd in Manila
  assert.equal((await post("/v1/study-kit", { text: NOTES })).status, 200);
  const later = (await (await get("/v1/usage")).json()) as { day: string; you: { study: number } };
  assert.equal(later.day, "2026-10-22");
  assert.equal(later.you.study, 1);
});

test("when the app hangs up, the Claude call is aborted and nothing is written", async () => {
  let sawAbort!: () => void;
  const aborted = new Promise<void>((resolve) => (sawAbort = resolve));
  const { post, logFor, logs } = await start({
    generators: fakes({
      studyKit: (_input, { signal }) =>
        new Promise((_resolve, reject) => {
          signal?.addEventListener("abort", () => {
            sawAbort();
            reject(new Error("aborted"));
          });
        }),
    }),
  });
  const controller = new AbortController();
  const pending = post("/v1/study-kit", { text: NOTES }, "secret", {
    signal: controller.signal,
    headers: { "x-request-id": "cancel-me" },
  });
  setTimeout(() => controller.abort(), 100);
  await assert.rejects(pending);
  await aborted; // the fake saw its signal fire
  const line = await logFor("cancel-me");
  assert.equal(line.status, 499);
  assert.equal(line.code, "cancelled");
  assert.equal(logs.filter((l) => l.level === "error").length, 0);
  // The server carries on.
  const check = { question: "Q?", answer: "A", userAnswer: "A" };
  assert.equal((await post("/v1/check-answer", check)).status, 200);
});

test("Claude and SDK errors become clear codes", async () => {
  const headers = new Headers({ "retry-after": "12" });
  const cases: Array<[unknown, number, string]> = [
    [new Anthropic.InternalServerError(529, { type: "error" }, "Overloaded", headers), 503, "busy"],
    [new Anthropic.RateLimitError(429, { type: "error" }, "Slow down", headers), 503, "busy"],
    [new Anthropic.InternalServerError(500, { type: "error" }, "Oops", headers), 502, "upstream"],
    [new Anthropic.APIConnectionTimeoutError(), 504, "timeout"],
    [new Anthropic.APIConnectionError({ message: "ECONNRESET" }), 502, "upstream"],
    [new Anthropic.AuthenticationError(401, { type: "error" }, "bad key", headers), 500, "server_key"],
    [new Anthropic.BadRequestError(400, {}, "billing", headers, "billing_error"), 500, "server_setup"],
    [new RefusedError("no", usage()), 422, "declined"],
    [new TooLongError(usage()), 413, "too_long"],
    [new BadOutputError("empty answer", usage()), 502, "bad_output"],
    [new Error("boom"), 500, "internal"],
  ];
  for (const [err, status, code] of cases) {
    const { post } = await start({
      generators: fakes({
        checkAnswer: async () => {
          throw err;
        },
      }),
    });
    const res = await post("/v1/check-answer", { question: "Q?", answer: "A", userAnswer: "A" });
    const json = (await res.json()) as ErrorBody;
    assert.equal(res.status, status, `${String(err)}`);
    assert.equal(json.error.code, code, `${String(err)}`);
    assert.ok(json.error.message.length > 10);
    assert.equal(json.error.requestId, res.headers.get("x-request-id"));
    if (code === "busy") assert.equal(res.headers.get("retry-after"), "12");
  }
});

test("too_long says what was too long", async () => {
  const { post } = await start({
    generators: fakes({
      quiz: async () => {
        throw new TooLongError(usage());
      },
    }),
  });
  const res = await post("/v1/quiz", { cards: [{ front: "Q", back: "A" }] });
  assert.equal(res.status, 413);
  assert.match(((await res.json()) as ErrorBody).error.message, /quiz/);
});

test("a refusal fallback is noted in the log line", async () => {
  const { post, logFor } = await start({
    generators: fakes({
      checkAnswer: async () => ({
        ...usage(0.01, { model: "claude-opus-5", fallback: true }),
        data: { verdict: "wrong", feedback: "No." },
        ms: 1,
      }),
    }),
  });
  const res = await post("/v1/check-answer", { question: "Q?", answer: "A", userAnswer: "B" });
  assert.equal(res.status, 200);
  const line = await logFor(res.headers.get("x-request-id")!);
  assert.equal(line.model, "claude-opus-5");
  assert.equal(line.fallback, true);
});

test("behind a proxy each device is counted by its forwarded address, which it can't fake", async () => {
  const { post, base } = await start({ generators: fakes(), trustProxy: 1, dailyLimit: 1 });
  const as = (forwarded: string) => ({ headers: { "x-forwarded-for": forwarded } });
  const usageAs = async (forwarded: string) =>
    (
      (await (
        await fetch(base + "/v1/usage", {
          headers: { authorization: "Bearer secret", "x-forwarded-for": forwarded },
        })
      ).json()) as { you: { address: string; study: number } }
    ).you;

  assert.equal((await post("/v1/study-kit", { text: NOTES }, "secret", as("203.0.113.7"))).status, 200);
  // A made-up address in front doesn't make a new client: the proxy's entry (last) counts.
  const spoofed = await post("/v1/study-kit", { text: NOTES }, "secret", as("10.9.9.9, 203.0.113.7"));
  assert.equal(spoofed.status, 429);
  assert.equal((await post("/v1/study-kit", { text: NOTES }, "secret", as("198.51.100.2"))).status, 200);
  assert.deepEqual(await usageAs("198.51.100.2"), {
    address: "198.51.100.2",
    study: 1,
    studyLimit: 1,
    checks: 0,
    checkLimit: 300,
  });
});

test("the 10-minute rate limit kicks in after the allowance", async () => {
  const { post } = await start({ generators: fakes(), rateLimit: 2 });
  const statuses: number[] = [];
  for (let i = 0; i < 3; i++) statuses.push((await post("/v1/check-answer", {})).status);
  assert.deepEqual(statuses, [400, 400, 429]);
});

test("CORS lets the web app read the request id", async () => {
  const { base } = await start({ generators: fakes() });
  const res = await fetch(base + "/v1/study-kit", { method: "OPTIONS" });
  assert.equal(res.status, 204);
  assert.match(res.headers.get("access-control-expose-headers") ?? "", /X-Request-Id/);
  assert.match(res.headers.get("access-control-allow-headers") ?? "", /X-Request-Id/);
});
