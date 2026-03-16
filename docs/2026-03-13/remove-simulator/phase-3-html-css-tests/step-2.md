# Step 2: E2E 테스트 업데이트 (시뮬레이터 테스트 제거)

## TC

| # | 테스트 | 기대결과 | 실제결과 |
|---|--------|----------|----------|
| TC-1 | activateSimulator 함수 없음 | grep 결과 없음 | ✅ |
| TC-2 | switchM 참조 없음 | grep 결과 없음 | ✅ |
| TC-3 | data-m= 참조 없음 | grep 결과 없음 | ✅ |
| TC-4 | modelSel/actionBtn/histPanel 참조 없음 | grep 결과 없음 | ✅ |
| TC-5 | 프록시 테스트 유지 (proxyStartBtn, dtab 등) | grep 존재 | ✅ |
| TC-6 | TypeScript 문법 오류 없음 | npx tsc --noEmit 통과 | ✅ |

## 구현 내용
- Step 1에서 E2E 테스트 업데이트 함께 완료됨
- activateSimulator(), activateProxy() 헬퍼 함수 제거
- 시뮬레이터 전용 테스트 14개 제거 (메커니즘 탭, API 키, 히스토리, Export 등)
- 프록시 테스트 8개 유지 (시작 버튼, offProxy, UI 반응성, debounce, 언어 전환, 상세 탭)

## 실행 결과

```
$ grep -c "activateSimulator" tests/e2e/app.spec.ts
0

$ grep -c "switchM" tests/e2e/app.spec.ts
0

$ grep -c "data-m=" tests/e2e/app.spec.ts
0

$ grep -c "modelSel\|actionBtn\|histPanel" tests/e2e/app.spec.ts
0

$ grep -c "proxyStartBtn\|dtab" tests/e2e/app.spec.ts
4
```
