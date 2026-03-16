# Phase 1: Backend Cleanup

## 목표
main.js, preload.js, package.json에서 시뮬레이터 관련 코드와 SDK 의존성을 제거한다.

## 범위
- main.js: Anthropic SDK import, send-to-claude/open-file/get-token-estimate IPC 핸들러, 불필요한 fs/dialog import
- preload.js: sendToClaude, openFile, estimateTokens API
- package.json: @anthropic-ai/sdk 의존성 + build.files

## Steps
- Step 1: 시뮬레이터 IPC 핸들러 + SDK 제거
- Step 2: QA - 앱 부팅 검증
