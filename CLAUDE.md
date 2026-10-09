# The Long Walk — Claude Code rules

## Workflow
- Two-phase: Phase 1 is read-only investigation with a report back.
  Do not implement until I say go.
- Every task states its out-of-scope list. Stay inside it.
- Never run the game. I verify against a live instance and report back.

## Git
- Local commits only when I explicitly ask. Never stage with
  `git add .`; name each path.
- One concern per commit. If the diff mixes my task with unrelated
  WIP, commit only my files and tell me.
- Run `git status` before staging; the tree often has WIP files
  that must not be committed.
- Always commit with `git commit -- <paths>`, so files another session
  has staged can't be included.
- When more than one Claude Code session works at once, each works in
  its own git worktree, never in the shared main tree:
  `git worktree add ../journey-of-milo-<task> -b <task-branch>` (or
  detached at main). Commit there, then bring the commits onto main
  (fast-forward or cherry-pick) by explicit path.
- Never run two sessions in the same working tree. If another session
  may be active, work in your own `git worktree`. Before editing
  anything in main, check `git status` and stop if there are changes
  you didn't make.
- Never deliberately break code in main, even temporarily: no mutation
  tests, no backup-and-restore. Breakage tests run only in a throwaway
  worktree, which you delete afterwards.
- Never edit shared tools (run_probes.sh, CLAUDE.md) while another
  session's probe run may be using them; commit such changes quickly
  and separately.
- New scripts and shaders (.gd, .gdshader, .gdshaderinc) ship with
  their .uid. After creating one, run the Godot 4.7.1 main executable
  (not the _console wrapper) with `--headless --path . --import`,
  confirm the .uid exists, and stage it by path in the same commit as
  the file. The .githooks/pre-commit hook rejects a commit that misses
  one (enable per machine: `git config core.hooksPath .githooks`).
- The .githooks/ folder also carries the Git LFS hooks, so pushes
  upload LFS objects; git-lfs must be installed on every machine.
- Don't stage default_bus_layout.tres unless a bus change was
  intended; revert stray edits from the editor's Audio panel.

## Probes
- Run them with tools/run_probes.sh (--help), from your own worktree:
  `--path <worktree>`, after `--import` there. With no -j it runs one
  probe at a time when under 6 GB is free at the start, else two; it
  waits for memory rather than start a probe that would leave under
  2000 MB free, and ends everything it started if it's stopped.
- During a task: run only the new probes and the probe files the task
  edited (`--probe`), once, at the end, in the foreground - not whole
  areas, and not `--changed`.
- Areas and `--changed` sweeps are for `--prepush`: before a push, run
  `--prepush` once, in the foreground. It runs the probes mapped to the
  files changed in origin/main..HEAD, plus the fast tier, and prints the
  list first.
- Runs record their timings in tools/probe_times.local.txt (git-ignored),
  never in the tracked tools/probe_times.txt; `--refresh-times` copies
  the local averages over it when I choose to commit them. `--batch`
  splits by the committed copy.
- `--full` only when I ask for it, always as `--full --batch 1/4` ...
  `--batch 4/4`, each in the foreground.
- Never run probes in the background. Never start probes while another
  session's probes are running: check for running Godot probe
  processes first (PowerShell: `Get-CimInstance Win32_Process -Filter
  "Name='Godot_v4.7.1.exe'"`, any whose CommandLine has
  `-s res://tests/`, or `--headless --path . --import` - a run's import);
  if there are any, stop and tell me.
- If a run is stopped for memory, don't retry: end any leftover
  processes from it, report, and wait.
- Docs, assets and visual-only changes need no probe run.

## Probe worktrees
- When testing a change to any .import file in a worktree that copied
  the main tree's .godot cache, first delete that asset's cached
  entries in the worktree (.godot/imported/<file>-*), so --import
  re-imports it with the new settings. Otherwise the stale import
  stays and the probes test the old settings.

## Godot conventions
- Godot 4.7.1, GDScript.
- All tunable values are `@export`. No hardcoded balance numbers.
- Use runtime `load()` for asset paths, never `preload` constants —
  they break teammate checkouts.
- Build for current consumers. Extract shared helpers only when a
  third instance exists.
- Audio follows 04_FIELD_ASSET_SPEC §4: WAV or MP3 are both fine - don't
  flag the format. Do flag level (not −6 dBFS peak), trim (more than a
  few ms before the first transient) and channels (stereo for a
  positional sound).

## GDScript strictness
- The project treats inferred-Variant as an error. Never write `:=`
  when the right-hand side is untyped: lerp(), get_node(),
  get_node_or_null(), Dictionary access, Object.get(), or any
  function without a declared return type. Declare the type
  explicitly, use lerpf/lerp with typed operands, and give every
  function a return type including -> void.
- Every field script uses class_name.

## Field conventions
- Field forward is derived at runtime from spawn→ForwardMarker via
  RegionField.get_forward(). Never hardcode an axis. The Tower is a
  landmark placed for the frames that show it, not an axis — nothing
  derives direction from it.
- RegionField is the scene root; child NodePaths are ^"Sea", not
  ^"../Sea".
- Children _ready() before parents. Anything a child needs from
  RegionField goes through a lazy getter.
- Every @export tunable gets a setter that re-applies live so
  Remote-tab edits take effect. No apply-once-in-_ready exports.
- Imported models: origin may be centered, not at the feet — ground
  by AABB. Mixamo rigs face +Z; apply a yaw offset. AnimationTree
  root_node must point at the model. FBX imports carry a static
  "Take 001" clip that outscores the real one on track count — select
  by keyframe count.
- Freezing RegionField removes physics bodies unless disable_mode is
  MAKE_STATIC; anything that must be raycast during battle needs it.

## Project docs
- docs/ holds the design context, in number order - read
  docs/00_START_HERE.md first, then what the task needs:
  02_GAME_FRAMEWORK_v2.md wins on structure, 03_ART_DIRECTION_BIBLE_v2.md
  on visual principle, 04_FIELD_ASSET_SPEC_v1.md on numbers and pipeline
  (masks, models, sound, UI), 05_REGION_01_v4.md for region 1,
  06_REGION_PROGRESSION_v1.md for the premise and the later regions.
  01_CURRENT_STATE is a snapshot and goes stale - check git log instead.
- Read 02_GAME_FRAMEWORK_v2.md and, for a field task, 04_FIELD_ASSET_SPEC_v1.md
  before any design or field work.
- DESIGN.md tracks parked decisions and deferred items. Update it when
  a decision is deferred.
- BESTIARY.md is the enemy source of truth - and does not exist yet;
  battle/rules/enemies/*.tres is the truth until it does.
