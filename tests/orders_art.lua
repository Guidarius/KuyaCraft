local F=require('src.asset_frames')
local T={}
function T.register(test)
 test('unit','Orders dedicated sprite mappings preserve legacy fixtures',function()
  for _,id in ipairs({'footman','gryphon','reliquary','crossbow'}) do assert(F.assetId({kind=id,category='unit'})==id) end
  for _,id in ipairs({'keep','depot','barracks','sanctum'}) do assert(F.assetId({kind=id,category='building'})==id) end
  assert(F.assetId({kind='shield'})=='shieldguard' and F.assetId({kind='warden'})=='warden')
  assert(F.assetId({kind='worker',carrying=0})=='worker' and F.assetId({kind='worker',carrying=1})=='worker_loaded')
 end)
 test('unit','construction frames clamp and advance at thirds; legacy fallback remains',function()
  local m={clips={construction={frames={S={7,8,9}}}}}
  for _,case in ipairs({{301,7},{300,7},{201,7},{200,8},{101,8},{100,9},{1,9}}) do assert(F.construction(m,case[1],300)==case[2]) end
  assert(F.construction(m,0,300)==nil and F.construction(m,-1,300)==nil)
  assert(F.construction(m,10,0)==nil and F.construction({clips={}},10,300)==nil)
 end)
 test('unit','mounted stride and neutral shrine clip use normal read-only playback',function()
  local function clip(loop,n) local f={};for i=1,n do f[i]=i end;return {durationMs=1000,loop=loop,contactFrame=1,frames={S=f,E=f}} end
  local m={referenceStride={distance=.5},clips={idle=clip(true,4),move=clip(true,8),attack=clip(false,1),death=clip(false,6)}}
  local e={id=1,kind='gryphon',x=128,y=0,alive=true};local before=require('src.sim.codec').encode(e)
  local _,state,name=F.select(m,e,{x=64,y=0},2,{direction='E'})
  assert(name=='move' and state.moveMs==500)
  F.select(m,e,{x=64,y=0},2,state);assert(state.moveMs==500,'redraw advanced movement twice')
  assert(require('src.sim.codec').encode(e)==before)
  local _,_,idle=F.select(m,{kind='reliquary',x=0,y=0},nil,30,{})
  assert(idle=='idle','neutral compatibility attack must not create attacks')
 end)
 test('simulation','Orders art fixture retains safe gameplay placements',function() require('tests.orders_lab').check() end)
end
return T
