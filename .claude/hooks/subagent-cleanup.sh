#!/bin/bash
# subagent-cleanup: SubagentStop hook
# sub-agent 종료 시 승인 목록에서 제거

INPUT=$(cat)

AGENT_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
[ -z "$AGENT_SESSION_ID" ] && exit 0

APPROVED_FILE="/tmp/.ai-bouncer-approved-agents"
[ -f "$APPROVED_FILE" ] || exit 0

# 해당 session_id 행 제거
TEMP=$(mktemp)
grep -v "^${AGENT_SESSION_ID}|" "$APPROVED_FILE" > "$TEMP" 2>/dev/null || true
mv "$TEMP" "$APPROVED_FILE"

# 파일이 비었으면 삭제
[ -s "$APPROVED_FILE" ] || rm -f "$APPROVED_FILE"

exit 0
