# Phase 1: Core Sentry Setup

## 목표
@sentry/electron을 설치하고 main/renderer 양쪽 프로세스에서 Sentry를 초기화한다.

## 범위
- package.json 의존성 및 빌드 설정
- main.js Sentry 초기화 (beforeSend로 민감 헤더 필터링)
- preload.js Sentry renderer 초기화

## Steps
1. Install @sentry/electron + update build.files
2. Initialize Sentry in main.js
3. Initialize Sentry in preload.js

## 완료 기준
- 앱이 에러 없이 시작됨
- Sentry가 양쪽 프로세스에서 초기화됨
- 민감 헤더가 Sentry 이벤트에서 제거됨
