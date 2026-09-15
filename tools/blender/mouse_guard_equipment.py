"""Removable socket equipment and a weighted vest for the compact mouse base."""
import math
import bpy
from mathutils import Vector, Matrix
from unit_model import Builder, material, PALM, _solve_arm

def build(rig):
    b=Builder(rig)
    mats={k:material('MouseGuard_'+k,c,t) for k,c,t in [
        ('steel',(.34,.40,.42),False),('edge',(.68,.73,.71),False),
        ('wood',(.25,.13,.055),False),('gold',(.66,.43,.13),False),
        ('team',(.20,.38,.61),True)]}
    groups={k:[] for k in ('sword','shield','helmet','armor')}
    def socket_part(obj,slot):
        # Builder vertices are rest-armature coordinates. Convert to the actual
        # socket frame, including its bone-tail offset and the rig's world scale.
        marker=bpy.data.objects['attach_'+slot]
        xform=marker.matrix_world.inverted() @ rig.matrix_world
        obj.data.transform(xform)
        obj.modifiers.clear();obj.vertex_groups.clear()
        obj.parent=marker;obj.matrix_parent_inverse=Matrix.Identity(4);obj.matrix_basis=Matrix.Identity(4)
        groups['sword' if slot=='weapon' else slot].append(obj)
        return obj
    hand=rig.data.bones['hand_r'].matrix_local
    # Longitudinal local X passes directly through the mitten palm.
    def sword(obj):
        return socket_part(obj,'weapon')
    sword(b.box('GuardSwordGrip',PALM,(.18,.043,.043),'hand_r',mats['wood'],hand))
    sword(b.box('GuardSwordGuard',PALM+Vector((.105,0,0)),(.035,.21,.045),'hand_r',mats['gold'],hand))
    v=[(.12,-.068,0),(.12,0,.026),(.12,.068,0),(.12,0,-.026),
       (.42,-.049,0),(.42,0,.020),(.42,.049,0),(.42,0,-.020),(.53,0,0)]
    faces=[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,8),(5,6,8),(6,7,8),(7,4,8)]
    blade=b.mesh('GuardSwordBlade',[hand @ (PALM+Vector(x)) for x in v],faces,'hand_r',mats['edge']);sword(blade)
    # A compact pointed shield: local X is vertical in the fitted carry pose.
    hand=rig.data.bones['hand_l'].matrix_local
    shape=[(-.22,0),(-.09,-.155),(.13,-.155),(.19,-.09),(.19,.09),(.13,.155),(-.09,.155)]
    def shield(name,scale,depth,thickness,mat):
        points=[hand @ (PALM+Vector((x*scale,y*scale,z))) for z in (depth,depth+thickness) for x,y in shape]
        n=len(shape);faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        return socket_part(b.mesh(name,points,faces,'hand_l',mat),'shield')
    shield('GuardShieldRim',1,-.095,.045,mats['wood'])
    shield('GuardShieldFace',.84,-.105,.010,mats['team'])
    socket_part(b.box('GuardShieldHandle',PALM,(.09,.04,.15),'hand_l',mats['wood'],hand),'shield')
    socket_part(b.box('GuardShieldBoss',PALM+Vector((0,0,-.12)),(.075,.075,.032),'hand_l',mats['gold'],hand),'shield')
    # Central helmet cap leaves both round ears exposed. No plume or micro-detail.
    rings=[(1.19,.22,.19),(1.27,.13,.165),(1.345,.055,.08)]
    verts=[(rx*math.cos(k*math.tau/12),-.025+ry*math.sin(k*math.tau/12),z) for z,rx,ry in rings for k in range(12)]
    faces=[]
    for j in range(2):
        for k in range(12):
            # Side openings at the ear roots, with central front/back coverage.
            if j==0 and k in (0,5,6,11):continue
            faces.append((j*12+k,j*12+(k+1)%12,(j+1)*12+(k+1)%12,(j+1)*12+k))
    faces.append(tuple(range(24,36)))
    socket_part(b.mesh('GuardHelmet',verts,faces,'Head',mats['steel']),'helmet')
    socket_part(b.box('GuardHelmetBrow',(0,-.212,1.195),(.26,.035,.045),'Head',mats['edge']),'helmet')
    # Duplicate only torso rings above the hips and preserve their exact weights.
    body=bpy.data.objects['Body'];ids=list(range(12,72));verts=[];weights=[]
    for i in ids:
        v=body.data.vertices[i];verts.append((v.co.x*1.09,v.co.y*1.12,v.co.z))
        weights.append({body.vertex_groups[g.group].name:g.weight for g in v.groups})
    faces=[(j*12+k,j*12+(k+1)%12,(j+1)*12+(k+1)%12,(j+1)*12+k) for j in range(4) for k in range(12)]
    vest=b.mesh('GuardArmorVest',verts,faces,None,mats['steel'],weights);vest.data.materials.append(mats['team'])
    for f in vest.data.polygons:
        if f.center.y<-.10:f.material_index=1
    solid=vest.modifiers.new('ArmorThickness','SOLIDIFY');solid.thickness=.012;solid.offset=1
    groups['armor'].append(vest)
    for slot,objects in groups.items():
        col=bpy.data.collections.new('Equipment_'+slot);bpy.context.scene.collection.children.link(col)
        for obj in objects:
            for old in list(obj.users_collection):old.objects.unlink(obj)
            col.objects.link(obj);obj['equipmentSlot']=slot;obj['generatedBy']='mouse_guard_equipment_v1'
    return b.objects,{k:[o.name for o in v] for k,v in groups.items()}

def fit_pose(rig,clip,phase):
    """Fit arm carry to equipment; original bare actions remain independently editable."""
    base=Matrix(((0,1,0),(0,0,1),(1,0,0)))
    chest=rig.pose.bones['spine_03'].matrix @ rig.data.bones['spine_03'].matrix_local.inverted()
    wave=math.sin(phase*math.tau)
    thrust=math.sin(math.pi*phase)**3 if clip=='punch' else 0
    cheer=math.sin(math.pi*phase)**2 if clip=='celebrate' else 0
    for side,sign in [('_r',-1),('_l',1)]:
        point=Vector((sign*.36,-.18-(.13*thrust if sign==-1 else .015),.66+.018*wave+.36*cheer))
        angle=(.95*thrust if sign==-1 else -.12)
        orient=chest.to_3x3() @ Matrix.Rotation(-.55 if sign==-1 else .08,3,'Y') @ Matrix.Rotation(angle,3,'X') @ base
        _solve_arm(rig,side,chest @ point,orient)
    bpy.context.view_layer.update()
