# Region 1 — Detail v4

**Companion to:** Region Progression v2, Game Framework v2
**Status:** Working. Floors 1 and 2 exist; several threads open and flagged.

**Changed in v4:** rewritten against the 3D build. §2 frame rule softened (a low shelf is permitted). §3 gradient now has concrete values per floor. §6 keeper settled. §9 rewards and belongings updated. §12 threads closed or re-stated. Wrack-line, hull, and 2D-layer language removed.

---

## 1. What the region is about

**Crossing into range.** The shoreline is where the player starts, but the subject is the walk inland — across the boundary where the signal begins to have effect. The player came from somewhere that still had things in it. Everything from here inward has less.

### Water

The region is a **tidal flat**: the zone between where the sea reaches and where it does not. It makes the threshold visible, gives water without giving a sea, and is the most inhabited ground there is — which is what the least depleted region needs.

The sea is still not the subject. The subject is the ground the sea has left.

---

## 2. Spatial logic

Arrival at the water's edge → inland → the land narrows to a neck → the way onward is under water until the floor is cleared → a bar surfaces → the next floor.

**Direction of travel is away from the sea.** The sea is a thing the character could turn back toward and doesn't.

**Frame:** horizontal throughout. A low exposed shelf (≈1 m, walkable from the landward side, a drop on the seaward side) is permitted as the first exposed rock of the dry end arriving early; cliffs, banks, anything overhead are not. Region 2 begins the compression; Region 1 spends almost none of it.

**Exits.** A floor's exit can be on any side. Region 1's first two floors exit inland; later floors need not.

---

## 3. The wet-to-dry gradient

Region 1 is a gradient from tidal flat to dry inland, and the run moves along it. Each floor's `FloorData` carries the values; depth sets a target and floors vary around it.

**Early — wet.** Standing pools, reflective flats, the most life in the game. Interior height 0.25 m above sea level, relief 0.15, caustics 0.15.

**Middle — the transition.** Damp giving way to dry. Interior height rising, relief growing, caustics fading. Floor 2: 0.30 / 0.18 / 0.12.

**Late — dry.** Dunes (elevation layer), marram at its densest, no standing water, first exposed rock, the sea gone from the frame.

**What the gradient drives:** ground tint, standing water, wet band, vegetation (not yet built), visible life, landform (elevation layer), the worn band's depth.

**Ground is authored:** a painted landmass mask per floor (30 px/m) plus an optional elevation layer. Painted shapes should not repeat: a bulb with a neck (floor 1), a bar with a pinch and an island (floor 2), and something else again after that. If every floor is a bulb, the player learns the shape and stops looking.

---

## 4. The tower across Region 1

Visible in every battle frame and at every threshold, never during the walk. Grows ≈2% per floor. Across the region, from unreadable to barely resolvable.

---

## 5. Condition — the least depleted region

Region 1 is the **benchmark**. Everything after reads as emptier by comparison.

- Vegetation healthy and unremarkable (not yet built).
- Ground undisturbed. No damage anywhere.
- Near-zero built structures. Hulls are boats, not buildings, and only in the opening floor.
- Roads faint: the worn band is subtle enough to lose.
- **Someone is still here.** The keeper (§6). Something is still here: the cormorant, the pool with a crab beside it.

---

## 6. The keeper — the opening floor (settled)

One figure at the shoreline, present at the start of every run. She stands on the **east shore** of the opening flat, a little over a metre from the water, facing out over it, her back three-quarter to the camera. In frame from spawn, ~12 m away.

**Function.** She is the run's starting hand, delivered by a person: she holds out one card — a small bone card in her outstretched hand, which lifts to a readable card when the player is near; click to take. One of three class-neutral cards per run, rolled from her pool. Take it or don't; either way the transaction is complete.

She is the only figure in the game looking the other way. The player leaves her behind in the first floor. She is the last person who speaks to the player for a long time.

**Lines** (world voice, Spectral, near her, no speech framing): on first approach, *"She holds something out. It was not hers."*; on every re-approach after, *"Still facing out."* No other text.

**Constraints.** She does not explain, follow, request, need, or turn. She is present in every run. Her hem and hair move in the wind; she does not.

**Her pool** (`cards/neutral/`, no class flavour): Left Hand (deal 6; 10 if first card this turn — half of a future set with Right Hand), Untouched (block 4, +4 if undamaged last turn), Second Thoughts (draw 2).

### Relationship to the collector (§9)

The collector is a function still executing with the owner gone. The keeper is a person who stayed and is not doing anything. The collector is busy; she is still.

---

## 7. The traveller — first appearance

One NPC, travelling the same direction as the player. He recurs across the run (Progression §3, §5). **Not yet built.**

**Constraints.** He does not explain, need, or stop. He must be established here as unremarkable and in good condition, and he must be ahead of the player when he leaves the frame.

**Open:** how he exists on a data-driven floor — a prop with a line that is simply *further along* each floor, or something that moves.

---

## 8. Light

**Bright and empty, not cold and empty.** High pale sky, washed out. Depth fog 14 → 28 m in the sky's colour; sun 0.9 neutral-cool with soft shadows; neutral ambient. No warm light anywhere in the region — no golden hour, fire, warm rim or warm sky. Rest happens without fire.

**Surfaces may lean warm.** Dry sand (0.74, 0.70, 0.60), bleached wood, exposed stone: R−B ≈ +0.1 in 0..1 terms. Wet sand darker, not lighter (× ~0.72). Water cool and slate — shallow (0.54, 0.60, 0.61), deep (0.26, 0.36, 0.41) — with the seabed visible and caustics through the shallows. Dry sand is the brightest large surface in the frame; nothing on the water is brighter than it.

---

## 9. Floor and event grammar

### Governing principle

**Nothing in this region was arranged for the player.** Things set down and not picked up. Mid-use, unhurried, no panic.

### Rewards after a fight

Interim: a static screen over the dimmed field — *Left behind* — offering gold and one card of three; skip is final; walking on closes it. Target: three cards on the sand where the enemy stood, taken by walking to them (the machinery exists).

### Belongings (findings)

Someone's pack, set down. Walk up, a line, and one choice: what's inside (a card from the belongings pool), the coin, or leave it. You take one thing. The register is **intrusion**, and the owner is not dead, merely gone.

### Standing pools

Water the tide left, still (no swash, no foam), sky in it, caustics on the bottom, a wet rim. Something is usually beside one. Painted into the mask as enclosed water.

### Optional ground

Islands reached by wading a shoal (thigh-deep, deep water either side; the wade costs HP with the drain on); alcoves under a shelf's seaward foot reached only from the water. Optional ground holds the better fights and finds, and the walk to it is part of the price.

### Rest

**Rest without fire.** Open: what replaces the fire as the reason to stop — shelter, water, sitting down, or the act of stopping.

### Events

Findings, not incidents. A fork where one path is worn and one is not; a place where something was left mid-action.

### Shop — the collector (not yet built)

**Exchange without a merchant.** A creature bred or trained to fetch, carry, sort and hand over, still doing the job centuries after the people left. Same failure mode as the tower at the scale of one animal.

Guardrails: it is not waiting for the player and does not like them; it is good at its job; no mammal warmth. It keeps an appointment with a building that is no longer there. Removal/trade lives here.

### Combat

The only room type requiring no re-registering. See §10.

---

## 10. Encounter logic

Enemies are things that stayed. **Strangeness scales with depletion.** Region 1's roster should read as understandable: today one enemy (Sputter, a crab); the roster needs two or three more, one elite, and the region-end fight.

Enemies stand still, often facing away from the player — a crab looking at a pool is the premise in one frame. Contact begins combat; clusters share one contact zone (unbuilt).

---

## 11. What Region 1 must not do

- No ruins or rubble; no damage of any kind
- No warm light (slight warm bias in dry surfaces is permitted)
- No gloom, heavy weather, or darkness
- No verticals except the tower and a low exposed shelf
- No explanation, from the keeper, the traveller, or anything else
- No maritime subject matter beyond the opening floor (the hulls appear once)
- No humanoid merchant
- No room that reads as arranged, guarded, or prepared for the player
- No props that explain: a crab beside a pool, not a crab among rocks

---

## 12. Open threads

**Threshold marker.** Answered: the neck, the channel, and the bar that surfaces.

**Arrival method.** Answered: by sea — hulls hauled above the tide line, spawn at the water's edge.

**Non-traveller life.** Partly answered: a cormorant on a hull that leaves when approached; something beside each pool. What else, and how represented, is open. Birds at the waterline are the cheapest next step.

**Multi-enemy clusters.** Needed for the island on floor 2 and for the AoE cards to mean anything.

**The collector's recurrence deeper in.** Open.

**The traveller on a floor.** Open (§7).

**Vegetation.** Nothing yet — marram at the dry end, sparse salt-tolerant tufts at the wet end. Follows the elevation layer and the dunes.

---

## 13. Not decided here

Region name, world-voice text beyond the lines authored, the traveller's appearance, the keeper's name and why she stayed, the collector's species and form.
