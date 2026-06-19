# v3 Balance Targets

Milestone 28 tunes against one intended first-time demo run rather than
trying to balance every possible route.

## Target Run

Expected route:

1. Finish Mill Yard intro and claim the block.
2. Enter Canal Side, answer Ghost Line, and claim the block.
3. Meet Vesper, possibly get one gallery canvas refused, then complete
   one accepted sale.
4. Paint the Ghost Local once.
5. Climb into Rooftop Row and claim it.

Target feel:

* Completion window: 35-50 minutes for a new tester who reads prompts.
* Caught/fall budget: 1-3 total mistakes without ending the run.
* Paint purchases: 1-3 paint packs on the main path.
* Rank pacing: Known by the Mill Yard claim, Block King near the end
  rather than before Canal Side has landed.
* Grind budget: no more than two optional wall paints or one delivery
  run required to recover from a normal mistake.

## Balance Notes

Milestone 28 reduces stacked reputation inflation from district claims,
trains, gallery, and Rooftop Row while making paint recovery less brittle
around the train/gallery/rooftop stretch. Data moves first; code changes
are limited to smoke-test invariants.

The v4 cap/morale pass keeps the target route stable after two late v3
systems started touching the economy:

* **Calligraphy Cap:** maximum cap rep modifier is 1.25x, but it also adds
  +1 paint and +0.06 suspicion. It should read as an expressive choice for
  a few important walls, not the default route for every required paint.
* **Mops/markers:** marker work is tag-only, lower heat, and lower rep; the
  mop is throw-up/piece-only, louder, +1 paint, and slightly higher rep. Both
  stay in the same equipped-tool lane as caps so Standard does not gain a
  stacked modifier pile.
* **Team morale:** morale only scales crew role bonuses, not direct wall
  reputation. Its range is 0.9x-1.1x around the neutral 1.0x baseline, so a
  winning crew makes support roles feel sharper without replacing the main
  path's mission, wall, train, gallery, and territory pacing.

Smoke now includes both systems in the balance snapshot (`caps` and `crew`)
and asserts their headline ceilings: Calligraphy stays at or below 1.25x
rep, and morale role scaling stays at or below 1.1x.

The v4 economy regression guard stores headline target values in
`Data/balance_regression_targets.json`. Each row names a snapshot path,
target, and tolerance. Smoke fails when one of those values moves outside
its tolerance, so tuning PRs need to update the ledger deliberately instead
of quietly shifting paint costs, mission recovery, train rewards, gallery
payouts, claim bonuses, cap multipliers, or morale ceilings.

Difficulty presets must keep **Standard** as the unchanged target-run baseline.
Relaxed and Hard scale heat gain, patrol density, shop prices, and cash rewards
only after the player chooses them from the new-game alias modal.

Rival wall-duel forfeits are tuned per crew in `Data/crews.json`. Penalties
should sting enough to make ignoring callouts meaningful without undoing more
than a normal mistake budget's worth of main-path progress.

Morale-driven crew events are deliberately small. High morale can grant a
single supply favor, and low morale suppresses one recruited role until the
crew recovers; neither should rewrite the Standard target route's paint,
cash, or reputation pacing.

The main path should always have:

* Piece unlocked before any required piece objective.
* Roller unlocked before any Rooftop Row roller objective.
* At least one affordable paint-pack recovery path before late high-cost
  work.
* Enough planned paint plus one pack to cover the required train,
  gallery, and Rooftop Row beats.
* A return route from Rooftop Row back to Canal Side.
