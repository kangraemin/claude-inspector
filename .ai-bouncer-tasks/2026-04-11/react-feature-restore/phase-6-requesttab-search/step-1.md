## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-1 | search prop 전달 | `grep -c 'search={search' src/presentation/components/ProxyDetail/RequestTab.tsx` → 1 | ✅ |
| TC-2 | mechKey prop 전달 | `grep -c 'mechKey={mechFilter}' src/presentation/components/ProxyDetail/RequestTab.tsx` → 1 | ✅ |

## 실행 출력

TC-1: `grep -c 'search={search' src/presentation/components/ProxyDetail/RequestTab.tsx`
→ 1

TC-2: `grep -c 'mechKey={mechFilter}' src/presentation/components/ProxyDetail/RequestTab.tsx`
→ 1
