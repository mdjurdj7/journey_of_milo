# Design decisions log

Parked decisions and deferred items - see CLAUDE.md's own pointer to this
file. Not a full design document, just what's been consciously set aside
so it doesn't get silently reinvented or silently forgotten.

## Parked

- **Chain roles (Opener/Closer, chain payoffs).** The old project's
  `CardData.chain_role`/`chain_followup_effect` are not ported to the new
  rules layer (`cards/card_data.gd`). No current card needs them - revisit
  once a real card actually wants a chain-shaped payoff, not before.
  (2026-09-11, rules-layer port.)

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
- **CardData.CardType should gain TOLL and rename SKILL to GUARD.** The
  card face's keyline/field/type label (strike / guard / toll) is
  derived in `CardView._derive_keyline_type()`: any Toll-mechanic effect
  (`TOLL_*`, `SELF_DAMAGE_TOLL`) makes a toll card, otherwise SKILL is
  guard and ATTACK is strike. Once CardType carries the three real
  values that derivation goes away and the face reads `card_type`
  directly. Card data untouched for now. (2026-09-17, ink-on-bone card.)
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
- **A card pool scan must take an explicit folder list, never "everything
  under `cards/`".** There is no pool scan today (decks come from
  `CharacterData.starting_deck_counts`, by explicit reference), so the
  question is only which shape the first one takes. `cards/neutral/` now
  holds class-agnostic cards the Keeper hands out (Left Hand, Untouched,
  Second Thoughts) - they are hers to give, not reward or shop stock, and
  a scan rooted at `cards/` would sweep them into both. The old project
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
- **The Dragonfly borrows the Sputter's hit sound.** `battle/rules/
  enemies/dragonfly.tres` names `hit_shell_1.mp3` in `contact_sounds` -
  a TODO placeholder, not a choice: a 14 HP insect should not crack like
  a shell. Replace when it has takes of its own; nothing else references
  the file through the dragonfly. (2026-09-21, dragonfly rules.)
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
- **The overhang hides the Wanderer for ~2 m.** A cutaway/fade for
  interiors is deferred to Region 3, where the run goes vertical. Floor
  2's SandOverhang lets him walk ~2 m in under its roof. From about
  x 9.6 (the lip is at 9.35-9.85) to the cave's back wall at 7.8, the
  field camera loses him, his contact shadow with him. The cards'
  lifted CardViews are drawn on a CanvasLayer from their anchors, so the
  lift and the take still read. (2026-09-25, sculpted overhang.)
