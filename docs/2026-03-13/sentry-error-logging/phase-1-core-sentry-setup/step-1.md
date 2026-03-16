# Step 1: Install @sentry/electron + update build config ✅

## Tasks
1. Run `npm install @sentry/electron`
2. In `package.json` → `build.files` array, add `"node_modules/@sentry/**"`

## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-01 | @sentry/electron 설치 | node_modules/@sentry/electron 존재 + package.json dependency 등록 | ✅ |
| TC-02 | build.files 업데이트 | package.json build.files에 `node_modules/@sentry/**` 포함 | ✅ |
| TC-03 | 기존 의존성 유지 | @anthropic-ai/sdk 의존성 그대로 존재 | ✅ |

## 실행출력

```
TC-01: dep: ^7.10.0, Module installed: YES
TC-02: has-sentry: true, build.files includes node_modules/@sentry/**
TC-03: has-anthropic: true
```
