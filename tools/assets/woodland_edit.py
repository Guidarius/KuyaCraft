"""Optional Aseprite round trip. Baselines and editor files never overwrite themselves."""
import argparse,json,subprocess,shutil,os
from pathlib import Path
from PIL import Image
import pixel
from pack import lua,contained,digest

def metadata(root,height):
    cat=json.loads((root/'assets/generated/woodland/catalog.json').read_text())
    return json.loads((root/cat['units']['mouse_builder_'+str(height)]).with_suffix('.json').read_text())

def frames(root,m):
    pages={}
    for clip,c in m['clips'].items():
        for direction,ids in c['frames'].items():
            for sample,i in enumerate(ids,1):
                f=m['frames'][i-1];box=(f['x'],f['y'],f['x']+f['width'],f['y']+f['height'])
                images=[]
                for kind in ('color','mask'):
                    path=m['pages'][f['page']-1][kind]
                    if path not in pages:pages[path]=Image.open(root/path).convert('RGBA')
                    images.append(pages[path].crop(box))
                yield f"{m['bodyHeightPixels']}/{clip}/{direction}/{sample}",images,c['durationMs']/len(ids)/1000

def run_editor(exe,folder,code):
    script=folder/'operation.lua';script.write_text(code,encoding='utf8')
    prefs=folder/'aseprite-config';prefs.mkdir(exist_ok=True)
    result=subprocess.run([exe,'--batch','--verbose','--script',str(script)],env={**os.environ,'ASEPRITE_USER_FOLDER':str(prefs)},capture_output=True,text=True)
    if result.stdout:print(result.stdout)
    if result.stderr:print(result.stderr)
    if result.returncode:
        raise RuntimeError('Aseprite failed; inspect '+str(prefs/'aseprite.log'))

def prepare(root,height,folder,exe):
    m=metadata(root,height)
    if folder.exists():raise ValueError('Editor workspace already exists; preserving it. Choose another --workspace.')
    folder.mkdir(parents=True)
    records=[];code=[]
    for i,(key,images,duration) in enumerate(frames(root,m),1):
        if i==1:code += [f'local s=Sprite({images[0].width},{images[0].height})','local color=s.layers[1];color.name="color"','local mask=s:newLayer();mask.name="mask";mask.isVisible=false']
        else:code += ['s:newEmptyFrame()']
        code += [f's.frames[{i}].duration={duration}']
        for kind,im in zip(('color','mask'),images):
            path=folder/f'base-{i}-{kind}.png';im.save(path)
            code += [f's:newCel({kind},s.frames[{i}],Image{{fromFile={lua(path.as_posix())}}},Point(0,0))']
        records.append({'key':key,'index':i})
    first=1
    for clip,c in m['clips'].items():
        for direction,ids in c['frames'].items():
            last=first+len(ids)-1
            code += [f's:newTag({first},{last}).name={lua(clip+"_"+direction)}'];first=last+1
    code += [f'local p=Palette({len(m["pixelStyle"]["palette"])})']
    for i,c in enumerate(m['pixelStyle']['palette']):
        r,g,b=pixel.rgb(c);code += [f'p:setColor({i},Color{{r={r},g={g},b={b},a=255}})']
    code += ['s:setPalette(p)',f's:saveAs({lua((folder/"mouse.aseprite").as_posix())})']
    run_editor(exe,folder,'\n'.join(code))
    assert (folder/'mouse.aseprite').exists(),'Aseprite did not save (check license/CLI support)'
    data={'sourceRevision':m['sourceRevision'],'buildId':m['buildId'],'height':height,'style':m['pixelStyle'],'size':images[0].size,'frames':records}
    data['baselineHashes']={p.name:digest(p) for p in folder.glob('base-*.png')}
    (folder/'workspace.json').write_text(json.dumps(data,indent=2))
    print('Editable workspace: '+str(folder/'mouse.aseprite'))

def import_edits(root,folder,exe,check_only=False):
    data=json.loads((folder/'workspace.json').read_text());m=metadata(root,data['height'])
    if data['sourceRevision']!=m['sourceRevision'] or data['buildId']!=m['buildId']:
        raise ValueError('Editor baseline is stale; review changes against a new export')
    for name,h in data['baselineHashes'].items():
        assert digest(contained(folder,name))==h,'Baseline was modified: '+name
    cleanup=root/'art/cleanup/woodland';entries=pixel.cleanup_manifest(cleanup,data['sourceRevision'])
    code=[f'local s=app.open({lua((folder/"mouse.aseprite").as_posix())})',f'assert(#s.frames=={len(data["frames"])},"Frame count changed")',f'assert(s.width=={data["size"][0]} and s.height=={data["size"][1]},"Canvas changed")','assert(#s.layers==2,"Keep exactly color and mask layers")']
    for kind in ('color','mask'):
        code += [f'local {kind}=nil;for _,l in ipairs(s.layers) do if l.name=="{kind}" then {kind}=l end end;assert({kind},"Missing {kind} layer")']
        for record in data['frames']:
            i=record['index'];path=folder/f'edited-{i}-{kind}.png'
            code += [f'do local im=Image(s.width,s.height);local cel={kind}:cel({i});if cel then im:drawImage(cel.image,cel.position) end;im:saveAs({lua(path.as_posix())}) end']
    run_editor(exe,folder,'\n'.join(code))
    changed=[]
    for record in data['frames']:
        i=record['index']
        images=[Image.open(folder/f'edited-{i}-{k}.png').convert('RGBA') for k in ('color','mask')]
        pixel.validate_pixels(*images,data['style'])
        bases=[Image.open(folder/f'base-{i}-{k}.png').convert('RGBA') for k in ('color','mask')]
        if any(a.tobytes()!=b.tobytes() for a,b in zip(images,bases)):changed.append((record,images))
    # Validate the whole edit before changing source. Existing revisions remain on disk.
    if changed and not check_only:
        edit_id=digest(folder/'mouse.aseprite')[:24];dest=cleanup/'edits'/edit_id;dest.mkdir(parents=True,exist_ok=True)
        shutil.copy2(folder/'mouse.aseprite',dest/'mouse.aseprite')
        for record,images in changed:
            paths={}
            for kind,im in zip(('color','mask'),images):
                path=dest/f'{record["index"]}-{kind}.png';im.save(path);paths[kind]=path.relative_to(cleanup).as_posix()
            entries[record['key']]=paths
        temp=cleanup/'manifest.incoming.json';temp.write_text(json.dumps({'sourceRevision':data['sourceRevision'],'frames':entries},indent=2))
        temp.replace(cleanup/'manifest.json')
    print(f'{len(changed)} changed frames; '+('validated only' if check_only else 'import complete'))
    return len(changed)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['prepare','import','check'])
    p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2]);p.add_argument('--height',type=int,choices=[32,48,64],default=48)
    p.add_argument('--workspace',type=Path,required=True);p.add_argument('--aseprite',default='C:/Program Files/Aseprite/Aseprite.exe')
    a=p.parse_args();root=a.root.resolve();folder=a.workspace.resolve()
    if a.mode=='prepare':prepare(root,a.height,folder,a.aseprite)
    else:import_edits(root,folder,a.aseprite,a.mode=='check')
