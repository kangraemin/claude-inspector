## 목표
captureStore에 50개 제한 추가 — 50개 초과 시 오래된 것부터 제거

## 범위
- src/presentation/store/captureStore.ts — addCapture 함수 수정

## Steps
1. addCapture에 50개 슬라이싱 로직 추가
