# Step 2: proxy-stop race condition 방지

## 완료 기준
- `const srv = proxyServer; proxyServer = null;` 패턴 적용
- `srv.close()`로 변경
- 기존 테스트 통과

## 테스트 케이스
| TC | 시나리오 | 기대 결과 | 실제 결과 |
|---|---|---|---|
| TC-1 | proxyServer를 먼저 null로 설정 | `const srv = proxyServer; proxyServer = null;` 패턴 존재 | ✅ PASS |
| TC-2 | srv.close() 사용 | `srv.close(...)` 호출 확인 | ✅ PASS |
| TC-3 | close 콜백에서 proxyServer = null 제거 | 콜백 내에 `proxyServer = null` 없음 | ✅ PASS |
| TC-4 | npm run test:unit 통과 | 기존 13개 테스트 모두 통과 | ✅ PASS (13/13) |

## 검증 명령
- `grep -A5 'proxy-stop' main.js` — race condition 방지 패턴 확인
- `npm run test:unit` — 기존 테스트 통과 확인

## 실행 결과
```
$ grep -A6 'proxy-stop' main.js
ipcMain.handle('proxy-stop', () => {
  if (!proxyServer) return { stopped: true };
  const srv = proxyServer;
  proxyServer = null;
  return new Promise((resolve) => {
    srv.close(() => { resolve({ stopped: true }); });
  });

$ npm run test:unit
✔ 13/13 tests passed (duration: 96ms)
```

## 구현 내용
- `main.js` line 215-222: proxy-stop에서 `const srv = proxyServer; proxyServer = null;`로 race condition 방지, `srv.close()`로 변경
