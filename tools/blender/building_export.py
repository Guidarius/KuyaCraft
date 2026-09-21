"""Fixed-facing, footprint-aligned building sprites using the production passes."""
import json
import math
import time
from pathlib import Path
import bpy
from mathutils import Vector
import building_model as model
from pipeline import DIRECTIONS, bounds, configure_camera, digest, mask_material, setup_scene, set_frame, write_json


def run(options):
    if not bpy.app.background: raise RuntimeError('Buildings require isolated background Blender')
    started=time.monotonic();rootpath=Path(options.root);output=Path(options.output)
    output.mkdir(parents=True,exist_ok=True)
    path=rootpath/'art/recipes'/f'{options.unit}.json';recipe=json.loads(path.read_text())
    if recipe['unitId']!=options.unit or recipe['sourceId']!='procedural_buildings_v1':
        raise ValueError('Building recipe identity mismatch')
    if type(recipe['footprintCells']) is not int or not 1<=recipe['footprintCells']<=4:
        raise ValueError('Invalid building footprint')
    spec=recipe['clips']['idle']
    if type(spec['samples']) is not int or not 1<=spec['samples']<=8 or not spec['loop']:
        raise ValueError('Invalid building idle cycle')
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    assembly,meshes,moving=model.build(recipe)
    scene,root,camera=setup_scene(assembly,meshes,dict(recipe,referenceHeight=1))
    poses=[]
    for size in (64,96,128,192,256):
        configure_camera(scene,camera,size);poses=[]
        for sample in range(spec['samples']):
            set_frame(sample+1);bpy.context.view_layer.update()
            coords=[ob.matrix_world@v.co for ob in meshes for v in ob.data.vertices]
            half=recipe['footprintCells']*26/128
            if any(abs(v.x)>half+.0001 or abs(v.y)>half+.0001 or v.z<-.0001 for v in coords):
                raise ValueError('Building geometry exceeds its declared footprint or floor')
            poses.append({'clip':'idle','direction':'S','sample':sample+1,'bounds':bounds(scene,camera,meshes,size)})
        if all(min(p['bounds'][:2])>=2 and max(p['bounds'][2:4])<=size-2 for p in poses):break
    else: raise ValueError('Building exceeds 256px canvas')
    set_frame(1);scene.frame_start=1;scene.frame_end=spec['samples']
    normal={o.name:list(o.data.materials) for o in meshes};masks={True:mask_material(True),False:mask_material(False)}
    report={'version':2,'unitId':options.unit,'profileId':'building_overhead_v1','fixedFacing':'S',
            'footprintCells':recipe['footprintCells'],'cellSize':size,'anchorX':size/2,'anchorY':size/2+8,
            'bodyHeightPixels':32,'directions':DIRECTIONS,'clips':{'idle':dict(spec,samples=1 if options.preview else spec['samples'])},
            'frames':[],'renderScale':2,'preview':options.preview,'sourceHash':digest(path),'bounds':poses,
            'meshValidation':{'objects':len(meshes),'triangles':sum(len(p.vertices)-2 for ob in meshes for p in ob.data.polygons),
                              'rigidJoints':[ob.name for ob,_ in moving]},
            'renderSettings':{'engine':scene.render.engine,'samples':32,'elevation':60,'pixelsPerUnit':64,
                              'colorTransform':'Standard','exposure':0,'gamma':1}}
    write_json(output/'inventory.json',dict(report['meshValidation'],source='Original procedural building modules',blender=bpy.app.version_string))
    # The asset viewer's canonical directions alias these same fixed frames during packing.
    if options.mode!='inspect':
        for sample in range(report['clips']['idle']['samples']):
            set_frame(sample+1);entry={'clip':'idle','direction':'S','sample':sample+1}
            for channel in ('color','mask'):
                for ob in meshes:
                    for i,mat in enumerate(normal[ob.name]):ob.data.materials[i]=mat if channel=='color' else masks[bool(mat.get('team',False))]
                relative=Path('raw')/'idle'/'S'/f'{sample+1:03d}-{channel}.png'
                (output/relative).parent.mkdir(parents=True,exist_ok=True)
                scene.render.filepath=str(output/relative);bpy.ops.render.render(write_still=True);entry[channel]=relative.as_posix()
            report['frames'].append(entry)
    for ob in meshes:
        for i,mat in enumerate(normal[ob.name]):ob.data.materials[i]=mat
    set_frame(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(output/(options.unit+'.blend')))
    report['elapsedSeconds']=round(time.monotonic()-started,2);write_json(output/'render.json',report)
    print('ASSET_RENDER_COMPLETE',options.unit,len(report['frames']),report['elapsedSeconds'],flush=True)
