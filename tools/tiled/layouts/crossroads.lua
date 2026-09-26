-- Crossroads: 192x192, west against east. The short way between the bases runs through a
-- walled clearing at the very centre with a narrow gate on each side and two small fields
-- inside it: whoever holds the middle holds the direct road and both of those fields. The
-- long ways are two wide outer lanes. Each player's natural sits on the lane that leaves
-- their own base, and the enemy's lane arrives at their back door, so expanding protects
-- the way out and does nothing for the way in.
return function(Layout)
    local L=Layout('crossroads',192,192)
    -- Main on the west edge, field to the north of the keep.
    L.carve(20,94,15)
    L.base(16,92)
    -- North through the throat to the natural, then east along the north lane all the way to
    -- the enemy main's northern door. The rotation makes the south lane, arriving at ours.
    L.corridor({{20,80},{20,68}},4)
    L.carve(22,56,12)
    L.expansion('naturals',24,56,L.NATURAL,-1,1,1000,3500)  -- field on the west wall, away from the exit
    L.corridor({{32,54},{60,38},{96,30},{150,40},{172,66},{172,82}},6)
    -- The lane's third base, in a bay off its highest point.
    L.carve(98,20,11)
    L.expansion('forward',102,18,L.THIRD,1,1,800,3000)
    -- The direct road: east from the main to the gate, and the walled centre.
    L.corridor({{34,94},{72,94}},5)
    L.corridor({{72,94},{84,95}},2)
    L.disc(96,96,16)
    -- The field lies south of the road for us and north of it for them, clear of the gates.
    L.expansion('contested',99,106,L.THIRD,1,1,800,3000)
    L.road({{22,88},{20,68},{22,60}})
    L.road({{30,54},{60,38},{96,32}})
    L.road({{30,94},{95,95}})
    L.forest(44,84,50,89);L.forest(56,98,62,103)
    L.forest(70,28,76,32);L.forest(120,36,126,41)
    L.forest(8,104,13,108);L.forest(40,60,45,65)
    return L.finish()
end
