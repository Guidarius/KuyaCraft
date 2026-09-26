"""Reopen every Orders scene and compare all saved poses with the export report.
Run with Blender background --python-exit-code 1 --python this.py -- <root>.
"""
import json, math, sys
from pathlib import Path
import bpy
root=Path(sys.argv[sys.argv.index('--')+1]).resolve()
sys.path.insert(0,str(root/'tools/blender'))
import pipeline as p
ids=['worker','worker_loaded','footman','crossbow','gryphon','reliquary','keep','depot','barracks','sanctum']
cat=json.loads((root/'assets/generated/catalog.json').read_text())
results=[]
for uid in ids:
    meta=json.loads((root/cat['units'][uid]).with_suffix('.json').read_text())
    stage=root/'artifacts/asset-build'/meta['buildId']/uid
    recipe=json.loads((root/'art/recipes'/f'{uid}.json').read_text())
    report=json.loads((stage/'render.json').read_text())
    bpy.ops.wm.open_mainfile(filepath=str(stage/f'{uid}.blend'),use_scripts=False)
    scene=bpy.context.scene;export=bpy.data.objects['ExportRoot']
    meshes=[o for o in scene.objects if o.type=='MESH']
    assert meshes and all(len(o.data.polygons)>0 for o in meshes)
    assert all(o.data.materials and all(m.node_tree.nodes.get('Principled BSDF') for m in o.data.materials) for o in meshes),'Saved scene has mask materials'
    if 'sourceHash' in recipe:
        assert p.digest(root/'art/source/rig-library/RTSAssets.blend')==recipe['sourceHash']
        assert len(bpy.data.objects['Armature'].data.bones)==65
        for name in ['Idle_Loop','Walk_Loop','Sword_Idle','Sword_Attack_Standing','Death01']:
            assert bpy.data.actions.get(name),'Original action missing: '+name
    if uid=='gryphon':
        rider=bpy.data.objects['Armature'];mount=bpy.data.objects['GryphonRig']
        assert rider.parent.name=='SaddleSocket' and len(mount.data.bones)==18
        assert all(mount.data.bones.get(row+side+'Paw') for row in ('F','H') for side in ('L','R'))
    min_z=100;max_error=0;poses=report['bounds']
    for pose in poses:
        if uid in ids[6:]:
            p.set_frame(pose['stage'])
        else:
            clip=pose['clip']
            if uid in ids[:4]:p.assign(bpy.data.objects['Armature'],bpy.data.actions[f'RTS_{uid}_{clip}'])
            else:
                for ob in scene.objects:
                    action=bpy.data.actions.get(f'RTS_{uid}_{clip}_{ob.name}')
                    if action:p.assign(ob,action)
            export.rotation_euler.z=math.pi-report['directions'].index(pose['direction'])*math.pi/4
            p.set_frame(pose['sample'])
        bpy.context.view_layer.update()
        visible=[o for o in meshes if not o.hide_render]
        actual=p.bounds(scene,scene.camera,visible,report['cellSize'])
        error=max(abs(a-b) for a,b in zip(actual,pose['bounds']));max_error=max(max_error,error);min_z=min(min_z,actual[4])
        assert error<.001,(uid,pose,error)
        assert all(math.isfinite(v) for v in actual)
        assert actual[4]>=-.002,(uid,pose,'floor penetration',actual[4])
    # Re-render a larger inspection image without changing the calibrated camera.
    if uid in ids[6:]:p.set_frame(4)
    else:
        for ob in scene.objects:
            action=bpy.data.actions.get(f'RTS_{uid}_idle_{ob.name}') or (bpy.data.actions.get(f'RTS_{uid}_idle') if ob.name=='Armature' else None)
            if action:p.assign(ob,action)
        p.set_frame(1);export.rotation_euler.z=math.pi/4
    out=root/'artifacts/orders/reopened';out.mkdir(parents=True,exist_ok=True)
    scene.render.resolution_x=scene.render.resolution_y=report['cellSize']*6
    scene.render.filepath=str(out/f'{uid}.png');bpy.ops.render.render(write_still=True)
    results.append(dict(unit=uid,buildId=meta['buildId'],poses=len(poses),minimumZ=min_z,maxSavedPoseError=max_error,editableMeshes=len(meshes)))
(root/'artifacts/orders/blend-verification.json').write_text(json.dumps(results,indent=2))
print('ORDERS_REOPEN_PASS',sum(r['poses'] for r in results),'saved poses',len(results),'scenes')
