<div align="center">

# Claude Inspector

**See what Claude Code actually sends to the API.**

MITM proxy that intercepts Claude Code CLI traffic in real-time,<br>
plus a simulator to hand-craft and test all 5 prompt augmentation mechanisms.

[Getting Started](#getting-started) · [Proxy Mode](#-proxy-mode) · [Simulator Mode](#-simulator-mode) · [How It Works](#how-it-works)

</div>

---

<p align="center">
  <img src="public/screenshots/proxy-request.png" width="49%" alt="Proxy Request View" />
  <img src="public/screenshots/proxy-analysis.png" width="49%" alt="Proxy Analysis View" />
</p>

## Getting Started

```bash
git clone https://github.com/kangraemin/claude-inspector.git
cd claude-inspector
npm install
npm start
```

## Proxy Mode

Intercept **real** Claude Code CLI traffic via a local MITM proxy.

```
Claude Code CLI  →  Inspector (localhost:9090)  →  api.anthropic.com
```

**1.** Click **Start Proxy** in the app<br>
**2.** Run Claude Code through the proxy:

```bash
ANTHROPIC_BASE_URL=http://localhost:9090 claude
```

**3.** Every API request/response is captured in real-time.

### What you can do

| Tab | Description |
|-----|-------------|
| **Messages** | Browse `messages[]` by role — filter by user/assistant/system, full-text search (`Cmd+F`) |
| **Request** | Raw request JSON with collapsible tree, mechanism filter chips (CLAUDE.md, Slash Cmd, Skill...) |
| **Response** | Full response including SSE stream auto-reassembly |
| **Analysis** | Auto-detects which of the 5 mechanisms are present and explains each one |

## Simulator Mode

Build API payloads by hand and send them to Claude — great for understanding how each mechanism actually works at the API level.

| Mechanism | Injection Point | Sendable |
|-----------|----------------|----------|
| **CLAUDE.md** | `messages[].content` → `<system-reminder>` | Yes |
| **Output Style** | `system[]` additional block | Yes |
| **Slash Command** | `messages[].content` → `<command-message>` | Yes |
| **Skill** | `tool_result` after `tool_use` | Inspect only |
| **Sub-Agent** | Separate isolated API call | Inspect only |

Features: live JSON preview, **Send to Claude** with real API calls, **Export** to cURL / Python / TypeScript, session history (last 10 requests).

## How It Works

Claude Code enhances every API call with up to **5 prompt augmentation mechanisms**. These are invisible during normal usage. Claude Inspector makes them visible by:

1. **Proxy Mode** — sits between Claude Code and the Anthropic API, capturing the full request/response payload before it leaves your machine
2. **Simulator Mode** — lets you construct the same payload structures manually to understand exactly what each mechanism adds

> **Privacy**: All traffic stays on your machine. The proxy runs on `localhost` only. No data is sent anywhere except directly to `api.anthropic.com`.

## Tech Stack

- **Electron** — cross-platform desktop (macOS `hiddenInset` titlebar)
- **Vanilla JS** — zero frameworks, zero build steps
- **Node `http`/`https`** — lightweight MITM proxy
- **@anthropic-ai/sdk** — API calls in main process via IPC
- **highlight.js** + **marked** — syntax highlighting & markdown rendering

## Build

```bash
npm run dist         # .dmg + .exe
npm run dist:mac     # macOS only (arm64 + x64)
npm run dist:win     # Windows only (NSIS)
```

## Related

Built on top of the research from [Reverse Engineering Claude Code — How Skills Different from Agents, Commands, and Styles](https://levelup.gitconnected.com/reverse-engineering-claude-code-how-skills-different-from-agents-commands-and-styles-b94f8c8f9245).

## License

MIT
