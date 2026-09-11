"""Transactional asset build command. Requires Python 3.10+ and Pillow."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid
from pack import contained, digest, lua, pack, validate_unit, write_pair

ROSTER = ['shieldguard','worker','worker_loaded','crossbow','warden']

def build_key(root, source, unit, version):
    files = [source, root/'art/recipes'/f'{unit}.json']
    files += sorted((root/'art/recipes').glob('*profile*.json'))
    files += sorted((root/'tools/blender').glob('*.py')) + sorted((root/'tools/assets').glob('*.py'))
    h = hashlib.sha256(version.encode())
    for p in files:
        h.update(p.name.encode()); h.update(p.read_bytes())
    return h.hexdigest()[:24], {str(p.relative_to(root)) if p.is_relative_to(root) else str(p):digest(p) for p in files}

def validate_worker_pair(metadata):
    if not all(unit in metadata for unit in ('worker','worker_loaded')): return
    ordinary, loaded = metadata['worker'], metadata['worker_loaded']
    if ordinary.get('referenceStride') != loaded.get('referenceStride'):
        raise ValueError('Worker cargo variants have incompatible reference stride')
    if set(ordinary['clips']) != set(loaded['clips']):
        raise ValueError('Worker cargo variants have incompatible clips')
    for name, clip in ordinary['clips'].items():
        other = loaded['clips'][name]
        if any(clip.get(k) != other.get(k) for k in ('durationMs','loop','contactFrame')):
            raise ValueError('Worker cargo variants have incompatible clip timing: '+name)
        for direction, frames in clip['frames'].items():
            other_frames = other['frames'][direction]
            if len(frames) != len(other_frames): raise ValueError('Worker cargo variants have incompatible sample counts')
            for first, second in zip(frames,other_frames):
                a, b = ordinary['frames'][first-1], loaded['frames'][second-1]
                if any(a[k] != b[k] for k in ('width','height','anchorX','anchorY')):
                    raise ValueError('Worker cargo variants have incompatible frame anchors')

def read_catalog(root, required=None, validate_assets=True):
    base = root/'assets/generated/catalog'
    if not base.with_suffix('.lua').exists():
        # Lua alone commits publication. JSON without Lua is an interrupted
        # first publication and must not prevent a fresh build or v1 fallback.
        return None
    cat = json.loads(base.with_suffix('.json').read_text(encoding='utf8'))
    active_lua = base.with_suffix('.lua').read_text(encoding='utf8')
    if active_lua != 'return ' + lua(cat) + '\n':
        # A hard interruption can occur after JSON replacement but before the
        # atomic runtime commit. The backed-up JSON then describes active Lua.
        backup = base.parent/'catalog.previous.json'
        previous = json.loads(backup.read_text(encoding='utf8')) if backup.exists() else None
        if previous is None or active_lua != 'return ' + lua(previous) + '\n': raise ValueError('Catalog Lua/JSON mismatch')
        cat = previous
    if cat.get('version') != 2: raise ValueError('Unsupported catalog version')
    if validate_assets:
        metadata = {}
        for unit in required or cat['units']:
            if unit not in cat['units']: raise ValueError('Required asset absent: ' + unit)
            meta = validate_unit(root, cat['units'][unit])
            if meta['unitId'] != unit: raise ValueError('Catalog unit identity mismatch')
            metadata[unit] = meta
        validate_worker_pair(metadata)
    return cat

def publish(root, units):
    base = root/'assets/generated'
    base.mkdir(parents=True, exist_ok=True)
    # Replaced entries need not be readable: a new build is also how corrupt
    # old assets are repaired. Validate every final merged entry below instead.
    previous = read_catalog(root, validate_assets=False)
    cat = {'version':2, 'units':dict(previous['units']) if previous else {}}
    cat['units'].update(units)
    metadata = {}
    for unit, path in cat['units'].items():
        metadata[unit] = validate_unit(root, path)
        if metadata[unit]['unitId'] != unit: raise ValueError('Invalid catalog identity')
    validate_worker_pair(metadata)
    token = uuid.uuid4().hex
    # Runtime publication is one atomic replace of catalog.lua; JSON is inspection data.
    write_pair(base / ('catalog-' + token), cat)
    old = {}
    for ext in ('json','lua'):
        target = base / ('catalog.'+ext)
        old[ext] = target.read_bytes() if target.exists() else None
        if target.exists(): shutil.copy2(target, base/('catalog.previous.'+ext))
    try:
        for ext in ('json','lua'):
            os.replace(base/('catalog-'+token+'.'+ext), base/('catalog.'+ext))
    except Exception:
        # In particular, Windows may refuse replacement while a reader holds Lua.
        # Restore inspection data so the previous runtime catalog remains usable.
        for ext in ('json','lua'):
            target = base/('catalog.'+ext)
            if old[ext] is None:
                target.unlink(missing_ok=True)
            elif target.read_bytes() != old[ext]:
                target.write_bytes(old[ext])
        raise
    return cat

def package(root, destination):
    cat = read_catalog(root, ROSTER if (root/'assets/generated/catalog.lua').exists() else None)
    source = root/'assets/generated'
    if not source.exists(): return
    if not cat:
        # Only the legacy proof files, never stale v2 builds or unrelated generated output.
        for name in ('shieldguard.png','shieldguard_mask.png','shieldguard.lua','shieldguard.json','shieldguard-mask.png'):
            p = source/name
            if p.exists():
                target = destination/'assets/generated'/name
                target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(p,target)
        return
    paths = set()
    catalog_target = destination/'assets/generated/catalog'
    catalog_target.parent.mkdir(parents=True,exist_ok=True)
    write_pair(catalog_target,cat)
    for entry in cat['units'].values():
        meta = validate_unit(root, entry)
        p = contained(root, entry)
        paths.update((p,p.with_suffix('.json'),p.parent/'validation.json'))
        for page in meta['pages']:
            paths.update(contained(root,page[k]) for k in ('color','mask'))
    for p in sorted(paths):
        target = destination/p.relative_to(root)
        target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(p,target)

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2])
    ap.add_argument('--source',type=Path)
    ap.add_argument('--blender',default=r'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe')
    ap.add_argument('--mode',choices=['build','preview','inspect','validate','legacy','package'],default='build')
    ap.add_argument('--unit',action='append'); ap.add_argument('--roster',choices=['bastion','woodland'],default='bastion')
    ap.add_argument('--force',action='store_true'); ap.add_argument('--destination',type=Path)
    args = ap.parse_args(argv); root = args.root.resolve()
    if args.roster == 'woodland':
        if args.mode not in ('build','preview','validate') or args.unit:
            raise ValueError('Woodland pilot supports Build/Preview/Validate with its three fixed variants')
        from woodland import build
        return build(root,(args.source or root/'art/source/rig-library/RTSAssets.blend').resolve(),args.blender,args.mode,args.force)
    units = args.unit or ROSTER
    if any(u not in ROSTER for u in units): raise ValueError('Unknown unit; choose '+', '.join(ROSTER))
    if args.mode == 'package':
        if not args.destination: raise ValueError('Package requires --destination')
        package(root,args.destination.resolve()); print('Active assets packaged and verified.'); return
    if args.mode == 'validate':
        if not read_catalog(root,units): raise ValueError('No v2 catalog to validate')
        print('Validated: '+', '.join(units)); return
    source = (args.source or root/'art/source/rig-library/RTSAssets.blend').resolve()
    if not source.is_file() and args.mode != 'legacy': raise ValueError('Saved Blender source missing: '+str(source))
    version = subprocess.check_output([args.blender,'--version'],text=True).splitlines()[0]
    if args.mode == 'legacy':
        subprocess.run([args.blender,'--background','--factory-startup','--python-exit-code','1','--python',str(root/'tools/blender/export_unit.py'),'--',str(root)],check=True); return
    entries, results, failures = {}, [], []
    batch_start = time.monotonic()
    for unit in units:
        started = time.monotonic()
        key, deps = build_key(root,source,unit,version)
        stage = root/'artifacts/asset-build'/(key+('-preview' if args.mode == 'preview' else ''))/unit
        output = root/'assets/generated/builds'/key/unit
        metadata = (output/'metadata.lua').relative_to(root).as_posix()
        try:
            invalid_cache = False
            if args.mode == 'build' and output.exists():
                try: validate_unit(root, metadata)
                except Exception: invalid_cache = True
                if not args.force and not invalid_cache:
                    entries[unit] = metadata
                    results.append({'unit':unit,'cached':True,'buildId':key}); print(unit+': valid cache'); continue
            stage.mkdir(parents=True,exist_ok=True)
            (stage/'dependencies.json').write_text(json.dumps({'blender':version,'files':deps},indent=2),encoding='utf8')
            command = [args.blender,'--background','--factory-startup','--python-exit-code','1','--python',str(root/'tools/blender/pipeline.py'),'--','--root',str(root),'--source',str(source),'--unit',unit,'--output',str(stage),'--mode','inspect' if args.mode == 'inspect' else 'render']
            if args.mode == 'preview': command.append('--preview')
            print('Rendering '+unit+'; log: '+str(stage/'blender.log'),flush=True)
            with (stage/'blender.log').open('w',encoding='utf8') as log:
                subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
            if args.mode != 'inspect':
                packed = stage/('packed-'+uuid.uuid4().hex)
                prefix = output.relative_to(root).as_posix()
                pack(stage,packed,key,prefix)
                if args.mode == 'build':
                    output.parent.mkdir(parents=True,exist_ok=True)
                    if output.exists() and not invalid_cache:
                        # Never modify an active immutable build during --force verification.
                        old = json.loads((output/'validation.json').read_text())
                        new = json.loads((packed/'validation.json').read_text())
                        if old != new: raise ValueError('Forced rebuild differs from immutable build; retain artifacts and use a new source/recipe revision')
                    else:
                        incoming = output.parent/(unit+'-incoming-'+uuid.uuid4().hex)
                        shutil.copytree(packed,incoming)
                        if output.exists():
                            os.replace(output,output.parent/(unit+'-corrupt-'+uuid.uuid4().hex))
                        os.replace(incoming,output)
                    validate_unit(root,metadata); entries[unit] = metadata
            results.append({'unit':unit,'buildId':key,'seconds':round(time.monotonic()-started,2),'stage':str(stage)})
        except Exception as e:
            failures.append({'unit':unit,'error':str(e)}); print(unit+': FAILED: '+str(e),file=sys.stderr)
    report = {'mode':args.mode,'seconds':round(time.monotonic()-batch_start,2),'results':results,'failures':failures}
    report_path = root/'artifacts/asset-build/latest-report.json'; report_path.parent.mkdir(parents=True,exist_ok=True)
    report_path.write_text(json.dumps(report,indent=2),encoding='utf8')
    if failures: raise ValueError('Asset batch failed; previous catalog preserved. See '+str(report_path))
    if args.mode == 'build': publish(root,entries)
    print(json.dumps(report,indent=2))

if __name__ == '__main__':
    try: main()
    except Exception as exc: print('Asset pipeline: '+str(exc),file=sys.stderr); sys.exit(1)
