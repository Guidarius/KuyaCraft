-- Open Reach: 224x224, corner against corner, and almost all of it open ground. There is
-- no chokepoint anywhere: two stubs of rock shade each main, a block of rock fills the very
-- centre so armies pass to one side of it, and everything else is grass broken by woods.
-- Four fields lie within reach of each base, so it is the map for wide economies, for
-- flanks, and for a Megacorp that wants to spread relays.
return function(Layout)
    local L=Layout('open_reach',224,224)
    L.rect(6,6,217,217)
    L.base(22,24)
    -- The stubs that make a main feel like a place: one to the east, one to the south.
    L.rock(46,6,51,22);L.rock(6,48,20,53)
    -- Natural to the east past the stub, third to the south, a fourth far along the north edge.
    L.expansion('naturals',70,24,L.NATURAL,1,1,1000,3500)
    L.expansion('forward',30,78,L.THIRD,1,1,800,3000)
    L.expansion('contested',176,26,L.THIRD,-1,1,800,3000)
    -- The centre block, and outcrops that break the long sight lines across the reach.
    L.rock(102,102,121,121)
    L.rock(84,58,92,63);L.rock(58,84,63,92);L.rock(132,40,138,48);L.rock(40,132,48,138)
    L.road({{28,26},{64,26}})
    L.road({{24,32},{30,72}})
    L.road({{34,36},{98,98}})
    L.forest(60,44,67,50);L.forest(44,60,50,67)
    L.forest(96,20,103,25);L.forest(20,110,25,117)
    L.forest(120,70,127,76);L.forest(70,120,76,127)
    L.forest(150,96,156,103);L.forest(88,150,95,156)
    L.forest(160,50,166,56);L.forest(108,84,113,89)
    return L.finish()
end
