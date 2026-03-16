# Phase 3: index.html HTML/CSS cleanup + tests

## 목표
시뮬레이터 전용 HTML 요소, CSS, CDN(marked.js)을 제거하고 E2E 테스트를 업데이트한다.

## 범위
- HTML: 랜딩 페이지, 탭 네비게이션, normalPanels(시뮬레이터 패널), 헤더의 simulator 전용 컨트롤(API key, model select, history btn)
- CSS: 시뮬레이터 전용 스타일 (landing, config-panel, preview-panel, resp, export, history 관련)
- CDN: marked.js 제거 (시뮬레이터 마크다운 렌더링용)
- E2E 테스트: 시뮬레이터 테스트 제거, 프록시 테스트 유지

## Steps
- Step 1: HTML/CSS/CDN 정리 및 E2E 테스트 업데이트
