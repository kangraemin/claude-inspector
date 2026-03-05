# Phase 4 Step 1~3: E2E 테스트

## 테스트 기준 (TC)

### TC 4.1: 리스너 중복 등록 방지
- 프록시 5회 start/stop 반복
- page.evaluate()로 electronAPI.offProxy 호출 횟수 확인
- 각 start마다 offProxy가 선행 호출되었는지 검증

### TC 4.2: 반복 토글 후 UI 반응성
- 프록시 10회 토글
- 프록시 시작 상태에서 버튼 클릭
- 500ms 이내 UI 응답 (disabled → enabled) 확인

### TC 4.3: 프록시 목록 debounce
- electronAPI mock으로 연속 3개 IPC 이벤트 주입
- proxyList DOM 업데이트 횟수 카운팅
- 1~2회만 발생하는지 확인

## 구현 내용
tests/e2e/app.spec.ts에 프록시 관련 테스트 3개 추가

## 결과
- [x] TC-4.1 통과
- [x] TC-4.2 통과
- [x] TC-4.3 통과
