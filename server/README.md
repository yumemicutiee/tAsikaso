# tAsikaso study server

A small Node.js service that the app calls to turn scanned notes into
clean notes, key concepts, flashcards and quizzes, and to mark typed quiz
answers. It holds the Anthropic API key, so the key never ships inside the
app. Claude Opus 5.5 at `high` effort by default; both are settings.

## Run it on your computer

Needs Node.js 22 or newer (24 LTS recommended).

```bash
cd server
npm install
copy .env.example .env      # then put your ANTHROPIC_API_KEY and an APP_TOKEN in .env
npm run dev                 # http://localhost:8787
```

**First thing after adding your key**, check that Claude answers:

- `npm run try` sends built-in sample notes straight through Claude and
  prints the study kit, the tokens, the cost and how long it took.
  `npm run try -- notes.txt` does the same with your own text.
- `LIVE_CLAUDE=1 npm test` (PowerShell: `$env:LIVE_CLAUDE=1; npm test`)
  runs the normal tests plus one live study kit, and checks that every card
  and question in it is usable. Costs a few US cents.

To use the local server from the app: on a phone on the same Wi-Fi, set the
server address in the app to `http://<your PC's IP>:8787` (Settings → Smart
Study); on the web build use `http://localhost:8787`. Plain `http://` only
works in **debug** builds of the Android app (Android blocks it otherwise);
a release build needs an `https://` address, which any host gives you.

## Deploy

A study kit at `high` effort takes 30–120 seconds, so the server needs a
host that keeps a normal, long-running Node process. **Serverless
functions with short time limits (Vercel, Netlify and the like) will cut
study kits off** and are not suitable. Render, Railway, Fly.io, a VPS or
any machine that runs Node or Docker all work.

### Render (free tier is fine to start)

`render.yaml` in this folder is a Render Blueprint for the service.

1. Push the repo to GitHub.
2. Make a random app token and keep it for step 5:
   `node -e "console.log(require('crypto').randomBytes(32).toString('base64url'))"`
3. On [render.com](https://render.com): **New → Blueprint**, connect the
   repo, and set **Blueprint path** to `server/render.yaml`.
4. Render asks for the two secrets: `ANTHROPIC_API_KEY` (from
   platform.claude.com → API keys) and `APP_TOKEN` (from step 2). The other
   settings are filled in from the Blueprint; change them later under the
   service's **Environment** tab.
5. Wait for the first deploy, then open
   `https://<service>.onrender.com/health`; it should say `{"ok":true}`.
6. In the app, Settings → Smart Study: server address
   `https://<service>.onrender.com`, token from step 2. Or build them in:
   `flutter build apk --dart-define=STUDY_AI_URL=https://<service>.onrender.com --dart-define=STUDY_AI_TOKEN=…`.
7. Check the limits are counted per phone: call `GET /v1/usage` (with the
   token) from two phones on different networks; `you.address` should
   differ. If every phone shows the same address, Render has an extra proxy
   in front, so set `TRUST_PROXY=2`.

Without the Blueprint, **New → Web Service** works too: root directory
`server`, build command `npm ci && npm run build`, start command
`npm start`, health check path `/health`, and the environment variables
from the table below (`TRUST_PROXY=1`, `NODE_VERSION=24`). Don't set
`NODE_ENV=production` for the build, or `npm ci` skips TypeScript.

The free tier sleeps after 15 minutes without requests; the first request
after that waits 30–60 seconds while it wakes (the app allows 3 minutes),
and each wake-up starts the daily counters from zero (see below). A paid
instance stays awake.

### Docker, a VPS or another host

```bash
docker build -t tasikaso-study-server server
docker run -d -p 8787:8787 --restart unless-stopped \
  -e ANTHROPIC_API_KEY=sk-ant-... -e APP_TOKEN=... -e TRUST_PROXY=1 \
  tasikaso-study-server
```

The image is Node 24 on Alpine with only the compiled server and its
runtime dependencies, running as a non-root user. Put it (or `npm ci &&
npm run build && npm start` on any machine with Node) behind something
that serves HTTPS, such as Caddy or nginx; set `TRUST_PROXY` to the number
of proxies in front (usually 1). The server listens on `PORT`.

## Settings

Environment variables (or `.env` when running locally). A value that is
set but can't be used stops the server at start-up with a message, rather
than quietly switching a limit off.

| Variable | Default | What it is |
|---|---|---|
| `ANTHROPIC_API_KEY` | (required) | Your key from platform.claude.com. |
| `APP_TOKEN` | (none: open) | A long random string; the app sends it as `Authorization: Bearer …`. Always set it on a public server. |
| `PORT` | `8787` | Usually set by the host (Render uses 10000). |
| `TRUST_PROXY` | `0` | Number of proxies in front of the server. `1` on Render, Railway, nginx etc., so the limits see each device's real address. |
| `CLAUDE_MODEL` | `claude-opus-5-5` | The model. Prices for the cap are in `src/pricing.ts`. |
| `CLAUDE_EFFORT` | `high` | `low`, `medium`, `high`, `xhigh` or `max`, for study kits and quizzes. |
| `CLAUDE_CHECK_EFFORT` | `low` | Effort for marking one typed answer: a quick judgement while the student waits. |
| `RATE_LIMIT` | `30` | Requests per device per 10 minutes (any route). |
| `DAILY_LIMIT` | `60` | Study kits + quizzes per device per day. `0` = no daily limit. |
| `DAILY_CHECK_LIMIT` | `300` | Answer checks per device per day. `0` = no daily limit. |
| `DAILY_BUDGET_USD` | `5` | Estimated Claude spend per day for the whole server, in US dollars. `0` = no cap. |
| `DAY_TIME_ZONE` | `Asia/Manila` | Whose midnight starts a new day for the daily limits. |
| `HEALTH_DETAILS` | off | `1` = `/health` also shows the model and effort. |

## What it costs, and the limits that protect the bill

Opus 5.5 is $4 per million input tokens and $20 per million output tokens
(thinking counts as output). A three-page scan is roughly 2–4k tokens in
and, at `high` effort, 8–20k out including thinking, so about $0.15–0.45 —
₱9–26 — per study kit, and a few centavos per answer check. `CLAUDE_EFFORT=medium`
roughly halves that; `CLAUDE_MODEL=claude-sonnet-5-5` halves it again.

Every Claude call is priced from the token counts Anthropic returns
(every attempt, including a declined one before a refusal fallback, at its
own model's price) and added to today's total. Four limits stand between
the server and a surprise bill:

- **The app token.** Without it, nothing reaches Claude. Keep it private.
- **The 10-minute rate limit** per device (`RATE_LIMIT`).
- **The daily limit** per device (`DAILY_LIMIT` study kits and quizzes,
  `DAILY_CHECK_LIMIT` answer checks). Over it, the app shows "You've
  reached today's limit of 60 Smart Study requests. Try again tomorrow."
- **The daily spend cap** for the whole server (`DAILY_BUDGET_USD`). Once
  today's estimate reaches it, every request gets "The study server has
  reached today's limit. Try again tomorrow." until midnight in
  `DAY_TIME_ZONE`. $5 is roughly 10–30 study kits a day for everyone
  together; raise it once `/v1/usage` and the Claude Console show what real
  use costs.

Things to know about these limits:

- They are kept **in memory**, which is right for one server process. A
  restart, a deploy or a free instance waking up starts the day's counters
  from zero, and several instances would each count on their own. For more
  than that, keep the counters in a shared store (Redis or a database).
- A "device" is an IP address. Phones behind the same school Wi-Fi or the
  same mobile-network gateway share one allowance. Per-student limits need
  per-student tokens or accounts.
- The cap is checked before each request starts, so requests already
  running when it's reached can take the day a little over it.
- A request the app abandons is stopped at once (below), but what Claude
  generated until then is billed and isn't reported back, so the server
  estimates it from how long the call ran.
- Prices for models missing from `src/pricing.ts` are taken as the dearest
  in it, so the estimate errs high. The Claude Console's usage page is the
  real bill: **also set a monthly spend limit there** as the backstop that
  survives restarts.

## Endpoints

All take and return JSON. Every reply carries an `X-Request-Id` header (the
app's own `X-Request-Id` is kept if it sends one); quote it when reporting
a problem, since the server's log line for the request has the same id.
Errors look like `{"error": {"code": "…", "message": "…", "requestId": "…"}}`;
`message` is written for students and the app shows it as it is.

- `GET /health` → `{ok: true}`; no token needed. With `HEALTH_DETAILS=1`
  also `{model, effort, checkEffort}`.
- `POST /v1/study-kit` `{text, title?, maxCards?, quizCount?}` →
  `{kit: {title, summary, notes, concepts[], cards[], quiz[]}, model, usage}`.
  `text` is 20–120,000 characters. `maxCards` 0–60 (0 = just type up the
  notes), `quizCount` 0–40. `notes` uses plain lines: `# ` heading, `## `
  section, `- ` bullet, blank line between blocks.
- `POST /v1/quiz` `{title?, cards[], concepts?, count?, types?}` → `{quiz: {questions[]}, model, usage}`.
  Up to 200 cards and 120,000 characters of card text; only the `types`
  asked for come back.
- `POST /v1/check-answer` `{question, answer, acceptable?, userAnswer}` →
  `{check: {verdict, feedback}, model, usage}` with verdict `correct`, `partly` or `wrong`.
- `GET /v1/usage` (token needed) → today's numbers:
  `{day, timeZone, resetsInSeconds, requests, byRoute, refused, tokens,
  spentUsd, budgetUsd, remainingUsd, you: {address, study, studyLimit, checks, checkLimit}}`.

`usage` in the POST replies is `{input, output}` tokens. A quiz question is
`{type, prompt, options, answerIndex, answer, acceptable, explanation, cardIndex}`
with type `multiple_choice`, `true_false`, `fill_blank` or `typed`;
`answerIndex` counts from 0 and is -1 for `fill_blank` and `typed`. See
`src/schemas.ts` for the exact shapes.

**When the app gives up.** If the app closes the connection before the
answer is ready (its 3-minute timeout, or a Cancel button), the server
aborts the call to Claude straight away so the rest isn't generated and
paid for, writes nothing back, and logs the request with status 499 and
code `cancelled`.

### Error codes

| Code | HTTP | When |
|---|---|---|
| `bad_request` | 400 | The body is missing, isn't JSON, or a field is out of range; the message names the field. |
| `unauthorized` | 401 | Missing or wrong app token. |
| `not_found` | 404 | No such endpoint. |
| `too_long` | 413 | Notes, quiz or answer too big for one go (input over the limits, or Claude's answer didn't fit). |
| `declined` | 422 | Claude's safety filters declined, even after the refusal fallback. |
| `rate_limited` | 429 | Too many requests from this device in 10 minutes. `Retry-After` says when. |
| `daily_limit` | 429 | This device has used today's `DAILY_LIMIT` (or `DAILY_CHECK_LIMIT`). `Retry-After` = seconds to midnight. |
| `budget` | 503 | The server has spent `DAILY_BUDGET_USD` today. `Retry-After` = seconds to midnight. |
| `busy` | 503 | Anthropic is overloaded or the account's rate limit is hit. Try again in a minute. |
| `timeout` | 504 | Claude didn't answer in time. |
| `upstream` | 502 | Couldn't reach Claude, or Claude returned an error. |
| `bad_output` | 502 | Claude's answer wasn't the JSON asked for (empty or cut off). |
| `server_key` | 500 | The server's API key is missing or wrong. |
| `server_setup` | 500 | The Claude account can't be used: no credit, no access to the model, or a wrong `CLAUDE_MODEL`. |
| `internal` | 500 | A bug in the server; the log has the details. |

`cancelled` (499) is never sent, since the app has already gone; it only
appears in the log.

## Logs

One JSON line per request on stdout (the host keeps them):

```json
{"time":"2026-10-21T08:15:02.120Z","level":"info","msg":"request","requestId":"6f1c…","method":"POST","route":"/v1/study-kit","status":200,"ms":48210,"client":"9b2e41c07a1d","model":"claude-opus-5-5","inputTokens":3120,"outputTokens":14877,"costUsd":0.31002,"fallback":false}
```

`model` is the model that actually answered; `fallback: true` means
Claude Opus 5.5 declined and a refusal fallback model served the answer.
`client` is a short hash of the device's address, not the address itself.
`estimated: true` marks the cost of an abandoned request. Failures add a
`"request failed"` line with Anthropic's own status, error type and request
id. `/health` checks aren't logged.

## Tests

`npm test` runs offline: the Claude calls go to a fake Anthropic API on
localhost (`test/fake-anthropic.ts`) through the real SDK, so streaming,
aborts, refusals, `max_tokens`, overloads and broken JSON are all covered
without a key. The live test (`test/live.test.ts`) shows as skipped unless
`LIVE_CLAUDE=1` and `ANTHROPIC_API_KEY` are set. `npm run typecheck` checks
the server, the tests and the scripts. GitHub runs all of this on every
change under `server/` (`.github/workflows/server-ci.yml`).

## Later: very long notes

Study kits may use up to 64,000 output tokens, and input is capped at
120,000 characters (about 40k tokens), so a long chapter fits in one
request. A whole notebook would need splitting: cut the text at headings
or page breaks into pieces of ~30k characters, make a kit for each, then
merge the notes in order, de-duplicate cards and concepts, and draw the
quiz from the merged cards with `/v1/quiz`. That multiplies the cost and
the wait, so it would also need a progress display in the app; it isn't
built yet.

## Layout

```
src/index.ts     starts the server (reads .env when present, checks settings)
src/config.ts    environment variables
src/app.ts       Express routes, token check, limits, request ids, logs, error replies
src/claude.ts    the Claude calls: structured JSON output, adaptive thinking, refusal fallbacks, cost
src/pricing.ts   dollars per million tokens, by model
src/ledger.ts    today's requests and spend (daily limit and cap)
src/prompts.ts   what Claude is asked to do
src/schemas.ts   request and response shapes (zod)
src/normalize.ts tidies Claude's output so every card and question is usable
scripts/try.ts   one study kit from the command line
test/            npm test (no API calls)
render.yaml      Render Blueprint
Dockerfile       production image
```
