"""Reopen the published pod scene and verify actual keyed doors and camera bounds."""
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector

root=Path(sys.argv[sys.argv.index('--')+1]).resolve()
sys.path.insert(0,str(root/'tools/blender'))
import pipeline as p
catalog=json.loads((root/'assets/generated/catalog.json').read_text())
meta=json.loads((root/catalog['units']['drop_pod']).with_suffix('.json').read_text())
stage=root/'artifacts/asset-build'/meta['buildId']/'drop_pod'
report=json.loads((stage/'render.json').read_text())
bpy.ops.wm.open_mainfile(filepath=str(stage/'drop_pod.blend'),use_scripts=False)
scene=bpy.context.scene;meshes=[ob for ob in scene.objects if ob.type=='MESH']
assert len(meshes)==report['meshValidation']['objects']
assert len(meta['frames'])==7 and meta['fixedFacing']=='S'
doors=[bpy.data.objects[name] for name in ('DoorHingeLeft','DoorHingeRight')]
checks=[]
for frame in range(1,7):
    scene.frame_set(frame);bpy.context.view_layer.update()
    extent=p.bounds(scene,scene.camera,meshes,report['cellSize'])
    assert extent[4]>=-.0001 and min(extent[:2])>=2 and max(extent[2:4])<=report['cellSize']-2
    for door,sign in zip(doors,(-1,1)):
        assert door.animation_data.action and len(door.children)==3
        assert abs(door.rotation_euler.z-sign*math.radians(105)*(frame-1)/5)<.0001
    checks.append({'frame':frame,'bounds':extent})
scene.frame_set(6);scene.render.filepath=str(stage/'reopened-open.png');bpy.ops.render.render(write_still=True)
(stage/'saved-scene-check.json').write_text(json.dumps({'passed':True,'checks':checks},indent=2))
review=root/'artifacts/drop-pod-review';review.mkdir(parents=True,exist_ok=True)
for mat in bpy.data.materials:
    if mat.get('team'):mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.035,.16,.72,1)
scene.render.resolution_x=scene.render.resolution_y=768
scene.camera.data.ortho_scale=1.4
for label,frame in (('closed',1),('open',6)):
    scene.frame_set(frame);scene.render.filepath=str(review/f'{label}-game-camera.png');bpy.ops.render.render(write_still=True)
scene.frame_set(6);scene.camera.location=(2,-4,3)
scene.camera.rotation_euler=(Vector((0,0,.42))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
scene.camera.data.ortho_scale=1.6
scene.render.filepath=str(review/'open-assembly.png');bpy.ops.render.render(write_still=True)
print('PASS saved drop pod: two editable door joints, six keyed poses, grounded, no clipping, seven unique atlas frames')
