import type { AiFlowResult } from '../entities/AiFlowResult';
import type { AiFlowStep } from '../entities/AiFlowStep';

export interface ClaudeMdSection {
  label: string;
  path: string;
  content: string;
  cls: string;
  scope: 'global' | 'local';
}

export interface MechanismDetection {
  claudeMd: string | null;
  outputStyle: string[] | null;
  slashCommand: { tag: string; full: string } | null;
  skills: Array<{ id: string; input: unknown }>;
  subAgents: Array<{ id: string; name: string; input: unknown }>;
}

/** ResponseParserService — AI 응답 및 프록시 데이터 파싱 (기존 index.html 로직 이관) */
export class ResponseParserService {
  /** CLAUDE.md system-reminder 텍스트를 섹션 배열로 파싱 */
  parseClaudeMdSections(inner: string): ClaudeMdSection[] {
    const re = /Contents of (.+?) \((.+?)\):\n\n([\s\S]*?)(?=\n\nContents of |\s*$)/g;
    const sections: ClaudeMdSection[] = [];
    let m: RegExpExecArray | null;
    while ((m = re.exec(inner)) !== null) {
      const filePath = m[1], desc = m[2], content = m[3].trim();
      const fname = filePath.split('/').pop() ?? filePath;
      const isGlobal = /global|private global/i.test(desc);
      const isMemory = /memory/i.test(desc) || /\/memory\//.test(filePath);
      let label: string, cls: string;
      if (isMemory) {
        label = '🧠 Memory: ' + fname; cls = 'green';
      } else if (/\/rules\//.test(filePath)) {
        label = (isGlobal ? '📜 Global Rule: ' : '📜 Local Rule: ') + fname;
        cls = isGlobal ? 'green' : 'cyan';
      } else if (/CLAUDE\.md$/i.test(filePath)) {
        label = isGlobal ? '📋 Global CLAUDE.md' : '📋 Local CLAUDE.md';
        cls = isGlobal ? 'green' : 'cyan';
      } else {
        label = '📋 ' + fname; cls = 'green';
      }
      sections.push({ label, path: filePath, content, cls, scope: isGlobal ? 'global' : 'local' });
    }
    return sections;
  }

  /** API 요청 body에서 Claude Code 5가지 메커니즘 탐지 */
  detectMechanisms(body: Record<string, unknown> | null): MechanismDetection {
    const found: MechanismDetection = {
      claudeMd: null, outputStyle: null, slashCommand: null, skills: [], subAgents: [],
    };
    if (!body) return found;

    const system = body.system;
    if (Array.isArray(system) && system.length >= 2) {
      found.outputStyle = (system as Array<{ type: string; text: string }>)
        .filter(s => s.type === 'text').map(s => s.text);
    }

    const msgs = (body.messages as Array<{ role: string; content: unknown }>) || [];
    for (const msg of msgs) {
      const contents = Array.isArray(msg.content) ? msg.content
        : (typeof msg.content === 'string' ? [{ type: 'text', text: msg.content }] : []);
      for (const c of contents as Array<{ type: string; text?: string; id?: string; name?: string; input?: unknown }>) {
        if (c.type === 'text' && typeof c.text === 'string') {
          const srMatch = c.text.match(/<system-reminder>([\s\S]*?)<\/system-reminder>/);
          if (srMatch && !found.claudeMd) found.claudeMd = srMatch[1].trim();
          const cmdMatch = c.text.match(/<command-message>([\s\S]*?)<\/command-message>/);
          if (cmdMatch) found.slashCommand = { tag: cmdMatch[1].trim(), full: c.text };
        }
        if (c.type === 'tool_use' && c.name === 'Skill') {
          found.skills.push({ id: c.id ?? '', input: c.input });
        }
        if (c.type === 'tool_use' && (c.name === 'Task' || c.name === 'Agent')) {
          found.subAgents.push({ id: c.id ?? '', name: c.name, input: c.input });
        }
      }
    }
    return found;
  }

  /** AI Flow claude -p 응답 텍스트를 AiFlowResult로 파싱 */
  parseAiFlowResponse(text: string): AiFlowResult {
    const steps: AiFlowStep[] = [];
    const stepRegex = /STEP\s+(\d+)\s*:\s*(.+?)(?:\n|\r)/g;
    let match: RegExpExecArray | null;
    const positions: Array<{ idx: number; num: number; title: string; end: number }> = [];
    while ((match = stepRegex.exec(text)) !== null) {
      positions.push({ idx: match.index, num: parseInt(match[1]), title: match[2].trim(), end: match.index + match[0].length });
    }
    const mermaidSectionStart = text.search(/\n\s*-*\s*\nMERMAID:/i);
    const textEnd = mermaidSectionStart > 0 ? mermaidSectionStart : text.length;

    for (let i = 0; i < positions.length; i++) {
      const start = positions[i].end;
      const end = i + 1 < positions.length ? positions[i + 1].idx : textEnd;
      const body = text.slice(start, end).trim();
      const refs: number[] = [];
      for (const rm of body.matchAll(/Request\s*#(\d+)/gi)) refs.push(parseInt(rm[1]));
      const hlMatch = body.match(/HIGHLIGHT:\s*(.+)/i);
      const highlight = hlMatch ? (hlMatch[1].trim() === 'none' ? null : hlMatch[1].trim()) : null;
      steps.push({ num: positions[i].num, title: positions[i].title, body, refs: [...new Set(refs)], highlight });
    }

    let summary = '';
    if (positions.length > 0) {
      const lastBody = text.slice(positions[positions.length - 1].end, textEnd).trim();
      const lines = lastBody.split('\n').map(l => l.trim()).filter(Boolean);
      if (lines.length > 0 && !lines[lines.length - 1].match(/^\[Request/)) {
        summary = lines[lines.length - 1];
      }
    }

    const mermaidMatch = text.match(/MERMAID:\s*\n([\s\S]*?)(?:\n---|\s*$)/i);
    let mermaid: string | null = null;
    if (mermaidMatch) {
      mermaid = mermaidMatch[1].trim().replace(/^```[\w]*\s*\n?/gm, '').replace(/```\s*$/gm, '').trim();
    }

    return { steps, summary, mermaid, raw: text };
  }
}
