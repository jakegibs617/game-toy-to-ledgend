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

The main path should always have:

* Piece unlocked before any required piece objective.
* Roller unlocked before any Rooftop Row roller objective.
* At least one affordable paint-pack recovery path before late high-cost
  work.
* Enough planned paint plus one pack to cover the required train,
  gallery, and Rooftop Row beats.
* A return route from Rooftop Row back to Canal Side.
