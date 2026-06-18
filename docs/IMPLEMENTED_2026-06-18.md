# Implementation Notes — 2026-06-18

## Implemented today

- Added Nia "Stash" as a recruitable Supply Runner crew member.
- Wired the new `supply_runner` role into shop prices and delivery payouts via
  data-driven multipliers.
- Added Tali "Echo" as a recruitable Hype crew member.
- Wired the new `hype` role into ambient crowd-reaction rep and nightclub set
  payouts.
- Added Vale "Fix" as a recruitable Fixer crew member.
- Wired the new `fixer` role into caught-penalty reduction and cleanup sweep
  odds.
- Updated Lupe's shop UI and playtest balance metrics so displayed economy
  values match actual payouts.
- Added smoke coverage for recruitment, role effects, delivery/nightclub payout
  math, crowd-reaction rep, caught penalties, and the blackbook Crew page.
- Updated the feature ledger and changelog.

## Recommended next milestones

1. Battle paper-cut prototype: decide graffiti battle vs dance/rap battle scope
   and ship one playable micro-loop.
2. Battle Specialist crew role that improves battle timing windows or rewards.
3. Crew loyalty and morale: recruited members can gain trust, get rattled by
   sellout/gallery choices, and unlock better role modifiers.
4. Crew upgrade board in the blackbook for spending crew rep on member perks.
5. Rival direct challenge duels with wagered walls and a visible outcome log.
6. Rival alliance/pressure state so crews react differently to repeated hits,
   defenses, and public wins.
7. Safehouse sleep/skip-time action that advances heat decay, cleanup, and
   train schedules.
8. Safehouse customization with earned posters, sticker sheets, and crew props.
9. Sketch editor milestone: save simple blackbook sketches and reuse selected
   sketches as paste-up/poster variants.
10. Fourth district preproduction: pick Downtown, Train Yard proper, Gallery
   Quarter, or Substation and define its signature mechanic before building.
11. Playtest feedback pass for economy stacking after Supply Runner, Hype, and
   Fixer bonuses.
12. Full crew upgrade board with loyalty-based role tuning and member-specific
   mini-perks.
