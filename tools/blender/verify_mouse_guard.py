"""Inspect saved equipped NLA playback, grip contact and blade surface crossings."""
import argparse,json,math,sys
from pathlib import Path
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
import pipeline as p
from unit_model import PALM

def run(a):
    out=a.output.resolve();m=json.loads((out/'manifest.json').read_text())
    assert not m['preview']
    assert p.digest(a.base/'mouse_base.blend')==m['baseBlendHash']
    bpy.ops.wm.open_mainfile(filepath=str(out/'mouse_guard.blend'))
    rig=bpy.data.objects['MouseBaseRig'];scene=bpy.context.scene
    assert len(rig.data.bones)==71 and len(rig.animation_data.nla_tracks)==6
    assert all(s['bareAction'] in bpy.data.actions for s in m['clips'].values())
    inventory=json.loads((a.base/'source-inventory.json').read_text())
    assert all(s['name'] in bpy.data.actions for s in inventory['actions'])
    assert all(o in bpy.data.objects for names in m['equipment'].values() for o in names)
    armor=bpy.data.objects['GuardArmorVest'];assert armor.modifiers[0].object==rig
    assert all(abs(sum(g.weight for g in v.groups)-1)<1e-5 for v in armor.data.vertices)
    checks={};evaluated_triangles=0;collision_targets=('Head','Ear_l','Ear_r','Body','GuardHelmet','GuardShieldRim')
    for clip,spec in m['clips'].items():
        max_error=0;min_floor=100;crossings=[]
        for n in range(spec['frames']):
            scene.frame_set(spec['timelineStart']+n);bpy.context.view_layer.update()
            deps=bpy.context.evaluated_depsgraph_get();geometry={}
            for obj in scene.objects:
                if obj.type!='MESH':continue
                ev=obj.evaluated_get(deps);mesh=ev.to_mesh()
                if clip=='idle' and n==0:evaluated_triangles+=sum(len(f.vertices)-2 for f in mesh.polygons)
                vertices=[ev.matrix_world @ v.co for v in mesh.vertices]
                assert all(math.isfinite(c) for v in vertices for c in v)
                geometry[obj.name]=BVHTree.FromPolygons(vertices,[list(f.vertices) for f in mesh.polygons])
                if obj.get('equipmentSlot'):min_floor=min(min_floor,min(v.z for v in vertices))
                ev.to_mesh_clear()
            for obj_name,bone in [('GuardSwordGrip','hand_r'),('GuardShieldHandle','hand_l')]:
                obj=bpy.data.objects[obj_name];assert obj.parent.type=='EMPTY'
                center=sum((v.co for v in obj.data.vertices),Vector())/len(obj.data.vertices)
                error=(obj.matrix_world @ center-rig.matrix_world @ (rig.pose.bones[bone].matrix @ PALM)).length
                max_error=max(max_error,error)
            hit=[name for name in collision_targets if geometry['GuardSwordBlade'].overlap(geometry[name])]
            if hit:crossings.append({'frame':n+1,'targets':hit})
        checks[clip]={'frames':spec['frames'],'maxGripError':max_error,'equipmentMinZ':min_floor,'bladeSurfaceCrossings':crossings}
        assert max_error<1e-4,('Grip drift',clip,max_error)
        assert min_floor>-.001,('Equipment below floor',clip,min_floor)
    result={'basePreserved':True,'sourceActionsRetained':len(inventory['actions']),'bareActionsRetained':6,'equippedActions':6,'evaluatedTriangles':evaluated_triangles,'checks':checks}
    p.write_json(out/'saved-scene-validation.json',result)
    assert all(not c['bladeSurfaceCrossings'] for c in checks.values()),'Blade crosses character; inspect saved-scene-validation.json'
    print('GUARD_SAVED_SCENE_VALID',json.dumps(result),flush=True)

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--base',type=Path,required=True);ap.add_argument('--output',type=Path,required=True)
    run(ap.parse_args(sys.argv[sys.argv.index('--')+1:]))
