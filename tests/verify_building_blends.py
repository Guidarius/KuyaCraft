"""Reopen every published building; verify saved meshes/keys and render review views.

blender --background --factory-startup --python-exit-code 1 --python
tests/verify_building_blends.py -- <repository>
"""
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector

root=Path(sys.argv[sys.argv.index('--')+1]).resolve()
sys.path.insert(0,str(root/'tools/blender'))
from building_model import IDS
from pipeline import bounds, set_frame

catalog=json.loads((root/'assets/generated/catalog.json').read_text())
review=root/'artifacts/building-review';review.mkdir(parents=True,exist_ok=True)
results=[]
for unit in IDS:
    meta=json.loads((root/catalog['units'][unit]).with_suffix('.json').read_text())
    stage=root/'artifacts/asset-build'/meta['buildId']/unit
    report=json.loads((stage/'render.json').read_text())
    bpy.ops.wm.open_mainfile(filepath=str(stage/(unit+'.blend')))
    scene=bpy.context.scene;camera=scene.camera
    meshes=[ob for ob in scene.objects if ob.type=='MESH']
    assembly=bpy.data.objects['BuildingAssembly'];half=meta['footprintCells']*26/128
    assert assembly['footprintCells']==meta['footprintCells']
    assert scene.view_settings.view_transform=='Standard'
    assert len(meshes)==report['meshValidation']['objects']
    assert any(mat.get('team',False) for ob in meshes for mat in ob.data.materials)
    positions=[]
    for entry in report['bounds']:
        set_frame(entry['sample']);bpy.context.view_layer.update()
        actual=bounds(scene,camera,meshes,report['cellSize'])
        assert max(abs(a-b) for a,b in zip(actual,entry['bounds']))<.001,(unit,'reopened bounds differ')
        coords=[ob.matrix_world@v.co for ob in meshes for v in ob.data.vertices]
        assert all(math.isfinite(n) for v in coords for n in v)
        assert all(abs(v.x)<=half+.0001 and abs(v.y)<=half+.0001 and v.z>=-.0001 for v in coords),(unit,'footprint/floor')
        positions.append([(ob.name,tuple(ob.location),tuple(ob.rotation_euler)) for ob in scene.objects if ob.animation_data])
    if len(report['bounds'])>1: assert positions[0]!=positions[1],(unit,'idle does not animate')
    set_frame(1)
    # Cosmetic review copy only: neither the saved blend nor runtime material is edited.
    for mat in bpy.data.materials:
        if mat.get('team',False): mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.14,.40,.68,1)
    scene.render.resolution_x=scene.render.resolution_y=512
    camera.data.ortho_scale=meta['footprintCells']*26/64*1.48
    scene.render.filepath=str(review/(unit+'-game.png'));bpy.ops.render.render(write_still=True)
    # Additional three-quarter assembly view for matching the concept; gameplay stays fixed.
    target=Vector((0,0,half*.40));camera.location=target+Vector((3,-5,7))
    camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(review/(unit+'-assembly.png'));bpy.ops.render.render(write_still=True)
    results.append({'unit':unit,'buildId':meta['buildId'],'footprintCells':meta['footprintCells'],
                    'poses':len(report['bounds']),'triangles':report['meshValidation']['triangles'],
                    'atlasBytes':sum(p['width']*p['height']*8 for p in meta['pages'])})
(review/'verification.json').write_text(json.dumps(results,indent=2))
print('PASS reopened buildings:',len(results),'models,',sum(r['poses'] for r in results),'poses; footprint, floor, bounds, team materials and rigid animation')
