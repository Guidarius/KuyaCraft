-- The Narrows: 160x224, north against south. Three lanes cross a wide band of rock: a
-- seven-cell bridge down the middle, wooded on both banks, and one long five-cell lane down
-- each flank. The natural sits behind the main's throat, but the enemy's flank lane comes
-- out at its southern edge, so it is safe from the bridge and open to a long walk round. A
-- third base hangs off each flank lane and a contested pocket opens off each side of the
-- bridge at the midline.
return function(Layout)
    local L=Layout('the_narrows',160,224)
    -- Main in the north-west corner, its field to the north; the throat runs south to the natural.
    L.carve(22,22,15)
    L.base(18,18)
    L.corridor({{22,36},{22,50}},4)
    L.carve(24,60,12)
    L.expansion('naturals',24,60,L.NATURAL,-1,1,1000,3500)  -- field on the west wall, away from the exit
    -- Out of the natural to the northern plaza, and the three lanes south from there.
    L.corridor({{34,60},{68,60}},5)
    L.carve(80,62,13)
    L.corridor({{80,74},{80,112}},3)
    L.corridor({{92,60},{130,60},{148,84},{148,140},{130,163},{92,163}},2)
    -- The flank lane's third base, and the pocket off the bridge at the midline.
    L.disc(134,106,13);L.corridor({{144,106},{148,106}},3)
    L.expansion('forward',138,104,L.THIRD,1,1,800,3000)
    -- The pocket authored here is on our own lane but far down it; the one the rotation puts on
    -- the enemy's lane is the nearer to us, so the anchors are named by who reaches them first.
    local forward=L.map.anchors.forward;forward[1],forward[2]=forward[2],forward[1]
    L.disc(58,106,13);L.corridor({{68,106},{80,106}},3)
    L.expansion('contested',62,104,L.THIRD,1,1,800,3000)
    L.road({{24,28},{22,50},{24,56}})
    L.road({{32,60},{68,60},{80,64},{80,111}})
    -- The short connectors are paved so the generator's coastline cannot pinch them shut.
    L.road({{70,106},{80,106}});L.road({{142,106},{148,106}})
    L.forest(70,78,75,86);L.forest(85,90,90,98)
    L.forest(68,50,74,54);L.forest(88,68,93,73)
    L.forest(8,30,12,36);L.forest(30,8,35,12)
    L.forest(126,64,131,68)
    return L.finish()
end
