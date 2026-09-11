"""Pixel finishing and cleanup failures must never silently change source edits."""
import sys,json,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/assets'))
from PIL import Image
import pixel

class PixelPilot(unittest.TestCase):
    def setUp(self):
        self.style=json.loads((Path(__file__).resolve().parents[1]/'art/recipes/woodland/mouse_builder.json').read_text())
    def test_outline_is_exactly_one_pixel(self):
        c=Image.new('RGBA',(7,7));c.putpixel((3,3),(190,130,70,255))
        out,mask=pixel.finish(c,Image.new('RGBA',c.size),c.size,self.style)
        self.assertEqual(out.getbbox(),(2,2,5,5))
        self.assertEqual(sum(v[3]>0 for v in out.getdata()),9)
        self.assertEqual(out.getpixel((2,2)),(*pixel.rgb(self.style['palette'][0]),255))
        self.assertEqual(out.tobytes(),pixel.finish(c,Image.new('RGBA',c.size),c.size,self.style)[0].tobytes())
    def test_all_five_team_shades(self):
        c=Image.new('RGBA',(5,1));mask=Image.new('RGBA',c.size,(255,255,255,255))
        for i in range(5):c.putpixel((i,0),(i*51+25,100,100,255))
        out,m=pixel.finish(c,mask,c.size,self.style)
        self.assertEqual([p[0] for p in m.getdata()],[51,102,153,204,255])
        pixel.validate_pixels(out,m,self.style)
    def test_rejects_alpha_palette_and_team_corruption(self):
        c=Image.new('RGBA',(1,1),(*pixel.rgb(self.style['palette'][0]),255));m=Image.new('RGBA',(1,1),(0,0,0,255))
        for bad in [(0,0,0,128),(255,0,255,255)]:
            with self.assertRaises(ValueError):pixel.validate_pixels(Image.new('RGBA',(1,1),bad),m,self.style)
        with self.assertRaises(ValueError):pixel.validate_pixels(c,Image.new('RGBA',(1,1),(51,0,0,255)),self.style)
    def test_cleanup_preserved_and_stale_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);path=root/'manifest.json'
            path.write_text(json.dumps({'sourceRevision':'old','frames':{'x':{}}}));before=path.read_bytes()
            with self.assertRaisesRegex(ValueError,'stale'):pixel.cleanup_manifest(root,'new')
            self.assertEqual(path.read_bytes(),before)
            self.assertEqual(pixel.cleanup_manifest(root,'old'),{'x':{}})
    def test_cleanup_escape_and_size_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);c=Image.new('RGBA',(2,2));m=c.copy()
            with self.assertRaisesRegex(ValueError,'escapes'):pixel.override(root,{'x':{'color':'../bad.png','mask':'m.png'}},'x',c,m,self.style)
            Image.new('RGBA',(1,1)).save(root/'c.png');m.save(root/'m.png')
            with self.assertRaisesRegex(ValueError,'size'):pixel.override(root,{'x':{'color':'c.png','mask':'m.png'}},'x',c,m,self.style)
    def test_editor_import_retains_source_and_rejects_stale(self):
        from unittest.mock import patch
        import woodland_edit
        from pack import digest
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);folder=root/'editor';folder.mkdir()
            (folder/'mouse.aseprite').write_bytes(b'editable fixture')
            c=Image.new('RGBA',(2,2),(*pixel.rgb(self.style['palette'][0]),255))
            m=Image.new('RGBA',(2,2),(0,0,0,255))
            for kind,im in [('color',c),('mask',m)]:
                im.save(folder/f'base-1-{kind}.png');im.save(folder/f'edited-1-{kind}.png')
            data={'sourceRevision':'rev','buildId':'build','height':48,'size':[2,2],'style':self.style,'frames':[{'key':'48/idle/S/1','index':1}],'baselineHashes':{p.name:digest(p) for p in folder.glob('base*.png')}}
            (folder/'workspace.json').write_text(json.dumps(data))
            with patch.object(woodland_edit,'metadata',return_value=data),patch.object(woodland_edit,'run_editor'):
                self.assertEqual(woodland_edit.import_edits(root,folder,'unused',True),0)
                c.putpixel((0,0),(*pixel.rgb(self.style['palette'][1]),255));c.save(folder/'edited-1-color.png')
                self.assertEqual(woodland_edit.import_edits(root,folder,'unused',True),1)
                self.assertFalse((root/'art/cleanup/woodland/manifest.json').exists())
                self.assertEqual(woodland_edit.import_edits(root,folder,'unused'),1)
                cleanup=root/'art/cleanup/woodland';entries=pixel.cleanup_manifest(cleanup,'rev')
                actual,_=pixel.override(cleanup,entries,'48/idle/S/1',c,m,self.style)
                self.assertEqual(actual.tobytes(),c.tobytes())
                self.assertEqual(next(cleanup.rglob('mouse.aseprite')).read_bytes(),b'editable fixture')
            with patch.object(woodland_edit,'metadata',return_value={**data,'sourceRevision':'changed'}):
                with self.assertRaisesRegex(ValueError,'stale'):woodland_edit.import_edits(root,folder,'unused')
if __name__=='__main__':unittest.main()
