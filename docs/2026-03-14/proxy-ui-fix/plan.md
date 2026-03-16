# macOS 트래픽 라이트 독립 titlebar 영역 추가

## 변경 파일별 상세

### `public/index.html`
- **변경 이유**: macOS hiddenInset 모드에서 트래픽 라이트(닫기/최소화/확대)가 헤더 콘텐츠와 겹침. 다른 앱처럼 상단에 별도 드래그 영역을 두어 분리.
- **Before** (현재 코드):
```css
.header { -webkit-app-region: drag; }
.header-right, .header-right *, .logo { -webkit-app-region: no-drag; }
body.darwin .header { padding-left: 76px; }
```
```html
<header class="header">
  <div class="logo">...
```
- **After** (변경 후):
```css
.titlebar {
  display: none; height: 28px; flex-shrink: 0;
  background: var(--surface); -webkit-app-region: drag;
}
body.darwin .titlebar { display: block; }
.header { -webkit-app-region: drag; }
.header-right, .header-right *, .logo { -webkit-app-region: no-drag; }
```
```html
<div class="titlebar"></div>
<header class="header">
  <div class="logo">...
```
- **영향 범위**: macOS에서만 28px 높이의 빈 드래그 영역 추가. Windows/Linux는 display:none으로 무영향.

## 검증
- `npm start`로 앱 실행
- macOS에서 트래픽 라이트가 titlebar 영역 안에 위치하고 헤더와 겹치지 않음 확인
