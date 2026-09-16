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
4. **The camera moves only when the player moves it.** Alerts never recentre. Bookmarks, minimap
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

Ranked. Everything marked Free is presentation-only and reversible.

| # | Change | Tier | How it is judged |
|---|---|---|---|
| 1 | **Hit flash.** A unit that takes damage tints for 2–3 frames. The `hit` effect already exists as a hook; nothing marks the victim. | Free | Capture at the impact frame; feedback test asserts one flash per hit, none on a miss |
| 2 | **Health bar chip.** `healthTrails` drains immediately; hold the trail 300 ms, then drain over 200 ms, so the amount lost is readable. | Free | Capture 300 ms after a hit; test asserts the trail lags the bar |
| 3 | **Order marker by kind.** One marker for every order today. Colour and shape per kind — move, attack-move, patrol — so the player can see what they told the army to do. | Free | Captures of all three; existing acknowledgement test unchanged |
| 4 | **Formation ghosts.** After a group order, show the assigned slots as faint dots for ~1 s. Makes the new formation behaviour legible instead of mysterious. | Free | Capture; slots come from the order, so no simulation read-back |
| 5 | **Selection pop.** Selection rings scale 1.15 → 1.0 over 80 ms instead of appearing. | Free | Capture at 40 ms; effect count unchanged |
| 6 | **Low-health pulse** on your own units under 30%, bounded by the effect cap. | Free | Capture; UI benchmark effect ceiling holds |
| 7 | **Queued waypoints.** Shift-queued orders draw a faint line through their waypoints while the unit is selected. | Free | Capture with three queued orders |
| 8 | **Unit turning.** Facing snaps between the eight sprite headings; interpolate the choice over ~100 ms so a turning unit does not flicker between frames. | Free | Capture mid-turn; watch for fighting the eight-direction art |
| 9 | **Edge scroll curve.** Acceleration and a speed setting, matched to keyboard scrolling. | Free | UI test drives the edge for 1 s and asserts distance and no overshoot |
| 10 | **Fog edge softening.** One-pixel feather on the fog texture; the boundary is currently a hard step. | Free | Capture; fog upload cost re-measured (it was 0.24 ms) |
| 11 | **Minimap damage flash** when something of yours is hit off-screen. The alert system already knows. | Free | Capture; merged with the existing alert, not a second cue |
| 12 | **Cue names per unit kind** for select, order and attack, wired but silent until the user records them. | Free | Audio stub test asserts the cue name asked for, one per action |
| 13 | **Camera nudge on alert**, off by default, since rule 4 forbids moving the camera unasked. | Free | Setting test; default off |
| 14 | **Attack windup anticipation.** The `windup` effect exists; give it a small scale so a swing reads before it lands. | Free | Capture at windup and impact; timing unchanged |
| 15 | **Impact dust, footfalls, unit chatter.** | Costly | User's art and audio; wire the hooks only |

## Not to do

- **Hit-stop or animation-driven pauses.** The simulation runs at a fixed 20 Hz for every peer;
  freezing it for feel breaks lockstep and replays.
- **Automatic camera moves**, including "helpfully" centring on an attack.
- **Placeholder assets** of any kind.
- **Reading presentation state back into the simulation.** Nothing in `src/ui` may write to the
  world; if a feel change seems to need it, the change is wrong.
