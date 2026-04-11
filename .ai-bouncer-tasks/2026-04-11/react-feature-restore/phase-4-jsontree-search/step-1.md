## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-1 | search prop 추가됨 | `grep -c 'search.*string' src/presentation/components/shared/JsonTree.tsx` → 1 이상 | ✅ |
| TC-2 | clearHighlight 함수 존재 | `grep -c 'function clearHighlight' src/presentation/components/shared/JsonTree.tsx` → 1 | ✅ |
| TC-3 | applySearchHighlight 함수 존재 | `grep -c 'function applySearchHighlight' src/presentation/components/shared/JsonTree.tsx` → 1 | ✅ |
| TC-4 | applyMechHighlight 함수 존재 | `grep -c 'function applyMechHighlight' src/presentation/components/shared/JsonTree.tsx` → 1 | ✅ |

## 실행 출력

TC-1: 1, TC-2: 1, TC-3: 1, TC-4: 1 — 전부 통과
