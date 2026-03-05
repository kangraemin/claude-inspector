# Critical 에러 핸들링 수정

## Context
코드 리뷰에서 발견된 Critical 버그 2종. 클립보드 API는 HTTPS 제한 또는 권한 거부 시
unhandled promise rejection 발생. fs.readFileSync는 파일 읽기 실패 시 Electron IPC 핸들러가
예외를 던져 렌더러에 전파됨.

---

## Phase 1: clipboard.writeText() .catch() 추가 (index.html)

### Step 1: 5개 함수 각각에 .catch() 핸들러 추가

**파일**: `public/index.html`

| 함수 | 라인 | 현재 패턴 → 수정 |
|------|------|-----------------|
| `copyPayload()` | ~1739 | `.then(...)` → `.then(...).catch(e => console.error('copy failed', e))` |
| `copyResponse()` | ~1816 | `.then(...)` → `.then(...).catch(e => console.error('copy failed', e))` |
| `copyExport()` | ~1925 | `.then(...)` → `.then(...).catch(e => console.error('copy failed', e))` |
| `copyProxyCmd()` | ~2987 | `.then(...)` → `.then(...).catch(e => console.error('copy failed', e))` |
| `copyProxyDetail()` | ~2999 | `.then(...)` → `.then(...).catch(e => console.error('copy failed', e))` |

각 함수의 `.then()` 블록 닫는 `)` 직후에 `.catch(e => console.error('copy failed', e))` 추가.

---

## Phase 2: fs.readFileSync try/catch 추가 (main.js)

### Step 2: open-file IPC 핸들러 에러 처리

**파일**: `main.js`, 라인 ~103-113

```js
// 현재
ipcMain.handle('open-file', async () => {
  const { canceled, filePaths } = await dialog.showOpenDialog({ ... });
  if (canceled || !filePaths.length) return null;
  return { path: filePaths[0], content: fs.readFileSync(filePaths[0], 'utf-8') };
});

// 수정 후
ipcMain.handle('open-file', async () => {
  const { canceled, filePaths } = await dialog.showOpenDialog({ ... });
  if (canceled || !filePaths.length) return null;
  try {
    return { path: filePaths[0], content: fs.readFileSync(filePaths[0], 'utf-8') };
  } catch (e) {
    console.error('file read failed', e);
    return { path: filePaths[0], content: null, error: e.message };
  }
});
```

렌더러에서 `content === null`이면 에러 처리 가능하도록 error 필드도 반환.

---

## Verification

```bash
npm run test:unit   # 파싱 로직 유닛 테스트
npm run test:e2e    # E2E 테스트 25개 통과 확인
```

수동 확인:
- 클립보드 복사 버튼 정상 동작 (Copied! 피드백)
- 잘못된 파일 경로로 open-file 시도 시 앱 크래시 없이 null 반환
