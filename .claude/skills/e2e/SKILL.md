---
name: e2e
description: Run e2e and unit tests for Claude Inspector. Use after code changes to verify regressions.
user-invocable: true
---

## Claude Inspector 테스트 실행

### Unit tests (파싱 로직)
```bash
npm run test:unit
```
- `parseClaudeMdSections` — CLAUDE.md system-reminder 섹션 파싱
- `parseUserText` — 사용자 메시지 내 injected block 감지
- `detectMechanisms` — 5가지 메커니즘 감지 로직

### E2E tests (Electron UI)
```bash
npm run test:e2e
# headed 모드 (브라우저 보이게)
npm run test:e2e -- --headed
# 특정 테스트만
npm run test:e2e -- --grep "탭 클릭"
# 디버그 모드 (step-by-step)
npm run test:e2e -- --debug
```
- 앱이 실행 중이면 먼저 종료: `pkill -x "Electron"`

### 전체 실행
```bash
npm test
```

## 현재 상태
- 브랜치: !`git branch --show-current`
- 변경 파일: !`git diff --name-only HEAD 2>/dev/null | head -10`

---

## Playwright 핵심 패턴

### 셀렉터 우선순위
```typescript
// ✅ 권장: role, label, data-testid 순
page.getByRole('button', { name: '프록시 시작' })
page.getByLabel('API Key')
page.locator('[data-testid="proxy-toggle"]')
page.locator('[data-m="claude-md"]')  // 이 프로젝트 convention

// ❌ 금지: CSS 클래스, nth-child
page.locator('.btn.active')
page.locator('div > span:nth-child(2)')
```

### 대기 전략
```typescript
// ❌ 금지: 고정 타임아웃
await page.waitForTimeout(3000);

// ✅ 권장: 상태/요소 기반
await page.waitForLoadState('domcontentloaded');
await expect(page.locator('[data-m="claude-md"]')).toHaveClass(/active/);
await expect(page.getByText('Copied!')).toBeVisible();
```

### Page Object Model (복잡한 테스트에서 활용)
```typescript
// tests/e2e/pages/MechanismPage.ts
export class MechanismPage {
  constructor(private page: Page) {}

  tab(name: string) {
    return this.page.locator(`[data-m="${name}"]`);
  }

  async switchTo(name: string) {
    await this.tab(name).click();
    await expect(this.tab(name)).toHaveClass(/active/);
  }
}
```

### 네트워크/IPC 모킹 (프록시 테스트)
```typescript
// Anthropic API 응답 모킹
await page.route('**/api.anthropic.com/**', route => {
  route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify({ id: 'msg_test', content: [{ type: 'text', text: 'ok' }] }),
  });
});
```

### 실패 시 트레이스 수집
```typescript
// playwright.config.ts에 추가
use: {
  trace: 'on-first-retry',
  screenshot: 'only-on-failure',
  video: 'retain-on-failure',
}
```

---

## 테스트 실패 대처

| 원인 | 해결 |
|------|------|
| 앱 실행 중 충돌 | `pkill -x "Electron"` |
| 포트 충돌 | `lsof -ti:9090 \| xargs kill` |
| 셀렉터 못 찾음 | `--headed` 모드로 실행해 직접 확인 |
| 타임아웃 | `waitForTimeout` → `waitForLoadState` 변경 |
| Unit test 불일치 | `public/index.html` 함수와 `tests/unit/parse.test.mjs` 기대값 동기화 확인 |

---

## 테스트 피라미드

```
      /E2E\         ← 앱 실행·탭 전환·프록시 제어
     /──────\
    /Unit    \      ← parseClaudeMdSections, detectMechanisms
   /──────────\
```

E2E는 핵심 워크플로우만. 파싱 로직 엣지케이스는 unit test로.
