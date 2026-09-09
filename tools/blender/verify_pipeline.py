"""Blender-hosted pure sampling/intake checks; does not render or alter live files."""
import sys
import json
from pathlib import Path
root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'tools/blender'))
import pipeline as p
import bpy
assert p.sample_times(0,36.8,6,False)[-1] == 36.8
assert len(p.sample_times(0,32,8,True)) == 8
assert p.sample_times(0,32,8,True)[-1] == 28
assert p.sample_times(3.25,3.25,1,False) == [3.25]
try:p.sample_times(5,1,4,True)
except ValueError:pass
else:raise AssertionError('Invalid sample range accepted')
source=root/'art/source/rig-library/RTSAssets.blend'
expected=json.loads((source.parent/'source.json').read_text())
assert p.digest(source)==expected['sha256']
rig=p.import_source(source)
info=p.inventory(source,rig)
assert len(info['bones'])==65 and len(info['actions'])==120
assert 'index_01_l' in info['bones'] and 'thumb_03_r' in info['bones']
assert all(next(a for a in info['actions'] if a['name']==name)['slots']==['OBArmature'] for name in ['Idle_Loop','Walk_Loop','Death01'])
assert info['sourceFps']==24 and info['sourceFpsBase']==1
assert not info['drivers']
assert p.digest(source)==expected['sha256']
p.write_json(root/'artifacts/asset-intake/test-report.json',{'passed':True,'tests':['fractional endpoint','loop endpoint exclusion','single frame','invalid range','source hash preservation','bone and action inventory','slots','effective fps','driver audit']})
print('PASS ASSET_PIPELINE_SAMPLING_INTAKE')
