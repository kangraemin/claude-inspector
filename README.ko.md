<div align="center">

# Claude Inspector

**Claude Code가 API에 실제로 무엇을 보내는지 확인하세요.**

Claude Code CLI 트래픽을 실시간으로 가로채<br>
5가지 프롬프트 증강 메커니즘을 모두 시각화하는 MITM 프록시.

[시작하기](#시작하기) · [배울 수 있는 것들](#배울-수-있는-것들) · [프록시 모드](#-프록시-모드) · [동작 원리](#동작-원리)

[English](README.md) | **한국어**

</div>

---

<p align="center">
  <img src="public/screenshots/proxy-request-ko.png" width="100%" alt="Proxy — CLAUDE.md Global/Local 섹션 칩과 인라인 텍스트 하이라이트가 표시된 Request 뷰" />
</p>

<p align="center">
  <img src="public/screenshots/proxy-analysis-ko.png" width="100%" alt="Proxy — 5가지 메커니즘을 자동 감지하고 섹션 내용을 보여주는 Analysis 뷰" />
</p>

## 배울 수 있는 것들

아래 내용은 모두 Claude Inspector로 **실제 캡처된 트래픽**을 분석해 발견한 것입니다.

### 1. "hello"라고 입력하면 — Claude는 이 전체 JSON을 받는다

한 단어를 보내도 API는 64개 이상의 메시지, 3개의 system 블록, 27개 이상의 도구 스키마, 숨겨진 메타데이터가 담긴 JSON 페이로드를 받습니다. 이것은 **실제 Claude Code 세션에서 캡처한 데이터**입니다:

```json
{
  "model": "claude-sonnet-4-6",
  "max_tokens": 32000,
  "thinking": { "type": "adaptive" },
  "stream": true,
  "context_management": {
    "edits": [{ "type": "clear_thinking_20251015", "keep": "all" }]
  },
  "metadata": {
    "user_id": "user_003619f3...9c_account_e4008a49-..._session_cdc418a2-..."
  },
  "system": [ ...3 blocks... ],        // #4 참조
  "tools": [ ...29 schemas... ],       // 빌트인 27개 + 이미 로드된 MCP 2개 (#5 참조)
  "messages": [ ...64 items... ]       // 전체 대화가 매 턴마다 재전송됨
}
```

**각 필드가 보여주는 것:**

- **`messages[]`에 64개 항목** — 전체 대화 히스토리가 매 API 호출마다 재전송됩니다. 1턴이면 1개, 10턴이면 10개, 64턴이면 64개 전부. 대화가 길어질수록 토큰 비용이 기하급수적으로 증가합니다.
- **`metadata.user_id`** — 한 문자열에 세 ID가 인코딩됩니다: `user_<64자 hex>` + `account_<UUID>` + `session_<UUID>`. Anthropic은 이 하나의 필드로 개별 메시지, 계정, 세션을 모두 추적할 수 있습니다.
- **`thinking.type: "adaptive"`** (Sonnet) — 요청마다 동적으로 thinking 사용 여부를 결정합니다. **Opus**는 `"enabled" + budget_tokens: 31999`로 항상 최대 예산을 할당합니다.
- **`context_management`** — 공개 API 스펙에 없는 비공개 객체입니다. `clear_thinking_20251015` 편집 지시는 컨텍스트가 길어질 때 thinking 블록을 어떻게 처리할지 API에 알려줍니다.
- **`tools[]`에 29개** — 빌트인 27개 + 이 세션에서 이미 지연 로드된 MCP 2개. MCP 도구를 사용할수록 이 숫자가 늘어납니다.

### 2. CLAUDE.md는 매 턴마다 여러 개의 이름 붙은 섹션으로 주입된다

모든 user 메시지는 실제로 3개의 content 블록으로 구성됩니다. 직접 입력한 텍스트는 `content[2]`뿐이고, 나머지 두 개는 Claude Code가 자동으로 앞에 붙입니다:

```json
{
  "role": "user",
  "content": [
    // [0] Claude Code가 주입하는 스킬 목록
    { "type": "text", "text": "<system-reminder>\nThe following skills are available...\n</system-reminder>" },

    // [1] 모든 CLAUDE.md + rules + memory + 날짜 — 이 캡처에서 8,528자
    { "type": "text", "text": "<system-reminder>\n
        Contents of /Users/you/.claude/CLAUDE.md (user's private global instructions):\n...
        Contents of /Users/you/.claude/rules/git-rules.md (user's private global instructions):\n...
        Contents of /Users/you/project/.claude/CLAUDE.md (project instructions):\n...
        Contents of /Users/you/project/.claude/memory/MEMORY.md (auto-memory):\n...
        currentDate: 2026-03-01
      \n</system-reminder>" },

    // [2] 실제로 입력한 내용
    { "type": "text", "text": "hello" }
  ]
}
```

**주입 순서는 항상 고정:** 글로벌 CLAUDE.md → 글로벌 rules 파일 → 로컬 CLAUDE.md → 자동 메모리 → `currentDate`.

**왜 비용이 배가 되는가:** Claude Code는 매 API 호출마다 `messages[]` 배열 **전체**를 재전송합니다. 대화가 30턴이라면, 8,500자 분량의 CLAUDE.md가 페이로드 안에 30번 등장합니다 — `messages[0]`에 한 번씩 포함되어서요. 500줄짜리 CLAUDE.md는 모든 요청마다, 영원히, 토큰을 소모합니다. 간결하게 유지하세요.

### 3. 32,000 토큰 중 31,999개가 thinking에 할당된다

모든 assistant 응답에는 CLI에서 볼 수 없는 숨겨진 `thinking` 블록이 포함됩니다. 64개 메시지 캡처에서 **31개의 assistant 턴 중 16개**에 thinking 블록이 있었습니다:

```json
{
  "role": "assistant",
  "content": [
    { "type": "thinking",
      "thinking": "The user wants to start inspection using the dev skill. Let me invoke the dev skill.",
      "signature": "Eu0BCkYICxgCKkDLtz8rLXrByzrD..." },
    { "type": "tool_use",
      "name": "Skill",
      "input": { "skill": "dev" } }
  ]
}
```

- **Opus**: `budget_tokens: 31999` / `max_tokens: 32000` — 출력 예산의 거의 전부가 thinking에 할당됩니다. 사람 눈에 보이는 응답엔 토큰이 1개만 남습니다.
- **Sonnet**: `"type": "adaptive"` — 요청의 복잡도에 따라 thinking 예산을 동적으로 조절합니다.
- **`signature`** — thinking 내용에 대한 암호화 서명입니다. 악의적인 콘텐츠가 thinking 블록을 위조하거나 수정하려는 프롬프트 인젝션 공격을 방지합니다.
- **터미널에서는 보이지 않지만** 캡처된 트래픽에는 그대로 기록됩니다 — Claude Inspector의 Messages 탭에서 확인할 수 있습니다. 복잡한 지시에도 정확한 도구 호출이 가능한 이유가 바로 이것입니다.

### 4. 시스템 프롬프트: 캐싱되는 3개의 블록

`system` 필드는 단순 문자열이 아니라 **3개 블록의 배열**이며, 각 블록마다 캐싱 전략이 다릅니다:

```json
"system": [
  // [0] 80자 — cache_control 없음 (항상 새로 계산 — CLI 버전마다 변경됨)
  { "text": "x-anthropic-billing-header: cc_version=2.1.63.a43; cc_entrypoint=cli; cch=edd82;" },

  // [1] 57자 — 1시간 캐시
  { "text": "You are Claude Code, Anthropic's official CLI for Claude.",
    "cache_control": { "type": "ephemeral", "ttl": "1h" } },

  // [2] 15,359자 — 1시간 캐시
  { "text": "You are an interactive agent that helps users with software engineering tasks...",
    "cache_control": { "type": "ephemeral", "ttl": "1h" } }
]
```

**왜 3개로 나누는가?** 프롬프트 캐싱은 캐시 경계가 안정적이어야 작동합니다. CLI 버전마다 바뀌는 빌링 헤더를 블록 `[0]`으로 분리하면, 블록 `[1]`과 `[2]`가 독립적으로 캐시될 수 있습니다.

**블록 `[2]`에는 모든 것이 들어 있습니다** — 전체 행동 규칙, 27개 도구 스키마 설명, 현재 환경 정보(OS, 쉘, 모델명, 날짜), git 상태, MCP 서버 설명까지. 15,359자 분량이지만 캐싱 덕분에 매 요청마다 전송되어도 **캐시 만료 후 첫 요청만** 전체 처리 비용을 냅니다. 이후 1시간 이내 요청은 캐시 읽기 할인이 적용됩니다.

### 5. MCP 도구는 토큰 절약을 위해 지연 로드된다

27개의 빌트인 도구(`Read`, `Bash`, `Edit`, `Glob`, `Grep`, `Agent`...)는 매 요청마다 **전체 JSON 스키마**와 함께 전송됩니다. 하지만 **MCP 도구는 그렇지 않습니다** — 처음에는 이름 목록만 존재합니다:

```json
{
  "name": "ToolSearch",
  "description": "...Available deferred tools (must be loaded before use):\nmcp__til-server__create_til\nmcp__til-server__update_til\n..."
}
```

**2단계 지연 로드 흐름:**

1. `system[]` 블록의 "MCP Server Instructions" 섹션에서 각 서버의 목적을 설명합니다 (*"Use context7 to retrieve up-to-date documentation"*)
2. 모델이 설명을 읽고 MCP 도구가 필요하다고 판단합니다
3. 모델이 `ToolSearch`를 쿼리로 호출 → 전체 스키마가 반환되어 `tools[]`에 추가됩니다
4. 모델이 실제 MCP 도구를 호출합니다

**이 캡처에서의 전/후:** `ToolSearch`에 8개의 MCP 도구가 지연 도구로 등록되어 있습니다. 하지만 `mcp__context7__resolve-library-id`와 `mcp__context7__query-docs`는 세션 앞부분에서 이미 로드되어 `tools[]`에 포함됩니다 → 총 29개(빌트인 27개 + 로드된 MCP 2개). `til-server` 6개는 아직 필요하지 않아 지연 상태입니다.

사용하지 않는 MCP 스키마는 토큰을 전혀 소비하지 않는 것이 핵심입니다.

## 시작하기

```bash
git clone https://github.com/kangraemin/claude-inspector.git
cd claude-inspector
npm install
npm start
```

## 🔌 프록시 모드

로컬 MITM 프록시를 통해 **실제** Claude Code CLI 트래픽을 인터셉트합니다.

```
Claude Code CLI  →  Inspector (localhost:9090)  →  api.anthropic.com
```

**1.** 앱에서 **Start Proxy** 클릭<br>
**2.** 프록시를 통해 Claude Code 실행:

```bash
ANTHROPIC_BASE_URL=http://localhost:9090 claude
```

**3.** 모든 API 요청/응답이 실시간으로 캡처됩니다.

### 할 수 있는 것들

| 탭 | 설명 |
|-----|-------------|
| **Messages** | role별로 `messages[]` 탐색 — user/assistant/system 필터, 전체 텍스트 검색(`Cmd+F`) |
| **Request** | 접고 펼 수 있는 트리 형태의 원시 요청 JSON; CLAUDE.md 칩을 파일별로 분리(Global CLAUDE.md, Global Rules, Local CLAUDE.md, Memory) — 칩 클릭 시 해당 섹션 인라인 하이라이트 |
| **Response** | SSE 스트림 자동 재조립을 포함한 전체 응답 |
| **Analysis** | 5가지 메커니즘 자동 감지, 주입된 각 섹션의 내용을 구문 강조와 함께 표시 — 칩 클릭 시 해당 섹션으로 이동 |

## 동작 원리

Claude Code는 모든 API 호출에 최대 **5가지 프롬프트 증강 메커니즘**을 적용합니다 — 하지만 일반적인 사용 중에는 보이지 않습니다.

| 메커니즘 | 주입 위치 | 상세 |
|-----------|----------------|--------|
| **CLAUDE.md** | `messages[].content` → `<system-reminder>` | 글로벌 + 로컬 CLAUDE.md, rules 파일, memory — 각각 이름 붙은 섹션으로 나열 |
| **Output Style** | `system[]` 추가 블록 | `/output` 스타일 설정 시 추가됨 |
| **Slash Command** | `messages[].content` → `<command-message>` | 메시지 앞에 커맨드 프롬프트 주입 |
| **Skill** | Skill `tool_use` 이후 `tool_result` | 도구 결과 흐름을 통해 반환되는 스킬 내용 |
| **Sub-Agent** | Task 도구를 통한 별도의 격리된 API 호출 | 완전히 독립적인 API 호출 생성 |

Claude Inspector는 Claude Code와 Anthropic API 사이에 위치해 전체 요청/응답 페이로드를 캡처합니다 — 무엇이 어디에 주입되는지 정확히 확인할 수 있습니다.

> **프라이버시**: 모든 트래픽은 내 컴퓨터에만 머뭅니다. 프록시는 `localhost`에서만 실행됩니다. `api.anthropic.com`으로 직접 전송되는 것 외에 어디에도 데이터를 보내지 않습니다.

## 기술 스택

- **Electron** — 크로스플랫폼 데스크탑 (macOS `hiddenInset` 타이틀바)
- **Vanilla JS** — 프레임워크 없음, 빌드 단계 없음
- **Node `http`/`https`** — SSE 스트림 재조립이 포함된 경량 MITM 프록시
- **highlight.js** + **marked** — 구문 강조 및 마크다운 렌더링

## 빌드

```bash
npm run dist         # .dmg + .exe
npm run dist:mac     # macOS only (arm64 + x64)
npm run dist:win     # Windows only (NSIS)
```

## 관련 자료

[Reverse Engineering Claude Code — How Skills Different from Agents, Commands, and Styles](https://levelup.gitconnected.com/reverse-engineering-claude-code-how-skills-different-from-agents-commands-and-styles-b94f8c8f9245) 연구를 기반으로 제작되었습니다.

## 라이선스

MIT
