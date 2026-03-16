# Step 1: EADDRINUSE 재시도 1회 제한

## 완료 기준
- `let retried = false` 플래그 추가
- EADDRINUSE 에러 시 `!retried` 체크 후 재시도, 두 번째부터는 resolve({ error })
- 기존 테스트 통과

## 테스트 케이스
| TC | 시나리오 | 기대 결과 | 실제 결과 |
|---|---|---|---|
| TC-1 | main.js에 `let retried = false` 플래그 존재 | `retried` 변수가 server.on('error') 핸들러 바로 위에 선언됨 | ✅ PASS (line 197) |
| TC-2 | EADDRINUSE 분기에서 `!retried` 조건 체크 | `if (err.code === 'EADDRINUSE' && !retried)` 패턴 존재 | ✅ PASS (line 199) |
| TC-3 | 재시도 시 `retried = true` 설정 | retried 플래그가 true로 설정된 후 listen(0) 호출 | ✅ PASS (line 200) |
| TC-4 | 두 번째 EADDRINUSE 시 resolve({ error }) | else 분기에서 resolve({ error: err.message }) 호출 | ✅ PASS (line 203) |
| TC-5 | npm run test:unit 통과 | 기존 13개 테스트 모두 통과 | ✅ PASS (13/13) |

## 검증 명령
- `grep -n 'retried' main.js` — retried 플래그 존재 확인
- `grep -A3 'EADDRINUSE' main.js` — 조건 분기 확인
- `npm run test:unit` — 기존 테스트 통과 확인

## 실행 결과
```
$ grep -n 'retried' main.js
197:    let retried = false;
199:      if (err.code === 'EADDRINUSE' && !retried) {
200:        retried = true;

$ npm run test:unit
✔ 13/13 tests passed (duration: 95ms)
```

## 구현 내용
- `main.js` line 197-204: `let retried = false` 플래그 추가, EADDRINUSE 조건에 `&& !retried` 추가, 재시도 전 `retried = true` 설정
