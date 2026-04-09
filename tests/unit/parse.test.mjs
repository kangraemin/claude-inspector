/**
 * Unit tests for parsing functions in public/index.html
 * 함수를 index.html에서 직접 추출해 테스트 (리팩토링 없이)
 *
 * Run: npm run test:unit
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

// ─── 함수 복사 (index.html과 동기화 필요) ────────────────────────────────────

function parseClaudeMdSections(inner) {
  const re = /Contents of (.+?) \((.+?)\):\n\n([\s\S]*?)(?=\n\nContents of |\s*$)/g;
  const sections = [];
  let m;
  while ((m = re.exec(inner)) !== null) {
    const path = m[1], desc = m[2], content = m[3].trim();
    const fname = path.split('/').pop();
    const isGlobal = /global|private global/i.test(desc);
    const isMemory = /memory/i.test(desc) || /\/memory\//.test(path);
    let label, cls;
    if (isMemory) {
      label = '🧠 Memory: ' + fname; cls = 'green';
    } else if (/\/rules\//.test(path)) {
      label = (isGlobal ? '📜 Global Rule: ' : '📜 Local Rule: ') + fname;
      cls = isGlobal ? 'green' : 'cyan';
    } else if (/CLAUDE\.md$/i.test(path)) {
      label = isGlobal ? '📋 Global CLAUDE.md' : '📋 Local CLAUDE.md';
      cls = isGlobal ? 'green' : 'cyan';
    } else {
      label = '📋 ' + fname; cls = 'green';
    }
    sections.push({ label, path, content, cls, scope: isGlobal ? 'global' : 'local' });
  }
  return sections;
}

function detectMechanisms(body) {
  const found = { claudeMd: null, outputStyle: null, slashCommand: null, skills: [], subAgents: [] };
  if (!body) return found;

  if (Array.isArray(body.system) && body.system.length >= 2) {
    found.outputStyle = body.system.filter(s => s.type === 'text').map(s => s.text);
  }

  const msgs = body.messages || [];
  for (const msg of msgs) {
    const contents = Array.isArray(msg.content) ? msg.content
                   : (typeof msg.content === 'string' ? [{ type: 'text', text: msg.content }] : []);
    for (const c of contents) {
      if (c.type === 'text' && typeof c.text === 'string') {
        const srMatch = c.text.match(/<system-reminder>([\s\S]*?)<\/system-reminder>/);
        if (srMatch && !found.claudeMd) {
          found.claudeMd = srMatch[1].trim();
        }
        const cmdMatch = c.text.match(/<command-message>([\s\S]*?)<\/command-message>/);
        if (cmdMatch) {
          found.slashCommand = { tag: cmdMatch[1].trim(), full: c.text };
        }
      }
      if (c.type === 'tool_use' && c.name === 'Skill') {
        found.skills.push({ id: c.id, input: c.input });
      }
      if (c.type === 'tool_use' && (c.name === 'Task' || c.name === 'Agent')) {
        found.subAgents.push({ id: c.id, name: c.name, input: c.input });
      }
    }
  }
  return found;
}

// ─── parseClaudeMdSections ───────────────────────────────────────────────────

test('global CLAUDE.md 단일 섹션', () => {
  const input = `Contents of /Users/ram/.claude/CLAUDE.md (user's private global instructions for all projects):\n\n# Global Rules\ncontent here`;
  const sections = parseClaudeMdSections(input);
  assert.equal(sections.length, 1);
  assert.equal(sections[0].label, '📋 Global CLAUDE.md');
  assert.equal(sections[0].scope, 'global');
  assert.equal(sections[0].cls, 'green');
  assert.ok(sections[0].content.includes('# Global Rules'));
});

test('local CLAUDE.md 단일 섹션', () => {
  const input = `Contents of /project/CLAUDE.md (project instructions, checked into the codebase):\n\n# Project Rules\ncontent`;
  const sections = parseClaudeMdSections(input);
  assert.equal(sections.length, 1);
  assert.equal(sections[0].label, '📋 Local CLAUDE.md');
  assert.equal(sections[0].scope, 'local');
  assert.equal(sections[0].cls, 'cyan');
});

test('global + local 복수 섹션', () => {
  const input = [
    `Contents of /Users/ram/.claude/CLAUDE.md (user's private global instructions for all projects):\n\n# Global Rules\nglobal content`,
    `Contents of /project/CLAUDE.md (project instructions, checked into the codebase):\n\n# Local Rules\nlocal content`,
  ].join('\n\n');
  const sections = parseClaudeMdSections(input);
  assert.equal(sections.length, 2);
  assert.equal(sections[0].scope, 'global');
  assert.equal(sections[1].scope, 'local');
});

test('global rule 파일', () => {
  const input = `Contents of /Users/ram/.claude/rules/git-rules.md (user's private global instructions for all projects):\n\n# Git Rules\ncontent`;
  const sections = parseClaudeMdSections(input);
  assert.equal(sections.length, 1);
  assert.equal(sections[0].label, '📜 Global Rule: git-rules.md');
  assert.equal(sections[0].scope, 'global');
});

test('memory 파일', () => {
  const input = `Contents of /Users/ram/.claude/projects/foo/memory/MEMORY.md (user's auto-memory, persists across conversations):\n\n# Memory\ncontent`;
  const sections = parseClaudeMdSections(input);
  assert.equal(sections.length, 1);
  assert.equal(sections[0].label, '🧠 Memory: MEMORY.md');
});

test('실제 system-reminder 형식 — 4개 섹션 분리', () => {
  const input = [
    `Contents of /Users/ram/.claude/CLAUDE.md (user's private global instructions for all projects):\n\n# Global Rules\ncontent`,
    `Contents of /Users/ram/.claude/rules/git-rules.md (user's private global instructions for all projects):\n\n# Git Rules\ncontent`,
    `Contents of /project/CLAUDE.md (project instructions, checked into the codebase):\n\n# Claude Inspector\ncontent`,
    `Contents of /Users/ram/.claude/projects/foo/memory/MEMORY.md (user's auto-memory, persists across conversations):\n\n# Memory\ncontent`,
  ].join('\n\n');
  const sections = parseClaudeMdSections(input);
  assert.equal(sections.length, 4);
  assert.equal(sections[0].label, '📋 Global CLAUDE.md');
  assert.equal(sections[1].label, '📜 Global Rule: git-rules.md');
  assert.equal(sections[2].label, '📋 Local CLAUDE.md');
  assert.equal(sections[3].label, '🧠 Memory: MEMORY.md');
});

test('섹션 없으면 빈 배열', () => {
  const sections = parseClaudeMdSections('아무 내용 없음');
  assert.equal(sections.length, 0);
});

// ─── detectMechanisms ────────────────────────────────────────────────────────

test('system-reminder → claudeMd 감지', () => {
  const body = {
    messages: [{
      role: 'user',
      content: '<system-reminder>\nContents of /path/CLAUDE.md (desc):\n\ncontent\n</system-reminder>\nhello',
    }],
  };
  const det = detectMechanisms(body);
  assert.ok(det.claudeMd);
  assert.ok(det.claudeMd.includes('Contents of'));
});

test('system 배열 2개 이상 → outputStyle 감지', () => {
  const body = {
    system: [
      { type: 'text', text: 'base system' },
      { type: 'text', text: 'output style' },
    ],
    messages: [],
  };
  const det = detectMechanisms(body);
  assert.ok(det.outputStyle);
  assert.equal(det.outputStyle.length, 2);
});

test('command-message → slashCommand 감지', () => {
  const body = {
    messages: [{
      role: 'user',
      content: '<command-message>commit</command-message>\n/commit',
    }],
  };
  const det = detectMechanisms(body);
  assert.ok(det.slashCommand);
  assert.ok(det.slashCommand.tag.includes('commit'));
});

test('tool_use Skill → skills 감지', () => {
  const body = {
    messages: [{
      role: 'assistant',
      content: [{ type: 'tool_use', id: 'tu_1', name: 'Skill', input: { skill: 'e2e' } }],
    }],
  };
  const det = detectMechanisms(body);
  assert.equal(det.skills.length, 1);
  assert.equal(det.skills[0].input.skill, 'e2e');
});

test('tool_use Agent → subAgents 감지', () => {
  const body = {
    messages: [{
      role: 'assistant',
      content: [{ type: 'tool_use', id: 'tu_2', name: 'Agent', input: { description: 'test agent' } }],
    }],
  };
  const det = detectMechanisms(body);
  assert.equal(det.subAgents.length, 1);
  assert.equal(det.subAgents[0].name, 'Agent');
});

test('빈 body → 모두 null/empty', () => {
  const det = detectMechanisms({});
  assert.equal(det.claudeMd, null);
  assert.equal(det.outputStyle, null);
  assert.equal(det.slashCommand, null);
  assert.equal(det.skills.length, 0);
  assert.equal(det.subAgents.length, 0);
});

// ─── parseAiFlowResponse ────────────────────────────────────────────────────

function parseAiFlowResponse(text) {
  const steps = [];
  const stepRegex = /STEP\s+(\d+)\s*:\s*(.+?)(?:\n|\r)/g;
  let match;
  const positions = [];
  while ((match = stepRegex.exec(text)) !== null) {
    positions.push({ idx: match.index, num: parseInt(match[1]), title: match[2].trim(), end: match.index + match[0].length });
  }
  for (let i = 0; i < positions.length; i++) {
    const start = positions[i].end;
    const end = i + 1 < positions.length ? positions[i + 1].idx : text.length;
    const body = text.slice(start, end).trim();
    const refs = [];
    for (const rm of body.matchAll(/Request\s*#(\d+)/gi)) refs.push(parseInt(rm[1]));
    steps.push({ num: positions[i].num, title: positions[i].title, body, refs: [...new Set(refs)] });
  }
  let summary = '';
  if (positions.length > 0) {
    const lastBody = text.slice(positions[positions.length - 1].end).trim();
    const lines = lastBody.split('\n').map(l => l.trim()).filter(Boolean);
    if (lines.length > 0 && !lines[lines.length - 1].match(/^\[Request/)) summary = lines[lines.length - 1];
  }
  return { steps, summary, raw: text };
}

test('STEP 포맷 정상 파싱', () => {
  const text = 'STEP 1: MCP 도구 탐색\n[Request #1, Request #2]\n설명\n\nSTEP 2: 코드 수정\n[Request #3]\n수정 내용';
  const result = parseAiFlowResponse(text);
  assert.equal(result.steps.length, 2);
  assert.equal(result.steps[0].title, 'MCP 도구 탐색');
  assert.deepEqual(result.steps[0].refs, [1, 2]);
  assert.deepEqual(result.steps[1].refs, [3]);
});

test('빈 응답 → 빈 steps', () => {
  const result = parseAiFlowResponse('');
  assert.equal(result.steps.length, 0);
});

test('단일 STEP + summary', () => {
  const text = 'STEP 1: 초기화\n[Request #5]\n설명 내용\n전체 요약입니다.';
  const result = parseAiFlowResponse(text);
  assert.equal(result.steps.length, 1);
  assert.equal(result.summary, '전체 요약입니다.');
});
