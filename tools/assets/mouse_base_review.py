"""Build a local interactive motion review and video frames from actual Blender renders."""
import argparse,json,math,sys
from pathlib import Path
from PIL import Image,ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parent))
import pixel
def run(root,out):
    m=json.loads((out/'manifest.json').read_text());assert not m['preview'],'Full render required'
    verification=out/'saved-scene-validation.json'
    if verification.exists():m['evaluatedTriangles']=json.loads(verification.read_text())['evaluatedTriangles']
    style=json.loads((root/'art/recipes/woodland/mouse_builder.json').read_text())
    frames={};pixel_frames={};columns=8
    for clip,spec in m['clips'].items():
        count=spec['frames'];frames[clip]=[]
        for n in range(1,count+1):
            path=out/'review'/clip/f'{n:03}.png'
            im=Image.open(path).convert('RGBA');assert im.size==(384,384);frames[clip].append(im)
        for height in (32,48,64):
            size=m['gameCell']*height//64;key=f'{clip}-{height}';images=[]
            for n in range(1,count+1):
                raw=Image.open(out/'game'/clip/f'{n:03}.png').convert('RGBA')
                assert raw.size==(m['gameCell']*2,m['gameCell']*2)
                mask_path=out/'mask'/clip/f'{n:03}.png'
                coverage=Image.open(mask_path).convert('RGBA') if mask_path.exists() else Image.new('RGBA',raw.size)
                c,mask=pixel.finish(raw,coverage,(size,size),style)
                pixel.validate_pixels(c,mask,style);images.append(c)
            pixel_frames[key]=images
        for key,images,size in [(clip+'-review',frames[clip],384)]+[(f'{clip}-{h}',pixel_frames[f'{clip}-{h}'],m['gameCell']*h//64) for h in (32,48,64)]:
            sheet=Image.new('RGBA',(columns*size,math.ceil(count/columns)*size))
            for n,im in enumerate(images):sheet.paste(im,((n%columns)*size,(n//columns)*size))
            sheet.save(out/(key+'.png'))
        # Dense ordered samples, including repeated start for loops.
        cells=frames[clip]+([frames[clip][0]] if spec['loop'] else [])
        sheet=Image.new('RGB',(8*160,math.ceil(len(cells)/8)*180),(220,218,196));d=ImageDraw.Draw(sheet)
        for i,im in enumerate(cells):
            x=i%8*160;y=i//8*180;im=im.resize((160,160));sheet.paste(im,(x,y+20),im)
            d.text((x+5,y+3),f'{clip} {i+1}',fill=(30,40,30))
        sheet.save(out/(clip+'-sequence.jpg'))
    html=(root/'tools/assets/mouse_base_viewer.html').read_text(encoding='utf-8-sig').replace('__MANIFEST__',json.dumps(m))
    (out/'index.html').write_text(html,encoding='utf8')
    # Shared 12-second timeline: genuine loops repeat, one-shots have a quiet hold.
    sequence=out/'video';sequence.mkdir(exist_ok=True)
    for tick in range(144):
        canvas=Image.new('RGB',(960,800),(222,220,198));draw=ImageDraw.Draw(canvas)
        draw.text((20,12),m.get('videoTitle',f'MOUSE BASE / {m["triangles"]} triangles / equipment-free animation test'),fill=(32,46,35))
        for i,(clip,spec) in enumerate(m['clips'].items()):
            x=(i%3)*320;y=42+(i//3)*375;count=spec['frames']
            local=(tick*2)%(count+(0 if spec['loop'] else 24));n=min(local,count-1)
            draw.text((x+12,y+5),clip.upper(),fill=(32,46,35))
            im=frames[clip][n].resize((290,290));canvas.paste(im,(x+15,y+15),im)
            im=pixel_frames[clip+'-48'][n];canvas.paste(im,(x+186,y+226),im)
            draw.text((x+193,y+342),'48 px / 1x',fill=(32,46,35))
        canvas.save(sequence/f'{tick:03}.png')
    print('SHOWCASE_READY',out/'index.html')
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2]);ap.add_argument('--output',type=Path,required=True)
    a=ap.parse_args();run(a.root,a.output)
