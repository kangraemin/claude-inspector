<div align="center">

# Claude Inspector

**See what Claude Code actually sends to the API.**

MITM proxy that intercepts Claude Code CLI traffic in real-time<br>
and visualizes all 5 prompt augmentation mechanisms.

[Install](#install) · [What You'll Learn](#what-youll-learn) · [Proxy Mode](#proxy-mode) · [How It Works](#how-it-works)

**English** | [한국어](README.ko.md)

</div>

---

<p align="center">
  <img src="public/screenshots/proxy-request-ko.png" width="100%" alt="Proxy — Request view showing CLAUDE.md Global/Local section chips with inline text highlight" />
</p>

<p align="center">
  <img src="public/screenshots/proxy-analysis-en.png" width="100%" alt="Proxy — Analysis view auto-detecting all 5 mechanisms with section content" />
</p>

## What You'll Learn

All discovered from **real captured traffic** with Claude Inspector.

### 1. CLAUDE.md is re-injected every single turn

You type `hello`. Claude Code actually sends 3 content blocks:

| Block | What's inside |
|-------|--------------|
| `content[0]` | Skills list (`<system-reminder>`) |
| `content[1]` | All your CLAUDE.md, rules, memory — **~10KB** |
| `content[2]` | What you actually typed |

**Injection order:** Global CLAUDE.md → Global rules → Project CLAUDE.md → Memory → `currentDate`

**Why this matters:** These ~10KB are included in **every request**. Not stacked — but re-sent each time. A verbose CLAUDE.md silently inflates every API call.

| Source | Size |
|--------|------|
| Global CLAUDE.md | ~1,000 chars |
| Global rules (4 files) | ~6,000 chars |
| Project CLAUDE.md | ~800 chars |
| Auto-memory | ~1,800 chars |
| **Total per request** | **~10,000 chars** |

### 2. MCP tools are lazy-loaded

- **Built-in tools** (27) — full JSON schemas sent every request
- **MCP tools** — deferred as names only, loaded on demand via `ToolSearch`

**The flow:** Model reads MCP server description → calls `ToolSearch` → gets full schema → calls the actual tool. Unused MCP tools never consume tokens.

### 3. Skill ≠ Command — three injection paths

Typing `/something` triggers one of three completely different mechanisms:

| | Local Command | User-Invoked Skill | Assistant-Invoked Skill |
|---|---|---|---|
| **Example** | `/mcp`, `/clear` | `/commit`, `/dev-bounce` | `Skill("finish")` |
| **Who triggers** | User | User | Model decides |
| **Injection** | `<local-command-stdout>` | `<command-name>` tags + full prompt | `tool_use` → `tool_result` |
| **Reaches model?** | Result only | Full prompt | Full prompt |

- **Local command** — CLI handles it locally, model sees only the outcome
- **User-invoked skill** — full skill prompt dumped into your message
- **Assistant-invoked skill** — model calls `Skill` tool, receives prompt as `tool_result`

### 4. Context compaction summarizes your conversation

When nearing the context limit, Claude Code **compresses the entire conversation** into a structured summary in `messages[0]`:

- **Preserved:** original requests, file paths with line numbers, error history, user messages verbatim, pending tasks (9 sections total)
- **Lost:** individual tool results, thinking blocks, granular back-and-forth

A 153-message conversation (~40KB) compresses to ~10KB. But this summary is re-sent every subsequent request.

### 5. Skills and plans persist forever in a session

Once invoked, skill prompts and plan files **stay in every request** until the session ends.

| Persistent context | Size in this capture |
|--------------------|---------------------|
| 2 invoked skills (`dev-bounce` + `finish`) | ~13KB |
| Active plan file | ~5KB |
| CLAUDE.md (section 1) | ~10KB |
| Compacted context (section 4) | ~10KB |
| **Total hidden overhead** | **~38KB per request** |

- **Skills compound** — each `/skill` stays forever. Five 3KB skills = 15KB added to every request.
- **Plans linger** — unfinished plans keep consuming tokens until session end.

## Install

### Homebrew (Recommended)

```bash
brew tap kangraemin/tap
brew install --cask claude-inspector
```

### Direct Download

[⬇ Download v1.1.1 (.dmg)](https://github.com/kangraemin/claude-inspector/releases/latest)

| Mac (Apple Silicon) | Mac (Intel) |
|---|---|
| `Claude-Inspector-1.1.1-arm64.dmg` | `Claude-Inspector-1.1.1-x64.dmg` |

Download, open the `.dmg`, drag the app to Applications, and launch.

## For Contributors

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
| **Request** | Raw request JSON with collapsible tree; CLAUDE.md chips broken down by file (Global CLAUDE.md, Global Rules, Local CLAUDE.md, Memory) — click any chip to highlight that section inline |
| **Response** | Full response including SSE stream auto-reassembly |
| **Analysis** | Auto-detects which of the 5 mechanisms are present, shows each injected section's content with syntax highlighting — click a chip to jump to that section |

## How It Works

Claude Code enhances every API call with up to **5 prompt augmentation mechanisms** — but these are invisible during normal usage.

| Mechanism | Injection Point | Detail |
|-----------|----------------|--------|
| **CLAUDE.md** | `messages[].content` → `<system-reminder>` | Global + Local CLAUDE.md, rules files, and memory — each listed as a named section |
| **Output Style** | `system[]` additional block | Added when `/output` style is set |
| **Slash Command** | `messages[].content` → `<command-message>` | Command prompt injected before your message |
| **Skill** | `tool_result` after Skill `tool_use` | Skill content returned via tool result flow |
| **Sub-Agent** | Separate isolated API call via Task tool | Spawns a fully independent API call |

Claude Inspector sits between Claude Code and the Anthropic API, capturing the full request/response payload — so you can see exactly what gets injected and where.

> **Privacy**: All traffic stays on your machine. The proxy runs on `localhost` only. No data is sent anywhere except directly to `api.anthropic.com`.

## Tech Stack

- **Electron** — cross-platform desktop (macOS `hiddenInset` titlebar)
- **Vanilla JS** — zero frameworks, zero build steps
- **Node `http`/`https`** — lightweight MITM proxy with SSE stream reassembly
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
