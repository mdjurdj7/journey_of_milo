# Game Framework (v2 — working)

**Status:** Working design context for the 3D build. Settled items are stated plainly; open items are listed at the end and are not implied by anything above them.

**Companion docs:** Art Direction Bible v2, Region Progression v2, Region 1 Detail v4, Field Asset Spec v1. This document is the structural layer those sit on. Where they conflict on structure, this document wins; the visual principles in the bible still apply.

**Changed in v2:** floors are data; per-floor budget and region length; forward vs. tower; camera and battle-frame rules; Grace replaces Rally; stances; the cost rule for Wanderer cards; the reward economy; the UI language; presentation rules for props vs. characters; open list rewritten.

---

## 1. Shape of a run

A run is a sequence of **floors**. Each floor is a navigable 3D field the player walks freely under a high, close, top-down camera (the Dreams frame: pitch 50°, distance 12 m, the horizon never in frame). The player sees what is in the field and chooses what to approach.

**A floor is data.** `FloorData` holds: the painted landmass mask and its origin, an optional elevation layer, spawn, exit direction, enemies (type, position, yaw), props (scene, placement, world-voice line, overrides), reward pool, gold range, and the wetness/gradient values. `RegionData` is an ordered list of floors. One field scene loads any floor; nothing floor-specific is authored in the scene file.

A floor holds:

- **Encounters** — enemies placed in the field, visible, mostly still. Contact begins combat.
- **Findings** — belongings, standing pools, things left; a state of affairs the player discovers, never a thing that happens to them.
- **Objectives** — what must be done to open the way onward. Today: the floor's required fight.

**Budget per floor** (target ≈ 5–7 minutes): 2–3 encounters of which one is required; one finding; an elite roughly every third floor; the collector once per region; a rest node once per region before the region-end fight. The tutorial floor is the deliberate exception (one crab, the keeper, the hulls). Optional content is where the best finds live and may cost HP to reach (wading).

**Regions** are 3–4 floors, the last carrying the region-end fight. Each region has its own palette, ground, weather and roster, and each is a measurement of distance from the tower. Region 1 is the tidal flat.

**Exits can be anywhere.** A floor declares its exit direction; the gate, the surfaced bar, the worn band and the camera bound key on it. The tower's direction is fixed and separate — a landmark the route bends toward, not an axis.

**Transition.** At the end of the surfaced bar (two steps past the gate line) the field freezes, the camera lifts toward the tower for 0.6 s, the ambience ducks, the frame fades to the fog colour, the next floor loads, and the frame fades back with the Wanderer at the new spawn facing the exit. Deck, HP, gold and RNG state carry (RunState); Toll and Grace are per-combat and do not.

## 2. Combat

Combat happens **in place**. Contact freezes the field, the camera swings side-on (pitch 12°) over 0.6 s, the Wanderer steps to battle spacing, and the card battle plays over the live scene. There is no separate battle backdrop; the tower is visible above the horizon behind the enemy's side of the frame, a fraction larger each floor.

The frame **fits the encounter**: distance from the combatants' extent plus a margin, clamped to a minimum so one small enemy is not zoomed in on; the enemy's side gets slightly more room; the lowest feet clear the hand by a set fraction of the viewport.

Outcomes: **Win** — the enemy is removed; the reward screen follows the frame's return. **Escape** — the Wanderer is pushed back; the enemy remains. **Lose** — the run ends.

Combat feedback is on the field models: lunges, recoils, rising numbers — procedural tweens, not clips. Enemy **intent** (next action: glyph + number) shows above the head from the moment the frame settles, always the *next* action, hidden while the enemy acts, emphasised when lethal.

Multi-enemy encounters are a cluster sharing one contact zone; all members stand in the battle frame. *(Not yet built — see §6.)*

## 3. Systems

**Energy** is the per-turn cost of playing cards, for every class.

**Toll** (Wanderer) accrues only from self-inflicted HP loss — self-damage effects, status ticks, stances — never from enemy hits. It resets per combat. Reckoning spends it 1:1 for damage; Debt Forgiven spends it for HP; the class pool adds collectors and sinks. *Possible later exception: enemy hits give Toll only while cornered.*

**Grace** (Wanderer passive; replaces the old Rally) is survival, not reward. An unblocked enemy hit opens recoverable HP; damage the player deals on their next turn reclaims it 1:1; it is capped per window by the largest single hit and clears at the end of that turn. Self-damage never opens it. Drawn as a pale segment on the HP bar. Cards may later extend the window or raise the cap.

**Stances** are a card type: ongoing per-combat effects, one active at a time (playing another replaces it). Self-Eater: your Attacks deal 3 more and cost 2 HP (the HP loss is self-inflicted and makes Toll).

**Block** absorbs before HP; **absorb** persists longer. If an HP-adjacent mechanic must be cut for complexity, absorb goes before Grace.

**The Wanderer's card rule:** every Wanderer card answers *what does this cost, or what has already been paid.* Plain numbers cards (a Defend, a Bludgeon) belong to the class-agnostic region pool, with one deliberate exception — Endure, the class's "costs nothing" rest card.

**Planned archetype — cornered:** stays at ≤ 25% HP for much greater output. Needs ways in (self-damage), ways to survive there (negate, absorb, Toll→block, Grace), and payoffs that are dead above the line.

**The deck is built from the field.** The keeper's card, fight rewards, belongings, the collector. The deck is the record of how the player walked.

**Rewards.** After a won fight: an interim static screen ("Left behind") over the dimmed field offering gold and a one-of-three card choice (skip is final), rolled from the floor's `RewardPool` via RunState's seeded RNG. Target: world-placed rewards (three cards on the sand where the enemy stood; walk up to lift, walk away to skip) — the machinery exists (`RewardSpread`) and is the eventual default. Belongings: one choice from a bag (a card from a typed pool, or coin, or leave it). Later: enemy drops from a class-agnostic per-region "what stayed" pool weighted toward the killed enemy; class cards from the keeper, belongings and the collector; removal/trade at the collector.

**Enemies are things that stayed.** Region 1's are legible and unaltered; inward they grow stranger because isolation has had longer to work. Strangeness tracks depletion, not difficulty. Enemy contact sounds belong to the enemy (by material).

**Nothing in a floor is arranged for the player.** No room is guarded, prepared or set up as a challenge.

## 4. Presentation

- Godot 4.7.1, 3D. **Props are flat-shaded** (one shared material + tint; silhouette is all that survives). **Characters are textured** (the Wanderer, the keeper). Atmosphere comes from depth fog (14 → 28 m), overcast light (sun 0.9, neutral ambient, soft shadows) and value.
- **Dark figures on pale ground.** Characters, enemies and UI are the dark elements; the world is the pale one.
- **Ground is a painted mask** (30 px/m; white = sand) plus an optional elevation layer; height is a deterministic function of position (`get_height_at`) and everything placed on the field grounds through it. Borders are water: one sea plane, the shoreline from the mask, collision walls out past a wade margin; the inland edge stays dry.
- **Two voices.** *World voice* — authored lines in Spectral, appearing near the thing that says them (the keeper, a hull). *System voice* — UI in Alegreya Sans: ink on the world, no boxes, no glow; cards are bone with ink type; energy pips, Toll and HP readouts as numerals and hairlines.
- **The tower** is visible only in the battle frame and at thresholds — never during the walk. It renders unfogged as a silhouette almost the colour of the sky.
- Region 1: no warm light anywhere. Surfaces may carry a slight warm bias; light may not.
- Tunables are exported with live setters; the Remote tab is the tuning panel. Nothing hardcodes an axis.

## 5. Two-person production

- Card rules ported from the old project as a deliberate re-derivation; the view layer is new. The old card pool is reference only; Wanderer cards are authored fresh to the cost rule.
- Creature and prop models are generated (Meshy, Smart Topology, texture off for props), imported as glb at real scale, origin at the feet, and take the shared flat material. Characters keep their texture.
- The Wanderer is a Mixamo-rigged humanoid; creatures are mostly still with procedural motion.
- Sound: short WAVs trimmed to the first transient, normalised to −6 dBFS, mixed in-engine; swing < card play < contact; no music in Region 1; the sea/wind bed ducks on contact.
- Two-phase prompts (read-only report → confirm → implement); explicit out-of-scope lists; the human runs the live verification. Never `git add .`; single-concern commits; no push unless told. Data before tuning (RunLogger).

## 6. Open

- Multi-enemy contact and clusters (the island on floor 2 is the first consumer).
- The belongings screen (one choice from a bag) and the belongings pool.
- The collector (shop creature) and removal; the rest node without fire.
- Region 1 roster beyond Sputter; the first elite; the region-end fight.
- Exposed-rock shading for elevated ground; dunes at the dry end.
- The traveller — where he stands on a floor, and the summit encounter (Region Progression §5–6).
- RunLogger as a real per-battle log; all tuning waits on it.
- Whether the interim reward screen becomes the world-placed spread once clusters and belongings exist.
- An editor tool to preview a floor's data in the scene.

## 7. Not decided here

Region names, world-voice text beyond the lines already authored, the game's title, card content beyond the current pools, enemy rosters beyond Region 1, and specific palette values (see the Field Asset Spec for current numbers).
