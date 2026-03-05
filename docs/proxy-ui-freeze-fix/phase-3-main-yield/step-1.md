# Phase 3 Step 1: main.js setImmediate yield

## 테스트 기준 (TC)

### TC-1: IPC 전송이 이벤트 루프를 블로킹하지 않음
- **전제**: 큰 스트리밍 응답 (4KB+) 수신
- **행동**: proxyRes.on('end') 콜백 실행
- **기대**: IPC send가 setImmediate 내에서 실행되어 메인 프로세스 이벤트 루프에 양보

## 구현 내용
`proxyRes.on('end')` 콜백에서 `mainWin.webContents.send('proxy-response', ...)` 호출을
`setImmediate(() => { ... })` 로 감쌈.

## 결과
- [x] TC-1 통과
