## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-1 | mechFilter 타입이 string or null로 변경됨 | `grep -c 'mechFilter: string' src/presentation/store/uiStore.ts` → 1 이상 | ✅ |
| TC-2 | 초기값이 null로 변경됨 | `grep -c 'mechFilter: null' src/presentation/store/uiStore.ts` → 1 | ✅ |

## 실행 출력

TC-1: `grep -c 'mechFilter: string' src/presentation/store/uiStore.ts`
→ 1

TC-2: `grep -c 'mechFilter: null' src/presentation/store/uiStore.ts`
→ 1
