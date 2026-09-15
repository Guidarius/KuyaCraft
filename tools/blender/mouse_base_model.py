"""Equipment-free mouse: source-compatible names, compact rest lengths, simple skin."""
import math
import bpy
from mathutils import Vector, Matrix
from unit_model import Builder, material, PALM, _aim_bone
import woodland_model

def derive(source):
    rig=woodland_model.derive(source);rig.name='MouseBaseRig'
    bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='EDIT')
    for b in rig.data.edit_bones:
        for p in (b.head,b.tail):
            if abs(p.x)>.167:p.x=math.copysign(.167+(abs(p.x)-.167)*.70,p.x)
        if b.name.startswith(('thigh','calf','foot','ball','toe')):
            b.head.x*=1.55;b.tail.x*=1.55
    for side,sign in [('L',1),('R',-1)]:
        b=rig.data.edit_bones.new('mouse_ear_'+side)
        b.head=(sign*.22,.01,1.26);b.tail=(sign*.27,.01,1.48)
        b.parent=rig.data.edit_bones['Head']
    points=[(0,.15,.42),(0,.32,.32),(.10,.49,.28),(.24,.58,.34),(.32,.60,.48)]
    for i in range(4):
        b=rig.data.edit_bones.new('mouse_tail_'+str(i+1));b.head=points[i];b.tail=points[i+1]
        b.parent=rig.data.edit_bones['pelvis' if i==0 else 'mouse_tail_'+str(i)]
    bpy.ops.object.mode_set(mode='OBJECT')
    rig.show_in_front=True;rig.data.display_type='STICK'
    rig['proportionProfile']='mouse_base_v1';rig['forward']='-Y';rig['up']='Z'
    return rig

def ellipsoid(b,name,c,r,bone,mat,sides=8,rings=5):
    c=Vector(c);v=[c+Vector((0,0,-r[2]))]
    for j in range(1,rings):
        lat=-math.pi/2+math.pi*j/rings
        for k in range(sides):
            lon=2*math.pi*k/sides
            v.append(c+Vector((r[0]*math.cos(lat)*math.cos(lon),r[1]*math.cos(lat)*math.sin(lon),r[2]*math.sin(lat))))
    top=len(v);v.append(c+Vector((0,0,r[2])))
    f=[(0,1+(k+1)%sides,1+k) for k in range(sides)]
    for j in range(rings-2):
        for k in range(sides):
            a=1+j*sides+k;d=1+j*sides+(k+1)%sides
            f.append((a,d,d+sides,a+sides))
    f += [(top,1+(rings-2)*sides+k,1+(rings-2)*sides+(k+1)%sides) for k in range(sides)]
    return b.mesh(name,v,f,bone,mat)

def tube(b,name,centers,radii,weights,mat,sides=8):
    v=[]
    for j,c in enumerate(centers):
        c=Vector(c);axis=Vector(centers[min(j+1,len(centers)-1)])-Vector(centers[max(j-1,0)])
        axis.normalize();u=axis.cross(Vector((0,1,0)))
        if u.length<.01:u=axis.cross(Vector((1,0,0)))
        u.normalize();w=axis.cross(u)
        for k in range(sides):
            t=2*math.pi*k/sides;v.append(c+radii[j]*(u*math.cos(t)+w*math.sin(t)))
    faces=[tuple(reversed(range(sides))),tuple(range((len(centers)-1)*sides,len(centers)*sides))]
    for j in range(len(centers)-1):
        for k in range(sides):faces.append((j*sides+k,j*sides+(k+1)%sides,(j+1)*sides+(k+1)%sides,(j+1)*sides+k))
    return b.mesh(name,v,faces,None,mat,[w for w in weights for _ in range(sides)])

def build(rig):
    b=Builder(rig)
    mats={k:material('MouseBase_'+k,c) for k,c in [
        ('fur',(.43,.34,.25)),('cream',(.78,.68,.48)),('pink',(.65,.31,.28)),('dark',(.035,.025,.022))]}
    rings=[(.30,.12,.11),(.40,.21,.15),(.55,.25,.18),(.69,.235,.165),(.82,.17,.125),(.95,.105,.10)]
    verts=[];weights=[]
    ws=[{'pelvis':1},{'pelvis':1},{'pelvis':.5,'spine_01':.5},{'spine_01':.3,'spine_02':.7},{'spine_02':.25,'spine_03':.75},{'spine_03':1}]
    for j,(z,rx,ry) in enumerate(rings):
        for k in range(12):
            a=2*math.pi*k/12;verts.append((rx*math.cos(a),ry*math.sin(a),z));weights.append(ws[j])
    faces=[tuple(reversed(range(12))),tuple(range(60,72))]
    for j in range(5):
        for k in range(12):faces.append((j*12+k,j*12+(k+1)%12,(j+1)*12+(k+1)%12,(j+1)*12+k))
    torso=b.mesh('Body',verts,faces,None,mats['fur'],weights);torso.data.materials.append(mats['cream'])
    for face in torso.data.polygons:
        face.material_index=1 if face.center.y<-.1 and face.center.z<.79 else 0
    ellipsoid(b,'Head',(0,-.025,1.07),(.27,.22,.245),'Head',mats['fur'],10,5)
    ellipsoid(b,'Muzzle',(0,-.205,1.005),(.17,.15,.105),'Head',mats['cream'],8,4)
    ellipsoid(b,'Nose',(0,-.341,1.035),(.042,.028,.031),'Head',mats['pink'],6,3)
    for side,sign in [('_l',1),('_r',-1)]:
        ellipsoid(b,'Eye'+side,(sign*.128,-.208,1.12),(.036,.032,.049),'Head',mats['dark'],8,4)
        # A slightly forward-facing flattened disc; only 26 vertices per ear shell.
        bone='mouse_ear_'+('L' if sign==1 else 'R')
        center=Vector((sign*.245,.005,1.345));v=[];sides=12
        normal=Vector((0,-.84,.54));u=Vector((1,0,0));w=normal.cross(u)
        for depth in [-.031,.031]:
            for i in range(sides):
                t=2*math.pi*i/sides;v.append(center+u*(.175*math.cos(t))+w*(.195*math.sin(t))+normal*depth)
        v += [center-normal*.037,center+normal*.037]
        f=[]
        for i in range(sides):
            n=(i+1)%sides;f += [(24,n,i),(25,12+i,12+n),(i,n,12+n,12+i)]
        ear=b.mesh('Ear'+side,v,f,bone,mats['fur']);ear.data.materials.append(mats['pink'])
        for i,face in enumerate(ear.data.polygons):face.material_index=1 if i%3==1 else 0
        for limb,names,rs in [('Arm',('upperarm','lowerarm'),(.085,.076,.057)),('Leg',('thigh','calf'),(.115,.098,.075))]:
            upper,lower=[n+side for n in names]
            a=rig.data.bones[upper].head_local.copy();mid=rig.data.bones[upper].tail_local.copy();end=rig.data.bones[lower].tail_local.copy()
            centers=[a,a.lerp(mid,.6),mid,mid.lerp(end,.35),end]
            tube(b,limb+side,centers,[rs[0],rs[0],rs[1],rs[1],rs[2]],[{upper:1},{upper:1},{upper:.5,lower:.5},{lower:1},{lower:1}],mats['fur'])
        hand=rig.data.bones['hand'+side]
        palm=hand.matrix_local @ PALM
        ellipsoid(b,'Paw'+side,palm,(.068,.068,.074),'hand'+side,mats['pink'],8,4)
        foot=rig.data.bones['foot'+side].head_local
        ellipsoid(b,'Foot'+side,foot+Vector((0,-.05,.008)),(.092,.145,.065),'foot'+side,mats['pink'],8,4)
    chain=[rig.data.bones['mouse_tail_'+str(i)] for i in range(1,5)]
    centers=[x.head_local.copy() for x in chain]+[chain[-1].tail_local.copy()]
    tube(b,'Tail',centers,[.041,.034,.026,.019,.009],[{'mouse_tail_1':1},{'mouse_tail_1':.5,'mouse_tail_2':.5},{'mouse_tail_2':.5,'mouse_tail_3':.5},{'mouse_tail_3':.5,'mouse_tail_4':.5},{'mouse_tail_4':1}],mats['pink'],6)
    for obj in b.objects:obj['generatedBy']='mouse_base_v1';obj['part']=obj.name
    sockets={}
    for name,bone,point in [('helmet','Head',(0,0,1.27)),('torso','spine_03',(0,0,.81)),
        ('shoulder_l','upperarm_l',(.19,0,.90)),('shoulder_r','upperarm_r',(-.19,0,.90)),
        ('shield','hand_l',rig.data.bones['hand_l'].matrix_local @ PALM),
        ('weapon','hand_r',rig.data.bones['hand_r'].matrix_local @ PALM),
        ('bracer_l','lowerarm_l',rig.data.bones['lowerarm_l'].head_local),
        ('bracer_r','lowerarm_r',rig.data.bones['lowerarm_r'].head_local)]:
        obj=bpy.data.objects.new('attach_'+name,None);bpy.context.scene.collection.objects.link(obj)
        obj.empty_display_type='ARROWS';obj.empty_display_size=.08;obj.parent=rig;obj.parent_type='BONE';obj.parent_bone=bone
        bpy.context.view_layer.update();obj.matrix_world=Matrix.Translation(Vector(point))
        obj['attachmentType']='skinned clothing shares rig' if name=='torso' else 'rigid bone socket'
        sockets[name]={'bone':bone,'restPosition':list(point)}
    return b.objects,sockets

def pose(source,rig,clip,phase):
    for b in rig.pose.bones:
        b.matrix_basis=Matrix.Identity(4)
        if b.name in source.pose.bones:
            origin=source.pose.bones[b.name];b.rotation_mode='QUATERNION'
            b.rotation_quaternion=origin.matrix_basis.to_quaternion();b.location=origin.location*.52
    rig.pose.bones['root'].location.x=rig.pose.bones['root'].location.y=0
    bpy.context.view_layer.update()
    # Grounded character-fit gait. Source retains upper-body intent and timing.
    locomotion=clip in ('walk','run')
    for side,sign in [('_l',1),('_r',-1)]:
        t=phase*2*math.pi+(0 if sign==1 else math.pi)
        foot=Vector((sign*.12,-.02+((.17 if clip=='run' else .12)*math.cos(t) if locomotion else 0),.062+((.12 if clip=='run' else .07)*max(0,math.sin(t)) if locomotion else 0)))
        upper,lower='thigh'+side,'calf'+side;hip=rig.pose.bones[upper].head.copy()
        a=rig.data.bones[upper].length;b=rig.data.bones[lower].length;axis=foot-hip
        d=max(.001,min(axis.length,a+b-.001));axis.normalize()
        pole=Vector((0,-1,0));pole=(pole-axis*pole.dot(axis)).normalized()
        along=(a*a-b*b+d*d)/(2*d);knee=hip+axis*along+pole*math.sqrt(max(0,a*a-along*along))
        _aim_bone(rig,upper,hip,knee);_aim_bone(rig,lower,knee,foot)
        fm=rig.data.bones['foot'+side].matrix_local.copy();fm.translation=foot
        rig.pose.bones['foot'+side].matrix=fm;bpy.context.view_layer.update()
    for i in range(1,5):
        b=rig.pose.bones['mouse_tail_'+str(i)];b.rotation_mode='XYZ'
        b.rotation_euler.z=(.08 if locomotion else .035)*math.sin(phase*2*math.pi-i*.45)
    for side,sign in [('L',1),('R',-1)]:
        b=rig.pose.bones['mouse_ear_'+side];b.rotation_mode='XYZ'
        b.rotation_euler.y=sign*.035*math.sin(phase*2*math.pi-.4)
    bpy.context.view_layer.update()
