import type { ProxyCapture } from '../entities/ProxyCapture';
import { PromptText } from '../value-objects/PromptText';
import { ResponseParserService } from './ResponseParserService';

/** PromptBuilderService — AI 분석 프롬프트 생성 (기존 index.html 로직 이관) */
export class PromptBuilderService {
  private readonly parser = new ResponseParserService();

  /** AI Flow 분석 프롬프트 생성 */
  buildAiFlowPrompt(captures: ProxyCapture[], locale: string): PromptText {
    const lang = locale === 'ko' ? 'Korean' : 'English';
    const summaries = this._buildCaptureSummaries(captures);
    const promptStr = `You are analyzing a Claude Code CLI session captured by a proxy inspector.
Below is a JSON array of ${summaries.length} API request/response pairs, ordered oldest-first.
Each has a "request_num" (e.g., Request #1 = oldest, Request #${summaries.length} = newest).
The "session" field indicates: "main" = main conversation, "sub-agent(from Request #N)" = spawned by an Agent/Task tool call in Request #N.

Analyze the session flow and produce a structured summary in ${lang}.

Focus on:
- MCP tool discovery → schema loading → actual tool calls
- Skill search → Skill loading → execution chains
- ToolSearch → ToolUse chains
- Sub-agent spawning and what they did
- Slash command → Skill execution flows
- Multi-turn conversation progression

When you detect these patterns, explain the MECHANISM:
- **MCP dynamic loading**: Claude Code has deferred MCP tools. When Claude needs one, it calls ToolSearch to fetch the schema, then the tool becomes callable. Explain this loading chain when you see ToolSearch → mcp__* patterns.
- **Skill loading**: When a slash command is used, Claude Code injects it via <command-message>. Claude then calls the Skill tool to load and execute the skill prompt. Explain this when you see command-message → Skill tool_use patterns.
- **ToolSearch → ToolUse**: Deferred tools aren't loaded until needed. ToolSearch fetches their schemas on demand. Explain when you see ToolSearch followed by a tool_use for the searched tool.

Output format (strictly follow):
---
STEP 1: [short title]
[Request #N, Request #M]
HIGHLIGHT: <most_relevant_tool_use_name or "none">
[2-3 sentence description. When MCP/Skill mechanisms are involved, explain HOW the loading works.]

STEP 2: [short title]
[Request #N]
HIGHLIGHT: <tool_use_name or "none">
[2-3 sentence description]
---

Rules:
- Group related requests into the same step
- Always reference specific Request #N numbers in brackets
- HIGHLIGHT must be a single tool_use name (e.g., "ToolSearch", "mcp__context7__query-docs", "Skill") or "none"
- When MCP or Skill mechanisms are involved, include a brief explanation of HOW the loading works
- For each step, explain the full causal chain: what Claude called → what the response returned → how Claude interpreted that response → what Claude decided to do next
- Use "response_tools" field to identify what tools came back in each response
- Make Claude's decision explicit: "Claude received X from the response, which meant Y, so it called Z next"
- If sub-agent requests exist, clearly indicate they are sub-agent calls
- Number steps sequentially (STEP 1, STEP 2, ...)
- End with a one-line overall session summary after the last step
- "tools" and "mechanisms" fields show only NEW entries vs the previous main request (delta). Absence means same as before.

After the summary, output a MERMAID flowchart showing the INTERNAL MECHANISM flow (not just request connections).
Show how Claude Code's prompt augmentation pipeline works across requests:
---
MERMAID:
graph TD
    A["User asks question"] --> B["Claude needs MCP tool"]
    B --> C["ToolSearch: fetch schema"]
    C --> D["Schema loaded: mcp__x__y"]
    D --> E["tool_use: mcp__x__y"]
    E --> F["tool_result returned"]
    F --> G["Claude generates answer"]
---

Rules for MERMAID:
- Use graph TD (top-down)
- Every chain must follow this 3-step pattern: [Claude calls tool] --> (Response: what came back) --> {Claude decides: why next action} --> [Claude calls next tool]
- The decision node {} is mandatory: it explains WHY Claude took the next action based on what the response returned. Without this node, causality is missing.
- Example chain:
    A["resolve-library-id\\n(Req 4)"] --> B("Response: library ID returned")
    B --> C{"Claude: has ID, needs docs"}
    C --> D["query-docs\\n(Req 5)"]
- Include these patterns when detected:
  - ToolSearch → schema returned → Claude: now callable → tool_use (deferred tool loading)
  - command-message → Skill tool_use → skill prompt injected → Claude: executes skill (skill loading)
  - Agent/Task tool_use → sub-agent spawned → sub-agent result (sub-agent flow)
  - system-reminder injection (CLAUDE.md loading)
- Use descriptive node labels like "ToolSearch: fetch mcp schema" not "Req 1"
- Add Request numbers as annotations: e.g., A["ToolSearch: fetch schema\\n(Req 1)"]
- Do NOT use # character in labels
- Keep labels under 50 characters
- Use different node shapes: [] for Claude actions, () for responses/results, {} for Claude decisions

Data:
${JSON.stringify(summaries, null, 1)}`;
    return PromptText.create(promptStr);
  }

  /** Optimization 분석 프롬프트 생성 */
  buildOptimizationPrompt(captures: ProxyCapture[], locale: string): PromptText {
    const lang = locale === 'ko' ? 'Korean' : 'English';
    const data = this._buildOptimizationData(captures);
    const promptStr = `Analyze this Claude Code session and provide optimization advice in ${lang}.

Focus ONLY on things the user can control and fix:
- prompt_injections.content: read the actual file contents and identify redundant/verbose/rarely-triggered sections. Give specific line-level examples.
- Flag any injection over 2000 chars as potentially bloated.
- Check if rules are duplicated across multiple files.
- If everything looks lean already, say so briefly.

Do NOT mention cache efficiency. Be concise. Use bullet points. Give specific file names and sizes.

Data:
${JSON.stringify(data, null, 1)}`;
    return PromptText.create(promptStr);
  }

  private _buildOptimizationData(captures: ProxyCapture[]) {
    const selected = [...captures].reverse();
    let injections: Array<{ file: string; chars: number; content: string }> = [];
    const tokenStats: Array<{ input: number; output: number; cache_read: number }> = [];
    let foundInjections = false;

    for (const entry of selected) {
      if (!foundInjections) {
        const det = this.parser.detectMechanisms(entry.body);
        if (det.claudeMd) {
          foundInjections = true;
          const sections = this.parser.parseClaudeMdSections(det.claudeMd);
          injections = sections.map(s => ({ file: s.label, chars: s.content.length, content: s.content }));
        }
      }
      const usage = (entry.response?.body as Record<string, unknown> | undefined)?.usage as Record<string, number> | undefined;
      if (usage) {
        tokenStats.push({
          input: usage['input_tokens'] || 0,
          output: usage['output_tokens'] || 0,
          cache_read: usage['cache_read_input_tokens'] || 0,
        });
      }
    }

    return {
      request_count: selected.length,
      prompt_injections: injections,
      token_summary: {
        total_input: tokenStats.reduce((s, t) => s + t.input, 0),
        total_output: tokenStats.reduce((s, t) => s + t.output, 0),
        requests: tokenStats.length,
      },
    };
  }

  private _buildCaptureSummaries(captures: ProxyCapture[]) {
    const selected = [...captures].reverse(); // oldest-first
    let prevMain: { toolSet: Set<string>; mechSet: Set<string> } | null = null;
    let lastMainWithAgent: number | null = null;

    return selected.map((entry, idx) => {
      const reqNum = idx + 1;
      const body = entry.body;
      const msgs: Array<{ role: string; content: unknown }> = (body?.['messages'] as Array<{ role: string; content: unknown }>) || [];
      const summary: Record<string, unknown> = {
        request_num: reqNum,
        model: body?.['model'] || 'unknown',
        messages_count: msgs.length,
      };

      const toolUses: string[] = [];
      let hasAgentCall = false, hasTeamCreate = false;
      for (const m of msgs) {
        const contents = Array.isArray(m.content) ? m.content : [];
        for (const c of contents as Array<{ type: string; name?: string }>) {
          if (c.type === 'tool_use' && c.name) {
            toolUses.push(c.name);
            if (c.name === 'Agent' || c.name === 'Task') hasAgentCall = true;
            if (c.name === 'TeamCreate') hasTeamCreate = true;
          }
        }
      }

      let isSubAgent = false;
      if (msgs.length <= 3 && lastMainWithAgent !== null) {
        isSubAgent = true;
        summary['session'] = `sub-agent(from Request #${lastMainWithAgent})`;
      } else {
        summary['session'] = 'main';
        if (hasAgentCall || hasTeamCreate) lastMainWithAgent = reqNum;
      }

      const allTools = [...new Set(toolUses)];
      if (prevMain && !isSubAgent) {
        const newTools = allTools.filter(t => !prevMain!.toolSet.has(t));
        if (newTools.length) summary['tools'] = newTools;
      } else {
        if (allTools.length) summary['tools'] = allTools;
      }

      const det = this.parser.detectMechanisms(body);
      const mechs: string[] = [];
      if (det.claudeMd) mechs.push('CLAUDE.md');
      if (det.slashCommand) mechs.push('SlashCommand');
      if (det.skills.length) mechs.push('Skill');
      if (det.subAgents.length) mechs.push('SubAgent');

      if (prevMain && !isSubAgent) {
        const newMechs = mechs.filter(m => !prevMain!.mechSet.has(m));
        if (newMechs.length) summary['mechanisms'] = newMechs;
      } else {
        if (mechs.length) summary['mechanisms'] = mechs;
      }

      if (!prevMain && !isSubAgent && det.claudeMd) {
        const sections = this.parser.parseClaudeMdSections(det.claudeMd);
        if (sections.length) {
          summary['prompt_injections'] = sections.map(s => ({ label: s.label, chars: s.content.length, scope: s.scope }));
        }
      }

      const usage = (entry.response?.body as Record<string, unknown> | undefined)?.usage as Record<string, number> | undefined;
      if (usage) {
        summary['tokens'] = {
          input: usage['input_tokens'] || 0,
          output: usage['output_tokens'] || 0,
          cache_read: usage['cache_read_input_tokens'] || 0,
          cache_write: usage['cache_creation_input_tokens'] || 0,
        };
      }

      const respContent = (entry.response?.body as Record<string, unknown> | undefined)?.content;
      if (Array.isArray(respContent)) {
        const respTools = (respContent as Array<{ type: string; name?: string }>).filter(c => c.type === 'tool_use').map(c => c.name).filter(Boolean);
        if (respTools.length) summary['response_tools'] = [...new Set(respTools)];
      }

      if (!isSubAgent) {
        prevMain = {
          toolSet: new Set([...(prevMain?.toolSet || []), ...allTools]),
          mechSet: new Set([...(prevMain?.mechSet || []), ...mechs]),
        };
      }

      return summary;
    });
  }
}
