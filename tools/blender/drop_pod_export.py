"""Fixed-view sprite prop using the production camera, editable door keys and team masks."""
import json
import time
from pathlib import Path
import bpy
import drop_pod_model
from pipeline import DIRECTIONS, bounds, configure_camera, digest, mask_material, setup_scene, set_frame, write_json


def run(options):
    if not bpy.app.background:raise RuntimeError('Drop pod export requires isolated background Blender')
    started=time.monotonic();rootpath=Path(options.root);output=Path(options.output);output.mkdir(parents=True,exist_ok=True)
    path=rootpath/'art/recipes/drop_pod.json';recipe=json.loads(path.read_text())
    assert recipe['unitId']=='drop_pod' and recipe['sourceId']=='procedural_drop_pod_v1'
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    assembly,meshes,doors=drop_pod_model.build(recipe)
    scene,root,camera=setup_scene(assembly,meshes,dict(recipe,sourceId='procedural_buildings_v1',referenceHeight=1))
    poses=[]
    for size in (64,96,128):
        configure_camera(scene,camera,size);poses=[]
        for clip,spec in recipe['clips'].items():
            for sample in range(spec['samples']):
                set_frame(sample+1);bpy.context.view_layer.update()
                pose=bounds(scene,camera,meshes,size)
                assert pose[4]>=-.0001,'Drop pod crosses ground'
                poses.append(dict(clip=clip,direction='S',sample=sample+1,bounds=pose))
        if all(min(p['bounds'][:2])>=2 and max(p['bounds'][2:4])<=size-2 for p in poses):break
    else:raise ValueError('Drop pod exceeds 128px canvas')
    normal={ob.name:list(ob.data.materials) for ob in meshes};masks={True:mask_material(True),False:mask_material(False)}
    clips={name:dict(spec,samples=1 if options.preview else spec['samples']) for name,spec in recipe['clips'].items()}
    report=dict(version=2,unitId='drop_pod',profileId='prop_overhead_v1',fixedFacing='S',cellSize=size,
                anchorX=size/2,anchorY=size/2+8,bodyHeightPixels=32,directions=DIRECTIONS,clips=clips,
                frames=[],renderScale=2,preview=options.preview,sourceHash=digest(path),bounds=poses,
                meshValidation={'objects':len(meshes),'triangles':sum(len(p.vertices)-2 for ob in meshes for p in ob.data.polygons),
                                'rigidJoints':[ob.name for ob,_ in doors]},
                renderSettings={'engine':scene.render.engine,'samples':32,'elevation':60,'pixelsPerUnit':64,
                                'colorTransform':'Standard','exposure':0,'gamma':1})
    write_json(output/'inventory.json',dict(report['meshValidation'],blender=bpy.app.version_string))
    if options.mode!='inspect':
        for clip,spec in clips.items():
            for sample in range(spec['samples']):
                set_frame(sample+1);entry=dict(clip=clip,direction='S',sample=sample+1)
                for channel in ('color','mask'):
                    for ob in meshes:
                        for i,mat in enumerate(normal[ob.name]):ob.data.materials[i]=mat if channel=='color' else masks[bool(mat.get('team',False))]
                    relative=Path('raw')/clip/'S'/f'{sample+1:03d}-{channel}.png';(output/relative).parent.mkdir(parents=True,exist_ok=True)
                    scene.render.filepath=str(output/relative);bpy.ops.render.render(write_still=True);entry[channel]=relative.as_posix()
                report['frames'].append(entry)
    for ob in meshes:
        for i,mat in enumerate(normal[ob.name]):ob.data.materials[i]=mat
    set_frame(1);scene.frame_start=1;scene.frame_end=recipe['clips']['deploy']['samples']
    bpy.ops.wm.save_as_mainfile(filepath=str(output/'drop_pod.blend'))
    report['elapsedSeconds']=round(time.monotonic()-started,2);write_json(output/'render.json',report)
    print('ASSET_RENDER_COMPLETE drop_pod',len(report['frames']),report['elapsedSeconds'],flush=True)
