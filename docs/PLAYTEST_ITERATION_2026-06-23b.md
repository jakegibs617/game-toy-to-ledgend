# Playtest Iteration 2 — 2026-06-23

## Goal
Verify whether the Iteration 1 HUD wall-prompt changes improved the agent's wall
choices, and identify the next highest-impact stall in the current build.

## Build Context
Iteration 1 shipped focused-wall HUD prompts that translate wall state into
action language (open wall, already yours, rival-held, cleanup-buffed, neutral).
These appear only after the player focuses a wall, not before.

## Playtest Setup
- Model: qwen3:14b
- Mode: text-only (--no-vision)
- Turn count: 50 turns (baseline run 2)
- Starting state: fresh save (save files deleted before launch)
- Commit: main branch as of 2026-06-23

## Progression Result
- Opening chain: ✓ Complete — turns 1–21 ran cleanly
- Paint 3 different walls: ✗ 1/3 walls painted — stalled in actor nav turns 29–46, then no eligible wall within 14m; navigating to a 37m wall when turns ran out
- Rival retake: ✗ Not reached
- Crew-piece objective: ✗ Not reached
- Later objectives: ✗ Not reached

## What the Agent Did
Turns 1–3: Alias modal confirmed via `paint`, navigated to wall_median_01, painted first tag.
Turns 4–8: Returned to safehouse, went back to check tag, painted throw-up.
Turns 9–12: Visited Lupe, bought supplies, cycled fill color.
Turns 13–21: Met Moth, recovered blackbook from north alley, returned it. Chain unlocked "Paint 3 different walls."
Turn 22: Chose `goto_wall` — server navigated to wall_corner_01.
Turn 24: Painted wall_corner_01 (throw-up). 1/3 walls complete.
Turns 25–28: Chose `move` (four times) — exploring to find the next wall, but `nearby_walls` had no useful guidance. Model chose `move` because it couldn't evaluate wall eligibility without owner or category info.
Turn 29: Chose `goto_actor` — misdirected to a non-objective actor at ~4m (likely a bench or ambient NPC).
Turns 30–45: Stuck with active actor nav at nav_d=4m. Harness overrode every model action to `wait`. Stuck oscillated 13–82 as sidesteps fired. Old actor-nav-stop only covered "own the block" objective — did not fire.
Turn 46: Force-stop fired (same_obj=23, stuck_frames=82). Nav cancelled.
Turn 47: Close-wall aim redirect aimed at wall_corner_01 (1.8m). Paint blocked: correctly blocked by "different walls" guard (wall in all_painted_walls). Also, wall_corner_01 was buffed by city cleanup.
Turns 48–49: No eligible alt wall within 14m → empty goto_wall sent; server picked a wall 37m away.
Turn 50: Still navigating to 37m wall. Max turns reached.

## Three-Move Planning Moments
- Turn 23 (post-nav to corner_01): planned reach wall_corner_01 → aim → paint. Executed correctly.
- Turn 8: planned reach objective wall → aim → paint throw-up. Executed correctly.
- Turn 34: planned alternate wall target, correct reasoning, but harness override to `wait` blocked it.

## One-Move Planning Moments
- Turn 1: alias modal → `paint`. Correct.
- Turn 11: Lupe in range → `interact`. Correct.
- Turn 18: blackbook in range → `interact`. Correct.
- Turn 37: intended `aim_at` (reacting to new context), blocked by active actor nav.

## Wall Meaning Findings
- Open walls (alley_n_01, alley_n_02): not visible in `nearby_walls` during the post-paint wander (distance > NEARBY_RADIUS=14m or model chose moves in wrong direction).
- Player-owned wall (corner_01): no `owner` field in `nearby_walls`, so model couldn't exclude it when choosing the next wall target. Model chose `move` instead of `goto_wall` with a different wall.
- Rival-held walls: not observable without `owner` field.
- Territory-neutral walls: `territory_neutral` was already exposed; the model did not engage this field during the stall.
- Wall categories: `wallCategory` not exposed in `nearby_walls`, so model couldn't differentiate open_wall vs community_wall vs landmark during free-roam selection.

## Culture / Narrative Findings
- Writer ethics: not tested beyond the opening chain.
- Graffiti hierarchy: agent correctly upgraded from tag to throw-up on objective cue.
- Reputation vs heat: model tracked both correctly during the opening chain.
- Mentor feedback: not reached.
- Rival reaction: not reached.
- Crew identity: Moth recruited successfully; crew-piece not reached.
- Tone: opening dialogue lines were noticed and noted positively.

## Bugs Found
- Actor-nav-stop harness fix only covered "own the block" objective; "Paint 3 different walls" got no recovery, causing a 20+ turn stall.

## Stalls / Loops
- Turns 29–50: 21+ consecutive turns stuck in actor nav during "Paint 3 different walls." Root cause: model chose `goto_actor` when confused (no wall info after first paint), and no harness recovery existed for this objective type.

## Confusing Moments
- After painting wall_corner_01, the model had no way to distinguish player-owned walls from blank ones in `nearby_walls`. It chose `move` (exploration) rather than targeting another wall, then switched to `goto_actor` when no useful options were visible.

## Positive Moments
- Opening chain (alias → tag → throw-up → Lupe → Moth → blackbook) completed in 21 turns with no stalls. This entire sequence is now stable.
- The `paint_objective` macro continued to handle Lupe-mission beats cleanly.
- Model correctly used `one_move` planning for reactive moments (pickups, NPCs in range).

## Professional Critique
The opening mission chain is now stable and shows real design clarity — objective hints, `paint_objective`, and Moth's recruitment all flow without friction. The prototype breaks down precisely at the first free-roam objective: "Paint 3 different walls." Without `owner` and `wallCategory` in `nearby_walls`, the model cannot distinguish the wall it just painted from a blank target, and has no basis for choosing direction. The actor-nav-stop gap compounds this: once the model latches onto a non-objective actor, nothing recovers it until the 50-turn limit.

## Top Recommended Improvements
1. **Add `owner` and `wallCategory` to `nearby_walls` observation** — highest impact. Model has no data to choose the next wall after painting the first. (Implemented in Iteration 2.)
2. **Extend actor-nav-stop to all free-roam objectives** — fixes the 20-turn stall at turns 29–50. (Implemented in Iteration 2.)
3. **Add jump to stuck-sidestep recovery** — low cost; helps when geometry traps block the sidestep from making progress. (Implemented in Iteration 2.)
4. Update AGENT_CHEATSHEET.md to explain new `owner` / `wallCategory` fields so the model knows to use them.
5. Consider expanding NEARBY_RADIUS from 14m to 18–20m so the model sees more walls when exploring after a paint.

## Development Decision
All three fixes were implemented in this session (Iteration 2):
- `agent_server.gd`: `_nearby_walls()` now exposes `wallCategory` and `owner`; `_update_stuck` adds a brief jump with the sidestep.
- `pilot.py`: actor-nav-stop extended from "own the block" only to all free-roam objectives (fires at same_obj >= 5 if dist <= 2.5 or same_obj >= 12).
- `AGENT_CHEATSHEET.md`: new nearby_walls fields documented with decision guidance.

---

# Post-Fix Playtest — 2026-06-23 (same day)

## Playtest Setup
- Model: qwen3:14b
- Mode: text-only (--no-vision)
- Turn count: 50 turns (post-fix run)
- Starting state: fresh save
- Build: main + Iteration 2 fixes (agent_server.gd + pilot.py + AGENT_CHEATSHEET.md)

## Progression Result
- Opening chain: ✓ turns 1–21 (identical to baseline)
- Paint 3 different walls: ✓ Complete — 3/3 walls by turn 33
- Rival retake: ✓ Complete — turn 34
- Crew-piece objective: ✓ Complete — turn 48
- Own the block: started turn 49; max turns reached while navigating

## What Improved vs Baseline
- Baseline: 1/3 walls painted, stalled turns 29–50 in actor nav
- Post-fix: 3/3 walls, rival retake, crew piece — all objectives cleared in 50 turns

## Key Moments
- Turn 23 three-move plan: "After painting, seek new walls (prefer 'city' or 'rival' owned walls with `territory_neutral: false`)" — model explicitly reading and using the new `owner` field.
- Turn 28–29: Owned-wall redirect fired for wall_corner_01 (player-owned). Previously this redirect was missed because focus was empty. New `owner` field in `nearby_walls` confirmed the wall state, enabling the redirect.
- Turn 29: Harness redirected to goto_wall → server picked wall_landmark_01 (34m, vis=5).
- Turn 31: Painted wall_landmark_01 (+121 rep). Model three-move plan: "Navigate to wall_loading_01 next (rival-owned but city-buffed) / Secure third via wall_alley_n_01 to demonstrate territory takeover." Model is chain-planning using category+owner data.
- Turn 33: Painted wall_loading_01 (3/3 walls). Objective → "A crew hit your wall — take it back!"
- Turn 34: Repainted rival-held wall_loading_01. Objective → "Put up a piece with your crew."
- Turn 36–48: Navigated to wall_alley_n_01 for crew piece. Stuck at 4m for ~12 turns. Wall-skip fired turn 46 → redirected to wall_alley_n_02. Piece painted at turn 48. Objective → "Own the block."
- No `goto_actor` misdirection during "Paint 3 walls" or crew-piece phase. Actor-nav-stop extension appears to have discouraged actor selection.

## Remaining Issues in Post-Fix Run
- Crew-piece phase: 12-turn stuck at wall_alley_n_01 (turns 38–47). Same geometry-stall pattern. Wall-skip recovered it, but 12 turns wasted.
- The free-roam actor-nav-stop fix was not explicitly triggered this run (no `!! harness: free-roam actor-nav stop` line), but the owned-wall redirect and cheatsheet changes prevented the model from choosing `goto_actor` in the first place.
- Turn 49 shows the influence grind just starting; not enough turns to complete.

## What Confirmed Working
- New `owner` field: model used "player/rival/city/open" language in planning from turn 23 onward.
- New `wallCategory` field: model referenced "buffed city wall" and "rival-stenciled open wall" in plans at turns 31–33.
- Owned-wall redirect: fired immediately at turn 28 instead of waiting 20+ turns.
- AGENT_CHEATSHEET guidance: model explicitly quoted the new decision rule ("prefer city/rival, avoid player") in its three-move plans.

## Top Recommended Next Targets
1. Address the crew-piece geometry stall at wall_alley_n_01 (12 turns). Investigate why nav_d stays at 4m for so long before the wall-skip fires. The jump-in-sidestep should help but may need more turns to trigger.
2. Start the influence grind test — the post-fix run reached "Own the block" but ran out of turns. Need a 60–70 turn run to see if the grind completes cleanly.
3. Increase NEARBY_RADIUS from 14m to 18m — the model still recommends "add more walls to nearby_walls" when exploring; a wider radius would reduce the 34m dead-reckoning goto_wall calls.
---

# Follow-up Verification / Iteration 3 - 2026-06-23

## Trigger
A fresh 70-turn influence verification attempt reproduced a different blocker
before influence could be proven. After painting `wall_corner_01`, the player
got physically blocked near the owned wall (observed as another NPC/local
obstacle in the path). The pilot then kept trying far `goto_wall` targets while
still focused on `wall_corner_01`.

## Failed Run Snapshot
- Model: qwen3:14b
- Mode: text-only (--no-vision)
- Intended turn count: 70
- Stopped manually: turn 39 after the blocker was clear enough to diagnose
- Progress: opening chain clean through turn 21, first free-roam wall painted
  turn 24, then stalled around turns 29-39 near `wall_corner_01`
- Key log details:
  - Turn 28: bad `goto_actor`/missing actor target recovered into `goto_wall`
  - Turns 29-33: `nav_d=37m`, stuck frames rising, still near/focused on
    `wall_corner_01`
  - Turn 34: `wall-unstick back from 'wall_corner_01'`, with
    `wall_landmark_01` in skip
  - Turns 37-39: paint repeatedly blocked on `wall_corner_01` while no useful
    local alt was visible

## Fix
`Scripts/Debug/agent_server.gd` stuck recovery now escalates instead of repeating
the same side-step:
- First stuck escape: side-step + jump
- Second stuck escape: back + side + jump
- Third stuck escape: run + back + side + jump

The fix also releases `move_forward` before the escape so the player does not
continue pressing into the NPC/obstacle while trying to dodge.

## Post-Fix Verification
- Model: qwen3:14b
- Mode: text-only (--no-vision)
- Turn count: 45
- Starting state: fresh save
- AGENT=1 launch: pass, no parse errors in captured stderr

## Progression Result
- Opening chain: complete through turn 21
- Paint 3 different walls: complete by turn 35
- Rival retake: complete turn 36
- Crew-piece objective: complete turn 38
- Own the block: reached turn 39
- Influence grind: painted `wall_landmark_01` turn 41 and `wall_median_01` turn
  44; max turns reached on turn 45 before objective completion

## Notes
- The exact turn-29-to-39 blocker did not recur after the stronger unstick.
- The post-fix route used `wall_mill_glass_01` as one of the three different
  walls. It appears to count for the objective, but it is territory-neutral and
  does not help the later influence objective.
- The influence chain is still not fully verified. Next run should be 60-70
  turns with this unstick patch applied.
