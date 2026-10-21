# tAsikaso study server

A small Node.js service that the app calls to turn scanned notes into
clean notes, key concepts, flashcards and quizzes, and to mark typed quiz
answers. It holds the Anthropic API key, so the key never ships inside the
app. Claude Opus 5.5 at `high` effort by default; both are settings.

## Run it on your computer

Needs Node.js 20 or newer.

```bash
cd server
npm install
copy .env.example .env      # then put your ANTHROPIC_API_KEY and an APP_TOKEN in .env
npm run dev                 # http://localhost:8787
```

`npm run try` sends built-in sample notes straight through Claude and
prints the result, so you can check the key and see what a study kit looks
like. `npm run try -- notes.txt` does the same with your own text.

To use the local server from the app: on a phone on the same Wi-Fi, set the
server address in the app to `http://<your PC's IP>:8787` (Settings → Smart
Study); on the web build use `http://localhost:8787`.

## Put it on your website

Any host that runs Node works. Build with `npm install && npm run build`,
start with `npm start`, and set these environment variables:

| Variable | What it is |
|---|---|
| `ANTHROPIC_API_KEY` | Your key from platform.claude.com. |
| `APP_TOKEN` | A long random string; the app sends it as `Authorization: Bearer …`. |
| `PORT` | Usually set by the host. |
| `TRUST_PROXY` | `1` on Render, Railway, Vercel, nginx etc., so rate limits see the real client address. |
| `CLAUDE_MODEL` | Default `claude-opus-5-5`. |
| `CLAUDE_EFFORT` | Default `high` (`low`, `medium`, `high`, `xhigh`, `max`). |
| `CLAUDE_CHECK_EFFORT` | Effort for marking one typed answer. Default `low`: it's a quick judgement and the student is waiting. |
| `RATE_LIMIT` | Requests per device per 10 minutes. Default 30. |

Free tiers on Render and Railway are enough to start. The server has no
database; nothing is stored between requests.

Then put the server's address and the token into the app: Settings → Smart
Study, or bake them in at build time with
`flutter build apk --dart-define=STUDY_AI_URL=https://… --dart-define=STUDY_AI_TOKEN=…`.

## What it costs

Opus 5.5 is $4 per million input tokens and $20 per million output tokens
(thinking counts as output). A three-page scan is roughly 2–4k tokens in
and, at `high` effort, 8–20k out including thinking, so about $0.15–0.45 —
₱9–26 — per study kit, and a few centavos per answer check. `CLAUDE_EFFORT=medium`
roughly halves that; `CLAUDE_MODEL=claude-sonnet-5-5` halves it again.
Rate limits and the app token are what stand between you and someone
else's bill, so keep the token private and watch the usage page.

## Endpoints

All take and return JSON. Errors look like `{"error": {"code": "…", "message": "…"}}`.

- `GET /health` → `{ok, model, effort}`; no token needed.
- `POST /v1/study-kit` `{text, title?, maxCards?, quizCount?}` →
  `{kit: {title, summary, notes, concepts[], cards[], quiz[]}, model, usage}`.
  `notes` uses plain lines: `# ` heading, `## ` section, `- ` bullet, blank
  line between blocks.
- `POST /v1/quiz` `{title?, cards[], concepts?, count?, types?}` → `{quiz: {questions[]}, model, usage}`.
- `POST /v1/check-answer` `{question, answer, acceptable?, userAnswer}` →
  `{check: {verdict, feedback}, model, usage}` with verdict `correct`, `partly` or `wrong`.

A quiz question is `{type, prompt, options, answerIndex, answer, acceptable, explanation, cardIndex}`
with type `multiple_choice`, `true_false`, `fill_blank` or `typed`. See
`src/schemas.ts` for the exact shapes.

Error codes: `unauthorized` (401), `bad_request` (400), `rate_limited` and
`busy` (429), `declined` (422, Claude's safety filters), `too_long` (413),
`upstream` (502), `server_key` (500).

## Layout

```
src/index.ts     starts the server (reads .env when present)
src/app.ts       Express routes, token check, rate limit, error replies
src/claude.ts    the Claude calls: structured JSON output, adaptive thinking, refusal fallbacks
src/prompts.ts   what Claude is asked to do
src/schemas.ts   request and response shapes (zod)
src/normalize.ts tidies Claude's output so every card and question is usable
scripts/try.ts   one study kit from the command line
test/            npm test (no API calls)
```
