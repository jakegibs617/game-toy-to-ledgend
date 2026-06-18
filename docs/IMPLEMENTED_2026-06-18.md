# Implementation Notes — 2026-06-18

## Implemented today

- Added Nia "Stash" as a recruitable Supply Runner crew member.
- Wired the new `supply_runner` role into shop prices and delivery payouts via
  data-driven multipliers.
- Added Tali "Echo" as a recruitable Hype crew member.
- Wired the new `hype` role into ambient crowd-reaction rep and nightclub set
  payouts.
- Updated Lupe's shop UI and playtest balance metrics so displayed economy
  values match actual payouts.
- Added smoke coverage for recruitment, role effects, delivery/nightclub payout
  math, crowd-reaction rep, and the blackbook Crew page.
- Updated the feature ledger and changelog.

## Recommended next milestones

1. Battle paper-cut prototype: decide graffiti battle vs dance/rap battle scope
   and ship one playable micro-loop.
2. Battle Specialist crew role that improves battle timing windows or rewards.
3. Fixer crew role that reduces cleanup/buffing or lowers heat after catches.
4. Crew loyalty and morale: recruited members can gain trust, get rattled by
   sellout/gallery choices, and unlock better role modifiers.
5. Crew upgrade board in the blackbook for spending crew rep on member perks.
6. Rival direct challenge duels with wagered walls and a visible outcome log.
7. Rival alliance/pressure state so crews react differently to repeated hits,
   defenses, and public wins.
8. Safehouse sleep/skip-time action that advances heat decay, cleanup, and
   train schedules.
9. Safehouse customization with earned posters, sticker sheets, and crew props.
10. Sketch editor milestone: save simple blackbook sketches and reuse selected
   sketches as paste-up/poster variants.
11. Fourth district preproduction: pick Downtown, Train Yard proper, Gallery
   Quarter, or Substation and define its signature mechanic before building.
12. Playtest feedback pass for economy stacking after Supply Runner and Hype
   bonuses.
