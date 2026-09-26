"""Orders catalog coverage, memory, immutable Megacorp art and cargo continuity."""
import json, sys, unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/assets'))
import build
class OrdersAssets(unittest.TestCase):
    def test_active_contract(self):
        root=Path(__file__).resolve().parents[1]
        if not (root/'assets/generated/catalog.json').exists():self.skipTest('Production catalog is not installed')
        cat=build.read_catalog(root)
        if not all(k in cat['units'] for k in build.ORDERS_UNITS+build.ORDERS_BUILDINGS):self.skipTest('Orders production batch is not installed')
        meta={k:json.loads((root/v).with_suffix('.json').read_text()) for k,v in cat['units'].items()}
        build.validate_worker_pair(meta)
        for k in build.ORDERS_UNITS:
            self.assertEqual(set(meta[k]['directions']),{'N','NE','E','SE','S','SW','W','NW'})
            self.assertIn('attack',meta[k]['clips'])
        for k,size in [('keep',4),('depot',2),('barracks',3),('sanctum',3)]:
            m=meta[k];self.assertEqual(m['footprintCells'],size)
            self.assertEqual(len(m['clips']['construction']['frames']['S']),3)
            for d in m['directions']:self.assertEqual(m['clips']['construction']['frames'][d],m['clips']['construction']['frames']['S'])
            self.assertEqual(len({(f['width'],f['height'],f['anchorX'],f['anchorY']) for f in m['frames']}),1)
        self.assertEqual(len(meta['reliquary']['clips']['attack']['frames']['S']),1)
        self.assertAlmostEqual(meta['gryphon']['referenceStride']['distance'],.11/.6*64/26)
        baseline=root/'artifacts/orders/baseline-catalog.json'
        if baseline.exists():
            old=json.loads(baseline.read_text())
            for k in build.AIRCRAFT+build.INFANTRY+build.BUILDINGS+build.PROPS:self.assertEqual(cat['units'][k],old['units'][k])
            def allocation(c):
                return sum(sum(p['width']*p['height']*8 for p in json.loads((root/v).with_suffix('.json').read_text())['pages']) for v in c['units'].values())
            before=allocation(old);after=allocation(cat)
            self.assertLessEqual(after-before,64*1024*1024)
            (root/'artifacts/orders/texture-allocation.json').write_text(json.dumps(dict(beforeBytes=before,afterBytes=after,deltaBytes=after-before,units={k:sum(p['width']*p['height']*8 for p in v['pages']) for k,v in meta.items()}),indent=2))
if __name__=='__main__':unittest.main()
