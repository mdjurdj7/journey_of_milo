# The Long Walk — Claude Code rules

## Workflow
- Two-phase: Phase 1 is read-only investigation with a report back.
  Do not implement until I say go.
- Every task states its out-of-scope list. Stay inside it.
- Never run the game. I verify against a live instance and report back.

## Git
- Never `git add .`. Stage explicit file paths only.
- Local commits only. Never push unless told.
- One concern per commit. Behavior-identical refactors are separate
  commits from feature work.
- Run `git status` before staging; the tree often has WIP files
  that must not be committed.

## Godot conventions
- Godot 4.7.1, GDScript.
- All tunable values are `@export`. No hardcoded balance numbers.
- Use runtime `load()` for asset paths, never `preload` constants —
  they break teammate checkouts.
- Build for current consumers. Extract shared helpers only when a
  third instance exists.

## Project docs
- DESIGN.md tracks parked decisions and deferred items. Update it when
  a decision is deferred.
- BESTIARY.md is the enemy source of truth.
