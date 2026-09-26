-- The bot is chosen by the player's faction: content names the strategy module under
-- src/bot/ that plays it, so a new faction brings its own plan without touching this file.
-- Every strategy receives only the filtered view a player would, plus the content.
local B={}
function B.commands(view,C)
 local faction=C.factions[view.player.faction]
 local name=faction and faction.bot
 if not name then return {} end
 return require('src.bot.'..name).commands(view,C)
end
return B
