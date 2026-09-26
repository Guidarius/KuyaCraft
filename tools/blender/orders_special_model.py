"""Mounted ground Gryphon and rigid floating Reliquary. No gameplay dependencies."""
import math
import bpy
from mathutils import Matrix, Vector
from building_model import Builder as Kit
from aircraft_model import material
from unit_model import Builder, _aim_bone, _solve_arm, PALM
import orders_model


def empty(name, parent=None, location=(0,0,0)):
    ob=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(ob)
    ob.parent=parent;ob.location=location
    return ob


def palette():
    return {name:material('Orders_'+name,c,team=team) for name,c,team in [
        ('ivory',(.68,.65,.54),False),('iron',(.055,.062,.07),False),
        ('brass',(.48,.32,.12),False),('team',(.54,.54,.54),True),
        ('relic',(.95,.77,.35),False),('hide',(.27,.25,.22),False)]}


def solve_leg(rig, upper, lower, paw, target, bend):
    hip=rig.pose.bones[upper].head.copy();target=Vector(target);axis=target-hip
    a=rig.data.bones[upper].length;b=rig.data.bones[lower].length
    d=max(.0001,min(axis.length,a+b-.0001));axis.normalize()
    along=(a*a-b*b+d*d)/(2*d);bend=Vector(bend);bend=(bend-axis*bend.dot(axis)).normalized()
    knee=hip+axis*along+bend*math.sqrt(max(0,a*a-along*along));ankle=hip+axis*d
    _aim_bone(rig,upper,hip,knee);_aim_bone(rig,lower,knee,ankle)
    pose=rig.data.bones[paw].matrix_local.copy();pose.translation=ankle
    rig.pose.bones[paw].matrix=pose;bpy.context.view_layer.update()


def mount_rig(parent):
    data=bpy.data.armatures.new('GryphonSkeleton');rig=bpy.data.objects.new('GryphonRig',data)
    bpy.context.scene.collection.objects.link(rig);rig.parent=parent
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='EDIT')
    def bone(name,a,b,parent_name=None):
        ob=data.edit_bones.new(name);ob.head=a;ob.tail=b
        if parent_name:ob.parent=data.edit_bones[parent_name]
    bone('root',(0,0,0),(0,0,.10));bone('body',(0,0,.24),(0,.08,.24),'root')
    bone('head',(0,-.16,.30),(0,-.28,.42),'body')
    bone('tail',(0,.18,.26),(0,.30,.24),'body')
    for side,x in [('L',.135),('R',-.135)]:
        bone('wing'+side,(x,0,.30),(x,.17,.25),'body')
        for row,y in [('F',-.14),('H',.14)]:
            name=row+side
            bone(name+'Upper',(x,y,.245),(x,y+(-.025 if row=='F' else .04),.135),'body')
            bone(name+'Lower',(x,y+(-.025 if row=='F' else .04),.135),(x,y,.035),name+'Upper')
            bone(name+'Paw',(x,y,.035),(x,y-.045,.035),name+'Lower')
    bpy.ops.object.mode_set(mode='OBJECT')
    return rig


def build_gryphon(recipe, source):
    from pipeline import import_source, reset_pose
    from pathlib import Path
    rider=import_source(Path(source));reset_pose(rider)
    motion=empty('MountedAssembly');rig=mount_rig(motion);m=palette();b=Builder(rig)
    b.ellipsoid('GryphonBody',(0,.015,.255),(.155,.205,.135),'body',m['hide'])
    b.ellipsoid('IvoryBreast',(0,-.145,.29),(.14,.10,.13),'body',m['ivory'])
    b.ellipsoid('BeakedHead',(0,-.265,.40),(.105,.104,.11),'head',m['ivory'])
    b.mesh('GreatBeak',[(-.075,-.30,.40),(.075,-.30,.40),(0,-.405,.335),
                        (-.060,-.30,.445),(.060,-.30,.445),(0,-.375,.41)],
           [(0,1,2),(3,5,4),(0,3,4,1),(1,4,5,2),(2,5,3,0)],'head',m['brass'])
    for x in (-.101,.101):b.box('Eye',(x,-.279,.431),(.012,.042,.024),'head',m['iron'])
    for side,x in [('L',.135),('R',-.135)]:
        sign=1 if x>0 else -1
        # Three broad layered slabs, held folded against the flank, never spread.
        for i in range(3):
            y=-.05+i*.065;z=.335-i*.023
            vertices=[(x-sign*.035,y-.07,z),(x+sign*.065,y-.045,z-.025),
                      (x+sign*.055,y+.16,z-.115),(x-sign*.015,y+.11,z-.07)]
            vertices += [(a-sign*.022,c,d-.016) for a,c,d in vertices]
            b.mesh('FoldedWing'+side+str(i),vertices,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],
                   'wing'+side,m['iron'] if i!=1 else m['ivory'])
        for row,y in [('F',-.14),('H',.14)]:
            name=row+side
            for part,r in [('Upper',.048),('Lower',.036)]:
                bone=rig.data.bones[name+part];b.capsule(name+part,bone.head_local,bone.tail_local,r,name+part,m['ivory'],sides=6)
            b.box(name+'Paw',(x,y-.018,.032),(.088,.11,.064),name+'Paw',m['brass'])
    b.capsule('Tail',(0,.18,.265),(0,.31,.24),.035,'tail',m['hide'],sides=6)
    b.box('TeamSaddlecloth',(0,.045,.34),(.32,.27,.035),'body',m['team'])
    for x in (-.168,.168):b.box('SaddlePanel',(x,.055,.28),(.022,.18,.14),'body',m['team'])
    meshes=b.objects
    rider_recipe={'unitId':'gryphon','model':{'type':'footman','family':'orders'}}
    meshes += orders_model.build_unit(rider,rider_recipe)
    saddle=empty('SaddleSocket',motion,(0,.035,.365));rider.parent=saddle;rider.scale=(.19,)*3
    rider.location=(0,0,-.95*.19)
    neutral_aim=Matrix(((0,1,0),(-1,0,0),(0,0,1)))
    rigs=[rig,rider]
    def pose(clip,phase):
        for skeleton in rigs:
            for bone in skeleton.pose.bones:bone.matrix_basis=Matrix.Identity(4)
        death=phase if clip=='death' else 0
        bob=.006*math.sin(phase*math.tau*2) if clip=='move' else .003*math.sin(phase*math.tau)
        body=rig.data.bones['body'].matrix_local.copy();body.translation.z+=bob-.10*death
        rig.pose.bones['body'].matrix=body;bpy.context.view_layer.update()
        for side,x in [('L',.135),('R',-.135)]:
            for row,y in [('F',-.14),('H',.14)]:
                t=(phase+(0 if (row+side) in ('FL','HR') else .5))%1
                fy=y;z=.035
                if clip=='move':
                    if t<.6:fy+=-.055+.11*t/.6
                    else:
                        swing=(t-.6)/.4;fy+=.055-.11*swing;z+=.055*math.sin(math.pi*swing)
                solve_leg(rig,row+side+'Upper',row+side+'Lower',row+side+'Paw',(x,fy,z),
                          (0,-1 if row=='F' else 1,0))
        head=rig.pose.bones['head'];head.rotation_mode='XYZ'
        head.rotation_euler.x=.10*math.sin(phase*math.tau) if clip=='idle' else .12*death
        saddle.location=(0,.035,.365+bob-.10*death);saddle.rotation_euler.x=-.45*death
        bpy.context.view_layer.update()
        for side,sign in [('_l',1),('_r',-1)]:
            solve_leg(rider,'thigh'+side,'calf'+side,'foot'+side,(sign*.46,.03,.43),(sign,-.3,0))
        orders_model.correct_pose(rider,rider_recipe,'idle',phase)
        strike=math.sin(math.pi*phase) if clip=='attack' else 0
        _solve_arm(rider,'_r',Vector((-.25,-.22-.18*strike,1.23+.10*strike)),neutral_aim)
        motion.location=(0,0,0);motion.rotation_euler=(0,0,0)
    return {'motion':motion,'meshes':meshes,'rigs':rigs,'objects':[motion,saddle,rider],
            'pose':pose,'stride':(.11/.6)*64/26,'rider':rider,'mount':rig,'sourceHash':recipe['sourceHash'],
            'notes':'Folded-wing ground gait; saddle socket; preserved humanoid rider library'}


def build_reliquary(recipe):
    motion=empty('ReliquaryAssembly');b=Kit(motion);m=palette()
    b.lathe('RelicBase',(0,0,.19),[(0,.10),(.04,.17),(.09,.12)],m['brass'],sides=4)
    for x in (-.135,.135):
        b.box('ShrineColumn',(x,.02,.405),(.036,.08,.27),m['ivory'],bevel=.004)
        a=Vector((x,.02,.54));end=Vector((0,.02,.68))
        beam=b.box('PointedCanopy',(a+end)/2,(.037,.12,(end-a).length),m['ivory'],bevel=.004)
        beam.rotation_euler=(end-a).to_track_quat('Z','Y').to_euler()
    b.lathe('RelicHeart',(0,-.045,.29),[(0,0),(.055,.061),(.17,.035),(.24,0)],m['relic'],sides=4)
    b.box('CanopyTeamCap',(0,.045,.635),(.055,.11,.07),m['team'],bevel=.004)
    animated=[motion]
    for x in (-.235,.235):
        hinge=empty('BannerHinge',motion,(x,0,.395));animated.append(hinge)
        b.box('BannerArm',(x/2,0,.395),(abs(x),.025,.025),m['brass'],bevel=.002)
        b.mesh('HangingTeamCloth',[(-.042,-.005,0),(.042,-.005,0),(.042,-.005,-.15),(0,-.005,-.195),(-.042,-.005,-.15)],
               [(0,1,2,3,4)],[m['team']],hinge)
    def pose(clip,phase):
        t=phase*math.tau;death=phase if clip=='death' else 0
        motion.location=(0,0,.012*math.sin(t)*(1-death)-.14*death)
        motion.rotation_euler=(0,.17*death,0)
        for i,ob in enumerate(animated[1:]):ob.rotation_euler.x=.10*math.sin(t+i*.7)*(1-death)
    return {'motion':motion,'meshes':b.meshes,'rigs':[],'objects':animated,'pose':pose,'stride':1,
            'notes':'Rigid shrine and two keyed banner hinges; no humanoid rig or attack mechanic'}
