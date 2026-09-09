"""Original Bastion mesh recipes on the preserved source skeleton.

Only call in an isolated working scene. All coordinates are armature rest space;
the exporter owns orientation, normalization and action evaluation. No source
bone or action is renamed, removed, or modified here.
"""
import math
import bpy
from mathutils import Matrix, Vector

PALM = Vector((0, .060, 0))
REQUIRED = ['pelvis', 'spine_01', 'spine_02', 'spine_03', 'Head'] + [
    part + side for side in ('_l', '_r') for part in
    ('upperarm', 'lowerarm', 'hand', 'thigh', 'calf', 'foot')]


def material(name, color, team=False):
    mat = bpy.data.materials.new('Bastion_' + name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    node = mat.node_tree.nodes.get('Principled BSDF')
    node.inputs['Base Color'].default_value = (*color, 1)
    node.inputs['Roughness'].default_value = .8
    mat['team'] = team
    return mat


class Builder:
    def __init__(self, rig):
        self.rig, self.objects = rig, []

    def mesh(self, name, vertices, faces, bone, mat, weights=None):
        data = bpy.data.meshes.new(name)
        data.from_pydata(vertices, [], faces)
        data.update()
        ob = bpy.data.objects.new(name, data)
        bpy.context.scene.collection.objects.link(ob)
        ob.parent = self.rig
        ob.matrix_parent_inverse = Matrix.Identity(4)
        ob.matrix_basis = Matrix.Identity(4)
        ob.data.materials.append(mat)
        ob['team'] = bool(mat.get('team', False))
        ob['generatedBy'] = 'unit_model_v1'
        if weights is None:
            ob.vertex_groups.new(name=bone).add(list(range(len(vertices))), 1, 'REPLACE')
        else:
            for index, weighted in enumerate(weights):
                for group, amount in weighted.items():
                    vg = ob.vertex_groups.get(group) or ob.vertex_groups.new(name=group)
                    vg.add([index], amount, 'REPLACE')
        mod = ob.modifiers.new('PreservedSourceRig', 'ARMATURE')
        mod.object = self.rig
        self.objects.append(ob)
        return ob

    def box(self, name, center, size, bone, mat, transform=None):
        c, s = Vector(center), Vector(size) / 2
        verts = [c + Vector((x*s.x, y*s.y, z*s.z))
                 for x, y, z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),
                                  (-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        if transform is not None:
            verts = [transform @ v for v in verts]
        return self.mesh(name, verts, [(0,3,2,1),(4,5,6,7),(0,1,5,4),
                                     (1,2,6,5),(2,3,7,6),(3,0,4,7)], bone, mat)

    def capsule(self, name, a, b, radius, bone, mat, sides=8, secondary=None):
        a, b = Vector(a), Vector(b)
        axis = (b-a).normalized()
        u = axis.cross(Vector((0,1,0)))
        if u.length < .01:
            u = axis.cross(Vector((1,0,0)))
        u.normalize()
        v = axis.cross(u).normalized()
        verts, weights = [], []
        rings = [(0,.45),(.12,1),(.5,1.06),(.88,.9),(1,.4)]
        for t, scale in rings:
            for k in range(sides):
                angle = 2*math.pi*k/sides
                verts.append(a.lerp(b,t) + radius*scale*(u*math.cos(angle)+v*math.sin(angle)))
                amount = max(0, (t-.75)*.6) if secondary else 0
                weights.append({bone:1-amount, **({secondary:amount} if amount else {})})
        faces = [tuple(reversed(range(sides))), tuple(range((len(rings)-1)*sides,len(rings)*sides))]
        for j in range(len(rings)-1):
            for k in range(sides):
                n=(k+1)%sides
                faces.append((j*sides+k,j*sides+n,(j+1)*sides+n,(j+1)*sides+k))
        return self.mesh(name, verts, faces, bone, mat, weights)

    def ellipsoid(self, name, center, radius, bone, mat, transform=None):
        c, r = Vector(center), Vector(radius)
        verts=[]
        for j in range(7):
            lat=-math.pi/2+math.pi*(j+.04)/6.08
            for k in range(10):
                lon=2*math.pi*k/10
                p=c+Vector((r.x*math.cos(lat)*math.cos(lon),r.y*math.cos(lat)*math.sin(lon),r.z*math.sin(lat)))
                verts.append(transform @ p if transform is not None else p)
        faces=[]
        for j in range(6):
            for k in range(10):
                n=(k+1)%10
                faces.append((j*10+k,j*10+n,(j+1)*10+n,(j+1)*10+k))
        faces.extend([tuple(reversed(range(10))),tuple(range(60,70))])
        return self.mesh(name,verts,faces,bone,mat)


def build_unit(rig, recipe):
    missing=[name for name in REQUIRED if name not in rig.data.bones]
    if missing:
        raise ValueError('Missing source bones: '+', '.join(missing))
    kind=recipe.get('model',{}).get('type',recipe['unitId'])
    worker=kind in ('worker','worker_loaded')
    hero=kind=='warden'
    b=Builder(rig)
    mats={name:material(name,col,team) for name,col,team in [
        ('skin',(.64,.39,.22),False),('cloth',(.57,.57,.57),True),
        ('steel',(.31,.39,.43),False),('edge',(.65,.71,.69),False),
        ('leather',(.19,.095,.045),False),('wood',(.39,.20,.075),False),
        ('gold',(.75,.48,.10),False),('dark',(.055,.067,.07),False),
        ('cargo',(.48,.36,.19),False) ]}
    def head(name): return rig.data.bones[name].head_local.copy()
    def tail(name): return rig.data.bones[name].tail_local.copy()
    b.ellipsoid('Pelvis',head('pelvis')+Vector((0,0,.03)),(.205,.135,.15),'pelvis',mats['leather'])
    b.ellipsoid('Tunic',Vector((0,.01,1.19)),(.235 if not worker else .21,.155,.275),'spine_02',mats['cloth'])
    b.box('Belt',(0,-.005,1.00),(.39,.29,.055),'spine_01',mats['leather'])
    b.box('Buckle',(0,-.159,1.00),(.075,.018,.06),'spine_01',mats['gold'])
    if not worker:
        b.ellipsoid('Breastplate',(0,-.055,1.285),(.245 if hero else .22,.137,.18),'spine_03',mats['steel'])
        b.box('TeamTabard',(0,-.16,1.11),(.16,.032,.25),'spine_02',mats['cloth'])
    neck=head('Head')
    b.capsule('Neck',neck-Vector((0,0,.12)),neck+Vector((0,0,.02)),.065,'Head',mats['skin'])
    b.ellipsoid('HeadStump',neck+Vector((0,-.018,.09)),(.119,.105,.15),'Head',mats['skin'])
    # Eye bar and nose preserve facing at sprite scale without tiny facial topology.
    b.box('EyeBar',neck+Vector((0,-.116,.12)),(.12,.016,.026),'Head',mats['dark'])
    b.box('Nose',neck+Vector((0,-.128,.075)),(.035,.035,.046),'Head',mats['skin'])
    b.ellipsoid('Helmet' if not worker else 'WorkCap',neck+Vector((0,0,.16)),(.137,.122,.106 if not worker else .062),'Head',mats['steel'] if not worker else mats['cloth'])
    if not worker:
        b.box('HelmetBrow',neck+Vector((0,-.122,.133)),(.225,.03,.045),'Head',mats['gold'] if hero else mats['edge'])
    if hero:
        b.box('WardenCrest',neck+Vector((0,.005,.285)),(.05,.23,.13),'Head',mats['cloth'])
    for side in ('_l','_r'):
        for part,rad,mat in [('thigh',.103,'leather'),('calf',.087,'leather'),('upperarm',.089,'cloth'),('lowerarm',.065,'skin' if worker else 'steel')]:
            name=part+side
            second={'thigh':'calf','upperarm':'lowerarm','lowerarm':'hand'}.get(part)
            b.capsule(name,head(name),tail(name),rad,name,mats[mat],secondary=second+side if second else None)
        p=head('foot'+side)
        b.box('Boot'+side,p+Vector((0,-.055,-.015)),(.155,.27,.135),'foot'+side,mats['leather'])
        if not worker:
            b.ellipsoid('Pauldron'+side,head('upperarm'+side),(.145 if hero else .115,.13,.14),'upperarm'+side,mats['gold'] if hero else mats['steel'])
        hand='hand'+side
        hmat=rig.data.bones[hand].matrix_local
        b.ellipsoid('PalmStump'+side,PALM,(.057,.083,.052),hand,mats['skin'],hmat)
    right=rig.data.bones['hand_r'].matrix_local
    left=rig.data.bones['hand_l'].matrix_local
    if kind in ('shieldguard','warden'):
        length=.65 if hero else .52
        b.box('SwordHandle',PALM,(.19,.038,.042),'hand_r',mats['leather'],right)
        b.box('SwordGuard',PALM+Vector((.09,0,0)),(.035,.25,.045),'hand_r',mats['gold'],right)
        b.box('SwordBlade',PALM+Vector((.12+length/2,0,0)),(length,.09,.025),'hand_r',mats['edge'],right)
        # Hand +Z faces forward in the authored carry pose; the team face is outward.
        b.box('ShieldRim',PALM+Vector((0,0,.065)),(.56,.40,.055),'hand_l',mats['edge'],left)
        b.box('ShieldFace',PALM+Vector((0,0,.102)),(.50,.34,.026),'hand_l',mats['cloth'],left)
        b.box('ShieldBoss',PALM+Vector((0,0,.124)),(.11,.11,.025),'hand_l',mats['gold'],left)
    elif worker:
        b.box('ToolHandle',PALM+Vector((.11,0,0)),(.58,.036,.038),'hand_r',mats['wood'],right)
        b.box('ToolHead',PALM+Vector((.38,0,0)),(.11,.25,.065),'hand_r',mats['steel'],right)
        if kind=='worker_loaded' or recipe.get('model',{}).get('cargo',False):
            b.ellipsoid('CargoSack',(0,.175,1.22),(.23,.12,.22),'spine_02',mats['cargo'])
            for x in (-.115,.115):
                b.box('CargoStrap',(x,.13,1.265),(.035,.24,.34),'spine_02',mats['leather'])
            for z in (1.13,1.29):
                b.capsule('CargoLog',(-.27,.23,z),(.27,.23,z),.055,'spine_02',mats['wood'])
    elif kind=='crossbow':
        b.box('CrossbowStock',PALM+Vector((0,.115,0)),(.085,.53,.075),'hand_r',mats['wood'],right)
        b.box('CrossbowBow',PALM+Vector((0,.31,0)),(.62,.055,.048),'hand_r',mats['steel'],right)
        b.box('CrossbowString',PALM+Vector((0,.22,-.035)),(.58,.012,.012),'hand_r',mats['dark'],right)
        b.box('CrossbowBolt',PALM+Vector((0,.19,-.055)),(.015,.43,.015),'hand_r',mats['edge'],right)
    else:
        raise ValueError('Unknown model type '+kind)
    rig['bastionModel']=kind
    rig['gripOffset']=list(PALM)
    return b.objects


def _aim_bone(rig,name,start,end):
    rest=rig.data.bones[name].matrix_local.to_3x3()
    q=rest.col[1].normalized().rotation_difference((end-start).normalized())
    matrix=(q.to_matrix() @ rest).to_4x4()
    matrix.translation=start
    rig.pose.bones[name].matrix=matrix
    bpy.context.view_layer.update()


def _solve_arm(rig,side,palm,orientation,elbow_up=False):
    """Analytic non-stretch two-bone solve in armature space, then wrist orientation."""
    upper,lower,hand=('upperarm'+side,'lowerarm'+side,'hand'+side)
    shoulder=rig.pose.bones[upper].head.copy()
    wrist=palm-orientation @ PALM
    direction=wrist-shoulder
    a,b=rig.data.bones[upper].length,rig.data.bones[lower].length
    d=max(.0001,min(direction.length,a+b-.001))
    direction.normalize()
    wrist=shoulder+direction*d
    along=(a*a-b*b+d*d)/(2*d)
    bend=Vector((1 if side=='_l' else -1,0,.6 if elbow_up else -.6))
    bend=(bend-direction*bend.dot(direction)).normalized()
    elbow=shoulder+direction*along+bend*math.sqrt(max(0,a*a-along*along))
    _aim_bone(rig,upper,shoulder,elbow)
    _aim_bone(rig,lower,elbow,wrist)
    matrix=orientation.to_4x4()
    matrix.translation=wrist
    rig.pose.bones[hand].matrix=matrix
    bpy.context.view_layer.update()


def correct_pose(rig,recipe,clip,phase):
    """Called once after evaluating each pristine source sample; no action edits.

    Exporter bakes these evaluated matrices into its derived working action.
    Death deliberately retains the source fall and carries attached equipment.
    """
    kind=recipe.get('model',{}).get('type',recipe['unitId'])
    if isinstance(clip,dict):
        clip=clip.get('id',clip.get('name','idle'))
    if clip=='death':
        # The source is an unarmed fall: its relaxed wrists point a long weapon
        # into the ground. Lay equipment beside the corpse while preserving
        # wrist positions and the original torso/leg fall. Correct only the
        # anatomical-body floor offset, never raise the body to clear a sword.
        blend=max(0.0,min(1.0,(phase-.30)/.35))
        blend=blend*blend*(3-2*blend)
        ground_blend=max(0.0,min(1.0,(phase-.25)/.23))
        ground_blend=ground_blend*ground_blend*(3-2*ground_blend)
        pelvis=rig.pose.bones['pelvis']
        matrix=pelvis.matrix.copy()
        matrix.translation.z += .095*ground_blend
        pelvis.matrix=matrix
        bpy.context.view_layer.update()
        if kind=='worker_loaded':
            # The back bundle supports the fallen upper torso. Recline the
            # spine over it while hips and legs retain the source ground fall.
            spine=rig.pose.bones['spine_01']
            matrix=spine.matrix.copy()
            rotation=Matrix.Rotation(.72*ground_blend,3,'X') @ matrix.to_3x3()
            raised=rotation.to_4x4()
            raised.translation=matrix.translation
            spine.matrix=raised
            bpy.context.view_layer.update()
        if kind=='crossbow':
            # Cradle the crossbow above the fallen torso, with its stock along
            # the body. Generic sword wrist orientation puts the broad bow
            # beyond the extended source wrist/head and breaks the 128px cell.
            torso=rig.pose.bones['spine_03'].matrix @ rig.data.bones['spine_03'].matrix_local.inverted()
            aim=Matrix(((1,0,0),(0,-1,0),(0,0,-1)))
            orientation=(torso.to_3x3() @ aim).to_quaternion().slerp(aim.to_quaternion(),blend).to_matrix()
            grip=torso @ Vector((-.07,-.17,1.29))
            _solve_arm(rig,'_r',grip,orientation,elbow_up=True)
            _solve_arm(rig,'_l',grip+orientation @ Vector((0,.18,0)),orientation,elbow_up=True)
            return
        flat=Matrix(((0,1,0),(-1,0,0),(0,0,1))).to_quaternion()
        for side in ('_l','_r'):
            hand=rig.pose.bones['hand'+side]
            matrix=hand.matrix.copy()
            rotation=matrix.to_quaternion().slerp(flat,blend).to_matrix().to_4x4()
            rotation.translation=matrix.translation
            hand.matrix=rotation
            bpy.context.view_layer.update()
        if kind=='warden':
            # Larger hero shoulders/crest require a compact settled fall.
            # Curl the elbows rather than translating or shrinking the corpse.
            for side in ('_l','_r'):
                hand=rig.pose.bones['hand'+side]
                orientation=hand.matrix.to_3x3()
                palm=hand.matrix @ PALM
                target=Vector((palm.x,min(palm.y,1.16),max(palm.z,.15)))
                _solve_arm(rig,side,palm.lerp(target,blend),orientation,elbow_up=True)
            head=rig.pose.bones['Head']
            matrix=head.matrix.copy()
            settled=(Matrix.Rotation(.95*blend,3,'X') @ matrix.to_3x3()).to_4x4()
            settled.translation=matrix.translation
            settled.translation.y -= .05*blend
            head.matrix=settled
            bpy.context.view_layer.update()
        return
    if kind=='worker_loaded':
        spine=rig.pose.bones['spine_02']
        spine.matrix_basis=spine.matrix_basis @ Matrix.Rotation(.055,4,'X')
        bpy.context.view_layer.update()
    torso=rig.pose.bones['spine_03'].matrix @ rig.data.bones['spine_03'].matrix_local.inverted()
    if kind=='crossbow':
        # Weapon is the reference: support grip lies .18 along its stock axis.
        recoil=.045*math.exp(-((phase-.45)/.11)**2) if clip=='attack' else 0
        aim=Matrix(((1,0,0),(0,-1,0),(0,0,-1)))
        orient=torso.to_3x3() @ aim
        grip=torso @ Vector((-.07,-.17+recoil,1.29))
        support=grip+orient @ Vector((0,.18,0))
        _solve_arm(rig,'_r',grip,orient)
        _solve_arm(rig,'_l',support,orient)
    elif kind in ('worker','worker_loaded') and clip=='work':
        swing=math.sin(phase*math.tau)
        orient=torso.to_3x3() @ Matrix.Rotation(.6*swing,3,'X') @ rig.data.bones['hand_r'].matrix_local.to_3x3()
        grip=torso @ Vector((-.23,-.35,1.13+.13*swing))
        _solve_arm(rig,'_r',grip,orient)
    elif kind in ('shieldguard','warden') and clip in ('idle','move','attack'):
        # Keep shield away from helmet and across the left flank. Source right-arm sword motion survives.
        orient=torso.to_3x3() @ Matrix(((0,1,0),(0,0,-1),(-1,0,0)))
        _solve_arm(rig,'_l',torso @ Vector((.31,-.20,1.08)),orient)
        if kind=='warden' and clip=='attack':
            # The longer hero blade needs a small wrist recovery correction at
            # the low sweep; damage timing and the source arm path are retained.
            hand=rig.pose.bones['hand_r']
            matrix=hand.matrix.copy()
            original=matrix.to_quaternion()
            axis=matrix.to_3x3().col[0].normalized()
            horizontal=Vector((axis.x,axis.y,0))
            if horizontal.length>.001:
                target=(axis.rotation_difference(horizontal.normalized()) @ original)
                corners=[PALM+Vector((x,y,z)) for x in (.12,.77) for y in (-.045,.045) for z in (-.0125,.0125)]
                if min((matrix @ c).z for c in corners)<.015:
                    low,high=0.,1.
                    for _ in range(14):
                        middle=(low+high)/2
                        candidate=original.slerp(target,middle).to_matrix().to_4x4()
                        candidate.translation=matrix.translation
                        if min((candidate @ c).z for c in corners)<.015:low=middle
                        else:high=middle
                    corrected=original.slerp(target,high).to_matrix().to_4x4()
                    corrected.translation=matrix.translation
                    hand.matrix=corrected
                    bpy.context.view_layer.update()


def grip_report(rig):
    bpy.context.view_layer.update()
    right=rig.pose.bones['hand_r'].matrix
    left=rig.pose.bones['hand_l'].matrix
    a,b=right @ PALM,left @ PALM
    report={'rightPalm':list(a),'leftPalm':list(b),'stumpBones':['hand_l','hand_r'],
            'boneCount':len(rig.data.bones),'fingerGeometry':False}
    if rig.get('bastionModel')=='crossbow':
        support=right @ (PALM+Vector((0,.18,0)))
        report['supportGripError']=float((b-support).length)
    return report
