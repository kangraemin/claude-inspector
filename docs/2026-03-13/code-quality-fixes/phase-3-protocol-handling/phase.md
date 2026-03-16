# 개발 Phase 3: main.js 프로토콜 처리

## 목표
- SSE 파싱: 스트림 끝 빈 줄 없을 때 마지막 이벤트 유실 방지 (Issue 6)
- proxy-stop race condition 방지 (Issue 7)

## 범위
- 변경 대상 파일: `main.js` — parseSseStream 함수 리팩터링 + proxy-stop 핸들러 수정

## Steps
- Step 1: parseSseStream에 processEvent 헬퍼 추출 + 루프 후 잔여 이벤트 처리
- Step 2: proxy-stop에서 proxyServer를 먼저 null로 설정하여 race condition 방지

## 선행 조건
- Phase 2 완료

## 완료 기준
- `npm run test:unit` 통과
- 빈 줄 없는 SSE 스트림에서 마지막 이벤트가 처리되는 코드 확인
- proxy-stop에서 `const srv = proxyServer; proxyServer = null;` 패턴 확인
