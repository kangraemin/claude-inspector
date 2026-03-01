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
```
- 앱 실행 중이면 먼저 종료: `pkill -x "Electron"`
- 앱 시작, 탭 전환, 프록시 제어 동작 검증

### 전체 실행
```bash
npm test
```

## 현재 상태
- 브랜치: !`git branch --show-current`
- 변경 파일: !`git diff --name-only HEAD 2>/dev/null | head -10`

## 테스트 실패 시
- **Unit test 실패**: `public/index.html` 내 함수 로직과 `tests/unit/parse.test.mjs` 기대값 비교
- **E2E 실패**: `pkill -x "Electron"` 후 재시도. 포트 충돌이면 `lsof -ti:9090 | xargs kill`
