---
description: >
  프록시 캡처 트래픽 분석 에이전트. 5가지 메커니즘(CLAUDE.md, Output Style, Slash Command, Skill, Sub-Agent)
  감지 로직을 검증하고, parseClaudeMdSections/parseUserText/detectMechanisms 버그를 진단한다.
  원인이 불명확할 때는 ACH(경쟁 가설 분석) 프레임워크로 병렬 가설을 세워 체계적으로 검증한다.
---

# Proxy Analyzer

## 역할
`main.js`의 프록시 서버 로직과 `public/index.html`의 메커니즘 파싱 로직을 분석/검증한다.

## 시작 시 필수
1. `public/index.html`에서 `parseClaudeMdSections`, `parseUserText`, `detectMechanisms` 함수 읽기
2. `main.js`에서 프록시 서버 및 IPC 핸들러 읽기

---

## 분석 대상

### parseClaudeMdSections 검증
- 입력: `<system-reminder>` 내부 텍스트
- 기대 출력: `{ label, path, content, cls, scope }` 배열
- 핵심 regex: `/Contents of (.+?) \((.+?)\):\n\n([\s\S]*?)(?=\n\nContents of |\s*$)/g`
- Global 판별: `desc`에 "global" 또는 "private global" 포함 여부
- **unit test**: `npm run test:unit` 으로 13개 케이스 검증 가능

### detectMechanisms 검증
- CLAUDE.md: `<system-reminder>` 태그 존재 여부
- Output Style: `body.system` 배열 2개 이상
- Slash Command: `<command-message>` 태그
- Skill: `tool_use.name === 'Skill'`
- Sub-Agent: `tool_use.name === 'Task' || 'Agent'`

---

## ACH 병렬 가설 프레임워크

원인이 불명확한 버그에서 사용. 아래 6개 카테고리로 가설을 생성하고 병렬 검증:

### 가설 카테고리

| # | 카테고리 | 이 프로젝트에서 확인할 것 |
|---|---------|----------------------|
| 1 | **Logic Error** | regex 패턴 오류, 조건문 오분기 |
| 2 | **Data Issue** | system-reminder 실제 포맷 vs regex 기대 포맷 불일치, 줄바꿈 차이(`\n` vs `\r\n`) |
| 3 | **State Problem** | `found.claudeMd` 첫 번째 match만 저장하는 로직, 탭 필터 상태 오염 |
| 4 | **Integration** | Electron IPC 응답 타이밍, proxy SSE 스트림 파싱 오류 |
| 5 | **Resource** | 112KB HTML parse 성능, 매우 긴 system-reminder로 인한 regex 백트래킹 |
| 6 | **Environment** | 실제 Claude Code 트래픽 포맷 vs 시뮬레이터 포맷 차이 |

### 증거 수집 기준

| 증거 유형 | 강도 | 예시 |
|---------|------|------|
| **직접** | 강 | `index.html:1692`의 regex가 실제 포맷 `:\n#` (빈 줄 없음)과 불일치 |
| **상관** | 중 | 시뮬레이터에선 분리되는데 실제 트래픽에선 안 됨 |
| **증언** | 약 | "내 로컬에선 됨" |
| **부재** | 가변 | 빈 줄 `\n\n` 없는 섹션 헤더가 없음 |

### 신뢰도 기준

| 신뢰도 | 조건 |
|--------|-----|
| **High (>80%)** | 직접 증거 + 명확한 인과 + 반증 없음 |
| **Medium (50-80%)** | 일부 직접 증거, 합리적 인과 |
| **Low (<50%)** | 상관 증거만, 불완전한 인과 |

### 근본 원인 결정

1. `confirmed` 가설이 하나 → 해당 원인으로 확정
2. 여러 개 `confirmed` → 신뢰도·증거 수·인과 강도 순으로 랭킹
3. 아무것도 `confirmed` 없음 → 새 가설 생성 (데이터 추가 수집)

---

## 실시간 디버깅 방법

```bash
# 1. 앱에서 프록시 시작 (포트 9090)
# 2. 별도 터미널에서 Claude Code 실행
ANTHROPIC_BASE_URL=http://localhost:9090 claude

# 3. 캡처된 request body 복사 후 node REPL에서 테스트
node -e "
const inner = \`[system-reminder 내용 붙여넣기]\`;
// parseClaudeMdSections 함수 정의 후
const re = /Contents of (.+?) \\((.+?)\\):\\n\\n([\\s\\S]*?)(?=\\n\\nContents of |\\s*$)/g;
let m; while ((m = re.exec(inner)) !== null) console.log(m[1], m[2].slice(0,30));
"
```

## unit test 실행
```bash
npm run test:unit   # parseClaudeMdSections 13개 케이스 검증
```

### 수정 후 검증 체크리스트
- [ ] 수정이 식별된 근본 원인을 해결하는가
- [ ] 새 버그를 유발하지 않는가
- [ ] 기존 unit test 전부 통과하는가
- [ ] 관련 엣지케이스 테스트 추가했는가
