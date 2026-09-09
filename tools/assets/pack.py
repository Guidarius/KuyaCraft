"""Deterministic sprite atlas packing; independent of Blender and LÖVE."""
import hashlib
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw

DIRECTIONS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def contained(root, relative):
    path = (Path(root) / relative).resolve()
    if not path.is_relative_to(Path(root).resolve()):
        raise ValueError('Path escapes asset root: ' + str(relative))
    return path

def lua(value):
    if value is None: return 'nil'
    if isinstance(value, bool): return 'true' if value else 'false'
    if isinstance(value, (float, int)): return str(value)
    if isinstance(value, str): return json.dumps(value, ensure_ascii=True)
    if isinstance(value, list): return '{' + ','.join(lua(v) for v in value) + '}'
    return '{' + ','.join('[' + lua(k) + ']=' + lua(v) for k, v in sorted(value.items())) + '}'

def write_pair(path, value):
    Path(path).with_suffix('.json').write_text(json.dumps(value, indent=2) + '\n', encoding='utf8')
    Path(path).with_suffix('.lua').write_text('return ' + lua(value) + '\n', encoding='utf8')

def reduced(color, mask, size):
    # RGBa is Pillow's premultiplied format: transparent RGB cannot create halos.
    color = color.convert('RGBA').convert('RGBa').resize(size, Image.Resampling.LANCZOS).convert('RGBA')
    mask = mask.convert('RGBA').convert('RGBa').resize(size, Image.Resampling.LANCZOS).convert('RGBA')
    return color, mask

def extrude(image, gutter=2):
    """Extend exact RGBA edge texels, including alpha, into every gutter."""
    w, h = image.size
    result = Image.new('RGBA', (w+2*gutter, h+2*gutter))
    result.paste(image, (gutter,gutter))
    result.paste(image.crop((0,0,1,h)).resize((gutter,h)), (0,gutter))
    result.paste(image.crop((w-1,0,w,h)).resize((gutter,h)), (w+gutter,gutter))
    result.paste(image.crop((0,0,w,1)).resize((w,gutter)), (gutter,0))
    result.paste(image.crop((0,h-1,w,h)).resize((w,gutter)), (gutter,h+gutter))
    for sx,sy,dx,dy in ((0,0,0,0),(w-1,0,w+gutter,0),(0,h-1,0,h+gutter),(w-1,h-1,w+gutter,h+gutter)):
        result.paste(Image.new('RGBA',(gutter,gutter),image.getpixel((sx,sy))), (dx,dy))
    return result

def pack(stage, output, build_id, game_prefix):
    stage, output = Path(stage), Path(output)
    spec = json.loads((stage / 'render.json').read_text(encoding='utf8'))
    if spec['directions'] != DIRECTIONS: raise ValueError('Expected canonical eight directions')
    cell = spec['cellSize']
    width, height = (cell, cell) if isinstance(cell, int) else cell
    gutter, maximum = 2, 2048
    pitch_x, pitch_y = width + gutter * 2, height + gutter * 2
    columns, rows = maximum // pitch_x, maximum // pitch_y
    if columns < 1 or rows < 1: raise ValueError('Cell exceeds atlas limit')
    if not (0 <= spec['anchorX'] <= width and 0 <= spec['anchorY'] <= height): raise ValueError('Anchor outside cell')
    indexed = {}
    for f in spec['frames']:
        key = (f['clip'], f['direction'], f['sample'])
        if key in indexed: raise ValueError('Duplicate raw frame')
        indexed[key] = f
    ordered = []
    for name, clip in sorted(spec['clips'].items()):
        if clip['durationMs'] <= 0 or clip['samples'] < 1: raise ValueError('Invalid clip duration/samples')
        for direction in DIRECTIONS:
            for sample in range(1, clip['samples'] + 1):
                # Export samples and runtime frame IDs are one based.
                key = (name, direction, sample)
                if key not in indexed: raise ValueError('Missing raw frame ' + str(key))
                ordered.append(indexed.pop(key))
    if indexed: raise ValueError('Unexpected raw frames')
    output.mkdir(parents=True, exist_ok=True)
    meta = dict(version=2, unitId=spec['unitId'], buildId=build_id, profileId=spec['profileId'], directions=DIRECTIONS,
                bodyHeightPixels=spec['bodyHeightPixels'], pages=[], frames=[], clips={})
    if 'referenceStride' in spec: meta['referenceStride'] = spec['referenceStride']
    for name, clip in sorted(spec['clips'].items()):
        meta['clips'][name] = {k:v for k,v in clip.items() if k not in ('samples','frames')}
        meta['clips'][name]['frames'] = {d:[] for d in DIRECTIONS}
    capacity = columns * rows
    thumbs, animation = [], []
    for start in range(0, len(ordered), capacity):
        batch = ordered[start:start + capacity]
        page_w = min(columns, len(batch)) * pitch_x
        page_h = math.ceil(len(batch) / columns) * pitch_y
        color_page, mask_page = (Image.new('RGBA', (page_w, page_h)) for _ in range(2))
        page_id = len(meta['pages']) + 1
        for j, raw in enumerate(batch):
            color = Image.open(contained(stage, raw['color'])).convert('RGBA')
            mask = Image.open(contained(stage, raw['mask'])).convert('RGBA')
            if color.size != (width * 2, height * 2) or mask.size != color.size: raise ValueError('Raw color/mask size mismatch')
            bbox = color.getchannel('A').getbbox()
            if not bbox: raise ValueError('Empty raw frame')
            if bbox[0] == 0 or bbox[1] == 0 or bbox[2] == color.width or bbox[3] == color.height: raise ValueError('Clipped raw frame: ' + raw['color'])
            color, mask = reduced(color, mask, (width, height))
            x, y = (j % columns) * pitch_x + gutter, (j // columns) * pitch_y + gutter
            color_page.paste(extrude(color,gutter), (x-gutter,y-gutter))
            mask_page.paste(extrude(mask,gutter), (x-gutter,y-gutter))
            meta['frames'].append(dict(page=page_id, x=x, y=y, width=width, height=height, anchorX=spec['anchorX'], anchorY=spec['anchorY']))
            meta['clips'][raw['clip']]['frames'][raw['direction']].append(len(meta['frames']))
            if raw['sample'] == 1: thumbs.append((raw['clip'] + ' ' + raw['direction'], color.copy()))
            if raw['clip'] == 'move' and raw['direction'] == 'S': animation.append(color.copy())
        color_name, mask_name = f'color-{page_id:02}.png', f'mask-{page_id:02}.png'
        color_page.save(output / color_name); mask_page.save(output / mask_name)
        meta['pages'].append(dict(color=game_prefix + '/' + color_name, mask=game_prefix + '/' + mask_name, width=page_w, height=page_h))
    write_pair(output / 'metadata', meta)
    contact = Image.new('RGBA', (8 * (width + 12), math.ceil(len(thumbs)/8) * (height+24)), '#353b43')
    draw = ImageDraw.Draw(contact)
    for i, (label, thumb) in enumerate(thumbs):
        x, y = (i % 8)*(width+12), (i//8)*(height+24)
        contact.alpha_composite(thumb, (x,y+16)); draw.text((x,y), label, fill='white')
    contact.save(stage / 'contact-sheet.png')
    if animation:
        animation[0].save(stage / 'motion-preview.png', save_all=True, append_images=animation[1:], duration=max(1, meta['clips']['move']['durationMs']//len(animation)), loop=0, disposal=1)
    report = {'version':1, 'unitId':spec['unitId'], 'files':{p.name:digest(p) for p in sorted(output.iterdir()) if p.is_file() and p.name != 'validation.json'}}
    (output / 'validation.json').write_text(json.dumps(report, indent=2), encoding='utf8')
    return meta

def validate_unit(root, metadata_path):
    root = Path(root)
    file = contained(root, metadata_path)
    meta = json.loads(file.with_suffix('.json').read_text(encoding='utf8'))
    if meta['version'] != 2 or meta['directions'] != DIRECTIONS: raise ValueError('Unsupported asset metadata')
    if file.read_text(encoding='utf8') != 'return ' + lua(meta) + '\n': raise ValueError('Lua/JSON metadata mismatch')
    report = json.loads((file.parent / 'validation.json').read_text(encoding='utf8'))
    if report.get('version') != 1 or report.get('unitId') != meta['unitId']: raise ValueError('Invalid validation report identity')
    required_files = {file.name,file.with_suffix('.json').name}
    for page in meta['pages']:
        for kind in ('color','mask'):
            atlas = contained(root,page[kind])
            if atlas.parent != file.parent: raise ValueError('Atlas outside immutable unit build')
            required_files.add(atlas.name)
    if not required_files.issubset(report['files']): raise ValueError('Incomplete checksum coverage')
    for name, expected in report['files'].items():
        if digest(contained(file.parent, name)) != expected: raise ValueError('Corrupt asset: ' + name)
    if not meta['pages'] or not meta['frames']: raise ValueError('Empty asset')
    required_clips = {'idle','move','attack','death'}
    if meta['unitId'] in ('worker','worker_loaded'): required_clips.add('work')
    if not required_clips.issubset(meta['clips']): raise ValueError('Missing required clips')
    def integer(value): return type(value) is int
    def finite(value): return type(value) in (int,float) and math.isfinite(value)
    if not finite(meta['bodyHeightPixels']) or meta['bodyHeightPixels'] <= 0: raise ValueError('Invalid body height')
    for page in meta['pages']:
        if any(not integer(page[k]) or not 0 < page[k] <= 2048 for k in ('width','height')): raise ValueError('Invalid atlas dimensions')
        for kind in ('color','mask'):
            with Image.open(contained(root, page[kind])) as img:
                if img.size != (page['width'],page['height']): raise ValueError('Atlas dimensions mismatch')
                img.verify()
    for f in meta['frames']:
        if not integer(f['page']) or not 1 <= f['page'] <= len(meta['pages']): raise ValueError('Invalid page index')
        if any(not integer(f[k]) for k in ('x','y','width','height')) or min(f['width'],f['height']) <= 0: raise ValueError('Invalid frame dimensions')
        page = meta['pages'][f['page']-1]
        if f['page'] < 1 or min(f['x'],f['y']) < 2 or f['x']+f['width']+2 > page['width'] or f['y']+f['height']+2 > page['height']: raise ValueError('Invalid frame rectangle')
        if any(not finite(f[k]) or not 0 <= f[k] <= f[bound] for k,bound in (('anchorX','width'),('anchorY','height'))): raise ValueError('Invalid frame anchor')
    for clip in meta['clips'].values():
        if not integer(clip['durationMs']) or clip['durationMs'] <= 0 or type(clip['loop']) is not bool: raise ValueError('Invalid clip timing')
        if set(clip['frames']) != set(DIRECTIONS): raise ValueError('Invalid clip directions')
        count = len(clip['frames']['N'])
        if 'contactFrame' in clip and (not integer(clip['contactFrame']) or not 1 <= clip['contactFrame'] <= count): raise ValueError('Invalid contact frame')
        for d in DIRECTIONS:
            ids = clip['frames'][d]
            if not ids or len(ids) != count or any(not integer(i) or i < 1 or i > len(meta['frames']) for i in ids): raise ValueError('Invalid clip frames')
    return meta
