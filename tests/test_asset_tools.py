"""Run with Python + Pillow: python -m unittest discover -s tests -p test_asset_tools.py."""
import json
import copy
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools/assets'))
from PIL import Image, ImageDraw
import build
from pack import DIRECTIONS, digest, pack, reduced, validate_unit, write_pair

class Assets(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.stage = self.root/'stage'; self.stage.mkdir()
        self.out = self.root/'assets/generated/builds/test/shieldguard'
        frames = []
        for d in DIRECTIONS:
            c = Image.new('RGBA',(128,128)); ImageDraw.Draw(c).rectangle((40,20,88,108),fill=(180,60,20,255))
            m = Image.new('RGBA',(128,128)); ImageDraw.Draw(m).rectangle((44,30,70,80),fill=(255,255,255,255))
            c.save(self.stage/(d+'.png')); m.save(self.stage/(d+'mask.png'))
            frames.append(dict(clip='idle',direction=d,sample=1,color=d+'.png',mask=d+'mask.png'))
        self.spec = dict(unitId='shieldguard',profileId='test',directions=DIRECTIONS,cellSize=64,anchorX=32,anchorY=54,bodyHeightPixels=32,clips={'idle':dict(samples=1,durationMs=1000,loop=True)},frames=frames)
        for clip in ('move','attack','death'):
            self.spec['clips'][clip]=dict(samples=1,durationMs=1000,loop=clip=='move')
            self.spec['frames'].extend(dict(f,clip=clip) for f in frames[:8])
        self.save()
    def tearDown(self): self.temp.cleanup()
    def save(self): (self.stage/'render.json').write_text(json.dumps(self.spec))
    def packed(self):
        meta = pack(self.stage,self.out,'test',self.out.relative_to(self.root).as_posix())
        return meta, (self.out/'metadata.lua').relative_to(self.root).as_posix()
    def test_pack_validate_alignment(self):
        meta,path = self.packed(); validate_unit(self.root,path)
        self.assertEqual(meta['clips']['attack']['frames']['N'],[1])
        self.assertEqual(len(meta['frames']),32)
        self.assertEqual(meta['frames'][0]['anchorY'],54)
        with Image.open(self.out/'color-01.png') as page, Image.open(self.out/'mask-01.png') as mask:
            self.assertEqual(page.getpixel((0,0))[3],0)
            self.assertEqual(page.size,mask.size)
    def test_procedural_aircraft_key_needs_no_external_blend(self):
        recipe=self.root/'art/recipes/command_blimp.json'
        recipe.parent.mkdir(parents=True); recipe.write_text('{"version":1}')
        key,deps=build.build_key(self.root,None,'command_blimp','Blender test')
        self.assertEqual(list(deps),[str(Path('art/recipes/command_blimp.json'))])
        recipe.write_text('{"version":2}')
        changed,_=build.build_key(self.root,None,'command_blimp','Blender test')
        self.assertNotEqual(key,changed)
    def test_missing_frame_rejected(self):
        self.spec['frames'].pop(); self.save()
        with self.assertRaisesRegex(ValueError,'Missing raw'): self.packed()
    def test_building_fixed_view_packs_once(self):
        self.spec.update(unitId='orbital_command',profileId='building_overhead_v1',fixedFacing='S',footprintCells=4)
        self.spec['clips']={'idle':self.spec['clips']['idle']}
        self.spec['frames']=[f for f in self.spec['frames'] if f['clip']=='idle' and f['direction']=='S']
        self.save();meta,path=self.packed();validate_unit(self.root,path)
        self.assertEqual(len(meta['frames']),1)
        self.assertEqual(meta['footprintCells'],4)
        for d in DIRECTIONS: self.assertEqual(meta['clips']['idle']['frames'][d],[1])
        self.assertEqual(meta['pages'][0]['width'],68)
    def test_unit_cannot_skip_headings_with_fixed_view(self):
        self.spec['fixedFacing']='S';self.save()
        with self.assertRaisesRegex(ValueError,'Fixed facing'): self.packed()
    def test_clipping_rejected(self):
        Image.new('RGBA',(128,128),'red').save(self.stage/'N.png')
        with self.assertRaisesRegex(ValueError,'Clipped'): self.packed()
    def test_mask_size_rejected(self):
        Image.new('RGBA',(64,64)).save(self.stage/'Nmask.png')
        with self.assertRaisesRegex(ValueError,'size mismatch'): self.packed()
    def test_transparent_rgb_does_not_bleed(self):
        c = Image.new('RGBA',(8,8),(0,255,0,0)); ImageDraw.Draw(c).rectangle((2,2,5,5),fill=(255,0,0,255))
        small,_ = reduced(c,c,(4,4))
        self.assertTrue(all(small.getpixel((x,y))[1] == 0 for x in range(4) for y in range(4) if small.getpixel((x,y))[3]))
    def test_corrupt_atlas_rejected(self):
        _,path=self.packed(); (self.out/'color-01.png').write_bytes(b'broken')
        with self.assertRaisesRegex(ValueError,'Corrupt'): validate_unit(self.root,path)
    def test_catalog_preserved_on_invalid_publish(self):
        _,path=self.packed(); build.publish(self.root,{'shieldguard':path})
        before=(self.root/'assets/generated/catalog.lua').read_bytes()
        with self.assertRaises(FileNotFoundError): build.publish(self.root,{'worker':'assets/missing.lua'})
        self.assertEqual(before,(self.root/'assets/generated/catalog.lua').read_bytes())
    def test_lua_json_agreement(self):
        _,path=self.packed(); (self.root/path).write_text('return {}')
        with self.assertRaisesRegex(ValueError,'mismatch'): validate_unit(self.root,path)
    def test_hard_interruption_uses_previous_inspection_json(self):
        _,path=self.packed(); build.publish(self.root,{'shieldguard':path})
        build.publish(self.root,{'shieldguard':path})
        json_path=self.root/'assets/generated/catalog.json'
        json_path.write_text(json.dumps({'version':2,'units':{}}))
        self.assertIn('shieldguard',build.read_catalog(self.root)['units'])
    def test_first_publication_interruption_can_recover(self):
        _,path=self.packed()
        base=self.root/'assets/generated'
        (base/'catalog.json').write_text(json.dumps({'version':2,'units':{'shieldguard':path}}))
        self.assertIsNone(build.read_catalog(self.root))
        build.publish(self.root,{'shieldguard':path})
        self.assertEqual(build.read_catalog(self.root)['units']['shieldguard'],path)
    def test_new_build_replaces_corrupt_active_asset(self):
        _,old_path=self.packed(); build.publish(self.root,{'shieldguard':old_path})
        (self.out/'color-01.png').write_bytes(b'corrupted active atlas')
        self.out=self.root/'assets/generated/builds/new/shieldguard'
        _,new_path=self.packed()
        build.publish(self.root,{'shieldguard':new_path})
        self.assertEqual(build.read_catalog(self.root)['units']['shieldguard'],new_path)
    def test_corrupt_unreplaced_asset_still_blocks_publication(self):
        _,path=self.packed(); build.publish(self.root,{'shieldguard':path})
        before=(self.root/'assets/generated/catalog.lua').read_bytes()
        (self.out/'color-01.png').write_bytes(b'corrupted active atlas')
        with self.assertRaisesRegex(ValueError,'Corrupt asset'): build.publish(self.root,{})
        self.assertEqual(before,(self.root/'assets/generated/catalog.lua').read_bytes())
    def test_worker_pair_requires_compatible_playback(self):
        meta,_=self.packed()
        cases=[
            ('reference stride',lambda m:m.update(referenceStride={'distance':9,'units':'navigationCells'})),
            ('clip timing',lambda m:m['clips']['move'].update(durationMs=500)),
            ('sample counts',lambda m:m['clips']['move']['frames'].update(N=[1,2])),
            ('frame anchors',lambda m:m['frames'][0].update(anchorY=53)),
        ]
        build.validate_worker_pair({'worker':meta,'worker_loaded':copy.deepcopy(meta)})
        for reason,mutation in cases:
            with self.subTest(reason=reason):
                changed=copy.deepcopy(meta); mutation(changed)
                with self.assertRaisesRegex(ValueError,reason): build.validate_worker_pair({'worker':meta,'worker_loaded':changed})
    def test_publish_replace_failure_rolls_back(self):
        _,path=self.packed(); build.publish(self.root,{'shieldguard':path})
        before=(self.root/'assets/generated/catalog.lua').read_bytes()
        original=build.os.replace
        def fail_lua(source,target):
            if str(target).endswith('catalog.lua'): raise PermissionError('locked runtime catalog')
            return original(source,target)
        with patch.object(build.os,'replace',side_effect=fail_lua):
            with self.assertRaises(PermissionError): build.publish(self.root,{'shieldguard':path})
        self.assertEqual(before,(self.root/'assets/generated/catalog.lua').read_bytes())
        build.read_catalog(self.root)
    def test_cache_key_unit_isolation(self):
        recipe=self.root/'art/recipes'; recipe.mkdir(parents=True)
        for unit in ('worker','shieldguard'): (recipe/(unit+'.json')).write_text('{}')
        source=self.root/'source.blend'; source.write_bytes(b'source')
        old=build.build_key(self.root,source,'shieldguard','Blender fixture')[0]
        (recipe/'worker.json').write_text('{"changed":true}')
        self.assertEqual(old,build.build_key(self.root,source,'shieldguard','Blender fixture')[0])
        source.write_bytes(b'changed'); self.assertNotEqual(old,build.build_key(self.root,source,'shieldguard','Blender fixture')[0])
    def test_package_requires_complete_roster(self):
        _,path=self.packed(); build.publish(self.root,{'shieldguard':path})
        with self.assertRaisesRegex(ValueError,'Required asset absent'): build.package(self.root,self.root/'package')
    def test_package_only_referenced_assets(self):
        entries={}
        for unit in build.ROSTER:
            self.spec['unitId']=unit; self.save()
            if unit in ('worker','worker_loaded') and 'work' not in self.spec['clips']:
                self.spec['clips']['work']=dict(samples=1,durationMs=1000,loop=True)
                self.spec['frames'].extend(dict(f,clip='work') for f in self.spec['frames'][:8]); self.save()
            self.out=self.root/'assets/generated/builds/test'/unit
            _,path=self.packed(); entries[unit]=path
        build.publish(self.root,entries)
        stale=self.root/'assets/generated/builds/stale'; stale.mkdir()
        (stale/'unused.png').write_bytes(b'not an asset')
        target=self.root/'package'; build.package(self.root,target)
        self.assertFalse((target/'assets/generated/builds/stale').exists())
        build.read_catalog(target,build.ROSTER)
    def test_multiple_pages_and_variable_clip_samples(self):
        self.spec['cellSize']=1020; self.spec['anchorX']=510; self.spec['anchorY']=900
        for d in DIRECTIONS:
            for suffix in ('.png','mask.png'):
                im=Image.new('RGBA',(2040,2040)); ImageDraw.Draw(im).rectangle((500,500,1500,1500),fill='white')
                im.save(self.stage/(d+suffix))
        self.save(); meta,path=self.packed()
        self.assertEqual(len(meta['pages']),8)
        self.assertEqual(meta['frames'][4]['page'],2)
        validate_unit(self.root,path)
    def test_gutters_extrude_rgba_on_both_atlases(self):
        for suffix in ('.png','mask.png'):
            im=Image.new('RGBA',(128,128)); ImageDraw.Draw(im).rectangle((1,1,126,126),fill=(210,85,40,255))
            im.save(self.stage/('N'+suffix))
        meta,_=self.packed(); f=meta['frames'][0]
        for name in ('color-01.png','mask-01.png'):
            with Image.open(self.out/name) as page:
                x,y=f['x'],f['y']; edge=page.getpixel((x,y+20))
                self.assertGreater(edge[3],0)
                self.assertEqual(page.getpixel((x-1,y+20)),edge)
                self.assertEqual(page.getpixel((x-2,y+20)),edge)
                self.assertEqual(page.getpixel((x-2,y-2)),page.getpixel((x,y)))
    def mutate_metadata(self, mutation):
        meta,path=self.packed(); mutation(meta); write_pair(self.out/'metadata',meta)
        report_path=self.out/'validation.json'; report=json.loads(report_path.read_text())
        for name in ('metadata.lua','metadata.json'): report['files'][name]=digest(self.out/name)
        report_path.write_text(json.dumps(report)); return path
    def test_semantic_validation_rejects_invalid_contracts(self):
        cases=[
            ('Missing required',lambda m:m['clips'].pop('move')),
            ('Invalid clip timing',lambda m:m['clips']['idle'].update(durationMs=0)),
            ('Invalid clip timing',lambda m:m['clips']['idle'].update(durationMs=1.5)),
            ('Invalid contact',lambda m:m['clips']['attack'].update(contactFrame=2)),
            ('Invalid clip frames',lambda m:m['clips']['idle']['frames'].update(NE=[1,2])),
            ('Invalid frame anchor',lambda m:m['frames'][0].update(anchorX=1000)),
            ('Invalid atlas dimensions',lambda m:m['pages'][0].update(width=4096)),
            ('Invalid page index',lambda m:m['frames'][0].update(page=0)),
        ]
        for reason,mutation in cases:
            with self.subTest(reason=reason):
                path=self.mutate_metadata(mutation)
                with self.assertRaisesRegex(ValueError,reason): validate_unit(self.root,path)
    def test_checksum_report_must_cover_pages(self):
        _,path=self.packed(); report_path=self.out/'validation.json'
        report=json.loads(report_path.read_text()); report['files'].pop('mask-01.png'); report_path.write_text(json.dumps(report))
        with self.assertRaisesRegex(ValueError,'checksum coverage'): validate_unit(self.root,path)
    def test_path_escape_rejected(self):
        self.spec['frames'][0]['color']='../outside.png'; self.save()
        with self.assertRaisesRegex(ValueError,'escapes'): self.packed()

if __name__ == '__main__': unittest.main()
