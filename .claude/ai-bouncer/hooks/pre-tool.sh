#!/usr/bin/env bash
# PreToolUse — 현재 스테이지의 forbid를 강제한다.
#
# ⚠️ 매 도구 호출마다 돈다. 그리고 이 hook이 타임아웃되면 차단이 **아예 안 된다**
#    (공식 문서: "don't count on a stalled hook to act as a gate").
#    그래서 여기서는 jq로 compiled.json을 읽기만 한다. 명령 실행 금지.

set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../engine/lib/common.sh"

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

SESSION="$(jq -r '.session_id // empty' <<<"$INPUT")"
CWD="$(jq -r '.cwd // empty'            <<<"$INPUT")"
TOOL="$(jq -r '.tool_name // empty'     <<<"$INPUT")"
[ -n "$CWD" ] || CWD="$PWD"
[ -n "$SESSION" ] && [ -n "$TOOL" ] || exit 0

TASK="$(bouncer_my_task "$CWD" "$SESSION")" || exit 0
STAGE="$(bouncer_state "$TASK" '.current_stage')"
[ -n "$STAGE" ] && [ "$STAGE" != "cancelled" ] || exit 0

# ── 엔진 전용 파일 보호 (스테이지와 무관하게 항상) ────────────
# state.json을 모델이 고치면 단계 건너뛰기가 가능해진다.
FILE_PATH="$(jq -r '.tool_input.file_path // .tool_input.path // empty' <<<"$INPUT")"
case "$FILE_PATH" in
  */.ai-bouncer/tasks/*/state.json|*/.ai-bouncer/tasks/*/.active|*/workflow.compiled.json)
    bouncer_block "⛔ [ai-bouncer] 엔진 상태 파일은 직접 수정할 수 없다.
단계 전이는 엔진만 한다. 조건을 충족시켜서 넘어가라." ;;
esac

FORBID="$(bouncer_stage "$CWD" "$STAGE" | jq -c '.forbid // {}')"
REASON="$(jq -r '.reason // ""' <<<"$FORBID")"
[ -n "$REASON" ] || REASON="현재 단계에서 허용되지 않는 동작이다."
deny() { bouncer_block "⛔ [ai-bouncer / $STAGE] $1

$REASON"; }

EDIT="$(jq -c '.edit_files // null' <<<"$FORBID")"
PUSH="$(jq -r '.push'               <<<"$FORBID")"

# 경로가 edit_files 스코프에 걸리는가. true면 전체, 배열이면 glob(선두 !는 예외).
path_forbidden() {
  local p="$1"
  [ "$EDIT" = "null" ] && return 1
  [ "$EDIT" = "true" ] && return 0
  local pat neg matched=1
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    neg=0; case "$pat" in "!"*) neg=1; pat="${pat#!}" ;; esac
    # shellcheck disable=SC2254
    case "$p" in $pat) [ "$neg" = 1 ] && return 1 || matched=0 ;; esac
  done < <(jq -r '.[]?' <<<"$EDIT")
  return $matched
}

case "$TOOL" in
  Edit|Write|MultiEdit|NotebookEdit)
    # 프로젝트 기준 상대경로로만 판정한다. 절대경로로 한 번 더 보면
    # "!docs/**" 같은 예외가 앞의 "**"에 다시 걸려 무효화된다.
    REL="${FILE_PATH#"$CWD"/}"
    if path_forbidden "$REL"; then
      deny "파일 수정이 차단되었다: ${REL:-$FILE_PATH}"
    fi
    exit 0 ;;

  Bash)
    CMD="$(jq -r '.tool_input.command // empty' <<<"$INPUT")"
    [ -n "$CMD" ] || exit 0

    # bouncer 자신의 명령은 항상 허용 (게이트를 통과할 유일한 수단이므로)
    case "$CMD" in bouncer\ *|*/bouncer.sh\ *) exit 0 ;; esac

    if [ "$PUSH" = "true" ] && printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'; then
      deny "push가 차단되었다."
    fi

    # edit_files는 bash 우회도 함께 막는다. 스코프 배열이면 대상 경로까지 판정.
    if [ "$EDIT" != "null" ] && printf '%s' "$CMD" | grep -Eq \
      '(^|[;&|[:space:]])(rm|mv|cp|touch|truncate|mkdir)[[:space:]]|[^|>]>[[:space:]]*[^|[:space:]]|(^|[[:space:]])tee[[:space:]]|sed[[:space:]]+(-[^[:space:]]*[[:space:]]+)*-i'; then
      if [ "$EDIT" = "true" ]; then
        deny "셸을 통한 파일 수정이 차단되었다: ${CMD:0:80}"
      else
        # 스코프가 있으면 명령에 등장하는 "경로처럼 보이는" 토큰만 판정한다.
        # `**` 패턴은 아무 단어에나 걸리므로 명령어 이름까지 검사하면 전부 차단된다.
        prev=""
        for tok in $CMD; do
          case "$tok" in
            -*|"|"|"&&"|";"|"||") prev="$tok"; continue ;;
            ">"|">>") prev="$tok"; continue ;;
          esac
          # 리다이렉트 대상은 무조건 경로. 그 외엔 / 나 . 을 포함할 때만 경로로 본다.
          if [ "$prev" = ">" ] || [ "$prev" = ">>" ] || case "$tok" in */*|*.*) true ;; *) false ;; esac; then
            if path_forbidden "${tok#./}"; then
              deny "셸을 통한 파일 수정이 차단되었다: $tok"
            fi
          fi
          prev="$tok"
        done
      fi
    fi

    while IFS= read -r pat; do
      [ -z "$pat" ] && continue
      if printf '%s' "$CMD" | grep -Eq "$pat"; then
        deny "차단된 명령이다: ${CMD:0:80}"
      fi
    done < <(jq -r '.bash[]?' <<<"$FORBID")
    exit 0 ;;
esac
exit 0
