# Adding content safely

1. Give the definition a stable ID. Keep the source data serializable: integers, strings, booleans, and tables; place validation/functions in separate modules.
2. Add a focused strategic role rather than duplicating an existing unit with a new name.
3. Specify health, integer speed/range, tick cooldown, costs, production time, and sight.
4. Reference shared definitions; never mutate the global content table during a match.
5. Give the unit a producer: list it in a building's `produces`, or in a faction `roster` for the legacy war hall. A faction is declared by the schema below; a hero-and-roster faction is the legacy shape and still validates.

6. Give each upgrade milestone exactly two choices with meaningful tradeoffs.
7. Implement exceptional mechanics inside the simulation, with explicit stable ordering and integer arithmetic. UI and animation must only display outcomes.
8. Test ownership, invalid orders, death/cancellation, fog, snapshots during pending work, and replay continuation.
9. Ensure the bot can use the new content through the filtered view and normal commands.
10. Supply placeholder visuals first, then an exported atlas with validated anchors, directions, team mask, loop behavior, and frame timing.
11. Run the full suite, the rendered proof, and relevant stress scenarios.
12. Document intentional replay compatibility changes; do not silently replace expected results.

Current cancellation default: 50% construction refund, rounded down per resource; 100% refund for the last queued recruit. Current hero progression thresholds: 60/160/320 XP; revival: 120 gold and 200 ticks. These are provisional balance values.

The initial data validator checks faction references and upgrade shape. Add deeper validation as new mechanics introduce constraints. There is no arbitrary content scripting language or downloaded-mod execution path.

Abilities and status effects have their own authoring reference:
[ABILITIES.md](ABILITIES.md). The experience and revival numbers quoted earlier in this
file predate the `marches-v1` profile; `src/content.lua` is authoritative and
[BALANCE_AND_PACING.md](BALANCE_AND_PACING.md) records the current values.

## Faction schema (simulation version 20)

Every field is optional and defaults to the behaviour the Bastion and Wild Pact content had
before the schema existed. Validation is in `src/content_validate.lua`; the accessors that
apply the defaults are `Sim.hqKind`, `Sim.workerKind`, `Sim.producesFor`, `Sim.supplyCap` and
`Sim.defeated` in `src/sim/init.lua`.

```lua
factions[id] = {
  label, blurb,                   -- the menu's name and one-line description
  hq = 'hq',                      -- building spawned at the start position
  worker = 'worker',              -- the unit that builds; false for a faction with none
  defeat = 'all_hq',              -- 'all_hq': lose when nothing of the hq kind stands or is
                                  -- under construction; 'unique_hq': lose when the starting
                                  -- one dies, and it can never be built again
  supplyCap = 200,                -- ceiling when rules.supplyFromBuildings is on
  buildings = { ... },            -- the build card, in order; nil = the legacy four
  starting = { resources = { gold = 650 }, units = { 'worker', 'worker' } },
  hero, roster, upgrades          -- legacy hero factions only
}
buildings[kind] += produces = { unit ids }, requires = { building ids }, supply = n, armor = n,
                   onNode = 'gold'   -- must stand squarely on a node of this resource
units[kind]     += armor = n, requires = { building ids }
rules           += resources = { 'gold' },      -- ledger keys in display order; every cost uses one
                   supplyFromBuildings = false, -- true: the cap is the sum of completed buildings' supply
                   cancelRefundPercent = 50
```

`requires` is checked when a building is placed and when a unit is queued, and the reason
names the missing building. `Sim.missingRequirement` answers the same question for a world,
a view, the HUD and the bot.
