## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-1 | input dark bg CSS 추가됨 | `grep -c 'input\[type=number\]' src/styles/index.css` | ✅ |
| TC-2 | .aiflow-step-num.sub CSS 추가됨 | `grep -c 'aiflow-step-num.sub' src/styles/index.css` | ✅ |
| TC-3 | .mech-chip CSS 추가됨 | `grep -c 'mech-chip' src/styles/index.css` | ✅ |
| TC-4 | .search-bar-row CSS 추가됨 | `grep -c 'search-bar-row' src/styles/index.css` | ✅ |
| TC-5 | .token-info-row CSS 추가됨 | `grep -c 'token-info-row' src/styles/index.css` | ✅ |
| TC-6 | .onboard-overlay CSS 추가됨 | `grep -c 'onboard-overlay' src/styles/index.css` | ✅ |

## 실행 출력

TC-1: `grep -c 'input\[type=number\]' src/styles/index.css`
→ 3

TC-2: `grep -c 'aiflow-step-num.sub' src/styles/index.css`
→ 1

TC-3: `grep -c 'mech-chip' src/styles/index.css`
→ 9

TC-4: `grep -c 'search-bar-row' src/styles/index.css`
→ 1

TC-5: `grep -c 'token-info-row' src/styles/index.css`
→ 1

TC-6: `grep -c 'onboard-overlay' src/styles/index.css`
→ 1
