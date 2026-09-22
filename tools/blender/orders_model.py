"""Cathedral infantry around the preserved humanoid rig; derived geometry only."""
import copy
import math
import bpy
from mathutils import Matrix, Vector
import unit_model as base


def legacy_recipe(recipe):
    r = copy.deepcopy(recipe)
    if r['model']['type'] == 'footman': r['model']['type'] = 'shieldguard'
    return r


class Builder(base.Builder):
    def prism(self, name, outline, depth, bone, mat, transform=None):
        # Outline in X/Z, extrusion in Y; equipment may supply a hand-local transform.
        vertices = [Vector((x, y, z)) for y in (-depth/2, depth/2) for x, z in outline]
        if transform is not None: vertices = [transform @ p for p in vertices]
        n = len(outline)
        faces = [tuple(reversed(range(n))), tuple(range(n, 2*n))]
        faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
        return self.mesh(name, vertices, faces, bone, mat)


def build_unit(rig, recipe):
    kind = recipe['model']['type']
    meshes = base.build_unit(rig, legacy_recipe(recipe))
    palette = {'skin':(.48,.32,.22), 'steel':(.70,.67,.56), 'edge':(.84,.80,.66),
               'leather':(.065,.055,.047), 'wood':(.15,.095,.05), 'gold':(.49,.34,.13),
               'cargo':(.32,.23,.13), 'dark':(.025,.030,.035), 'cloth':(.54,.54,.54)}
    mats = {}
    for ob in meshes:
        for mat in ob.data.materials:
            name = mat.name.removeprefix('Bastion_').split('.')[0]
            if name in palette:
                color = palette[name];mat.diffuse_color = (*color,1)
                mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*color,1)
                mats[name] = mat
        ob['generatedBy'] = 'orders_cathedral_v1'
    # Workers did not previously use armor edge/dark materials on any mesh.
    for name,color in palette.items():
        if name not in mats:
            mats[name]=base.material('Orders_'+name,color,team=name=='cloth')
    b = Builder(rig);b.objects = meshes
    def remove(prefixes):
        for ob in list(b.objects):
            if any(ob.name.startswith(p) for p in prefixes):
                b.objects.remove(ob);bpy.data.objects.remove(ob, do_unlink=True)
    remove(('Helmet','WorkCap','ShieldRim','ShieldFace','ShieldBoss'))
    neck = rig.data.bones['Head'].head_local
    from mathutils import Matrix
    head = Matrix.Translation(neck + Vector((0,0,.04)))
    worker = kind in ('worker','worker_loaded')
    hood = [(-.155,0),(.155,0),(.155,.19),(0,.33),(-.155,.19)]
    b.prism('PointedHood' if worker else 'WedgeHelmet',hood,.28,'Head',mats['edge'],head)
    b.box('HoodOpening' if worker else 'VisorSlit',neck+Vector((0,-.148,.17)),
          (.155,.019,.14 if worker else .032),'Head',mats['dark'])
    if worker:
        b.box('Apron',(0,-.168,1.035),(.27,.03,.37),'spine_01',mats['cloth'])
        b.box('ToolPack',(0,.19,1.25),(.30,.13,.29),'spine_02',mats['wood'])
        for ob in b.objects:
            if ob.name.startswith('ToolHead'):
                right=rig.data.bones['hand_r'].matrix_local;inv=right.inverted()
                center=base.PALM+Vector((.38,0,0))
                for v in ob.data.vertices:
                    p=inv@v.co-center;p.x*=1.5;p.z*=2.0;v.co=right@(p+center)
        if kind=='worker_loaded' or recipe.get('model',{}).get('cargo'):
            remove(('CargoSack',))
            b.box('SquareCargo',(0,.235,1.25),(.42,.21,.38),'spine_02',mats['cargo'])
    elif kind=='crossbow':
        # Wide, flat shoulder cloth reads from above; nothing simulates loose fabric.
        b.prism('ShoulderMantle',[(-.29,1.27),(.29,1.27),(.20,1.46),(-.20,1.46)],.25,
                'spine_03',mats['cloth'],Matrix.Translation((0,-.015,0)))
    else:
        # A broader bevel-free blade survives the fixed overhead projection.
        remove(('SwordBlade',))
        right=rig.data.bones['hand_r'].matrix_local
        blade=[(.12,-.075),(.55,-.075),(.64,0),(.55,.075),(.12,.075)]
        vertices=[right@(base.PALM+Vector((x,y,z))) for z in (-.022,.022) for x,y in blade]
        faces=[(4,3,2,1,0),(5,6,7,8,9)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)]
        b.mesh('SwordBlade',vertices,faces,'hand_r',mats['edge'])
        # Kite geometry in hand-local XY, with the face on +Z like the fitted carry pose.
        hand=rig.data.bones['hand_l'].matrix_local
        outline=[(-.29,-.18),(.17,-.23),(.31,0),(.17,.23),(-.29,.18)]
        def shield(name,scale,z,mat):
            vertices=[hand@(base.PALM+Vector((x*scale,y*scale,zz))) for zz in (z,z+.025) for x,y in outline]
            faces=[(4,3,2,1,0),(5,6,7,8,9)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)]
            b.mesh(name,vertices,faces,'hand_l',mat)
        shield('KiteShieldRim',1,.055,mats['edge']);shield('KiteShieldTeam',.84,.083,mats['cloth'])
        b.box('ShieldHeraldBar',base.PALM+Vector((-.03,0,.114)),(.24,.055,.022),'hand_l',mats['gold'],hand)
        for x in (-.085,.085):
            b.box('SplitTabard',(x,-.16,.91),(.13,.03,.25),'pelvis',mats['cloth'])
    rig['ordersModel']=kind
    return b.objects


def correct_pose(rig, recipe, clip, phase):
    r=legacy_recipe(recipe)
    if clip=='death' and recipe['model']['type'] in ('worker','worker_loaded'):
        # Both rigid packs support the upper body during the source fall.
        r['model']['type']='worker_loaded'
    base.correct_pose(rig,r,clip,phase)
    if recipe['model']['type']=='footman' and clip in ('idle','move','attack'):
        torso=rig.pose.bones['spine_03'].matrix @ rig.data.bones['spine_03'].matrix_local.inverted()
        rotation=torso.to_quaternion().to_matrix()
        # Tilt the kite face upward 45 degrees and clear the torso silhouette.
        q=math.sqrt(.5)
        shield=rotation @ Matrix(((0,1,0),(-q,0,-q),(-q,0,q)))
        base._solve_arm(rig,'_l',torso@Vector((.43,-.22,1.12)),shield)
        # Ready -> windup -> contact (sample 3) -> follow-through -> ready.
        yaw,pitch=0,.35
        if clip=='attack':
            keys=[(0,0,.35),(.2,-1.05,.85),(.4,.15,.12),(.6,1.05,.12),(.8,.4,.25),(1,0,.35)]
            for a,b in zip(keys,keys[1:]):
                if a[0]<=phase<=b[0]:
                    t=(phase-a[0])/(b[0]-a[0]);t=t*t*(3-2*t)
                    yaw=a[1]+(b[1]-a[1])*t;pitch=a[2]+(b[2]-a[2])*t
                    break
        c,s=math.cos(pitch),math.sin(pitch)
        sword=rotation @ Matrix.Rotation(yaw,3,'Z') @ Matrix(((0,1,0),(-c,0,s),(s,0,c)))
        base._solve_arm(rig,'_r',torso@Vector((-.36,-.28,1.05)),sword)
    if clip=='death' and recipe['model']['type'] in ('worker','worker_loaded'):
        t=max(0,min(1,(phase-.25)/.23));t=t*t*(3-2*t)
        spine=rig.pose.bones['spine_01'];m=spine.matrix.copy()
        tilted=(Matrix.Rotation(.23*t,3,'X')@m.to_3x3()).to_4x4();tilted.translation=m.translation
        spine.matrix=tilted;bpy.context.view_layer.update()


def grip_report(rig):
    return base.grip_report(rig)
