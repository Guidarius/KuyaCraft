"""Original landed Megacorp modules. Normalized square footprint, front -Y, Z up.

Named rigid parts and neutral team material; no external meshes or humanoid rig.
The exporter scales the complete assembly to the recipe's existing navigation cells.
"""
import math
import bpy
from aircraft_model import material

IDS = ('orbital_command', 'mc_barracks', 'requisition_office', 'med_bay',
       'armory', 'orbital_relay', 'substrate_rig', 'charge_rig', 'bunker')


class Builder:
    def __init__(self, root):
        self.root, self.meshes, self.moving = root, [], []
        self.team = material('BuildingTeamShell', (.50, .50, .50), team=True)
        self.ivory = material('BuildingIvory', (.66, .63, .54))
        self.base = material('BuildingGraphite', (.10, .12, .14))
        self.dark = material('BuildingRecess', (.018, .029, .042))
        self.glass = material('BuildingGlass', (.038, .076, .105), .3, .1)
        self.light = material('BuildingLamp', (.45, .70, .72))

    def empty(self, name, pos=(0, 0, 0), parent=None):
        ob = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(ob)
        ob.parent = parent or self.root; ob.location = pos
        return ob

    def mesh(self, name, vertices, faces, mats, parent=None):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(vertices, [], faces); mesh.update()
        ob = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(ob); ob.parent = parent or self.root
        for mat in mats: mesh.materials.append(mat)
        self.meshes.append(ob); ob['generatedBy'] = 'megacorp_buildings_v1'
        return ob

    def box(self, name, pos, dims, mat=None, bevel=.035, parent=None):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
        ob = bpy.context.object; ob.name = name
        ob.dimensions = dims
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        ob.parent = parent or self.root; ob.location = pos
        if bevel:
            mod = ob.modifiers.new('Simple rounded shell', 'BEVEL')
            mod.width = min(bevel, min(dims)*.4); mod.segments = 2
            bpy.ops.object.modifier_apply(modifier=mod.name)
        ob.data.materials.append(mat or self.ivory)
        self.meshes.append(ob); ob['generatedBy'] = 'megacorp_buildings_v1'
        return ob

    def lathe(self, name, pos, profile, mat=None, sides=12, bands=None, parent=None):
        vertices = [(r*math.cos((i+.5)*math.tau/sides), r*math.sin((i+.5)*math.tau/sides), z)
                    for z, r in profile for i in range(sides)]
        faces = []
        for j in range(len(profile)-1):
            for i in range(sides):
                k=(i+1)%sides
                faces.append((j*sides+i, j*sides+k, (j+1)*sides+k, (j+1)*sides+i))
        faces += [tuple(reversed(range(sides))), tuple((len(profile)-1)*sides+i for i in range(sides))]
        ob = self.mesh(name, vertices, faces, [mat or self.ivory, self.team], parent)
        ob.location = pos
        for j in bands or ():
            for i in range(sides): ob.data.polygons[j*sides+i].material_index = 1
        if len(profile)-2 in (bands or ()): ob.data.polygons[-1].material_index = 1
        return ob

    def vault(self, name, pos, width, length, height, team=True):
        # Half-round pressure shell with a flattened belly; bands run along its length.
        rings = [(-length/2, .82), (-length*.40, 1), (length*.40, 1), (length/2, .82)]
        sides=11
        vertices=[(width/2*scale*math.cos(i*math.pi/(sides-1)), y,
                   height*scale*math.sin(i*math.pi/(sides-1))) for y,scale in rings for i in range(sides)]
        faces=[]
        for j in range(3):
            for i in range(sides-1):
                faces.append((j*sides+i,(j+1)*sides+i,(j+1)*sides+i+1,j*sides+i+1))
        faces += [tuple(range(sides)),tuple(3*sides+i for i in reversed(range(sides)))]
        faces.append((0, sides-1, 4*sides-1, 3*sides))
        ob=self.mesh(name,vertices,faces,[self.ivory,self.team]);ob.location=pos
        if team:
            for i in range(2,8): ob.data.polygons[10+i].material_index=1
        return ob

    def feet(self, span=.38, size=.20):
        for x in (-span,span):
            for y in (-span,span):
                self.box('LandingFoot', (x,y,.045), (size,size,.09), self.base, .025)

    def door(self, y, z=.14, width=.22, height=.24, x=0):
        self.box('DoorFrame',(x,y,z),(width+.045,.035,height+.035),self.ivory,.018)
        self.box('RecessedDoor',(x,y-.020,z),(width,.014,height),self.dark,.022)
        self.box('DoorLamp',(x,y-.029,z+height*.28),(width*.45,.008,.013),self.light,.003)


def build(recipe):
    root=bpy.data.objects.new('BuildingAssembly',None);bpy.context.scene.collection.objects.link(root)
    b=Builder(root);kind=recipe['unitId']
    if kind == 'orbital_command':
        b.lathe('LandedSkirt',(0,0,0),[(0,.35),(.045,.43),(.10,.44),(.13,.40)],b.base,sides=16)
        b.lathe('VisorBelt',(0,0,0),[(.12,.395),(.27,.395)],b.glass,sides=16)
        b.lathe('CommandRoof',(0,0,0),[(.265,.40),(.30,.445),(.345,.43),(.44,.32),(.49,.14),(.50,.06)],sides=16,bands=(2,))
        b.lathe('RoofCap',(0,0,.495),[(0,.082),(.018,.075)],b.base)
        for angle in (-math.pi/4, math.pi/4, math.pi):
            x,y=.39*math.cos(angle),.39*math.sin(angle)
            ob=b.box('LandingButtress',(x,y,.11),(.20,.22,.22),bevel=.06);ob.rotation_euler.z=angle
            ob=b.box('ButtressSole',(x,y,.03),(.22,.24,.06),b.base);ob.rotation_euler.z=angle
        b.lathe('RadarStem',(.18,.22,.40),[(0,.052),(.13,.052)],b.base)
        b.lathe('RadarPuck',(.18,.22,.53),[(0,.10),(.04,.10),(.06,.076)],bands=(1,))
    elif kind == 'mc_barracks':
        b.box('HangarFoundation',(0,0,.06),(.92,.90,.12),b.base);b.feet()
        for x in (-.235,.235):
            b.vault('PressureHangar',(x,.005,.12),.43,.85,.35)
            b.door(-.435,.22,.16,.19,x)
        b.box('CenterLink',(0,.02,.17),(.18,.59,.20),b.base)
        b.box('LinkRoof',(0,.10,.29),(.17,.26,.07),b.ivory)
        b.door(-.38,.18,.23,.23)
    elif kind == 'requisition_office':
        b.box('CargoFoundation',(0,0,.045),(.92,.92,.09),b.base);b.feet()
        b.box('DispatchHatch',(0,0,.10),(.40,.43,.05),b.dark)
        b.box('HatchPanel',(0,0,.127),(.32,.35,.012),b.base,.02)
        for x in (-.30,.30):
            for y in (-.30,.30):
                b.box('CargoPod',(x,y,.22),(.34,.34,.34),bevel=.075)
                b.box('PodTeamCap',(x,y,.397),(.255,.255,.024),b.team,.04)
        for y in (-.29,.29): b.box('HatchBrace',(0,y,.17),(.34,.11,.16),b.base)
        b.door(-.36,.16,.23,.16)
    elif kind == 'med_bay':
        b.box('MedicalFoundation',(0,0,.04),(.91,.79,.08),b.base);b.feet(.34,.15)
        b.vault('MedicalShell',(0,0,.11),.66,.78,.40)
        b.vault('MedicalRoofBand',(0,-.03,.12),.68,.15,.40,False)
        for x in (-.405,.405):
            tank=b.lathe('MedicalCapsule',(x,.035,.24),[(-.29,.02),(-.26,.07),(-.20,.087),(.20,.087),(.26,.07),(.29,.02)])
            tank.rotation_euler.x=math.pi/2
            collar=b.lathe('CapsuleMount',(x,.03,.24),[(-.075,.09),(.075,.09)],b.base)
            collar.rotation_euler.x=math.pi/2
        b.door(-.404,.22,.24,.29)
    elif kind == 'armory':
        b.box('VaultFoundation',(0,0,.045),(.92,.86,.09),b.base);b.feet(.35,.19)
        b.box('ArmoredVault',(0,-.015,.23),(.80,.74,.37),bevel=.095)
        b.box('VaultTeamRoof',(0,-.08,.421),(.51,.43,.025),b.team,.045)
        for x in (-.34,.34): b.box('ArmoredCheek',(x,-.07,.245),(.15,.70,.36),bevel=.055)
        barrel=b.lathe('RearArmorDrum',(0,.24,.44),[(-.42,.105),(-.35,.125),(.35,.125),(.42,.105)],b.base)
        barrel.rotation_euler.y=math.pi/2
        for x in (-.30,.30):
            ring=b.lathe('DrumCollar',(x,.24,.44),[(-.055,.132),(.055,.132)])
            ring.rotation_euler.y=math.pi/2
        b.door(-.405,.19,.40,.25)
    elif kind == 'orbital_relay':
        b.lathe('RelaySkirt',(0,0,0),[(0,.37),(.065,.46),(.12,.41)],b.base)
        b.lathe('RelayPedestal',(0,0,.10),[(0,.41),(.065,.40),(.16,.29),(.17,.18)],bands=(1,))
        b.lathe('Mast',(0,0,.26),[(0,.11),(.24,.11)],b.base)
        pivot=b.empty('DishAzimuth',(0,0,.48));b.moving.append((pivot,'dish'))
        tilt=b.empty('DishTilt',parent=pivot);tilt.rotation_euler.x=math.radians(32)
        # A thick closed concave bowl: outer shell up to rim, inner bowl back to hub.
        dish=b.lathe('DishBowl',(0,0,0),[(-.075,.09),(-.05,.22),(.035,.36),(.085,.385),
                        (.115,.38),(.09,.34),(.005,.20),(-.025,.06)],sides=12,parent=tilt,bands=(1,2))
        b.lathe('DishReceiver',(0,0,-.025),[(0,.055),(.08,.04)],b.base,parent=tilt)
        b.feet(.30,.18)
    elif kind == 'substrate_rig':
        b.lathe('PumpCore',(0,0,0),[(0,.20),(.08,.25),(.16,.20),(.37,.17)],b.base)
        for angle in (math.pi/2,math.pi*7/6,math.pi*11/6):
            x,y=.30*math.cos(angle),.30*math.sin(angle)
            ob=b.box('PumpFoot',(x,y,.07),(.24,.28,.14),b.base);ob.rotation_euler.z=angle
            ob=b.box('PumpShoulder',(x,y,.18),(.20,.24,.19),bevel=.055);ob.rotation_euler.z=angle
            ob=b.box('ShoulderTeamPanel',(x,y,.279),(.13,.15,.018),b.team,.015);ob.rotation_euler.z=angle
        motion=b.empty('PumpStroke',(0,0,.29));b.moving.append((motion,'pump'))
        b.lathe('PumpPiston',(0,0,0),[(0,.09),(.24,.09)],b.ivory,parent=motion)
        b.lathe('PumpCap',(0,0,0),[(.18,.14),(.37,.14),(.40,.11)],b.team,parent=motion)
    elif kind == 'charge_rig':
        b.box('CapacitorBase',(0,0,.045),(.94,.75,.09),b.base);b.feet(.32,.20)
        for x in (-.255,.255):
            b.lathe('CapacitorTank',(x,0,.07),[(0,.19),(.055,.23),(.12,.23),(.47,.23),(.56,.20),(.63,.11),(.64,.055)],bands=(2,))
            b.lathe('TankCap',(x,0,.714),[(0,.061),(.018,.057)],b.base)
        b.box('CapacitorBridge',(0,.03,.21),(.23,.42,.25),b.base)
        b.box('BridgePanel',(0,-.19,.22),(.14,.025,.14),b.ivory,.015)
    elif kind == 'bunker':
        b.lathe('BunkerSkirt',(0,0,0),[(0,.43),(.06,.49),(.10,.47)],b.base,sides=8)
        b.lathe('ArmoredPillbox',(0,0,0),[(.075,.46),(.27,.46),(.35,.39),(.355,.02)],sides=8,bands=(2,))
        for angle in (-math.pi/2,-math.pi/4,0,math.pi/4,math.pi/2,math.pi,math.pi*3/4,math.pi*5/4):
            x,y=.429*math.cos(angle),.429*math.sin(angle)
            port=b.box('FiringSlot',(x,y,.19),(.24,.018,.065),b.dark,.009)
            port.rotation_euler.z=angle+math.pi/2
    else: raise ValueError('Unknown building '+kind)
    # Each authored part remains editable. The complete footprint is never auto-fit.
    # Shape revisions therefore cannot silently alter world scale or collision alignment.
    root.scale=(recipe['footprintCells']*26/64,)*3
    root['footprintCells']=recipe['footprintCells'];root['front']='-Y'
    for ob,kind in b.moving:
        base=ob.location.copy()
        count=recipe['clips']['idle']['samples']
        for i in range(count+1):
            t=i/count
            if kind=='pump': ob.location.z=base.z+.035*math.sin(t*math.tau)
            else: ob.rotation_euler.z=math.radians(18)*math.sin(t*math.tau)
            ob.keyframe_insert('location',frame=i+1);ob.keyframe_insert('rotation_euler',frame=i+1)
        ob.animation_data.action.name='RTS_'+recipe['unitId']+'_idle_'+kind
    return root,b.meshes,b.moving
