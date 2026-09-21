"""Collect the validated Orders art and review evidence; never exports or publishes assets."""
import hashlib
import html
import json
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
UNITS = ('worker', 'worker_loaded', 'footman', 'crossbow', 'gryphon', 'reliquary', 'keep', 'depot', 'barracks', 'sanctum')

def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)

def archive(folder):
    target = folder.with_suffix('.zip')
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as out:
        for file in sorted(folder.rglob('*')):
            if file.is_file():
                out.write(file, file.relative_to(folder.parent))
    return {'path': str(target), 'bytes': target.stat().st_size,
            'sha256': hashlib.file_digest(target.open('rb'), 'sha256').hexdigest()}

def main():
    evidence = ROOT/'artifacts/orders'
    package = Path((ROOT/'artifacts/latest-package.txt').read_text(encoding='utf-8-sig').strip())
    assert package.is_dir() and package.parent == ROOT/'dist'
    for case in ('orders', 'megacorp', 'review', 'replay'):
        assert (package/'artifacts'/f'smoke-{case}.png').is_file(), f'Missing fused smoke {case}'
    bundle = ROOT/'dist'/('Orders-Art-Review-' + package.name.removeprefix('LoveRTS-'))
    bundle.mkdir(exist_ok=False)
    catalog = json.loads((ROOT/'assets/generated/catalog.json').read_text())
    allocation = json.loads((evidence/'texture-allocation.json').read_text())
    inventory = []
    for unit in UNITS:
        build = Path(catalog['units'][unit]).parts[3]
        source = ROOT/'artifacts/asset-build'/build/unit
        render = json.loads((source/'render.json').read_text())
        record = {k:render[k] for k in ('unitId','cellSize','anchorX','anchorY','directions','clips')}
        record.update(buildId=build, frameCount=len(render['frames']), decodedBytes=allocation['units'][unit])
        inventory.append(record)
        for name in (f'{unit}.blend','inventory.json','render.json','dependencies.json','contact-sheet.png'):
            if (source/name).exists(): copy(source/name,bundle/'scenes'/unit/name)
        preview = source/'motion-preview.png'
        if preview.exists(): copy(preview,bundle/'motion'/f'{unit}.png')
        copy(ROOT/'art/recipes'/f'{unit}.json',bundle/'art/recipes'/f'{unit}.json')
        copy(evidence/'reopened'/f'{unit}.png',bundle/'reopened'/f'{unit}.png')
    copy(ROOT/'scripts/select-orders-clip.py',bundle/'scripts/select-orders-clip.py')
    for name in ('orders-units.png','orders-buildings.png','prompts.txt'):
        copy(ROOT/'artifacts/concept-art'/name,bundle/'concepts'/name)
    for pattern in ('page-*.png','poses-*.png','playable-orders.png'):
        for file in sorted((evidence/'review').glob(pattern)): copy(file,bundle/'review'/file.name)
    for name in ('ORDERS_CATHEDRAL.md','ORDERS_ART_HANDOFF.md','ORDERS_CONCEPT_PROMPTS.md'):
        copy(ROOT/'docs/art'/name,bundle/name)
    for name in ('test-all.log','python-final.log','catalog-final.log','blend-verification.log',
                 'blend-verification.json','authoritative-source-check.json','prior-replay-check.log',
                 'performance-summary.json','performance-summary.md','texture-allocation.json','hardware.json',
                 'roof-regression.log','review-capture.log','clip-helper.log','package.log','package-smoke.log'):
        copy(evidence/name,bundle/'evidence'/name)
    for name in ('baseline','final-performance'):
        shutil.copytree(evidence/name,bundle/'evidence'/name)
    copy(ROOT/'assets/generated/catalog.json',bundle/'evidence/catalog.json')
    copy(package/'BUILD-INFO.json',bundle/'evidence/BUILD-INFO.json')
    copy(package/'artifacts/smoke-orders.png',bundle/'review/packaged-orders.png')
    payload={'assets':inventory,'allocation':allocation,'package':json.loads((package/'BUILD-INFO.json').read_text(encoding='utf-8-sig'))}
    for target in (evidence/'asset-inventory.json',bundle/'asset-inventory.json'):
        target.write_text(json.dumps(payload,indent=2)+'\n',encoding='utf8')
    cards=[]
    for unit in UNITS[:6]:
        cards.append(f'<article><h3>{unit}</h3><img src="motion/{unit}.png"><img class="zoom" src="motion/{unit}.png"><p><a href="scenes/{unit}/{unit}.blend">Editable Blender scene</a></p></article>')
    boards=[]
    for file in sorted((bundle/'review').glob('*.png')):
        boards.append(f'<figure><a href="review/{file.name}"><img class="board" src="review/{file.name}"></a><figcaption>{html.escape(file.stem)}</figcaption></figure>')
    page='''<!doctype html><meta charset="utf-8"><title>Orders cathedral review</title>
<style>body{background:#171b22;color:#e4e0d5;font:16px system-ui;margin:30px;max-width:1400px}a{color:#80caff}section{display:flex;flex-wrap:wrap;gap:20px}article{background:#292e35;padding:18px}img{image-rendering:pixelated}.zoom{width:192px;margin-left:20px}.board{width:100%;max-width:1200px}figure{margin:30px 0}</style>
<h1>Orders cathedral art</h1><p>Six unit variants, four buildings, ground-only Gryphon, unchanged gameplay.</p>
<p>Native APNGs play the exported clips. The adjacent enlarged version helps inspect motion; gameplay-camera boards below determine scale.</p>
<p><a href="ORDERS_ART_HANDOFF.md">Evidence and remaining failures</a> · <a href="ORDERS_CATHEDRAL.md">Workflow and five-minute playtest</a> · <a href="asset-inventory.json">Asset inventory</a></p>
<p>In Blender, import runpy and call runpy.run_path('/absolute/bundle/scripts/select-orders-clip.py')['select']('gryphon','move') to select synchronized actions at their authored speed. Original library actions remain preserved.</p>
<h2>Native motion previews</h2><section>'''+''.join(cards)+'</section><h2>Gameplay, scale, grayscale, silhouettes and every pose</h2>'+''.join(boards)+'''
<h2>Concepts</h2><p>Illustrative references; exported models and existing mechanics are authoritative.</p>
<a href="concepts/orders-units.png"><img class="board" src="concepts/orders-units.png"></a>
<a href="concepts/orders-buildings.png"><img class="board" src="concepts/orders-buildings.png"></a>'''
    (bundle/'index.html').write_text(page,encoding='utf8')
    manifest={'game':archive(package),'art':archive(bundle),'packageSmoke':['orders','megacorp','review','replay'],
              'gallery':str(bundle/'index.html'),'sourceRevision':payload['package']['sourceRevision']}
    (evidence/'delivery.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf8')
    print(json.dumps(manifest,indent=2))

if __name__ == '__main__': main()
