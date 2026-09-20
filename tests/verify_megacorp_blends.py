"""Reopen the latest infantry export, inspect posed geometry and render stress views.

Blender --background --factory-startup --python-exit-code 1
        --python tests/verify_megacorp_blends.py -- <root>
Accepts either a preview or a complete build as the latest asset-build report.
"""
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

root=Path(sys.argv[sys.argv.index('--')+1]).resolve()
sys.path.insert(0,str(root/'tools/blender'))
import pipeline as p
import megacorp_model as model
batch=json.loads((root/'artifacts/asset-build/latest-report.json').read_text())
out=root/'artifacts/infantry-review';out.mkdir(parents=True,exist_ok=True)
results=[]
for record in batch['results']:
    unit=record['unit']
    if unit not in ('associate','medic','enforcer'):continue
    stage=Path(record.get('stage') or root/'artifacts/asset-build'/record['buildId']/unit)
    recipe=json.loads((root/'art/recipes'/f'{unit}.json').read_text())
    report=json.loads((stage/'render.json').read_text())
    bpy.ops.wm.open_mainfile(filepath=str(stage/f'{unit}.blend'),use_scripts=False)
    rig=bpy.data.objects['Armature'];scene=bpy.context.scene;export=bpy.data.objects['ExportRoot']
    assert len(rig.data.bones)==65
    assert all(bpy.data.actions.get(a['name']) for a in json.loads((stage/'inventory.json').read_text())['actions'])
    assert p.digest(root/'art/source/rig-library/RTSAssets.blend')==recipe['sourceHash']
    meshes=[o for o in scene.objects if o.type=='MESH' and o.get('megacorpPart')]
    assert all(not any('finger' in g.name or 'thumb' in g.name or 'index' in g.name for g in o.vertex_groups) for o in meshes)
    checks=[]
    for clip,spec in recipe['clips'].items():
        p.assign(rig,bpy.data.actions[f'RTS_{unit}_{clip}'])
        for sample in range(1,spec['samples']+1):
            export.rotation_euler.z=0;p.set_frame(sample);bpy.context.view_layer.update()
            deps=bpy.context.evaluated_depsgraph_get();bottom=1e10;surfaces={}
            for ob in meshes:
                ev=ob.evaluated_get(deps);mesh=ev.to_mesh()
                verts=[ev.matrix_world @ v.co for v in mesh.vertices]
                assert all(math.isfinite(x) for v in verts for x in v)
                bottom=min(bottom,min(v.z for v in verts))
                surfaces[ob.name]=BVHTree.FromPolygons(verts,[list(f.vertices) for f in mesh.polygons])
                ev.to_mesh_clear()
            assert bottom>=-.002,(unit,clip,sample,'floor penetration',bottom)
            grip=model.grip_report(rig)
            if unit=='associate' and clip!='death':assert grip['supportGripError']<.015,(clip,sample,grip)
            overlap=0
            if unit=='associate':
                overlap=sum(len(surfaces[n].overlap(surfaces['HelmetShell'])) for n in ('CarbineHousing','CarbineBarrel'))
            elif unit=='enforcer':
                overlap=len(surfaces['ImpactGauntlet'].overlap(surfaces['PressureBarrel']))
            assert overlap==0,(unit,clip,sample,'weapon/body surface crossing',overlap)
            checks.append({'clip':clip,'sample':sample,'minZ':bottom,'weaponBodySurfaceCrossings':overlap,
                           'supportGripError':grip.get('supportGripError',0)})
    # Direct comparison to every stored bounds sample after reopening.
    for pose in report['bounds']:
        p.assign(rig,bpy.data.actions[f"RTS_{unit}_{pose['clip']}"])
        export.rotation_euler.z=math.pi-report['directions'].index(pose['direction'])*math.pi/4
        p.set_frame(pose['sample']);bpy.context.view_layer.update()
        actual=p.bounds(scene,scene.camera,meshes,report['cellSize'])
        assert max(abs(a-b) for a,b in zip(actual,pose['bounds']))<.001,(unit,pose,actual)
    for mat in bpy.data.materials:
        if mat.get('team'):
            mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.035,.16,.72,1)
    scene.render.resolution_x=scene.render.resolution_y=512
    for view in ('game','front'):
        if view=='front':
            target=Vector((0,0,.48));scene.camera.location=(2.5,-4,2.7)
            scene.camera.rotation_euler=(target-scene.camera.location).to_track_quat('-Z','Y').to_euler()
            scene.camera.data.ortho_scale=1.45
        for clip,sample in (('idle',1),('move',3),('attack',recipe['clips']['attack'].get('contactFrame',1)),('death',8)):
            p.assign(rig,bpy.data.actions[f'RTS_{unit}_{clip}']);p.set_frame(sample)
            export.rotation_euler.z=math.pi/4 if view=='game' else 0
            scene.render.filepath=str(out/f'{unit}-{view}-{clip}.png');bpy.ops.render.render(write_still=True)
    results.append({'unit':unit,'bones':65,'posesVerified':len(report['bounds']),
                    'sourcePreserved':True,'checks':checks})
(out/'verification.json').write_text(json.dumps(results,indent=2))
print('INFANTRY_REOPEN_REVIEW',[(r['unit'],r['posesVerified'],max(c['weaponBodySurfaceCrossings'] for c in r['checks'])) for r in results])
