## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-1 | MechChipsRow 컴포넌트 추가됨 | `grep -c 'function MechChipsRow' src/presentation/components/ProxyDetail/ProxyDetail.tsx` → 1 | ✅ |
| TC-2 | SearchBar 컴포넌트 추가됨 | `grep -c 'function SearchBar' src/presentation/components/ProxyDetail/ProxyDetail.tsx` → 1 | ✅ |
| TC-3 | dtabs에 Copy 버튼 존재 | `grep -c 'copyDetail' src/presentation/components/ProxyDetail/ProxyDetail.tsx` → 2 | ✅ |

## 실행 출력

TC-1: 1, TC-2: 1, TC-3: 2 — 전부 통과
