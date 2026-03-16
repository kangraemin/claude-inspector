# Step 3: QA — 전체 테스트 실행

## TC

| # | 테스트 | 기대결과 | 실제결과 |
|---|--------|----------|----------|
| TC-1 | unit 테스트 통과 | npm run test:unit 13/13 통과 | ✅ |
| TC-2 | JS 문법 오류 없음 | node --check 통과 | ✅ |
| TC-3 | 시뮬레이터 HTML 잔재 없음 | landingPanel, tabNav, normalPanels grep 0 | ✅ |
| TC-4 | 시뮬레이터 CSS 잔재 없음 | config-panel, preview-panel, landing grep 0 | ✅ |
| TC-5 | 시뮬레이터 JS 잔재 없음 | SHOW_SIMULATOR, getMechanisms, buildPayload grep 0 | ✅ |
| TC-6 | 프록시 기능 보존 | proxyPanel, toggleProxy, renderProxyList 존재 | ✅ |

## 실행 결과

```
$ npm run test:unit
ℹ tests 13
ℹ pass 13
ℹ fail 0

$ node --check /tmp/t.js
SYNTAX:OK

TC-3 HTML remnants:
  landingPanel: 0
  tabNav: 0
  normalPanels: 0

TC-4 CSS remnants:
  config-panel: 0
  preview-panel: 0
  landing: 0

TC-5 JS remnants:
  SHOW_SIMULATOR: 0
  getMechanisms: 0
  buildPayload: 0

TC-6 Proxy preserved:
  proxyPanel: 3
  toggleProxy: 2
  renderProxyList: 7
```
