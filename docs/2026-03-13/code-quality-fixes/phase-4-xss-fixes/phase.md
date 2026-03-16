# 개발 Phase 4: public/index.html XSS 수정

## 목표
- onclick 핸들러 XSS 방지: data-key 속성 + esc() 사용 (Issue 1)
- 토큰 팝오버 미이스케이프 값에 esc() 적용 (Issue 4)

## 범위
- 변경 대상 파일: `public/index.html` — mech-chip onclick, 토큰 팝오버 값 이스케이프

## Steps
- Step 1: mech-chip onclick XSS 수정 — safePattern 제거, data-key + esc() 사용, setProxyDetailMechFilter 시그니처 변경
- Step 2: 토큰 팝오버 값에 esc() 적용 — d.model, d.kb, d.total, d.cachePct, r.label, r.tokens, r.price, r.cost

## 선행 조건
- Phase 3 완료

## 완료 기준
- `npm run test:unit` 통과
- safePattern 코드 제거 확인
- 토큰 팝오버 innerHTML에서 esc() 적용 확인
