# Abilities and status effects

How to author an ability, what the simulation does with it, and the rules a new one has
to respect. The implementation is `src/sim/abilities.lua`, `src/sim/projectiles.lua` and
`src/sim/stats.lua`; the definitions are in `src/content.lua`.

This is a small fixed vocabulary, not a scripting language. The roadmap's rule stands:
begin with damage, healing, stat modifiers, auras, toggles and timed effects, and do not
build a universal ability language before two factions have shown what they need. An
ability the vocabulary cannot express is written as ordinary Lua named by ability id, the
same way the hero passives are written today.

## Authoring

```lua
C.abilities = {
  challenge = {
    label='Challenge', hotkey='e', slot=3,
    target='unit',                       -- none | unit | point | area | direction
    range=T.cells(5),
    filter={enemy=true, building=false}, -- who it may be aimed at
    cost={mana=45}, cooldown=T.ticks(12),
    castPoint=T.ticks(.3), backswing=T.ticks(.35),
    tip='Deals 60 damage and slows one enemy by 35% for 4 seconds.',
    effects={
      {kind='damage', amount=60},
      {kind='status', status='slow', ticks=T.ticks(4), percent=-35},
    },
  },
}
C.units.warden.abilities={'bulwark','challenge'}
C.units.warden.mana=200
C.units.warden.manaRegen=1   -- per second
```

Every duration and distance goes through `src/content_time.lua`, which rejects anything
that is not a whole number of ticks or subunits. Percentages are integers.

| Field | Meaning |
|---|---|
| `target` | One of five kinds. `none` fires where the caster stands and needs a `radius`; `unit` needs a visible entity passing `filter`; `point` and `area` take ground, and `area` needs a `radius`; `direction` is a line from the caster and needs a `width`. |
| `range` | How far the caster may be and still cast. Not checked when the command is accepted: a caster out of range walks in first, like an attack order. `none` must have no range. |
| `filter` | `enemy`, `ally`, `self`, `building`. Absent means enemy units only. Neutral counts as hostile, as it does for ordinary acquisition. |
| `castPoint` | Ticks from the start of the cast to the moment it takes effect. Moving before this cancels the cast and costs nothing. |
| `backswing` | Recovery after the point. Moving during it throws the recovery away but not the effect. |
| `slot` | Fixed position on the command card. Two abilities on one unit may not share a slot. |
| `effects` | Ordered list from a fixed vocabulary. |

### Effects

| Kind | Fields | Notes |
|---|---|---|
| `damage` | `amount` | Reduced by the target's armour, floored at 1. |
| `heal` | `amount` | Clamped to maximum health; emits `healed`. |
| `status` | `status`, `ticks`, and `magnitude`, `percent` or `amount` | Applies a status from `C.statuses`. |
| `projectile` | `speed`, `radius`, `pierce`, `onHit` | Launches instead of resolving. `onHit` is a list of the three kinds above, applied when it arrives. |

### Statuses

```lua
C.statuses = {
  guard = {stack='max', beneficial=true, modifiers={armor=0}},
  slow  = {stack='refresh', modifiers={speedPercent=0}},
  root  = {stack='refresh', flags={noMove=true}},
  stun  = {stack='refresh', flags={noMove=true, noAttack=true, noCast=true}},
  burn  = {stack='refresh', period=20, effects={{kind='damage', amount=1}}},
}
```

`modifiers` are read by the stat resolver and are the only way a statistic is ever
changed. The value in the definition is a default; what the ability passes as
`magnitude` or `percent` is what is actually applied, so one `slow` definition serves
slows of different strengths. Fields the resolver understands: `speed`, `speedPercent`,
`damage`, `damagePercent`, `armor`, `range`, `attackPeriod`, `windup`, `sight`.

`flags` are hard gates checked where the action they forbid is decided: `noMove` in
movement, `noAttack` where a swing starts, `noCast` at the command and in the cast phase,
`invulnerable` where damage is applied and where a target is validated.

`stack` says what a second application does. `refresh` replaces the duration; `max` keeps
the stronger magnitude and the longer remaining time; `stack` increments up to
`maxStacks`. `period` makes a status tick on its own, and `beneficial` lets it through
invulnerability.

## What the simulation does

Order within a tick, from `Sim.step`:

1. Statuses whose time is up are swept, before commands, so nothing observes a status on
   a tick it is no longer active for.
2. Commands are applied. A `cast` becomes an order, so Shift queues it and Stop clears
   it, and a caster with the ability on cooldown holds the order rather than being
   refused.
3. Movement, then visibility, then order completion.
4. Projectiles fly and report what they hit.
5. The cast phase starts, commits and finishes casts.
6. Combat runs, and every effect from steps 4 to 6 is applied together, so a spell and a
   sword landing on the same tick resolve as one event rather than in scan order.

Mana is spent and the cooldown starts at the cast point, not when the command is issued.
A cast is revalidated there, exactly as an attack is revalidated at its impact: the
target may have died or walked away while the arm came round.

## Rules a new ability must respect

- **Integers only.** No floats reach the simulation. Use `T.ticks` and `T.cells`.
- **No randomness.** There is none in the simulation and an ability must not need any.
  Where variance is wanted, derive it from state that is already deterministic, or
  reintroduce the project PRNG as a deliberate versioned change with its state in the
  authoritative snapshot.
- **Order by `w.order`.** Area and line effects collect their targets in world order, so
  two peers resolve the same area identically whatever order the commands arrived in.
- **New entity fields are authoritative by existing.** The whole entity is hashed. A
  field must be an integer, a string, a boolean or a flat table of those.
- **The view is a whitelist.** A new field is invisible to the interface until it is
  named in `VIEW_FIELDS`, and private until it is named in `OWNER_FIELDS`.
- **Add a scenario.** `tests/ability_scenarios.lua` covers cancellation, cooldown and
  mana, area membership, burn periodicity, skill-shot first-hit, stun gating, projectile
  flight and recycling, snapshot continuation and arrival-order independence. A new
  mechanic needs its own.
- **Bump the versions.** A rule change bumps `Sim.VERSION` and `C.version`, which rejects
  older replays rather than misreporting them as divergence.

## What is deliberately not here

- **Auto-attacks do not travel.** The homing projectile mode would make a crossbow bolt
  a real body that can be walked out of, and `projectileSpeed` on a unit definition is
  where that would go. Turning it on changes when every ranged trade in the game lands,
  which is a balance change that wants a playtest rather than a commit.
- **Autocast.** No ability toggles itself on. The card has no autocast ring yet.
- **Ability levels.** An ability is one definition. Hero upgrades still work by
  hard-coded milestone branches rather than by levelling an ability.
- **Charges.** One cooldown per ability, no stacking charges.

## Current content

Provisional numbers, chosen to prove all four targeting kinds run end to end through
shipping content. They want playtesting, not defending.

| Hero | Ability | Kind | Cost | Cooldown | Effect |
|---|---|---|---:|---:|---|
| Warden | Bulwark | none, 6-cell radius | 60 | 24 s | Allies take 4 less damage per hit for 8 s |
| Warden | Challenge | unit, 5 cells | 45 | 12 s | 60 damage, 35% slow for 4 s |
| Beastkeeper | Thornfall | area, 8 cells, 2.5 radius | 70 | 20 s | 30 damage, burns 15 a second for 5 s |
| Beastkeeper | Snare | direction, 7 cells | 50 | 16 s | Thrown at 3 cells/s; first enemy takes 35 and is rooted 3 s |
