# Icon and pip inventory

A drawing list, not an implementation plan. Every symbol the match UI needs, what it means,
where it is drawn today, and what size it has to read at. Draw tier 1 first.

Nothing in this document has been implemented. There is no icon loader, no `icon` field in
`src/content.lua`, and no tracked directory for UI art. Wiring the slots is a separate task;
this file is what that task will be built against, and what the art is drawn to.

Scope is the match HUD and world-space overlays. The shell (main menu, skirmish setup,
lobby, replay browser, settings, results) is out of scope.

Counted here: **94 symbols** — 31 in tier 1, 45 in tier 2, 18 in tier 3 — plus a pip and bar
specification that is drawing code rather than art.

## Why this exists

Almost everything the player reads every second is a literal string. `Gold  650` and
`Food  18 / 80` in the top bar. The cost letters `g` / `f` / `m` / `xp` on every command
button. `Level 2`, `T1`, `Learned`, `Excluded`, `Reviving 8s`, `Advancing 12s`, and an
ability's remaining cooldown concatenated into its own button label. `HQ` / `T` / `WAR` /
`MINE` / `OUTPOST` painted on the buildings themselves. Ten alert categories separated only
by their sentence.

Where a symbol does exist it is procedural vector code in `src/ui/icons.lua` — 29 lines, 13
named glyphs — and it collapses distinct things onto the same picture:

- `Icons.draw` falls through to one generic head-and-shoulders figure (`src/ui/icons.lua:17`)
  for **every** `recruit-*` action, so nine trainable units look identical on the card, and
  every unit in the selection tiles looks identical too (`src/ui/hud.lua:205`).
- The pattern `name:find('ability%-')` (`src/ui/icons.lua:6`) matches all four abilities
  *and* all twelve hero upgrades, so sixteen buttons draw the same framed plus.
- `barracks`, `tower` and `outpost` share one building glyph (`src/ui/icons.lua:11`).
- `hold`, `patrol`, `revive` and `cancel-research` have no branch at all. `cancel-research`
  misses the `cancel` branch because that branch is an exact match.
- On the minimap a hero and a gold mine are both diamonds, and every non-hero unit is the
  same 1.8-pixel dot (`src/ui/minimap.lua:102-104`).

Three places already reserve a slot for art that does not exist: `src/app.lua:45-47` ("The
user's own icons drop in over these later; the slot and the position are what the code owes
them"), `docs/UI_UX_ROADMAP.md:217`, and the cost-letter map at `src/ui/widgets.lua:28`.
`STATUS.md:1073` records "Not done: icons in tooltips (there are no icons for costs yet)".

## Conventions

### Keys

Icon keys already exist implicitly. `src/ui/hud.lua:124` passes the action id as the icon
name; `src/ui/hud.lua:205` passes the entity kind. This document keeps that: lowercase
kebab, matching either the command-card action id (`recruit-crossbow`, `ability-bulwark`,
`build-menu`) or the content id (`shield`, `extractor`, `stun`).

Two naming problems have to be settled before art is filed:

- **Upgrade keys collide between factions.** `src/ui/actions.lua:88` builds
  `ability-<tier>-<choice>`, so Bastion's *Wide protection* and the Wild Pact's *Rapid
  recovery* are both `ability-1-1`. This document lists twelve distinct upgrade icons and
  recommends faction-qualified keys — `upgrade-bastion-1-1` — because the two factions want
  visibly different art.
- **`cancel-research` needs its own key**, not a fallback onto `cancel`. Cancelling a
  research is not cancelling a construction site, and the tooltip already says so.

### Sizes

Measured from the code. These are the sizes the art must survive at, not the sizes it is
drawn at.

| Slot | Display size | Source |
|---|---|---|
| Command card button icon | **10 px** in a 98×46 button | `src/ui/widgets.lua:16`; grid `src/ui/hud.lua:122-124` |
| Selection tile icon | at most **24 px** (tile capped at 34) | `src/ui/hud.lua:196-205` |
| Hero portrait | **38×42** | `src/ui/icons.lua:20-27`, called from `src/ui/hud.lua:44` |
| Status effect pip | **5×5** world px, times camera zoom | `src/app.lua:487-492` |
| Minimap marker | **4–5 px** | `src/ui/minimap.lua:101-124` |
| Cost symbol, inline with the card font | about **8 px** (font `card` is 10) | `src/ui/widgets.lua:25-30` |
| Hotkey cap | about **10 px** | `src/ui/widgets.lua:18` |

**10 px is too small for a role icon on a 98×46 button.** Warcraft 3's card is
icon-dominant, and so is the concept art in `UI_AND_UNIT_CONCEPTS.md` ("a simple bold role
icon" per button). Draw the card icons to read at **32 px**; enlarging the slot is the
implementation task's problem, not an art problem.

UI scaling is a single whole-canvas `love.graphics.scale(settings.scale/100)` clamped to
80–125% with no DPI variants (`src/ui/hud.lua:15-17`, `src/ui/settings.lua`), so **one
source size per icon is enough**. Author at 4× the display size — 128 px for a 32 px card
icon — on a transparent square, and let the packer downsample.

### Where the files go — undecided

`src/asset_catalog.lua:4-8` (`safePath`) hard-requires every asset path to begin
`assets/generated/`, and `assets/generated/` is untracked. Hand-drawn icons are *source*
art, not generated output, so they do not belong there. Two options, and this is the user's
call because it decides where the files are saved:

1. **Widen the sandbox** to also allow a tracked `assets/ui/`, and load icons with a small
   loader of their own. Simplest; icons are versioned with the code.
2. **Feed them through `tools/assets`** the way unit sprites go, so icons are packed into an
   atlas and published into the generated catalog. Consistent with the existing pipeline,
   but it means hand-drawn PNGs live under `art/` and are rebuilt into `assets/generated/`.

The precedent worth copying either way is `src/ui/audio.lua`: a data-driven manifest where
each entry may supply a file path and keeps its procedural recipe as a fallback
(`docs/COMMAND_CARDS.md`, "Feedback and audio extension"). An icon manifest built that way
lets `src/ui/icons.lua` stay as the fallback for anything not yet drawn.

---

## Tier 1 — a word or a bare letter where a symbol must go

Read constantly, and currently unreadable at a glance. 31 symbols.

### Economy (4)

| Key | Meaning | Drawn today | Size |
|---|---|---|---|
| `gold` | The only real resource | Letter `g` on every cost row (`src/ui/widgets.lua:28`); the word `Gold` in the top bar (`src/ui/hud.lua:23`) | 8 and 16 px |
| `food` | Supply used against the cap of 80 | Letter `f`; the word `Food` (`src/ui/hud.lua:26-27`) | 8 and 16 px |
| `mana` | Ability cost and hero pool | Letter `m` | 8 px |
| `xp` | Upgrade threshold, not spent | Letters `xp` | 8 px |

`lumber='w'` also sits in that map. The economy is gold-only; **do not draw it** — it should
be deleted when the slot is wired.

### Top bar (4)

| Key | Meaning | Drawn today |
|---|---|---|
| `clock` | Match time at the fixed tick rate | `MM:SS` text, `src/ui/hud.lua:28-29` |
| `idle-worker` | Count of workers with no order | Text `Idle: 2 [F9]`, `src/ui/hud.lua:76` |
| `pending-order` | Commands awaiting simulation acknowledgement | Text `N pending` and a separator, `src/ui/hud.lua:130,132` |
| `command-rejected` | The last command was refused | A bare 3×19 red rectangle, `src/ui/hud.lua:131` |

### Frames and affordances (4)

| Key | Meaning | Drawn today |
|---|---|---|
| `keycap` | Frame behind a hotkey letter, so it reads as a key | Bare uppercase letter, `src/ui/widgets.lua:18`; `[Q]` in tooltips, `src/ui/tooltip.lua:122` |
| `tier-pip` | Hero upgrade tier 1–3 | Text badge `T1`, `src/ui/widgets.lua:17`, set at `src/ui/actions.lua:91` |
| `subgroup-active` | Which unit type owns the command card | A literal `"> "` string prefix, `src/ui/hud.lua:88` |
| `queue-cancel` | Click this queue slot to cancel it | A literal lowercase `x` appended to the label, `src/ui/hud.lua:102` |

The hotkey cap and the tier badge currently draw at the same coordinates
(`src/ui/widgets.lua:17-18`) and overlap on an upgrade button. Worth knowing when sizing
both.

### Hero dock (4)

| Key | Meaning | Drawn today |
|---|---|---|
| `level-chevron` | Hero level 0–3 | Text `Level 2`, `src/ui/hud.lua:48-59`; `(level 2)` appended to a tooltip title, `src/ui/tooltip.lua:72` |
| `upgrade-ready` | A tier is unlocked and unspent | Text button `Upgrade available`, `src/ui/hud.lua:66` |
| `revive` | Bring the hero back at the HQ | Text `Revive: 200 gold` / `Reviving 8s`, `src/ui/hud.lua:68`; card action `src/ui/actions.lua:127` |
| `stance-defensive` and `stance-offensive` | Two-state toggle — one icon per state | Sentence `Stance offensive: toggle`, `src/ui/hud.lua:62`; card action `src/ui/actions.lua:125`. The existing `stance` glyph (`src/ui/icons.lua:15`) is a single shield and does not show which state is active |

### Alert categories (7)

All ten alert kinds are distinguished purely by their sentence today
(`src/ui/alerts.lua:25-35`), and the priority computed at `src/ui/alerts.lua:16` is never
shown. Seven icons cover all ten, because the three "under attack" alerts want the same
picture with a different subject.

| Key | Covers |
|---|---|
| `alert-attack` | `Hero under attack`, `Headquarters under attack`, `Your forces are under attack` |
| `alert-hero-down` | `Hero lost - revive at headquarters` |
| `alert-control-point` | `Control point captured`, `Control point taken by the enemy`, and both "hold both control points" notices |
| `alert-build-complete` | `Construction complete` |
| `alert-build-stopped` | `Construction stopped - send a worker back` |
| `alert-order-blocked` | `Order blocked`, `Production exit blocked` |
| `alert-upgrade-ready` | `Hero upgrade available` |

### Building identity (5)

These five serve **three** slots each: the world label, the build command card, and the
minimap. Draw once.

| Key | Label | Drawn today |
|---|---|---|
| `hq` | Headquarters | `HQ` printed on the building, `src/app.lua:417` |
| `barracks` | War hall | `WAR` printed; card glyph shared with tower and outpost, `src/ui/icons.lua:11` |
| `tower` | Watchtower | `T` printed; shared glyph |
| `extractor` | Extractor | `MINE` printed; has its own headframe glyph, `src/ui/icons.lua:13` — the one building glyph that is already specific |
| `outpost` | Outpost | `OUTPOST` printed; shared glyph |

### Tooltip ownership (3)

| Key | Meaning | Drawn today |
|---|---|---|
| `own`, `enemy`, `neutral` | Whose entity the tooltip describes | The words `Yours` / `Enemy` / `Neutral`, `src/ui/tooltip.lua:32`, coloured at `src/ui/tooltip.lua:28` |

---

## Tier 2 — a generic or duplicated stand-in already exists

Something is drawn, but it is wrong, or it is the same picture as something else. 45 symbols.

### Unit icons (9)

Each serves both `recruit-<id>` on the command card and the selection tile. All nine draw
the same generic figure today (`src/ui/icons.lua:17`). Ids and labels from `src/content.lua`.

| Key | Label | Faction | Role |
|---|---|---|---|
| `worker` | Worker | both | Builds, and is the only HQ-trained unit |
| `shield` | Shieldguard | Bastion | Melee line |
| `crossbow` | Crossbow | Bastion | Ranged, 5 cells |
| `medic` | Standard bearer | Bastion | Healer; needs HQ advancement |
| `siege` | Ram | Bastion | Heavy melee; needs HQ advancement |
| `stalker` | Stalker | Wild Pact | Fast melee |
| `thorn` | Thorn thrower | Wild Pact | Ranged, 4.5 cells |
| `sprite` | Grove sprite | Wild Pact | Healer; needs HQ advancement |
| `beast` | Heavy beast | Wild Pact | Heavy melee; needs HQ advancement |

The three neutral camp units — `neutral` (Camp guard), `scout` (Camp scout), `leader` (Camp
leader) — are never recruited and appear only in the inspect card. They are optional; a
single shared `neutral-camp` icon would do.

### Hero art (4)

| Key | Meaning | Drawn today |
|---|---|---|
| `portrait-warden` | Bastion hero bust, 38×42 | Procedural polygons, `src/ui/icons.lua:20-27` |
| `portrait-beastkeeper` | Wild Pact hero bust, 38×42 | The same polygons; the two heroes differ by **one colour channel** (`src/ui/icons.lua:23`) |
| `warden` | Hero icon at card and tile size | Generic figure |
| `beastkeeper` | Hero icon at card and tile size | Generic figure |

### Ability icons (4)

All four draw the same framed plus (`src/ui/icons.lua:6`). Definitions in `src/content.lua`.

| Key | Ability | Hero | Card slot | Aim |
|---|---|---|---|---|
| `ability-bulwark` | Bulwark | Warden | 2 | No target; allies within 6 cells take 4 less damage for 8 s |
| `ability-challenge` | Challenge | Warden | 3 | One enemy unit; 60 damage and −35% speed for 4 s |
| `ability-thornfall` | Thornfall | Beastkeeper | 2 | Ground circle; 30 damage then a burn |
| `ability-snare` | Snare | Beastkeeper | 3 | Aimed line; 35 damage and a 3 s root on the first enemy hit |

Slots are fixed by content and validated unique per unit (`src/content_validate.lua:63-73`),
so a player learns the position as well as the picture — the art has to carry the difference
on its own.

### Upgrade icons (12)

Three tiers, two mutually exclusive choices per tier, per faction. Effects from
`src/ui/actions.lua:163-166`.

| Key | Faction | Tier | Choice | Effect |
|---|---|---|---|---|
| `upgrade-bastion-1-1` | Bastion | 1 | Wide protection | Protection radius 6 → 8 cells |
| `upgrade-bastion-1-2` | Bastion | 1 | Deep protection | Protection reduces damage by a further 2 |
| `upgrade-bastion-2-1` | Bastion | 2 | Vanguard damage | Attack damage +6 |
| `upgrade-bastion-2-2` | Bastion | 2 | Guardian health | Max and current health +240 |
| `upgrade-bastion-3-1` | Bastion | 3 | Quick attacks | Attack period −4 ticks |
| `upgrade-bastion-3-2` | Bastion | 3 | Enduring aura | Protection radius +2 cells |
| `upgrade-wild-1-1` | Wild Pact | 1 | Rapid recovery | Out-of-combat recovery 8 → 14 per second |
| `upgrade-wild-1-2` | Wild Pact | 1 | Opening sprint | +4 speed for 2 s on entering combat |
| `upgrade-wild-2-1` | Wild Pact | 2 | Predator damage | Attack damage +6 |
| `upgrade-wild-2-2` | Wild Pact | 2 | Ancient health | Max and current health +200 |
| `upgrade-wild-3-1` | Wild Pact | 3 | Quick attacks | Attack period −4 ticks |
| `upgrade-wild-3-2` | Wild Pact | 3 | Pack recovery | Nearby allies recover 4 health per second out of combat |

A learned choice stays on the card in green and the excluded one stays in grey
(`src/ui/actions.lua:91`, drawn `src/ui/widgets.lua:23`), so each icon must still read when
desaturated.

### Missing command glyphs (3)

| Key | Command | Drawn today |
|---|---|---|
| `hold` | Stand still and fire; never chase | Generic figure (`src/ui/actions.lua:99`) |
| `patrol` | Walk a beat and engage along it | Generic figure (`src/ui/actions.lua:104`) |
| `cancel-research` | Stop HQ advancement, refund 50% | Generic figure — misses the `cancel` branch (`src/ui/actions.lua:119`) |

`move`, `attack`, `stop`, `cancel`, `build-menu`, `back-card`, `research`, `abilities` and
`extractor` all have specific glyphs already (`src/ui/icons.lua:5-16`). They are candidates
for a redraw in the final style, not gaps.

### Status effect icons (6)

**The one slot the code already reserves.** The 5×5 positions at `src/app.lua:487-492` are
exactly where these drop in; the comment at `src/app.lua:45-47` says so. Definitions in
`src/content.lua`; current swatch colours at `src/app.lua:48-49`.

| Key | Status | What it does | Current swatch |
|---|---|---|---|
| `guard` | Guard | Beneficial; reduces damage per hit | green |
| `slow` | Slow | Speed penalty | pale blue |
| `root` | Root | Cannot move | blue |
| `stun` | Stun | Cannot move, attack or cast | violet |
| `burn` | Burn | Periodic damage | orange |
| `status-other` | Fallback for any status with no icon | white |

Statuses are public in both directions (`src/sim/init.lua:356-361`), so a stunned enemy must
read as stunned from across the screen at 5 px.

### Minimap markers (7)

All bare geometry today (`src/ui/minimap.lua:101-104`), with a hero and a gold mine both
drawn as diamonds and every non-hero unit as the same dot.

| Key | Meaning | Drawn today |
|---|---|---|
| `map-hero` | Hero | Large diamond — the same shape as a gold mine |
| `map-worker` | Worker | 1.8 px dot |
| `map-melee` | Melee unit | The same dot |
| `map-ranged` | Ranged unit | The same dot |
| `map-building` | Building | 5×5 square, outlined when remembered rather than seen |
| `map-gold` | Gold mine | Small diamond |
| `map-control-point` | Control point | Circle outline in the owner's colour |

Markers are drawn in the owner's colour and dimmed when remembered
(`src/ui/minimap.lua:98-99`), so each shape must survive being greyed and shrunk.

---

## Tier 3 — nice to have

Works adequately as geometry; improves with art. 18 symbols.

| Key | Meaning | Drawn today |
|---|---|---|
| `rally-flag` | Where a building sends new units | Vertical line and a triangle, `src/app.lua:669` |
| `cursor-arrow`, `cursor-move`, `cursor-attack`, `cursor-build`, `cursor-invalid` | Pointer state | Procedurally rasterised ImageData, `src/ui/input.lua:261-283` |
| `order-move`, `order-attack`, `order-patrol`, `order-cast` | What was ordered, at the destination | Contracting ellipses coloured by `ORDER_COLORS`, `src/app.lua:35-37`, drawn `src/app.lua:570-587` |
| `placement-valid`, `placement-invalid` | Building ghost verdict | Green or red rectangle with hatching, `src/app.lua:650-656` |
| `node-amount` | Gold remaining in a mine | Nothing in the world; text in the inspect card, `src/ui/hud.lua:174` |
| `carrier-payload` | This carrier is worth intercepting | Gold chevron polygon, `src/app.lua:440` — see the findings below |
| `replay-play`, `replay-pause`, `replay-back`, `replay-forward` | Playback transport | The words `Play`, `Pause`, `-10s`, `+10s`, `src/ui/hud.lua:136-140` |

---

## Pips and bars

Drawing-code rules rather than art, recorded here because they answer the same question the
icons do. **Every bar in the game today is one `rectangle('fill')` scaled by a ratio. There
are no segments anywhere.** The decision taken is Warcraft 3 style: notched bars, so damage
reads as notches lost, and a unit's toughness reads from its notch count before it is
touched.

| Bar | Today | Becomes |
|---|---|---|
| Unit health, 28×4 world px | Solid fill, `src/app.lua:473-477` | Notched; notch count from max HP |
| Hero health in the dock, 145 px | Solid green, `src/ui/hud.lua:45` via `bar()` at `src/ui/hud.lua:11-13` | The same notch count, wider notches |
| Mana, 28×3 world px | Solid blue, `src/app.lua:482-484` | Notched, one notch per fixed mana chunk |
| Construction progress | Solid gold, `src/app.lua:414-415` | Notched, so progress reads without watching |
| Hero XP | Solid, `src/ui/hud.lua:54` | Notched per tier, with the level chevrons beside it |
| Production progress | Solid, `src/ui/hud.lua:104-108` | Notched; the queue slots themselves become pips |
| Per-unit tile health, 4 px | Lerped red-to-green fill, `src/ui/hud.lua:206-208` | Already pip-shaped — keep as is |

### Proposed notch counts — defaults, the user's call

Notch sizes are balance-adjacent, so these are proposals with a recommendation, not
decisions. They were chosen against the real values in `src/content.lua`.

**Units: one notch per 100 max HP, clamped to 3–10 notches.** On the 28 px world bar that is
2.8–9.3 px a notch, wide enough for a one-pixel gap. It gives:

| Unit | Max HP | Notches |
|---|---|---|
| Worker | 220 | 3 (clamped) |
| Grove sprite | 250 | 3 (clamped) |
| Thorn thrower | 280 | 3 |
| Crossbow | 320 | 3 |
| Stalker | 340 | 3 |
| Shieldguard | 420 | 4 |
| Heavy beast | 760 | 8 |
| Ram | 900 | 9 |
| Beastkeeper | 900 | 9 |
| Warden | 1000 | 10 |

A worker, a crossbow and a stalker all land on three notches, which is right — they die to
about the same amount of attention. The heavies separate clearly.

**Buildings: one notch per 300 max HP, clamped to 3–10.** Watchtower 700 → 3, Extractor
900 → 3, Outpost 1400 → 5, War hall 1500 → 5, Headquarters 2800 → 9. Buildings do not draw a
health bar at all today — see the findings below.

**Mana: one notch per 25.** Both heroes have 200, so eight notches, and each of the four
abilities costs between 45 and 70 — roughly two to three notches, which is the number a
player actually wants to count.

**Construction and production: ten notches, fixed**, since they are a fraction of a whole
rather than an amount.

Check these against `src/content.lua` again when the change is implemented; unit HP moves
with balance.

### Other pips

| Pip | Meaning | Today |
|---|---|---|
| Level chevrons | Hero level 0–3 | Text `Level 2`, `src/ui/hud.lua:59` |
| Status strip | Active statuses, one per slot | Already a pip row of 5×5 swatches, `src/app.lua:487-492` — gets icons, keeps the geometry |
| Control-group badge | Which group 1–9 a selected unit belongs to | A printed digit on a rounded rect, `src/app.lua:495-500` |
| Tier badge | Upgrade tier 1–3 | Text `T1`, `src/ui/widgets.lua:17` |
| Queue slots | Position in a production queue of up to 5 | Text buttons, `src/ui/hud.lua:102` |

---

## Open decisions

1. **Where icon files live** — widen `safePath` to a tracked `assets/ui/`, or pack them
   through `tools/assets` into the generated catalog. See *Where the files go* above.
2. **Faction-qualified upgrade keys** — recommended, and assumed by the twelve rows above.
   It is a change to `src/ui/actions.lua:88`.
3. **Notch counts** — the defaults proposed above.
4. **Whether neutral camp units get their own icons**, or share one `neutral-camp`.
5. **Whether the card icon slot grows from 10 px to 32 px**, which changes the button layout
   at `src/ui/hud.lua:122-124` and `src/ui/widgets.lua:16-22`.

## Adjacent findings

Three defects found while auditing, recorded so they are not lost. None is an icon problem
and none was fixed here; each wants its own task.

1. **The `work` animation clip can never play.** `src/asset_frames.lua:46` selects it on
   `order.kind=='harvest' and e.harvestRemaining`, but `harvestRemaining` is never written by
   the simulation and is not in `VIEW_FIELDS` (`src/sim/init.lua:309-315`). The clip is
   required by the catalog validator for `worker` and `worker_loaded`
   (`src/asset_catalog.lua:43`), is authored in `art/recipes/worker.json`, and ships in the
   atlas — it is built, paid for, and unreachable.
2. **The carrier payload chevron is invisible to the enemy.** `src/app.lua:440` gates it on
   `payload`, an owner-only view field (`src/sim/init.lua:317`), so the intent stated in the
   comment at `src/app.lua:421-423` — that an enemy can see what a convoy is worth cutting —
   is not achieved.
3. **Buildings never draw a health bar.** The bar block at `src/app.lua:472-477` sits inside
   the unit branch, so a damaged building reads only in the HUD card. This is why the
   building notch counts above are a proposal for a bar that does not exist yet.
