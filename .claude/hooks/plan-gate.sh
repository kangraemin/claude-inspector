#!/bin/bash
# plan-gate: PreToolUse hook
# Write/Edit 시도 전 아티팩트 기반 검증 — state.json 플래그만으로 우회 불가

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Write/Edit/MultiEdit 계열만 체크
case "$TOOL" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

# 세션 격리: session_id 추출
export SESSION_ID
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

# --- ai-bouncer start ---

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

# CHECK 0: ~/.claude/plans/ 경로 → 즉시 ALLOW (Claude Code 내부 plan 파일)
if [[ "$FILE_PATH" == "$HOME/.claude/plans/"* ]] || [[ "$FILE_PATH" == *"/.claude/plans/"* ]]; then
  exit 0
fi

# CHECK 1: 예외 패턴 (*/plan.md, */step-*.md, */phase-*.md) → 즉시 ALLOW
if [[ "$FILE_PATH" == */plan.md ]] || [[ "$FILE_PATH" == */step-*.md ]] || [[ "$FILE_PATH" == */phase-*.md ]]; then
  exit 0
fi

# resolve_task_dir: 공유 라이브러리 사용
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/resolve-task.sh"

# .active 없거나 비어있으면 → 통과
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

# CHECK 1.5: workflow_phase 화이트리스트
case "$WORKFLOW_PHASE" in
  planning|development|verification) ;;
  *)
    jq -n '{decision:"block", reason:"⛔ workflow_phase가 허용되지 않는 값입니다."}'
    exit 0 ;;
esac

# CHECK 2: planning 단계 → BLOCK
if [ "$WORKFLOW_PHASE" = "planning" ]; then
  jq -n '{
    decision: "block",
    reason: "Planning 단계입니다. Q&A가 완료되고 계획이 승인된 후 개발을 시작하세요."
  }'
  exit 0
fi

# CHECK 3: plan_approved 체크 + plan.md 파일 실존 이중 체크
if [ "$PLAN_APPROVED" != "true" ]; then
  jq -n '{
    decision: "block",
    reason: "계획이 승인되지 않았습니다. /dev-bounce로 계획을 수립하고 승인 후 개발을 시작하세요."
  }'
  exit 0
fi

if [ ! -f "${TASK_DIR}/plan.md" ]; then
  jq -n '{
    decision: "block",
    reason: "plan.md 파일이 존재하지 않습니다. 계획 문서가 실제로 작성되어야 합니다."
  }'
  exit 0
fi

# SIMPLE 모드: plan_approved + plan.md 존재만으로 통과
if [ "$MODE" = "simple" ]; then
  exit 0
fi

# --- 이하 NORMAL 모드 전용 ---

# agent_mode 읽기 (config.json에서)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
AGENT_MODE=$(jq -r '.agent_mode // "team"' "$REPO_ROOT/.claude/ai-bouncer/config.json" 2>/dev/null || echo "team")

# agent_mode별 검증 분기
case "$AGENT_MODE" in
  team)
    # CHECK 4: development + team_name 비어있음 → BLOCK
    if [ "$WORKFLOW_PHASE" = "development" ] && [ -z "$TEAM_NAME" ]; then
      jq -n '{
        decision: "block",
        reason: "⛔ [team] 팀이 구성되지 않았습니다. TeamCreate로 팀을 먼저 생성하세요."
      }'
      exit 0
    fi

    # CHECK 5: development + team config.json 미존재 → BLOCK
    if [ "$WORKFLOW_PHASE" = "development" ]; then
      TEAM_CONFIG="$HOME/.claude/teams/${TEAM_NAME}/config.json"
      if [ ! -f "$TEAM_CONFIG" ]; then
        jq -n '{
          decision: "block",
          reason: "⛔ [team] 팀 디렉토리가 존재하지 않습니다. TeamCreate로 팀을 먼저 생성하세요."
        }'
        exit 0
      fi

      # CHECK 6: team members < 1 → BLOCK
      MEMBER_COUNT=$(jq -r '.members | length' "$TEAM_CONFIG" 2>/dev/null)
      MEMBER_COUNT=${MEMBER_COUNT:-0}
      if [ "$MEMBER_COUNT" -lt 1 ] 2>/dev/null; then
        jq -n '{
          decision: "block",
          reason: "⛔ [team] 팀 멤버가 없습니다. Lead 에이전트를 먼저 스폰하세요."
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
    jq -n '{decision:"block", reason:"⛔ development이지만 dev_phase/step 미설정"}'
    exit 0
  fi
fi

# CHECK 6.7: dev_phases 비어있는지 검증
if [ "$WORKFLOW_PHASE" = "development" ] && [ "$MODE" = "normal" ]; then
  DEV_PHASES_COUNT=$(jq '.dev_phases | length' "$STATE_FILE" 2>/dev/null)
  if [ "${DEV_PHASES_COUNT:-0}" -le 0 ] 2>/dev/null; then
    jq -n '{decision:"block", reason:"⛔ dev_phases가 비어있습니다. Lead가 phase 구조를 먼저 정의해야 합니다."}'
    exit 0
  fi
fi

# CHECK 6.8: verification인데 모든 Phase가 완료되지 않았으면 → BLOCK
if [ "$WORKFLOW_PHASE" = "verification" ] && [ "$MODE" = "normal" ]; then
  DEV_PHASES_COUNT=$(jq '.dev_phases | length' "$STATE_FILE" 2>/dev/null)
  DEV_PHASES_COUNT=${DEV_PHASES_COUNT:-0}
  if [ "$DEV_PHASES_COUNT" -gt 0 ]; then
    ALL_PHASES_DONE=true
    for phase_idx in $(seq 1 "$DEV_PHASES_COUNT"); do
      PHASE_FOLDER=$(jq -r ".dev_phases[\"$phase_idx\"].folder // \"\"" "$STATE_FILE" 2>/dev/null)
      [ -z "$PHASE_FOLDER" ] && PHASE_FOLDER="phase-${phase_idx}"
      PHASE_DIR="${TASK_DIR}/${PHASE_FOLDER}"
      # phase 디렉토리에 step-*.md가 있고, 모두 ✅를 포함해야 함
      HAS_STEPS=false
      for step_file in "$PHASE_DIR"/step-*.md; do
        [ -f "$step_file" ] || continue
        HAS_STEPS=true
        if ! grep -q '✅' "$step_file" 2>/dev/null; then
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
      jq -n --arg count "$DEV_PHASES_COUNT" '{
        decision: "block",
        reason: ("⛔ verification 단계이지만 모든 개발 Phase가 완료되지 않았습니다. 미완료 Phase의 개발을 먼저 완료하세요. (총 " + $count + "개 Phase)")
      }'
      exit 0
    fi
  fi
fi

# CHECK 7: current_dev_phase > 0 AND current_step > 0
if [ "$CURRENT_DEV_PHASE" -gt 0 ] 2>/dev/null && [ "$CURRENT_STEP" -gt 0 ] 2>/dev/null; then
  DEV_PHASE_KEY="$CURRENT_DEV_PHASE"
  STEP_KEY="$CURRENT_STEP"

  # phase_folder 조회
  PHASE_FOLDER=$(jq -r ".dev_phases[\"$DEV_PHASE_KEY\"].folder // \"\"" "$STATE_FILE" 2>/dev/null)
  # folder 없으면 기본값 fallback (CHECK 7 스킵 방지)
  [ -z "$PHASE_FOLDER" ] && PHASE_FOLDER="phase-${DEV_PHASE_KEY}"

  PHASE_DIR="${TASK_DIR}/${PHASE_FOLDER}"

  # CHECK 7-PHASE: 이전 Phase 완료 검증 (current_dev_phase > 1일 때)
  PREV_DEV_PHASE=$((CURRENT_DEV_PHASE - 1))
  if [ "$PREV_DEV_PHASE" -gt 0 ]; then
    PREV_PHASE_FOLDER=$(jq -r ".dev_phases[\"$PREV_DEV_PHASE\"].folder // \"\"" "$STATE_FILE" 2>/dev/null)
    [ -z "$PREV_PHASE_FOLDER" ] && PREV_PHASE_FOLDER="phase-${PREV_DEV_PHASE}"
    PREV_PHASE_DIR="${TASK_DIR}/${PREV_PHASE_FOLDER}"
    # 이전 Phase의 모든 step.md에 ✅가 있어야 함
    PREV_PHASE_INCOMPLETE=false
    for prev_step_file in "$PREV_PHASE_DIR"/step-*.md; do
      [ -f "$prev_step_file" ] || continue
      if ! grep -q '✅' "$prev_step_file" 2>/dev/null; then
        PREV_PHASE_INCOMPLETE=true
        break
      fi
    done
    if [ "$PREV_PHASE_INCOMPLETE" = true ]; then
      jq -n --arg phase "$PREV_DEV_PHASE" '{
        decision: "block",
        reason: ("⛔ Phase " + $phase + "의 모든 Step이 완료되지 않았습니다. 이전 Phase를 먼저 완료하세요.")
      }'
      exit 0
    fi
  fi

  # CHECK 7a: phase.md 존재 검증
  if [ ! -f "${PHASE_DIR}/phase.md" ]; then
    jq -n --arg phase "$DEV_PHASE_KEY" '{
      decision: "block",
      reason: ("Dev Phase " + $phase + "의 phase.md가 존재하지 않습니다. Lead가 phase.md를 먼저 생성해야 합니다.")
    }'
    exit 0
  fi

  # CHECK 7a-2: phase.md 필수 섹션 검증
  for section in "## 목표" "## 범위" "## Steps"; do
    if ! grep -q "$section" "${PHASE_DIR}/phase.md" 2>/dev/null; then
      jq -n --arg phase "$DEV_PHASE_KEY" --arg s "$section" '{
        decision: "block",
        reason: ("Dev Phase " + $phase + "의 phase.md에 필수 섹션 누락: " + $s)
      }'
      exit 0
    fi
  done

  # 이전 step 검증 (M > 1일 때)
  PREV_STEP=$((CURRENT_STEP - 1))
  if [ "$PREV_STEP" -gt 0 ]; then
    PREV_STEP_FILE="${PHASE_DIR}/step-${PREV_STEP}.md"

    # CHECK 7b: 이전 step 파일 미존재 → BLOCK
    if [ ! -f "$PREV_STEP_FILE" ]; then
      jq -n --arg phase "$DEV_PHASE_KEY" --arg step "$PREV_STEP" '{
        decision: "block",
        reason: ("Dev Phase " + $phase + " Step " + $step + " 문서가 존재하지 않습니다.")
      }'
      exit 0
    fi

    # CHECK 7c: 이전 step에 ✅ 미포함 → BLOCK
    if ! grep -q '✅' "$PREV_STEP_FILE" 2>/dev/null; then
      jq -n --arg phase "$DEV_PHASE_KEY" --arg step "$PREV_STEP" '{
        decision: "block",
        reason: ("Dev Phase " + $phase + " Step " + $step + " 테스트가 통과되지 않았습니다 (✅ 없음). 테스트를 먼저 통과시킨 후 진행하세요.")
      }'
      exit 0
    fi

    # CHECK 7c-2: 이전 step의 TC 실행출력 검증
    if ! grep -qE '(실행출력|실행 결과|출력:|Output:)' "$PREV_STEP_FILE" 2>/dev/null; then
      jq -n --arg phase "$DEV_PHASE_KEY" --arg step "$PREV_STEP" '{
        decision: "block",
        reason: ("Dev Phase " + $phase + " Step " + $step + "의 TC에 실행출력이 없습니다. 테스트 실행 결과를 반드시 기록하세요.")
      }'
      exit 0
    fi
  fi

  # 현재 step 검증
  CURRENT_STEP_FILE="${PHASE_DIR}/step-${STEP_KEY}.md"

  # CHECK 7d: 현재 step 파일 미존재 → BLOCK
  if [ ! -f "$CURRENT_STEP_FILE" ]; then
    jq -n --arg phase "$DEV_PHASE_KEY" --arg step "$STEP_KEY" '{
      decision: "block",
      reason: ("Dev Phase " + $phase + " Step " + $step + " 의 step.md가 존재하지 않습니다. Lead가 step.md를 먼저 생성해야 합니다.")
    }'
    exit 0
  fi

  # CHECK 7e: 현재 step에 TC 행 내용 없음 → BLOCK
  if ! grep -E '^\| *TC-[0-9]+ *\| *[^ |]' "$CURRENT_STEP_FILE" >/dev/null 2>&1; then
    jq -n --arg phase "$DEV_PHASE_KEY" --arg step "$STEP_KEY" '{
      decision: "block",
      reason: ("Dev Phase " + $phase + " Step " + $step + " 의 테스트 기준이 정의되지 않았습니다. QA가 TC를 먼저 작성해야 합니다.")
    }'
    exit 0
  fi
fi

# --- ai-bouncer end ---

exit 0
