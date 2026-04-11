## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-1 | addCapture에 50개 제한 로직 존재 | `grep -c 'next.length > 50' src/presentation/store/captureStore.ts` | ✅ |

## 실행 출력

TC-1: `grep -c 'next.length > 50' src/presentation/store/captureStore.ts`
→ 1
