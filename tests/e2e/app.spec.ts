/**
 * E2E tests for Claude Inspector (Electron)
 *
 * Run: npm run test:e2e
 * 앱이 실행 중이면 먼저 종료: pkill -x "Electron"
 */
import { test, expect, _electron as electron } from '@playwright/test';
import type { ElectronApplication, Page } from '@playwright/test';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

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

test('5개 메커니즘 탭 모두 존재', async () => {
  const tabs = ['claude-md', 'output-style', 'slash-command', 'skill', 'sub-agent'];
  for (const m of tabs) {
    await expect(page.locator(`[data-m="${m}"]`)).toBeVisible();
  }
});

test('API 키 입력란 존재', async () => {
  // API key input이 있거나 placeholder가 있는 input
  const apiKeyInput = page.locator('input[type="password"], input[placeholder*="API"], input[placeholder*="sk-"]').first();
  await expect(apiKeyInput).toBeVisible();
});

// ─── 메커니즘 탭 전환 ────────────────────────────────────────────────────────

test('CLAUDE.md 탭 클릭 → 컨텐츠 전환', async () => {
  await page.click('[data-m="claude-md"]');
  await expect(page.locator('[data-m="claude-md"]')).toHaveClass(/active/);
});

test('Output Style 탭 클릭 → 컨텐츠 전환', async () => {
  await page.click('[data-m="output-style"]');
  await expect(page.locator('[data-m="output-style"]')).toHaveClass(/active/);
});

test('Slash Command 탭 클릭 → 컨텐츠 전환', async () => {
  await page.click('[data-m="slash-command"]');
  await expect(page.locator('[data-m="slash-command"]')).toHaveClass(/active/);
});

// ─── 프록시 ──────────────────────────────────────────────────────────────────

test('프록시 시작 버튼 존재', async () => {
  // 프록시 탭으로 이동하거나 헤더에 있는 프록시 버튼 확인
  const proxyBtn = page.locator('button:has-text("프록시"), button:has-text("Proxy"), button:has-text("Start"), #proxyToggle').first();
  await expect(proxyBtn).toBeVisible();
});
