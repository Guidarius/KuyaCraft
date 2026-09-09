# Adding content safely

1. Give the definition a stable ID. Keep the source data serializable: integers, strings, booleans, and tables; place validation/functions in separate modules.
2. Add a focused strategic role rather than duplicating an existing unit with a new name.
3. Specify health, integer speed/range, tick cooldown, costs, production time, and sight.
4. Reference shared definitions; never mutate the global content table during a match.
5. Add the unit to a faction roster, preserving four combat types plus worker and hero.
6. Give each upgrade milestone exactly two choices with meaningful tradeoffs.
7. Implement exceptional mechanics inside the simulation, with explicit stable ordering and integer arithmetic. UI and animation must only display outcomes.
8. Test ownership, invalid orders, death/cancellation, fog, snapshots during pending work, and replay continuation.
9. Ensure the bot can use the new content through the filtered view and normal commands.
10. Supply placeholder visuals first, then an exported atlas with validated anchors, directions, team mask, loop behavior, and frame timing.
11. Run the full suite, the rendered proof, and relevant stress scenarios.
12. Document intentional replay compatibility changes; do not silently replace expected results.

Current cancellation default: 50% construction refund, rounded down per resource; 100% refund for the last queued recruit. Current hero progression thresholds: 60/160/320 XP; revival: 120 gold and 200 ticks. These are provisional balance values.

The initial data validator checks faction references and upgrade shape. Add deeper validation as new mechanics introduce constraints. There is no arbitrary content scripting language or downloaded-mod execution path.
