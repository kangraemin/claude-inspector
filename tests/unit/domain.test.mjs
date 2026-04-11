/**
 * Unit tests for Domain layer — React 리팩토링 후 행동 동등성 검증
 * Run: node --test tests/unit/domain.test.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

// ─── ResponseParserService (인라인 구현 — TS 없이 테스트) ───────────────────

function parseClaudeMdSections(inner) {
  const re = /Contents of (.+?) \((.+?)\):\n\n([\s\S]*?)(?=\n\nContents of |\s*$)/g;
  const sections = [];
  let m;
  while ((m = re.exec(inner)) !== null) {
    const filePath = m[1], desc = m[2], content = m[3].trim();
    const fname = filePath.split('/').pop() ?? filePath;
    const isGlobal = /global|private global/i.test(desc);
    const isMemory = /memory/i.test(desc) || /\/memory\//.test(filePath);
    let label, cls;
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

function detectMechanisms(body) {
  const found = { claudeMd: null, outputStyle: null, slashCommand: null, skills: [], subAgents: [] };
  if (!body) return found;

  const system = body.system;
  if (Array.isArray(system) && system.length >= 2) {
    found.outputStyle = system.filter(s => s.type === 'text').map(s => s.text);
  }

  const messages = body.messages ?? [];
  for (const msg of messages) {
    const contents = Array.isArray(msg.content) ? msg.content : [{ type: 'text', text: msg.content }];
    for (const c of contents) {
      if (c.type === 'text' && typeof c.text === 'string') {
        const smMatch = c.text.match(/<system-reminder>([\s\S]*?)<\/system-reminder>/);
        if (smMatch) {
          const inner = smMatch[1];
          if (/Contents of .+ \(.+\):/m.test(inner)) {
            found.claudeMd = inner;
          }
          if (/The following skills (were invoked|are available)/i.test(inner) || /### Skill:/.test(inner)) {
            const skillMatches = [...inner.matchAll(/### Skill:\s*(\S+)/g)];
            for (const sm of skillMatches) {
              found.skills.push({ id: sm[1], input: null });
            }
          }
        }
        const cmdMatch = c.text.match(/<command-message>([\s\S]*?)<\/command-message>/);
        if (cmdMatch) {
          found.slashCommand = { tag: cmdMatch[0], full: cmdMatch[1] };
        }
      }
      if (c.type === 'tool_use' && c.name === 'Task') {
        found.subAgents.push({ id: c.id, name: c.name, input: c.input });
      }
    }
  }
  return found;
}

function sessionIdFromText(text) {
  let hash = 0;
  for (let i = 0; i < text.length; i++) {
    hash = ((hash << 5) - hash + text.charCodeAt(i)) | 0;
  }
  return 'session-' + Math.abs(hash).toString(36);
}

// ─── InMemoryCaptureRepository (인라인) ─────────────────────────────────────

class InMemoryCaptureRepository {
  constructor() { this.captures = []; }
  getAll() { return [...this.captures]; }
  add(capture) { this.captures.push(capture); }
  updateResponse(id, response) {
    const c = this.captures.find(x => x.id === id);
    if (c) c.response = response;
  }
  clear() { this.captures = []; }
}

// ─── Tests ──────────────────────────────────────────────────────────────────

test('parseClaudeMdSections — global CLAUDE.md 감지', () => {
  const inner = `Contents of /Users/foo/.claude/CLAUDE.md (user's private global instructions for all projects):

# Global Rules
- rule 1`;
  const sections = parseClaudeMdSections(inner);
  assert.equal(sections.length, 1);
  assert.equal(sections[0].cls, 'green');
  assert.match(sections[0].label, /Global CLAUDE\.md/);
  assert.equal(sections[0].scope, 'global');
});

test('parseClaudeMdSections — local CLAUDE.md 감지', () => {
  const inner = `Contents of /project/CLAUDE.md (project instructions, checked into the codebase):

# Project Rules`;
  const sections = parseClaudeMdSections(inner);
  assert.equal(sections.length, 1);
  assert.equal(sections[0].cls, 'cyan');
  assert.match(sections[0].label, /Local CLAUDE\.md/);
  assert.equal(sections[0].scope, 'local');
});

test('parseClaudeMdSections — memory 파일 감지', () => {
  const inner = `Contents of /Users/foo/.claude/memory/notes.md (memory file):

some notes`;
  const sections = parseClaudeMdSections(inner);
  assert.equal(sections.length, 1);
  assert.match(sections[0].label, /Memory/);
  assert.equal(sections[0].cls, 'green');
});

test('parseClaudeMdSections — 규칙 파일 감지', () => {
  const inner = `Contents of /project/.claude/rules/git-rules.md (project rule):

# Git Rules`;
  const sections = parseClaudeMdSections(inner);
  assert.equal(sections.length, 1);
  assert.match(sections[0].label, /Local Rule/);
});

test('parseClaudeMdSections — 다수 섹션 파싱', () => {
  const inner = `Contents of /foo/CLAUDE.md (project instructions, checked into the codebase):

section1

Contents of /bar/.claude/CLAUDE.md (user's private global instructions for all projects):

section2`;
  const sections = parseClaudeMdSections(inner);
  assert.equal(sections.length, 2);
});

test('detectMechanisms — claudeMd 감지', () => {
  const body = {
    messages: [{
      role: 'user',
      content: [{ type: 'text', text: '<system-reminder>Contents of /foo/CLAUDE.md (project instructions):\n\n# Rules</system-reminder>' }],
    }],
  };
  const result = detectMechanisms(body);
  assert.ok(result.claudeMd !== null);
  assert.match(result.claudeMd, /Contents of/);
});

test('detectMechanisms — slashCommand 감지', () => {
  const body = {
    messages: [{
      role: 'user',
      content: [{ type: 'text', text: '<command-message>/commit message here</command-message>' }],
    }],
  };
  const result = detectMechanisms(body);
  assert.ok(result.slashCommand !== null);
  assert.match(result.slashCommand.full, /\/commit/);
});

test('detectMechanisms — outputStyle 감지', () => {
  const body = {
    system: [
      { type: 'text', text: 'You are Claude.' },
      { type: 'text', text: 'Output style instructions.' },
    ],
  };
  const result = detectMechanisms(body);
  assert.ok(result.outputStyle !== null);
  assert.equal(result.outputStyle.length, 2);
});

test('detectMechanisms — subAgent Task 감지', () => {
  const body = {
    messages: [{
      role: 'assistant',
      content: [{ type: 'tool_use', id: 'tu_1', name: 'Task', input: { description: 'do something' } }],
    }],
  };
  const result = detectMechanisms(body);
  assert.equal(result.subAgents.length, 1);
  assert.equal(result.subAgents[0].name, 'Task');
});

test('detectMechanisms — 메커니즘 없음', () => {
  const body = {
    messages: [{ role: 'user', content: [{ type: 'text', text: 'Hello' }] }],
  };
  const result = detectMechanisms(body);
  assert.equal(result.claudeMd, null);
  assert.equal(result.slashCommand, null);
  assert.equal(result.skills.length, 0);
  assert.equal(result.subAgents.length, 0);
});

test('detectMechanisms — null body 처리', () => {
  const result = detectMechanisms(null);
  assert.equal(result.claudeMd, null);
  assert.equal(result.outputStyle, null);
});

test('SessionId — 동일 텍스트 → 동일 해시', () => {
  const h1 = sessionIdFromText('test-text-123');
  const h2 = sessionIdFromText('test-text-123');
  assert.equal(h1, h2);
});

test('SessionId — 다른 텍스트 → 다른 해시', () => {
  const h1 = sessionIdFromText('text-a');
  const h2 = sessionIdFromText('text-b');
  assert.notEqual(h1, h2);
});

test('SessionId — session- 접두어 포함', () => {
  const h = sessionIdFromText('any-text');
  assert.match(h, /^session-/);
});

test('InMemoryCaptureRepository — add + getAll 순서 보존', () => {
  const repo = new InMemoryCaptureRepository();
  repo.add({ id: 1, body: null });
  repo.add({ id: 2, body: null });
  repo.add({ id: 3, body: null });
  const all = repo.getAll();
  assert.equal(all.length, 3);
  assert.equal(all[0].id, 1);
  assert.equal(all[2].id, 3);
});

test('InMemoryCaptureRepository — getAll은 복사본 반환', () => {
  const repo = new InMemoryCaptureRepository();
  repo.add({ id: 1 });
  const a = repo.getAll();
  a.push({ id: 999 });
  assert.equal(repo.getAll().length, 1);
});

test('InMemoryCaptureRepository — updateResponse 동작', () => {
  const repo = new InMemoryCaptureRepository();
  repo.add({ id: 1, body: null, response: undefined });
  repo.updateResponse(1, { status: 200, body: { ok: true } });
  assert.deepEqual(repo.getAll()[0].response, { status: 200, body: { ok: true } });
});

test('InMemoryCaptureRepository — updateResponse 없는 id → 무시', () => {
  const repo = new InMemoryCaptureRepository();
  repo.add({ id: 1, body: null });
  assert.doesNotThrow(() => repo.updateResponse(999, { status: 200, body: null }));
  assert.equal(repo.getAll()[0].response, undefined);
});

test('InMemoryCaptureRepository — clear 동작', () => {
  const repo = new InMemoryCaptureRepository();
  repo.add({ id: 1 });
  repo.add({ id: 2 });
  repo.clear();
  assert.equal(repo.getAll().length, 0);
});
