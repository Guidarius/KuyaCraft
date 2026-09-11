# LoveRTS — Movement, responsiveness and ability-system audit

Audit date 2026-09-10, against commit `a20f1ad` (simulation version 8, content version 4). Every claim below was checked against the source; line references are to that commit. The simulation suite was run first and passed (44 tests). Nothing in this document changes code; it is the map for the next stretch of work.

The question asked was: how far is the game from Warcraft 3 in movement and responsiveness, what quality-of-life features are missing, and what would it take to add abilities and status effects with skill shots, area targeting, instant casts and unit-targeted casts.

## 1. Summary

The foundations are unusually solid for a prototype: a float-free, replay-exact 20 Hz simulation, real attack phases with cancellation, edge-to-edge ranges, shadowcast line of sight, formation pacing, rally, patrol, follow, per-unit selection tiles, an idle-worker cycler, camera bookmarks and a latency inspector. Offline click-to-motion is about 50–100 ms, which is Warcraft 3 territory.

What keeps it from *feeling* like Warcraft 3 is concentrated in five places, in order of how much a player would notice:

1. **Units walk cell-centre to cell-centre.** There is no path smoothing, so every route through open ground is a chain of 45° hops (`src/sim/movement.lua:103`). This is the single most visible difference and the cheapest to fix.
2. **Nobody ever gets pushed.** Collision is a hard veto (`src/sim/movement.lua:46-49`), idle units step aside only after a mover has been stuck for half a second, and Hold units never move. Crowds hesitate and shuffle instead of flowing.
3. **Orders are silent.** There is no unit acknowledgement, no selection-circle flash, no windup anticipation. In multiplayer the fixed 200 ms lockstep delay is fully exposed because nothing masks it.
4. **A few controls are actively wrong by Warcraft 3 rules.** A-clicking an enemy attack-moves to its feet instead of focusing it; Tab throws away the rest of the selection; the command card is a flowing list whose buttons move.
5. **There is no ability layer at all.** No mana, no cooldowns beyond the auto-attack, no status effects, no projectiles, no targeting state machine, no stat resolver. Hero kits are hard-coded branches on `e.kind` and `e.upgrades[n]`.

Section 6 designs the ability and status-effect system so that it fits the determinism contract and reuses the attack-phase, order-queue and carrier-entity patterns that already exist.

## 2. Movement versus Warcraft 3

### 2.1 What exists

| Component | Implementation | Where |
|---|---|---|
| Grid | 1 cell = 256 subunits; walkability is a boolean set, no terrain costs | `src/sim/fixed.lua:1`, `src/sim/path.lua:27-29` |
| Search | Per-unit 8-way A*, octile heuristic, deterministic binary heap, 256 expansions per tick shared by every in-flight search | `src/sim/path.lua:3-25,135-147`, `src/content.lua:4` |
| Fast path | Straight-line probe on the command tick, 16,384 cells per tick globally | `src/sim/path.lua:68-82` |
| Waypoints | Literal parent chain; units aim at the exact centre of every cell | `src/sim/path.lua:110-117`, `src/sim/movement.lua:103` |
| Local steering | Proposal/reservation: longest-wait first, seven fixed rotations of the desired vector (0°, ±26.5°, ±45°, ±90°, then ±135° after 10 stuck ticks), always full step length | `src/sim/movement.lua:5,63-79,85-89` |
| Separation | Allies must keep 75 % of combined radii, enemies 100 %. Hard rejection, never displacement | `src/sim/geometry.lua:31-34` |
| Yielding | Only after a mover has waited 10 ticks; only units on a `stop` order; exactly one cell sideways; never Hold units | `src/sim/movement.lua:106-113,140` |
| Repath | Next node unwalkable, congestion for 10 ticks, chase target moved cell, in-flight search invalidated by `navVersion` | `src/sim/movement.lua:100-101,162-169`, `src/sim/path.lua:104` |
| Group moves | Distinct claimed destination cells per unit around the click; slowest-member speed cap | `src/sim/init.lua:75-108,564-576,719-748` |
| Kinematics | Constant speed, no acceleration, no heading state; facing is derived in the renderer from position deltas | `src/sim/movement.lua:52-62`, `src/asset_frames.lua:12-15` |
| Chokepoints | Static keep-right lane rule for two-cell passages | `src/sim/path.lua:32-63` |
| Targeting | Every damage-capable unit rescans every hostile every tick, linear, nearest wins with id tiebreak | `src/sim/init.lua:779-793,826-831` |

### 2.2 Gaps, ranked by player impact

**Path smoothing (string pulling).** Units should walk straight lines between the corners that actually constrain them. The infrastructure is already there: waypoints accept sub-cell `px,py` (used today only for melee contact points, `src/sim/init.lua:806`), and `G.terrain(w,x,y,r)` tests radius-aware clearance. The change is a post-pass after `expand()` completes (`src/sim/path.lua:110-117`) that walks the cell chain, keeps a waypoint only when the straight segment to the next candidate fails the radius-aware terrain sweep, and emits `px,py` centres for the kept ones. Diagonal corner-cutting is already rejected by the direct probe (`src/sim/path.lua:77`); the same test applies. This changes movement results and therefore bumps the simulation version.

**Completed paths are never invalidated.** A building placed ten cells ahead is only noticed when the unit reaches the cell (`src/sim/movement.lua:100`). In-flight searches already compare against `w.navVersion` (`src/sim/path.lua:104`); stamping `e.pathVersion` at path completion and checking it in the same block fixes this in a few lines.

**Pushing and prompt yielding.** Warcraft 3 moves idle units out of the way immediately and lets moving allies squeeze past each other. Here the yield gate is `waitTicks>=10` (`src/sim/movement.lua:106`) and only `order.kind=='stop'` units qualify. Two steps:
- Lower the gate to two or three ticks and extend eligibility to any unit with no goal and no attack phase, still excluding Hold.
- Add a second resolution pass after the proposal loop (`src/sim/movement.lua:133-172`) that, for overlapping *allied* bodies, moves the lower-priority body by the overlap along the separating axis, bounded per tick and bounded away from terrain. Keep enemy and terrain clearance hard. The 75 % compression rule becomes the resting target rather than a veto.

**Formation-preserving group moves.** Slots are assigned by an outward ring search from the click, so the group's shape is discarded and a column arrives as a queue collapsing into a lattice. `args.group` is already plumbed (`src/sim/init.lua:471,582`). Replace the per-unit `nearest()` call at `src/sim/init.lua:576` with a group solver: compute the group's centroid and move vector, generate a slot pattern oriented along it (rows of `2*radius` spacing, heavies at the back is a content choice), and assign units to slots by nearest-slot matching in stable id order. Add a real per-unit stop tolerance (WC3 units stop when close enough rather than seeking a centre) so the last stragglers do not thread through the arrived group.

**Turn rate and heading.** Warcraft 3 has per-unit turn rates but ground units accelerate instantly, so acceleration should *not* be added. Heading matters for two things: sprites that snap between eight directions on a one-tick reversal, and abilities that need a facing (cones, dashes, skill shots fired "forward"). Do the render-side fix first: smooth `attackHeading`/movement heading over ~80 ms in `src/asset_frames.lua`. Add authoritative `e.heading` only when an ability needs it (section 6 assumes it exists for cone targeting).

**Scalable pathing for armies.** With 100 units repathing at once each gets 2.5 expansions per tick. Options, cheapest first: share one search per group move (path from the group centroid, members follow with their slot offset, each runs a short local search only when its offset cell is blocked); cache completed paths keyed by `(startCell, goalCell, navVersion)` for reuse by neighbours; hierarchical or flow-field pathing last, and only if measurements demand it.

**Target acquisition is O(units × enemies) every tick.** The spatial bins in `src/sim/geometry.lua:9-18` already exist and are rebuilt each step; `enemyTarget` should query them within sight radius and then apply the same distance-then-id order. This is also the largest remaining cost in `combatOrders` (STATUS.md step timings) and directly reduces the worst-case tick.

**Ranged chase positioning brute-forces ~225 cells** per retarget (`src/sim/init.lua:815-821`). Walk rings outward from the ideal stand-off distance and stop at the first free cell.

**Deferred, with a reason:** terrain movement costs (no roads or mud exist in the maps), flying units (no air roster yet; carriers are a working template for the pass-through half), and physics-style steering (would fight the deterministic proposal model for no visible gain).

### 2.3 Movement test gaps

The crowd suite asserts arrival within 6,000 ticks, no overlap and bounded expansions (`tests/control_scenarios.lua:38-66`). It does not assert path length, straightness, arrival ticks or cohesion, so a 3× regression in movement quality passes. Add, as regression gates with recorded baselines:
- Path straightness ratio: distance walked over straight-line distance for open-ground moves, expected close to 1.0 after smoothing.
- Arrival tick ceilings per fixture at roughly 1.5× the current measurements (932, 1,640, 868, 4,079).
- Group cohesion: spread of arrival ticks and final positions within a group move.
- Building placed mid-route triggers a reroute within N ticks.
- Direction-change count per unit per move as a jitter metric.

### 2.4 Latent hazards found on the way

- Bin keys `F.cell(y)*256+F.cell(x)` (`src/sim/movement.lua:8`, `src/sim/geometry.lua:13`) and the lane cache key (`src/sim/path.lua:48`) assume map width below 256 or 259 cells. The shipping map is 128 wide, so this is safe today; a wider map would silently corrupt collision. Assert it in `Sim.create`.
- `scale()` truncation in `src/sim/movement.lua:6` makes rotated sidesteps slightly shorter than straight steps.
- `F.approach` (`src/sim/fixed.lua:46-57`) and the legacy healing path (`src/sim/init.lua:906-908`, dead under the shipping profile) are unused.
- `docs/CONTROL_MOVEMENT.md` still lists patrol and follow as deferred and gives radii as 80/112 only; workers are 72 and heroes 96.

## 3. Responsiveness

### 3.1 The pipeline as built

| Stage | Behaviour | Where |
|---|---|---|
| Frame loop | Fixed 50 ms tick, delta clamped to 0.25 s, offline backlog above 0.5 s discarded, at most 8 catch-up ticks per frame | `src/app.lua:136-153` |
| Offline latency | Commands stamped with the next tick and applied there: exactly 1 tick, so 50–100 ms from click to authoritative motion | `src/app.lua:169-175`, `tests/control_input.lua:18` |
| Lockstep latency | Fixed 3-tick lookahead, effectively 4 ticks (200 ms) because submission happens inside the step loop; the game stalls on "Waiting for complete tick" above roughly 140 ms round trip | `src/app.lua:161-168` |
| Interpolation | Units and carriers are drawn between previous and current tick position, trailing by 0–50 ms. Buildings, effects, order lines, floating text and health bars use raw tick positions | `src/app.lua:177-188,278-283`, `src/feedback.lua:94,119` |
| Local feedback | Contracting destination ripple (0.45 s), UI click tone, "Order issued" text, instant selection ring, five procedural cursors, live build ghost with reason | `src/app.lua:402-412`, `src/ui/input.lua:41,105-159` |
| Acknowledgement | Per-command `accepted`/`rejected` events reconcile a pending table; F3 shows ticks and ms | `src/app.lua:199-205`, `src/ui/order_debug.lua:11` |

### 3.2 Gaps

- **No unit acknowledgement.** Warcraft 3 masks its own 100–250 ms lockstep delay with an instant voice line and a selection-circle pulse. Neither exists (`docs/UI_UX_ROADMAP.md:9`). The code-side hook is small: on `I.intent`, flash the selection rings of the ordered units for ~200 ms and call a new `app.audio:ack(kind, orderKind)` slot keyed by unit kind so the user can drop in voice lines per faction. The audio manifest already supports priority and cooldown per sound (`src/ui/audio.lua:2-13`).
- **Windup has no presentation.** The sim emits `windup` (`src/sim/init.lua:917`) and only the F3 panel reads it. A small anticipation cue (a sound slot, a brief ring on the attacker) makes attacks feel committed and makes cancelled swings legible.
- **Half the scene is still at 20 Hz.** Tracers, hit sparks, health bars and order lines snap while the units under them glide. Give feedback items an entity anchor and resolve their position through the same interpolation as `drawEntity`.
- **Hover is recomputed only on mouse motion** (`src/ui/input.lua:101`), so the cursor and hover ring go stale when units walk under a still pointer. Recompute once per tick as well.
- **Adaptive lockstep.** The three-tick buffer is a constant. Negotiate the lookahead from measured round trip (WC3 grows its turn length under latency instead of stalling), and keep the F3 number honest by including it.
- **Interpolation trails, it does not predict.** This is the correct choice for a lockstep RTS and matches Warcraft 3; leave it.

## 4. Controls and quality of life

### 4.1 Wrong by Warcraft 3 rules (fix first)

| Behaviour | Today | Expected | Where |
|---|---|---|---|
| A-click on an enemy | Issues attack-move to the point; the picked target is discarded | Focused `attack` on that unit | `src/ui/input.lua:37,92` |
| Tab | Replaces the selection with one subgroup; cannot cycle back to the whole army | Keeps the selection, moves the active subgroup and command card | `src/ui/input.lua:237-239` |
| Command card | Variable-length list flowed three wide; button positions move with the selection | Fixed grid with stable slots per action | `src/ui/actions.lua:4-39`, `src/ui/hud.lua:85-88` |
| Recruit hotkeys | Q/W/E/R by roster index; Q also toggles hero stance | Stable per-unit letter defined in content | `src/ui/actions.lua:26,36` |
| Box select | Own units only, no cap, no priority; primary unit is the lowest id | Combat units before workers, units never mixed with buildings, hero first for the card | `src/ui/input.lua:166-169` |
| Health bars | Team-coloured in the world | Green/yellow/red ramp (the tiles already do this) | `src/app.lua:349`, `src/ui/hud.lua:129` |

### 4.2 Missing features a Warcraft 3 player reaches for

Controls
- Shift+number appends to a control group; a setting for whether assigning to a group removes the unit from other groups.
- Ctrl+double-click or Ctrl+click: select all of a type across the map (today only on screen, `src/ui/input.lua:94`).
- Select idle hero and cycle heroes when there are several; a "hero under attack" portrait flash exists as a plan item only.
- Smart cast and self-cast modifiers (needed by section 6).
- Attack-ground for siege and hold fire, once abilities exist.
- Rally point as a card button and on the minimap, in addition to right-click.
- Queued build ghosts stay drawn for shift-queued placements (today only the live ghost).
- A minimap ping that reaches the other player. Today Alt-click is local only (`src/ui/input.lua:71`). Route it as a `ping` command that the sim accepts and re-emits as an event with no state change; that keeps it deterministic and replayable.
- Chat for multiplayer. There is none.

Information
- World hover tooltip after ~0.4 s: name, health, owner (`src/ui/widgets.lua:18-23` is HUD-only).
- Structured tooltips: cost line, hotkey highlight, icon; the current fixed 300×62 box overflows on long text.
- Alerts for any own unit or building under attack off screen, not only hero and HQ (`src/ui/alerts.lua:13-18`), with viewport-edge arrows.
- Aura and buff visibility: the Warden aura has no ring, no recipient marker, nothing (`src/sim/init.lua:865-875`). Section 6 makes auras statuses, which gives them icons for free.
- Damage and experience floating text as a setting, off by default to stay in Warcraft 3's idiom.

Camera
- Zoom notches are instant jumps; ease them like centring already is (`src/ui/camera.lua:45-48`).
- Hero follow hard-centres every frame; add a dead zone.
- Keyboard pan is a flat 350 px/s; expose speed in Settings.

### 4.3 Presentation hooks the code should leave for the user's art and audio

The user owns sound and graphics. The code side should expose, not fill:
- `app.cursorImages` is described as the override hook (`src/ui/input.lua:123`) but is never read; make it real.
- Audio slots for: unit acknowledgement per kind and order, selection per kind, windup, cast, status applied, projectile launch and impact, level up. Keep the manifest fields (gain, priority, cooldown, bus, pitch set).
- Effect anchors for: aura rings, status icons over units, cast bars, projectile sprites, area previews. `src/feedback.lua` today is a 256-item list of line primitives with linear fade; give it keyframed items with entity anchors and an easing table before spells arrive, otherwise every spell will be an ad-hoc branch like the crossbow tracer (`src/feedback.lua:72`).
- Animation clips: the catalog requires idle, move, attack, death (`src/asset_catalog.lua:30`); reserve `cast` and `hit` clip names now so exports can include them.
- Six of nine unit kinds have no art path and render as identical capsules (`src/asset_frames.lua:3-11`). Silhouette readability is a Warcraft 3 property that no code change can supply.

### 4.4 Stale documentation and dead code to clear

- `app.attackMove` is never assigned and `app.attackMode` (`src/ui/input.lua:115`) is a typo for it; both branches are dead.
- `src/app.lua:250-254` describes income inference that the `delivered` event replaced.
- `docs/CONTENT_AUTHORING.md:16` lists XP and revival numbers from an old profile.
- `docs/ASSET_PIPELINE_PLAN.md:126-128` says damage is instantaneous and windup needs a sim change; the sim has had windup since version 3.

## 5. The entity and combat model, as it bears on abilities

These are the facts the design in section 6 relies on.

- **Entities are encoded wholesale.** `Sim.serializeAuthoritative` hashes every field on every entity (`src/sim/init.lua:1021-1034`). A new field is authoritative by existing; the only constraints are integers only, no floats, no cycles (`src/sim/codec.lua:45-65`). A new field is invisible to the UI unless added to `VIEW_FIELDS` or `OWNER_FIELDS` (`src/sim/init.lua:264-269`).
- **Commands are validated in one function** with a kind allowlist (`src/sim/init.lua:455-456`), a strictly increasing per-player sequence, and a per-kind branch. The UI, bot and network pass any kind through unchanged.
- **Tick order is fixed:** commands → `combatOrders` → `economy` → `movement` → `visibility` → `finishOrders` → `combat` → conditional second `visibility` (`src/sim/init.lua:981`). Damage is dealt last, all hits are collected first and applied together so mutual kills resolve (`src/sim/init.lua:924-929`).
- **The attack phase is the template for a cast phase:** `e.attack={target,start,impact,finish,period,dx,dy}` (`src/sim/init.lua:916`), revalidated at impact, cancelled by movement before impact, and exported to the view for animation.
- **Orders are a queue** with replace/append/stop semantics shared by every order kind (`src/sim/init.lua:432-451`). A cast that needs to walk into range should be an order, not a side effect.
- **Carriers are the template for projectiles:** their own category, in `w.order` and therefore serialized, not selectable, not in the collision bins, no orders, cached route (`src/sim/carriers.lua`).
- **Stats are read directly from content at every site.** There is no resolver. The sites a modifier system must hook: speed at `src/sim/movement.lua:52-62` and `src/sim/init.lua:735`; damage at `src/sim/init.lua:833,889,909`; range inside `G.weaponRangeAt` (`src/sim/geometry.lua:56`) plus `src/sim/init.lua:800-819`; cooldown and windup at `src/sim/init.lua:913-914`; sight at `src/sim/init.lua:182,189,780`; mitigation only inside `protection()` (`src/sim/init.lua:865-875`); targetability inside `validTarget` (`src/sim/init.lua:794-796`) and the eight `Sim.visible` consumers.
- **Hero kits are branches**, not data: every upgrade effect is an `e.kind`/`e.upgrades[n]` test at its consumption site. The faction upgrade table holds only labels (`src/content.lua:41,43`).
- **Content is immutable at runtime** and validated at test start (`src/content_validate.lua`). Author-facing seconds and cells convert exactly through `src/content_time.lua`.
- **No randomness.** `src/sim/rng.lua` exists and is unused. Abilities must not need rolls; where variance is wanted, derive it from state (tick, id) rather than a PRNG, or reintroduce the PRNG as a versioned change with its state in the authoritative snapshot.

## 6. Ability and status-effect system design

The roadmap's guidance stands: "Begin with damage, healing, stat modifiers, auras, toggles, and timed effects" and "avoid a universal ability language before two factions demonstrate the requirements." The design below is a small fixed vocabulary of effect kinds, not a scripting language. It is sized so that the first two hero kits and one support unit per faction can be expressed in data, with anything exotic written as a focused Lua branch keyed by ability id, exactly as passives are today.

### 6.1 Content schema

```lua
C.abilities = {
  shockwave = {
    label='Shockwave', slot={3,1}, hotkey='w',
    target='direction',                 -- none | unit | point | area | direction
    range=T.cells(7), width=T.cells(1.25),
    filter={enemy=true, ally=false, self=false, building=false},
    cost={mana=60}, cooldown=T.ticks(9),
    castPoint=T.ticks(0.3), backswing=T.ticks(0.5),
    effects={
      {kind='projectile', speed=48, pierce=true, radius=160,
       onHit={{kind='damage', amount=75}, {kind='status', status='slow', ticks=T.ticks(2), percent=-30}}},
    },
  },
  war_stomp = { target='none', radius=T.cells(3), castPoint=T.ticks(0.25), ...,
    effects={{kind='status', status='stun', ticks=T.ticks(2)}, {kind='damage', amount=40}} },
  heal_wave = { target='unit', filter={ally=true, self=true}, range=T.cells(6), castPoint=0,
    effects={{kind='heal', amount=120}} },
  flame_ring = { target='area', radius=T.cells(2.5), range=T.cells(8), castPoint=T.ticks(0.4),
    effects={{kind='status', status='burn', ticks=T.ticks(5), perSecond=15}} },
}
C.statuses = {
  slow  = {stack='refresh', modifiers={speedPercent=true}},
  stun  = {stack='refresh', flags={noMove=true, noAttack=true, noCast=true}, cancelsWindup=true},
  root  = {stack='refresh', flags={noMove=true}},
  burn  = {stack='refresh', tick=T.ticks(1), effects={{kind='damage', amount='perSecond'}}},
  guard = {stack='max',     modifiers={armor=3}},        -- the Warden aura, as a status
}
C.units.warden.abilities = {'guard_aura', 'shockwave', 'war_stomp'}
C.units.warden.mana = 300; C.units.warden.manaRegen = 1   -- per second, converted to per-20-ticks
```

Rules for the schema:
- All times and distances go through `T.ticks`/`T.cells` so they are exact integers; percentages are integers.
- `target` is one of exactly five kinds. `none` is instant or self; `unit` needs a visible entity passing `filter`; `point` needs a map coordinate; `area` is a point with a `radius` preview and radial selection; `direction` is a point that is normalised into a unit vector from the caster, for skill shots, cones and dashes.
- `effects` is an ordered list of a fixed vocabulary: `damage`, `heal`, `status`, `projectile`, `dash`, `summon`, `reveal`, `custom` (a Lua function keyed by ability id in `src/sim/abilities.lua`, for anything the vocabulary cannot express).
- `castPoint` is the tick offset at which the effect fires and mana and cooldown are spent; `backswing` is the recovery during which the unit cannot start another action but may cancel by moving. This mirrors the attack phase and Warcraft 3's cast point/backswing.
- Validation in `src/content_validate.lua`: every referenced status and ability exists, `slot` is unique per unit, `castPoint+backswing` is at least one tick, `range` is zero for `none`, `width` and `radius` are present only where the target kind uses them.

### 6.2 Command and order

Add `cast` to the kind allowlist (`src/sim/init.lua:455`) with `args={ability, target | x,y, append}`. Validation, in order: the caster owns the ability, is alive, is not flagged `noCast`, the ability is off cooldown, mana suffices, the target is visible and passes the filter (reusing the `attack` and `follow` checks at `src/sim/init.lua:585-591`), and coordinates are in bounds (`F.integer` pattern at `src/sim/init.lua:550`).

Range is *not* validated at command time. The command becomes an order `{kind='cast', ability, target, x, y}` through `setOrder` so Shift appends and Stop clears it, and the unit walks into range exactly as an `attack` order does. `none`-targeted abilities with `castPoint=0` resolve immediately in `apply`, like `toggle` does today, and never enter the queue.

Add `ping` at the same time: accepted, emitted as an event to the player's team, no state change.

### 6.3 Cast phase and processing order

Insert an `abilities(w)` phase between `finishOrders` and `combat` in `src/sim/init.lua:981`:

1. For units with a `cast` order and no `e.cast` phase: if in range (`G.weaponRangeAt` with the ability range in place of the weapon range), stop, face the target, and set `e.cast={ability, start, point=tick+castPoint, finish=point+backswing, target, x, y, dx, dy}`. Otherwise `approachTarget` as `attack` does.
2. At `point`: revalidate target life, visibility and filter; spend mana; set `e.cooldowns[ability]=tick+cooldown`; resolve targets into a list ordered by `w.order`; append the ability's effects for each target to a per-tick `pending` list; emit `cast`. Cancellation before `point` follows the attack rule at `src/sim/init.lua:850`: any new order or a `noCast` status clears `e.cast` with nothing spent.
3. `combat(w)` then appends auto-attack hits to the same `pending` list, and a single `applyEffects(w, pending)` runs damage, heals and status applications in list order before deaths are resolved. This keeps "collect, then apply" so a stun landing on the same tick as a killing blow resolves deterministically.

Instant unit-targeted casts with `castPoint=0` still go through the phase; they just fire on the tick the unit is in range.

### 6.4 Statuses and the stat resolver

`e.statuses` is an array in application order: `{id, source, until, magnitude, stacks}`. Stacking policy comes from `C.statuses[id].stack`: `refresh` replaces the duration, `max` keeps the stronger magnitude, `stack` increments up to a cap. Expiry is swept at the top of the tick before commands so a status never affects a tick past its `until`. Periodic statuses fire on `(tick - appliedTick) % period == 0`.

A new `src/sim/stats.lua` becomes the only place content stats are read for gameplay:

```lua
Stats.speed(w,e)         -- base + flat, then × (100 + Σpercent) / 100, floored, min 1, then group cap
Stats.damage(w,e)        -- base + flat (hero upgrade, stance) + status flat
Stats.armor(w,e)         -- Σ status armor (Warden aura included), applied as max(1, damage - armor)
Stats.range(w,e), Stats.attackPeriod(w,e), Stats.sight(w,e)
Stats.can(w,e,'move'|'attack'|'cast'|'turn'), Stats.is(w,e,'invulnerable'|'hidden'|'revealed')
```

Every direct read listed in section 5 is replaced by a resolver call. The existing hero branches (stance damage, pursuit speed, sprint, quick attacks, aura) become the first modifiers the resolver knows about, so the behaviour is unchanged and the golden replays prove it before any new content is introduced. Auras become statuses re-applied each tick by their source with `until=tick+1`, which unifies the Warden's kit with the new system and gives auras icons and rings in the UI for free.

Flags are checked at exactly these gates: `noMove` at `src/sim/movement.lua:94` beside the Hold test; `noAttack` at `src/sim/init.lua:833,909` and it cancels an uncommitted windup via the existing `src/sim/init.lua:850` path; `noCast` in `apply` and in the cast phase; `invulnerable` in `applyEffects` and in `validTarget`; `hidden` in every `Sim.visible` consumer unless a `revealed` status is present.

### 6.5 Projectiles

A new entity category `projectile`, built like carriers: in `w.entities` and `w.order` (so snapshots and hashes cover flight), not selectable, not in the collision bins, excluded from `w.blocked`. Fields: `x,y,dx,dy,speed,remaining,source,ability,radius,pierce,hit={ids…}`. Two flight modes:
- **Homing**, with a target id: `F.vector` toward the target each tick, impact when within `radius + target radius`. This also lets ranged auto-attacks become true projectiles later (`C.units.crossbow.projectileSpeed`) so a unit can walk out of a shot, which is a Warcraft 3 property the tracer fakes today.
- **Linear**, for skill shots: fixed integer velocity, `remaining` distance decremented each tick; each tick test entities in the bins within `radius` along the swept segment, ordered by `w.order`, apply `onHit` to the first (or all, if `pierce`) not already in `hit`, and die at zero range or on the first non-pierce hit.

A `projectiles(w)` step runs before `abilities(w)` so impacts land in the same `pending` list. The view exposes projectiles with `x,y,dx,dy,kind` for the renderer; presentation interpolates them like carriers.

### 6.6 Targeting in the UI

Replace `app.targetMode` (a bare command-kind string, `src/ui/actions.lua:10-14`) with one targeting record:

```lua
app.targeting = {kind='area', ability='flame_ring', casters={…}, range=2048, radius=640, filter=…}
```

`I.updateHover` derives the cursor and validity from it: unit cursor over a valid filter match, invalid cursor otherwise, the range ring drawn around the primary caster, the area circle or direction arrow drawn at the cursor, and out-of-range shown by dimming the preview (the unit will walk, as in Warcraft 3). Left click issues `cast` for every selected caster that has the ability, with `append` from Shift. Escape and right click cancel as today.

Settings: **smart cast** (press the hotkey to cast at the cursor immediately, hold for the preview), **self-cast** on Alt, and **auto-cast** toggled by right-clicking the button (stored per entity as `e.autocast[ability]`, evaluated in the cast phase with the same targeting rules).

Command card: a fixed 4×3 grid where every action's `slot` comes from content, so buttons never move. Ability buttons need a cooldown sweep, a mana cost line in the tooltip, a stack or charge count, and an autocast ring. The view exposes `cooldowns`, `mana`, `maxMana`, `statuses` (id, remaining ticks) and `cast` for owned units, and `statuses` plus `cast` for visible enemies. Selection tiles gain a mana bar under the health bar; units gain a status icon strip; the hero dock gains a mana bar.

Events for presentation: `cast` (source, ability, x, y, target), `status_applied` and `status_expired` (entity, status, source), `projectile_hit` (projectile, target). All go through `emit` so fog filtering and audiences apply automatically.

### 6.7 Bot

The bot is stateless and reads only the filtered view (`src/bot.lua:5-6`). Give abilities a `bot` block in content: `{use='enemies_in_radius', min=3}` for area stuns, `{use='ally_below', fraction=50}` for heals, `{use='target_hero'}` for single-target nukes. A small scoring pass per hero per bot tick reads `cooldowns` and `mana` from the view and emits `cast`. This keeps the bot a playability workload rather than a competitor, which is its stated purpose.

### 6.8 Tests and versioning

This is a simulation version bump and a content version bump with regenerated golden replays, recorded in STATUS.md per AGENTS.md. Regression scenarios to add before any real content:
- Cast cancels on a move before the cast point with nothing spent; completes if the move arrives after.
- Cooldown and mana are enforced; a second cast is rejected with a reason.
- Stun cancels an uncommitted windup and an uncommitted cast; a committed hit still lands.
- Slow reduces distance per tick by the expected integer amount; root blocks movement but not attacks.
- Invulnerable takes no damage and cannot be acquired.
- Skill shot hits the first unit in `w.order` along the line; pierce hits all; misses die at range.
- Area effect target order is `w.order` and the same regardless of command arrival order.
- Snapshot during flight, during a cast phase and with active statuses restores to identical continuation.
- Replay round trip with every target kind.
- Stat resolver refactor alone (section 6.4, step one) reproduces the three golden replays byte for byte.

## 7. Recommended order of work

Each line is independently shippable and testable. Rough sizes assume one engineer familiar with the code.

1. **Control fixes** (small, UI only): A-click focuses, non-destructive Tab, box-select priority, health-bar ramp, hover recompute per tick, ack flash plus audio slot, windup cue, interpolate feedback items. Removes the "wrong by WC3 rules" list.
2. **Stat resolver refactor** (medium, sim, no behaviour change): `src/sim/stats.lua`, hero branches become modifiers, golden replays must not change. This is the foundation for both statuses and future balance work.
3. **Path smoothing and path invalidation** (medium, sim, versioned): the biggest visible movement gain. Add straightness and arrival-tick gates.
4. **Yielding and pushing** (medium, sim, versioned): lower the yield gate, extend eligibility, add the allied overlap-resolution pass. Re-measure the crowd fixtures.
5. **Statuses, cast phase, command and view** (large, sim + UI): sections 6.2–6.4 and 6.6 without projectiles; ship with one instant, one unit-targeted and one area ability on the existing heroes.
6. **Projectiles and direction targeting** (medium, sim + UI): section 6.5; convert the crossbow tracer to a real projectile as the proof.
7. **Formation-preserving group moves** (medium, sim, versioned): section 2.2.
8. **Command card grid, cooldown sweeps, mana and status UI, smart cast** (medium, UI).
9. **Adaptive lockstep and networked ping** (small to medium, net + sim).
10. **Binned target acquisition and ring-walk stand-off search** (small, sim, no behaviour change): pure performance, verified by identical replays.

Everything in this list stays inside the determinism contract and the Raspberry Pi 5 budget: the added per-tick work is one status sweep and one cast phase over living units, plus projectiles that are at most a few dozen entities.
