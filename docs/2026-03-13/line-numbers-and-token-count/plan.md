# Line Numbers + Token Count 표시 기능

## Context
프록시 뷰의 Request/Response 탭에서 JSON 트리가 렌더링될 때 줄 번호가 없어 디버깅 시 특정 위치를 참조하기 어렵고, request의 토큰 소비량을 한눈에 확인할 수 없음.

## 변경 파일별 상세

### `public/index.html`

#### 1. CSS 추가 — `.jt-lined` 줄 번호 스타일 (line 611 `.jt-row` 뒤에 삽입)

- **변경 이유**: CSS counter 기반으로 `.jt-row`에 줄 번호를 자동 부여
- **Before** (line 611):
```css
    .jt-row  { display: block; white-space: nowrap; }
    .jt-str-long { display: inline; }
```
- **After**:
```css
    .jt-row  { display: block; white-space: nowrap; }
    .jt-lined { counter-reset: jt-line; }
    .jt-lined .jt-row { counter-increment: jt-line; }
    .jt-lined .jt-row::before {
      content: counter(jt-line);
      display: inline-block;
      width: 40px;
      text-align: right;
      padding-right: 12px;
      color: var(--dim);
      font-size: 11px;
      user-select: none;
      opacity: 0.5;
    }
    .jt-str-long { display: inline; }
```
- **영향 범위**: 모든 `.jt-lined` 컨테이너 내 `.jt-row` 요소에 줄 번호 표시

#### 2. CSS 추가 — `.proxy-token-pill` 스타일 (같은 CSS 블록에 추가)

- **변경 이유**: 토큰 추정 pill UI 스타일
- **Before** (line 637):
```css
    .analysis-block .jt-row { white-space: normal; }
```
- **After**:
```css
    .proxy-token-pill {
      padding: 4px 12px;
      font-size: 11px;
      color: var(--dim);
      border-bottom: 1px solid var(--border);
      flex-shrink: 0;
    }
    .analysis-block .jt-row { white-space: normal; }
```
- **영향 범위**: 프록시 Request 탭 상단에만 표시

#### 3. `renderJsonTree` 함수에 `.jt-lined` 클래스 추가 (line 1708)

- **변경 이유**: `renderJsonTree`로 렌더링되는 모든 JSON 트리에 줄 번호 활성화
- **Before** (line 1708):
```javascript
  container.innerHTML = buildJsonHtml(obj, 0);
}
```
- **After**:
```javascript
  container.innerHTML = buildJsonHtml(obj, 0);
  container.classList.add('jt-lined');
}
```
- **영향 범위**: 프록시 Request/Response 탭, Payload 미리보기 모두 줄 번호 표시

#### 4. `renderProxyDetail` 함수에 토큰 pill 추가 (line 2862-2863)

- **변경 이유**: Request 탭일 때 검색바 아래에 토큰 추정 정보 표시
- **Before** (line 2862-2863):
```javascript
  const prevScrollTop = document.getElementById('proxyDetailCode')?.scrollTop ?? 0;
  detail.innerHTML = header + '<div class="json-tree-view" id="proxyDetailCode" style="flex:1;overflow:auto"></div>';
```
- **After**:
```javascript
  const tokenInfo = proxyDetailTab === 'request' && data
    ? (() => {
        const bytes = new TextEncoder().encode(JSON.stringify(data)).length;
        const kb = (bytes / 1024).toFixed(1);
        const tokens = Math.ceil(bytes / 3.5);
        return `<div class="proxy-token-pill">${kb} KB · ~${tokens.toLocaleString()} tok</div>`;
      })()
    : '';
  const prevScrollTop = document.getElementById('proxyDetailCode')?.scrollTop ?? 0;
  detail.innerHTML = header + tokenInfo + '<div class="json-tree-view" id="proxyDetailCode" style="flex:1;overflow:auto"></div>';
```
- **영향 범위**: `renderProxyDetail` 함수 내 Request 탭에서만 표시

## 검증
- 검증 명령어: `pkill -x "Electron" 2>/dev/null; npm start &`
- 기대 결과:
  1. 프록시 뷰 Request/Response 탭에서 JSON 트리 각 행 왼쪽에 줄 번호 표시
  2. Request 탭 상단에 `N.N KB · ~N,NNN tok` pill 표시
  3. Payload 미리보기에도 줄 번호 표시
  4. 기존 검색, 메커니즘 필터, 접기/펼치기 기능 정상 작동
