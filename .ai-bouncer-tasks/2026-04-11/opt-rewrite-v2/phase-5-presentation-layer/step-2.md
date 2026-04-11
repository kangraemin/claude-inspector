# Step 2: Hooks

## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-01 | useAnalyzeAiFlow.ts — AnalyzeAiFlowUseCase 래핑 | analyze/cancel 함수 노출 | ✅ |
| TC-02 | useOptimization.ts — OptimizeSessionUseCase 래핑 | start/cancel 함수 노출 | ✅ |
| TC-03 | useProxy.ts — ManageProxyUseCase 래핑 | start/stop 함수 노출 | ✅ |
| TC-04 | useElectronEvents.ts — IPC 이벤트 → store 업데이트 | captureStore 갱신 로직 | ✅ |
| TC-05 | npx tsc --noEmit 에러 없음 | exit 0 | ✅ |

검증 명령어:
```bash
ls src/presentation/hooks/
npx tsc --noEmit && echo "tsc OK"
```

## 실행출력

```
$ ls src/presentation/hooks/
useAnalyzeAiFlow.ts
useElectronEvents.ts
useOptimization.ts
useProxy.ts

$ npx tsc --noEmit && echo "tsc OK"
tsc OK
```

TC-01 ✅ useAnalyzeAiFlow.ts — analyze/cancel 함수 노출
TC-02 ✅ useOptimization.ts — start/cancel 함수 노출
TC-03 ✅ useProxy.ts — start/stop 함수 노출
TC-04 ✅ useElectronEvents.ts — onProxyRequest/onProxyResponse → captureStore 갱신
TC-05 ✅ tsc --noEmit → exit 0
