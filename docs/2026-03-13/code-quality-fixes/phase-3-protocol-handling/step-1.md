# Step 1: SSE 파싱 마지막 이벤트 유실 방지

## 완료 기준
- processEvent 헬퍼 함수 추출
- for 루프 후 `if (events.data) processEvent(events.data)` 추가
- 기존 테스트 통과

## 테스트 케이스
| TC | 시나리오 | 기대 결과 | 실제 결과 |
|---|---|---|---|
| TC-1 | processEvent 헬퍼 함수 추출 | parseSseStream 내부에 processEvent 함수 정의 존재 | ✅ PASS (line 15) |
| TC-2 | for 루프 후 잔여 이벤트 처리 | `if (events.data) processEvent(events.data)` 코드 존재 (루프 바깥) | ✅ PASS (line 35) |
| TC-3 | `var msg` → `let msg` 변경 | `let msg` 또는 함수 스코프 내 선언 확인 | ✅ PASS (line 14) |
| TC-4 | npm run test:unit 통과 | 기존 13개 테스트 모두 통과 | ✅ PASS (13/13) |

## 검증 명령
- `grep -n 'processEvent' main.js` — 헬퍼 함수 확인
- `grep -n 'events.data.*processEvent' main.js` — 루프 후 잔여 처리 확인
- `npm run test:unit` — 기존 테스트 통과 확인

## 실행 결과
```
$ grep -n 'processEvent' main.js
15:    function processEvent(data) {
30:        processEvent(events.data);
35:    if (events.data) processEvent(events.data);

$ npm run test:unit
✔ 13/13 tests passed (duration: 100ms)
```

## 구현 내용
- `main.js` line 12-37: parseSseStream 리팩터링 — processEvent 헬퍼 추출, `var msg` → `let msg`, 루프 후 잔여 이벤트 처리 추가
