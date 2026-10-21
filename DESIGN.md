# Design decisions log

Parked decisions and deferred items - see CLAUDE.md's own pointer to this
file. Not a full design document, just what's been consciously set aside
so it doesn't get silently reinvented or silently forgotten.

## Audio format

Short SFX may be WAV or MP3: the format isn't a spec issue
(04_FIELD_ASSET_SPEC §4). What the spec holds them to is unchanged and
still checked on every new sound - trimmed to within a few ms of the
first transient, normalised to −6 dBFS peak, and mono for a positional
sound (one played from a body in the world). (2026-10-03; the spec said
WAV only, while most of the project's sounds were already MP3.)

## Card draw sound

`assets/audio/ui/card_draw.wav` is the old 2D project's per-card draw
sound, `reference/old_project/deck-builder/assets/audio/ui/one card
draw.mp3` (the same bytes as `assets/audio/ui_old/one card draw.mp3`,
left as is). Processing: decoded from the 128 kbps MP3 (48 kHz stereo);
the start kept - its soft slide comes about 180 ms before the main
transient and is what makes it read as a draw, so it is not trimmed to
the transient as §4 would have it; the tail cut at the first zero
crossing after 400 ms (past ~325 ms only a −57..−63 dB residue, then the
file's padding and an end click), no fade; normalised to −6 dBFS peak
(−4.2 dB); written as 16-bit 48 kHz stereo WAV, 400 ms. It is 2D, on the
SFX bus at `BattleOverlay.card_draw_volume_db` −22, 6 dB under card play.
One take only, against §4's two or three: each play's pitch moves by up
to ±`card_draw_pitch_jitter` (0.05, the old project's ±5%) instead of a
round-robin. A second or third take would replace the jitter.
(2026-10-06.)

## Combat effects

Combat effects are ink strokes: matte, brush-like, in ink or deep maroon,
revealed by a sweep and faded out. No glow, no emission brighter than the
scene, no particles or sparkle. One reusable stroke builds them
(`battle/effects/brush_stroke_effect.gd`, a ribbon along a path - an arc
today); a card names its effect scene in `CardData.play_effect_scene_path`
and a new effect is a new .tscn with different settings. The stroke paces
the hit reactions it passes; the hits themselves, HP and kills, still land
at the card's impact. Blood Arc's arc (#461613, 0.9) is the first.
(2026-10-03.)

One exception to "no particles": a death's sand. When an enemy dies, a
few wisps of sand lift from where it lies and drift off downwind, fading
(`FieldEnemy.spawn_death_wisps()`) - world sand, sand-coloured and toward
the fog, not a combat effect, and never brighter than the ground; no
glow, no burst. The death itself is a slump and a fade into the fog
colour (the enemy fog pass's `veil`), never a flash. A killing blow plays
in full - every hit, number, hit-stop (`BattleFeedback.big_hitstop_ms`
on a kill), recoil and play effect - before the death begins; the rules
drop the enemy at once. (2026-10-09; the stop per fighter since
2026-10-17.)

## Wind

The field's wind is `RegionField.get_wind_direction()`: the + direction
of the floor's ground ripples (`FloorData.wind_ripple_angle`, measured
from +X toward +Z) where its sand is rippled, else
`RegionField.default_wind_angle_degrees`. Anything that drifts downwind
reads it - a death's sand today. (2026-10-09.) Floor 3's dune-grass tufts
sway along it (`tuft_card.gdshader`, set by FieldScatter); blown sand
should read the same value. (2026-10-16.)

Each floor can set its own: `FloorData.use_wind_angle` /
`wind_angle_degrees`, ahead of the ripple angle and the default, and the
ripples turn with it. Everything the wind moves reads it live - ripples,
lee shade, tufts, blowing sand, dust shadows, death wisps, the shore
flock, the Keeper's cloth and hair. Floors 1-2 keep the default 30;
floors 3-5 blow toward +Z (90), crest to lee on floor 5's south-facing
shelf. Floors 3 and 4 have no slip-face direction of their own (their
ridges are symmetric, steep side inward), so 90 there is one prevailing
wind for the region. The Wanderer has no cloth or hair wind yet; that
waits for his Blender work. (2026-10-18.)

Floor 3's stream banks have their own tuft kind (`dune_grass_bank`): pool
rim within 3 m of the water, rock allowed, anywhere outside the crane
pair's stance area (stance distance + 1 m) and never in the water. On
the west bank the worn path's keep-out shrinks to a quarter of the
floor's (0.7 m of its centreline at today's 2.8 m; 0.5 m ramp) for this
kind only, so tufts reach the water's edge beside the path; the floor's
keep-out - the ground's band half-width plus its edge noise, read live,
so it narrows with the path - still holds for the rest. (2026-10-16.)

Floor 3's edge tufts follow the walkable edge (the ledges) rather than a
fixed band (ScatterEntry's Edge group): densest on the edge and up to
1 m onto the bank, falling off into the floor to a reach that wanders
0.6-6 m along it, with about 30% of the edge bare. Clumps are bigger and
tighter (small tufts 20%, medium 45%, large 35%); three in four stones
have a clump round them. (2026-10-16.)

## The played card

A played card is out of the hand from the moment the play commits, before
any of its effects resolve - a rules change: it no longer counts toward
the hand cap of 10 while it resolves, so Second Thoughts played at 9
cards ends on 10. The order (`BattleController._resolve_play()`):

- Commit: the cost is paid and the card leaves `deck.hand`
  (`Deck.begin_play()`) for no pile - no slot in the hand, no room in its
  row. A swing starts; the card fades where it is.
- The fade's end (`HandContainer.play_fade_duration`, 0.16 s): the card
  goes to its pile (`Deck.settle_play()` - the discard, or the exhaust
  pile for Spent, Consumed, a Power or a Stance) and its readout ticks.
- A card with no `battle_animation` resolves in that same frame, after
  it: what it draws flies in once it has gone. A card with one - every
  Attack, and Brace - resolves at its impact delay from the commit, its
  lunge and hit unchanged. The rule is the clip, not the card type.
- Until its effects have resolved (`Deck.end_play()`) a reshuffle leaves
  the card in the discard, so a draw on a card never draws the card itself.

A Consumed card is in the exhaust pile from the fade's end, so a fight
that ends on it still takes it out of the run deck. This replaces the
0.45 s settle timer and closes the deferred item on a card's time in hand
depending on its impact time. (2026-10-07.)

## Card rarity

A simple HP-for-resource trade is a Common: lose a little HP, get one
plain resource back, with no condition or build-around. Small Price
(formerly Open Wound - lose 2 HP, draw 1) and Down Payment (lose 1 HP,
gain 5 Toll) moved from Uncommon to Common on that rule. (2026-10-04.)

The Wanderer's card rule (02_GAME_FRAMEWORK §3): the Wanderer's identity
is in the cards that pay - HP, Toll, or a Critical state. Not every card
must; Commons can be plain tools (Slash, Carve, Brace, Bide).
(2026-10-04, with Bide.)

## Elite rewards

`EnemyData.is_elite` is no longer a tag only. A fight with an elite in it
pays the floor's gold roll times `RegionField.elite_gold_multiplier`
(1.5, rounded) and rolls its card reward at the pool's elite rarity
rates (`RewardPool`'s Elite rarity rates: Common 0 / Uncommon 75 / Rare
23 / Ultra Rare 2, renormalised over the tiers with a card left, as the
normal rates are - so Common only when nothing else is). A bundle or
cache keeps its own flat roll. (2026-10-05.)

An elite leaves armor, not a keepsake or Glassbone: one worn piece
(`TrinketData.slot` WORN) from its `armor_table`, RARE at its
`armor_rare_chance` (0.22), never the piece already worn, lying on the
sand where it fell (`WorldArmor`), beside the usual card offer. The
Wardling leaves the Harness or, rarely, Wardling's Lamp; the Adder its
Shed Skin or, rarely, the Coiled Wrap. Keepsakes now come only from the
keeper and from deeds. (2026-10-16, armor.)

The region-end fight (floor 5's Greyshelf) is not elite: it pays the
floor's own gold and its Glassbone x1, and its card reward is set on the
placement - `FloorEnemy.card_reward = TOP_TIER_FIRST`, which replaced the
placeholder's `elite_card_rates` - to offer three distinct cards from the
highest tier down (`RewardPool.roll_top_tier()`): Ultra Rare first, and
only when that runs dry the next tier fills the rest. With no Ultra Rare
card yet it offers three Rares; Ultra Rares added to the pool are offered
first without a change. Skip works as for any fight. Nothing reads a
"region end" flag - it is the last floor's fight and its placement's
reward setting. (2026-10-05, Greyshelf.)

## Run log

RunLogger (`run/run_logger.gd`) writes one JSON-lines file per run to
user://runs/ (%APPDATA%\Godot\app_userdata\Journey of Milo\runs\), a line
per event, flushed as written: run_start (with the short git commit read
from .git, "unknown" without one), floor_entered, fight_start, fight_end
(the fight's sums and every card played), the reward-side choices, and
run_end. `tools/summarise_runs.py` reads the folder (`--since` a date or
a commit). Switched by `RegionField.run_logging_enabled`; never draws
from any generator; off in a headless instance unless a probe gives it a
folder (run_log_probe). (2026-10-04.)

- **Card HP split.** A played card's HP is `hp_cost` (its price: the
  stance's, Collateral's swap - `EffectContext.pay_upfront_hp_cost()`)
  and `hp_effect` (its own self-damage effects).
- **Pick rate is fight rewards only.** Belongings, bundle and find offers
  are counted in their own columns. A bundle or a find is logged only
  when taken (opening one and walking away is not an offer the log
  sees), and a RewardSpread's cards left on the sand log nothing.
- **"won" is unused** until a region-end fight exists: the region's last
  floor wraps to the first, and floor_entered carries a `lap` count
  (`RunState.region_lap`) instead.
- **A run with no fight and no choice is deleted** at its end (quitting
  from the title). A run with no run_end line - the editor's Stop, a
  crash - is "unfinished" in the summary.
- **Debug outcomes** (the battle's F1 row WIN/LOSE/ESCAPE) are marked
  `debug: true`; the summary leaves them out unless `--include-debug`.
  Escape exists only there today.

## Floor 2's shelf

Floor 2 no longer has its low stone shelf (the RockShelf at (-4.6, -24.4),
north-west of the crab's inlet). 05_REGION_01 §2 permits a low exposed
shelf as the first rock of the dry end arriving early; on floor 2 that
beat is dropped, and floors 3-5 keep theirs. In its place is the beach's
own transition: a strandline along the shore, a broken sand fence (five
SandFence sections) a few metres inland, and marram on low hummocks
behind it. RockShelf and its masks' flattening are untouched, for reuse.
(2026-10-17.)

Two fights fix where that dressing can go. The Sputter + Underfoot frame
looks south from about (2.8, -31.4), across the ground east of x -1 between
z -27 and the crab, so the fence stops 4 m west of the worn path (no
section east of it) and the marram stays west of x -0.6. The island's
dragonfly patrol keeps 6.8 m round each waypoint clear, which covers the
inlet's north shore west of x -6 and the west shore south of z -27: the
strandline lies only between those keep-outs and 3 m short of the Underfoot,
and up the west shore north of z -27. (2026-10-17.)

## Parked

- **The Nettlebasket's numbers are provisional.** Floor 4's optional
  road-side fight (`battle/rules/enemies/nettlebasket.tres`, `nettle.tres`):
  she has 36 HP, Pinch 6, Signal, Sting 12; each Nettle has 9 HP (one
  Carve's 6 leaves it standing, two finish it) and Nips for 2. Retune
  from playtest logs (the run log's `woke` and `signal_answer` lines).
  Open with them: her Signal's intent shows its glyph alone, not what
  the Nettles' answers will deal, and the lethal preview doesn't count
  those answers; at 0.12 scale the Nettles read small in the battle
  frame. (2026-10-18.)
- **Weapons modify the class's basic attack.** The run carries one
  weapon (`RunState.weapon`, from `CharacterData.starting_weapon`), shown
  in the HUD's WEAPON slot. What a weapon is for: it changes the class's
  basic attack - Slash for the Wanderer - through
  `WeaponData.modify_basic_attack()`, which each fight's deck is built
  through (`BattleController.fight_card()`), and which every deck view shows
  its cards as (`RunState.as_carried()` - DeckView, the wagon); the run's
  deck itself is never rewritten. The Rusted Blade is the baseline and
  leaves Slash unchanged. A weapon stays out of the battle hover reveal
  and out of `held_pieces()`. Its art is
  `assets/textures/weapons/rusted_blade.png`. (2026-10-17.)
  Greyshelf's Tail (`run/weapons/greyshelfs_tail.tres`) is offered after
  every Greyshelf win while not carried (`EnemyData.weapon_reward`), on a
  line of the reward screen's own - its name / CHOOSE, which opens its
  plate with TAKE and LEAVE; WALK ON leaves it (2026-10-20):
  Slash plays as Lash, Slash+ as Lash+ (`cards/weapon/`). **Placeholder
  art:** the Tail's plate reuses the Rusted Blade's art and Lash/Lash+
  reuse Slash's, until real art exists. (2026-10-18.)
  **Reveal sound:** `assets/audio/sfx/weapon_reveal.mp3` plays once as a
  weapon offer's plate appears (`RegionField._on_weapon_shown()`). It is
  the old 2D project's ultra-rare drop sound,
  `reference/old_project/deck-builder/assets/audio/cards/ultra_rare.mp3`
  (its `rare_drop`; the same bytes as `assets/audio/cards_old/
  ultra_rare.mp3`), copied unprocessed. Against §4 it peaks −1 dBFS, not
  −6, and starts ~31 ms in; at 9.5 s (audible to ~6.1 s) it is a sting,
  stereo, played 2D. Its level is set in `weapon_reveal_volume_db` (−17)
  instead, just under a full heavy hit. (2026-10-18.)
- **The Samurai's skillchains (prototype).** They replace the old
  project's Opener/Closer chain roles, which were never ported.
  - **Properties.** A card carries one of Advance, Hold or Withdraw, or
    none (`CardData.chain_property`). The loop is Advance -> Hold ->
    Withdraw -> Advance. A card whose property follows the last chained
    card's raises the chain a level (1, 2, 3...). A card with no property
    ends the chain; one with the wrong property starts a new chain at
    level 0. The chain resets at the end and start of each turn
    (`Skillchain`, kept on the player's Combatant).
  - **Skillchains.** Each link fires one after the card's own effects:
    Advance -> Hold **Parry** (Block x level), Hold -> Withdraw
    **Recover** (draw), Withdraw -> Advance **Lunge** (damage x level to
    the card's target; nothing if the card's own blow killed it). Lunge
    is not an Attack's blow: no attack bonus, Bent Nail or Ransom. The
    numbers are `CharacterData.parry_block_per_level` (3), `recover_draw`
    (1) and `lunge_damage_per_level` (3). Run log: the `skillchain`
    mechanic line (format 11).
  - **Burst** (`CardData.burst`) reads the chain level from before the
    card was played, through `CardEffect.bonus_per_chain_level`. The
    face prints the live number in a fight and `{chain_bonus}` outside
    one.
  - **Starter deck** (`run/data/samurai.tres`, cards in `cards/samurai/`,
    all STARTER_ONLY): 4 Cut (Advance, 1, deal 6), 2 Guard (Hold, 1, 5
    block), 2 Step Back (Withdraw, 0, draw 1), 1 Measured Cut (Hold, 1,
    deal 5), 1 Severance (Burst, 1, deal 5 plus 4 per chain level). The
    standing row shows "Chain N · <last skillchain>" while a chain is
    live.
  - **Open:** the Edge and Counter archetypes; her reward pool (her
    starters never roll, so her rolls are neutral cards only); tempering
    her cards (none has a tempered version); attack animations for her
    model (her cards leave `battle_animation` empty); balance - every
    number above is a prototype guess.
  (2026-10-19, Samurai prototype.)
- **Endure stays out of the Wanderer reward pool.** Restored to the
  belongings and collector pools (2026-10-16).
- **Debt Forgiven removed; Toll has no HP sink for now.** Turning Toll
  into HP let a player stall a fight to heal, so the card, its art and
  its pool entries are gone (2026-10-16). The TOLL_HEAL effect stays in
  the code with no card using it - `toll_heal_effect.gd`, its resolver
  entry, the enum entry and CardView's `{toll_heal}` token - pending a
  separate decision on that code.
- **Floor 4's dig site is a reserved spot only.** Its position lives in
  `assets/field/masks/source/floor4/floor4_layout.json`
  (`suggested_placements_world_xz.dig`, (-3.0, -21.8), on the ring's
  north side past the dune). Nothing reads it: there is no dig site
  yet. When it is built it becomes a second option in floor 4's "pup"
  event slot (`FloorData.event_slots`, anchored at the pup's (11.0,
  -17.3) - moved 2026-10-18 from (19.5, -14.0), well before the Adder),
  its prop offset from that anchor to this position - so a run
  stands one or the other. The collector is a FloorProp in its hollow off
  the west arm, (-19.8, -11.8). (2026-10-04, floor 4; moved 2026-10-15
  with the new ground - the ring, the collector's hollow and the Adder's
  den; the event slot 2026-10-16.)
- **Floor 4's pup wears the adult Dunecur at 0.6 scale.** A stand-in
  until a pup asset exists: `DunecurPup.model_scene_path` and
  `painted_albedo_path` swap it, `attachment_tuned_scale` keeps
  DunecurPose's metres fitting. Its hollow's brush is the floor's own
  scatter set (`floor4_pup_hollow.tres`, an `area` round the pup), so it
  stays if the dig is rolled in the pup's place - move it onto the
  option if that reads wrong. (2026-10-16.)
- **Floor 5's finding is a reserved spot only.** Its position lives in
  `assets/field/masks/source/floor5/floor5_layout.json`
  (`markers_world_xz.finding`, (-7.167, -15.9), in the side pocket off
  the climb's west side), placed by the walkable sample. Nothing reads
  it: what is found there isn't decided, so FloorData carries no field
  for it. Add one when the finding is built. (2026-10-05, floor 5.)
- **Floor 2's Underfoot + Dragonfly and Siltjaw pair wait for a single
  island option.** Floor 2 keeps both roll rules (`FloorData.roll_unique_
  enemies`, `roll_single_and_multi`): while the island stands only
  dragonflies, a crab option with a Dragonfly can never stand, and the
  crab and island are always multi-enemy fights, so the siltjaw slot must
  stand its lone Siltjaw. Both options are held back rather than shipped
  unrollable, and so is the pair's dig rule (a Siltjaw can't dig while a
  packmate is under the sand or digging that turn; it Snaps and digs on
  its next turn). Add them once the island has a single non-dragonfly
  option: the crab's `underfoot_dragonfly` (the Underfoot with a lone
  Dragonfly, `dragonfly_lone.tres`), and `siltjaw_pair` (each about 70% of
  the lone Siltjaw's HP, starting on the same loop so turn 2 has both
  Charges queued; the dug-in one plays the mound rules - three 12 HP
  mounds, each with its plate). (2026-10-16,
  floor 2 encounter variety.)
- **Height-based ground tints use a fixed land height.** Basin tint,
  crest light and the slope-tint fade (`basin_tint_heights`,
  `crest_min_height`, `slope_tint_fade_height`) are all measured from
  the floor's land level, one height for the whole floor. That suits a
  flat walk floor; a floor that climbs needs them relative to the local
  walk floor. Floor 5 (walk floor 0.4 m to 3.45 m) works round it: basin
  tint off, no fade, crest light from 3.7 m so only the upper ridges
  light. Revisit when a second climbing floor exists. (2026-10-05.)
- **Field pieces still built from y 0, harmless on floor 5.** Audited
  when floor 5 put the walk floor 1-4 m up; ExitGate's trigger was the
  one that broke and now stands on the ground (d645a41). Still from y 0:
  the gate's own origin (the first enemy's position, read in RegionField
  `_ready()` before FieldEnemy grounds itself a frame later); the
  CHANNEL gate's Blocker and BlockContactArea (0-1.4 m off that origin -
  a CHANNEL exit on high ground would sit under the sand; floor 5 is
  LINE, which disables both); the boundary walls (world y -4 to +6 -
  terrain near 5.6 m at the wall line would let him step over); the
  escape push (`RegionField`, `wanderer.global_position = target` at the
  enemy's body height, not the ground's - on a slope he lands in or above
  the relief and `_hold_above_visible_ground()` corrects it with a
  warning). And the camera has no terrain collision: side-on in a battle
  it stands ~2.8 m over the feet, so ground ~3 m above the fight about
  10 m to the side would hide it - check in play on floor 5's crest. Fix
  each when a floor needs it: seat on `Ground.get_height_at()`.
  (2026-10-05, floor 5.)
- **The Dragonfly stays on its glb material, off the painted shader.**
  Every other enemy wears `field/wanderer_painted.gdshader` with its own
  colour map (`EnemyData.painted_albedo_path`). The Dragonfly's body is
  low-poly (4.1k triangles) and its normal map is what smooths it: without
  it, as the painted shader draws it, the eyes and thorax show hard
  facets. The fix, when it's taken up, is smoothing the mesh's own normals
  in Blender (then point `dragonfly.tres` and `dragonfly_lone.tres` at
  `Dragonfly_body_texture_0.png`), not adding normal maps to the painted
  shader. Its wings are separate alpha-scissor materials either way.
  (2026-10-12, roster on the painted shader.)

## Deferred

- **The Samurai is a shell; these are left as they are.** She is a
  second CharacterData (`run/data/samurai.tres`), selected by
  RegionField's `starting_character` export, with no cards, mechanics or
  rig of her own yet (her cards: `cards/samurai/AUTHORING.md`). Open:
  - **Samphire is in her rolls.** Her pool (`cards/pools/samurai_pool.
    tres`) names `cards/samurai/` and `cards/neutral/`, and Samphire, the
    reward screen's fixed extra and the Collector's fixed card, lives in
    the second. The Wanderer's pool holds no neutral card at all.
    Accepted for now.
  - **Floor props hand her Wanderer cards.** Floor 2's belongings pool
    holds Hold Fast and the Collector's stock on floor 4 holds 27
    Wanderer cards; both are props' own pools, which the class's pool
    doesn't replace (`RegionField.run_reward_pool()` stands in only for
    the floor's `reward_pool`), nor does it replace a floor's `rare_pool`.
  - **"him" in the world's lines:** `run/run_over.tscn`'s drowned_line
    ("The water took him.") and RegionField's hold_line_world_line ("Not
    with that still behind him.") are the Wanderer's words for any class.
  - **Her sounds are the Wanderer's placeholders.** Attack and hit sounds
    come from `assets/audio/Wanderer/` (AttackAudio, HitAudio) whoever
    plays. Footsteps are the same folder's, but with no foot bones her
    FootprintSpawner never sets up, so she makes none (and leaves no
    prints) until she's rigged.
  - **No rig.** `samurai_v1.glb` is a static mesh: on the field it slides
    as the body moves; in a fight there's no draw, Slash, Brace or idle,
    the entry lock clears on its timer, and a card's `battle_animation`
    (the Wanderer's clip names - Left Hand's Slash) plays nothing, its
    damage landing at its authored `impact_time`. Hit flash, recoil and
    the stance turns are tweens and play as for him.
  - **Placeholders:** her max HP (80, the Wanderer's),
    `field_model_height` 1.7 (the glb's own) and
    `field_model_yaw_degrees` 180 are guesses to settle in play. Her
    albedo is the glb's own base colour, unpainted. Her starting deck is
    the skillchain prototype's ten (see Parked, "The Samurai's
    skillchains"), its numbers guesses too.
  - **The compendium shows her five starters** under SAMURAI: it lists
    every card in `cards/samurai/`, STARTER_ONLY or not.
  - **No Devour, and no sustain in a fight.** Devour is the Wanderer's
    (`CharacterData.has_devour`, on in `wanderer.tres` only): her fights
    show no Devour button and nothing reaches the action. Her own
    ability, not designed yet, will take Devour's HUD slot over the
    energy readout; until then she has no in-battle sustain.
  (2026-10-18, Samurai shell.)
- **The Siltjaw's mound rework leaves four things open.** Its mounds are
  12 HP targets with plates, unbroken it erupts for 14 (Block-only),
  breaking its own brings it up Exposed through your next turn with the
  overkill raw, and its tell is a 6% settle every 3.5 s. Open:
  - **Card faces read the Siltjaw, not the mound.** An armed card over a
    mound (`BattleController.preview_context_against()`) prints its
    number against the enemy under it; a mound has no statuses, so the
    two only differ when the Siltjaw holds an incoming modifier.
  - **The intent reads "←14", not "ERUPT 14"**, the same glyph-and-number
    form every intent uses. A move name on the intent would be a change
    to BattleIntent for every enemy.
  - **A mound hit reuses the blade-into-sand clips**
    (`sword_ground_strike_sand_*`, `FieldEnemy.dig_mound_hit_clips`),
    played `dig_mound_hit_gain_db` (6) over the contact volume so they
    read at contact level; a softer sand thud of its own waits for a
    sound pass. Never the shell on a mound - it would lie on an empty one
    or give the answer away on its own; only breaking its own mound plays
    the Siltjaw's contact sound, as it surfaces. (2026-10-18.)
  - **The numbers are a first guess:** Siltjaw 44 HP, mounds 12, Erupt 14,
    `tell_strength` 0.06 - tune from play and the run logs' fight lengths
    (26 s median before).
  (2026-10-17, Siltjaw mound rework.)
- **Sea wave calming under a painted landmass mask.** `sea.gdshader`'s
  `wave_fade_factor()` is its own port of Ground's SDF shoreline
  (`landmass_side_distance()`/`landmass_seaward_distance()`, uniforms
  pushed by `Sea._push_landmass_uniforms()`). When Ground runs a
  `landmass_mask` instead, the shader keeps calming waves along the
  invisible SDF shore, not the painted one - the wet band, wade drain and
  walls all follow the mask, only wave amplitude doesn't. Fix when it
  matters visually: push Ground's signed distance grid to the sea shader
  as a `sampler2D` plus its world rect/cell size, and have
  `landmass_distance()` sample that when a mask is active. Waves were out
  of scope for the mask pass. (2026-09-16, landmass mask.)
  Update: that texture now exists - `Ground._push_mask_distance_texture()`
  uploads the grid as an R32F `ImageTexture` (uniforms
  `landmass_distance_tex/_origin/_cell/_dims/_ready`, sampled by
  `ground.gdshader`'s `landmass_distance_at()` for the swash surge's
  shore gate). The sea side only needs the same five uniforms pushed to
  its material and a mask-mode branch in `landmass_distance()`; still not
  built. (2026-09-16, swash.)
- **Card faces keep thematic labels; CardType stays mechanical.** The
  face's type label, field tint and glyph show a thematic category
  (STRIKE / GUARD / TOLL / UTILITY / STANCE / POWER), derived in
  `CardView._derive_keyline_type()`; `CardData.CardType` (ATTACK / SKILL
  / STANCE / POWER) stays what the rules read. The old plan to give
  CardType a TOLL value and rename SKILL to GUARD is dropped - on a card
  with art the label is the only place the category shows, and the
  rules only ever ask "is it an Attack?". The one bridge: ATTACK <=>
  STRIKE, both ways, so the label tells a reader which cards the "your
  Attacks" effects touch. `tests/starter_cards_probe.gd` enforces it.
  Reckoning, a Toll spender that resolves as an Attack, reads STRIKE.
  (2026-10-03; replaces the 2026-09-17 rename plan.)
- **Field HUD still speaks the old panel language.** The battle UI is
  ink on the world (BattleTheme's `Battle/ink`/`bone` tokens - HP
  readouts' battle style, BattleIntent, BattleResources, End Turn, the
  DECK/DISCARD lines). Out of scope for that pass and still on the older
  `CardFace` tokens: HPBar/EnemyStatus's *field* style (bare rounded bar +
  outlined numbers), DeckView's panel, FloatingNumber, TargetLine and
  BattleFeedback's flash colour. Restyle them together when the field HUD
  gets its pass; the CardFace tokens can go once nothing reads them.
  (2026-09-17, battle UI ink pass. 2026-09-19: the field's deck line moved
  over - DeckPanel is now the one ink line the battle's DECK/DISCARD
  readouts use too.)
- **The HP bar has no dedicated probe.** `ui/hp_bar.gd` (the field and
  battle HP readouts, the Toll block off the bar's end) is exercised only
  by the fights kill_order_probe runs, which is what tools/run_probes.sh
  maps a change there to; nothing checks its readouts' numbers or layout
  directly. Write one when the field HUD gets its pass. (2026-10-03,
  probe runner.)
- **A card pool scan must take an explicit folder list, never "everything
  under `cards/`".** There is no pool scan today (decks come from
  `CharacterData.starting_deck_counts`, by explicit reference), so the
  question is only which shape the first one takes. `cards/neutral/`
  holds class-agnostic cards the Keeper used to hand out (Left Hand,
  Untouched, Second Thoughts) - not reward or shop stock, and a scan
  rooted at `cards/` would sweep them into both. Since 2026-09-30 she
  offers a keepsake instead; the three, with Hold Fast and Endure, are
  floor 2's belongings stock (`cards/pools/belongings_pool.tres`) and the
  Collector's (`cards/pools/collector_pool.tres`). The old project
  hit exactly this and solved it by hiding the cards in a subfolder its
  flat, non-recursive scan happened to miss (`npc_offers/`, see
  `reference/old_project/deck-builder/docs/DESIGN.md`) - a guard that
  depended on the scan staying non-recursive. Name the folders a pool
  draws from instead, so adding a folder is a decision rather than a
  side effect. (2026-09-19, Keeper's offer.)
- **The old project's Wanderer pool is reference, not a source to port
  from.** Six of its cards (Ballast, Forbearance, Guillotine, Paid in
  Pain, Siphon, Unflinching) were ported and then rolled back out again:
  they mapped onto the effect system cleanly enough, but porting a pool
  card-by-card imports the old class's economy along with it, and this
  Wanderer's costs are being set to their own principle. Wanderer reward
  cards will be authored fresh against that principle instead.
  `cards/pools/wanderer_pool.tres` stays in place with an EMPTY entries
  array - the reward machinery (RewardPool, RewardSpread, the seeded
  RunState.rng) is all built and wired, so authoring a card and adding a
  line to that pool is the whole job. A fight with an empty pool drops
  nothing and says so once per session rather than warning per fight.
  Three of the old cards could not have been ported at all, and the
  reasons are worth keeping: **Retaliation** - nothing reads a retaliate
  status when the player is hit; reflecting a hit back has no home in
  the damage pipeline. **Selfeater** - its status wants
  `attack_hp_drain_base`/`attack_hp_drain_increment`/`is_persistent_
  stance` on StatusData, and the card is `CardType.STANCE`, a third type
  CardData doesn't carry. **Owed** - the status's behaviour lives in the
  damage pipeline rather than in StatusData, and the card needs a
  per-CARD `toll_cost`, which only CardEffect has. ("Pound of Flesh" and
  "Overdraw" were also asked after; neither exists in the old project.)
  (2026-09-19, first fight rewards.)
- **With Regards is authored but deliberately out of the reward pool.**
  "Deal 8; if this kills, gain 1 energy" is a fine card in a fight with
  several enemies and close to a dead one in a fight with a single enemy
  - the kill that pays it out is the kill that ends the fight, so the
  energy arrives with nothing left to spend it on. It stays in
  `cards/data/` and out of `cards/pools/wanderer_pool.tres` until a floor
  fields more than one enemy at a time. Carve ("deal 5 to all enemies")
  has the same shape but is not held back: it is merely unexciting
  against one enemy rather than actively dead. (2026-09-19, second
  Wanderer card pass.)
  Update: floor 2 now fields one - the island's three Sputters fight as
  a cluster (`FloorEnemy.group`), so the card is no longer dead there.
  Still out of the pool: floor 1 is one crab and the pool is per floor,
  so putting it in is a per-floor pool decision, not a side effect of
  the cluster landing. (2026-09-21, multi-enemy clusters.)
  Update: in the pool now, as an Uncommon. Blood Arc joined it in the
  same pass, so the pool holds 15 Wanderer cards and no longer sits
  empty as the entry above describes. Floor 1's single crab still makes
  it a weak pick there; the card itself is unchanged. (2026-09-26,
  card rarity.)
  Update: the kill now heals 5 instead of refunding 1 Energy ("If this
  kills, heal 5", capped at max HP). A heal still counts when the kill
  ends the fight, so the single-enemy case above no longer makes the
  card dead. (2026-10-08.)
- **Rarity rolls only a fight's card reward.** `RewardPool.roll_by_
  rarity()` (tier first, 60/30/9/1, empty tiers renormalised) is what
  the reward screen and the fight's sand spread call; belongings bags,
  bundles, single-card props, caches placed as a `RewardSpread` prop
  and the Keeper keep the flat `roll()`. Deferred: whether exploration
  rewards get their own rarity rates. Giving them the fight's rates as
  a side effect would have rebalanced every floor's props, so that is a
  separate decision. (2026-09-26, card rarity.)
- **Rarity has no look yet.** No border, gem, colour or glow marks a
  card's tier on its face, and no debug view shows it. The data is in
  place (`CardData.rarity`); the visual treatment is its own pass.
  (2026-09-26, card rarity.)
- **The Dragonfly borrows the Sputter's hit sound.** `battle/rules/
  enemies/dragonfly.tres` and `dragonfly_lone.tres` name the Sputter's
  crack in `contact_sounds` - a TODO placeholder, not a choice: a 14 HP
  insect should not crack like a shell. The file was `hit_shell_1.mp3`
  and is now `hit_armor.mp3`, the Sputter's armoured-hit sound, under
  the same ID, so the dragonflies sound as they did. They need contact
  takes of their own. (2026-09-21, dragonfly rules; 2026-10-04,
  renamed.)
- **A cluster's contact zone is the union of its members' own contact
  spheres, not one merged shape.** Contact with any member starts the
  fight with every member of its `FloorEnemy.group` still standing
  (`RegionField._battle_members_for()`); nothing else exists on the
  field for a cluster - no node, no Area of its own. That is exact as
  long as neighbours stand within 2 x `contact_radius` (4 m) of each
  other, which the island's three do (1.3-1.5 m). A cluster spread wider
  than that would have holes in its zone; if one is ever authored, give
  the cluster a merged Area (a capsule along its line) instead of
  growing every member's sphere. (2026-09-21, multi-enemy clusters.)
- **Floors as data - what the first pass left open.** `region_field.tscn`
  is the region (sea, sky, light, tower, HUD); a floor is a `FloorData`
  in `floors/` (`region1_floor1.tres` = the tutorial floor extracted,
  `region1_floor2.tres` = Map3), listed by `floors/region1.tres`, and a
  floor change is a `reload_current_scene()` with
  `RunState.current_floor_index` advanced under a root-level `FloorFade`.
  Left for later: (1) the region's last floor wraps back to floor 1 with
  a print - region 2 and the traveller are not this pass. (2) Floor 2's
  belongings marker is a placeholder: a `FloorProp` whose scene is
  `world_card.tscn`, holding one card rolled from the floor's reward
  pool; a real find type replaces it. (3) The editor no longer previews
  a floor - Ground gets its mask from FloorData at runtime, so the scene
  shows the SDF landmass when edited. (4) Resolved 2026-09-20: the
  threshold look-up aims at the tower's base, and the tower now renders
  outside the depth fog (unshaded, `disable_fog`, painted fog colour
  darkened by `tower_contrast`) as a landmark west of the field, so the
  look finds a silhouette rather than flat fog. (2026-09-19, floors as
  data.)
- **The bundle's opened pose, its tail in the wind, and a real rare
  pool.** `bundle.glb` is one static mesh with no opened or tail-down
  variant, so a taken BundleProp only darkens (`opened_tint`) and falls
  silent. The knot's loose ends (about 0.10-0.15 m at y 0.45-0.58) could
  move through keeper_wind.gdshader's hair mask aimed at the knot, with
  its hem and luma tests switched off, but that takes the bundle off the
  hulls' shared flat material, and cloth that small barely reads from
  the field camera; it stays still. `FloorData.rare_pool` exists and is
  empty on every floor, so the 5% rare draw falls back to the bundle's
  own pool until trinkets or weapons exist. (2026-09-22, bundle.)
- **The Siltjaw borrows the Sputter's contact sounds.** Its rules,
  intent, burial and buried look (a SandMound over it in the field) are
  built (`battle/rules/enemies/siltjaw.tres`, `field/sand_mound.gd`); its
  `contact_sounds` are the Sputter's shell takes and the `hit_armor`
  crack (2026-10-18) until it has its own. It no longer
  roams: it stands at a fixed spot on floor 2's flats, and its mound
  samples the sand once. (2026-09-25, Siltjaw rules pass; 2026-09-26,
  roam removed.)
- **The battle debug row isn't gated to debug builds.** `BattleOverlay`'s
  `DebugRow` (Win/Lose/Escape/Draw/Discard) is only hidden by default,
  and F1 shows it in any build, release included. The field's F1 row
  (RegionField, the Keepsake button) exists only when
  `OS.is_debug_build()`; the battle row was left as it is. Gate it the
  same way before a release build. (2026-09-28, keepsakes.)
- **The focus-language drawing is copied, not shared.** The title menu,
  `RewardScreen`, `LootScreen`, `BelongingsScreen` and now
  `KeepsakeOffer` each draw the same focus language (utility grey at
  rest, bone or ink plus a short hairline to the left when focused);
  the four screens each carry their own outlined-text helper, and
  `RewardScreen`, `BelongingsScreen` and `KeepsakeOffer` each build
  their own scrim. Extracting one helper means touching the reward
  screen, which was out of scope for the alcove belongings pass, so the
  fourth copy went in as a copy; the keepsake prototype added the fifth
  the same way. `TroughChoice`, in progress in another session, will be
  the sixth. Extracting the shared helper is the next task once both
  have landed. (2026-09-26, alcove belongings; 2026-09-28, keepsakes.)
  `CardCompendium`'s BACK (the title's Cards screen) is one more copy -
  the title menu's ink item and hairline - and its click-to-inspect is
  DeckView's lift copied without the dim; both go with the extraction.
  (2026-10-02, card compendium.)
- **Floor 3 (Map4) is a walkable shell, not a finished floor.** One
  placeholder Sputter stands on the required fight at (-3, -9) so the
  gate has an enemy to measure from and the line something to lift on;
  the rest of the roster, the finding and the elite are unauthored. The
  elite flat is undersized: its largest flat circle is ~6.5 m, centred
  (11, -18), against the 9-10 m it was meant to be - two sea inlets pinch
  it north and south. Its steep faces (over 45 degrees, painted narrower
  than the ~1.2 m spec 04 asks for) will sawtooth and are left as painted
  for now: the NW dune's (5.4 m2), the mass east of spawn's (0.7 m2), the
  mass beside the finding's (0.6 m2) are all in the walking frame from
  the route; the east shoulder's (1.8 m2) only from the elite flat.
  (2026-09-26, floor 3.)
- **A bundle's once-only state doesn't survive a revisit.** `BundleProp`
  tracks taken (`is_opened`) and its line (`_line_shown`) on the node,
  and the region wraps back to floor 1 without a new run
  (`RegionField._on_floor_exited()`), so on a second pass a bundle would
  roll again and could be taken twice. The fix is Hull's, Keeper's and
  `TroughProp`'s static set keyed by the spawner's `floor path#index`,
  cleared by `RunState.new_run()`. No floor carries a bundle since floor
  2's became the trough, so it waits for the next one. (2026-09-29,
  trough.)
- **Battle-line placement ignores static props; enemies can be placed
  inside props** (seen with the floor 2 trough and the dragonfly patrol).
  `_place_cluster_line()` and the patrol's perches only avoid wet sand, so
  the island pack's line and perches pass through the trough. The trough
  now stands at yaw 45 (basin facing southeast, readable from the
  southern approach; back edge still up); its overlap was re-measured
  with a different offline 3D check - about 10 of 36 settled battle
  frames intersect it, ignoring single-point touches - which is not
  comparable to the earlier "about 8 of 36" at yaw 150. Follow-up: have
  battle placement avoid static prop footprints. (2026-09-29, trough;
  yaw 2026-09-30.)
- **Glassbone's upgrade economy is deferred.** Glassbone is the single
  material reward (Glassbone x1; Framework §3), kept apart from gold,
  which stays the currency. The run holds it (RunState.glassbone): the
  Greyshelf leaves one (the elites leave armor instead), and a belongings cache
  sometimes holds one. Its first use is tempering at floor 3's wagon:
  1 Glassbone (Wagon.temper_cost) swaps a card for its authored tempered
  version (CardData.tempered, cards/tempered/), once per card - only the
  five starters have one yet, and the values are provisional. Still not
  designed: its other uses (equipment, keepsakes, other workbenches or
  shrines), tempered versions past the starters, undoing a temper, what
  things cost in the long run, and how often it drops. (2026-09-30,
  Glassbone docs; tempering 2026-10-07.)
- **The keeper's pool is the run's opening lean; small finds are the
  bedroll's.** The keeper offers one of House Key, Frayed Cord, Departure
  Stub, Bent Nail, Worn Page and Blue Fastener (run/keepsakes/keeper/
  keeper_keepsakes.tres, weight 1 each); the belongings bedroll's table
  holds Wrapped Sweet, White Shell, Signal Glass and Pressed Flower - a
  column still unreachable while floor 2's cache offers the Bedroll.
  The files kept their paths and UIDs, so the folder names no longer
  match the tables: run/keepsakes/keeper/ holds three of the bedroll's,
  and three of hers live in run/keepsakes/. (2026-10-18, keeper pool.)
- **Armor is deferred past its first four pieces.** The WORN slot, its
  rules (max HP while worn, the first hit halved, Block at the start,
  damage back) and the two elites' tables are in. Deferred: armor shown
  on the Wanderer's model, final models and art (the four are placeholder
  primitives and SVGs, by path), more pieces and more elites, and the
  battle row dimming a spent Lamp (the row dims nothing yet). Deeds
  themselves are deferred. (2026-10-16, armor.) A piece is named by the find line (FindLine,
  "You find a harness on the Wardling.") once the reward screen closes,
  its name in the cards' rarity finish; the RARE finish's dark gold was
  tuned against bone, so a dark-world variant for that line is deferred
  until a floor uses ui_on_dark_world. (2026-10-16, find line.)
- **Signal Glass shows no future intent.** Its intended effect was to
  preview each enemy's intent after the current one. The intent
  architecture doesn't support that cleanly: erratic enemies (Sputter)
  roll their next intent with the unseeded global `randf()` only when
  they advance (`EnemyTurn._advance_intent()`); an interrupt, an
  interjected intent, a lone pack member's skip or a pain turn can
  replace the next one; and `battle_intent.gd` shows one intent per
  enemy. It ships as +3 Block at the start of combat
  (`TrinketData.combat_start_block`). Revisit if intents ever become
  pre-rolled for their own reasons. (2026-09-30, Keeper keepsakes.)
- **The keepsake plaque's flavour line is a slanted upright face.** The
  project ships no italic font, so `WorldKeepsake` leans AlegreyaSans
  through `FontVariation.variation_transform` (`flavor_slant`, 0.2). It
  hasn't been seen in a live instance yet; if the lean reads wrong or
  goes the wrong way, flip the sign or ship an AlegreyaSans Italic and
  point the plaque at it. The empty art square is a placeholder until the
  six Keeper keepsakes have object art (`TrinketData.art`). (2026-09-30,
  Keeper keepsakes.)
- **Leaving the Keeper's keepsake is final.** With a keepsake already held,
  her plaque offers REPLACE <held> / KEEP <held>. KEEP resolves the offer
  the way KeepsakeOffer's KEEP CURRENT does: her keepsake is gone for the
  run and she won't hold it out again. Walking away without choosing
  resolves nothing. Revisit if KEEP should leave it in her hand instead.
  (2026-09-30, Keeper keepsakes.)
- **The Keeper's plaque flips sides to stay off the Wanderer.**
  `WorldKeepsake` stands on her screen-right unless he is on her
  screen-right as it lifts, when it stands on her screen-left
  (`_choose_side()`: his origin's projected x against hers). The side is
  chosen once per lift and held until the plaque is back in her hand, so
  it never swaps while he moves in front of it. `screen_gap_px` (40) is
  measured from her meshes' projected bounds, which take in her hair
  tips from any angle. In 1080p stills with him 1.2 m from her on eight
  sides, neither figure is covered on any of them. (2026-09-30, Keeper
  keepsakes.)
- **Glassbone has no art and no world-placed reward yet.** The reward
  screen's Glassbone line draws a placeholder shard (a hairline outline
  in the line's own colour) until `RewardScreen.glassbone_icon_path`
  names a texture, and the take borrows the gold sound under it.
  `RewardMode.SPREAD` (cards on the sand) has no Glassbone piece, so a
  win there leaves the Glassbone unoffered, with a warning; the SCREEN
  default offers it. When the spread becomes the default it needs a
  piece to walk to. (2026-09-30, Glassbone phase 1.)
- **The Dunecur is placeholder in voice and bones.** Its glb keeps its
  flank patchwork and shoulder flaps (no replacement is coming for now);
  `DunecurPose` is tuned to it - the crest band widened over the flaps
  and squashed when folded, narrowed over the nape - so a new model needs
  its region exports retuned. Its `contact_sounds` borrow the old
  `combat_old/hit.wav` the Wardling uses.
  The bones it feeds over (`BoneScatter`, floor 4) are primitives -
  capsules, ovoids, drums - until bone models exist; `model_paths` takes
  one glb per piece kind and swaps them in. (2026-10-04, Dunecur.)
- **The Greyshelf's jaw doesn't open.** Its glb's mouth is sealed - the
  lip line at the snout is painted, no gap and no interior - so the
  Gape's tell is `GreyshelfPose`'s rear of the forequarters with the
  throat swelling and its blue deepening (`field/greyshelf_throat.gdshader`,
  hue and value only, no glow). A jaw needs a model with a mouth. It lies
  on a crest rock at the mouth of floor 5's north bulb - a placeholder
  glb (`assets/models/props/crest rock/`, `BaskingSlab` with the rock's
  model and colour map as overrides) until a Meshy rock replaces it - up
  by its `FloorEnemy.height_offset_m`, settled 0.05 m into the stone
  (`EnemyData.sink_m`, which lowers the model without burying it the way
  a negative `rest_height_m` does; 0.3 m on open sand put its feet under
  the relief). The rock's top tilts about 0.15 m along its length, so
  the tail end sits a little into it. The rock is stretched to hold all
  four feet 0.3 m inside its top's edge in the battle pose
  (`BaskingSlab.model_scale` 1.2 along, 1.6 across - 7.3 x 5.5 m), and
  the stance is 2.3 m from the snout: the rock's base flares ~0.9 m past
  its top, and the fight's framing rule (`FloorEnemy.battle_frame_screen`:
  the Wanderer at 0.3 of the width, the snout no further left than 0.55)
  needs the room. Its contact area is 4.4 m, so the rock's front edge
  (4.2 m ahead of it) never stops the Wanderer short of contact. Off the
  rock at half HP, it steps
  off the rock's camera side onto the sand at its foot, toward the
  Wanderer (`FloorEnemy.phase_drop_offset`), the frame fitted as if it
  stood further out (`phase_drop_frame_offset`) so it reads as just off
  the rock
  and turns to the Wanderer; an escape climbs it back. Its
  `contact_sounds` borrow `combat_old/hit.wav`, as the Dunecur and the
  Wardling do. It wears the painted shader on its own colour map
  (`Greyshelf_colour.png`); its glb's embedded maps are discarded on
  import. (2026-10-05, Greyshelf.)
- **The card export should be generated, like the enemy export.**
  `docs/wanderer_card_export.json` is rebuilt by throwaway scripts and
  committed by hand, so nothing notices when it drifts from the cards.
  `docs/enemy_export.json` is the pattern to follow: a generator
  (`tests/enemy_export.gd` - not `tools/`, which is `.gdignore`d, so no
  class_name or .uid there - a `SceneTree` script whose static `to_json()`
  writes deterministic output, no date, no commit) and a probe
  (`tests/enemy_export_probe.gd`) that fails when the committed file differs
  from what the generator builds now, mapped in `tools/run_probes.sh` to the
  files it reads. The card export needs a real CardView for its face text
  and rules font size, so its generator builds one. (2026-10-05, enemy
  export.)
- **The Underfoot's contact sound is a placeholder.** Its
  `contact_sounds` borrow `combat_old/hit.wav`, as the Greyshelf, the
  Dunecur and the Wardling do, until a hit on a sand-covered ray is
  recorded. (2026-10-08, Underfoot.)
- **The Glower's contact sound is a placeholder too.** The same
  `combat_old/hit.wav`, until a hit on a pufferfish (soft deflated, a
  taut drum inflated) is recorded. (2026-10-17, Glower.)
- **The shield and the card glyphs are still line drawings.** The enemy
  intent glyphs are inked - filled, tapered pen strokes over a bone
  outline (`BattleIntent._glyph_shapes()`, `_ribbon()`, `_draw_ink()`).
  Two places that were drawn as "the same hand" weren't moved with them:
  the block shield beside the HP readouts (`EnemyStatus` and `HPBar`,
  `block_glyph_line_width_px` - still the old even 3.5 px polyline) and
  CardView's keyline glyphs (`_draw_glyph()`, polylines with a faint
  second stroke). Card UI and status icons were out of scope for the
  intent pass. Ink them when either gets its pass - the helpers are in
  BattleIntent, to be shared once a second consumer needs them.
  (2026-10-08, intent glyphs.)
- **The intent's lethal warning ignores a strike back and next turn's
  Venom.** `EnemyTurn.preview_intent()`'s `lethal` replays the queued
  intent's hits only. It doesn't know that an Attack played into a Coiled
  enemy draws a hit back (`EnemyTurn.counter_strike()`), nor that Venom
  takes its stacks at the start of the next turn before anything else
  (`BattleController._start_player_turn()`), so a fight with the Adder
  can kill a player the display said was safe. Left as it is for the
  Adder's first pass; fold both in if play shows it misleads.
  (2026-10-09, the Adder.)
- **Slash contact on a timer beside the clip - next fix.** The card's
  contact (card_swing, card_impact: hit flash, damage, sound) lands on
  `create_timer()` waits in `BattleController` (the play's settle/swing/
  impact loop, timed from `_impact_delay_for()` -> `Wanderer.
  get_clip_contact_time()`), not on the clip's own playhead. Anything that
  moves the playhead apart from wall time - the hit-stop
  (`Wanderer.hold_animation()`), a next card waiting on
  `slash_cancel_time`, a blend - lets the two drift. Fix: a method key on
  the Slash clip at `slash_contact_time`, as DrawSword's grab now is
  (`Wanderer._merge_clips()`, `_on_draw_sword_grab_key()`), with the
  controller waiting on the Wanderer's contact signal instead of its own
  timer. (2026-10-14, after the DrawSword grab moved onto a method key.)
