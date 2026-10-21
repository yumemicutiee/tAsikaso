import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import type { Server } from "node:http";

import { createApp } from "../src/app.js";

// Routes that never reach Claude: health, auth, validation, rate limiting.

let server: Server;
let base: string;

before(async () => {
  const app = createApp({ appToken: "secret", rateLimit: 2 });
  await new Promise<void>((resolve) => {
    server = app.listen(0, () => resolve());
  });
  const address = server.address();
  assert.ok(address && typeof address === "object");
  base = `http://127.0.0.1:${address.port}`;
});

after(() => server.close());

const post = (path: string, body: unknown, token?: string) =>
  fetch(base + path, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });

test("health needs no token", async () => {
  const res = await fetch(base + "/health");
  assert.equal(res.status, 200);
  const json = (await res.json()) as { ok: boolean; model: string };
  assert.equal(json.ok, true);
  assert.equal(json.model, "claude-opus-5-5");
});

test("a missing or wrong token is refused", async () => {
  const res = await post("/v1/study-kit", { text: "x".repeat(40) });
  assert.equal(res.status, 401);
  const wrong = await post("/v1/study-kit", { text: "x".repeat(40) }, "nope");
  assert.equal(wrong.status, 401);
});

test("a bad body is a 400 with a readable message", async () => {
  const res = await post("/v1/study-kit", { text: "short" }, "secret");
  assert.equal(res.status, 400);
  const json = (await res.json()) as { error: { code: string; message: string } };
  assert.equal(json.error.code, "bad_request");
  assert.match(json.error.message, /text/);
});

test("unknown paths are 404 JSON", async () => {
  const res = await fetch(base + "/nothing", {
    headers: { authorization: "Bearer secret" },
  });
  assert.equal(res.status, 404);
  const json = (await res.json()) as { error: { code: string } };
  assert.equal(json.error.code, "not_found");
});

test("the rate limit kicks in after the allowance", async () => {
  // Only requests that pass the token check count; the allowance is 2 and
  // the tests above have used some of it.
  let status = 0;
  for (let i = 0; i < 3 && status !== 429; i++) {
    status = (await post("/v1/check-answer", {}, "secret")).status;
  }
  assert.equal(status, 429);
});
