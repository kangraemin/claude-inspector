# Phase 2 Step 2: renderProxyDetail debounce (100ms)

## 테스트 기준 (TC)

### TC-1: 응답 이벤트 배치 처리
- **전제**: 동일 id로 50ms 간격으로 2개 'proxy-response' 이벤트 수신
- **행동**: 각 콜백에서 debouncedRenderProxyDetail 호출
- **기대**: 150ms 이내에 renderProxyDetail이 1회만 호출됨

## 구현 내용
- debouncedRenderProxyDetail 헬퍼 추가 (100ms setTimeout)
- IPC onProxyResponse 콜백에서 renderProxyDetail → debouncedRenderProxyDetail로 교체

## 결과
- [x] TC-1 통과
