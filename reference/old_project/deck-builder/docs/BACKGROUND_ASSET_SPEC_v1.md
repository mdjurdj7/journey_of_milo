# Background Asset Generation Spec v1

**Purpose:** Replace procedural polygon silhouettes with generated placeholder art, without discarding the working layer architecture or the inspector-tunable palette.

**Status:** Working spec. Viewport-dependent numbers marked `[FILL]`.

---

## 1. Strategy

### Hybrid, not full replacement

The existing layer stack in `field_room.gd` is sound and already maps to Art Direction Bible §10. Seven layers, sensible parallax factors, atmosphere separated from silhouette. That is the expensive part and it does not need rebuilding.

What is wrong is the *content* of three layers — the industrial polygon vocabulary. Replace the content, keep the stack.

### Keep procedural

| Element | Why |
|---|---|
| Sky gradient | Three-stop gradient. As an image it is larger, softer, and loses the live slider at exactly the moment you are hunting for "high-key pale." |
| Horizon haze | A colored band with an exported height. Nothing to draw. |
| Particulates (far/near) | Density, scatter, and drift are parameters. Baking them into a plate loses motion and control. |
| Tide bands / wavy strips | Procedural jitter reads better in motion than a fixed wave. |
| Ground base band | Ties to collision and floor line. Leave the geometry alone. |

### Generate as assets

| Element | Why |
|---|---|
| Tower silhouette | The single most important shape in the game. Must be authored, not formula'd. |
| Far-layer structures | Shape language. Bible §1 — shape is the whole argument. |
| Mid-layer structures | As above, at a nearer read. |
| Vegetation clusters | Bible §14 asks for designed masses, not generated blobs. |
| Ground decoration / debris | Same. |
| Foreground occluders | Bible §10's framing layer. Currently disabled; assets are what make it worth enabling. |

---

## 2. The critical technique — alpha masks, not colored art

**Every generated silhouette asset is a flat white shape on full transparency.** No color, no gradient, no internal shading, no texture.

Color is applied in-engine via `modulate` from the existing `@export` color variables.

Why this matters:

- **Palette stays tunable.** The 21 exported colors keep working. A cold-to-pale re-theme remains an inspector pass, not a regeneration cycle.
- **Atmospheric perspective stays free.** Bible §4 requires distance to remove contrast and saturation. With masks, that is per-layer `modulate` — the same asset can sit at three depths at three values.
- **Design flux is cheap.** You are one week into a re-theme. Baking color into plates means every premise adjustment is a regeneration.
- **Generation gets easier.** Asking an image tool for a clean silhouette on transparent is a far more reliable request than asking for a correctly-lit, correctly-valued painted plate.

The tradeoff: no internal value variation within a silhouette. Bible §7 permits foreground shapes to retain faint internal information, which masks cannot carry. Accept this for placeholder; revisit if the foreground layer needs it later.

---

## 3. Dimensions and tiling

### Fill these in first

- `VIEWPORT_W` = `[FILL]`
- `VIEWPORT_H` = `[FILL]`
- `SKY_BAND_H` = height from top of frame to `floor_line_y` = `[FILL]`

### Seamless horizontal tiling is mandatory

Parallax layers scroll. Any asset that spans the frame must tile seamlessly left-to-right, or the seam will be visible on every room traverse. Use Godot's `motion_mirroring` on the `ParallaxLayer`, set to the texture width.

This applies to: horizon bands, continuous vegetation strips, ground decoration strips.

It does **not** apply to discrete objects — individual structures, the tower, single occluder props. Those are placed instances, not tiling strips, and should be generated as isolated shapes with transparent margins.

### Per-asset sizing

| Asset | Target size | Notes |
|---|---|---|
| Tower | Height ≈ 0.5–0.8 × `SKY_BAND_H`, width ≈ 0.06–0.12 × height | Generate tall; scale down in engine. Keep aspect. |
| Far structures | Height ≈ 0.15–0.3 × `SKY_BAND_H` | Discrete, transparent margin all sides. |
| Mid structures | Height ≈ 0.3–0.5 × `SKY_BAND_H` | As above. |
| Vegetation clusters | Height ≈ 0.08–0.15 × `SKY_BAND_H` | Generate 4–6 variants for scatter variety. |
| Ground decoration | Small, discrete | 6–8 variants. |
| Foreground occluders | Height ≈ 0.4–0.7 × `VIEWPORT_H` | Hangs from top of frame. Generous transparent margin below. |

Generate at **2× intended display size** so downscaling stays clean and you retain headroom if the viewport changes.

---

## 4. Value targets per layer

Bible §5 requires contrast to separate depth planes, not individual objects. With alpha masks, this is entirely a `modulate` decision — but the assets must be generated with the right *density* to support it.

| Layer | Modulate target | Asset density guidance |
|---|---|---|
| Extreme distance (tower, initial) | Barely separated from sky | Simple mass, no internal openings |
| Far | Low contrast against horizon | Simple mass, minimal negative space |
| Mid | Moderate separation | Some internal negative space permitted |
| Ground / gameplay | Clear separation | Full shape definition |
| Foreground occluder | Darkest, near-silhouette | Strong outline, large scale |

**Density is the thing the generator controls.** A far-layer shape with lots of internal holes will read as busy no matter how you tint it. Ask for simpler masses at distance.

---

## 5. Subject constraints for generation

Every asset must satisfy the Region 1 constraints. When prompting an image tool, these are non-negotiable:

**Forbidden:**
- Wreckage, rubble, debris fields, collapse
- Damage, breaks, impact, burning
- Industrial machinery, cranes, gantries, pipes, beams
- Anything implying force or catastrophe
- Rust, staining, decay-as-damage

**Required register:**
- Intact, or aged by time rather than event
- Terrain and vegetation dominant
- Built objects near-absent in Region 1 specifically

**Shape language (Bible §1, §12):**
- Recognizable by gesture before detail
- Asymmetric, irregular, deliberately composed
- Designed rather than observed — the few branches that make the strongest gesture, not the hundred a real tree has

---

## 6. Generation prompt scaffold

Prefix every asset request with this, then append the subject:

> Flat white silhouette on a fully transparent background. Solid opaque white shape, no color, no gradient, no shading, no texture, no outline, no internal detail. Clean anti-aliased edges. The shape should be recognizable by its outline alone. Asymmetric and deliberately composed rather than symmetrical or generic. Centered with transparent margin on all sides. PNG with alpha.

Then the subject, briefly. Resist adding atmosphere, lighting, or mood words — those belong to the engine layer, not the asset.

**Do not** include palette, color, weather, or lighting terms in asset prompts. Those are `modulate` and the procedural layers.

---

## 7. Asset manifest — Region 1

Minimum viable set to replace the current industrial vocabulary:

**Tower** — 1 asset. Tapering vertical mass. No ornament, no internal structure. Must read at extreme distance as an unresolved silhouette and still hold up when seen larger in later regions.

**Far structures** — 0 assets for Region 1. Built structures are near-absent here by design. The far layer carries the tower and haze only.

**Mid structures** — 0–1 assets. If anything, a terrain form (headland, rise, outcrop) rather than a built object.

**Vegetation clusters** — 4–6 variants. Grouped masses per Bible §14, not individual plants.

**Ground decoration** — 6–8 variants. Stones, grass tufts, ground irregularity.

**Foreground occluders** — 2–3 variants. Terrain or vegetation overhanging the frame. This layer is currently disabled; enabling it with real assets is the single biggest depth win available.

Region 1 is deliberately asset-light. The region's argument is emptiness, and the manifest should reflect that.

---

## 8. Migration path

1. Generate the tower asset first, alone. Drop it into the existing far layer as a guaranteed element. Confirm the premise reads before generating anything else.
2. Add vegetation and ground decoration variants. Retire `_irregular_blob_shape()` consumers one at a time.
3. Enable the foreground occluder layer with real assets.
4. Delete the industrial shape functions (`_add_crane_silhouette`, `_add_gantry_silhouette`, `_add_platform_silhouette`, `_add_pipe_run`, `_add_industrial_support_beams`) and their entries in the three `Array[Callable]` pools.
5. Palette pass — the 23 color values, cold to high-key pale.

Steps 1–4 are additive and reversible. Step 5 is the one that trips the validator (§9).

---

## 9. Known collision — the luminance validator

`_validate_background_contrast()` gates background colors against the palest enemy, which encodes an assumption that **backgrounds are darker than characters.**

The new direction is a high-key pale sky. Brightening into it will fail this assertion at boot.

The fix is not to loosen the check. It is to decide that the game reads as **dark figures against pale ground** — which is more bible-compliant than the current arrangement (§1 shape-first, §11 character readability) but inverts the validator's premise and affects character and enemy art, not just backgrounds.

**Settle this before the palette pass**, not as a failing assert during it.

---

## 10. Palette drift — separate problem

`SunkenWorksPalette` has one live consumer in `field_room.gd` (`_add_exit_haze`) and holds a parallel, unread set of colors. It is the battle backdrop's real source.

The re-theme is the natural moment to decide whether it becomes the single source of truth or is deleted. Doing the field palette pass without deciding widens an existing split.

**Not a blocker for asset generation.** Flagged so it does not get worse silently.

---

## 11. Painted-track register

§2's technique (alpha masks, tinted at runtime via `modulate`/`silhouette_vertical_shade.gdshader`) is the default for everything this document otherwise covers. A small number of assets deliberately opt OUT of it: painted plates with baked color and value, rendered as a bare `Sprite2D` with no tint applied at all. Each is a real exception to the document's own central technique, not a variant of it — this table exists so that number stays visible and small rather than growing silently, one "just this once" at a time.

**No prior version of this table exists in the repo** (confirmed by search before writing this section) — the "five entries against a six-entry threshold" this entry was expected to land against could not be located. Starting fresh at the entries that are actually shippable today:

| Room type | Asset | Node | Assignment site |
|---|---|---|---|
| TREASURE | `belonging_pack.png` | `FieldChest` belonging Sprite2D | `field_chest.gd`, `_build_belonging_sprite()` |
| TREASURE | `belonging_case.png` | `FieldChest` belonging Sprite2D | `field_chest.gd`, `_build_belonging_sprite()` |
| TREASURE | `belonging_roll.png` | `FieldChest` belonging Sprite2D | `field_chest.gd`, `_build_belonging_sprite()` |
| TREASURE | `belonging_groundsheet_lighter.png` | plain Sprite2D, no Area2D | `field_room.gd`, `_add_treasure_groundsheet()` |
| FORGE | `Wagon.png` | `FieldForge` Wagon Sprite2D | `field_forge.tscn`/`wagon_placement.gd` |

`Wagon.png`, added 2026-09-04: the forge's own backdrop prop, a painted craftsman's wagon behind the workbench - gameplay-plane painted plate, no palette participation. Full opacity, no modulate tint, drawn under the bench via plain node order (not z_index) - see `wagon_placement.gd`'s own header.

**Threshold: 6.** At 5 of 6. Re-examine the painted-vs-tinted split itself once a sixth entry is proposed, rather than adding a seventh on the same "just this once" basis that got the list here.
