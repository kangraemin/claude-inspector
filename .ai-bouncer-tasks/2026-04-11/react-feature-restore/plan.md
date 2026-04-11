# Plan: React 누락 기능 전부 복구

## Context
React 리라이트 과정에서 vanilla `public/index.html`에 있던 기능들이 미이식됨.
사용자 불만: 포트 흰색, Request/Response/Analysis 기능 사라짐, AI Flow 스크롤 불가, UI 깨짐.

## 전략
Phase별로 구현 → 각 Phase 완료 후 해당 e2e TC 실행으로 검증.

---

## Phase 1: `src/styles/index.css` — CSS 8종 추가

파일 끝에 추가:

```css
/* 1-A. Input dark background (포트 흰색 버그) */
input[type=number], input[type=text], select {
  background: var(--bg); color: var(--text); border: 1px solid var(--border);
  border-radius: 4px; padding: 6px 9px; font-size: 12px; outline: none; width: 100%;
}
input[type=number]:focus, input[type=text]:focus { border-color: var(--blue); }
input:disabled { opacity: .5; cursor: not-allowed; }
input[type=number] { width: auto; }

/* 1-B. AI Flow sub-step orange / scroll fix */
.aiflow-step-num.sub { background: var(--orange); }
.aiflow-container { min-height: 0; }

/* 1-C. Mech chips */
.mech-chip { padding: 2px 8px; border-radius: 10px; font-size: 10px; cursor: pointer;
  border: 1px solid; font-family: 'SF Mono', monospace; font-weight: 600;
  transition: all .15s; white-space: nowrap; }
.mech-chip.active { box-shadow: 0 0 0 2px currentColor; }
.mech-chip.cm  { color: var(--green);  border-color: rgba(78,201,176,.4);  background: rgba(78,201,176,.08); }
.mech-chip.st  { color: var(--blue);   border-color: rgba(86,156,214,.4);  background: rgba(86,156,214,.08); }
.mech-chip.sc  { color: var(--yellow); border-color: rgba(220,220,170,.4); background: rgba(220,220,170,.06); }
.mech-chip.sk  { color: var(--purple); border-color: rgba(197,134,192,.4); background: rgba(197,134,192,.08); }
.mech-chip.sa  { color: var(--orange); border-color: rgba(206,145,120,.4); background: rgba(206,145,120,.08); }
.mech-chip.mc  { color: #4fc1ff;       border-color: rgba(79,193,255,.4);  background: rgba(79,193,255,.08); }
.mech-chips-row { display: flex; gap: 5px; padding: 6px 12px; flex-wrap: wrap;
  border-bottom: 1px solid var(--border); background: var(--surface); flex-shrink: 0; }

/* 1-D. Search bar */
.search-bar-row { display: flex; align-items: center; gap: 6px;
  padding: 5px 12px; border-bottom: 1px solid var(--border);
  background: var(--surface); flex-shrink: 0; }
.search-bar-input { flex: 1; background: var(--bg); border: 1px solid var(--border);
  border-radius: 4px; padding: 4px 8px; color: var(--text); font-size: 12px;
  outline: none; width: auto; }
.search-bar-input:focus { border-color: var(--blue); }
.search-hl { background: rgba(220,220,170,.35); border-radius: 2px; }
.mech-hl-text { background: rgba(78,201,176,.25); border-radius: 2px; }

/* 1-E. Token info badges */
.token-info-row { display: flex; flex-wrap: wrap; gap: 6px;
  padding: 6px 12px; border-bottom: 1px solid var(--border);
  background: var(--surface); flex-shrink: 0; }
.tt-badge { font-size: 10px; font-family: 'SF Mono', monospace;
  padding: 2px 7px; border-radius: 4px;
  background: var(--surface2); border: 1px solid var(--border); color: var(--dim); }
.tt-badge.green { border-color: rgba(78,201,176,.4); color: var(--green); }
.tt-badge.blue  { border-color: rgba(86,156,214,.4); color: var(--blue); }
.tt-badge.yellow{ border-color: rgba(220,220,170,.35); color: var(--yellow); }

/* 1-F. Header version / update badge */
.logo-ver { font-size: 10px; color: var(--dim); opacity: .5; }
.update-badge { font-size: 10px; padding: 2px 8px; border-radius: 10px; cursor: pointer;
  background: rgba(78,201,176,.12); border: 1px solid rgba(78,201,176,.4);
  color: var(--green); font-weight: 600; display: none; }

/* 1-G. Onboarding modal */
.onboard-overlay { position: fixed; inset: 0; background: rgba(0,0,0,.6);
  display: flex; align-items: center; justify-content: center; z-index: 9999; }
.onboard-card { background: var(--surface); border: 1px solid var(--border); border-radius: 12px;
  padding: 28px 32px; max-width: 420px; width: 90%;
  display: flex; flex-direction: column; gap: 14px; }
.onboard-title { font-size: 16px; font-weight: 700; }
.onboard-sub { font-size: 12px; color: var(--dim); }
.onboard-steps { padding-left: 18px; font-size: 12px; color: var(--text); line-height: 2; }
.onboard-cmd { display: block; margin-top: 4px; background: var(--bg);
  border: 1px solid var(--border); border-radius: 4px; padding: 5px 10px;
  font-family: 'SF Mono', monospace; font-size: 11px; user-select: all; }
.onboard-note { font-size: 11px; color: var(--dim); line-height: 1.6; }
.onboard-btn { background: var(--blue); color: #fff; border: none; border-radius: 6px;
  padding: 9px 0; font-size: 13px; font-weight: 600; cursor: pointer; width: 100%; }
```

검증 TC: TC-57, TC-58, TC-69, TC-70, TC-73

---

## Phase 2: `src/presentation/store/captureStore.ts` — 50개 제한

### Before
```ts
addCapture: (capture) =>
  set((s) => ({ captures: [...s.captures, capture] })),
```

### After
```ts
addCapture: (capture) =>
  set((s) => {
    const next = [...s.captures, capture];
    return { captures: next.length > 50 ? next.slice(next.length - 50) : next };
  }),
```

---

## Phase 3: `src/presentation/store/uiStore.ts` — mechFilter 타입 수정

### Before
```ts
type MechFilter = string[];
mechFilter: MechFilter;
setMechFilter: (filter: MechFilter) => void;
// ...
mechFilter: [],
setMechFilter: (mechFilter) => set({ mechFilter }),
```

### After
```ts
mechFilter: string | null;
setMechFilter: (filter: string | null) => void;
// ...
mechFilter: null,
setMechFilter: (mechFilter) => set({ mechFilter }),
```

---

## Phase 4: `src/presentation/components/shared/JsonTree.tsx` — search/mechKey prop 추가

### Props 변경
```ts
// Before
interface JsonTreeProps {
  data: unknown;
  className?: string;
}

// After
interface JsonTreeProps {
  data: unknown;
  className?: string;
  search?: string;
  mechKey?: string | null;
}
```

### 모듈 레벨 helper 함수 추가 (export 없이)
```ts
function clearHighlight(container: HTMLElement, cls: string) {
  container.querySelectorAll(`span.${cls}`).forEach(el => {
    el.replaceWith(document.createTextNode(el.textContent ?? ''));
  });
  container.normalize();
}

function applySearchHighlight(container: HTMLElement, query: string) {
  const walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT);
  const nodes: Text[] = [];
  let node: Node | null;
  while ((node = walker.nextNode())) nodes.push(node as Text);
  const re = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi');
  for (const tn of nodes) {
    if (!re.test(tn.textContent ?? '')) { re.lastIndex = 0; continue; }
    re.lastIndex = 0;
    const frag = document.createDocumentFragment();
    let last = 0, m: RegExpExecArray | null;
    const text = tn.textContent ?? '';
    while ((m = re.exec(text)) !== null) {
      if (m.index > last) frag.appendChild(document.createTextNode(text.slice(last, m.index)));
      const span = document.createElement('span');
      span.className = 'search-hl';
      span.textContent = m[0];
      frag.appendChild(span);
      last = m.index + m[0].length;
    }
    if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
    tn.parentNode?.replaceChild(frag, tn);
  }
}

function applyMechHighlight(container: HTMLElement, mechKey: string) {
  const tagMap: Record<string, string> = {
    cm: 'system-reminder',
    sc: 'command-message',
  };
  const tag = tagMap[mechKey];
  if (!tag) return;
  applySearchHighlight(container, tag);
  container.querySelector('.search-hl')?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  // search-hl → mech-hl-text로 class 교체
  container.querySelectorAll('.search-hl').forEach(el => {
    (el as HTMLElement).className = 'mech-hl-text';
  });
}
```

### useEffect 추가 (JsonTree 컴포넌트 안)
```ts
// 기존 data effect는 유지
useEffect(() => { /* ... innerHTML 설정 ... */ }, [data]);

// search highlight — data 변경 후에도 재적용
useEffect(() => {
  if (!ref.current) return;
  clearHighlight(ref.current, 'search-hl');
  if (search?.trim()) applySearchHighlight(ref.current, search.trim());
}, [search, data]);

// mech highlight
useEffect(() => {
  if (!ref.current) return;
  clearHighlight(ref.current, 'mech-hl-text');
  if (mechKey) applyMechHighlight(ref.current, mechKey);
}, [mechKey, data]);
```

검증 TC: TC-62

---

## Phase 5: `src/presentation/components/ProxyDetail/ProxyDetail.tsx` — Copy 버튼 + MechChipsRow + SearchBar

### 추가할 내부 컴포넌트

```tsx
import { ResponseParserService } from '../../../domain/services/ResponseParserService';
const parser = new ResponseParserService();

function MechChipsRow({ capture }: { capture: ProxyCapture }) {
  const mechFilter = useUiStore(s => s.mechFilter);
  const setMechFilter = useUiStore(s => s.setMechFilter);
  const det = parser.detectMechanisms(capture.body);

  const chips: { key: string; cls: string; label: string }[] = [];
  if (det.claudeMd) chips.push({ key: 'cm', cls: 'cm', label: 'CLAUDE.md' });
  if (det.outputStyle) chips.push({ key: 'st', cls: 'st', label: 'Output Style' });
  if (det.slashCommand) chips.push({ key: 'sc', cls: 'sc', label: '/' + det.slashCommand.tag.slice(0, 10) });
  det.skills.forEach((_, i) => chips.push({ key: `sk_${i}`, cls: 'sk', label: 'Skill' }));
  det.subAgents.forEach((sa, i) => chips.push({ key: `sa_${i}`, cls: 'sa', label: sa.name }));

  if (chips.length === 0) return null;
  return (
    <div className="mech-chips-row">
      {chips.map(c => (
        <span
          key={c.key}
          className={`mech-chip ${c.cls}${mechFilter === c.key ? ' active' : ''}`}
          onClick={() => setMechFilter(mechFilter === c.key ? null : c.key)}
        >{c.label}</span>
      ))}
    </div>
  );
}

function SearchBar() {
  const search = useUiStore(s => s.search);
  const setSearch = useUiStore(s => s.setSearch);
  return (
    <div className="search-bar-row">
      <span style={{ fontSize: 10, color: 'var(--dim)' }}>🔍</span>
      <input
        className="search-bar-input"
        type="text"
        placeholder="Search..."
        value={search}
        onChange={e => setSearch(e.target.value)}
      />
      {search && (
        <button className="copy-small" style={{ padding: '2px 6px' }} onClick={() => setSearch('')}>✕</button>
      )}
    </div>
  );
}
```

### ProxyDetail 렌더링 변경

copyDetail 함수 추가:
```ts
const copyDetail = () => {
  if (!capture) return;
  const data = detailTab === 'response' ? capture.response?.body : capture.body;
  navigator.clipboard.writeText(JSON.stringify(data, null, 2));
};
```

Before:
```tsx
<div className="dtabs">
  {TABS.map(...)}
</div>
<div style={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
```

After:
```tsx
<div className="dtabs">
  {TABS.map(...)}
  <button className="copy-small" style={{ marginLeft: 'auto' }} onClick={copyDetail}>
    Copy
  </button>
</div>
{capture && detailTab !== 'aiflow' && <MechChipsRow capture={capture} />}
{capture && (detailTab === 'request' || detailTab === 'response') && <SearchBar />}
<div style={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
```

검증 TC: TC-59, TC-60, TC-63, TC-64, TC-65

---

## Phase 6: `src/presentation/components/ProxyDetail/RequestTab.tsx` — search/mechKey 전달

### Before
```tsx
{capture.body ? <JsonTree data={capture.body} /> : ...}
```

### After
```tsx
const search = useUiStore(s => s.search);
const mechFilter = useUiStore(s => s.mechFilter);
// ...
{capture.body ? (
  <JsonTree data={capture.body} search={search || undefined} mechKey={mechFilter} />
) : ...}
```

검증 TC: TC-62

---

## Phase 7: `src/presentation/components/ProxyDetail/ResponseTab.tsx` — 토큰 배지 추가

### TokenInfoRow 컴포넌트 추가
```tsx
function TokenInfoRow({ body }: { body: unknown }) {
  const usage = (body as any)?.usage;
  if (!usage) return null;
  const totalIn = usage.input_tokens ?? 0;
  const out = usage.output_tokens ?? 0;
  const cacheRead = usage.cache_read_input_tokens ?? 0;
  const cacheWrite = usage.cache_creation_input_tokens ?? 0;
  const cacheHit = totalIn > 0 ? Math.round(cacheRead / totalIn * 100) : 0;
  return (
    <div className="token-info-row">
      <span className="tt-badge blue">in {totalIn.toLocaleString()}</span>
      <span className="tt-badge">out {out.toLocaleString()}</span>
      {cacheRead > 0 && <span className="tt-badge green">cache_read {cacheRead.toLocaleString()} ({cacheHit}%)</span>}
      {cacheWrite > 0 && <span className="tt-badge yellow">cache_write {cacheWrite.toLocaleString()}</span>}
    </div>
  );
}
```

### ResponseTab 렌더링 변경

Before:
```tsx
<div style={{ padding: '8px 12px', ... }}>
  <span>Status: </span>...
</div>
{capture.response.body != null ? <JsonTree ... /> : ...}
```

After:
```tsx
<div style={{ padding: '8px 12px', ... }}>
  <span>Status: </span>...
</div>
<TokenInfoRow body={capture.response.body} />
{capture.response.body != null ? (
  <JsonTree data={capture.response.body} search={search || undefined} mechKey={mechFilter} />
) : ...}
```

(search, mechFilter도 useUiStore에서 가져와 JsonTree에 전달)

검증 TC: TC-66

---

## Phase 8: `src/presentation/components/ProxyDetail/AnalysisTab.tsx` — 섹션 개선

### CLAUDE.md — parseClaudeMdSections 호출

Before:
```tsx
<div className="analysis-block highlight-green" style={{ maxHeight: 300, overflow: 'auto' }}>
  {detection.claudeMd}
</div>
```

After:
```tsx
{(() => {
  const sections = parser.parseClaudeMdSections(detection.claudeMd!);
  return sections.length > 0 ? sections.map((s, i) => (
    <div key={i} style={{ marginBottom: 6 }}>
      <div style={{ fontSize: 10, color: 'var(--dim)', marginBottom: 3, fontWeight: 600 }}>{s.label}</div>
      <div className="analysis-block highlight-green" style={{ maxHeight: 200, overflow: 'auto' }}>{s.content}</div>
    </div>
  )) : (
    <div className="analysis-block highlight-green" style={{ maxHeight: 300, overflow: 'auto' }}>{detection.claudeMd}</div>
  );
})()}
```

`parser`는 모듈 레벨에서 이미 `const parser = new ResponseParserService()` 로 선언되어 있음.

### Skills — id + input JSON 표시

Before:
```tsx
<div className="analysis-block highlight-purple" style={{ fontSize: 11 }}>{sk.id}</div>
```

After:
```tsx
<div className="analysis-block highlight-purple" style={{ fontSize: 11 }}>
  <div style={{ color: 'var(--purple)', fontWeight: 700, marginBottom: 4 }}>id: {sk.id}</div>
  <pre style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-all', color: 'var(--dim)', fontSize: 10 }}>
    {JSON.stringify(sk.input, null, 2)}
  </pre>
</div>
```

### SubAgents — name + input JSON 표시

Before:
```tsx
<div className="analysis-block highlight-orange" style={{ fontSize: 11 }}>{sa.name}</div>
```

After:
```tsx
<div className="analysis-block highlight-orange" style={{ fontSize: 11 }}>
  <div style={{ color: 'var(--orange)', fontWeight: 700, marginBottom: 4 }}>{sa.name}</div>
  <pre style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-all', color: 'var(--dim)', fontSize: 10 }}>
    {JSON.stringify(sa.input, null, 2)}
  </pre>
</div>
```

검증 TC: TC-67, TC-68

---

## Phase 9: `src/presentation/components/Header/Header.tsx` — 버전 + 업데이트 배지

### After (전체)
```tsx
import { useState, useEffect } from 'react';
import { useUiStore } from '../../store/uiStore';
import { t } from '../../../i18n';

export function Header() {
  const locale = useUiStore((s) => s.locale);
  const setLocale = useUiStore((s) => s.setLocale);
  const [version, setVersion] = useState('');
  const [updateReady, setUpdateReady] = useState(false);

  useEffect(() => {
    fetch('build-info.json').then(r => r.json())
      .then(d => setVersion(`v${d.version} (${d.hash})`))
      .catch(() => {});
    (window as any).electronAPI?.onUpdateAvailable?.(() => setUpdateReady(true));
  }, []);

  return (
    <header className="header">
      <div className="logo">
        <div className="logo-icon">CI</div>
        <span className="logo-text">Claude Inspector</span>
        <span className="logo-sub">{t(locale, 'header.logoSub')}</span>
        {version && <span className="logo-ver">{version}</span>}
      </div>
      <div className="header-right">
        {updateReady && (
          <button className="update-badge" style={{ display: 'block' }}
            onClick={() => (window as any).electronAPI?.installUpdate?.()}>
            Update
          </button>
        )}
        <button className="copy-small" onClick={() => setLocale(locale === 'ko' ? 'en' : 'ko')}>
          {locale === 'ko' ? 'EN' : 'KO'}
        </button>
      </div>
    </header>
  );
}
```

검증 TC: TC-70

---

## Phase 10: `src/App.tsx` — Onboarding Modal + Cmd+F 단축키

### 추가할 OnboardingModal 컴포넌트 (App.tsx 상단에)
```tsx
function OnboardingModal({ onClose }: { onClose: () => void }) {
  return (
    <div className="onboard-overlay">
      <div className="onboard-card">
        <div className="onboard-title">Claude Inspector 시작하기</div>
        <div className="onboard-sub">Claude Code API 요청을 실시간으로 시각화합니다</div>
        <ol className="onboard-steps">
          <li>왼쪽 패널에서 <b>Start Proxy</b> 클릭</li>
          <li>새 터미널에서 명령 실행:
            <code className="onboard-cmd">ANTHROPIC_BASE_URL=http://localhost:9090 claude</code>
          </li>
          <li>Claude Code를 사용하면 요청이 자동으로 캡처됩니다</li>
        </ol>
        <div className="onboard-note">※ 프록시 없이 바로 사용해도 됩니다</div>
        <button className="onboard-btn" onClick={onClose}>시작하기</button>
      </div>
    </div>
  );
}
```

### AppInner 변경
```tsx
import { useState, useEffect } from 'react';
import { useUiStore } from './presentation/store/uiStore';

function AppInner() {
  useElectronEvents();
  const [onboarded, setOnboarded] = useState(() => !!localStorage.getItem('ci-onboarded'));

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'f') {
        e.preventDefault();
        document.querySelector<HTMLInputElement>('.search-bar-input')?.focus();
      }
      if (e.key === 'Escape') {
        useUiStore.getState().setSearch('');
        useUiStore.getState().setMechFilter(null);
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, []);

  return (
    <>
      {!onboarded && (
        <OnboardingModal onClose={() => {
          localStorage.setItem('ci-onboarded', '1');
          setOnboarded(true);
        }} />
      )}
      <Header />
      <div className="main">
        <div className="proxy-panel">
          <ProxyControl />
          <div className="proxy-stream">
            <ProxyList />
            <ProxyDetail />
          </div>
        </div>
      </div>
    </>
  );
}
```

검증 TC: TC-61, TC-69, TC-72

---

## E2E 테스트 추가 (`tests/e2e/app.spec.ts` 에 TC-57~73 append)

기존 TC-01~56 유지, 아래를 파일 끝에 추가:

```ts
// TC-57: 포트 입력 배경 어두운색
test('TC-57 포트 입력 배경색 어두운색', async () => {
  const input = page.locator('input[type=number]').first();
  const bg = await input.evaluate(el => getComputedStyle(el).backgroundColor);
  const r = parseInt(bg.match(/\d+/)?.[0] ?? '255');
  expect(r).toBeLessThan(100);
});

// TC-58: aiflow-container min-height 0
test('TC-58 aiflow-container min-height: 0px', async () => {
  const container = page.locator('.aiflow-container');
  const styles = await container.evaluate(el => ({
    overflowY: getComputedStyle(el).overflowY,
    minHeight: getComputedStyle(el).minHeight,
  }));
  expect(styles.overflowY).toBe('auto');
  expect(styles.minHeight).toBe('0px');
});

// TC-59: Request 탭 검색바 표시
test('TC-59 Request 탭 캡처 선택 시 search-bar-row 표시', async () => {
  const entries = page.locator('.prx-entry');
  if (await entries.count() > 0) {
    await entries.first().click();
    await page.locator('.dtab', { hasText: 'Request' }).click();
    await expect(page.locator('.search-bar-row')).toBeVisible();
  }
});

// TC-60: search-bar-input 존재
test('TC-60 .search-bar-input 표시됨', async () => {
  await expect(page.locator('.search-bar-input')).toBeVisible();
});

// TC-61: Meta+F 검색바 포커스
test('TC-61 Meta+F → 검색바 포커스', async () => {
  await page.keyboard.press('Meta+f');
  await expect(page.locator('.search-bar-input')).toBeFocused({ timeout: 1000 });
});

// TC-62: 검색어 → search-hl 생성
test('TC-62 검색어 입력 → .search-hl 하이라이트 생성', async () => {
  const entries = page.locator('.prx-entry');
  if (await entries.count() > 0) {
    await entries.first().click();
    await page.locator('.dtab', { hasText: 'Request' }).click();
    await page.locator('.search-bar-input').fill('model');
    await page.waitForTimeout(300);
    expect(await page.locator('.search-hl').count()).toBeGreaterThan(0);
  }
});

// TC-63: CLAUDE.md 캡처 → mech-chips-row 표시
test('TC-63 CLAUDE.md 포함 캡처 선택 시 mech-chips-row 표시', async () => {
  await app.evaluate(({ BrowserWindow }) => {
    BrowserWindow.getAllWindows()[0]?.webContents.send('proxy-request', {
      id: 9001, ts: new Date().toISOString(), method: 'POST', path: '/v1/messages',
      body: { model: 'claude-sonnet-4-6', messages: [{ role: 'user', content: [
        { type: 'text', text: '<system-reminder>Contents of /test/CLAUDE.md (project instructions):\n\ntest content</system-reminder>\nHello' }
      ]}]},
      sessionId: 'session-mech', isApiKey: false,
    });
  });
  await page.waitForTimeout(500);
  const entries = page.locator('.prx-entry');
  if (await entries.count() > 0) {
    await entries.last().click();
    await page.locator('.dtab', { hasText: 'Request' }).click();
    await page.waitForTimeout(200);
    await expect(page.locator('.mech-chips-row')).toBeVisible();
  }
});

// TC-64: mech-chip.cm 표시
test('TC-64 CLAUDE.md 캡처 — .mech-chip.cm 표시', async () => {
  const chip = page.locator('.mech-chip.cm');
  if (await chip.count() > 0) await expect(chip.first()).toBeVisible();
});

// TC-65: Copy 버튼 dtabs에 존재
test('TC-65 .dtabs 내 Copy 버튼 존재', async () => {
  await expect(page.locator('.dtabs .copy-small')).toBeVisible();
});

// TC-66: 토큰 배지 표시
test('TC-66 Response 탭 — usage 포함 응답 후 token-info-row 표시', async () => {
  await app.evaluate(({ BrowserWindow }) => {
    BrowserWindow.getAllWindows()[0]?.webContents.send('proxy-response', {
      id: 9001, status: 200,
      body: { usage: { input_tokens: 1000, output_tokens: 200, cache_read_input_tokens: 800, cache_creation_input_tokens: 200 }},
    });
  });
  await page.waitForTimeout(400);
  const entries = page.locator('.prx-entry');
  if (await entries.count() > 0) {
    await entries.last().click();
    await page.locator('.dtab', { hasText: 'Response' }).click();
    await page.waitForTimeout(200);
    await expect(page.locator('.token-info-row')).toBeVisible();
  }
});

// TC-67: Analysis — analysis-block 표시
test('TC-67 Analysis 탭 — CLAUDE.md 캡처 선택 시 analysis-block 표시', async () => {
  const entries = page.locator('.prx-entry');
  if (await entries.count() > 0) {
    await entries.last().click();
    await page.locator('.dtab', { hasText: 'Analysis' }).click();
    await page.waitForTimeout(200);
    await expect(page.locator('.analysis-block')).toBeVisible();
  }
});

// TC-68: Analysis — Skill input JSON 표시
test('TC-68 Analysis — Skill 포함 캡처 highlight-purple 표시', async () => {
  await app.evaluate(({ BrowserWindow }) => {
    BrowserWindow.getAllWindows()[0]?.webContents.send('proxy-request', {
      id: 9002, ts: new Date().toISOString(), method: 'POST', path: '/v1/messages',
      body: { model: 'claude-sonnet-4-6', messages: [{ role: 'user', content: [
        { type: 'tool_use', id: 'toolu_01', name: 'Skill', input: { skill: 'commit' } }
      ]}]},
      sessionId: 'session-skill', isApiKey: false,
    });
  });
  await page.waitForTimeout(400);
  const entries = page.locator('.prx-entry');
  if (await entries.count() > 0) {
    await entries.last().click();
    await page.locator('.dtab', { hasText: 'Analysis' }).click();
    await page.waitForTimeout(200);
    await expect(page.locator('.analysis-block.highlight-purple')).toBeVisible();
  }
});

// TC-69: Onboarding CSS 존재
test('TC-69 .onboard-overlay CSS 정의됨', async () => {
  const has = await page.evaluate(() =>
    [...document.styleSheets].some(ss => {
      try { return [...ss.cssRules].some(r => r.cssText.includes('onboard-overlay')); }
      catch { return false; }
    })
  );
  expect(has).toBe(true);
});

// TC-70: logo-ver CSS 존재
test('TC-70 .logo-ver CSS 정의됨', async () => {
  const has = await page.evaluate(() =>
    [...document.styleSheets].some(ss => {
      try { return [...ss.cssRules].some(r => r.cssText.includes('logo-ver')); }
      catch { return false; }
    })
  );
  expect(has).toBe(true);
});

// TC-71: 50개 제한
test('TC-71 캡처 50개 초과 → 최대 50개 유지', async () => {
  for (let i = 3000; i <= 3051; i++) {
    await app.evaluate(({ BrowserWindow }, id) => {
      BrowserWindow.getAllWindows()[0]?.webContents.send('proxy-request', {
        id, ts: new Date().toISOString(), method: 'POST', path: '/v1/messages',
        body: null, sessionId: 'session-bulk', isApiKey: false,
      });
    }, i);
  }
  await page.waitForTimeout(1200);
  expect(await page.locator('.prx-entry').count()).toBeLessThanOrEqual(50);
});

// TC-72: Escape → 검색 초기화
test('TC-72 Escape → 검색 입력값 초기화', async () => {
  const input = page.locator('.search-bar-input');
  if (await input.count() > 0) {
    await input.fill('test');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(200);
    expect(await input.inputValue()).toBe('');
  }
});

// TC-73: aiflow-step-num.sub CSS 존재
test('TC-73 .aiflow-step-num.sub CSS 정의됨', async () => {
  const has = await page.evaluate(() =>
    [...document.styleSheets].some(ss => {
      try { return [...ss.cssRules].some(r => r.cssText.includes('aiflow-step-num.sub')); }
      catch { return false; }
    })
  );
  expect(has).toBe(true);
});
```

---

## 최종 검증

```bash
npx vite build
npm run test:e2e
```

기대 결과: **TC-01 ~ TC-73 전부 통과**

## E2E 영향 분석
- 기존 TC-01~56: 변경 없음 (selector 동일)
- uiStore mechFilter 타입 변경 (`string[]` → `string | null`): 기존 사용처 없으므로 영향 없음
- 신규 TC-57~73: 신규 기능 검증
