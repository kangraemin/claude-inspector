# Step 2: Initialize Sentry in main.js ✅

## Tasks
1. Add Sentry require + init at the very top of main.js (before all other requires)
2. DSN from `process.env.SENTRY_DSN` (empty string default)
3. beforeSend filter strips sensitive headers from breadcrumbs

## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-01 | Sentry require 위치 | main.js 첫 번째 줄이 `@sentry/electron/main` require | ✅ |
| TC-02 | Sentry.init 호출 | dsn, environment, release, beforeSend 설정 존재 | ✅ |
| TC-03 | beforeSend 필터 | x-api-key, authorization 헤더 삭제 로직 존재 | ✅ |
| TC-04 | 기존 코드 유지 | electron, fs, path 등 기존 require 그대로 존재 | ✅ |

## 실행출력

```
TC-01: main.js line 1 = "const Sentry = require('@sentry/electron/main');"
TC-02: Sentry.init({ dsn, environment, release, beforeSend }) 확인
TC-03: delete bc.data['x-api-key'], ['X-Api-Key'], ['authorization'], ['Authorization'] 확인
TC-04: line 22-27에 electron, fs, path, http, https, Anthropic require 유지
```
