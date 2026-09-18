-- Tooltips, the Warcraft 3 way. A command card button answers at once, in a fixed place just above
-- the card, so a player sweeping the pointer across the card reads each cost without the panel
-- chasing the cursor. Everything else -- the resource bar, the hero panel, a unit in the world --
-- waits a moment, so a pointer passing over does not flicker, and then sits beside the pointer.
-- Once a tooltip has been shown, the next one within a short grace shows at once, as a menu does.
--
-- A tooltip is a spec:
--   title    the name, in gold
--   key      the hotkey, drawn at the right of the title
--   subtitle one line under the title, for whose it is ('Enemy', 'Tier 2')
--   subtitleColor
--   reason   why it cannot be used now, in red, above the description
--   status   a state that is not a failure ('Learned'), in green
--   lines    description text, each a string or {text, color}
--   stats    short facts ('HP 420'), joined on one row
--   costs    from Actions.costs; short ones red with what you have
--   anchor   'card' to sit above the command card instead of beside the pointer
-- Presentation only: nothing here reads anything a view does not carry, or writes anywhere.
local T={}
T.DELAY=0.35
T.GRACE=0.4
T.MAX_WIDTH=300
T.MIN_WIDTH=150
T.PAD=9
T.COLORS={
 title={.97,.88,.6},key={1,.8,.3},body={.83,.86,.81},dim={.62,.66,.62},reason={1,.45,.36},
 status={.56,.9,.6},cost={.9,.84,.56},short={1,.38,.32},own={.45,.8,1},enemy={1,.45,.38},neutral={.95,.78,.38},
 panel={.035,.05,.065,.97},edge={.55,.46,.27,.9},
}
local COST_NAMES={gold='gold',food='food',mana='mana',xp='XP'}
T.OWNER_LABELS={own='Yours',enemy='Enemy',neutral='Neutral'}
-- What a node is called, by the resource it holds.
T.RESOURCE_NAMES={gold='Gold mine',substrate='Substrate patch',charge='Charge geyser'}
-- What an own unit is doing, in words. Orders not listed (stop, idle) say nothing.
T.DOING={move='Moving',attack='Attacking',attack_move='Attack-moving',patrol='Patrolling',hold='Holding position',
 build='Building',follow='Following',cast='Casting'}

-- The spec for a widget. A button whose `tip` is a table already is a spec; otherwise one is made
-- from its label, reason, tip text and command details.
function T.fromWidget(b)
 if type(b.tip)=='table' then
  local spec=b.tip
  if b.reason and not spec.reason then spec.reason=b.reason end
  return spec
 end
 local d=b.details or {}
 local spec={title=d.title or b.title or b.label,key=d.key,costs=d.costs,stats=d.stats,subtitle=d.badge and ('Tier '..d.badge:sub(2)) or nil,anchor=b.anchor}
 -- A learned choice is not an error, so it is not coloured as one.
 if d.status=='Learned' then spec.status='Learned'
 elseif b.reason then spec.reason=b.reason end
 if d.lines then spec.lines=d.lines elseif b.tip and b.tip~='' then spec.lines={b.tip} end
 return spec
end

local function ownerOf(app,e)
 if e.owner==app.player then return 'own' elseif e.owner==0 then return 'neutral' end
 return 'enemy'
end
-- What a player learns by resting the pointer on something in the world: what it is, whose it is,
-- and how it is doing. Only fields a view carries for that entity, so fog and enemy privacy hold.
function T.entity(app,e)
 local C=app.content
 local d=C.units[e.kind] or C.buildings[e.kind]
 local side=ownerOf(app,e)
 local spec={subtitle=T.OWNER_LABELS[side],subtitleColor=T.COLORS[side],lines={},stats={}}
 if e.category=='node' then
  spec.title=T.RESOURCE_NAMES[e.resource] or 'Resource'
  spec.subtitle=nil
  spec.lines[1]=(e.amount or 0)..' '..tostring(e.resource)..' remaining'
  spec.lines[2]={'Workers harvest it, one at a time per patch.',T.COLORS.dim}
  return spec
 end
 spec.title=d and d.label or e.kind
 if d and d.hero and e.xp then local level=0;for i,t in ipairs(C.rules.xpThresholds) do if e.xp>=t then level=i end end;spec.title=spec.title..'  (level '..level..')' end
 spec.stats[#spec.stats+1]='HP '..math.max(0,e.hp)..' / '..e.maxHp
 if e.maxMana then spec.stats[#spec.stats+1]='Mana '..(e.mana or 0)..' / '..e.maxMana end
 if not e.alive then spec.reason=e.category=='building' and 'Destroyed' or 'Dead'
 elseif (e.remaining or 0)>0 and d and d.buildTicks and d.buildTicks>0 then
  local done=math.floor(100*(1-e.remaining/d.buildTicks))
  spec.lines[#spec.lines+1]=e.stalled and {'Construction stopped at '..done..'%',T.COLORS.reason} or 'Under construction, '..done..'%'
 elseif side=='own' and e.category=='unit' then
  local doing=e.blockedReason or (e.order and e.order.kind)
  if e.blockedReason then spec.lines[#spec.lines+1]={e.blockedReason,T.COLORS.reason}
  elseif doing and T.DOING[doing] then spec.lines[#spec.lines+1]=T.DOING[doing] end
 end
 if side=='own' and e.queue and #e.queue>0 then
  local head=C.units[e.queue[1].kind]
  spec.lines[#spec.lines+1]='Training '..(head and head.label or e.queue[1].kind)..(#e.queue>1 and (' (+'..(#e.queue-1)..' queued)') or '')
 end
 return spec
end

local function seconds(ticks) return string.format('%g',ticks/20)..'s' end
-- Stats for something you are about to train or build, straight from content.
function T.statsFor(d,kind)
 local stats={}
 if not d then return stats end
 if d.buildTicks and d.buildTicks>1 then stats[#stats+1]=(kind=='unit' and 'Train ' or 'Build ')..seconds(d.buildTicks) end
 if d.hp then stats[#stats+1]='HP '..d.hp end
 if d.damage and d.damage>0 then stats[#stats+1]='Damage '..d.damage end
 if d.range and d.damage and d.damage>0 then stats[#stats+1]='Range '..string.format('%.1f',d.range/256) end
 if kind=='unit' and d.speed then stats[#stats+1]='Speed '..d.speed end
 return stats
end
local DIM={.62,.66,.62}
-- What a building is for, from the flags content gives it, so the text cannot drift from the rules.
function T.purpose(kind,d)
 local lines={}
 if d.onNode then lines[#lines+1]='Built squarely on a '..d.onNode..' node.' end
 if d.dropoff then lines[#lines+1]='A drop-off: workers deliver what they harvest here.' end
 if d.supply and d.supply>0 then lines[#lines+1]='Provides '..d.supply..' supply.' end
 if d.garrison then lines[#lines+1]='Holds '..d.garrison..' slots; occupants '..(d.garrisonFights and 'fight from inside and take half splash.' or 'are sheltered and cannot fight.') end
 if d.coverage then lines[#lines+1]='Projects relay coverage '..math.floor(d.coverage/256)..' cells around it.' end
 if d.income then local parts={};for key,amount in pairs(d.income) do parts[#parts+1]=amount..' '..key end;table.sort(parts);lines[#lines+1]='Earns '..table.concat(parts,', ')..' a minute inside coverage'..(d.incomeOffline and ', less outside it.' or '.') end
 if d.produces and #d.produces>0 then lines[#lines+1]='Trains '..#d.produces..' kind'..(#d.produces>1 and 's' or '')..' of unit.' elseif kind=='barracks' then lines[#lines+1]='Trains your army.' end
 if d.damage and d.damage>0 then lines[#lines+1]='Attacks enemies in range.' end
 lines[#lines+1]={'Shift-click places another site. Each selected worker builds one.',DIM}
 return lines
end

-- Lays the spec out once: every row with its font, colour and offset, and the panel size. Drawing
-- and the tests both read this, so what is measured is exactly what is drawn.
function T.layout(spec,font,titleFont)
 titleFont=titleFont or font
 local pad=T.PAD
 local rows={}
 local inner=T.MIN_WIDTH-2*pad
 local keyText=spec.key and spec.key~='' and ('['..spec.key:upper()..']') or nil
 local titleWidth=titleFont:getWidth(spec.title or '')+(keyText and font:getWidth(keyText)+14 or 0)
 inner=math.max(inner,math.min(T.MAX_WIDTH-2*pad,titleWidth))
 local function widen(text) inner=math.max(inner,math.min(T.MAX_WIDTH-2*pad,font:getWidth(text))) end
 local texts={}
 local function push(text,color,gap) texts[#texts+1]={text=text,color=color,gap=gap} ;widen(text) end
 if spec.subtitle then push(spec.subtitle,spec.subtitleColor or T.COLORS.dim) end
 if spec.reason then push(spec.reason,T.COLORS.reason,4) end
 if spec.status then push(spec.status,T.COLORS.status,4) end
 for i,line in ipairs(spec.lines or {}) do
  if type(line)=='table' then push(line[1],line[2] or T.COLORS.body,i==1 and 4 or 0) else push(line,T.COLORS.body,i==1 and 4 or 0) end
 end
 if spec.stats and #spec.stats>0 then push(table.concat(spec.stats,'   '),T.COLORS.dim,4) end
 local costs={}
 for _,c in ipairs(spec.costs or {}) do
  local name=COST_NAMES[c.key] or c.label
  local text=c.amount..' '..name
  if c.short then text=text..' (have '..math.max(0,c.available or 0)..')' end
  costs[#costs+1]={text=text,color=c.short and T.COLORS.short or T.COLORS.cost}
 end
 local costWidth=0
 for i,c in ipairs(costs) do costWidth=costWidth+font:getWidth(c.text)+(i>1 and 16 or 0) end
 inner=math.max(inner,math.min(T.MAX_WIDTH-2*pad,costWidth))
 local lineHeight=font:getHeight()
 local y=pad
 rows[#rows+1]={kind='title',text=spec.title or '',key=keyText,y=y}
 y=y+titleFont:getHeight()+2
 for _,t in ipairs(texts) do
  y=y+(t.gap or 0)
  local _,wrapped=font:getWrap(t.text,inner)
  rows[#rows+1]={kind='text',text=t.text,color=t.color,y=y}
  y=y+#wrapped*lineHeight
 end
 if #costs>0 then
  y=y+5
  -- Costs wrap as whole items, never mid-number.
  local x=0
  for _,c in ipairs(costs) do
   local width=font:getWidth(c.text)
   if x>0 and x+16+width>inner then x=0;y=y+lineHeight end
   if x>0 then x=x+16 end
   rows[#rows+1]={kind='cost',text=c.text,color=c.color,x=x,y=y}
   x=x+width
  end
  y=y+lineHeight
 end
 return {rows=rows,width=inner+2*pad,height=y+pad,inner=inner}
end

-- Where the panel goes. `area` is the screen in the HUD's scaled units; `card` is the command card
-- rectangle; `mx,my` is the pointer. The panel never leaves the screen and never covers the pointer.
function T.place(layout,anchor,area,mx,my,card)
 local w,h=layout.width,layout.height
 local x,y
 if anchor=='card' and card then
  x=card.x+card.w-w;y=card.y-h-6
 else
  x=mx+16;y=my+22
  if x+w>area.w-4 then x=mx-w-8 end
  if y+h>area.h-4 then y=my-h-8 end
 end
 x=math.max(4,math.min(x,area.w-w-4))
 y=math.max(area.top or 4,math.min(y,area.h-h-4))
 return x,y
end

function T.draw(spec,x,y,layout,font,titleFont)
 local g=love.graphics
 titleFont=titleFont or font
 local c=T.COLORS
 g.setColor(c.panel);g.rectangle('fill',x,y,layout.width,layout.height,4)
 g.setColor(c.edge);g.setLineWidth(1);g.rectangle('line',x+.5,y+.5,layout.width-1,layout.height-1,4)
 local pad=T.PAD
 for _,row in ipairs(layout.rows) do
  if row.kind=='title' then
   g.setFont(titleFont);g.setColor(c.title);g.print(row.text,x+pad,y+row.y)
   g.setFont(font)
   if row.key then g.setColor(c.key);g.printf(row.key,x+pad,y+row.y+(titleFont:getHeight()-font:getHeight()),layout.inner,'right') end
  elseif row.kind=='text' then
   g.setColor(row.color);g.printf(row.text,x+pad,y+row.y,layout.inner)
  else
   g.setColor(row.color);g.print(row.text,x+pad+row.x,y+row.y)
  end
 end
end

-- Timing. `state` lives on the widget set; `id` is whatever is under the pointer this frame.
-- Returns true when the tooltip for `id` should be drawn now.
function T.ready(state,id,clock,instant)
 if id~=state.id then
  state.id=id;state.since=clock
 end
 if not id then return false end
 local warm=state.shownAt and clock-state.shownAt<=T.GRACE
 if instant or warm or clock-state.since>=T.DELAY then state.shownAt=clock;return true end
 return false
end
return T
