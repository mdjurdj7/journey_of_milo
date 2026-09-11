# Deck Builder — Design Document

## Overview

A single-hero roguelike deckbuilder inspired by Slay the Spire's core loop:
cards, energy, telegraphed enemy intents, a branching map, and repeatable
runs. Where it diverges from that inspiration is in identity and world —
characters are jobs with real lore, and the world tells its story through
what you find rather than what it explains.

## Re-theme (2026-08-30)

The region's industrial and wreckage framing has been removed
deliberately. It is not deprecated or paused — it is cut.

The world premise has changed. `REGION_PROGRESSION_v1.md` is the current
source of truth for premise, world state, and region structure.
`REGION_01_v1.md` holds the first region's constraints.
`BACKGROUND_ASSET_SPEC_v1.md` holds background asset strategy.
`ART_DIRECTION_BIBLE_v1.md` holds the visual specification.

The existing ## Biomes section below predates this change and has not
yet been reconciled. Where it conflicts with the new documents, the new
documents win. Terminology is now "region", not "biome".

Industrial silhouette functions and vocabulary in `field_room.gd` are
now orphaned by design and scheduled for removal. They are not to be
extended or reintroduced.

## Pillars

### 1. Characters as main jobs

Each playable character has fixed lore, an aesthetic, a combat philosophy,
and a curated card pool. Character identity IS the main job — you aren't
picking a class skin, you're picking a specific person with a specific way
of fighting and a specific place in the world.

A character's identity may also include its **resource system**, not just
its card pool — how a character generates and spends the thing that gates
playing cards is a primary lever for making characters feel mechanically
different from each other, not just re-skinned. Working examples for
future characters:

- **Classic energy** — a flat per-turn allowance to spend (Slay the
  Spire-style).
- **Rage/momentum** — build a resource via cheap attacks, spend it on
  finishers.
- **Cooldown/rhythm systems** — FFXI-inspired, cards or abilities recover
  over time rather than drawing from a shared per-turn pool.

**Implementation status (underlying system, no select UI yet):** a
`CharacterData` resource (`character_data.gd`) holds a class's name and
`card_pool_folder`; `RunState.current_class` says which class the current
run's player is (hardcoded default for now, since there's no
character-select screen). Reward pools are fully per-class, Slay the
Spire-style — `reward_screen.gd` folder-scans only the active class's
`card_pool_folder`, never a shared pool. The starting deck
(`RunState.STARTING_DECK`) stays universal regardless of class. Two
classes exist so far: Wanderer (`resources/cards/classes/wanderer/` — the
full original card set) and Samurai (`resources/cards/classes/samurai/`).
The Samurai (renamed from the earlier "Rogue" placeholder 2026-09-03,
which had 2 throwaway cards — Backstab and Shadow Step, both deleted) is a
chain/combo class built on the existing OPENER/CLOSER system (see
`card_data.gd`'s `ChainRole` and the "Combat tempo / momentum-sequencing"
note below). **The Opener/Closer chain mechanic is light and optional for
every other class** — e.g. the Wanderer's Bite Down is an Opener that
carries no payoff of its own — **but for the Samurai it is the core,
heavily-ingrained identity mechanic**: its pool is meant to be designed
around setting up and spending chains, not treating them as an occasional
bonus. Its card pool is **intentionally empty right now** — the folder
holds only a `.gitkeep` — pending card design.

### 2. Subjobs

A secondary discipline acquired during a run, layering a smaller splash of
cards or a passive mechanic onto the character. Working idea: subjobs are
discovered in the world — relics, inscriptions, remnants of those who came
before — fusing them with the lore and drops pillars. A subjob should feel
like you've absorbed a fragment of someone else's story, not like you
unlocked a talent tree node.

### 3. Rare drops

Equipment that is exciting and build-defining, carrying the world's lore
through cryptic item descriptions. A rare drop should make you want to
read its flavor text twice and reroute your run plan around it.

**Rarity tiers** (applies to cards now, and to equipment once it exists):
COMMON, RARE, ULTRA_RARE, SECRET_RARE. SECRET_RARE is deliberately kept
out of normal reward rolls for now - see Ideas Parking Lot.

### 4. Challenge & worldbuilding philosophy (Dark Souls, narrowly scoped)

Two things borrowed deliberately, nothing else:

- (a) Hard-but-fair difficulty — the player should be able to trace every
  loss back to a decision they made, not a stat check.
- (b) A world that doesn't explain itself — lore lives in item
  descriptions and environmental storytelling, not exposition dumps.

Explicitly **NOT** grimdark. The hardness is mechanical, not tonal.

### 5. Aesthetic

Varied, vibrant environments in the spirit of Chrono Cross, FFXI, and
Kingdom Hearts — beaches, mountains, ancient villages, ruins. Branching
paths may eventually route through different biomes.

## Open Questions

1. **Emotional tone** — lonely/post-collapse vs. populated/lively?
   Leaning lonely and melancholy (Shadow of the Colossus, Chrono Cross:
   beautiful but haunted by absence). Undecided.
2. **Subjob acquisition** — how are subjobs acquired, and can they change
   mid-run?
3. **Resource system roster** — which resource systems (classic energy,
   rage/momentum, cooldown/rhythm, others) actually make it into the game?
4. **Subjobs and resource systems** — does a subjob interact with the
   character's resource system, or only layer in cards?
5. **Combat tempo** — this game should feel different from StS's short,
   per-turn-efficiency staccato. Influences suggest a setup-and-payoff
   cadence (FFXI skillchains/magic bursts, Souls openings-and-punishes,
   FF8 limit moments): longer arcs where turns build toward earned burst
   windows. Levers to explore: fight length, how coupled consecutive
   turns are, enemy patterns as longer readable phrases, resource systems
   that accumulate across turns. Statuses/keywords should be designed to
   SERVE the chosen tempo, not imported. Deliberate design session
   needed.

   **MOMENTUM / SEQUENCING MECHANIC (strong lean, not yet designed in
   detail):** combat should reward sequencing cards deliberately, not
   just spending energy efficiently - this is the concrete mechanical
   expression of the setup-and-payoff tempo thesis above. Leaning toward
   a category-based chain system (inspired by FFXI skillchains) rather
   than card-specific synergy text: playing cards of matching/
   complementary types in sequence builds a counter or triggers a bonus,
   using the existing `card_type` field rather than requiring cards to
   reference each other individually - cheaper to build and balance for
   a small team, and truer to the actual reference. Open sub-questions:
   does a broken chain reset to zero or decay gradually; is this a
   universal system, or IS this character one's specific resource
   identity (strong potential tie-in to Pillar 1, characters as main
   jobs); what a completed chain actually rewards (bonus damage, a draw,
   something else). Needs a dedicated design session before building -
   significant enough to shape card design and resource identity going
   forward, not a quick add.

   **Current lean on universal-vs-character-specific (2026-09-03):** BOTH,
   at different intensities. The lightweight `chain_role` OPENER/CLOSER
   prototype stays available to any class as an occasional bonus (the
   Wanderer's Bite Down uses it this way), but it is the CORE identity
   mechanic for the Samurai class specifically - that pool will be built
   around chains rather than dabbling in them. See the Samurai entry
   under Pillar 1.

   **MINIMUM VIABLE PROTOTYPE built for feel, NOT the answer to the
   open questions above (DECIDED - implemented):** before committing to
   the full category-based system, built the smallest possible slice to
   let the setup-and-payoff FEEL actually be played, not just discussed.
   Deliberately not the real system - no decay/reset question resolved,
   no universal-vs-character-specific decision made, no reward beyond a
   flat damage number. Two roles on `CardData.chain_role` (see its own
   note): `NONE` (every card except the two below), `OPENER`, `CLOSER`.
   Playing an Opener sets `battle.gd`'s `chain_empowered` true; the next
   Closer played consumes it; unused, it expires when the turn ends
   (`_discard_entire_hand()`). A second Opener played while already
   empowered is WASTED, not refreshed - deliberately: the empowerment
   already lasts until end of turn or consumption, whichever comes
   first, and a second Opener can't extend either of those, so
   "refresh" would be a distinction with no actual effect to express -
   the boolean model makes this the natural behavior with no special-
   case code, not an extra rule bolted on. Slash (existing starting-
   deck card, was "Strike" until the 2026-09-05 rename) is the test
   Opener; Heavy Blow (existing wanderer card, 12
   damage) is the test Closer.

   **Opener swapped from Slash to Bite Down (2026-08-23):** Slash's
   `chain_role` reverted to its `NONE` default; Bite Down (see its own
   entry below - a `CardEffect.EffectType.HEAL`-refund CLOSER payoff was
   removed from it 2026-08-26, unrelated to this) now carries `chain_role
   = OPENER` instead. Heavy Blow stays the test Closer, unchanged.

   **Chain state moved from card text to a glow (DECIDED - implemented,
   superseding this section's original text-based version):**
   playtesting the first version (an appended "Closer"/"EMPOWERED: N
   damage" line on the card face, in the `[keyword]`/`[modified]`
   semantic tags) found it read as clutter and, worse, as the CARD being
   buffed rather than a CHAIN completing. Replaced with `card.gd`'s
   `chain_glow`, toggled by `set_chain_available(active)`. A Closer's
   card text now carries NO chain wording at all, ever; an Opener keeps
   a single minimal line, no explanatory sentence - now (REFINED
   2026-08-24) its OWN smaller, unbolded style
   (`chain_role_font_size_px`/`chain_role_color`, both `@export`ed on
   card.gd) rather than the shared `[keyword]` tag it started with -
   playtesting/review found `[keyword]`'s bold full-size treatment
   (correct for an inline rules term like Kept Warmth's "Consumed")
   inverted the hierarchy here, reading bigger/bolder than the card's
   own effect text above it. `_chain_role_suffix()` builds this
   directly with explicit `[font_size=]`/`[color=]` BBCode rather than
   through `CardTextStyles`' shared STYLES dict, since the size has to
   scale with this card INSTANCE's own current `_scale_factor` -
   STYLES has no notion of that, it only emits fixed color/bold/italic.
   `ChainGlow` (a child of `Visual` in card.tscn) had to be
   reparented from a sibling of `Visual` to a CHILD of it after
   playtesting found it didn't move with the card on hover - hover/
   armed/refusal animations only ever animate `Visual`'s own position/
   scale (see `card.gd`'s `_play_hover_tween()`), so a sibling node just
   sat still while the card rose past it; as a child, it inherits that
   same transform for free, no new animation code needed.

   The glow itself went through a second round after that: a hard-
   edged border ring (the first version) played fine as a proof of
   concept but was too easy to miss and too visually similar to two
   already-crowded "ring around the card" channels - the hover state
   and the rarity border. Two changes fixed that:
   1. A soft SHADOW instead of a border, via `StyleBoxFlat`'s own
      `shadow_color`/`shadow_size` (real blur, nothing custom) -
      `ChainGlow`'s rect now matches `Visual`'s own exactly, since a
      shadow already blurs OUTWARD from its box's edge on its own; no
      more manual oversize/offset math to push a ring past Visual's
      edge. Reads as light spilling from behind the card, not a line
      drawn around it - genuinely distinct from the hard-edged rarity
      border, and from hover, which never drew a border at all.
   2. A slow PULSE (`chain_glow_pulse_period_sec`, tweening `chain_
      glow`'s own `modulate:a` between 100% and 60% of `chain_glow_
      intensity`, infinite-looped) - motion is what actually catches
      the eye during play. Reuses `vitals_bar.gd`'s own low-HP pulse
      shape exactly (`set_loops()`, `TRANS_SINE`/`EASE_IN_OUT`, two
      legs of the same duration) rather than inventing a second
      breathing-animation pattern. The dip amount itself is a fixed
      internal constant (`CHAIN_GLOW_PULSE_DIP`), not its own export -
      the brief asked for exactly four tunables (speed, intensity,
      spread, color), and "how breathy" is a fixed character of the
      effect rather than a per-tuning-pass knob.
   `chain_glow_color`/`_intensity`/`_spread_px`/`_pulse_period_sec` are
   all exported. Both the pulse (`modulate:a`) and hover/armed
   (`Visual`'s own `position`/`scale`) animate different properties, so
   neither fights the other - a glowing Closer stays legibly pulsing
   even while hovered.

   **Chain sound wired in (DECIDED - implemented):** `audio_manager.gd`'s
   `"chain_impact"` now maps to a real file, `chain_burst.mp3` (~2s, a
   boom/crack with tail), still played layered on `"damage_enemy"` at
   the chain payoff's own delayed beat (see the payoff-sequencing note
   above) - both the same frame, on separate pooled players. Checked
   the actual overlap risk rather than assuming: parsed `hit.wav`'s WAV
   header directly (sample rate/data-chunk size, no external tool
   needed) - exactly 0.172s long, comfortably inside the 0.3s `chain_
   payoff_delay_sec` gap, so the Closer's own hit sound has already
   finished before the chain sound ever starts.

   **The payoff is a separate follow-up hit, not a boosted value
   (DECIDED - implemented, superseding this section's original +6-bonus
   version):** the original version added `CHAIN_CLOSER_BONUS_DAMAGE`
   directly onto the Closer's own effect value (12 -> 18 in one
   resolution) - mechanically fine, but it meant the card being buffed
   WAS the chain completing, the same "buffed card, not a chain"
   framing the glow section above already moved away from on the visual
   side. Restructured so the Closer's own effects always resolve
   completely unmodified, and a chain payoff is a SEPARATE, later
   `_resolve_card_effect()` call (`battle.gd`'s `_trigger_chain_payoff()`)
   against a `CardEffect` (`_chain_payoff_effect`) that lives on Battle,
   not on the Closer card - `CHAIN_PAYOFF_DAMAGE` (8) lands as its own
   hit on top of Heavy Blow's untouched 12, for the same ~20 total
   ballpark the old +6-to-18 approach landed in, tuned up slightly now
   that the payoff carries its own full impact treatment and needs to
   read as a satisfying hit on its own, not a token addendum. Routing
   through the SAME `_resolve_card_effect()` every other effect already
   uses (rather than calling `_deal_damage_to_enemy()` directly) is what
   lets a future chain payoff be something other than damage with ZERO
   new resolution code: that match already handles BLOCK/SELF_DAMAGE/
   DRAW/HEAL identically to DAMAGE (none of those branches read
   `target` at all), so changing `_chain_payoff_effect.effect_type`/
   `.value` in `_ready()` is all a block-granting or card-drawing chain
   payoff would need. The one thing that WOULD need new code is an
   `EffectType` this match has no case for yet (applying a status, say)
   - the same cost any other new card effect would already need, not
   anything chain-specific. One shared effect for every chain today,
   matching this prototype's "one flat number" simplicity everywhere
   else; promoting it to a per-Closer field
   (`CardData.chain_followup_effect`) would be the natural next step if
   different Closers should ever trigger different payoffs.

   Playtesting this version surfaced a real sequencing problem: the
   payoff triggered in the SAME frame as the Closer's own hit, with only
   a small internal delay (`enemy.gd`'s own hitstop, before its VISUALS
   revealed) separating them - not enough for the two to read as
   distinct events. Fixed by moving the delay to where the sequence
   actually needs pacing: `battle.gd`'s `chain_payoff_delay_sec`
   (0.3s - mid-range of a "clearly two beats, not one" target) now
   delays the payoff's TRIGGER itself (`_trigger_chain_payoff()` awaits
   it before calling `_resolve_card_effect()` at all), called fire-and-
   forget from `_play_card()` so nothing else about that card's own
   bookkeeping (hand spacing, affordability, energy/pile labels) waits
   on it. Guarded against the target already being gone by the time the
   delayed trigger fires (a corpse doesn't get a second hit, same
   instinct `_check_pain_turn_trigger()` already follows). `enemy.gd`'s
   own hitstop-before-reveal became redundant once the trigger itself
   was what needed spacing out, and was removed - `flash_damage()` is
   fully synchronous again.

   **Impact feedback for the chain payoff (DECIDED - implemented):**
   the payoff has to be FELT, not just read as a number, or the feel
   test can't answer the question it exists to answer. No impact-tier
   system existed anywhere in the project yet (checked before building
   - no camera shake, hitstop, or graded hit-feedback of any kind, in
   battle or the field), so this built ONE small tiered system rather
   than a one-off "chain hit" special case: every channel below has
   both a normal-hit setting and a stronger payoff one, all
   `@export`ed, so "stronger than a normal attack" is an actual felt
   comparison. All four fire together on the payoff specifically (see
   the sequencing note above for why that's now a real, separate beat)
   - never on the Closer's own hit, which always uses the plain tier.
   - **Burst** (`enemy.gd`'s `_play_chain_burst()`): the existing red
     hit-flash (`_play_flash()`) still fires for every hit unchanged -
     reads as "you got hit," and shouldn't stop meaning that. The
     payoff ADDS a new element on top: a filled circle built entirely
     in code (Polygon2D has no built-in circle shape, so a small
     `_circle_points()` helper fakes one), scaling up from small while
     fading out. Amber, matching `chain_glow`'s own color and
     `CardTextStyles`' `"modified"` style - one color vocabulary for
     "chain" across the whole feature.
   - **Screen shake** (`battle.gd`'s `_play_screen_shake()`): this
     scene has no `Camera2D` to shake (static, non-scrolling), so this
     moves the whole `UI` `CanvasLayer`'s own `offset` instead - the
     one property that visibly moves everything under it at once. A
     short, decaying side-to-side jitter.
   - **Sound** (`audio_manager.gd`): a new `"chain_impact"` SFX name,
     played ALONGSIDE `"damage_enemy"` (both fire the same frame,
     landing on two different pooled players - genuine layering) - no
     file mapped yet (same placeholder convention as `"heal"`/
     `"block_gained"`), wants a distinct texture (a crack/boom) that
     still reads UNDER the normal hit sound rather than a louder copy
     of it.

   Verified via headless battle instances across the whole arc of this
   feature: playing Slash then Heavy Blow while empowered dealt exactly
   the intended total damage every time it was checked (18 under the
   bonus-value version, 20 split 12-then-8 under the separate-hit
   version), confirmed via enemy HP delta; a second Slash while already
   empowered left state unchanged; unused empowerment cleared on end-of-
   turn discard; a Closer drawn mid-turn after an Opener showed its
   chain-available state immediately, no click needed to "notice" it;
   `play_sfx("chain_impact")` confirmed firing layered on `"damage_
   enemy"`; screen-shake peaks confirmed distinguishable between tiers,
   not just in exported numbers. One real bug caught along the way: an
   early version of the appended card-face text wasn't being run through
   `CardTextStyles.expand()`, so semantic tags rendered as literal
   bracketed text - moot now that Closer text was removed entirely, but
   the underlying "expand the combined string once, not each part
   separately" lesson still applies to Opener's own remaining line.
6. ~~**Equipment mechanics**~~ **MINIMAL SLICE IMPLEMENTED (2026-08-22)**
   — see the Rewards section's own "Equipment as card modifiers" note,
   now split into a DIRECTION DECIDED paragraph and an IMPLEMENTED one
   underneath it. Equipment modifies how existing cards behave (not
   passive stats, not granted cards - that's the subjob system's role);
   one weapon slot, one weapon (Last Wages), three modifier shapes, and
   loot/UI wiring now exist and are dev-testable. Still open: the
   armor/trinket slots, stacking limits once there's more than one
   slot, and real acquisition (drops/shop) - a real design session with
   my brother is still needed before any of THAT gets built.
7. **Quest items** — does including quest/story items as a reward type
   imply a full quest system, or just flavor collectibles?
8. **Encounter avoidance cost** — what does it cost the player (time,
   resources, risk) to avoid a visible encounter rather than engage it?
   See Run Structure & Navigation's field mechanics parking lot.
9. ~~**EVENT room content**~~ **DECIDED (2026-08-23)** — every EVENT
   room now spawns The Pay House, the first real enterable structure
   (see Sunken Works below and the new Equipment note on its second
   weapon-acquisition path). Not a pool of possible events yet - just
   this one, always - but the placeholder marker ("An event would happen
   here," printed and nothing else) is gone from the EVENT path for
   good, replaced by a real three-way decision with a real cost and a
   real reward.
10. **BOSS room design** — the run graph now routes to a real boss room
    (see Run Structure & Navigation's Run graph section), and it now
    fights a real, dedicated encounter (BOSS_01, see the Bestiary's own
    entry for the Charge mechanic - 2026-08-29, BOSS_01 pass), not the
    old scaled-up-regular-enemy placeholder. Naming, fiction, silhouette,
    and art are still entirely undesigned - "BOSS_01" is a working name
    only, deliberately out of scope for the pass that built the mechanic.
    One directional constraint now exists ahead of that session, from
    the Beachwrack's own design note (see Bestiary below): whatever the
    Sunken Works boss becomes, its silhouette logic should read as
    ARCHITECTURE that walks (facility that became mobile), distinct
    from the Beachwrack's biology that accumulated the facility onto
    itself - the two share materials (rust, industrial fittings,
    concrete-adjacent tones) but not body plan, deliberately, so the
    Beachwrack establishes the biome's material world without
    telegraphing what the boss actually is.
11. **Run graph visibility** — should the player ever see the graph
    (a map screen, a reveal-as-you-go view), or does it stay hidden and
    only manifest as the doors in front of them? Not building a map
    screen yet either way; the dev-only console printout (see Run graph
    below) is not a stand-in answer to this question.
12. **Field figure anonymity** — the field figure (see Run Structure &
    Navigation's field juice notes) is deliberately an anonymous
    silhouette right now. Does it stay that way, or become
    character-specific (a per-character shape/color, once playable
    characters beyond the placeholder exist)? An anonymous silhouette
    supports the beautiful-but-lonely tone (Journey, Shadow of the
    Colossus at a distance - see Pillar 5 and open question 1); a
    character-specific figure would support Pillar 1 (characters as main
    jobs, a specific person with a specific way of fighting) instead.
    Undecided which matters more once there's more than one character.
13. **Consumables/items** — should the game have one-shot usable items?
    Case for: variance insurance, hoard-vs-use tension, design space for
    dramatic effects that would be broken as repeatable cards; fits the
    found-remnants fiction as the lowest tier of found objects. Case
    against: cards + equipment + subjobs already give three power axes;
    a fourth risks clutter and competes for reward slots and UI.
    **DECISION DEFERRED** - equipment's general direction is now
    decided (card modifiers, see open question 6 above), but the
    specific question this depends on (does a trinket slot exist, and
    would a one-shot consumable be redundant with it) is exactly the
    "three-slot structure" sub-question that direction left open.
    Revisit once that's settled.
14. ~~**ELITE as a node type**~~ **DECIDED** — see the new ELITE Rooms
    section below. A real run-graph node type now, the same shape SHOP
    already had (guaranteed count, placed in a fixed layer range, door
    previews) - not a chance roll inside COMBAT anymore.
15. **SECRET_RARE acquisition** — now that the regular (COMMON/RARE) and
    rare-drop (ULTRA_RARE) card tables are both decided (see Rewards),
    SECRET_RARE is the one rarity tier with no path to the player at
    all. Reserved for world discovery and optional difficult encounters
    per Pillar 3, but neither of those is designed yet - see Ideas
    Parking Lot's Secret Rare bullet.
16. ~~**Multi-enemy combat mechanics**~~ **DECIDED** — see the new
    Multi-Enemy Combat section below. Battle now genuinely supports 1-3
    enemies, with click-based targeting for single-target card effects
    and sequential (not simultaneous) enemy turns. Field encounters can
    now produce a real multi-enemy fight too - see Bestiary's "Authored
    encounters" (`EncounterData`/`EncounterPool`) and its first entry,
    Twin Glasswings - though most combat blobs still roll a single
    enemy independently, unchanged; authored encounters are the rare
    exception, not the default.
17. **META-PROGRESSION (deferred, significant)** — when a run ends, by
    victory or death, the player earns a persistent currency or XP spent
    OUTSIDE runs to permanently alter future gameplay. Gives failed runs
    value and creates a long-term progression arc across many attempts,
    not just within one. Design capture only - nothing here is decided,
    and nothing should be implemented off this entry alone. Three
    categories of unlock to consider:
    - **New game elements** — permanently adding new card pools,
      equipment, or entirely new playable characters to the random drop
      tables for all future runs. Expands variety over time rather than
      power.
    - **Stat and system modifiers** — in the spirit of Darkest Dungeon's
      town upgrades: spend resources to permanently raise starting HP,
      increase gold drop rates, or unlock services (e.g. a blacksmith
      who lets a run begin with a pre-upgraded card). Directly increases
      power, so needs careful tuning against run difficulty.
    - **Aesthetic and lore progress** — unlocking narrative beats,
      character backstories, or cosmetic changes so the world feels
      reactive to repeated attempts, the same "world that doesn't
      explain itself" instinct Pillar 4(b) already holds for lore
      generally, applied across runs instead of within one. Story
      delivered through repetition rather than despite it (the Hades
      model), not exposition dumped in one sitting.

    Open questions: which currency (single or multiple)? Does it come
    from both wins and losses, and at what rate? Where is it spent - a
    hub screen, a location, something diegetic? Does meta-progression
    risk making early runs feel deliberately underpowered (the common
    criticism of the model)? Should some unlocks be variety-only rather
    than power, to avoid trivializing the base difficulty over time?

    Depends on: a stable run difficulty baseline (so upgrades can be
    tuned against something), and a larger content pool (unlocks need
    things worth unlocking). Revisit once the core run loop is balanced
    and content has grown.

## First Playable

Scope: one battle, one placeholder character, ~5 card types, one enemy
with telegraphed intents, win/lose state.

Character one uses **classic energy (3/turn)** as the baseline resource
system.

**Resource display (DECIDED — a component, not a label):** the energy
readout in battle is `ResourceDisplay` (resource_display.gd/.tscn), a
reusable component with pluggable display modes (`enum Mode { PIP, BAR,
NUMERIC }`) rather than a Label battle.gd formats text into directly.
Battle only ever calls one method, `update(current, max_value)`,
regardless of mode - same "owns the numbers, doesn't decide how they
look" split VitalsBar/Enemy already follow. This is the seam Pillar
1's future resource systems (rage/momentum, cooldown/rhythm) route
through: a discrete per-charge resource like classic energy reads
naturally as **PIP** (filled/dimmed symbols, implemented now, with a
spend-pulse and a staggered refill-sequence animation); an accumulating
meter would want **BAR**; a resource with no natural discrete unit would
want **NUMERIC** - both exist as real enum values already wired into
`update()`'s dispatch, currently falling back to a plain numeric readout
(with a one-time console warning) rather than a real gauge. Adding a
real BAR mode later is entirely a change inside resource_display.gd; no
caller anywhere else needs to change. PIP mode's own overflow case
(`pip_max_threshold`, default 6 - a future energy-boosting effect
pushing max energy higher) reuses that exact same numeric fallback,
rather than needing its own special-casing.

**Explicitly out of scope for this milestone:** map, shops, subjobs,
equipment.

**Data design note:** card data should be structured so a second card
pool (a second character's cards, or an early subjob's cards) can be
layered in later without reworking the first pool. In practice this means
each card's data should stand alone (its own resource/definition) rather
than being hardcoded into a single big list tied to one character.

**Starting deck (balance, tuned repeatedly):** exactly 9 cards - 3x
Slash, 2x Bite Down, 2x Brace, 1x Reckoning, 1x Down Payment (2026-09-05,
starter-deck rework - REPLACES the prior 11-card 5x Strike/5x Guard/1x
Bite Down composition; Strike itself was renamed to Slash later the
same day, same card, same resource). Guard moved out to the Wanderer reward/shop
pool, then RETIRED in the same pass
(`resources/cards/classes/wanderer/retired/guard.tres`) - no longer
guaranteed at run start, and no longer reward/shop-rollable either,
though it filled a starter slot for most of this project's history.
Reckoning is preloaded for the starter deck
from its own class-pool path and stays reward/shop-rollable too - a run
can draft a second copy on top of the one guaranteed at the start.
Heavy Blow is no longer a starting
card; it still exists and is now a reward-pool card instead (moved from
`resources/cards/` into `resources/cards/classes/wanderer/`, so
reward_screen.gd's per-class folder scan picks it up like any other
Wanderer reward automatically). Reckless Swing and Focus, which also
moved this same way at the time, were later deleted outright (2026-08-23,
alongside Berserk Jab, Blood Pact, Bulwark, Crushing Blow, Rend, Second
Wind, and Ward of Pain) - a batch of early AI-generated filler cleared
out to make room for real, deliberately designed cards rather than kept
as reward-pool padding. Quick Slash, which briefly filled the third
starting-deck slot after that point, was removed from the game entirely
(2026-08-24, not moved to the reward pool) - it was a 0-cost attack with
no chain identity that diluted draws without teaching anything.

**Absorb (new, 2026-09-05, Forbearance pass):** a second, independent
damage-reduction pool from block, granted by the new `CardEffect.
EffectType.ABSORB` (first and only user: Forbearance,
`resources/cards/classes/wanderer/forbearance.tres`, 1 energy, gain 8
absorb - a Wanderer reward/shop-pool card, not a starter one). Four
mechanical properties, all decided together:
- **Persists until spent** - unlike block, which clears every turn
  (`battle.gd`'s `_start_player_turn()`), absorb is reset ONLY at battle
  start and otherwise carries across as many turns as it takes to spend.
- **Subtracted after block** - `_resolve_damage()` applies block first,
  then absorb, then whatever's left spills onto HP.
- **Opens no Rally** - Rally only ever fills from damage that actually
  reaches HP (`damage_to_hp`), computed net of BOTH block and absorb, so
  damage absorbed by either one is equally invisible to Rally.
- **Bypassed by self-damage and status ticks** - `SELF_DAMAGE`,
  `SELF_DAMAGE_TOLL`, and any status-tick damage all write to player HP
  directly and never route through `_resolve_damage()`, so absorb (like
  block) never reduces any of those - only an enemy's own ATTACK intent
  can be absorbed.

**The third slot is the deck's IDENTITY card, not a filler slot
(DECIDED) -** whatever occupies it should always teach the Wanderer's
"pays for power" philosophy, not just be whichever cheap attack happens
to be handy. Filled as of 2026-08-24 by **Bite Down**
(`resources/cards/bite_down.tres`, 1 energy, 10 damage, lose 2 HP) -
the 2 HP is unconditional, no way to play around it, which is the
whole point. Originally also `chain_role = CLOSER` with a refund
payoff (a Slash into Bite Down as a full chain available from turn
one, without a reward-pool Closer like Heavy Blow); REMOVED 2026-08-26
because a refund on THIS card's own cost undercut the very lesson the
card exists to teach - see the Wanderer's own Characters entry
("Bite Down's chain payoff: REVERSED") for the full reasoning. Bite
Down is `chain_role = OPENER` now (the test Opener - see the chain
prototype section under Open Questions), carrying no payoff of its own;
it always costs its 2 HP regardless of chain state.
Placed in `resources/cards/` alongside Slash/Guard, not under
`resources/cards/classes/wanderer/`, matching the existing rule that
file location follows DECK ROLE (starting vs. reward-pool), not
thematic ownership - the same reason Slash/Guard themselves live there
instead of the Wanderer's own class folder. Worth naming plainly: this
makes the "universal regardless of class" starting deck noted above no
longer thematically neutral (Bite Down is Wanderer-specific fiction).
Harmless today only because the Samurai has no character-select path to
actually be played yet (see Pillar 1) - a real per-class starting deck
is future work if the Samurai ever becomes reachable, not decided here.

Reward pools are per-class now, not shared - see the Characters section
above. The composition itself lives as one dictionary, `STARTING_DECK`
in run_state.gd - card resource to copy count - specifically so it's a
one-line edit to retune, not a hunt through run-setup code.

## Run Structure & Navigation (DECIDED: field rooms — mechanics still open)

How players move between battles.

**Decision:** field-based room navigation is the run structure. The
field-room prototype confirmed embodied movement increases character
ownership and agency over an abstract node map — that's the deciding
factor, not just aesthetic preference.

**Options considered** (kept for context):

- (a) **Abstract node map** (StS) — cheap, randomizable, genre-standard.
- (b) **Embodied node map** (Darkest Dungeon carriage) — atmosphere at
  low structural cost.
- (c) **Room-based explorable field** (Hades model) — discrete
  procedural-friendly rooms you physically walk through, visible/
  avoidable encounters (Chrono Cross), discovery in the world, biome
  flavor per room. **Chosen.**
- (d) **Continuous overworld** — rejected for now: art/content cost
  multiplies beyond solo scope.

**Decision criterion** (still governs everything built on top of this):
movement must create decisions (routing, risk-vs-avoid, discovery), not
travel time.

**Synergies:** field rooms serve the aesthetic pillar (walking through
beautiful lonely places IS the tone) and the discovery pillar (subjobs/
remnants found in the world).

**Room size:** ~1.2x the screen width, crossable in a few seconds - the
original prototype size (2 screens wide) felt like travel time rather
than a space to make decisions in. Tune further by feel as mechanics get
added, but this is the baseline now, not an open question.

**Field movement redesign (DECIDED) - horizontal-only, matching battle's
own spatial grammar:** the field used to be free 2D movement (any
direction, content scattered at arbitrary Y positions); it's now a strict
side-scroller - the player walks left/right only, pinned to one fixed
floor line (y=540 in every standard-size room), the same left-right axis
Battle Layout already lays combat out on. No jumping, no vertical
mechanic of any kind was added or considered - this is a constraint, not
a placeholder for one. Landed in three small steps, each committed and
verified independently before the next started:

1. **Movement (`player.gd`):** removed the W/S/up/down input entirely -
   `velocity.y` is always `0.0`, so there's no code path left that could
   move the player vertically, not just opposing inputs that happen to
   cancel. A/D and left/right arrows are unchanged. Facing (the battle-
   silhouette flip - see Battle Layout's player silhouette note) already
   only read horizontal velocity, so it kept working with no changes of
   its own.
2. **Camera (`field_camera.gd`, attached to the existing Player/Camera2D
   node):** the camera no longer sits dead-centered on the player - it
   eases its own local x-offset toward `facing_offset_px` (default
   `220px`) in whatever direction the player is currently facing (same
   velocity-reading pattern `player_visual.gd` uses), so more of the room
   ahead is visible than behind - "looking ahead," not off-balance.
   Reversing direction re-centers smoothly (frame-rate-independent
   exponential lerp, rate `offset_smoothing`, default `8.0`), never
   snaps. No new clamping logic was needed for this: Camera2D's existing
   `limit_left`/`limit_right`/etc. (already set per room) clamp the
   rendered view to the room's true edges regardless of the offset, so
   the camera can never scroll past a wall into empty space.
3. **Content positioning (`room_state.gd`'s `SPAWN_SLOTS`, `field_room.
   gd`'s `_exit_positions()`):** every piece of room content - encounter
   blobs, chests, event/shop markers, doors - now sits on that same fixed
   floor line, spread left-to-right across the walkable width instead of
   scattered on the Y axis: entrance near one end, points of interest
   along the way (`SPAWN_SLOTS`' five candidates, 375px apart - clear of
   a blob's own 140px NoticeZone radius on both sides), door(s) toward
   the far end. A room with two forward graph edges now spreads its two
   doors HORIZONTALLY near the far end (`EXIT_X ± EXIT_X_OFFSET`, both on
   the same fixed y) rather than vertically stacked on the old right
   wall - close enough to read as one fork, an 80px gap between their
   hitboxes so they're still distinctly clickable, never past the room's
   true edge. [SUPERSEDED - see the Run Structure & Navigation section's
   own "Navigation redesign - step 1" note: a room spawns exactly ONE
   door now, regardless of edge count, `_exit_positions()` no longer
   exists. Left here as the historical record of this step's own
   reasoning, not the current behavior.] The opening room's chest (see
   its own note below) collapsed
   from three randomized wall-adjacent spots (top/bottom/right) to one
   fixed spot on the line, since top/bottom stopped being reachable
   positions at all once vertical movement was gone.

Proximity/interaction triggers (a blob's NoticeZone pulse, a chest's own
hitbox) needed no logic changes - they're plain Area2D overlap checks,
unaffected by which axis content happens to move along - but every
distance now reads as a clean linear approach instead of an incidental
diagonal one, which is arguably more legible, not just a side effect.

Explicitly NOT done in the movement/camera/positioning steps above
(deliberately deferred): background rendering/art direction, and
door-wall-variation logic - those steps were positioning only, no
visual layer work.

**Step 4 - background layering and ground plane (DECIDED structure,
placeholder content):** the room stopped reading as content floating in
a void once it got an actual side-view composition - EXIT_Y_CENTER (540)
is now both the player's floor line AND the horizon: everything above it
is sky, everything at-or-below it is ground.

- **Ground plane:** `Floor` (`field_room.tscn`) was resized from a
  flat, full-room-height rectangle to just the ground band, y=540 (its
  own top edge, exactly the floor line) down to the bottom wall. Same
  flat color as before, just now positioned to actually mean something -
  the player's feet sit exactly on this shape's top edge instead of
  hovering somewhere inside a uniform floor tint. The opening room's
  ocean/void inset (`_apply_coastal/industrial_opening_room_layout()`)
  keeps working unchanged - it only ever touched the LEFT edge's x
  coordinates on this same polygon, never its y extent.
- **Background layers:** a `ParallaxBackground` (`field_room.tscn`'s
  `Background` node, added as FieldRoom's first child so it renders
  behind everything else) with two `ParallaxLayer` children, FarLayer
  and MidLayer, built and populated at runtime by `field_room.gd`'s
  `_build_background_layers()`, which calls `_populate_far_layer()`/
  `_populate_mid_layer()`. Originally two simple triangle silhouettes
  per layer, placeholder structure only - see the Biomes section's own
  "Applied to the field" note below for what actually fills these now
  (The Sunken Works, not still-placeholder mountains).
- **Parallax speeds (exported, `@export_group("Background layers")` on
  field_room.gd):** `far_layer_motion_scale` (0.15) and
  `mid_layer_motion_scale` (0.45) - both well under the camera's own 1:1
  speed, and clearly different from each other, which is what actually
  reads as depth rather than "a slightly-lagging duplicate of the room."
  Verified headlessly: at a measured camera movement of 380px, FarLayer
  moved exactly 57px and MidLayer exactly 171px - precisely 0.15x and
  0.45x, confirming Godot's own parallax math is doing exactly what the
  exported scale says, and the two layers' movement ratio (171/57 = 3.0)
  exactly matches the ratio between their motion_scale values.
- **No-gap guarantee:** each layer's placeholder content is built as one
  `BACKGROUND_TILE_WIDTH` (900px) tile, then set to repeat forever via
  `ParallaxLayer.motion_mirroring` - this is what makes "never reveals a
  gap at a room edge" true BY CONSTRUCTION rather than by careful sizing:
  the content simply never runs out, regardless of the room's actual
  width or where Camera2D's `limit_left`/`limit_right` (see the movement
  redesign note above) clamp the view. Verified both headlessly (camera
  pinned at its clamped maximum against the right wall, layer positions
  stayed exactly where they were - no runaway drift past the clamp) and
  visually (a real screenshot at the right wall, fully clamped, shows the
  same complete mountain/ground coverage as mid-room, no black void
  anywhere).
- **The ground itself is NOT a ParallaxLayer:** `Floor`, the walls, and
  all room content stay ordinary scene geometry moving exactly 1:1 with
  the camera (motion_scale would effectively be 1.0, which is just...
  not being inside a ParallaxLayer at all) - they have to align exactly
  with the player's real world position, never lag behind it the way a
  background silhouette is supposed to.
- **Biome-swap seam (structure built now, first real content set now
  fills it - see the Biomes section below):** `_build_background_layers()`
  (the layering setup - motion_scale, mirroring, layer count) and the
  populate functions (the actual shapes/colors) are deliberately
  separate. A future SECOND biome would keep the exact same
  ParallaxBackground/ParallaxLayer setup and only swap which populate
  functions fill it - the same variant-dispatch shape the opening room's
  own coastal vs. industrial split already uses for its ocean/void wall
  treatment. Confirmed this actually holds, not just asserted: the
  Sunken Works content pass (see Biomes below) touched only the populate
  functions' own content - zero changes to `_build_background_layers()`
  itself.
- **Verified against both opening-room variants:** real screenshots
  (not just inspected properties) confirm the background backdrop
  composites correctly behind BOTH the coastal room's sand-toned ground
  and the industrial room's concrete floor plus its existing support
  beams/rust decorations (those decorations sit in `content_root`, drawn
  after `Background`, so they correctly render in FRONT of the sky - a
  structure reads as reaching from floor to ceiling, not tucked behind
  the backdrop).

Placeholder shapes only as of this step - see the Biomes section below
for the first real content pass (The Sunken Works); no door/wall-
variation logic touched by either.

**Step 5 - composition & scale tuning (DECIDED numbers, all exported for
further retuning once real art lands):** the structure from steps 1-4
was sound but under-tuned - the floor line sat at the room's dead center
(reading as a shelf, not a world) and every enemy silhouette shared one
uniform field scale regardless of the creature's own authored size,
which made the Glasswing read as roughly a third the player's height -
comical, not fragile.

- **Floor line moved from y=540 to y=900** (`RoomState.floor_line_y`,
  exported, replacing what used to be field_room.gd's own private
  `EXIT_Y_CENTER` const - see below for why it moved autoloads). Against
  the room's 1080-tall viewport: the ground band below the line shrank
  from 500px/46% of the frame (540 to the bottom wall at 1040) to
  140px/13% (900 to 1040) - a thin strip near the bottom, not a split
  screen. Sky - top wall (y=40) down to the floor line - now spans ~80%
  of the frame instead of ~46%, which is what actually reads as "a world
  stretching up and away" rather than "a room."
- **floor_line_y moved from field_room.gd to RoomState:** every position
  that has to stay pinned to the floor line - SPAWN_SLOTS, the opening
  room's enemy/chest spots, both exit-door constants, the background
  sky/ground split - now reads `RoomState.floor_line_y` at the point of
  use instead of embedding y=540 as part of a `const Vector2`. Concretely
  this meant converting `SPAWN_SLOTS`/`OPENING_ROOM_ENEMY_POSITION`/
  `OPENING_ROOM_CHEST_POSITION` from full positions to bare X values
  (GDScript consts can't reference a tunable `@export var`, so the old
  `const Array[Vector2]` shape couldn't stay both const AND
  retunable) - `Vector2(x, RoomState.floor_line_y)` is built at each call
  site instead. One consequence worth flagging explicitly: this is now
  the ONE control for the floor line, but it is NOT the same number as a
  full-height wall's vertical center (see the next bullet) - those used
  to coincide by coincidence (both were 540, since the floor line used to
  BE the room's center), and conflating them after this change would have
  silently mis-centered the opening room's ocean/void wall.
- **`field_room.gd`'s `ROOM_VERTICAL_CENTER` (540, unchanged):** the
  opening room's ocean/void wall (see the coastal/industrial prototype
  notes above) spans the room's ENTIRE height, top to bottom, regardless
  of where the player's floor line sits - it needs the room's true
  geometric center, not the floor line, to stay correctly positioned.
  Kept as its own separate constant specifically so this doesn't
  regress the next time floor_line_y gets retuned.
- **Camera needed NO changes at all for this:** verified headlessly -
  Camera2D's vertical clamp stayed pinned to exactly y=540 before AND
  after the floor line moved, because the room's height (1080) exactly
  equals the viewport height (1080), so the ONLY vertical camera position
  that satisfies both `limit_top`/`limit_bottom` is the room's dead
  center, full stop, regardless of where anything inside the room is
  positioned. Moving the floor line just moves where within that
  already-fully-visible fixed frame the player/ground happen to sit -
  exactly the composition change wanted, with zero camera-side work.
- **Parallax needed no changes either:** re-verified the same headless
  measurement from step 4 (camera movement vs. layer offset) after the
  floor line move - still an exact 0.15x/0.45x split, still zero drift
  once the camera clamps at a wall, still full coverage via motion_
  mirroring. The sky/ground split line these layers key off of (`Room
  State.floor_line_y`) moved, but the mechanism reading it didn't need
  to change - see `_populate_background_layer()`.
- **Floor stays a runtime-computed shape now, not a static .tscn bake:**
  `field_room.gd`'s new `_position_floor()` rebuilds Floor's polygon from
  `RoomState.floor_line_y` (and fixed room-bound consts `ROOM_FLOOR_
  LEFT_X`/`_RIGHT_X`/`_BOTTOM_Y`) every time a room loads, so retuning
  the exported floor line can never drift out of sync with what's
  actually drawn - one source of truth instead of a const the .tscn also
  has to be hand-edited to match.
- **Enemy field scale is now per-creature, not one shared constant:**
  `EnemyData.field_visual_scale` (new export, default 1.0) multiplies on
  top of `field_blob.gd`'s own baseline (`FIELD_VISUAL_SCALE`, raised
  from 0.9 to 3.0 so the DEFAULT - an enemy that doesn't set this field
  at all - already lands close to the player's own height, not
  comically small; `ENCOUNTER_VISUAL_SCALE` scaled up together with it,
  0.68 to 2.27, preserving the same ~0.756 ratio between solo and
  grouped-encounter rendering). Measured each existing silhouette's real
  rendered height against the player's own (via `VisualBounds.compute()`
  - the same utility enemy.gd's battle-side bottom-anchoring already
  uses - headlessly, not eyeballed) and tuned each creature's multiplier
  to its own intended silhouette direction (see each Bestiary entry
  above) rather than a uniform target:
    - Wardling: 1.2 -> renders at ~1.5x the player's height. Explicitly
      "taller than the player and looming," per its own Bestiary entry's
      "tall and too thin" direction - verified via a real screenshot
      with both figures side by side.
    - Tideworn: 1.3 -> ~0.5x player height. "Low and wide (beach-bound,
      not upright)" is this creature's own defining silhouette
      direction, not a bug to fix - shrinking it further than the
      Wardling is correct, not an oversight.
    - Thicket Stalker: 0.9 -> ~0.53x player height. Same "low, wide, four
      stubby legs" reasoning as the Tideworn.
    - Unrelieved: left at the 1.0 default -> ~0.98x player height,
      matching its own "angular and vertical" sentry silhouette.
    - Glasswing: first tuned to 1.05 (-> ~1.0x player height) to fix the
      reported "reads as a third the player's height" complaint - this
      OVER-corrected (reported back at ~2x player height in play,
      towering rather than fragile), so it was retuned again to 0.7
      (-> ~66% player height) once actual design intent was stated
      explicitly: shorter and slighter than the player, reads as
      fragile/quick, NOT looming - the earlier "tall, narrow" silhouette
      note described its SHAPE (thin/vertical), not that it should match
      or exceed the player's height. Re-measured with a rigorous pixel
      scan of a real screenshot (not VisualBounds.compute() alone this
      time - isolating each silhouette's actual on-screen top/bottom
      pixels against a same-row reference column, since VisualBounds
      measures authored shape data, not final on-screen composition) to
      confirm the corrected value lands in the intended 60-75% range
      before settling on it. The Wardling (still the only enemy that
      towers) and Tideworn (still well under player height) were
      re-verified the same way and needed no change - both already
      matched their stated intent.
  Applied inside `field_blob.gd`'s shared `_build_member_visual()` to
  BOTH the real-art and plain-fallback-square branches, so an enemy's
  intended relative size holds even before real art exists for it -
  consistent with every other "unarted enemy still works" guarantee in
  this codebase.
- **Everything bottom-anchored moved together, automatically:** because
  SPAWN_SLOTS/exits/opening-room content all read `RoomState.floor_line_y`
  live rather than embedding their own copy of the old y=540, none of
  them needed a second, separate edit to follow the floor line move -
  moving the one exported number was sufficient, which is the entire
  point of having made it the single source of truth in step 4 already.

All of this - floor_line_y, far/mid_layer_motion_scale (from step 4,
unaffected), and every enemy's field_visual_scale - stays `@export`, on
the understanding that these are eyeballed numbers that will need
retuning again once real character/enemy art replaces the current mix of
a real player sprite and hand-drawn placeholder silhouettes.

**Follow-up fix - trigger/notice radius scale WITH the enemy (field_
blob.gd):** the fight-trigger hitbox and NoticeZone's proximity-pulse
radius used to be fixed sub-resource shapes (80x80, radius 140) baked
into field_blob.tscn, sized against the field scale from before this
whole composition pass - once field_visual_scale made creatures range
from the Tideworn's small silhouette to the Wardling looming over the
player, that fixed size stopped meaning anything (trivial to trigger on
a small enemy, requiring walking almost through a large one). `_resize_
triggers()` now sizes both from visual_root's own real rendered
width/height (via VisualBounds, the same utility the foot-anchor math
already uses) - `hitbox_size_factor` (0.7) and `notice_radius_factor`
(1.1) are the tunable multipliers, `min_hitbox_size`/`min_notice_radius`
floor them so a very small/low creature still gets a genuinely clickable
box. Runs once after the visual is built and again on every live rescale
(the `_on_enemy_data_changed()` rebuild - see the previous field_visual_
scale commit), so retuning an enemy's size live keeps its trigger
proportional too, not just its art. Verified per enemy (Tideworn wide,
Wardling tall-narrow, Glasswing balanced) that the hitbox shape actually
reflects each creature's own silhouette proportions, not one generic
box, and that doubling field_visual_scale live doubles the trigger size
in lockstep.

**Related bug this surfaced - idle bob was discarding position
entirely:** while chasing an unrelated "global vertical drop offset does
nothing" report, found that `enemy_visual.gd`'s idle bob wrote `position.
y = <bob wave>` as an ABSOLUTE assignment every `_process()` frame -
silently erasing field_blob.gd's own foot-anchor/offset math back to
~0 the instant idle motion started. Invisible for years of normal
enemies (their computed anchor already landed close to 0), but exposed
the moment a deliberately large offset (`all_enemies_field_drop_px`)
was added. Fixed by having the bob capture its resting position once in
`_ready()` and sway AROUND it instead of replacing it - confirmed via
enemy.gd (battle) that this node's position is never otherwise touched
there, so the fix is a no-op outside the field.

**Room width tuning pass (DECIDED):** standard combat rooms felt
cramped in the side-scroller layout - the room this replaced (2300
total/2220 interior, a carryover from the room's original top-down
size) produced only ~2.7s of entrance-to-exit walking time. New
baseline, `RoomState.standard_room_width` (`@export`, 4400 default,
same "shared layout config" home `floor_line_y` already lives in):

- **The math**, against `player.gd`'s own `SPEED` (750px/s): target
  4-7 seconds of straight-line walking, entrance to exit, in a single-
  encounter room (no detours) - picked the middle of that range (~5.5s)
  as the design target, giving a target walking DISTANCE of `750 * 5.5
  = 4125px`. Entrance and exit both keep a fixed 100px margin from
  their respective wall's inner face (`EXIT_MARGIN`, unchanged by
  width), so `standard_room_width = 4125 + 100 + 100 + 80` (both
  walls' own 40px thickness) `= 4405`, rounded to a clean `4400`.
  Verified via a real headless walk (not just the arithmetic): a
  standard room's actual entrance (x=140) to exit (x=4260) trigger
  fired at **5.43s** - almost exactly on target, comfortably inside the
  4-7s window.
- **Applied as the ONE shared width** every room uses (standard AND the
  opening room both did before this pass too, per the coastal/
  industrial prototype's own "same footprint, fair comparison"
  reasoning already established) - not a new per-room-type system.
  `field_room.gd`'s `_position_room_bounds()` (new, called every room
  load before `_position_floor()`) resizes TopWall/BottomWall's
  `half_length` and RightWall's position from this one property, the
  same "runtime-computed from a single exported source of truth"
  pattern `_position_floor()` already established for `floor_line_y`.
  LeftWall never moves - the entrance/left edge is always the fixed
  origin regardless of width.
- **Wider rooms for 2-encounter/opening-room dressing - PROPOSED, not
  built this pass:** +20% (`standard_room_width * 1.2 ≈ 5280`) reads as
  sensibly roomier without doubling the crossing time outright - two
  encounters plus a chest need more breathing room than one, but
  shouldn't take proportionally twice as long to walk end to end.
  Building this for real is a bigger structural change than this pass's
  scope (every hand-placed position in room_state.gd/field_room.gd
  would need its own per-room-type width-relative math, not just a
  bigger constant on the one shared value) - left as a real proposal
  for a future pass, not a stub.
- **Re-verified rather than assumed proportional:** `SPAWN_SLOTS`
  (renamed `SPAWN_SLOT_FRACTIONS`) converted from fixed absolute X
  values to FRACTIONS of the walkable width (0.1/0.3/0.5/0.7/0.9),
  converted back to an absolute X via the room's actual current width
  at the point of use (`RoomState._spawn_slot_x()`) - so a future width
  retune keeps every candidate proportionally placed instead of
  drifting toward the entrance or into the exit fork. At the new width
  this lands neighbors 864px apart, comfortably clear of even a
  doubled/oversized enemy's NoticeZone radius (measured up to ~330-400px
  in the trigger-sizing pass) - trigger/notice radii themselves needed
  no change at all, since they scale from each enemy's own rendered
  size (see that pass), never from room width. The opening room's hand-
  placed enemy/chest X (`OPENING_ROOM_ENEMY_X`/`_CHEST_X`) were re-tuned
  to the same ~30%/~65%-of-the-way pacing at the new, longer spawn-to-
  exit distance (1750/3000, from 1150/1650) - re-verified via a live
  walk for that room too (4.77s, its own spawn point sits closer to
  center than a standard room's, by design - see the coastal shore
  spawn note above). Door positioning (`EXIT_X_OFFSET`, the two-door
  spread) needed no change - it's a fixed distance from the wall, not a
  fraction of the room, so it stays correct at any width automatically.

**Follow-up - retuned down after playtesting:** 4400 hit the walking-
time math on paper but read as too wide once actually played.
`standard_room_width` dropped to **2800** - removes ~75% of the 2100px
this pass had added over the original 2300 (`2300 + 0.25*2100 = 2800`),
a feel-based correction layered on top of the time-based math rather
than a rejection of it. Walking time at 2800: `(2800 - 280) / 750 =
3.36s` (verified via the same real headless walk: 3.30s) - now under
the original 4-7s target range, which is fine; that range was a
starting estimate to reason FROM, not a hard constraint once real
playtest feedback exists to weigh against it. Because `SPAWN_SLOT_
FRACTIONS` are fractions of the width (not fixed pixels), they needed
no changes at all to stay correctly placed at the new width - only the
opening room's hand-placed `OPENING_ROOM_ENEMY_X`/`_CHEST_X` (absolute,
not fraction-based) needed re-tuning, to the same ~30%/~65% pacing at
this narrower distance (1300/2000, from 1750/3000).

**Entrance clearance (DECIDED - generalized to ALL content types):**
before this pass, "stay clear of the entrance" was only a loose,
inconsistent convention - `SPAWN_SLOT_FRACTIONS`' own smallest candidate
(0.1) gave every content type a soft ~10% margin (never actually
enemy-specific; chests and event/shop markers drew from the exact same
fraction list an encounter blob did), but that margin was measured from
the WALL, not the player's actual spawn point (which sits `ENTRANCE_
MARGIN`, 100px, further in), and the opening room's hand-placed
`OPENING_ROOM_ENEMY_X`/`_CHEST_X` bypassed it entirely, since they were
never drawn from `SPAWN_SLOT_FRACTIONS` at all. Replaced with one real,
shared rule: no room content of any kind - encounters, chests, event
markers, shop markers, or any future placeable type - may be placed
within `RoomState.entrance_clearance_fraction` (`@export`, default
**0.3**) of the room's walkable width, measured from the player's own
entrance/spawn point. A fraction of walkable width, not a fixed pixel
value, so the same number holds correctly at any `standard_room_width`
retune AND at the opening room's own (different, closer-to-center) spawn
point without needing a second room-specific constant.

Mechanically, ONE function decides this for every content type:
`RoomState._available_spawn_slots()` filters `SPAWN_SLOT_FRACTIONS` down
to only the candidates that clear `_min_content_x()` (spawn position plus
the fraction, converted to an absolute X) BEFORE shuffling - excluded,
not rolled-then-clamped, the same "a filtered-out option never has a
chance to be picked" idiom `_pick_blob_count()` already uses for `max_
encounters_per_room`. Every `SPAWN_SLOT_FRACTIONS`-based layout generator
(`_generate_combat_layout()`, `_generate_treasure_layout()`,
`_generate_marker_layout()` - which `_generate_shop_layout()` also goes
through - `_generate_boss_layout()`, `_generate_elite_layout()`) calls
this one function instead of each duplicating its own `duplicate()` +
`shuffle()` pattern, which is what makes this a single shared rule rather
than a convention every content type has to remember to respect
independently.

**The opening room's hand-placed positions had to come under the same
rule, not stay exempt from it:** they're deliberately NOT drawn from
`SPAWN_SLOT_FRACTIONS` (their own comment explains why - the room's
narrative beats and the chest's guaranteed placement both need control
`_available_spawn_slots()`'s randomness can't offer), but "hand-placed"
should mean "not randomized," not "unchecked." `RoomState.opening_room_
player_spawn_x` (`@export`, `700.0`) moved from `field_room.gd` into
`RoomState` for exactly this reason - the same "one shared source of
truth once more than one thing needs the same number" reasoning
`floor_line_y` was already moved here for (see the composition & scale
pass above) - so `_min_content_x()` can check the opening room's fixed
positions against its own real spawn point, not just the standard room's.
A `RoomState._ready()` assertion (the same "announce a violation loudly
at boot" philosophy `run_state.gd`'s `_validate_run_graph()` already
uses) now checks both `OPENING_ROOM_ENEMY_X` and `_CHEST_X` against this
rule every time the game starts.

That check caught a real, previously-invisible violation:
`OPENING_ROOM_ENEMY_X` was tuned against "~30% of the way from spawn to
the EXIT" (a smaller distance than 30% of the room's full walkable
width, since spawn sits short of the exit), so at `1300` it landed short
of the new rule's `1516` minimum. Re-tuned to **1600** - comfortably
clear, not flush against the boundary. `OPENING_ROOM_CHEST_X` (`2000`)
already cleared the rule with room to spare and needed no change.

**Verified**, not just reasoned through: 40 fresh `RunState.reset()`
generations, checking `RoomState._generate_layout()`'s output for every
room type (COMBAT, TREASURE, EVENT, SHOP, ELITE, BOSS) plus both opening
room variants (coastal and industrial) against `_min_content_x()` -
320 layout generations total, zero content placed inside the clearance
zone.

**Exit clearance + enemy-to-enemy spacing (IMPLEMENTED, 2026-08-23):**
entrance clearance above never had an exit-side counterpart, and no rule
at all governed how close two enemies in the same room could land to
each other - reported as enemies overlapping/crowding the exit and each
other. Two new, ENEMY-SPECIFIC rules (unlike entrance clearance, these
deliberately don't apply to chests/markers - a chest near the exit was
never the actual problem, and filtering it too would shrink its own
placement variety for nothing):

- `RoomState.exit_clearance_fraction` (`@export`, default **0.15**): no
  enemy blob may spawn within this fraction of the room's walkable width
  of the exit door - mirrors `entrance_clearance_fraction`'s exact shape
  (`_max_content_x()` alongside the existing `_min_content_x()`, a new
  mirrored `EXIT_MARGIN` constant alongside `WALL_INSET`'s own "duplicated
  on purpose" precedent, since layout generates before `field_room.tscn`
  exists to ask directly). Inviolable - never relaxed, matching entrance
  clearance's own stance.
- Enemy-to-enemy spacing: two blobs in the same room must clear at least
  one full sprite width apart (the wider of the two), using each blob's
  REAL rendered field width, not a percentage of room width (a percentage
  bunches enemies in narrow rooms - exactly where crowding hurts most -
  and scatters them in wide ones). Real width wasn't knowable before a
  `FieldBlob` existed to measure it, so `field_blob.gd` gained two static
  helpers, `field_width()`/`encounter_field_width()`, that reuse the exact
  same `VisualBounds`/`FIELD_VISUAL_SCALE`/`ENCOUNTER_VISUAL_SCALE`/
  `ENCOUNTER_VISUAL_GAP` math `_build_member_visual()`/`_setup_multi_
  visual()` already use at runtime, just callable on an off-tree temp
  instance at layout-generation time - one shared source of truth for
  "how wide is this creature on the field," not a second approximation.

**Blob placement moved off the fixed 5-slot grid, enemies only:**
filtering `SPAWN_SLOT_FRACTIONS` by both entrance AND exit clearance
together left only 2 of the 5 candidates (0.5, 0.7) - exactly the max
blob count, which would have made every 2-enemy room deterministically
use the same two spots, no placement variety left. Instead, `RoomState.
_place_blob_positions()` picks a random CONTINUOUS X (or two, correctly
spaced) inside `[_min_content_x(), _max_content_x()]` - more variety for
a single blob than the old grid gave, not less. If two blobs' required
gap doesn't fit that zone (a narrow room, or two wide sprites), spacing
is the one thing allowed to relax - never entrance/exit clearance - and
the pair falls back to the zone's two extreme ends, with a `push_warning`
identifying which room/widths were too tight to fit cleanly. Chest/marker
placement is completely untouched - still the same shared discrete-slot
system entrance clearance already generalized. `_generate_combat_layout()`
now rolls WHICH enemy/encounter each blob gets first (unchanged odds/
logic), then measures widths and places positions together, since two
blobs' positions depend on both widths at once. `_generate_elite_layout()`/
`_generate_boss_layout()` (always exactly one blob) get the same
single-position call instead of their old discrete-slot pick, so their
one enemy also respects exit clearance now. The opening room's hand-placed
`OPENING_ROOM_ENEMY_X` already cleared 15% exit clearance numerically at
its current tuning (1600, zone caps at 2252) - no re-tune needed, just
extended the existing boot-time assert to also check it (mirroring how
that same assert already caught a real entrance-clearance violation once).

**Verified headlessly:** 500 generated combat rooms (261 of them
two-blob) plus 50 elite and 50 boss rooms, zero enemy positions outside
`[_min_content_x(), _max_content_x()]`; a forced pathological case (two
5000px-wide "enemies," far wider than any real sprite, in the default
1296px-wide valid zone) correctly relaxed to the zone's two extreme
ends, logged the expected warning, and still cleared entrance/exit
clearance even in that fallback.

**Fix (2026-08-23): a circular preload broke every plain (non-encounter)
blob touched on the field.** The first version of the above reached
`field_blob.gd`'s new static width helpers via `const FieldBlobScript :=
preload("res://field_blob.gd")` at the top of `room_state.gd`. That's a
compile-time dependency - `room_state.gd` can't finish compiling until
`field_blob.gd` does. But `field_blob.gd`'s own `_on_body_entered()`
references the `RoomState` autoload by its global name, which needs
`room_state.gd`'s class resolved to type-check `RoomState.pending_
encounter_enemies` (`Array[EnemyData]`) - a cycle. Godot breaks a cycle
like this by falling back to a generic, untyped `Node` for whichever
side loses the race (here: `RoomState` as seen FROM `field_blob.gd`),
which routes every property assignment through the slow reflection-based
`Object.set()` path instead of a compiled field write - and THAT path
rejects a bare `[]` array literal against a typed `Array[EnemyData]`
property. Surfaced as `Invalid assignment of property or key
'pending_encounter_enemies' with value of type 'Array' on a base object
of type 'Node (room_state.gd)'` the instant any plain enemy blob (not an
authored encounter) was touched on the field - `field_blob.gd:394`,
`RoomState.pending_encounter_enemies = []`, code this pass never even
touched. Fixed by replacing the top-level `preload()` with a `_field_
blob_script() -> GDScript` helper that calls plain `load()` instead -
a runtime call with no static-analysis-time dependency, so it can't
create the cycle - same script, same static methods, just fetched
lazily. Verified headlessly both in isolation (the exact `RoomState.
pending_encounter_enemies = []` assignment, called from `field_blob.gd`
via a real `_on_body_entered()`) and via the full pipeline (a freshly
generated room's real blobs, each touched in turn) - no error either way
after the fix.

**Fix (2026-08-27): blobs and chests could land on top of each other,
silently swallowing the encounter.** The split described above - blobs
placed via continuous random + an ad-hoc pairwise check,
chests/markers/boss/elite via the fixed `SPAWN_SLOT_FRACTIONS` grid -
meant a COMBAT room's optional chest (`_generate_combat_layout()`'s own
`CHEST_CHANCE` roll) and its blob(s) were positioned by two systems that
never knew about each other. Two of the grid's three entrance-clearance-
surviving slots (1400, 1944) sit well inside the blobs' own [956, 2252]
continuous zone, so a chest landing there could sit on or near a blob.
Blobs don't use click hit-testing at all (`field_room.gd`'s own doc:
they get no `input_event`, a click just walks the player there) - the
real interaction fires from `body_entered` once the player's body
overlaps the target's own Area2D, and Godot fires that independently per
overlapping area with no priority/z-order this codebase controls. If a
chest and a blob's hitboxes overlapped, which one's handler actually won
was genuinely incidental, not deterministic - confirmed by inspection,
not fixed: preventing the overlap in the first place is the real fix,
not adding hit-test priority on top of an interaction model that was
never supposed to need it.

Replaced both systems with one: `RoomState._place_content_positions
(count)` - rejection sampling within the same `[_min_content_x(),
_max_content_x()]` zone for EVERY room-content type (blobs, chests,
markers, boss, elite alike), checked against every already-placed item
in that same room regardless of type. One flat `@export var
min_separation_px` (400.0) for every item, deliberately not per-type
width math the way the old enemy-to-enemy check computed a required gap
from each sprite's own real rendered width - `field_width()`/
`encounter_field_width()` (see above) are unused as of this pass, kept
for a real per-type sizing pass later if 400px flat ever proves wrong
for a specific content type. `@export var max_placement_attempts` (30)
caps the retry loop; if every attempt fails, the room falls back to
whichever candidate had the largest minimum distance found, logging a
warning - sized so this should be rare (see below), not routine.
`SPAWN_SLOT_FRACTIONS`/`_available_spawn_slots()`/`_spawn_slot_x()` are
gone entirely - nothing calls them any more.

Sized against the room's ACTUAL current geometry (2800 `standard_room_
width`, interior 2720, valid zone 1296px wide) rather than the stale
"4400/interior 4320/864px apart" figures the old `SPAWN_SLOT_FRACTIONS`
comment carried (fixed alongside this pass - see that constant's own
former doc, now removed with it). Worst case today - 2 blobs + a chest,
3 items in the 1296px zone - needs 2 * 400 = 800px reserved for the two
required gaps, leaving 496px (~38%) of genuine slack; rejection sampling
should essentially always succeed well inside 30 attempts for that case.

**Known latent bug, deliberately NOT fixed by this pass:**
`_place_blob_positions()` (the function this pass removed) only ever had
branches for 0-1 and exactly-2 items - a 3-blob combat room would have
indexed out of bounds on its returned array. `_place_content_positions()`
now handles any count correctly, so this specific crash risk is gone as
a side effect, but it's worth recording that it was NEVER reachable in
practice regardless: `RoomState.max_encounters_per_room` defaults to 2,
which excludes count-3 from `_pick_blob_count()`'s own roll entirely
(`three_blob_weight` exists but is dead weight at that cap). Raising
`max_encounters_per_room` to 3 in the future is safe now without needing
a separate placement fix first.

**Known limitation, exposed (not fixed here) by the wreckage heap
(2026-08-28):** `_place_content_positions()` reasons about a single POINT
per item, never an item's own visual/trigger EXTENT - fine for every
content type this was designed against (chests, blobs, markers, all far
smaller than the room's own entrance/exit clearance margins), but the
wreckage heap's ~1320px pile is close to the entire ~1296px-wide zone
this function is even allowed to place a point within. The raw position
it hands back can legally sit close enough to a wall that the pile's own
trigger zone clips straight through it (confirmed headlessly - up to
181px past a wall across 30 raw placements). Fixed with a targeted clamp
in `field_room.gd`'s own `_spawn_heap()` (`heap_min_wall_clearance_px`),
not a general fix to this function - any FUTURE large field object will
need the same per-object clamp treatment, or this function will need to
actually learn about item extents (e.g. an optional half-width parameter
factored into its own zone bounds), whichever a second large object
actually ends up needing.

**Now the key open question:** which mechanics actually make field
freedom meaningful, rather than just a slower way to reach the next
fight? Candidate mechanics (unvetted parking lot, not commitments):

- Branching exits with previews — routing decisions, Hades-style.
- Avoidance costs — dodging a visible fight saves HP but forfeits
  loot/XP.
- Enemy aggro radius — enemies that chase once you enter their space
  (FFXI aggro-reading).
- Visible elite variants — worth hunting or fleeing on sight.
- Discovery nodes — remnants/inscriptions in rooms, tying into the
  subjob and lore pillars.
- Biome flavor per room.

Field mechanics get added one at a time, each playtested against the
decision criterion above (does it create a decision, or just add travel
time) before the next one is considered.

**Escape resolution (INFRASTRUCTURE ONLY, 2026-08-23):** a third way a
combat node can resolve, alongside victory/defeat - the encounter ends
with the enemy neither killed nor the player defeated, no rewards. This
commit builds ONLY the resolution mechanism itself (see `battle.gd`'s
`_on_battle_escaped()`); the actual trigger (a distance mechanic, an
enemy that can be fled from) is still just the "Avoidance costs" bullet
above, unbuilt. Reachable today only via a dev-only `DevEscapeButton`
(same shape as `DevDamageButton`/`DevStatusButton`), purely to verify
the mechanism before anything real can invoke it.

`RunLogger.log_battle_end()` took a `victory: bool` before this - now a
nested `BattleOutcome { VICTORY, DEFEAT, ESCAPE }` enum, matched for the
log word. `battle.gd`'s three resolution functions (`_on_all_enemies_
defeated()`, `_on_player_defeated()`, `_on_battle_escaped()`) share a
new `_close_out_battle(outcome)` for the bookkeeping every path needs
(`battle_over`, the RunLogger call, disabling End Turn/Deck, AND -
new - `_cancel_targeting()`/resetting `chain_empowered`: victory/defeat
never needed that, since whatever card caused either is always already
past its own targeting stage by the time damage resolves, but escape is
reachable from an out-of-band trigger at any point, including mid-
targeting). Escape shares victory's own presentation via a second
factored helper, `_play_post_battle_beat()` (the dim overlay, a held
beat, Continue fading in at the same hand-relative position) minus the
defeated-enemy animation, since nothing died - a silent cut would read
as a crash, not a resolution.

`_on_post_battle_button_pressed()` used to read `defeat_label.visible`
as a stand-in for "did we lose" - fine with two outcomes, not a real
switch. Now matches on the real `_battle_outcome` `_close_out_battle()`
recorded. Escape's own branch there is deliberately real, not a
`return`/early-exit bypassing reward routing: it goes to `field_room.
tscn` and currently awards nothing, but it's structured as the SAME
dispatch point victory's own reward routing goes through, so a future
escape-specific drop is a change inside that branch, not a new path
alongside it.

The blob touched to start an escaped fight still marks itself defeated
and vanishes on return to the field, exactly like a win - a deliberate
choice (escape consumes the node, the player just leaves with nothing),
not the bug it would look like from `RoomState.last_encountered_blob_id`
alone. See `field_blob.gd`'s own updated note: `blob_defeated` now means
RESOLVED, not KILLED.

**Room types:** COMBAT, TREASURE, EVENT, SHOP, BOSS.

**Run graph (DECIDED — replaces the old random per-room roll):** the
whole run's room sequence is generated up front, at run start, as a
layered graph — a run-graph generator, not a room-by-room roll. Each
node is one room; edges run forward only, from one layer to the next.

- **Layers:** 8. Layer 1 (start) and layer 8 (boss) are always a single
  node; layers 2–7 are 2–3 nodes each (random per layer), capped so a
  layer never asks for more nodes than its predecessor can actually
  reach within the forward-edge cap (only ever bites right after the
  single start node - see `_pick_layer_size()`).
- **Edges:** adjacent layers only, no skipping. Every node gets 1 to
  `max_forward_edges` (default 2) forward edges - a hard cap, tunable.
  Generation guarantees every node is reachable from the start and every
  path reaches the boss (see run_state.gd's `_connect_layers()` - a
  target-first pass assigns every next-layer node to a source with spare
  capacity, so it can't get stuck or exceed the cap the way an earlier,
  buggier version once did).
- **Type assignment:** the final node is always BOSS. Exactly one SHOP
  is placed somewhere in layers 3–6. At least one TREASURE and one EVENT
  are guaranteed somewhere in the run. Everything left over rolls
  COMBAT-weighted, roughly 60/15/10/15 combat/treasure/event/shop
  overall (SHOP's count is fixed by the guarantee, not part of that
  roll).
- **Parameters are tunable:** layer count, layer sizes, the forward-edge
  cap, the shop's allowed layer range, and the leftover-roll weights are
  all `@export` fields on the RunState autoload (run_state.tscn) — expect
  to tune these by feel, same as RoomState's existing weights.
- **Field integration:** the room the player is standing in IS the
  current graph node. **Navigation redesign step 1 (DECIDED, see its own
  note below the Run graph section) changed how this shows up in a
  room:** a room used to spawn one door per forward edge (up to two,
  each previewing its destination's type); it now always spawns exactly
  ONE door regardless of edge count, with no destination preview at all,
  temporarily just following the first edge when a node has more than
  one. The graph itself still generates and validates real branching
  exactly as described below - only how a room PRESENTS its node's
  edges changed. Walking through the door still genuinely advances
  RunState to that edge's target node.
- **Dev aid:** the generated graph prints to the console at run start
  (layer by layer, types and connections), then a validation pass
  re-checks every invariant above (edge caps, reachability, exactly one
  shop, a terminal boss) and reports anything that doesn't hold - so a
  future generator bug announces itself here instead of surfacing later
  as a crash. Neither is player-facing, see open question 11.

**Navigation redesign - step 1, single exit per room (DECIDED, this
step only):** answers part of open question 11 (the graph stays hidden,
still only manifesting as doors) while replacing IN-ROOM branching with
a real map screen instead - the two-door fork the field movement
redesign built (see that section below) turned out to be the wrong
place for a routing decision to live: a fork read from the doorway, not
felt as a real choice, and doesn't extend cleanly to more than two
edges. Step 1, done now: every room spawns exactly ONE door
(`field_room.gd`'s `_spawn_exits()`), regardless of how many forward
edges `RunState.current_node` actually has - `RunState.max_forward_
edges` and the whole graph generator are UNCHANGED, still branching for
real (up to 2 edges per node by default). When a node has more than one
edge, the single door temporarily just follows the FIRST one
(`connections[0]`) - a placeholder, not a design decision, so the run
stays fully playable start to boss while step 2 (a real map screen,
NOT built yet) is designed. The door's own type-preview label (and the
elite-specific gold/pop-in styling on it - see the ELITE Rooms section
below) is gone too - previewing a destination at the door stopped
making sense once destination choice was moving to a map instead;
`field_exit.gd` no longer has a `PreviewLabel` node at all. Verified
headlessly: a 2-edge node still spawns exactly one door and genuinely
advances `RunState.current_node` to the first edge on contact; a 0-edge
(boss) node still spawns no door, same as before this step.

**Navigation redesign - step 2, the map screen itself (DECIDED,
functional pass - correctness over visual identity):** `map_screen.gd`/
`.tscn` render `RunState.run_graph` (plus `opening_node`, prepended as
its own row - the same "not really part of `run_graph`" shape
`_print_run_graph()`'s dev console dump already treats it with) as a
real, clickable node layout - not just the console printout.

- **Layout direction: bottom-to-top.** Matches Slay the Spire's own map
  convention directly - the strongest reason to pick it, since DESIGN.md's
  very first line names StS's core loop as this game's primary
  inspiration. Also reads as "climbing toward the boss," fitting Pillar
  4's hard-but-fair framing better than a left-to-right layout, which
  would echo the FIELD ROOM's own side-scroll axis instead of reading as
  a distinct, more abstract kind of space.
- **Full visibility, structured for progressive reveal later:** every
  node renders today (`reveal_layers_ahead` defaults to `-1`, meaning
  "no limit"). `_is_node_revealed()` is the one gate `_build_map()`
  already checks before rendering a node (and, since an edge to a
  hidden node has no drawn endpoint, before drawing that edge too) -
  turning progressive reveal on later is changing that one exported
  number to a real layer count, not a rewrite. Still undecided at that
  point (deliberately not built now, nothing to justify it yet): whether
  a hidden node stays simply ABSENT (today's behavior) or gets a "?"
  fog-of-war placeholder instead - a content decision, not a structural
  one this property doesn't already support.
- **Three visual states, one line color** - current (gold, disabled),
  reachable-from-current (green, clickable), everything else
  (dark/disabled) - explicit `StyleBoxFlat` backgrounds plus a forced
  white font color on every button, NOT `Control.modulate` (modulate
  tints a Button's text along with its background multiplicatively,
  which read fine for the brighter current/reachable colors but made
  the dark unreachable background pair with equally-darkened, illegible
  text - caught via a real screenshot, not just inspecting properties,
  same verification standard the rest of this project already holds
  itself to).
- **Reusable modal pattern (DECIDED - reused, not reinvented):** same
  shape as `deck_viewer.gd` - a high-layer `CanvasLayer`, hidden by
  default, `PROCESS_MODE_ALWAYS` so it keeps working while the tree is
  paused, a full-screen `Backdrop` blocking clicks to anything behind
  it, the whole `SceneTree` paused while open (blocks field movement
  too - `player.gd` polls raw key state every physics frame, which no
  Control's mouse filter alone would stop), Escape closes it from
  anywhere. Reads `RunState` directly rather than being handed data, so
  any scene can add it as a plain child and just call `open_map()` - no
  wiring back to the caller needed.
- **Interaction, scoped to this step only:** clicking a reachable node's
  button calls `RunState.current_node = node` FOR REAL and rebuilds the
  map in place - the new current node's highlight and its own reachable
  set update correctly, verified headlessly across a real click (not
  just inspected pre/post state). What this step deliberately does NOT
  do: close the map or load a new field room on click - that's step 3
  ("map-selection-loads-room," not built yet). This is what makes the
  map genuinely testable in isolation right now: open it, click through
  several nodes in a row, and watch the graph-walking logic work, before
  any real scene-flow wiring exists to test it through.
- **Temporary dev entry point:** a "Map (Dev)" button in the field
  room's own HUD (next to the existing Deck button) is the ONLY way to
  open this today - there's no exit-triggers-map wiring yet (also step
  3). Remove this button once step 3 gives the map a real trigger.
- **Verified headlessly, not just visually:** node button count matches
  the graph's true node count; exactly one CURRENT button and the
  correct REACHABLE count (matching `current_node.connections.size()`
  exactly) both before and after a click; a boss node (0 connections)
  shows zero reachable buttons and doesn't crash; closing unpauses the
  tree and hides the overlay.

**Navigation redesign - step 3, wiring the map into real scene flow
(DECIDED):** replaces step 1's temporary "the door auto-picks the first
edge" placeholder for real - the door no longer decides anything at all.

- **The door just reports, same shape as `field_marker.gd`'s
  `shop_entered`:** `field_exit.gd` lost `target_node` entirely and now
  emits `exit_entered()` - "just announce it, let something else decide
  what it means," the identical pattern the shop marker already uses for
  its own door-adjacent trigger. `field_room.gd`'s `_spawn_exits()`
  connects it straight to `map_screen.open_map_for_travel()`. The lock/
  unlock logic (a combat room's door stays locked until every encounter
  is defeated) is completely untouched - only the "what happens when an
  UNLOCKED door fires" part changed.
- **Two modes, one screen:** `open_map_for_viewing()` (a real, permanent
  "Map" HUD button now, promoted from step 2's "Map (Dev)" placeholder -
  proposed and built this way specifically to answer item 4: informational,
  dismissible via Close or Escape, reachable nodes shown but never
  wired to a click handler) vs. `open_map_for_travel()` (opened only by
  the door - no Close button, Escape does nothing while it's up, a
  reachable node's click genuinely commits: `RunState.advance_to_next_
  room()`, `RunState.current_node = node`, `RoomState.load_room(node.
  room_type)`). Considered whether travel mode should allow backing out
  (item 3's own question) - didn't find a compelling reason to: the
  player has already walked into the exit, and an "undo" would need
  either a second confirmation step (adding friction to reverse a
  friction-adding safety net) or silently un-committing a choice DESIGN.
  md's Combat Telegraphing philosophy already treats as a hard-but-fair
  moment elsewhere in this game. Defaulted to requiring a real choice,
  per the task's own instruction.
- **The pause/transition interaction, the real risk in this step:**
  `RoomState.load_room()` ends in `SceneTransition.go_to()`, which
  `await`s its own fade Tweens - `SceneTransition` is a plain autoload
  `CanvasLayer` with no `PROCESS_MODE_ALWAYS` override, so those Tweens
  would themselves be frozen by this screen's own `get_tree().paused =
  true` if it were still in effect when `go_to()` starts, hanging the
  transition indefinitely instead of ever reaching the new room.
  `_on_node_pressed()` hides the map and unpauses BEFORE calling
  `RoomState.load_room()` specifically to avoid this - verified
  headlessly (a watcher node added directly under `get_tree().root`,
  deliberately OUTSIDE the scene that's about to be replaced, so it
  survives the swap to actually confirm `current_scene` became the new
  `FieldRoom` instance) that the real transition completes rather than
  stalling, and that `RunState`/`RoomState` end up correctly updated
  once it does.
- **Boss node, same as any other (item 5):** nothing about `run_complete_
  screen.gd`'s own trigger needed to change - it already keys off
  `RoomState.current_room_type == BOSS` (set by the same `RoomState.
  load_room()` call every other node selection already goes through),
  never anything about which door or map click led there. Verified
  directly: selecting the boss node on the map produces a room whose
  `current_room_type` is genuinely `BOSS`.
- **Full loop, verified end to end:** viewing mode confirmed
  informational/dismissible with zero clickable nodes; travel mode
  confirmed non-dismissible (Escape does nothing) with an immediate,
  synchronous unpause on click (before the transition itself starts);
  the real scene swap confirmed to complete (not just RunState's
  synchronous fields updating early, which happens well before the
  visual transition finishes and would have falsely read as "done" if
  that's all this checked); `room_number` incrementing and the new
  room's type matching the selected node, both confirmed after the swap
  actually lands.

**Opening room (DECIDED):** every run now opens with a dedicated
single-enemy, guaranteed-card-reward room, prepended ahead of the normal
generated graph — giving new runs a gentle, purposeful start without
altering the existing graph's structure or guarantees. Mechanically it's
a single node (`RunState.opening_node`) kept OUTSIDE the 8-layer array
above rather than generated as part of it — layer 1 and everything after
still generates exactly as it always did (same `shop_min_layer`/
`elite_min_layer` ranges, same node count/connection rules), just
reached one room later than before. Always COMBAT type, always exactly
one enemy — The Tideworn (see Bestiary), designed specifically for this
room: 20 HP, weak 3-damage attacks, an erratic (not fixed-loop) intent
pattern, so the run's first fight is honestly gentle and honestly
strange rather than a real threat. Its card-choice reward is guaranteed
(skips the normal 60% `card_reward_chance` roll, the same way an ELITE
victory's reward already skips it) — the only two things special about
this room; its chest roll, room/battle counters, and everything else
behave exactly like any other combat room.

**Current policy - combat room door lock:** a combat room's exit(s) stay
locked — all of them at once, if there are two — until every encounter
in it is defeated. This is a placeholder stance, not a permanent one -
it exists because avoidance isn't a real decision yet (no aggro, no
branching routes to duck down). Revisit once those mechanics land;
forced combat and meaningful avoidance are in tension, and the mechanics
parking lot above already assumes avoidance will eventually be real.

**Boss:** the BOSS room contains one encounter, same as any other field
blob - `room_state.gd`'s `_generate_boss_layout()` always loads BOSS_01
(`resources/enemies/bosses/boss_01.tres`) directly now (2026-08-29,
BOSS_01 pass), REPLACING the old placeholder (a random regular enemy,
scaled up 2.5x HP/+50% attack damage, relabeled "[Name] Alpha" at fight
time - removed along with `_make_boss_variant()`). See the Bestiary's own
BOSS_01 entry for the Charge mechanic; naming, fiction, and art are still
fully open (see open question 10) - "BOSS_01" is a working name only.
Beating it shows a **Run Complete!** screen (rooms cleared, gold earned)
instead of the usual reward screen, then returns to the title screen -
the run has nowhere further to go once the boss is down.

**Field juice (polish pass, no new mechanics):**

- **Battle transition:** already covered before this pass existed -
  every scene change in the field path (blob → battle, battle → field on
  return, room → room through a door) already went through
  SceneTransition, whose 0.3s fade-out/fade-in was already exactly the
  spec. Nothing needed to change here; this was already consistent.
- **Encounter approach cue:** each field blob has a second, larger Area2D
  (NoticeZone, ~140px radius vs. the 80px hitbox that actually starts the
  fight) that triggers a looping scale-pulse + brighter color tint while
  the player is inside it, stopping the instant they leave. Purely
  visual, no aggro/chasing - see field_blob.gd.
- **Chest flourish:** opening a chest flashes bright then settles into a
  distinct duller "opened" color (not just a dimmed version of the
  closed one), with a small scale punch. Skipped a particle burst - the
  instruction allowed skipping it if it complicated things, and the
  color/scale combo already reads as a flourish without it. Superseded
  in part 2026-08-25 (see the Rewards section's "Chest rewards route
  through the loot window" note) - the chest no longer plays
  `gold_claimed` or shows its own floating "+N Gold" number itself,
  since gold is no longer applied at open time at all; the loot window
  it now opens into carries both, at claim time.
- **Door unlock cue:** a combat room's exit(s) already flashed and
  color-tweened locked → unlocked on clearing (from earlier work); this
  pass adds a sound (`door_unlock`, once per room, not once per door) so
  clearing a room is audible without needing to check the enemy count.
  **No file exists for it yet** - see Audio's placeholder gap list.
- **Player figure:** the placeholder square is now a small hand-drawn
  silhouette - five Polygon2D primitives (head, torso, two legs, one
  arm), built at runtime, not an imported sprite - in a single
  `@export` color (see player_visual.gd), tuned to read against the
  room's cool dark walls/floor without reading as a UI marker. It flips
  to face the last direction moved (holding that facing while idle),
  bobs very slightly while standing still, and bobs/leans a bit more
  while walking - all `@export`-tunable, all purely visual. This is
  deliberately an anonymous silhouette, not a specific character - see
  open question 12. The visual lives entirely on its own child node
  (Visual, a sibling of the CollisionShape2D, not a wrapper around it)
  with its own script that just watches its parent CharacterBody2D's
  velocity - player.gd (movement/input) and the collision shape didn't
  need to change at all, and swapping in real character art later is a
  one-node replacement.

**Enemy silhouettes (DECIDED — same visual language as the player
figure):** enemies get the same "small hand-drawn Polygon2D shapes, not
an imported sprite" treatment as the player, shared between the field
and battle instead of authored twice. EnemyData gets an optional
`visual_scene` (a PackedScene); enemy_visual.gd is the shared behavior
script (color, idle bob) every silhouette scene attaches, the same
"script owns behavior, scene owns shape" split as field_blob.gd/.tscn -
Thicket Stalker (low, wide, four stubby legs, mossy green, slow heavy
bob) and Glasswing (tall, narrow, angular wings, pale ice-blue, quick
light bob) are the two authored so far. The SAME scene is instanced both
as the field encounter blob (field_blob.gd, scaled down,
FIELD_VISUAL_SCALE) and in battle (enemy.gd, scaled up via its exported
`silhouette_scale`) - one asset, not two. An enemy with no
`visual_scene` falls back to a plain colored shape in both places (the
square field blobs already showed, and a new plain octagon in battle,
which had no shape of its own before this) - "unarted enemies still
work."

This required a real structural change, not just art: field blobs used
to be generic (the actual enemy was rolled at random only once the
player already committed to the fight, inside battle.gd), which would
have made "field encounters show the actual enemy silhouette" a lie.
Enemy selection moved to room-generation time instead -
room_state.gd's `_generate_combat_layout()`/`_generate_boss_layout()`
now pick each blob's enemy via the new `EnemyPool.pick_random()` (a
small shared static helper, same shape as WeightedRandom/RunNode - both
room_state.gd and battle.gd's dev-chain fallback need "a random enemy,"
so one place decides what the bestiary is) at the same time they decide
its position. `RoomState.pending_enemy_data` carries that choice from
"the player touched this blob" through to battle.gd's `_spawn_enemy()`,
which fights that exact enemy instead of rolling a fresh one - the field
preview and the fight are now guaranteed to be the same creature.

The existing field proximity pulse and battle flash-on-hit both still
work unchanged: the pulse now animates whichever node is actually
showing (`.scale`/`.modulate`, generalized to work identically whether
that's the fallback square or a real silhouette instance - see
field_blob.gd's `visual_root`), and the battle flash already worked by
tinting the whole Enemy Control's `modulate`, which cascades to every
child regardless of how many are nested underneath - the new silhouette
picked it up for free.

**Silhouette authoring convention (DECIDED) - feet at the origin:**
every enemy_visual_*.tscn draws its shapes so the creature's FEET sit at
this scene's own local origin (y = 0), with the rest of the body
extending UPWARD in negative y - a Polygon2D's points, a Sprite2D's
texture, whatever the shape ends up being, all follow this the same
way. This is what lets enemy.gd's battle layout bottom-anchor each
creature (see its "Vitals cluster layout" note): the silhouette's feet
sit a fixed gap above the HP bar, its head - wherever that actually
ends up for THIS creature - is a fixed gap below the intent icon, and a
short creature (Thicket Stalker) simply doesn't reach as high as a tall
one (the Wardling) rather than both being centered in space reserved
for whichever is tallest.

The convention only has to be followed approximately - the actual
anchor point is computed at runtime from the shape's real rendered
bounds (`VisualBounds.compute()` in visual_bounds.gd), not assumed to
be exactly y = 0, so a shape that's slightly off (or a future Sprite2D/
AnimatedSprite2D with some built-in padding around its texture) still
lands correctly instead of silently drifting off the bar. That runtime
computation is also what makes the whole system art-agnostic: it reads
whatever node type is actually present (Polygon2D today; Sprite2D/
AnimatedSprite2D need no new layout code, only a new branch inside
VisualBounds itself, which is the one place per-node-type bounds logic
lives) - dropping in real art later to replace a placeholder shape
needs no changes to enemy.gd, field_blob.gd, or this convention.

**Biome adaptation of rooms:** the room/node system is biome-agnostic by
design (room_type drives gameplay, not geometry) - only the visual/
geometric authoring layer needs to vary per biome. For a coastal ruin
biome specifically: walls become terrain edges (cliff, treeline, water,
rubble) rather than masonry; doors become passages (gaps in a sea-wall,
paths between dunes, doorways in collapsed structures) - same functional
role, different dressing.

**Open question:** do room shapes stay a consistent rectangular class
across all biomes (cheaper, more game-y) or does each biome get its own
irregular room-shape vocabulary (stronger sense of place, more art cost
per biome)? Leaning toward biome-specific shapes eventually, but this is
a real scope decision to make deliberately, likely alongside the broader
art direction session.

**First biome-adaptation prototype - coastal beach (opening room only,
EXPERIMENTAL, not yet a general pattern):** the opening room (see its
own note above) is the test case, at the STANDARD 2300x1080 room size
(a bigger room was tried and reverted - it read as empty padding, not
worth the tradeoff) - the ocean occupies the left portion, the player
spawns near a shoreline just past it, and open beach extends right
toward the Tideworn and the exit. Answers the open question above in
favor of "geometry CAN vary per room, driven entirely by script, no new
node types" - `field_wall.gd`'s existing `FieldWall` (already a
script-driven slab computed from exports, not hand-drawn per instance)
turned out to need no new rendering concept at all: the ocean is the
SAME wall, just reconfigured at runtime with far more thickness and a
blue tint (new `configure()`/`set_depth_shade()` methods), its existing
depth-shade strip repurposed as a foam band at the shoreline instead of
its usual baseboard shadow. Collision and visual reach exactly the same
depth from the true edge - no gap between where the water LOOKS
impassable and where it actually is (Combat Telegraphing's "what's
shown is what's real" fairness principle, applied to terrain). A
looping ambience (`room1_waves` - see `music_manager.gd`) plays while
the player is in this room, stopping automatically the moment they
leave (through the exit OR into the fight) via the same `stop_music()`
call `scene_transition.gd` already makes at the start of every scene
change - no room-specific stop logic needed.

Implemented as a runtime override, not a second scene:
`field_room.gd`'s `_apply_opening_room_layout()` checks
`RunState.current_node == RunState.opening_node` (same identity check
`room_state.gd`/`reward_screen.gd` already use for this room) and, only
when true, reconfigures the LEFT wall into the ocean, recolors the
floor polygon's left portion sand-tone, moves the player spawn, and
starts the ambience - top/bottom/right walls, the camera limits, and
the exit door position all stay exactly what field_room.tscn already
bakes in, same as every other room. The Tideworn's fight and the chest
both get hand-placed positions on the direct spawn-to-exit line (the
chest between the Tideworn and the exit) rather than the shared,
standard-room-sized `SPAWN_SLOTS` list every other combat room draws
from. The chest's position used to be randomized between three
candidates tucked near a different wall edge each (top, bottom, or
right, deliberately never the left/ocean edge - a chest that reads as
about to be swept out to sea would undercut the room's tone); top and
bottom stopped being reachable positions at all once the field movement
redesign (see this section's own note above) removed vertical movement
entirely, so that variation collapsed to the one fixed spot. This
chest-placement rule is still scoped to this one room only; every other
combat room's chest still comes from the general `CHEST_CHANCE` roll
against `SPAWN_SLOTS`, unchanged.

**Gotcha discovered while verifying this prototype - the HUD's dead
zone:** the first pass made the ocean 320 units deep and spawned the
player at x=420, both entirely inside world x:0-420 - and world x:0-420
is PERMANENTLY covered on screen by the HUD (`field_room.tscn`'s UI/HUD
panel, a fixed screen-space `CanvasLayer` overlay) for any room, because
`Camera2D.limit_left = 0` means the camera can never scroll past the
room's true left edge, so that span always maps to the same screen
pixels the HUD already occupies. The ocean was, in fact, rendering
correctly the entire time (confirmed by sampling actual pixel colors
from a real screenshot, not just checking exported properties) - it was
just narrow enough to sit entirely behind the UI, reading as "nothing
here" rather than "water" even to a careful look. Fixed by widening the
ocean to well past x=420 (currently 510 deep, shore at x=530 - trimmed
down ~15% from an initial 600 once it read as visible, purely a feel
tweak with the same HUD margin re-checked) and moving spawn to x=700 -
not a rendering bug, a framing one. Worth remembering for any FUTURE
room-edge content near the left wall: anything meant to be seen needs
to clear x=420, or verify it with an actual rendered screenshot, not
just its logged/inspected properties.

**Water height, anchored to the floor line (DECIDED):** the ocean used
to span the room's FULL height (LeftWall's vertical center/half_length
both set to the room's true geometric middle, a leftover from before the
field movement redesign gave the room a real floor line - see that
section above) - a wall of water reaching the ceiling, hiding the sky/
mountain parallax layers behind it entirely. Now anchored to `RoomState.
floor_line_y` like everything else: its bottom sits at `ROOM_FLOOR_
BOTTOM_Y` (the same bound the ground band's own polygon uses) and its
top rises only `opening_room_water_height_above_floor` (`@export`,
260px default) above the floor line - a shore meeting the sea, not a
wall. Collision and visual share this exact span (same `FieldWall.
configure()` call sizes both at once), so there's no invisible collision
above where the water visually ends - verified directly (the collision
shape's own computed world-space bounds matched the intended y=640-1040
range exactly) and by walking the player left into it (stops flush
against the visible shoreline/foam, at exactly the water's true edge,
same as the horizontal depth's own existing "what's shown is what's
real" guarantee). No z-order change was needed - Background already
draws before every wall in tree order (see field_room.tscn), so shrinking
the water's height was sufficient on its own to reveal the sky/mountains
above it again; the water still correctly occludes background where
their ranges DO overlap (near the shoreline), confirmed via screenshot.

**Water motion (DECIDED):** a soft, slow-pulsing foam line at the shore,
not a scrolling texture or wave simulation - the foam band (see above)
breathes its own opacity between roughly 0.8x and 1.2x over a ~4 second
cycle AND creeps toward the sand and back (~12px each way), same
slow-sine-in-`_process()` technique `enemy_visual.gd`'s idle bob already
uses elsewhere, just applied to alpha and position together. Position
matters, not just alpha - an opacity-only fade read as a strip
flickering in place, not water in motion; the shift is what actually
sells "advancing toward the coast," brightest exactly when it's
advanced furthest (in phase with the alpha swing, confirmed headless).
Built as an opt-in feature on `FieldWall` itself
(`depth_shade_pulse_enabled`/`_period_sec`/`_alpha_amount`/
`_shift_px`, all default off) rather than anything opening-room-
specific, so any other wall could pick up the same subtle life later
without a second implementation - only `field_room.gd`'s ocean actually
turns it on. Speed/amplitude/shift/the foam's base color are
`@export`s on `field_room.gd` (not baked consts, unlike this room's
other numbers) specifically so they can be tuned by eye in the
Inspector. Verified headless that both the alpha AND the position
genuinely oscillate in phase, stay bounded within their tuned swings
(never fully transparent, never shifting further than tuned), and are a
complete no-op for every other wall/room - `_process()` returns
immediately when the flag is off, so the cost is one sine call on one
node, only in this one room.

**What this establishes for a REAL future biome system, if this prototype
holds up:** room dimensions and per-wall styling are both just numbers a
room can override at load time - nothing about `FieldWall`'s collision/
visual split, or `field_room.gd`'s fixed node structure, assumes a single
universal size or a uniform wall treatment. A future biome would still
need its own dedicated per-room override function (this one isn't
generalized into a reusable "biome profile" resource yet - deliberately
out of scope for a first test), but the mechanism it would build on top
of already works.

**Second prototype - industrial/space variant (EXPERIMENTAL, parallel
comparison only, not a commitment):** a direct aesthetic opposite of the
coastal room above, built to compare side by side before either
direction gets committed to real content. Deliberately kept at the exact
same 2300x1080 footprint and the exact same boundary depth (510) as the
coastal variant, so the comparison is genuinely fair - same room, same
scale, only material and mood differ. The enemy encounter is The
Unrelieved (see the Bestiary below) - same 20 HP/3-damage difficulty
tier as the Tideworn, a fixed rather than erratic intent pattern (see
its own Bestiary entry for what that means mechanically), a mechanical
sentry rather than a natural process, spawned via `room_state.gd`'s
`_generate_opening_combat_layout()`, which now picks whichever enemy
matches `RoomState.opening_room_variant`.

**Material (DECIDED - revised): vast, poured, decaying CONCRETE, not
clean metal** - closer to BLAME!'s brutalist megastructure than sleek
sci-fi. The first pass leaned all-metal; this revision keeps the left
boundary's starfield/void exactly as it was (see below - deliberately
untouched) but reworks everything else: a mottled, muted gray-tan
concrete floor and walls (`opening_room_concrete_floor_color`/
`_wall_color`) carry low-alpha irregular stain blotches and thin jagged
cracks (`opening_room_stain_color`/`_crack_color`) - age and decay, not
manufacture. Metal is now an ACCENT, not the dominant surface: three
support beams cross the floor (`OPENING_ROOM_BEAM_X_POSITIONS`, not a
dense uniform grid the way the old panel-seam layout was - occasional
structural elements in a vast poured space, not "assembled from
plates"), a matching trim strip runs along each wall's base (reusing
`FieldWall`'s depth-shade strip, same "repurpose the existing strip for
a new cue" move the coastal variant already makes with foam), and rust
streaks (`opening_room_rust_color`) bleed from both ends of every beam -
literally where metal meets concrete, at the floor AND the ceiling
joint. All of it flat `Polygon2D` shapes (irregular octagons for stains,
thin zigzag slivers for cracks, tapered streaks for rust) - no shader,
no texture, same "simple flat shapes" language the rest of the game
uses, just applied to a rougher material. Every color is `@export`, not
`const` (`opening_room_concrete_floor_color` through `_rust_color`),
specifically so the material's feel can be tuned by eye in the
Inspector - this is the part of the room this revision is actually
about. The Unrelieved's own sharp, unnaturally symmetric silhouette
reads even more distinctly now against an aged, imperfect backdrop than
it did against a uniformly clean one - confirmed via screenshot, the
contrast the creature's own Bestiary entry calls for is, if anything,
stronger post-revision.

Also gained its own ambience: `room1_alt_drone` (see `music_manager.gd`'s
`MUSIC_FILES`), started the same way the coastal room's `room1_waves`
already is - `MusicManager.play_music()`, stopped automatically by
`scene_transition.gd`'s `stop_music()` the instant the player leaves,
no special-casing needed.

Selected via `RoomState.opening_room_variant` (an enum, default
`COASTAL`) - real run generation never touches this field; it only
changes via two "Dev: Opening Room" buttons on the title screen (see
`title_screen.gd`), each jumping straight to the opening room the same
way the existing "Dev: Battle Chain" shortcut skips straight to a
battle. `field_room.gd`'s `_apply_opening_room_layout()` is a small
dispatcher that reads the variant and calls either
`_apply_coastal_opening_room_layout()` or
`_apply_industrial_opening_room_layout()` - the coastal function is
completely unaffected by any of this. The left-edge void/starfield
treatment (`OPENING_ROOM_VOID_COLOR`/`OPENING_ROOM_STAR_COLOR`, kept as
consts, not exports) is explicitly UNCHANGED by this revision - a small
fixed constellation of flat octagon "dots" (not a shader, not
randomized - the same hand-placed-small-list spirit as `SPAWN_SLOTS`).

Explicitly built to be easy to remove: deleting
`RoomState.opening_room_variant`, the two title-screen buttons, and
`field_room.gd`'s industrial-specific consts/functions removes the
option entirely with no other code touched, if the coastal direction
wins the comparison.

### Optional encounters (PARKED — design notes only, 2026-08-28)

Two distinct kinds of optional content have come up, and they should
**not** share a mechanic — they're answering different questions.

**1. Sacrifice content.** Visible on the map, harder than a normal room,
better rewards. The whole point is knowing what you're giving up before
you commit, so it has to be plainly advertised — a sacrifice you didn't
know you were making isn't a decision, it's a trap. Two candidate
shapes, neither built:

- A node that **replaces** a normal one at a position already on the
  path — cheaper to build than it sounds: no new map topology, no extra
  routing logic, just a different room type rolled (or forced) into an
  existing slot. The cost is opportunity, not distance — you get a
  harder fight and a better reward in the same room you'd have had
  anyway, nothing about the graph itself changes shape.
- A **branch that costs run progress** — extra rooms that don't advance
  you toward the boss, or a path that rejoins the main route later
  having skipped whatever rewards the main route offered along the way.
  This one DOES touch topology (a real detour), which is why it's listed
  second: more structural work than the first shape for a similar
  player-facing effect.

Either shape needs the reward to visibly outweigh the risk at a glance —
the player should be able to look at the map and know "that one's
harder, that one pays better," not discover it by walking in.

**2. Hidden content.** Rewards attention, not commitment. Some players
are never going to find it, and that's the point — it's a discovery
payoff, not a decision the run design has to make legible up front.
Putting it on the map at all would make it not hidden, so it can't live
in the same layer sacrifice content does — it lives in the **field**
instead: something noticeable in a room if you're looking (an unusual
silhouette, an object that doesn't match the room's normal dressing), a
route through a room that isn't announced by anything (no marker, no
door, just a path that happens to lead somewhere), or an interactable
the map never shows because it was never a graph node to begin with.

**Rejected: a terminal side branch that returns you to the map.** A dead-
end branch node that, once resolved, dumps you back onto the map you
just left isn't actually a routing decision — it's a yes/no on a single
fight, wearing routing clothes. The map's own shape does no real work in
that design: whether the branch is drawn as a fork in the graph or just
a plain "Fight this optional room? Y/N" prompt on the current node
changes nothing about what the player is actually deciding. If the
answer is really just "fight or don't," build that directly — don't
spend graph topology dressing up a binary choice as a path choice.

**Both sacrifice shapes are blocked on the HP calibration pass.** A
"harder than normal" fight means nothing until normal fights are
actually tuned — there's no baseline difficulty to sacrifice content
relative to yet. Don't build either shape before that pass lands.

**Newly possible, not the same thing: a chokepoint encounter.** Now that
single-node chokepoints are a real, structural part of the run graph
(see `run_state.gd`'s `layer_size_1_weight` and its chokepoint-adjacency
rule), a rare encounter placed at a chokepoint is something every run
that generates one will actually meet — nobody chose to detour into it,
nobody can avoid it. That's **not** optional content by either shape
above; it's closer to a scripted **event** (a guaranteed beat the run
graph occasionally produces), a different design question entirely. Not
designed here, just recorded as newly structurally available now that
chokepoints exist at all — they didn't when this section was last
substantially written.

## Biomes

Where a biome gets a real identity - concept, mood, non-negotiable
visual rules - before (or instead of) art. Same relationship to Pillar
5 (Aesthetic) that the Bestiary section below has to individual
creatures: identity decided deliberately here, not backed into once
assets already exist. The coastal and industrial opening-room
prototypes (see Run Structure & Navigation's own biome-adaptation
notes above) are the structural groundwork a biome entry builds on -
this section is content decided FOR that mechanism, not a new one.

### The Sunken Works (first biome)

**Concept:** a huge abandoned industrial facility built along a coast,
being slowly reclaimed by nature under harsh, bright sunlight. Concrete
platforms, rusted machinery, pipes, cranes, broken gantries. Dry
grasses, vines, and strange vegetation growing through structures. Deep
blue ocean beyond the ruins; occasional pools of dark still water inside
collapsed interiors. Almost no conventional civilization remains. A
handful of very strange silhouettes moving through it.

**Design intent:** this biome deliberately sits at the OVERLAP of the
two competing aesthetic directions the coastal and industrial opening-
room prototypes put side by side (vibrant/organic vs. cold/industrial -
see those notes above). It is not a permanent commitment to a hybrid
aesthetic - it's the biome that will help decide between them by being
something we can actually stand in and evaluate, rather than debating in
the abstract. Whether it settles the comparison in favor of one
direction, the other, or the blend itself is an open outcome, not a
premise.

**Non-negotiable pillar - HARSH BRIGHT SUNLIGHT:** sun-bleached is what
keeps this from becoming generic post-apocalyptic gray. If the palette
drifts overcast or dim during implementation, the biome loses its
distinctness. Brightness is a design requirement here, not an
atmospheric preference to be traded away for mood during
implementation.

**Storytelling:** the environment should imply that something happened
here without explaining what - Pillar 4(b)'s "a world that doesn't
explain itself," applied to a specific place. An industrial setting
provides implicit narrative for free (what was made here, who worked
here, why did they stop) with no written exposition required, the same
environmental-storytelling approach the Wardling's harness already uses
at the creature level (see Bestiary below).

**Creature fit:** the existing bestiary suits this biome without
adjustment - the Tideworn (debris assembled by tide, now industrial
wreckage - see its own entry below), the Unrelieved (a sentry still
holding its post in an abandoned facility - see its own entry below),
and the Wardling (something kept and tended, now abandoned - more
poignant near a workplace that implies workers and routine - see its
own entry below). The Beachwrack (see its own entry below) was designed
FOR this biome specifically - a sea-born body the facility accumulated
onto - replacing the Thicket Stalker, which predates this biome and
was never actually part of this list.

**Applied to the field (DECIDED) - every room, not just the opening
one:** the background layers and standard-room ground (see Run Structure
& Navigation's own background-layering/composition-tuning notes above
for the mechanism this content fills) now render this biome everywhere,
not only the coastal opening room's own hand-authored dressing.

- **Background layers (`field_room.gd`'s `_populate_far_layer()`/
  `_populate_mid_layer()`):** replaced the placeholder mountain triangles
  with a small silhouette vocabulary - cranes (mast + boom), broken
  gantries (a beam on two UNEVEN legs, reading as broken rather than
  merely old), platform slabs, pipe runs, and vegetation clumps (reusing
  the industrial opening room's own `_irregular_blob_shape()`) - shared
  by both layers and by the standard-room ground decorations below, so
  everything draws from one vocabulary rather than each surface
  authoring its own. FarLayer draws smaller, hazier (lower-alpha)
  versions further from the ground line; MidLayer draws nearer, more
  saturated ones reaching closer to it, with vegetation clumps anchored
  at each structure's base - "nature reclaiming it," not just ruins.
  Each room's `_ready()` randomly picks which vocabulary entries appear
  and where (within the same repeating tile the no-gap guarantee above
  already relies on), which is what gives rooms modest, same-vocabulary
  variation for free - no extra per-room plumbing needed, confirmed by
  screenshotting two standard-room loads back to back and seeing
  different structure combinations in each.
- **Real bug fixed along the way, not just a content swap:** FarLayer
  turned out to be COMPLETELY invisible before this pass - both layers
  drew a full opaque sky-colored rectangle, MidLayer is added as a LATER
  sibling (so it draws on top), and an opaque rect fully occludes
  whatever's behind it. Confirmed by screenshotting with MidLayer hidden:
  a distinctly different silhouette had been sitting back there,
  unrendered, this entire time. Only FarLayer draws the sky fill now;
  MidLayer draws only its own silhouettes with no rect of its own, so
  FarLayer's sky and distant shapes genuinely show through the gaps
  between MidLayer's nearer ones - the two-layer depth effect this
  system was always supposed to have is now actually visible, confirmed
  via screenshot, not just present in the scene tree.
- **Standard-room ground (`field_room.gd`'s new
  `_apply_standard_ground_treatment()`):** every non-opening room's floor
  gets a warm, sun-bleached concrete/dry-earth base color plus a handful
  of cracks and lighter sandy patches (reusing the industrial opening
  room's own `_crack_shape()`/`_irregular_blob_shape()`/
  `_add_floor_decoration()` rather than a second copy of that pattern),
  randomized per room load rather than hand-placed - standard rooms
  already regenerate fresh each visit, unlike the opening room's own
  fixed narrative beats. Deliberately tuned warmer/lighter than a pure
  concrete gray specifically so it reads as continuous with the coastal
  opening room's own sand, not a different material - confirmed via
  screenshot, standard-room floors and the opening room's sand read as
  variations on one palette, not two.
- **HARSH BRIGHT SUNLIGHT held throughout:** every new color (sky,
  structure, vegetation, ground) is deliberately high-brightness,
  moderate-to-low saturation, and warm - confirmed via screenshot that
  the sky reads as a genuine bright daytime blue and every surface stays
  sun-bleached, not sliding toward the overcast gray this biome's own
  non-negotiable pillar (above) explicitly warns against.
- **Retint regressed the pillar, then was corrected (2026-08-24 ->
  2026-08-25):** a later palette-only pass retinted structures to cold
  steel and ground to silt/mud to fix a frontier-western misread (the
  original warm timber/tan palette read as dry desert frontier, not a
  reclaimed coastal facility) - that fix worked on its own. The same
  pass also desaturated and dimmed the sky toward an "overcast" read,
  which directly violated this pillar. Once the structure/ground retint
  alone was confirmed to fix the frontier-western misread, the sky
  desaturation turned out to be unneeded for that fix and was reverted
  (`field_room.gd`'s `sky_gradient_top_color`/`sky_gradient_horizon_
  color`, back to their pre-desaturation values) - bright, saturated
  light again, over cold steel and wet silt rather than warm timber and
  dry sand. The pillar is about the LIGHT, not the material hues sitting
  under it; cold materials in harsh bright sun is the intended register
  going forward, not overcast dimness.
- **The opening room automatically reads as this biome's coastal edge,
  not a separate look:** `_build_background_layers()` already ran before
  `_apply_opening_room_layout()`'s own coastal/industrial dressing (see
  Run Structure & Navigation above), so the opening room picked up this
  same background content with no special-casing needed - confirmed via
  screenshot, the same crane/gantry/platform vocabulary and bright sky
  render behind its own shore and sand. SUPERSEDED for the structure
  silhouettes specifically (2026-08-27, "empty skyline" pass below) -
  "no special-casing needed" stopped being true once one of those
  structures started landing next to the NPC; the sky/haze/particulate
  parts of this same content are unaffected and still apply as written.
- **Every color and layer-content count stays `@export`** (two new
  groups on `field_room.gd`: "Background layers - Sunken Works sky &
  haze"/"...near structures", plus "Ground - standard rooms") - eyeballed
  numbers, same expectation-to-retune stance every other biome-adjacent
  export in this file already has.
- **Scope held deliberately:** wall tint (`_apply_wall_tint()`) was left
  untouched - room-type signal colors (the BOSS/ELITE tints) are a
  different, gameplay-communicating role than atmospheric dressing, not
  something this pass touched.

**Follow-up - three real regressions from the pass above, all fixed
(DECIDED):** playtesting found the first pass over-corrected in ways the
screenshots above didn't happen to catch.

- **Density (DECIDED - reworked):** the background read as visually
  noisy - too many similarly-sized shapes competing for attention, not
  an environment read at a glance. Pillar 5's aesthetic is composition
  and restraint, not quantity. `far_structure_count`/`mid_structure_
  count` both dropped from 2 to 1 (one deliberate element per tile per
  layer), the standalone vegetation clump (independent of any structure)
  was removed entirely - every clump now reads as attached to something,
  not scattered - and the new `structure_scale` export (1.25) makes the
  one structure that DOES appear larger and simpler rather than
  compensating for fewer shapes with smaller ones. The single biggest
  lever, though, was `background_tile_width` (see the tiling fix below) -
  a much wider repeat interval means more negative space between
  repeats, not just fewer shapes packed into a smaller one.
- **Value separation (DECIDED - a real, enforced rule now, not an
  eyeballed choice):** the first pass's sky (luminance ~0.76) landed
  almost exactly as bright as the Glasswing's own pale silhouette
  (~0.83, the palest color in the bestiary) - nearly invisible against
  it, confirmed via screenshot. Root cause: the pass picked a bright sky
  by hue/warmth alone without checking it against what has to read
  clearly in front of it - hue and brightness are independent, and two
  colors can be "different" while sharing nearly the same value. Fixed
  at the VALUE level, not by outlining or otherwise special-casing any
  enemy (the task's own instruction, and the right one - an outline
  would have treated the symptom for one creature, not the actual rule
  for all of them): every background/ground color now has to clear
  `field_room.gd`'s `_validate_background_contrast()`, which checks each
  one's perceptual luminance against two authored floors -
  `background_plane_luminance_floor` (0.70) for broad surfaces like sky
  and ground, `background_detail_luminance_floor` (0.45) for smaller
  elements within them - not against any enemy's color, asserted every
  room load, the same "announce a
  violation loudly" philosophy `RoomState`'s own entrance-clearance
  check already established, so a future color retune that drifts back
  into an enemy's own value range fails loudly instead of silently
  making something hard to see again. Retuned every color that needed
  it (sky, far/mid structures, vegetation, ground base, ground patches)
  to clear this ceiling with real margin - confirmed both by the
  assertion passing and by screenshotting the Glasswing AND the Wardling
  (the next-palest) standing in front of the new background, both
  clearly legible.
- **Tiling gap (DECIDED - root cause found, not just patched):** a real,
  confirmed-via-screenshot gap appeared at the room's right edge - the
  parallax "no-gap guarantee" from the original background-layering pass
  turned out not to hold at every camera position. Root cause:
  `BACKGROUND_TILE_WIDTH` was a fixed 900px, well under the game's
  actual 1920px logical viewport (`window/size/viewport_width` in
  `project.godot` - the window itself displays smaller, but everything
  renders against this wider logical canvas). Covering a viewport wider
  than the tile requires THREE tile-repeats visible at once at some
  scroll phases (the tail of one, all of the next, the head of a third);
  `ParallaxLayer.motion_mirroring` doesn't reliably draw that many,
  which is exactly what left a visible strip of nothing at the specific
  phase the room's right-edge camera clamp happened to land on. Fixed by
  raising `background_tile_width` (now `@export`, not a fixed const)
  past the viewport width, to 2200 - past this point, at most TWO
  tile-repeats are ever needed to cover any viewport, which is the safe
  case `motion_mirroring` handles correctly by construction. `field_
  room.gd`'s `_ready()` now also asserts `background_tile_width >=` the
  actual logical viewport width every room load, so a future retune
  can't silently reintroduce this. Re-verified via screenshot at BOTH
  extreme edges of the widest room in the game (`RoomState.standard_
  room_width`) - full coverage, no gap either side.

**Opening room gets an empty skyline (2026-08-27) - the first real
special-case for this room's own background content.** Investigation
(see this pass's own report) confirmed the crane/gantry/platform/pipe
silhouettes above are drawn into FarLayer/MidLayer's own `motion_
mirroring` tile, not world space - the same mechanism that guarantees
no gap ever opens at a room edge (see the tiling fix above) also means
a structure can't be excluded from just one region of a room by
position; the whole tile either has them or doesn't. One of them was
landing next to the opening room's own NPC (see the NPCs section), a
place this room specifically wants to read as empty.

- New `opening_room_far_structure_count`/`opening_room_mid_structure_
  count` exports (both 0 by default, "Opening room - empty skyline"
  group) - tunable rather than hardcoded zeros specifically so this can
  be dialed back up without a code change if an empty skyline reads as
  unfinished once seen live.
- `_build_background_layers()` mutates the shared `far_structure_count`/
  `mid_structure_count` exports to these opening-room values BEFORE
  `_populate_far_layer()`/`_populate_mid_layer()` read them, gated on
  `RunState.current_node == RunState.opening_node` - the same "mutate a
  shared export once, before anything reads it" pattern `enemy.gd`'s own
  `set_enemy_data()` already uses for `silhouette_scale`, safe here for
  the same reason (a fresh `field_room.tscn` instance per room load,
  never read twice). Follows `_apply_standard_ground_treatment()`'s own
  precedent of checking the opening room specifically, just as a
  mutation instead of an early return - this function still has shared
  setup below (sky gradient, particulates, occluders) the opening room
  keeps unchanged.
- **Horizon haze survives for free, no special-casing needed:**
  `_add_horizon_haze()` is called unconditionally, before `_populate_
  far_layer()`'s own structure loop - that loop already does nothing at
  count 0, so the haze band (atmosphere, not a structure) is untouched.
- **Vegetation disappears with its structures, no orphaned clumps, also
  for free:** `_populate_mid_layer()`'s vegetation loop iterates `bases`,
  which is only ever populated inside the (now zero-iteration) structure
  loop - an empty `bases` array means the vegetation loop is a no-op too,
  by construction, not a separate check that needed adding.
- **What's left in the opening room's mid/far layers at zero:** far
  layer keeps only the horizon haze band (confirmed headlessly: exactly
  one child, the haze `Polygon2D`) and the sky gradient (a separate
  `SkyLayer` CanvasLayer, untouched by this pass); mid layer is
  completely empty (confirmed headlessly: zero children) - MidLayer has
  no base fill of its own (see its own "no base rect" note above), so an
  empty MidLayer means the sky/haze behind it simply shows through
  uninterrupted, not a visible gap or blank panel. Particulates
  (drifting motes) and the standard ground treatment (sand, per the
  coastal variant) are both untouched by this pass and still render as
  before - the change is scoped to the four structure shapes and their
  attached vegetation only.

Verified headlessly (9 checks): the opening room's own `far_structure_
count`/`mid_structure_count` land on the new exports' values (0/0) after
`_ready()`, its far layer ends up with exactly one child (the haze) and
its mid layer with zero; a non-opening room in the same run is
unaffected - its counts stay at their normal defaults (1/1) and both
layers still populate a structure (plus vegetation in MidLayer's case).

**Ground debris constrained to stay below the field line (2026-08-27).**
Investigation first: `RoomState.floor_line_y` (`@export`, default 900)
was already the single source of truth for the horizon/ground seam,
read consistently everywhere (horizon haze, tide bands, ground
treatment) - nothing new needed exporting there. Every ground decoration
this file draws (`_irregular_blob_shape()`'s blobs, the coastal/seam
debris plate rects, `_crack_shape()`'s cracks) is a `Polygon2D` CENTERED
on its own local origin (0,0) and only ever offset/rotated as a whole
via `position`/`rotation` - never scaled or skewed - so `position` IS
the anchor, and how far a piece's own edges reach above that anchor is
fully determined by its shape and rotation.

- **Root cause: two different placement patterns, both broken the same
  way.** `_add_seam_debris()`/`_add_coastal_seam_debris()` placed each
  piece's CENTER Y jittered ACROSS the line on purpose (`floor_line_y +
  randf_range(-radius * 0.5, radius * 0.5)`) - the deliberate original
  intent of the "break up the hard sky/ground seam" pass this whole
  debris family was built for, now superseded by this fix's own brief.
  `_apply_standard_ground_treatment()`'s ground_patch/ground_crack loops
  already centered BELOW the line (`floor_line_y + 20` minimum) but
  still didn't account for the shape's own extent past its center - a
  70px-radius blob's own jitter table reaches up to `radius * 1.1` above
  center (46-77px depending on radius), comfortably enough to punch back
  above the line from a center that was nominally "safe."
- **New `_shape_max_upward_reach(shape, rotation_radians)`** - rotates
  every vertex with the engine's own `Vector2.rotated()` (the identical
  transform `Polygon2D.rotation` applies at render time) and returns the
  most negative resulting Y, negated. Exact per shape and per rotation,
  not a hand-derived constant - and deliberately NOT reusing `_add_
  coastal_seam_debris()`'s own existing `radius * 1.3` margin, which is
  specific to blobs AND to the HORIZONTAL direction (its own doc: index
  4, angle 180°); the true vertical reach for the same blob shape is
  smaller (`radius * 1.1`, index 6, angle 270°) and a crack/plate's own
  reach is shape- and rotation-dependent in a way no single constant
  could cover for whatever shape a future pass adds.
- **Constrained at spawn time, not clamped after** (per this fix's own
  brief): every one of the four spawn sites now builds its shape (and
  rotation, where one applies) BEFORE rolling a Y position, so the valid
  band (`[floor_line_y + reach, ROOM_FLOOR_BOTTOM_Y - GROUND_DEBRIS_
  BOTTOM_MARGIN_PX]` - the bottom margin now a shared named constant, 20,
  matching what ground_patch/crack already used before this pass) is
  known BEFORE `randf_range()` samples the actual center - keeps the
  distribution even across that band rather than piling up at either
  edge, confirmed headlessly (top-edge depths spread from ~1px to ~98px
  below the line across 105 sampled pieces, not clustered near either
  bound).
- **"Report rather than shrink" is real but not currently reachable** -
  a `push_warning()` fires and the piece is skipped (not spawned at all)
  if a shape's own reach leaves no valid band (`min_y > max_y`). At
  today's radius/length ranges this never fires (confirmed headlessly,
  0 warnings across 13 room rolls) - the tightest case (a 70px ground-
  patch blob) still leaves a ~43px valid window - but the guard exists
  for whenever these ranges get retuned larger.
- **Scope held deliberately**: `_add_seam_vegetation()`/`_add_coastal_
  seam_vegetation()` (the same debris family's own vegetation-clump
  siblings, sharing the identical straddle-the-line placement math)
  were left untouched - plant growth crossing the line reads as
  reaching UP out of the ground, not as broken geometry the way inert
  debris/rubble sitting half in mid-air does, and "debris/clutter" in
  this fix's own brief didn't name vegetation. Flagged as a judgment
  call, not silently decided.

Verified headlessly (5 checks, not via screenshot - this project's own
standing instruction is that Claude never attempts screenshot-based
self-verification, headless or not, so numeric bounding-box assertions
across many room rolls stood in for the requested screenshots; the
report back to the user says so explicitly rather than silently
substituting): across 8 standard-room rolls (80 debris pieces) and 5
coastal-room rolls (25 debris pieces), the true rotated bounding box of
every single piece stays entirely at or below `floor_line_y` - zero
violations - and the pieces' own top edges span a 97px range of depths
below the line rather than clustering at either boundary.

**Parallax stack extended: sky gradient, horizon haze, particulates,
foreground occluders (IMPLEMENTED, 2026-08-24).** Four additions on top
of the existing FarLayer/MidLayer system above, EXTENDED IN PLACE, not
refactored toward a per-biome resource - `BiomeData` untouched, that
abstraction deliberately deferred until a second biome exists to
constrain its shape (premature with only Sunken Works). Everything
already documented above (`motion_mirroring` at `background_tile_width`,
`_validate_background_contrast()`, per-room re-randomization, MidLayer's
no-fill-of-its-own behavior) is unchanged.
- **Sky gradient replaces FarLayer's flat `sky_color` fill.** Lives in a
  NEW `SkyLayer` `CanvasLayer` (layer -100, so it draws behind the whole
  scene tree) rather than inside the parallax stack - a true non-
  parallaxing full-viewport fill needs to NOT be a `ParallaxLayer` at
  all: `motion_scale=(0,0)` doesn't reliably guarantee gap-free
  horizontal coverage as the camera pans the way this layer's own
  tiling does at a nonzero scale, and a `CanvasLayer` sidesteps that
  question entirely. The "drift against the horizon" risk this
  placement was chosen to avoid turned out to be moot in THIS game
  specifically - `Camera2D.limit_top`/`limit_bottom` are pinned to the
  room's fixed 1080px height, exactly matching the 1920x1080 logical
  viewport, so there's zero vertical camera scroll by construction (see
  `_room_height()`'s own note) - but the CanvasLayer is still the more
  robust choice for the horizontal axis regardless. Built from just two
  `@export`ed colors (`sky_gradient_top_color`/`sky_gradient_horizon_
  color`, deeper/lighter respectively) into a two-stop `Gradient` wrapped
  in a `GradientTexture2D`, assigned to a plain `TextureRect` - no
  separate Gradient resource exposed on its own, same "plain exported
  Color, not a sub-resource" shape every other tunable here uses.
- **Horizon haze band** kills the hard sky/ground seam - a `Polygon2D`
  inside FarLayer (so it tiles/scrolls for free via that layer's own
  existing mirroring) using `vertex_colors` (not a flat `.color`) for a
  real top-to-bottom alpha fade: transparent at its own top edge, full
  `horizon_haze_alpha` right at `RoomState.floor_line_y`. Its bottom
  edge sits exactly on the seam since anything below that line is
  covered by Floor's own opaque fill regardless (Floor draws AFTER
  Background in the scene tree). This intentionally BRIGHTENS the
  horizon, which the existing contrast validator would have rejected or
  had to exempt - instead `_validate_background_contrast()` gained a
  second pass that alpha-composites the haze (at its real color/alpha)
  over every already-checked background color and validates THAT
  blended luminance, not the haze's raw color. Since luminance is linear
  in RGB, blending two already-compliant colors can never itself exceed
  the ceiling - this passes by construction with today's sky-derived
  haze color, but it's a real check, not an exemption: a future haze
  color that ISN'T derived from the sky (or an alpha pushed toward
  opaque) still gets caught.
- **Foreground occluder layer (rebar, hanging cable, framing) - DISABLED
  by default** behind `foreground_occluders_enabled`, per this pass's
  own brief (evaluate combat readability separately before shipping it
  active). Lives in `Foreground`, a SECOND `ParallaxBackground` (with its
  own `OccluderLayer`) positioned AFTER `Player` in field_room.tscn, NOT
  a third child of the existing `Background` node - a `ParallaxLayer`'s
  draw order is fixed by wherever its OWN `ParallaxBackground` sits in
  the tree, so there's no way to get "some children draw behind Player,
  one draws in front" out of a single `ParallaxBackground`.
  `occluder_layer_motion_scale` defaults 1.4 (>1.0, scrolling FASTER
  than the 1:1 play plane - every other layer here uses <1.0 for the
  opposite reason). Its shapes hang from the TOP of the frame downward
  (`_add_hanging_rebar`/`_add_hanging_cable`/`_add_hanging_frame`) - the
  opposite anchor convention from every background structure (which
  plant their feet at `base` and grow upward), deliberately: these read
  as things between the camera and the play plane, which conventionally
  intrude from off-frame at the top, not stand on the player's own
  ground line. Left completely unpopulated (no children at all) when
  disabled, not just hidden, so there's nothing to evaluate until it's
  actually turned on.
- **Particulates:** two depth bands (`particulate_far_layer`/
  `particulate_near_layer`, new `ParallaxLayer`s in the existing
  Background node, so they stay behind the play plane) of sparse
  drifting motes - far slower/fainter, near faster/slightly more
  visible, the same depth language the structure layers already use,
  with drift speed/alpha standing in for the size/height cues structures
  use. Each mote is a tiny `_irregular_blob_shape()` blob with `field_
  particulate.gd` attached via `set_script()` on a plain `Polygon2D.new()`
  (not an instanced scene) - that script's own `_process()` gives it a
  constant horizontal drift, wrapping at `background_tile_width` so the
  wrap lines up with the layer's own mirroring period instead of visibly
  teleporting. Drift is INDEPENDENT of the layer's own `motion_scale`
  (the camera-pan-driven parallax, handled entirely by the engine) - a
  mote gets both cues at once. Minimal by default (2-3 motes per band,
  alpha ~0.15-0.22) - meant to be barely-there ambient texture, not a
  snow effect.
- **Verified headlessly:** the sky gradient resolves to a real linear
  `GradientTexture2D`; FarLayer contains the 4-vertex-color haze
  polygon; both particulate layers populate at their (minimal) default
  counts; occluders stay fully unpopulated and invisible until the
  export flips, then populate with the correct faster-than-1.0 motion
  scale; and `_validate_background_contrast()` - including its new
  haze-blend pass - runs clean with every default value in place (the
  first-pass default `sky_gradient_horizon_color` actually violated the
  ceiling and was retuned down until this passed for real, not adjusted
  around).

**Room framing removal (DECIDED):** none of the four walls render a
visible slab by default - a plain colored band at ANY of the room's
edges read as an artificial UI frame around the playfield in the side-
scrolling layout, not architecture, and (since it's ordinary scene
geometry drawn AFTER the parallax background, at a different scroll
rate) occasionally visibly clipped a background structure that happened
to scroll behind it. Room edges are now defined by biome content alone -
the sky and ground already extend edge to edge (see the background-
layering/tiling-gap fixes above), so removing the walls' own rendered
bodies doesn't leave a void, it just stops drawing a border nothing else
needed.

- **Started as LeftWall/RightWall only, extended to all four:** the
  first pass only touched the horizontal edges (the ones the player
  actually walks toward and bumps into) and left TopWall/BottomWall
  alone, reasoning they were "mostly off-camera in normal play." That
  reasoning didn't hold: the camera shows the room's FULL height at all
  times (room height == viewport height leaves no vertical scroll room
  at all - see the composition & scale pass's own note), so the top/
  bottom bands were actually on screen every room, all the time, not
  just at an extreme - the exact same "artificial UI frame" problem,
  just missed because it wasn't associated with walking toward an edge.
- **Visual-only, collision untouched:** `FieldWall.set_visual_enabled()`
  hides/shows only `wall_body`/`depth_shade` (plain `Polygon2D` children
  with no collision role) - `CollisionShape2D` is never touched, so the
  player is blocked in exactly the same place as before. `field_room.
  gd`'s `_apply_room_framing()` calls this `false` on all four walls,
  right after `_apply_wall_tint()`.
- **A room WITH real edge content keeps it:** the opening room's ocean
  (coastal variant) and void/starfield (industrial variant) both call
  `left_wall.set_visual_enabled(true)` right after configuring
  themselves - a real feature is exactly what a rendered border was
  standing in for, so those aren't removed, just no longer a plain gray
  default. RightWall/TopWall/BottomWall never get re-enabled anywhere,
  in any room - nothing repurposes any of them into content.
- **Floor AND sky extended to the room's TRUE outer edges, not just the
  walls' inner collision face, on all four sides now:** `_position_
  floor()` used to stop 40px short of each true edge (`ROOM_FLOOR_LEFT_
  X`/`_room_floor_right_x()`/`ROOM_FLOOR_BOTTOM_Y`, matching where the
  now-invisible walls' own bodies used to visually cover that gap), and
  `_populate_far_layer()`'s sky rectangle stopped 40px short of the true
  top (`BACKGROUND_TOP_Y`, TopWall's own inner edge) the same way. With
  the walls no longer drawing anything there, those 40px strips read as
  clipped/unrendered content right at each boundary - fixed by building
  the floor polygon from `(0, 0)` to `(_room_width(), _room_height())`
  (new helper, mirroring `_room_width()`) and the sky rectangle's top
  edge to `0` instead of `BACKGROUND_TOP_Y`. The player's actual
  reachable extent is unchanged (still bounded by collision at the
  walls' true footprint); the ground/sky now simply continue visually a
  little past where the player can stand or where structures reach,
  which reads as "the room continues beyond what's walkable" rather than
  "the world stops exactly at your feet." `ROOM_FLOOR_LEFT_X`/`_room_
  floor_right_x()`/`ROOM_FLOOR_BOTTOM_Y`/`BACKGROUND_TOP_Y` all keep
  their existing meaning for every OTHER caller (the exit door position,
  ground-decoration placement bounds, the opening room's water/void
  bottom edge, background structure size proportions) - those still want
  to stay comfortably inside the walkable area or use the same
  proportion basis as before, not jump to the raw true edge.
- **Verified, not just reasoned through:** collision was checked with
  REAL `move_and_slide()` calls (not teleporting, which bypasses
  collision resolution entirely) - the player still stops at the walls'
  true footprint (~65px in from the true left edge, ~25px short of the
  right wall's inner face, both exactly matching the player's own 25px
  collision half-width) in a standard room, and the opening room's ocean
  collision independently verified the same way, starting from a
  position clearly outside its own collision box rather than already
  overlapping it. `TopWall`/`BottomWall`'s own `CollisionShape2D`
  (`disabled`, position, shape size) confirmed unchanged after the
  follow-up pass too - the player can never actually reach either
  anyway (no vertical movement at all - see the field movement
  redesign), so this was a direct property check rather than a
  move-and-slide walk. Screenshots at both extreme edges of a standard
  room, the opening room, AND a normal mid-room view (the one the player
  actually sees the vast majority of the time, where a top/bottom band
  would have been most obvious) confirm no gray band on any of the four
  edges, no clipped content, full edge-to-edge coverage.

**Follow-up - the opening room's own ocean/void still had a corner gap
(DECIDED, fixed):** the room-framing pass above extended the PLAIN
floor/sky to the room's true edges, but never touched the ocean's
(coastal)/void's (industrial) own polygon math, which still used the
OLD x=20/`ROOM_FLOOR_BOTTOM_Y` boundary convention from before that
pass - a real, reported gap at the room's true left edge and below the
ocean once LeftWall/BottomWall's own (now-invisible) bodies stopped
covering that last sliver. Fixed by extending the ocean's depth (not
just shifting its position) so its OUTWARD edge reaches the true left
edge (0) while its INNER/shore edge - where it meets the sand, still
carefully tuned to clear the HUD's own dead zone (see `OPENING_ROOM_
OCEAN_DEPTH`'s own comment) - stays exactly where it was; shifting
position alone would have dragged the shore edge inward too, just
swapping one gap for another. The ocean's bottom edge now extends to
the room's true bottom (`_room_height()`) instead of `ROOM_FLOOR_
BOTTOM_Y`, the same fix already applied to the plain floor. The
industrial void got the identical depth-extension fix on its left edge
(it already spanned the room's full true height, so no bottom-edge fix
was needed there). Verified by reading the ocean/void's own rendered
polygon bounds directly (world x=0.00, world y=1080.00 exactly) and by
sampling rendered pixel colors at the room's true corner - the ocean's
exact blue and the void's exact near-black both render there, not the
engine's own unrendered-gap color.

**Beachy water edge (2026-08-27, DECIDED, implemented):** the ocean's
top edge (where it meets the sand/sky) was a ruler-straight horizontal
line - structurally so, since the ocean's shape comes from `FieldWall.
_rect_points()` (shared by all 4 room walls), which only ever builds a
plain 4-point axis-aligned rectangle with no organic-edge capability at
all. Rather than touch that shared script for a one-room cosmetic need,
`_add_coastal_water_edge()` overlays a second, independent wavy band
centered on the water's own top edge, reusing `_add_wavy_band()`'s
existing jittered-per-segment technique (already used a few hundred
lines down for the tide bands) instead of inventing new wave math.
Drawn in the ocean's own color and spanning exactly the ocean's own
width (0 to the shore line, via `_coastal_shore_x()`) - new exports
`coastal_water_edge_height`/`coastal_water_edge_wave_amplitude` (20/22
px) control the band's own thickness and how far each segment's edges
wander from it. Since the band straddles the old flat line, only the
upward half of that wander is visually meaningful (peaks poking past
the old line into what used to be flat sand/sky); the downward half
repaints already-ocean-colored area, which is fine - it's what keeps
the band's average position anchored on the real waterline. Verified
headlessly: the resulting polygon spans the full expected ocean width
(x: 0 to 400) and straddles the old flat line (y: 867.8 to 915.3
against a computed `water_top_y` of 887.0), with a peak breaking the
old horizon by about 19px.

**Battle backdrop (DECIDED) - texture-based, not generated:** unlike the
field room, battle is fixed-size, non-interactive, and static - no
camera to scroll, no edges to walk toward - so a single rendered image
per biome is the natural backdrop, not shapes generated at runtime the
way the field's own parallax layers are.

- **`BiomeData` (new `biome_data.gd`) is the shared seam:** a plain
  `Resource` (same shape as `CardData`/`EnemyData`/`CharacterData`) with
  `biome_name`, `battle_backdrop` (`Texture2D`, optional), and
  `backdrop_fallback_color`. `RunState.current_biome` (mirroring
  `current_class`'s own "const preload, `reset()` picks the default,
  no select UI yet" shape) is the one place a run's biome identity
  lives - the same object a future map header would read `biome_name`
  from, not a second copy of that data. Only one biome exists so far
  (`resources/biomes/sunken_works.tres`), so this isn't a real choice
  yet either, same as `current_class` isn't.
- **Asset folder mirrors the card-art convention:** `assets/biomes/
  sunken_works/` holds the raw image (`SunkenWorks1.png`), the same
  "assets live outside `resources/`, the `.tres` just points at one"
  split `CardData.art_texture` already established for `assets/cards/
  art/`. `sunken_works.tres` points at it via its own imported UID -
  re-verify/update that UID if the image is ever replaced wholesale
  (not just edited in place) rather than swapped for a genuinely new
  file, since a fresh import can mint a new one (see the section below
  on how to drop in a new backdrop).
- **`battle.gd`'s `_apply_battle_backdrop()`, called once from
  `_ready()`:** two-layer fallback, the same "empty means fall back
  gracefully, not broken" shape `CardData.art_texture`/`EnemyData.
  visual_scene` already use - `BackdropColor` (a plain `ColorRect`,
  always present) shows `backdrop_fallback_color`; `BackdropTexture`
  draws on top and only turns visible once a real `battle_backdrop`
  exists. A biome with no art yet still reads as sun-bleached and
  biome-appropriate (Sunken Works' own fallback is its sky color, not a
  generic gray), never as a missing-texture error. `STRETCH_KEEP_ASPECT_
  COVERED` fills the screen edge to edge with no letterboxing, cropping
  whatever overflows - the same fill behavior `card.gd`'s own art
  texture already uses, at scene scale instead of a card's.
- **A real, confirmed-via-screenshot value-separation regression this
  surfaced (fixed, NOT with an outline - the corner-label cluster had no
  legibility mechanism at all to begin with, unlike the flavor-text
  system below):** `RoomLabel`/`BattleLabel`/`TurnLabel`/`GoldLabel`/
  `ClassLabel` share a pale, semi-transparent `font_color` tuned against
  a plain dark scene, with no background panel - fine before any
  backdrop existed, nearly invisible against a bright sky once one did.
  Every OTHER piece of battle UI already sits on its own solid opaque
  panel (HP bars, cards, the End Turn/dev buttons) rather than relying
  on text color alone; this cluster was the one exception. Fixed with a
  single dark, semi-opaque `ColorRect` (`InfoLabelBackground`) behind
  the whole cluster, rather than rewriting five labels' own color -
  consistent with how everything else already solves this. Checked the
  enemy intent flavor line too (explicitly named in the task this pass
  came from) - it already has its OWN dedicated legibility mechanism
  (`flavor_outline_color`, a 3px near-black outline on near-white text,
  from an earlier legibility pass), genuinely different from the corner
  labels' total absence of one, so left untouched at the time. That
  per-element outline was later generalized into the shared
  `OverlayStyle` convention below, alongside every other overlay element
  that had the same problem.
- **Verified against a real battle screenshot, not just inspected
  properties:** the backdrop fills the screen edge to edge at the
  correct aspect; the player silhouette, enemy silhouette (tested
  against both Thicket Stalker and a Wardling), HP bars, intent icons,
  energy pips, and every card all read clearly against it; the info
  label cluster reads clearly after the fix.

**Overlay legibility (DECIDED):** every piece of combat UI that sits
directly over the battle backdrop - the intent icon+number, floating
damage numbers, HP bar numbers, block/status badge numbers, enemy name
introductions, and intent flavor text - uses a dark outline (text) or
icon drop shadow (Polygon2D icon shapes, which have no native outline
property), never a background panel, for legibility. A panel reads as
UI chrome sitting on top of the scene; an outline is direction-agnostic
contrast that stays legible whether it lands on bright open sky, a
shadowed structure, or a busy tangle of ruins, without adding visual
weight of its own - it reads as part of the scene rather than as
interface chrome. One shared style, defined once in `overlay_style.gd`
(a scene autoload, `OverlayStyle`, following the same `@export`-needs-a-
scene pattern as `RunState`/`RoomState` - see its own header comment):
`outline_color`/`outline_width`/`outline_opacity` are the one place this
gets tuned, retuning every consumer at once instead of N independent
copies drifting apart. `apply_to_label()` covers text (Godot's built-in
`font_outline_color`/`outline_size`); `make_icon_shadow()` covers icon
shapes by instantiating a second copy of the same shapes, tinting every
Polygon2D descendant to the shared color, and relying on draw order to
sit it behind the real icon. This is deliberately NOT how block/status
badges' own circular panel works - that panel is established, intentional
framing for a distinct UI object, not bare overlay text/icon sitting
directly on the scene, so it's out of scope for this convention and
stays as-is.

**Flavor text's legibility treatment went through several rounds before
landing (DECIDED - confirmed via screenshot each time):** the intent
flavor line (and DefeatFlavorLabel) renders at a fixed height beneath
the HP bar (see Combat Telegraphing below), which on the current
backdrop is always over the bright, warm-gray concrete ground,
regardless of a creature's horizontal position - a harder spot than
every other overlay element, which sits mostly over sky/structure.
First attempt: invert the shared convention entirely (dark fill, light
outline, via a new `use_light_outline` flag on
`OverlayStyle.apply_to_label()`) - near-white text on the near-white
ground was the original problem, so the fill flipped dark. That read
crisply but still felt thin at 16-22px, so `flavor_bold_strength`
(`FontVariation.variation_embolden`, the same fake-bold technique
`vitals_bar.gd`/`block_badge.gd`/`intent_display.gd` already use for
their own numbers) and a thicker `flavor_outline_width` (6, via a
`width_override` param on `apply_to_label()`) were added on top,
eventually landing `flavor_bold_strength` at 1.8 after comparing 1.0/
1.4/1.8/2.2 side by side - 2.2 started crowding adjacent letters
together at this font size.
  
Final direction (reverted the color/outline choice, kept the weight):
solid white fill again, carried mainly by that same bold weight rather
than a dominant outline - the outline is now a genuinely FAINT
supporting edge, not the primary legibility mechanism. `apply_to_label()`
gained a matching `opacity_override` param (the same shape as
`width_override`, just the other direction - fainter instead of
thicker) so `flavor_outline_width`/`flavor_outline_opacity` could drop to
3/0.3 without touching the shared `OverlayStyle` defaults every other
consumer still uses. Verified via headless screenshot against both the
concrete ground and the pale sky: bold white text with the faint
outline reads clearly at a glance in both, with the outline itself only
apparent on close inspection - "feint, not chrome."

**The intent number is the deliberately dominant number in the cluster
(DECIDED - confirmed via screenshot):** `intent_display.tscn`'s own
`value_bold_strength` default (1.0) was being pulled DOWN to 0.5 by
`enemy.tscn`'s own instance override - the opposite of the "intent reads
as visually dominant between the two [numbers]" intent the script's own
header comment already documented (see `intent_display.gd`'s
`value_font_size` note). Bumped that override to 1.6, added a
`value_outline_width` export to `intent_display.gd` (mirroring
`enemy.gd`'s flavor-text pattern - a per-consumer `width_override`
passed through `OverlayStyle.apply_to_label()`, not a change to the
shared `outline_width`) set to 5, and bumped `icon_scale` from 1.3 to
1.5 alongside it so the icon doesn't end up visually undersized next to
a suddenly much heavier number. Compared bold/outline/icon-scale triples
side by side via headless screenshot (0.5/4/1.30 through 2.0/6/1.65) -
landed on 1.6/5/1.5 as clearly dominant over the HP number and flavor
text in the same cluster while staying crisp (a single digit doesn't
suffer the letter-crowding failure mode multi-word flavor text hit at
high embolden values, so this could push further than flavor text did).

**...and flavor text pulled back to match (DECIDED - confirmed via
screenshot):** once the intent number above was deliberately made
dominant, flavor text needed to read as secondary to it, not just
legible in isolation - `flavor_font_size` dropped from `enemy.tscn`'s
old 18 override back to `intent_display.gd`'s own default of 16, and
`flavor_color`'s alpha dropped from fully opaque to 0.85. The outline
treatment itself (`flavor_outline_width`/`flavor_outline_opacity`,
still 3/0.3) is UNCHANGED - that's still what keeps this readable
against a bright ground or a pale sky regardless of biome; only the
fill's own size/opacity moved, which is what actually controls how
much attention it draws relative to intent. Compared font-size/opacity
pairs side by side via headless screenshot against both the ground and
the sky (18/1.00 current, down through 14/0.70) - landed on 16/0.85 as
a real, visible step down in emphasis that stays clearly legible in
both regions; 14/0.70 started feeling borderline against the ground.

**The Pay House (first enterable structure, IMPLEMENTED 2026-08-23) -
resolves Open Questions' "EVENT room content":** every EVENT room now
spawns a small ruined booth the player can walk into - the run's first
real interior space, and the first content that isn't a fight, a chest,
or a shop. A three-way decision (pay in blood, pay in gold, or leave)
that always ends the same way if paid: a weapon. Body text, exactly as
approved: *"The window still opens when you knock. Wire mesh, a ledger
gone to rust, a slot that takes two kinds of payment. Nothing moves
behind the mesh. Nothing has to."* Deliberately answers nothing about
who or what is on the other side - Pillar 4(b)'s "a world that doesn't
explain itself," the same restraint the Bestiary already holds to,
applied to a piece of architecture instead of a creature.

**The generic enterable-structure pattern (built for reuse, not just for
this one building):** two shared scripts split the pattern into an
exterior half and an interior half, so a SECOND structure needs only new
CONTENT, never new plumbing:
- `field_structure.gd` (`class_name FieldStructure`, extends `Area2D`) -
  the exterior door. Exports `structure_id`/`interior_scene`, both baked
  into the structure's own `.tscn` rather than handed in by whatever
  spawns it. On contact: saves `RoomState.player_position`/`has_saved_
  position` exactly like `field_chest.gd` already does (this is what
  puts the player back at THIS door, not the room's default spawn, once
  they leave the interior - `field_room.tscn`'s own `_ready()` restore
  logic needed zero changes to pick this up), then `SceneTransition.
  go_to(interior_scene.resource_path)`. Stays enterable FOREVER - never
  disconnected, never gated on `RoomState.structure_resolved` - because
  resolution is something the INTERIOR shows, not something that should
  block walking back up to a door that's still standing there.
- `field_interior.gd` (`class_name FieldInterior`, extends `Node2D`) -
  the interior shell. Owns a smaller room (`@export interior_width`,
  1000px vs. `RoomState.standard_room_width`'s 2800, same 1080-tall/
  `floor_line_y`-on-900 convention as a standard room so `Player`/
  `FieldCamera` need zero interior-specific changes), four `FieldWall`s
  resized via the existing `.configure()` API (the same resize-in-place
  mechanism the opening room already uses for its own non-standard
  bounds - no new wall system), a fixed near-the-door player spawn
  (deliberately NOT reading `RoomState.player_position`/`has_saved_
  position` - those hold the EXTERIOR field room's coordinates, set by
  `field_structure.gd` right before this scene loaded, and meaningless
  inside a much smaller interior; left untouched here so they're still
  correct once the player exits back out), a bare `Area2D` "ExitDoor"
  (built fresh, NOT `field_exit.gd` - that script is tied to run-graph
  travel/the map screen, which is wrong here: leaving a structure returns
  to the SAME exterior room, not a new one) that just calls `SceneTransition.
  go_to("res://field_room.tscn")` on contact, a `Content` node for the
  structure's own bespoke interactable(s), and a minimal HUD: `VitalsBar`/
  `GoldDisplay`, plus a Deck button/`DeckViewer` (fix, 2026-08-23 -
  checking your deck/equipped weapon is still relevant while deciding on
  an interior's own interaction, so it stayed accessible; the original
  build had left it out alongside ShopWindow/MapScreen/room labels/Map
  button, which genuinely don't apply here since they're all about
  managing/navigating the RUN). One small public hook, `refresh_hp_bar()`, lets
  a structure's own content script tell this bar to re-pull from
  `RunState` after changing HP directly outside battle - `VitalsBar` is
  push/pull-fed, never self-watching (see its own header), so something
  has to say "now" - a content script reaches it via `get_tree().
  current_scene` (which IS this `FieldInterior` instance while its own
  scene is loaded) rather than a hand-wired reference, keeping the shell
  fully generic with zero knowledge of what's actually in `Content`.
  **`RunState.player_hp` itself has no change signal** (unlike `gold`,
  which announces every change via `gold_changed` - see `RunState.
  add_gold()`/`spend_gold()`) - every caller that mutates it outside
  battle (`pay_window.gd`'s Blood cost, `shop_window.gd`'s Rest heal,
  `field_heap.gd`'s wreckage-heap sifting/effect resolution) is
  responsible for pushing its own HUD refresh by hand afterward
  (`refresh_hp_bar()` above, or a direct `VitalsBar.update_hp()` call
  where a `RunHUD` reference is already in hand), same as `VitalsBar`
  itself never watching `RunState` in the first place. Not an oversight -
  just a gap nothing has closed yet, flagged here (2026-08-28) so a
  future caller doesn't assume one exists by analogy with `gold_changed`
  and silently ship a stale bar.
- **Adding a second structure needs exactly:** (a) a new exterior
  `.tscn` with `field_structure.gd` attached + its own hand-drawn
  Polygon2D silhouette, (b) a new interior `.tscn` using `field_
  interior.gd` as its root + its own bespoke `Content` children and
  their own script(s), (c) one new preload + one new `match` case in
  `field_room.gd`'s `_spawn_structure()`, (d) a unique `structure_id`.
  Nothing else changes - `RoomState.structure_resolved` and both shared
  scripts are already generic over `structure_id`.
- `RoomState.structure_resolved: Dictionary` (structure_id -> bool) -
  same shape/spirit as `blob_defeated`, cleared in `reset_room()`
  alongside it, survives a same-room round trip (structure -> reward_
  screen -> field_room) the same way `blob_defeated`/`chest_opened` do,
  since that round trip never calls `load_room()`/`reset_room()`.
- `room_state.gd`'s `_generate_event_layout()` (replacing the EVENT
  branch's old `_generate_marker_layout()` call in `_generate_layout()`)
  produces a single `{"kind": "structure", "structure_id": "pay_house",
  "position": ...}` entry - not a pool of possible events, every EVENT
  room gets the Pay House, always. Deliberately does NOT also carry an
  `"interior_scene_path"` key even though an early draft of this entry
  shape suggested one - `field_pay_house.tscn`'s own `FieldStructure.
  interior_scene` export already carries that; repeating it in the
  layout dict would just be a second place it could drift out of sync.
  `field_room.gd`'s new `_spawn_structure()` only needs `structure_id` to
  pick the right preloaded exterior scene.
- `field_marker.gd`'s old EVENT branch (`print("An event would happen
  here")`) is gone - unreachable now that EVENT rooms never generate a
  `"marker"` entry. Its SHOP branch is completely untouched.

**The Pay House itself:**
- **Exterior** (`field_pay_house.tscn`) - a small ruined booth, hand-
  drawn flat `Polygon2D` shapes (Body/Roof/Doorway/Sill/RustStreak, feet
  at the ground line like every other field silhouette), NOT a sprite -
  same procedural-geometry convention `field_chest.gd`'s Body/Lid/Latch
  and the Sunken Works' own structure vocabulary already establish.
  Palette is the exact decaying-concrete/rust language the industrial
  opening room's own revision already settled on (see this section's own
  earlier entry) - concrete body `(0.38, 0.37, 0.34)`, metal-accent roof/
  sill `(0.42, 0.44, 0.47)`, a rust streak `(0.55, 0.32, 0.18)` bleeding
  from the roofline - reused directly rather than a third, competing
  material vocabulary for the same biome. The doorway is a plain dark
  opening (near-black) with no separate "interact" prompt - the
  `Area2D` trigger zone sits right there, same "walking up to it is
  the interaction" convention every other field trigger uses.
- **Interior** (`pay_house_interior.tscn`, root uses `field_interior.gd`)
  - the pay window is a `Content` child, `pay_window.gd` (`class_name
  PayWindow` - purely so this instance can be reached with a proper
  static type from outside, mirroring why `FieldWall`/`WeaponData` have
  one; nothing in production code references it, the same way `field_
  chest.gd`/`field_blob.gd` get by without a `class_name` at all). Its
  own simple `Polygon2D` geometry (Frame + a dark Mesh suggesting a
  grate) - interact-on-contact, no separate prompt, matching every other
  trigger.
- **Persistence:** `RoomState.structure_resolved.get("pay_house", false)`
  checked once in `pay_window.gd`'s `_ready()`. Resolved -> Frame/Mesh
  recolor to a dulled `resolved_color` (its own distinct color, not a
  `modulate` dim - the same "opened is a genuinely different color, not
  just darker" treatment `field_chest.gd`'s `opened_color` already uses
  for a chest), a `ClosedLabel` reading *"The window doesn't open
  again."* becomes visible, and `body_entered` is never connected at all
  - the window is genuinely inert, not just visually different.
  Unresolved -> live geometry, `body_entered` connects normally.
- **The choice modal** - built as `PayWindow`'s own children (a
  `CanvasLayer` + dimmed `ColorRect` backdrop + centered `Panel`, reusing
  reward_screen.gd's exact `CardChoiceOverlay` shape: same `StyleBoxFlat`
  values (`bg_color (0.16, 0.16, 0.2, 1)`, `border_color (0.4, 0.42,
  0.48, 1)`, 13px rounded corners), INSTANT show/hide (no fade),
  `get_tree().paused = true/false`, `ModalLayer.process_mode = PROCESS_
  MODE_ALWAYS` so its own buttons keep working while the tree is paused
  - because this is a real three-way DECISION, not a special reveal
  moment, the same distinction reward_screen.gd's own header draws
  between its card-choice modal and its rare-drop reveal's fade/
  crossfade treatment. Three buttons: Pay in Blood, Pay in Gold, Leave.
- **Costs, exact, as approved (the blood cost was explicitly simplified
  from an earlier percentage-based proposal to a flat number during
  approval):**
  - Gold: flat 50 (`PayWindow.GOLD_COST` - initially 180, lowered to 100
    then 50, both 2026-08-23). The Pay in Gold button is
    `.disabled` whenever `RunState.gold < GOLD_COST`, re-checked every
    time the modal opens (not just once) - same affordability-disable
    shape `shop_row.gd`'s own `set_affordable()` already uses for Buy
    buttons, reusing Godot's default disabled-button styling rather than
    a bespoke dim treatment.
  - Blood: `min(15, RunState.player_hp - 1)` (`_blood_cost()`) - never
    fatal, never below 1 HP remaining. At `player_hp <= 1` this floors to
    0 - an edge case that will essentially never come up given normal HP
    totals, verified headlessly anyway (both the ordinary 5-HP case and
    the exact `player_hp == 1` edge land at exactly 1 HP afterward, never
    0). Applied directly (`RunState.player_hp = max(RunState.player_hp -
    cost, 1)`, mirroring the spirit of `battle.gd`'s `_deal_self_
    damage()` without routing through any CardEffect machinery, since
    this isn't a card) - `FieldInterior.refresh_hp_bar()` immediately
    pushes the change to the interior's own HP bar, no flinch/combat
    feedback needed outside a fight. No affordability gate on this
    option - the cost formula already makes it always payable, by
    construction.
- **Resolution:** `PayWindow._apply_resolution()` commits `RoomState.
  structure_resolved["pay_house"] = true` and `RoomState.pending_weapon_
  grant` IMMEDIATELY (synchronously, before any animation), deliberately
  split out from the outcome-text-then-transition tail that follows it -
  what actually happened doesn't wait on how it's shown, which is also
  what makes the state change independently verifiable in a headless
  test without needing to wait through (or ever trigger) the real scene
  transition. The modal then swaps its body/buttons for a one-line
  outcome (in place, same panel) - *"The dish empties. Something in the
  slot clicks open."* (blood) or *"The coin drops. Something in the slot
  clicks open."* (gold) - for `OUTCOME_DISPLAY_SEC` (1.2s) before handing
  off to the loot window: `RoomState.pending_weapon_grant` set to `The
  Creditor` (blood) or `Last Wages` (gold), then `SceneTransition.
  go_to("res://reward_screen.tscn")` - `pending_chest_gold` is
  deliberately never touched, so the loot window shows a single WEAPON
  row with no gold row alongside it, and the existing hover-preview/
  equip/swap-decision machinery (see the Equipment note below) just
  works with no new UI. Leave: closes the modal, touches nothing - not a
  permanent resolution, the choice is still there next visit.
- **Fix (2026-08-23): `RunState.battle_number` was incorrectly advancing
  on a Pay House payment.** `reward_screen.gd`'s `_continue_to_next_
  battle()` only skipped `RunState.advance_to_next_battle()` for
  `_is_chest_reward` (driven by `pending_chest_gold >= 0`) - a condition
  the Pay House never satisfies, since its reward is weapon-only. Fixed
  with a new one-shot field, `RoomState.pending_non_battle_reward`, set
  by `PayWindow._apply_resolution()` alongside its other three lines,
  read into a local `_skips_battle_advance` in `reward_screen.gd`'s
  `_ready()` (and cleared back to `false` the same one-shot way every
  other `pending_*` field is), then OR'd into the existing `_is_chest_
  reward` check in `_continue_to_next_battle()`. `battle_number` is only
  consulted by the title screen's dev-only "Battle Chain" shortcut and a
  cosmetic in-battle label today, so this had no visible effect in normal
  play, but it contradicted the codebase's own stated intent for
  non-battle field sources (see `_is_chest_reward`'s own comment: "a
  chest never fought a battle... no battle_number advance") and would
  have mattered for any future code that trusts `battle_number`.
  Verified headlessly: Pay House reward leaves `battle_number` unchanged,
  a real battle victory still advances it, a chest reward still doesn't.
- **Fix (2026-08-23): exterior too small, and an enter/exit loop on the
  door.** Two bugs found in play, both fixed together:
  - The exterior silhouette (`field_pay_house.tscn`) had no scale applied
    at all - it rendered at its raw authored geometry (~112px tall),
    dwarfed by the player. Measured the player's real on-screen field
    height via `VisualBounds.compute()` (the same utility the enemy
    field-scale tuning pass above used) at 307.2px, and set the root
    `Area2D`'s `scale` to `5.485714` so the exterior renders at exactly
    2x that (614.4px) - verified headlessly to land on 2.000000x.
  - Walking in trapped the player in an entering/exiting loop. Root
    cause, on both ends of the trip: `FieldStructure`'s door is
    deliberately never-resolving/always-enterable (see its own note
    above `_on_body_entered`), but it was saving `body.global_position` -
    the exact contact point, sitting right on the door's own collision
    box - as the return point. Landing back there on exit immediately
    re-triggered entry. Separately, `pay_house_interior.tscn`'s player
    spawn point (`door_spawn_margin` past the wall) and its `ExitDoor`'s
    own collision box overlapped by 5px, so the interior fired its exit
    trigger on the very first physics frame too - the same bug, on the
    other side of the trip. Fixed generically in `field_structure.gd`
    (new `_safe_return_position()`, added `RETURN_SAFETY_MARGIN := 40.0`)
    by pushing the saved return point clear of the door's own
    `CollisionShape2D` - reading the shape's real size and this node's
    own `scale` rather than a fixed number, so any future structure gets
    a correct, non-overlapping return point for free regardless of its
    own size. Fixed the interior side by moving `pay_house_interior.
    tscn`'s `ExitDoor` from `x=90` to `x=50`, clearing the player's spawn
    point by ~35px instead of overlapping it by 5px - a per-interior
    authored value (see this interior's own hand-placed geometry), not a
    `field_interior.gd` change, since a future interior's own `ExitDoor`
    placement is exactly the kind of bespoke-per-.tscn value this shell
    deliberately leaves alone. Verified headlessly: neither the exterior
    return point nor the interior spawn point overlaps its nearby
    collision box any more.
- **Fix (2026-08-23): the EVENT room's own exit door could land behind
  the (now much bigger, see the scale fix above) Pay House.**
  `_generate_event_layout()` used to draw the structure's spawn X from
  the same random `_available_spawn_slots()` pool every other content
  type uses - fine at the old, tiny geometry, but at 2x player height
  (~550px wide) the 0.9 slot puts the structure's right edge past the
  room's own fixed exit-door position (`field_room.gd`'s `EXIT_X`,
  2660), covering the door entirely (reported as "I need an exit door on
  the right side"). Fixed by pinning the structure to the room's
  horizontal center (slot `0.5`) instead of rolling for it - there's
  only ever one Pay House per EVENT room, so there's no variety benefit
  to randomizing its position the way there is for combat encounters,
  and center placement clears both the entrance and the exit door by a
  wide margin without this function needing to know the structure's own
  real pixel footprint. Verified headlessly: ~986px of clearance between
  the structure's right edge and the exit door (previously overlapping
  at the 0.9 slot). Exit doors were already unlocked immediately in
  EVENT rooms (see `_update_exit_lock()`'s own note: only COMBAT/ELITE
  lock) - resolving the Pay House was never required to leave, so no
  locking logic was needed, only making the existing door reachable.
- **Feature (2026-08-23): a back door out of the Pay House's interior, so
  the player can walk THROUGH the structure instead of being stuck at
  it.** Even centered (see the fix above), the Pay House's exterior
  trigger box is now big enough to sit across a real chunk of the room's
  own walking path, and its door deliberately never stops being
  enterable (see `field_structure.gd`'s own note on why - resolution is
  something the interior shows, not something that gates the door). That
  meant walking around the outside to continue toward the room's exit
  wasn't actually possible: touching the box from any side just re-
  entered the interior again, every time - reported as "I get stuck in
  a loop... there is no exit from within the Pay House... cannot walk
  past it." Added a second, generic mechanism to the reusable structure
  pattern itself (not a Pay-House-only hack):
  - `RoomState.structure_bypass_position` - a point clear of the
    structure's own collision box, ALWAYS on the right (every room's
    exit sits to the right - see `field_room.gd`'s `EXIT_X` - so "past
    the structure" always means further right, unlike the front door's
    return point, which depends on which side the player approached
    from). Computed and saved by `field_structure.gd`'s
    `_on_body_entered()` at the same moment it saves the normal front-
    door return point, using the same real shape-size/scale math (see
    its own `_collision_half_width()`, now shared by both).
  - `field_interior.gd` grew an OPTIONAL `back_exit_door` (`get_node_or_
    null("BackExitDoor")` - null, harmlessly, for any interior that
    doesn't add one). When present, walking into it sets `RoomState.
    player_position` to `structure_bypass_position` before returning to
    `field_room.tscn`, instead of the front door's saved position.
  - `pay_house_interior.tscn` adds one `BackExitDoor` `Area2D` at its
    right side (`x=880`, same 60x200 trigger shape as the existing
    `ExitDoor`, mirrored) - the only per-interior change; nothing about
    `field_structure.gd`'s or `field_interior.gd`'s own generic behavior
    is Pay-House-specific.
  - Documented as "Optional (e)" in `field_structure.gd`'s own "adding a
    second structure" recipe - only structures big enough to actually
    block the room's path need one; a small future structure off to one
    side can skip it entirely and nothing breaks.
  Verified headlessly: the saved bypass position clears the structure's
  own collision box; the interior correctly finds and wires up the new
  door; walking into it hands `RoomState.player_position` off to the
  bypass point exactly as intended. Re-verified the front door's own
  return-position fix still holds after sharing `_collision_half_width()`
  between both doors' math.
- **Fix (2026-08-23): claiming the reward returned the player to the
  front door, not past the structure.** Resolving the Pay House
  transitions straight from the interior to `reward_screen.tscn` (see
  the Resolution note above) and, once Continue is pressed, straight on
  to `field_room.tscn` - neither `ExitDoor` nor `BackExitDoor` ever
  fires along that path, so `RoomState.player_position` was still
  whatever `field_structure.gd` saved when the player first walked IN
  (the front-door position), landing them back at the door they entered
  through rather than continuing on. `PayWindow._apply_resolution()` now
  also overwrites `RoomState.player_position` with `RoomState.structure_
  bypass_position` - the same point the back door itself uses - so
  finishing the event (either payment) continues the player past the
  structure, toward the room's exit, exactly as if they'd walked out the
  back. Leave still doesn't touch `player_position` at all - only
  actually completing the event moves the return point. Verified
  headlessly: claiming a reward lands `player_position` on the bypass
  point, not the front-door position.
- **Structural pass (2026-08-23): wider exterior, correct approach
  z-order, and a real run-advancing exit inside the interior.** Four
  placeholder-shape changes (current art stays procedural geometry,
  meant to be replaced by real assets later - no decorative investment
  here):
  1. **Widened the exterior.** `field_pay_house.tscn`'s `Body`/`Roof`
     widened from a ~90/100-unit-wide shed silhouette to ~280/290 units -
     reads as a larger civic/institutional structure now, not a lookout
     shed. Only the X coordinates changed; Y stays untouched, so the
     roof's existing taper (8-unit inset over a 12-unit rise, unchanged)
     and the 2x-player-height scale (`field_pay_house.tscn`'s own
     `scale`, from the earlier scale-fix entry above) both carry over
     exactly. `RustStreak` (the roofline accent) shifted with the new
     right edge so it still reads as bleeding from the corner, not
     stranded mid-wall. `Sill` was reshaped from a flat lintel bar into
     an actual diagonal leaning-plank quad next to the doorway (the
     doorway itself never moved, so no separate repositioning was needed
     once the plank is anchored to it rather than to the Body's width).
     Real consequence of a much wider building: `field_structure.gd`'s
     `_safe_bypass_position()` (the far-right "get past the building"
     point - see the back-door/reward-claim entries above) previously
     measured clearance off the doorway's own small `CollisionShape2D`
     (~70 units), not the whole silhouette - fine at the old size, but a
     wide building made that land well short of actually clearing it.
     Switched `_safe_bypass_position()` to measure the structure's real
     visual bounds instead (`VisualBounds.compute()` on `Silhouette` -
     the same utility the enemy field-scale pass and `enemy.gd`'s
     battle-side bottom-anchoring already use), not assuming left/right
     symmetry since a decorative accent could in principle sit further
     out on one side. `_safe_return_position()` (the front door's own
     return point) deliberately did NOT get the same change - see the
     follow-up fix below, where an initial pass got this wrong by
     applying the wide-silhouette clearance there too. Verified
     headlessly: the widened silhouette still clears both room walls and
     the room's own exit door by a wide margin (~465px).
  1b. **Fix (2026-08-23, same day): the front door's own return point had
     briefly inherited the same wide-silhouette clearance as the bypass
     point** - an overcorrection from 1 above, applying `_safe_bypass_
     position()`'s "clear the WHOLE building" reasoning to `_safe_return_
     position()` too, which only ever needed to clear the doorway itself
     (a wide facade is mostly just wall - the door is still one specific
     spot on it). Reported as "exits to the left of the entire structure,
     not the entry door." Split the two back apart: `_safe_return_
     position()` reverted to measuring clearance off the doorway's own
     `CollisionShape2D` (`_door_half_width()`, restoring the original
     ~232px-from-center value), while `_safe_bypass_position()` keeps the
     full-silhouette measurement from 1 above - the two points now
     correctly serve their two different purposes (step back outside near
     the door you used, vs. get all the way past a wide building).
     Verified headlessly: the front-door return position lands ~232px
     from center (matching the pre-widening doorway-based value, well
     under the ~795px half-width the full silhouette would give), still
     clear of the door's own collision box, while the bypass position
     still lands ~835px out, clearing the whole silhouette.
  2. **Fixed the player rendering behind the building on approach.**
     Root cause was neither `y_sort_enabled` nor an explicit `z_index`
     conflict - neither is used anywhere in `field_room.tscn`/`field_
     room.gd`. It was pure scene-tree order: Godot draws later siblings
     on top when z-index ties (the default, for everyone), and `Player`
     was declared BEFORE `Content` in `field_room.tscn` - so anything
     spawned into `Content` (any structure, blob, or chest, not just the
     Pay House) always drew in front of the player, unconditionally. Only
     visible before because nothing spawned there was big enough to make
     it obvious. Fixed at the correct layer, not with a one-off z_index:
     reordered `Player` to come after `Content`/`Exits` in the node tree,
     so the player draws in front of all room content by default,
     system-wide.
  3. **Added a real, run-advancing exit inside the interior.** Replaced
     the earlier back-door mechanism (`field_interior.gd`'s `back_exit_
     door`, which only returned the player to the field room, positioned
     past the structure - see the back-door feature entry above) with
     `advance_exit_door`: a real `field_exit.gd` instance (the same
     script/signal/lock API every field room's own exit uses, not a
     bespoke one), wired the exact same way `field_room.gd`'s `_spawn_
     exits()` wires its own door (`exit_entered.connect(map_screen.
     open_map_for_travel)`). `field_interior.gd` now also optionally
     hosts a `MapScreen` instance (confirmed reusable as a plain child of
     any scene per its own header note - it reads `RunState` directly, no
     wiring back to the caller needed), conditional on `advance_exit_door`
     being present, mirroring the same "optional pair, only if this
     interior's own .tscn adds them" shape `back_exit_door` used. Walking
     into it now opens the travel map immediately, right from inside the
     Pay House, and picking a node calls the fully generic `RoomState.
     load_room()` - no special-casing needed, since that function was
     never field-room-specific to begin with. `pay_house_interior.tscn`'s
     `AdvanceExitDoor` gets its own visual: a slim near-black rectangle
     (matching `Doorway`'s own color) reading as a doorway silhouette,
     distinct from a normal field exit's green/red lock-state coloring -
     safe because nothing ever calls `.lock()`/`.unlock()` on this door
     (EVENT rooms/interiors are never locked), so its static color is
     never overwritten. The front `ExitDoor` (left side) is unchanged -
     still a non-committal "step back outside" with no map screen forced.
     Caught and fixed a real bug during verification: an earlier edit to
     `field_interior.gd` had accidentally dropped the `player_hp_bar`
     `@onready` declaration entirely, which failed to PARSE (not just
     fail at runtime) - per this project's own standing headless-testing
     lesson, a script that fails to parse never registers its `class_
     name`, so every `get_node_or_null()`-based optional lookup elsewhere
     silently returns a plain untyped node instead of erroring where the
     actual problem is. Restored the missing declaration; re-verified all
     8 headless checks pass afterward.
  4. **Left the interaction window untouched**, as directed - `pay_
     window.gd`'s body/outcome text and Pay in Blood/Pay in Gold/Leave
     options are unchanged by this pass.
- **Reward-screen routing fix (a real correctness requirement, not
  cosmetic):** `reward_screen.gd`'s `_continue_to_next_battle()` routes
  Continue to `field_room.tscn` if `_is_chest_reward` is true, else to
  `field_room.tscn` if `RoomState.in_field_encounter` is true, else to
  `battle.tscn` (the title screen's dev battle-chain path). A weapon-only
  grant with neither flag set would have fallen through to `battle.
  tscn` - wrong for this path. Fix: `PayWindow._apply_resolution()` also
  sets `RoomState.in_field_encounter = true` right alongside the pending
  weapon grant - the EXACT same flag/branch `field_blob.gd` already sets
  before starting a real fight, reused here for the same meaning ("this
  reward claim originated in the field room, not the title screen's dev
  shortcut") rather than repurposing `_is_chest_reward`'s own narrower
  meaning (this isn't a chest - `pending_chest_gold` is never set).
  Verified headlessly: with `pending_weapon_grant` set and `in_field_
  encounter` true, `reward_screen.tscn` builds exactly one WEAPON loot
  row, claiming it (no weapon equipped) equips directly, and the
  routing condition Continue would branch on selects `field_room.tscn`,
  never `battle.tscn`.

**Verified headlessly** (throwaway `test_pay_house_verify.gd`/`.tscn`,
deleted after passing - 31/31 checks passed): an EVENT room's `room_
layout` contains the Pay House structure entry; walking a real `Player`
instance into the exterior's `Area2D` (calling `_on_body_entered()`
directly, matching how this project's own chest/weapon tests already
work) sets `player_position`/`has_saved_position`, and the interior
scene instantiates cleanly both unresolved (live trigger, no "closed"
label) and with `structure_resolved = {"pay_house": true}` pre-set
(inert trigger, "closed" label visible); Pay in Blood costs exactly 15
HP at full health, floors to land at exactly 1 HP (never 0) at both 5 HP
and 1 HP starting points, and grants The Creditor; Pay in Gold costs
exactly `GOLD_COST` gold (50, see this section's own cost note above),
grants Last Wages, and the button is confirmed disabled below that
amount and enabled at/above it; Leave changes nothing
and leaves the choice re-triggerable; claiming the granted weapon
through a real `reward_screen.tscn` instance equips it directly (no
weapon previously equipped) and Continue's routing condition resolves to
`field_room.tscn`, not `battle.tscn`.

## Combat Telegraphing (DECIDED)

Enemy intents are communicated iconographically, not as a text sentence:
a small original Polygon2D shape (same hand-drawn silhouette language as
every enemy/player visual - see Run Structure & Navigation's enemy
silhouettes note) shows the intent's TYPE - attack (an angular blade,
warm/red) or defend (a shield, cool blue-grey) today, structured so a
later type (buff/debuff/special) is one new shape plus one lookup entry,
not a change to how the display works (see intent_display.gd's
ICON_SCENES). The icon sits beside an explicit, always-accurate number -
the number shown is exactly what lands, full stop. This is Pillar 4(a)'s
hard-but-fair stance made literal: difficulty comes from hard decisions
made with full information, never from hidden or misleading intent.

An optional short flavor line can accompany an intent, in smaller,
dimmer text - tone without competing with the number for attention.
Most enemies have none. The Wardling is the first to use it: its
escalation stages (see Bestiary below) drive the line through
tentative-to-frenzied wording while the icon and the true damage number
never change meaning, only value. It renders beneath the HP bar, not
between the intent icon and the creature - atmospheric information
doesn't belong in the primary scanning path, and (see the UI convention
below) it must never be able to push the icon+number away from a fixed
position just because a particular enemy happens to have one.

**UI convention (DECIDED) - optional elements never reserve layout
space:** applies throughout, not just here. A UI element that's
sometimes absent (a flavor line, a name overlay, a future status icon)
must never claim a fixed slot in another element's layout "just in
case" - if it did, every enemy WITHOUT that content would show a dead
gap, and the elements around it would be positioned relative to a slot
whose size depends on content that isn't even there. The concrete
pattern (see enemy.gd's vitals cluster): pick ONE thing to be the fixed
anchor (here, the intent icon+number's position, itself derived from
the creature's actual head), position everything else - including
optional content - as an overlay or a separately-anchored element
relative to THAT, never by reserving room inside a shared block whose
size would otherwise vary with content.

**Enemy name display (DECIDED):** enemy names are introductions, not
labels - the world doesn't annotate itself (Pillar 4(b)). A name isn't
permanently on screen; it fades in near the silhouette when a fight
starts, holds briefly, fades out, and is otherwise available on demand
by hovering the silhouette (see enemy.gd's `_play_name_intro()`/
`_on_silhouette_mouse_entered()`). Silhouettes carry moment-to-moment
identification; names give elites and bosses weight instead of clutter -
an elite's introduction (also used for any boss fight, regardless of
the base creature - see battle.gd's `_make_boss_variant()` forcing
`EnemyData.is_elite`) holds longer, renders larger and gold-toned, and
pops in rather than just fading, so encountering one registers as an
event. The introduction never blocks or delays the player's first turn -
it's a Tween running alongside, not something anything `await`s.

**Attack lunge and intent refresh (DECIDED):** two small readability
fixes, both in `enemy.gd`, both exported for feel:

- An enemy resolving an ATTACK intent plays a brief, fast jerk toward
  the player (`play_attack_lunge()` - `attack_lunge_distance_px`/`_out_
  sec`/`_return_sec`) at the moment the hit lands, called from
  `battle.gd`'s `_resolve_enemy_intent()` alongside `_enemy_attack_
  player()`. DEFEND never calls it - block gain stays visually calm, on
  purpose, rather than reusing the same cue for a different kind of
  turn.
- Once an enemy's turn resolves, its intent display doesn't just snap to
  the next value - it fades out completely (icon+number+flavor
  together, via `IntentDisplay`'s own `modulate`), holds empty for
  `intent_refresh_gap_sec` (~0.3-0.5s), then fades the new intent in
  (`refresh_intent()`, called from `battle.gd`'s `_advance_enemy_
  intent()` instead of the plain instant `show_intent()` the very first
  display at spawn still uses). This runs every time an intent
  advances, even when the new value is identical to the one just used -
  the fade cycle itself is what tells the player "this is a new turn's
  intent," not a comparison against the previous number (verified
  against Glasswing's own `[4, 4, 9]` pattern, where turns 1 and 2 both
  show "4" - the elapsed time confirms the full cycle still plays both
  times).
- Sequencing matters: the lunge fires as part of RESOLVING the attack,
  before `ENEMY_RESOLVE_PAUSE` and the intent refresh that follows it -
  the player sees the hit land, THEN the readout clears, cause before
  reset, never the two blurred together.

## Status Effects (DECIDED: mechanism only — no named content yet)

Generic scaffolding for buffs/debuffs, built so a future design session
can define real, tempo-serving statuses (see Open Questions #5's
standing directive: statuses must be designed to SERVE this game's
combat tempo, not imported from another game's vocabulary) without
having to invent any engine plumbing first. Nothing described here is
content - no CardEffect or EnemyIntent applies a status yet, and the one
status that exists (`test_effect.tres`) is an explicitly-labeled dev
placeholder, not a real design, wired only to a dev-only button in
battle.tscn for verification.

**Data shape:** `StatusEffectData` (a `Resource`, authored as a `.tres`
like `CardData`/`EnemyData`) holds an id, display name, a `Category`, a
magnitude, a duration in turns (or `DURATION_UNTIL_REMOVED`, a sentinel
`-1`, for a status that only leaves via some future explicit removal
effect - no such effect exists yet either), and a `stack_rule`. Runtime
state per active instance (`ActiveStatus`, a plain `RefCounted`, mirroring
the static-definition/mutable-runtime-state split `EnemyIntent`/
`EnemyCombatant` already established) tracks its own current magnitude
and turns remaining separately from the `.tres` defaults, so stacking can
diverge from them over a status's lifetime.

**Category is the only thing that decides what a status DOES, and it's
deliberately generic, not flavored:**
- `TICK` - deals its magnitude as unblockable damage once per turn, at
  the START of its holder's own turn (mirrors `_deal_self_damage()`'s
  "this bypasses block" stance - a DoT ticking through a full-block
  turn would feel like it wasn't really guarded against, when the
  status was never a blockable attack to begin with).
- `MODIFIER` - adjusts incoming or outgoing damage (`ModifierTarget`),
  either by flat addition or by percentage (`ModifierOperation.MULTIPLY`
  stores magnitude as a percentage - e.g. 50 means +50% - specifically
  so magnitude stays an int with no separate float field to keep in
  sync).
- `INFORMATIONAL` - no mechanical effect; a pure marker category for
  whatever a future status needs to just be visible/trackable without
  doing anything on its own.

No category hardcodes what a *specific* status is about (poison, weak,
whatever) - it only hardcodes the generic MECHANISM a status in that
category uses, the same way `CardEffect.EffectType` supplies a generic
engine (DAMAGE, BLOCK, ...) that content fills in with specific numbers,
not the other way around.

**Stacking:** re-applying a status whose data already has a matching
active entry doesn't add a second, separate instance - it stacks onto
the existing one, per `stack_rule`: `REFRESH_DURATION` (the default -
resets duration to the fresh application's default, magnitude
untouched), `ADD_MAGNITUDE` (sums magnitude, duration untouched), or
`REFRESH_AND_ADD` (both). `REFRESH_DURATION` was chosen as the global
default specifically to avoid runaway magnitude creep from repeated
small applications being the assumed norm - a status opts into the
stronger `ADD_MAGNITUDE`/`REFRESH_AND_ADD` behavior per-`.tres`, it's
never accidental.

**Turn-boundary ticking:** each combatant ticks its OWN active statuses
at the start of its OWN turn - the player's in `_start_player_turn()`,
each enemy's in `_resolve_enemy_intent()` before that enemy's intent
resolves. A TICK status that defeats its holder here ends the battle
before anything else that turn would otherwise run.

**Display:** a row of small icon+number badges (`StatusBadge`, mirroring
`BlockBadge`'s visual pattern at a smaller diameter, since several can
show at once) sits just outside `VitalsBar`'s right edge - the mirror
placement of `BlockBadge` overlapping the left edge. Follows the same
UI convention Combat Telegraphing established: an empty status list
reserves no layout space, it's just an empty row.

**Known future gap, deliberately left open:** `_update_intent_display()`
(what the player sees BEFORE an enemy's turn resolves) does not run
`_apply_status_modifiers()` - only escalation does today. The first
`MODIFIER`-category status that affects `OUTGOING_DAMAGE` will need the
display path updated too, or the number shown will stop being the
number that lands, breaking Combat Telegraphing's core promise. Flagged
in code at the `_resolve_enemy_intent()` call site; not fixed now
because no such status exists to actually violate it yet.

**Defining a new named status, once one is designed:** author a new
`StatusEffectData` `.tres` (see `resources/statuses/test_effect.tres`
for the shape) with its real id/display name/icon color, pick whichever
`Category` matches the design (TICK for DoT-style, MODIFIER for
amplification/reduction, INFORMATIONAL for a pure marker), and set
magnitude/duration/stack_rule to taste. The remaining step - a card or
enemy intent actually applying that resource to a combatant's status
list via `_apply_status()` - doesn't exist as a mechanism yet (no
`CardEffect.EffectType` case, no `EnemyIntent.IntentType` case reaches
it); that's the next piece of plumbing a real status will need, not
something this pass builds ahead of having content to justify it.

## Battle Layout (DECIDED)

Battle is arranged horizontally - player on the left, enemy (or enemies,
see below) on the right, both roughly centered vertically in the
screen's upper band, hand anchored at the bottom as always. This
replaced an earlier layout where the enemy alone was centered and the
player had no figure in battle at all, just an HP bar in the corner.

**Player battle presence:** the player now has a silhouette in battle,
reusing the SAME asset the field already uses (`player_visual.gd`) via a
new `player_visual.tscn` wrapper - one script, two ways of attaching it
(inline under `Player` in field_room.tscn for the field, instanced
standalone for battle), the identical "one asset, not two" reasoning the
enemy silhouette work already established. `player_visual.gd` degrades
gracefully with no `CharacterBody2D` parent to read velocity from (as in
battle): idle bob still plays, walk-bob/lean/facing-changes simply never
trigger, since none of them fire without real motion.

**Player vitals cluster:** `player_battle_visual.gd`/`.tscn` is the
player's side of the same bottom-anchored positioning convention Enemy
already uses (see Combat Telegraphing's enemy silhouette note) - the
silhouette's feet sit a fixed gap above a VitalsBar, itself using the
same compact `bar_height_px` treatment as an enemy's own bar, so the two
sides read as visually consistent. Deliberately its own script, not a
shared base class with `enemy.gd` - Enemy's layout math is interleaved
with name/intent/flavor logic the player side has none of, and
extracting a shared piece would mean touching existing, working enemy
code for a fairly small amount of overlap.

**EnemyZone:** the enemy side is a real `HBoxContainer` capable of
holding several enemy clusters side by side (silhouette + intent +
vitals, each), not just a single centered Enemy - see Multi-Enemy Combat
below for what now actually fills it beyond one.

**Vertical composition rebalance (DECIDED):** shrinking the hand
(`HAND_CARD_SCALE`) used to be the only lever for reclaiming vertical
space, and it fought directly against card readability - the actual
fix was never card size, it was that the fully-visible hand and the
top-anchored combatants left a dead band of empty space between them
(97-135px) with nothing using it. Replaced with two changes together:

- **The hand sits mostly below the screen's bottom edge at rest,
  rising fully into view on hover** - `battle.gd`'s `hand_rest_visible_
  height_px` (`@export`, 100px) controls how much of a card's own
  height, from its top (cost badge, then name), stays visible without
  hovering; the art slot and description sit genuinely off-screen, not
  just visually covered. This is an EXTENSION of `card.gd`'s existing
  hover pop-out, not a second mechanism: `hover_offset`/`hover_scale`/
  `hover_duration`/`armed_offset`/`armed_scale` moved from `const` to
  `@export var` on `Card` (identical default values, so deck-viewer/
  reward-screen cards - which never touch them - are completely
  unaffected), and `battle.gd` sets a bigger `hover_offset`/`armed_
  offset` on each hand card specifically, sized to exactly cancel
  `HandContainer`'s own below-fold sink plus the SAME extra lift
  (`hover_rise_extra_px`, 50px) and armed-vs-hover distance (`armed_
  extra_lift_px`, 30px) the original constants already used. The
  card's own rest state (`visual.position = Vector2.ZERO`) never
  changes - it's `HandContainer`'s own box that moves mostly off-
  screen, which is what makes hovering the visible sliver (the only
  part the mouse can physically reach) still register as hovering the
  whole card. `hover_duration` also grows for hand cards specifically
  (0.18s vs. `Card`'s own 0.1s default) since they now travel much
  further - same easing curve, a magnitude tweak only.

  **`armed_offset`/`armed_extra_lift_px` REMOVED (2026-08-25, center-
  slot pass)** - a raised-in-place armed pose put a right-side hand
  card directly over the enemy sprite/HP bar/flavor text while a left-
  side one cleared them entirely; narrowing the hand couldn't fix this
  on its own since the card itself, not the hand's width, was the
  problem. Armed now flies to ONE fixed on-screen point regardless of
  hand slot (`battle.gd`'s `armed_card_center_y_px`, X always viewport-
  center) via `card.gd`'s `visual.top_level`, not a per-slot local
  offset - see `card.gd`'s `set_armed()` for the mechanism. `hover_
  offset`/`hover_scale`/`hover_duration` and ordinary (non-armed) hover
  are unchanged.
- **Player/enemy combatants moved down toward the screen's vertical
  center**, using the space the sunk hand freed up - `battle.gd`'s new
  `combatant_top_offset_px` (`@export`, 291px) repositions `PlayerBattle
  Visual`/`EnemyZone`'s own boxes to a shared top offset, preserving
  each box's own baked height so nothing inside either one (intent
  icons, name labels, vitals bars - all positioned in LOCAL space
  relative to their own parent) needed a separate fix; they move down
  automatically with their box. Picked so `EnemyZone`'s own (taller) box
  centers almost exactly on the screen's true vertical middle (540).

Verified against a real battle screenshot at a full 10-card hand: cost
and name read clearly on every card without hovering; hovering the
leftmost AND rightmost cards (not just a middle one) brings each fully
into view, including its full description, with no clipping at either
screen edge; all 10 cards still fit the screen width; clicking a card
still plays the correct one (hand size 10 -> 9, the clicked card's data
matching what was actually removed); enemy name/intent stay correctly
positioned above the repositioned silhouette; the battle backdrop (see
the Biomes section's own battle-backdrop note) still reads clearly
behind the rebalanced composition.

**Follow-up - grounding the combatants surfaced a real conflict between
the two exports above (DECIDED, resolved):** the first pass's `combatant
_top_offset_px` (291) centered `EnemyZone`'s box on the screen's true
vertical middle, but against the actual battle backdrop that still read
as the combatants floating above its foreground concrete rather than
standing on it. Moving them down to genuinely stand on the ground
(confirmed by comparing screenshots before/after, not by re-deriving the
center-of-screen math) needed a much bigger offset (480, close to the
literally-requested "+200px") - and at that offset, `hand_rest_visible_
height_px`'s own ideal value (220, showing most of the art slot) put the
hand right back into the combatants' own HP bars. The two exports draw
on the same limited vertical budget between the combatants and the
screen's bottom edge; pushing one all the way to its own independent
ideal starves the other, confirmed empirically (screenshotting each
candidate pair, not computed from box heights alone - where a box's
VISIBLE content actually ends doesn't match its own baked height
exactly, so the numbers alone weren't reliable enough to trust without
looking at the result).

Resolved as a deliberate compromise, not a full win for either side:
`combatant_top_offset_px` settled at 480 (close enough to the ground to
still read as standing on it) and `hand_rest_visible_height_px` at 140
(real, meaningfully more art than the original 100px baseline - roughly
the top third of the art slot - while leaving genuine, if modest,
clearance above the hand). Re-verified the full battery from the pass
above still holds at these settled values: full 10-card hand readable
without hovering, both extreme cards rise fully into view with no
clipping, all 10 fit the width, clicking still plays the correct card.

**Follow-up - full art at rest, combatants moved UP instead of further
down (DECIDED):** the compromise above still wasn't enough art to
identify a card by its artwork alone, and separately, the combatants
sitting higher on the backdrop's concrete apron (a framing preference,
not a "stand on the ground" correction this time) turned out to free up
the SAME shared vertical budget from the opposite direction - moving
`combatant_top_offset_px` UP by 216px (20% of the 1080-tall viewport, to
264) instead of pushing it further down did what the previous pass
couldn't: leave enough room for `hand_rest_visible_height_px` to grow to
238, clearing the art slot's own full range (local y ~93-235 at
`HAND_CARD_SCALE` 1.0) with only the description below the fold. Both
numbers moving in the direction that widens the gap between them,
instead of both competing to shrink it, is what actually resolved the
previous pass's conflict - not a new tradeoff, just discovering the
conflict was only inherent to the SPECIFIC prior direction (combatants
down, hand up) rather than to the two exports themselves.

Verified against a real battle screenshot: full art slot visible on
every one of a 10-card hand's cards without hovering, description
genuinely below the fold; hovering the leftmost and rightmost cards
both reveal the complete card (including description) with no clipping
at the top of the screen; all 10 still fit the screen width; clicking
still plays the correct card. Also verified HP bars, intent icons,
enemy name, AND floating damage numbers (`enemy.gd`'s
`_spawn_floating_damage()`, added as a child of `Enemy` itself - the
same local-space positioning as everything else in the box) all move
up together with the repositioned combatants - triggered a real hit via
a Slash card (not the dev -100 button, which would defeat the target
and turn this into a defeat-sequence screenshot instead of a clean
composition check) and confirmed the floating number lands correctly
over the (now higher) enemy silhouette.

**Engine note - `show_behind_parent` produces no visible draw slot under a
CanvasLayer (2026-09-01, contact-shadow rendering-failure investigation):**
`Enemy`/`PlayerBattleVisual`'s own contact shadow (`EntityShadow.attach()`,
used to ground both against the battle backdrop) was invisible in every real
capture despite every property read - `visible`, `is_visible_in_tree()`,
position, scale, color - reading correct. Root cause, confirmed by toggling
the property live and capturing pixels, not by reading properties: setting
`show_behind_parent = true` on the shadow `Sprite2D` draws nothing at all
(not merely hidden behind something) when its parent is a `Control` living
under `battle.tscn`'s `UI` `CanvasLayer`. Setting it `false` in the exact
same spot made the shadow render immediately. Confirmed NOT specifically
about being a *direct* child of the `CanvasLayer` - `Enemy`'s shadow fails
the same way and `Enemy` sits two levels below `UI` (`UI` -> `EnemyZone` ->
`Enemy`). Left undetermined whether the true trigger is "any `CanvasItem`
with a `CanvasLayer` ancestor at any depth" or "`Control`-type immediate
parent" specifically - both differ from field's `Node2D`-parented entities
simultaneously, and isolating which one alone is decisive wasn't worth the
side quest.

Workaround, NOT a universal fix: `EntityShadow.attach()`'s `use_sibling_
index_zero` params key (default `false`, every field consumer's behavior
unchanged) inserts the shadow as sibling index 0 instead of setting `show_
behind_parent` - `grounding.gd` (battle's own consumer) is the only caller
that sets it `true`. Deliberately not unified with `show_behind_parent`
even for field's own use: index 0 draws behind EVERY sibling the parent
has, where `show_behind_parent` draws behind only the parent's own
drawing regardless of sibling order - they coincide for today's field
entities only because none of them have a shadow-relevant sibling that
should draw BEFORE the shadow would otherwise land. A future consumer
needing that distinction should reach for this same param, not assume the
two mechanisms are interchangeable.

## Multi-Enemy Combat (DECIDED)

Battle now supports 1-3 simultaneous enemies (an `Array` of `EnemyData`)
and click-based targeting for single-target card effects - resolving
Open Question 16. Most combat blobs still spawn exactly one enemy, as
before - `battle.gd`'s `_resolve_enemies_data()` is the seam a blob
touches to hand Battle more than one `EnemyData`, now actually used by
the rare AUTHORED encounter (see Bestiary's "Authored encounters" and
`RoomState.pending_encounter_enemies`), not just a theoretical one.

**Targeting state machine:** two vars on `battle.gd`
(`_pending_target_card_instance`/`_pending_target_data`) carry the whole
thing - `null` is normal hand state, non-null means "a card is armed,
waiting for a target click." A card only ever arms if it has a `DAMAGE`
effect (the one targeted `CardEffect.EffectType` today) AND more than
one enemy is alive; with exactly one enemy standing, a targeted card
still resolves the instant it's clicked, no extra step - the common
case stays exactly as fast as it's always been. Armed, the card gets a
raised, gold-tinted "primed" look (`Card.set_armed()`) and every living
enemy pulses (`Enemy.set_targetable()`, the same infinite scale+tint
pulse skeleton `field_blob.gd`'s proximity notice already uses).
Resolving is a click on any living enemy (`Enemy.enemy_clicked`, via
its existing `SilhouetteHoverArea`); cancelling - no energy spent, card
stays in hand - is clicking the armed card again, a different card, an
End Turn/Deck/dev-damage click, or a raw background click
(`Battle._unhandled_input()`, which is why `HandContainer`/`EnemyZone`
both need `mouse_filter = IGNORE` - neither has click behavior of its
own, and the default STOP would otherwise swallow a background click
before it ever reached the fallback).

**Defeat, per-enemy:** a defeated enemy fades out immediately (its own
`play_defeat_sequence()`, fire-and-forget if others are still up - the
fight doesn't pause to watch it happen) and stops being a legal target
right away (its silhouette's hitbox goes `mouse_filter = IGNORE` the
same moment). Only once every enemy is down does the real victory
sequence run (`_on_all_enemies_defeated()` - dim, beat, Continue,
exactly as before), awaiting the LAST enemy's own fade.

**Enemy turns are sequential, not simultaneous:** `_run_enemy_turn()`
walks every living enemy in spawn order, each with the same
telegraph-pause → resolve → resolve-pause → advance-intent beat a
single enemy always had - which already reads as readable separation
between consecutive enemies without a new pause constant. A player
death partway through (an earlier enemy's attack) stops the rest from
acting that turn.

**Enemy formation scales with count:** each enemy's cluster width/bar
width/silhouette scale (its own single-enemy-tuned defaults, untouched)
get multiplied by `Battle.two_enemy_scale_factor`/`three_enemy_scale_
factor` once at spawn, based on how many are actually in the fight -
`EnemyZone` (an `HBoxContainer`, `alignment = CENTER`) already packs and
centers whatever children it has with a fixed separation regardless of
count, so shrinking each cluster (rather than changing how they're
packed) is what makes 2-3 enemies read as one tight, deliberate group
instead of several full single-enemy-sized boxes with dead margin
between them - verified: at both counts the gap between adjacent
clusters is the exact separation value on both sides, and the whole
group's visual center lands exactly on EnemyZone's anchor point. A
defeated enemy stays put as a child of `EnemyZone`, still reserving its
slot - it was pulled out to let the container auto-recenter survivors
in an earlier pass, but that reads as the group jumping mid-fight; a
kill now just fades that one slot to nothing (`Enemy.play_defeat_
sequence()`) and leaves everyone else exactly where they were.

**Still open:** verified 3-enemy clusters land ~89px into `EndTurnButton`
at the current default `three_enemy_scale_factor` (0.45) - shrinking
further to clear it starts hurting legibility (a smaller silhouette than
even the field scale), so this is left as a tune-by-eye tradeoff rather
than solved outright; `EnemyZone`'s anchor position or `EndTurnButton`
itself may need to move once a 3-enemy `EncounterData` (see Bestiary's
"Authored encounters") actually exists to look at - only a 2-enemy
encounter (Twin Glasswings) has been authored so far.

## ELITE Rooms (DECIDED)

Resolves open question 14: ELITE is now a real room/node type in the run
graph - `RoomType.Kind.ELITE`, alongside COMBAT/TREASURE/EVENT/SHOP/
BOSS - not a chance roll inside an ordinary COMBAT room anymore. A
deliberate risk/reward routing fork, the same shape SHOP already had.

**Placement:** `run_state.gd`'s `_assign_room_types()` reserves 2-4
ELITE LAYERS per run (`elite_layer_count_min`/`elite_layer_count_max`,
2026-08-28, guaranteed-elite-layers pass), chosen before any other room
type is placed, spaced at least `elite_layer_min_gap` layers apart, and
excluding the boss's own last layer plus the first
`elite_excluded_post_opening_layers` layers after the opening room (an
elite fight shouldn't be the run's introduction). Each reserved layer
gets exactly one ELITE node; a low, separately-tuned chance
(`elite_side_by_side_promotion_chance`) promotes a second node in that
same layer too, without changing the layer count. This replaced an
earlier flat node-pool shuffle-and-slice (`elite_count_min`/
`elite_count_max` + `elite_min_layer`/`elite_max_layer`) that guaranteed
a total NODE count but nothing about which LAYERS those nodes landed on.
`_validate_run_graph()` checks the elite layer count, the gap between
chosen layers, and that every ELITE node's layer is inside the eligible
window, the same shape its existing `shop_count != 1` check already used.

**A separate, smaller encounter pool:** `EncounterPool.pick_random()`
(see Bestiary's "Authored encounters") now takes a folder parameter -
the general `ENCOUNTER_FOLDER` ordinary combat blobs roll against via
`encounter_chance`, or `ELITE_ENCOUNTER_FOLDER`
(`resources/encounters/elite/`), which `room_state.gd`'s new
`_generate_elite_layout()` always draws from. The Wardling and Twin
Glasswings both moved here - the Wardling as a 1-entry `EncounterData`
(`wardling_solo.tres`), Twin Glasswings as the same 2-entry one that
already existed, just relocated. **Elite content is no longer reachable
any other way**: `_generate_combat_layout()` now always passes
`allow_elite=false` to `EnemyPool.pick_random()`, and its general
`encounter_chance` roll only ever pulls from the now-empty general
folder - an elite fight only ever happens by choosing the ELITE door.
This surfaced a real bug in `field_blob.gd`: `_setup_visual()` branched
on `encounter_enemies.size() > 1`, so a 1-enemy `EncounterData` (the
solo Wardling) fell through to the plain fallback octagon instead of
its real silhouette. Fixed to branch on non-empty instead, and
`_setup_multi_visual()` now renders a single member at the normal
`FIELD_VISUAL_SCALE` rather than the group-shrink `ENCOUNTER_VISUAL_
SCALE` - an elite should never render smaller than an ordinary enemy.

**Door preview - REMOVED (see the navigation redesign's step 1 below):**
this used to give `field_exit.gd`'s preview label the same visual weight
`enemy.gd`'s elite name-intro already gives an elite/boss encounter
inside battle (gold-toned, larger, popping in rather than just
appearing), so an elite door read as distinct before the player
committed to it. Both the ordinary room-type label and this elite-
specific styling are gone now that a door no longer reveals its
destination at all - that choice moved to the map screen instead (not
built yet - see the navigation redesign note).

**Room behavior once inside:** an ELITE room locks its exits exactly
like a COMBAT room until its one encounter is defeated (`field_room.gd`'s
`_update_exit_lock()`) - the "legible, deliberate decision" happens at
the door in the room before it; once inside, it's a fight room like any
other, same as DESIGN.md's existing combat door-lock policy already
argues (avoidance isn't a real decision yet). Walls tint a muted gold
(`ELITE_WALL_COLOR`) instead of the normal gray-blue, echoing BOSS's own
red tint at the same visual weight but a different color - the room
itself signals "this is different" before the fight starts.

**Boosted rewards:** `reward_screen.gd` reads `RoomState.current_room_
type == ELITE` once per battle (still accurate when the reward screen
loads - nothing between the elite blob dying and this screen advances
to a new room). An elite victory gets gold `* elite_gold_multiplier`
(2.0 by default), a guaranteed card-choice row (skips the normal 60%
miss chance), and its own independent rare-drop chance (`elite_rare_
drop_chance`, 0.35 - well above the normal 0.08). All four exported for
tuning.

**Per-type minimum guarantees, generalized beyond ELITE (2026-08-28,
per-type minimum pass).** `RunState.room_type_min_instances` (Dictionary,
`Kind -> minimum count`) is the mirror image of `room_type_max_instances`
(see the wreckage heap's own note) - seeded today with `HEAP: 1` only,
since "the wreckage heap must appear at least once per run" is a real
requirement (see the NPCs section's own field-interactables note) that
nothing else guaranteed. Reserved by `_reserve_minimum_instances()`,
called from `_assign_room_types()` right before the leftover weighted
fill, among reachable candidates - same overall PATTERN elite's own
layer reservation above established (reserve first, let everything else
fill in around it), but deliberately NOT built on `_reserve_elite_layers()`
itself: that function's gap-spacing and side-by-side-promotion machinery
exist specifically for ELITE's own min/max RANGE across multiple reserved
layers, which a flat per-type floor doesn't need. What DOES generalize
cleanly (and is reused as-is) is `_compute_reachable_nodes()` - already
fully generic, no ELITE-specific logic in it at all.

Layer 0 (the run's own first non-opening room) is excluded from every
minimum reservation, for the same reason `elite_excluded_post_opening_
layers` already excludes it from ELITE - checked, not assumed, that this
matters: layer 0 is NOT currently guaranteed to be COMBAT at all (EVENT/
TREASURE/HEAP can already land there via the ordinary guaranteed-random-
pick/leftover-roll steps, measured at roughly 40% of 200 generated runs
combined), but a minimum guarantee forces a type onto some layer with
CERTAINTY rather than odds, and layer 0 - the room reached immediately
after the always-COMBAT opening room - is the one layer where adding
that certainty for a non-combat type is least wanted.

**Not validated, on purpose:** a future `room_type_min_instances` entry
whose minimum exceeds its own `room_type_max_instances` cap isn't
rejected or clamped - the minimum simply wins, since it's reserved and
committed before the leftover loop's own max-aware filtering ever runs;
only a `push_warning` flags the conflict. Likewise, if total minimums
across every seeded type ever exceeded how many eligible rooms a run
actually has, `_reserve_minimum_instances()` reserves as many as it can
and warns about the shortfall, rather than crashing or hanging - the
same "clamp, warn, don't fail" shape `_reserve_elite_layers()`'s own
`max_feasible` clamp and `_place_content_positions()`'s own fallback
already established for their own equivalent shortfalls. Neither case is
reachable today at `HEAP: min 1, max 2`.

Verified headlessly across 10 generated run graphs: HEAP appeared at
least once and never more than twice in every run (3 runs got 1, 7 got
2), landing across a real spread of layers 1-9 (not pinned to one spot),
and never once on layer 0.

## Shop (DECIDED)

The SHOP room is now a real interaction, not a placeholder marker.
Deliberately neutral/functional presentation - no merchant flavor, no
themed dressing - since the game's overall aesthetic direction is still
undecided (see Ideas Parking Lot's ART DIRECTION SESSION note); the shop
is capability first, skin later.

**Structure:** walking into the shop's field marker opens ShopWindow
(shop_window.gd/.tscn), reusing the loot window's shape - a panel of
rows, a Leave button, blocking the field beneath it while open (pauses
the SceneTree, same mechanism DeckViewer already uses). Gold is spent
immediately per purchase, not a cart/checkout flow - every Buy button
calls straight into `RunState.spend_gold()` (the new mirror of
`add_gold()`) the instant it's pressed, and every row's affordability
re-checks right after. The exit door is never locked for a SHOP room
(same "only COMBAT/ELITE lock" rule field_room.gd already had) - the
shop is never mandatory.

**Stock (DECIDED - fixed per room, not per visit):** a SHOP room rolls
3-4 cards (COMMON/RARE only - ULTRA_RARE stays a gift-only tier, see
Rewards below) ONCE, at room-generation time (`RoomState.shop_stock`,
set by room_state.gd's `_generate_shop_layout()`), the same "generated
once, just read/depleted afterward" relationship `room_layout` already
has with field_room.gd. A purchase erases that exact card from
`shop_stock` and its row from the window; closing the window and
walking back onto the marker reopens showing exactly what's left,
never a reroll. `CardPool.load_class_pool()` (a new shared helper) is
what both this roll and reward_screen.gd's regular/rare card rolls read
the class's pool through now, so there's one definition of "this class's
cards," not two.

**Card removal (DECIDED - the highlighted offer):** a "Remove a Card"
service opens DeckViewer in a new selection mode (`open_cards(...,
selection_mode=true, manage_pause=false)` - the `manage_pause` flag
exists specifically so DeckViewer's own close() doesn't resume the field
while ShopWindow, nested one level up, is still open on top of it) -
clicking a card there removes it from `RunState.deck` for real via the
existing `remove_card_from_deck()`. Priced at 50 gold, **scaling +25 per
removal bought this run** (50 -> 75 -> 100 -> ...) rather than a flat
price: removal is the single strongest deck-improving purchase in the
genre, and a flat cost would let one lucky gold haul buy several in the
same visit. `RunState.card_removals_purchased` tracks the count run-
wide (not room-wide) on purpose, in case a future run ever has more than
one shop. Given its removal, RemoveRow renders with a brighter, thicker
NEUTRAL border (`ShopRow.set_highlighted()`) - not a rarity color, since
the shop's aesthetic is still undecided - so it reads as the most
valuable line in the shop without borrowing color language that means
something else elsewhere (rarity, elite, boss).

**Rest (DECIDED):** heals 25% of max HP for 150 gold, repeatable up to
full HP (each purchase independently priced/capped, no scaling needed -
HP itself is the natural limit once the Buy button disables at full).
Priced steep on purpose: it's the run's only healing outside rare
ULTRA_RARE cards, so it should read as a deliberate, meaningful spend at
the one guaranteed shop, not a casual top-up.

**Bug fixed: field HUD froze behind the shop overlay (DECIDED -
implemented):** `GoldDisplay`'s tick-up animation and `VitalsBar`'s HP
bar fill both animate via `create_tween()`, and a Godot tween bound to a
node stops advancing whenever that node's own effective process mode is
paused - which every field-room overlay (`ShopWindow`, `DeckViewer`,
`MapScreen`) triggers the instant it opens (`get_tree().paused = true`).
A purchase or Rest made with the shop open still updated `RunState`
correctly and still emitted `gold_changed` (signal emission and direct
method calls aren't pause-gated), but the tween animating that new value
onto the SCREEN never advanced until the overlay closed and unpaused it
- reading as "nothing happened" until the moment of closing, when the
already-queued tween suddenly caught up. `VitalsBar`'s printed HP NUMBER
was actually fine (`update_hp()` sets that text synchronously, outside
any tween) - it was specifically the bar's FILL graphic, and gold's
ENTIRE displayed number (which only ever changes via the tween), that
froze.

Fixed at the source rather than per-overlay: both `gold_display.gd` and
`vitals_bar.gd` now set `process_mode = Node.PROCESS_MODE_ALWAYS` in
their own `_ready()` - the same mechanism `ShopWindow`/`DeckViewer`
already use to stay interactive under their own pause. A tween only
pauses if ITS bound node's effective process mode does, regardless of
how many paused ancestors sit above it, so this covers every overlay
that pauses the tree today (and any future one) automatically, not just
the shop - checked `MapScreen`/`DeckViewer` and confirmed they pause the
same way, and `reward_screen.gd`'s own "loot window" doesn't have this
problem in the first place since it's a separate scene transition, not
an overlay stacked on top of a still-visible field HUD. No EVENT room
overlay exists yet to check (still a placeholder - see Open Questions).

**Economy tuning (sanity-checked against typical play before building):**
the shop sits in run-graph layers 3-6, and since the run graph only ever
puts the player through ONE room per layer (whichever node their chosen
path hits), that's 2-5 prior rooms (avg ~3.5) of gold income before they
reach it. A COMBAT room nets ~48g on average (avg 1.8 blob-fights per
room * ~20g reward each, plus a 60% chance of a 15-25g field chest); a
TREASURE room nets ~50g (guaranteed 40-60g chest); an EVENT room nets
~0g (still a placeholder, see Open Questions). That puts typical gold at
the shop around 120-160g - enough for roughly one "big" pick (a RARE
card or the first removal) plus one small one (a common card), not
everything at once, which is the intended tension.

## NPCs (DECIDED — in-world contact + click-to-accept, no modal)

`NPCData` (`npc_data.gd`) is the static definition of one NPC - name,
world-voice line, the card she grants, her silhouette (see its own
header for the full field rundown); `RunState.npc_interacted`
(Dictionary, keyed by `npc_id`) is the per-run mutable half - whether
THIS run's player has already accepted her offer, surviving independent
of whether her room ever gets revisited.

**Deliberate deviation from ShopWindow's pattern (2026-08-27).** The
closest existing analogue for "player touches a field object, something
offers them a choice" is ShopWindow's pause-and-modal - full screen,
backdrop, the works. Rejected on purpose for this beat: a modal is too
heavy for "she holds something out." The whole interaction stays
in-world - no pause, no backdrop, no panel, nothing but a line of text
near her and a click.

- **field_npc.gd fires `npc_entered`/`npc_exited`** (Area2D `body_
  entered`/`body_exited`, same detection shape field_marker.gd/field_
  chest.gd/field_blob.gd already use) - reports the touch and the
  walk-away, nothing more. It doesn't know whether she's been talked to
  before or what accepting does; field_room.gd owns both decisions (see
  its `_on_npc_entered()`/`_on_npc_clicked()`), the same "announce it,
  let something else decide" split field_marker.gd's own shop_entered
  wiring already established one level further.
- **The offer text is world-voice, not dialogue** - no quotes, no name
  label, no speech framing, sourced straight from `NPCData.dialogue_
  text` ("She holds something out. It was not hers." - placeholder).
  Rendered in Spectral (`assets/fonts/Spectral-Regular.ttf`), the same
  serif this project's other world-voice text already uses (loot_row.
  gd's own `WEAPON_NAME_FONT`) - full-color/serif for world-voice vs.
  sans/muted for system-voice is this project's established two-
  register split (see the Toll section's own note on the same
  principle). `OverlayStyle.apply_to_label()` gives it the same
  backdrop-legibility outline every other field/battle label already
  gets.
- **Fade in on contact, fade out on walking away, asymmetric** (`offer_
  fade_in_sec`/`offer_fade_out_sec`, both `@export`, defaults 0.2s/1.1s)
  - reuses enemy.gd's own `_fade_flavor_to()` shape exactly (kill-then-
  create on a dedicated tween), not a new timing system. Fast in reads
  as immediately responsive; slow out reads as the line settling back
  into the scene rather than being snatched away.
- **Click-to-accept needed its OWN handler, not the shared one.**
  field_room.gd's `_on_interactable_clicked()` always means "walk to
  this node" (every other interactable fires its real interaction from
  arrival, via its own `body_entered`) - a click on her sometimes has to
  mean "accept" instead, but ONLY while her offer is actually showing.
  Bolting that branch onto the shared function would have made every
  OTHER interactable's click handling something that needed re-proving
  safe. Instead, NPCs get a dedicated `_on_npc_clicked()`: if the
  clicked NPC is the one currently tracked in `_npc_in_contact` (set by
  `_on_npc_entered()`, cleared by `_on_npc_exited()`/on accept), the
  click accepts; otherwise it walks the player to her exactly like
  clicking any other interactable does - so approaching her by clicking
  from a distance is completely unaffected.
- **Accepting**: `RunState.add_card_to_deck(npc_data.granted_card)` (
  Ballast, placeholder) + `RunState.npc_interacted[npc_data.npc_id] =
  true`, with `_npc_in_contact` cleared and her offer faded out
  immediately for click feedback - no confirmation step.
- **Walking away without clicking leaves her available.** `_on_npc_
  exited()` only clears the contact-tracking var and fades her text out;
  nothing marks her resolved. Re-entering her trigger later in the same
  visit runs `_on_npc_entered()` fresh, which re-offers exactly as
  before - re-approachable for free, no re-arming logic needed.
- **After accepting, contact shows nothing** (the chosen option between
  "nothing" and "a second line" - no second line invented, per this
  pass's own brief against inventing flavor text). `_on_npc_entered()`
  checks `RunState.npc_interacted` first and returns immediately if
  she's already resolved, so `_npc_in_contact` never gets set and her
  label never shows again, this visit or any future one.
- **Reachability, confirmed not re-derived:** the opening room's own
  placement pass already put her BEHIND the player's spawn point
  (`OPENING_ROOM_NPC_X` = 450, spawn at 1200, exit at 2660 - see room_
  state.gd's own note on why) specifically so reaching her means
  deliberately walking away from the exit, never a detour on the way to
  it. Verified headlessly this pass (not just re-read): the exit sits
  over 1000px from her position, and nothing in this pass touched
  placement, spawn, or exit logic.

Verified headlessly (21 checks, real `field_room.tscn` instantiated
against a freshly reset run rather than testing the two scripts in
isolation): the opening room's layout still spawns exactly one FieldNPC
with dialogue/granted-card data wired through from `NPCData`; contact
fades her offer in with the exact `dialogue_text` string; walking away
fades it back out and leaves her re-offering on a second approach;
accepting grants exactly one Ballast, marks her interacted, and fades
her text out immediately; a second contact in the same visit no longer
arms `_npc_in_contact` or shows her label; a second click after
accepting falls through to the harmless walk-to branch rather than
granting a second card; and the exit remains reachable without ever
needing to pass through her trigger.

**Real art (Keeper.png, 2026-08-27) replaces the vector placeholder -
this project's first raster NPC/character sprite outside the player.**
Located at `assets/npcs/Keeper.png` (1024x1536). Mid-pass complication,
noted for the record: the version first found on disk was a flat RGB
image with a solid near-white background and no alpha channel at all
(confirmed: `Image.detect_alpha()` false, format RGB8) - unusable
directly in a `Sprite2D` without producing a visible white rectangle. A
background-removal pass was built and run (flood-fill from the image
border rather than a flat color threshold, so a pale-but-genuine cloak
highlight wouldn't get eaten just for being close to white) and its
output wired up - but partway through wiring, `Keeper.png` itself was
replaced on disk with a properly re-exported version that already
carries real alpha (confirmed: `detect_alpha()` now `ALPHA_BLEND`,
format RGBA8, corner pixel fully transparent). The derived cutout file
and its own background-removal script were both discarded as no longer
needed; everything below wires directly to the (now-transparent)
`Keeper.png`, re-measured fresh against that actual file rather than
carrying over numbers from the discarded intermediate.

- **One visible thing worth a live check, not fixed here:** the current
  `Keeper.png` shows a soft light halo/glow bleeding a short distance
  past her silhouette's edge, rather than a hard cutout - visible
  against a black backdrop when inspecting the alpha channel directly.
  Could read as an intentional ghostly aura (thematically not wrong for
  a mysterious figure) or as a background-removal artifact from
  whatever tool produced this version - not this pass's call, since the
  file arrived already processed; flag it if it reads wrong once seen
  against the actual field backdrop.
- **Import settings match this project's own default exactly** - no
  filter/compress override, same as every other project texture
  (`Keeper.png.import`'s own params are byte-for-byte the vanilla
  texture-importer defaults). There was nothing enemy-specific to match
  here despite this pass's own original framing - every enemy
  silhouette in this game is hand-drawn vector `Polygon2D` art, not a
  raster sprite at all; the only existing raster-character precedent in
  the whole project is the Wanderer's own `player_visual.tscn`, which
  follows this exact same "no per-asset import override" convention.
- **Visual scene structure**: `npc_visual_keeper.tscn`, a plain `Node2D`
  root (same root type `npc_visual_placeholder.tscn` - now unused, left
  in place as a template - already used) holding one `Sprite2D` child,
  `centered` at its Godot default (true) with `offset.y = -686.0` so her
  measured solid FEET (not the full canvas's own bottom edge, which has
  real but asymmetric empty padding on every side) land at local y=0 -
  the same "feet at the visual scene's own local origin" convention
  `field_npc.tscn`'s collision shape and the old placeholder's
  hand-authored polygons already assumed.
- **New per-NPC scale export, `NPCData.visual_scale`** (this NPC:
  0.213) - same role as `EnemyData.field_visual_scale` (every
  silhouette/sprite is authored at its own arbitrary coordinate scale,
  so a flat 1:1 instantiation would render wildly wrong sizes), applied
  by `field_npc.gd`'s `_ready()` to `visual_root` itself (the shared
  container), not the instantiated visual node - composes cleanly
  regardless of whether what's inside is a `Sprite2D` (Keeper) or a
  hand-drawn `Polygon2D` tree (any future NPC that wants one), with
  neither side needing to know which the other is.
- **Scale chosen to match the Wanderer's own field-room height, not an
  arbitrary guess:** the Wanderer's real rendered height in a field room
  measures 305.6px (one idle-animation frame's true ink bounding box,
  191px, times its own net scale chain - `AnimatedSprite2D.scale` 8
  times `PlayerVisual`'s own field-level `scale` 0.2 = 1.6). At
  `visual_scale 0.213`, Keeper's own measured solid height comes out to
  305.2px - confirmed headlessly, a 0.999 ratio, functionally identical
  standing height. No narrative reason surfaced to make her taller or
  shorter, so parity with the player was the default rather than
  picking a number by eye; retune `visual_scale` directly if a
  different read is wanted.
- **Facing confirmed correct, no flip needed:** she faces viewer-left in
  the source art; the opening room's water/horizon sit at LOW world x
  (the coastal shore hugs the room's left edge - see this room's own
  water-extent notes above), and she's placed at x=450, close to and
  right of the shoreline, well left of both the player's spawn (1200)
  and the exit (2660). Facing left means facing the water - the correct
  direction unflipped, so `Sprite2D.flip_h` was left at its default
  `false`.
- **Measured numbers for the world-voice text repositioning (not moved
  this pass, per its own brief - just reported):** at her placed
  position (450, 900 - `RoomState`'s default `floor_line_y`), her solid
  head-top lands at world Y **594.8**, her solid feet at world Y
  **900.0** (exactly on the floor line, confirmed headlessly). `Offer
  Label`'s own current fixed offset (`field_npc.tscn`, roughly -180 to
  -145 above the trigger's local origin) sits well above this - it was
  authored against the old placeholder's much shorter silhouette
  (~130px tall) and currently lands behind/above the player's own head
  rather than near HER head, exactly the gap this task's own brief
  flagged. Left untouched pending a deliberate repositioning pass now
  that these real numbers exist to design against.

Verified headlessly (6 checks, against the final real-alpha `Keeper.
png`, not the discarded intermediate): `NPCData.visual_scene`/`visual_
scale` load correctly from the opening room's own resource; `field_
npc.gd` applies the scale to `visual_root`; the `Sprite2D` instantiates
under it with the expected (now genuinely alpha-blended) texture; and
her measured solid feet land exactly on the floor line at her placed
position (not floating, not sunk).

**`OfferLabel` repositioned above her actual head (2026-08-27, same-day
follow-up).** Retuned live in the editor after the pass above: `visual_
scale` 0.213 -> 0.18, `Sprite.offset.y` -686.0 -> -620.0 (`npc_visual_
keeper.tscn`) - smaller and sitting a little higher relative to her feet
than the numbers this section originally measured against. `OfferLabel`
(`field_npc.tscn`) moved from offset_top/bottom -180/-145 to -301/-266 -
re-measured fresh against these NEW live numbers (not the stale 594.8
figure two paragraphs up, which is now out of date) rather than nudged
by eye: her solid head-top now sits at Area2D-local y -246.06 (world Y
653.9, at her placed position), and the label's own bottom edge sits at
-266.0 - a 20px clearance, matching this project's own "a gap above the
head" convention (enemy.gd's own name/flavor label gap uses the same
shape, just for battle instead of field). Label WIDTH/HEIGHT (its own
35px vertical span, 320px horizontal) untouched - only the vertical
position moved. Verified headlessly (the same live-measurement
technique as the pass above, re-run against the new scale/offset): the
gap between the label's bottom edge and her measured head-top comes out
to +19.94px, confirming she clears it with the intended margin rather
than overlapping.

Flagged for whoever retunes `visual_scale`/`Sprite.offset.y` again
later: `OfferLabel`'s own offset is still a hand-computed constant, not
self-adjusting - a further rescale will need this same recomputation
repeated, the same staleness this pass itself was fixing. A future pass
could make `field_npc.gd` measure her real rendered bounds at runtime
(the same `VisualBounds`-based auto-anchoring `field_blob.gd` already
does for enemies) and position `OfferLabel` from that directly, but
that's a bigger change than this one-off fix called for.

**Trigger widened so the player and Keeper don't stand in the same
space (2026-08-27).** The original `CollisionShape2D` (70x130) was
narrower than her own rendered silhouette - a player walking up had to
overlap her sprite before `npc_entered` even fired, so both figures
were already crammed together the instant her offer text showed.

- **New `field_npc.gd` exports, `trigger_width_px` (360, up from 70) and
  `approach_stop_distance_px` (140)** - `_ready()` duplicates the
  `.tscn`'s shared `RectangleShape2D` before mutating `size.x` to `
  trigger_width_px` (same "duplicate a shared resource before touching
  it per-instance" rule `card.gd`'s own zone styles already follow),
  leaving height (130) untouched - only the horizontal approach
  distance needed widening. Both exported separately rather than
  deriving one from the other: "how far away does contact fire" and
  "where does a click-to-approach stop" are related but distinct feels,
  and `approach_stop_distance_px` is deliberately kept well under
  `trigger_width_px / 2` so a click-to-approach always lands INSIDE the
  trigger zone (140 < 180) - if it didn't, a click could stop the player
  just short of the zone with no offer showing, which would read as
  broken.
- **`field_room.gd`'s `_on_npc_clicked()` no longer walks to her exact
  position.** Every OTHER interactable's click-to-walk target is its
  own literal position (standing on a chest or a door is fine); doing
  the same for her would still land the player on top of her even with
  a wide trigger, since the walk animation ends exactly where it was
  told to. The "not yet in contact" branch now computes a stop point
  `approach_stop_distance_px` from her center, on whichever side the
  player already happens to be standing (`signf(player.x - npc.x)`) -
  so a click from either direction stops at a mirrored, equally clear
  distance rather than overshooting to one fixed side.
- **Reachability re-confirmed, not just assumed still true:** widening
  70px to 360px still leaves the trigger's own right edge (630, at her
  x=450) far short of both the player's spawn (1200) and the exit
  (2660) - she stays exactly as skippable as she was at the old, much
  narrower width, since neither figure in this room ever needed to
  pass near her at all (see this NPC's own placement-pass note above on
  why she sits BEHIND spawn in the first place).
- **Measured gap when contact fires (for tuning):** approaching from her
  only reachable side (the right, matching every measurement above),
  contact begins the instant the player's own 50px-wide collision box
  first touches the widened trigger's edge - at that moment, the gap
  between the player's own collision edge and her measured sprite's own
  right edge comes out to **~116px**. This is a collision-box-to-sprite-
  edge measurement (the most precise numbers available on each side),
  not a sprite-to-sprite one - the player's own visual sprite may extend
  slightly beyond or within its 50px collision box, not separately
  measured here. Retune `trigger_width_px` directly if 116px reads too
  close or too generous once seen live.

Verified headlessly (9 checks): the collision shape's width matches the
export and stays well above the old 70px value while height stays
unchanged; the trigger's span clears both spawn and the exit with
significant margin; a click-to-approach from her only reachable side
stops at the expected offset (not her exact position) and lands inside
the trigger zone; and the contact-gap math above was computed from
these same verified numbers, not asserted separately.

**`approach_stop_distance_px` retuned so click and keyboard arrival read
similarly (2026-08-27, same-day follow-up).** The pass above's own
140px default was picked without checking it against the keyboard
case's own ~116px contact gap - they turned out clearly different
(~51px for a click-arrival vs ~116px for keyboard, confirmed headlessly)
even though both are meant to read as "she stopped a clear, similar
distance away." Root cause in the CONSTRAINT this value was checked
against, not just the number itself: the original doc claimed it had to
stay under `trigger_width_px / 2` for the stop point to land inside the
trigger, but that ignored the player's OWN 50px collision width - the
real bound is `approach_stop_distance_px < trigger_width_px / 2 + 25`
(half the player's own box), which left real headroom sitting unused.
Retuned 140 -> 190: click-arrival gap now measures ~101px against
keyboard's ~116px (within 15px, with its own 15px overlap-safety margin
intact) - close without shaving that margin down to nothing. Verified
headlessly (9 checks, extending the pass above's own suite): both gaps
computed fresh from the current live numbers land within 20px of each
other, the click-stop still lands inside the trigger (the offer is
showing the instant the walk finishes, not just short of her with
nothing happening), and the shared `_on_interactable_clicked()` used by
chests/markers/structures is unchanged - still walks to a clicked
node's exact position, confirmed by regression check, not just
assumption.

**Card offer added - a floating Card near her, no modal (2026-08-27).**
Investigation first (see this pass's own report): `card.gd`/`card.tscn`
is a self-contained `Control`, already instantiated outside battle by
`reward_screen.gd`/`shop_window.gd`/`deck_viewer.gd` via the exact same
recipe (`instantiate()` -> `set_scale_factor()` -> `set_card_data()` ->
connect `card_clicked`) - no changes to `card.gd` itself were needed,
and no modal/pause/panel was ever part of the design.

- **Accepting moved from her trigger to the card itself.**
  `_on_npc_clicked()`'s old "click her while in contact -> accept"
  branch is gone - clicking her now does nothing while approached (she's
  already there; nothing to walk to). The card's own `card_clicked`
  signal is the accept path, via a new `_on_npc_offer_card_clicked()`
  bound to the specific `npc`. Confirmed (not assumed) this needs no
  click-vs-walk disambiguation: a `Control`'s `_gui_input()` claims the
  event during Godot's GUI pass before `_unhandled_input()`'s ground-
  click-to-move or the NPC's own Area2D `input_event` ever see it - the
  same guarantee this project's own click-to-move already documents for
  every other Control-based popup.
- **`_npc_offer_card` persists across an approach cycle, not destroyed
  and recreated** - built once, lazily, on first contact; walking away
  only fades it (`_hide_npc_offer_card()`), never frees it, so "she
  stays re-approachable, returning shows the same card again" (this
  feature's own brief) is literally the same node, confirmed headlessly.
  Only accepting frees it, at the end of its own fly-away tween.
- **Scale: `npc_offer_card_scale` (0.5, exported).** Native scale
  renders ~345px tall against her/the player's own ~305px (see the
  Keeper art pass's own measurements) - oversized. At 0.5, the card's
  measured on-screen size comes out to **123.75 x 172.5px** - roughly
  two-thirds her own ~258px current height, confirmed headlessly.
- **Sequencing: text first, card after a beat.** New `npc_offer_card_
  delay_sec` (0.5, exported) gates the card's own fade-in via a single
  tween's `tween_interval()` before its `tween_property()` step - same
  kill-then-create tween shape `field_npc.gd`'s own `_fade_offer_to()`
  already uses, just with a wait spliced in front. The fade-in/out
  DURATIONS aren't a second pair of exports - they read `npc.offer_
  fade_in_sec`/`offer_fade_out_sec` directly (field_npc.gd) per this
  feature's own brief ("reuse the existing fade timing approach"), so
  card and text share one paced feel rather than two independently
  tuned fades that happen to overlap.
- **Hover left fully enabled** - `mouse_filter` untouched (unlike the
  `MOUSE_FILTER_IGNORE` reward-screen/shop already use for their own
  STATIC previews) - this card is clickable, and reward-screen-style
  hover lift is the right affordance for "this is the thing you take."
- **Accept: grant, mark resolved, refresh the deck counter, fly to the
  deck, free.** No confirmation step. `deck_button.text` is now
  refreshed on accept - its own `_ready()` comment ("deck composition
  can't change while walking around a field room... a one-time set")
  stopped being true the moment this feature shipped, flagged and fixed
  rather than left silently stale. The fly-away target is computed
  ONCE, mapping `deck_button`'s own screen position (it lives in the
  `UI` `CanvasLayer`, rendered in raw viewport pixels regardless of
  camera position) back through the INVERSE of the active camera's
  canvas transform, into a world-space point the still-`content_root`-
  resident card can tween its own `position` toward directly - no
  reparenting into the UI layer needed for one brief animation.
  `mouse_filter` is set to `IGNORE` the INSTANT it's clicked (before the
  fly-away even starts), plus an `npc_interacted` guard in the handler
  itself - belt-and-suspenders against a second click mid-flight
  double-granting the card, confirmed headlessly.
- **After accepting, contact shows nothing - same choice as the text
  itself already made**, inherited for free: `_show_npc_offer_card()` is
  only ever called from inside `_on_npc_entered()`'s existing `RunState.
  npc_interacted` gate, so no separate check was needed for the card to
  respect the same "no invented replacement flavor" rule.

Verified headlessly (27 checks): card data/scale/hover-enabled state
correct on first contact; text visibly completes its own fade before
the card's delay window even ends; both fade out together on exit
without the card being freed; re-approach reuses the identical card
instance and re-fades it; clicking her own trigger while in contact
neither accepts nor moves the player; clicking the card grants exactly
one card, marks her resolved, refreshes the deck label, and disables
further clicks on that same card instance immediately; a second click
mid-flight grants nothing further; the card frees itself once the
fly-away tween completes; re-contact after accepting arms neither the
old contact-tracking var nor a new card; and the exit remains clear of
her (now-widened) trigger throughout.

**Card repositioned and shrunk - it was sitting on top of her (2026-08-
27, same-day follow-up).** Measured, not guessed: her sprite's real
rect is x[392,520] y[654,912]; the original card (0.5 scale, Y-offset
only) landed at x[388,512] y[674,846] - nearly identical to hers,
confirming the reported bug outright.

- **`npc_offer_card_x_offset` (new export, -150)** - the missing knob.
  The original code only offset Y, implicitly centering the card's X on
  her own, which is exactly what caused the overlap. Negative moves the
  card toward lower world x - this room's water/shore side, and the
  side away from the player's only approach direction (spawn/exit both
  sit at higher x) - clearing her sprite's own left edge with a
  confirmed ~49px gap, not just "probably clear."
- **`npc_offer_card_y_offset` corrected (-140 -> -120)** to her actual
  measured mid-height (783, i.e. -117 from her own Area2D origin,
  rounded to -120) rather than a value that happened to land in her
  figure band without being checked against her real midpoint.
- **`npc_offer_card_scale` corrected (0.5 -> 0.35)** - 0.5 (~172px)
  still read as roughly a third of the screen height; 0.35 measures
  ~121px, confirmed at 46.8% of her own height - just under half, per
  this fix's own target.
- **Composition reported (not just the fix in isolation):** at the
  moment contact fires (player at the trigger's edge, x=655), the three
  elements span world x[257, 722] roughly - card [257,343], her
  [392,520], player centered near 655-680 - each clearly separated with
  no overlap, confirmed headlessly rather than eyeballed from the
  numbers alone.
- **Left-edge/HUD clipping checked, not assumed clear:** the card's own
  left edge (257) sits well past both the room's true left edge (world
  x=0) and the playable floor's left bound (x=40) - when the player is
  this close to the left wall, the camera clamps flush against it
  (`limit_left=0`), so world x and screen x are identical in this exact
  scenario, making this check meaningful rather than approximate. The
  HUD's own `DeckButton`/`MapButton` sit at screen y 1000-1047, entirely
  below the card's own screen-space bottom edge (~480, using the fixed
  world-to-screen Y relationship this room's camera always holds) - no
  vertical proximity to worry about either.
- **`OfferLabel` flagged, not moved (per this fix's own brief).** It's
  still centered on her own X (450) exactly as before - now that the
  card sits well to her left (centered at 300) rather than underneath
  her, the label's own centering no longer relates to the card's
  position the way it read before the fix (when card and NPC nearly
  coincided). Whether that still looks right, needs to widen to also
  span the card, or needs to move entirely is a live-composition call,
  not resolved here.

Verified headlessly (8 checks): the card's actual instantiated position
matches the computed rect; it sits entirely left of her sprite with no
horizontal overlap; it stays within her vertical figure band; its
height is well under hers; and it clears both the room's left edge and
the HUD's own screen band.

**Card's internal proportions fixed - `set_scale_factor()` was never
meant to go this small (2026-08-27, same-day follow-up).** At 0.35 the
card no longer read as a shrunk hand card - the art slot's own border/
margin relationship had nearly collapsed and both fonts had rounded
down to single-digit pixel sizes. Root cause, confirmed by reading
`card.gd` rather than guessing: `set_scale_factor()` re-lays-out the
card at a new authored size (fonts, margins, badge sizes, corner radii
all multiplied by the factor), but every border width on the card face
- the outer rarity border AND the name-banner/art-slot/description-
panel borders - is a FIXED constant baked into `card.tscn`'s own
`StyleBoxFlat` resources, untouched by `_apply_layout()`. At `f=1.0` a
4px outer border against a 10px margin is a thin accent; below `f≈0.4`,
`outer_margin_px * f` drops under that fixed border - a structural
inversion, not just "things got small." Every real caller (reward
screen, shop, deck viewer) has only ever used 1.0-1.6 - nothing had
ever pushed this factor below native size before.

- **`card.gd` itself is UNCHANGED behavior-wise** - other callers
  depend on `set_scale_factor()` at their own 1.0-1.6 range, and fixing
  the re-layout math itself was out of scope. Only a comment was added
  to `set_scale_factor()` documenting the ~0.4 floor and its root cause,
  for whoever reaches for this function at a small factor next.
- **The offer card is now ALWAYS laid out at `set_scale_factor(1.0)`** -
  full, correctly-proportioned hand-card layout, unconditionally. It
  never renders "at 0.35" internally at all any more.
- **`npc_offer_card_scale` repurposed** to drive a plain uniform `scale`
  on a NEW wrapper node (`_npc_offer_card_wrapper`, a `Node2D`) instead
  of `set_scale_factor()` - the card renders smaller by being rendered
  through a transform, not by being re-laid-out smaller. Deliberately
  NOT applied to `visual` (Card's own inner Panel) - hover/armed already
  tween `visual.scale` to ABSOLUTE targets (`Vector2.ONE` at rest,
  `hover_scale`/`armed_scale` otherwise - see card.gd's own `_play_
  hover_tween()`), so a non-1.0 baseline living on that same property
  would fight those tweens outright, snapping the card to native size
  the instant it's hovered instead of popping proportionally. Holding
  the transform one level OUTSIDE `visual`, on a sibling wrapper around
  the whole Card control, lets the two scales compose multiplicatively
  instead of fighting: `wrapper.scale` (0.35) times `visual.scale` (1.0
  or `hover_scale`) is exactly the proportional pop this needed -
  confirmed headlessly at 0.385 effective scale on hover, nowhere near
  native 1.0.
- **On-screen envelope is mathematically unchanged** at the same
  `npc_offer_card_scale` value either way (`design_size * scale`, always
  was) - only what renders INSIDE that envelope changed. `npc_offer_
  card_x_offset`/`_y_offset` were RE-VERIFIED against this, not
  reflexively retuned - confirmed headlessly that the rendered rect
  lands at the exact same position or clears her sprite/the screen
  edge/the HUD by the same margins already measured in the pass above.
- **A real ordering bug surfaced while verifying this, not from
  inspection alone**: the first working version called `set_scale_
  factor()`/`set_card_data()` on the card BEFORE adding it to the tree
  (wrapper added last). Card.gd's own `@onready` vars (`visual`,
  `name_label`, ...) are null until a node is actually in the SceneTree,
  so both calls crashed partway through - `_apply_layout()`/`_update_
  display()` silently stopped at the first null access, and since
  `_ready()`'s own later `_apply_layout()` call never re-invokes `set_
  card_data()`, the card would have kept showing `card.tscn`'s own
  placeholder name/cost forever, with only its fonts/layout
  self-correcting. Fixed by adding the wrapper to `content_root` FIRST,
  then the card to the wrapper, before configuring it at all - the same
  add-then-configure order the original single-node version already
  used, just with the extra wrapper level threaded through correctly.
  Confirmed via an actual script-error crash while verifying, then
  re-confirmed clean and showing the real granted card's name/cost
  after the fix.
- **Also fixed in passing, confirmed via git history, not assumed**:
  `npc_offer_card_scale`'s own value had silently reverted from 0.35
  back to 0.5 in the immediately-prior debris-fix commit - an
  unintentional side effect of recovering a different function
  definition that had gone missing from a concurrent edit during that
  same pass, not a deliberate change. Restored to 0.35 here.

Verified headlessly (25 checks): the card lays out at full 22px/15px
fonts (not ~8px/~5px); its actual name/cost text shows the real granted
card, not `card.tscn`'s own placeholder (the ordering bug's own
regression test); the rendered envelope is pixel-identical to the
pre-fix rect; hovering pops the effective scale to ~0.385 while leaving
the wrapper's own 0.35 untouched (not jumping to native 1.0); un-
hovering returns cleanly; the card's own global transform scale (what
Godot's input hit-testing actually reads) reflects the wrapper's 0.35,
confirming the click target shrinks in lockstep with what's rendered;
and the accept/fly-away flow still frees both the wrapper and its child
card correctly.

**Larger at rest, substantial hover expansion (2026-08-27, same-day
follow-up).** 0.35 had correct proportions (the pass above) but read as
too small to comfortably read the name/description at rest, and card.
gd's own shared `hover_scale` (1.1) stacked on a 0.35 wrapper was only a
barely-perceptible 0.385 effective scale.

- **`npc_offer_card_scale` raised 0.35 -> 0.55** (~190px tall at rest,
  ~74% of her own ~258px height) - comfortably readable, at the cost of
  a tighter (but still clear, ~24px vs the old ~49px) gap to her sprite,
  confirmed headlessly rather than assumed.
- **New `npc_offer_card_hover_multiplier` (1.65), applied to the
  WRAPPER's own scale on hover** - `card.gd`'s own shared `hover_scale`
  is completely untouched (still 1.1, still drives `visual` exactly as
  it does for every other Card instance). This multiplier stacks with
  it instead of replacing it: `0.55 * 1.65 * 1.1 ≈ 0.998` - confirmed
  headlessly at 0.998, effectively native hand-card size, matching
  "roughly hand-card size" per this pass's own brief without hardcoding
  1.0 directly (a genuine multiplier on the rest scale keeps the hover
  target scaling sensibly if `npc_offer_card_scale` itself is retuned
  again later).
- **Triggered off the card's own plain `mouse_entered`/`mouse_exited`**
  (Control's built-in signals, the exact same ones `card.gd`'s own
  internal hover listener already responds to) - no new signal or
  public API needed on `card.gd`, and its behavior is genuinely
  unchanged; this pass only ADDS a second listener on the same signal.
- **Expands away from her, not into her sprite, per this pass's own
  brief** - the card's NEAR edge (the one facing her; `signf(npc_offer_
  card_x_offset)` decides which side that is, so this generalizes if a
  future NPC has the card on her other side) stays mathematically FIXED
  between rest and hover - confirmed headlessly to 5 decimal places, not
  just "close." Only the FAR edge moves, and therefore the wrapper's own
  center, computed fresh from the stored rest anchor each time rather
  than compounding off wherever a previous hover animation left off. Y
  stays centered on the rest position - nothing adjacent above or below
  her figure band needed the same treatment.
- **Smooth via the same tween-based approach, reusing `card.gd`'s own
  `hover_duration`** rather than a new export, per this pass's own
  brief - a separate `_npc_offer_card_hover_tween` (not the show/hide
  fade's own tween) drives it, so hovering mid-fade-in can't have one
  animation stomp the other.
- **Re-verified at the expanded size, not assumed still clear:** the
  hover envelope still clears her sprite (near edge, fixed, already
  clears it at rest), the screen's true left edge, the playable floor's
  left bound, and the HUD's own screen band - all confirmed headlessly
  at the LARGER hover size, not just carried over from the rest-size
  checks in the pass above.
- **A real edge case found and closed, not just handled by luck:**
  walking away while the mouse happens to still be resting over the
  card's own screen rect (camera panning usually slides the card out
  from under a stationary cursor on its own, but that's incidental, not
  guaranteed) previously would have left the wrapper stuck at its
  expanded hover scale/position, since `_show_npc_offer_card()` only
  re-fades `modulate` on a later approach, never resets the wrapper's
  own transform. `_hide_npc_offer_card()` now snaps the wrapper back to
  its stored rest scale/position unconditionally on every walk-away,
  confirmed headlessly by hovering, exiting mid-tween, and re-approaching.
- Clicking mid-hover (the ordinary way a player would actually use
  this - hovering to read, then clicking to take) is handled too: the
  accept handler now also kills any in-flight hover tween before
  starting the fly-away, so the two tweens can't fight over the same
  wrapper properties.

Verified headlessly (20 checks): rest and hover envelopes both clear
her sprite/the screen edge/the HUD; the near edge is mathematically
fixed between rest and hover while the far edge visibly grows away; the
combined wrapper + `visual` hover scale lands at 0.998 (both listeners
firing, matching real play); un-hovering returns to rest exactly; the
mid-hover walk-away edge case resets cleanly and a later re-approach
isn't left stuck expanded; and accepting mid-hover still grants the
card and frees the wrapper correctly.

**Single granted card replaced with a random pool of three (2026-08-27,
same-day follow-up).** `NPCData.granted_card: CardData` -> `granted_
cards: Array[CardData]` (the same flat-typed-array shape `CardData.
upgrades`/`EncounterData.enemies` already use for their own "reference
several resources directly, pick/use one" cases) - one entry means the
same "always this exact card" behavior as before; more means field_
room.gd rolls one at random the first time her offer shows.

- **The pick is stable for the whole visit, for free, not via new
  bookkeeping.** `_npc_offer_picked_card` (new field_room.gd var) is
  rolled (`granted_cards.pick_random()`) inside the SAME `if _npc_
  offer_card == null:` lazy-build guard that already makes the card
  NODE itself persist across a walk-away/return cycle (see that var's
  own doc) - the roll and the node's lifetime start together, so
  "stable across a visit" falls out of the existing persistence
  mechanism rather than needing its own separate state. Confirmed
  headlessly across 10 repeated walk-away/return cycles, not just once.
  Lives on field_room.gd, not on NPCData - NPCData stays the static,
  never-mutated DEFINITION of her whole pool; which ONE card she's
  actively showing this visit is interaction state, the same split this
  project draws everywhere else (EnemyData/EnemyCombatant, StatusEffect
  Data/ActiveStatus).
- **Kept out of the general reward/shop pool, not just placed
  anywhere.** `CardPool.load_class_pool()` (shared by reward_screen.gd's
  rolls and RoomState's shop stock) does a FLAT, non-recursive scan of
  `card_pool_folder`'s own `.tres` files - the same mechanism that
  already excludes `resources/cards/classes/wanderer/retired/heavy_
  blow.tres` from ever being offered. The three new cards live in a new
  sibling exclusion folder, `resources/cards/classes/wanderer/npc_
  offers/`, confirmed headlessly to be invisible to `load_class_pool()`
  - without this they'd also start appearing as ordinary card rewards
  and shop stock, not just from her.
- **Three new `CardData` resources, 1 energy each** (the shared default,
  left unset rather than redundantly authored, matching `slash.tres`'s
  own convention): **Held Position** (`BLOCK`, value 8, untargeted),
  **Second Wind** (`DRAW`, value 2, untargeted), **Left Hand** (`DAMAGE`,
  value 6, `requires_target = true`). Names are explicitly placeholders
  per this pass's own brief.
- **None of the three touch Toll or chaining, confirmed by inspection,
  not assumption**: every `CardEffect`'s own `toll_cost`/`toll_
  threshold`/`threshold_value`/`toll_gain`/`status_data` sit at their
  untouched defaults (0/0/0/0/null), and every `CardData`'s own `chain_
  role`/`chain_followup_effect` sit at `NONE`/`null` - confirmed
  headlessly per card, not just by never having typed a Toll or chain
  field into the `.tres` files.

**Flagged, not worked around: all three cards' CONDITIONAL clauses need
new battle-side infrastructure that doesn't exist today.** Per this
pass's own explicit instruction ("report anything that needs a new
effect or condition, rather than working around it") - investigated via
a fresh read of `battle.gd` rather than assumed:

- **Held Position** ("if you took no damage last turn, gain 4 more")
  needs a NEW per-turn boolean battle.gd doesn't track at all today -
  confirmed no `took_damage_last_turn`-shaped var anywhere, and no reset
  of one in `_start_player_turn()`. The existing non-Toll conditional
  precedent (Paid in Pain's own `TOLL_BLOCK`, doubling on `RunState.
  player_hp < player_max_hp * 0.5` via `_is_player_below_half_hp()`)
  proves the SHAPE (a small helper predicate + a branch in `_resolve_
  card_effect()`/`_card_condition_active()`) is a known, already-used
  pattern - this card just needs the underlying state added first.
- **Second Wind** ("if your hand is empty after playing this, draw 1
  more") needs something structurally NEW, not just a missing state
  var: every existing conditional (`TOLL_THRESHOLD_DAMAGE`, `TOLL_
  BLOCK`) checks its condition BEFORE computing the effect's value -
  none of them re-check a DIFFERENT piece of state (hand size) AFTER an
  earlier effect on the same card has already resolved, to conditionally
  chain a follow-up. `hand.is_empty()`/`hand.size()` as a card-effect
  condition doesn't appear anywhere in `battle.gd` today.
- **Left Hand** ("if this is the first card you've played this turn,
  deal 4 more") needs a NEW per-turn counter - confirmed `battle.gd` has
  no cards-played-this-turn tracking (`_play_card()` never increments
  one, `_start_player_turn()` never resets one). `turn_number` (`battle.
  gd`, incremented once per player turn) exists but counts BATTLE turns,
  not card plays within one - it can't stand in for this without a
  separate counter.
- **What's actually implemented today**: only the GUARANTEED base of
  each effect (8 block / 2 draw / 6 damage) - the conditional bonus
  clause is authored in full in each card's own `description` (matching
  this pass's own given design text exactly, one clause per line per
  this project's established convention) but does NOT currently fire in
  play. This mirrors Reckoning's own precedent (its live-updating "amount
  consumed" text was left static pending a template system that didn't
  exist yet, documented rather than faked) - the text states the
  intended design; the mechanic behind the second clause is pending the
  new state/condition work flagged above, not silently working around
  it with an ill-fitting existing effect.

Verified headlessly (50 checks): the pool holds exactly the three named
cards with the correct effect type/value/target per card; every field
that would touch Toll or chaining stays at its default; none of the
three appear in `CardPool.load_class_pool()`'s own scan; the same card
is picked and shown across 10 repeated walk-away/return cycles (not
just once); and accepting grants the exact card that was displayed, not
an independent re-roll.

**Post-interaction line added - contact after accepting no longer shows
nothing (2026-08-27, same-day follow-up).** This project's own original
choice for the already-accepted case ("show nothing... no second line
invented" - see this NPC's own earlier passes) is superseded here by
explicit request: `NPCData.post_interaction_text` (new flat `@export`,
same house pattern as `dialogue_text`) holds a SEPARATE line, not a
second read of the offer text - "here's what I'm offering" and "you've
already taken it" are different beats.

- **`_on_npc_entered()`'s already-interacted branch** (previously a bare
  `return`, showing nothing) now shows `post_interaction_text` instead
  and returns - no card, and `_npc_in_contact` is deliberately left
  null, since there's nothing left to accept and a click on her should
  just walk to her like any other interactable, not be gated by contact
  tracking that no longer means anything once she's resolved.
- **Shows every time, not once** - the branch has no first-time-only
  gate, the same "no gating" shape the original offer line's own display
  already had - confirmed headlessly across 5 repeated approaches after
  accepting.
- **Same mechanism, not a parallel one**: both lines go through the
  identical `show_offer()`/`hide_offer()` pair on `field_npc.gd` (same
  `OfferLabel`, same Spectral styling, same `offer_fade_in_sec`/`_out_
  sec` timing) - only WHICH string gets passed in differs, based on
  `RunState.npc_interacted`. `_on_npc_exited()` needed no change at all
  - `hide_offer()` already fades out whatever text currently happens to
  be showing, without needing to know which line it is.
- **Layout confirmed, not assumed**: "Still facing out." measures 135px
  wide at the label's own font/size (Spectral, 20px) against a 320px-
  wide `OfferLabel` - 42% of the available width, comfortably one line,
  no wrap. Renders centered (the label's own existing `horizontal_
  alignment`), so a short line just reads as a short centered line, not
  an oddly-empty wide box.

Verified headlessly (15 checks): the correct line shows before/after
accepting; no card appears in the post-interaction case; `_npc_in_
contact` stays null once resolved; the line reappears on 5 repeated
approaches, not just the first; both fade timings are shared, confirmed
by measuring the actual alpha after each duration; and the placeholder
text's own rendered width clears the label's width with room to spare.

**Field interactables now come in two shapes, NOT unified (2026-08-28,
wreckage heap).** `field_npc.gd` above is a one-way world-voice PROMPT -
a single decorative `Label`, with every click routed through the Area2D's
own collision shape as one whole-object click (walk-to-her if not yet in
contact, accept-via-the-offered-card's-own-click if already in contact -
never a click on her own OfferLabel). `field_heap.gd` (see the wreckage
heap's own notes) is a two-option CHOICE prompt - Sift/Leave as real
`Button` nodes, each handling its own `pressed` signal directly, because
a single decorative Label had no way to distinguish two separately-
clickable options; a click on the pile's own silhouette is now ALWAYS
just "walk toward it," never a resolved interaction, once Sift/Leave
exist to do that job instead. These two shapes were built one at a time,
for two different needs, and nothing generalizes between them yet - a
third field interactable needing a menu should look at field_heap.gd's
shape, not field_npc.gd's, but there's no shared base to inherit from
either way. Also worth noting for the same reason: `OverlayStyle.
apply_to_label()` is typed to `Label` specifically and cannot style a
`Button` - field_heap.gd's own Sift/Leave buttons read `OverlayStyle.
color()`/`outline_width` directly instead, rather than widening that
shared autoload's signature over this one case.

**Positioning is unified the same way - not unified at all (2026-08-28,
prompt-follows-player pass).** `field_npc.gd`'s own `OfferLabel` is a
flat offset baked into `field_npc.tscn`, relative to HER OWN Area2D
origin - never updated per frame, never actually tracking the player.
This is currently invisible: she's person-sized with a narrow (360px)
trigger zone, so "fixed above her" and "above whichever player happens
to be in contact" are almost always the same point in practice. It's the
exact same latent issue the wreckage heap exposed at scale - a much
larger pile with a much wider trigger zone made "fixed relative to the
interactable" and "above the player" visibly diverge, and pushed the
prompt up near the room's own ceiling besides. `field_heap.gd` was fixed
instead: it stores the player reference on contact and repositions its
own prompt every frame to a fixed clearance above their head (see its
own `_process()`/`prompt_head_clearance_px`), freezing in place then
fading once contact ends rather than continuing to chase them.
`field_npc.gd` was NOT touched - the two remain two separate techniques
solving the same problem differently (one gets away with a static offset
by virtue of scale, one can't), not a shared mechanism either could pull
from.

**The wreckage heap must appear at least once per run** (2026-08-28) -
unlike every other leftover-roll room type (COMBAT/TREASURE/EVENT), which
have no per-run minimum, only a run-wide maximum (`RunState.room_type_
max_instances`). See the Run Structure & Navigation section's own note on
`RunState.room_type_min_instances` for how this guarantee is reserved
without displacing the run's first fight or landing in a predictable
layer every time.

## Characters

Where a playable character gets a real identity - lineage, philosophy,
visual, the mechanical concepts that follow from both - before (or
instead of) code, same purpose the Bestiary below serves for enemies.
`CharacterData` (`character_data.gd`) currently holds just a name and a
`card_pool_folder` - bare mechanical scaffolding, no lore behind either
class yet (see Pillar 1). This section is for a character once it has a
real identity, starting with the first.

### The Wanderer (character one, the Wanderer class)

The in-fiction identity behind the class the code now also calls
"Wanderer" (`resources/cards/classes/wanderer/`, `RunState`'s hardcoded
default `current_class`) - renamed from the earlier placeholder
"Warrior" (2026-08-24) once code and fiction had the same name to
agree on.

**Lineage:** inspired by Dark Knights from FFXI and FFXIV. Not a
straightforward warrior - a character built around PAYING rather than
gaining. Costs are the identity, not a drawback.

**Core concepts (working list, will expand over time):**
- Lifesteal and drain effects
- Trading health for resources
- Absorbing enemy stats, or even enemy abilities
- Casting magic spells alongside melee attacks
- Heavy attacks

**Innate passive: Rally (IMPLEMENTED, 2026-08-24; corrected same day -
see below).** The first Core concept bullet above made mechanical, but
as a recoverable POOL, not flat lifesteal: unblocked damage the
Wanderer takes from an enemy attack banks into battle.gd's `rally_pool`
(fight-scoped, alongside `toll`); dealing damage recovers
`rally_recovery_percent` (a plain `CharacterData` int, 0 for the Samurai,
20 for the Wanderer - placeholder pending the enemy HP calibration pass;
briefly retuned to 50% 2026-08-25, reverted to 20% 2026-09-03) of the
damage dealt, capped at whatever's actually in the pool. Both
halves key off `_deal_damage_to_enemy()`'s `result["damage_to_hp"]`
(the recovery side) and `_enemy_attack_player()`'s own (the fill side)
- the same "not fully blocked" figure Toll/debris-spawn/Retaliation
already use, so blocked damage banks nothing. Self-inflicted damage
(Blood Tithe, a future Toll generator - `_deal_self_damage()`) and
status DoT ticks never touch `rally_pool` at all, only an actual enemy
attack does - the pool cap is what makes "no path heals the Wanderer
without a recoverable pool backing it" true structurally, not by
convention. NOT persistent: cleared at the end of the Wanderer's own
turn (`_on_end_turn_button_pressed()`, before the enemy phase that
would refill it) and on battle end (`_close_out_battle()`), on top of
the fresh-battle reset every fight-scoped var here gets - a pool that
outlived its own turn would let a single big hit's recovery linger and
fund healing across unrelated later exchanges, which isn't what "Rally"
was meant to reward.

**Correction (same day):** shipped once already as flat lifesteal -
`lifesteal_percent` healing off EVERY point of outgoing damage
unconditionally, no pool, no source restriction. That wasn't what was
specced; replaced outright (not layered on top) once caught, per this
entry's own IMPLEMENTED-then-corrected note above.

**Rally's visual: a third HP-bar zone (IMPLEMENTED, 2026-08-24).**
`rally_pool` had no visual before this - `vitals_bar.gd` gained a
RallyOverlay Panel, layered on top of HPBar's own idle background but
under BarBorder, whose left/right anchors encode `[current, min(current
+ pool, max_hp)]` as fractions of the bar's width. That range is where
HPBar's OWN fill already stops short (0..current) and its background
still shows (current..max) - RallyOverlay only ever needs to paint the
recoverable slice of that background region, so "empty/permanently
lost" (current+pool..max) needed no new code at all, it's just HPBar's
existing background left uncovered. Player-only: `show_rally_pool`
defaults false (this script is Enemy's own bar too) and only player_
battle_visual.tscn's instance sets it true - an enemy's RallyOverlay
stays permanently invisible, not an always-empty segment gated at
paint time. Color is a desaturated (not alpha-faded) variant of
whichever fill color is currently active, recomputed in `_apply_bar_
color()` so a low-HP color swap carries it along automatically -
`Color.from_hsv(h, s * rally_pool_saturation_scale, v, a)`, alpha
untouched, matching this feature's own "read as an intentional state,
not a rendering artifact" brief.

Both edges are driven by direct `tween_property()` calls on `anchor_
left`/`anchor_right` (no manual per-frame sync loop) - a recovery's HP
gain and pool shrink read as "the same motion" for free, because
`current + pool` is mathematically invariant across a pure recovery or
a pure pool-fill event (proven out in battle.gd's rally_pool doc): as
long as `update_hp()` and `update_rally_pool()` are called with the
SAME duration for the SAME event, Tween's own "animate from whatever
the property currently is" behavior makes the two edges move in
lockstep with no shared clock needed. Expiry uses a separate, longer
`rally_expire_drain_duration_sec` (0.6s vs. the ordinary 0.25s) so the
drain reads as its own deliberate, noticeable moment - that's the
animation meant to teach a player the window exists at all. Battle-end
reset is a hard snap, no tween, per spec ("the bar is going away
anyway").

Self-damage (Blood Tithe) needed no dedicated call site: `_update_
player_panel()` (battle.gd's one shared "player HP/block panel
changed" hook, already called by `_deal_self_damage()`/a status tick/
everywhere else HP moves) now also re-anchors RallyOverlay from
whatever `rally_pool` currently is - since self-damage never touches
`rally_pool`, recomputing from the newly-lower `RunState.player_hp`
against the SAME pool correctly shrinks the recoverable ceiling
(shifts both edges left together, same width) rather than leaving a
stale, now-wrong faded segment behind. `_enemy_attack_player()` is the
one exception needing its own explicit second push, since its existing
`_update_player_panel()` call fires BEFORE `rally_pool` actually grows
(pre-existing code shape, not changed for this feature) - see that
function's own note.

Verified headlessly: an enemy's RallyOverlay never becomes visible; a
fully-blocked hit leaves the overlay collapsed; an unblocked hit's
overlay bounds match `[hp, hp+pool]` exactly; self-damage shrinks the
ceiling by the self-damage amount without growing the pool; a full
recovery collapses the overlay while leaving its right edge (the
ceiling) unchanged; and letting the window lapse visibly animates the
overlay down to collapsed over the drain duration, not instantly.

**Design implications already visible:**
- The chain system (Opener/Closer - see Open Questions' Combat tempo
  note) is a natural fit for the melee/spell split - one category could
  open, the other close, making chaining express the character rather
  than sitting on top of it. Not yet decided which way.
- An attack that costs the caster HP as part of its normal price (not a
  debuff, not a drawback bolted onto an otherwise-normal card) is this
  character's philosophy in miniature - the shape Reckless Swing used to
  have, before that specific card was deleted (2026-08-23, alongside the
  rest of an early AI-generated batch - see the Starting deck note
  above) as generic filler, no identity behind it yet to justify it. The
  pattern came back for real as **Overreach** (2026-08-24, `resources/
  cards/blood_tithe.tres`) - the starting deck's identity-card slot (see
  the Starting deck note's own DECIDED entry), not a reward-pool
  build-around: 1 energy, 10 damage, lose 2 HP (tuned up from 8,
  2026-08-27). Originally shipped with
  `chain_role = CLOSER` and a refund payoff; REMOVED (2026-08-26) - see
  "Bite Down's chain payoff: REVERSED" below for why. Today `chain_
  role` is `OPENER` (the test Opener): Bite Down opens a chain but
  carries no payoff of its own, and always costs its 2 HP when played,
  chained turn or not.
  Deliberately renamed rather than reusing "Reckless Swing" as-is - that
  name describes carelessness, not deliberate payment, and read as
  exactly the generic-fantasy vocabulary this pass was already trying to
  move away from. Tuned down hard from the original 14 damage (`Reckless
  Swing`'s number, at 1 energy with no chain role at all) - a guaranteed
  starter card needed real restraint, not a reward-pool power level.
  Itself renamed again (2026-08-27) from "Blood Tithe" to "Overreach" -
  same card, `card_name` and the resource FILENAME both updated to
  match (was `blood_tithe.tres`, now `resources/cards/overreach.tres`,
  matching the existing filename-follows-card_name convention `heavy_
  blow.tres`/`kept_warmth.tres` already use); every mention of "Blood
  Tithe" throughout this doc, including historical/superseded write-ups
  below, has been updated to match rather than left inconsistent.
  Renamed a third time (2026-08-28) from "Overreach" to "Bite Down" -
  same card, `card_name` and the resource FILENAME both updated again
  (now `resources/cards/bite_down.tres`); every mention of "Overreach"
  throughout this doc has been swept to match, same as the prior rename.
  Standalone it already beats Heavy Blow's own rate (10 dmg/energy vs.
  6), which is the point: the difference is what the HP pays for.
- **Bite Down's chain payoff: REVERSED (DECIDED, implemented
  2026-08-26).** The refund below was removed - Bite Down is no
  longer a Closer (`chain_role` is `OPENER` now, the test Opener, with
  no payoff of its own), has no `chain_followup_effect`, and its 2 HP
  cost is unconditional now, chained turn or not. Kept the write-up
  below as a record of what was tried and why it didn't hold up, but
  none of it describes current behavior.

  **Why:** a chain payoff that refunds a card's OWN cost makes the
  UNCHAINED version feel like a mistake rather than a choice - "I
  should have set this up first" instead of "I chose to pay for this
  now." That's backwards from what Bite Down exists to teach: the
  Wanderer pays for power, full stop, not "pays for power unless
  sequenced correctly, in which case it's free." A cost that can be
  played around into non-existence stops functioning as the
  character's identity and starts reading as a puzzle to solve around
  it. Bite Down's cost should always be paid - every play of the
  card should cost 2 HP, no exceptions, no "correct" way to avoid it.
  The chain system itself isn't the problem (Heavy Blow's bonus-damage
  payoff has no such issue - it never made an ALTERNATIVE version of
  itself feel like a mistake, since Heavy Blow doesn't have a
  cost to escape from), only pairing that specific reward SHAPE with a
  card whose whole point is an unavoidable cost.

  **Future direction:** an interaction with HP-cost cards (reducing,
  refunding, or converting the cost) may fit better on WEAPONS or other
  cards than on the paying card's own chain payoff - see DESIGN.md's
  Equipment note. As a build CHOICE the player opts into (equip a
  weapon that does this), rather than a rule baked into the card
  itself, the same refund idea stops teaching "this cost isn't real"
  and starts reading as "I built around this cost on purpose." Nothing
  currently implements this; it's a direction for whenever equipment
  gets its own real design pass, not a TODO for the card itself.

  --- Historical implementation notes (superseded, kept for context) ---

  Every other Closer's chain payoff (Heavy
  Blow's, and the shared default before this existed) is a flat bonus
  hit - Bite Down's is the 2 HP it costs coming back. Chained, it's a
  wash: pay 2, get 2 back. Unchained, it costs HP for real. This makes
  the card's identity and its chain payoff the SAME idea, not two
  unrelated systems bolted together - a Dark Knight's sacrifice,
  performed correctly (i.e., sequenced), doesn't cost him. It rewards
  sequencing with SUSTAIN rather than raw power, which is what actually
  creates a real decision each time the card is held: play it now and
  bleed for the damage, or wait for the setup and pay nothing. It also
  deliberately does NOT stack another damage number onto an already
  strong card - see the corrected chain math right above, now 14 rather
  than 22 - keeping the "restraint" reasoning that picked 8 damage in
  the first place intact rather than undermining it with an even bigger
  chained total.

  Implementation note: no separate "ChainEffect" resource exists (an
  earlier framing of this request assumed one already did) - what
  actually exists, and what this reuses, is `battle.gd`'s own shared
  chain-payoff mechanism, generalized from "one hardcoded bonus-damage
  CardEffect for every Closer" to a new `CardData.chain_followup_effect:
  CardEffect` field, read instead of the shared default when a Closer
  sets one (null - Heavy Blow - falls back to the old shared behavior,
  completely unchanged). A refund needed zero new EffectTypes: HEAL
  already existed, so Bite Down's payoff is just a HEAL-type
  `CardEffect` for 2, the same vocabulary every other card effect
  already uses - proving the point requested here, that the mechanism
  supports varied payoffs as DATA, not as a special case in code. Fixed
  one real bug surfaced while wiring this in: the payoff's old "skip if
  the target's already dead" guard was written assuming every payoff
  hits the enemy, which stopped being true the moment a payoff could be
  about the PLAYER instead - left as-is, a lucky overkill would have
  silently denied Bite Down's refund for the crime of dealing enough
  damage, exactly backwards. Scoped the guard to DAMAGE-type payoffs
  specifically; a refund now fires regardless of the target's state.

  Feedback treatment: the HP cost is genuinely PAID first (SELF_DAMAGE
  resolves immediately, same as unchained), then the payoff refunds it
  ~0.3s later (the same delay every chain payoff already uses) - a
  visible drop-then-recovery, not a cost that silently never applied.

  **Correction after playtesting (DECIDED, implemented 2026-08-24):**
  the first version's refund played a small amber burst at the player's
  vitals bar, matching the enemy-side chain burst's own language - but
  this read as a UI effect happening near a number, not as something
  happening to the CHARACTER. Replaced with two purpose-built, character-
  centered reactions on `PlayerBattleVisual` (`player_battle_visual.gd`),
  deliberately built to never look alike despite both being red/blood-
  toned rather than the old amber - motion and WEIGHT differ, not just
  color:
  - `play_hp_cost_flinch()` - the unchained (or chained-but-not-yet-
    refunded) cost: the character's own visual pulls slightly inward
    (scale down) and darkens (a dark red tint), then releases back -
    blood draining OUT, reading as loss. No extra shape, just the
    figure itself reacting - generic over any `SELF_DAMAGE` effect, not
    Bite-Down-specific code, called from `battle.gd`'s `_deal_self_
    damage()`.
  - `play_chain_refund_aura()` - the chain payoff specifically: a red
    aura (a `Polygon2D` circle, sized to envelop the rendered figure,
    not the tiny pre-scale one) pulses OUTWARD and brightens around the
    character a few times before fading - blood staying in/returning to
    the body, reading as gain. An entire extra glow shape only the
    refund gets, on top of (not instead of) the flinch's own darkening
    logic never running for this path - only ever called from `battle.
    gd`'s `_heal_player()` when `chain_payoff` is true.

  The refund's floating number is still recolored, but to a solid red
  (`battle.gd`'s `CHAIN_REFUND_NUMBER_COLOR`) matching the aura's own
  family instead of the old chain amber - this fully commits to "blood,"
  not "generic chain bonus," diverging on purpose from Heavy Blow's own
  bonus-damage payoff, which still reads amber. `chain_refund` (the sfx
  layered on top of the normal `heal` cue) is now a real file - a
  heartbeat, not an impact, sourced to `assets/audio/combat/hp_loss_
  card_heartbeat.mp3`. The unchained cost's own sound is untouched (see
  `_deal_self_damage()`'s own `damage_player` call) - only the CHARACTER
  gained a reaction, not a new sound, keeping the "cost" side reusing
  what it already had. Every color/scale/radius/pulse timing/duration
  value on both functions is `@export`ed for tuning, same as the rest
  of this game's hand-tuned visual language.

  Verified headlessly, not just written: unchained Bite Down costs 2
  HP with no refund, and correctly plays ONLY the flinch (character
  pulls inward and darkens mid-tween, settles back to neutral after, no
  aura shape spawned at all); chained, the player's HP returns to
  exactly its pre-card value and spawns exactly one aura polygon whose
  color/radius match the exported values precisely; Heavy Blow's own
  chain (still bonus damage) is completely unaffected by any of this;
  and the overkill/defeated-target edge case from the original
  implementation still holds - Bite Down's refund still fires when its
  own hit finishes the enemy, while Heavy Blow's bonus damage still
  correctly skips a target that's already dead.
- Kept Warmth (`kept_warmth.tres`, ULTRA_RARE, restores 25 HP) means
  more in a character where healing is deliberately scarce - a rare,
  precious reprieve rather than a routine tool, which only works if
  most of the kit really does spend HP as freely as this pillar implies.

**Visual:** cloaked figure, hooded, face not visible. Something odd is
under the hood - this is a deliberate story hook and should NEVER be
explained. Consistent with Pillar 4(b) - lore lives in implication, not
exposition.

**Future structure:** classes will eventually support multiple builds
within them, so card design should leave room for divergent paths
within a single character rather than one linear identity - a card list
that only ever adds up one way isn't ready for that yet.

**Concepts to explore (UNVETTED - conversation starters, not a
roadmap):** all of the below needs discussion with my brother before
any implementation.

- Cards that get stronger as HP drops. Classic Dark Knight territory
  (FF's Darkness scaling at low health). Makes the attrition economy
  load-bearing: a run where you're bleeding becomes simultaneously more
  dangerous and more powerful. Genuine tension rather than a flat
  resource cost.
- Absorbed abilities that persist past the fight. If stealing enemy
  abilities is on the table, the most interesting version is one where
  what you took STAYS - the deck carries a mark from the creature you
  killed. Mechanics as memory, which fits the world's preoccupation with
  what's left behind.
- Costs that aren't HP. Card exile, forced discard, energy debt next
  turn, self-applied debuffs. Dark Knights pay in various currencies;
  varying the currency keeps "everything costs something" from becoming
  monotonous.
- A resource unique to the Wanderer. Pillar 1 already notes characters
  may have distinct resource systems. Something accumulated by paying
  and spent on spells (working ideas: drained essence, accumulated
  dread) would make the melee/spell split mechanical rather than
  cosmetic.
- Spells cost health, attacks restore it. The cleanest expression of the
  loop: swing to sustain, cast to spend. Gives every turn a natural
  rhythm and makes the melee/spell distinction matter in every hand.
  Currently the most immediately buildable of these.

**Guillotine (IMPLEMENTED, 2026-08-23) - a second Closer, replacing Heavy
Blow in the pool:** cost 2, deal 4 damage 3 times (three separate
`DAMAGE` `CardEffect`s, not one combined 12 - the player sees three
hits land, same as any other multi-effect card). Common, same tier
Heavy Blow held. `flavor_text` (never rendered in play - see that
field's own doc): "It doesn't ask twice. It falls, and it doesn't
stop." Heavy Blow itself moved to `resources/cards/classes/wanderer/
retired/` rather than being deleted - the exact same "non-recursive
folder scan excludes it, history stays on disk" precedent the retired
Thicket Stalker enemy already established, not a new convention.

**Its chain payoff, Stoppage, is a genuinely reusable resource, not a
value inlined into the card:** lives as its own standalone `.tres`
(`resources/chain_payoffs/stoppage.tres`), referenced by `CardData.
chain_followup_effect` the same way any other Closer's payoff already
is - a FUTURE Closer's own `chain_followup_effect` can point at this
exact same file. Required a new `CardEffect.EffectType.STUN` (`value`
unused, same "ignored for this type" shape `TOLL_DAMAGE` already
established) and a new `CardEffect.combat_message: String` field, read
only by `STUN` - deliberately NOT named `flavor_text`, since `CardData.
flavor_text` already means the opposite (never shown in combat); this
one is specifically FOR combat display, so sharing the name would have
read as a contradiction of that rule.

**Reuses the Wardling's own pain-turn mechanism exactly, not a parallel
implementation - required a small rename, not a rewrite:** a stun
cancels the target's queued intent for its next turn, which is
precisely what the Wardling's below-50%-HP pain turn already does (see
its own entry below). Before this, every piece of that mechanism was
named "pain turn" specifically - `EnemyCombatant.pain_turn_pending`,
`Enemy.show_pain_turn()`/`play_pain_flinch()`, `IntentDisplay.show_
pain()`, six `@export` tunables - which would have meant a Guillotine
stun literally calling a function named `show_pain_turn()`, reading as
a lie in the code. Renamed the SHARED parts to generic vocabulary
(`intent_interrupted_pending`, `show_intent_interrupt()`/`play_
interrupt_flinch()`, `show_interrupted()`) with a new shared entry
point, `battle.gd`'s `_apply_intent_interrupt(target, message)`, called
by both `_check_pain_turn_trigger()` (the Wardling's own HP-threshold
path, completely unchanged in behavior) and `_resolve_card_effect()`'s
new `STUN` case. `EnemyCombatant.pain_turn_used` - the Wardling's own
"exactly once per fight" guard - deliberately did NOT get folded into
the shared flag: a chain-payoff stun has no such limit of its own
(Guillotine can stun again every time it's chained), and sharing the
guard would have wrongly coupled two unrelated mechanics (a card stun
blocking, or being blocked by, the Wardling's real pain turn). The
"corpse doesn't get hit again" guard on chain payoffs (`_trigger_chain_
payoff()`) extended from DAMAGE-only to DAMAGE-or-STUN, for the same
reason it already existed for DAMAGE - a stun has nothing left to
cancel on a dead enemy.

The new sound (`AudioManager`'s `"chain_stoppage"`, `combat/guillotine.
wav`) plays ONLY at the `STUN` call site in `_resolve_card_effect()`,
not inside the shared `_apply_intent_interrupt()` - the Wardling's own
pain turn has never had a sound, and putting it in the shared function
would have silently given it one just because a second, unrelated
trigger now also reaches the same code. "Don't change the Wardling's
existing behavior" held literally: nothing about ITS trigger, guard, or
presentation gained anything new.

**Verified headlessly:** Guillotine's own data (3x4 `DAMAGE`, `CLOSER`,
`chain_followup_effect` pointing at the real Stoppage resource,
mechanical-only `description`); the pool swap (Heavy Blow out,
Guillotine in, via `CardPool.load_class_pool()`); played chained - all
3 hits land, Stoppage sets the interrupt flag, no extra damage from the
stun itself, and the target's own attack that turn is genuinely
cancelled (player takes no damage); played unchained - the same 3 hits
land with no stun triggered at all; and, as a regression check, the
Wardling's own pain turn fired via its real HP-threshold path exactly
as before - `pain_turn_used` set, the shared interrupt flag set by ITS
trigger, its own attack cancelled - completely unaffected by the rename.

**Its own play sound, not just the chain payoff's (2026-08-23):** new
`CardData.play_sfx: String` (empty = every other card, plays the shared
generic `"card_play"` cue exactly as before - same "empty means no
effect" shape `EnemyData.attack_impact_sfx` already established for the
enemy-attack-lands equivalent), read by `battle.gd`'s `_play_card()`.
Guillotine sets it to `"guillotine_play"` (`combat/guillotine.wav`) -
its own heavier cue the instant it's played, separate from `"chain_
stoppage"` (`combat/stoppage_chain.mp3`), the different cue for its
chain payoff landing a beat later. Verified headlessly: Guillotine's own
override resolves to a real file; an unrelated card (Slash) still
falls through to the shared cue, unaffected.

**Its 3 hits land staggered, not all at once (2026-08-23):** new
`@export var multi_hit_delay_sec: float = 0.15` on `battle.gd`, same
"distinct hit, not its own big beat" register `weapon_reflect_delay_sec`
(also 0.15s) already established - meaningfully shorter than `chain_
payoff_delay_sec` (0.3s), since these are three pieces of ONE strike in
a flurry, not separate beats the way a chain payoff is its own moment.
`_apply_card_effects()` (now async) inserts the gap only BETWEEN two
consecutive hit-type effects (`DAMAGE`/`TOLL_DAMAGE`) - checked on both
the current and the next effect, so an unrelated pair (Riposte's block-
then-strike, Bite Down's damage-then-self-damage) stays exactly as fast
as it's always been; only a card with two hit effects back to back
gets the new gap at all, and Guillotine is the only one today.
`_play_card()` now awaits it (previously fire-and-forget) specifically
so a chain payoff can't start until every one of the card's own hits
has actually landed - energy/hand/pile state was already applied
synchronously before that point, so only the trailing label refreshes
and the payoff wait on the stagger, nothing a player could exploit by
clicking mid-sequence. Verified headlessly: calling the (now-coroutine)
effects resolver without awaiting it lands exactly the first hit
synchronously, real wall-clock time elapses between each subsequent
hit (measured via `Time.get_ticks_msec()`), Riposte/Bite Down/Slash
are provably unaffected, and a chained Guillotine's payoff still only
triggers after all 3 hits are confirmed landed.

**The gap widens into the third hit (2026-08-24):** the uniform 0.15s
gap made the third hit land too fast, on top of the second. New `@export
var multi_hit_delay_extra_sec: Array[float] = [0.1, 0.3]` on `battle.gd`
- per-GAP additions on top of `multi_hit_delay_sec`, indexed by which
gap it is (0 = hit 1->2, 1 = hit 2->3). Total gaps: 0.25s then 0.45s -
the strike gathers weight into its last hit rather than landing as three
identical, evenly-spaced pieces. `_apply_card_effects()` now counts GAPS
with its own `hit_gap_index` (not effect array indices), so it stays
correct even for a hypothetical future card mixing hit and non-hit
effects. Global on `battle.gd`, same shape `multi_hit_delay_sec` itself
already has, not a new per-card-authored field - only Guillotine has
this shape today, so in practice this IS Guillotine's own rhythm.
Verified headlessly (7 checks): the exact expected gap durations,
neither hit landing early, and each landing once its own real gap has
actually elapsed.

**Reworked from 3-hit to single-instance (2026-08-26):** `3x4 DAMAGE`
(above) became one `14 DAMAGE` `CardEffect`; `description` changed from
"Deal 4 damage, 3 times." to "Deal 14 damage." Cost, `CLOSER` chain
role, and the Stoppage chain payoff are all untouched. Reason: multi-hit
and a chain payoff are two separate combo identities competing on one
card - when Stoppage's stun lands, a player has no way to tell whether
it's the chain completing or just the third hit connecting. A single
instance reads as a finishing blow (matching the card's own name) and
frees multi-hit up as its own distinct design space for a future card,
rather than something Guillotine happens to also do.

`multi_hit_delay_sec`/`multi_hit_delay_extra_sec` (both above) are left
in place, unchanged, as general `battle.gd` infrastructure - no card
exercises them today, but they were never Guillotine-specific code, only
Guillotine-shaped data. `_apply_card_effects()`'s own stagger logic
still fires correctly for any future card with two-or-more consecutive
`DAMAGE`/`TOLL_DAMAGE` effects; it simply has nothing to stagger for
Guillotine's own new one-effect shape.

New sound: `combat/Guillotine.mp3` replaces `combat/guillotine.wav`
(deleted) as `"guillotine_play"`'s file in `AudioManager.SFX_FILES` -
the old cue was cut for a 3-hit flurry, this one for a single heavier
blow. Its volume trim reset to 0.0 (the old -1.94dB was tuned by ear for
the old file specifically) pending a real in-game listen. `combat/
multi_hit_attack.wav` was added in the same pass and is NOT wired to
anything yet - reserved for whichever future card actually reintroduces
a multi-hit shape.

**Wind-up added: `CardData.impact_delay` (2026-08-27), Guillotine sets
0.5s (raised same day from an initial 0.2s, which read as too quick to
register as a wind-up once seen live):** with the hit back down to one
instance, an instant number read
as weightless for what's meant to be a finishing blow. New optional
`@export var impact_delay: float = 0.0` on `CardData` - 0.0 (every card
except Guillotine) is exactly today's behavior, nothing changes until a
card sets it. `battle.gd`'s `_play_card()` still fires the player's own
step-forward nudge immediately regardless (it's the swing, not the
impact - has to start right away to fill the gap before the hit lands),
but now only fires the card's `play_sfx` immediately when `impact_delay
<= 0`; a nonzero delay defers that same sound into `_apply_card_
effects()`, which waits it out ONCE before touching the effects list at
all (not per-effect, not per-target - structurally impossible to repeat
per hit, since there's no per-hit path left for it to live on), then
fires the sound right before resolving the first effect. Damage number/
HP change/hit reaction were already synchronous inside `_resolve_card_
effect()`/`_deal_damage_to_enemy()` with no `await` between them, so
gating the whole resolution on one upfront wait is what makes all four
(sound included) land on the same frame, and the existing `await
_apply_card_effects(...)` in `_play_card()` (there since the 3-hit
stagger) is what already holds `_trigger_chain_payoff()` back until
after the delay elapses too, for free - no new code needed at that call
site. The enemy-death check (`_deal_damage_to_enemy()`'s own trailing
`if target.hp <= 0`) was already the last thing in that same
synchronous chain, so a killing Guillotine hit was never at risk of
triggering the death animation before the hit itself registered.
Verified via a real headless battle instantiation (not just static
reading, at the original 0.2s value - the mechanism is a single
timer read from CardData, so the later 0.5s retune changes nothing
about which numbers below would shift): the nudge tween exists
same-frame, HP is provably unchanged same-frame, impact lands ~170-180ms
after play (target 200ms, well within frame-timing variance), a chained
Guillotine's stun applies at ~490ms (impact_delay 0.2s + the existing
chain_payoff_delay_sec 0.3s), strictly after the impact - and Slash
(impact_delay 0.0) still changes HP on the exact same frame it's played,
confirming every other card's
timing is untouched.

## Bestiary

Where a creature gets a real identity - concept, tone, silhouette, lore,
behavior - before (or instead of) code. Thicket Stalker and Glasswing
(see Run Structure & Navigation's enemy silhouette work) are visual
shapes with no designed identity behind them yet; this section is for
enemies that have one, starting with the first.

**Design test for every entry here:** if a detail makes the creature more
monstrous, it is probably wrong; if it makes it more wretched, it is
probably right. This is Pillar 4's hard-but-fair/not-grimdark stance and
the aesthetic pillar's beautiful-but-lonely tone (see open question 1),
translated into a rule for designing a specific creature rather than
staying an abstract stance about the whole game.

### The Tideworn (opening room)

**Concept:** not a living creature in the normal sense - driftwood,
shell fragments, kelp, scraps of something man-made, shaped and
assembled by the tide over time into a form that moves. It has no
intent the way a predator or the Wardling does; it's closer to a
natural process that happens to be hostile, like a tide pool that
occasionally lurches.

**Tone register:** deliberately distinct from the Wardling's
pitiable-and-unsettling register (see the design test above, and the
Wardling entry below) - not sad or desperate, just strange and quietly
uncanny. Passive erosion and accumulation, not abandonment. Where the
Wardling is a thing that was left behind, the Tideworn was never
anything to begin with - it assembled itself out of whatever the tide
brought in. Nothing to grieve, nothing to pity; just something the sea
occasionally does.

**Silhouette direction:** low and wide (beach-bound, not upright) - a
deliberate contrast with the Wardling's tall, too-thin verticality.
Asymmetric in a way that reads as ASSEMBLED rather than grown: one side
longer than the other, jagged where the Wardling was smooth-but-wrong.
Wrongness lives in MATERIAL rather than proportion - a few small
color-variant fragment shapes layered together (driftwood brown, pale
shell-white, dull kelp-green) rather than one solid silhouette fill,
selling "made of disparate pieces" the way the Wardling's silhouette
sells "starved" through proportion alone. Same "original hand-drawn
shapes, not sprites" visual language as every other silhouette (see Run
Structure & Navigation's enemy silhouettes note) - a direction for that
treatment, not a departure from it.

**Combat concept (DECIDED - implemented):** simple and legible, erratic
rather than escalating - a deliberate departure from the Wardling's
escalating-desperation pattern (see its own Combat concept below),
since this creature has no throughline of desperation to escalate.
Three intents - a strong 9-damage attack, a weak 4-damage attack, and a
genuine do-nothing "idle" turn (see the guardrail notes below for why
three, not two) - picked completely independently each time (repeats
allowed except for idle immediately after idle), rather than stepping
through a loop the way every other enemy's `intents` array does. This needed a genuinely new mechanism,
not just new numbers: `EnemyData.erratic_intent_selection` (see enemy_
data.gd) opts an enemy out of `battle.gd`'s normal fixed-loop advance
and into a fresh random pick instead, both for the very first intent
shown at spawn and every advance after - every other enemy defaults
this off and is completely unaffected. The unpredictability is entirely
about SEQUENCE, never about hidden information - the number shown is
always the number that resolves (see Combat Telegraphing below); what's
unknown is only which of the two faces comes up next.

Originally shipped as a 3-damage attack against a 4-block defend -
playtesting showed this was toothless (a single 5-block Guard already
covered the attack with room to spare, so the fight could be won by
autopiloting Slashes without ever reading the intent number) and the
defend turn just made the fight drag without adding threat. Retuned so
the creature carries exactly ONE real lesson - unpredictable AND
capable of actually hurting you - rather than diluting it across two
harmless turns:
- **Attack: 3 → 9** (briefly retuned to 7 on 2026-08-27, reverted back
  to 9 the same day). Not a new power level for the bestiary - Glasswing
  (the very next early-tier enemy, 26 HP) already uses a 9-damage spike
  turn in its own fixed pattern. Against a single Guard (5 block), 9
  leaves 4 unblocked - a real, felt cost for assuming block covers it,
  not a rounding error. Unblocked entirely, it's ~13% of the player's
  70 max HP - noticeable, not swingy for an opening fight.
- **Defend → Idle.** The flavor line ("Sags. Something shifts loose,
  then settles.") already read as the creature losing cohesion rather
  than a deliberate guard - now that's mechanically true too: nothing
  is gained, nothing lands, the flavor line carries the whole beat on
  its own. Needed a real (if small) new mechanism rather than just
  setting DEFEND's value to 0 - a shield icon showing "0" would read as
  a display bug, not a deliberate beat (see BlockBadge's own "never
  show a null state" instinct elsewhere in this codebase). `EnemyIntent.
  IntentType` gained a third case, `IDLE` (see enemy_intent.gd) -
  `IntentDisplay.show_intent()` shows neither icon nor number for it
  (the same blank treatment `show_pain()` already used for the
  Wardling's pain-turn beat), and `battle.gd`'s resolution `match` on
  intent type needed no new code at all - an unmatched case in a
  GDScript `match` with no `_:` branch is already a safe no-op, which
  is exactly "genuinely isn't there."
- **20 HP → 24.** Not solving for total fight length (the player's own
  damage output didn't change) but for making sure the erratic pattern
  actually gets SEEN - at 20 HP, a strong opening hand (3 Slashes = 18
  damage) left the Tideworn at 2 HP after turn one, meaning a second
  good turn could kill it before a second enemy turn ever happened. A
  creature whose whole purpose is teaching "read the intent, don't
  assume you're safe" failing to ever show its punishing side to a
  confident player defeats the point. 24 HP survives an 18-damage alpha
  strike, guaranteeing at least one enemy turn always happens, while
  still clearing in the same 2-3 rounds this room already targeted.
  Stays below Glasswing's 26 - still the lowest HP in the bestiary.
  **Since revised further** (untracked in this doc at the time, then
  buffed again 2026-08-27): current `max_hp` is 50, well above
  Glasswing's 26 - the "lowest HP in the bestiary" framing above no
  longer holds. Re-tune the felt-math above against 50 (not 24) if
  revisiting this fight's pacing.

Verified via headless screenshot (both intents shown correctly - blank
idle beat with flavor line, "9" attack with icon) and by resolving each
directly: an idle turn changes neither player HP nor block; an attack
turn against 5 block lands for exactly 4 damage and consumes the block
to 0, confirming the math (and the honest telegraphing) end to end.

**No-consecutive-idle guardrail (DECIDED - confirmed via simulation):**
even at a fair 50/50 pick, playtesting showed idle could still come up
often enough in a row that a confident player could clear the fight
without the 9-damage turn ever landing - the lesson only works if the
threat shows up at a guaranteed minimum rate, not just "on average."
`_advance_enemy_intent()`'s erratic branch now calls a small helper,
`_pick_erratic_intent_index()`, which excludes IDLE-type intents from
the candidate pool ONLY when the intent being left was itself IDLE -
every other transition (attack-into-attack, attack-into-idle, idle-
into-attack) stays a free, unweighted pick. This is a property of
erratic selection generally, not a Tideworn-specific special case (any
future erratic enemy with an IDLE intent gets the same guarantee for
free) - and it deliberately does NOT touch the very first intent shown
at spawn (`_spawn_enemies()`'s own pick), which has no "previous" turn
to constrain against.

The constraint has an unavoidable side effect worth naming rather than
fighting: forbidding idle-after-idle changes the natural long-run idle
frequency from 50% to 1-in-3 (a two-state Markov chain where idle can
only be reached from attack, at 50%, while attack is reachable from
both states) - this is the mathematical minimum needed to guarantee
"never two idle turns in a row," not extra suppression stacked on top
of it. Confirmed empirically two ways: an isolated 4,020-turn
simulation across 20 chains (zero consecutive-idle violations, idle
frequency 0.339 - within noise of the theoretical 0.333) and 96 turns
across 6 real, full battle instances driven through the actual
`_advance_enemy_intent()` path rather than the picker in isolation
(zero violations, idle frequency 0.354).

**A third intent, to keep the guardrail from being too easy to read
(DECIDED - confirmed via simulation):** with only idle/attack, the
no-consecutive-idle rule above had a side effect nobody wanted - a
collapse turn now GUARANTEED the very next turn was the 9-damage hit,
which a player learns after one fight and then plays around perfectly,
defeating the point of "erratic." Added a second attack intent at
value 4 (comfortably under a single Guard's 5 block, distinct from both
idle's 0 and the strong hit's 9) so a collapse turn now guarantees only
that A hit is coming, not WHICH one. `_pick_erratic_intent_index()`
needed no changes at all - it was already generic over however many
intents exist; this is purely a data change (a third `EnemyIntent` in
`tideworn.tres`). Uniform (unweighted) selection among the three
outcomes was kept rather than hand-weighting them, since the resulting
stationary distribution already favors the lesson without any tuning:
idle 25%, weak attack 37.5%, strong attack 37.5% - a HIGHER strong-hit
rate than the old two-state design's 33%, because a third state dilutes
idle more than it dilutes attack. Confirmed via a 6,020-turn synthetic
simulation (idle 0.248, weak 0.383, strong 0.369 - matches theory
closely, zero consecutive-idle violations) and a "turns until the first
9-damage hit" study across 2,000 fresh-spawn trials (average 1.62
turns; 76% of fights see it within the first two turns, which covers
the fight's typical length at 24 HP).

**Role:** the guaranteed enemy in every run's prepended opening room
(layer 0 - see Run Structure & Navigation's Opening room note) - the
first thing a new run shows the player. Lives in its own
`resources/enemies/opening/` subfolder rather than alongside every
other enemy, so `EnemyPool.pick_random()`'s flat folder scan can never
roll it as an ordinary random encounter anywhere else in the run - this
room is the only place it exists.

### The Unrelieved (industrial/space room, EXPERIMENTAL)

Parallel to The Tideworn above - see Run Structure & Navigation's
industrial opening-room prototype note for the room this creature
belongs to.

**Concept:** not suffering, not confused - a sentry still executing its
original duty long after whatever it was built to guard against is
gone. Its wound is obsolete duty, not abandonment or decay: it cannot
recognize that its purpose ended, and it functions correctly, which is
precisely what makes it unsettling rather than pitiable.

**Tone register:** distinct from both the Wardling (pitiable-and-
unsettling, desperate - see its own entry below) and the Tideworn
(impersonal, uncanny through strangeness - see above) - cold, precise,
unwavering. Nothing to grieve, and nothing to pity in the way the
Wardling asks for pity: a machine correctly carrying out a pointless
order isn't tragic the way a starved, abandoned creature is. It's just
wrong in a way that has no author left to blame and no closure to
offer.

**Rhythm as design signature (DECIDED - bestiary-wide pattern,
implemented):** where the Wardling escalates (climbing dread) and the
Tideworn is erratic (chaos - see its own Combat concept), the
Unrelieved repeats a perfectly fixed intent pattern with total,
mechanical regularity - no variation, no escalation, the exact same
sequence every time. This makes it the safest fight in the bestiary
mechanically (fully predictable, nothing to read or adapt to turn over
turn) - a real design constraint, not an oversight: this creature can't
lean on any of the tricks the other two use to be unsettling, so unease
has to come entirely from voice and precision instead of
unpredictability. Together the three enemies establish three distinct
rhythms as a deliberate, whole-bestiary pattern: climbing dread, chaos,
cold repetition.

20 HP, two 3-damage attacks and one 4-block defend, in a fixed 3-step
loop - deliberately the SAME difficulty tier as the Tideworn (also 20
HP/3-damage), a parallel opening encounter, not a harder or easier one.
The "fixed" part needed no new mechanism at all, unlike the Tideworn's
erratic pick or the Wardling's escalation multipliers - it's simply
`EnemyData.erratic_intent_selection` left at its default `false` and
`escalation_multipliers` left empty, the same untouched fixed-loop
advance (`battle.gd`'s `_advance_enemy_intent()`: index+1, wrapping)
every enemy already had before either of those two mechanisms existed.
Verified headless across 11 advances: the sequence is exactly
0,1,2,0,1,2,... every time, never varying.

**Silhouette direction:** angular and vertical where the other two are
organic - hard edges, geometric, unnaturally symmetrical stillness
between actions (no idle bob/wobble the way the Tideworn/Wardling both
have - the stillness itself should read as the wrongness, the same way
the Tideworn's wrongness lives in material and the Wardling's in
proportion). A single point of "attention" (a light, a sensor) as the
only expressive element on an otherwise faceless form - matches the
industrial room's own material language (metal, panel seams, hard
edges) the same way the Tideworn's fragment-shape silhouette matches
the coastal room's assembled-driftwood language.

**Voice:** clinical, procedural, treats the player as an anomaly in a
log rather than an enemy - "Contact registered." / "Threat parameters
unmet." No desperation, no malice, no awareness of loneliness. Distinct
from the Tideworn (which has no intent the way a predator does, and
never speaks at all) and from the Wardling's tentative-to-frenzied
wording (see its own Combat concept) - the Unrelieved is the first
enemy in the bestiary that actually talks, in a register that's the
opposite of both: total clarity, total certainty, zero feeling.

**Role:** the enemy for the alternate industrial/space version of the
opening room (see the industrial opening-room prototype note above,
EXPERIMENTAL, reachable via the title screen's "Dev: Opening Room
(Industrial)" button) - built as a direct aesthetic comparison to the
coastal Tideworn room. Lives in the same `resources/enemies/opening/`
subfolder as the Tideworn, for the same reason (kept out of
`EnemyPool.pick_random()`'s scan entirely - neither can ever be rolled
as an ordinary random encounter). `room_state.gd`'s
`_generate_opening_combat_layout()` now picks whichever of the two
matches `RoomState.opening_room_variant` - the industrial room no
longer borrows the Tideworn placeholder.

### The Beachwrack (baseline bruiser, Sunken Works)

**Concept:** something whale-adjacent that came ashore and never left.
It has been here long enough that the facility has accumulated onto it
- scaffolding, railings, and industrial fittings embedded in its back,
kelp and debris hanging off it. It is not built for land. Its limbs are
bearing weight they were never meant to carry, and it moves by hauling
itself forward.

**Tone register:** immense, laboring, out of place - a body persisting
in conditions that don't suit it. Distinct from both existing registers
in this bestiary: not pitiable in the Wardling's abandoned-and-starving
sense (nobody kept this and stopped - nobody was ever involved), and
not uncanny in the Tideworn's assembled-from-fragments sense (this is
one continuous, straining body, not disparate pieces given a form).
The axis here is ENDURANCE - present-tense labor, not a memory of
neglect or a natural process that happens to be hostile. Passes the
Bestiary's own design test (wretched, not monstrous): the wrongness is
that it's still here, still hauling itself, not that it wants to hurt
anyone.

**Silhouette direction:** low, wide, and MASSIVE - a bulk body slung
between short thick limbs, head low to the ground, reading as heavy and
dragging rather than upright and threatening. Grays and pale blues of
something sea-born as the base material, with rust-brown industrial
fittings and dark hanging growth (kelp, debris) as accumulated detail
layered on top - the same "wrongness lives in material" approach the
Tideworn's fragment-color layering already established, but the base
body reads as one continuous creature underneath the accretion, not
assembled from separate pieces. Shares "low and wide" with the Tideworn
at the silhouette-direction level, but at a completely different scale
and for a different reason - the Tideworn is small (~0.5x player
height, debris that happened to cohere); the Beachwrack is the opposite
extreme, easily the largest silhouette in the bestiary once built. Same
"original hand-drawn shapes, not sprites" visual language as every
other silhouette (see Run Structure & Navigation's enemy silhouettes
note) - a direction for that treatment, not a departure from it.

**Implemented, then corrected after playtesting:** the first build's
base color `(0.58, 0.62, 0.66, 1)` was almost the same lightness as the
Sunken Works sky backdrop `(0.52, 0.64, 0.72, 1)` - a real value-
separation bug, the same category of problem the corner-label cluster
hit earlier (see the Battle backdrop's own note above), just never
caught because this creature hadn't been seen against the real backdrop
yet. Darkened to `(0.30, 0.36, 0.44, 1)` - still a cool gray-blue
sea-tone, but now clearly separated from the sky, in the same value
range every other enemy already sits in (Unrelieved's `(0.32, 0.34,
0.38)`, Tideworn's `(0.42, 0.32, 0.22)`). Also added a small dark `Eye`
polygon on the Head shape - the silhouette read as inert mass without
one; a single small living detail is enough to sell BIOLOGY, distinct
from the boss's eventual architecture-based design (see the Design
note below on sharing materials, not body plan). Also flipped
horizontally after playtesting (head/front now toward -x instead of
+x) so it faces left - `enemy_visual.gd` deliberately has no shared
facing/flip system (enemies don't have a "which way am I walking" the
way the player does - see its own comment), so this was done by
mirroring every Polygon2D's own authored x-coordinates directly in
`enemy_visual_beachwrack.tscn`, a per-creature authoring choice rather
than a new engine-wide mechanism.

**Design note - shares materials with the Sunken Works boss, not body
plan:** rust, industrial fittings, and concrete-adjacent tones are
material language this creature will end up sharing with whatever the
Sunken Works boss becomes (see the BOSS room design open question,
still unresolved) - but the Beachwrack's identity is BIOLOGY that
accumulated the facility onto itself, not FACILITY that became mobile.
Keeping those two silhouette logics distinct (a body wearing
industrial wreckage vs. industrial wreckage that IS a body) is what
lets this creature establish the biome's material world without
telegraphing what the boss actually is once that gets designed.

**Combat role:** the baseline bruiser - the standard Sunken Works fight
that teaches reading an enemy's rhythm and blocking on the heavy turns,
the same pedagogical slot the Thicket Stalker occupied before this
entry (see "Replacing the Thicket Stalker" below). The lesson is
patience and correct block timing against a legible, fully-telegraphed
threat (see the Wind-Up Swing mechanic below), not uncertainty about
WHETHER something is coming - that core promise never breaks. What
IS erratic, after playtesting (see the Wind-Up Swing section's own
"Third state" note below), is the timing BETWEEN swings, not the swing
itself - a deliberate, narrower kind of unpredictability than the
Tideworn's, which contrast this way: the Tideworn is unpredictable
about WHAT'S coming (idle vs. weak hit vs. strong hit, no visible
warning); the Beachwrack is unpredictable only about WHEN the next
warning starts, never about whether a warning precedes the hit. High
HP, sized against the Wardling's 90 as the reference point
- the Wardling is this bestiary's only enemy confirmed to function
correctly in playtesting so far (see the Tideworn's own retuning
history: its original 20 HP let the erratic pattern go unseen; the
Thicket Stalker's 45 HP is the other data point this replaces). It
needs to survive long enough for its own attack pattern to actually
cycle into view, and for a chain sequence (see the Chaining prototype,
Combat tempo open question) to matter across the fight rather than
being over before a second Opener/Closer pairing is even possible.
**Implemented:** max_hp = 80 (see `resources/enemies/beachwrack.tres`),
Wind-Up Swing and its Attack both at value 15 - 15 clearly exceeds a
single Guard's 5 block, and now exceeds even TWO Guards stacked (10) -
a direct consequence of raising the originally-proposed value (10) to
15 during approval, which removes "commit two Guards to fully deny the
spawn" as an option Knocks Something Loose's own design assumed might
exist; full block-or-race still holds, it just can't be made fully
free through block volume alone anymore. Originally a two-entry FIXED
loop; see the Third state note below the Wind-Up Swing section for why
a third intent and erratic selection replaced that after playtesting.

**Signature mechanic - Wind-Up Swing:** the Beachwrack telegraphs its
heavy attack a full turn before it lands - an intent that reads as
"shifting its weight," not yet an attack, followed the NEXT turn by the
actual hit. This is a genuine block-or-race decision, not just a bigger
number to respect: spend the wind-up turn defending (a Guard is up in
time for the real hit), or spend it pushing damage and try to kill the
Beachwrack before that hit ever lands. The heaviest hit should clearly
exceed what a single Guard (5 block) absorbs - the same "block isn't
automatically safety" principle the Tideworn's own retuning already
established (see its own Combat concept above), now taught through
advance warning instead of unpredictability, which is the opposite
lesson: the Tideworn punishes ASSUMING safety, the Beachwrack rewards
ACTUALLY READING the intent and planning a turn ahead.

**Implemented:** the SEQUENCING initially needed no new system at all -
a fixed (non-erratic) `intents` loop, the same shape Thicket Stalker/
Glasswing already use, guarantees "wind-up always precedes the hit" for
free, since it's just the next entry in the same cycle. The wind-up
turn DID get its own `IntentType` (`WIND_UP`, added to `enemy_intent.
gd`) - it needed a distinct icon regardless of what the number ended up
doing (see below), since showing anything under ATTACK's own icon
reads as "this lands now."

**Third state, and the number's removal (DECIDED after playtesting,
implemented):** a strict two-beat wind-up/swing loop became a
metronome after one cycle - the exact same failure mode the Tideworn
hit before ITS fix (see its own "third intent" note above), just with a
different cause (period-2 alternation instead of a coin-flip that
could still cluster). Fixed the same way in spirit but NOT by copying
the Tideworn's exact mechanism wholesale: switched the Beachwrack to
`erratic_intent_selection = true` and added a third intent, **Settle**
(IDLE-type, 0 value, "Settles its weight. Something groans beneath the
plating.") - reusing the Tideworn's own blank IDLE display treatment
for free.

Naively going erratic would have broken the fairness contract outright
- a free random pick could land on the swing with no wind-up ever
shown, on turn one or any other turn. `battle.gd`'s `_pick_erratic_
intent_index()` gained a hard rule ahead of its existing no-consecutive
-idle guardrail: whatever intent immediately follows a WIND_UP in the
array is a FORCED transition (100%, not a weighted pick) and is
excluded from the general random pool entirely - it can only ever be
reached the turn right after its own wind-up
(`_erratic_locked_followup_indices()`). This also had to apply to the
very first intent an erratic enemy ever shows at spawn, not just to
turn-to-turn advances - a fresh fight opening directly on the swing
would be the same fairness break on turn one, so `_spawn_enemies()`/
`_spawn_additional_enemy()` now roll the first intent through a new
`_pick_erratic_initial_index()` that excludes locked indices too. Both
helpers are written generically over "any WIND_UP's paired follow-up,"
not hardcoded to the Beachwrack - an enemy with no WIND_UP intent (the
Tideworn) gets an empty locked list and is completely unaffected;
confirmed via a headless regression check (the Tideworn's own no-
consecutive-idle behavior, re-tested after this change: unchanged).

Resulting chain for the Beachwrack: Wind-Up -> Swing always (rule 1);
from Swing, a pick between Wind-Up again or Settle; from Settle, forced
back to Wind-Up (rule 2, since Settle is IDLE-type and can't repeat
itself). Confirmed via headless simulation: every wind-up is followed
by its swing with zero exceptions, the swing is never reached any other
way, Settle never repeats back-to-back, and both the short (Wind-Up->
Swing->Wind-Up) and long (Wind-Up->Swing->Settle->Wind-Up) cycles
occur.

**Settle weighted down (DECIDED after further playtesting,
implemented):** an even 50/50 at the Swing->{Wind-Up, Settle} branch put
Settle's long-run frequency at ~19.6%, which still came up often enough
to feel too common in play. Rather than hand-tuning the erratic picker
itself (which would risk touching the Tideworn's own already-tuned
distribution - see its own "third intent" note above), added a real
weighting knob to the general mechanism: `EnemyIntent.erratic_weight`
(default 1.0 - equal odds, identical to a plain unweighted pick, so
every existing enemy's distribution is untouched unless explicitly
retuned), consulted via `WeightedRandom.pick()` (the same weighted-roll
utility already used elsewhere - see `enemy_data.gd`'s own note on
`pool_weight`) in both `_pick_erratic_intent_index()` and `_pick_
erratic_initial_index()`. The Beachwrack's Settle intent is weighted to
0.4 against Wind-Up's default 1.0 - confirmed via a 40,000-turn headless
simulation to bring Settle's long-run frequency down to ~12.6% (all
three fairness guarantees above still hold with zero exceptions), while
a parallel regression check confirmed the Tideworn's own distribution
(strong ~37% / idle ~25% / weak ~37%) is completely unchanged.

Once the number was gone from the wind-up turn (next paragraph), the
sequencing change above is what keeps the OUTCOME still fully fair even
though the TIMING is now genuinely unpredictable - the number always
correctly foreshadowed things over a two-turn window before; now the
icon's mere presence does, backed by a transition rule that can't be
skipped.

**Wind-up icon, number removed (DECIDED after playtesting,
implemented):** the wind-up turn originally showed its real upcoming
damage number under the icon (see the paragraph above this one).
Playtesting found this read oddly on its own - a bare "15" with nothing
landing that turn looked like a display bug rather than a deliberate
beat, especially once nothing else on screen explained why. `Intent
Display.show_intent()` now hides the number for `WIND_UP` the same way
it already does for `IDLE`; the icon alone has to carry "something big
is coming" now. Redesigned three times: a plain amber upward triangle,
then a raised cocked-back hammer silhouette, then a double upward
chevron - each an improvement, but all three were still a SEPARATE
hand-drawn symbol, in its OWN accent color, that the player had to
learn to associate with "attack coming." The design that actually
stuck (see the Polish Backlog idea that proposed it, now implemented
and removed from that list): render `WIND_UP` as a **literal hollow,
pulsing outline of ATTACK's own blade shape, tuned to that same red** -
the exact same silhouette, unfilled (the backdrop shows through the
middle, not a see-through tint of a filled copy), so the icon teaches
itself. The player doesn't need to learn what the wind-up icon means as
a new symbol; they already know what the solid red blade means, and an
outline of that exact shape reads immediately as "that, but not yet."

**Correction after a first pass (DECIDED, implemented):** the first
build used a Line2D outline colored with a flat opacity reduction on
top of the source shape's own color - technically an outline, but with
a stroke wide enough (and faded enough) relative to the icon's own tiny
shapes that it still read as "a see-through blob," not "a crisp hollow
shape." Fixed on three fronts: (1) the stroke got thinner (1.5px, down
from 3px) so it actually traces a visible gap around each shape's own
interior instead of filling it edge to edge; (2) the opacity fade was
removed entirely - the outline is full-strength color, no transparency
effect, so "hollow" comes from being unfilled, not from being faded;
(3) since a thin full-opacity outline is still inherently lower-contrast
than a filled shape against a bright backdrop, `IntentDisplay`'s
existing per-icon drop shadow (`OverlayStyle.make_icon_shadow()`) was
fixed to actually reach it - it had been silently doing nothing for
`HollowIcon` specifically, a two-part bug: it tints shapes before
they're added to the tree (fine for a hand-authored icon, whose
`Polygon2D` children exist immediately), but `HollowIcon` used to build
its own `Line2D` children lazily in `_ready()`, which hadn't fired yet
at tint time, AND the tint function only recognized `Polygon2D`, not
`Line2D`, in the first place. Fixed both: `HollowIcon.source_scene` now
builds its outline immediately via a custom property setter, the moment
it's assigned (matching a hand-authored icon's own "shapes exist right
after instantiate()" behavior), and `OverlayStyle`'s tint function
recognizes both shape types now - a fix to the shared mechanism itself,
so any future outline-based icon gets a working shadow for free, not
just this one.

Built generically rather than as Beachwrack-specific art: a new
`HollowIcon` script (`hollow_icon.gd`) takes any icon `PackedScene` as
`source_scene` and rebuilds each of its `Polygon2D` shapes as a closed
`Line2D` outline at runtime (matching position/rotation/scale/offset,
closing the loop by repeating the first point - `Line2D` has no native
closed-loop flag). `intent_icon_windup.tscn` is now just a `HollowIcon`
pointed at `intent_icon_attack.tscn` - no hand-drawn wind-up geometry
exists anymore, so the wind-up icon can never visually drift out of
sync with whatever the attack icon actually looks like, including after
a future redesign. `IntentDisplay.ICON_SCENES` still maps `WIND_UP` to
this one scene exactly as before, so this is transparent to every other
system: any future enemy that uses a `WIND_UP` intent gets this same
treatment automatically, same as it already would have with a
hand-drawn icon - nothing about this is Beachwrack-specific.

A slow, subtle pulse (`HollowIcon`'s own `pulse_enabled`/`pulse_period_
sec`/`pulse_min_opacity`/`pulse_max_opacity`, animating the outline's
own `modulate.a`, which cascades to every `Line2D` child for free) sells
"charging up" without needing a second animated symbol - this is the
ONLY opacity effect in play; at `pulse_max_opacity` the outline is
full-strength color, never dimmed on its own. `outline_color` and
`outline_width` are both real `@export`ed knobs on `HollowIcon` (not
derived automatically from the source shape's own color, and not baked
constants) - `intent_icon_windup.tscn` sets `outline_color` to match
`intent_icon_attack.tscn`'s red explicitly, so the two stay visually
tied by deliberate choice, tunable independently if that relationship
ever needs to change. The real number still always appears -
just on the swing turn, one turn later, guaranteed by the forced
Wind-Up-to-Swing transition above rather than shown early - so Combat
Telegraphing's "the number shown is what lands" rule still holds, it's
now carried by the icon+timing pair instead of an early preview number.

**Centering fix (DECIDED, implemented):** `IntentDisplay.center_within()`
used to run ONCE per creature, at spawn/layout time, computing the
icon+number group's position from a fixed "icon, then a gap, then a
number" total width - correct for ATTACK/DEFEND, but wrong for
`WIND_UP`, which shows only the icon: the icon still sat shifted left,
reserving empty space for a number that was never going to render, off-
center from the creature. Fixed by moving the actual positioning math
into a new `_recenter(has_number: bool)`, called fresh every time
`show_intent()`/`clear()`/`show_pain()` changes what's actually showing
- `center_within()` itself now just remembers the target width. An
icon shown alone centers on the icon's own width; an icon+number
centers on both together, exactly as before. Not `WIND_UP`-specific
code - any future intent type that shows an icon without a number
inherits correct centering automatically.

**Reversed - opacity replaces hollow, number restored (DECIDED,
implemented, 2026-08-26):** the hollow-outline treatment above, and the
hidden number before it, both got reopened once `pip.gd`'s energy pips
separately adopted hollow-vs-filled to mean spent-vs-available (see
Combat Telegraphing's pip entry). That made `WIND_UP`'s existing
hollow-outline icon a second, unrelated thing using the same visual
grammar - a hollow shape now had two different meanings depending on
which corner of the screen you were looking at. Fixed by dropping
`HollowIcon` for this entirely (`hollow_icon.gd` and
`intent_icon_windup.tscn` deleted - `HollowIcon` had no other caller):
`IntentDisplay.ICON_SCENES[WIND_UP]` now points at
`intent_icon_attack.tscn` directly, the same preload as `ATTACK` itself
(still guaranteed to never visually diverge from it, just via sharing
one scene instead of rebuilding its outline at runtime), rendered at a
new `pending_opacity` export (0.55, matching `HollowIcon`'s own former
`pulse_min_opacity` - the dimmest point its pulse used to reach,
already playtested as legible) applied to `icon_root` and `value_label`
alike via a new `_apply_pending_state()`.
`show_intent()` no longer hides `WIND_UP`'s number either - it shows
the same icon+number pair as a real intent, just recessive, since
`WIND_UP` is a genuine two-turns-out preview and the player needs the
actual value to plan against it, not just the fact that a hit is
coming. `EnemyIntent.value` is no longer just a human-readability
convention for a `WIND_UP` entry (see `beachwrack.tres`) - it's now the
real previewed number, so it must match its paired `ATTACK`'s value
exactly. Showing an icon+number pair for `WIND_UP` also fixes its old
off-center position for free: `_recenter(has_number)` above treated
`WIND_UP` as icon-only (a narrower `total_width` than `ATTACK`/
`DEFEND`'s), which is exactly what put it at a different position than
a real intent; now every non-`IDLE` type takes the same
`has_number = true` path and lands at the identical position.
No pulse animation carried over (`HollowIcon`'s own pulse was a
property of the outline treatment specifically, not something this
opacity-based approach needed to replicate) - both values below are
static.

**Retuned same day (DECIDED, implemented):** a single 0.55 shared by
icon and number read as "a slightly lighter active intent," not
"clearly not-yet-live," when there was no active intent alongside it to
compare against - the actual bar this needed to clear. Split into two
separate exports, `pending_icon_opacity` (0.3) and `pending_value_
opacity` (0.5), pushed further down and apart rather than just lower
together: a uniform alpha multiplier doesn't fade the two evenly in
PERCEIVED terms - the icon is saturated red against a pale sky backdrop
that stays visually loud even dimmed, while the number's pale fill
drops off faster at the same alpha - so the icon needed to go lower
than the number for the pair to read as one evenly-faded unit instead
of a strong icon next to a weak number. Checked against both real
backdrops this renders over (pale sky, darker enemy sprite).

**Signature mechanic - Knocks Something Loose:** if the Wind-Up Swing
connects (isn't fully blocked), debris shakes free from the
Beachwrack's own accumulated growth and a Tideworn spawns into the
fight. ONCE per fight maximum - this is a single consequence for a
missed block, not a snowball, and needs the same one-shot guard shape
`EnemyCombatant.pain_turn_used` already established for the Wardling's
pain turn (see battle.gd) - a boolean on the Beachwrack's own combatant
that permanently disables the trigger after the first successful hit,
regardless of how many more heavy hits land afterward. Missing the
block doesn't just cost HP, it costs a whole new problem - giving the
Wind-Up Swing's block-or-race decision real teeth beyond a damage
number.

**Implemented:** this needed a genuinely new battle-system capability,
not just new enemy data - `battle.gd`'s new `_spawn_additional_enemy()`
mirrors `_spawn_enemies()`'s per-enemy instancing (Enemy scene, an
`EnemyCombatant`, signal wiring, an erratic-intent roll, appending to
the shared `enemies` array) for a combatant joining a fight already in
progress. `EnemyData.debris_spawn_enemy` (default null, "empty means
unaffected" like `escalation_multipliers`/`pain_turn_hp_threshold`
above) names the real resource to spawn; `EnemyCombatant.debris_spawn_
used` is the one-shot guard, the exact shape anticipated above. The
trigger hooks in at `_enemy_attack_player()`, inside the branch where
`damage_to_hp > 0` - i.e. it fires whenever ANY damage got through,
fully-blocked hits never reach it, without being scoped to a specific
intent (this creature only has one real attack, so that's already
equivalent to "the Wind-Up Swing landed" - see `enemy_data.gd`'s own
comment on why a future multi-attack enemy would need a real per-
intent flag here instead).

The two open questions above resolved as: (1) **not** re-derived - the
newcomer joins at its own normal solo scale, already-present enemies
are NOT retroactively rescaled via `_multi_enemy_scale_factor()`. This
is a disclosed trade-off, not an oversight: no existing code path
supports re-deriving an already-laid-out enemy's `cluster_width_px`/
`bar_width_px`/`silhouette_scale`, so a full-scale "solo" Beachwrack
next to a full-scale "solo" Tideworn may look visually inconsistent
compared to how two enemies present when a fight starts with both
already known - worth an eyeball pass once seen on screen, and a
candidate for a real fix if it reads badly in play. (2) confirmed via
headless testing, not just assumed: turn-sequencing and the victory
check needed ZERO additional code beyond correctly appending to
`enemies` - `_run_enemy_turn()`'s snapshot-based iteration and
`_on_enemy_defeated()`'s `_living_enemies().is_empty()` check were
already fully generic over the array, and the Beachwrack is still
fought solo (bringing the total to 2 once the Tideworn joins), same as
assumed.

**Spawn distance (DECIDED after playtesting, implemented):** the "worth
an eyeball pass" flag above turned out to matter - the newcomer kept
its full 500px solo-sized reserved LAYOUT BOX (`cluster_width_px`) in
EnemyZone's HBoxContainer, meant for a creature fought alone and
centered in the whole zone, which read as two separate encounters
rather than debris shaking loose right next to the Beachwrack. Fixed
narrowly: a new `DEBRIS_SPAWN_CLUSTER_WIDTH_SCALE` (0.4) shrinks only
the newcomer's `cluster_width_px`/`bar_width_px` in `_spawn_additional_
enemy()` - the reserved BOX, not the creature's own rendered SILHOUETTE
size (`silhouette_scale` is untouched, on purpose - see the "not re-
derived" paragraph above, which this doesn't revisit). A distance fix,
not a size fix: the Tideworn still renders at its normal, fully
recognizable scale, just packed snug against the Beachwrack instead of
centered in a mostly-empty box of its own.

**Fiction note:** the Tideworn spawn is deliberate connective tissue,
not an arbitrary reinforcement mechanic - the Tideworn IS debris
assembled by the tide, and the Beachwrack is a creature covered in
accumulated debris. Something shaking loose from it and reassembling is
what makes both creatures make more sense together than either does
alone: the Tideworn was always described as something the tide
"occasionally does," and now the fiction has a specific, embodied source
for one. The spawned Tideworn should be the actual `tideworn.tres`
resource already tuned and verified (see its own Combat concept above)
- not a reskinned copy with its own stat block - so the connective
tissue is literal, not just thematic.

**Audio (IMPLEMENTED):** three real sounds, replacing what had been
silent placeholders - `wind_up` (plays whenever a `WIND_UP` intent
resolves, generic over the mechanic - see battle.gd's `_resolve_enemy_
intent()`), `beachwrack_impact` (the swing landing on the player,
wired via `EnemyData.attack_impact_sfx` instead of the shared
`damage_player` cue every other enemy still uses - a creature this size
shouldn't sound like a Wardling's claw), and `debris_spawn` (the
Tideworn shaking loose). All three live under `assets/audio/enemies/
Beachwrack/` - see the Audio section's own Folder layout note for why
that's the first real content in `enemies/`, and the convention it sets
for any future creature-specific sound.

**Replacing the Thicket Stalker (IMPLEMENTED):** the Thicket Stalker
(low, wide, four stubby legs, mossy green - see Run Structure &
Navigation's enemy silhouette work) was designed and built before the
Sunken Works biome existed, and its mossy-green palette has no place in
this biome's sun-bleached industrial-coastal material language (see the
Sunken Works' own Creature fit note, which already never listed the
Thicket Stalker as belonging here). The Beachwrack replaces it
entirely, not alongside it. `resources/enemies/thicket_stalker.tres`
was relocated (via `git mv`, preserving history) to
`resources/enemies/retired/thicket_stalker.tres` - `EnemyPool.pick_
random()`'s folder scan is confirmed non-recursive, so this fully
removes it from the pool without deleting the file, the same mechanism
that already keeps the Tideworn/Unrelieved out of the general pool by
living in their own `opening/` subfolder. Verified via a 200-roll
headless check: the Thicket Stalker was never picked, the Beachwrack
was.

### The Wardling (elite)

**Concept:** something that was kept - tended, fed, purposed - and then
abandoned when whoever cared for it did not come back. It is starving,
and has been for a long time. It is aggressive out of desperation, not
malice.

**Tone register:** pitiable AND unsettling, never simply frightening -
the design test above applied to this specific creature. Shadow of the
Colossus and Chrono Cross in creature form: beautiful-but-lonely
expressed as a thing that was left behind, not a thing that was always
monstrous.

**Silhouette direction:** tall and too thin, limbs disproportionately
long, posture collapsed or exhausted - like it is holding itself up.
Unsettling through ONE wrong element rather than many scary ones: head
too small, set too low, or angled slightly wrong. Asymmetric stance. Same
"original hand-drawn shapes, not sprites" visual language as every other
silhouette in the game (see Run Structure & Navigation's enemy
silhouettes and field juice notes) - this is a direction for that
treatment, not a departure from it.

**Lore detail:** it still wears a remnant of what kept it - a harness, a
collar, a ceremonial marker - ornament on a starved frame. This is the
detail that makes it pitiable rather than merely grotesque, and it plants
a thread without saying a word: someone made this, someone fed it, they
are gone. Environmental storytelling with no exposition, same as Pillar
4(b) - the harness IS the lore delivery, not a label or a codex entry
explaining it.

**Field behavior concept:** rather than the standard proximity pulse
(see field_blob.gd's NoticeZone), the Wardling turns to face the player
when they come near, and then does not move. Something that watches.
Dread through stillness, not aggression - a deliberate departure from
the pulse-and-brighten cue every other encounter uses, because "notices
you and reacts with stillness" is a different feeling than "notices you
and gets excited," and this creature is specifically not excited to see
anyone.

**Combat concept:** escalating desperation. Damage climbs as the fight
continues - it is not getting angrier, it is getting more frantic. Intent
text should read tentative early and frenzied late. This is the first
playable test of open question 5's setup-and-payoff tempo thesis: early
turns become about preparing for what it becomes, rather than every turn
being interchangeable.

**Role:** first ELITE-tier enemy, and the first entry in the dedicated
elite encounter pool (`wardling_solo.tres`) - see the new ELITE Rooms
section, which resolves open question 14.

### Outbound (leaves mid-fight, Sunken Works, back half)

**Concept:** something large moving fast through a flooded space, on its
way somewhere else. Its attacks are incidental - wash and undertow, chip
damage from a body that isn't aiming at the player at all, just passing
close enough to matter. It doesn't fight to win; it fights because it
hasn't finished leaving yet. Given accumulating distance from the moment
it's engaged, and past a threshold it's simply gone - the fight ends via
the escape resolution path (see Run Structure & Navigation's own Escape
resolution entry), not a kill.

**Role:** the first real trigger for that escape path, and the first
enemy whose outgoing damage taken falls off over the course of a fight
- previously infrastructure with no live user. Regular (not elite)
tier, uncommon, solo only, gated to the back half of the run (layer 4
onward of 0-7) - see EnemyPool.pick_random()'s new `current_layer`/
`allow_escape` params and EnemyData's new `min_layer` field, both
documented at their own declarations.

**IMPLEMENTED (2026-08-23), values deliberately untuned - HP baseline
calibration and escape-rate tuning both happen later, once there's more
than one enemy to calibrate against:**

- `max_hp = 70` - Wardling (90, the bestiary's only enemy confirmed to
  function correctly in playtesting, see the Beachwrack's own note on
  using it as an anchor) halved, landing between Glasswing (26) and
  Beachwrack (80).
- Two alternating plain `ATTACK` intents, no `WIND_UP` entries at all -
  "Wash" (3 dmg) and "Undertow" (4 dmg), both below Glasswing's 6/6/9
  floor. "Not aiming at the player" is carried by flavor text, not a
  new intent type - the engine has no other way for an enemy to deal
  damage to the player, and building one felt like scope the mechanic
  itself didn't need.
- `escape_distance_per_turn = 10.0`, `escape_distance_max = 100.0` - 10
  enemy turns to escape if never pressured, well past a normal kill
  (70 HP over maybe 6-7 player turns at typical damage), so escape stays
  a rare outcome under ordinary play, not the expected ending.
- `pool_weight = 0.5` - reuses Wardling's own already-established
  "uncommon" number rather than inventing a new rarity tier.
- `min_layer = 4` - never a candidate before the run's back half. A hard
  floor, not a soft weighting ramp: below layer 4, `EnemyPool.pick_
  random()` excludes it from the roll entirely (same "excluded, not
  rolled-then-clamped" idiom `_pick_blob_count()`/`_available_spawn_
  slots()` already use), rather than a lower chance that could still
  fire early. `allow_escape = false` at the boss roll specifically - a
  boss that could flee the run's own climax fight was a deliberate no,
  not an oversight; `_make_boss_variant()`'s deep `duplicate()` would
  otherwise have carried the mechanic straight through un-scaled.
- No `visual_scene` yet - renders as the plain fallback square in both
  field and battle, same "unarted enemies still work" shape every other
  enemy had before its own silhouette existed.

**Where the mechanic actually lives (see enemy_data.gd's own Escape
section and battle.gd's own note above `_escaping_enemy`):** distance is
scoped to the ENCOUNTER, not the enemy - the live per-fight counter
(`battle.gd`'s `_escape_distance`, plus `_escaping_enemy`, found once at
spawn) lives on the battle scene itself, since a Resource like EnemyData
can be shared/reloaded across fights and writing live progress onto it
would leak between them. `EnemyData.escape_distance_per_turn`/`_max` are
CONFIG only (0.0 default, inert for every enemy but Outbound), read once
to seed that live state - the exact same "empty/zero means no effect"
shape `pain_turn_hp_threshold`/`escalation_multipliers`/`debris_spawn_
enemy` already established. Combat resolution stays ignorant of all of
this except ONE seam: `_deal_damage_to_enemy()` applies a linear falloff
scalar (`1.0 - distance/max`, clamped `[0, 1]` - 1.0 at zero distance, a
pure no-op multiply) right after the existing status-modifier call and
before `_resolve_damage()`, a no-op for every target that isn't the
fight's own `_escaping_enemy`. Nothing in `_resolve_card_effect()`,
`_resolve_damage()`, or the targeting path knows this mechanic exists.
The tick itself (`_tick_escape_distance()`) runs once, at the very end
of `_run_enemy_turn()` - literally "end of enemy turn," not "end of
this one combatant's own resolution" (the two are the same moment for a
solo enemy like Outbound today). Crossing the threshold calls the
existing `_on_battle_escaped()` fire-and-forget, same pattern `_on_
enemy_defeated()` already uses for triggering victory - no new plumbing
needed for `_on_end_turn_button_pressed()`'s own "don't start the next
player turn if the battle's already over" check to do the right thing.

No presentation this pass - no distance bar, no HUD readout. Escape's
own existing dim/beat/Continue sequence (see Run Structure & Navigation's
Escape resolution entry) already gives the ending a visible beat, so an
Outbound fight ending this way doesn't read as a crash even without a
running display of the mechanic building toward it; watching distance
rise turn to turn is left for a later, dedicated presentation commit.

**Verified headlessly:** `EnemyPool.pick_random()` gating (200 trials
below `min_layer`, zero picks; 400 trials at it, at least one pick; 300
trials with `allow_escape=false`, zero picks); a real battle against
Outbound with no player damage dealt beyond two probe hits - the falloff
scalar measured exactly `1.0` at zero distance and `0.7` at distance
30/100, a 10-damage probe hit landing as 7 at that point, distance
ticking up exactly 10/turn, and reaching max distance correctly ending
the battle via the escape path (`_battle_outcome == ESCAPE`, Outbound
left `is_defeated == false` - it left, it wasn't killed) - plus a
regression check that an ordinary enemy (Beachwrack) gets no `_escaping_
enemy` set for its fight and takes full, completely unscaled damage.

**Retuned - accelerating retreat and a falloff floor (2026-08-27, the
escape-rate/falloff tuning pass flagged as deferred above):**

- `max_hp = 90` (was 70, then 80 from an earlier balance pass) - HP
  calibration pass continuing, not part of this specific retune's own
  reasoning.
- `escape_distance_per_turn` (a flat 10/turn) replaced by `escape_
  distance_ramp = [10, 15, 20, 25, 30]` - an ACCELERATING retreat
  instead of a constant one, indexed by turns elapsed since combat
  start (0-based, clamped to the ramp's last entry past 5 turns - see
  `battle.gd`'s own `_tick_escape_distance()`). Deliberately sums to
  exactly `escape_distance_max` (100, unchanged) across the ramp's own
  5 entries, so an unpressured fight still reaches escape at almost
  exactly the same pace the original flat rate implied (5 turns instead
  of 10, since the ramp front-loads lower and back-loads higher) -
  `escape_distance_max` itself didn't need to move for that to hold.
- `_escape_falloff_scalar()` was a bare linear ramp from 1.0 at zero
  distance to 0.0 at `escape_distance_max`. Now plateau-then-linear:
  full damage (1.0) through `ESCAPE_FALLOFF_PLATEAU_DISTANCE` (20), then
  linear down to `ESCAPE_FALLOFF_FLOOR` (0.4) at max distance - a kill
  stays fully live in the opening turns, and never becomes literally
  impossible (the old curve's 0.0 floor meant a hit landing in the same
  instant as the escape threshold could deal zero damage; now it always
  deals at least 40%). Both new constants live at the top of the same
  function in `battle.gd`, one-file-edit tunable, same as the ramp
  table on `EnemyData`.

**Verified headlessly (2026-08-27 retune):** HP and the ramp array read
back correctly from the resource; the falloff curve measured exactly
`1.0` at distance 0 and 20 (the plateau's own edge), `0.7` at 60 (the
linear segment's midpoint, halfway between 1.0 and the 0.4 floor), `0.4`
at 100, and still `0.4` on a deliberate overshoot past 100 (never
negative, never below the floor); five successive per-turn ticks
matching the ramp exactly (10, 25, 70 after turns 3-4, 100 after turn 5)
and correctly triggering escape (`battle_over`, `_battle_outcome ==
ESCAPE`, Outbound left `is_defeated == false`) the instant cumulative
distance reached exactly `escape_distance_max`; and a fresh battle whose
first tick happens on turn 9 (well past the ramp's 5 entries) correctly
clamping to the final entry (30) rather than erroring or falling back to
0.

**Dev Battle Chain, battle 2 (2026-08-23):** the title screen's fixed
chain (see `battle.gd`'s own `DEV_CHAIN_BATTLE_*` consts) had Twin
Glasswings there; swapped to Outbound so the escape mechanic is reached
by clicking the same dev shortcut, not an occasional layer-4+ roll. Twin
Glasswings remains reachable normally (ELITE rooms, and any un-pinned
chain battle from 4 onward).

**Recession (IMPLEMENTED, 2026-08-23) - the primary signal, not a bar or
a number:** as distance climbs, Outbound's silhouette visibly drifts
away and shrinks - `enemy.gd`'s new `set_recession(fraction)`, called
from `battle.gd`'s `_tick_escape_distance()` right after each tick,
tweening `visual_container`'s position/scale/modulate continuously
rather than snapping. Drift and shrink carry the effect
(`recession_drift_px = Vector2(70, -15)`, away from the player and
slightly up; `recession_min_scale = 0.62`); alpha is deliberately
restrained (`recession_min_alpha = 0.92`) - Outbound has one small man-
made detail in its silhouette doing real work, and fading it out would
be the first thing lost. No new depth system - reuses the exact
position/scale/modulate properties `play_attack_lunge()`/`play_
interrupt_flinch()`/the targetable pulse already animate on this same
node; no fog, no parallax, no camera exists to build one with.

**The real finding: three existing animations reset `visual_container`
to a HARDCODED rest value, which would have silently erased recession
the next time any of them played.** `play_attack_lunge()`'s `rest_x`,
`play_interrupt_flinch()`'s and the targetable pulse's return-to-
`Vector2.ONE` all assumed "rest" could only ever mean the creature's
original spawn position/scale - true for every enemy until this one,
where "rest" now moves over the course of a fight. Fixed by generalizing
all three to read a new per-instance baseline (`_rest_position`, cached
once in `_apply_creature_layout()`; `_recession_offset`/`_recession_
scale`, updated by `set_recession()`) instead of the hardcoded literals
- a no-op change for every enemy but Outbound, since that baseline never
moves unless `set_recession()` is called. `hover_area`/`vitals_bar`/
`intent_display`/`name_label` deliberately stay fixed, untouched by any
of this - only the silhouette itself recedes, keeping the HUD legible
and sidestepping any targeting-hitbox mismatch (moot in practice anyway:
Outbound is solo, so `_on_card_clicked()` never needs an actual click on
it to resolve a target). The Creditor's reflected hit and chain glow are
both unrelated to `visual_container`'s position and need no changes.
One accepted gap, documented rather than solved: `set_recession()`'s own
tween is a fourth, independent tween on the same node - in practice it
never overlaps with the other three (recession only ticks once, at the
end of an enemy turn, well after that turn's own lunge/flinch already
finished; the next attack/stun is at least a full player turn later,
far past `recession_tween_sec`) - real tween arbitration across four
sources for one enemy's presentation wasn't judged worth building.

**Verified headlessly (14 checks):** the baseline vars update correctly
and the tween lands on the expected position/scale/alpha; a lunge and a
flinch fired AFTER `set_recession()` both settle back to the RECEDED
rest, not the original spawn spot - directly proving the fix for the
finding above; a non-escaping enemy's baseline never moves and its
lunge/flinch still return to the exact original values; and a real
fight's own `_tick_escape_distance()` call correctly drives the
baseline through the same path a live game would use.

**Retuned - scale as the primary carrier, and IntentDisplay now follows
(2026-08-24):** the first pass (`recession_min_scale` 0.62) read as
barely perceptible at 30/100 distance - drift alone reads as fidgeting,
not leaving. `recession_min_scale` dropped substantially, to **0.35** -
at max distance the silhouette is now unmistakably small, "far out over
the water," not just nudged. `recession_drift_px` raised from `(70,
-15)` to **`(110, -25)`** as the secondary carrier. `recession_min_
alpha` unchanged at 0.92 - stays restrained on purpose, so a much
smaller silhouette still reads clearly instead of also fading toward
invisible.

New `intent_follows_recession`/`intent_follows_recession_scale`
(both default true, independently toggleable) let `IntentDisplay` drift
(and shrink) along with the silhouette - a SEPARATE tween from `visual_
container`'s own, since `IntentDisplay` is a sibling positioned via a
one-time baked absolute value at spawn (`_apply_creature_layout()`),
never parented under `visual_container` or otherwise live-linked to it;
a new `_intent_rest_position` cache gives it its own baseline to drift
from, the same shape `_rest_position` already established. The HP bar
(`vitals_bar`), `hover_area` (the click/hover target), and `NameLabel`
all deliberately stay PINNED - a shrinking, fading health readout is
worst exactly when the race is tightest, and a moving hover target is
bad; the intent number is smaller and reads as diegetic rather than
system-voice, so it can follow without becoming a readability problem
the bar would. Lower collision risk than `visual_container`'s own four-
source situation: `IntentDisplay`'s existing animations (`refresh_
intent()`/`show_intent_interrupt()`) only ever touch `rotation`/
`modulate:a`, never `position`/`scale`, so the new follow-tween can run
concurrently with either without either erasing the other - no baseline-
generalization needed the way `play_attack_lunge()`/`play_interrupt_
flinch()`/the targetable pulse required. One real fix needed: scaling
`IntentDisplay` down without recentering its pivot would shrink it
toward its default top-left corner, adding an unwanted extra drift on
top of the intentional one - `set_recession()` now sets `pivot_offset =
size / 2.0` before that tween, matching `show_intent_interrupt()`'s own
existing reasoning for the same fix, scoped to this call site only
(size doesn't change with scale, so both calls always agree regardless
of order).

**Verified headlessly (22 checks):** the new default values; position
AND scale both land on the exact expected targets for both `visual_
container` and `IntentDisplay` together; `vitals_bar`/`hover_area`
(position and size)/`NameLabel` all measurably unchanged after a full
recession tween; `IntentDisplay`'s pivot is centered, not top-left; both
follow-toggles work independently (position-only, and fully off with
`visual_container` still receding normally regardless); and a non-
escaping enemy's `IntentDisplay` never moves at all.

**The falloff readout (point 3 of this commit's own brief), and the
generic card-hover seam it's built on (IMPLEMENTED, 2026-08-23):**
investigated the trigger before building anything, per instruction -
Battle's real "card armed and targeting" state machine
(`_pending_target_card_instance`) only ever activates when `_begin_
targeting()` runs, itself gated on `_living_enemies().size() > 1` -
since Outbound is always solo, arming structurally never happens in a
real Outbound fight, so "while a card is armed" was never actually
available as a trigger. Decided: show the readout while the player
hovers any damage-dealing hand card, Outbound being the escaping enemy -
card-in-hand hover is the actual moment of deciding what to play;
silhouette hover isn't a decision, just the mouse being somewhere.

Built generically rather than Outbound-specific, since it's real
plumbing worth having again: `card.gd` gained `card_hover_changed
(card_data, hovering)`, emitted unconditionally from `_on_mouse_entered/
exited()` - regardless of armed state (`_is_hovered` already tracks
underneath the suppressed animation while armed - see `set_armed()`'s
own note) - so any future caller doesn't need to know about the armed
state machine at all. `battle.gd` tracks the hovered card by INSTANCE
(`_hovered_card_instance`/`_hovered_card_data`, not just data - two hand
copies of the same card, e.g. two Slashes, would otherwise make "which
one un-hovered" ambiguous) and dispatches through one new function,
`_update_damage_preview()` - today the ONLY reader is Outbound's escape
falloff, but a weapon modifier already silently changes a card's real
damage, and the dormant status-modifier system is a second real
invisible number-changer; both are meant to read through this exact
same seam later, not grow their own hover plumbing. `_card_needs_
target()` is reused as the "does this card deal damage" condition - it
already means exactly that (`DAMAGE`/`TOLL_DAMAGE`), independent of
enemy count or arming, which is what makes it usable here despite never
activating for a solo fight in its ORIGINAL (targeting) use.

Two dangling-reference risks handled explicitly, since `mouse_exited`
doesn't reliably fire on a node that's about to be freed: `_play_card()`
clears the hover if the just-played card was the hovered one, and
`_discard_entire_hand()` (which frees the WHOLE hand before the enemy's
turn even starts) does the same for whatever was still hovered when End
Turn was pressed.

The readout itself (`Enemy`'s new `DamagePreviewLabel`) follows the same
inert-field shape every other opt-in display on this shared scene
already uses - `update_damage_falloff(scalar)`/`hide_damage_falloff()`
are only ever called for the fight's own `_escaping_enemy`, so every
other enemy carries the (empty, invisible) field for free and nothing
ever touches it. Sits just above the HP bar, NOT a reserved layout slot
the way `FlavorLabel`'s is (that one commits space whether or not it has
text this turn - this is transient, on-demand, no slot to reserve).
Hides itself (not "-0% dmg") when there's nothing yet to report, same
"empty means nothing to show" instinct as everywhere else. A muted rust
color, deliberately NOT the "modified" amber `CardTextStyles`/the chain
burst already use - that vocabulary means boosted; this is a reduction,
and reusing it would teach the wrong lesson.

**Verified headlessly (16 checks):** hovering a damage card shows
nothing at zero distance (nothing to report yet) and the correct
percent once there's real falloff; un-hovering hides it; hovering a
non-damage card (Iron Will) tracks the hover but never shows anything;
playing the hovered card and discarding the whole hand both correctly
clear the dangling reference; and in a normal (non-Outbound) fight,
hovering a damage card tracks hover state with zero enemy-side effect,
confirmed no crash and nothing shown.

**Moved onto the card face itself (2026-08-24) - DamagePreviewLabel
retired for this path, left in place inert:** a hovered card reading
"Deal 6 damage" next to a separate "-40% dmg" over the enemy asked the
player to do arithmetic mid-decision. Now the card just says what it
will actually do - "Deal 4 damage." `card.gd`'s `show_modified_damage
(scalar)` substitutes `str(effect.value)` for each `DAMAGE`-type effect
(not `TOLL_DAMAGE` - its `value` is unused/meaningless, and Reckoning's
own text was deliberately written with no literal number for exactly
that reason) with a `[reduced]`-tagged copy of the falloff-adjusted
number - a new `card_text_styles.gd` semantic tag, muted rust,
deliberately NOT reusing `[modified]` (that one already means BOOSTED;
reusing it for a reduction would teach the wrong lesson). `_refresh_
description_text()` gained an optional override-source parameter so
this reuses the exact same expand/chain-suffix/center-wrap tail rather
than a second copy of it; `restore_description()` is just that same
function called with no override, since it was always a full rebuild
from `card_data.description` - there was never anything to cache.
`battle.gd`'s `_update_damage_preview()` now writes straight to `_
hovered_card_instance` instead of the enemy label, gated the same way
plus a `scalar < 1.0` check (no falloff yet reads as no visible change,
not a same-number recolor). The three existing clearing points (hover
exit, play, discard) now call `restore_description()` directly instead
of routing through the dispatch function.

**The design rule this encodes, for whatever reads this next:**
player-side modifiers (a weapon, a player status) are target-
independent - they resolve to the same one number regardless of which
enemy gets hit - and belong on the card face UNCONDITIONALLY. Target-
side modifiers are normally AMBIGUOUS the moment there's more than one
enemy on screen (which one does the printed number even describe?) and
belong on the target instead - `DamagePreviewLabel` stays for exactly
that future case, a target-side modifier that can't collapse to a
single card-face number. Escape falloff is target-side but gets the
card-face treatment ONLY because Outbound is guaranteed solo - a
deliberate, narrow exception for this one mechanic, not a reversal of
the general rule. A future multi-enemy target-side modifier should read
`DamagePreviewLabel`, not this path.

Known, accepted limitation: the substitution matches `str(effect.value)`
against raw text, not structurally - a hypothetical future card whose
OTHER (non-damage) effect happened to print the exact same number as
its damage value ("Deal 6 damage. Draw 6 cards.") would have both
recolored. No card today has that shape.

**Verified headlessly (13 checks):** zero distance leaves a hovered
card's text unchanged and `DamagePreviewLabel` never lights up; real
falloff shows the reduced number in a color tag on Slash, still with
`DamagePreviewLabel` untouched; un-hovering restores the exact original
text; a non-damage card (Iron Will) stays untouched while hovered;
Guillotine's three repeated hits update together in one pass; and
playing the hovered card / discarding the hand both correctly clear
the tracked reference.

### BOSS_01 (boss, Sunken Works)

**Working name only** - naming, fiction, silhouette, and art are all
deliberately out of scope for the pass that built this entry (2026-08-29).
This is a mechanics-only writeup; treat every other Bestiary entry's
Concept/Tone register/Silhouette direction/Lore detail sections as the
template to fill in once that design session happens, not as something
this entry is skipping by accident.

**Concept (mechanical only):** a single stationary boss with high HP that
periodically enters a multi-turn Charge (2026-08-29 rework - REMOVES the
pass's original TELEGRAPH/SWING preamble, which never shipped as
described below anyway - see this entry's own note in its git history).
No wind-up turn: turn 1 is a normal attack (14), and outside the charge
window the boss picks randomly between two baseline attacks each turn
(14 and 10). A 3-turn WINDOW then opens - the boss keeps attacking every
turn during it too, but at a fixed, reduced 6 damage
(`EnemyData.charge_attack_value`), while player damage accumulates
against it; the intent shown on each window turn displays BOTH that
attack value and the accumulating damage readout at once, so the window
reads as "still hitting you, AND still vulnerable," not an idle lull. If
accumulated damage clears the threshold by the window's last turn, the
Charge is interrupted and nothing happens; if not, the boss gains a
3-turn, +50% outgoing-damage buff. The buff and the next Charge cycle
never overlap - a new window cannot begin while the buff is still active
(see `battle.gd`'s `_advance_boss_charge()`).

**Numbers chosen (see this pass's own report to the user for full
reasoning):** max HP 270 (3x the Wardling's 90, the only current elite -
no other boss/elite reference point exists yet to derive from).
`charge_damage_threshold` 60 (~22% of max HP - lowered from an initial
95/35% after playtesting found the higher bar too hard to clear on a
mediocre deck across exactly 3 window turns; easier to raise again after
watching runs than to leave it walling players). The threshold is
clamped against the boss's own current HP at the moment each window
begins, so a late-fight Charge can never demand more damage to interrupt
than the boss has left to give.

**Progress display note:** Charge progress currently shows as a
system-voice numeric readout (accumulated/threshold, in the same flavor-
line slot escalation text uses on other enemies). Alternative considered:
a threshold marker on the boss's own HP bar, so accumulation reads as
normal damage landing with no numeral at all. Revisit after first
playtests - a raw X/Y readout is, by a wide margin, the most system-voice
element in the game sitting on its most dramatic moment.

**Role:** the Sunken Works BOSS room's only encounter - loaded directly
by `room_state.gd`'s `_generate_boss_layout()` (`BOSS_01_ENEMY`), not
reachable through `EnemyPool.pick_random()` at all (see `enemy_pool.gd`'s
`BOSS_ENEMY_FOLDER`, same "excluded folder, not a convention to
remember" idiom `OPENING_ENEMY_FOLDER`/`ENCOUNTER_ONLY_ENEMY_FOLDER`
already use).

### Authored encounters (DECIDED)

Not a mechanics question - Multi-Enemy Combat's engine already handled
1-3 enemies before this existed - but a **content** one: `EnemyPool.
pick_random()` alone would only ever roll each field blob's occupant
independently (see Run Structure & Navigation's enemy silhouettes
note), which would make a 2-3 enemy fight just several unrelated rolls
dumped into the same battle, not a deliberate group. A real
multi-enemy encounter should be **authored, not randomly assembled**.

`EncounterData` (`encounter_data.gd`, same "plain `.tres` container"
shape as `EnemyData`/`CardData`) names a specific, deliberate group of
1-3 `EnemyData` entries, plus its own `pool_weight` - the SAME enemy
resource can appear more than once in that list (see
twin_glasswings.tres), since nothing at runtime mutates an `EnemyData`,
only the per-fight `EnemyCombatant` wrapping it (see Multi-Enemy
Combat). `EncounterPool.pick_random(folder)` (`encounter_pool.gd`,
mirroring `EnemyPool` exactly) picks one from whichever folder it's
given, the same weighted-roll technique as everywhere else
(`WeightedRandom`) - see the new ELITE Rooms section for the second,
elite-only folder this now supports.

Wired into field generation at the blob level, not the room level:
`RoomState._generate_combat_layout()` still rolls 1-3 independent blobs
per combat room exactly as before, but each blob now has a small
`encounter_chance` (gated behind `_past_first_layer()` - a deliberately
harder fight shouldn't ambush the player's very first battle of the
run) to become an authored `EncounterData` from the GENERAL pool
instead of a single random enemy. A blob touched this way sets
`RoomState.pending_encounter_enemies` (checked first by battle.gd's
`_resolve_enemies_data()`, ahead of the ordinary single-enemy
`pending_enemy_data`) rather than one enemy - single-enemy blobs are
entirely unchanged, still the common case. The general pool is empty
right now (both encounters authored so far are elite-tier - see ELITE
Rooms) - ready for the next non-elite one.

The field preview stays honest for a group the same way it already was
for one enemy (see enemy_data.gd's visual_scene comment: "never a
bait-and-switch") - `field_blob.gd` shows every member of the encounter
side by side (`_setup_multi_visual()`), shrunk and spaced the same
spirit as `enemy.gd`'s own multi-enemy formation scaling, so the player
can see "this is two enemies" before ever walking in.

**The design task itself:** compose an encounter from the enemies
already authored (Thicket Stalker, Glasswing - see Run Structure &
Navigation), and write it up the same way the Wardling entry above is
written - what does the pairing actually demand from the player that no
single enemy demands alone? A good exercise in exactly the skill this
whole section exists to practice: creature (and now encounter) identity
decided before code, not after. First entry below - more are open for
whoever wants to compose the next one.

#### Twin Glasswings (first authored encounter, working name)

**Composition:** two Glasswings, together - no stat changes, no
variant, the exact same `EnemyData` twice.

**Design intent:** a single Glasswing asks "can you outrace chip
damage" - fast, light hits that punish a slow, defensive hand. Two of
them doesn't just double that question, it changes its shape entirely:
pressure now comes from both at once, but only one can be killed at a
time, which makes WHERE that pressure goes a real decision for the
first time in this game. Splitting damage across both keeps them both
alive longer - worse, since neither dies and both keep hitting every
turn. Focusing one down fast reduces total incoming pressure sooner,
but means eating both intents in full while doing it. That tradeoff
IS the encounter - the first fight in the game where targeting is a
genuine tactical question rather than a formality (a single-enemy fight
never asks it at all; even the earlier Thicket Stalker + Glasswing
pairing, used only to test the multi-enemy engine itself, was never
designed as a real encounter with an intended tension).

It has to read as noticeably harder than a solo Glasswing despite being
"the same enemy twice" - the difficulty comes entirely from the
targeting dilemma above, not from padded numbers. If it just feels like
more HP and more damage, the design has failed regardless of what the
numbers say.

**Rarity:** now lives in `res://resources/encounters/elite/` (moved
there once ELITE became its own room type - see the ELITE Rooms
section), reachable only by choosing an ELITE door, never an ordinary
combat blob. Running into it should register as a step up in
difficulty, never a routine roll.

## Toll (DECIDED — accrual + display only, 2026-08-25; card effects that
read from it come later)

A per-combat accumulating resource: what the Sunken Works extracts from
you. Deliberately NOT a status effect - no `StatusEffectData`, no
`ActiveStatus`, no `StatusBadge`, no place in `StatusBadgeRow`. It's its
own concept with its own display (`toll_display.gd`/`.tscn`), living
directly on `battle.gd` (`var toll: int = 0`) right alongside
`player_block` - same fight-scoped lifetime, reset once per fresh battle
instance in `_start_battle()`, never persisting between fights.

**Accrual rules:**
- Increases by the amount of HP actually LOST, from ANY source - enemy
  attacks, card costs, status ticks, anything. The player doesn't choose
  whether they pay, only whether it buys them anything (future card
  effects, not built yet).
- Accrues from HP actually lost, not damage dealt or attempted - block
  absorption reduces it exactly the way it reduces the hit itself (an
  8-damage attack against 6 block only adds 2).
- Never decreases on healing.
- No cap.

**Centralized at one point, not per call site:** `battle.gd`'s
`_set_player_hp(new_hp: int)` is the single function every player-HP
change (loss OR gain) routes through - `_deal_self_damage()`, `_deal_
status_tick_damage_to_player()`, `_enemy_attack_player()` (via `_resolve_
damage()`, which already separates block-absorbed from HP-lost), and
`_heal_player()` all pass their already-computed new value into it
instead of assigning `RunState.player_hp` directly. It derives the
ACTUAL amount lost from the real before/after delta, not from whatever
"amount" argument a caller passed in - this correctly handles an
overkill hit at low HP (`RunState.player_hp` floors at 0, so the true
loss can be smaller than the raw incoming amount) without over-counting
Toll, verified headlessly (an overkill hit at 3 HP adds exactly 3 to
Toll, not the full incoming amount). A future HP-loss source (a new
card cost, a new status, a new enemy mechanic) picks this up
automatically just by routing its own already-existing HP math through
this one function - no new per-site bookkeeping needed. Two field-scene
HP-loss sites (`pay_window.gd`'s Pay House blood cost, `shop_window.
gd`'s rest heal) are deliberately NOT routed through this - Toll is
combat-scoped, and neither of those has a `battle.gd`/Toll instance
alive to accrue into in the first place.

**Display:** `toll_display.gd`/`.tscn`, instanced directly in `player_
battle_visual.tscn` (NOT inside `vitals_bar.gd`/`.tscn`, even though
that's where the HP bar and `StatusBadgeRow` live - `VitalsBar` is
shared by the player's field HUD, the player's battle HUD, AND every
enemy, so anything added there would leak into contexts Toll has no
business appearing in). Its own fixed row directly below the HP bar,
same width, horizontally centered the same way - status badges only
ever grow RIGHTWARD off the bar (`StatusBadgeRow` sits beside it, not
below it, despite the "above status icons" framing this feature was
originally requested with - see the row-below resolution note below),
so a row below the bar can never be displaced by however many pile up,
regardless of count.
- One row: "TOLL" (small, dimmed, `Color(0.55, 0.52, 0.47, 1)`) and the
  number (larger, brighter, `Color(0.35, 0.68, 0.62, 1)` - a murky teal,
  distinct from both the HP bar's red (`vitals_bar.gd`'s `normal_color`,
  `(0.8, 0.2, 0.2, 1)`) and the energy pips' yellow (`resource_display.
  gd`'s `pip_lit_color`, `(0.95, 0.85, 0.3, 1)`)), right-aligned in a
  fixed-width slot so digits grow leftward without shifting the "TOLL"
  label or the row's own right edge.
- Existing project font throughout (no new typeface) - same `OverlayStyle.
  apply_to_label()` outline treatment every other combat HUD label
  already uses (the HP number, block badge, status badges, intent,
  floating numbers), for the same over-the-backdrop legibility reason.
- Hidden entirely at 0 (`modulate.a = 0`); the first time it becomes
  positive, the row fades in (`fade_in_duration_sec`) with the number
  snapping straight to the correct value (the fade IS the reveal - no
  need to also tick up from 0 at the same moment); every increment after
  that ticks the displayed number up (`tween_method`, same technique
  `reward_screen.gd`'s own gold-tick animation already uses) rather than
  snapping. No sound.
- `_has_shown` is tracked entirely inside `toll_display.gd` itself
  (mirrors `vitals_bar.gd`'s own `_has_shown_hp` pattern) - resets for
  free every fresh battle instance, no explicit reset code needed
  anywhere else.

**Verified headlessly:** self-damage/status-tick/enemy-attack each
correctly add their real HP-lost amount to Toll; an attack fully
absorbed by block adds 0; a partially-absorbed attack adds only the
HP-lost portion; healing never changes Toll; the overkill-at-low-HP
edge case lands exactly on the true loss. The HUD component itself:
starts hidden, becomes visible and shows the correct value on first
increment.

**Not built yet, by design (this commit is accrual + display only):** no
card reads Toll, no spending/consumption mechanic, no cap, no way to
reduce it below its running total. `battle.gd`'s own `toll` field is
already the accessible value a future card effect would read from -
nothing further needs to change in this system to wire that up later.

**Presentation fix (2026-08-25):** the first pass above had real
legibility/alignment problems once seen in play, all fixed at once:
- **Color:** the murky teal read as a second signal - specifically as
  healing or a positive status, the opposite of what Toll means -
  rather than as neutral emphasis. Replaced with a monochrome pair:
  `word_color` stayed a dimmed warm grey (now `#6b6255`, matching
  `weapon_pickup_window.tscn`'s own de-emphasized tone rather than a
  one-off value) and `value_color` became a near-white `#f0e8da`
  (matching that same file's own brightened hover/focus tone) - the
  WEIGHT difference between dim and bright carries the hierarchy, not a
  second hue.
- **Alignment:** `TollDisplay`'s own width used to be forced to match
  `bar_width_px` (220px, the full HP bar's width) by `player_battle_
  visual.gd`, with the number right-aligned at the far end - leaving a
  large empty gap between "TOLL" and the number instead of reading as
  one grouped element. `toll_display.gd` now computes its own compact
  layout in code (`_layout_row()`): `word_label` sized to its own real
  rendered "TOLL" width via `reset_size()` (not a guessed constant),
  `value_label` positioned immediately after it with a small fixed gap
  (`word_value_gap_px`) in its own fixed-width column
  (`value_column_width_px`, wide enough for 3 digits) - the column's
  right edge is what stays fixed as digits grow, not the whole row's.
  `player_battle_visual.gd` no longer forces `toll_display`'s width at
  all; it only positions the row, left-aligned to the bar's own left
  edge.
- **Legibility:** both `word_font_size`/`value_font_size` bumped one
  step up (14→17, 22→26) - too small against the battle backdrop's own
  bright sky/pale concrete/foliage. `OverlayStyle.apply_to_label()` was
  already being called (the same shared outline every other combat HUD
  label uses), but at the shared default width (4) - too thin given
  Toll, unlike the HP bar's numerals, has no solid bar behind it for
  free contrast. Now uses `OverlayStyle`'s own `width_override` param
  (exactly what it exists for - see its own docstring) at 6.
- **Spacing:** `player_battle_visual.gd`'s `toll_row_gap_px` (the gap
  between the HP bar's bottom edge and the Toll row) bumped from 6px to
  14px - the two read as one crowded element at the original gap, not
  two related-but-distinct ones.

Verified headlessly (13 checks): `value_color` isn't green-dominant and
reads as near-white; `word_color` is dimmed; both font sizes and the
outline override are larger than the originals; the row is positioned
left-aligned to the bar (not stretched to its width) with the new
larger gap; `value_label` sits immediately after `word_label` in a
fixed-width, right-aligned column whose right edge doesn't move as the
displayed value grows from 1 to 2 digits.

**Bold value (2026-08-25):** `value_bold_strength` (0.5 default) - same
fake-bold technique (`FontVariation.variation_embolden`, no separate
bold font asset) `vitals_bar.gd`'s own `_apply_bold()` already uses for
the HP number. Only the value gets it, matching this row's own
weight-carries-hierarchy design - "TOLL" stays regular weight.

**First card that spends it: Reckoning (2026-08-26).** `resources/cards/
classes/wanderer/reckoning.tres` - 2 energy, RARE (this game's `Rarity`
enum has no "uncommon" tier to map to - RARE is the step above
baseline, closest to what was asked for). "Consume all Toll. Deal
damage to the target equal to the amount consumed."

- New `CardEffect.EffectType.TOLL_DAMAGE` (`card_effect.gd`) - `value`
  is unused; the amount is whatever `battle.gd`'s own `toll` is at
  resolution time, not an authored number. `_resolve_card_effect()`'s
  new branch reads `toll`, zeroes it, then deals that amount as damage
  through the SAME modifier pipeline every ordinary `DAMAGE` effect
  uses (`_apply_status_modifiers`/`_weapon_modified_value`) - the Toll
  consumed is the base number, not a special exception immune to
  weapon/status damage modifiers every other attack card respects.
- `_card_needs_target()` and a new `_card_requires_toll()` both derive
  from the effect list (`effect_type == TOLL_DAMAGE`), not an authored
  `CardData` flag - same "derived from what the card does" philosophy
  `_card_needs_target()`'s own original comment already states. Back
  Pay gets the existing multi-enemy targeting flow for free.
- **Unplayable, not playable-but-useless, while Toll is 0** (this
  card's own brief) - enforced in TWO places, mirroring exactly how
  energy affordability already works: a new `_is_card_playable(data)`
  (energy AND, if `_card_requires_toll()`, `toll > 0`) drives the
  visual dim wherever `set_affordable()` was previously computed
  inline from energy alone, AND `_on_card_clicked()` independently
  refuses the play (`play_refused()` + the existing `card_refused` sfx)
  if Toll is 0 - a stale visual state can never let a click through.
  `_set_player_hp()` now also calls `_update_hand_affordability()`
  whenever Toll actually increases, so a Reckoning sitting in hand lights
  up the instant Toll becomes spendable, not on some later, unrelated
  action.
- **The HUD's "hidden at 0, shown forever after" rule never anticipated
  Toll going DOWN mid-battle** - nothing else in the game had ever done
  that before this card. New `toll_display.gd`/`player_battle_visual.gd`
  method, `consume()`/`consume_toll_display()`: fades the row back to
  hidden and resets `_has_shown`, mirroring the existing "hidden at 0"
  rule bidirectionally rather than leaving the display stuck on a stale
  number - so a LATER re-accrual later in the same fight correctly
  fades back in instead of silently reappearing already-visible. This
  touches presentation code, but only to keep it CORRECT for a scenario
  (Toll being spent) that genuinely didn't exist before this card -
  nothing about the already-decided accrual/display behavior itself
  changed.
- Not an Opener or a Closer - `chain_role` left at its `NONE` default,
  completely outside the chain system, per this card's own brief.
- **Card text is static, not live** - this project's card rendering has
  no dynamic-value/template system at all today (`CardData.description`
  is a plain exported string; `CardTextStyles.expand()` only rewrites
  semantic BBCode tags like `[modified]`/`[keyword]`, it never
  substitutes a computed NUMBER into text). Showing a live "amount
  consumed (7)" in Reckoning's own description would need: (a) some
  templating syntax in `description` for "insert the current Toll
  here," (b) `card.gd` re-rendering that text against a live value
  rather than once at `set_card_data()` time, and (c) something
  actively PUSHING that re-render to every Back-Pay-holding hand card
  every time Toll changes - which, unlike energy (already re-pushed to
  every card via `_update_hand_affordability()`), would need `battle.gd`
  to track "which cards currently in hand need a text refresh," since
  Toll can change from ANY HP loss, not just card plays. Real, but
  clearly a new system, not a small addition - per this card's own
  brief, left as static text ("Consume all Toll. Deal damage equal to
  the amount consumed.") pending a separate decision.
- Flavor: "The Works keeps a ledger. Today, it pays." - no existing
  card in this game carries flavor text at all (checked every one);
  originally appended as a second `description` line (see the split fix
  right below - that placement didn't last).

**Fix (2026-08-26): flavor split out of `description` entirely, into a
new `CardData.flavor_text` field never rendered by `card.gd`.** Back
Pay's flavor line, concatenated into `description` above, was rendering
in every play/reward context (hand, reward screen, card-choice) - all
of which share the exact same `Card` component and read `description`
as the whole of what gets shown. A reward/choose-a-card screen is a
fast mechanical comparison task; flavor text is a reading task dropped
in the middle of it, and it visibly compressed Reckoning's own effect
text and shifted its position relative to neighboring cards with no
flavor (Heavy Blow, Riposte) - exactly backwards for a card whose
effect is the longest and most conditional of the three, which needs
MORE clarity than its neighbors, not less. `description` is now
mechanical-only, everywhere, by policy (not just for Reckoning) -
`flavor_text` exists on `CardData` for every card but is read by
nothing yet, reserved for the deck viewer to surface later (browsing,
not optimizing, is where flavor belongs - that reader doesn't exist
yet and wasn't built as part of this fix). Audited the entire card pool
(wanderer + the second class's pool + base) - Reckoning was the only card
with flavor mixed into `description` anywhere; nothing else needed touching.
Verified headlessly: `description` no longer contains the flavor
line, `flavor_text` holds it, and the actual RENDERED card text (the
same `Card.description_label` every hand/reward/choice card uses)
shows the mechanical effect with no flavor at all.

Verified headlessly (18 checks): card data/effect type load correctly;
targeting and Toll-requirement recognition both correct; unplayable
(dimmed, and an actual click refused with energy untouched) at Toll=0;
a Reckoning already in hand re-brightens automatically the instant Toll
accrues, with no other action needed; playing it spends energy, resets
Toll to exactly 0, and deals exactly the consumed amount as damage; the
HUD's `_has_shown` resets after consumption.

**Promoted into a real player-resource cluster (2026-08-25).** Toll used
to render as a bare row (no backing panel) instanced inside `player_
battle_visual.tscn`, well away from the energy pips (`resource_display.
tscn`, anchored separately near the hand) despite both being player
resources - and it hid entirely at 0, fading in/out. Replaced with:

- **New `player_resource_cluster.gd`/`.tscn`**, replacing `EnergyDisplay`
  at the same anchored spot in `battle.tscn` (bottom-left, above the
  hand). Holds a `ColorRect` backing panel styled like the run-info
  panel at top-left (`InfoLabelBackground`'s own `Color(0.05, 0.05,
  0.08, 0.55)`, the closest existing HUD-panel reference), with the
  energy pips on top and `TollDisplay` directly below, both left-aligned
  to the same inset so neither can shift the other. `battle.gd` now
  talks to this cluster (`update_energy()`/`update_toll()`) instead of
  reaching into `player_battle_visual`/`energy_display` separately.
  `TollDisplay` no longer lives in `player_battle_visual.tscn` at all -
  that script's own Toll methods and layout math were removed with it.
- **Value size, hierarchy:** `value_font_size` raised hard (26→44) -
  "larger than the pip cluster's visual weight" (a pip's own diamond is
  32px) was this pass's own explicit brief: Toll is a number the player
  does arithmetic against before playing a Toll-gated card, not just a
  readout to notice. `word_font_size` stayed small/muted (system-voice
  register, unchanged in spirit) - only the value's weight and size
  carry emphasis, same "hierarchy via weight, not a second hue" rule the
  original color fix above already established.
- **`value_column_width_px` re-measured for the new size** (50→90,
  against a direct engine measurement of bold "999" at the new font
  size, 77px, plus margin) - still the same "reserve the width so 3
  digits never resize anything" mechanism from the original alignment
  fix above, just re-validated at the new scale.
- **Zero state reworked: dimmed, not hidden.** The old "hidden at 0,
  fades in on first accrual, fades out on consume()" model made sense
  when Toll was its own free-floating row that could just not be there;
  inside a permanent backing panel grouped with the pips, a row that
  pops in and out read as inconsistent with everything else living in
  it. Now always visible - `zero_state_modulate` (a grey/faint multiply
  on the WHOLE row, same shape as `card.gd`'s own `UNAFFORDABLE_
  MODULATE`) at Toll=0, snapping to full-strength `Color.WHITE` the
  instant Toll is positive. `_has_shown` is gone entirely - nothing here
  is ever actually hidden any more, so there's no "has it been shown
  yet" question left to track.
- **`consume()`/`consume_toll_display()` REMOVED, not just reworked** -
  once zero became "tick down and dim" instead of "fade to invisible,"
  it became byte-for-byte the same thing `update_toll(0)` already does;
  the two only ever existed as separate entry points because the OLD
  fade-in/fade-out behavior genuinely needed different code for accrual
  vs. spend. `battle.gd`'s own TOLL_BLOCK/TOLL_RETALIATE/TOLL_DAMAGE
  branches all call `update_toll(toll)` unconditionally now, with no
  `if toll <= 0` branch in front of it - toll is never negative by
  construction (`_card_toll_requirement()` already guarantees enough
  Toll before a spend is allowed to play at all), so this needed no
  defensive guard either.
- **Change pulse:** a short scale bump on the value label alone (`pulse_
  scale`/`pulse_duration_sec`, ~0.12s total) on every `update_toll()`
  call, reusing `pip.gd`'s own spend-pulse vocabulary (`create_tween()`,
  a `scale` squash/pop, no new animation system) - ties the accrual to
  whatever hit caused it. Plays independently of the
  digit-counting tween (`tick_duration_sec`, unchanged) rather than
  chained onto it, so the pulse stays snappy even while a big multi-
  digit tick is still counting up.
- Accrual logic itself (what causes Toll to change, and by how much) is
  completely untouched by this pass - this was presentation and
  placement only.

**Fix pass, same day - clipping, weight, hierarchy, layout, position.**
Five problems once seen live, all in the cluster/Toll pass above:

- **Value clipped by the panel's own bottom edge.** The cluster's
  `cluster_width_px`/`cluster_height_px` were fixed exports, hand-
  computed against pip/Toll geometry with ZERO margin - any real-world
  drift from the guess (font metrics, in this case) meant clipping was
  guaranteed eventually. Root-caused two levels deep and fixed at both:
  `toll_display.gd`'s own row heights used to be a flat `row_height_px`
  guess (54px) that undershot the value font's REAL measured line
  height (`Font.get_height(44)` = 61px) with nothing left over -
  replaced with heights derived from `Font.get_height()` directly, plus
  a real `row_padding_px` margin, so this can't silently drift out of
  sync with the font again. `player_resource_cluster.gd` now reads each
  child's own real size (`toll_display.size`, the pip row's `get_
  combined_minimum_size()` - NOT `.size`, which is stale until an actual
  layout pass runs, verified headlessly) and adds `content_padding_px`
  on every side, instead of a separately hand-picked constant that had
  to agree with those children by luck.
- **Panel opacity cut hard: 0.55 -> 0.18.** The original value was a
  direct copy of `InfoLabelBackground` (the top-left DEBUG panel) -
  fine for a small text cluster, way too heavy once stretched behind a
  bigger box. Brief asked for something closer in weight to `VitalsBar`'s
  own idle background than to that debug panel; same panel_color hue
  kept, only the alpha changed.
- **`word_font_size` 16 -> 20, plus new `word_letter_spacing_px` (2px,
  glyph spacing via a `FontVariation` - same technique `weapon_pickup_
  window.gd`'s own `_setup_letter_spacing()` uses)** - "TOLL" read as
  incidental at 16 next to a 44px value; still system-voice (sans,
  small, muted), just legible in its own right now.
- **Layout: stacked, not side-by-side.** "TOLL" above the value, both
  left-aligned (`value_label` switched from right-aligned to left-
  aligned - digits now grow rightward within the reserved column
  instead of leftward from a fixed right edge) - the old row read as a
  debug readout, not a grouped resource display.
- **Cluster moved down, closer to the hand:** `battle.gd`'s
  `energy_display_hand_gap_px` cut from 20 to 8 - Toll/the pips are
  player-facing controls that belong grouped with the hand below them.

**Backing panel REMOVED entirely (2026-08-25, same-day follow-up)** -
the `Background` `ColorRect` above was tried at two opacities (0.55,
then 0.18) and dropped outright rather than tuned a third time. The
grouping itself is carried by POSITION alone now (pips directly above
Toll, both left-aligned to the same inset) - the same way `RoomLabel`/
`BattleLabel`/`TurnLabel`/`GoldLabel`/`ClassLabel` already read as one
cluster purely from being stacked together, with no panel of their own
(`InfoLabelBackground` sits behind THOSE for a different reason - that
text sits directly over variable backdrop art with no other legibility
help, which doesn't apply to this cluster). `player_resource_cluster.gd`
still sizes itself from real content (unchanged from the fix above),
just without anything drawing behind it.

**Active-state indicator for conditional cards (2026-08-27).** Compound
("Deal 6 damage. If Toll is 15 or more, deal 16 damage instead.") gave
no visual acknowledgment that its condition had gone live once Toll
actually crossed 15 - a state the player needs to plan toward several
turns in advance, since the interesting decision point is well before
the threshold, not at it. Built generally (Paid in Pain's HP-threshold
double, Retaliation, future chain-payoff cards will need the same
signal), not special-cased to Compound. Explicit design constraint: the
conditional STRUCTURE must stay visible at all times, active or not -
only WEIGHT and COLOR change, nothing reflows and no text is replaced,
so the player can still read the threshold even while it's inactive.

- **Description text markup:** two new semantic tags,
  `[cond_active]`/`[cond_inactive]`, wrapping the two numbers a
  conditional effect switches between - see `card_data.gd`'s own
  `description` field doc for the full authoring convention (including
  the "one clause per line" rule formalized in this same pass, applied
  to Compound: `"Deal [cond_inactive]6[/cond_inactive] damage.\nIf Toll
  is 15 or more, deal [cond_active]16[/cond_active] damage instead."`).
  Expanded by a new `CardTextStyles.expand_conditional()`, kept
  deliberately separate from the existing static `STYLES`/`expand()` -
  those two tags need live boolean+color state passed in per render,
  which a fixed lookup table has no way to express. Inactive: both tags
  strip to nothing, falling back to `DescriptionLabel`'s own default
  color/weight for free (this IS the "normal styling throughout, no
  dimming" inactive case - not a separate code path). Active: `[cond_
  active]` renders bold + `condition_active_value_color`; `[cond_
  inactive]` renders plain + a dimmed color built from `HudPalette.
  SYSTEM_TEXT` at `condition_inactive_value_dim_alpha` alpha.
- **General condition-active hook, not a Compound special case:** new
  `battle.gd` function `_card_condition_active(data: CardData) -> bool`,
  same "derive a fact about a card from its effects, centrally" idiom
  `_is_card_playable()`/`_card_needs_target()`/`_card_toll_requirement()`
  already use. Today it recognizes exactly one shape - a `CardEffect`
  with `effect_type == TOLL_THRESHOLD_DAMAGE`, active when `toll >=
  effect.toll_threshold` - because that's the only conditional shape
  that's data-driven today. Paid in Pain's own condition (double block
  below 50% HP) is hardcoded directly in its `TOLL_BLOCK` resolution
  branch with no corresponding `CardEffect` field, so this hook does NOT
  yet cover it - giving Paid in Pain its own indicator later needs a new
  `CardEffect` field for the HP threshold first, deliberately left out of
  this pass's scope.
- **Frame treatment: a new `ConditionFrame` panel**, sibling to the
  existing `ChainGlow` panel inside `Visual`, deliberately different
  from it in BOTH mechanism and color family. `ChainGlow` is a soft
  pulsing amber drop-shadow (`shadow_color`/`shadow_size`) meaning
  "chain live now"; `ConditionFrame` is a static, non-pulsing BORDER-only
  `StyleBoxFlat` (transparent `bg_color`) meaning "condition active,"
  toggled via `card.gd`'s new `set_condition_active()`. Color chosen
  deliberately cool/neutral (`condition_frame_color`, default a teal
  `Color(0.55, 0.75, 0.8, 1)`), NOT warm/gold - `ARMED_MODULATE` (the
  existing armed/selected whole-card tint) is already warm gold, and
  Compound will very often be armed while its own condition is active,
  so two warm signals stacked on the same card at once would read as
  different intensities of one signal rather than two distinct channels.
  Border width/intensity/corner radius all scale the same way every
  other per-instance style already does, in `_apply_layout()`. All three
  visual knobs (`condition_active_value_color`, `condition_inactive_
  value_dim_alpha`, `condition_frame_color`/`condition_frame_intensity`/
  `condition_frame_width_px`) are `@export`, per this pass's own brief.
- **Live updates, not just on draw/hover.** Toll can change from ANY HP
  loss (see this section's own accrual rules above) or from a card that
  spends it, not just from playing the conditional card itself - so
  cards already sitting in hand need to react without the player
  touching them. Traced all Toll-mutation sites exhaustively rather than
  assuming the existing `_update_hand_affordability()` call sites
  (added for energy affordability, a different trigger) already covered
  this: `_start_battle()` reset, `TOLL_DAMAGE`'s reset-to-0, `TOLL_
  BLOCK`/`TOLL_RETALIATE`'s spends, `SELF_DAMAGE_TOLL`'s accrual, and
  `_set_player_hp()`'s own `+=` (the one function every player-HP change
  routes through, per this section's own centralization note above) are
  the complete set - all six already flow through `_update_hand_
  affordability()`'s existing three call sites, now extended to also
  call the new `card.set_condition_active()` per card alongside `set_
  affordable()`. The one gap found: a card's FIRST frame in hand
  (`_add_card_to_hand_display()`, both initial draw and mid-turn draws)
  runs before that card exists in `hand_container` for the loop above to
  reach - given its own explicit `set_condition_active()` call right
  alongside its existing `set_affordable()` call so a freshly-drawn
  Compound never opens already stale.

**Extended to Paid in Pain (2026-08-27, same-day follow-up).** Paid in
Pain ("Spend 7 Toll. Gain 10 block, 20 if below half HP.") doubles
`value` when `RunState.player_hp < RunState.player_max_hp * 0.5` -
hardcoded directly in `TOLL_BLOCK`'s own resolution branch, not a
`CardEffect` field (see `card_effect.gd`'s own TOLL_BLOCK doc: "the
first card using this specifies a fixed double, not a per-card tunable
ratio"). Extending the indicator to it needed no new field, just
recognizing the existing shape:

- `_card_condition_active()` gained a `TOLL_BLOCK` branch, active below
  half HP - the exact same comparison `_resolve_card_effect()` already
  doubles on, now shared through a new `_is_player_below_half_hp()`
  rather than typed out a second time and risking the two drifting
  apart from each other.
- Description updated to the same tag/one-clause-per-line convention as
  Compound: `"Spend 7 Toll.\nGain [cond_inactive]10[/cond_inactive]
  block.\nIf below half HP, gain [cond_active]20[/cond_active]
  instead."`
- **Real gap found generalizing past a Toll-only condition:** Compound's
  condition only ever moves one direction observable from HP loss (Toll
  never decreases from healing), so `_set_player_hp()` only called
  `_update_hand_affordability()` on `lost > 0`. Paid in Pain's condition
  is HP-based in BOTH directions - healing back above half HP needs to
  un-arm a Paid in Pain already in hand exactly as promptly as dropping
  below half arms one, and the loss-only gate left that direction
  stale. Fixed by moving the `_update_hand_affordability()` call to fire
  on ANY HP change (`RunState.player_hp != old_hp`), not just a loss -
  Toll's own accrual-on-loss logic above it is untouched, this only
  widened when the hand gets told to re-check itself.

Verified headlessly (regression + new cases): all of the original 16
condition-indicator checks above still pass unchanged; Paid in Pain
reports inactive at full HP and active below half HP via
`_card_condition_active()` directly; a Paid in Pain already in hand
picks up the frame the instant HP crosses below half via `_deal_self_
damage()`/`_set_player_hp()`, AND correctly drops the frame again when
healed back above half in the same mock hand - the specific direction
the gap above was found in.

**Fix pass (2026-08-27, live-play correction) — the frame wasn't reading
at all, and text emphasis was too narrow.** Two problems reported once
seen in an actual battle (Compound in hand at Toll 23, condition live):

- **ConditionFrame was invisible in practice - a rendering/compositing
  problem, not a toggle-wiring bug.** Confirmed headlessly first (per
  this fix's own brief: verify before assuming) that `condition_frame.
  visible` and its StyleBoxFlat's border properties were all correct at
  runtime - the bug wasn't there. The real cause: `condition_frame`
  shared Visual's EXACT rect (same anchors, zero offset), so its border
  drew directly on top of Visual's own rarity border (`StyleBoxFlat_
  default`, 4px, fully opaque) - a thinner (3px), semi-transparent
  (0.6 alpha) second border stacked in the identical pixel band just
  tints whatever's already there rather than reading as a separate
  element, especially on a RARE card (Compound), whose border is
  already a saturated blue in roughly the same cool family as the
  frame's own old teal. Root-caused, not just retuned: new `condition_
  frame_expand_px` (5px) pushes the frame's own rect outward past
  Visual's edge in `_apply_layout()`, the same "extends outward, never
  overlaps the border" relationship `chain_glow`'s own shadow already
  has with it - just via a wider rect instead of a blur, keeping this a
  hard-edged border by design (still a different MECHANISM from chain_
  glow, per that field's own doc).
- **Color axis was wrong.** The original pick (a cool teal) was chosen
  to avoid colliding with `ARMED_MODULATE`'s warm gold - but the
  SELECTED/armed border isn't the only, or even the primary, border a
  condition-active RARE card sits beside: `RARITY_BORDER_COLORS[RARE]`
  (card.gd's own dict) is a prominent, saturated blue, and a cool teal
  frame is in the same family as blue, not gold. Corrected to a vivid
  crimson/magenta (`Color(0.85, 0.15, 0.4, 1)`) - clear of RARE's blue
  first, and still clear of `ARMED_MODULATE`'s gold second (a saturated
  magenta stays reddish-pink even multiplied by a warm tint, never
  reading as "more gold").
- **Intensity raised substantially** (`condition_frame_intensity` 0.6 ->
  0.92, `condition_frame_width_px` 3px -> 4px) - re-scoped as the
  PRIMARY signal for condition-active, with the text re-weighting below
  as secondary support, not the reverse. Needs to read at a glance while
  scanning a hand, not reward a close look.
- **Text emphasis moved from number-level to CLAUSE-level.** Wrapping
  only the numeral (`[cond_inactive]6[/cond_inactive]`) read as
  typographic noise - one bold digit floating in an otherwise-normal
  sentence - rather than a state change, and left the base line at full
  strength while the conditional number was bold, presenting two
  simultaneously "live-looking" numbers. `expand_conditional()` itself
  needed NO code change (already pure text-replacement, agnostic to
  what it wraps) - only Compound's own markup changed, wrapping each
  FULL CLAUSE: `"[cond_inactive]Deal 6 damage.[/cond_inactive]\n[cond_
  active]If Toll is 15 or more, deal 16 damage instead.[/cond_active]"`.
  Inactive still strips to nothing (unchanged "normal styling
  throughout" behavior); active now bolds/brightens the ENTIRE
  conditional line and dims the ENTIRE base line, both directions of
  contrast present at once, exactly this fix's own brief.

Verified headlessly (22 checks, on top of the original 16/19-check
suites from the two earlier passes, both of which still pass
unchanged): `condition_frame`'s rect offsets are pushed outward by
`condition_frame_expand_px * scale` in `_apply_layout()`, clear of
Visual's own border band; the frame's border color/alpha match the new
crimson/high-intensity values; Compound's rendered description at Toll
14 shows the base clause at full DescriptionLabel default color/weight
with no emphasis anywhere; at Toll 15+, the base clause carries the
dimmed color with no bold, and the conditional clause carries bold +
the active color, across each clause's FULL text, not a single
substring; and the armed (`ARMED_MODULATE`) case still leaves the
frame's own crimson distinguishable from both the plain RARE blue
border and the warm gold tint once modulate is applied on top.

## Card Upgrades (DECIDED — mechanism + shop integration)

A card upgrade REPLACES a card with a different `CardData` resource
outright, rather than applying a numeric delta/modifier to the existing
one. Deliberate: an upgrade needs to be able to change a card's damage,
energy cost, HP cost, Toll interaction, chain role, name, and flavor
text - not just its numbers, which a delta/modifier system (the kind
`weapon_modifier.gd` already uses for equipment) can't express. Full
resource replacement handles both a trivial "+3 damage" bump and a
complete identity change with the same mechanism, so even the simple
case goes through it.

**Data model:** `CardData.upgrades: Array[CardData]` - a card's possible
upgrades, authored as ordinary, complete `CardData` resources in their
own right (not partial "diff" objects). Empty/unset (every base card
before this pass) means the card can't be upgraded. Most cards are
expected to carry exactly one entry (a straight improvement); a
signature card can carry two, offering a directional choice instead -
the list itself carries both shapes with no mode flag, since `card_
upgrade_service.gd` only ever branches on `upgrades.size()` (1 vs.
more), never on anything authored here. An upgraded card's OWN
`upgrades` list is expected to stay empty - no chained upgrades. This is
an AUTHORING convention, not something enforced in code: as long as
every upgrade `.tres` leaves the field empty, chaining is structurally
impossible without someone deliberately adding code for it later.

**Deck representation this relies on:** `RunState.deck: Array[CardData]`
holds ONE DISTINCT resource instance per deck slot (2026-08-29, per-copy
card identity pass - see the dedicated section just below this one for
the full decision; before that pass, 5x Slash in the deck was literally
the same preloaded object 5 times over, and this paragraph used to say
so). `RunState.replace_card_in_deck(old_card, new_card)` finds the
matching array slot by object identity and overwrites it in place - now
correctly the SPECIFIC copy `old_card` actually refers to, not merely
"a" same-named slot that happened to be first, since every slot is its
own object.

**`card_upgrade_service.gd`** - a new autoload (`card_upgrade_service.
tscn`, same "scene autoload" shape every other one here uses), callable
from anywhere as `CardUpgradeService.offer_upgrade(filter)`. `filter` is
an optional `Callable(CardData) -> bool`; an invalid/unset one (the
default) means every upgradeable deck card is eligible. Returns a
Dictionary (`{"outcome": Outcome, "old_card": CardData, "new_card":
CardData}`, same "plain Dictionary for a one-shot multi-field return"
shape `battle.gd`'s own `_resolve_damage()` already uses) rather than a
new typed result class - `Outcome` is `UPGRADED`/`CANCELLED`/`NO_
ELIGIBLE_CARDS`. A caller must `await` it (it's a real coroutine, not
fire-and-forget only when the return value is discarded - see `battle.
gd`'s own `_on_dev_upgrade_button_pressed()`/`_run_dev_upgrade()` split
for the fire-and-forget shape). `NO_ELIGIBLE_CARDS` is reported with NO
overlay ever shown - a caller (a future shop) is expected to check this
itself rather than let the player buy/trigger an upgrade with nothing to
spend it on.

**Selection UI reuses `DeckViewer`, not a new overlay.** `deck_viewer.
gd` already has a general "pick one card out of a list" selection mode
(`open_cards(cards, title, selection_mode, manage_pause)`, emitting
`card_selected`) - `shop_window.gd`'s existing "Remove a Card" flow
already proves this shape works for picking one card out of the LIVE
deck specifically (as opposed to `reward_screen.gd`'s card-choice modal,
built for a small curated set of fresh options, not the deck itself).
`card_upgrade_service.tscn` owns its OWN private `DeckViewer` instance
as a child, rather than depending on whichever scene happens to have one
already wired up (the way `shop_window.gd` currently requires `field_
room.gd` to hand it a reference) - `DeckViewer`'s own header already
states it's built to be added "as a plain child anywhere in its tree"
with "no wiring back to the caller needed," which is exactly what makes
a global service owning a private instance the correct, zero-setup
shape. The service awaits `card_selected` (a card was picked) or
`visibility_changed` going false with nothing picked (Escape/Close, both
already route through `DeckViewer.close()`) to tell a real pick apart
from a cancel; the same "reconnect defensively since a cancelled one-
shot connection stays attached" idiom `shop_window.gd`'s own removal
flow already uses, since a lambda can't be `is_connected()`-matched
across calls the way a named method can.

**Flow:** gather eligible cards (has at least one upgrade AND passes
`filter`) -> if none, report `NO_ELIGIBLE_CARDS` immediately -> open
`DeckViewer` in selection mode over the eligible cards -> on pick, if
`upgrades.size() == 1` apply it directly, otherwise open `DeckViewer`
again over the two options -> `RunState.replace_card_in_deck()` -> report
`UPGRADED`. Cancelling at EITHER stage leaves `RunState.deck` completely
untouched - nothing writes to it before the final replace call.

**Authored upgrades (this commit, starter deck only):** straightforward
numerical bumps, no branching -
`resources/cards/upgrades/slash_plus.tres` (6 -> 9 damage), `guard_
plus.tres` (5 -> 8 block), `bite_down_plus.tres` (10 -> 14 damage, the 2
HP cost and OPENER chain role both unchanged). Kept in their own
`resources/cards/upgrades/` folder, sibling to `resources/cards/classes/`
- clear of `CharacterData.card_pool_folder` (`res://resources/cards/
classes/wanderer/`), so none of these can ever be scanned into the
reward/shop pool by accident (`CardPool.load_class_pool()`'s own `Dir
Access.get_files()` isn't recursive regardless, but this also doesn't
depend on that for correctness - they were never inside the scanned
folder in the first place, same as the base Slash/Guard/Bite Down
themselves).

**Dev trigger:** `battle.tscn`'s new `DevUpgradeButton` calls `CardUpgrade
Service.offer_upgrade()` with no filter - same "safe to click, dev-only"
spirit as `DevDamageButton`/`DevStatusButton`/`DevEscapeButton`. Only
ever touches `RunState.deck` - an upgrade triggered mid-battle has no
effect on that battle's own already-copied draw/hand/discard piles, same
already-accepted behavior `add_card_to_deck()`/`remove_card_from_deck()`
have; the change shows up next battle, or immediately via the Deck
button.

**Out of scope for the mechanism commit (per its own brief):** shop
integration (now built, see below), items, events, upgrade balance,
branching upgrades, any change to the deck viewer itself, and any change
to how cards play.

Verified headlessly: gathering eligibility (including a filter that
excludes everything, reported as `NO_ELIGIBLE_CARDS` with no overlay
shown); picking a card and its upgrade correctly swaps exactly one deck
slot (verified against a real Slash -> Slash+ swap, deck size
unchanged, count of each name correct); cancelling at the card-choice
stage leaves `RunState.deck` byte-for-byte unchanged; the two-option
branch (a synthetic test card, since no real card branches yet) opens a
second selection stage and swaps in whichever option was actually
picked; the dev button is wired correctly inside a real instantiated
`battle.tscn`.

**Shop integration (second commit).** `shop_window.gd` gains an
"Upgrade a Card" offer, presented alongside "Remove a Card" - one FLAT
`upgrade_price` (60g, between removal's own base 50g and a rare card's
80g), deliberately NOT derived from the selected card or its upgrade:
the player's decision here is WHICH CARD to improve, not which upgrade
to buy (every card offers at most a small, curated set of upgrades
decided at authoring time). Repeatable within a visit, same as Remove a
Card (no one-shot "already used" flag on either) - `_refresh_after_
purchase()` re-evaluates the row's own affordability/eligibility after
every purchase exactly like it already does for `remove_row`.

- **Eligibility, not just affordability:** the row is greyed (`set_
  affordable(false)`, ShopRow's existing single boolean) whenever gold is
  short OR the deck has nothing upgradeable left - both fold into that
  one existing call rather than adding a second "eligible" concept to a
  shared component. The eligibility half reads `CardUpgradeService.has_
  eligible_cards()`, a new PUBLIC wrapper around the service's own
  existing (previously private) `_gather_eligible()` check - added
  specifically so the shop never re-derives "does the deck have an
  upgradeable card" as a second copy of that rule.
- **A real, necessary fix to the service itself, not scope creep:**
  `offer_upgrade()`'s internal `DeckViewer` call hardcoded `manage_
  pause=true` in the mechanism commit (its only caller, `battle.gd`'s
  dev button, isn't already paused). Calling it from the shop - already
  paused - unconditionally with that hardcoded true would have UNPAUSED
  the tree the instant the upgrade overlay closed, waking the field up
  while the shop was still visibly open on top of it - the exact bug
  `shop_window.gd`'s own `_on_remove_pressed()` already documents
  guarding against for its OWN nested `DeckViewer`. `offer_upgrade()`
  now takes an optional `manage_pause` (default true, preserving the dev
  button's existing behavior); the shop passes `false`.
- `CardUpgradeService` owns its OWN private `DeckViewer` instance (see
  the mechanism commit's own note on why) rather than reusing `shop_
  window.gd`'s externally-wired one the way "Remove a Card" does - two
  different services, two different `DeckViewer` instances, both able to
  show a selection overlay on top of the still-open shop panel
  underneath, same visual stacking either way (both scenes' own `layer`
  values already sit above `shop_window.tscn`'s).

Verified headlessly against a real instantiated `ShopWindow` + its own
`DeckViewer`: buying with sufficient gold replaces the card, deducts
gold, and leaves the tree still paused (not woken by the service's own
close - confirming the `manage_pause` fix); cancelling mid-selection
changes neither gold nor the deck, and leaves the row enabled; gold
below `upgrade_price` disables the row; a deck with no upgradeable cards
disables the row and the overlay never opens even if `buy_pressed` is
forced; upgrading one of 5 identical Slashes (a fresh reset deck)
produces exactly 4 Slash + 1 Slash+, not 5 Slash+; the upgraded card
shows up in both a freshly-instantiated `battle.tscn`'s own draw pile/
hand and in `DeckViewer`'s own "Belongings" grid.

## Per-Copy Card Identity (DECIDED — Option A: duplicate at grant time)

Before this pass (2026-08-29), `RunState.deck: Array[CardData]` held
shared resource REFERENCES, not per-copy instances - 5x Slash in the
deck was the same preloaded object 5 times over, both for the starting
deck (`_build_starting_deck()`'s `STARTING_DECK` dictionary keys) and
for every card granted afterward (`add_card_to_deck()`'s caller handing
over whatever `CardPool.load_class_pool()` gave it, which - since
Godot's `load()` caches by path - is the exact same engine-cached object
for every reward roll/shop slot/NPC offer that ever names the same card
in one run). That collapsing was harmless as long as nothing needed to
tell two copies of the same card apart: `card_upgrade_service.gd`'s own
"upgrade any one of N identical Slashes" framing (see the Card Upgrades
section just above) was written explicitly assuming it never would.

It stopped being harmless once a mechanic needed to target one SPECIFIC
physical copy rather than a card type - the motivating case was a boss
attack meant to mark one particular card in the discard/draw pile (still
not implemented as of this decision - see its own investigation report).
With every same-named copy sharing one object, "mark this exact card"
and "mark every copy of this card everywhere in the run" were the same
operation - not a viable foundation for that kind of effect, and not one
that scales to branching upgrades either (two copies of the same base
card independently taking different upgrade paths needs the deck slots
to already be distinguishable BEFORE either is touched).

**Two approaches were assessed** (full investigation report, not
reproduced here): (A) duplicate `CardData` per deck slot at the moment a
card enters `RunState.deck`, so identity Just Works everywhere that
already compares/erases/finds by reference; (B) a lightweight
`CardInstance` wrapper (`RefCounted`, same shape as `ActiveStatus`/
`EnemyCombatant`) holding a reference to the shared, immutable authored
`CardData` plus per-instance runtime state, with `RunState.deck` and
every battle pile retyped to hold wrappers instead.

**(A) was chosen.** The actual gap was narrow - two call sites
(`RunState.add_card_to_deck()`, the one chokepoint every grant path
already funnels through; `_build_starting_deck()`'s own separate loop,
which doesn't) - and closing it there makes every existing identity-
based site (`remove_card_from_deck()`'s erase, `replace_card_in_deck()`'s
find, the shop/reward pools' own "don't offer this roll twice" erases)
correct FOR FREE, with zero changes anywhere else: `battle.gd`'s piles,
`card.gd`'s rendering, `deck_viewer.gd`, `shop_window.gd`, `card_
glossary.gd`, `reward_screen.gd`, and `card_upgrade_service.gd` all
already treated a deck/pile entry as a plain `CardData` reference, and
still do - the only difference is that reference is no longer
accidentally shared. (B) would have touched essentially the whole
card-handling surface (every `Array[CardData]`-typed export/parameter/
signal in ~28 files, GDScript having no transparent field delegation to
avoid rewriting every direct field read) to solve a larger, more general
problem than the one actually in front of us.

**Duplication depth: shallow (`CardData.duplicate()`'s own default,
`subresources = false`), not deep.** `CardData.effects: Array[CardEffect]`
and `chain_followup_effect: CardEffect` stay shared references to the
same authored effect objects across every duplicated copy of a card -
confirmed safe by checking every direct field WRITE onto a `CardEffect`
project-wide: the only one found (`battle.gd`'s own `_chain_payoff_
effect`) configures a throwaway `CardEffect.new()` Battle owns privately,
never one read off a card's own `effects` array. Nothing mutates a
loaded `CardEffect` (or a `StatusEffectData` one points at) at runtime,
so every copy of "Slash" safely reading the exact same immutable
Damage-6 `CardEffect` is correct, not a latent bug one level down - a
deep duplicate would only spend memory defending against a mutation that
structurally cannot happen. Same reasoning extends to `upgrades: Array
[CardData]`: upgrade candidates are read-only menu options, never
mutated before or after being chosen, so leaving every duplicated copy
of "Slash" pointing at the ONE canonical `slash_plus.tres` (rather
than each minting its own duplicate of it) is correct, not an oversight.

**Enforcement is by convention, not the type system.** Nothing stops a
future call site from appending an un-duplicated, `load()`-sourced
`CardData` straight into `RunState.deck` and silently reintroducing
shared references - the two duplication sites are the only thing
maintaining the invariant, and there's exactly one real chokepoint
(`add_card_to_deck()`) plus one loop (`_build_starting_deck()`) to keep
honest, not a scattered set. `CardData` itself carries no marker that
would let a future reader detect a violation after the fact.

**The documented fallback, if this stops being enough:** a `CardInstance`
wrapper (Option B above) - specifically once `CardData` starts
accumulating MULTIPLE independent kinds of per-instance runtime state at
once (a temporary cost modifier, an upgrade-branch marker, a mark-attack
flag, all potentially live on the same copy simultaneously). At that
point "just add another plain field to `CardData`" starts to strain the
same way it would for any resource asked to be both static authored data
and a growing pile of mutable runtime state, and the clean split a
wrapper gives - authored data immutable and shareable, runtime state
genuinely per-instance - stops being optional cleanliness and starts
paying for the wider rewrite it costs. Nothing found in this decision's
own investigation suggests that point has been reached yet.

## Rewards

Post-battle rewards will eventually include multiple types: cards, gold
(currency), equipment (three slots — weapon / armor / trinket, making
Pillar 3's rare drops concrete), and possibly quest/story items. The
reward screen's architecture should treat reward types as extensible —
adding a new type should not require restructuring the screen.

**First reward types built:** cards and gold only (see reward screen v1).
Equipment, and quest/story items if they happen, come later.

**Card acquisition philosophy (DECIDED — cards are drops, not
currency):** cards used to be a guaranteed three-choice pick every
battle - a fixed reward slot the player always saw, which made it feel
like a currency payout (always there, always the same shape) rather
than something found. That undercut Pillar 3 (rare drops should be
exciting) for cards specifically, even though equipment was always
meant to feel this way.

- **Regular card reward:** no longer guaranteed. A card-choice row
  (three options, COMMON/RARE only - see `card_reward_chance`,
  default 60%) appears most battles, not every battle. When it doesn't,
  the loot window is just gold, and that's a normal outcome, not a
  worse one - see reward_screen.gd's `_generate_loot()`.
- **ULTRA_RARE arrives as an unchosen gift**, not a slot in the regular
  three-choice pool. Its own independent roll (`rare_drop_chance`,
  default 8%) can land on any battle regardless of whether the regular
  card roll also hit - a victory can produce both, either, or neither.
  It shows up as its own visually-elevated loot row (gold border,
  thicker frame - see loot_row.gd's `_apply_rarity_style()`), suggestive
  rather than descriptive before it's opened ("Something Rare," not the
  card's name). Clicking it opens a reveal - the card at the same larger
  scale the regular choice uses, with a short beat of animation - then
  Take or Leave, never a choice between alternatives (see
  reward_screen.gd's `_open_rare_drop_reveal()`).
- **SECRET_RARE stays excluded from every drop table** - reserved for
  world discovery and optional difficult encounters, not yet designed
  (see Open Questions and Ideas Parking Lot).

**Loot row architecture holds:** LootEntry's `LootType` enum plus
reward_screen.gd's single `_claim_entry()` dispatch point already
treated every reward as "a type tag plus whatever data that type
needs" (see reward_screen.gd's header comment) - the rare-drop row
slotted in as one more enum value, one more `_claim_entry()` branch,
and one more `create_*()` factory, without touching the window's
layout or claiming flow. A future equipment drop follows the identical
shape: `LootType.EQUIPMENT`, a `LootEntry.equipment_data` field, a
`create_equipment_drop()` factory, and a `_claim_equipment()` branch
that adds it to the player's loadout instead of the deck - the same
"gift, single row, one dispatch branch" pattern the rare card drop
already proves out, likely reusing the same elevated-row styling for
its own rarity tier.

**Chest rewards route through the loot window (DECIDED, implemented
2026-08-25):** a field chest used to apply its gold directly to
`RunState` the instant it was touched, silently, with its own separate
floating "+N Gold" popup - a different presentation from a battle
victory's gold for no real reason, and a missed chance to reuse the
claim-with-a-tick-up moment the loot window already does well.
Presentation only - what a chest actually CONTAINS is untouched (still
gold only; see the "still open" list below the equipment note, since
richer chest contents are pending exactly that design work).

Mechanically: `field_chest.gd` rolls the amount and hands it off via a
new `RoomState.pending_chest_gold` (same "set right before the
transition, read once by the destination scene" shape `pending_enemy_
data` already established for field_blob.gd's own battles - see its
own doc comment), then transitions straight to `reward_screen.tscn`
instead of touching `RunState.gold` at all. `reward_screen.gd`'s
`_ready()` checks that field FIRST: if set, the loot list is built as a
single gold-only `LootEntry` directly - `_generate_loot()`'s own random
rolling (which could otherwise hand a chest a card choice or a rare
drop) never runs for this path at all. A local `_is_chest_reward` flag,
copied from that check, is what lets the SAME `_continue_to_next_
battle()` that already returns a battle victory to the field room do
the same for a chest - skipping `RunState.advance_to_next_battle()`
(a chest isn't a fight) but reusing the exact same `SceneTransition.
go_to("res://field_room.tscn")` return path, which is also what makes
the room resume correctly: nothing about that path resets room-local
state (`RoomState.reset_room()` only runs between DIFFERENT rooms), so
`chest_opened` (and the chest's own already-opened silhouette,
untouched by any of this) survives the round-trip for free, the same
mechanism a defeated field blob already relies on. Also carries over
field_blob.gd's own "remember where the player was standing"
handoff (`RoomState.player_position`/`has_saved_position`) - without
it the field would have resumed at its default entrance spawn instead
of where the chest was. The "Leave unclaimed loot?" confirmation
(`_has_unclaimed_loot()`) needed no changes at all - it already just
checks the generic `loot` array, regardless of how it was populated.

Verified headlessly: opening a chest sets the hand-off fields and
captures the player's position without touching `RunState.gold` at
all; the reward screen correctly builds a gold-only single-entry loot
list and clears the hand-off field; claiming that row through the real
claim path adds the gold and correctly clears the unclaimed-loot flag;
and a fresh chest instance in an already-opened room starts in the
opened state with no click listener reconnected, confirming re-entry
can't re-trigger it.

**Follow-up fix - the transition felt slow (DECIDED, implemented
2026-08-25):** the first version waited for the open flourish to fully
finish (`lid_open_duration_sec + OPEN_FLASH_DURATION`, ~0.5s) before
even starting `SceneTransition.go_to()`, which then adds its OWN fixed
fade cost (0.3s out, swap, 0.3s in) on top - over a second total,
noticeably slower than every other field trigger in the game.
field_blob.gd's own touch-to-battle transition is instant on contact,
no pre-wait at all. Fixed the same way: the explicit wait was removed
entirely, `SceneTransition.go_to()` now fires immediately after
starting the flourish tween rather than after it. The flourish still
reads fine - it keeps animating and stays visible through the fade-out
on its own, it never needed a dead stop first to be seen.

**A chest's weapon drop is a loot row now, not an auto-opened screen
(DECIDED, implemented 2026-08-25):** a chest's weapon used to skip the
loot window entirely - `reward_screen.gd`'s `_ready()` forced the Equip/
Leave Behind decision the instant the screen loaded, before the gold row
(or anything else) was ever reachable, same as a Pay House or dev-grant
weapon still does today. For a chest specifically, that read as the
window jumping straight past its own gold row to a decision the player
hadn't asked to make yet. It's a row now, exactly like gold/card-choice/
rare-drop: `_display_loot()` builds one from the WEAPON entry (name
only, serif world-voice font via `loot_row.gd`'s new `WEAPON_NAME_FONT`,
an empty slot reserved beside it for a future system-voice subtype
indicator - trinket vs. weapon, once a second equipment type exists),
and `_claim_entry()`'s new WEAPON case is what opens `weapon_pickup_
window` on click. Nothing about that window itself changed - same
Equip/Leave Behind screen, same equipped-weapon comparison.

The one real behavioral difference from every other row type: Leaving a
chest's weapon does NOT claim its row. It stays exactly as unclaimed and
clickable as before, so the same weapon can be reconsidered again before
the chest is closed - `_active_weapon_row`, set explicitly by whichever
call opened the window (never inferred from `RoomState` after the fact),
is what tells `_on_weapon_pickup_resolved()` a row exists to return to at
all. Taking it DOES claim the row, but the row is removed outright rather
than left behind greyed-out with a checkmark - there's nothing left to
compare once it's equipped, unlike a claimed gold/card/rare-drop row,
which still has something worth showing (the amount, which card was
picked). Closing the chest (`_on_continue_pressed()`) skips the "Leave
unclaimed loot?" confirmation for a chest specifically now, regardless of
what's still sitting unclaimed - open question, not fully settled: if a
weapon drop turns out to be significant enough that silently losing one
to an unnoticed close reads as a bug rather than a real choice, this is
the branch to add a confirmation back to.

A weapon from any OTHER source (the Pay House, a title-screen dev-grant)
is completely unaffected - still the exact same immediate auto-open, no
row, no loot list, since neither ever pairs a weapon with other loot for
a list to be worth building in the first place.

**Equipment as card modifiers (DIRECTION DECIDED 2026-08-25, needs a
design session with my brother before implementation):** resolves
Open Questions' long-standing "what does equipment actually do." Two
things equipment is explicitly NOT: a source of passive stat boosts
(boring, inflationary - a bigger number doesn't change how a fight is
played, just how big the numbers in it are), and a source of granted
cards (that's the subjob system's own role - see Pillar 2 - and
equipment doing it too would blur two systems that should stay
distinct). Instead, equipment MODIFIES how existing cards behave -
reference point: Hades' boons and Daedalus hammers, which alter your
existing abilities rather than adding new ones, so a run's identity
comes from what changed about your core tools, not from how many tools
you've accumulated.

Example shapes (illustrative, not final designs - actual modifiers are
part of the still-needed design session): Strikes drain HP, chains
refund energy instead of HP, the first card played each turn costs
nothing, blood costs (Wanderer-specific - see its own Characters entry)
are halved, Closers hit twice.

**Why this is worth building, not just thematically tidy - it resolves
several separate open problems at once:**
- TREASURE rooms finally get something worth stopping for. They used to
  hand out gold only (see the Shop section's own economy math) and were
  strictly worse than a COMBAT room, which also grants gold on top of
  a card shot - a real (if low-odds) chance at equipment (IMPLEMENTED
  2026-08-27 - see below) gives this room type its own reason to exist.
- Gold gets something worth spending on beyond cards already declined
  at the shop - currently its only sink.
- ELITE rooms get a concrete reason to be worth the extra danger
  (better equipment), not just a harder fight for its own sake.
- The loot window gets its second row type, the exact extension point
  `LootType`/`_claim_entry()` were already architected for (see the
  paragraph above) - this was speculative scaffolding until now.
- Pillar 3's rare drops (FFXI-inspired, in the design since the
  Pillars were first written) finally has a concrete thing to BE,
  not just a stated intention.
- A small number of modifier pieces still produces real run-to-run
  variation, without needing a large content budget - the right kind
  of scope for a small team, the same reasoning that already shaped
  the Bestiary's own "few creatures, real identity" approach.

**Still open, blocking full implementation:** the armor/trinket slots
(weapon is now built - see the IMPLEMENTED note below - but nothing
about how it was built commits armor/trinket to the same shape). How
many modifiers can be active/stacked at once, once there's more than
one slot? Acquisition is PARTIALLY resolved now - weapons drop from
TREASURE chests (2026-08-27, see below) and can now also be chosen
deterministically at The Pay House (2026-08-23, see the Sunken Works
section above) - but that's two sources out of several still on the
table (shop listings, COMBAT/ELITE/BOSS reward tables) and answers
nothing about armor/trinket's own acquisition once they exist.

**IMPLEMENTED (minimal, dev-testable, 2026-08-22):** a first slice
answering "what kind of thing is equipment" in code, not just design
prose - one slot (weapon), one item (Last Wages), gated behind a dev
button, no drop-table wiring. Resolves two of this note's open
questions outright; leaves the rest (armor/trinket, stacking,
acquisition) for later.

- `RunState.equipped_weapon: WeaponData` - one flat field, null at the
  start of every run. Deliberately not a slot dictionary/enum system
  built ahead of need - armor/trinket, if they happen, arrive later as
  sibling fields following this exact shape, per this session's
  explicit "do NOT build them now" instruction.
- `WeaponData` (`weapon_data.gd`) - same Resource-per-.tres pattern as
  CardData/EnemyData: `weapon_name`, `rarity` (reuses CardData.Rarity,
  same border-color language card.gd already draws from), `description`
  (lore text ONLY, per Pillar 3/4(b) - see below), and `modifier`.
- `WeaponModifier` (`weapon_modifier.gd`) - a small CLOSED set of
  shapes, not an open-ended effect system, mirroring CardEffect's own
  "one Resource, an enum saying what kind, a value" shape:
  - `CATEGORY_DAMAGE` - +value damage on DAMAGE-type card effects,
    scoped to ALL_ATTACKS/OPENERS/CLOSERS via a small purpose-built
    `TargetScope` enum (not a reuse of CardType/ChainRole directly -
    a future modifier might filter on something neither expresses).
  - `CHAIN_PAYOFF_DAMAGE` - +value damage on a chain's own payoff hit
    specifically, ONLY when that payoff is itself DAMAGE-type - a
    Closer whose payoff is a HEAL (no card sets one today - Blood
    Tithe's own refund was removed 2026-08-26, see the Wanderer's own
    Characters entry) would be untouched by design, not a bug: a
    weapon about striking harder shouldn't inflate a sustain effect.
  - `CATEGORY_ENERGY_COST` - -value energy cost (floored at 0),
    same TargetScope. Every read of `CardData.energy_cost` in
    battle.gd (affordability display, the play-guard, the actual
    spend - four call sites) routes through one shared
    `_effective_energy_cost()` helper, so a cost modifier can never
    make a card LOOK unaffordable while it's actually playable.
  - `SELF_DAMAGE_REFLECT` (The Creditor, 2026-08-27) - the first shape
    that ISN'T "adjust one number on the effect that's resolving": when
    a card's own SELF_DAMAGE effect resolves, the SAME amount lands on
    the card's target as a separate follow-up hit
    (`battle.gd`'s `_reflect_self_damage()`, called from the SELF_
    DAMAGE branch of `_resolve_card_effect()`). Ignores `target_scope`
    (no "which cards" - every SELF_DAMAGE effect qualifies) AND ignores
    `value` (a strict 1:1 mirror per the brief, not a tunable
    multiplier - overloading `value` with different math than every
    other Kind uses it for would confuse more than it'd save). Three
    resolved implementation questions:
    - **No target?** A SELF_DAMAGE-only card with no DAMAGE effect of
      its own never triggers `_card_needs_target()` in the first place,
      so `target` is `null` when it resolves - the reflect just no-ops.
      Same "empty means unaffected" shape every other weapon check uses.
    - **Multi-enemy: which target?** The card's OWN existing target,
      not all enemies - `_resolve_card_effect()` already has the exact
      `EnemyCombatant` the card was aimed at, so this needed zero new
      targeting logic. Also avoids a balance trap (a single-target
      self-damage card silently becoming an AoE multiplier just because
      three enemies are on screen) and reads better fictionally (the
      cost becomes damage against THIS fight, not a curse on the room).
      Verified with a real 2-enemy fight headlessly: the untargeted
      enemy takes zero reflected damage.
    - **Non-card self-damage sources?** None exist - `_deal_self_
      damage()` has exactly one caller today (SELF_DAMAGE's own branch),
      always triggered by a card, so this never needed extra scoping to
      stay card-only.
    Feedback: the shared red hit-flash (`_play_flash()`) is untouched -
    "you got hit" stays universal, chain or reflect or otherwise. On
    top of that, the reflected hit gets its own floating-number color
    (`battle.gd`'s `weapon_reflect_number_color`, a steel-blue,
    `@export`ed - required `enemy.gd`'s `flash_damage()`/`_spawn_
    floating_damage()` to accept a color argument instead of always
    hardcoding `FLASH_COLOR`, its only other caller), a layered sfx cue
    (`"weapon_reflect"`, no file recorded yet - same placeholder
    convention as `card_refused`/`block_gained`), and a short stagger
    (`weapon_reflect_delay_sec`, 0.15s - shorter than the chain
    payoff's 0.3s, since this is a smaller, more incidental effect, not
    its own dedicated "moment") so it reads as a distinct second hit
    rather than a number popping on top of the card's own damage number
    in the same frame. Rides the NORMAL screen-shake tier, not a third
    tier of its own.
  - Adding a 5th shape means: one enum value, one case wherever the
    numeric helpers dispatch on kind - or, if the shape isn't "adjust
    one number" (e.g. a structural rule like "draw an extra card"), a
    small dedicated hook elsewhere, the same way HEAL needed no new
    chain-payoff machinery but a hypothetical DRAW-type payoff would,
    and SELF_DAMAGE_REFLECT needed its own dedicated function rather
    than reusing `_weapon_modified_value()`.
  - The mechanical line (e.g. "Chain payoffs deal +4 damage") is
    GENERATED from the modifier's own data (`describe()`), never
    hand-written - this directly answers the open question above about
    lore text competing with mechanical text: they're not the same
    field at all. `WeaponData.description` stays pure flavor prose;
    `WeaponModifier.describe()` is the only place rules text is ever
    produced, so retuning how a shape reads never means hunting
    through multiple UI scripts.
- **Last Wages** (RARE, `resources/weapons/last_wages.tres`).
  `CHAIN_PAYOFF_DAMAGE +4`. *"Paid out before the work was finished.
  Whoever it was owed to never came to collect."*
- **The Creditor** (RARE, `resources/weapons/the_creditor.tres`,
  2026-08-27) - the second weapon, continuing the debt/labor/payment
  vocabulary Last Wages started (the alternate name floated and unused
  when Last Wages was first proposed - see this section's own
  IMPLEMENTED note history). `SELF_DAMAGE_REFLECT`. *"Debts come due
  eventually. This one doesn't wait - it simply collects, from
  whoever's standing closest."* No icon art yet.
- Loot integration: `LootEntry.LootType.WEAPON` (loot_entry.gd) and a
  matching `_claim_weapon()` branch in reward_screen.gd's
  `_claim_entry()` dispatch - the exact extension shape RARE_CARD_DROP
  already proved out (one enum value, one branch, one factory function,
  the row/claim UI itself unchanged). Claiming into an empty slot
  equips immediately; claiming with a weapon already equipped opens a
  side-by-side swap decision (`WeaponSwapOverlay` in reward_screen.tscn)
  instead - modeled on the card-choice overlay's instant open/close +
  paused-tree pattern (a real comparison between two known things), not
  the rare-drop reveal's fade-based full takeover (a single unveiling).
  Not exercised by real gameplay yet (nothing's in a drop table), but
  the swap path is unit-tested directly (see below) and now has a
  second real weapon (The Creditor) to actually swap TO once both are
  dev-granted in the same run.
- **Icon art (`WeaponData.icon_texture`, optional):** same "empty means
  no art" shape as `CardData.art_texture`, assets living in `assets/
  equipment/weapons/`. Left null, every display below falls back to
  exactly how it rendered before this field existed - text only, no
  error. Last Wages now has real art wired in.
- **`WeaponCard` (`weapon_card.gd`/`.tscn`), the one consistent
  equipment presentation:** structurally similar to `Card` (see
  card.gd) - an outer frame, a name zone, an art zone, in a
  VBoxContainer whose stretch ratios reserve each zone a fixed
  proportion - but deliberately distinct enough to never read as "a
  card you could play": a dark metal-plate palette instead of Card's
  parchment tone, sharper corners, no cost badge (weapons aren't
  played), and two SEPARATE text zones below the art - a generated
  mechanical effect line (prominent, accent blue) and a hand-written
  lore line (visually de-emphasized: smaller, muted, and genuinely
  italic via a sheared `FontVariation`, since Godot doesn't synthesize
  italics for a font with no italic style of its own). Reuses `Card.
  RARITY_BORDER_COLORS` directly for its own border - one rarity, one
  color, wherever it shows up. One instance, reused everywhere a
  weapon needs showing via `set_weapon_data()` (the same "one instance,
  re-fed" shape shop_window.gd's own card preview already established)
  - not a bespoke layout per screen:
  - **Loot-row hover preview:** hovering a WEAPON row in the loot
    window shows the full WeaponCard off to the side
    (`WeaponPreviewContainer` in reward_screen.tscn), fading in/out the
    same way shop_window.gd's own card-offer preview does. `LootRow`
    gained `weapon_hovered`/`weapon_unhovered` signals for this,
    mirroring `ShopRow`'s identical pair.
  - **The equip/swap comparison:** `WeaponSwapOverlay`'s two columns
    now each just wrap a `WeaponCard` instance (plus a small "Currently
    Equipped"/"Newly Found" tag label) instead of a bespoke set of
    icon/name/lore/effect nodes - the earlier ad-hoc version this
    replaced was built before this component existed.
  - **DeckViewer's equipped-weapon readout (REWORKED 2026-08-23, twice
    in one day):** a first pass showed a full-size, frozen WeaponCard
    pinned above the deck grid - it made the weapon feel appropriately
    significant, but at that size it ate most of the screen, leaving
    almost no room to actually see the deck. Reworked into a compact
    icon row instead: just the weapon's icon (or its name as plain text
    if it has no icon yet, or "None" if nothing's equipped - three
    states, same "empty means unaffected" shape everywhere else in this
    project uses), hoverable to reveal the FULL WeaponCard as a
    fade-in preview beside it - the same lazy-build-once-then-refeed
    pattern reward_screen.gd's own weapon-row preview already
    established (which itself mirrors shop_window.gd's card-offer
    preview), not a baked-in instance this time. `WeaponCard.gd` still
    carries the opt-in Hover export group this pass introduced (see its
    own header note on why hover is per-instance, not global to every
    WeaponCard) - it just isn't exercised here anymore now that the
    equipped row itself is a plain icon, not a WeaponCard instance.
    The equipped row is no longer pinned above a separate fixed
    ScrollContainer either - it's the FIRST item inside one shared
    scrolling VBoxContainer along with the Deck label and the grid, so
    it scrolls away with everything else instead of permanently eating
    screen space. The panel itself reads as two clearly labeled
    sections ("Equipped" above the weapon, "Deck (N)" above the grid -
    the count lives on this smaller label now, not the screen's main
    title) under the title "Belongings" (briefly "Loadout" for one
    session, retitled the same day once the screen's actual shape
    settled). Both section labels (and the equipped row) are hidden,
    and the card grid reclaims that space via ordinary VBoxContainer
    reflow, when this same viewer is opened in shop_window.gd's
    card-removal selection mode - equipment has no place in a focused
    "pick a card" task.
  - **The deck grid itself got denser**, in the same pass: its own
    card scale (`DeckViewer.deck_card_scale`) is now `@export`ed and
    completely independent of `Card`'s scale anywhere else (hand,
    reward screen, shop) - tuning how small a deck-grid card rests at
    can never shrink a hand card by accident. Legibility at a small
    resting size comes from hover: `DeckViewer.deck_card_hover_scale`
    (also `@export`ed, also independent of Card's own default hover_
    scale everywhere else) reads a thumbnail back up on hover, reusing
    Card's own existing hover mechanism (just tuned per-instance for
    this view) rather than a second enlarge system.
  - **Cards were too small, and blurry on hover (FIXED 2026-08-25):**
    the first pass (`deck_card_scale = 0.45`, `deck_card_hover_scale =
    2.6x`) made resting text barely legible AND visibly blurry when
    enlarged - a real scaling artifact, not a rendering bug: Card's
    hover animation (see card.gd's `_play_hover_tween()`) only ever
    applies a `visual.scale` TRANSFORM, a purely visual stretch of
    whatever was already rasterized at the RESTING size - fonts are
    rasterized at `name_font_size_px * deck_card_scale` and never
    re-rasterized larger just because the transform grew. At the old
    values that meant a ~10px name font visually stretched to ~26px -
    heavy blur. A FULLY crisp fix would mean re-rasterizing at native
    resolution on every hover (calling `set_scale_factor()` instead of
    only scaling the transform), but that changes `custom_minimum_
    size`, which `GridContainer` uses for cell sizing - every OTHER
    card in the grid would jump to make room the instant one is
    hovered, which is worse than the blur it would fix. The scoped fix
    instead: raise `deck_card_scale` substantially (0.45 -> 0.8, so
    fonts rasterize at an already-legible size) and lower `deck_card_
    hover_scale` to match (0.8 rest is already close to readable, so
    hover needs far less multiplication on top of it - 2.6x -> 1.35x).
    The stretch ratio, and therefore the visible blur, drops sharply as
    a result, without touching Card's shared hover mechanism at all.
  - **Columns FIXED, not fill-the-width (REFINED 2026-08-24):** the
    first version went to 10 columns to use the panel's full width,
    which fit most decks without scrolling but read badly at sizes that
    don't divide evenly - one long row plus a lone orphan card on the
    next line. `DeckViewer.deck_grid_columns` (`@export`, default 6,
    within the 5-6 range this was scoped to) now sets a FIXED row
    width instead, so the grid always resolves into clean, evenly
    filled rows - the tradeoff being more decks now need to scroll to
    see everything (verified headlessly via real ScrollContainer
    v-scrollbar math: a short deck needs none, a 30-card deck does).
  - **Equipped icon got a defined slot (REFINED 2026-08-24):** the
    bare 56px icon read as a stray floating image with nothing marking
    it as "equipment." `EquippedSlot` (a bordered, framed Panel the
    icon and its text fallback both sit inside, same dark-inset visual
    language as WeaponCard's own art slot) gives it a real container.
    Both the slot's own size (`DeckViewer.equipped_slot_size`, default
    88px) and the icon's inset within it (`equipped_icon_padding_px`)
    are `@export`ed - still deliberately much smaller than a resting
    deck-grid card (the grid card is now the bigger of the two - see
    above), since this is a glance-sized indicator, not a second place
    to cram full detail (that's still the hover preview's job).
  - **Equipped-icon hover area was misaligned (FIXED 2026-08-25):**
    hovering directly over the visible icon did nothing, while hovering
    the empty space around it opened the preview - backwards from what
    it looked like should happen. Cause: hover detection was wired to
    `EquippedIconRow`, the WIDE (near-full-panel-width) container that
    centers the slot - but `EquippedSlot`, a child `Panel` sitting on
    top of it with the default `MOUSE_FILTER_STOP`, silently claimed
    every mouse event over its OWN rect (the visible frame) without
    anything listening to IT, leaving only the empty margins around it
    to actually reach EquippedIconRow's listener. Fixed by moving the
    hover connection onto `EquippedSlot` itself - the hoverable area
    now matches the visible frame exactly - and setting `EquippedIcon`/
    `EquippedFallbackLabel`/`EquippedIconRow` all to `MOUSE_FILTER_
    IGNORE` so nothing can repeat the same shadowing at another level.
  - **Content centers vertically when it doesn't fill the screen
    (REFINED 2026-08-24, tightened 2026-08-25):** a short deck used to
    leave a large empty gap at the bottom while everything crowded the
    top of the panel - ordinary top-aligned ScrollContainer/
    VBoxContainer behavior. `_center_content_vertically()` measures the
    content block's actual height against the viewport (via
    `get_combined_minimum_size()`, read synchronously - Control's
    minimum-size system recomputes on demand, no frame-delay `await`
    needed) and grows `ContentMargin`'s top/bottom margins evenly past
    their fixed baseline (`content_top/bottom_clearance_px`, both now
    `@export`ed) to split any leftover space. Once content is taller
    than the viewport (a big deck), the "extra" slack clamps to zero
    and this is a no-op - scrolling from the top, not centering, is
    correct there. The TOP baseline used to double as hover-growth
    clearance for the grid's own first row (90px, sized for the old
    2.6x hover multiplier) - but the Equipped section itself already
    sits between this margin and the grid, well over 100px tall on its
    own, so the grid's first row was never actually at risk of
    reaching this particular margin. That made the title-to-"Equipped"
    gap far bigger than it needed to be for no real benefit; tightened
    to 24px. The BOTTOM baseline still guards genuine hover-growth
    clipping for the grid's LAST row (nothing sits below the grid to
    absorb that the way the Equipped section does above it), so it
    stays larger (60px).
  Every sizing/layout/font/hover value on WeaponCard itself
  (`design_size`, zone stretch ratios, margins, font sizes, the lore
  italic skew, both text colors, hover offset/scale/duration) is still
  `@export`ed for Inspector tuning, same convention as Card Layout/Card
  Fonts on card.gd - unchanged by this rework, just no longer exercised
  by DeckViewer's own equipped-weapon row specifically (see above).
- Dev access only, originally, then extended to a real source: two
  separate "Dev: Grant Last Wages"/"Dev: Grant The Creditor" buttons on
  the title screen (not one that cycles - same "direct comparison, one
  click each" reasoning the opening-room variant buttons already
  established) send their weapon through `RoomState.pending_weapon_
  grant` (the same "pending_*" hand-off pattern `pending_chest_gold`
  already established) into a weapon-only reward_screen.tscn load. No
  shop listing, no COMBAT/ELITE/BOSS reward table grants one yet - see
  the next note for the one real source that now exists.
- **Weapons drop from TREASURE chests (IMPLEMENTED 2026-08-27):** the
  first real (non-dev) source. `field_chest.gd` gained `weapon_drop_
  chance` (an independent roll, never a replacement for the gold roll -
  a chest can grant both, on the same trip) plus `weapon_common_weight`/
  `weapon_rare_weight`, mirroring reward_screen.gd's own card-choice
  weighting so "how rare is rare" means the same thing for weapons as
  for cards. `room_state.gd`'s `COMBAT_CHEST_WEAPON_CHANCE` (0.0) vs.
  `TREASURE_CHEST_WEAPON_CHANCE` (0.15), copied into each spawned
  chest's own field by `field_room.gd` the same way `min_gold`/
  `max_gold` already are, is what actually makes this a TREASURE-room
  incentive rather than a universal chest bonus - COMBAT chests
  (including the opening room's guaranteed one) stay gold-only, exactly
  as before. 15% was chosen deliberately higher than reward_screen.gd's
  own `rare_drop_chance` (8%, ULTRA_RARE cards only) - a real, FELT
  reason to visit a TREASURE room, not an equally-rare coincidence
  dressed up as a destination - while staying well under "expected
  every time," which would cheapen the gift-drop feel equipment is
  meant to have.

  New `weapon_pool.gd` (`WeaponPool`, same small-RefCounted-utility
  shape as `CardPool`/`EnemyPool`/`EncounterPool`) scans `resources/
  weapons/` as ONE flat pool - equipment isn't per-class the way cards
  are (see this Pillar's own "Rare drops" framing: equipment is
  universal), so this doesn't read `CharacterData.card_pool_folder` the
  way `CardPool.load_class_pool()` does. `pick_weighted()` mirrors
  reward_screen.gd's own `_pick_card_by_rarity()` exactly: roll a
  rarity via `WeightedRandom`, then step down a tier at a time until
  something in the pool actually matches (COMMON is the floor) - with
  only two RARE weapons existing today, every roll currently lands on
  RARE regardless of what tier came up, the same "empty tier is a
  content gap, not a bug" stance the card system already takes.

  Nothing about the loot window itself needed to change - `RoomState.
  pending_weapon_grant` was already a generic hand-off (built for the
  dev buttons), and `reward_screen.gd`'s `_ready()` already turns it
  into a claimable WEAPON row regardless of what set it. A chest that
  rolls both gold and a weapon shows both rows in the same window,
  correctly, with zero extra code - the two `if` blocks there were
  already independent, not mutually exclusive.

- **Both weapons also gained a second, DETERMINISTIC acquisition path
  (IMPLEMENTED 2026-08-23):** The Pay House (see the Sunken Works
  section above, and the resolved "EVENT room content" Open Question) -
  pay in blood for The Creditor, pay in gold for Last Wages, both
  guaranteed rather than rolled. This is the first non-RNG way to get
  either weapon, sitting deliberately opposite the TREASURE chest's own
  15% gamble: a player who specifically wants The Creditor's reflect
  playstyle (or just needs Last Wages' chain payoff right now) can walk
  into any EVENT room and choose it, at a real, felt cost (HP or gold)
  rather than hoping. Uses the exact same hand-off `RoomState.pending_
  weapon_grant` + `reward_screen.tscn` load the chest/dev-grant paths
  already established - no new weapon-grant UI, same claim/equip/swap
  machinery, same `WeaponCard` presentation.

Verified headlessly a second time (`test_weapon_card.tscn`, since
deleted) for the card-style presentation specifically: WeaponCard shows
the right name/generated-effect/lore text and the actual icon texture
(falling back to a hidden art zone with no error when unset); rarity
border color comes from `Card.RARITY_BORDER_COLORS` and visibly differs
between tiers; a WEAPON LootRow emits weapon_hovered/unhovered (a
non-WEAPON row never does); hovering a row opens reward_screen.gd's
preview container and builds/feeds one WeaponCard instance, unhovering
clears the tracking state; the swap overlay's two embedded WeaponCards
correctly show the equipped vs. offered weapon; and DeckViewer's
WeaponCard instance correctly toggles against its own NoWeaponLabel and
uses its smaller per-instance design_size override.

Verified headlessly (`test_weapon_system.tscn`, since deleted): resource
loading and `describe()` text for Last Wages; `RunState.equipped_weapon`
starts null after `reset()`; the dev-grant flow builds exactly one
WEAPON-type loot entry; claiming into an empty slot equips directly
with the swap overlay never opening; claiming with a slot already
filled opens the swap overlay, correctly shows both weapons' names, and
both Keep Current (leaves the equipped weapon and the tree's pause
state unchanged, marks the offered entry claimed+declined) and Equip
New (actually swaps, marks claimed and NOT declined) resolve correctly;
all three modifier shapes' resolution logic in battle.gd, called
directly against synthetic CardData/WeaponModifier instances -
CATEGORY_DAMAGE respecting TargetScope (an ATTACK card boosted, a
SKILL card untouched, a null source_card - i.e. no card behind the
value - untouched), CATEGORY_ENERGY_COST respecting scope and flooring
at 0, and CHAIN_PAYOFF_DAMAGE boosting a DAMAGE-type payoff via a
freshly-constructed CardEffect (confirming the original resource -
Bite Down's own chain_followup_effect, in the real case - is never
mutated in place) while leaving a HEAL-type payoff completely
untouched; and every one of these confirmed as a true no-op with no
weapon equipped at all.

Verified headlessly a third time (The Creditor, since-deleted test
scene) against a REAL battle instance, not synthetic effect calls: with
no weapon equipped, Bite Down's own damage lands and nothing else; with
The Creditor equipped, the enemy takes Bite Down's own damage PLUS the
reflected self-damage amount, while the player's own HP cost is
unaffected (still paid in full, normally); a synthetic SELF_DAMAGE-only
CardData (confirmed via `_card_needs_target()` to genuinely need no
target) resolves its self-damage with zero enemy-side effect and no
error when played with a null target; equipping Last Wages instead (the
wrong `Kind`) leaves Bite Down's reflect completely inert; and, in a
REAL forced 2-enemy fight (`RoomState.pending_encounter_enemies`, not a
single-enemy pinned battle), the untargeted second enemy took zero
reflected damage while the card's own target took both hits - the
multi-enemy targeting question wasn't just reasoned through, it was
checked against an actual second combatant.

Verified headlessly a fourth time (chest weapon drops, since-deleted
test scene) against a real `field_chest.tscn` instance, not a
hand-built `LootEntry`: `WeaponPool.load_pool()` finds both real
weapons; `pick_weighted()` never returns anything outside that pool
across 50 rolls; a COMBAT-configured chest (`weapon_drop_chance =
COMBAT_CHEST_WEAPON_CHANCE`) drops zero weapons over 100 real `_on_
body_entered()` calls; a TREASURE-configured chest lands at 15.7% over
3000 trials against a 15% target (well inside a 3% tolerance band) -
the rate wasn't just set, it was measured; opening a chest forced to
`weapon_drop_chance = 1.0` produces a loot window with BOTH a gold row
and a WEAPON row whose `weapon_data` matches exactly what the chest
rolled, hovering it opens the real preview showing that same weapon,
and claiming it into an empty slot equips it directly; and, with Last
Wages already equipped, a second chest-granted weapon (The Creditor)
correctly opens the swap overlay showing the REAL currently-equipped
weapon on one side and the REAL newly-offered one on the other,
resolving Equip New to the correct result - the swap flow was verified
against two actual, different weapons for the first time, not two
synthetic `WeaponData` instances built just for the test.

- **Rework (2026-08-24): weapons are a decision, not a receipt.** The
  original design above let a weapon sit in the loot list as an ordinary
  row - hover-only detail panel off to the side, and claiming it into an
  empty slot equipped it SILENTLY, no confirmation at all. Both of those
  meant a player could hit Continue having never actually seen what a
  weapon does. Reworked so a WEAPON entry never becomes a row at all:
  - `reward_screen.gd`'s `_display_loot()` skips it; `_ready()` checks
    `loot` for an unclaimed WEAPON entry and, if found, immediately opens
    a dedicated screen and hides `loot_panel` before the first frame ever
    renders - Continue (and the rest of the loot list) simply isn't
    reachable until the weapon decision is made. `pending_weapon_grant`
    is a single field, not a list, so there's at most one WEAPON entry
    ever - no queue needed.
  - The old `WeaponSwapOverlay` (two equal-weight WeaponCard columns,
    `CurrentColumn`/`NewColumn`) is now `WeaponRewardOverlay`, and it's
    deliberately ASYMMETRIC, not a comparison of equals: the offered
    weapon keeps the full `WeaponCard` treatment (art, name, effect,
    lore, all visible immediately, `OfferedColumn`/`OfferedWeaponCard`) -
    that's what the screen is about. The currently-equipped weapon drops
    to a small `EquippedIcon` (64x64, hidden if nothing's equipped) plus
    a compact `EquippedSummaryLabel` reading "`[name] — [effect]`" (reused
    directly from `WeaponData.modifier.describe()` - the exact same call
    `WeaponCard`'s own effect line makes, so the wording can't drift out
    of sync) or explicitly "None equipped" - never hidden, since an
    absent element reads as a bug and an explicit "none" reads as
    information. Buttons relabeled Keep Current/Equip New ->
    **Leave Behind**/**Equip**.
  - The old auto-equip-if-empty shortcut is GONE - every weapon reward,
    empty slot or not, now goes through this same forced decision. This
    was a deliberate, confirmed behavior change, not just a visual one.
  - Hovering `EquippedIcon` still reveals a full `WeaponCard` popup - but
    now for the CURRENTLY EQUIPPED weapon (not "whichever row you're
    hovering," since there's only one hoverable thing left on this
    screen), smaller than the offered card (`EQUIPPED_POPUP_SCALE =
    0.65`) and positioned to its LEFT (`EquippedWeaponPopupContainer`,
    repurposed from the old per-row `WeaponPreviewContainer` - same
    lazy-build/fade-tween shape, just retargeted and repositioned, and
    with the old `_previewing_weapon_row` race-guard dropped entirely -
    there's only one possible hover source now, so nothing to guard
    against).
  - `loot_row.gd`'s WEAPON-specific branches (the icon swap, the
    elevated rarity-style condition, `weapon_hovered`/`weapon_unhovered`)
    are gone, not left dead - a WEAPON entry can never reach a `LootRow`
    any more. `loot_row.tscn`'s now-fully-unused `IconTexture` node was
    removed with it.
  - Gold and card rewards are completely untouched - still plain rows in
    the shared list, exactly as documented above; only the weapon path
    branches differently now, at `_display_loot()`/`_ready()`, not
    inside the shared `_claim_entry()` dispatch a row-click still uses
    for everything else.
  - No speculative generic `EquipmentData` abstraction was built for
    armor/trinket - there's no data model for either yet, and guessing
    at one now would be premature. What DOES carry forward is the
    screen's shape (big offered item, small current-item summary with an
    explicit "none" state, two actions) - a future equipment slot would
    most likely get its own version of this same shape rather than
    reusing `WeaponRewardOverlay` literally.
  - Verified headlessly (25 checks): an empty-slot reward hides
    `loot_panel`/pauses the tree/shows "None equipped" immediately, and
    Equip correctly updates `RunState.equipped_weapon` and restores
    `loot_panel`; a swap-decision reward shows the real equipped weapon's
    name+effect text (matching `WeaponCard`'s own wording exactly),
    Leave Behind leaves `RunState.equipped_weapon` untouched, and
    hovering `EquippedIcon` pops up a smaller `WeaponCard` for the
    EQUIPPED weapon specifically (not the offered one); a combined
    gold-plus-weapon chest reward opens the weapon screen while still
    producing exactly one gold row (not a weapon row); a pure gold/card
    reward never opens the weapon screen at all and never touches
    `get_tree().paused`.
- **Fix (2026-08-24): a real, game-wide input deadlock, exposed (not
  caused) by the weapon pickup window.** `scene_transition.gd`'s
  `go_to()` sets its full-screen `fade_rect.mouse_filter = STOP` for the
  duration of a transition and only resets it back to `IGNORE` on its
  own LAST line, after `await`ing its fade-in tween's `finished` signal.
  `SceneTransition` itself had no `process_mode` override - default
  `PROCESS_MODE_PAUSABLE` - so if the destination scene paused the tree
  before that fade-in tween finished, the tween froze mid-flight and
  `go_to()`'s own coroutine never reached that last line. `fade_rect` -
  a `CanvasLayer` deliberately layered ABOVE every scene's own UI so its
  fade always draws on top (see this file's own header) - was left
  sitting at `mouse_filter = STOP` forever: invisible once fully faded
  in, but silently eating every hover and click in the entire game, with
  nothing left able to unpause the tree to release it. Reported as "I
  cannot interact with or hover over the buttons" on the weapon pickup
  window, which pauses almost immediately after `reward_screen.tscn`
  loads (see `_open_weapon_reward()`) - well before the fade-in's 0.3s
  naturally finishes. A first attempted fix (deferring the pause by one
  frame) didn't help, because the deadlock reproduces as long as the
  pause lands before the fade-in completes either way, and one frame is
  nowhere near 0.3s. This exact scenario had simply never come up before
  in this codebase - nothing had ever paused that early after a
  transition - so the flaw was real but entirely latent until the
  weapon pickup rework's own `_ready()`-time auto-open exercised it for
  the first time. Fixed at the source, not on the one caller that
  exposed it: `SceneTransition._ready()` now sets `process_mode =
  PROCESS_MODE_ALWAYS` on itself unconditionally, so a transition's own
  fade always finishes and releases `mouse_filter` regardless of
  whatever the destination scene does the instant it loads. Verified
  headlessly: a real `SceneTransition.go_to()` into `reward_screen.tscn`
  with a pending weapon grant (which pauses the tree almost immediately)
  still ends with `fade_rect.mouse_filter == IGNORE`, confirmed via a
  companion node parented to the `SceneTransition` autoload itself (not
  `current_scene`, which `go_to()` frees as part of the real scene swap)
  so it survives to observe the result.
- **Fix (2026-08-23): a weapon-only reward showed a pointless extra
  screen after Take It/Leave It.** `reward_screen.gd`'s
  `_on_weapon_pickup_resolved()` always ended with `loot_panel.visible =
  true`, unconditionally reopening the loot window underneath once the
  weapon window closed. That's correct when a weapon is paired with
  other loot - a `TREASURE` chest's weapon roll (`field_chest.gd`'s
  `_on_body_entered()`) always sets `pending_chest_gold` alongside
  `pending_weapon_grant`, so there's a real gold row still to claim -
  but The Pay House (`pay_window.gd`'s `_apply_resolution()`) never sets
  `pending_chest_gold`, so its `loot` array holds only the weapon entry,
  which never becomes a row (see this section's own note above). The
  reopened `loot_panel` had nothing in it but the static `Gold: N`
  total (the player's current wallet, not a reward - always displayed,
  see `_ready()`) and a Continue button, reading as a second, pointless
  reward screen stacked right after the one the player just resolved.
  Fixed with a new `_has_other_loot()` check: if nothing but the (now-
  claimed) weapon entry remains in `loot`, `_on_weapon_pickup_resolved()`
  skips reopening `loot_panel` entirely and calls
  `_continue_to_next_battle()` directly instead - the same place
  Continue would have taken the player, reached one click sooner.
  Verified headlessly both ways: the Pay House's weapon-only flow now
  keeps `loot_panel.visible == false` all the way through resolving Take
  It, while a chest's paired weapon-plus-gold flow still leaves it
  `true` so the gold row stays reachable.

**Run context (HP/gold/room) now visible on the reward screen
(2026-08-26):** every Toll card keys off HP (Paid in Pain's below-half
clause, Retaliation asking the player to eat a hit), so choosing a card
reward with no visible HP was a real information gap - the screen had
no run context at all before this, just the loot itself over a black
background. Fixed by extracting the field room's own HP-bar/gold/room-
number/room-type block into a new reusable scene, `run_hud.tscn`/
`run_hud.gd` (`RunHUD`, extends `VBoxContainer`) - deliberately NOT
including battle-scoped state (Toll, energy, block, hand/draw/discard
counts), which are meaningless outside combat and stay in `battle.gd`'s
own separate HUD. Fully self-sufficient, same "drop this in and it just
works" shape `GoldDisplay` (one of its own children) already
established - it sets its own labels and refreshes its own HP bar from
`RunState`/`RoomState` in its own `_ready()`, rather than requiring
whatever scene owns it to push values in. `field_room.gd` was
refactored to instance this instead of its old inline `UI/HUD`
`VBoxContainer` - same node name (`HUD`) kept in the instance so every
existing `$UI/HUD/...` path elsewhere in the script still resolves
unchanged; `_room_type_display_name()` moved into `run_hud.gd`, since
it's about the label now showing it, not field-room logic. Verified
headlessly (live instantiation, not just structural inspection): the
field room's own labels/HP still read correctly, and
`shop_window.player_hp_bar` correctly resolves to the exact same
`VitalsBar` instance as before (needed for its own Rest-purchase HP
push).

`reward_screen.tscn` now instances the same `RunHUD`, positioned
identically (top-left, same offsets) and ordered right after the
screen's own `Background` and before every reward overlay, so the HUD
sits above the base background but every reward panel still draws over
it, never the reverse. Also added the Deck button (already present and
wired to `deck_viewer.open_deck` in every OTHER reward-screen state,
but silently non-functional from the card-choice modal specifically) -
fixing this needed two independent things, not one: `deck_button.
process_mode = PROCESS_MODE_ALWAYS` (matching `card_choice_overlay`'s
own identical fix, needed so it keeps processing input through that
overlay's tree-pause), and a NEW `DeckViewer.open_deck(manage_pause:
bool = true)` parameter so closing the deck doesn't incorrectly unpause
the tree out from under a still-open card-choice modal (reward_
screen.gd now connects to `func(): deck_viewer.open_deck(not get_tree
().paused)` instead of a bare method reference, deciding fresh at each
click which state it's actually in). Discovered and fixed a second,
pre-existing instance of the same underlying issue while verifying
this: `LootPanel` (the screen's own PRIMARY state, shown before any
card-choice row is even clicked) is a full-screen `Control` left at
Godot's default `mouse_filter` (`STOP`), silently swallowing every
click meant for `DeckButton` beneath it - same "decorative full-screen
wrapper needs explicit IGNORE" issue `card.tscn`'s own zone panels
already had to work around. Fixed the same way, though it took two
passes to get right: `CardChoiceOverlay`'s own `DimBackground` child
was fixed first, which turned out not to be enough on its own - with no
CHILD of `CardChoiceOverlay` left claiming the click at `DeckButton`'s
position, Godot's hit-test fell back to `CardChoiceOverlay` itself (the
outer wrapping `Control`, also full-screen, also still Godot's default
`STOP`) as the next candidate, which still consumed it. Fixed by setting
`CardChoiceOverlay`'s own `mouse_filter` to `IGNORE` too, verified this
time by simulating Godot's actual hit-test algorithm (reverse child
order, deepest-first, skip `IGNORE`, stop at the first real match)
rather than just checking each property in isolation. `RareDropOverlay`/
`LeaveConfirmPanel` share the same full-screen-Control-at-default-filter
shape and were NOT touched - flagged, not fixed speculatively, for
whoever next needs the Deck button reachable from one of those instead.
The Map button was deliberately left off this screen entirely - the
player shouldn't be able to
navigate away from an unresolved reward choice.

Also removed the card-choice modal's own "Choose a Card" heading and
let the panel's existing center-anchored `VBoxContainer` (`MainColumn`)
naturally recenter its two remaining children (the card row and Skip
button) in the freed space - no new layout logic needed, since
`MainColumn` was already anchored/grown around the panel's own center
before this; removing a child just shrinks its computed size and the
same anchor math recenters the rest automatically. Verified live: with
the heading gone, `MainColumn` reports `size=(952, 472)` positioned at
`(74, 114)` inside the `(1100, 700)` panel - exactly `550 - 476` and
`350 - 236`, i.e. precisely centered with zero leftover gap, not just
eyeballed.

### Trinkets (PARKED — investigation before implementation, 2026-09-04)

Passive run-persistent items. Existing scaffolding, from an earlier
pass: `trinket_data.gd`/`trinket_modifier.gd` (same `WeaponData`/
`WeaponModifier`-shaped pattern), `RunState.equipped_trinket` as a
sibling field to `equipped_weapon`, and one authored resource
(`resources/trinkets/amnesty.tres`) — but "no pool and no faucet" (see
the Polish Backlog's own Treasure Chest C note above): no pickup, loot,
reward, or deck-viewer UI reads any of it yet. This entry is design
thinking toward filling that gap, not a build plan — nothing below is
implemented.

- "Trinket" is placeholder vocabulary, pending a naming pass
  ("keepsake" considered — maybe too on-the-nose).
- **Sourcing:** the collector ONLY, plus, later, a rare buried-heap
  variant (see below). No reward-node drops, no rarity-tier drip, no
  top-bar accumulation UI. Ceiling ~2-3 per run — each one a decision
  and an object, not a passive stack. ("The collector" is a new/renamed
  NPC concept, not yet cross-referenced against the Keeper elsewhere in
  this doc — unresolved.)
- **Effects must hook native systems** — Toll, Rally windows, chains,
  Consumed cards, dig, forge — never a generic stat effect ("gain X at
  combat start" is the StS-smell to refuse).
- **Shelved effect concept:** persistent Toll as an authored exception —
  e.g. someone's ledger: enter fights with Toll equal to HP missing.
  Persistence only ever as a stated trinket effect, never a global rule
  (Toll is battle-scoped by design — see the Toll section above; field
  HP costs are pure).
- **Buried-heap growth path:** the wreckage heap's buried structural
  object (currently always a shard as of the 2026-09-04 dug-shard pass —
  see `field_heap.gd`'s `buried_object_texture`/`_shard_area`) would
  become variable: shard common, trinket rare, weapon rarest — visible
  from the first dig, so the player prices HP against what they can
  see. Requires staged reveal art per variant. Keeps big loot out of the
  sift table (scraps only) and keeps reward tiers honest against the
  Cache's encounter chest.
- **Rationale for collector sourcing:** a creature bred to collect,
  dealing in the small possessions of people who left — trinkets are
  what the exchange is ABOUT. This is the differentiation from Slay the
  Spire relics; hold it.

## Audio

**SFX (DECIDED — placeholder sounds, real system):** AudioManager (an
autoload, audio_manager.tscn) is the only thing in the game that plays a
sound or touches an audio file. Every hook elsewhere just calls
`AudioManager.play_sfx("some_name")` — game start (Begin Run, once per
new run - see title_screen.gd's `_on_begin_run_pressed()`, NOT the dev
battle-chain shortcut, which never touches the field), card
played/refused, damage to enemy/player, an enemy attack fully absorbed
by block (`full_block` - only on a FULL block; a partial one still
plays the normal damage-to-player cue, since some damage got through -
see battle.gd's `_enemy_attack_player()`), block gained, gold claimed
(a field chest routes through the same loot window a battle victory
does now - see the Rewards section's own note - so `gold_claimed`
plays at the same moment, claiming the row, either way; opening the
chest itself is silent), walking through an
unlocked door, a combat room's exit unlocking, combat start, a card
picked on the reward screen, victory, defeat — or, for footsteps, the
looping pair
`play_looping("walking")`/`stop_looping("walking")` (started/stopped
every physics frame by player.gd based on whether a direction key is
held). Which file a name plays (and how loud) lives in one dictionary in
audio_manager.gd — swapping a placeholder for real art later is a
one-line edit, not a hunt through the codebase. Files aren't all one
format (some are WAV, some MP3); the looping code path handles both
since a looped sound needs its loop flag set differently per format
(AudioStreamWAV's loop_mode enum vs. AudioStreamMP3's loop bool). A pool
of 8 AudioStreamPlayers, handed out round-robin, means overlapping
one-shot sounds don't cut each other off; looping sounds instead get
their own dedicated player each, since something needs to be able to
stop that specific sound on demand. SceneTransition stops every looping
sound both at the start of `go_to()` AND again after the scene swap
completes - the outgoing scene's Player can still be processing
movement input during the fade-out, and a single stop-at-the-start
call let a still-held movement key resurrect the walking loop right as
battle loaded (fixed 2026-08-17; the second call closes that window,
since nothing in battle can restart a loop that isn't there to restart).

**Folder layout (DECIDED, implemented):** `assets/audio/` is organized
into subfolders by trigger CATEGORY, not by file format or any other
property - `cards/`, `combat/`, `enemies/`, `field/`, `ui/`, `ambient/`,
`music/`. Every `SFX_FILES` filename in `audio_manager.gd` includes its
own category prefix (e.g. `"cards/card_play.wav"`); `SFX_FOLDER` itself
stays the flat `res://assets/audio/` base. `ambient/` starts empty -
reserved for sounds that don't exist yet (environmental loops), not a
sign anything's missing. `enemies/` holds its first real content as of
this pass - `enemies/Beachwrack/`, three creature-specific cues (see
the Beachwrack's own Bestiary entry: `wind_up`, `beachwrack_impact`,
and `debris_spawn`) - so future creature-specific sounds should follow
the same `enemies/<CreatureName>/` nesting rather than dropping
straight into `enemies/`. Music is handled separately by
`music_manager.gd` (see below) - its own `MUSIC_FOLDER` points straight
at `assets/audio/music/`, since every track that manager owns belongs
there, unlike SFX which splits across the other six categories by what
triggers each one.

**Placeholder gap:** the sound hooks above, plus `wind_up` and
`beachwrack_impact` (see the Beachwrack's own Bestiary entry - a
per-enemy override via `EnemyData.attack_impact_sfx`, distinct from the
shared `damage_player` cue every other enemy's attack still uses), need
19+ names total; `card_refused`, `block_gained`, `door_unlock`,
`victory`, and `defeat` have no file yet (`heal` and `chain_refund` now
do - Kept Warmth's own cue and a heartbeat sfx for a HEAL-type chain
payoff, see the Wanderer's Characters entry - `chain_refund` has no
live caller today since Bite Down's own refund was removed, but
stays mapped and ready) — they're wired everywhere they should play,
but AudioManager no-ops (with a console warning) until something is
mapped to them.
`door_unlock` specifically needs a short lock-disengaging cue (a
click/chime, under ~0.5s) distinct from `door_opened`'s creak-and-swing
sound - see Run Structure & Navigation's field juice notes. `field/
coin.wav`, `combat/blocking.wav`, and `field/chest_unlock.wav` are
unused (the field chest's gold sound reuses `gold_claimed`/`gold.wav`
rather than needing its own; `blocking.wav` was sourced for
`block_gained` but the mapping was reverted - see audio_manager.gd's git
history around 2026-08-17 if picking this back up; `chest_unlock.wav`
was added without a stated purpose - possibly meant for `door_unlock`
above, unconfirmed). `cards/ultra_rare_drop.wav` is a second, likewise
unused, take on the same idea `rare_drop`/`ultra_rare.mp3` already
covers.

**Levels:** the placeholder files vary wildly in loudness by design
accident, not intent — measuring peak/RMS off the raw WAV data found
card_play/hit/gold all sitting within a hair of full-scale (~-1 dBFS
RMS), while open_door has much more headroom (~-28 dBFS RMS). AudioManager
applies a per-sound dB trim (documented in its VOLUME_TRIM_DB comment)
toward a common target, plus a master_volume export (default 0.7,
tunable in the Inspector) — re-measure and re-tune those trims whenever a
placeholder file gets replaced.

**Music (DECIDED — a second, separate autoload):** MusicManager owns
background music - looping tracks with different lifetime rules than
AudioManager's one-shot SFX pool (a track persists across scene changes
until explicitly stopped, rather than firing once per moment), exactly
the split this section originally called for. `MusicManager.play_music(
"some_name")`/`stop_music()` mirror AudioManager's own naming-indirection
pattern (`MUSIC_FILES`, a name -> file map) and per-manager `master_
volume` export, kept as a fully independent mix rather than sharing
AudioManager's volume knob. Only one track plays at a time, no
crossfading - the only music that exists yet is the title theme (`title_
screen.gd`'s `_ready()`), and this stays exactly as simple as what's
needed until a second track (a battle theme, ambient field music) asks
for more. `scene_transition.gd`'s `go_to()` calls `stop_music()`
alongside its existing `AudioManager.stop_all_looping()` call, so leaving
the title screen (by any path - Begin Run or the Dev Battle Chain
shortcut) can never let the theme bleed into a run in progress.

**Explicitly out of scope this pass:** no settings menu, no crossfading
between tracks.

## Dev Tools

Utilities that exist for the developer's own use during playtesting -
never shown to a player, never part of the actual game loop.

**Run logging (DECIDED, implemented 2026-08-24):** `RunLogger`
(`run_logger.gd`, an autoload) writes a plain-text summary of one run -
the generated graph, every room choice (and what the alternatives
were), gold gained, reward offers vs. what got taken, and a full
turn-by-turn combat log (cards played, chain payoffs, damage dealt/
taken, mid-fight enemy spawns) - to `run_logs/run_YYYYMMDD_HHMMSS.txt`
in the project folder, one file per run, written the moment a run
actually ends (the boss falls, or the player does). Built for offline
analysis - reading back what a real playtest actually did, especially
whether routing choices and reward screens produce real decisions or
not - rather than reconstructing a run from memory or console
scrollback after the fact.

**On by default, toggle to disable:** `@export var enabled: bool` on
`run_logger.tscn` (edit the scene directly, or select the RunLogger
node in the editor's autoload list and flip it in the Inspector) - a
dev tool, not a shipping feature, so every logging call is a single
early-return check away from a complete no-op. No settings-menu
exposure; this is a developer's own switch, not a player-facing one.

**Architecture:** every other system calls one of RunLogger's plain
functions (`log_card_played()`, `log_damage_dealt()`, `log_room_
entered()`, etc.) at the exact moment that thing already happens in its
own code - `battle.gd`, `map_screen.gd`, `reward_screen.gd`, `field_
chest.gd`, and `title_screen.gd` each gained one or two one-line calls,
nothing more invasive. RunLogger never reaches INTO those systems to
ask what happened; they tell it, same "one place owns the how" split
AudioManager/MusicManager already use for their own concerns. Reuses
existing formatting where it already existed rather than duplicating
it - `run_state.gd`'s own dev-console graph print (`_print_run_graph()`)
was split into a `_run_graph_text()` that both the console and the log
file now read from, instead of a second copy of that logic living here.
A turn is bracketed by `begin_turn()`/`end_turn()` (called at each
player turn's start, and once more at battle end to flush whichever
turn was still open) - everything logged in between (cards, damage
dealt/taken) accumulates into that one turn's line, written out as a
single skimmable row rather than an event-per-line dump.

**Verified headlessly, not just written:** a real battle driven through
actual `battle.gd` code (turns, card plays, a full chain payoff
including its refund, a mid-fight enemy spawn) produced a log file
whose every expected line was confirmed present by substring match,
including the correct turn attribution (an enemy's action logs against
the turn it happened at the END of, matching the real turn-loop order,
not the turn about to start) and an honest read on Bite Down's chain
refund specifically: "took 2" and "HP 70->70" both show up on the same
line, meaning the log tells the true story (real damage happened AND
was refunded) rather than hiding the cost because it netted to zero.

**Per-battle instrumentation (2026-08-25, data-collection only - no
combat behavior, tuning, or card changes).** `log_battle_end()` now
appends a 3-line summary after the existing "Battle result:" line,
accumulated across the WHOLE battle rather than per-turn: turn count,
start/end HP, dealt/taken damage (taken split into blocked/unblocked -
`_resolve_damage()` gained an `absorbed` key alongside its existing
`hp`/`block`/`damage_to_hp`, purely additive), total Toll accrued and
its peak, cards played, total energy left unspent across every turn,
and three chain counters (openers played, payoffs actually fired,
empowerment expired unused). Enemy names (already known at `log_battle_
start()`) are repeated in the summary too, so it reads as a self-
contained block without scrolling back up.

Wired into the SAME call sites those things already flow through,
per this pass's own brief, not a parallel tracking system:
- Damage/Toll: `_enemy_attack_player()`'s existing `_resolve_damage()`
  result, `_deal_self_damage()`/`_deal_status_tick_damage_to_player()`'s
  existing `log_damage_taken()`/`log_damage_dealt()` calls, and a new
  sibling `RunLogger.log_toll_change(toll)` added next to each of the 5
  existing `player_resource_cluster.update_toll(toll)` calls (the
  established "toll just changed, push it" checkpoint already used
  everywhere toll actually changes - accrual in `_set_player_hp()`, the
  `SELF_DAMAGE_TOLL` top-up, and the `TOLL_DAMAGE`/`TOLL_BLOCK`/`TOLL_
  RETALIATE` spends).
- Chain: `_update_chain_state()`'s own `OPENER` branch (counts every
  Opener PLAYED, including a "wasted" replay while already empowered -
  the brief's own "openers played," not "times empowerment actually
  flipped"), `_trigger_chain_payoff()` right where it actually resolves
  (not where it's entered - a payoff that bails out early, target
  already dead or battle already over, never fired), and `_discard_
  entire_hand()`'s existing unconditional `chain_empowered = false` -
  now only counted as an expiry if it was actually true first.
- `end_turn()`/`log_battle_end()` both gained a required `energy_left`
  param - `_start_player_turn()`'s own existing `RunLogger.end_turn()`
  call already ran BEFORE refilling energy for the new turn, so the
  value was already sitting right there; `_close_out_battle()`'s own
  call just needed `energy` added to what it already passes.

All per-battle counters reset inside `log_battle_start()` specifically
(called once per `battle.gd`'s own `_start_battle()`), not on scene
load/autoload `_ready()` - a run spanning several battles gets an
independent count for each one.

Verified headlessly two ways: a direct unit-level check of the
accumulator math and exact line formatting against hand-computed
expected values (a two-turn synthetic battle - accrual vs. spend
correctly only counting the accrual side toward "accrued," peak
tracking correctly holding its high point through a later spend); and a
real `battle.tscn` instance driven through its own actual functions
(`_deal_damage_to_enemy()`, `_enemy_attack_player()` with both a partial
and a full block, `_deal_self_damage()`, a real `_update_chain_state()`/
`_trigger_chain_payoff()`/`_discard_entire_hand()` sequence), whose
resulting blocked/unblocked split (9 taken, 8 blocked) matched hand
arithmetic exactly, including a chain payoff's own damage correctly
folding into the same "dealt" total as the direct hit that triggered it.

## Ideas Parking Lot

Unvetted ideas — things worth remembering, not yet worth designing:

- Quest items
- Secret Rare acquisition - maybe never offered in normal rewards;
  found/discovered in the world only? Ties to lore pillar.

## Polish Backlog

Known rough edges - functional, not fixed, deliberately deferred:

- **Intent icons** - functional but visually unresolved. Part of the
  broader art direction question, not a standalone fix. Cheap to swap
  (two Polygon2D shapes) once a visual language exists.
- **ART DIRECTION SESSION (deferred, significant)** - the game has no
  established visual language beyond "silhouettes." Individual asset
  dissatisfaction (intent icons, card art slot, UI composition, room
  environments) is downstream of this. Decide the visual language
  deliberately in one session rather than fixing assets piecemeal.
  Consider doing this with brother's input.
- **Enemy flavor text position (2026-08-27)** - renders directly under
  the enemy HP bar today, which is wrong two ways: (1) that's also where
  the shared VitalsBar StatusBadgeRow renders an enemy's own status
  badges (see status_effect_data.gd) - no enemy statuses exist yet, so
  the collision is latent, but it'll break the moment one is; (2) it's
  world-voice text sitting in the system-voice zone right next to the
  HP bar and badge row, muddying the two-register UI principle (serif/
  full-color for world-voice, sans/muted for system-voice). Likely fix:
  move it up near/under the intent indicator instead - it describes the
  same thing the intent does (what the enemy's about to do), so grouping
  them puts world-voice with the read it flavors and frees the under-bar
  zone for badges. Deferred until enemy statuses actually exist, so the
  whole enemy UI zone gets one deliberate pass instead of two nudges.
- **Duplicated `_room_width()` (2026-08-29)** - `room_state.gd` and
  `field_room.gd` each carry an independent `_room_width()`
  implementation. They must return identical values or content placement
  desyncs from the rendered room. They cannot share one because layout is
  generated before `field_room.tscn` exists.

  This is the same lifecycle constraint that already duplicates
  `WALL_INSET` and `EXIT_MARGIN`. Second instance of the pattern; not
  unifying yet.

  If a third appears, or if COMBAT width changes and placement drifts,
  that's the trigger to extract a shared pre-scene geometry source.
- **Treasure Chest C: weapon-only, not currency-or-equipment
  (2026-08-29)** - Treasure Chest C was designed as upgrade currency or
  equipment. Upgrade currency does not exist as a spendable resource
  (`CardUpgradeService.offer_upgrade()` is free; shop `upgrade_price`
  gates the offer, not the swap). Trinkets have a type, a RunState slot,
  and one authored resource, but no pool and no faucet. Chest C ships as
  weapon-only until one of those exists.
- **Treasure chests B and C use different presentation registers
  (2026-08-29)** - B reveals a card in world space (the Keeper's own
  in-field Card path); C opens a modal pause window (WeaponPickupWindow).
  Accepted for now. Unify if it reads badly in playtest.
- **`forge_weight` temporarily elevated (2026-09-02)** - raised from an
  original 6.0 to 15.0 (`run_state.gd`) as a stopgap: at 6.0, roughly
  half of generated runs contained zero FORGE rooms, and until region-
  boundary forging exists as a second shard sink, a run with no forge at
  all strands its shards with nowhere to spend them - contaminating
  early economy playtests, not just a rare flavor gap. 15.0 measures at
  ~79% of runs containing at least one FORGE. Revert toward scarcity
  (back down near the original 6.0, or wherever balance actually wants
  it) once region-boundary forging ships and shards have a second sink.

### Candidate: Rally recovery preview on targeting

When targeting with an attack card, the HP bar could preview how much of the
rallyable segment would convert to real HP — a distinct slice within the faded
zone showing the portion that would be recovered.

Reasoning for this shape over a numeric readout:
- The bar already teaches Rally spatially; a number would be a second channel
  explaining the same thing, and the weaker one. Players need to know "most of
  it" or "a little of it," not the exact figure.
- Handles the pool cap for free — if the attack would recover more than the pool
  holds, the whole faded segment lights and it's visibly clear there's nothing
  further to gain.
- The vitals area is already dense (HP bar, rallyable segment, status badge row,
  Toll, Block badge). Reusing the bar avoids adding a fifth element.

Deferred deliberately. Rally recovery is set to 20% (a 2026-08-25 retune to 50%
was reverted 2026-09-03 - see the Rally passive entry above) and hasn't been
played across enough fights to know whether the recovery amount is something
players want to plan around or something that simply happens. Build this if the
want shows up during play; the bar plus the recovery animation may already be
enough.
