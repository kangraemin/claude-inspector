## Step 1: offProxy guard 적용

| TC | 설명 | 기대결과 | 실제 결과 |
|----|------|----------|-----------|
| TC-1 | toggleProxy에 electronAPI guard 존재 | try 블록 첫줄에 `if (!window.electronAPI)` guard | ✅ line 1110 확인 |
| TC-2 | 페이지 로드 sync에 optional chaining 적용 | `window.electronAPI?.offProxy?.()` 사용 | ✅ line 2215 확인 |

### 검증명령
- TC-1: `grep -n "if (!window.electronAPI)" public/index.html`
- TC-2: `grep -n "offProxy" public/index.html`

## 실행 결과
```
$ grep -n "if (!window.electronAPI)" public/index.html
1110:    if (!window.electronAPI) throw new Error('electronAPI not available');

$ grep -n "offProxy" public/index.html
1113:      window.electronAPI.offProxy();
1117:      window.electronAPI.offProxy();
2215:      window.electronAPI?.offProxy?.();
```

toggleProxy 내부 1113, 1117은 line 1110 guard로 보호됨. 2215는 optional chaining 적용 완료.
