"""Rounded Megacorp capsule: heat shield, pressure shell, rigid twin doors, three fins."""
import math
import bpy
from building_model import Builder


def build(recipe):
    root=bpy.data.objects.new('DropPodAssembly',None);bpy.context.scene.collection.objects.link(root)
    b=Builder(root)
    b.lathe('HeatShield',(0,0,0),[(0,.27),(.035,.36),(.095,.38),(.13,.33)],b.base)
    b.lathe('LowerCollar',(0,0,0),[(.115,.33),(.18,.35),(.21,.33)])
    b.lathe('DarkInterior',(0,.035,.15),[(0,.245),(.53,.245)],b.dark)
    # Three-quarter pressure wall: the forward quarter is a genuine door opening.
    verts=[];faces=[]
    for z,r in ((.18,.33),(.66,.33),(.75,.29)):
        verts += [(r*math.cos(math.radians(-45+i*22.5)),r*math.sin(math.radians(-45+i*22.5)),z) for i in range(13)]
    for j in range(2):
        for i in range(12):faces.append((j*13+i,j*13+i+1,(j+1)*13+i+1,(j+1)*13+i))
    hull=b.mesh('PressureShell',verts,faces,[b.team,b.ivory])
    for p in hull.data.polygons:
        if p.index>=12:p.material_index=1
    b.lathe('RoundedCap',(0,0,0),[(.70,.31),(.78,.31),(.86,.24),(.92,.13),(.93,.035)],bands=(1,2))
    b.lathe('CapButton',(0,0,.928),[(0,.052),(.016,.045)],b.base)
    for angle in (math.pi/2,math.pi*7/6,math.pi*11/6):
        pivot=b.empty('LandingFin',(0,0,0));pivot.rotation_euler.z=angle-math.pi/2
        b.box('FinSole',(0,.395,.04),(.20,.20,.08),b.base,.025,parent=pivot)
        b.box('FinShoulder',(0,.355,.225),(.135,.20,.34),b.ivory,.04,parent=pivot)
        b.box('FinTeamPatch',(0,.405,.23),(.085,.025,.19),b.team,.015,parent=pivot)
    doors=[]
    for sign in (-1,1):
        pivot=b.empty('DoorHingeLeft' if sign<0 else 'DoorHingeRight',(sign*.235,-.255,.425))
        b.box('DoorShell',(-sign*.115,-.040,0),(.23,.075,.43),b.ivory,.035,parent=pivot)
        b.box('DoorTeamPanel',(-sign*.115,-.080,.005),(.17,.012,.32),b.team,.024,parent=pivot)
        b.box('DoorGrip',(-sign*.185,-.090,.015),(.025,.017,.105),b.base,.006,parent=pivot)
        doors.append((pivot,sign))
    port=b.empty('PortholeMount',(0,-.282,.77));port.rotation_euler.x=math.pi/2
    b.lathe('PortholeRim',(0,0,0),[(0,.064),(.020,.064),(.027,.047)],b.ivory,parent=port)
    b.lathe('PortholeGlass',(0,0,.027),[(0,.047),(.004,.043)],b.glass,parent=port)
    root.scale=(recipe['visualDiameterCells']*26/64,)*3
    root['presentationOnly']=True
    for pivot,sign in doors:
        for i in range(recipe['clips']['deploy']['samples']):
            pivot.rotation_euler.z=sign*math.radians(105)*i/(recipe['clips']['deploy']['samples']-1)
            pivot.keyframe_insert('rotation_euler',frame=i+1)
        pivot.animation_data.action.name='RTS_drop_pod_deploy_'+pivot.name
    return root,b.meshes,doors
