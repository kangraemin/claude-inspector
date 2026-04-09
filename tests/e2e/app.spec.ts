/**
 * E2E tests for Claude Inspector (Electron) — Proxy mode only
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

// ─── 기본 UI ─────────────────────────────────────────────────────────────────

test('앱 타이틀 확인', async () => {
  await expect(page).toHaveTitle('Claude Inspector');
});

// ─── 프록시 ──────────────────────────────────────────────────────────────────

test('프록시 시작 버튼 존재', async () => {
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

// ─── 언어 전환 ───────────────────────────────────────────────────────────────

test('언어 전환 버튼 클릭 → 로케일 변경', async () => {
  const btn = page.locator('#langToggleBtn');
  const beforeText = await btn.innerText();
  await btn.click();
  const afterText = await btn.innerText();
  expect(afterText).not.toBe(beforeText);
  // 원상복구
  await btn.click();
});

// ─── 프록시 UI 요소 ─────────────────────────────────────────────────────────

test('#proxyStartBtn ID 명확화 확인', async () => {
  await expect(page.locator('#proxyStartBtn')).toHaveCount(1);
});

// ─── 프록시 상세 탭 버튼 ────────────────────────────────────────────────────

for (const dtab of ['aiflow', 'request', 'response', 'analysis']) {
  test(`프록시 상세 탭 버튼: ${dtab}`, async () => {
    await expect(page.locator(`.dtab[data-dtab="${dtab}"]`)).toHaveCount(1);
  });
}

// ─── offProxy 안전성 ─────────────────────────────────────────────────────────

test('모든 offProxy 호출이 안전하게 보호됨 (guard 또는 optional chaining)', () => {
  const html = fs.readFileSync(path.join(ROOT, 'public/index.html'), 'utf8');

  // toggleProxy 내부: electronAPI guard가 try 블록 전에 존재 (early return)
  const toggleProxyMatch = html.match(/async function toggleProxy\(\)[\s\S]*?if \(!window\.electronAPI\) return;[\s\S]*?try\s*\{/);
  expect(toggleProxyMatch).not.toBeNull();

  // 페이지 로드 sync: optional chaining 사용
  const syncBlock = html.match(/프록시 상태 동기화[\s\S]*?\}\)\(\)/);
  expect(syncBlock).not.toBeNull();
  // offProxy in sync block should use optional chaining
  const syncOffProxy = syncBlock![0].match(/electronAPI\?\.offProxy\?\.\(\)/);
  expect(syncOffProxy).not.toBeNull();
});

test('프록시 토글 시 pageerror 없음', async () => {
  const pageErrors: string[] = [];
  const handler = (err: Error) => pageErrors.push(err.message);
  page.on('pageerror', handler);

  try {
    const btn = page.locator('#proxyStartBtn');
    await btn.click();
    await expect(btn).not.toBeDisabled({ timeout: 5000 });
    await page.waitForTimeout(300);

    // stop
    await btn.click();
    await expect(btn).not.toBeDisabled({ timeout: 5000 });
    await page.waitForTimeout(300);

    const offProxyErrors = pageErrors.filter(e => e.includes('offProxy') || e.includes('electronAPI'));
    expect(offProxyErrors).toHaveLength(0);
  } finally {
    page.removeListener('pageerror', handler);
  }
});

test('AI Flow 탭 클릭 → aiflow 컨텐츠 영역 표시', async () => {
  await page.locator('.dtab[data-dtab="aiflow"]').click();
  // 캡처 없으면 안내 메시지(aiflow-status) 표시
  await expect(page.locator('.aiflow-status')).toBeVisible({ timeout: 5000 });
});

test('프록시 시작→정지 전체 사이클 정상 동작', async () => {
  const btn = page.locator('#proxyStartBtn');
  const portInput = page.locator('#proxyPort');

  // 시작
  await btn.click();
  await expect(btn).not.toBeDisabled({ timeout: 5000 });

  // 포트 값 존재 확인
  const port = await portInput.inputValue();
  expect(Number(port)).toBeGreaterThan(0);

  // 정지
  await btn.click();
  await expect(btn).not.toBeDisabled({ timeout: 5000 });
});
