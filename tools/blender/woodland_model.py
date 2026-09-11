"""Original mouse volumes and a proportion-fitted copy of the source skeleton."""
import math
import bpy
from mathutils import Vector, Matrix
from unit_model import Builder, material, PALM, _solve_arm, _aim_bone

def fit_point(p):
    # Short legs, compact torso; preserve joint hierarchy and bone rolls.
    return Vector((p.x*.87,p.y*.8,p.z*.52 if p.z<1 else .52+(p.z-1)*.85))

def derive(source):
    rig=source.copy();rig.data=source.data.copy();rig.name='MouseRig'
    bpy.context.scene.collection.objects.link(rig);rig.animation_data_clear()
    bpy.context.view_layer.objects.active=rig;rig.select_set(True);source.select_set(False)
    bpy.ops.object.mode_set(mode='EDIT')
    for bone in rig.data.edit_bones:
        bone.use_connect=False
        bone.head=fit_point(bone.head);bone.tail=fit_point(bone.tail)
    bpy.ops.object.mode_set(mode='OBJECT')
    for bone in rig.pose.bones:
        for c in list(bone.constraints):bone.constraints.remove(c)
    rig['derivedFrom']=source.name;rig['proportionProfile']='mouse_short_legs_v1'
    return rig

def build(rig):
    b=Builder(rig)
    m={k:material('Mouse_'+k,c,t) for k,c,t in [
        ('fur',(.59,.36,.18),False),('muzzle',(.83,.62,.36),False),('ear',(.63,.30,.25),False),
        ('cloth',(.23,.32,.12),False),('team',(.52,.52,.52),True),
        ('wood',(.34,.19,.085),False),('leather',(.20,.11,.055),False),('dark',(.016,.020,.017),False)]}
    h=rig.data.bones['Head'].head_local
    # Crown excludes ears. Broad head and cheeks are deliberately unlike human geometry.
    b.ellipsoid('HeadCrown',h+Vector((0,-.03,.19)),(.255,.22,.27),'Head',m['fur'])
    b.ellipsoid('Muzzle',h+Vector((0,-.225,.095)),(.18,.13,.125),'Head',m['muzzle'])
    b.ellipsoid('Nose',h+Vector((0,-.344,.11)),(.045,.033,.034),'Head',m['dark'])
    for sign in [-1,1]:
        center=h+Vector((sign*.24,.015,.40))
        tilt=Matrix.Translation(center) @ Matrix.Rotation(-.65,4,'X') @ Matrix.Translation(-center)
        b.ellipsoid('EarOuter'+str(sign),center,(.19,.068,.235),'Head',m['fur'],tilt)
        b.ellipsoid('EarInner'+str(sign),center+Vector((0,-.060,0)),(.142,.027,.18),'Head',m['ear'],tilt)
        b.ellipsoid('Eye'+str(sign),h+Vector((sign*.105,-.223,.225)),(.030,.025,.043),'Head',m['dark'])
    b.ellipsoid('Tunic',(0,0,.68),(.23,.155,.235),'spine_02',m['cloth'])
    b.ellipsoid('Pelvis',(0,0,.46),(.19,.135,.11),'pelvis',m['cloth'])
    b.box('Belt',(0,-.01,.52),(.40,.29,.055),'spine_01',m['leather'])
    b.box('Pouch',(-.18,-.15,.45),(.12,.075,.15),'pelvis',m['leather'])
    for side in ['_l','_r']:
        for part,radius,mat in [('thigh',.095,'cloth'),('calf',.085,'fur'),('upperarm',.082,'cloth'),('lowerarm',.065,'fur')]:
            bone=rig.data.bones[part+side]
            b.capsule(part+side,bone.head_local,bone.tail_local,radius,part+side,m[mat])
        foot=rig.data.bones['foot'+side].head_local
        b.ellipsoid('Boot'+side,foot+Vector((0,-.065,-.016)),(.095,.16,.072),'foot'+side,m['muzzle'])
        b.ellipsoid('PalmStump'+side,PALM,(.060,.080,.060),'hand'+side,m['fur'],rig.data.bones['hand'+side].matrix_local)
    # Full shoulder wrap is visible from front/back; no skin receives team color.
    shoulder=rig.data.bones['upperarm_l'].head_local
    b.ellipsoid('TeamShoulder',shoulder,(.14,.18,.105),'upperarm_l',m['team'])
    right=rig.data.bones['hand_r'].matrix_local
    b.box('MalletHandle',PALM+Vector((.12,0,0)),(.50,.045,.045),'hand_r',m['wood'],right)
    b.ellipsoid('MalletHead',PALM+Vector((.34,0,0)),(.13,.19,.13),'hand_r',m['wood'],right)
    points=[(0,.12,.43),(.12,.29,.32),(.30,.42,.28),(.42,.43,.42),(.46,.41,.57)]
    for i in range(len(points)-1):b.capsule('Tail'+str(i),points[i],points[i+1],.042-i*.006,'pelvis',m['ear'],sides=6)
    return b.objects

def pose(source,rig,clip,phase):
    # Transfer source-local animation deltas onto different rest lengths; no source edits.
    for b in rig.pose.bones:
        origin=source.pose.bones[b.name]
        b.rotation_mode='QUATERNION';b.rotation_quaternion=origin.matrix_basis.to_quaternion()
        b.location=origin.location*.52;b.scale=(1,1,1)
    bpy.context.view_layer.update()
    # Motion root stays in place. Hands carry the mallet beside, not through, the face.
    rig.pose.bones['root'].location.x=0;rig.pose.bones['root'].location.y=0
    for side,sign in [('_l',1),('_r',-1)]:
        t=phase*2*math.pi+(0 if sign==1 else math.pi)
        foot=Vector((sign*.105,-.035+(.13*math.cos(t) if clip=='move' else 0),.075+(.095*max(0,math.sin(t)) if clip=='move' else 0)))
        upper,lower='thigh'+side,'calf'+side
        hip=rig.pose.bones[upper].head.copy();a=rig.data.bones[upper].length;b=rig.data.bones[lower].length
        axis=foot-hip;d=min(axis.length,a+b-.0001);axis.normalize()
        pole=Vector((0,-1,0));pole=(pole-axis*pole.dot(axis)).normalized()
        along=(a*a-b*b+d*d)/(2*d);knee=hip+axis*along+pole*math.sqrt(max(0,a*a-along*along))
        _aim_bone(rig,upper,hip,knee);_aim_bone(rig,lower,knee,foot)
        fm=rig.data.bones['foot'+side].matrix_local.copy();fm.translation=foot;rig.pose.bones['foot'+side].matrix=fm
        bpy.context.view_layer.update()
    base=Matrix(((0,1,0),(0,0,1),(1,0,0)))
    swing=math.sin(phase*2*math.pi)
    angle=0 if clip!='work' else -.75+.85*math.cos(phase*2*math.pi)
    orient=Matrix.Rotation(angle,3,'X') @ base
    _solve_arm(rig,'_r',Vector((-.34,-.19,.64+(0.07*swing if clip=='work' else .015*swing))),orient)
    _solve_arm(rig,'_l',Vector((.30,-.10,.56)),base)
    bpy.context.view_layer.update()
