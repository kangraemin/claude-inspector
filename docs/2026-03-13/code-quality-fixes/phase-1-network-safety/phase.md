# 개발 Phase 1: main.js 네트워크 안전성

## 목표
- EADDRINUSE 무한 재시도 방지 (Issue 2)
- req 스트림 에러 핸들러 추가 (Issue 3)
- proxyRes 스트림 에러 핸들러 추가 (Issue 10)

## 범위
- 변경 대상 파일: `main.js` — 서버/프록시 에러 핸들링 보강

## Steps
- Step 1: EADDRINUSE 재시도 1회 제한 — `retried` 플래그로 무한 루프 방지
- Step 2: req/proxyRes 에러 핸들러 추가 — 스트림 에러 시 안전하게 응답 종료

## 선행 조건
- 없음

## 완료 기준
- `npm run test:unit` 통과
- EADDRINUSE 재시도가 1회로 제한되는 코드 확인
- req, proxyRes에 error 이벤트 핸들러 존재 확인
