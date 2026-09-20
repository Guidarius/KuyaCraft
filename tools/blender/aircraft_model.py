"""Original Megacorp pressure-hull aircraft. Coordinates are Blender units, nose -Y.

Rigid, named editable modules; team color is an upper-shell material assignment,
never a colored window. This generator does not touch the saved humanoid library.
"""
import math
import bpy


def material(name, color, roughness=.7, metallic=0, team=False):
    mat = bpy.data.materials.new('Megacorp_' + name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    node = mat.node_tree.nodes.get('Principled BSDF')
    node.inputs['Base Color'].default_value = (*color, 1)
    node.inputs['Roughness'].default_value = roughness
    node.inputs['Metallic'].default_value = metallic
    mat['team'] = team
    return mat


class Builder:
    def __init__(self, root):
        self.root, self.meshes = root, []
        self.graphite = material('Graphite', (.105, .125, .15))
        self.team = material('TeamShell', (.56, .56, .56), team=True)
        self.rim = material('Aluminum', (.43, .46, .48), .4, .25)
        self.dark = material('RubberAndExhaust', (.017, .021, .027), .9)
        self.glass = material('SmokedGlass', (.055, .044, .029), .2, .15)

    def lathe(self, name, profile, center, radii=(1, 1), materials=None,
              team_rings=(), sides=12, parent=None, caps=True):
        """Closed profile around Y. Profile endpoints can be poles or annular lips."""
        vertices = [(radii[0]*r*math.cos(2*math.pi*i/sides), y,
                     radii[1]*r*math.sin(2*math.pi*i/sides))
                    for y, r in profile for i in range(sides)]
        faces = []
        for j in range(len(profile)-1):
            for i in range(sides):
                k = (i+1) % sides
                faces.append((j*sides+i, (j+1)*sides+i, (j+1)*sides+k, j*sides+k))
        if caps:
            faces += [tuple(range(sides)), tuple((len(profile)-1)*sides+i for i in reversed(range(sides)))]
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(vertices, [], faces); mesh.update()
        ob = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(ob)
        ob.parent = parent or self.root; ob.location = center
        for mat in materials or [self.graphite]: mesh.materials.append(mat)
        if team_rings:
            for j in team_rings:
                for i in range(sides):
                    # One uninterrupted crown across the upper half of the hull.
                    if math.sin(2*math.pi*(i+.5)/sides) > .08:
                        mesh.polygons[j*sides+i].material_index = 1
        ob['generatedBy'] = 'megacorp_pressure_hulls_v1'
        self.meshes.append(ob)
        return ob

    def capsule(self, name, center, length, width, height, team=True):
        h = length/2
        return self.lathe(name, [(-h, .05), (-h*.88, .60), (-h*.60, .94),
                          (-h*.28, 1), (h*.35, 1), (h*.76, .85), (h*.96, .42), (h, .05)],
                          center, (width/2, height/2), [self.graphite, self.team],
                          range(2, 6) if team else ())

    def port(self, name, center, radius, depth, glass=False, parent=None):
        # Ring lip, recessed dark face: no accidentally forward-facing engine holes.
        ob = self.lathe(name+'Rim', [(-depth, 1), (0, 1), (0, .76), (-depth, .76), (-depth,1)],
                       center, (radius, radius), [self.rim], parent=parent, caps=False)
        self.lathe(name+'Inset', [(-depth*.45, .76), (-depth*.46, .01)],
                   center, (radius, radius), [self.glass if glass else self.dark], parent=parent)
        return ob


def build(recipe):
    root = bpy.data.objects.new('AircraftMotion', None)
    bpy.context.scene.collection.objects.link(root)
    b = Builder(root)
    recoil = None
    if recipe['unitId'] == 'command_blimp':
        b.lathe('PressureHull', [(-.39,.76), (-.23,.97), (.02,1), (.30,.94), (.49,.66), (.57,.10)],
                (0,0,.33), (.35,.28), [b.graphite,b.team], range(4))
        b.lathe('ObservationCollar', [(-.40,.81),(-.36,.84),(-.34,.78)],
                (0,0,.33), (.35,.28), [b.rim])
        b.lathe('BubbleVisor', [(-.535,.03),(-.515,.34),(-.47,.62),(-.397,.77)],
                (0,0,.33), (.35,.28), [b.glass])
        b.capsule('BellyGondola', (0,.02,.08), .37,.32,.16, False)
        for side in (-1,1):
            b.capsule('Thruster'+str(side), (side*.335,.33,.24), .32,.20,.20, False)
            # A reversed port puts the opening on +Y, the rear.
            port_root = bpy.data.objects.new('RearThrusterSocket'+str(side), None)
            bpy.context.scene.collection.objects.link(port_root); port_root.parent=root
            port_root.location=(side*.335,.494,.24);port_root.rotation_euler.z=math.pi
            b.port('Exhaust'+str(side),(0,0,0),.084,.026,parent=port_root)
        puck=b.lathe('RelayPuck',[(-.035,1),(.008,1),(.024,.8)],(0,.25,.60),(.09,.09),[b.rim])
        puck.rotation_euler.x=math.pi/2
    elif recipe['unitId'] == 'battleship':
        b.capsule('CenterPressureHull', (0,0,.29), 1.03,.48,.45)
        for side in (-1,1):
            pod=b.capsule('EngineNacelle'+str(side), (side*.45,0,.29), 1.25,.34,.39)
            # Short crossbeam behind the bow leaves the two forward channels clear.
            mount=b.capsule('ShoulderMount'+str(side),(side*.26,.10,.26),.28,.15,.15,False)
            mount.rotation_euler.z=math.pi/2
            socket=bpy.data.objects.new('RearEngineSocket'+str(side),None)
            bpy.context.scene.collection.objects.link(socket);socket.parent=root
            socket.location=(side*.45,.612,.29);socket.rotation_euler.z=math.pi
            b.port('EngineExhaust'+str(side),(0,0,0),.115,.03,parent=socket)
        b.port('BridgePorthole',(0,-.47,.355),.067,.024,glass=True)
        recoil=bpy.data.objects.new('CannonRecoil',None)
        bpy.context.scene.collection.objects.link(recoil);recoil.parent=root
        recoil.location=(0,-.43,.17)
        b.lathe('CannonBarrel',[(-.235,.8),(-.17,.86),(0,1)],(0,0,0),(.087,.087),[b.graphite],parent=recoil)
        b.port('CannonMuzzle',(0,-.235,0),.084,.04,parent=recoil)
    else:
        raise ValueError('Unknown aircraft: '+recipe['unitId'])
    return root,b.meshes,recoil


def pose(root, recoil, clip, sample, spec):
    t=sample/(spec['samples'] if spec['loop'] else max(1,spec['samples']-1))
    root.location=(0,0,0);root.rotation_euler=(0,0,0)
    if recoil: recoil.location.y=-.43
    if clip in ('idle','move'):
        root.location.z=.008*math.sin(t*math.tau)
        root.rotation_euler.x=math.radians(-2 if clip=='move' else 0)
    elif clip=='attack' and recoil:
        contact=(spec.get('contactFrame',1)-1)/max(1,spec['samples']-1)
        # A held barrel before contact; recoil and recovery are cosmetic only.
        recover=max(0,(t-contact)/max(.001,1-contact))
        recoil.location.y += .085*(1-recover) if t>=contact else 0
    elif clip=='death':
        root.rotation_euler.y=math.radians(spec.get('rollDegrees',22))*t
        root.rotation_euler.x=math.radians(spec.get('pitchDegrees',-8))*t
        root.location.z=spec.get('drop',-.045)*t
