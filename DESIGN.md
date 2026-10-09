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
normal rates are - so Common only when nothing else is). Keepsakes and
Glassbone stay their own fields (`keepsake_table`, `glassbone_reward`).
A bundle or cache keeps its own flat roll. (2026-10-05.)

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

## Parked

- **Chain roles (Opener/Closer, chain payoffs).** The old project's
  `CardData.chain_role`/`chain_followup_effect` are not ported to the new
  rules layer (`cards/card_data.gd`). No current card needs them - revisit
  once a real card actually wants a chain-shaped payoff, not before.
  (2026-09-11, rules-layer port.)
- **Endure out of every Wanderer card pool, for now.** Taken out of
  `cards/pools/wanderer_pool.tres` (2026-10-03) and then out of
  `cards/pools/belongings_pool.tres`, the floor-2 belongings and
  Keeper pool (2026-10-04). The card's data is untouched; its file moved
  to `cards/neutral/endure.tres` (2026-10-04), so the compendium files it
  under Neutral. The probes that play it directly still do. Put it
  back by re-adding the entries (and Endure to `card_rarity_probe.gd`'s
  EXPECTED_POOL, count back to 20).
- **Floor 4's dig site is a reserved spot only.** Its position lives in
  `assets/field/masks/source/floor4/floor4_layout.json`
  (`markers_world_xz.dig_site`, (15.733, -31.5), on the east arc),
  placed by the walkable sample. Nothing reads it: there is no dig site
  yet, so FloorData carries no field for it. Add one when it is built,
  from this position. The collector's marker, (11.0, -22.5) in its bay
  on the dune's east flank, is now a FloorProp (a Collector, facing west
  into the bay - the faint side of the loop). This note had both spots
  wrong before - (14.5, -30) and (21, -42), the last off the land; the
  JSON's are the ones the walkable sample paints. (2026-10-04, floor 4;
  corrected 2026-10-05, the collector.)
- **Floor 5's finding is a reserved spot only.** Its position lives in
  `assets/field/masks/source/floor5/floor5_layout.json`
  (`markers_world_xz.finding`, (-7.167, -15.9), in the side pocket off
  the climb's west side), placed by the walkable sample. Nothing reads
  it: what is found there isn't decided, so FloorData carries no field
  for it. Add one when the finding is built. (2026-10-05, floor 5.)
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

## Deferred

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
  offers a keepsake instead; the three are now floor 2's belongings
  stock, with Hold Fast (`cards/pools/belongings_pool.tres`), and nowhere
  else. The old project
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
- **The Siltjaw still wears the Sputter's body and has no contact
  sound.** Its rules, intent, burial and buried look (a SandMound over it
  in the field) are built (`battle/rules/enemies/siltjaw.tres`,
  `field/sand_mound.gd`); the surfaced body is the default glb and its
  `contact_sounds` is empty. Build both with the model. It no longer
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
  Wardling and the Greyshelf leave one each, and a belongings cache
  sometimes holds one. Its first use is tempering at floor 3's wagon:
  1 Glassbone (Wagon.temper_cost) swaps a card for its authored tempered
  version (CardData.tempered, cards/tempered/), once per card - only the
  five starters have one yet, and the values are provisional. Still not
  designed: its other uses (equipment, keepsakes, other workbenches or
  shrines), tempered versions past the starters, undoing a temper, what
  things cost in the long run, and how often it drops. (2026-09-30,
  Glassbone docs; tempering 2026-10-07.)
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
  sunk 0.3 m on the crest (`EnemyData.sink_m`, which lowers the model
  without burying it the way a negative `rest_height_m` does), and its
  `contact_sounds` borrow `combat_old/hit.wav`, as the Dunecur and the
  Wardling do. Its material is the field's for every enemy, normal map
  included, as the Siltjaw's is. (2026-10-05, Greyshelf.)
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
