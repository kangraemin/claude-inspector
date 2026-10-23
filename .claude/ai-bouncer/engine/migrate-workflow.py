#!/usr/bin/env python3
"""옛 전체 사본 workflow.yaml 을 "기본값과 다른 것만" 남긴 override 로 바꾼다.

install/update 때마다 돈다. 이미 override 인 파일에는 아무것도 바꾸지 않는다(멱등).
기준은 legacy-defaults.json(과거 default.yaml 전 버전의 지문)과 현재 default.yaml 이다:
  - 어느 버전의 기본값 step 과도 같은(label + 내용) step 은 버린다 → 최신 기본값이 대신 쓰인다.
  - 기본값과 같은 settings / forbid / on_fail / workflow 는 버린다. 폐기된 키(forbid.edit_files 등)도 버린다.
  - 다른 것만 남는다. 주석은 사라진다. 원본은 workflow.yaml.bak 로 남긴다.
  - 옛 기본값에는 있었는데 사본에서 사용자가 지운 step 은 `remove:` 로 남긴다.
  - 옛 기본값 그대로인 prompts/*.md 는 지운다(기본 프롬프트는 이제 엔진이 갖는다).
usage: migrate-workflow.py <workflow.yaml>
"""
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import compile as C            # noqa: E402
import legacy as L             # noqa: E402

HEADER = '''# ai-bouncer 레포별 워크플로우 설정 — 기본값과 다른 것만 적는다.
# 기본값은 엔진(.claude/ai-bouncer/engine/default.yaml)이 갖고 업데이트 때마다 바뀐다.
# 병합 규칙: settings 는 키 단위 덮기 / stages.<이름>.steps 는 label 이 같으면 교체·새 label 이면 뒤에 추가 /
#            remove: [label…] 로 기본 step 삭제 / forbid 는 키 단위 덮기. 스키마: docs/SCHEMA.md
'''


# ── 최소 YAML 출력기 (pyyaml·내장 파서 양쪽에서 같은 값으로 읽히는 부분집합) ──────────
def _key(k):
    return k if re.match(r'^[A-Za-z_][\w.-]*$', k) else json.dumps(k, ensure_ascii=False)


def _block_ok(s):
    if '\n' not in s.rstrip('\n') or '\r' in s or '\t' in s or s.endswith('\n\n'):
        return False
    lines = s.rstrip('\n').split('\n')
    return not lines[0].startswith(' ') and not any(l != l.rstrip() for l in lines)


def _scalar(v, ind, block):
    if v is None:
        return 'null'
    if v is True:
        return 'true'
    if v is False:
        return 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        if block and _block_ok(v):
            head = '|' if v.endswith('\n') else '|-'
            pad = ' ' * (ind + 2)
            body = '\n'.join((pad + l) if l else '' for l in v.rstrip('\n').split('\n'))
            return head + '\n' + body
        return json.dumps(v, ensure_ascii=False)
    raise TypeError(type(v))


def emit(obj, ind=0, block=True):
    pad = ' ' * ind
    out = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, dict) and v:
                out.append('%s%s:\n%s' % (pad, _key(k), emit(v, ind + 2, block)))
            elif isinstance(v, list) and v and any(isinstance(x, dict) for x in v):
                out.append('%s%s:\n%s' % (pad, _key(k), emit(v, ind + 2, block)))
            elif isinstance(v, list):
                out.append('%s%s: [%s]' % (pad, _key(k), ', '.join(json.dumps(x, ensure_ascii=False) for x in v)))
            elif isinstance(v, dict):
                out.append('%s%s: {}' % (pad, _key(k)))
            else:
                out.append('%s%s: %s' % (pad, _key(k), _scalar(v, ind, block)))
    else:                                    # 리스트 (항목은 매핑)
        for x in obj:
            body = emit(x, ind + 2, block).split('\n')
            body[0] = pad + '- ' + body[0][ind + 2:]
            out.append('\n'.join(body))
    return '\n'.join(out)


# ── 변환 ─────────────────────────────────────────────────────
def load_legacy():
    for p in (os.path.join(HERE, 'legacy-defaults.json'),
              os.path.join(HERE, '..', 'config', 'legacy-defaults.json')):
        if os.path.isfile(p):
            with open(p, encoding='utf-8') as fh:
                return json.load(fh)
    return None


def best_version(versions, stage, steps):
    """이 사본이 어느 기본값 버전에서 갈라졌는지 — step 이 가장 많이 겹치는 버전. 동률이면 앞(최신)."""
    best, score = None, 0
    for v in versions:
        sv = v['stages'].get(stage)
        if not sv:
            continue
        pool = sv['steps']
        n = sum(1 for st in steps if L.norm_step(st) in pool)
        if n > score:
            best, score = v, n
    return best


def convert(raw, base_raw, legacy, repo_dir):
    """(override dict, 지울 prompts 상대경로 목록)"""
    base = L.snapshot(base_raw)
    versions = [base] + legacy['versions']
    olds = legacy['versions']
    known_prompts = legacy.get('prompts', {})
    drop_files, keep_refs = set(), set()
    ov = {'version': 1}

    eff = dict(C.SETTINGS, **(base_raw.get('settings') or {}))
    st_out = {}
    for k, v in (raw.get('settings') or {}).items():
        if k in C.RETIRED_SETTINGS or v == eff.get(k):
            continue
        if any(k in ver['settings'] and ver['settings'][k] == v for ver in versions):
            continue
        st_out[k] = v
    if st_out:
        ov['settings'] = st_out

    wf_out = {}
    for n, w in (raw.get('workflows') or {}).items():
        snap = {'label': (w or {}).get('label'), 'stages': (w or {}).get('stages')}
        if any(ver['workflows'].get(n) == snap for ver in versions):
            continue
        wf_out[n] = w
    if wf_out:
        ov['workflows'] = wf_out

    stages_out = {}
    for n, body in (raw.get('stages') or {}).items():
        body = body or {}
        steps = body.get('steps') or []
        pools = [ver['stages'][n]['steps'] for ver in versions if n in ver['stages']]
        vstar = best_version(olds, n, steps)
        out = {}

        kept, labels = [], set()
        for stp in steps:
            norm = L.norm_step(stp)
            if stp.get('label'):
                labels.add(stp['label'])
            same = any(norm in pool for pool in pools)
            if same and stp.get('inject_file'):
                path = os.path.join(repo_dir, stp['inject_file'])
                known = known_prompts.get(stp['inject_file'], [])
                if os.path.isfile(path):
                    with open(path, encoding='utf-8') as fh:
                        if L.sha(fh.read()) not in known:
                            same = False          # 프롬프트 파일을 고쳤다 — 사용자 것이다
                        else:
                            drop_files.add(stp['inject_file'])
            if not same:
                kept.append(stp)
                if stp.get('inject_file'):
                    keep_refs.add(stp['inject_file'])

        if n in base['stages'] and vstar is not None:
            gone = [s['label'] for s in base['stages'][n]['steps']
                    if s.get('label') and s['label'] not in labels
                    and any(x.get('label') == s['label'] for x in vstar['stages'][n]['steps'])]
            if gone:
                out['remove'] = gone
        if kept:
            out['steps'] = kept

        bst = base['stages'].get(n, {'forbid': {}, 'on_fail': None})
        vst = vstar['stages'][n] if vstar else {'forbid': {}, 'on_fail': None}
        f = L.norm_forbid(body.get('forbid'))
        p = bool(f.get('push'))
        fo = {}
        if p != bool(bst['forbid'].get('push')) and p != bool(vst['forbid'].get('push')):
            fo['push'] = p
        r = f.get('reason', '')
        raw_reason = (body.get('forbid') or {}).get('reason', '')
        if r and not any(r == ver['stages'].get(n, {}).get('forbid', {}).get('reason') for ver in versions):
            fo['reason'] = raw_reason
        elif fo.get('push') and r:
            fo['reason'] = raw_reason
        if fo:
            out['forbid'] = fo
        of = body.get('on_fail')
        if of != bst['on_fail'] and of != vst['on_fail']:
            out['on_fail'] = of

        if out:
            stages_out[n] = out
    if stages_out:
        ov['stages'] = stages_out
    return ov, sorted(drop_files - keep_refs)


def main(argv):
    if len(argv) < 2:
        sys.stderr.write('usage: migrate-workflow.py <workflow.yaml>\n')
        return 2
    path = os.path.abspath(argv[1])
    if not os.path.isfile(path):
        return 0
    repo_dir = os.path.dirname(path)
    try:
        raw, _ = C.load_yaml(path)
        base_path = C.find_base(HERE)
        legacy = load_legacy()
        if not raw or not isinstance(raw, dict) or raw.get('base') or not base_path or not legacy:
            return 0
        if set(raw) - C.ROOT_KEYS:
            return 0
        base_raw, _ = C.load_yaml(base_path)
        ov, drop_files = convert(raw, base_raw, legacy, repo_dir)

        # 같은 결과면 건드리지 않는다(멱등). 비교는 파싱된 값으로 한다.
        cur = {k: v for k, v in raw.items()}
        if json.dumps(cur, sort_keys=True, ensure_ascii=False) == json.dumps(ov, sort_keys=True, ensure_ascii=False):
            return 0

        text = None
        for block in (True, False):
            cand = HEADER + '\n' + emit(ov, 0, block) + '\n'
            tmp = path + '.migrate.tmp'
            with open(tmp, 'w', encoding='utf-8') as fh:
                fh.write(cand)
            try:
                a, _ = C.load_yaml(tmp)
                b, _ = C.load_yaml(tmp, force_mini=True)
            finally:
                os.unlink(tmp)
            if a == ov and b == ov:
                text = cand
                break
        if text is None:
            sys.stderr.write('ai-bouncer: workflow.yaml 변환 결과가 원본과 달라 건너뛴다(그대로 둔다)\n')
            return 0
        # 변환 결과가 컴파일되는지 본다. 안 되면 원본을 건드리지 않는다.
        sources = []
        merged = C.merge_raw(base_raw, os.path.dirname(base_path), ov, repo_dir)
        C.compile_config(merged, repo_dir, sources)
    except Exception as exc:                 # 마이그레이션 실패가 설치를 막으면 안 된다
        sys.stderr.write('ai-bouncer: workflow.yaml 변환 건너뜀 — %s\n' % exc)
        return 0

    bak = path + '.bak'
    if os.path.exists(bak):
        bak = '%s.bak-%s' % (path, time.strftime('%Y%m%d%H%M%S'))
    with open(path, encoding='utf-8') as fh:
        orig = fh.read()
    with open(bak, 'w', encoding='utf-8') as fh:
        fh.write(orig)
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(text)
    for rel in drop_files:
        try:
            os.unlink(os.path.join(repo_dir, rel))
        except OSError:
            pass
    left = sum(len(v) if isinstance(v, (dict, list)) else 1 for k, v in ov.items() if k != 'version')
    print('  workflow.yaml: 기본값과 같은 부분을 걷어내고 override만 남김 (남은 항목 %d, 원본 %s)'
          % (left, os.path.basename(bak)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
