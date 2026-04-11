## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-1 | OnboardingModal 컴포넌트 추가됨 | `grep -c 'function OnboardingModal' src/App.tsx` → 1 | ✅ |
| TC-2 | Cmd+F 단축키 코드 존재 | `grep -c 'search-bar-input' src/App.tsx` → 1 | ✅ |
| TC-3 | Escape 단축키 코드 존재 | `grep -c 'Escape' src/App.tsx` → 1 | ✅ |

## 실행 출력

TC-1: 1, TC-2: 1, TC-3: 1 — 통과
