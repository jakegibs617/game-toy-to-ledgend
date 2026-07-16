# Game Design Document: Graffiti Open-World RPG Prototype

## Working Title

**Toy to Legend**

Alternative titles:

* **King the City**
* **Buffed**
* **All City**
* **The Last Wall**
* **Blackbook**

## High Concept

Build a playable open-world graffiti RPG inspired by the exploration, faction, progression, and world-reactivity of games like *Fallout 4* and *Starfield*, but centered around graffiti culture, street reputation, crew politics, territory control, and artistic progression.

The player starts as an unknown “toy” writer and rises toward becoming an all-city legend by tagging walls, painting larger pieces, recruiting crew members, battling rival writers, avoiding city cleanup crews, and shaping the visual identity of the city.

The world should visibly change based on player actions. Walls remember who painted them. Rival crews respond. Tags get crossed out, buffed, covered, or praised. The city becomes a living canvas.

---

# 1. Core Fantasy

The player should feel like:

> “I am becoming known across the city through style, risk, territory, and reputation.”

The primary fantasy is not combat-first. It is about:

* Discovering hidden urban spaces
* Finding high-value walls
* Painting tags, throw-ups, pieces, and murals
* Building a crew
* Competing with rivals
* Managing heat from authorities
* Becoming visually present across the city
* Watching the environment evolve because of your art

---

# 2. Genre

Primary genre:

**Open-world graffiti RPG / territory-control sim**

Secondary genre elements:

* Urban exploration
* Faction RPG
* Crew management
* Stealth-lite
* Reputation sim
* Creative sandbox
* Mission-based progression

---

# 3. Target Prototype Scope

The first build should be a **vertical slice**, not a full city.

## MVP Environment

One small but dense district:

* 3–5 city blocks
* 10–20 paintable surfaces
* 3 rival crew zones
* 1 safehouse / home base
* 1 supply shop or stash location
* 1 train yard or industrial zone
* 1 high-risk landmark wall
* 5–10 NPCs
* 2–3 recruitable crew members
* 3 basic mission types
* Basic day/night or heat cycle

## MVP Goal

The player should be able to:

1. Walk around a small urban district.
2. Find paintable walls.
3. Place graffiti on walls.
4. Gain reputation from visible graffiti.
5. Trigger rival crew responses.
6. Recruit at least one crew member.
7. Assign that crew member a role.
8. Watch rival crews cover or cross out player graffiti.
9. Complete missions that increase territory control.
10. Reach a prototype end-state: “Known Writer” or “Block King.”

---

# 4. Core Gameplay Loop

## Primary Loop

1. Explore the city.
2. Discover paintable surfaces.
3. Paint tags, throw-ups, or pieces.
4. Gain reputation based on location, style, risk, and visibility.
5. Rival crews or city cleanup respond.
6. Player upgrades skills, recruits crew, and unlocks better tools.
7. Player claims higher-value walls and larger territory.
8. The city visually reflects the player’s rise.

## Short Loop

Explore → Paint → Gain Rep → Avoid Heat → Return to Safehouse

## Medium Loop

Accept mission → Scout target wall → Gather supplies → Bring crew → Paint piece → Defend reputation

## Long Loop

Claim district → Defeat rival crew influence → Unlock new zone → Become all-city legend

---

# 5. Player Progression

The player progresses from unknown beginner to respected writer.

## Reputation Ranks

Suggested progression:

1. **Toy**
2. **Rookie**
3. **Up**
4. **Known**
5. **Block King**
6. **Citywide**
7. **All City**
8. **Legend**

Each rank unlocks:

* New wall types
* New spray tools
* Better crew recruits
* More dangerous missions
* New districts
* New graffiti styles
* Larger pieces
* More aggressive rival responses

## XP Sources

The player earns XP or reputation from:

* Tags
* Throw-ups
* Pieces
* Murals
* High-risk locations
* Rooftops
* Train cars
* Rival crew battles
* Blackbook sketching
* Visiting galleries
* Studying street art
* Completing missions
* Recruiting respected writers
* Defending territory

---

# 6. Player Stats

The player should have RPG-style stats, but they should fit the graffiti fantasy.

## Suggested Stats

### Style

Affects visual quality, reputation multiplier, and NPC respect.

### Nerve

Affects ability to paint high-risk locations under pressure.

### Speed

Affects how quickly graffiti is completed.

### Stealth

Affects chance of avoiding security, cops, cameras, and witnesses.

### Influence

Affects recruitment, crew morale, and faction negotiation.

### Technique

Affects access to complex pieces, murals, stencils, wildstyle, and multi-color work.

### Hustle

Affects supply acquisition, mission payouts, and street connections.

---

# 7. Skills and Perks

The game should use a perk-tree system similar in spirit to *Fallout 4*, but themed around graffiti.

## Example Perk Trees

### Style Tree

* Cleaner Lines
* Better Fill
* Wildstyle Starter
* Color Theory
* Signature Handstyle
* Icon Maker

### Stealth Tree

* Quiet Footsteps
* Camera Blindspot
* Rooftop Entry
* Night Writer
* Silent Escape

### Crew Tree

* Recruit Lookout
* Recruit Filler
* Recruit Getaway
* Crew Morale Boost
* Call Backup
* Crew Piece Bonus

### Territory Tree

* Faster Claiming
* Rep from Tags
* Rep from Throw-ups
* Wall Memory Bonus
* District Influence

### Supplies Tree

* Paint Discount
* Larger Inventory
* Better Caps
* Rare Colors
* Stencil Kit
* Roller Extension

---

# 8. Graffiti System

The graffiti system is the heart of the game.

## Graffiti Types

### Tag

Fast, low-risk, low reward.

Use case:

* Mark presence
* Start claiming a wall
* Low supply cost

### Throw-up

Medium speed, medium reward.

Use case:

* Stronger territory signal
* More visible
* Can cover tags

### Piece

Slow, higher risk, high reward.

Use case:

* Major reputation boost
* Requires supplies and time
* Vulnerable to interruption

### Mural

Large-scale, mission-level graffiti.

Use case:

* Story missions
* Crew projects
* District-changing artwork

### Stencil

Fast repeatable graphic.

Use case:

* Branding
* Political art
* Fast territory spread

### Roller / Rooftop Blockbuster

High-risk, high-visibility.

Use case:

* Endgame territory
* Big reputation multiplier

---

# 9. Paintable Surface System

Every paintable surface should be a game object with state.

## Wall Properties

Each wall should track:

* Wall ID
* Location
* Owner crew
* Current graffiti layer
* Visibility score
* Risk score
* Size
* Surface type
* Cleanup probability
* Rival response probability
* Player reputation value
* Historical graffiti layers

## Wall States

Possible states:

* Blank
* Player tag
* Player throw-up
* Player piece
* Player mural
* Rival tag
* Rival throw-up
* Rival piece
* Crossed out
* Buffed / painted over
* Protected
* Landmark wall

## Wall Memory

Walls should remember history.

Example:

* Player tags wall.
* Rival crosses it out.
* Player comes back with a throw-up.
* City buffs the wall.
* Player paints a larger piece.
* NPCs begin commenting on it.

This creates emergent storytelling.

---

# 10. Graffiti Creation Mechanics

The prototype does not need a full drawing engine at first.

## MVP Approach

Use selectable graffiti assets.

The player chooses:

* Name / writer alias
* Tag style
* Fill color
* Outline color
* Icon / symbol
* Piece type

The game then places a decal or mesh onto the wall.

## Later Advanced System

Future versions can include:

* Freehand spray painting
* Stencil upload system
* Procedural handstyles
* Layered graffiti editor
* Drips, overspray, caps, texture
* Custom blackbook editor

## MVP Implementation Requirement

For the MVP, implement graffiti as decals or planes projected onto paintable wall surfaces.

Minimum requirements:

* Place graffiti on valid wall
* Scale to wall area
* Save graffiti state
* Load graffiti state
* Allow rival graffiti to overwrite or cross out existing graffiti

---

# 11. Reputation System

Reputation determines player rank and social power.

## Reputation Formula

Reputation gain should consider:

* Graffiti type
* Wall visibility
* Wall risk
* Rival territory bonus
* Current heat level
* Style score
* Crew bonus
* Whether wall was previously owned
* Whether piece remains visible over time

Example formula:

Reputation gained =
Base graffiti value × Visibility multiplier × Risk multiplier × Style multiplier × Territory modifier

## Reputation Decay

Some graffiti should lose value over time if:

* It is buffed by cleanup crews
* Rival crews cover it
* It is in a low-traffic location
* The player ignores the district

## Public Reputation vs Crew Reputation

Consider tracking separate reputation types:

### Public Rep

How known the player is citywide.

### Crew Rep

How respected the player is by other writers.

### Heat

How much attention the player has from authorities.

### Territory Influence

How much control the player has over a district.

---

# 12. Heat System

Heat represents police, security, city cleanup, cameras, and neighborhood attention.

## Heat Sources

Heat increases when the player:

* Paints in high-risk zones
* Paints during the day
* Paints near cameras
* Gets seen by NPCs
* Paints landmark walls
* Hits transit property
* Repeatedly attacks rival zones

## Heat Effects

Higher heat causes:

* More patrols
* Faster cleanup response
* More locked areas
* More NPC suspicion
* Increased mission difficulty
* Greater reputation reward for risky actions

## Heat Reduction

Heat decreases when:

* Player lays low
* Changes district
* Uses stealth
* Bribes informants
* Completes cleanup diversion missions
* Sends crew to distract patrols

---

# 13. Rival Crew System

Rival crews are a key part of the world simulation.

## MVP Rival Crews

Create three rival crews for the prototype.

Example:

### The Buff Kings

A crew obsessed with clean block letters and dominance.

### Ghost Line

A stealthy crew that paints rooftops and hidden infrastructure.

### Chrome Saints

A flashy crew known for metallic pieces and train-yard work.

## Rival Crew Behavior

Rival crews should:

* Claim walls
* Cross out player tags
* Cover weak graffiti
* Defend landmark walls
* Send challenges
* Offer alliances
* Retaliate when disrespected
* Become recruitable or allied later

## “Toy” Mechanic

If the player has low reputation or places weak graffiti in respected territory, rivals may write **“TOY”** over the player’s work.

This should be emotionally meaningful. It tells the player they need to improve.

## Rival Response Triggers

Rival action may trigger when:

* Player paints over rival wall
* Player claims too many walls in one district
* Player paints a landmark wall
* Player loses a battle
* Player ignores a direct challenge

---

# 14. Crew Recruitment System

The player can build a crew.

## Crew Member Roles

### Lookout

Warns player of cops, cameras, or witnesses.

### Filler

Helps fill large pieces faster.

### Supply Runner

Finds paint, caps, rollers, and rare colors.

### Getaway

Reduces escape difficulty after high-heat actions.

### Hype

Improves reputation gain and NPC reaction.

### Battle Specialist

Helps in dance battles, rap battles, or crew confrontations.

### Fixer

Reduces heat or negotiates with factions.

## Crew Member Properties

Each crew member should have:

* Name
* Alias
* Role
* Loyalty
* Style
* Risk tolerance
* Special ability
* Relationship to rival crews
* Recruitment condition
* Upgrade path

## MVP Crew Members

Implement 2–3 recruitable NPCs.

Example:

### Mina “Moth”

Role: Lookout
Trait: Better at night missions
Recruitment: Help her recover a blackbook from a rival crew.

### Rico “Caps”

Role: Supply Runner
Trait: Discounts on paint
Recruitment: Complete a delivery without being spotted.

### Jay “Metro”

Role: Filler
Trait: Speeds up large pieces
Recruitment: Win a wall challenge.

---

# 15. Mission Design

Missions should support the graffiti fantasy and introduce systems gradually.

## Mission Types

### Tag Mission

Paint 3 low-risk walls to establish presence.

### Throw-up Mission

Cover a rival mark in a contested area.

### Piece Mission

Paint a larger piece while avoiding interruption.

### Recruitment Mission

Help an NPC writer and unlock them as crew.

### Rival Challenge

Compete against another writer for a wall.

### Supply Run

Steal, buy, or recover paint supplies.

### Rooftop Mission

Reach a difficult location and paint a high-visibility wall.

### Cleanup Retaliation

Repaint a wall that the city buffed.

### Landmark Mission

Paint a famous wall to unlock a new rank.

---

# 16. Prototype Mission Chain

## Mission 1: First Mark

Goal:

* Teach movement and tagging.

Objectives:

* Choose writer alias.
* Find first legal or low-risk wall.
* Place first tag.
* Return to safehouse.

Reward:

* Unlock reputation system.
* Gain starter paint.

## Mission 2: Don’t Be a Toy

Goal:

* Introduce rival crew.

Objectives:

* Find your crossed-out tag.
* Inspect wall.
* Learn that a rival wrote “TOY.”
* Paint a better throw-up over it.

Reward:

* Unlock throw-ups.
* Gain small reputation boost.

## Mission 3: Get Supplies

Goal:

* Introduce supply system.

Objectives:

* Visit supply contact.
* Get paint cans.
* Choose colors.
* Avoid or talk past suspicious NPC.

Reward:

* Unlock color selection.

## Mission 4: Find a Lookout

Goal:

* Introduce crew recruitment.

Objectives:

* Meet Mina “Moth.”
* Help recover her blackbook.
* Recruit her as lookout.

Reward:

* Unlock crew assignment.

## Mission 5: Claim the Block

Goal:

* Introduce territory.

Objectives:

* Paint 3 walls in contested zone.
* Defend one wall from rival overwrite.
* Complete a crew-assisted piece.

Reward:

* Become “Known.”
* Unlock next district placeholder.

---

# 17. World Design

## Prototype District

The first district should feel like an industrial urban neighborhood.

Suggested environment components:

* Brick mill buildings
* Old loading docks
* Chain-link fences
* Rooftop access
* Underpass
* Small bodega or corner store
* Train yard edge
* Alley network
* Buffed walls
* Abandoned lot
* One iconic landmark wall

## Visual Inspiration

The world should include:

* Layered graffiti
* Weathered brick
* Peeling posters
* Rusted metal
* Painted-over walls
* Old industrial architecture
* Neon nightlife elements
* Stickers
* Wheatpaste posters
* Burned or cleared wall sections
* Drips and overspray

## Environmental Storytelling

Examples:

* A buffed wall with faint old tags showing through
* Rival crew stickers near their territory
* Memorial mural in an alley
* Police notice near a train yard
* Blackbook pages hidden in abandoned buildings
* Gallery flyers hinting at art-world missions

---

# 18. Factions

The MVP should include lightweight factions.

## Faction Types

### Rival Crews

Compete for walls and reputation.

### City Cleanup

Buffs walls and removes graffiti.

### Security / Police

Increase heat and interrupt risky painting.

### Local Businesses

May support or oppose the player.

### Art World

Galleries, collectors, and mural commissions.

### Underground Scene

DJs, dancers, MCs, skaters, and party promoters.

---

# 19. Non-Combat Conflict Systems

The game should avoid relying on guns or traditional combat as the primary mechanic.

Conflict can happen through:

* Graffiti battles
* Dance battles
* Rap battles
* Reputation challenges
* Chase sequences
* Stealth escapes
* Crew intimidation
* Negotiation
* Territory control
* Artistic one-upmanship

## Optional Physical Conflict

If implemented, physical conflict should be minimal and stylized.

Better approach:

* Push past security
* Escape pursuit
* Avoid confrontation
* Use crew abilities
* Win through reputation instead of violence

---

# 20. Battle Systems

## Graffiti Battle

A graffiti battle is a structured challenge for control over a wall.

Possible scoring:

* Style
* Size
* Location risk
* Color complexity
* Crew support
* Time efficiency
* Audience reaction

## Breakdance Battle

A rhythm or timing-based mini-game.

Stats:

* Strength
* Flexibility
* Style
* Stamina
* Crowd Control

## Rap / Verbal Battle

Optional later system.

Could use:

* Dialogue choices
* Reputation checks
* Topic counters
* Crowd meter

---

# 21. Economy and Supplies

## Currencies

### Cash

Used to buy supplies.

### Paint

Consumable resource for graffiti.

### Caps

Modify spray behavior.

### Influence

Used for favors, crew recruitment, or faction negotiation.

## Supplies

* Black paint
* White paint
* Fill colors
* Outline colors
* Fat caps
* Skinny caps
* Mops
* Markers
* Rollers
* Stencils
* Gloves
* Masks
* Blackbook pages

## MVP Economy

For the prototype:

* Give the player limited paint.
* Each graffiti action consumes paint.
* Player can replenish paint from a supply contact.
* Higher-value graffiti costs more paint.

---

# 22. Safehouse / Home Base

The safehouse is the player’s hub.

## MVP Features

* Change outfit
* View blackbook
* Manage crew
* View map
* Store supplies
* Review reputation
* Sleep or wait to reduce heat

## Future Features

* Customize room
* Display sketches
* Plan missions
* Upgrade crew
* Store rare paint
* Listen to radio
* Manage district influence

---

# 23. Blackbook System

The blackbook is the player’s creative progression interface.

## MVP

The blackbook should show:

* Player alias
* Unlocked styles
* Current tags
* Crew members
* Known rival crews
* Reputation rank
* Painted walls
* Mission notes

## Future

The blackbook can become:

* Sketch editor
* Quest journal
* Style progression tree
* Collectible archive
* Lore system
* Custom graffiti library

---

# 24. Map and Territory

## District Map

The map should show:

* Paintable walls
* Claimed walls
* Rival walls
* Buffed walls
* High-risk locations
* Safehouse
* Supply contact
* Crew member locations

## Territory Score

Each district should track influence:

* Player influence
* Rival crew influence
* City cleanup pressure
* Heat level
* Public visibility

## Claiming Territory

The player claims territory by:

* Painting visible walls
* Maintaining graffiti over time
* Winning graffiti battles
* Recruiting local crew
* Completing district missions

---

# 25. NPC System

## NPC Types

### Civilians

React to graffiti, report suspicious behavior, comment on reputation.

### Writers

Can be rivals, allies, mentors, or recruits.

### Security

Interrupts painting and increases heat.

### Cleanup Workers

Buff walls over time.

### Scene NPCs

DJs, dancers, gallery owners, shopkeepers, skaters.

## MVP NPC Behavior

Implement simple behavior:

* Patrol
* Idle
* React to player painting
* Trigger heat
* Give mission
* Become recruitable
* Cross out or repaint walls through scripted events

---

# 26. Dialogue System

Dialogue should support RPG-style choice.

## Dialogue Uses

* Recruit crew
* Negotiate with rivals
* Accept missions
* Talk to supply contacts
* Learn lore
* Resolve conflict without violence

## Dialogue Checks

Some dialogue options can require:

* Influence
* Reputation rank
* Crew loyalty
* Style
* Prior mission completion

---

# 27. Art Direction

## Visual Style

The game should blend:

* Realistic urban structure
* Stylized graffiti
* Saturated color accents
* Weathered city textures
* Nightlife glow
* Comic-book confidence
* Hip-hop poster energy

## Mood

The city should feel:

* Lived-in
* Layered
* Competitive
* Creative
* Dangerous but not dystopian
* Gritty but colorful
* Full of hidden art

## Graffiti Look

Graffiti should include:

* Tags
* Throw-ups
* Wildstyle
* Blockbusters
* Stickers
* Wheatpaste
* Murals
* Buff marks
* Cross-outs
* Paint drips
* Overspray

---

# 28. Audio Direction

## Music

Suggested soundtrack direction:

* Boom bap
* Underground hip-hop
* Afro house influence
* Breakbeat
* Lo-fi city ambience
* Late-night radio mixes
* Industrial percussion

## Ambient Audio

* Distant trains
* Traffic
* Sirens
* Basketball courts
* Skateboards
* Spray cans
* Footsteps in alleys
* Rooftop wind
* Neon buzz
* Club bass from buildings

## Sound Effects

Important SFX:

* Spray can shake
* Spray hiss
* Cap change
* Marker squeak
* Footsteps on metal stairs
* Chain-link fence
* Police radio
* Camera beep
* Crowd reaction
* Paint roller

---

# 29. Technical Direction

## Recommended Engine

Use **Godot** or **Unity** for a prototype.

### Godot Advantages

* Free and open source
* Lightweight
* Good for agent-driven iteration
* Simple scene structure
* Good for stylized 3D prototypes

### Unity Advantages

* Mature 3D tooling
* Strong asset store
* Better decal workflows
* More tutorials
* Better third-person controller templates

## Recommended Choice

For fastest prototype, use **Unity** if the agent can use assets and existing controller systems.

For fully open-source development, use **Godot 4**.

The agent should choose one engine and remain consistent. Do not switch engines mid-project.

---

# 30. Core Technical Systems

The implementation agent should build these systems as separate modules.

## Required Systems

1. Player movement controller
2. Camera controller
3. Paintable wall detection
4. Graffiti placement system
5. Graffiti persistence system
6. Wall ownership state
7. Reputation manager
8. Heat manager
9. Rival crew manager
10. Crew recruitment manager
11. Mission system
12. Dialogue system
13. Map / territory tracker
14. Inventory / supplies system
15. Save/load system

---

# 31. Data Model

## Wall Data

Each wall should have:

```json
{
  "wallId": "wall_001",
  "districtId": "district_mill_yard",
  "position": [0, 0, 0],
  "size": "medium",
  "visibility": 3,
  "risk": 2,
  "surfaceType": "brick",
  "ownerCrewId": "player",
  "currentGraffitiId": "graffiti_001",
  "state": "player_throwup",
  "cleanupChance": 0.1,
  "rivalResponseChance": 0.2
}
```

## Graffiti Data

```json
{
  "graffitiId": "graffiti_001",
  "creatorId": "player",
  "crewId": "player_crew",
  "wallId": "wall_001",
  "type": "throwup",
  "style": "bubble",
  "fillColor": "red",
  "outlineColor": "black",
  "createdAtGameTime": 1024,
  "repValue": 25,
  "isCrossedOut": false,
  "isBuffed": false
}
```

## Crew Member Data

```json
{
  "memberId": "npc_mina_moth",
  "name": "Mina",
  "alias": "Moth",
  "role": "lookout",
  "loyalty": 50,
  "style": 4,
  "specialAbility": "early_warning",
  "recruited": false
}
```

## Rival Crew Data

```json
{
  "crewId": "ghost_line",
  "name": "Ghost Line",
  "style": "stealth_rooftop",
  "aggression": 3,
  "territory": ["alley_north", "rooftop_01"],
  "relationshipToPlayer": -20
}
```

---

# 32. Save System

The prototype must save:

* Player position
* Player reputation
* Player heat
* Inventory supplies
* Completed missions
* Crew members recruited
* Wall states
* Graffiti placed
* Rival graffiti responses
* District control values

Save/load is important because wall persistence is central to the fantasy.

---

# 33. AI Simulation

The world does not need complex AI at first.

## MVP Simulation

Use scheduled or event-based simulation.

Example:

* Every in-game hour, rival crews evaluate contested walls.
* Every in-game day, city cleanup may buff some walls.
* If player paints over a rival wall, rival response chance increases.
* If heat is high, patrols become more frequent.

## Simulation Events

Possible events:

* Rival crosses out player tag.
* Rival covers player throw-up.
* City buffs wall.
* NPC praises player piece.
* Crew member finds supplies.
* New mission appears.
* Rival sends challenge.

---

# 34. Prototype User Stories

The agent should implement against these user stories.

## Graffiti Placement

As a player, I can approach a valid wall and press an interact button to paint graffiti so that I can mark the city.

Acceptance criteria:

* Valid walls show an interaction prompt.
* Invalid surfaces do not.
* Choosing graffiti places visible artwork.
* The wall records ownership and graffiti type.
* Reputation increases.

## Rival Response

As a player, I can return to a wall and see that a rival crew has crossed out or covered my work so that the world feels reactive.

Acceptance criteria:

* Rival response can trigger after player paints in rival territory.
* Wall visual changes.
* Player receives notification.
* Territory score updates.

## Crew Recruitment

As a player, I can complete a mission for an NPC and recruit them into my crew.

Acceptance criteria:

* NPC gives mission.
* Mission can be completed.
* NPC becomes available in crew menu.
* Crew member grants a passive bonus.

## Territory Claiming

As a player, I can paint multiple walls in a district and increase my influence.

Acceptance criteria:

* District influence increases after painting.
* Rival influence decreases when player covers rival work.
* Map reflects territory changes.
* Reaching threshold unlocks a mission or rank.

---

# 35. MVP Milestones

## Milestone 1: Project Setup

Deliverables:

* Engine project created
* Third-person or first-person controller
* Simple test map
* Basic camera
* Interaction system

Done when:

* Player can move around a small test district and interact with objects.

## Milestone 2: Paintable Walls

Deliverables:

* Paintable wall objects
* Interaction prompt
* Graffiti placement
* Basic decal or plane rendering
* Wall state tracking

Done when:

* Player can place graffiti on multiple walls and each wall remembers its state.

## Milestone 3: Reputation and Inventory

Deliverables:

* Reputation counter
* Basic graffiti types
* Paint supply cost
* Simple UI
* Rank progression

Done when:

* Tags, throw-ups, and pieces give different rep and cost supplies.

## Milestone 4: Rival Crew Reactions

Deliverables:

* Rival crew data
* Rival wall ownership
* Cross-out mechanic
* Overwrite mechanic
* Basic event notifications

Done when:

* Rival crews can mark over player graffiti after triggers.

## Milestone 5: Crew Recruitment

Deliverables:

* Recruitable NPC
* Simple mission
* Crew menu
* Role bonus

Done when:

* Player can recruit one crew member and receive a gameplay benefit.

## Milestone 6: Territory System

Deliverables:

* District influence values
* Map indicators
* Claimed walls
* Rival control
* Territory threshold reward

Done when:

* Player can claim a block by painting enough key walls.

## Milestone 7: Vertical Slice Mission Chain

Deliverables:

* 5 connected missions
* Intro sequence
* Rival “TOY” moment
* Crew recruitment
* Final district claim mission

Done when:

* Player can play from unknown beginner to “Known Writer.”

## Milestone 8: Polish Pass

Deliverables:

* Better UI
* Better wall art
* Sound effects
* Lighting pass
* Save/load
* Bug fixes

Done when:

* Prototype feels coherent and can be shown to another person.

---

# 36. Development Priorities

## Must-Have

* Movement
* Paintable walls
* Graffiti placement
* Wall state persistence
* Reputation
* Rival overwrite/cross-out
* Crew recruitment
* Territory tracking
* Save/load

## Should-Have

* Heat
* Patrols
* Supply inventory
* Simple missions
* Dialogue
* Blackbook UI
* District map

## Could-Have

* Freehand spray painting
* Dance battles
* Rap battles
* Gallery missions
* Procedural graffiti
* Rooftop climbing
* Train painting
* Dynamic NPC crowd reactions

## Do Not Build Yet

Avoid these until the vertical slice works:

* Full city
* Multiplayer
* Complex combat
* Procedural world generation
* Advanced freehand painting
* Full faction diplomacy
* Large quest trees
* Character creator
* Vehicle systems
* Online graffiti sharing

---

# 37. Prototype Controls

Suggested controls:

## Keyboard / Mouse

* WASD: Move
* Mouse: Look
* Shift: Run
* Space: Jump
* E: Interact
* Tab: Blackbook / menu
* M: Map
* 1: Tag
* 2: Throw-up
* 3: Piece
* F: Use crew ability
* Esc: Pause

## Controller

* Left stick: Move
* Right stick: Camera
* A / X: Jump
* X / Square: Interact
* Y / Triangle: Blackbook
* B / Circle: Cancel
* D-pad: Select graffiti type
* Right trigger: Paint
* Left bumper: Crew ability

---

# 38. UI Requirements

## HUD

Show:

* Current reputation
* Current rank
* Heat level
* Paint supply
* Current graffiti type
* Nearby wall prompt

## Wall Interaction UI

When facing a paintable wall, show:

* Wall name or ID
* Risk
* Visibility
* Current owner
* Available actions:

  * Tag
  * Throw-up
  * Piece
  * Inspect

## Blackbook UI

Show:

* Player alias
* Rank
* Crew
* Graffiti styles
* Missions
* District influence
* Rival crews

## Map UI

Show:

* Player location
* Owned walls
* Rival walls
* Buffed walls
* Mission targets
* Supply contact
* Safehouse

---

# 39. Narrative Premise

The player is a new writer entering a city where graffiti culture is controlled by old crews, cleanup initiatives, private security, and art-world opportunists.

The player starts unknown, gets disrespected, and must earn their name.

The story should focus on:

* Identity
* Style
* Respect
* Risk
* Creative ownership
* Public space
* Rivalry
* Community
* Selling out vs staying underground

---

# 40. Opening Sequence

The game begins at night near an underpass.

The player chooses a writer alias and paints their first tag. It feels small but meaningful.

The next day, the player returns and sees that someone has written **TOY** over it.

This becomes the inciting incident.

The player then decides to:

* Improve
* Recruit help
* Claim better walls
* Challenge the crew that disrespected them

---

# 41. Tone Guidelines

The tone should be:

* Stylish
* Street-level
* Funny at times
* Competitive
* Respectful of graffiti culture
* Not cartoonishly criminal
* Not police-procedural
* Not superhero fantasy
* Not generic cyberpunk

Avoid making the world only about crime. The game is about art, reputation, and public space.

---

# 42. Cultural Handling Guidelines

The agent should treat graffiti and hip-hop culture with respect.

Avoid:

* Caricatures
* Fake slang overload
* Over-criminalizing every character
* Making all writers gang members
* Reducing graffiti to vandalism only
* Treating art culture as shallow decoration

Include:

* Mentorship
* Skill development
* Style lineage
* Blackbooks
* Respect for old heads
* Local scene politics
* Art vs commerce tension
* Community spaces
* Real artistic labor

---

# 43. Example NPCs

## Old Head Mentor

Name: Darnell “Prime”
Role: Mentor
Function: Teaches player about respect, history, and style.
Gameplay: Unlocks blackbook upgrades.

## Rival Crew Leader

Name: Vale
Alias: VEK
Crew: The Buff Kings
Function: Early antagonist.
Gameplay: Crosses out player tags and challenges player.

## Supply Contact

Name: Lupe
Role: Shopkeeper / fixer
Function: Sells paint, caps, and mission leads.

## Recruitable Lookout

Name: Mina
Alias: Moth
Role: Lookout
Function: Warns player during high-risk painting.

## Gallery Contact

Name: Ellis
Role: Curator
Function: Offers legal mural work later, creating tension between underground rep and public success.

---

# 44. Example Graffiti Styles

MVP styles:

* Basic handstyle
* Bubble throw-up
* Block letters
* Sharp angular piece
* Stencil icon

Future styles:

* Wildstyle
* Chrome burner
* Roller blockbuster
* Character mural
* Wheatpaste poster
* Sticker slap
* Political stencil
* Memorial mural

---

# 45. Example Districts for Future Expansion

## Mill Yard

Industrial starter zone.

## Canal Side

Bridges, water, old tunnels, high-visibility walls.

## Downtown

Businesses, cameras, high pedestrian traffic.

## Train Yard

High risk, high rep.

## Rooftop Row

Hard-to-reach blockbuster locations.

## Gallery Quarter

Art-world missions and legal walls.

## Substation

Industrial infrastructure and security-heavy zones.

---

# 46. Success Criteria for Prototype

The prototype is successful if a tester can say:

* “I understand why painting this wall matters.”
* “I noticed the city changed because of what I did.”
* “I got annoyed when a rival wrote over my work.”
* “I wanted to come back and reclaim the wall.”
* “Recruiting a crew member felt useful.”
* “I can see how this could grow into a bigger RPG.”

---

# 47. Implementation Agent Instructions

The implementation agent should proceed in small, testable increments.

## Agent Rules

1. Do not attempt to build the full game at once.
2. Prioritize playable systems over visual polish.
3. Keep all major systems data-driven.
4. Use placeholder art until systems work.
5. Make walls persistent as early as possible.
6. Make rival reactions simple but visible.
7. Avoid scope creep.
8. Document every major system.
9. Create test scenes for each mechanic.
10. Maintain a running changelog.

## First Agent Task

Create the base project and implement:

* A small graybox city block
* Player movement
* Paintable wall component
* Interaction prompt
* Basic graffiti placement using placeholder decals
* Reputation increase when graffiti is placed
* Wall state saved in memory

Do not build missions, crew, or rival AI until graffiti placement and wall state are reliable.

---

# 48. Suggested Folder Structure

```text
/Game
  /Scenes
    MainMenu
    PrototypeDistrict
    Test_GraffitiWall
    Test_CrewRecruitment
  /Scripts
    /Player
    /Graffiti
    /Walls
    /Crew
    /Rivals
    /Missions
    /UI
    /SaveSystem
    /Data
  /Art
    /Graffiti
    /Characters
    /Environment
    /UI
  /Audio
    /Music
    /SFX
  /Data
    walls.json
    graffiti_styles.json
    crews.json
    missions.json
    npc_data.json
```

---

# 49. Placeholder Assets Needed

For MVP, create or source placeholder assets:

* 5 wall textures
* 5 graffiti decals
* 3 rival graffiti decals
* 1 “TOY” cross-out decal
* 1 player character placeholder
* 3 NPC placeholders
* 1 small city block environment
* Spray can sound
* UI icons for reputation, heat, paint, crew

---

# 50. Final MVP Deliverable

The MVP should be a playable build where:

1. Player starts in a small district.
2. Player paints a first tag.
3. Rival crew writes “TOY” over it.
4. Player gets supplies.
5. Player paints stronger graffiti.
6. Player recruits a lookout.
7. Player claims several walls.
8. Player completes a final block-control mission.
9. The district map shows player influence.
10. Save/load preserves the wall states.

The emotional arc should be:

**Unknown → disrespected → improving → recruiting → retaliating → claiming space → becoming known.**
