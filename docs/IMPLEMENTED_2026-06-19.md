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

### PR #45 — Rival Wall Duels

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

## Verification

- PR #43: 3 clean headless smoke runs and 1 clean windowed boot.
- PR #44: 3 clean headless smoke runs and 1 clean windowed boot.
- PR #45: 3 clean headless smoke runs and 1 clean windowed boot.
- Final merged `main`: `5a4fd77` Merge pull request #46.

## Current Project State

- v3 milestones 27–32 are complete.
- Product_reqs.md items are implemented.
- The first post-M32 battle-system slice, rival wall duels, is implemented.
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
3. **Battle Specialist crew role.** Hook into wall duels: improve duel rewards,
   soften forfeits, or reveal active callouts sooner.
4. **Duel pressure and forfeits.** Add a clear timer or cleanup/fail condition
   so ignored callouts can become losses without surprising the player.
5. **Crew morale layer.** Small team-level morale affected by gallery sales,
   rival losses, duel wins, and loyalty milestones.
6. **Rival duel ladder.** Let each crew escalate from one-off callouts to a
   named three-wall challenge arc without building full faction diplomacy.
7. **Sketch editor / blackbook customization.** Save a bench sketch or
   freehand motif and reuse it as a custom piece.
8. **Cap/can inventory expansion.** Generalize fat cap into skinny/fat/
   calligraphy caps with paint-cost, detail, and suspicion tradeoffs.
9. **Rival alliance / ceasefire path.** Dialogue/data path for softening one
   crew relationship without building full faction diplomacy.
10. **MultiMesh street-detail pass.** Reduce the repeated street-detail node
    count flagged by runtime budgets before adding a fourth district.
11. **Outfit / alias presentation pass.** Let rank or crew loyalty unlock
    visible outfit accents and stronger alias identity.
12. **Safehouse room depth.** Small room upgrades that display earned posters,
    sketches, and crew mementos without becoming a decorating sim.
13. **Fourth district groundwork.** Scope Downtown or Gallery Quarter only
    after M34 and the runtime budget confirms headroom.
14. **Playtest metrics export polish.** Make capture files easier to compare
    between testers and candidate builds.
