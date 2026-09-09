"""Owned background-scene recipe: python scripts/export-assets.ps1 launches this file."""
import bpy
import math
import json
import sys
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
import numpy as np

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
root = Path(args[0]).resolve()
output = root / "assets" / "generated"
proof = root / "artifacts" / "sprite-source"
output.mkdir(parents=True, exist_ok=True)
proof.mkdir(parents=True, exist_ok=True)
# This script is only launched with --factory-startup in a new background process.
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x = scene.render.resolution_y = 128
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.film_transparent = True
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.display.shading.cavity_type = "BOTH"
scene.view_settings.view_transform = "Standard"
scene.render.fps = 8

def material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    return mat
team = material("Team cloth", (0.68, 0.68, 0.68))
skin = material("Skin", (0.7, 0.46, 0.25))
metal = material("Steel", (0.32, 0.38, 0.42))
leather = material("Leather", (0.12, 0.07, 0.035))
blade = material("Blade", (0.66, 0.73, 0.73))
bpy.ops.object.armature_add()
rig = bpy.context.object
rig.name = "ShieldguardRig"
bpy.ops.object.mode_set(mode="EDIT")
for bone in list(rig.data.edit_bones):
    rig.data.edit_bones.remove(bone)
specs = {
    "root": ((0,0,0), (0,0,0.25), None),
    "torso": ((0,0,0.72), (0,0,1.25), "root"),
    "head": ((0,0,1.25), (0,0,1.7), "torso"),
    "armL": ((-0.38,0,1.22), (-0.38,0,0.62), "torso"),
    "armR": ((0.38,0,1.22), (0.38,0,0.62), "torso"),
    "legL": ((-0.16,0,0.72), (-0.16,0,0.08), "root"),
    "legR": ((0.16,0,0.72), (0.16,0,0.08), "root")
}
for name, (head, tail, parent) in specs.items():
    bone = rig.data.edit_bones.new(name)
    bone.head, bone.tail = head, tail
    if parent:
        bone.parent = rig.data.edit_bones[parent]
bpy.ops.object.mode_set(mode="OBJECT")
parts = []
def mesh(name, location, scale, mat, bone, shape="cube"):
    if shape == "sphere":
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=location)
    else:
        bpy.ops.mesh.primitive_cube_add(size=2, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.materials.append(mat)
    obj.color = (1,1,1,1) if mat == team else (0,0,0,1)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1, "REPLACE")
    modifier = obj.modifiers.new("Rig", "ARMATURE")
    modifier.object = rig
    obj.parent = rig
    parts.append(obj)
    return obj
mesh("Tunic",(0,0,1.03),(.3,.18,.33),team,"torso","sphere")
mesh("Head",(0,-.015,1.55),(.25,.22,.25),skin,"head","sphere")
mesh("Helmet",(0,.025,1.72),(.26,.22,.1),metal,"head","sphere")
mesh("Belt",(0,0,.79),(.29,.19,.065),leather,"torso")
for side, x in [("L",-.17),("R",.17)]:
    mesh("Leg"+side,(x,0,.43),(.12,.13,.32),leather,"leg"+side)
    mesh("Boot"+side,(x,-.09,.1),(.14,.23,.10),metal,"leg"+side)
for side,x in [("L",-.4),("R",.4)]:
    mesh("Arm"+side,(x,0,.95),(.13,.14,.27),team,"arm"+side,"sphere")
    mesh("Hand"+side,(x,-.025,.69),(.13,.13,.13),skin,"arm"+side,"sphere")
mesh("Shield",(-.47,-.19,.95),(.23,.055,.34),team,"armL","sphere")
mesh("ShieldBoss",(-.47,-.25,.95),(.075,.035,.075),metal,"armL","sphere")
mesh("SwordGrip",(.40,-.04,.62),(.04,.045,.16),leather,"armR")
mesh("SwordBlade",(.40,-.04,.22),(.065,.025,.3),blade,"armR")

bpy.ops.object.camera_add(location=(0,-6,5))
camera = bpy.context.object
camera.rotation_euler = (Vector((0,0,.85))-camera.location).to_track_quat("-Z","Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 3.35
scene.camera = camera
actions = {}
for clip in ("idle","move","attack","death"):
    rig.animation_data_clear()
    for frame in range(1,5):
        phase = (frame-1)/4 * math.tau
        for bone in rig.pose.bones:
            bone.rotation_mode = "XYZ"
            bone.rotation_euler = (0,0,0)
            bone.location = (0,0,0)
        if clip == "idle":
            rig.pose.bones["torso"].rotation_euler.x = .025 * math.sin(phase)
        elif clip == "move":
            for bone, sign in (("legL",1),("legR",-1),("armL",-1),("armR",1)):
                rig.pose.bones[bone].rotation_euler.x = .38 * math.sin(phase) * sign
        elif clip == "attack":
            rig.pose.bones["armR"].rotation_euler.x = [0,-1.2,0.7,0][frame-1]
            rig.pose.bones["torso"].rotation_euler.z = [0,-.2,.2,0][frame-1]
        else:
            t=(frame-1)/3
            rig.pose.bones["root"].rotation_euler.x = -t*math.pi/2
            rig.pose.bones["root"].location.z = .18*t
        for bone in rig.pose.bones:
            bone.keyframe_insert(data_path="rotation_euler",frame=frame)
            bone.keyframe_insert(data_path="location",frame=frame)
    action=rig.animation_data.action
    action.name=clip
    action.use_fake_user=True
    actions[clip]=(action, rig.animation_data.action_slot)
rig.animation_data.action, rig.animation_data.action_slot=actions["idle"]
scene.frame_set(1)
scene.frame_start,scene.frame_end=1,4
bpy.ops.wm.save_as_mainfile(filepath=str(proof/"shieldguard.blend"))

width,height=1024,2048
atlases={name:np.zeros((height,width,4),dtype=np.float32) for name in ("color","mask")}
metadata={"version":1,"frameSize":128,"columns":8,"framesPerClip":4,"directions":8,"clips":["idle","move","attack","death"],"fps":8,
          "atlas":"assets/generated/shieldguard.png","mask":"assets/generated/shieldguard-mask.png"}
anchor=world_to_camera_view(scene,camera,Vector((0,0,0)))
metadata["anchorX"]=round(anchor.x*128)
metadata["anchorY"]=round((1-anchor.y)*128)
buffer=np.empty(128*128*4,dtype=np.float32)
for clip_index,clip in enumerate(metadata["clips"]):
    rig.animation_data.action,rig.animation_data.action_slot=actions[clip]
    for direction in range(8):
        rig.rotation_euler.z = -direction*math.pi/4
        for frame in range(1,5):
            scene.frame_set(frame)
            index=clip_index*32+direction*4+frame-1
            x,y=(index%8)*128,(index//8)*128
            for channel in ("color","mask"):
                shading=scene.display.shading
                shading.light="STUDIO" if channel=="color" else "FLAT"
                shading.color_type="MATERIAL" if channel=="color" else "OBJECT"
                shading.show_shadows=channel=="color"
                shading.show_cavity=channel=="color"
                path=proof/("frame-"+channel+".png")
                scene.render.filepath=str(path)
                bpy.ops.render.render(write_still=True)
                image=bpy.data.images.load(str(path),check_existing=False)
                image.pixels.foreach_get(buffer)
                atlases[channel][height-y-128:height-y,x:x+128,:]=buffer.reshape((128,128,4))
                bpy.data.images.remove(image)
for channel,data in atlases.items():
    image=bpy.data.images.new("Atlas-"+channel,width=width,height=height,alpha=True)
    image.pixels.foreach_set(data.ravel())
    image.filepath_raw=str(output/("shieldguard.png" if channel=="color" else "shieldguard-mask.png"))
    image.file_format="PNG"
    image.save()
(output/"shieldguard.json").write_text(json.dumps(metadata,indent=2),encoding="utf8")
(output/"shieldguard.lua").write_text("return {version=1, frameSize=128, columns=8, framesPerClip=4, directions=8, fps=8, anchorX="+str(metadata["anchorX"])+", anchorY="+str(metadata["anchorY"])+"}\n",encoding="utf8")
(proof/"report.json").write_text(json.dumps({"blender":bpy.app.version_string,"frames":128,"directions":8,"clips":metadata["clips"],"anchor":[metadata["anchorX"],metadata["anchorY"]],"maskAligned":True},indent=2))
print("LOVE_RTS_EXPORT_COMPLETE",str(output))
