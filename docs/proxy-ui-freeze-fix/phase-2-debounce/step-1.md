# Phase 2 Step 1: renderProxyList debounce (50ms)

## 테스트 기준 (TC)

### TC-1: 연속 이벤트 배치 처리
- **전제**: 10ms 간격으로 3개 'proxy-request' IPC 이벤트 수신
- **행동**: 각 이벤트 콜백에서 debouncedRenderProxyList 호출
- **기대**: 60ms 이내에 renderProxyList DOM 업데이트가 1~2회만 발생

### TC-2: debounce 타이머 리셋
- **전제**: 첫 번째 이벤트 발생 후 30ms 내 두 번째 이벤트 발생
- **기대**: 타이머가 리셋되어 두 번째 이벤트 기준 50ms 후 한 번만 렌더링

## 구현 내용
- debouncedRenderProxyList 헬퍼 추가 (50ms setTimeout)
- IPC onProxyRequest 콜백에서 renderProxyList → debouncedRenderProxyList로 교체

## 결과
- [x] TC-1 통과
- [x] TC-2 통과
