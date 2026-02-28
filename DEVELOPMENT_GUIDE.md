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

## 목표 기능 (다음 작업)

### P0 — 즉시 필요
1. **server.ts 제거** — web 모드 완전 삭제, package.json 정리
2. **토큰 카운터** — 페이로드 전송 전 예상 토큰 수 표시 (claude-tokenizer or tiktoken)
3. **파일 불러오기** — Electron dialog로 실제 CLAUDE.md 파일 불러오기
4. **Markdown 응답 렌더링** — response 패널에서 marked.js로 렌더링

### P1 — 핵심 UX
5. **코드 내보내기** — 페이로드를 cURL / Python / TypeScript 스니펫으로 복사
6. **요청 히스토리** — 최근 10개 실험 저장, 클릭하면 복원
7. **페이로드 크기 표시** — JSON 크기 (KB) 실시간 표시

### P2 — 심화
8. **응답 비교** — 두 응답을 나란히 비교
9. **CLAUDE.md @file 확장 미리보기** — @file.md 참조 시 실제 내용 포함 미리보기
