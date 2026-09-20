"""Reopen exported aircraft and compare evaluated motion bounds to the build report.

Run in background Blender: --python tests/verify_aircraft_blends.py -- <repo root>
"""
import json
import math
from pathlib import Path
import sys
import bpy

root=Path(sys.argv[sys.argv.index('--')+1]).resolve()
sys.path.insert(0,str(root/'tools/blender'))
from pipeline import bounds, set_frame

catalog=json.loads((root/'assets/generated/catalog.json').read_text())
results=[]
for unit in ('command_blimp','battleship'):
    metadata=json.loads((root/catalog['units'][unit]).with_suffix('.json').read_text())
    stage=root/'artifacts/asset-build'/metadata['buildId']/unit
    report=json.loads((stage/'render.json').read_text())
    bpy.ops.wm.open_mainfile(filepath=str(stage/(unit+'.blend')),use_scripts=False)
    scene=bpy.context.scene
    meshes=[o for o in scene.objects if o.type=='MESH']
    assert not any(o.type=='ARMATURE' for o in scene.objects)
    assert any(m.get('team') for o in meshes for m in o.data.materials)
    assert not any(m.name.startswith(('TeamCoverage','OccluderCoverage')) for o in meshes for m in o.data.materials)
    assert sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)==report['meshValidation']['triangles']
    for sample in report['bounds']:
        clip=sample['clip']
        for name in ('AircraftMotion','CannonRecoil'):
            ob=bpy.data.objects.get(name)
            if ob:
                action=bpy.data.actions[f'RTS_{unit}_{clip}_{name}']
                ob.animation_data.action=action;ob.animation_data.action_slot=action.slots[0]
        bpy.data.objects['ExportRoot'].rotation_euler.z=math.pi-report['directions'].index(sample['direction'])*math.pi/4
        set_frame(sample['sample']);bpy.context.view_layer.update()
        actual=bounds(scene,scene.camera,meshes,report['cellSize'])
        assert all(math.isfinite(v) for v in actual)
        assert max(abs(a-b) for a,b in zip(actual,sample['bounds']))<.001,(unit,sample,actual)
    # An independent saved-scene render for visual inspection against the packed source.
    for name in ('AircraftMotion','CannonRecoil'):
        ob=bpy.data.objects.get(name)
        if ob:
            action=bpy.data.actions[f'RTS_{unit}_idle_{name}']
            ob.animation_data.action=action;ob.animation_data.action_slot=action.slots[0]
    bpy.data.objects['ExportRoot'].rotation_euler.z=-math.pi/4
    set_frame(1);scene.render.filepath=str(stage/'reopened-idle-SW.png')
    bpy.ops.render.render(write_still=True)
    results.append({'unit':unit,'posesVerified':len(report['bounds']),
                    'triangles':report['meshValidation']['triangles'],'savedSceneReopened':True})
(root/'artifacts/aircraft-blend-validation.json').write_text(json.dumps(results,indent=2))
print('PASS saved aircraft: material restoration, editable actions and all evaluated bounds',results)
