import assert from "node:assert/strict";
import { test } from "node:test";

import { ConfigError, readConfig } from "../src/config.js";
import { DailyLedger } from "../src/ledger.js";
import { costUsd, priceFor } from "../src/pricing.js";

// Prices, the daily ledger and the settings that drive them.

test("prices: Opus 5.5 is $4 in / $20 out per million tokens", () => {
  assert.equal(costUsd("claude-opus-5-5", { input: 1_000_000, output: 0 }), 4);
  assert.equal(costUsd("claude-opus-5-5", { input: 0, output: 1_000_000 }), 20);
  assert.ok(Math.abs(costUsd("claude-opus-5-5", { input: 3000, output: 15_000 }) - 0.312) < 1e-9);
});

test("prices: switching to Sonnet 5.5 costs it at Sonnet rates", () => {
  assert.equal(costUsd("claude-sonnet-5-5", { input: 1_000_000, output: 1_000_000 }), 12);
});

test("prices: a dated id uses its family; an unknown model the dearest rate", () => {
  assert.equal(priceFor("claude-opus-5-5-20261101").price.input, 4);
  assert.equal(priceFor("claude-opus-5").price.input, 5);
  const unknown = priceFor("some-new-model");
  assert.equal(unknown.known, false);
  assert.ok(unknown.price.output >= 50);
});

test("ledger: the day is the configured time zone's date", () => {
  const ledger = new DailyLedger({
    timeZone: "Asia/Manila",
    dailyLimit: 0,
    dailyCheckLimit: 0,
    budgetUsd: 0,
    now: () => Date.parse("2026-10-21T16:30:00Z"), // 00:30 on the 22nd in Manila
  });
  assert.equal(ledger.today(), "2026-10-22");
  assert.equal(ledger.secondsToMidnight(), 23.5 * 3600);
});

test("ledger: 0 turns the limits and the cap off", () => {
  const ledger = new DailyLedger({ timeZone: "UTC", dailyLimit: 0, dailyCheckLimit: 0, budgetUsd: 0 });
  ledger.record({ inputTokens: 1, outputTokens: 1, costUsd: 1000 });
  for (let i = 0; i < 500; i++) assert.equal(ledger.admit("a", "study", "/v1/study-kit").ok, true);
  const report = ledger.report("a");
  assert.equal(report.budgetUsd, null);
  assert.equal(report.you.study, 500);
  assert.equal(report.you.studyLimit, null);
});

test("ledger: clients are counted separately", () => {
  const ledger = new DailyLedger({ timeZone: "UTC", dailyLimit: 1, dailyCheckLimit: 1, budgetUsd: 5 });
  assert.equal(ledger.admit("a", "study", "/v1/quiz").ok, true);
  assert.equal(ledger.admit("a", "study", "/v1/quiz").ok, false);
  assert.equal(ledger.admit("b", "study", "/v1/quiz").ok, true);
  assert.equal(ledger.admit("a", "check", "/v1/check-answer").ok, true);
});

test("settings: defaults", () => {
  const c = readConfig({});
  assert.equal(c.port, 8787);
  assert.equal(c.rateLimit, 30);
  assert.equal(c.dailyLimit, 60);
  assert.equal(c.dailyCheckLimit, 300);
  assert.equal(c.dailyBudgetUsd, 5);
  assert.equal(c.timeZone, "Asia/Manila");
  assert.equal(c.trustProxy, 0);
  assert.equal(c.healthDetails, false);
});

test("settings: values are read, and a bad one stops the server instead of switching a limit off", () => {
  const c = readConfig({
    PORT: "10000",
    TRUST_PROXY: "1",
    DAILY_BUDGET_USD: "2.5",
    DAILY_LIMIT: "0",
    HEALTH_DETAILS: "true",
    DAY_TIME_ZONE: "UTC",
  });
  assert.equal(c.port, 10000);
  assert.equal(c.trustProxy, 1);
  assert.equal(c.dailyBudgetUsd, 2.5);
  assert.equal(c.dailyLimit, 0);
  assert.equal(c.healthDetails, true);
  assert.equal(readConfig({ TRUST_PROXY: "0" }).trustProxy, 0);
  assert.equal(readConfig({ TRUST_PROXY: "2" }).trustProxy, 2);
  assert.equal(readConfig({ TRUST_PROXY: "true" }).trustProxy, 1);
  for (const env of [
    { RATE_LIMIT: "lots" },
    { RATE_LIMIT: "0" },
    { DAILY_BUDGET_USD: "-1" },
    { DAILY_LIMIT: "1.5" },
    { TRUST_PROXY: "maybe" },
    { DAY_TIME_ZONE: "Mars/Olympus" },
  ]) {
    assert.throws(() => readConfig(env), ConfigError, JSON.stringify(env));
  }
});
