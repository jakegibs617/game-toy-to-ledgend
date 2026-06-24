# Playtest Feedback Summary

## Build / Iteration
Iteration 1, local working tree on 2026-06-23.

## What the gaming agent attempted
The Ollama pilot played from a fresh save through alias confirmation, first tag, safehouse return, Lupe supplies, Moth recruitment, blackbook recovery, the 3-wall Mill Yard objective, rival retake, crew-piece objective, and early territory influence.

## 3-move planning moments
- Post-fix turn 23: while navigation was active and the objective was stable, the agent planned to reach `wall_corner_01`, aim, then paint.
- Post-fix turn 34: while focused on `wall_landmark_01`, it planned to paint that wall, move to a second wall, then find a third wall.
- Diagnostic turn 34: it reasoned that `wall_loading_01` was a valid unique wall for the 3-wall objective and painted it.

## 1-move reactive moments
- Post-fix turn 1: it used a one-move style to confirm the alias modal.
- Post-fix turn 18: it used a one-move style to pick up Moth's blackbook.
- Post-fix turn 37: it reacted to the rival-retake objective by immediately repainting the challenged wall.

## Bugs found
- The pilot often outputs three plan entries even when it selects `one_move`; the schema/prompt needs stricter validation or post-processing.
- During open wall objectives, `goto_wall` can restart or do nothing for several turns before the harness fallback forces a new global wall target.

## Confusing moments
- Mission-critical actors and pickups are not visually distinguished enough when optional prompts are nearby.
- Open multi-wall objectives do not clearly show which unfocused walls are blank, already yours, rival-held, or neutral.
- Territory-neutral walls are mechanically valid to paint but do not help territory control; this was unclear before the prompt fix.

## Fun or promising moments
- The first tag, throw-up upgrade, rival retake, and crew-piece beats all progressed through real input.
- Big reputation jumps on landmark/piece painting were noticeable and motivating.
- The rival retake objective created a clear retaliatory moment and the agent answered it immediately.

## Professional critique
The prototype's core graffiti RPG loop is present and playable: paint, earn rep, get rival pressure, recruit crew, and claim territory. The weakest part is communication before the player focuses an object. Once focused, the new wall prompt helps explain territory value, but players still need spatial guidance to identify the next meaningful wall or objective target without wandering or relying on the map/harness.

## Top recommended improvements
1. Add lightweight in-world wall-state indicators for open, owned, rival-held, and neutral walls.
2. Add clearer mission/objective target markers for NPCs and pickups.
3. Show multi-wall objective progress and avoid repeats more explicitly.
4. Add stronger rival-retake feedback showing influence/control changed.
5. Tighten the Ollama playtest schema so `one_move` plans are logged as one step.

# Development Task List

## Critical
- [ ] Fix free-roam `goto_wall` no-progress loops when no wall is focused.

## High Impact
- [ ] Add in-world wall-state indicators for nearby paintable walls.
- [ ] Add objective target markers for current NPC/pickup targets.
- [ ] Add clear feedback when repainting a rival-held wall changes influence.

## Medium
- [ ] Show "different walls" progress and repeat-wall warnings in the HUD.
- [ ] Improve can-selection feedback when objectives say to press a slot key.

## Low / Polish
- [ ] Add color swatches or a small visual confirmation when cycling fill colors.

## Deferred
- [ ] Add more Mill Yard wall variety; current issue is clarity before content volume.
