# Content map — Region 1 ("Landfall")

A read-only audit of every point of interest (POI) on the five floors of `floors/region1.tres`, with walking distances measured on each floor's own walk grid. Snapshot of `main` at `9384be1` (2026-10-15). Images are in `docs/content_map/`.

## How this was measured

- **Positions** are world (x, z) in metres. Every floor spawns at the origin, so they are also offsets from spawn. −Z is up the image, toward the tower. Enemy and prop positions are where they spawned in a headless load of each floor, not the authored values.
- **Walk grid.** Each floor's `NavGrid` was dumped after a headless load: Ground's walk heights, deep water, slopes over 45°, prop footprints, and 0.35 m cells inflated by 0.5 m. Paths use the same rules as `AStarGrid2D`: 8-way moves, diagonals only past no obstacle, shallows cost ×6, and line-of-sight smoothing that never wades where the raw path didn't.
- **Ledge walls re-stamped.** The dumped grid leaks through most of the `LedgeBarrier` walls on floors 3–5 (see the side finding at the end), while the walls themselves stop him. So every ledge line was stamped solid with the grid's own inflation before pathing. The distances below are what he can actually walk.
- **Leg ends.** A leg to a fight ends where he enters the nearest contact zone (`contact_radius_m`, 1.0–3.2 m). A leg to a prop ends at its approach or trigger radius. The gate and exit are lines across the exit direction, not points: the hold or channel line, and the 2 m-deep exit trigger (`ExitGate.fit_trigger_to_land`). A leg to either ends at the nearest walkable crossing.
- **Straight line** is measured to the same leg end, so it compares directly with the walking distance. "Centre" is the straight line to the POI's own centre.
- **Speed.** The Wanderer walks at **5.0 m/s**: `region_field.tscn` overrides the script's 4.5. Walking times are distance ÷ 5.0, with no acceleration or click overhead.
- **Detour** = extra distance to leave the main route, visit the POI and rejoin, inserted at the cheapest leg. **All detours** is the best order for visiting every optional POI on its leg, solved as one tour, not a sum, since the trough sits on the island and the bird next to Hull2.
- **Empty stretch** = the longest run of the main route with no content POI within 6 m. Spawn, gate, exit, silent hulls and the rock shelf don't count as content. Members of a pack count individually.
- **Real floor times** come from the 182 run logs in `user://runs/`: debug runs excluded, lap 0 only, timed from one floor's `floor_entered` to the next. They are your own playtests across several versions, so treat them as a floor rather than a target.

Rewards by role (`run/encounter_rewards.tres`): **required** = a card offer + the floor's gold; **elite** = a card offer at elite rates + gold ×1.5 (+ the enemy's keepsake roll and Glassbone); **optional basic** = a card offer + the floor's gold, and a 30 % chance of a Samphire beside them (removal is the collector's alone); **region-end** = cards top tier first + gold.

No slot on any floor has more than one option, so **nothing is randomized yet**. No floor has an **event**.

---

## Floor 1: the landing (tutorial)

![Floor 1](content_map/floor1.png)

Gold 10–15. CHANNEL gate.

| POI | Type | Req? | Gives | (x, z) | Access |
|---|---|---|---|---|---|
| Spawn | spawn | – | – | (0.0, 0.0) | – |
| Sputter (`crab`) | required fight | yes | cards + 10–15 gold | (−2.3, −10.7) | dry, beside the pool |
| The Keeper | NPC | no | keepsake offer (one per run, from her table) | (10.1, −7.0) | dry |
| Hull2 | world-voice prop | no | nothing (line: "Hauled up past the tide, and left.") | (−7.5, −0.3) | dry |
| Cormorant (on Hull0) | ambient | no | nothing (flies off at 4 m, once per run) | (−10.2, 0.2) | dry |
| Hull0, Hull3 | dressing (silent) | no | nothing | (−10.5, −1.3), (−8.2, −9.0) | dry, not counted |
| Gate | gate (channel) | yes | – | crossing at (−0.4, −16.5) | channel drains to a bar on clear |
| Exit | exit | yes | – | (−0.4, −18.2) | across the bar |

**Main route**

| Leg | Walk | Straight (centre) | Wading | Time |
|---|---|---|---|---|
| Spawn → Sputter contact | 8.9 m | 8.9 (10.9) m | 0 | 1.8 s |
| Sputter → gate | 8.0 m | 7.8 m | 0 | 1.6 s |
| Gate → exit | 1.8 m | 1.8 m | 1.6 m* | 0.4 s |
| **Total** | **18.6 m** | | | **3.7 s** |

\* The 1.6 m is the channel as the grid had it at load. By the time he crosses, it has drained to a bar, so there is no wading in play.

**Detours:** the Keeper +11.1 m (2.2 s) · Hull2 +4.7 m (0.9 s) · cormorant +6.5 m (1.3 s) · Hull3 +4.9 m (1.0 s). All detours: **41.1 m (8.2 s)**, visiting bird → Hull2 → Keeper on the way up.

**Longest empty stretch:** 4.7 m, the first steps from spawn, (0, 0) → (−1.0, −4.7). There is effectively none.

---

## Floor 2: the island shore

![Floor 2](content_map/floor2.png)

Gold 12–18. LINE gate.

| POI | Type | Req? | Gives | (x, z) | Access |
|---|---|---|---|---|---|
| Spawn | spawn | – | – | (0.0, 0.0) | – |
| Sputter + Underfoot (`crab`, one of two) | required fight | yes | cards + 12–18 gold | Sputter (1.5, −21.3), Underfoot (−0.8, −21.3) | dry |
| Underfoot + Glower (`crab`, the other) | required fight | yes | cards + 12–18 gold | Glower (1.5, −23.0) in its own standing pool (1.6 × 1.2 m), Underfoot (−0.8, −21.3) | dry |
| Dragonfly ×3 (`island`) | optional fight | no | cards + 12–18 gold, 30 % extra | patrol (−16.8, −20.8) → (−13.0, −20.4) → (−14.8, −18.5) | **wading**, ~6 m each way |
| Trough **or** Glassbone seam (`island_reward`, 1:1) | trough / seam | no | trough: heal 15; seam: 1 Glassbone (one temper at floor 3's wagon); either once per run, inert until the island is cleared | (−15.1, −19.9) | **wading**, on the island |
| Siltjaw (`siltjaw`) | optional fight | no | cards + 12–18 gold, 30 % extra | (5.2, −7.0) | dry, on a dune 0.55 m up |
| Belongings cache | finding | no | one of: 45 gold / a card (belongings pool) / the Bedroll (a rest: 30 % of max HP, one use; not with one carried); 25 % that one also holds Glassbone. Line: "Three packs, set down out of the wind. Nobody came back." | (10.1, −24.3) | dry, the east alcove |
| Rock shelf | terrain | no | nothing (a walkable slab) | (−4.6, −24.4) | dry, not counted |
| Gate | gate (hold line) | yes | – | crossing at (0.9, −28.8) | – |
| Exit | exit | yes | – | (0.9, −30.5) | – |

**Main route**

| Leg | Walk | Straight (centre) | Wading | Time |
|---|---|---|---|---|
| Spawn → crab contact | 20.0 m | 20.0 (21.2) m | 0 | 4.0 s |
| Crab → gate | 8.7 m | 8.7 m | 0 | 1.7 s |
| Gate → exit | 1.8 m | 1.8 m | 0 | 0.4 s |
| **Total** | **30.5 m** | | | **6.1 s** |

**Detours:**
- Siltjaw: +1.8 m (0.4 s). It sits beside the route.
- Island: +26.0 m (5.2 s), 12.2 m of it wading.
- Trough: +22.8 m (4.6 s), 11.3 m wading. It is the same trip as the island.
- Cache: +9.0 m (1.8 s).

All detours: **73.0 m (14.6 s), 13.1 m wading**, visiting Siltjaw on the way up, then island → trough → cache after the crab.

**Longest empty stretch:** 4.5 m, (0.4, −10.8) → (0.7, −15.3), between Siltjaw and the crab. There is effectively none.

---

## Floor 3: the inland basin

![Floor 3](content_map/floor3.png)

Gold 15–22. LINE gate, 32 m beyond the Blackback.

| POI | Type | Req? | Gives | (x, z) | Access |
|---|---|---|---|---|---|
| Spawn | spawn | – | – | (0.0, 0.0) | – |
| Blackback + Nipper (`blackback`) | required fight | yes | cards + 15–22 gold | Blackback (−3.0, −9.0), Nipper (−4.7, −8.5) | dry |
| Wardling (`wardling`) + hitching post | elite | no | cards (elite rates) + 22–33 gold + keepsake roll + 1 Glassbone | Wardling (17.6, −13.6), post (15.9, −16.1) | **behind a ledge wall**: the straight line from the route crosses the wall, so he goes round into the east lobe from the north |
| Wagon | workbench | no | temper a card for 1 Glassbone. Line: "A wagon, unhitched. The tools are still on it." | (−7.3, −28.1) | dry, the north-west lobe |
| Gate | gate (hold line) | yes | – | crossing at (20.9, −31.5) | – |
| Exit | exit | yes | – | (22.3, −32.9) | – |

**Main route**

| Leg | Walk | Straight (centre) | Wading | Time |
|---|---|---|---|---|
| Spawn → Blackback contact | 7.5 m | 7.5 (9.5) m | 0 | 1.5 s |
| Blackback → gate | 34.2 m | 34.2 (32.9) m | 0 | 6.8 s |
| Gate → exit | 2.0 m | 2.0 m | 0 | 0.4 s |
| **Total** | **43.7 m** | | | **8.7 s** |

**Detours:** Wardling +13.5 m (2.7 s) · Wagon +12.9 m (2.6 s). All detours: **81.2 m (16.2 s)**.

**Longest empty stretch:** **28.7 m (5.7 s)**, (2.2, −12.4) → the exit at (22.3, −32.9). That is everything after the Blackback: the whole north-east arm. The Wardling passes 10 m off it, behind its wall, and the Wagon about 19 m.

---

## Floor 4: the dune loop

![Floor 4](content_map/floor4.png)

Gold 18–25. LINE gate.

| POI | Type | Req? | Gives | (x, z) | Access |
|---|---|---|---|---|---|
| Spawn | spawn | – | – | (0.0, 0.0) | – |
| Dunecur (`dunecur`) + bones | required fight | yes | cards + 18–25 gold | Dunecur (−18.5, −35.0), bones (−19.7, −35.4) | dry, at the mouth of the exit neck |
| Adder (`adder`) | elite | no | cards (elite rates) + 27–37 gold + keepsake roll + 1 Glassbone | (11.0, −22.5) | **behind a ledge**: in the curl of the central dune, reached round the east side of the ring |
| The Collector | NPC (shop) | no | shop: 5 cards (collector pool), Samphire, one removal (50) — never restocked. Line: "It is sorting what it has." | (−24.4, −21.6) | dry, the west pocket |
| Gate | gate (hold line) | yes | – | crossing at (−25.7, −34.8) | – |
| Exit | exit | yes | – | (−27.5, −35.1) | – |

**Main route**

| Leg | Walk | Straight (centre) | Wading | Time |
|---|---|---|---|---|
| Spawn → Dunecur contact | 37.1 m | 36.5 (39.4) m | 0 | 7.4 s |
| Dunecur → gate | 8.7 m | 8.7 m | 0 | 1.7 s |
| Gate → exit | 1.8 m | 1.8 m | 0 | 0.4 s |
| **Total** | **47.6 m** | | | **9.5 s** |

**Detours:** Adder +27.6 m (5.5 s) · Collector +5.8 m (1.2 s). All detours: **94.7 m (18.9 s)**.

**Longest empty stretch:** **33.9 m (6.8 s)**, from spawn (0, 0) to (−16.4, −29.2): the whole first leg, up the west side of the central dune. The Collector is 12 m off it.

---

## Floor 5: the climb (region end)

![Floor 5](content_map/floor5.png)

Gold 35–45. LINE gate.

| POI | Type | Req? | Gives | (x, z) | Access |
|---|---|---|---|---|---|
| Spawn | spawn | – | – | (0.0, 0.0) | – |
| Greyshelf (`greyshelf`) | region-end fight | yes | cards top tier first + 35–45 gold + 1 Glassbone | (−0.6, −42.0) | dry, 3.3 m above spawn up the slope |
| Gate | gate (hold line) | yes | – | crossing at (−0.5, −53.9) | – |
| Exit | exit | yes | – | (−0.5, −55.6) | – |

**Main route**

| Leg | Walk | Straight (centre) | Wading | Time |
|---|---|---|---|---|
| Spawn → Greyshelf contact | 38.9 m | 38.9 (42.0) m | 0 | 7.8 s |
| Greyshelf → gate | 15.0 m | 15.0 m | 0 | 3.0 s |
| Gate → exit | 1.8 m | 1.8 m | 0 | 0.3 s |
| **Total** | **55.7 m** | | | **11.1 s** |

**Detours:** none. There is nothing optional on the floor.

**Longest empty stretch:** **35.9 m (7.2 s)**, from spawn (0, 0) to (−0.4, −35.8), the whole climb. A second stretch of 7.4 m runs past the gate. The west pocket, about (−8, −16), and the wide bulb north of the exit are unused ground.

---

## Per-floor summary

| | F1 | F2 | F3 | F4 | F5 |
|---|---|---|---|---|---|
| Required fights | 1 | 1 | 1 | 1 | 1 (region end) |
| Optional fights | 0 | 2 | 0 | 0 | 0 |
| Elites | 0 | 0 | 1 | 1 | 0 |
| **Encounters total** | **1** | **3** | **2** | **2** | **1** |
| Findings (belongings / pool) | 0 (Hull2's line) | 2 (cache, trough) | 0 | 0 | 0 |
| NPC / shop / workbench | Keeper | – | Wagon | Collector | – |
| Ambient / world-voice | bird, Hull2 | – | – | – | – |
| Main route | 18.6 m · 3.7 s | 30.5 m · 6.1 s | 43.7 m · 8.7 s | 47.6 m · 9.5 s | 55.7 m · 11.1 s |
| With all detours | 41.1 m · 8.2 s | 73.0 m · 14.6 s | 81.2 m · 16.2 s | 94.7 m · 18.9 s | 55.7 m · 11.1 s |
| Wading (all detours) | 0 in play | 13.1 m | 0 | 0 | 0 |
| Longest empty stretch | 4.7 m | 4.5 m | **28.7 m** | **33.9 m** | **35.9 m** |
| Playtest floor time, median (n) | 1.7 min (22) | 2.6 min (16) | 2.2 min (12) | 2.6 min (9) | 1.7 min (5) |
| Playtest time outside fights, median | 38 s | 50 s | 41 s | 55 s | 19 s |

Median fight lengths from the same logs: Sputter 30 s · Siltjaw 26 s · Dragonfly ×3 26 s · Sputter + Underfoot 40 s · Blackback + Nipper 37 s · Wardling 47 s · Dunecur 44 s · Adder 41–93 s (n = 3) · Greyshelf 57 s.

### Against the framework budget (02 §1)

The framework budget per floor is 2–3 encounters with one required, one finding, and about 5–7 minutes.

- **Time: every floor is under budget, by 2.5–4 minutes.** Walking is 4–11 s on the main route and at most 19 s with every detour. The floor's time is its fights, screens and transitions, and in your playtests that comes to 1.7–2.6 minutes. Walking can't close the gap. Reaching 5–7 minutes takes more stops (fights, findings, choices), not more ground.
- **Floor 1** is the declared exception: one crab, the Keeper and the hulls. It matches its brief.
- **Floor 2** is the only floor fully on budget: 3 encounters, one required, two findings (cache and trough). Its optional content is where the framework says it should be, behind 6 m of wading.
- **Floor 3** has 2 encounters, which is in range, but **no finding**. The Wagon is a workbench, not a finding.
- **Floor 4** has 2 encounters, in range, and the Collector, but **no finding**.
- **Floor 5** has **1 encounter and nothing else**. It is under budget on encounters and findings, and there is **no rest before the region-end fight**: the only heals in the region are floor 2's trough (half of runs - the other half roll its Glassbone seam) and a Bedroll from floor 2's belongings.
- **Region-level:**
  - Elites fall on floors 3 *and* 4, back to back. The framework says roughly every third floor.
  - The Collector appears once, on floor 4, as the framework asks.
  - The region has 5 floors; the framework says 3–4.

### Where floors need content

1. **Floor 5**: the 36 m climb from spawn to the Greyshelf is the longest empty stretch in the region, and the floor has nothing optional. It is the natural place for the missing rest before the region-end fight, and the west pocket at about (−8, −16) is open ground.
2. **Floor 4**: the 34 m first leg, spawn → Dunecur, passes nothing. The floor has no finding.
3. **Floor 3**: the 29 m arm after the Blackback, (2, −12) → the exit, passes nothing. The floor has no finding.
4. **Floors 1–2** are dense. On floor 2, no stretch of the route is more than 4.5 m from content.

---

## Side finding (not fixed; out of scope)

**The walk grid leaks through ledge walls.** The most likely cause, from reading the code rather than testing a fix: in `NavGrid.footprint_cells()`, a `LedgeBarrier` segment box that covers no cell centre falls back to a line between the midpoints of `hull[0..1]` and `hull[half..half+1]`. The box is 0.2 m thick and the cells are 0.35 m. When those two hull edges are the box's long sides, the fallback line runs across the box rather than along it, and only about one cell gets stamped.

In the dumped grids, 94–96 % of each of floors 3–5 is reachable from spawn, including the ground outside the walls and the top of floor 4's central dune. One gap on floor 3 is 7.9 m long: the south edge of the Wardling's lobe, (7.5, −9.95) → (15.4, −9.9). The physics wall still stops him. What changes is the plan: a path or click can route through a gap, and he would then stall against the invisible wall (`path_stuck`).

`tests/pathing_probe.gd` checks a single stem → lobe path against the ledge lines, so a leak anywhere else wouldn't show up in it.
