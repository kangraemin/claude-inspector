# Step 1: HTML/CSS/CDN 정리 및 E2E 테스트 업데이트

## TC

| # | 테스트 | 기대결과 | 실제결과 |
|---|--------|----------|----------|
| TC-1 | landingPanel HTML 제거 | grep 결과 없음 | ✅ |
| TC-2 | normalPanels HTML 제거 | grep 결과 없음 | ✅ |
| TC-3 | tabNav 제거 | grep 결과 없음 | ✅ |
| TC-4 | header에 API key/model/history 컨트롤 없음 | grep 결과 없음 | ✅ |
| TC-5 | marked.js CDN 제거 | grep 결과 없음 | ✅ |
| TC-6 | proxyPanel HTML 유지 | 존재 확인 | ✅ |
| TC-7 | 시뮬레이터 전용 CSS 제거 | landing/config-panel 등 없음 | ✅ |
| TC-8 | JS 문법 오류 없음 | node --check 통과 | ✅ |
| TC-9 | E2E 테스트에서 시뮬레이터 테스트 제거 | 시뮬레이터 참조 없음 | ✅ |
| TC-10 | unit 테스트 통과 | npm run test:unit 통과 | ✅ |

## 구현 내용
- HTML: landingPanel, tabNav (6개 탭 버튼), normalPanels (config-panel, preview-panel, hist-panel) 제거
- HTML: header에서 hist-btn, modelSel, apiGroup 제거; logo의 onclick/title 속성 제거
- CDN: marked.js `<script>` 태그 제거
- CSS 제거: .config-panel, .file-btn, .example-row, .ex-tag, .warn-row, .w-icon, .flow*, .btn-sim, .btn-sa, .preview-panel, .preview-header, .ptabs, .ptab, .pactions, .size-pill, .live-pill, .live-dot, .pview, #pv-response, .resp-*, .md-rendered, #pv-export, .exp-*, .hist-panel, .hist-entry, .hist-mech, .hist-msg, .hist-time, .landing*, .lc-*, .logo { cursor: pointer }, #normalPanels
- CSS 유지 (proxy 공유): .panel-header, .inject-chip, .config-body, .how-box, .how-title, .how-text, .field, .config-footer, .btn, .btn-send, .btn-copy, .copy-small, .hist-list, .hist-empty, .spin, @keyframes spin/pulse, scrollbar
- E2E: activateSimulator(), activateProxy() 제거; 시뮬레이터 전용 테스트 14개 제거; 프록시 테스트 8개 유지
- unit 테스트 13/13 통과

## 실행 결과

```
$ grep -c "landingPanel" public/index.html
0

$ grep -c "normalPanels" public/index.html
0

$ grep -c "tabNav" public/index.html
0

$ grep -c "modelSel|apiGroup|hist-btn|histToggleBtn" public/index.html
0

$ grep -c "marked" public/index.html
0

$ grep -c "proxyPanel" public/index.html
3

$ grep -c ".config-panel|.preview-panel|.hist-panel|.md-rendered|.landing|#pv-export|#pv-response" public/index.html
0

$ node --check /tmp/t.js
SYNTAX:OK

$ grep -c "activateSimulator|switchM|data-m=|actionBtn|modelSel|histPanel|histToggleBtn|exp-tab" tests/e2e/app.spec.ts
0

$ npm run test:unit
ℹ pass 13
ℹ fail 0
```
