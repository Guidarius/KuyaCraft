"""Blender console helper for synchronized derived clips, at metadata playback speed.
Example: runpy.run_path('D:/LoveRTS/.../scripts/select-orders-clip.py')['select']('gryphon','move')
Only touches animation assignments in the open derived scene, never the source file.
"""
import json
from pathlib import Path
import bpy

def select(unit,clip):
    root=Path(__file__).resolve().parents[1]
    recipe=json.loads((root/'art/recipes'/f'{unit}.json').read_text(encoding='utf8'))
    spec=recipe['clips'][clip]
    assert bpy.data.objects.get('ExportRoot'),'Open a derived export scene first'
    scene=bpy.context.scene
    if unit in ('keep','depot','barracks','sanctum'):
        scene.frame_start=4 if clip=='idle' else 1
        scene.frame_end=4 if clip=='idle' else 3
        scene.render.fps=1;scene.render.fps_base=1
    else:
        matched=0
        for ob in scene.objects:
            action=bpy.data.actions.get(f'RTS_{unit}_{clip}_{ob.name}')
            if not action and ob.name=='Armature':action=bpy.data.actions.get(f'RTS_{unit}_{clip}')
            if action:
                ob.animation_data_create();ob.animation_data.action=action
                ob.animation_data.action_slot=action.slots[0];matched+=1
        assert matched,'No matching derived actions in this scene'
        scene.frame_start=1;scene.frame_end=spec['samples']
        scene.render.fps=spec['samples']*1000;scene.render.fps_base=spec['durationMs']
    scene.frame_set(scene.frame_start)
    print('Selected',unit,clip,'at',spec['durationMs'],'ms per clip')
