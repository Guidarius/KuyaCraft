"""Native-size and 3x contact sheets for the published Footman and a baseline.

Run with Pillow Python: review_footman.py --root <checkout> --baseline <metadata.json>.
Outputs are ignored under artifacts/footman-review.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root', type=Path, required=True)
    ap.add_argument('--baseline', type=Path, required=True)
    args = ap.parse_args()
    root = args.root.resolve()
    catalog = json.loads((root/'assets/generated/catalog.json').read_text())
    current = (root/catalog['units']['footman']).with_suffix('.json')
    out = root/'artifacts/footman-review'
    out.mkdir(parents=True, exist_ok=True)
    for label, path in [('before', args.baseline), ('after', current)]:
        meta = json.loads(path.read_text())
        pages = [(Image.open(root/p['color']).convert('RGBA'),
                  Image.open(root/p['mask']).convert('RGBA')) for p in meta['pages']]
        def sprite(index):
            f = meta['frames'][index-1]
            box = (f['x'], f['y'], f['x']+f['width'], f['y']+f['height'])
            color, mask = [im.crop(box) for im in pages[f['page']-1]]
            pixels = []
            for (r,g,b,a),(m,_,__,___) in zip(color.getdata(),mask.getdata()):
                shade = (r*.299+g*.587+b*.114)*1.4
                pixels.append((*[round(c*(1-m/255)+min(255,t*shade)*m/255)
                                  for c,t in zip((r,g,b),(.38,.75,.96))],a))
            color.putdata(pixels)
            # One shared crop around the metadata ground anchor; no pose recentering.
            x,y = int(f['anchorX']),int(f['anchorY'])
            return color.crop((x-32,y-48,x+32,y+16))
        for clip, spec in meta['clips'].items():
            n = len(spec['frames']['N'])
            board = Image.new('RGBA',(8*200,n*270+35),'#19212b')
            draw = ImageDraw.Draw(board)
            draw.text((10,10),f'{label} / {clip}: 3x above, native below; each row is the next sample',fill='white')
            for d, heading in enumerate(meta['directions']):
                for i,index in enumerate(spec['frames'][heading]):
                    x,y = d*200,i*270+35
                    draw.rectangle((x,y,x+198,y+268),fill='#394c37' if d%2==0 else '#665847')
                    spr = sprite(index)
                    board.alpha_composite(spr.resize((192,192),Image.Resampling.NEAREST),(x+4,y+10))
                    board.alpha_composite(spr,(x+68,y+202))
                    draw.text((x+4,y+2),f'{heading} {i+1}',fill='white')
            board.convert('RGB').save(out/f'{label}-{clip}.png')
    print(out)


if __name__ == '__main__':
    main()
