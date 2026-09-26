-- The look of the interface by faction. Presentation only: colours, corner shape and a few
-- words, read by the HUD, the buttons and the menus. A faction with no entry (the fixture's
-- hero factions) gets the default, which is the look the interface always had.
--
-- The Orders are warm: dark oak, brass lines, parchment text, rounded corners. The Megacorp
-- is cold: gunmetal, cyan lines, square corners and an orange meter, like a control room.
-- Art for panels and frames will replace the flat fills; the keys are the hooks it hangs on.
local T={}
T.default={name='LoveRTS',motto='Small armies. Distinct factions. Every order matters.',
    panel={.065,.09,.11},line={.48,.4,.25},text={.83,.86,.81},dim={.62,.66,.62},accent={.91,.83,.59},
    button={.12,.17,.19},buttonHover={.22,.27,.27},buttonOff={.1,.13,.14},buttonLine={.47,.41,.27},buttonText={.91,.88,.76},
    backdrop={.035,.058,.075},shape={.13,.2,.22},card={.045,.07,.09},meter={.42,.76,.55},radius=4,supply='Food'}
T.factions={
    orders={name='THE ORDERS',motto='Keeps, workers and knights. Every Keep is a life.',
        panel={.105,.082,.06},line={.74,.58,.28},text={.94,.89,.78},dim={.7,.64,.52},accent={.97,.82,.44},
        button={.17,.13,.09},buttonHover={.29,.22,.14},buttonOff={.12,.1,.08},buttonLine={.68,.53,.26},buttonText={.96,.9,.76},
        backdrop={.06,.045,.035},shape={.2,.135,.085},card={.085,.065,.048},meter={.86,.68,.3},radius=6,supply='Supply'},
    megacorp={name='MEGACORP',motto='No workers. Everything arrives from orbit, inside relay coverage.',
        panel={.045,.07,.095},line={.22,.7,.82},text={.82,.92,.96},dim={.5,.66,.72},accent={.36,.9,1},
        button={.06,.11,.15},buttonHover={.09,.2,.26},buttonOff={.06,.085,.1},buttonLine={.2,.58,.7},buttonText={.84,.95,1},
        backdrop={.02,.038,.055},shape={.05,.13,.19},card={.035,.06,.085},meter={1,.56,.2},radius=0,supply='Supply'},
}
function T.of(faction) return T.factions[faction] or T.default end
-- Every theme carries every key, so a drawing site never has to guard one.
for id,theme in pairs(T.factions) do for key in pairs(T.default) do assert(theme[key]~=nil,'theme '..id..' is missing '..key) end end
return T
