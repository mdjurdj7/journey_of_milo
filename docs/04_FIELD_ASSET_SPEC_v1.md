# Field Asset Spec v1

**Purpose:** How assets for the 3D field are made, sized, imported and tuned. Replaces Background Asset Spec v2 (the 2D parallax pipeline), which is retired.

**Status:** Working. Numbers are current defaults; every one of them is a live export and may move.

---

## 1. Ground

### Landmass mask
- Grayscale PNG, **30 px/m**. White = sand, black = water, ~10 px Gaussian blur on the edge (the blur is bilinearly sampled, so the contour is sub-pixel).
- The image rect maps onto the world through `landmass_mask_origin` (UV of the pixel that sits on spawn). Spawn stays at the world origin; the origin does the shifting.
- The drawn 0.5 contour **is** the waterline. Sand rises from it to `interior_height` over `landmass_falloff_width`; water falls from it to `-below_sea_depth` over `underwater_falloff_width` (ease-in, so the first metre is shallow).
- Grey values below 0.5 paint **shoals**: sand below the waterline but shallow. The rule (built 2026-09-22): a value `v` under 0.5 scales the depth the distance ramp would otherwise give by `(0.5 - v) / 0.5`, so 0 is the open sea and 0.42 is a sixth of it. It never moves the waterline - only the seabed under it - and it can only make water **shallower**, so a wade that is already shallow (a narrow gap between two shores, or ground the exit channel has flattened) cannot be deepened by painting it.
- Calibrating one: measure the unpainted depth along the crossing first, then `v = 0.5 x (1 - target / measured)`. **Geometry first, paint second.** The depth on offer is set by the distance to the nearest drawn line and the ease-in ramp over `underwater_falloff_width`; a wade is a gap between two shores, so its middle is only ever a few metres from one of them. Region 1 floor 2's alcove: the crossing's midline is 2.25 m from shore, which at the region's 6 m ramp is 0.07-0.14 m however it is painted - wet sand, not a wade. It reads as a crossing at `underwater_falloff` **3.0 m** on that floor (a per-floor value; the region keeps 6.0), which offers 0.59 m, painted **v = 0.16 (grey 41)** for **0.37-0.53 m across the crossing**, shallowing to nothing at each end.
- A floor that changes `underwater_falloff` changes its whole seabed, not just the wade: every shore on it drops away faster.
- Geometry only: the ground shader still reads its depth tint and wet band from the distance field, so a shoal is shallow to stand in before it looks shallow.
- Enclosed water (not connected to the image border) is a **pool**: still — no swash, no foam, no wet surge. Computed by flood fill at load.
- The mask's top edge is clamped (dry) so a neck can run off the image; every other edge is water.
- Walls are placed at the land's bounding box plus the wade margin; the drain is what keeps the player near the shore.

### Elevation layer (optional)
- Second grayscale PNG on the same canvas. Value × `elevation_max_height` (default 1.2 m; the region scene sets 1.8) is added to land height. Soft edges (~2 m) are walkable ramps; hard edges (~0.4 m) are drops the Wanderer cannot climb (step-up 0.35 m).
- At the relief's 0.35 m vertex spacing, any drop steep enough to be unclimbable (over 45°) is at most ~2.4 cells wide. Along a wandering outline it renders as a **sawtooth**: the grid snaps the drawn line to 0.35 m teeth, and shading and rock tint follow every tooth. Paint faces about **1.2 m wide** (25–35°), which the relief draws cleanly, and put the "can't climb it" in a **ledge barrier** (`FloorData.ledges`: an invisible wall along the lip, one line per ledge). Keep a face's middle under ~45°: a smoothstep ramp peaks at 1.5× its mean slope, so ramp linearly with rounded ends. A face drawn near the shore stands taller than painted, because the ground under its foot falls toward sea level.
- **Under this sun (ESE, 45°), south- and east-facing faces are lit like flat ground (×1.0–1.2 of its brightness), so elevated terrain reads by colour, not by shading.** Only west- and north-facing faces fall into shade (×0.4–0.6). Author future shelves and banks knowing that: whatever should read on a sunlit face has to be carried by its colour and value.

### Rock mask (optional)
- Third grayscale PNG on the same canvas (`FloorData.rock_mask`): white = exposed stone may show here. The ground shader blends the dry colour toward `rock_color` (0.56, 0.59, 0.50) past `rock_slope_min` (22°) of shading-normal slope, over `rock_slope_blend` (12°) more — set for ~1.2 m faces. Flat tops and feet stay sand. The colour's green margin has to survive the cool sun, which lifts blue ~5% over red: (0.56, 0.58, 0.55) lit to a neutral that read blue beside the sand.
- No mask, no rock: steep **sand** stays sand. Floor 2's hollow wall (38.5°), floor 1's channel bank (39°) and any dune slip face would otherwise go grey. The mask can be rough — the outline grown ~1 m — because the slope finds the edge.

### Wear
- A worn band from spawn through the required fight to the exit: `wear_darken` 0.10, half-width 2 m, edges wobbled by noise; flattens grain and ripples. Optionally a painted wear mask on the same canvas. Region 1's band is faint; later regions deepen it.

### Gradient values (per floor, `FloorData`)
- `interior_height`, `landmass_falloff_width`, `relief_amplitude`, `caustic_strength`. Floor 1: 0.25 / 4.0 / 0.15 / 0.15. Floor 2: 0.30 / 4.0 / 0.18 / 0.12.

### Shoreline conventions
- The keeper stands ~1.2–1.3 m dry; hulls ≥ 2.5 m dry with every bow and stern ≥ 2 m dry; a crab beside a pool ~0.8 m dry.

## 2. Water

- One plane, wider than the field; depth from the depth buffer.
- Depth tint shallow → deep over `depth_opaque` (2.0 m); the refracted seabed is **absorbed** per channel (red fastest) so the seabed cools and darkens with depth rather than greying the water.
- Foam line ~0.04 m of depth; swash front and run-up on open shores, driven by a shared phase (period 10 s, spread ±0.075 of a cycle along the shore); surface pattern from a seamless NoiseTexture2D; sky reflection at a low floor; sun specular broad and faint (roughness 0.7, specular 0.12).
- The water's colour and reflection are **unlit** (EMISSION), so the shader value is the on-screen value; the sand is lit.
- Ambience: sea + wind loops, mixed low, ducked a few dB on contact.

## 3. Models

### Props (hulls, the bird, future belongings)
- Meshy, **Smart Topology, texture off**, Standard resolution, Pose off. Reference image on white with nothing but the object (no rail, no ground).
- Download glb, **Resize to real height**, origin **Bottom** (feet/keel at y 0).
- In engine: the shared flat material, tinted a step darker than sand (hulls (0.50, 0.47, 0.42); the cormorant (0.28, 0.29, 0.31)). Silhouette is all that survives.
- Age is placement: sink 0.3 × height, roll 8–12°, low side toward the water. Never damage.
- **Glassbone** is the one exception to the shared flat material (Bible §20): its own restrained material, with its values set when the first piece is built.

### Characters (the Wanderer, the keeper)
- Textured. Albedo only (roughness 1, specular 0, no normal map), double-sided where the glb says so. Wind on cloth/hair by vertex shader masks (height bands; luma for hair).
- Meshy image-to-3D from a single back/three-quarter view is enough for a figure seen from above.

### Sizes
- Wanderer 1.8 m; keeper 1.65 m; rowing boat 4.5 m; cormorant 0.5 m standing, 0.8 m wingspan.

## 4. Sound

- Short SFX as **WAV or MP3** (either is fine), trimmed to within a few ms of the first transient, tail cut where it falls below hearing, no fade, **normalised to −6 dBFS** peak, **mono** for positional sounds (anything played from a body in the world); high-pass whooshes at ~120 Hz.
- Mix in engine on an SFX bus: swing ≈ −20 dBFS at the listener (felt, not heard), card play ≈ −16, contact ≈ −13. Contact sounds belong to the enemy by material (`hit_shell`); the swing to the Wanderer; card play is 2D.
- Two or three takes per sound, round-robin, never the same take twice running.
- Ambience beds: 25–40 s seamless loops, −12 dBFS, different lengths so they don't phase.
- No music in Region 1.

## 5. UI

- **Ink** (0.165, 0.165, 0.18) on the world; **bone** (0.94, 0.91, 0.86) for cards and for text on a dark scrim. Both invert with `ui_on_dark_world`; cards never invert.
- Spectral SemiBold: card names, cost numerals, HP/Toll/intent numerals, world-voice lines. Alegreya Sans: rules text, labels, caps at 0.16 em.
- Cards 200 × 280 at 1×; hand at 0.95, rules line visible at rest; hover 1.15× in place; armed card slides to centre at 1.2×. Reward/inspect views 1× to 2.2×.
- No boxes, no glow, no icons libraries: glyphs are line drawings in the same hand (chevron, shield, arrow-over-line, two cards, a bitten ring).

## 6. Baked-colour register (from v2, kept)

Anything with colour baked in — the keeper's texture, the Wanderer's — does not re-theme with the palette. Track them here:

| Asset | Where | Notes |
|---|---|---|
| Wanderer texture | field | class model; retune by regeneration |
| Keeper texture | opening floor | tint multiply available |
| Water Shrine texture (the trough) | floor 2 island | the model's own albedo, water painted in; no tint |
| Greyshelf texture | floor 5 crest | dark slate, pale scutes, blue throat; no tint - the Gape's throat pass deepens its blue by hue and value |

If this list grows past half a dozen, the palette pass has quietly become a regeneration pass.

---

**Document Version:** 1.0
**Supersedes:** Background Asset Spec v2 (retired).
