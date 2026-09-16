# Game feel: the standard, and what to try next

Feel changes are cheap to make and easy to argue about for ever. This file fixes what "better"
means here, so an iteration can be judged without a playtest argument, and so a change nobody can
judge is not attempted in the first place.

It is written against what the game already does. Interpolation between ticks, health trails,
order markers, rally lines, screen shake, alert merging and per-cue audio cooldowns all exist;
the backlog below is what is missing or worth tuning, not a wish list.

## The contract

Seven rules. Each one is measurable, and each already has something that enforces it.

1. **The game answers the click, not the simulation.** Every accepted order shows its answer in
   the frame it was clicked: the marker, the unit flash, one sound. `tests/control_input.lua`
   prints the acknowledgement delay at 30, 60 and 144 FPS; it is currently 1 tick (50–67 ms)
   offline and 4 ticks (200–233 ms) in lockstep. The *answer* must not grow with input delay.
   Only the unit's movement may.
2. **One answer per order.** One flash, one sound, one marker. Never a second cue when the
   simulation later executes the order (improvement-loop iteration 1).
3. **Anything that changes the world is visible within 200 ms and audible at most once.** Four
   ticks. Repeated notices merge; per-key cooldowns and the four-item cap bound the rest.
4. **The camera moves only when the player moves it.** Alerts never recentre unless the player turned
   on Camera to alerts. Bookmarks, minimap
   clicks and the alert key do, because the player asked.
5. **Cosmetics never touch the simulation.** Every rendered test asserts `Sim.serializeCanonical`
   is unchanged across draws. A feel change that needs simulation state is not a feel change.
6. **Feedback is bounded.** At most 256 live effects and 32 audio sources, asserted by the UI
   benchmark, so a hundred deaths at once cannot cost a frame.
7. **No placeholder art or audio.** Wire the hook — an event, a cue name, a marker slot — and
   leave the asset to the user.

## Budgets

| Moment | Budget | Measured by |
|---|---|---|
| Click to visible answer | ≤ 1 frame | `tests/control_input.lua` |
| Click to sound | ≤ 1 frame | same |
| Click to the unit moving, offline | ≤ 3 ticks (150 ms) | same |
| Click to the unit moving, lockstep | ≤ input delay + 2 ticks | same |
| World event to its effect on screen | ≤ 4 ticks (200 ms) | rendered captures |
| Alert readable on screen | ≥ 2 s, merged if repeated within 1 s | `src/ui/alerts.lua` |
| Draw submission, 240 units at 1080p | ≤ 8 ms p95 cold | `--ui-benchmark` |
| Live effects / audio sources | ≤ 256 / ≤ 32 | UI benchmark asserts |

A change that breaks a budget is not shipped because it looks nicer.

## How to run one iteration

1. **Name the moment** in one sentence: "the click that starts a march", "the last hit on a
   building", "an army walking into a wall".
2. **Record what happens now.** A capture from `scripts/test-presentation.ps1`, plus the INPUT
   numbers if the moment involves input.
3. **Change one thing.** Not two.
4. **Prove it**: a test that fails without the change, a capture that shows it, the INPUT numbers
   no worse, and canonical state unchanged across draws.
5. **Judge against the contract**, not taste. If none of the above can settle it, the change is
   art, audio or balance: hand it to the user with a recommendation and stop.
6. **Revert if nothing moved.** A feel change that cannot be seen in a capture or a number is not
   a feel change.

## Choosing what is next

Rank by `(how often a player meets it) × (how sure we are it is wrong now) ÷ cost`, and prefer
changes that need no simulation version bump, because those are reversible in one commit.

- **Free**: presentation only. No simulation change, no version bump, no replay invalidation.
- **Cheap**: simulation, but no content or balance number moves.
- **Costly**: balance, content or art. The user decides, always.

## Backlog

Ranked, with where each item stands after the first feel pass (2026-09-16). Everything marked
Free is presentation-only and reversible; none of it moved the simulation version. Each change
has a check that was confirmed to fail with the change removed.

| # | Change | Tier | Status |
|---|---|---|---|
| 1 | **Hit flash.** A unit that takes damage tints for 2–3 frames. | Free | **Already existed** before the pass: `Feedback:flashing`, drawn in `src/app.lua`. The audit that wrote this list missed it. |
| 2 | **Health bar chip.** Hold the trail 300 ms, then drain over 200 ms, so the amount lost is readable. | Free | **Done**, batch A (0ca3aa0). Repeated hits keep the hold going for at most 1 s. |
| 3 | **Order marker by kind.** Colour and shape per kind — move, attack-move, patrol. | Free | **Done**, batch A. The marker only changed colour for rejected orders before; it now has a colour per order and a cross for a direct attack. |
| 4 | **Formation ghosts.** After a group order, show the assigned slots as faint dots for ~1 s. | Free | **Done**, batch A. Drawn from the orders the simulation accepted, for groups of two or more. |
| 5 | **Selection pop.** Selection rings scale 1.15 → 1.0 over 80 ms. | Free | **Done**, batch A. |
| 6 | **Low-health pulse** on your own units under 30%. | Free | **Done**, batch B (6882497). Drawn directly, not as an effect, so the effect cap is untouched. |
| 7 | **Queued waypoints.** Shift-queued orders draw through their waypoints while selected. | Free | **Already existed**: the order line loop in `src/app.lua` draws the current order and every queued one. |
| 8 | **Unit turning.** Stop a turning unit flickering between two of the eight headings. | Free | **Done**, batch B, as hysteresis rather than interpolation: a unit keeps its heading until it has turned 15° past the boundary. Interpolating between eight drawn headings would have fought the art. |
| 9 | **Edge scroll curve.** Acceleration and a speed setting, matched to keyboard scrolling. | Free | **Done**, batch C (b08d8f4). Edge and arrow keys share one ramp (40% → 100% over 0.33 s); **Scroll speed** is Slow / Normal / Fast in Settings. |
| 10 | **Fog edge softening.** | Free | **Done**, batch C: the fog texture is sampled linearly, a half-cell feather for no extra upload. |
| 11 | **Minimap damage flash** when something of yours is hit off-screen. | Free | **Done**, batch C: "Your forces are under attack", one per 12-cell area, merged and cooled down like every alert, and ringed on the minimap. |
| 12 | **Cue names per unit kind** for select, order and attack. | Free | **Done**. Orders already had `ack-<kind>-<order>` and `ack-<kind>`; batch D adds `select-<kind>`. Attacks stay on the shared `attack` cue, since a per-kind impact is item 15's art. |
| 13 | **Camera nudge on alert**, off by default. | Free | **Done**, batch C: **Camera to alerts** in Settings, off by default. Only attacks on your hero, headquarters or forces move it. |
| 14 | **Attack windup anticipation.** | Free | **Done**, batch B: the attacker swells by up to 7% through the windup. Timing unchanged. |
| 15 | **Impact dust, footfalls, unit chatter.** | Costly | **Hooks only**, listed below. The assets are the user's. |

Also fixed on the way: **Smart cast** was saved but never read back, so it reset on every launch.

## Hooks waiting for art and audio

Nothing below needs code to take effect.

- **Sound files.** Any entry in `A.manifest` (`src/ui/audio.lua`) plays a file when it gains a
  `path`; a missing or unreadable file keeps the synthesized tone.
- **Order voices.** `ack-<kind>-<order>`, then `ack-<kind>`, then `ack`. For example
  `ack-shield-attack`.
- **Selection voices.** `select-<kind>`, then `select`.
- **World cues.** `attack`, `death`, `ready`, `windup`, `alert`, `victory`, and the UI cues
  `click`, `accepted`, `rejected`.
- **Effects.** `src/feedback.lua` already raises `hit`, `tracer`, `windup`, `death`, `revived`,
  `healed`, `constructed`, `upgraded` and `ready` at the right entity and tick. Impact dust and
  footfalls belong on `hit` and on movement; chatter belongs on `select-<kind>` and `ack-<kind>`.
- **Sprites.** Unit art comes from the asset catalog (`src/asset_catalog.lua`, loaded by
  `src/sprites.lua`); see `tools/blender/README.md` for how a unit enters it.

## Not to do

- **Hit-stop or animation-driven pauses.** The simulation runs at a fixed 20 Hz for every peer;
  freezing it for feel breaks lockstep and replays.
- **Automatic camera moves**, including "helpfully" centring on an attack, except through the
  opt-in setting.
- **Placeholder assets** of any kind.
- **Reading presentation state back into the simulation.** Nothing in `src/ui` may write to the
  world; if a feel change seems to need it, the change is wrong.
