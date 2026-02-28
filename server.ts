import Anthropic from "@anthropic-ai/sdk";
import { createServer, IncomingMessage, ServerResponse } from "http";
import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(__dirname, "public/index.html"), "utf-8");

function body(req: IncomingMessage): Promise<any> {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", chunk => (data += chunk));
    req.on("end", () => {
      try { resolve(JSON.parse(data)); } catch { reject(new Error("Invalid JSON")); }
    });
  });
}

function json(res: ServerResponse, code: number, data: any) {
  const payload = JSON.stringify(data);
  res.writeHead(code, { "Content-Type": "application/json" });
  res.end(payload);
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url!, `http://localhost`);

  if (url.pathname === "/" && req.method === "GET") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(html);
    return;
  }

  if (url.pathname === "/api/send" && req.method === "POST") {
    try {
      const { payload, apiKey } = await body(req);
      if (!apiKey) return json(res, 400, { error: "API key required" });

      const client = new Anthropic({ apiKey });
      const response = await (client.messages.create as any)(payload);
      json(res, 200, { response });
    } catch (e: any) {
      json(res, 500, { error: e.message });
    }
    return;
  }

  res.writeHead(404);
  res.end("Not Found");
});

server.listen(3000, () => console.log("🔍 Claude Inspector → http://localhost:3000"));
