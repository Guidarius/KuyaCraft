"""Isolated mouse rendering; shares saved-source intake, camera, bounds and materials."""
import json, math, time
from pathlib import Path
import bpy
from mathutils import Vector
import pipeline as p
import woodland_model as model

def run(options):
    start=time.monotonic();rootpath=Path(options.root);out=Path(options.output);out.mkdir(parents=True,exist_ok=True)
    recipe=json.loads((rootpath/'art/recipes/woodland/mouse_builder.json').read_text(encoding='utf-8-sig'))
    source=p.import_source(Path(options.source));info=p.inventory(options.source,source)
    assert info['sourceHash']==recipe['sourceHash'],'Source hash mismatch'
    assert not info['drivers'],'Source drivers require review'
    p.write_json(out/'inventory.json',info)
    rig=model.derive(source);meshes=model.build(rig)
    captures={};timing={}
    for clip,spec in recipe['clips'].items():
        times=p.sample_times(*bpy.data.actions[spec['action']].frame_range,spec['samples'],True)
        captures[clip]=[]
        for i,t in enumerate(times):
            p.reset_pose(source);p.assign(source,bpy.data.actions[spec['action']]);p.set_frame(t)
            model.pose(source,rig,clip,i/len(times))
            deps=bpy.context.evaluated_depsgraph_get();feet=[]
            for obj in meshes:
                if obj.name.startswith('Boot'):
                    ev=obj.evaluated_get(deps);mesh=ev.to_mesh();feet += [v.co.z for v in mesh.vertices];ev.to_mesh_clear()
            matrix=rig.pose.bones['root'].matrix.copy();matrix.translation.z-=min(feet)
            rig.pose.bones['root'].matrix=matrix;bpy.context.view_layer.update()
            captures[clip].append({b.name:b.matrix.copy() for b in rig.pose.bones})
        timing[clip]={'sourceAction':spec['action'],'sourceSampleTimes':times}
    baked={};ordered=sorted(rig.pose.bones,key=lambda b:len(b.parent_recursive))
    for clip,poses in captures.items():
        rig.animation_data_clear();p.reset_pose(rig)
        for i,pose in enumerate(poses):
            bpy.context.scene.frame_set(i+1)
            for bone in ordered:
                bone.rotation_mode='QUATERNION';bone.matrix=pose[bone.name];bpy.context.view_layer.update()
                for prop in ['location','rotation_quaternion','scale']:bone.keyframe_insert(data_path=prop,frame=i+1)
        baked[clip]=rig.animation_data.action;baked[clip].name='Mouse_'+clip;baked[clip].use_fake_user=True
    scene,parent,camera=p.setup_scene(rig,meshes,{})
    body=[v.co.z for obj in meshes if obj.name=='HeadCrown' or obj.name.startswith('Boot') for v in obj.data.vertices]
    height=max(body)-min(body);parent.scale=(1/height,)*3
    # Sole-to-crown projected vertical height = 64 pixels; ears are excluded.
    for size in [128,160,192,224,256]:
        p.configure_camera(scene,camera,size);camera.data.ortho_scale=size/128
        allbounds=[]
        for clip,spec in recipe['clips'].items():
            p.assign(rig,baked[clip])
            for di,direction in enumerate(p.DIRECTIONS):
                parent.rotation_euler.z=math.pi-di*math.pi/4
                for n in range(spec['samples']):
                    p.set_frame(n+1);bpy.context.view_layer.update()
                    box=p.bounds(scene,camera,meshes,size)
                    allbounds.append({'clip':clip,'direction':direction,'sample':n+1,'bounds':box})
        if all(b['bounds'][0]>=6 and b['bounds'][1]>=6 and b['bounds'][2]<=size-6 and b['bounds'][3]<=size-6 for b in allbounds):break
    else:raise ValueError('Mouse exceeds 256 pixel canvas')
    clips={k:{'samples':1 if options.preview else v['samples'],'durationMs':v['durationMs'],'loop':True} for k,v in recipe['clips'].items()}
    report={'version':2,'unitId':'mouse_builder','profileId':'woodland_pixel_v1','cellSize':size,'anchorX':size//2,'anchorY':size//2+16,'bodyHeightPixels':64,'directions':p.DIRECTIONS,'clips':clips,'frames':[], 'sourceHash':info['sourceHash'],'bounds':allbounds,'animation':timing,'sourceBones':len(source.data.bones),'derivedBones':len(rig.data.bones),'sourceActions':len(info['actions']),'bodyHeightSourceUnits':height,'preview':options.preview}
    originals={obj.name:list(obj.data.materials) for obj in meshes};masks={True:p.mask_material(True),False:p.mask_material(False)}
    for clip,spec in clips.items():
        p.assign(rig,baked[clip])
        for di,direction in enumerate(p.DIRECTIONS):
            parent.rotation_euler.z=math.pi-di*math.pi/4
            for n in range(spec['samples']):
                p.set_frame(n+1);entry={'clip':clip,'direction':direction,'sample':n+1}
                for channel in ['color','mask']:
                    for obj in meshes:
                        for j,mat in enumerate(originals[obj.name]):obj.data.materials[j]=mat if channel=='color' else masks[bool(mat.get('team',False))]
                    path=Path('raw')/clip/direction/(str(n+1).zfill(3)+'-'+channel+'.png');(out/path).parent.mkdir(parents=True,exist_ok=True)
                    scene.render.filepath=str(out/path);bpy.ops.render.render(write_still=True);entry[channel]=path.as_posix()
                report['frames'].append(entry);print('MOUSE_POSE',len(report['frames']),flush=True)
    for obj in meshes:
        for j,mat in enumerate(originals[obj.name]):obj.data.materials[j]=mat
    p.assign(rig,baked['idle']);p.set_frame(1);parent.rotation_euler.z=0
    source.hide_set(True);source.hide_render=True
    scene.frame_start=1;scene.frame_end=recipe['clips']['idle']['samples']
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'mouse_builder.blend'))
    report['seconds']=time.monotonic()-start;p.write_json(out/'render.json',report)
    assert p.digest(options.source)==info['sourceHash']
    print('MOUSE_RENDER_COMPLETE',len(report['frames']),flush=True)
