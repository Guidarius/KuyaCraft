# Command cards and feedback

The card follows the active subgroup, preferring a hero when the content has one, while shared orders apply to the complete owned selection. Tab changes the subgroup without dropping the army. Worker-only selections and an active worker subgroup expose Build and Harvest; a unit with abilities exposes them in fixed slots; production and orbital logistics follow the primary selected building. F1 focuses the headquarters, or the hero in the mechanics fixture.

## Menus and requirements

- The Megacorp's Orbital Command card: Requisition (B) opens a page of every building it may order from orbit; each item in the call-down queue is a button showing its time in orbit, and a ready one reads Land and arms a landing site, drawn over the relay-coverage tint; Cancel last refunds 75%. Blimp and Battleship train from the same card. A selected Battleship carries Barrage (W) in slot 2: click the sky to bombard a circle; it reads the seconds left while cooling down. Drop pod (P) opens the pod page: load Associate/Medic/Enforcer (Q/W/E), Launch (T) arms a covered landing point, Unload pod refunds the open pod. A Bunker or Office with troops inside offers Unload all (U); right-clicking one of your own garrison buildings with troops selected sends them inside.
- Worker Harvest is G: click a patch or geyser and the worker works it until it is empty. A laden worker also offers Return cargo (C). Right-clicking a patch with workers selected harvests it.
- Worker Build opens with B. The buildings and their keys come from the faction's `buildings` list (Orders: Keep, Supply Depot, Barracks, Sanctum on Q/W/E/R). One selected worker receives each construction order, and right-clicking a site with more workers adds them to it. Shift repeats queued placement. Escape first cancels placement, then closes the submenu.
- (Fixture heroes.) A hero uses U to open three rows of paired upgrades. Each row identifies its tier. Learned and mutually excluded choices stay visible; future tiers show XP and prior-tier requirements. Available choices open the existing permanent-choice preview before committing. XP is a threshold and is not spent.
- Grey actions show the reason in their tooltip. Cost components turn red individually when insufficient; full resource names and available amounts appear in tooltips. Resource totals briefly flash red after a failed purchase. Recruitment includes supply reservations, queue capacity, construction completion and the unit's `requires` buildings (`Requires Armory`), and for the Megacorp coverage and the pod limit. Revival, in the fixture, checks the living HQ, gold and existing revival timer.
- Building prerequisites come from content `requires` (Barracks needs a Keep, Sanctum a Barracks) and are shown as the grey reason. Ability cards show mana shortages and cooldowns in fixed slots. Z toggles stance (fixture) without conflicting with ability hotkeys.
- Selection changes close incompatible menus and targeting. Mouse and keyboard both re-evaluate the action before execution. The simulation remains the final authority for delayed commands, including resources consumed by another command first. Replay and ended-match actions remain read-only.

## The Megacorp's orbital sidebar

Orbital logistics have no building on the map to click, so they are never behind a
selection: a strip down the right edge of the battlefield is on screen for the whole match
(`src/ui/orbital.lua`; the battlefield is narrowed for it, not covered). Everything it
shows comes from one pure function, `Orbital.model(view, content)`, which the Command's card
reads too, so the two cannot disagree.

- **ORBIT n / 5**, and how many items are produced at once. Five frames, empty ones drawn,
  so capacity reads before anything is ordered. A frame is **producing** (clock wipe and
  seconds), **READY** (bright pulsing frame and the word; click it, then click covered
  ground), or **waiting** (dim, its place in the queue). A READY building keeps its
  production slot until it lands, so whatever waits behind it reads **blocked**, in words.
  Right-click a frame to cancel it for 75%; right-click the ground while landing and the
  building stays READY. Descents are listed with their countdowns; click one to look.
- **PODS**, a pip per pod that could ever fly: filled is away, hollow is free, a dot is
  locked until another Requisition Office stands. Four seat cells in the order the troops
  step out, a bar under a heavy unit; click a seat to take that unit out for a full refund.
  The **launch dial** has four looks that differ in shape as well as colour: lit LAUNCH, a
  sweep with seconds while cooling, a double ring when every pod is away (with when the
  next lands), a bare ring saying LOAD. The cooldown is shown even while loading.
- Keys from anywhere: **B** Requisition, **P** Drop pod (P stays Patrol while units are
  selected), **F9** arms the next READY building and cycles, **Shift** while landing arms
  the next one at once. The pages stay open so several orders can be made in a row.
- Aiming a pod shows the coverage tint and a ring that is green on covered ground and red
  off it; an uncovered click says so at the pointer and keeps the aim. The owner's descent
  markers carry the name and seconds; the minimap blinks a chevron at each; a finished
  building raises an alert that arms the landing when clicked. Cues: `ready_to_land`,
  `pod_ready` (the dial finishing with troops aboard), `landing`, `pod_launch`.

## Feedback and audio extension

Selection, menu navigation, movement, attack orders, building orders, cancellation, stance changes, hero upgrades and research completion have distinct synthesized cues. Existing combat, construction/recruitment readiness and alert cues remain. Priority, per-cue cooldowns, volume buses and a 32-source pool bound audio; positional source reuse resets panning before non-positional UI cues.

`src/ui/audio.lua` contains the cue manifest. A cue may supply a bundled `path` to an audio file while retaining its frequency/duration recipe as fallback. Missing files fail per cue and retain synthesized sound. Use original/licensed source audio and retain the existing gain, priority, cooldown and bus settings. No downloaded recordings are required for this delivery.

`src/ui/command_feedback.lua` owns brief card outlines, cost flashes and up to 16 world feedback marks. Invalid targets/placements show a short red cross. Order markers identify an issued intention; success audio is driven by the matching simulation acknowledgement. A delayed rejection cannot recolor the marker for a newer order group. Replay seeking clears these transients. All of this state is presentation-only.

## Historical verification (before integration)

- `scripts/test.ps1 -Suite unit`: 13 passed, zero failed, including selection-order invariance, worker/hero/mixed context, tech/resource/food/queue/prior-tier requirements, replay blocking and canonical-state preservation.
- `scripts/test-ui.ps1`: rendered checks at 1280x720, 1920x1080 and 2560x1080, each with existing 80/100/125% scale checks. New checks exercise disabled mouse/keyboard parity, submenu cancellation, permanent upgrade submission, late acknowledgements, bounded feedback, missing-file audio fallback and drawing without simulation changes.
- Generated evidence: `artifacts/command-card-unit.log`, `command-card-rendered.log`, `ui-build-card-<width>.png`, `ui-ability-card-<width>.png` and `ui-mixed-card-<width>.png`.

Static captures are visually reviewed. Subjective audio mix, continuous play feel and two-PC multiplayer remain human checks. No authoritative gameplay code or balance definitions change in this delivery; the full long-running gameplay/performance suites are not rerun for these presentation changes.

## Tooltips

`src/ui/tooltip.lua` builds and draws every tooltip; `src/ui/widgets.lua` decides which one is
showing. The rules:

- **Command card: at once, above the card.** The panel's bottom-right corner sits just above the
  card, so sweeping the pointer across the buttons swaps the text in place, as in Warcraft 3.
- **Everything else waits 0.35 s, then sits beside the pointer**: the resource bar, the hero
  panel, the minimap, selection tiles, the production queue, alerts, menu buttons, and whatever
  the pointer rests on in the world. After a tooltip has shown, the next one within 0.4 s
  shows at once.
- **Order of rows:** title and hotkey; whose it is or its tier; why it is unavailable (red);
  what it does; stats (dim); costs, each red with what you have when it is short. A learned
  hero upgrade is green, not an error.
- **Placement:** the panel never covers the pointer and never leaves the screen. It flips left
  or up at an edge and is pushed back on when even that is not enough.
- **Hidden** while dragging a selection box, panning, dragging the minimap, or placing a
  building. A modal panel (pause, settings, upgrade choice) clears anything under it.
- **World tooltips only show what the view carries.** An enemy hero's experience is private, so
  its level is not shown.
- Build and train tooltips take their stats and purposes from content (`Tooltip.statsFor`,
  `Tooltip.purpose`), so they cannot drift from the rules. Spell tooltips show cooldown and
  range, with how to aim on a dim line; the mana cost is in the cost row only.

A widget can pass a full spec as its `tip` instead of a string; see the comment at the top of
`src/ui/tooltip.lua`.
