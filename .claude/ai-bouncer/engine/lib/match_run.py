"""직접 실행한 Bash 명령이 어느 run step 과 같은 검사인지 가린다.

먹맵(2026-10-23): 범위 e2e 를 `npx playwright test …` 로 직접 돌려 통과했는데
`bouncer run` 으로 돌린 것만 인정해 6분짜리를 기록용으로 다시 돌렸다.
같은 명령을 성공적으로 돌렸으면 그 결과를 증거로 받는다. 대신 결과를 숨길 수 있는
모양(파이프·연결·리다이렉트)이나 검사를 줄이는 옵션이 붙은 것은 받지 않는다.

입력(stdin, JSON): {cmd, work_root, steps:[{id, run}], scopes:{id:[경로]}}
출력: 맞는 step 마다 한 줄 "<id>\t<args JSON>"
"""
import json, os, re, shlex, sys

# 결과에 영향 없는 출력·병렬 옵션만 허용한다. --list·--grep·--last-failed 처럼
# 덜 돌리는 옵션은 받지 않는다.
HARMLESS = re.compile(r"^(--workers(=\S+)?|-j\d*|--reporter(=\S+)?|--headed|--quiet|-q|-v|--verbose|--colou?r(=\S+)?|--no-colou?r)$")


def norm(p):
    return p[2:] if p.startswith("./") else p


def main():
    d = json.load(sys.stdin)
    c = d["cmd"].strip()
    wr = os.path.realpath(d["work_root"])
    m = re.match(r"^cd\s+(\S+)\s*&&\s*(.*)$", c, re.S)
    if m:
        if os.path.realpath(os.path.expanduser(m.group(1).strip("\"'"))) != wr:
            return
        c = m.group(2).strip()
    c = re.sub(r"\s+2>&1\s*$", "", c)
    if re.search(r"[|;&<>`\n]|\$\(", c):
        return
    try:
        toks = shlex.split(c)
    except ValueError:
        return
    for s in d["steps"]:
        run = s.get("run") or ""
        if re.search(r"[|;&<>`\n]|\$\(", run.replace("{scope}", "")):
            continue
        bt = shlex.split(run)
        base = [t for t in bt if t != "{scope}"]
        # 프로그램 부분(옵션 전까지)은 그대로 같아야 한다
        head = []
        for t in base:
            if t.startswith("-"):
                break
            head.append(t)
        if toks[: len(head)] != head:
            continue
        rest, tail = toks[len(head):], base[len(head):]
        want_opts = [t for t in tail if t.startswith("-")]
        fixed = [t for t in tail if not t.startswith("-")]   # 명령에 원래 박힌 경로
        args, opts = [], []
        for t in rest:
            (opts if t.startswith("-") else args).append(t)
        if any(o not in want_opts and not HARMLESS.match(o) for o in opts):
            continue
        if any(o not in opts and not HARMLESS.match(o) for o in want_opts):
            continue
        if any(f not in args for f in fixed):
            continue
        args = [norm(a) for a in args if a not in fixed]
        want = [norm(p) for p in d["scopes"].get(s["id"], [])]
        if want and not set(want) <= set(args):
            continue
        print(f'{s["id"]}\t{json.dumps(args, ensure_ascii=False)}')


main()
