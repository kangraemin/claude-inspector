## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-1 | TokenInfoRow 컴포넌트 존재 | `grep -c 'function TokenInfoRow' src/presentation/components/ProxyDetail/ResponseTab.tsx` → 1 | ✅ |
| TC-2 | token-info-row 클래스 사용 | `grep -c 'token-info-row' src/presentation/components/ProxyDetail/ResponseTab.tsx` → 1 | ✅ |
| TC-3 | search/mechFilter 전달 | `grep -c 'mechKey={mechFilter}' src/presentation/components/ProxyDetail/ResponseTab.tsx` → 1 | ✅ |

## 실행 출력

TC-1: `grep -c 'function TokenInfoRow' src/presentation/components/ProxyDetail/ResponseTab.tsx`
→ 1

TC-2: `grep -c 'token-info-row' src/presentation/components/ProxyDetail/ResponseTab.tsx`
→ 1

TC-3: `grep -c 'mechKey={mechFilter}' src/presentation/components/ProxyDetail/ResponseTab.tsx`
→ 1
