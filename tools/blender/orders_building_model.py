"""Footprint-contained cathedral modules, with keyed construction visibility."""
import bpy
from building_model import Builder as Base
from aircraft_model import material

IDS = ('keep','depot','barracks','sanctum')


class Builder(Base):
    def __init__(self, root):
        super().__init__(root)
        self.ivory=material('OrdersStone',(.67,.64,.54))
        self.base=material('OrdersIron',(.065,.071,.079))
        self.wood=material('OrdersTimber',(.14,.085,.041))
        self.brass=material('OrdersBrass',(.48,.32,.12))
        self.light=material('OrdersRelic',(.90,.70,.30))

    def stage(self, ob, first=2, last=4):
        ob['firstStage']=first;ob['lastStage']=last;ob['generatedBy']='orders_cathedral_v1'
        return ob

    def block(self,name,pos,dims,mat=None,first=2,last=4):
        return self.stage(self.box(name,pos,dims,mat,bevel=.012),first,last)

    def roof(self,name,x,y,w,d,z,h):
        for side in (-1,1):
            # Separate halves: one roof plane is present in stage two.
            vertices=[]
            for y0 in (y-d/2,y+d/2):vertices += [(x,y0,z),(x+side*w/2,y0,z),(x,y0,z+h)]
            ob=self.mesh(name+('Left' if side<0 else 'Right'),vertices,
                         [(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)],[self.team])
            self.stage(ob,2 if side<0 else 3)
        self.block(name+'Ridge',(x,y,z+h),(.022,d,.024),self.brass,4)

    def arch(self,name,x,y,z,w,h,mat=None):
        points=[(-w/2,0),(w/2,0),(w/2,h*.65),(0,h),(-w/2,h*.65)]
        vertices=[(x+a,y+b,z+c) for b in (-.009,.009) for a,c in points]
        ob=self.mesh(name,vertices,[(4,3,2,1,0),(5,6,7,8,9)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)],[mat or self.dark])
        return self.stage(ob,2)


def build(recipe):
    root=bpy.data.objects.new('OrdersBuildingAssembly',None);bpy.context.scene.collection.objects.link(root)
    b=Builder(root);kind=recipe['unitId']
    b.block('Foundation',(0,0,.025),(.94,.94,.05),b.base,1)
    for x in (-.40,.40):
        b.block('LowWall',(x,0,.09),(.10,.81,.13),first=1,last=1)
    if kind=='keep':
        b.block('GateHall',(0,.045,.245),(.58,.78,.43))
        b.roof('Nave',0,.045,.64,.80,.46,.29)
        for x,h in ((-.34,.53),(.34,.66)):
            b.block('GateTower',(x,-.20,h/2),(.23,.38,h))
            b.roof('TowerCap',x,-.20,.27,.42,h,.16)
            b.arch('TowerWindow',x,-.397,h-.19,.085,.14)
            b.block('TowerBanner',(x,-.400,h*.40),(.12,.017,.19),b.team,4)
        b.arch('Gate',0,-.352,.05,.31,.35,b.wood)
    elif kind=='depot':
        b.block('Storehouse',(-.055,.035,.20),(.58,.73,.34))
        b.roof('StoreRoof',-.055,.035,.64,.78,.37,.28)
        b.arch('StoreDoors',-.055,-.341,.05,.32,.28,b.wood)
        for y in (-.24,.12):
            b.block('SupplyCrate',(.335,y,.13),(.20,.26,.21),b.wood,2)
            b.block('CrateBand',(.335,y,.238),(.025,.27,.016),b.brass,4)
    elif kind=='barracks':
        for x in (-.22,.22):
            b.block('ChapterHall',(x,.035,.21),(.40,.77,.37))
            b.roof('ChapterRoof',x,.035,.43,.82,.40,.27)
            b.arch('TroopEntrance',x,-.356,.05,.25,.28,b.wood)
        b.block('ChapterBanner',(0,-.37,.29),(.12,.025,.24),b.team,4)
    elif kind=='sanctum':
        b.block('Chapel',(0,0,.19),(.72,.70,.33))
        b.roof('ChapelRoof',0,0,.80,.76,.355,.24)
        b.block('CentralTower',(0,.055,.51),(.29,.32,.32))
        # Four triangular roof faces; faceted single spire, no round dome.
        vertices=[(-.19,-.145,.66),(.19,-.145,.66),(.19,.245,.66),(-.19,.245,.66),(0,.055,.94)]
        b.stage(b.mesh('SanctumSpire',vertices,[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(3,2,1,0)],[b.team]),3)
        b.arch('RelicWindow',0,-.112,.45,.17,.20,b.light)
        b.arch('ChapelDoor',0,-.36,.05,.23,.26,b.wood)
        b.block('SpireTip',(0,.055,.95),(.027,.027,.08),b.brass,4)
    else:raise ValueError('Unknown Orders building '+kind)
    for x in (-.43,.43):
        for y in (-.30,.27):
            b.block('Buttress',(x,y,.17),(.095,.13,.29),first=2)
    # Scaffolding remains within the occupied square and vanishes on completion.
    for x in (-.455,.455):
        for y in (-.37,.37):b.block('ScaffoldPost',(x,y,.26),(.026,.026,.48),b.wood,1,3)
        b.block('ScaffoldRail',(x,0,.39),(.026,.79,.035),b.wood,1,3)
    root.scale=(recipe['footprintCells']*26/64,)*3;root['footprintCells']=recipe['footprintCells']
    for frame in range(1,5):
        for ob in b.meshes:
            visible=ob['firstStage']<=frame<=ob['lastStage']
            ob.hide_render=not visible;ob.hide_viewport=not visible
            ob.keyframe_insert('hide_render',frame=frame);ob.keyframe_insert('hide_viewport',frame=frame)
    bpy.context.scene.frame_set(4)
    return root,b.meshes
