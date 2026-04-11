## TC

| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-1 | parseClaudeMdSections 호출 존재 | `grep -c 'parseClaudeMdSections' src/presentation/components/ProxyDetail/AnalysisTab.tsx` → 1 이상 | ✅ |
| TC-2 | Skill input JSON 표시 | `grep -c 'sk.input' src/presentation/components/ProxyDetail/AnalysisTab.tsx` → 1 이상 | ✅ |
| TC-3 | SubAgent input JSON 표시 | `grep -c 'sa.input' src/presentation/components/ProxyDetail/AnalysisTab.tsx` → 1 이상 | ✅ |

## 실행 출력

TC-1: `grep -c 'parseClaudeMdSections' src/presentation/components/ProxyDetail/AnalysisTab.tsx`
→ 1

TC-2: `grep -c 'sk.input' src/presentation/components/ProxyDetail/AnalysisTab.tsx`
→ 1

TC-3: `grep -c 'sa.input' src/presentation/components/ProxyDetail/AnalysisTab.tsx`
→ 1
