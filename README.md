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
  <img src="public/screenshots/proxy-analysis-en-t.png" width="100%" alt="Proxy — Analysis view auto-detecting all 5 mechanisms with section content" />
</p>

## What You'll Learn

Everything below was discovered by inspecting **real captured traffic** with Claude Inspector.

### 1. Your CLAUDE.md is injected as multiple named sections every turn

Every user message is actually 3 content blocks. What you type is only `content[2]`. The first two are silently prepended by Claude Code:

```json
{
  "role": "user",
  "content": [
    // [0] Skills list — injected by Claude Code
    { "type": "text", "text": "<system-reminder>\nThe following skills are available...\n</system-reminder>" },

    // [1] All your CLAUDE.md files, rules, memory, date — 8,528 characters in this capture
    { "type": "text", "text": "<system-reminder>\n
        Contents of /Users/you/.claude/CLAUDE.md (user's private global instructions):\n...
        Contents of /Users/you/.claude/rules/git-rules.md (user's private global instructions):\n...
        Contents of /Users/you/project/.claude/CLAUDE.md (project instructions):\n...
        Contents of /Users/you/project/.claude/memory/MEMORY.md (auto-memory):\n...
        currentDate: 2026-03-01
      \n</system-reminder>" },

    // [2] What you actually typed
    { "type": "text", "text": "hello" }
  ]
}
```

**The injection order is always:** Global CLAUDE.md → Global rules files → Local CLAUDE.md → Auto-memory → `currentDate`.

**Why this multiplies your costs:** Claude Code re-sends the **entire `messages[]` array** on every API call. If you have 30 conversation turns, those 8,500 characters of CLAUDE.md appear 30 times in the payload — once per turn, embedded in `messages[0]`. A 500-line CLAUDE.md costs tokens on every single request, forever. Keep it concise.

**How much does it actually cost?** Here's the breakdown from a real 153-message Opus session:

| Source | Size | Sent |
|--------|------|------|
| Global CLAUDE.md | ~1,000 chars | Every request |
| Global rules (4 files) | ~6,000 chars | Every request |
| Project CLAUDE.md | ~800 chars | Every request |
| Auto-memory (MEMORY.md) | ~1,800 chars | Every request |
| **Total** | **~10,000 chars** | **Every request, compounding** |

That's 10KB of instructions silently attached to every API call. In a long session, the cumulative cost of a verbose CLAUDE.md dwarfs the cost of your actual prompts.

### 2. MCP tools are lazy-loaded to save tokens

27 built-in tools (`Read`, `Bash`, `Edit`, `Glob`, `Grep`, `Agent`...) are sent with **full JSON schemas** in every request. But **MCP tools are not** — they start as just names in a list:

```json
{
  "name": "ToolSearch",
  "description": "...Available deferred tools (must be loaded before use):\nmcp__til-server__create_til\nmcp__til-server__update_til\n..."
}
```

**The two-step lazy-load flow:**

1. `system[]` block contains an "MCP Server Instructions" section describing what each server does (*"Use context7 to retrieve up-to-date documentation"*)
2. Model reads the description and decides it needs an MCP tool
3. Model calls `ToolSearch` with a query → the full schema is returned and added to `tools[]` for subsequent requests
4. Model calls the actual MCP tool

**Before/after in this capture:** 8 MCP tools are listed as deferred in `ToolSearch`. But `mcp__context7__resolve-library-id` and `mcp__context7__query-docs` had already been loaded earlier in the session — so `tools[]` shows 29 total (27 built-in + 2 loaded MCP). The 6 `til-server` tools are still deferred because they haven't been needed yet.

This design keeps every request lean: unused MCP schemas never consume tokens.

### 3. Skill ≠ Command — three different injection paths

When you type `/something` in Claude Code, what happens depends on *what* that something is. There are three completely different mechanisms, and they look nothing alike in the API payload:

**Local command** — handled entirely by the CLI client, never reaches the model:

```json
// You type: /mcp
{
  "role": "user",
  "content": [
    { "type": "text", "text": "<command-name>/mcp</command-name>\n<command-message>mcp</command-message>" },
    { "type": "text", "text": "<local-command-stdout>MCP dialog dismissed</local-command-stdout>" }
  ]
}
```

The CLI opens a local UI dialog, captures the result, and injects `<local-command-stdout>` into the message. The model sees only the outcome.

**User-invoked skill** — the full skill prompt is injected directly into the user message:

```json
// You type: /dev-bounce fix the scroll bug
{
  "role": "user",
  "content": [
    { "type": "text", "text": "<command-message>dev-bounce</command-message>\n<command-name>/dev-bounce</command-name>\n<command-args>fix the scroll bug</command-args>" },
    { "type": "text", "text": "Base directory for this skill: /Users/you/.claude/skills/dev-bounce\n\n# dev-bounce\n\nFull skill prompt text here..." }
  ]
}
```

The CLI resolves the skill, reads its prompt file, and dumps the entire text into the user message alongside XML tags.

**Assistant-invoked skill** — the model decides to call a skill via `tool_use`, and receives the prompt as a `tool_result`:

```json
// Assistant calls Skill tool
{ "type": "tool_use", "name": "Skill", "input": { "skill": "finish" } }

// System returns the skill prompt
{ "type": "tool_result", "content": "Launching skill: finish" },
{ "type": "text", "text": "# /finish\n\nFull skill prompt text here..." }
```

| | Local Command | User-Invoked Skill | Assistant-Invoked Skill |
|---|---|---|---|
| Example | `/mcp`, `/clear`, `/help` | `/dev-bounce`, `/commit` | `Skill("finish")`, `Skill("e2e")` |
| Who triggers | User types `/` | User types `/` | Model decides |
| Injection point | `<local-command-stdout>` in user msg | `<command-name>` tags + prompt in user msg | `tool_use` → `tool_result` |
| Reaches model? | Result only | Full prompt | Full prompt |

### 4. Context compaction — your conversation, summarized

When a session approaches the context window limit, Claude Code doesn't just truncate — it **compresses the entire conversation into a structured summary** and inserts it as a text block in `messages[0]`:

```json
{
  "type": "text",
  "text": "This session is being continued from a previous conversation that ran out of context.
    The summary below covers the earlier portion of the conversation.\n\n
    Summary:\n
    1. Primary Request and Intent:\n   - Badge scroll jump bug fix...\n
    2. Key Technical Concepts:\n   - Electron desktop app with vanilla HTML/CSS/JS...\n
    3. Files and Code Sections:\n   - public/index.html — line ~2639-2738...\n
    4. Errors and fixes:\n   - Badge scroll attempt 1 (commit b21672f): ...\n
    5. Problem Solving:\n   - JSON padding accumulation: Solved by...\n
    6. All user messages:\n   - \"아 진짜 개열받는다\"...\n
    7. Pending Tasks:\n   - Badge scroll jump fix (attempt 3)...\n
    8. Current Work:\n   - Working on the third attempt...\n
    9. Optional Next Step:\n   - Continue the dev-bounce workflow..."
}
```

**What's preserved:** The summary captures 9 structured sections — your original requests, technical context, exact file paths with line numbers, error history, user messages verbatim, and pending work. It's surprisingly thorough.

**What's lost:** Individual tool call results, intermediate thinking blocks, and the granular back-and-forth of the conversation. The model continues from the summary as if it remembers everything, but it's working from a compressed reconstruction — not the original context.

**The cost trade-off:** A 153-message conversation (~40KB in `messages[0]` alone) gets compressed into ~10KB. But this summary is now sent with every subsequent request, adding to the compounding cost described in section 1.

### 5. Plans and invoked skills persist in every request

Once you use a skill or enter plan mode, those prompts don't disappear after use — they're **re-injected into every subsequent request** for the rest of the session:

```json
// messages[0].content — injected every turn
[
  // Previously invoked skills — 12,951 chars in this capture
  { "type": "text", "text": "<system-reminder>\nThe following skills were invoked in this session.
      Continue to follow these guidelines:\n\n
      ### Skill: dev-bounce\n  [full 8KB skill prompt...]\n\n
      ### Skill: finish\n    [full 4KB skill prompt...]\n
    </system-reminder>" },

  // Active plan file — 4,708 chars
  { "type": "text", "text": "<system-reminder>\nA plan file exists from plan mode at: /.../plan.md\n\n
      Plan contents:\n# Badge scroll fix\n## Context\n...[full plan]...\n
    </system-reminder>" }
]
```

**The hidden cost of skills:** In this captured session, two invoked skills (`dev-bounce` + `finish`) added **12,951 characters** to every request. The active plan added another **4,708 characters**. Combined: **~18KB of persistent context** silently riding along on every API call — on top of the 10KB of CLAUDE.md (section 1).

**Why this matters:**
- **Skills compound.** Each `/skill` you invoke in a session stays forever. Five skills with 3KB prompts each = 15KB added to every request.
- **Plans linger.** A plan created in plan mode persists until the session ends. If you don't complete a plan, it keeps consuming tokens.
- **The total is staggering.** In this Opus capture: 10KB (CLAUDE.md) + 13KB (skills) + 5KB (plan) + 10KB (compacted context) = **~38KB of hidden overhead** before you even type a word.

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
