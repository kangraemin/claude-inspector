# Sentry Error Logging Integration

## 목표
Claude Inspector에 @sentry/electron을 통합하여 에러 로그 수집 기반을 마련한다.

## 범위
- @sentry/electron 의존성 설치 및 빌드 설정
- main process (main.js) Sentry 초기화
- renderer process (preload.js) Sentry 초기화
- 민감 정보 (API 키, Authorization 헤더) 필터링

## Phase 구성
- Phase 1: Core Sentry Setup (3 steps)

## 변경 파일
- `package.json`: 의존성 추가 + build.files 업데이트
- `main.js`: Sentry main process 초기화
- `preload.js`: Sentry renderer 초기화
