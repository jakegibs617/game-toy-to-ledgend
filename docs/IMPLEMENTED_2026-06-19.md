# Implemented — 2026-06-19

Development continued from current `main` and followed the branch → PR →
review → merge loop.

## Implemented Today

### PR #43 — Crew Loyalty & Role Upgrades

- Added saved crew loyalty (`crew.loyalty_by_member`, save v8).
- Crew now earns loyalty when roles visibly help: lookout warnings, getaway
  escapes, supply discounts/deliveries, crowd/nightclub hype, caught-penalty
  mitigation, and cleanup mitigation.
- Existing role bonuses now scale gently by loyalty while preserving the
  data-defined baseline around 50 loyalty.
- The blackbook Crew page shows loyalty, loyalty state, and role scale.
- Review found and fixed a migration edge: older saves seed from immutable
  member-data loyalty, not mutated runtime loyalty.

### PR #44 — Milestone 32: Battle Prototype Paper Cut

- Added `docs/BATTLE_PAPER_CUT_2026-06-19.md`.
- Compared dance, rap/verbal, and graffiti wall duel prototypes.
- Decision: no separate v3 battle minigame. The Undertow already covers the
  strongest 60-second timing interaction.
- Recommended post-candidate battle direction: rival wall duels tied to paint,
  territory, heat, crew, and rival stakes.

### PR #46 — Rival Wall Duels

- Implemented the post-M32 rival wall duel direction as a lightweight
  contested-wall callout instead of a separate battle minigame.
- Rival responses now open saved wall duels when they cross out or cover the
  player's work.
- Repainting the challenged wall answers the duel through the normal paint
  path, pays a small rep and crew-rep bonus, records wins/losses/streaks, and
  avoids instantly queueing another retaliation from the same answer stroke.
- Rival pending responses and active wall duels now save/load under a new
  `rivals` save section; save schema bumps to **v9** with migration.
- The blackbook City page shows wall-duel record and active callouts.
- Review found and fixed a direct-response state bug: scripted/direct
  `RivalManager.respond()` now clears stale pending entries just like timed
  responses.

### PR #47 — Safehouse Rest

- Added the first safehouse-depth slice: `R` at the focused safehouse zone
  rests while `E` still opens the crew board.
- Resting advances the existing heat/cleanup clock, runs one territory upkeep
  tick, restores a small amount of paint, records `game.safehouse_rests`, and
  shows one compact HUD outcome message.
- `HeatManager` and `TerritoryManager` now expose small public tick-advance
  helpers for scripted time skips.
- Save schema bumps to **v10** with migration for older saves.
- Review found and fixed an input-routing risk: rest now routes through HUD
  focus/modal state, so it cannot fire underneath an open modal.

### PR #48 — Battle Specialist Crew Role

- Added data-driven crew member **Inez "Clash"** as the Battle Specialist.
- `CrewManager` now has battle-specialist helpers that loyalty-scale wall-duel
  rep and crew-rep rewards.
- `RivalManager` stamps boosted rewards onto active wall-duel callouts when
  they open, so saved callouts keep stable stakes.
- Answering a wall duel gives Clash loyalty, matching the existing crew-role
  progression pattern.
- Smoke coverage recruits Clash, verifies her model and role helpers, checks
  boosted saved duel rewards, and confirms loyalty gain on duel win.

## Verification

- PR #43: 3 clean headless smoke runs and 1 clean windowed boot.
- PR #44: 3 clean headless smoke runs and 1 clean windowed boot.
- PR #46: 3 clean headless smoke runs and 1 clean windowed boot.
- PR #47: 4 clean headless smoke runs total and 1 clean windowed boot.
- PR #48: 3 clean sequential headless smoke runs and 1 clean windowed boot.
  A parallel smoke attempt was discarded because concurrent runs raced on the
  shared `user://` save file.
- Final pushed `main`: `94daf24` Add battle specialist crew role.

## Current Project State

- v3 milestones 27–32 are complete.
- Product_reqs.md items are implemented.
- The first post-M32 battle-system slice, rival wall duels, is implemented and
  now has the Battle Specialist crew hook.
- Safehouse sleep-to-skip is implemented as a compact rest action.
- The main feature blocker is now **M33 Playtest Feedback Pass**, which needs
  real tester observations rather than more speculative feature work.
- M34 v3 demo candidate should follow only after M33 findings are captured and
  fixed.

## Recommended Next Features / Milestones

1. **M33 Playtest feedback pass.** Run a tester through alias selection to
   Rooftop Row claim, capture confusion points, and make only prompt/data/UI
   fixes tied to findings.
2. **M34 v3 demo candidate.** Freeze after M33, run the full verification
   loop, update known issues, and tag a candidate.
3. **Duel pressure and forfeits.** Add a clear timer or cleanup/fail condition
   so ignored callouts can become losses without surprising the player.
4. **Crew morale layer.** Small team-level morale affected by gallery sales,
   rival losses, duel wins, and loyalty milestones.
5. **Rival duel ladder.** Let each crew escalate from one-off callouts to a
   named three-wall challenge arc without building full faction diplomacy.
6. **Sketch editor / blackbook customization.** Save a bench sketch or
   freehand motif and reuse it as a custom piece.
7. **Cap/can inventory expansion.** Generalize fat cap into skinny/fat/
   calligraphy caps with paint-cost, detail, and suspicion tradeoffs.
8. **Rival alliance / ceasefire path.** Dialogue/data path for softening one
   crew relationship without building full faction diplomacy.
9. **MultiMesh street-detail pass.** Reduce the repeated street-detail node
    count flagged by runtime budgets before adding a fourth district.
10. **Outfit / alias presentation pass.** Let rank or crew loyalty unlock
    visible outfit accents and stronger alias identity.
11. **Safehouse room depth.** Small room upgrades that display earned posters,
    sketches, and crew mementos without becoming a decorating sim.
12. **Fourth district groundwork.** Scope Downtown or Gallery Quarter only
    after M34 and the runtime budget confirms headroom.
13. **Playtest metrics export polish.** Make capture files easier to compare
    between testers and candidate builds.
14. **Safehouse rest presentation.** Add a short clock/lighting/audio beat to
    make the new rest action feel like time passed without building full
    day/night simulation.
15. **Duel reward tuning pass.** Revisit wall-duel rewards after playtest data
    now that Clash can boost the reward envelope.
