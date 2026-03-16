# CLAUDE.md 클릭 시 깨짐 수정

## 변경 파일별 상세
### `public/index.html`

#### highlightMechInJsonTree — CLAUDE.md(cm_*) 블록

- **변경 이유**: CLAUDE.md 칩 클릭 시 `expandLongStr` + `expandAncestors`로 긴 문자열을 자동 펼치면, 단일 `.jt-row` 안에 수백 줄의 텍스트가 표시되어 줄 번호 거터가 비어보임. 자동 펼침을 제거하고 해당 `.jt-row`만 하이라이트.
- **Before** (라인 ~2700-2739):
```javascript
if (mechKey.startsWith('cm')) {
    // ...
    for (const el of strEls) {
      if (!el.textContent.includes('Contents of ' + section.path)) continue;
      expandLongStr(el);
      expandAncestors(el);
      const html = el.innerHTML;
      // ... hlRange로 텍스트 범위 하이라이트
      hlRange(el, start, end, true);
      break;
    }
}
```
- **After**:
```javascript
if (mechKey.startsWith('cm')) {
    // ...
    // .jt-str, .jt-str-expanded, .jt-str-preview 모두 검색
    const allStr = container.querySelectorAll('.jt-str, .jt-str-expanded, .jt-str-preview');
    for (const el of allStr) {
      if (!el.textContent.includes('Contents of ' + section.path)) continue;
      // 자동 펼침 안 함. 부모 .jt-row를 찾아서 하이라이트
      expandAncestors(el);
      const row = el.closest('.jt-row');
      if (row) {
        row.classList.add('mech-hl-row');
        requestAnimationFrame(() => row.scrollIntoView({ behavior: 'smooth', block: 'start' }));
      }
      break;
    }
}
```
- **영향 범위**: CLAUDE.md 칩 클릭 동작만 변경. 다른 메커니즘(sc, os 등) 하이라이트는 그대로.

#### CSS — mech-hl-row 클래스 확인
- 이미 `mech-hl-row`가 정의되어 있는지 확인 필요. 없으면 추가.

## 검증
- 검증 명령어: `pkill -x "Electron" 2>/dev/null; npm start &`
- 기대 결과: CLAUDE.md 칩 클릭 시 해당 행이 하이라이트되고 스크롤됨. 문자열 자동 펼침 없음. 줄 번호 유지.
