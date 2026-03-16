#!/bin/bash
# subagent-track: SubagentStart hook
# 메인 세션이 sub-agent 스폰 시, 해당 sub-agent의 session_id를 승인 목록에 등록
# 승인된 sub-agent는 부모 task의 plan 기준으로 Write/Bash 허용

INPUT=$(cat)

# sub-agent의 session_id 추출
AGENT_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
[ -z "$AGENT_SESSION_ID" ] && exit 0

# 부모의 활성 task 찾기: development/verification phase인 .active task 검색
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
FOUND_TASK_DIR=""

# 날짜별 구조 스캔
if [ -d "$REPO_ROOT/docs" ]; then
  for date_dir in "$REPO_ROOT/docs"/*/; do
    [ -d "$date_dir" ] || continue
    for active_file in "$date_dir"*/.active; do
      [ -f "$active_file" ] || continue
      task_dir=$(dirname "$active_file")
      state_file="${task_dir}/state.json"
      [ -f "$state_file" ] || continue
      phase=$(jq -r '.workflow_phase // ""' "$state_file" 2>/dev/null)
      case "$phase" in
        development|verification)
          FOUND_TASK_DIR="$task_dir"
          break 2 ;;
      esac
    done
  done
fi

# persistent 경로도 확인
if [ -z "$FOUND_TASK_DIR" ]; then
  REPO_NAME=$(basename "$REPO_ROOT" 2>/dev/null)
  PERSISTENT_BASE="$HOME/.claude/ai-bouncer/sessions/${REPO_NAME}/docs"
  if [ -d "$PERSISTENT_BASE" ]; then
    for active_file in "$PERSISTENT_BASE"/*/.active; do
      [ -f "$active_file" ] || continue
      task_dir=$(dirname "$active_file")
      state_file="${task_dir}/state.json"
      [ -f "$state_file" ] || continue
      phase=$(jq -r '.workflow_phase // ""' "$state_file" 2>/dev/null)
      case "$phase" in
        development|verification)
          FOUND_TASK_DIR="$task_dir"
          break ;;
      esac
    done
  fi
fi

# 활성 development/verification task 없으면 등록 불필요
[ -z "$FOUND_TASK_DIR" ] && exit 0

# 승인 목록에 등록: session_id → task_dir 매핑
APPROVED_FILE="/tmp/.ai-bouncer-approved-agents"
echo "${AGENT_SESSION_ID}|${FOUND_TASK_DIR}" >> "$APPROVED_FILE"

exit 0
