## 목표
`window.electronAPI.offProxy()` 호출 시 guard 추가하여 undefined 에러 방지

## 범위
- `public/index.html`: toggleProxy() guard 추가 + 페이지 로드 sync optional chaining

## Steps

### Step 1: toggleProxy guard + 페이지로드 optional chaining
- `public/index.html` line 1109: try 블록 첫줄에 `if (!window.electronAPI)` guard 추가
- `public/index.html` line 2214: `window.electronAPI?.offProxy?.()` optional chaining 적용
