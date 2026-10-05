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

# 아래 차단들은 전부 "bouncer cancel / check 로 정리하라"를 안내한다.
# 그 명령까지 막으면 모델이 빠져나갈 길이 없다 — 엔진 명령은 먼저 통과시킨다.
# 단 **연산자가 하나도 없는 순수 호출**만. 접두로 인정하면
# `bouncer status && rm -rf x` 가 통째로 빠져나간다 (감사에서 실제로 뚫렸다).
if [ "$TOOL" = "Bash" ]; then
  _C="$(jq -r '.tool_input.command // empty' <<<"$INPUT")"
  _ROOT="$(bouncer_project_root "$CWD")"
  # grep 의 `^…$` 는 **줄** 앵커다. 명령 어딘가에 `bouncer` 한 줄만 끼우면
  # 통째로 통과했다 (감사에서 실제로 뚫렸다). 개행이 있으면 아예 면제하지 않는다.
  case "$_C" in
    *"
"*) ;;
    *)
      # 경로 형태는 **이 프로젝트의 설치본**만 인정한다. 접미사만 보면
      # /tmp/e/.claude/ai-bouncer/engine/bouncer.sh 를 심어 hook 을 끌 수 있다.
      if printf '%s' "$_C" | grep -Eq '^[[:space:]]*bouncer([[:space:]]+[^;&|<>()`$'"'"'"]*)?[[:space:]]*$' \
         || printf '%s' "$_C" | grep -qE "^[[:space:]]*(\./)?${_ROOT//\//\\/}/\.claude/ai-bouncer/engine/bouncer\.sh([[:space:]]+[^;&|<>()\`\$'\"]*)?[[:space:]]*$" \
         || printf '%s' "$_C" | grep -qE "^[[:space:]]*(\./)?\.claude/ai-bouncer/engine/bouncer\.sh([[:space:]]+[^;&|<>()\`\$'\"]*)?[[:space:]]*$"; then
        exit 0
      fi ;;
  esac
fi

TASK="$(bouncer_my_task "$CWD" "$SESSION")" || exit 0
# 도구 호출 수를 센다. Stop 이 "직전 차단 이후 모델이 아무것도 안 했다"를
# 알아야 백그라운드 작업 대기를 무한 차단 루프로 만들지 않는다. state.json 잠금을
# 타면 매 호출이 느려지므로 별도 파일에 덮어쓴다.
_SEQ="$(cat "$TASK/.tool_seq" 2>/dev/null)"; case "$_SEQ" in ''|*[!0-9]*) _SEQ=0 ;; esac
printf '%s' "$(( _SEQ + 1 ))" > "$TASK/.tool_seq" 2>/dev/null || true

# 여기까지 왔다는 건 이 세션에 활성 작업이 있다는 뜻이다.
# 그런데 상태나 설정을 못 읽으면 "규칙 없음"이 아니라 "규칙을 알 수 없음"이다.
# 그때 통과시키면 파일 하나 깨뜨리는 것으로 모든 가드가 사라진다 — 막는 쪽이 맞다.
COMPILED="$(bouncer_compiled_file "$CWD")"
if ! jq -e . "$COMPILED" >/dev/null 2>&1; then
  bouncer_block "⛔ [ai-bouncer] 워크플로우 설정을 읽을 수 없다: $COMPILED
규칙을 알 수 없는 상태에서는 진행할 수 없다.
  \`bouncer check\` 로 workflow.yaml을 확인하거나, 되돌린 뒤 다시 시도하라."
fi
if ! jq -e . "$TASK/state.json" >/dev/null 2>&1; then
  bouncer_block "⛔ [ai-bouncer] 작업 상태 파일이 손상됐다: $TASK/state.json
진행할 수 없다. \`bouncer cancel\` 로 정리하고 다시 시작하라."
fi

STAGE="$(bouncer_state "$TASK" '.current_stage')"
[ "$STAGE" = "cancelled" ] && exit 0
if [ -z "$STAGE" ]; then
  bouncer_block "⛔ [ai-bouncer] 현재 단계를 알 수 없다. \`bouncer cancel\` 로 정리하고 다시 시작하라."
fi

# ── 엔진 전용 파일 보호 (스테이지와 무관하게 항상) ────────────
# 이 파일들을 고치면 단계 건너뛰기나 가드 무력화가 가능해진다.
ENGINE_FILE_MSG="⛔ [ai-bouncer] 엔진 파일은 직접 수정할 수 없다.
단계 전이와 규칙은 엔진이 관리한다. 조건을 충족시켜서 넘어가라."

FILE_PATH="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' <<<"$INPUT")"
# 셸을 통한 접근은 guard.py가 같은 기준으로 막는다 (아래 Bash 분기).
# 여기서 정규식으로 한 번 더 보던 코드는 지웠다 — 두 벌로 관리하니
# 셸 쪽만 `.ai-bouncer` 부모 디렉토리를 놓쳐 `rm -rf .ai-bouncer` 가 통과했다.

STAGE_JSON="$(bouncer_stage "$CWD" "$STAGE")"
if [ -z "$STAGE_JSON" ]; then
  bouncer_block "⛔ [ai-bouncer] 진행 중인 단계 '$STAGE' 가 workflow.yaml에 없다.
작업 도중 삭제되었거나 이름이 바뀐 것으로 보인다.
무슨 규칙을 적용해야 할지 알 수 없어 진행할 수 없다.

  · workflow.yaml에서 '$STAGE' 를 되돌린다
  · 이 작업을 포기한다: bouncer cancel"
fi
FORBID="$(jq -c '.forbid // {}' <<<"$STAGE_JSON")"
REASON="$(jq -r '.reason // ""' <<<"$FORBID")"
[ -n "$REASON" ] || REASON="현재 단계에서 허용되지 않는 동작이다."
deny() {
  # 판정기가 낸 사유와 yaml의 reason 이 같은 말이면 두 번 보여주지 않는다.
  if [ "$1" = "$REASON" ] || printf '%s' "$1" | grep -qF "$REASON"; then
    bouncer_block "⛔ [ai-bouncer / $STAGE] $1"
  else
    bouncer_block "⛔ [ai-bouncer / $STAGE] $1

$REASON"
  fi
}

EDIT="$(jq -c '.edit_files // null' <<<"$FORBID")"
PUSH="$(jq -r '.push'               <<<"$FORBID")"

# 판정기는 하나만 쓴다. 예전에는 Edit 판정을 셸 `case` 로 따로 구현해서,
# 같은 파일에 대해 `*` 가 `/` 를 넘는지와 `!` 우선순위가 두 게이트에서 정반대였다.
GUARD="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/engine/lib/guard.py"
# 상대화 기준은 세션 cwd가 아니라 프로젝트 루트다.
# cwd 기준으로 잡으면 하위 디렉토리에서 연 세션은 글로브가 하나도 안 맞아
# 스코프가 통째로 꺼진다 (모노레포에서 흔한 패턴이다).
ROOT="$(bouncer_project_root "$CWD")"
WT="$(bouncer_state "$TASK" '.worktree.path')"
[ "$(bouncer_state "$TASK" '.work_root')" = "$WT" ] || WT=""

case "$TOOL" in
  Edit|Write|MultiEdit|NotebookEdit)
    if [ -f "$GUARD" ] && command -v python3 >/dev/null 2>&1; then
      if [ -z "$FILE_PATH" ] && [ "$(jq -r '.edit_files' <<<"$FORBID")" != "null" ]; then
        deny "어느 파일을 고치려는지 알 수 없다. 이 단계에는 수정 제한이 걸려 있다."
      fi
      # Bash 분기와 같은 방향으로 실패해야 한다. 예전엔 여기만 fail-open 이었다.
      R="$(python3 "$GUARD" --check-path "$(jq -c '.edit_files // null' <<<"$FORBID")" \
            "$ROOT" "$FILE_PATH" "$CWD" "$WT" 2>/dev/null)" \
        || deny "경로 판정 중 오류가 발생했다. 안전을 위해 차단한다."
      [ -n "$R" ] && deny "$R"
    elif [ "$(jq -r '.edit_files' <<<"$FORBID")" != "null" ]; then
      deny "경로 판정기를 사용할 수 없다 ($GUARD). 이 단계에는 수정 제한이 걸려 있다."
    fi
    exit 0 ;;

  Bash)
    CMD="$(jq -r '.tool_input.command // empty' <<<"$INPUT")"
    [ -n "$CMD" ] || exit 0
    # 정규식 블랙리스트로는 못 막는다는 게 감사로 확인됐다 —
    # 따옴표(`"rm" -f`), 인터프리터(`python3 -c "open(...,'w')"`), 에디터(`ed`),
    # git write 서브커맨드가 전부 빠져나갔고, `bouncer status; rm x` 처럼
    # 허용 명령 뒤에 붙이면 통째로 통과했다.
    # 그래서 명령을 세그먼트로 쪼개고 실행 파일 이름을 정규화해서 판정한다.
    # 제약이 하나도 없는 스테이지에서도 엔진 파일 보호는 살아 있어야 한다.
    # 예전에는 여기서 곧장 exit 0 해서, done 단계에서 상태 파일이 무방비였다.
    # 제약이 있는데 판정기를 못 쓰면 "제약 없음"이 아니라 "판정 불가"다. 막는다.
    if [ ! -f "$GUARD" ] || ! command -v python3 >/dev/null 2>&1; then
      deny "명령 판정기를 사용할 수 없다 ($GUARD).
이 단계에는 제약이 걸려 있는데 무엇이 허용되는지 판정할 수 없다.
설치가 손상됐을 수 있다 — 다시 설치하라."
    fi
    VERDICT="$(printf '%s' "$CMD" | python3 "$GUARD" \
      "$(jq -c '.edit_files // null' <<<"$FORBID")" \
      "$(jq -r '.push' <<<"$FORBID")" \
      "$(jq -c '.bash // []' <<<"$FORBID")" \
      "$ROOT" "$WT" "$CWD" 2>/dev/null)" || deny "명령 판정 중 오류가 발생했다. 안전을 위해 차단한다."
    [ -n "$VERDICT" ] && deny "$VERDICT"
    exit 0 ;;
esac
exit 0
