## Step 1: E2E 테스트 추가

| TC | 설명 | 기대결과 | 실제 결과 |
|----|------|----------|-----------|
| TC-1 | 정적검증: 모든 offProxy 호출이 guard로 보호됨 | toggleProxy 내 guard 존재 + 페이지로드 sync optional chaining | ✅ |
| TC-2 | 런타임검증: 프록시 토글 시 pageerror 없음 | 프록시 시작→정지 중 pageerror 0건 | ✅ |
| TC-3 | 런타임검증: 프록시 전체 사이클 정상 동작 | 시작→UI 확인→정지→UI 확인 | ✅ |
| TC-4 | 기존 11개 + 신규 테스트 전량 통과 | npm run test:e2e 전체 통과 | ✅ 14/14 passed |

### 검증명령
- `npm run test:e2e`

## 실행 결과
```
Running 14 tests using 1 worker

  ✓   1 앱 타이틀 확인 (51ms)
  ✓   2 프록시 시작 버튼 존재 (7ms)
  ✓   3 toggleProxy 시작 분기에 offProxy 선행 호출 코드 존재 (리스너 누적 방지) (2ms)
  ✓   4 반복 토글 후 UI 반응성 (500ms 이내) (384ms)
  ✓   5 연속 IPC 이벤트 시 proxyList debounce 동작 (129ms)
  ✓   6 언어 전환 버튼 클릭 → 로케일 변경 (36ms)
  ✓   7 #proxyStartBtn ID 명확화 확인 (3ms)
  ✓   8 프록시 상세 탭 버튼: messages (3ms)
  ✓   9 프록시 상세 탭 버튼: request (2ms)
  ✓  10 프록시 상세 탭 버튼: response (7ms)
  ✓  11 프록시 상세 탭 버튼: analysis (2ms)
  ✓  12 모든 offProxy 호출이 안전하게 보호됨 (guard 또는 optional chaining) (2ms)
  ✓  13 프록시 토글 시 pageerror 없음 (680ms)
  ✓  14 프록시 시작→정지 전체 사이클 정상 동작 (90ms)

  14 passed (5.8s)
```

Unit test: 13/13 passed
