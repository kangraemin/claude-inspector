---
name: dev-bounce
description: 코드 수정, 기능 구현, 버그 수정, 리팩토링, 파일 변경 등 모든 개발 작업에 반드시 사용해야 하는 구조화된 워크플로우. 사용자가 코드 변경을 요청하면 항상 이 스킬을 먼저 호출할 것. 복잡도에 따라 SIMPLE/NORMAL 모드 자동 분기. plan-gate hook이 이 스킬 없이 코드 수정을 차단하므로 우회 불가.
---

# dev-bounce

복잡도에 따라 두 가지 모드로 분기:
- **SIMPLE**: Main Claude가 직접 계획·개발·검증 (팀/phase/step 없음)
- **NORMAL**: Main Claude 계획 수립 → 승인 → Dev Team → TDD 개발 → 3회 연속 검증

계획 승인 없이는 코드를 수정하지 않는다.

**주의: plan-gate.sh + bash-gate.sh(2-layer)는 아티팩트를 직접 검증합니다. Write/Edit뿐 아니라 Bash를 통한 파일 쓰기도 차단됩니다.**

---

## 컨텍스트 복원 (세션 재시작 시)

아래 Python 스크립트를 **반드시 그대로 실행**하여 활성/미완료 작업을 탐색한다.
git log, 수동 파일 탐색 등으로 대체하지 않는다.

```bash
python3 -c "
import json, os, glob

results = {'active': None, 'incomplete': []}

# 1) .active 파일 스캔
for state_file in sorted(glob.glob('docs/*/*/state.json'), reverse=True):
    task_dir = os.path.dirname(state_file)
    active_file = os.path.join(task_dir, '.active')
    if os.path.isfile(active_file):
        results['active'] = {'task_dir': task_dir, 'state_file': state_file}
        break

# 2) .active 없으면 미완료 작업 스캔
if not results['active']:
    for state_file in sorted(glob.glob('docs/*/*/state.json'), reverse=True):
        try:
            state = json.load(open(state_file))
        except: continue
        phase = state.get('workflow_phase', '')
        if phase in ('done', ''): continue
        task_dir = os.path.dirname(state_file)
        task_name = os.path.basename(task_dir)
        date_dir = os.path.basename(os.path.dirname(task_dir))
        mode = state.get('mode', '?')
        dev_phase = state.get('current_dev_phase', 0)
        total_phases = len(state.get('dev_phases', {}))
        results['incomplete'].append({
            'label': f'{date_dir}/{task_name}',
            'phase': phase, 'mode': mode,
            'dev_phase': dev_phase, 'total_phases': total_phases,
            'task_dir': task_dir
        })

print(json.dumps(results, ensure_ascii=False))
"
```

### 결과 처리 (반드시 따를 것)

**Case A: `active`가 있음**
→ 해당 `state.json` 읽어 `workflow_phase` 확인 후 해당 Phase부터 재개.

**Case B: `active`는 없고 `incomplete`가 1개 이상**
→ **반드시 AskUserQuestion으로 사용자에게 확인** 후 진행. 임의로 선택 금지.

표시 형식:
```
미완료 작업이 발견되었습니다:

1. [2026-03-12/ai-tycoon-reskin] — development (Phase 2/3, NORMAL)
2. [2026-03-10/auth-refactor] — verification (SIMPLE)

이어서 진행할 작업 번호를 선택하세요. 새 작업은 "새로":
```

사용자가 선택하면:
1. 해당 task_dir에 `.active` 파일 재생성
2. `state.json`의 `workflow_phase`부터 재개

**Case C: `active`도 `incomplete`도 없음**
→ 새 작업 시작 (Phase 0부터)

---

## Phase 0: 인텐트 판별

1. intent 에이전트 스폰
2. 요청 원문 전달 → `[INTENT:*]` 수신
3. 처리:
   - `[INTENT:일반응답]` → 일반 응답 후 종료
   - `[INTENT:내용불충분]` → AskUserQuestion으로 개발 내용 구체화 요청 후 Phase 0 재시도
     (예: "어떤 기능/버그를 개발·수정할지 구체적으로 알려주세요.")
     ⚠️ "개발 작업으로 처리할까요?" 같은 yes/no 확인 질문 절대 금지.
   - `[INTENT:개발요청]` → Phase 0-B 진행
4. intent 에이전트 shutdown

### Phase 0-B: 복잡도 판별

`[INTENT:개발요청]` 수신 후 Main Claude가 직접 복잡도 판별.

**기본값은 NORMAL이다.** 아래 조건을 **전부** 충족할 때만 SIMPLE:

| SIMPLE 필수 조건 (전부 충족해야 함) |
|------|
| 변경 파일 1~2개 |
| 문서/설정 수정 또는 단순 버그 수정 (한 줄~수 줄 변경) |
| 새 테스트 케이스 불필요 |
| 구현 방향이 100% 명확 (설계 판단 없음) |

**애매하면 NORMAL.** 조건 하나라도 불확실하면 NORMAL로 분류한다.

판별 후 TASK_DIR 초기화 + state.json 생성:

TASK_DIR 초기화 (Python으로 실행):

1. `TASK_NAME`: 요청에서 핵심 키워드 추출 (예: `user-auth`)
2. `docs_base`: `docs/YYYY-MM-DD/` (프로젝트 로컬)
3. `task_dir`: `{docs_base}/{TASK_NAME}`
4. `.active` 파일 생성 (빈 파일 — hook이 session_id를 자동 claim)
5. `state.json` 생성:

```json
{
  "workflow_phase": "planning",
  "mode": "simple 또는 normal",
  "planning": {"no_question_streak": 0},
  "plan_approved": false,
  "team_name": "",
  "current_dev_phase": 0,
  "current_step": 0,
  "dev_phases": {},
  "verification": {"rounds_passed": 0},
  "task_dir": "docs/YYYY-MM-DD/task-name",
  "active_file": "docs/YYYY-MM-DD/task-name/.active"
}
```

- `mode: simple` → Phase S1 진행
- `mode: normal` → Phase 1 진행

**agent_mode 확인** (config.json에서 읽기):

```bash
python3 -c "
import json
cfg = json.load(open('.claude/ai-bouncer/config.json'))
print(cfg.get('agent_mode', 'team'))
"
```

`agent_mode` 값에 따라 NORMAL 모드의 Phase 1/3/4 동작이 달라진다 (아래 참조).

---

## SIMPLE 모드

### Phase S1: 계획 수립

Main Claude가 직접 수행 (팀 스폰 없음):

1. EnterPlanMode 호출
2. 관련 코드 탐색 (Read/Grep/Glob)
3. 필요시 사용자에게 AskUserQuestion 1~2회
4. `{TASK_DIR}/plan.md` 작성 (plan mode 안에서 Write — plan-gate가 `*/plan.md` 허용, Before/After 필수):
   ```markdown
   # <작업 제목>

   ## 변경 파일별 상세
   ### `파일경로/파일명`
   - **변경 이유**: ...
   - **Before** (현재 코드):
   ```
   현재 코드
   ```
   - **After** (변경 후):
   ```
   변경 코드
   ```
   - **영향 범위**: 이 변경이 영향을 주는 다른 파일/함수

   ## 신규 파일 (있는 경우)
   ### `새파일경로`
   - **용도**: ...
   - **핵심 코드**: ...

   ## 검증
   - 검증 명령어: `실행할 명령어`
   - 기대 결과: 구체적 출력
   ```
   ⚠️ "파일: 변경 내용" 한 줄로 떼우기 금지. 반드시 Before/After 코드 스니펫을 포함해야 한다.
5. plan mode 내부 plan 파일에도 계획 요약 정리 (사용자가 plan mode UI에서 확인)
6. ExitPlanMode 호출 = **사용자 승인 완료** (plan mode UI에서 계획을 확인하고 승인하는 자연스러운 흐름)
7. state.json 업데이트: `plan_approved = true`, `workflow_phase = "development"`

### Phase S2: 개발

> ExitPlanMode 시점에 이미 승인 완료 + state.json 업데이트됨 (Phase S1 Step 6~7).

#### TC 작성 (필수)

승인 후 반드시 `{TASK_DIR}/tests.md`에 TC를 작성한다. TC 스킵 금지.

테이블 + 실행출력 형식으로 작성한다. **실행출력이 비어있으면 검증 미완료로 간주하여 Phase 진행 불가.**

```markdown
| TC | 검증 항목 | 기대 결과 | 상태 |
|----|----------|----------|------|
| TC-01 | <뭘 검증하는지> | <어떤 결과가 나와야 하는지 구체적으로> | ✅/❌/⬜ |
| TC-02 | ... | ... | ⬜ |

## 실행출력

검증 명령어를 실행한 결과를 그대로 붙여넣는다. 어떤 명령을 돌렸고, 실제로 뭐가 나왔는지 증거를 남긴다.

TC-01: <실행한 명령어 또는 확인 방법>
→ <실제 출력 결과>

TC-02: <실행한 명령어>
→ <실제 출력 결과>
```

⬜는 미검증, ✅는 통과, ❌는 실패. 모든 TC가 ✅이고 실행출력이 채워져야 다음 단계 진행 가능.

1. TC 먼저 작성
2. TC 기반으로 코드 개발
3. 개발 완료 후 TC 실행 → tests.md에 실행출력 + 판정(✅/❌) 기록
4. 모든 TC ✅일 때만 Phase S3 진행

Main Claude가 직접 코드 수정 (phase/step 구조 없이 자유롭게).

> SIMPLE 모드에서는 `dev_phases`, `current_dev_phase`, `current_step`을 사용하지 않는다 (빈 객체/0 유지가 정상).
> hook은 SIMPLE 모드에서 이 필드를 검증하지 않는다.

### Phase S3: 검증 + 완료

개발 완료 후:

1. 테스트 실행 (pytest, lint 등) — 1회 통과면 OK
2. 경량 검증: plan.md 대비 실제 변경 확인
   - `{TASK_DIR}/plan.md` 읽어 변경 예정 파일 파악
   - `git diff HEAD~1 --name-only`로 실제 변경 파일 확인
   - 계획됐으나 미변경 파일이 있으면 사용자에게 경고 표시 (차단은 안 함)
   - 간단한 체크리스트 출력:
     ```
     [경량 검증]
     ✅ 테스트 통과
     ✅/⚠️ plan.md 대비 변경 확인: N/M 파일 일치
     (⚠️ 미변경: 파일명 — 의도된 것인지 확인 필요)
     ```
3. active_file 삭제: `rm -f {active_file}`
4. state.json `workflow_phase`를 `"done"`으로 업데이트
5. 사용자에게 완료 보고

---

## NORMAL 모드

### Phase 1: 계획 수립

Main Claude가 직접 수행 (팀 스폰 없음, SIMPLE S1과 동일):

1. EnterPlanMode 호출
2. 관련 코드 탐색 (Read/Grep/Glob)
3. 필요시 사용자에게 AskUserQuestion 1~2회
4. `{TASK_DIR}/plan.md` 작성 (plan mode 안에서 Write — plan-gate가 `*/plan.md` 허용, Before/After 필수):
   ```markdown
   # <작업 제목>

   ## 변경 파일별 상세
   ### `파일경로/파일명`
   - **변경 이유**: ...
   - **Before** (현재 코드):
   ```
   현재 코드
   ```
   - **After** (변경 후):
   ```
   변경 코드
   ```
   - **영향 범위**: ...

   ## 검증
   - 검증 명령어: `실행할 명령어`
   - 기대 결과: 구체적 출력
   ```
   ⚠️ "파일: 변경 내용" 한 줄로 떼우기 금지. 반드시 Before/After 코드 스니펫을 포함해야 한다.
5. plan mode 내부 plan 파일에도 계획 요약 정리 (사용자가 plan mode UI에서 확인)
6. ExitPlanMode 호출 = **사용자 승인 완료**
7. state.json 업데이트: `plan_approved = true`, `workflow_phase = "development"`

> 수정 요청은 plan mode 안에서 처리된다. 사용자가 plan mode UI에서 피드백 → Claude가 plan.md 수정 → 다시 ExitPlanMode.

---

### Phase 3: Dev Team 구성 + 개발

#### 3-1. Lead 에이전트 스폰

**agent_mode별 구성:**

| agent_mode | 동작 |
|---|---|
| `team` | TeamCreate로 Dev Team 생성 후 Lead 스폰. state.json `team_name` = TeamCreate 팀 이름 |
| `subagent` | Agent tool로 Lead 스폰. Lead가 Agent tool로 Dev/QA 스폰. state.json `team_name` = "" (빈 문자열) |
| `single` | Main Claude가 직접 phase 분해 + TDD 루프 수행. phase/step 구조는 유지 (hook 검증용). state.json `team_name` = "" |

**team 모드 (기본):**

TeamCreate로 Dev Team 생성 후 TASK_DIR 전달하여 Lead 스폰.

Lead가 수행:
1. `{TASK_DIR}/plan.md` 읽기
2. 팀 규모 종합 판단 → `[TEAM:duo|team]` 출력
3. 고수준 계획 → 개발 Phase 분해 → `[DEV_PHASES:확정]`
4. state.json `dev_phases` 초기화 + `team_name = '<TeamCreate 팀 이름>'` 설정

> **중요: Lead에게 스폰 시 반드시 다음을 명시할 것:**
> "Lead는 오케스트레이터로서 코드 파일을 직접 Write/Edit/Bash로 수정하지 않는다.
> 코드 구현은 반드시 Dev 에이전트를 스폰하여 위임한다.
> git commit/push도 Lead가 직접 하지 않는다."

**subagent/single 모드**: Lead에게 agent_mode를 전달. team_name은 빈 문자열로 유지.

> **subagent/single 모드 state.json 업데이트 의무:**
>
> team 모드와 동일하게, 다음 시점에 state.json을 반드시 업데이트한다:
> - **Lead**: `dev_phases` 초기화 후 `current_dev_phase = 1`, `current_step = 1` 설정
> - **QA** (또는 Lead가 겸임 시 Lead): Step 테스트 통과 시 `current_step++`
> - **Lead**: Phase 완료 시 `current_dev_phase++`, `current_step = 1` 리셋
>
> plan-gate/bash-gate가 이 카운터와 아티팩트 파일을 모두 검증하므로, 카운터 미업데이트 시 다음 step 코드 수정이 차단된다.
> single 모드에서는 Main Claude가 직접 이 업데이트를 수행한다.

#### 3-2. 팀 구성

| Lead 출력 | 팀 구성 |
|---|---|
| `[TEAM:duo]` | Dev 에이전트 1명 스폰 (QA는 Lead가 겸임) |
| `[TEAM:team]` | Dev + QA 에이전트 각 1명 스폰 |

> NORMAL 모드는 이미 복잡한 작업으로 판별된 상태. 최소 duo부터 시작한다.

#### 3-3. TDD 개발 루프 (Phase/Step 반복)

각 개발 Phase의 각 Step마다:

```
5-1. QA: docs/<task>/phase-N-*/step-M.md에 TC 먼저 작성
     → [STEP:N:테스트정의완료] 출력

5-2. Dev: TC 통과할 최소 코드 구현
          docs/<task>/phase-N-*/step-M.md 구현 내용 업데이트
     → [STEP:N:개발완료]
       빌드 명령: <명령어>
       결과: ✅ 성공

5-3. QA: 테스트 실행
     → [STEP:N:테스트통과]
       명령어: <명령어>
       결과: N/N 통과
     → step-M.md TC 테이블 "실제 결과" 컬럼에 ✅ 기록
     → step-M.md에 "## 실행 결과" 섹션 추가하여 실제 명령어 출력 붙여넣기 (필수)
     → state.json current_step++
     ⚠️ plan-gate가 이전 step의 실행출력 존재를 검증함. 없으면 다음 step 차단.

     실패 시 → Dev에 반려 → 5-2 반복
```

> **phase.md 필수 섹션**: `## 목표`, `## 범위`, `## Steps` — plan-gate가 검증하며 누락 시 코드 수정 차단.

#### 3-4. Step/Phase 완료 시 커밋

`.claude/ai-bouncer/config.json`에서 커밋 전략 확인 (프로젝트 로컬 경로):

```bash
python3 -c "
import json
cfg = json.load(open('.claude/ai-bouncer/config.json'))
print(cfg.get('commit_strategy','per-step'), cfg.get('commit_skill', False))
"
```

| commit_strategy | 커밋 시점 | commit_skill | 커밋 방법 |
|---|---|---|---|
| `per-step` | `[STEP:N:테스트통과]` 직후 | `true` | `/commit` 스킬 호출 |
| `per-step` | `[STEP:N:테스트통과]` 직후 | `false` | `git add` + `git commit` + `git push` |
| `per-phase` | 개발 Phase 마지막 Step 통과 후 | `true` | `/commit` 스킬 호출 |
| `per-phase` | 개발 Phase 마지막 Step 통과 후 | `false` | `git add` + `git commit` + `git push` |
| `none` | — | — | 커밋 스킵 (수동 관리) |

커밋 실패 시 다음 Step 진행 금지 — 원인 해결 후 재시도.

#### 3-5. 블로킹 에스컬레이션

Dev/QA가 구현 불가 또는 기획 질문이 생긴 경우:

```
[STEP:N:블로킹:기술불가] 또는 [STEP:N:블로킹:기획질문]
```

처리:
- `기술불가`: 사용자에게 보고, 범위 변경 필요하면 Phase 1 재시작
- `기획질문`: state.json `workflow_phase = "planning"` 리셋 → Phase 1 재시작

#### 3-6. Phase 완료 처리 (Main Claude 필수 확인)

Lead가 `[PHASE:N:완료]` 또는 `[ALL_STEPS:완료]`를 출력하면, **Main Claude가 반드시 다음을 확인**:

```bash
# state.json에서 남은 Phase 확인
python3 -c "
import json
state = json.load(open('{TASK_DIR}/state.json'))
current = state.get('current_dev_phase', 0)
total = len(state.get('dev_phases', {}))
print(f'current={current} total={total}')
if current < total:
    print(f'NEXT_PHASE={current + 1}')
else:
    print('ALL_DONE')
"
```

**결과에 따라 분기 (반드시 따를 것):**

- `NEXT_PHASE=N` → **Phase 4로 넘어가지 않는다.** Lead에게 "Phase N 개발을 시작하라"고 지시.
  state.json `current_dev_phase`를 N으로 업데이트.
- `ALL_DONE` → 모든 Phase 완료. Phase 4 (검증 루프) 진행.

> **주의**: Lead가 `[ALL_STEPS:완료]`를 출력해도 state.json의 dev_phases에 남은 Phase가 있으면
> **절대 Phase 4로 넘어가지 않는다.** 남은 Phase를 먼저 모두 완료해야 한다.
> Lead가 잘못 판단할 수 있으므로 Main Claude가 직접 dev_phases 개수를 확인한다.

---

### Phase 4: 연속 3회 검증 루프

Phase 4 시작 전 state.json `workflow_phase`를 `"verification"`으로 업데이트.
(completion-gate.sh가 verification 상태에서 3회 연속 통과 전 응답 종료를 차단)

**agent_mode별 구성:**

| agent_mode | 동작 |
|---|---|
| `team` | verifier 에이전트 스폰 (기본) |
| `subagent` | Agent tool로 verifier 스폰 |
| `single` | Main Claude가 직접 3회 검증 수행 |

1. verifier 에이전트 스폰 (TASK_DIR 전달)
2. verifier가 검증 루프 실행

3. `[VERIFICATION:N:실패:PHASE-P-STEP-M]` 수신 시 (hook 강제 흐름):
   - verifier가 자동으로: workflow_phase → "development", 실패 step ✅→❌, failure_count +1
   - **plan-gate가 verification 재진입을 자동 차단** (step에 ✅ 없으므로)
   - Main Claude가 Dev에게 실패한 Step 재작업 지시
   - Dev가 수정 완료 → step.md에 ✅ 복구
   - Main Claude가 workflow_phase → "verification" 재설정
   - verifier에게 "재검증 시작" 요청 (Round 1부터)

4. `[VERIFICATION:ESCALATION]` 수신 시 (failure_count >= 3):
   - AskUserQuestion으로 사용자에게 보고
   - 사용자 승인 없이 재시도 금지

5. `[DONE]` 수신 (verifications/round-*.md 3개 연속 통과):
   - verifier + 전체 팀 shutdown
   - active_file 삭제: `rm -f {active_file}`
   - state.json `workflow_phase`를 `"done"`으로 업데이트
     ⚠️ task_dir 자체는 절대 삭제하지 않는다. 모든 문서 보존.
   - 사용자에게 완료 보고

---

## 주의사항

- plan-gate.sh는 아티팩트(파일/팀 디렉토리)를 직접 검증합니다. state.json 플래그 조작으로 gate를 우회할 수 없습니다.
- 2-layer Bash 방어: bash-gate.sh(PreToolUse)가 쓰기 패턴을 감지하여 사전 차단하고,
  bash-audit.sh(PostToolUse)가 git diff로 모든 파일 변경을 감지하여 무단 변경을 자동 복원합니다.
  어떤 방법으로든 Bash를 통한 gate 우회는 100% 차단됩니다.
- SIMPLE 모드에서는 team/phase/step 검증을 건너뛰지만, `plan_approved` 검증은 유지됩니다.
- `[PLAN:승인됨]` 없이 코드 수정 시도 → plan-gate.sh / bash-gate.sh가 차단
- NORMAL 모드: 이전 Step의 step-M.md에 ✅가 없으면 다음 Step 코드 수정 → plan-gate.sh / bash-gate.sh가 차단
- 검증 미완료(NORMAL: round-*.md 3개 연속 통과) 상태에서 응답 종료 → completion-gate.sh가 차단
- 커밋: 로컬 `.claude/rules/git-rules.md` 우선, 없으면 `~/.claude/rules/git-rules.md`
- 완료 후 task_dir 삭제 금지 — active_file(`docs/YYYY-MM-DD/<task>/.active`)만 삭제한다
- 세션 격리: `.active` 파일은 `docs/YYYY-MM-DD/<task>/.active`에 위치하며 session_id를 저장. hook이 자동으로 claim한다.
- docs 구조: `docs/YYYY-MM-DD/task-name/` — 날짜별로 태스크 문서를 구조화
- config.json 경로: `.claude/ai-bouncer/config.json` (프로젝트 로컬)
- `enforcement_mode=prompt-only`일 때 hook이 없으므로 프롬프트 규칙만으로 워크플로우를 준수해야 한다. 차단이 아닌 가이드 역할.
- `agent_mode`에 따라 Phase 3/4의 에이전트 스폰 방식이 달라진다. config.json에서 확인 후 분기. Phase 1(계획 수립)은 항상 Main Claude가 직접 수행.
