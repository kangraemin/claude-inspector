#!/bin/bash
# bash-audit: PostToolUse hook (Layer 2)
# Bash 실행 후 git diff로 무단 파일 변경 감지 + 자동 복원

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Bash만 체크
[ "$TOOL" != "Bash" ] && exit 0

# --- ai-bouncer start ---

SNAPSHOT_FILE="/tmp/.ai-bouncer-snapshot"

# 스냅샷 없으면 → gate 비활성 판단 (bash-gate가 스냅샷 미생성) → 스킵
[ -f "$SNAPSHOT_FILE" ] || exit 0

# 승인된 sub-agent는 부모 task 기준으로 이미 gate 통과 → audit 스킵
AGENT_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
APPROVED_FILE="/tmp/.ai-bouncer-approved-agents"
if [ -n "$AGENT_SESSION_ID" ] && [ -f "$APPROVED_FILE" ]; then
  if grep -q "^${AGENT_SESSION_ID}|" "$APPROVED_FILE" 2>/dev/null; then
    rm -f "$SNAPSHOT_FILE"
    exit 0
  fi
fi

# 현재 상태 캡처
CURRENT_STATE=$(mktemp)
{ git diff --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort > "$CURRENT_STATE"

# 스냅샷과 diff → 새로 변경된 파일 목록
CHANGED_FILES=$(comm -13 "$SNAPSHOT_FILE" "$CURRENT_STATE" 2>/dev/null)

# 정리
rm -f "$SNAPSHOT_FILE" "$CURRENT_STATE"

[ -z "$CHANGED_FILES" ] && exit 0

# 예외 경로 필터
UNAUTHORIZED_FILES=""
while IFS= read -r file; do
  [ -z "$file" ] && continue

  case "$file" in
    */plan.md|*/step-*.md|*/phase-*.md|*/round-*.md|*/.active) continue ;;
    */tests.md) continue ;;
    */state.json) continue ;;
    plan.md) continue ;;
    .claude/plans/*|*/.claude/plans/*) continue ;;
    .claude/teams/*|*/.claude/teams/*) continue ;;
    docs/*/verifications/round-*.md) continue ;;
  esac

  UNAUTHORIZED_FILES="${UNAUTHORIZED_FILES}${file}"$'\n'
done <<< "$CHANGED_FILES"

# 빈 줄 제거
UNAUTHORIZED_FILES=$(echo "$UNAUTHORIZED_FILES" | sed '/^$/d')

[ -z "$UNAUTHORIZED_FILES" ] && exit 0

# 무단 변경 파일 복원
RESTORED_LIST=""
while IFS= read -r file; do
  [ -z "$file" ] && continue

  if git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
    # tracked 파일: git checkout으로 복원
    git checkout -- "$file" 2>/dev/null
    RESTORED_LIST="${RESTORED_LIST}  - ${file} (복원)"$'\n'
  else
    # untracked 파일: rm으로 제거
    rm -f "$file" 2>/dev/null
    RESTORED_LIST="${RESTORED_LIST}  - ${file} (삭제)"$'\n'
  fi
done <<< "$UNAUTHORIZED_FILES"

# 경고 메시지 출력
if [ -n "$RESTORED_LIST" ]; then
  echo ""
  echo "⚠️ [bash-audit] 무단 파일 변경 감지 및 자동 복원:"
  echo "$RESTORED_LIST"
  echo "Gate 조건을 충족하지 않은 상태에서 Bash를 통한 파일 변경은 허용되지 않습니다."
fi

# --- ai-bouncer end ---

exit 0
