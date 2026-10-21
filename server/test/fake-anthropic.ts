// A stand-in for the Anthropic API on localhost, so the real SDK (streaming,
// aborts, error classes) can be tested without a key or the network.

import { createServer, type IncomingHttpHeaders, type Server } from "node:http";

import Anthropic from "@anthropic-ai/sdk";

export type FakeReply =
  /** Server-sent events, as the Messages API streams them. */
  | { sse: object[]; errorEvent?: object; hang?: boolean }
  /** A plain HTTP error. */
  | { status: number; body: object; headers?: Record<string, string> };

export interface SeenRequest {
  headers: IncomingHttpHeaders;
  body: Record<string, any>;
}

type Block =
  | { type: "text"; text: string }
  | { type: "fallback"; from: string; to: string };

/** The stream for one message with [content]. */
export function messageEvents(o: {
  model?: string;
  content: Block[];
  stopReason?: string;
  stopDetails?: object | null;
  inputTokens?: number;
  outputTokens?: number;
  iterations?: object[];
}): object[] {
  const inputTokens = o.inputTokens ?? 1000;
  const events: object[] = [
    {
      type: "message_start",
      message: {
        id: "msg_fake",
        type: "message",
        role: "assistant",
        model: o.model ?? "claude-opus-5-5",
        content: [],
        stop_reason: null,
        stop_sequence: null,
        stop_details: null,
        usage: {
          input_tokens: inputTokens,
          output_tokens: 1,
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
        },
      },
    },
  ];
  o.content.forEach((b, index) => {
    if (b.type === "text") {
      events.push({
        type: "content_block_start",
        index,
        content_block: { type: "text", text: "", citations: null },
      });
      const half = Math.floor(b.text.length / 2);
      for (const part of [b.text.slice(0, half), b.text.slice(half)]) {
        events.push({ type: "content_block_delta", index, delta: { type: "text_delta", text: part } });
      }
    } else {
      events.push({
        type: "content_block_start",
        index,
        content_block: {
          type: "fallback",
          from: { model: b.from },
          to: { model: b.to },
          trigger: { type: "refusal" },
        },
      });
    }
    events.push({ type: "content_block_stop", index });
  });
  events.push(
    {
      type: "message_delta",
      delta: {
        stop_reason: o.stopReason ?? "end_turn",
        stop_sequence: null,
        stop_details: o.stopDetails ?? null,
      },
      usage: {
        input_tokens: inputTokens,
        output_tokens: o.outputTokens ?? 500,
        ...(o.iterations ? { iterations: o.iterations } : {}),
      },
    },
    { type: "message_stop" },
  );
  return events;
}

export class FakeAnthropic {
  readonly requests: SeenRequest[] = [];
  /** Requests whose client went away before the reply was finished. */
  aborted = 0;
  private replies: FakeReply[] = [];
  private server: Server | undefined;
  private abortWaiters: Array<() => void> = [];
  url = "";

  /** Queues the replies for the next requests, in order. */
  reply(...replies: FakeReply[]): this {
    this.replies.push(...replies);
    return this;
  }

  /** A real SDK client that talks to this fake. */
  client(): Anthropic {
    return new Anthropic({ apiKey: "sk-ant-fake", baseURL: this.url, maxRetries: 0 });
  }

  /** Resolves once a request has been abandoned by its client. */
  nextAbort(): Promise<void> {
    return new Promise((resolve) => this.abortWaiters.push(resolve));
  }

  async start(): Promise<this> {
    this.server = createServer((req, res) => {
      let raw = "";
      req.setEncoding("utf8");
      req.on("data", (chunk: string) => (raw += chunk));
      req.on("end", () => {
        this.requests.push({ headers: req.headers, body: raw ? JSON.parse(raw) : {} });
        res.on("close", () => {
          if (!res.writableFinished) {
            this.aborted++;
            for (const w of this.abortWaiters.splice(0)) w();
          }
        });
        const reply = this.replies.shift();
        if (!reply) {
          res.writeHead(500, { "content-type": "application/json" });
          res.end(JSON.stringify({ type: "error", error: { type: "api_error", message: "no reply queued" } }));
          return;
        }
        if ("status" in reply) {
          res.writeHead(reply.status, { "content-type": "application/json", ...reply.headers });
          res.end(JSON.stringify(reply.body));
          return;
        }
        res.writeHead(200, { "content-type": "text/event-stream", "request-id": "req_fake" });
        for (const e of reply.sse) {
          res.write(`event: ${(e as { type: string }).type}\ndata: ${JSON.stringify(e)}\n\n`);
        }
        if (reply.errorEvent) {
          res.write(`event: error\ndata: ${JSON.stringify(reply.errorEvent)}\n\n`);
        }
        if (!reply.hang) res.end();
      });
    });
    await new Promise<void>((resolve) => this.server!.listen(0, "127.0.0.1", resolve));
    const address = this.server.address();
    if (!address || typeof address !== "object") throw new Error("no address");
    this.url = `http://127.0.0.1:${address.port}`;
    return this;
  }

  close(): Promise<void> {
    return new Promise((resolve) => {
      this.server?.closeAllConnections();
      this.server?.close(() => resolve());
    });
  }
}
