// A stand-in for the Anthropic Messages API on :8797 for an end-to-end run:
// the real study server streams from it exactly as it would from Claude.
// It answers by the JSON schema the server asks for (study kit, quiz or
// answer check) and logs what it was sent.
import http from "node:http";

function events(json, model = "claude-opus-5-5") {
  const text = JSON.stringify(json);
  const half = Math.floor(text.length / 2);
  return [
    { type: "message_start", message: { id: "msg_e2e", type: "message", role: "assistant", model, content: [], stop_reason: null, stop_sequence: null, stop_details: null, usage: { input_tokens: 1200, output_tokens: 1, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 } } },
    { type: "content_block_start", index: 0, content_block: { type: "text", text: "", citations: null } },
    { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: text.slice(0, half) } },
    { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: text.slice(half) } },
    { type: "content_block_stop", index: 0 },
    { type: "message_delta", delta: { stop_reason: "end_turn", stop_sequence: null, stop_details: null }, usage: { input_tokens: 1200, output_tokens: 3400 } },
    { type: "message_stop" },
  ];
}

function answerFor(body) {
  const props = body?.output_config?.format?.schema?.properties ?? {};
  const user = JSON.stringify(body.messages ?? []);
  if ("verdict" in props) {
    return { verdict: "partly", feedback: "E2E feedback: close, but the key word is mitochondria." };
  }
  if ("questions" in props) {
    const allowed = (user.match(/Allowed types: ([a-z_, ]+)/)?.[1] ?? "multiple_choice")
      .split(",").map((s) => s.trim());
    const qs = [];
    if (allowed.includes("multiple_choice")) {
      qs.push({ type: "multiple_choice", prompt: "E2E question: what makes ATP?", options: ["Ribosome", "Mitochondria", "Nucleus", "Golgi"], answerIndex: 1, answer: "Mitochondria", acceptable: [], explanation: "E2E explanation.", cardIndex: 0 });
    }
    if (allowed.includes("typed")) {
      qs.push({ type: "typed", prompt: "E2E typed: which organelle makes ATP?", options: [], answerIndex: -1, answer: "Mitochondria", acceptable: [], explanation: "", cardIndex: 0 });
    }
    if (allowed.includes("true_false")) {
      qs.push({ type: "true_false", prompt: "E2E: ribosomes make proteins.", options: ["True", "False"], answerIndex: 0, answer: "True", acceptable: [], explanation: "", cardIndex: 1 });
    }
    return { questions: qs };
  }
  return { title: "E2E", summary: "E2E summary", notes: "# E2E", concepts: [], cards: [{ front: "E2E front", back: "E2E back" }], quiz: [] };
}

http.createServer((req, res) => {
  let raw = "";
  req.setEncoding("utf8");
  req.on("data", (c) => (raw += c));
  req.on("end", () => {
    let body = {};
    try { body = JSON.parse(raw || "{}"); } catch {}
    const props = Object.keys(body?.output_config?.format?.schema?.properties ?? {});
    console.log(`${new Date().toISOString()} ${req.method} ${req.url} model=${body.model} effort=${body?.output_config?.effort} thinking=${body?.thinking?.type} fallbacks=${body.fallbacks} beta=${req.headers["anthropic-beta"]} schema=[${props.join(",")}] max_tokens=${body.max_tokens}`);
    const reply = answerFor(body);
    res.writeHead(200, { "content-type": "text/event-stream", "request-id": "req_e2e" });
    for (const e of events(reply)) res.write(`event: ${e.type}\ndata: ${JSON.stringify(e)}\n\n`);
    res.end();
  });
}).listen(8797, "127.0.0.1", () => console.log("fake Claude on 8797"));
