# Battle Prototype Paper Cut — 2026-06-19

Milestone 32 asked for a paper prototype before building any Plan.md
section 20 battle system. Decision: **do not build a separate battle
minigame for v3**.

## Prototype Tested On Paper

### Dance Battle

- **Input pattern:** reuse the nightclub beat lane: 12 to 16 timed taps over
  roughly 45 to 60 seconds.
- **Scoring:** hype percentage from on-beat taps, scaled by Style and any
  future Battle Specialist support.
- **Fail state:** lose the cover/stake and take a small crew-rep hit.
- **Reward:** Style XP, crew rep, and possibly a rumor/recruit lead.
- **Why it could help:** it is readable and already proven by The Undertow.
- **Why it should not ship now:** it duplicates the nightclub loop without
  affecting walls, heat, territory, or the main paint economy.

### Rap / Verbal Battle

- **Input pattern:** three prompt choices per round: crowd-read, insult,
  deflect, name-drop, or crew callout.
- **Scoring:** choose counters that match the opponent's stance; Style helps
  crowd payoff, crew loyalty helps saves.
- **Fail state:** lose crew rep or worsen rival attitude.
- **Reward:** improve a rival relationship or unlock a direct wall challenge.
- **Why it could help:** it could make rivalry social instead of only
  retaliation.
- **Why it should not ship now:** it needs opponent writing, stance data, and
  new UI copy to feel better than existing dialogue.

### Graffiti Wall Duel

- **Input pattern:** accept a challenge on a contested wall, choose a graffiti
  type, then paint under pressure.
- **Scoring:** existing rep ingredients: style value, wall risk, color
  complexity, crew support, audience reaction, and time exposure.
- **Fail state:** rival keeps the wall and attitude worsens.
- **Reward:** immediate influence swing on the wall/district.
- **Why it could help:** it reinforces the game's strongest systems: paint,
  territory, rivals, heat, and crew.
- **Why it should not ship in v3:** it is the best long-term direction, but it
  is no longer a paper cut. It needs challenge data, rival stakes, UI prompts,
  and careful balance so it does not bypass the normal territory loop.

## Decision

For v3, **keep battles out of the candidate build**. The playable dance/DJ
modal already satisfies the strongest 60-second timing interaction, and a
second timing battle would read as filler.

The next battle work should be post-candidate and should start with
**rival wall duels**, not dance or rap. That version can reuse existing paint,
territory, rival, crew, heat, and crowd-reaction systems while giving the
future Battle Specialist role a reason to exist.

## Follow-Up Backlog

1. Rival wall duel data: challenged wall, rival crew, stake, allowed type.
2. Battle Specialist crew role: chance to reduce failure penalty or boost duel
   scoring.
3. Duel prompt and result toast, kept inside the existing HUD/modal rules.
4. Smoke coverage for accept, win, lose, and influence swing.
