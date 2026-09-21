"""Orders fixed-view buildings; all four stages share one footprint and canvas."""
import json
import time
from pathlib import Path
import bpy
import orders_building_model as model
from pipeline import DIRECTIONS, bounds, configure_camera, digest, mask_material, setup_scene, set_frame, write_json


def run(options):
    if not bpy.app.background:raise RuntimeError('Use isolated background Blender')
    started=time.monotonic();rootpath=Path(options.root);output=Path(options.output);output.mkdir(parents=True,exist_ok=True)
    path=rootpath/'art/recipes'/f'{options.unit}.json';recipe=json.loads(path.read_text(encoding='utf8'))
    assert recipe['unitId']==options.unit and recipe['sourceId']=='procedural_buildings_v1'
    assert recipe['footprintCells'] in (2,3,4)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    assembly,meshes=model.build(recipe)
    scene,root,camera=setup_scene(assembly,meshes,dict(recipe,referenceHeight=1))
    for size in (64,96,128,192,256):
        configure_camera(scene,camera,size);poses=[]
        for stage in range(1,5):
            set_frame(stage);bpy.context.view_layer.update()
            visible=[o for o in meshes if not o.hide_render]
            coords=[o.matrix_world@v.co for o in visible for v in o.data.vertices]
            half=recipe['footprintCells']*26/128
            if any(abs(p.x)>half+.0001 or abs(p.y)>half+.0001 or p.z<-.0001 for p in coords):
                raise ValueError('Orders building exceeds footprint/floor')
            poses.append({'stage':stage,'bounds':bounds(scene,camera,visible,size)})
        if all(min(p['bounds'][:2])>=2 and max(p['bounds'][2:])<=size-2 for p in poses):break
    else:raise ValueError('Orders building exceeds canvas')
    normal={o.name:list(o.data.materials) for o in meshes};masks={True:mask_material(True),False:mask_material(False)}
    report={'version':2,'unitId':options.unit,'profileId':'building_overhead_v1','fixedFacing':'S',
            'footprintCells':recipe['footprintCells'],'cellSize':size,'anchorX':size/2,'anchorY':size/2+8,
            'bodyHeightPixels':32,'directions':DIRECTIONS,'clips':recipe['clips'],'frames':[],
            'renderScale':2,'preview':options.preview,'sourceHash':digest(path),'bounds':poses,
            'meshValidation':{'objects':len(meshes),'triangles':sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons),
                              'constructionStages':3,'fixedFootprint':True},
            'renderSettings':{'engine':scene.render.engine,'samples':32,'elevation':60,'pixelsPerUnit':64,'colorTransform':'Standard','exposure':0,'gamma':1}}
    write_json(output/'inventory.json',dict(report['meshValidation'],blender=bpy.app.version_string,source='Original cathedral modules'))
    if options.mode!='inspect':
        for clip,spec in recipe['clips'].items():
            for sample in range(spec['samples']):
                set_frame(4 if clip=='idle' else sample+1)
                entry={'clip':clip,'direction':'S','sample':sample+1}
                for channel in ('color','mask'):
                    for ob in meshes:
                        for i,mat in enumerate(normal[ob.name]):ob.data.materials[i]=mat if channel=='color' else masks[bool(mat.get('team',False))]
                    rel=Path('raw')/clip/'S'/f'{sample+1:03d}-{channel}.png';(output/rel).parent.mkdir(parents=True,exist_ok=True)
                    scene.render.filepath=str(output/rel);bpy.ops.render.render(write_still=True);entry[channel]=rel.as_posix()
                report['frames'].append(entry)
    for ob in meshes:
        for i,mat in enumerate(normal[ob.name]):ob.data.materials[i]=mat
    set_frame(4);scene.frame_start=1;scene.frame_end=4
    bpy.ops.wm.save_as_mainfile(filepath=str(output/(options.unit+'.blend')))
    report['elapsedSeconds']=round(time.monotonic()-started,2);write_json(output/'render.json',report)
    print('ASSET_RENDER_COMPLETE',options.unit,len(report['frames']),flush=True)
