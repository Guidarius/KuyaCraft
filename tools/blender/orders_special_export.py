"""Small dedicated mounted/rigid adapter, sharing the production sprite contract."""
import json
import math
import time
from pathlib import Path
import bpy
import orders_special_model as model
from pipeline import DIRECTIONS, bounds, configure_camera, digest, mask_material, setup_scene, set_frame, write_json


def bake(assembly, recipe):
    objects=list(dict.fromkeys(assembly['objects']+assembly['rigs']))
    for ob in objects:
        ob.animation_data_clear()
    for rig in assembly['rigs']:
        for bone in rig.pose.bones:
            for constraint in list(bone.constraints):bone.constraints.remove(constraint)
        for constraint in list(rig.constraints):rig.constraints.remove(constraint)
    captures={}
    for clip,spec in recipe['clips'].items():
        captures[clip]=[]
        for sample in range(spec['samples']):
            phase=sample/(spec['samples'] if spec['loop'] else max(1,spec['samples']-1))
            assembly['pose'](clip,phase);bpy.context.view_layer.update()
            captures[clip].append((
                {ob.name:(ob.location.copy(),ob.rotation_euler.copy(),ob.scale.copy()) for ob in objects},
                {rig.name:{b.name:b.matrix.copy() for b in rig.pose.bones} for rig in assembly['rigs']}))
    actions={}
    for clip,poses in captures.items():
        for ob in objects:ob.animation_data_clear()
        for sample,(transforms,bones) in enumerate(poses):
            set_frame(sample+1)
            for ob in objects:
                ob.location,ob.rotation_euler,ob.scale=transforms[ob.name]
                for prop in ('location','rotation_euler','scale'):ob.keyframe_insert(prop,frame=sample+1)
            for rig in assembly['rigs']:
                for bone in sorted(rig.pose.bones,key=lambda b:len(b.parent_recursive)):
                    bone.rotation_mode='QUATERNION';bone.matrix=bones[rig.name][bone.name]
                    bpy.context.view_layer.update()
                    for prop in ('location','rotation_quaternion','scale'):bone.keyframe_insert(prop,frame=sample+1)
        actions[clip]=[]
        for ob in objects:
            action=ob.animation_data.action;action.name=f'RTS_{recipe["unitId"]}_{clip}_{ob.name}'
            action.use_fake_user=True;actions[clip].append((ob,action,ob.animation_data.action_slot))
    return actions


def run(options):
    if not bpy.app.background:raise RuntimeError('Use isolated background Blender')
    started=time.monotonic();rootpath=Path(options.root);output=Path(options.output);output.mkdir(parents=True,exist_ok=True)
    path=rootpath/'art/recipes'/f'{options.unit}.json';recipe=json.loads(path.read_text(encoding='utf8'))
    assert recipe['unitId']==options.unit
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    if options.unit=='gryphon':
        assert digest(options.source)==recipe['sourceHash'],'Source library differs from pin'
        assembly=model.build_gryphon(recipe,options.source)
    else:assembly=model.build_reliquary(recipe)
    actions=bake(assembly,recipe);meshes=assembly['meshes']
    scene,root,camera=setup_scene(assembly['motion'],meshes,recipe)
    def select(clip,sample,di):
        for ob,action,slot in actions[clip]:ob.animation_data.action=action;ob.animation_data.action_slot=slot
        root.rotation_euler.z=math.pi-di*math.pi/4
        set_frame(sample+1);bpy.context.view_layer.update()
    for size in (64,96,128):
        configure_camera(scene,camera,size);poses=[]
        for clip,spec in recipe['clips'].items():
            for di,direction in enumerate(DIRECTIONS):
                for sample in range(spec['samples']):
                    select(clip,sample,di)
                    poses.append(dict(clip=clip,direction=direction,sample=sample+1,bounds=bounds(scene,camera,meshes,size)))
        if all(min(p['bounds'][:2])>=2 and max(p['bounds'][2:4])<=size-2 for p in poses):break
    else:raise ValueError('Mounted/rigid asset exceeds 128px canvas')
    if min(p['bounds'][4] for p in poses)<-.012:raise ValueError('Mounted/rigid asset penetrates ground')
    info={'source':assembly['notes'],'sourceHash':assembly.get('sourceHash',digest(path)),
          'blender':bpy.app.version_string,'bones':{r.name:len(r.data.bones) for r in assembly['rigs']},
          'actions':[a.name for a in bpy.data.actions], 'objects':[o.name for o in meshes],
          'triangles':sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)}
    write_json(output/'inventory.json',info)
    select('idle',0,0);scene.frame_start=1;scene.frame_end=recipe['clips']['idle']['samples']
    bpy.ops.wm.save_as_mainfile(filepath=str(output/(options.unit+'.blend')))
    clips={k:{'durationMs':v['durationMs'],'loop':v['loop'],'samples':1 if options.preview else v['samples'],
              **({'contactFrame':1 if options.preview else v['contactFrame']} if 'contactFrame' in v else {})}
           for k,v in recipe['clips'].items()}
    report={'version':2,'unitId':options.unit,'profileId':recipe['profileId'],'cellSize':size,
            'anchorX':size/2,'anchorY':size/2+8,'bodyHeightPixels':32,'directions':DIRECTIONS,
            'clips':clips,'frames':[],'renderScale':2,'preview':options.preview,'sourceHash':info['sourceHash'],
            'meshValidation':info,'bounds':poses,'referenceStride':{'distance':assembly['stride'],'units':'navigationCells'},
            'renderSettings':{'engine':scene.render.engine,'samples':32,'elevation':60,'pixelsPerUnit':64,'colorTransform':'Standard','exposure':0,'gamma':1}}
    normal={o.name:list(o.data.materials) for o in meshes};masks={True:mask_material(True),False:mask_material(False)}
    if options.mode!='inspect':
        for clip,spec in clips.items():
            for di,direction in enumerate(DIRECTIONS):
                for sample in range(spec['samples']):
                    select(clip,sample,di);entry=dict(clip=clip,direction=direction,sample=sample+1)
                    for channel in ('color','mask'):
                        for ob in meshes:
                            for i,mat in enumerate(normal[ob.name]):ob.data.materials[i]=mat if channel=='color' else masks[bool(mat.get('team',False))]
                        rel=Path('raw')/clip/direction/f'{sample+1:03d}-{channel}.png';(output/rel).parent.mkdir(parents=True,exist_ok=True)
                        scene.render.filepath=str(output/rel);bpy.ops.render.render(write_still=True);entry[channel]=rel.as_posix()
                    report['frames'].append(entry)
                    print('ASSET_POSE',options.unit,len(report['frames']),flush=True)
    report['elapsedSeconds']=round(time.monotonic()-started,2);write_json(output/'render.json',report)
    print('ASSET_RENDER_COMPLETE',options.unit,len(report['frames']),flush=True)
