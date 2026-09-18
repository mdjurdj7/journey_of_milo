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
  outlined numbers), the field's DeckPanel box (hidden during battle),
  DeckView's panel, FloatingNumber, TargetLine and BattleFeedback's
  flash colour. Restyle them together when the field HUD gets its pass;
  the CardFace tokens can go once nothing reads them. (2026-09-17, battle
  UI ink pass.)
