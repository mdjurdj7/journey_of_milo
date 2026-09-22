# Art Direction Bible v2

## Project Visual Identity

> **Quiet weathered fantasy. Monumental silhouettes, muted regional palettes, selective detail, and atmosphere that consumes detail with distance.**

The world should evoke **solitude, scale, age, mystery, beauty, and melancholy**. The constant is the feeling of travelling through a vast, old world that exists far beyond the player.

**Changed in v2:** the principles (§1–§18) are unchanged in substance and shortened. §19 anchors now point at the 3D build. §20 replaces AI image-generation guidance with the rules the 3D field actually runs on. §21 checklist updated.

---

## 1. Shape Before Detail

Every major element works first as a silhouette. Favour forms slightly exaggerated, irregular, asymmetric, deliberately composed. A boat should be recognisable by its gesture before its planks are visible.

## 2. Rendering

Restrained painterly simplification, not photorealism and not flat vector. **Large shape → secondary shape → selective detail.** In the 3D build this is enforced by construction: props are flat-shaded and carry no surface detail at all; surface variation, where it exists, is procedural (sand grain, ripples, caustics, wear).

## 3. Colour and Chroma

Muted and low-chroma without becoming monochrome. Colours within a scene share one atmospheric colour. Pure saturated colour is reserved for rare focal purposes.

Regional palette families: Coast — blue-grey, slate, muted teal. Highland — ochre, grey-green, stone. Forest — moss, muted emerald. Snow — pale blue, lavender-grey. Autumn — dusty amber. Strange — desaturated violet, mauve. Underground — mineral blue, charcoal.

Consistency comes from **how colour is treated**, not from using the same hue everywhere.

## 4. Atmospheric Perspective

**Distance removes information.** Detail, contrast, saturation, edge sharpness and texture all fall away with distance. In the field this is depth fog in the sky's colour from 14 m to 28 m — everything past the inland wall is unreadable from spawn. The tower is the one deliberate exception (§20).

## 5. Value Hierarchy

Contrast separates **depth planes**, not individual objects. Under the top-down camera the planes are: the Wanderer and enemies (darkest), props (dark), sand (pale, the brightest large surface), water (cool, below sand in value), fog and sky (palest).

## 6. Lighting

Diffuse environmental illumination: overcast, haze, reflected light. Strong cinematic lighting only when narratively appropriate. Region 1: sun 0.9, neutral-cool, soft shadows at low opacity, neutral ambient; no warm light anywhere.

## 7. Shadows

No pure black. Shadow is a soft pale pool under a figure (a contact disc), not a hard shape.

## 8. Detail Distribution

Hierarchical and selective. **Negative space is intentional composition, not unfinished artwork.** Do not decorate the flat.

## 9. Environmental Scale

The player should frequently feel small. One enormous memorable silhouette beats dozens of small objects.

## 10. Composition under the top-down camera

The field camera (pitch 50°, distance 12 m) never frames the horizon. Composition happens in the ground plane: the shoreline's shape, the worn band, one prop, one figure, and the space between them. The traversable surface must read: *I can walk here* (sand), *I can wade here* (shallows), *I can't* (deep water). No glowing outlines, no game-like indicators.

## 11. Character Integration

Characters stay the cleanest elements in the frame: dark on pale, readable outline, nothing busy behind them. This is why sand is pale and props are darker than sand.

## 12. Environmental Shape Language

Designed rather than observed. A painted shoreline needs the few bends that make the strongest shape, not the hundred a real coast has.

## 13. Architecture

Not inherently Gothic. Different civilisations may develop their own proportions and materials. Region 1 has none.

## 14. Nature

Grass becomes masses; rock becomes planes; water becomes value and a line. Only selected areas receive finer rendering.

## 15. Warm Accents

Allowed but not a formula. Contextual meaning only. Some scenes contain no warm accent — Region 1 is that scene.

## 16. Weather and Atmosphere

Varies by region. Fog is a Region 1 device; it is not the whole game.

## 17. Regional Expression

**Consistent:** silhouette-first, selective detail, restrained saturation, atmospheric depth, strong value hierarchy, designed forms, character readability, monumental scale where appropriate.

**Allowed to change:** hue, weather, architecture, vegetation, terrain, lighting, density, civilisation, decay, mood, time of day.

## 18. Anti-Goals

Photorealism; generic AAA fantasy rendering; hyper-detail everywhere; crisp distant scenery; oversaturation; teal/orange as default; pure-black shadows; constant dramatic lighting; constant fog; constant ruins; constant Gothic; clutter; filling empty space because it exists; a glowing focal point in every scene; characters vanishing into busy backgrounds; **UI that looks like a menu on top of the world.**

> **Do not equate visual complexity with visual quality.**

## 19. Current Visual Anchors

**Anchor A — the opening floor at spawn.** Water at the bottom edge, hulls on the spit, the keeper on the far shore, sand rising into haze. The reference for the region's value structure and the first frame the player sees.

**Anchor B — the battle frame.** Side-on at pitch 12°, the fight on pale sand, the tower a pale silhouette above the horizon behind the enemy. The reference for character/enemy readability and the UI language sitting on the world.

**Anchor C — the card canvas.** Bone cards with ink type, the energy pips, Toll and HP readouts, the reward screen. The reference for system voice.

## 20. Rules the 3D field runs on

- **Ground:** painted landmass mask (30 px/m; white = sand; blurred edge) plus an optional elevation layer; height is a deterministic function of position.
- **Water:** one plane; depth-tinted and absorbing; seabed and caustics visible through the shallows; a thin foam line; swash on open shores only; pools still.
- **Props flat-shaded, characters textured.** Props take the shared flat material with a tint a step darker than sand; silvered wood leans slightly warm, never brown.
- **Fog** 14 → 28 m in the sky colour; the **tower** renders unfogged as a silhouette a few percent darker than the sky, visible only in the battle frame and at thresholds.
- **Palette (Region 1, before tonemap):** dry sand (0.74, 0.70, 0.60); wet sand × ~0.72; water shallow (0.54, 0.60, 0.61), deep (0.26, 0.36, 0.41); fog/sky (0.86, 0.87, 0.86); UI ink (0.165, 0.165, 0.18), bone (0.94, 0.91, 0.86); type keylines strike (0.62, 0.56, 0.49), guard (0.49, 0.56, 0.59), toll (0.54, 0.50, 0.58), utility (0.58, 0.58, 0.60), stance (0.52, 0.46, 0.56).
- **Type:** Spectral for world voice and card names; Alegreya Sans for system voice; one tracking value (0.16 em) for all caps labels.

## 21. Production Checklist

1. Does the frame work through large shapes alone?
2. Is the walkable ground immediately readable from the wadeable and the deep?
3. Does the Wanderer stay legible against everything behind him?
4. Does distance visibly remove information?
5. Is the palette cohesive and restrained — is dry sand the brightest large surface?
6. Is detail concentrated where it matters?
7. Is there enough negative space?
8. Does the environment feel larger than the character?
9. Does the UI sit *on* the world rather than in front of it?
10. Does it belong to the same visual world as the anchors?

If a frame fails the early questions, adding detail will not fix it.

---

**Document Version:** 2.0
**Status:** Working art-direction specification for the 3D build.
