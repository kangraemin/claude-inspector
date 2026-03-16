#!/bin/bash
# bash-gate: PreToolUse hook (Layer 1)
# Bash 도구로 파일 쓰기 우회 차단 — 쓰기 패턴 휴리스틱 감지

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Bash만 체크
[ "$TOOL" != "Bash" ] && exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
[ -z "$CMD" ] && exit 0

# 세션 격리: session_id 추출
export SESSION_ID
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

# --- ai-bouncer start ---

# 1. Fast exit: 쓰기 패턴 미포함 → exit 0 (git commit/push는 제외)
# fd redirect (2>/dev/null, 1>&2 등) 제거 후 검사 — 오탐 방지
CMD_CLEAN=$(echo "$CMD" | sed -E 's/[0-9]+>\/dev\/null//g; s/[0-9]+>[&]?[0-9]*//g')
if ! echo "$CMD_CLEAN" | grep -qE '>[^&]|>>|\btee\b|\bsed\b.*-i|\bcp\b|\bmv\b|\btouch\b|\bdd\b.*of=|\bpython|\bnode\b.*-e|\bruby\b.*-e|\bperl\b.*-e|\brm\b|\brmdir\b|\bunlink\b|\bcurl\b.*(-o|--output)|\bwget\b'; then
  # 쓰기 패턴 없지만 git commit/push면 commit_strategy 검증 필요
  if echo "$CMD" | grep -qE '^\s*git\s+(commit|push)\b'; then
    :
  else
    exit 0
  fi
fi

# 2. git 명령어 분기
if echo "$CMD" | grep -qE '^\s*git\b'; then
  # git commit/push → commit_strategy 검증 (아래 블록)
  if echo "$CMD" | grep -qE '\bgit\s+(commit|push)\b'; then
    :
  else
    # 나머지 git 명령 (status, add, diff 등) → 통과
    exit 0
  fi
fi

# 2-1. commit_strategy 검증 (git commit/push)
if echo "$CMD" | grep -qE '^\s*git\s+(commit|push)\b'; then
  REPO_ROOT_CS=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
  CONFIG_CS="$REPO_ROOT_CS/.claude/ai-bouncer/config.json"

  # config.json 없으면 통과
  [ ! -f "$CONFIG_CS" ] && exit 0

  COMMIT_STRATEGY=$(jq -r '.commit_strategy // "per-step"' "$CONFIG_CS" 2>/dev/null || echo "per-step")

  # none → 항상 block
  if [ "$COMMIT_STRATEGY" = "none" ]; then
    jq -n '{decision:"block", reason:"⛔ [bash-gate] commit_strategy=none: 커밋이 차단됩니다. 수동 관리 모드."}'
    exit 0
  fi

  # .active 탐색 (resolve-task.sh)
  SCRIPT_DIR_CS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR_CS/lib/resolve-task.sh"

  # .active 없으면 gate 비활성 → 통과
  [ -z "$TASK_NAME" ] && exit 0

  # state.json 없으면 통과
  [ -f "$STATE_FILE" ] || exit 0

  CS_WORKFLOW=$(jq -r '.workflow_phase // "done"' "$STATE_FILE" 2>/dev/null)
  CS_MODE=$(jq -r '.mode // "normal"' "$STATE_FILE" 2>/dev/null)

  # done → 항상 허용
  [ "$CS_WORKFLOW" = "done" ] && exit 0

  # verification → 모든 Phase 완료 시만 허용 (plan-gate CHECK 6.8 동등)
  if [ "$CS_WORKFLOW" = "verification" ] && [ "$CS_MODE" = "normal" ]; then
    DEV_PHASES_COUNT=$(jq '.dev_phases | length' "$STATE_FILE" 2>/dev/null)
    DEV_PHASES_COUNT=${DEV_PHASES_COUNT:-0}
    if [ "$DEV_PHASES_COUNT" -gt 0 ]; then
      ALL_DONE=true
      for pidx in $(seq 1 "$DEV_PHASES_COUNT"); do
        PFOLDER=$(jq -r ".dev_phases[\"$pidx\"].folder // \"\"" "$STATE_FILE" 2>/dev/null)
        [ -z "$PFOLDER" ] && PFOLDER="phase-${pidx}"
        PDIR="${TASK_DIR}/${PFOLDER}"
        HAS_STEPS=false
        for sf in "$PDIR"/step-*.md; do
          [ -f "$sf" ] || continue
          HAS_STEPS=true
          if ! grep -q '✅' "$sf" 2>/dev/null; then
            ALL_DONE=false
            break 2
          fi
        done
        if [ "$HAS_STEPS" = false ]; then
          ALL_DONE=false
          break
        fi
      done
      if [ "$ALL_DONE" = false ]; then
        jq -n --arg count "$DEV_PHASES_COUNT" '{
          decision: "block",
          reason: ("⛔ [bash-gate] verification이지만 미완료 Phase 존재. 개발을 먼저 완료하세요. (총 " + $count + "개 Phase)")
        }'
        exit 0
      fi
    fi
    exit 0
  fi

  # verification (simple) → 허용
  [ "$CS_WORKFLOW" = "verification" ] && exit 0

  # planning → block
  if [ "$CS_WORKFLOW" = "planning" ]; then
    jq -n '{decision:"block", reason:"⛔ [bash-gate] planning 단계에서는 커밋할 수 없습니다."}'
    exit 0
  fi

  # simple 모드 → development이면 허용 (step 검증 없음)
  if [ "$CS_MODE" = "simple" ]; then
    exit 0
  fi

  # --- NORMAL 모드 + development ---
  CS_PHASE=$(jq -r '.current_dev_phase // 0' "$STATE_FILE" 2>/dev/null)
  CS_STEP=$(jq -r '.current_step // 0' "$STATE_FILE" 2>/dev/null)
  CS_PHASE_FOLDER=$(jq -r ".dev_phases[\"$CS_PHASE\"].folder // \"\"" "$STATE_FILE" 2>/dev/null)

  [ -z "$CS_PHASE_FOLDER" ] && exit 0

  if [ "$COMMIT_STRATEGY" = "per-step" ]; then
    STEP_FILE_CS="${TASK_DIR}/${CS_PHASE_FOLDER}/step-${CS_STEP}.md"
    if [ -f "$STEP_FILE_CS" ] && grep -q '✅' "$STEP_FILE_CS" 2>/dev/null; then
      exit 0
    fi
    jq -n --arg p "$CS_PHASE" --arg s "$CS_STEP" \
      '{decision:"block", reason:("⛔ [bash-gate] commit_strategy=per-step: Phase " + $p + " Step " + $s + " 미완료. 테스트 통과 후 커밋하세요.")}'
    exit 0
  fi

  if [ "$COMMIT_STRATEGY" = "per-phase" ]; then
    STEP_COUNT_CS=$(jq -r ".dev_phases[\"$CS_PHASE\"].steps | length" "$STATE_FILE" 2>/dev/null)
    if [ "${STEP_COUNT_CS:-0}" -le 0 ] 2>/dev/null; then
      jq -n --arg p "$CS_PHASE" \
        '{decision:"block", reason:("⛔ [bash-gate] commit_strategy=per-phase: Phase " + $p + "에 Step이 없습니다. Step을 먼저 생성하세요.")}'
      exit 0
    fi
    LAST_STEP_CS=$(jq -r ".dev_phases[\"$CS_PHASE\"].steps | keys | map(tonumber) | max" "$STATE_FILE" 2>/dev/null)
    LAST_STEP_FILE_CS="${TASK_DIR}/${CS_PHASE_FOLDER}/step-${LAST_STEP_CS}.md"
    if [ -f "$LAST_STEP_FILE_CS" ] && grep -q '✅' "$LAST_STEP_FILE_CS" 2>/dev/null; then
      exit 0
    fi
    jq -n --arg p "$CS_PHASE" --arg ls "$LAST_STEP_CS" \
      '{decision:"block", reason:("⛔ [bash-gate] commit_strategy=per-phase: Phase " + $p + " 마지막 Step " + $ls + " 미완료. Phase 완료 후 커밋하세요.")}'
    exit 0
  fi

  # 알 수 없는 strategy → 통과 (하위 호환)
  exit 0
fi

# 3. 쓰기 패턴 상세 감지
IS_WRITE=false

# 리다이렉트: >, >> (단 >& 및 fd redirect 제외)
if echo "$CMD_CLEAN" | grep -qE '>[^>&]|>>'; then
  IS_WRITE=true
fi

# tee (파이프로 파일 쓰기)
if echo "$CMD" | grep -qE '\btee\b'; then
  IS_WRITE=true
fi

# sed -i (인플레이스 수정)
if echo "$CMD" | grep -qE '\bsed\b.*-i'; then
  IS_WRITE=true
fi

# cp, mv (파일 복사/이동)
if echo "$CMD" | grep -qE '\bcp\b|\bmv\b'; then
  IS_WRITE=true
fi

# touch (파일 생성)
if echo "$CMD" | grep -qE '\btouch\b'; then
  IS_WRITE=true
fi

# dd of= (블록 디바이스 쓰기)
if echo "$CMD" | grep -qE '\bdd\b.*of='; then
  IS_WRITE=true
fi

# 스크립트 언어로 파일 쓰기
if echo "$CMD" | grep -qE '\bpython[23]?\b.*(-c|<<)|\bnode\b.*-e|\bruby\b.*-e|\bperl\b.*-e'; then
  IS_WRITE=true
fi

# cat/echo + heredoc
if echo "$CMD" | grep -qE '\bcat\b.*>|\becho\b.*>|\bprintf\b.*>'; then
  IS_WRITE=true
fi

# rm, rmdir, unlink (파일/디렉토리 삭제)
if echo "$CMD" | grep -qE '\brm\b|\brmdir\b|\bunlink\b'; then
  IS_WRITE=true
fi

# curl -o/--output (파일 다운로드)
if echo "$CMD" | grep -qE '\bcurl\b.*(-o|--output)'; then
  IS_WRITE=true
fi

# wget (항상 파일 저장)
if echo "$CMD" | grep -qE '\bwget\b'; then
  IS_WRITE=true
fi

[ "$IS_WRITE" = "false" ] && exit 0

# 4. 예외 경로 — gate 관리 파일은 항상 허용
EXCEPTION=false

# ~/.claude/plans/ 경로
if echo "$CMD" | grep -qE '\.claude/plans/'; then
  EXCEPTION=true
fi

# state.json 파일 (.active는 예외 아님 — 비우기로 gate 무력화 방지)
# rm/rmdir/unlink은 state.json도 예외 아님 (삭제 방지)
if echo "$CMD" | grep -qE 'state\.json' && ! echo "$CMD" | grep -qE '\brm\b|\brmdir\b|\bunlink\b'; then
  EXCEPTION=true
fi

# plan.md, step-*.md, phase-*.md, round-*.md, tests.md
if echo "$CMD" | grep -qE 'plan\.md|step-[0-9]+\.md|phase-[0-9]+.*\.md|round-[0-9]+\.md|tests\.md'; then
  EXCEPTION=true
fi

# .active 파일 조작 (삭제 포함 — dev-bounce 완료 시 필요)
if echo "$CMD" | grep -qE '\.active'; then
  EXCEPTION=true
fi

[ "$EXCEPTION" = "true" ] && exit 0

# 5. Gate 검증 (plan-gate.sh CHECK 2~7 동일)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/resolve-task.sh"

# .active 없거나 비어있으면 → 통과 (gate 비활성)
if [ -z "$TASK_NAME" ]; then
  exit 0
fi

# state.json 없으면 통과
[ -f "$STATE_FILE" ] || exit 0

# state.json 값 읽기
WORKFLOW_PHASE=$(jq -r '.workflow_phase // "done"' "$STATE_FILE" 2>/dev/null)
PLAN_APPROVED=$(jq -r '.plan_approved // false' "$STATE_FILE" 2>/dev/null)
MODE=$(jq -r '.mode // "normal"' "$STATE_FILE" 2>/dev/null)
TEAM_NAME=$(jq -r '.team_name // ""' "$STATE_FILE" 2>/dev/null)
CURRENT_DEV_PHASE=$(jq -r '.current_dev_phase // 0' "$STATE_FILE" 2>/dev/null)
CURRENT_STEP=$(jq -r '.current_step // 0' "$STATE_FILE" 2>/dev/null)

# 스냅샷 저장 함수 (Layer 2용) — 세션 격리
save_snapshot() {
  local snap="/tmp/.ai-bouncer-snapshot-${SESSION_ID:-default}"
  { git diff --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort > "$snap" 2>/dev/null
}

# CHECK 1.5: workflow_phase 화이트리스트
case "$WORKFLOW_PHASE" in
  planning|development|verification) ;;
  *)
    save_snapshot
    jq -n '{decision:"block", reason:"⛔ [bash-gate] workflow_phase가 허용되지 않는 값입니다."}'
    exit 0 ;;
esac

# CHECK 2: planning → BLOCK
if [ "$WORKFLOW_PHASE" = "planning" ]; then
  save_snapshot
  jq -n '{
    decision: "block",
    reason: "⛔ [bash-gate] Planning 단계에서 Bash를 통한 파일 쓰기가 차단되었습니다. Q&A 완료 후 계획 승인을 받으세요."
  }'
  exit 0
fi

# CHECK 3: plan_approved + plan.md
if [ "$PLAN_APPROVED" != "true" ]; then
  save_snapshot
  jq -n '{
    decision: "block",
    reason: "⛔ [bash-gate] 계획 미승인 상태에서 Bash를 통한 파일 쓰기가 차단되었습니다. /dev-bounce로 계획을 승인받으세요."
  }'
  exit 0
fi

if [ ! -f "${TASK_DIR}/plan.md" ]; then
  save_snapshot
  jq -n '{
    decision: "block",
    reason: "⛔ [bash-gate] plan.md가 없는 상태에서 Bash를 통한 파일 쓰기가 차단되었습니다."
  }'
  exit 0
fi

# SIMPLE 모드: plan_approved + plan.md 존재만으로 통과
if [ "$MODE" = "simple" ]; then
  exit 0
fi

# --- 이하 NORMAL 모드 전용 ---

# CHECK 6.8: verification + 미완료 Phase → BLOCK (plan-gate 동등)
if [ "$WORKFLOW_PHASE" = "verification" ]; then
  DEV_PHASES_COUNT=$(jq '.dev_phases | length' "$STATE_FILE" 2>/dev/null)
  DEV_PHASES_COUNT=${DEV_PHASES_COUNT:-0}
  if [ "$DEV_PHASES_COUNT" -gt 0 ]; then
    ALL_PHASES_DONE=true
    for pidx in $(seq 1 "$DEV_PHASES_COUNT"); do
      PFOLDER=$(jq -r ".dev_phases[\"$pidx\"].folder // \"\"" "$STATE_FILE" 2>/dev/null)
      [ -z "$PFOLDER" ] && PFOLDER="phase-${pidx}"
      PDIR="${TASK_DIR}/${PFOLDER}"
      HAS_STEPS=false
      for sf in "$PDIR"/step-*.md; do
        [ -f "$sf" ] || continue
        HAS_STEPS=true
        if ! grep -q '✅' "$sf" 2>/dev/null; then
          ALL_PHASES_DONE=false
          break 2
        fi
      done
      if [ "$HAS_STEPS" = false ]; then
        ALL_PHASES_DONE=false
        break
      fi
    done
    if [ "$ALL_PHASES_DONE" = false ]; then
      save_snapshot
      jq -n '{decision:"block", reason:"⛔ [bash-gate] verification이지만 미완료 Phase 존재. 개발을 먼저 완료하세요."}'
      exit 0
    fi
  fi
  # verification + 모든 Phase 완료 → 통과
  save_snapshot
  exit 0
fi

# agent_mode 읽기 (config.json에서)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
AGENT_MODE=$(jq -r '.agent_mode // "team"' "$REPO_ROOT/.claude/ai-bouncer/config.json" 2>/dev/null || echo "team")

# agent_mode별 검증 분기
case "$AGENT_MODE" in
  team)
    # CHECK 4: development + team_name
    if [ "$WORKFLOW_PHASE" = "development" ] && [ -z "$TEAM_NAME" ]; then
      save_snapshot
      jq -n '{
        decision: "block",
        reason: "⛔ [bash-gate][team] 팀 미구성 상태에서 Bash를 통한 파일 쓰기가 차단되었습니다."
      }'
      exit 0
    fi

    # CHECK 5-6: team config + members
    if [ "$WORKFLOW_PHASE" = "development" ]; then
      TEAM_CONFIG="$HOME/.claude/teams/${TEAM_NAME}/config.json"
      if [ ! -f "$TEAM_CONFIG" ]; then
        save_snapshot
        jq -n '{
          decision: "block",
          reason: "⛔ [bash-gate][team] 팀 디렉토리 미존재 상태에서 Bash를 통한 파일 쓰기가 차단되었습니다."
        }'
        exit 0
      fi

      MEMBER_COUNT=$(jq -r '.members | length' "$TEAM_CONFIG" 2>/dev/null)
      MEMBER_COUNT=${MEMBER_COUNT:-0}
      if [ "$MEMBER_COUNT" -lt 1 ] 2>/dev/null; then
        save_snapshot
        jq -n '{
          decision: "block",
          reason: "⛔ [bash-gate][team] 팀 멤버 부족 상태에서 Bash를 통한 파일 쓰기가 차단되었습니다."
        }'
        exit 0
      fi
    fi
    ;;
  subagent)
    # subagent: team 구성 불필요, 위임 등록 검증은 resolve-task.sh fallback이 처리
    ;;
  single)
    # single: Main Claude가 직접 수행, 팀/에이전트 검증 불필요
    ;;
esac

# CHECK 6.5: development + step=0 방어
if [ "$WORKFLOW_PHASE" = "development" ]; then
  if [ "$CURRENT_DEV_PHASE" -le 0 ] 2>/dev/null || [ "$CURRENT_STEP" -le 0 ] 2>/dev/null; then
    save_snapshot
    jq -n '{decision:"block", reason:"⛔ [bash-gate] development이지만 dev_phase/step 미설정"}'
    exit 0
  fi
fi

# CHECK 6.7: dev_phases 비어있는지 검증
if [ "$WORKFLOW_PHASE" = "development" ] && [ "$MODE" = "normal" ]; then
  DEV_PHASES_COUNT=$(jq '.dev_phases | length' "$STATE_FILE" 2>/dev/null)
  if [ "${DEV_PHASES_COUNT:-0}" -le 0 ] 2>/dev/null; then
    save_snapshot
    jq -n '{decision:"block", reason:"⛔ [bash-gate] dev_phases가 비어있습니다. Lead가 phase 구조를 먼저 정의해야 합니다."}'
    exit 0
  fi
fi

# CHECK 7: step 검증
if [ "$CURRENT_DEV_PHASE" -gt 0 ] 2>/dev/null && [ "$CURRENT_STEP" -gt 0 ] 2>/dev/null; then
  DEV_PHASE_KEY="$CURRENT_DEV_PHASE"
  STEP_KEY="$CURRENT_STEP"

  PHASE_FOLDER=$(jq -r ".dev_phases[\"$DEV_PHASE_KEY\"].folder // \"\"" "$STATE_FILE" 2>/dev/null)
  # folder 없으면 기본값 fallback (CHECK 7 스킵 방지)
  [ -z "$PHASE_FOLDER" ] && PHASE_FOLDER="phase-${DEV_PHASE_KEY}"

  PHASE_DIR="${TASK_DIR}/${PHASE_FOLDER}"

  # CHECK 7a: phase.md 존재 검증
  if [ ! -f "${PHASE_DIR}/phase.md" ]; then
    save_snapshot
    jq -n --arg phase "$DEV_PHASE_KEY" '{
      decision: "block",
      reason: ("⛔ [bash-gate] Dev Phase " + $phase + "의 phase.md가 존재하지 않습니다. Lead가 phase.md를 먼저 생성해야 합니다.")
    }'
    exit 0
  fi

  # CHECK 7a-2: phase.md 필수 섹션 검증
  for section in "## 목표" "## 범위" "## Steps"; do
    if ! grep -q "$section" "${PHASE_DIR}/phase.md" 2>/dev/null; then
      save_snapshot
      jq -n --arg phase "$DEV_PHASE_KEY" --arg s "$section" '{
        decision: "block",
        reason: ("⛔ [bash-gate] Dev Phase " + $phase + "의 phase.md에 필수 섹션 누락: " + $s)
      }'
      exit 0
    fi
  done

  PREV_STEP=$((CURRENT_STEP - 1))
  if [ "$PREV_STEP" -gt 0 ]; then
    PREV_STEP_FILE="${PHASE_DIR}/step-${PREV_STEP}.md"

    if [ ! -f "$PREV_STEP_FILE" ]; then
      save_snapshot
      jq -n --arg phase "$DEV_PHASE_KEY" --arg step "$PREV_STEP" '{
        decision: "block",
        reason: ("⛔ [bash-gate] Dev Phase " + $phase + " Step " + $step + " 문서 미존재. Bash 파일 쓰기 차단.")
      }'
      exit 0
    fi

    if ! grep -q '✅' "$PREV_STEP_FILE" 2>/dev/null; then
      save_snapshot
      jq -n --arg phase "$DEV_PHASE_KEY" --arg step "$PREV_STEP" '{
        decision: "block",
        reason: ("⛔ [bash-gate] Dev Phase " + $phase + " Step " + $step + " 테스트 미통과. Bash 파일 쓰기 차단.")
      }'
      exit 0
    fi

    # CHECK 7c-2: 이전 step의 TC 실행출력 검증
    if ! grep -qE '(실행출력|실행 결과|출력:|Output:)' "$PREV_STEP_FILE" 2>/dev/null; then
      save_snapshot
      jq -n --arg phase "$DEV_PHASE_KEY" --arg step "$PREV_STEP" '{
        decision: "block",
        reason: ("⛔ [bash-gate] Dev Phase " + $phase + " Step " + $step + "의 TC에 실행출력이 없습니다. 테스트 실행 결과를 반드시 기록하세요.")
      }'
      exit 0
    fi
  fi

  CURRENT_STEP_FILE="${PHASE_DIR}/step-${STEP_KEY}.md"

  if [ ! -f "$CURRENT_STEP_FILE" ]; then
    save_snapshot
    jq -n --arg phase "$DEV_PHASE_KEY" --arg step "$STEP_KEY" '{
      decision: "block",
      reason: ("⛔ [bash-gate] Dev Phase " + $phase + " Step " + $step + " step.md 미존재. Bash 파일 쓰기 차단.")
    }'
    exit 0
  fi

  if ! grep -E '^\| *TC-[0-9]+ *\| *[^ |]' "$CURRENT_STEP_FILE" >/dev/null 2>&1; then
    save_snapshot
    jq -n --arg phase "$DEV_PHASE_KEY" --arg step "$STEP_KEY" '{
      decision: "block",
      reason: ("⛔ [bash-gate] Dev Phase " + $phase + " Step " + $step + " TC 미정의. Bash 파일 쓰기 차단.")
    }'
    exit 0
  fi
fi

# 모든 검증 통과 — 스냅샷 불필요 (gate 조건 충족)
# --- ai-bouncer end ---

exit 0
