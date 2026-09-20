"""Saved-rig sprite production. Run in an isolated Blender background process."""
import argparse
import hashlib
import json
import math
import sys
import time
from pathlib import Path

import bpy
from mathutils import Vector, Matrix
from bpy_extras.object_utils import world_to_camera_view

DIRECTIONS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']
REQUIRED = ['root', 'pelvis', 'spine_01', 'spine_02', 'spine_03', 'Head',
            'upperarm_l', 'lowerarm_l', 'hand_l', 'upperarm_r', 'lowerarm_r', 'hand_r',
            'thigh_l', 'calf_l', 'foot_l', 'thigh_r', 'calf_r', 'foot_r']


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, data):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(data, indent=2), encoding='utf8')


def sample_times(start, end, count, loop):
    if count < 1 or end < start:
        raise ValueError('Invalid sample interval')
    denominator = count if loop else max(1, count - 1)
    return [start + (end - start) * i / denominator for i in range(count)]


def set_frame(value):
    whole = math.floor(value)
    bpy.context.scene.frame_set(whole, subframe=value-whole)


def import_source(source):
    # Do not execute source text blocks or clear an interactive scene.
    if not bpy.app.background:
        raise RuntimeError('Production script requires isolated background Blender')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    with bpy.data.libraries.load(str(source), link=False) as (available, loaded):
        if 'Armature' not in available.objects:
            raise ValueError('Source requires the configured Armature object')
        loaded.objects = ['Armature']
        loaded.actions = list(available.actions)
        loaded.scenes = list(available.scenes)
    rig = loaded.objects[0]
    bpy.context.scene.collection.objects.link(rig)
    for action in loaded.actions:
        action.use_fake_user = True
    source_scene = loaded.scenes[0] if loaded.scenes else None
    rig['sourceFps'] = source_scene.render.fps if source_scene else 24
    rig['sourceFpsBase'] = source_scene.render.fps_base if source_scene else 1.0
    missing = [n for n in REQUIRED if n not in rig.data.bones]
    if missing:
        raise ValueError('Missing bones: '+', '.join(missing))
    if rig.animation_data:
        for track in rig.animation_data.nla_tracks:
            track.mute = True
    return rig


def inventory(source, rig):
    drivers = []
    for owner in [rig, rig.data]:
        if owner.animation_data:
            drivers.extend({'owner':owner.name, 'path':f.data_path, 'expression':f.driver.expression,
                            'type':f.driver.type} for f in owner.animation_data.drivers)
    return {'source':str(source), 'sourceHash':digest(source), 'blender':bpy.app.version_string,
            'armature':rig.name, 'bones':[b.name for b in rig.data.bones],
            'actions':[{'name':a.name, 'range':list(a.frame_range),
                        'slots':[s.identifier for s in a.slots]} for a in bpy.data.actions],
            'constraints':[{'bone':b.name, 'type':c.type, 'name':c.name}
                           for b in rig.pose.bones for c in b.constraints],
            'objectConstraints':[{'name':c.name,'type':c.type} for c in rig.constraints],
            'nlaTracks':[{'name':t.name,'muted':t.mute,'strips':[{'name':s.name,'action':s.action.name if s.action else None} for s in t.strips]}
                         for t in rig.animation_data.nla_tracks] if rig.animation_data else [],
            'drivers':drivers,
            'images':[{'name':i.name, 'filepath':i.filepath, 'packed':bool(i.packed_file)} for i in bpy.data.images],
            'texts':[t.name for t in bpy.data.texts], 'sourceFps':rig['sourceFps'], 'sourceFpsBase':rig['sourceFpsBase']}


def assign(rig, action):
    rig.animation_data_create()
    rig.animation_data.action = action
    slots = list(action.slots)
    slot = next((s for s in slots if s.identifier == 'OBArmature'), slots[0] if slots else None)
    if slot:
        rig.animation_data.action_slot = slot
    else:
        raise ValueError('Action has no compatible slot: '+action.name)


def reset_pose(rig):
    rig.location = (0, 0, 0)
    rig.rotation_euler = (0, 0, 0)
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)


def build_baked_actions(rig, recipe, model):
    """Capture evaluated source+corrections, then key editable derived actions."""
    captures = {}
    reports = {}
    for clip, spec in recipe['clips'].items():
        name = spec.get('action') or spec.get('sourceAction')
        if name not in bpy.data.actions:
            raise ValueError('Unknown source action: '+str(name))
        source_action = bpy.data.actions[name]
        interval = spec.get('range', list(source_action.frame_range))
        times = sample_times(*interval, spec['samples'], spec['loop'])
        poses = []
        roots = []
        headings = []
        foot_positions = []
        for index, source_time in enumerate(times):
            reset_pose(rig)
            assign(rig, source_action)
            set_frame(source_time)
            bpy.context.view_layer.update()
            roots.append(rig.pose.bones['root'].matrix.translation.copy())
            headings.append(rig.pose.bones['root'].matrix.to_quaternion().to_euler('XYZ').z)
            model.correct_pose(rig, recipe, clip, index/(len(times) if spec['loop'] else max(1,len(times)-1)))
            bpy.context.view_layer.update()
            deps = bpy.context.evaluated_depsgraph_get()
            evaluated = rig.evaluated_get(deps)
            poses.append({b.name:b.matrix.copy() for b in evaluated.pose.bones})
            foot_positions.append(evaluated.pose.bones['foot_l'].matrix.translation.copy())
        if clip == 'move':
            # Subtract only root planar translation; preserve vertical gait.
            base = roots[0]
            for pose, root, heading in zip(poses, roots, headings):
                shift = Matrix.Translation((base.x,base.y,0)) @ Matrix.Rotation(headings[0]-heading,4,'Z') @ Matrix.Translation((-root.x,-root.y,0))
                for bone in pose:
                    pose[bone] = shift @ pose[bone]
            root_xy=[pose['root'].translation for pose in poses]
            if any(math.hypot(p.x-root_xy[0].x,p.y-root_xy[0].y)>0.0001 for p in root_xy):
                raise ValueError('Baked locomotion retains planar root travel')
        captures[clip] = poses
        reports[clip] = {'sourceAction':name, 'sourceRange':interval, 'sourceSampleTimes':times,
                         'sourceDurationSeconds':(interval[1]-interval[0])/(rig['sourceFps']/rig['sourceFpsBase']),
                         'rootTravel':list(roots[-1]-roots[0]), 'sampleCount':len(times),
                         'footTravel':max(p.y for p in foot_positions)-min(p.y for p in foot_positions)}
    rig.animation_data_clear()
    for bone in rig.pose.bones:
        for constraint in list(bone.constraints):
            bone.constraints.remove(constraint)
    for constraint in list(rig.constraints):
        rig.constraints.remove(constraint)
    baked = {}
    # Bone list is parent-before-child in this supplied source.
    ordered = sorted(rig.pose.bones, key=lambda b:len(b.parent_recursive))
    for clip, poses in captures.items():
        rig.animation_data_clear()
        reset_pose(rig)
        for index, pose in enumerate(poses):
            bpy.context.scene.frame_set(index+1)
            for bone in ordered:
                bone.rotation_mode = 'QUATERNION'
                bone.matrix = pose[bone.name]
                bpy.context.view_layer.update()
                for prop in ['location', 'rotation_quaternion', 'scale']:
                    bone.keyframe_insert(data_path=prop, frame=index+1)
        action = rig.animation_data.action
        action.name = 'RTS_'+recipe['unitId']+'_'+clip
        action.use_fake_user = True
        baked[clip] = action
    return baked, reports


def setup_scene(rig, meshes, recipe):
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.color_depth = '8'
    scene.render.film_transparent = True
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    scene.render.fps = 24
    if hasattr(scene, 'eevee'):
        scene.eevee.taa_render_samples = 32
    world = bpy.data.worlds.new('RTSWorld')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.13,0.15,0.19,1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = .5
    scene.world = world
    root = bpy.data.objects.new('ExportRoot', None)
    scene.collection.objects.link(root)
    rig.parent = root
    # Known source is upright Z; scale uses rest head/feet rather than animated bounds.
    body_meshes = [o for o in meshes if any(n in o.name for n in ['Head','Boot','Helmet'])]
    rest_z = [v.co.z for o in body_meshes for v in o.data.vertices]
    height = (1 if recipe.get('sourceId') == 'procedural_aircraft_v1' else
              max(rest_z)-min(rest_z) if rest_z else rig.data.bones['Head'].tail_local.z)
    root.scale = (float(recipe.get('scale',1.0))/height,)*3
    for name, pos, energy, size in [('Key',(-3,-4,7),500,5),('Fill',(4,-1,4),200,4)]:
        data = bpy.data.lights.new(name, 'AREA'); data.energy=energy;data.shape='DISK';data.size=size
        obj = bpy.data.objects.new(name,data);scene.collection.objects.link(obj);obj.location=pos
        obj.rotation_euler = (Vector((0,0,.5))-obj.location).to_track_quat('-Z','Y').to_euler()
    data = bpy.data.cameras.new('RTSCamera');camera=bpy.data.objects.new('RTSCamera',data)
    scene.collection.objects.link(camera);data.type='ORTHO';scene.camera=camera
    return scene, root, camera


def configure_camera(scene, camera, size):
    up = Vector((0,math.sin(math.pi/3),math.cos(math.pi/3)))
    camera.location = Vector((0,-6,6*math.tan(math.pi/3))) + up*(8/64)
    camera.rotation_euler = Vector((0,6,-6*math.tan(math.pi/3))).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale = size/64
    scene.render.resolution_x = scene.render.resolution_y = size*2
    bpy.context.view_layer.update()


def bounds(scene, camera, meshes, size):
    deps=bpy.context.evaluated_depsgraph_get()
    xs=[];ys=[];zs=[]
    for obj in meshes:
        evaluated=obj.evaluated_get(deps)
        evaluated_mesh = evaluated.to_mesh()
        for vertex in evaluated_mesh.vertices:
            point=evaluated.matrix_world @ vertex.co
            projected=world_to_camera_view(scene,camera,point)
            xs.append(projected.x*size);ys.append((1-projected.y)*size);zs.append(point.z)
        evaluated.to_mesh_clear()
    return [min(xs),min(ys),max(xs),max(ys),min(zs)]


def mask_material(team):
    mat=bpy.data.materials.new('TeamCoverage' if team else 'OccluderCoverage');mat.use_nodes=True
    nodes=mat.node_tree.nodes;nodes.clear();out=nodes.new('ShaderNodeOutputMaterial');em=nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value=(1,1,1,1) if team else (0,0,0,1)
    mat.node_tree.links.new(em.outputs[0],out.inputs['Surface'])
    return mat


def run(options):
    if options.unit in ('command_blimp', 'battleship'):
        sys.path.insert(0,str(Path(options.root)/'tools/blender'))
        import aircraft_export
        return aircraft_export.run(options)
    if options.unit == 'mouse_builder':
        sys.path.insert(0,str(Path(options.root)/'tools/blender'))
        import woodland_export
        return woodland_export.run(options)
    start=time.monotonic();output=Path(options.output).resolve();output.mkdir(parents=True,exist_ok=True)
    source=Path(options.source).resolve();rig=import_source(source)
    info=inventory(source,rig);write_json(output/'inventory.json',info)
    if options.mode == 'inspect':
        print('ASSET_INSPECT_COMPLETE',len(info['actions']),len(info['bones']),flush=True);return
    if info['drivers']:
        raise ValueError('Source contains drivers requiring a recorded adapter before batch evaluation')
    rootpath=Path(options.root).resolve()
    sys.path.insert(0,str(rootpath/'tools'/'blender'))
    import unit_model
    recipe=json.loads((rootpath/'art'/'recipes'/(options.unit+'.json')).read_text(encoding='utf-8-sig'))
    if recipe['unitId'] != options.unit:
        raise ValueError('Recipe identity mismatch')
    if recipe.get('sourceHash') != info['sourceHash']:
        raise ValueError('Saved source differs from recipe pin; deliberately refresh recipe/source manifest')
    if recipe.get('rig') != rig.name:
        raise ValueError('Recipe rig does not match the saved source')
    for clip,spec in recipe['clips'].items():
        action=bpy.data.actions.get(spec.get('action',''))
        if action is None or recipe.get('slot') not in [slot.identifier for slot in action.slots]:
            raise ValueError('Missing source action or configured slot for '+clip)
        if not isinstance(spec.get('samples'),int) or spec['samples']<1:
            raise ValueError('Invalid sample count for '+clip)
        if not isinstance(spec.get('durationMs'),int) or spec['durationMs']<1:
            raise ValueError('Invalid presentation duration for '+clip)
    meshes=unit_model.build_unit(rig,recipe)
    if isinstance(meshes,dict):meshes=meshes['meshes']
    baked,animation_report=build_baked_actions(rig,recipe,unit_model)
    scene,root,camera=setup_scene(rig,meshes,recipe)
    pose_bounds=[]
    for size in [64,96,128]:
        configure_camera(scene,camera,size);pose_bounds=[]
        for clip,spec in recipe['clips'].items():
            assign(rig,baked[clip])
            for di,direction in enumerate(DIRECTIONS):
                root.rotation_euler.z=math.pi-di*math.pi/4
                for sample in range(spec['samples']):
                    set_frame(sample+1);bpy.context.view_layer.update()
                    b=bounds(scene,camera,meshes,size)
                    pose_bounds.append({'clip':clip,'direction':direction,'sample':sample+1,'bounds':b})
        if all(b['bounds'][0]>=2 and b['bounds'][1]>=2 and b['bounds'][2]<=size-2 and b['bounds'][3]<=size-2 for b in pose_bounds):break
    else:
        write_json(output/'bounds-failure.json',pose_bounds)
        bpy.ops.wm.save_as_mainfile(filepath=str(output/'bounds-failure.blend'))
        raise ValueError('Animation exceeds maximum128pxcell; inspect bounds-failure.json')
    normal_materials={o.name:list(o.data.materials) for o in meshes}
    masks={True:mask_material(True),False:mask_material(False)}
    clips={k:{'durationMs':v['durationMs'],'loop':v['loop'],'samples':1 if options.preview else v['samples'],
              **({'contactFrame':1 if options.preview else v['contactFrame']} if 'contactFrame' in v else {})}
           for k,v in recipe['clips'].items()}
    report={'version':2,'unitId':options.unit,'profileId':recipe.get('profileId','bastion_overhead_v1'),
            'cellSize':size,'anchorX':size/2,'anchorY':size/2+8,'bodyHeightPixels':32*recipe.get('scale',1),
            'directions':DIRECTIONS,'clips':clips,'frames':[], 'sourceHash':info['sourceHash'],
            'sourceFps':info['sourceFps'],'renderScale':2,'preview':options.preview,'animation':animation_report,
            'boneCount':len(rig.data.bones),'fingerGeometry':False,'bounds':pose_bounds,
            'renderSettings':{'engine':scene.render.engine,'samples':32,'elevation':60,'pixelsPerUnit':64,'colorTransform':'Standard','exposure':0,'gamma':1}}
    finger_groups=[g.name for obj in meshes for g in obj.vertex_groups if any(n in g.name for n in ['thumb','index','middle','ring','pinky'])]
    if finger_groups:
        raise ValueError('Generated unit unexpectedly has finger weights')
    report['meshValidation']={'objects':len(meshes),'triangles':sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons),
                              'fingerGroups':finger_groups,'stumps':[o.name for o in meshes if 'Stump' in o.name]}
    move=animation_report['move']
    stride=max(math.hypot(*move['rootTravel'][:2]),move['footTravel']*2)*root.scale.x*64/26
    report['referenceStride']={'distance':max(.1,stride),'units':'navigationCells'}
    report['grips'] = []
    for clip,spec in recipe['clips'].items():
        assign(rig,baked[clip])
        for sample in range(spec['samples']):
            set_frame(sample+1)
            grip=unit_model.grip_report(rig)
            report['grips'].append({'clip':clip,'sample':sample+1,**grip})
            if options.unit == 'crossbow' and clip != 'death' and grip.get('supportGripError',0) > .015:
                raise ValueError('Baked crossbow grip separates from stock')
    total=sum(c['samples'] for c in clips.values())*8
    for clip,spec in clips.items():
        assign(rig,baked[clip])
        for di,direction in enumerate(DIRECTIONS):
            root.rotation_euler.z=math.pi-di*math.pi/4
            for sample in range(spec['samples']):
                set_frame(sample+1);bpy.context.view_layer.update()
                entry={'clip':clip,'direction':direction,'sample':sample+1}
                for channel in ['color','mask']:
                    for obj in meshes:
                        for index,mat in enumerate(normal_materials[obj.name]):
                            obj.data.materials[index]=mat if channel=='color' else masks[bool(mat.get('team',False))]
                    relative=Path('raw')/clip/direction/(f'{sample+1:03d}-{channel}.png')
                    (output/relative).parent.mkdir(parents=True,exist_ok=True)
                    scene.render.filepath=str(output/relative)
                    bpy.ops.render.render(write_still=True)
                    entry[channel]=relative.as_posix()
                report['frames'].append(entry)
                print('ASSET_POSE',options.unit,len(report['frames']),total,flush=True)
    for obj in meshes:
        for i,mat in enumerate(normal_materials[obj.name]):obj.data.materials[i]=mat
    assign(rig,baked['idle']);root.rotation_euler.z=math.pi;set_frame(1)
    scene.frame_start=1;scene.frame_end=recipe['clips']['idle']['samples']
    bpy.ops.wm.save_as_mainfile(filepath=str(output/(options.unit+'.blend')))
    report['elapsedSeconds']=time.monotonic()-start
    write_json(output/'render.json',report)
    print('ASSET_RENDER_COMPLETE',options.unit,len(report['frames']),round(report['elapsedSeconds'],2),flush=True)


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--root',required=True);parser.add_argument('--source',required=True)
    parser.add_argument('--unit',default='shieldguard');parser.add_argument('--output',required=True)
    parser.add_argument('--mode',choices=['inspect','render'],default='render');parser.add_argument('--preview',action='store_true')
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    run(parser.parse_args(args))
