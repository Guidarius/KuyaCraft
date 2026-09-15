"""Reopen and validate the actual derived scene, including NLA playback and sockets."""
import argparse,json,sys,math
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import pipeline as p
def run(a):
    folder=a.output.resolve();m=json.loads((folder/'manifest.json').read_text());source=json.loads((folder/'source-inventory.json').read_text())
    assert not m['preview']
    assert p.digest(a.source)==m['sourceHash']
    bpy.ops.wm.open_mainfile(filepath=str(folder/'mouse_base.blend'))
    rig=bpy.data.objects['MouseBaseRig'];original=bpy.data.objects['Armature']
    assert len(original.data.bones)==65 and len(rig.data.bones)==71
    assert set(source['bones']).issubset(rig.data.bones.keys())
    assert all(a['name'] in bpy.data.actions for a in source['actions'])
    assert set(m['meshParts'])=={o.name for o in bpy.context.scene.objects if o.type=='MESH'}
    assert len(rig.animation_data.nla_tracks)==6
    for name,s in m['sockets'].items():
        ob=bpy.data.objects['attach_'+name]
        assert ob.parent==rig and ob.parent_type=='BONE' and ob.parent_bone==s['bone']
    ranges={}
    for clip,s in m['clips'].items():
        positions=[];lowest=[]
        for n in range(s['frames']):
            bpy.context.scene.frame_set(s['timelineStart']+n);bpy.context.view_layer.update()
            positions.append(tuple(rig.pose.bones['hand_r'].matrix.translation))
            deps=bpy.context.evaluated_depsgraph_get();z=[]
            for ob in bpy.context.scene.objects:
                if ob.type=='MESH':
                    ev=ob.evaluated_get(deps);data=ev.to_mesh()
                    assert all(math.isfinite(c) for v in data.vertices for c in v.co)
                    if ob.name.startswith('Foot'):z.extend((ev.matrix_world @ v.co).z for v in data.vertices)
                    ev.to_mesh_clear()
            lowest.append(min(z))
        travel=max((Vector(x)-Vector(positions[0])).length for x in positions)
        assert travel>1e-5,('NLA clip is static',clip)
        assert max(abs(z) for z in lowest)<.003,('Feet ungrounded',clip,min(lowest),max(lowest))
        ranges[clip]={'handTravel':travel,'floorRange':[min(lowest),max(lowest)]}
    result={'sourcePreserved':True,'sourceActionsRetained':len(source['actions']),'derivedBones':71,'triangles':m['triangles'],'clips':ranges,'equipmentMeshes':0,'sockets':len(m['sockets'])}
    p.write_json(folder/'validation.json',result);print('MOUSE_BASE_VALID',json.dumps(result))
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--source',type=Path,required=True);ap.add_argument('--output',type=Path,required=True)
    run(ap.parse_args(sys.argv[sys.argv.index('--')+1:]))
