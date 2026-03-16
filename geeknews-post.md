# Claude Inspector - Claude Code가 API에 실제로 뭘 보내는지 보여주는 도구

Claude Code를 쓰면서 "이게 내부적으로 API에 뭘 보내는 거지?" 라는 궁금증에서 시작한 macOS 데스크탑 앱.

Claude Code는 Anthropic SDK의 `ANTHROPIC_BASE_URL` 환경변수를 지원하는데, 이걸 `http://localhost:9090`으로 지정하면 모든 API 요청이 Inspector 프록시를 경유함.
프록시는 요청을 캡처해서 UI에 보여준 뒤, 그대로 `api.anthropic.com`으로 포워딩.
SSE 스트림 응답도 재조립해서 완전한 응답 객체로 시각화해줌.

실제 트래픽을 까보면서 발견한 것들:

**1. CLAUDE.md는 매 요청마다 주입됨**
`hello` 한 마디 쳤는데 앞에 ~12KB가 자동으로 붙어서 전송됨.
글로벌 CLAUDE.md(`~/.claude/CLAUDE.md`), 프로젝트 CLAUDE.md, 글로벌 rules, 그리고 memory까지 전부 합쳐서 ~10KB.
memory는 Claude Code가 세션 간 기억해야 할 내용을 자동으로 저장하는 파일임.
여기에 사용 가능한 스킬 목록(~2KB)까지 더해져서 총 ~12KB.
이 페이로드가 매 요청마다 반복되기 때문에, CLAUDE.md가 길수록 매번 토큰을 더 소비함.
500줄짜리 CLAUDE.md를 쓰고 있다면 매 API 호출마다 그만큼 조용히 태우고 있는 셈.

**2. MCP 도구는 지연 로드됨**
빌트인 27개 도구는 매번 전체 JSON 스키마가 전송됨.
반면 MCP 도구는 처음에 이름만 존재하다가, 모델이 `ToolSearch`를 호출하면 그때 스키마가 추가됨.
`tools[]` 배열이 27 → 29 → 35로 늘어나는 걸 실시간으로 확인 가능.
사용하지 않는 MCP 도구는 토큰을 소비하지 않는다는 뜻.

**3. 이미지는 base64로 JSON에 직접 포함됨**
스크린샷을 읽으면 base64 인코딩된 문자열로 JSON 본문에 직접 삽입됨.
스크린샷 한 장에 수백 KB가 요청 페이로드에 추가되므로, 이미지를 자주 읽히면 페이로드가 급격히 커짐.

**4. Skill과 Command는 완전히 다른 주입 경로**
`/something`을 입력하면 겉보기엔 비슷하지만, 내부적으로 세 가지 완전히 다른 메커니즘이 작동함.

`/clear`, `/mcp` 같은 **로컬 커맨드**는 로컬에서 실행되고 그 결과만 `<local-command-stdout>` 태그로 모델에 전달됨.
프롬프트 자체는 주입되지 않아서 이후 요청에 영향 없음.

`/commit` 같은 **사용자 스킬**은 완전히 다름.
스킬이 트리거되면 해당 스킬의 전체 프롬프트 텍스트가 user message에 그대로 주입됨.
문제는 이게 한 번 들어가면 세션이 끝날 때까지 `messages[]` 배열에 계속 남는다는 것.
이후 모든 API 요청에 스킬 프롬프트가 매번 재전송됨.

그리고 **어시스턴트 스킬**이라는 세 번째 경로도 있음.
모델이 스스로 `Skill("finish")` 같은 도구를 호출하는 건데, 이건 `tool_use` → `tool_result` 흐름으로 주입됨.
사용자 스킬과 마찬가지로 전체 프롬프트가 들어가고 세션 끝까지 남음.

**5. 이전 메시지가 계속 쌓임**
Claude Code는 `messages[]` 배열 전체를 매번 재전송함.
내가 입력한 메시지뿐 아니라, Claude가 답변한 내용(thinking, tool_use, 텍스트 응답)도 전부 `messages[]`에 포함됨.
CLAUDE.md가 매 턴마다 포함되기 때문에 30턴 = CLAUDE.md 30개 복사본 + Claude 응답 30개.
누적 전송량으로 보면 10턴에 ~200KB, 30턴이면 ~1MB+.

누적될수록 문제가 생김:
- 요청당 입력 토큰이 늘어나 API 비용 증가
- 컨텍스트 윈도우 한계에 도달하면 이전 메시지가 자동 압축되어 세부 내용 유실
- 페이로드가 클수록 응답 속도 저하

`/clear`로 정리하지 않으면 계속 누적됨.

**6. 서브 에이전트는 완전히 격리됨**
`Agent` 도구로 생성된 서브 에이전트는 별도의 API 호출로 실행됨.
부모의 대화 이력이 전혀 전달되지 않고, 작업 프롬프트만 받음.
도구 세트도 새로 구성되고 컨텍스트도 0에서 시작.
Inspector에서 부모와 서브 에이전트 호출을 나란히 비교할 수 있음.

GitHub: https://github.com/kangraemin/claude-inspector?tab=readme-ov-file#homebrew-recommended
