# Step 3: Initialize Sentry in preload.js ✅

## Tasks
1. Add `require('@sentry/electron/renderer').init();` at the very top of preload.js (before contextBridge)

## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-01 | Sentry renderer init 위치 | preload.js 첫 번째 줄이 `@sentry/electron/renderer` require + init | ✅ |
| TC-02 | 기존 코드 유지 | contextBridge, ipcRenderer require 및 exposeInMainWorld 그대로 존재 | ✅ |

## 실행출력

```
TC-01: preload.js line 1 = "require('@sentry/electron/renderer').init();"
TC-02: line 3 contextBridge/ipcRenderer require, line 5-20 exposeInMainWorld 유지 확인
```
