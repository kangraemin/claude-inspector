# Step 2: req/proxyRes 에러 핸들러 추가

## 완료 기준
- `req.on('error', ...)` 핸들러 추가: 400 응답 후 종료
- `proxyRes.on('error', ...)` 핸들러 추가: res.end() 호출
- 기존 테스트 통과

## 테스트 케이스
| TC | 시나리오 | 기대 결과 | 실제 결과 |
|---|---|---|---|
| TC-1 | req.on('error') 핸들러 존재 | createServer 콜백 내에서 req.on('error', ...) 호출 확인 | ✅ PASS (line 139) |
| TC-2 | req 에러 시 400 응답 | `if (!res.headersSent) res.writeHead(400)` + `res.end()` | ✅ PASS |
| TC-3 | proxyRes.on('error') 핸들러 존재 | proxyRes.on('error', ...) 호출 확인 | ✅ PASS (line 168) |
| TC-4 | proxyRes 에러 시 res.end() | 에러 핸들러에서 `res.end()` 호출 | ✅ PASS |
| TC-5 | npm run test:unit 통과 | 기존 13개 테스트 모두 통과 | ✅ PASS (13/13) |

## 검증 명령
- `grep -n "req.on('error'" main.js` — req 에러 핸들러 확인
- `grep -n "proxyRes.on('error'" main.js` — proxyRes 에러 핸들러 확인
- `npm run test:unit` — 기존 테스트 통과 확인

## 실행 결과
```
$ grep -n "req.on('error'" main.js
139:      req.on('error', () => {

$ grep -n "proxyRes.on('error'" main.js
168:          proxyRes.on('error', () => { res.end(); });

$ npm run test:unit
✔ 13/13 tests passed (duration: 94ms)
```

## 구현 내용
- `main.js` line 139-141: `req.on('error', ...)` 핸들러 추가 — 400 응답 후 종료
- `main.js` line 168: `proxyRes.on('error', ...)` 핸들러 추가 — res.end() 호출
