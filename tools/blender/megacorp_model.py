"""Rounded pressure-suit infantry on the preserved 65-bone library.

Geometry is authored in the unchanged source rest space. Derived poses crouch
and widen the stance with non-stretch limb solves; no rest bone or source action
is edited. Equipment is rigid to named hand/torso bones.
"""
import math
import bpy
from mathutils import Matrix, Vector
from unit_model import Builder, PALM, _aim_bone, _solve_arm, material

LEG_RATIO = .62  # Fixed suit proportions, never stretched to chase an animation target.


class SuitBuilder(Builder):
    def lathe(self, name, profile, radii, center, bone, mat, transform=None):
        verts=[];faces=[];sides=12
        for y,r in profile:
            for i in range(sides):
                a=i*math.tau/sides
                point=Vector(center)+Vector((radii[0]*r*math.cos(a),y,radii[1]*r*math.sin(a)))
                verts.append(transform @ point if transform is not None else point)
        for j in range(len(profile)-1):
            for i in range(sides):
                k=(i+1)%sides
                faces.append((j*sides+i,(j+1)*sides+i,(j+1)*sides+k,j*sides+k))
        faces += [tuple(range(sides)),tuple((len(profile)-1)*sides+i for i in reversed(range(sides)))]
        return self.mesh(name,verts,faces,bone,mat)

    def crown(self, obj, team, height):
        obj.data.materials.append(team)
        for p in obj.data.polygons:
            if sum(obj.data.vertices[i].co.z for i in p.vertices)/len(p.vertices)>height:
                p.material_index=1
        return obj

    def ring(self, name, center, radius, bone, mat, tube=.018):
        verts=[];faces=[]
        for i in range(12):
            a=i*math.tau/12
            for j in range(4):
                t=j*math.tau/4
                verts.append(Vector(center)+Vector(((radius+tube*math.cos(t))*math.cos(a),
                                                    tube*math.sin(t),(radius+tube*math.cos(t))*math.sin(a))))
        for i in range(12):
            for j in range(4):
                faces.append((i*4+j,i*4+(j+1)%4,((i+1)%12)*4+(j+1)%4,((i+1)%12)*4+j))
        return self.mesh(name,verts,faces,bone,mat)


def build_unit(rig, recipe):
    kind=recipe['unitId'];heavy=kind=='enforcer';b=SuitBuilder(rig)
    mats={name:material('Megacorp_'+name,col,team) for name,col,team in [
        ('graphite',(.11,.13,.16),False),('team',(.56,.56,.56),True),
        ('rubber',(.022,.026,.032),False),('rim',(.43,.46,.48),False),
        ('glass',(.055,.044,.03),False),('ceramic',(.60,.62,.60),False)]}
    mats['glass'].node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.18
    def head(name):return rig.data.bones[name].head_local.copy()
    def tail(name):return rig.data.bones[name].tail_local.copy()
    b.ellipsoid('HipJoint',(0,.01,.93),(.24 if heavy else .19,.17,.18),'pelvis',mats['rubber'])
    if heavy:
        ob=b.ellipsoid('PressureBarrel',(0,0,1.28),(.37,.265,.43),'spine_03',mats['graphite'])
        b.crown(ob,mats['team'],1.49)
        b.ring('PortholeRim',(0,-.246,1.46),.088,'spine_03',mats['rim'])
        b.ellipsoid('PortholeGlass',(0,-.257,1.46),(.078,.035,.078),'spine_03',mats['glass'])
    else:
        b.ellipsoid('EggTorso',(0,.015,1.15),(.255,.19,.285),'spine_02',mats['graphite'])
        if kind=='associate':
            helmet=b.lathe('HelmetShell',[(-.315,.03),(-.30,.35),(-.22,.76),(-.08,1),
                                          (.07,.94),(.22,.65),(.29,.03)],(.31,.32),
                           (0,0,1.66),'Head',mats['team'])
            helmet.data.materials.append(mats['glass'])
            for face in helmet.data.polygons:
                if sum(helmet.data.vertices[i].co.y for i in face.vertices)/len(face.vertices)<-.081:
                    face.material_index=1
            b.ring('BubbleVisorRim',(0,-.08,1.66),.314,'Head',mats['rim'],.012)
            b.ellipsoid('PressureCollar',(0,-.01,1.395),(.26,.235,.065),'spine_03',mats['rim'])
            b.ellipsoid('BatteryPack',(0,.195,1.22),(.22,.135,.25),'spine_02',mats['graphite'])
        else:
            transform=Matrix.Translation((0,.21,1.62)) @ Matrix.Rotation(math.pi/2,4,'Z')
            pack=b.lathe('MedicalCapsule',[(-.56,.03),(-.53,.55),(-.44,.92),(-.28,1),
                                          (.28,1),(.44,.92),(.53,.55),(.56,.03)],
                         (.195,.22),(0,0,0),'spine_03',mats['graphite'],transform)
            b.crown(pack,mats['team'],1.61)
            b.ellipsoid('HelmetShell',(0,-.08,1.52),(.18,.19,.22),'Head',mats['team'])
            b.ellipsoid('OvalVisor',(0,-.238,1.52),(.133,.058,.164),'Head',mats['glass'])
            b.ellipsoid('TreatmentPanel',(0,-.164,1.16),(.155,.056,.17),'spine_02',mats['ceramic'])
            b.box('PackPlusVertical',(.35,.02,1.62),(.043,.026,.17),'spine_03',mats['ceramic'])
            b.box('PackPlusHorizontal',(.35,.016,1.62),(.14,.03,.043),'spine_03',mats['ceramic'])
    for side in ('_l','_r'):
        for part,radius in [('thigh',.14 if heavy else .115),('calf',.115 if heavy else .095),
                            ('upperarm',.125 if heavy else .10),('lowerarm',.11 if heavy else .082)]:
            bone=part+side;a=head(bone);end=tail(bone)
            b.capsule(part+side,a.lerp(end,.08),a.lerp(end,.92),radius,bone,mats['graphite'])
            b.ellipsoid('Joint_'+part+side,a,(radius*.82,)*3,bone,mats['rubber'])
        foot=head('foot'+side)
        b.ellipsoid('Boot'+side,foot+Vector((0,-.065,-.025)),(.16 if heavy else .137,.22,.125),'foot'+side,mats['graphite'])
        shoulder=b.ellipsoid('ShoulderShell'+side,head('upperarm'+side),
                              (.23,.21,.245) if heavy else (.16,.165,.165),
                              'upperarm'+side,mats['graphite'])
        b.crown(shoulder,mats['team'],1.43)
        hand='hand'+side;transform=rig.data.bones[hand].matrix_local
        b.ellipsoid('PalmStump'+side,PALM,(.072,.083,.066),hand,mats['rubber'],transform)
    right=rig.data.bones['hand_r'].matrix_local
    if kind=='associate':
        b.lathe('CarbineHousing',[(-.09,.65),(-.04,1),(.14,1),(.21,.7)],(.08,.067),PALM,'hand_r',mats['rim'],right)
        b.lathe('CarbineBarrel',[(.18,.75),(.29,.75),(.32,1),(.37,1)],(.065,.065),PALM,'hand_r',mats['graphite'],right)
        b.lathe('CarbineMuzzle',[(.371,.82),(.375,.82)],(.065,.065),PALM,'hand_r',mats['rubber'],right)
    elif kind=='medic':
        b.lathe('TreatmentWand',[(-.05,.7),(.01,1),(.17,1),(.24,.65)],(.064,.064),PALM,'hand_r',mats['ceramic'],right)
        b.lathe('WandTeamBand',[(.14,1.04),(.19,1.04)],(.064,.064),PALM,'hand_r',mats['team'],right)
        b.lathe('WandTip',[(.242,.62),(.248,.62)],(.064,.064),PALM,'hand_r',mats['rubber'],right)
    else:
        b.lathe('ImpactGauntlet',[(-.12,.6),(-.05,.92),(.14,1),(.26,.90)],(.20,.20),PALM,'hand_r',mats['graphite'],right)
        b.lathe('ImpactFace',[(.261,.90),(.30,.83)],(.20,.20),PALM,'hand_r',mats['rim'],right)
    rig['megacorpModel']=kind
    for obj in b.objects:obj['megacorpPart']=True
    return b.objects


def aim_leg(rig,name,start,end):
    _aim_bone(rig,name,start,end)
    rig.pose.bones[name].matrix=rig.pose.bones[name].matrix @ Matrix.Diagonal((1,LEG_RATIO,1,1))
    bpy.context.view_layer.update()


def leg(rig,side,foot_matrix):
    upper,lower,foot=('thigh'+side,'calf'+side,'foot'+side)
    hip=rig.pose.bones[upper].head.copy();ankle=foot_matrix.translation.copy()
    ankle.x += .075 if side=='_l' else -.075
    axis=ankle-hip;a=rig.data.bones[upper].length*LEG_RATIO;b=rig.data.bones[lower].length*LEG_RATIO
    distance=min(axis.length,a+b-.001);axis.normalize()
    along=(a*a-b*b+distance*distance)/(2*distance)
    bend=Vector((.35 if side=='_l' else -.35,-1,0))
    bend=(bend-axis*bend.dot(axis)).normalized()
    knee=hip+axis*along+bend*math.sqrt(max(0,a*a-along*along))
    ankle=hip+axis*distance
    aim_leg(rig,upper,hip,knee);aim_leg(rig,lower,knee,ankle)
    foot_matrix.translation=ankle;rig.pose.bones[foot].matrix=foot_matrix
    bpy.context.view_layer.update()


def floor_meshes(rig):
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
    bottom=float('inf')
    for obj in bpy.context.scene.objects:
        if obj.type!='MESH' or not obj.get('megacorpPart'):continue
        evaluated=obj.evaluated_get(deps);mesh=evaluated.to_mesh()
        bottom=min(bottom,min((evaluated.matrix_world @ v.co).z for v in mesh.vertices))
        evaluated.to_mesh_clear()
    if bottom<0:
        pelvis=rig.pose.bones['pelvis'];matrix=pelvis.matrix.copy()
        matrix.translation.z -= bottom;pelvis.matrix=matrix
        bpy.context.view_layer.update()


def correct_pose(rig,recipe,clip,phase):
    kind=recipe['unitId'];heavy=kind=='enforcer'
    if clip!='death':
        feet={s:rig.pose.bones['foot'+s].matrix.copy() for s in ('_l','_r')}
        pelvis=rig.pose.bones['pelvis'];matrix=pelvis.matrix.copy()
        matrix.translation.z-=.42 if heavy else .40;pelvis.matrix=matrix
        bpy.context.view_layer.update()
        for side in feet:leg(rig,side,feet[side])
    else:
        # Keep the first falling pose at the suit's standing height, then let
        # the authored fall settle. Recenter its small backward drift so the
        # corpse retains the shared ground anchor and directional cell margin.
        settle=min(1.0,phase*2)
        settle=settle*settle*(3-2*settle)
        pelvis=rig.pose.bones['pelvis'];matrix=pelvis.matrix.copy()
        matrix.translation.z-=(.42 if heavy else .40)*(1-settle)
        matrix.translation.y-=.035*settle
        pelvis.matrix=matrix;bpy.context.view_layer.update()
        for side in ('_l','_r'):
            hip=rig.pose.bones['thigh'+side].head.copy()
            knee=rig.pose.bones['calf'+side].head.copy()
            foot=rig.pose.bones['foot'+side].matrix.copy()
            ankle=foot.translation.copy()
            shortened_knee=hip+(knee-hip)*LEG_RATIO
            shortened_ankle=shortened_knee+(ankle-knee)*LEG_RATIO
            aim_leg(rig,'thigh'+side,hip,shortened_knee)
            aim_leg(rig,'calf'+side,shortened_knee,shortened_ankle)
            foot.translation=shortened_ankle;rig.pose.bones['foot'+side].matrix=foot
            bpy.context.view_layer.update()
    # Shoulders move out to the suit's sides without changing the source rest rig.
    for side in ('_l','_r'):
        shoulder=rig.pose.bones['upperarm'+side];matrix=shoulder.matrix.copy()
        matrix.translation.x += (1 if side=='_l' else -1)*(.19 if heavy else .055)
        shoulder.matrix=matrix;bpy.context.view_layer.update()
    torso=rig.pose.bones['spine_03'].matrix @ rig.data.bones['spine_03'].matrix_local.inverted()
    aim=Matrix(((1,0,0),(0,-1,0),(0,0,-1)))
    orientation=torso.to_3x3() @ aim
    if kind=='associate':
        recoil=.045*max(0,1-abs(phase-.4)/.22) if clip=='attack' else 0
        grip=torso @ Vector((0,-.23+recoil,1.23))
        _solve_arm(rig,'_r',grip,orientation)
        _solve_arm(rig,'_l',grip+orientation @ Vector((0,.16,0)),orientation)
    elif kind=='medic':
        # A downward treatment tool, with a small authored reach in the review/work clip.
        reach=.04*(1-math.cos(math.tau*phase)) if clip=='work' else 0
        down=Matrix.Rotation(.5,3,'X') @ orientation
        _solve_arm(rig,'_r',torso @ Vector((-.30,-.19-reach,1.04)),down)
        _solve_arm(rig,'_l',torso @ Vector((.31,-.08,1.02)),orientation)
    else:
        strike=max(0,1-abs(phase-.4)/.28) if clip=='attack' else 0
        _solve_arm(rig,'_r',torso @ Vector((-.40,-.32-.16*strike,1.10+.30*strike)),orientation)
        _solve_arm(rig,'_l',torso @ Vector((.41,-.06,1.00)),orientation)
    floor_meshes(rig)


def grip_report(rig):
    a=rig.pose.bones['hand_r'].matrix; b=rig.pose.bones['hand_l'].matrix
    result={'boneCount':len(rig.data.bones),'fingerGeometry':False,
            'rightPalm':list(a @ PALM),'leftPalm':list(b @ PALM)}
    if rig.get('megacorpModel')=='associate':
        result['supportGripError']=((b @ PALM)-(a @ (PALM+Vector((0,.16,0))))).length
    return result
