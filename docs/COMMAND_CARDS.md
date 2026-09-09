# Command cards and feedback

The card evaluates the complete owned selection, independent of selection ordering. Only workers expose Build and Harvest; one hero exposes stance and the ability tree; a mixed army exposes shared movement/combat commands. One production building exposes its roster and research. Multiple buildings require narrowing the selection before production. Group badges in the dock show counts and let the player select a unit type.

## Menus and requirements

- Worker Build opens with B. Q/T/E/R select war hall/watchtower/outpost/lumber depot (the watchtower key follows Settings). One selected worker receives each construction order. Shift repeats queued placement. Escape first cancels placement, then closes the submenu.
- A lone hero uses U to open three rows of paired upgrades. Each row identifies its tier. Learned and mutually excluded choices stay visible; future tiers show XP and prior-tier requirements. Available choices open the existing permanent-choice preview before committing. XP is a threshold and is not spent.
- Grey actions show the reason in their tooltip. Cost components turn red individually when insufficient; full resource names and available amounts appear in tooltips. Gold/lumber totals briefly flash red after a failed purchase. Recruitment includes food reservations, queue capacity, construction completion and HQ advancement. Revival checks the living HQ, gold and existing revival timer.
- Current buildings have no additional technology prerequisites; this delivery displays existing rules rather than introducing new balance gates. The cost presenter supports resource keys plus an entity's mana field, but current content has no mana-consuming abilities.
- Selection changes close incompatible menus and targeting. Mouse and keyboard both re-evaluate the action before execution. The simulation remains the final authority for delayed commands, including resources consumed by another command first. Replay and ended-match actions remain read-only.

## Feedback and audio extension

Selection, menu navigation, movement, attack orders, building orders, cancellation, stance changes, hero upgrades and research completion have distinct synthesized cues. Existing combat, construction/recruitment readiness and alert cues remain. Priority, per-cue cooldowns, volume buses and a 32-source pool bound audio; positional source reuse resets panning before non-positional UI cues.

`src/ui/audio.lua` contains the cue manifest. A cue may supply a bundled `path` to an audio file while retaining its frequency/duration recipe as fallback. Missing files fail per cue and retain synthesized sound. Use original/licensed source audio and retain the existing gain, priority, cooldown and bus settings. No downloaded recordings are required for this delivery.

`src/ui/command_feedback.lua` owns brief card outlines, cost flashes and up to 16 world feedback marks. Invalid targets/placements show a short red cross. Order markers identify an issued intention; success audio is driven by the matching simulation acknowledgement. A delayed rejection cannot recolor the marker for a newer order group. Replay seeking clears these transients. All of this state is presentation-only.

## Verification

- `scripts/test.ps1 -Suite unit`: 13 passed, zero failed, including selection-order invariance, worker/hero/mixed context, tech/resource/food/queue/prior-tier requirements, replay blocking and canonical-state preservation.
- `scripts/test-ui.ps1`: rendered checks at 1280x720, 1920x1080 and 2560x1080, each with existing 80/100/125% scale checks. New checks exercise disabled mouse/keyboard parity, submenu cancellation, permanent upgrade submission, late acknowledgements, bounded feedback, missing-file audio fallback and drawing without simulation changes.
- Generated evidence: `artifacts/command-card-unit.log`, `command-card-rendered.log`, `ui-build-card-<width>.png`, `ui-ability-card-<width>.png` and `ui-mixed-card-<width>.png`.

Static captures are visually reviewed. Subjective audio mix, continuous play feel and two-PC multiplayer remain human checks. No authoritative gameplay code or balance definitions change in this delivery; the full long-running gameplay/performance suites are not rerun for these presentation changes.
