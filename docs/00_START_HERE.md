# Start here — context pack for the game

**Assembled:** 2026-09-20
**What this is:** the design documents for the game plus a snapshot of where the build stands, so a second Claude project can work on it with the same context as the first.

Upload every file in this folder to the project's knowledge. Read them in number order the first time.

---

## The project in five lines

- A roguelike deckbuilder in **Godot 4.7.1 (3D, GDScript)**. A run is a sequence of floors; each floor is a free-roam 3D field under a high top-down camera; card combat happens in place, with the camera swinging side-on.
- **Premise:** a tower was built to evacuate a world everyone believed was ending. Everyone left. The belief was wrong. The signal still runs and delivers nothing. The character is walking toward it without knowing that.
- **Tone:** indifferent, quiet loneliness in daylight. Not grimdark. Nothing in the world has a relationship with the player.
- **Region 1** is a tidal flat: bright, pale, empty, the least depleted place in the run.
- Two people work on it from one git repo. One does systems, architecture and implementation through Claude Code; the other contributes art assets and visual direction.

## The files

| # | File | What it settles | Trust level |
|---|---|---|---|
| 01 | `01_CURRENT_STATE_2026-09-20.md` | What is built, what changed recently that the docs don't say yet, open art needs, repo rules | Snapshot — goes stale; check `git log` |
| 02 | `02_GAME_FRAMEWORK_v2.md` | Structure: floors, combat, systems, presentation rules, open list | **Wins on structure** where docs disagree |
| 03 | `03_ART_DIRECTION_BIBLE_v2.md` | Visual principles, value hierarchy, palette numbers, anti-goals, checklist | **Wins on visual principle** |
| 04 | `04_FIELD_ASSET_SPEC_v1.md` | How assets are made, sized, imported, tuned: ground masks, water, models, sound, UI | **Wins on numbers and pipeline** |
| 05 | `05_REGION_01_v4.md` | Region 1 in detail: gradient, keeper, light, floor grammar, what it must not do | Current |
| 06 | `06_REGION_PROGRESSION_v1.md` | Premise, world-state consequences, the four regions, the traveller, the tower encounter | **Premise is current; presentation language is 2D-era** — see note below |

### Note on file 06

The other documents cite a "Region Progression v2". The copy in this pack is v1. If a v2 exists in the repo's `docs/` folder, use that instead and drop this one.

Until then, read v1 for **premise, world state, region function, the traveller and the tower encounter** — all of which still hold — and ignore its presentation language where it conflicts with files 02–05. Specifically:

- v1 says the tower is visible from every region while travelling. **Superseded:** under the top-down camera the horizon is never in frame. The tower is visible only in the battle frame, at floor thresholds, and on the title / zone intro (file 01).
- v1 talks about "frame", "crossing the frame", horizontal vs vertical composition. That is side-scroller language. The 3D equivalents are in the Bible §10 and the Framework §1–§2.

### Deliberately not included

`BACKGROUND_ASSET_SPEC_v2.md` — the 2D parallax pipeline (alpha masks vs painted plates). **Retired**; replaced by file 04. Leaving it out so nobody builds to it. The one idea that survived is the baked-colour register, which file 04 §6 carries.

---

## Rules that are easy to break

These come up constantly. They are all stated in the docs; collected here because they are the ones a fresh reader violates first.

**Fiction**
- Never explain the tower. World events leave questions unanswered.
- Nothing is arranged for the player: no room guarded, prepared, or set up as a challenge.
- **Damage is forbidden; age is required.** Nothing burned, broke, or was thrown down. Things were set down and not picked up, then stood for centuries without anyone caring.
- Enemies are things that stayed — in Region 1, ordinary and legible wildlife. Strangeness scales with depletion (distance inward), not difficulty.
- The signal is not addressed to anyone. No chosen-one framing.

**Visual**
- Dark figures on pale ground. Characters, enemies and UI are the dark elements; the world is the pale one.
- Region 1: **no warm light anywhere.** Dry surfaces may lean slightly warm; light may not.
- Props are flat-shaded, one shared material plus a tint — silhouette is all that survives. Characters are textured.
- No glow, no boxes, no icon libraries in UI. Ink on the world; bone cards with ink type; hairlines.
- Two voices: world voice in Spectral, system voice in Alegreya Sans.
- Do not decorate the flat. Negative space is composition.
- Age on props is placement (sink, roll), never damage.

---

## Suggested project instructions for the second Claude

Paste into the project's custom instructions and edit to taste:

> This project is a Godot 4.7.1 3D roguelike deckbuilder. The uploaded documents are the source of truth; where they conflict, GAME_FRAMEWORK wins on structure, ART_DIRECTION_BIBLE on visual principle, FIELD_ASSET_SPEC on numbers and pipeline. 01_CURRENT_STATE is a dated snapshot — prefer the repo's actual state when they differ.
>
> Before proposing art, props, creatures or UI, check the proposal against the Bible's anti-goals (§18), the production checklist (§21), and Region 1's "must not do" list (REGION_01 §11). Say plainly when something violates them.
>
> Give direct verdicts with reasoning rather than menus of options. Push back when a request conflicts with the documents.
>
> Anything not decided in the documents (region names beyond what 01 records, the game's title, the collector's species, the traveller's appearance, enemy rosters beyond Region 1) is open — propose, don't assume.
>
> For repo work follow the rules in 01_CURRENT_STATE §5.
