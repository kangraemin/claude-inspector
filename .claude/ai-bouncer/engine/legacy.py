"""과거 기본값 비교용 공용 함수 (migrate-workflow.py 와 tools/gen-legacy-defaults.py 가 쓴다)."""
import hashlib

# 비교에서는 없는 것으로 본다. plan_approved 는 폐기됐고, done 은 옛 기본값의 자기신고(verify 보고)에만
# 쓰였다 — 지금 기본값에서 빠진 게이트라 이 값 차이로 '사용자가 고친 사본'으로 오판하지 않게 한다.
RETIRED_BLOCKING = ('done', 'plan_approved')


def norm_step(st):
    """step 하나를 비교용으로 정규화한다. 같은 동작이면 같은 값이 나온다."""
    out = {}
    if not isinstance(st, dict):
        return None
    for k in ('label', 'inject', 'inject_file', 'run'):
        v = st.get(k)
        if v is None:
            continue
        out[k] = ' '.join(v.split()) if isinstance(v, str) else v
    b = st.get('blocking')
    if b is not None and b not in RETIRED_BLOCKING:
        out['blocking'] = b
    if st.get('optional'):
        out['optional'] = True
    if 'run' in st:
        by = st.get('by', 'model')
        out['by'] = by
        out['timeout'] = int(st.get('timeout', 30 if by == 'engine' else 600))
    return out


def norm_forbid(f):
    """edit_files 는 폐기됐으므로 비교에서 뺀다."""
    f = f or {}
    out = {}
    if f.get('push'):
        out['push'] = True
    if f.get('reason'):
        out['reason'] = ' '.join(str(f['reason']).split())
    return out


def snapshot(raw):
    """default.yaml 한 버전을 지문(JSON 가능)으로 만든다."""
    stages = {}
    for n, b in (raw.get('stages') or {}).items():
        b = b or {}
        stages[n] = {'steps': [norm_step(s) for s in (b.get('steps') or [])],
                     'forbid': norm_forbid(b.get('forbid')),
                     'on_fail': b.get('on_fail')}
    wfs = {n: {'label': (w or {}).get('label'), 'stages': (w or {}).get('stages')}
           for n, w in (raw.get('workflows') or {}).items()}
    return {'settings': raw.get('settings') or {}, 'workflows': wfs, 'stages': stages}


def sha(text):
    return hashlib.sha256(' '.join(text.split()).encode('utf-8')).hexdigest()
