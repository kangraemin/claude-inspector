#!/usr/bin/env bash
# 옛 로컬 설치본 자리 — 이 경로로 훅을 잡아 둔 세션을 전역 훅으로 넘긴다.
BOUNCER_FORWARDED=1 exec bash "/Users/ram/.claude/ai-bouncer/hooks/post-tool.sh" "$@"
