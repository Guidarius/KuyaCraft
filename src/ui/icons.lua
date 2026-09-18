-- Small geometric symbols remain legible without downloaded icon assets.
local I={}
function I.draw(name,x,y,size,disabled)
 local g=love.graphics;g.push('all');g.translate(x,y);g.scale(size/20);g.setColor(disabled and .4 or .86,disabled and .44 or .77,disabled and .44 or .49);g.setLineWidth(1.5)
 if name=='build-menu' then g.polygon('line',2,9,10,2,18,9);g.rectangle('line',4,9,12,10)
 elseif name=='abilities' or name:find('ability%-') then g.rectangle('line',3,3,14,14);g.line(10,5,10,15);g.line(5,10,15,10)
 elseif name=='back-card' then g.line(17,10,3,10,8,5);g.line(3,10,8,15)
 elseif name=='move' then g.line(2,16,17,3,8,3);g.line(17,3,17,12)
 elseif name=='stop' then g.rectangle('fill',4,4,12,12)
 elseif name=='attack' then g.line(3,17,17,3);g.line(3,3,17,17);g.line(1,13,7,19);g.line(13,19,19,13)
 elseif name=='barracks' or name=='tower' or name=='outpost' or name=='keep' or name=='depot' then g.rectangle('line',4,7,12,12);g.line(3,7,3,2,7,2,7,5,12,5,12,2,17,2,17,7)
 -- A headframe over a shaft: the extractor stands on the mine and lifts gold out of it.
 elseif name=='extractor' then g.polygon('line',5,18,8,4,12,4,15,18);g.line(6,11,14,11);g.line(8,4,12,8);g.line(12,4,8,8)
 -- A pick for harvesting; a bundle on a hoop for bringing the load back.
 elseif name=='harvest' then g.line(4,17,15,6);g.line(11,3,17,9);g.line(13,4,16,7)
 elseif name=='return-cargo' then g.circle('line',10,10,7);g.line(6,13,14,7);g.line(10,7,14,7,14,11)
 elseif name=='research' then g.line(10,18,10,3,4,9);g.line(10,3,16,9);g.circle('line',10,10,9)
 elseif name=='stance' or name=='passive' then g.polygon('line',3,3,10,1,17,3,16,12,10,19,4,12)
 elseif name=='cancel' then g.line(3,3,17,17);g.line(17,3,3,17)
 else g.circle('line',10,5,3);g.line(4,18,4,13,10,10,16,13,16,18);g.line(7,14,13,14) end
 g.pop()
end
function I.portrait(kind,x,y)
 local g=love.graphics;g.push('all')
 g.setColor(.13,.21,.24);g.rectangle('fill',x,y,38,42,4)
 g.setColor(kind=='warden' and .57 or .42,.7,.63);g.polygon('fill',x+4,y+41,x+6,y+27,x+19,y+20,x+32,y+27,x+35,y+41)
 g.setColor(.84,.73,.52);g.polygon('fill',x+10,y+9,x+28,y+9,x+26,y+23,x+19,y+29,x+12,y+23)
 g.setColor(.35,.45,.48);g.polygon('fill',x+8,y+10,x+11,y+3,x+27,y+3,x+30,y+10,x+20,y+14)
 g.setColor(.1,.14,.16);g.line(x+12,y+17,x+16,y+17);g.line(x+22,y+17,x+26,y+17)
 g.pop()
end
return I
