# Claude Inspector — Development Guide

## 프로젝트 개요

Claude Code의 5가지 프롬프트 메커니즘(CLAUDE.md, Output Style, Slash Command, Skill, Sub-Agent)이
실제로 Anthropic API에 어떤 JSON 페이로드를 만드는지 시각화하고 테스트하는 **Electron 데스크탑 앱**.

**타겟 유저**: Claude Code 내부 동작 원리를 파악하고 싶은 개발자

## 아키텍처

```
main.js         Electron main process — BrowserWindow 생성, IPC 핸들러
preload.js      contextBridge — window.electronAPI 노출
public/
  index.html    단일 파일 프론트엔드 (CSS + Vanilla JS 인라인)
package.json    Electron + electron-builder 설정
```

### IPC 채널

| 채널 | 방향 | 역할 |
|------|------|------|
| `send-to-claude` | renderer → main | Anthropic API 호출 |

## 기술 스택

- **Electron 33** — 데스크탑 앱
- **@anthropic-ai/sdk** — API 호출 (main process에서만)
- **Vanilla JS** — 프레임워크 없음, 빌드 스텝 없음
- **highlight.js (CDN)** — JSON 신택스 하이라이팅
- **marked.js (CDN)** — Markdown 렌더링

## 현재 기능

- 5가지 메커니즘 탭 (각 실제 API 페이로드 실시간 미리보기)
- CLAUDE.md / Output Style / Slash Command: 직접 API 전송 가능
- Skill: Simulate Effect (단순화 버전으로 실전 테스트)
- Sub-Agent: Run Sub-Agent (delegation prompt 단독 실행)
- API Key localStorage 저장
- 플로우 다이어그램 (Skill, Sub-Agent 동작 시각화)

## 개발 규칙

- **Electron Only** — server.ts 삭제, web fallback 코드 제거
- `public/index.html` 단일 파일 유지 (외부 .js/.css 파일 생성 금지)
- IPC 추가 시: main.js `ipcMain.handle` + preload.js `contextBridge` 동시 수정
- UI 스타일: VS Code Dark+ 테마 유지 (CSS 변수 --bg, --surface, --blue 등)
- 커밋: 한글, HEREDOC 필수 (`~/.claude/rules/git-rules.md`)

## 빌드/실행

```bash
npm start          # 개발 실행
npm run dev        # 개발 + 로깅
npm run dist       # 배포 빌드 → release/
```

## 현재 완료된 기능 (2026-02-28)

### ✅ P0 완료
- server.ts 제거, web fallback 완전 삭제
- KB · 토큰 수 실시간 표시 (헤더 size-pill)
- 📂 파일 불러오기 (Electron dialog IPC)
- Markdown 응답 렌더링 (marked.js CDN + MD 토글 버튼)

### ✅ P1 완료
- Export 탭 — cURL / Python / TypeScript 스니펫 생성
- 요청 히스토리 패널 (세션 내 최근 10개, 클릭 복원)
- KB · ~토큰 실시간 표시

### ✅ UX 버그 수정
- macOS 창 드래그 (`-webkit-app-region: drag`)
- 트래픽 라이트 버튼 겹침 (`body.darwin .header { padding-left: 76px }`)

---

## 다음 작업: 프록시 모드 (진짜 인스펙터)

### 개요
현재 앱은 "시뮬레이터" — 페이로드를 직접 구성해서 전송.
**목표**: Claude Code CLI의 실제 API 트래픽을 가로채서 실시간 시각화.

### 원리
```
Claude Code CLI → localhost:9090 (프록시) → Anthropic API
                        ↓
                  Inspector UI에 실시간 표시
```

Claude Code는 `ANTHROPIC_BASE_URL` 환경변수를 지원:
```bash
ANTHROPIC_BASE_URL=http://localhost:9090 claude
```

### 구현 계획

#### main.js 추가
```js
// HTTP 프록시 서버 (node:http)
const proxyServer = http.createServer(async (req, res) => {
  // 1. 요청 바디 수집
  // 2. IPC로 renderer에 전송 (실시간 표시)
  // 3. 실제 Anthropic API로 포워딩
  // 4. 응답 캡처 후 IPC로 전송
  // 5. 클라이언트에 응답 반환
});
proxyServer.listen(9090);
```

#### IPC 채널 추가
| 채널 | 방향 | 역할 |
|------|------|------|
| `proxy-request` | main → renderer | 캡처된 요청 페이로드 |
| `proxy-response` | main → renderer | 캡처된 응답 |
| `proxy-start` | renderer → main | 프록시 서버 시작 |
| `proxy-stop` | renderer → main | 프록시 서버 중지 |

#### UI 추가
- **Proxy 탭** 추가 (또는 별도 모드)
- 프록시 ON/OFF 토글 + 포트 설정
- 캡처된 요청 목록 (실시간 스트림)
- 클릭하면 페이로드 상세 보기
- `ANTHROPIC_BASE_URL=http://localhost:9090 claude` 명령 복사 버튼

### 기술 고려사항
- `node:http` 모듈로 프록시 서버 구현 (외부 의존성 불필요)
- HTTPS: Anthropic API는 HTTPS지만 프록시는 HTTP로 받고 내부에서 SDK로 포워딩
- 스트리밍 응답: Anthropic SDK의 streaming 지원 활용
- 포트 충돌: 9090 사용 중이면 자동으로 다음 포트 탐색

---

## 개발 규칙

- **Electron Only** — web fallback 코드 금지
- `public/index.html` 단일 파일 유지 (외부 .js/.css 파일 생성 금지)
- IPC 추가 시: main.js `ipcMain.handle` + preload.js `contextBridge` 동시 수정
- UI 스타일: VS Code Dark+ 테마 유지 (CSS 변수 --bg, --surface, --blue 등)
- 커밋: 한글, HEREDOC 필수 (`~/.claude/rules/git-rules.md`)
