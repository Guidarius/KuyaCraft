"""Attach the modular guard kit to a saved mouse base and bake fitted review clips."""
import argparse,hashlib,json,math,sys
from pathlib import Path
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
import pipeline as p
import mouse_guard_equipment as kit

def run(a):
    assert bpy.app.background,'Run in an isolated background process'
    source=a.base.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
    base_hash=p.digest(source/'mouse_base.blend')
    m=json.loads((source/'manifest.json').read_text());assert not m['preview']
    bpy.ops.wm.open_mainfile(filepath=str(source/'mouse_base.blend'))
    scene=bpy.context.scene;rig=bpy.data.objects['MouseBaseRig'];root=rig.parent
    bare={clip:bpy.data.actions[spec['action']] for clip,spec in m['clips'].items()}
    rig.animation_data_clear();p.reset_pose(rig);rig.data.pose_position='REST';bpy.context.view_layer.update()
    gear,slots=kit.build(rig);rig.data.pose_position='POSE'
    meshes=[o for o in scene.objects if o.type=='MESH']
    ordered=sorted(rig.pose.bones,key=lambda b:len(b.parent_recursive));fitted={}
    for clip,spec in m['clips'].items():
        captures=[]
        for n in range(spec['frames']):
            p.assign(rig,bare[clip]);p.set_frame(n+1)
            kit.fit_pose(rig,clip,n/(spec['frames'] if spec['loop'] else max(1,spec['frames']-1)))
            captures.append({b.name:b.matrix.copy() for b in ordered})
        rig.animation_data_clear();p.reset_pose(rig)
        for n,capture in enumerate(captures,1):
            scene.frame_set(n)
            for b in ordered:
                b.rotation_mode='QUATERNION';b.matrix=capture[b.name];bpy.context.view_layer.update()
                for prop in ('location','rotation_quaternion','scale'):b.keyframe_insert(data_path=prop,frame=n,group=b.name)
        action=rig.animation_data.action;action.name='MouseGuard_'+clip;action.use_fake_user=True
        fitted[clip]=action;spec['bareAction']=spec['action'];spec['action']=action.name
    m.update({'baseBlendHash':base_hash,'equipment':slots,'preview':a.preview,'recipeHash':hashlib.sha256(Path(__file__).read_bytes()+Path(kit.__file__).read_bytes()).hexdigest()})
    m['triangles']=sum(len(f.vertices)-2 for o in meshes for f in o.data.polygons)
    m['title']='Mouse guard · Equipment review';m['subtitle']='Sword, shield, open-ear helmet and weighted armor. Six fitted motions.'
    m['blendFile']='mouse_guard.blend';m['videoTitle']='MOUSE GUARD / modular equipment motion test'
    camera=bpy.data.objects['ReviewCamera'];game=bpy.data.objects['GameCamera_60deg']
    normal={o.name:list(o.data.materials) for o in meshes};mask={True:p.mask_material(True),False:p.mask_material(False)}
    checks={'baseBlendPreserved':True,'frames':{},'equipment':slots,'originalActionsRetained':all(n in bpy.data.actions for n in [s['bareAction'] for s in m['clips'].values()])}
    def render(path,cam,size,coverage=False):
        for o in meshes:
            for i,mat in enumerate(normal[o.name]):o.data.materials[i]=mask[bool(mat.get('team',False))] if coverage else mat
        team_mats={mat for values in normal.values() for mat in values if mat.get('team',False)}
        # The shared pixel finisher derives shade levels from neutral team color.
        # Review renders show blue; game input is neutral with a separate mask.
        for mat in team_mats:
            mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.52,.52,.52,1) if cam==game else (.20,.38,.61,1)
        scene.camera=cam;scene.render.resolution_x=scene.render.resolution_y=size
        path.parent.mkdir(parents=True,exist_ok=True);scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
    for clip,spec in m['clips'].items():
        p.assign(rig,fitted[clip]);collision_frames=[]
        indices=sorted(set([1,1+spec['frames']//3,1+2*spec['frames']//3,spec['frames']])) if a.preview else range(1,spec['frames']+1)
        for n in indices:
            p.set_frame(n)
            box=p.bounds(scene,game,meshes,m['gameCell']*2)
            assert min(box[:2])>1 and max(box[2:4])<m['gameCell']*2-1,('Equipment clips canvas',clip,n,box)
            deps=bpy.context.evaluated_depsgraph_get()
            def bvh(obj):
                ev=obj.evaluated_get(deps);mesh=ev.to_mesh()
                result=BVHTree.FromPolygons([ev.matrix_world @ v.co for v in mesh.vertices],[list(f.vertices) for f in mesh.polygons]);ev.to_mesh_clear();return result
            blade=bvh(bpy.data.objects['GuardSwordBlade'])
            if any(blade.overlap(bvh(bpy.data.objects[x])) for x in ('Head','Ear_l','Ear_r','Body','GuardHelmet','GuardShieldRim')):collision_frames.append(n)
            for obj in gear:
                if obj.name!='GuardArmorVest':assert obj.parent.type=='EMPTY'
            render(out/'review'/clip/f'{n:03}.png',camera,384)
            render(out/'game'/clip/f'{n:03}.png',game,m['gameCell']*2)
            render(out/'mask'/clip/f'{n:03}.png',game,m['gameCell']*2,True)
        checks['frames'][clip]={'samples':len(indices),'bladeSurfaceCrossings':collision_frames}
        print('GUARD_RENDERED',clip,checks['frames'][clip],flush=True)
    # Above/rear/side proofs on the same fitted idle, and eight independent headings.
    p.assign(rig,fitted['idle']);p.set_frame(1)
    for name in ('front','side','back','top'):render(out/'reference'/f'{name}.png',bpy.data.objects['Fit_'+name],512)
    for i in range(8):
        root.rotation_euler.z=i*math.pi/4;bpy.context.view_layer.update()
        render(out/'directions'/f'{i}.png',game,448)
    root.rotation_euler.z=0
    for obj in meshes:
        for i,mat in enumerate(normal[obj.name]):obj.data.materials[i]=mat
    for values in normal.values():
        for mat in values:
            if mat.get('team',False):mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.20,.38,.61,1)
    rig.animation_data_clear();rig.animation_data_create();cursor=1
    for marker in list(scene.timeline_markers):scene.timeline_markers.remove(marker)
    for clip,action in fitted.items():
        spec=m['clips'][clip];track=rig.animation_data.nla_tracks.new();track.name='Guard '+clip
        strip=track.strips.new(clip,cursor,action);strip.action_frame_start=1;strip.action_frame_end=spec['frames']
        strip.frame_start=cursor;strip.frame_end=cursor+spec['frames']-1;strip.extrapolation='NOTHING'
        scene.timeline_markers.new(clip,frame=cursor);spec['timelineStart']=cursor;cursor+=spec['frames']
    scene.frame_start=1;scene.frame_end=cursor-1;scene.frame_set(1);scene.camera=camera
    scene['ReviewInstructions']='Space plays six equipped clips. Toggle Equipment_* collections. Bare MouseBase_* actions are preserved.'
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'mouse_guard.blend'))
    assert p.digest(source/'mouse_base.blend')==base_hash
    p.write_json(out/'manifest.json',m);p.write_json(out/'validation.json',checks)
    print('GUARD_COMPLETE',m['triangles'],flush=True)

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--base',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--preview',action='store_true')
    run(ap.parse_args(sys.argv[sys.argv.index('--')+1:]))
