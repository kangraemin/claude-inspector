# Step 1: DI 컨테이너 및 Zustand 스토어

## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-01 | container.ts — createContainer() 함수 존재 | DIContainer 타입 반환 | ✅ |
| TC-02 | captureStore.ts — captures[], selectedId, proxyRunning 상태 | Zustand store 정의됨 | ✅ |
| TC-03 | aiflowStore.ts — aiflowState, result, optimization, chat 상태 | Zustand store 정의됨 | ✅ |
| TC-04 | uiStore.ts — detailTab, search, locale 상태 | Zustand store 정의됨 | ✅ |
| TC-05 | npx tsc --noEmit 에러 없음 | exit 0 | ✅ |

검증 명령어:
```bash
ls src/presentation/di/ src/presentation/store/
npx tsc --noEmit && echo "tsc OK"
```

## 실행출력

```
$ ls src/presentation/di/ src/presentation/store/
src/presentation/di/:
container.ts

src/presentation/store/:
aiflowStore.ts
captureStore.ts
uiStore.ts

$ npx tsc --noEmit && echo "tsc OK"
tsc OK
```

TC-01 ✅ container.ts — createContainer() + DIProvider + useDI 정의
TC-02 ✅ captureStore.ts — captures[], selectedId, proxyRunning 상태
TC-03 ✅ aiflowStore.ts — aiflowState, result, optimization, chat 상태
TC-04 ✅ uiStore.ts — detailTab, search, locale 상태
TC-05 ✅ tsc --noEmit → exit 0
