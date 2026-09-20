"""Rigid aircraft adapter for the production camera, paired passes and packer."""
import json
import math
from pathlib import Path
import time
import bpy
import aircraft_model as model
from pipeline import (DIRECTIONS, bounds, configure_camera, digest, mask_material,
                      setup_scene, set_frame, write_json)


def run(options):
    if not bpy.app.background:
        raise RuntimeError('Aircraft production requires isolated background Blender')
    started=time.monotonic()
    rootpath=Path(options.root).resolve(); output=Path(options.output).resolve()
    output.mkdir(parents=True,exist_ok=True)
    recipe_path=rootpath/'art/recipes'/f'{options.unit}.json'
    recipe=json.loads(recipe_path.read_text(encoding='utf8'))
    if recipe['unitId']!=options.unit or recipe['sourceId']!='procedural_aircraft_v1':
        raise ValueError('Aircraft recipe identity mismatch')
    for name,spec in recipe['clips'].items():
        if type(spec['samples']) is not int or spec['samples']<1 or type(spec['durationMs']) is not int or spec['durationMs']<1:
            raise ValueError('Invalid aircraft clip '+name)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    motion,meshes,recoil=model.build(recipe)
    scene,root,camera=setup_scene(motion,meshes,recipe)
    # Bake editable object actions. The exporter and saved scene read the same keys.
    actions={}
    for clip,spec in recipe['clips'].items():
        for ob in (motion,recoil):
            if ob: ob.animation_data_clear()
        for sample in range(spec['samples']):
            model.pose(motion,recoil,clip,sample,spec)
            for ob in (motion,recoil):
                if ob:
                    ob.keyframe_insert('location',frame=sample+1)
                    ob.keyframe_insert('rotation_euler',frame=sample+1)
        actions[clip]=[]
        for ob in (motion,recoil):
            if ob:
                action=ob.animation_data.action
                action.name=f'RTS_{options.unit}_{clip}_{ob.name}';action.use_fake_user=True
                actions[clip].append((ob,action,ob.animation_data.action_slot))

    def select(clip,sample,di):
        for ob,action,slot in actions[clip]:
            ob.animation_data.action=action;ob.animation_data.action_slot=slot
        root.rotation_euler.z=math.pi-di*math.pi/4
        set_frame(sample+1);bpy.context.view_layer.update()

    pose_bounds=[]
    for size in (64,96,128):
        configure_camera(scene,camera,size);pose_bounds=[]
        for clip,spec in recipe['clips'].items():
            for di,direction in enumerate(DIRECTIONS):
                for sample in range(spec['samples']):
                    select(clip,sample,di)
                    pose_bounds.append(dict(clip=clip,direction=direction,sample=sample+1,
                                            bounds=bounds(scene,camera,meshes,size)))
        if all(b['bounds'][0]>=2 and b['bounds'][1]>=2 and b['bounds'][2]<=size-2 and b['bounds'][3]<=size-2 for b in pose_bounds):
            break
    else:
        write_json(output/'bounds-failure.json',pose_bounds)
        raise ValueError('Aircraft exceeds approved 128px canvas')
    info={'source':'Original procedural pressure hulls','sourceHash':digest(recipe_path),
          'blender':bpy.app.version_string,'objects':[o.name for o in meshes],
          'triangles':sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons),
          'actions':[a.name for a in bpy.data.actions],'boneCount':0}
    write_json(output/'inventory.json',info)
    select('idle',0,0)
    scene.frame_start=1;scene.frame_end=recipe['clips']['idle']['samples']
    bpy.ops.wm.save_as_mainfile(filepath=str(output/(options.unit+'.blend')))
    if options.mode=='inspect': return
    clips={k:{'durationMs':v['durationMs'],'loop':v['loop'],
              'samples':1 if options.preview else v['samples'],
              **({'contactFrame':1 if options.preview else v['contactFrame']} if 'contactFrame' in v else {})}
           for k,v in recipe['clips'].items()}
    normal={o.name:list(o.data.materials) for o in meshes}
    masks={True:mask_material(True),False:mask_material(False)}
    report={'version':2,'unitId':options.unit,'profileId':recipe['profileId'],
            'cellSize':size,'anchorX':size/2,'anchorY':size/2+8,
            'bodyHeightPixels':recipe['bodyHeightPixels'],'directions':DIRECTIONS,
            'clips':clips,'frames':[],'renderScale':2,'preview':options.preview,
            'sourceHash':info['sourceHash'],'meshValidation':info,'bounds':pose_bounds,
            'referenceStride':{'distance':2,'units':'navigationCells'},
            'renderSettings':{'engine':scene.render.engine,'samples':32,'elevation':60,
                              'pixelsPerUnit':64,'colorTransform':'Standard','exposure':0,'gamma':1}}
    total=sum(c['samples'] for c in clips.values())*8
    for clip,spec in clips.items():
        for di,direction in enumerate(DIRECTIONS):
            for sample in range(spec['samples']):
                select(clip,sample,di)
                entry=dict(clip=clip,direction=direction,sample=sample+1)
                for channel in ('color','mask'):
                    for ob in meshes:
                        for i,mat in enumerate(normal[ob.name]):
                            ob.data.materials[i]=mat if channel=='color' else masks[bool(mat.get('team',False))]
                    relative=Path('raw')/clip/direction/f'{sample+1:03d}-{channel}.png'
                    (output/relative).parent.mkdir(parents=True,exist_ok=True)
                    scene.render.filepath=str(output/relative);bpy.ops.render.render(write_still=True)
                    entry[channel]=relative.as_posix()
                report['frames'].append(entry)
                print('ASSET_POSE',options.unit,len(report['frames']),total,flush=True)
    report['elapsedSeconds']=round(time.monotonic()-started,2)
    write_json(output/'render.json',report)
    print('ASSET_RENDER_COMPLETE',options.unit,len(report['frames']),report['elapsedSeconds'],flush=True)
