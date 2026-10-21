// A stand-in study server on :8799 that never answers POSTs in time and
// logs when the app drops the connection (to prove Cancel cuts the request).
import http from "node:http";

const server = http.createServer((req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Request-Id");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  if (req.method === "OPTIONS") return res.writeHead(204).end();
  if (req.url === "/health") return res.writeHead(200, { "content-type": "application/json" }).end('{"ok":true}');
  const started = Date.now();
  console.log(`${new Date().toISOString()} ${req.method} ${req.url} received`);
  res.on("close", () => {
    if (!res.writableEnded) {
      console.log(`${new Date().toISOString()} CLIENT CLOSED ${req.url} after ${Date.now() - started} ms`);
    }
  });
  const t = setTimeout(() => {
    res.writeHead(503, { "content-type": "application/json" });
    res.end('{"error":{"code":"busy","message":"slow test server"}}');
  }, 60_000);
  res.on("close", () => clearTimeout(t));
});
server.listen(8799, "127.0.0.1", () => console.log("slow server on 8799"));
