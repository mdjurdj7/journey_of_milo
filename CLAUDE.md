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

## Godot conventions
- Godot 4.7.1, GDScript.
- All tunable values are `@export`. No hardcoded balance numbers.
- Use runtime `load()` for asset paths, never `preload` constants —
  they break teammate checkouts.
- Build for current consumers. Extract shared helpers only when a
  third instance exists.

## GDScript strictness
- The project treats inferred-Variant as an error. Never write `:=`
  when the right-hand side is untyped: lerp(), get_node(),
  get_node_or_null(), Dictionary access, Object.get(), or any
  function without a declared return type. Declare the type
  explicitly, use lerpf/lerp with typed operands, and give every
  function a return type including -> void.
- Every field script uses class_name.

## Field conventions
- Field forward is derived at runtime from spawn→Tower via
  RegionField.get_forward(). Never hardcode an axis.
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

## Project docs
- DESIGN.md tracks parked decisions and deferred items. Update it when
  a decision is deferred.
- BESTIARY.md is the enemy source of truth.
- Read docs/GAME_FRAMEWORK.md before any design or field task.
