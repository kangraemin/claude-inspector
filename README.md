<div align="center">

# Claude Inspector

**See what Claude Code actually sends to the API.**

MITM proxy that intercepts Claude Code CLI traffic in real-time<br>
and visualizes all 5 prompt augmentation mechanisms.

[Getting Started](#getting-started) · [What You'll Learn](#what-youll-learn) · [Proxy Mode](#-proxy-mode) · [How It Works](#how-it-works)

</div>

---

<p align="center">
  <img src="public/screenshots/proxy-request.png" width="100%" alt="Proxy — Request view with mechanism filter chips and search" />
</p>

<p align="center">
  <img src="public/screenshots/proxy-analysis.png" width="100%" alt="Proxy — Analysis view auto-detecting all 5 mechanisms" />
</p>

## What You'll Learn

Everything below was discovered by inspecting **real captured traffic** with Claude Inspector.

### 1. The anatomy of a single API request

Every time Claude Code talks to the API, it sends this structure:

```json
{
  "model": "claude-opus-4-6",
  "system": [ ... ],          // System prompt (3 blocks)
  "messages": [ ... ],        // Full conversation history
  "tools": [ ... ],           // 24+ tool definitions
  "metadata": { "user_id": "user_..._{account}_{session}" },
  "max_tokens": 32000,
  "thinking": { "type": "enabled", "budget_tokens": 31999 },
  "context_management": { "edits": [{ "type": "clear_thinking_20251015", "keep": "all" }] },
  "stream": true
}
```

### 2. `system[]` — three blocks, not one

The system prompt is an **array** of separate blocks:

```json
"system": [
  // [0] Billing — Claude Code version tracking
  { "text": "x-anthropic-billing-header: cc_version=2.1.63.a43; cc_entrypoint=cli; cch=9fa5e;" },

  // [1] Identity — one-liner
  { "text": "You are Claude Code, Anthropic's official CLI for Claude.",
    "cache_control": { "type": "ephemeral", "ttl": "1h" } },

  // [2] Everything else — behavior rules, tool instructions, environment, MCP server descriptions, git status
  { "text": "You are an interactive agent that helps users with software engineering tasks...(thousands of lines)",
    "cache_control": { "type": "ephemeral", "ttl": "1h" } }
]
```

The `cache_control` with `ttl: "1h"` means this massive prompt is **cached for 1 hour** — repeat requests hit the cache instead of re-processing the full text.

### 3. `messages[]` — your input is never just your input

When you type `"hello"`, the actual first `user` message sent to the API looks like this:

```json
{
  "role": "user",
  "content": [
    // [0] Injected: available skills list
    { "type": "text", "text": "<system-reminder> The following skills are available: commit, review, test, pr, push... </system-reminder>" },

    // [1] Injected: CLAUDE.md + rules + memory + currentDate
    { "type": "text", "text": "<system-reminder> Contents of CLAUDE.md... Contents of git-rules.md... Contents of review-rules.md... </system-reminder>" },

    // [2] What you actually typed
    { "type": "text", "text": "hello" }
  ]
}
```

Your CLAUDE.md, rules, memory — **all re-sent every single turn** inside `<system-reminder>` tags. Longer files = more tokens burned per turn.

### 4. `thinking` — the model's hidden reasoning

Every assistant response includes a `thinking` block that you never see in the CLI:

```json
{
  "role": "assistant",
  "content": [
    { "type": "thinking",
      "thinking": "The user is greeting me in Korean. I'll respond briefly and friendly.",
      "signature": "Eu0BCkYICxgCKkDLtz8rLXrByzrD..." },
    { "type": "text",
      "text": "안녕하세요! 무엇을 도와드릴까요?" }
  ]
}
```

- `thinking` — the model's actual chain-of-thought reasoning
- `signature` — cryptographic signature to prevent tampering with thinking content
- `budget_tokens: 31999` — almost the entire `max_tokens` (32000) is allocated to thinking

### 5. `tools[]` — 24 built-in tools, MCP tools are lazy-loaded

Built-in tools like `Read`, `Bash`, `Edit`, `Glob`, `Grep` are sent with **full JSON schemas** every request:

```
Agent, TaskOutput, Bash, Glob, Grep, ExitPlanMode, Read, Edit, Write,
NotebookEdit, WebFetch, WebSearch, TaskStop, AskUserQuestion, Skill,
EnterPlanMode, TaskCreate, TaskGet, TaskUpdate, TaskList, EnterWorktree,
TeamCreate, TeamDelete, SendMessage, ToolSearch, ListMcpResourcesTool,
ReadMcpResourceTool
```

But **MCP tools** (like `context7`, `til-server`) are NOT in the `tools[]` array. Instead, only their names appear inside the `ToolSearch` tool's description:

```json
{
  "name": "ToolSearch",
  "description": "...Available deferred tools (must be loaded before use):
    mcp__context7__resolve-library-id
    mcp__context7__query-docs
    mcp__til-server__create_til
    ..."
}
```

The model must call `ToolSearch` first to load the full schema, then call the actual MCP tool. This **lazy-loading** saves tokens — 8 MCP tools' schemas don't get sent in every request.

### 6. Hooks inject messages as if the user sent them

When a hook fires (e.g., a stop hook detecting uncommitted changes), it appears as a **user message** with a `<system-reminder>`:

```json
{
  "role": "user",
  "content": [
    { "text": "<system-reminder> Stop hook blocking error from command: \"$HOME/.claude/hooks/auto-commit.sh\": 커밋되지 않은 변경사항이 있습니다. </system-reminder>" },
    { "text": "Stop hook feedback: 커밋되지 않은 변경사항이 있습니다. /commit을 실행하세요." }
  ]
}
```

The hook message is injected **as a user message** — the model sees it as coming from you.

### 7. `context_management` — controlling thinking block retention

```json
"context_management": {
  "edits": [{ "type": "clear_thinking_20251015", "keep": "all" }]
}
```

This controls whether previous turns' `thinking` blocks are kept or cleared. `keep: "all"` preserves all thinking history. When context runs low, Claude Code can change this to clear old thinking blocks — that's how context compression works under the hood.

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

## How It Works

Claude Code enhances every API call with up to **5 prompt augmentation mechanisms** — but these are invisible during normal usage.

| Mechanism | Injection Point |
|-----------|----------------|
| **CLAUDE.md** | `messages[].content` → `<system-reminder>` |
| **Output Style** | `system[]` additional block |
| **Slash Command** | `messages[].content` → `<command-message>` |
| **Skill** | `tool_result` after Skill `tool_use` |
| **Sub-Agent** | Separate isolated API call via Task tool |

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
