-- Flat navigation lab. Bridges and ramps are represented by narrow passages.
return function()
    local m={id='movement_lab',width=64,height=64,blocked={},resources={},camps={},
        starts={{x=2,y=2},{x=57,y=57},{x=57,y=2},{x=2,y=57}}}
    local function wall(x1,y1,x2,y2)
        for y=y1,y2 do for x=x1,x2 do m.blocked[y*64+x+1]=true end end
    end
    wall(15,0,15,10);wall(15,13,15,23) -- two-cell bridge
    wall(0,23,10,23);wall(12,23,23,23) -- single doorway
    wall(28,5,28,16);wall(28,16,37,16);wall(37,5,37,16) -- U
    wall(44,8,54,8);wall(44,8,44,17);wall(44,17,49,17) -- concave wall
    wall(27,29,45,29);wall(27,32,45,32) -- two-wide corridor/ramp
    for y=39,52,3 do for x=10,26,3 do wall(x,y,x,y) end end -- forest
    return m
end
