"""Deterministic pixel finishing and revision-bound editable frame overrides."""
import json
from pathlib import Path
from PIL import Image,ImageFilter

def rgb(value):return tuple(bytes.fromhex(value.lstrip('#')))

def finish(color,mask,size,style):
    palette=[rgb(c) for c in style['palette']];start=style['teamStart']
    assert len(palette)<=32 and start+5==len(palette)
    color=color.convert('RGBA').resize(size,Image.Resampling.BOX)
    mask=mask.convert('RGBA').resize(size,Image.Resampling.BOX)
    pal=Image.new('P',(1,1));colors=palette[:start]
    pal.putpalette([c for triple in colors+[colors[-1]]*(256-len(colors)) for c in triple])
    indexed=color.convert('RGB').quantize(palette=pal,dither=Image.Dither.NONE)
    alpha=color.getchannel('A').point(lambda v:255 if v>=128 else 0)
    outline=alpha.filter(ImageFilter.MaxFilter(3))
    out=Image.new('RGBA',size);coverage=Image.new('RGBA',size)
    cp,mp,ap,op,ip=color.load(),mask.load(),alpha.load(),outline.load(),indexed.load()
    dest,team=out.load(),coverage.load()
    for y in range(size[1]):
        for x in range(size[0]):
            if ap[x,y]:
                level=min(4,(cp[x,y][0]*5)//256) if mp[x,y][0]>=128 else None
                dest[x,y]=(*(palette[start+level] if level is not None else palette[ip[x,y]]),255)
                team[x,y]=((level+1)*51 if level is not None else 0,0,0,255)
            elif op[x,y]:dest[x,y]=(*palette[0],255);team[x,y]=(0,0,0,255)
    validate_pixels(out,coverage,style)
    return out,coverage

def validate_pixels(color,mask,style):
    if color.size!=mask.size:raise ValueError('Pixel mask size mismatch')
    allowed={rgb(c) for c in style['palette']}
    for a,b in zip(color.convert('RGBA').getdata(),mask.convert('RGBA').getdata()):
        if a[3] not in (0,255) or b[3]!=a[3]:raise ValueError('Pixel alpha must be binary and aligned')
        if a[3] and a[:3] not in allowed:raise ValueError('Pixel outside fixed palette')
        if b[0] not in (0,51,102,153,204,255) or b[1:3]!=(0,0):raise ValueError('Invalid discrete team index')
        if a[3] and b[0] and a[:3]!=rgb(style['palette'][style['teamStart']+b[0]//51-1]):raise ValueError('Team color/index disagreement')

def cleanup_manifest(root,revision):
    path=Path(root)/'manifest.json'
    if not path.exists():return {}
    data=json.loads(path.read_text(encoding='utf-8-sig'))
    if data.get('sourceRevision')!=revision:raise ValueError('Manual cleanup is stale; review it against source revision '+revision)
    return data.get('frames',{})

def override(root,entries,key,color,mask,style):
    if key not in entries:return color,mask
    paths=[]
    for kind in ('color','mask'):
        path=(Path(root)/entries[key][kind]).resolve()
        if not path.is_relative_to(Path(root).resolve()):raise ValueError('Cleanup path escapes source directory')
        paths.append(path)
    c,m=(Image.open(p).convert('RGBA') for p in paths)
    if c.size!=color.size:raise ValueError('Cleanup changes fixed frame size')
    validate_pixels(c,m,style);return c,m
