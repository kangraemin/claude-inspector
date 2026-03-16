# 시뮬레이터 코드 완전 제거

## Context
`SHOW_SIMULATOR = false`로 UI만 숨긴 시뮬레이터 코드가 여전히 로드되어 일부 환경에서 JS 에러 발생. 프록시 전용 앱으로 전환.

## 변경 파일별 상세

### `main.js`
- **Before**: Anthropic SDK import + send-to-claude, open-file, get-token-estimate IPC 핸들러 포함
- **After**: 프록시 IPC 핸들러만 유지 (proxy-start/stop/status)

### `preload.js`
- **Before**: sendToClaude, openFile, estimateTokens + 프록시 API
- **After**: platform + 프록시 API만 유지

### `package.json`
- **Before**: @anthropic-ai/sdk 의존성 + build.files에 SDK 포함
- **After**: SDK 제거, @sentry/electron 유지

### `public/index.html`
- **삭제 (~1000줄)**: 시뮬레이터 HTML/CSS/JS, 랜딩 페이지, 탭 내비게이션, i18n 키
- **유지**: 프록시 관련 전체, 공유 유틸(esc, renderJsonTree), i18n(proxy/token/onboard)

### `tests/e2e/app.spec.ts`
- 시뮬레이터 테스트 제거, 프록시 테스트 유지

## 검증
- `npm start` → 프록시 패널 바로 표시
- `npm test` 통과
