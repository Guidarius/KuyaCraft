"""Generate and review the modular base in an isolated background Blender process."""
import argparse,json,math,sys,hashlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
from mathutils import Vector,Matrix
import pipeline as p
import mouse_base_model as model
CLIPS={'idle':('Idle_Loop',True),'walk':('Walk_Loop',True),'run':('Jog_Fwd_Loop',True),
       'punch':('Punch_Jab',False),'hit':('Hit_Chest',False),'celebrate':('Celebration',False)}

def run(a):
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
    pin=json.loads((a.root/'art/source/rig-library/source.json').read_text())
    assert p.digest(a.source)==pin['sha256']
    source=p.import_source(a.source);info=p.inventory(a.source,source);p.write_json(out/'source-inventory.json',info)
    rig=model.derive(source);meshes,sockets=model.build(rig)
    source.hide_render=True;source.hide_set(True)
    scene,parent,camera=p.setup_scene(rig,meshes,{})
    # Explicit sole/crown rest height; the ear and tail bounds never change body scale.
    height=max(v.co.z for o in meshes if o.name=='Head' for v in o.data.vertices)-min(v.co.z for o in meshes if o.name.startswith('Foot') for v in o.data.vertices)
    parent.scale=(1/height,)*3;parent.rotation_euler.z=0
    actions={};manifest={'sourceHash':pin['sha256'],'sourceBones':len(source.data.bones),'derivedBones':len(rig.data.bones),'sockets':sockets,'clips':{},'crownHeight':height,'cameraGameElevation':60,'gameCell':224,'gameAnchor':[112,128]}
    ordered=sorted(rig.pose.bones,key=lambda b:len(b.parent_recursive))
    for clip,(name,loop) in CLIPS.items():
        action=bpy.data.actions[name];start,end=action.frame_range
        count=max(2,math.ceil(end-start)+(0 if loop else 1));captures=[]
        for n,t in enumerate(p.sample_times(start,end,count,loop)):
            p.reset_pose(source);p.assign(source,action);p.set_frame(t)
            model.pose(source,rig,clip,n/(count if loop else count-1))
            # Hold the lowest stance foot at z=0, not the hands or tail.
            deps=bpy.context.evaluated_depsgraph_get();low=100
            for obj in meshes:
                if obj.name.startswith('Foot'):
                    ev=obj.evaluated_get(deps);data=ev.to_mesh();low=min(low,min(v.co.z for v in data.vertices));ev.to_mesh_clear()
            mat=rig.pose.bones['root'].matrix.copy();mat.translation.z-=low;rig.pose.bones['root'].matrix=mat
            bpy.context.view_layer.update();captures.append({b.name:b.matrix.copy() for b in ordered})
        rig.animation_data_clear();p.reset_pose(rig)
        for n,capture in enumerate(captures,1):
            scene.frame_set(n)
            for b in ordered:
                b.rotation_mode='QUATERNION';b.matrix=capture[b.name];bpy.context.view_layer.update()
                for prop in ('location','rotation_quaternion','scale'):b.keyframe_insert(data_path=prop,frame=n,group=b.name)
        baked=rig.animation_data.action;baked.name='MouseBase_'+clip;baked.use_fake_user=True;actions[clip]=baked
        manifest['clips'][clip]={'action':baked.name,'sourceAction':name,'frames':count,'fps':24,'loop':loop,'durationMs':round(count/24*1000)}
        print('BAKED',clip,count,flush=True)
    # Structural assertions are independent from visual approval.
    tris=0
    for obj in meshes:
        obj.data.calc_loop_triangles();tris+=len(obj.data.loop_triangles)
        for v in obj.data.vertices:
            assert v.groups and abs(sum(g.weight for g in v.groups)-1)<1e-5,'Unnormalized skin: '+obj.name
        assert not any(t in obj.name.lower() for t in ('helmet','shield','sword','tunic','bracer'))
    manifest['recipeHash']=hashlib.sha256((Path(__file__).read_bytes()+Path(model.__file__).read_bytes())).hexdigest();manifest['triangles']=tris;manifest['meshParts']={o.name:len(o.data.vertices) for o in meshes}
    # Shared full-animation camera bounds, with no per-frame framing changes.
    p.configure_camera(scene,camera,224);camera.data.ortho_scale=224/128
    game_camera=camera.copy();game_camera.data=camera.data.copy();game_camera.name='GameCamera_60deg';scene.collection.objects.link(game_camera)
    camera.name='ReviewCamera';target=Vector((0,0,.5));camera.location=(3,-6,3.7)
    camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=2.1
    def render(path,cam,size):
        scene.camera=cam;scene.render.resolution_x=scene.render.resolution_y=size
        scene.render.filepath=str(path);path.parent.mkdir(parents=True,exist_ok=True);bpy.ops.render.render(write_still=True)
    views={}
    for name,loc in [('front',(0,-6,.6)),('side',(6,0,.6)),('back',(0,6,.6)),('top',(0,0,7))]:
        cam=camera.copy();cam.data=camera.data.copy();cam.name='Fit_'+name;scene.collection.objects.link(cam)
        cam.location=loc;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=1.9;views[name]=cam
    parent.rotation_euler.z=0
    # Rest skin test is distinct from animated idle.
    rig.animation_data_clear();p.reset_pose(rig);rig.data.pose_position='REST'
    for name,cam in views.items():render(out/'reference'/(name+'.png'),cam,512)
    rig.data.pose_position='POSE';parent.rotation_euler.z=0
    for clip,spec in manifest['clips'].items():
        p.assign(rig,actions[clip])
        indices=sorted(set([1,1+spec['frames']//3,1+2*spec['frames']//3,spec['frames']])) if a.preview else range(1,spec['frames']+1)
        for n in indices:
            p.set_frame(n)
            box=p.bounds(scene,game_camera,meshes,448)
            assert min(box[:2])>1 and max(box[2:4])<447,('Game camera clips',clip,n,box)
            render(out/'review'/clip/(f'{n:03}.png'),camera,384)
            render(out/'game'/clip/(f'{n:03}.png'),game_camera,448)
        print('RENDERED',clip,flush=True)
    # Every action remains individually editable; timeline offers them all in sequence.
    rig.animation_data_clear();rig.animation_data_create();cursor=1
    for clip,action in actions.items():
        track=rig.animation_data.nla_tracks.new();track.name='Showcase '+clip
        strip=track.strips.new(clip,cursor,action)
        strip.action_frame_start=1;strip.action_frame_end=manifest['clips'][clip]['frames']
        strip.frame_start=cursor;strip.frame_end=cursor+manifest['clips'][clip]['frames']-1
        strip.extrapolation='NOTHING';scene.timeline_markers.new(clip,frame=cursor)
        manifest['clips'][clip]['timelineStart']=cursor;cursor+=manifest['clips'][clip]['frames']
    scene.frame_start=1;scene.frame_end=cursor-1;scene.render.fps=24;scene.frame_set(1);scene.camera=camera
    bpy.ops.object.select_all(action='DESELECT');rig.hide_set(False);rig.select_set(True);bpy.context.view_layer.objects.active=rig
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.region_3d.view_perspective='CAMERA'
                area.spaces.active.shading.type='MATERIAL'
    scene['ReviewInstructions']='Space plays six clips. Select MouseBaseRig; attachment empties are named attach_*. Source rig preserved hidden.'
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'mouse_base.blend'))
    manifest['preview']=a.preview;p.write_json(out/'manifest.json',manifest)
    assert p.digest(a.source)==pin['sha256']
    print('MOUSE_BASE_COMPLETE',tris,'triangles',len(meshes),'parts',flush=True)

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2])
    ap.add_argument('--source',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--preview',action='store_true')
    run(ap.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []))
