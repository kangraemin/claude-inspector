# offProxy 버그 수정 + E2E 전량 재검사

## Context
`window.electronAPI.offProxy()` 호출 시 guard 없이 직접 접근하여 테스트/비-Electron 환경에서 "Cannot read properties of undefined (reading 'offProxy')" 에러 발생. E2E 테스트가 이를 감지하지 못하고 있음.

---

## Phase 1: offProxy 버그 수정 (`public/index.html`)

### `toggleProxy()` 함수 — 전체 guard 추가 (line 1109)
- **Before**:
```js
  try {
    if (proxyRunning) {
      await window.electronAPI.proxyStop();
      window.electronAPI.offProxy();
```
- **After**:
```js
  try {
    if (!window.electronAPI) throw new Error('electronAPI not available');
    if (proxyRunning) {
      await window.electronAPI.proxyStop();
      window.electronAPI.offProxy();
```

### 페이지 로드 프록시 동기화 — optional chaining (line 2214)
- **Before**:
```js
      window.electronAPI.offProxy();
```
- **After**:
```js
      window.electronAPI?.offProxy?.();
```

## Phase 2: E2E 테스트 수정 + 추가 (`tests/e2e/app.spec.ts`)

### 새 테스트 추가

1. **`모든 offProxy 호출이 안전하게 보호됨`** — 정적 검증
2. **`프록시 토글 시 pageerror 없음`** — 런타임 검증
3. **`프록시 시작→정지 전체 사이클 정상 동작`** — 런타임 검증

## 검증
- `npm run test:e2e` — 전체 통과 확인
- `npm run test:unit` — 유닛 테스트 통과 확인
