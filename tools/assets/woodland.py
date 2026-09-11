"""Experimental catalog builder; never publishes or packages the production catalog."""
import hashlib,json,subprocess,time,os,shutil
from pathlib import Path
from pack import pack,validate_unit,write_pair,digest
import pixel

CATALOG='assets/generated/woodland/catalog'

def validate(root):
    from pack import lua
    path=root/(CATALOG+'.json');cat=json.loads(path.read_text())
    assert (root/(CATALOG+'.lua')).read_text()=='return '+lua(cat)+'\n'
    assert set(cat['units'])=={'mouse_builder_32','mouse_builder_48','mouse_builder_64'}
    for name,path in cat['units'].items():
        m=validate_unit(root,path);assert m['unitId']==name
        from PIL import Image
        for page in m['pages']:
            pixel.validate_pixels(Image.open(root/page['color']),Image.open(root/page['mask']),m['pixelStyle'])
    return cat

def build(root,source,blender,mode='build',force=False):
    started=time.monotonic();recipe_path=root/'art/recipes/woodland/mouse_builder.json'
    recipe=json.loads(recipe_path.read_text(encoding='utf-8-sig'))
    if mode=='validate':validate(root);print('Woodland catalog validated');return
    assert digest(source)==recipe['sourceHash'],'Saved rig source differs from pin'
    version=subprocess.check_output([blender,'--version'],text=True).splitlines()[0]
    source_files=[source,recipe_path]+[root/'tools/blender'/x for x in ['pipeline.py','unit_model.py','woodland_model.py','woodland_export.py']]
    revision=hashlib.sha256((version+''.join(digest(p) for p in source_files)).encode()).hexdigest()[:24]
    cleanup_root=root/'art/cleanup/woodland';pixel.cleanup_manifest(cleanup_root,revision)
    cleanup_files=sorted(p for p in cleanup_root.rglob('*') if p.is_file() and p.suffix.lower() in ('.json','.png','.aseprite'))
    key=hashlib.sha256((revision+''.join(digest(root/'tools/assets'/n) for n in ['pack.py','pixel.py','woodland.py'])+''.join(digest(p) for p in cleanup_files)).encode()).hexdigest()[:24]
    base=root/'artifacts/woodland'/revision;render=base/('preview' if mode=='preview' else 'render');render.mkdir(parents=True,exist_ok=True)
    cached_render=(render/'render.json').exists()
    if force or not cached_render:
        command=[blender,'--background','--factory-startup','--python-exit-code','1','--python',str(root/'tools/blender/pipeline.py'),'--','--root',str(root),'--source',str(source),'--unit','mouse_builder','--output',str(render)]
        if mode=='preview':command.append('--preview')
        print('Rendering mouse; log: '+str(render/'blender.log'),flush=True)
        with (render/'blender.log').open('w') as log:subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
    raw=json.loads((render/'render.json').read_text())
    assert raw['sourceHash']==recipe['sourceHash'] and raw['preview']==(mode=='preview')
    expected=sum(x['samples'] for x in raw['clips'].values())*8
    assert len(raw['frames'])==expected
    raw_hashes={f[k]:digest(render/f[k]) for f in raw['frames'] for k in ('color','mask')}
    receipt=render/'raw-hashes.json'
    if receipt.exists() and not force:
        assert json.loads(receipt.read_text())==raw_hashes,'Raw render cache changed; use -Force to regenerate'
    else:receipt.write_text(json.dumps(raw_hashes,sort_keys=True))

    entries={};results=[]
    for height in recipe['bodyHeights']:
        unit='mouse_builder_'+str(height);stage=base/(mode+'-'+str(height));stage.mkdir(parents=True,exist_ok=True)
        spec=dict(raw);spec.update(unitId=unit,rawCellSize=raw['cellSize'],cellSize=raw['cellSize']*height//64,anchorX=raw['anchorX']*height//64,anchorY=raw['anchorY']*height//64,bodyHeightPixels=height,pixelStyle={k:recipe[k] for k in ['palette','teamStart','teamRamps']},sourceRevision=revision,cleanupRoot=str(cleanup_root))
        (stage/'render.json').write_text(json.dumps(spec,indent=2))
        prefix='assets/generated/woodland/builds/'+key+'/'+unit
        output=root/prefix;metadata=prefix+'/metadata.lua'
        if mode=='preview':output=stage/'packed'
        cached=False
        if output.exists() and mode=='build' and not force:
            try:validate_unit(root,metadata);cached=True
            except Exception:pass
        if not cached:
            incoming=stage/'packed-incoming'
            # Unique key protects existing outputs; pack overwrites only its own staging files.
            pack(stage,incoming,key,prefix,raw_root=render)
            if mode=='build' and output.exists():
                assert json.loads((output/'validation.json').read_text())==json.loads((incoming/'validation.json').read_text()),'Immutable pixel output changed; review source revision'
            else:
                output.parent.mkdir(parents=True,exist_ok=True);shutil.copytree(incoming,output,dirs_exist_ok=True)
        if mode=='build':
            m=validate_unit(root,metadata)
            from PIL import Image
            for page in m['pages']:
                pixel.validate_pixels(Image.open(root/page['color']),Image.open(root/page['mask']),m['pixelStyle'])
            entries[unit]=metadata
        results.append({'unit':unit,'cached':cached,'metadata':metadata,'stage':str(stage)})
    report={'sourceRevision':revision,'buildId':key,'mode':mode,'renderCached':cached_render and not force,'framesPerVariant':expected,'results':results,'seconds':time.monotonic()-started}
    if mode=='build':
        target=root/CATALOG;target.parent.mkdir(parents=True,exist_ok=True)
        cat={'version':2,'units':entries};write_pair(target.parent/'incoming',cat)
        # Commit point is Lua, as in the production pipeline; no production paths are touched.
        for ext in ['json','lua']:os.replace(target.parent/('incoming.'+ext),target.with_suffix('.'+ext))
        validate(root)
    (root/'artifacts/woodland/latest-report.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))
