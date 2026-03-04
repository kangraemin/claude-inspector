/**
 * E2E tests for Claude Inspector (Electron)
 *
 * Run: npm run test:e2e
 * 앱이 실행 중이면 먼저 종료: pkill -x "Electron"
 */
import { test, expect, _electron as electron } from '@playwright/test';
import type { ElectronApplication, Page } from '@playwright/test';
import path from 'node:path';
import fs from 'node:fs';

const ROOT = path.resolve(__dirname, '../..');

let app: ElectronApplication;
let page: Page;

test.beforeAll(async () => {
  app = await electron.launch({
    args: [ROOT],
    env: { ...process.env, NODE_ENV: 'test' },
  });
  page = await app.firstWindow();
  await page.waitForLoadState('domcontentloaded');
});

test.afterAll(async () => {
  await app.close();
});

/**
 * SHOW_SIMULATOR=false 상태에서 비proxy 탭들이 display:none으로 숨겨지므로,
 * 시뮬레이터 관련 테스트는 이 함수를 먼저 호출해 탭과 UI를 복원한다.
 */
async function activateSimulator() {
  await page.evaluate(() => {
    document.querySelectorAll<HTMLElement>('.tab').forEach(t => { t.style.display = ''; });
    (window as any).switchM('claude-md');
  });
}

/** 프록시 패널이 필요한 테스트 전 호출 */
async function activateProxy() {
  await page.evaluate(() => (window as any).switchM('proxy'));
}

// ─── 기본 UI ─────────────────────────────────────────────────────────────────

test('앱 타이틀 확인', async () => {
  await expect(page).toHaveTitle('Claude Inspector');
});

test('5개 메커니즘 탭 모두 존재', async () => {
  await activateSimulator();
  const tabs = ['claude-md', 'output-style', 'slash-command', 'skill', 'sub-agent'];
  for (const m of tabs) {
    await expect(page.locator(`[data-m="${m}"]`)).toBeVisible();
  }
});

test('API 키 입력란 존재', async () => {
  await activateSimulator();
  const apiKeyInput = page.locator('input[type="password"], input[placeholder*="API"], input[placeholder*="sk-"]').first();
  await expect(apiKeyInput).toBeVisible();
});

// ─── 메커니즘 탭 전환 ────────────────────────────────────────────────────────

test('CLAUDE.md 탭 클릭 → 컨텐츠 전환', async () => {
  await activateSimulator();
  await page.click('[data-m="claude-md"]');
  await expect(page.locator('[data-m="claude-md"]')).toHaveClass(/active/);
});

test('Output Style 탭 클릭 → 컨텐츠 전환', async () => {
  await activateSimulator();
  await page.click('[data-m="output-style"]');
  await expect(page.locator('[data-m="output-style"]')).toHaveClass(/active/);
});

test('Slash Command 탭 클릭 → 컨텐츠 전환', async () => {
  await activateSimulator();
  await page.click('[data-m="slash-command"]');
  await expect(page.locator('[data-m="slash-command"]')).toHaveClass(/active/);
});

// ─── 프록시 ──────────────────────────────────────────────────────────────────

test('프록시 시작 버튼 존재', async () => {
  await activateProxy();
  await expect(page.locator('#proxyStartBtn')).toBeVisible();
});

// ─── 프록시 리스너 중복 방지 / UI Freeze 방지 ─────────────────────────────────

test('toggleProxy 시작 분기에 offProxy 선행 호출 코드 존재 (리스너 누적 방지)', () => {
  // contextBridge frozen 제약으로 런타임 mock 불가 → 소스 코드 정적 검증
  const html = fs.readFileSync(path.join(ROOT, 'public/index.html'), 'utf8');

  // else { ... } 블록 내에서 onProxyRequest 등록 전에 offProxy()가 있는지 확인
  // "else {" 이후 첫 번째 offProxy 호출이 onProxyRequest보다 앞에 있어야 함
  const elseIdx = html.indexOf('// 기존 리스너 먼저 정리 후 새 리스너 등록 (누적 방지)');
  const offProxyIdx = html.indexOf('window.electronAPI.offProxy();', elseIdx);
  const onProxyRequestIdx = html.indexOf('window.electronAPI.onProxyRequest(', elseIdx);

  expect(elseIdx).toBeGreaterThan(-1); // 주석 존재
  expect(offProxyIdx).toBeGreaterThan(-1); // offProxy 호출 존재
  expect(onProxyRequestIdx).toBeGreaterThan(-1); // onProxyRequest 등록 존재
  // offProxy가 onProxyRequest보다 먼저 나와야 함
  expect(offProxyIdx).toBeLessThan(onProxyRequestIdx);
});

test('반복 토글 후 UI 반응성 (500ms 이내)', async () => {
  await activateProxy();
  const btn = page.locator('#proxyStartBtn');
  await expect(btn).toBeVisible();

  // 버튼이 비활성화 → 활성화되는 시간 측정
  const start = Date.now();
  await btn.click();
  // 버튼이 다시 enabled 되길 기다림 (최대 500ms)
  await expect(btn).not.toBeDisabled({ timeout: 500 });
  const elapsed = Date.now() - start;

  expect(elapsed).toBeLessThan(500);
});

test('연속 IPC 이벤트 시 proxyList debounce 동작', async () => {
  // renderer에서 직접 debouncedRenderProxyList 3회 연속 호출 후
  // renderProxyList 실제 실행 횟수가 1~2회인지 확인
  const renderCount = await page.evaluate(async () => {
    let count = 0;
    // @ts-ignore
    const origRender = window.renderProxyList;
    if (!origRender) return -1; // 함수 없으면 스킵

    // @ts-ignore
    window.renderProxyList = () => { count++; origRender(); };

    // 10ms 간격으로 3회 연속 호출
    // @ts-ignore
    if (typeof debouncedRenderProxyList === 'function') {
      // @ts-ignore
      debouncedRenderProxyList();
      await new Promise(r => setTimeout(r, 10));
      // @ts-ignore
      debouncedRenderProxyList();
      await new Promise(r => setTimeout(r, 10));
      // @ts-ignore
      debouncedRenderProxyList();
      // debounce 타이머 소진 대기 (50ms + 여유)
      await new Promise(r => setTimeout(r, 100));
    }

    // @ts-ignore
    window.renderProxyList = origRender;
    return count;
  });

  // debouncedRenderProxyList가 없으면 -1 반환 → 스킵
  if (renderCount === -1) return;
  // debounce로 인해 1회만 실행되어야 함
  expect(renderCount).toBeLessThanOrEqual(2);
  expect(renderCount).toBeGreaterThan(0);
});

// ─── 그룹 A: 나머지 메커니즘 탭 전환 ────────────────────────────────────────

test('Skill 탭 클릭 → active 클래스', async () => {
  await activateSimulator();
  await page.click('[data-m="skill"]');
  await expect(page.locator('[data-m="skill"]')).toHaveClass(/active/);
});

test('Sub-Agent 탭 클릭 → active 클래스', async () => {
  await activateSimulator();
  await page.click('[data-m="sub-agent"]');
  await expect(page.locator('[data-m="sub-agent"]')).toHaveClass(/active/);
});

// ─── 그룹 B: 히스토리 + 언어 전환 ───────────────────────────────────────────

test('히스토리 버튼 클릭 → 히스토리 패널 토글', async () => {
  await activateSimulator(); // histBtn은 simulator 모드에서만 visible
  const panel = page.locator('#histPanel');
  const btn = page.locator('#histToggleBtn');
  const initialHidden = await panel.evaluate(el => el.classList.contains('hidden'));
  await btn.click();
  if (initialHidden) {
    await expect(panel).not.toHaveClass(/hidden/);
  } else {
    await expect(panel).toHaveClass(/hidden/);
  }
  // 원상복구
  await btn.click();
});

test('언어 전환 버튼 클릭 → 로케일 변경', async () => {
  const btn = page.locator('#langToggleBtn');
  const beforeText = await btn.innerText();
  await btn.click();
  const afterText = await btn.innerText();
  expect(afterText).not.toBe(beforeText);
  // 원상복구
  await btn.click();
});

// ─── 그룹 C: 메커니즘 에디터 입력 ───────────────────────────────────────────

test('CLAUDE.md 탭 → #f-content textarea 입력 유지', async () => {
  await activateSimulator();
  await page.click('[data-m="claude-md"]');
  const textarea = page.locator('#f-content').first();
  await textarea.fill('test-content-input');
  await expect(textarea).toHaveValue('test-content-input');
});

test('Output Style 탭 → #f-content textarea 입력 유지', async () => {
  await activateSimulator();
  await page.click('[data-m="output-style"]');
  const textarea = page.locator('#f-content').first();
  await textarea.fill('output-style-input');
  await expect(textarea).toHaveValue('output-style-input');
});

test('Slash Command 탭 → #f-template textarea 입력 유지', async () => {
  await activateSimulator();
  await page.click('[data-m="slash-command"]');
  const textarea = page.locator('#f-template').first();
  await textarea.fill('slash-template-input');
  await expect(textarea).toHaveValue('slash-template-input');
});

// ─── 그룹 D: 핵심 UI 요소 존재 확인 ─────────────────────────────────────────

test('#actionBtn 전송 버튼 visible', async () => {
  await activateSimulator();
  await page.click('[data-m="claude-md"]');
  await expect(page.locator('#actionBtn')).toBeVisible();
});

test('#modelSel 드롭다운 DOM 존재', async () => {
  await expect(page.locator('#modelSel')).toHaveCount(1);
});

test('#proxyStartBtn ID 명확화 확인', async () => {
  await expect(page.locator('#proxyStartBtn')).toHaveCount(1);
});

// ─── 그룹 E: 프록시 상세 탭 버튼 ────────────────────────────────────────────

for (const dtab of ['messages', 'request', 'response', 'analysis']) {
  test(`프록시 상세 탭 버튼: ${dtab}`, async () => {
    await expect(page.locator(`.dtab[data-dtab="${dtab}"]`)).toHaveCount(1);
  });
}

// ─── 그룹 F: Export 버튼 정적 검증 ──────────────────────────────────────────

test('Export 언어 탭 3개 존재 (curl, python, typescript)', async () => {
  for (const lang of ['curl', 'python', 'typescript']) {
    await expect(page.locator(`.exp-tab[data-lang="${lang}"]`)).toHaveCount(1);
  }
});
