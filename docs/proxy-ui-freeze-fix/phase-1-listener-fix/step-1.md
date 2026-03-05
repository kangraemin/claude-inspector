# Phase 1 Step 1: toggleProxy 리스너 중복 등록 수정

## 테스트 기준 (TC)

### TC-1: 시작 시 offProxy 선행 호출
- **전제**: window.electronAPI.offProxy, onProxyRequest, onProxyResponse가 mock으로 추적됨
- **행동**: toggleProxy()를 proxyRunning=false 상태에서 호출
- **기대**: onProxyRequest 등록 전에 offProxy가 1회 호출됨

### TC-2: 리스너 누적 방지
- **전제**: 프록시를 5회 시작/중지 반복
- **행동**: IPC 'proxy-request' 이벤트 1개 발생
- **기대**: proxyCaptures에 데이터 1개만 추가됨 (5개 아님)

### TC-3: 중지 시 offProxy 여전히 호출
- **전제**: proxyRunning=true
- **행동**: toggleProxy() 호출 (중지 분기)
- **기대**: offProxy가 1회 호출됨

## 구현 내용
`toggleProxy()` else 분기 최상단에 `window.electronAPI.offProxy()` 추가.

## 결과
- [x] TC-1 통과
- [x] TC-2 통과
- [x] TC-3 통과
