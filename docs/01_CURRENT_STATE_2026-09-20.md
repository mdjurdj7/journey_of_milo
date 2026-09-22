# Current state — 2026-09-20

**Status:** a dated snapshot. It records what is built and what changed recently that files 02–06 do not say yet. It goes stale. When this file and the repo disagree, the repo is right — run `git log --oneline -20` first.

---

## 1. What exists in the 3D build

- **One field scene loads any floor** from data (`FloorData` / `RegionData`). Floors 1 and 2 of Region 1 exist. Floor 1 is the tutorial floor: a bulb of sand with a neck, water on three sides, hulls hauled up on a spit, the keeper on the east shore, one crab (Sputter), a gate, a bar that surfaces when the floor is cleared.
- **Camera:** top-down follow camera (pitch ~50°, 12 m). It never frames the horizon. Contact with an enemy freezes the field and swings the camera side-on (pitch 12°) for the card battle, played over the live scene.
- **Ground** is a painted landmass mask (30 px/m) plus an optional elevation layer. **Water** is one sea plane; the mask's 0.5 contour is the waterline.
- **The Wanderer** (textured, Mixamo-rigged) and **the keeper** (textured) are in. Props — three hulls and a cormorant — are flat-shaded.
- **Combat:** energy, block, Toll, Grace, stances; card hand and battle UI over the battle frame; enemy intent above the head; an interim "Left behind" reward screen.
- **Sound:** sea and wind ambience beds; short combat SFX. No music in Region 1.
- **Only one enemy is built: Sputter (a crab).** The old 2D project had more designs (a dragonfly, a debris quadruped, a horseshoe-crab elite, and others). They are reference only; none exist in the 3D build.

## 2. Changed on 2026-09-20 — not yet in the docs

### The tower is a landmark, not an axis
The tower sits far to the **west** of the opening floor (roughly due west of spawn, several hundred metres out), while the walk runs **inland (north)**. "Forward" comes from a `ForwardMarker` node, never from the tower's position. The tower renders unfogged, as a silhouette a few percent darker than the sky, with its foot fading out so it never meets a visible ground line.

### Title screen — over the live field
- Launch shows a flat boot colour for about a second while the field loads, then the title.
- The title is drawn **over the loaded field**, with the camera at the zone intro's opening pose and the fog closed to a couple of metres. The only thing of the world that survives is the tower, faint, right of centre. No sea, no land, no horizon.
- Type: the game title in **Spectral Light**, large, left-aligned on a generous left margin; below it `START GAME` and `EXIT GAME` in Alegreya Sans caps with 0.16 em tracking. The focused item is full ink with a short hairline to its left; the other is grey. No boxes, no button chrome, no background panel.
- Dev-only menu items from the old project were dropped. No settings, credits or version text yet.

### Zone intro — plays when a run starts
- On Start the title type fades, the fog opens, and the sea appears beneath a tower that has not moved. The region name fades in on the left in Spectral Light (~56 px at 1080p), holds, fades out.
- The camera then tilts and descends — about 3 seconds, one ease-in-out — from that near-level establishing shot into the normal top-down view on the Wanderer at the water's edge. Fog closes from the intro's long range back to the gameplay range during the move. Total about 4.5–5 s. Any fresh key/click after the first 0.4 s skips it.
- The opening frame is sea grading into fog in the lower ~40 %, the tower right of centre, the name on the left. No landmass, hulls or Wanderer in that first frame.
- It plays only on the first floor of a region at run start. Floor-to-floor transitions are unchanged: a brief look-up toward the tower, fade to fog, next floor.
- After death, Restart begins a new run directly (floor 0, full HP, intro) — it does not return to the title.

### Names
- **Region 1's name:** "Low Water" is the current proposal. The build may still show the placeholder "Region Name". Not final until it is in `floors/region1.tres`.
- **The game's title** is still officially undecided. The build currently displays "The Journey of Milo"; older notes use "The Long Walk" as a working title.

### In flight, not built
- **Live-bonus state on cards.** Cards with a conditional bonus (e.g. Left Hand: more damage if it is the first card this turn) will show when the bonus is live: the number shows the live value, the conditional clause goes from grey to full ink, and one hairline draws in along the card's type keyline; all of it reverses when the condition lapses mid-turn. No glow, pulse, colour change, icon or sound.

## 3. Known visual issues — open

- **The field renders darker than the palette numbers.** The Bible's Region 1 values are "before tonemap". After the tonemapper and contrast adjustment, the fog/sky authored at (0.86, 0.87, 0.86) lands around 0.76 on screen. The "high-key pale" target is being pulled down across the whole field. Unresolved; needs its own look.
- **An olive-tan band where the sea dissolves into fog** in the zone intro's opening frame. Probably seabed colour showing through where the water's depth tint and the fog cross over. It reads a little like a far shore in mist. Left alone for now.
- **The boot colour** (flat, not tonemapped) has to be matched by eye to the rendered fog, or there is a small step when the title arrives.

## 4. Art and design needs, from the documents' open lists

Nothing here is assigned or scheduled; it is what the docs say is missing.

**Creatures**
- Region 1 roster beyond Sputter: two or three more enemies, one elite, the region-end fight. All should read as ordinary, understandable wildlife that stayed. They stand still, often facing away from the player. "A crab beside a pool, not a crab among rocks."
- More non-enemy life: birds at the waterline are named as the cheapest next step.
- **The collector** (the shop): a creature bred to fetch, carry, sort and hand over, still doing its job centuries on. Species and form undecided. Guardrails: not waiting for the player, does not like them, good at its job, no mammal warmth, no humanoid merchant.

**Figures**
- **The traveller:** one NPC walking the same way as the player, always ahead, more worn at each meeting. In Region 1 he must read as unremarkable and in good condition. Appearance undecided. How he exists on a data-driven floor is open.

**Props and findings**
- **Belongings:** someone's pack, set down. The register is intrusion; the owner is gone, not dead. Flat-shaded props, distinct silhouettes.
- A **rest node without fire** — what replaces the fire as the reason to stop is open (shelter, water, sitting down, the act of stopping).

**Ground and vegetation**
- Vegetation: nothing exists yet. Marram grass at the dry end, sparse salt-tolerant tufts at the wet end. Masses, not individual plants.
- Dunes at the dry end (elevation layer); exposed-rock shading for elevated ground.
- More floor shapes. Painted landmass masks must not repeat: floor 1 is a bulb with a neck, floor 2 a bar with a pinch and an island. If every floor is a bulb the player stops looking.

**Pipeline reminder (full detail in file 04)**
- Props: Meshy, Smart Topology, texture **off**; glb at real scale, origin at the feet/keel; shared flat material with a tint a step darker than sand.
- Characters: textured, albedo only.
- Anything with colour baked in goes in the baked-colour register (file 04 §6).

## 5. Repo rules

One repo, two people, often more than one Claude Code session.

**Git**
- Never `git add .` — stage explicit paths only.
- Single-concern commits. Behaviour-identical refactors are committed separately from features.
- No push until the person says so. No force-push, no amend of commits that may have been pulled.
- Never `git stash`, `git restore` or `git checkout --` on a tree that may hold someone else's uncommitted work. Remove your own hunks by hand.
- Godot's `.uid` and `.import` sidecar files are committed alongside the asset or script.
- Several card `.tres` files carry CRLF line endings; git will normalise them the next time they are touched, so they may show as modified after an editor save. Cosmetic.
- If two sessions work at once, give each its own `git worktree` so they never share uncommitted hunks in one file.

**Godot**
- Use runtime `load()` for assets, not `preload` constants — `preload` on an asset the other person has not pulled breaks their checkout at parse time.
- `.tscn` files and `project.godot` are held in the open editor's memory. A text edit made while the scene's tab is open will be overwritten by the next editor save. Close the tab first, or make the change in the editor.
- Changes made in the editor's **Remote** tree while the game runs are lost on stop. Persistent values go on the node in the Local Inspector and are saved with the scene.
- All tunable values are `@export` with live setters. No hardcoded balance or layout numbers. Nothing hardcodes a world axis.
- Headless checks prove a script compiles. They prove nothing about how a frame looks. Visual work is verified in the running game — a screenshot of the running game is the accepted evidence.
- Claude Code does not run the game.

**Working pattern**
- Two-phase prompts: a read-only report first, a confirm, then implementation. Every prompt carries an explicit out-of-scope list and a verification list the human runs.
- See a thing run before building the next thing on top of it.
- No preemptive scaffolding: build for current consumers; extract a shared helper when a third consumer exists.
