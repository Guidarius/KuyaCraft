"""Summarize sequential pre/post art runs without hiding failed budgets or variation."""
import json,re,statistics
from pathlib import Path
root=Path(__file__).resolve().parents[1]
base=root/'artifacts/orders/baseline';final=root/'artifacts/orders/final-performance'
result={'sets':{},'canonicalUnchanged':True}
for label,directory in [('before',base),('after',final)]:
    rows={}
    for kind in ['fresh','live-orders','live-megacorp']:
        runs=[]
        for i in range(1,4):
            text=(directory/f'performance-{kind}-{i}.log').read_text(encoding='utf-8-sig')
            measures={m[0]:dict(zip(['p50','p95','p99','max'],map(float,m[1:]))) for m in re.findall(r'DIST (\w+) p50 ([\d.]+) p95 ([\d.]+) p99 ([\d.]+) max ([\d.]+)',text)}
            checkpoints=re.findall(r'CHECKPOINT (\d+) ([a-f0-9]+)',text)
            runs.append(dict(measures=measures,checkpoints=checkpoints,gateFailed='GATE FAIL' in text or 'FAIL ' in text,
                textureBytes=(int(re.search(r'TEXTURE_BYTES (\d+)',text)[1]) if 'TEXTURE_BYTES' in text else None),
                authoritativeBuild=(re.search(r'AUTHORITATIVE_BUILD (\w+)',text)[1] if 'AUTHORITATIVE_BUILD' in text else None),
                clampedSeconds=(float(re.search(r'frame time clamped ([\d.]+)',text)[1]) if 'frame time clamped' in text else None)))
        rows[kind]=runs
    result['sets'][label]=rows
for kind in result['sets']['before']:
    a=result['sets']['before'][kind];b=result['sets']['after'][kind]
    assert all(r['checkpoints']==a[0]['checkpoints'] for r in a+b),(kind,'Canonical checkpoint changed')
    assert all(r['authoritativeBuild']==a[0]['authoritativeBuild'] for r in a+b),(kind,'Authoritative build changed')
lines=['# Orders art performance comparison','','Three fresh processes per test, sequential 1080p/240-unit runs. Blender stopped. Values are medians of run p95, with min–max run p95 in parentheses. No performance improvement is claimed.','','| Scenario / metric | Before ms | After ms |','|---|---:|---:|']
for kind,metrics in [('fresh',['step_ms']),('live-orders',['step_ms','whole_tick_ms','frame_ms']),('live-megacorp',['step_ms','whole_tick_ms','frame_ms'])]:
    for metric in metrics:
        cells=[]
        for label in ['before','after']:
            v=[r['measures'][metric]['p95'] for r in result['sets'][label][kind]]
            cells.append(f'{statistics.median(v):.3f} ({min(v):.3f}–{max(v):.3f})')
        lines.append('| '+kind+' / '+metric+' | '+' | '.join(cells)+' |')
lines+=['','Full p50/p95/p99/max, draw calls, sampled heap, texture bytes, frame clamps and per-run gate results are preserved in performance-summary.json and raw logs. Checkpoints and authoritative source fingerprints match in every corresponding run.']
(root/'artifacts/orders/performance-summary.json').write_text(json.dumps(result,indent=2))
(root/'artifacts/orders/performance-summary.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
print('\n'.join(lines))
