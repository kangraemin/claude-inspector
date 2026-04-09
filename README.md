<div align="center">

# Claude Inspector

**See what Claude Code actually sends to the API — then let AI explain it.**

MITM proxy that intercepts Claude Code CLI traffic in real-time,<br>
visualizes all prompt augmentation mechanisms, and **analyzes session flows with AI**.

[Install](#install) · [AI Flow](#ai-flow) · [What You'll Learn](#what-youll-learn) · [Proxy Mode](#proxy-mode) · [Tech Stack](#tech-stack)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/kangraemin/claude-inspector)](https://github.com/kangraemin/claude-inspector/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-arm64%20%7C%20x64-black)](https://github.com/kangraemin/claude-inspector/releases/latest)

**English** | [한국어](README.ko.md)

</div>

---

<p align="center">
  <img src="public/screenshots/en-1.png" width="100%" alt="Proxy — Analysis view" />
</p>

<p align="center">
  <img src="public/screenshots/en-2.png" width="100%" alt="Proxy — Request view with cost breakdown" />
</p>

<p align="center">
  <img src="public/screenshots/en-3.png" width="100%" alt="Proxy — Request view" />
</p>

## AI Flow

**v1.2.0 NEW** — Select captured requests and let Claude (Sonnet) analyze the session flow.

### What It Does

AI Flow sends your captured request/response data to `claude -p` (Sonnet) and produces:

- **Step-by-step session summary** — what happened, in what order, with mechanism explanations
- **MCP dynamic loading chain** — how ToolSearch fetches schemas, how deferred tools become callable
- **Skill loading flow** — how slash commands trigger `<command-message>` → Skill tool_use
- **Sub-agent patterns** — which requests are main vs sub-agent, and how they relate
- **Mermaid flowchart** — visual diagram of the internal mechanism flow
- **Clickable references** — each step links to the actual Request, scrolling to the relevant tool_use

### How to Use

1. Capture some requests via the proxy
2. Click the **AI Flow** tab
3. Select requests to analyze (click to toggle, Shift+click for range)
4. Click **Analyze Session Flow**
5. Watch real-time streaming progress as Claude processes
6. Click any **Request #N** badge to jump to that request's tool_use in the JSON tree

### In-app Chat

After analysis, ask Claude follow-up questions about the session. The chat understands the full analysis context.

### Session Detection

Requests are automatically grouped by session using message content fingerprinting. Different sessions (main conversation, sub-agents, stop hooks) get different colored borders in the sidebar.

## What You'll Learn

All discovered from **real captured traffic**. See what Claude Code hides from you.

### 1. CLAUDE.md is injected into every single request

You type `hello`. Claude Code silently prepends **~12KB** before your message:

| Block | What's inside | Size |
|-------|--------------|------|
| `content[0]` | Available skills list | ~2KB |
| `content[1]` | CLAUDE.md + rules + memory | **~10KB** |
| `content[2]` | What you actually typed | few bytes |

**Injection order:** Global CLAUDE.md → Global rules → Project CLAUDE.md → Memory

This ~12KB payload is re-sent with **every request**. A 500-line CLAUDE.md quietly burns tokens on every API call. Keep it lean.

### 2. MCP tools are lazy-loaded — watch `tools[]` grow

Built-in tools (27) ship their full JSON schemas every request. MCP tools don't — they start as **names only**.

**Watch the count change in real-time:**

| Step | What happens | `tools[]` count |
|------|-------------|-----------------|
| Initial request | 27 built-in tools loaded | **27** |
| Model calls `ToolSearch("context7")` | Full schema for 2 MCP tools returned | **29** |
| Model calls `ToolSearch("til")` | 6 more MCP tool schemas added | **35** |

Unused MCP tools never consume tokens. The Inspector lets you watch `tools[]` grow as the model discovers what it needs.

### 3. Images are base64-encoded inline

When Claude Code reads a screenshot or image file, the image is **base64-encoded and embedded directly** in the JSON body:

```json
{
  "type": "image",
  "source": {
    "type": "base64",
    "media_type": "image/png",
    "data": "iVBORw0KGgo..."
  }
}
```

A single screenshot can add **hundreds of KB** to the request payload. The Inspector shows you the exact size.

### 4. Skill ≠ Command — completely different injection paths

Typing `/something` triggers one of three completely different mechanisms:

| | Local Command | User Skill | Assistant Skill |
|---|---|---|---|
| **Example** | `/mcp`, `/clear` | `/commit` | `Skill("finish")` |
| **Who triggers** | User | User | Model |
| **Injection** | `<local-command-stdout>` | Full prompt in user msg | `tool_use` → `tool_result` |
| **Model sees** | Result only | Full prompt | Full prompt |

**Commands** run locally and only pass the result. **Skills** inject the entire prompt text — and it **stays in every subsequent request** until the session ends.

### 5. Previous messages pile up — use `/clear` often

Claude Code re-sends the **entire** `messages[]` array with every request:

| Turns | Approx. cumulative transfer |
|-------|---------------------|
| 1 | ~15KB |
| 10 | ~200KB |
| 30 | ~1MB+ |

Most of it is old conversation you no longer need. Running `/clear` resets the context and drops the accumulated weight.

### 6. Sub-agents run in fully isolated contexts

When Claude Code spawns a sub-agent (via the `Agent` tool), it creates a **completely separate API call**. The parent and sub-agent have entirely different `messages[]`:

| | Parent API call | Sub-agent API call |
|---|---|---|
| **`messages[]`** | Full conversation history | Only the task prompt — **no parent history** |
| **CLAUDE.md** | Included | Included (independently) |
| **tools[]** | All loaded tools | Fresh set |
| **Context** | Accumulated | Starts from zero |

The Inspector captures both calls side by side, and AI Flow automatically detects and labels sub-agent sessions.

## Install

### Homebrew (Recommended)

```bash
brew install --cask kangraemin/tap/claude-inspector && sleep 2 && open -a "Claude Inspector"
```

### Direct Download

Download the `.dmg` from the [Releases](https://github.com/kangraemin/claude-inspector/releases/latest) page.

| Mac (Apple Silicon) | Mac (Intel) |
|---|---|
| [Claude-Inspector-arm64.dmg](https://github.com/kangraemin/claude-inspector/releases/latest) | [Claude-Inspector-x64.dmg](https://github.com/kangraemin/claude-inspector/releases/latest) |

### Upgrade

```bash
brew update && brew upgrade --cask claude-inspector && sleep 2 && open -a "Claude Inspector"
```

### Uninstall

```bash
brew uninstall --cask claude-inspector
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

**4 tabs to explore:**

| Tab | What it shows |
|-----|--------------|
| **AI Flow** | AI-powered session analysis with flowchart and chat |
| **Request** | Full JSON request body with collapsible tree, token cost breakdown |
| **Response** | Full JSON response with tool_use results |
| **Analysis** | Detected mechanisms (CLAUDE.md, Skills, MCP, Sub-agents) with colored chips |

## Development

```bash
git clone https://github.com/kangraemin/claude-inspector.git
cd claude-inspector
npm install
npm start        # Run in dev mode
npm run test:unit  # Unit tests
npm run test:e2e   # E2E tests (Playwright)
```

## Tech Stack

| Layer | What | Why |
|-------|------|-----|
| **Electron** | Desktop shell, IPC | Native macOS titlebar, code-signed + notarized DMG |
| **Vanilla JS** | Zero frameworks | Entire UI in a single `index.html` — no bundler, no React |
| **Node `http`/`https`** | MITM proxy | Intercepts Claude Code ↔ API traffic, reassembles SSE streams |
| **Mermaid.js** | Flowchart rendering | AI Flow mechanism diagrams |
| **claude -p** | AI analysis engine | Session flow analysis + in-app chat via Claude Sonnet |

> **Privacy**: All proxy traffic stays on `localhost`. AI Flow analysis runs locally via `claude -p` (your own Claude Code CLI).

## License

MIT
