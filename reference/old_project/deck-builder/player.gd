extends CharacterBody2D
class_name Player
# CharacterBody2D is Godot's built-in physics body for "something that
# moves around a 2D space and bumps into solid things" - a genuinely
# different kind of node from everything else in this project so far,
# which has all been Control (UI) or plain Node2D/Resource. The field
# room is a small physical space to walk through, not a screen of menus
# and cards, so it gets a real physics body instead.

const SPEED := 750.0
# The room is about 2300 units wide, ~1.2x the 1920-wide viewport (see
# field_room.tscn) - at this speed, walking from entrance to exit takes
# a few seconds, not a travel-time slog.

# --- Click-to-move (field movement redesign: mouse parity) ---
#
# Lives ALONGSIDE the keyboard path below, not instead of it - added as a
# second way to set `direction` each frame, with keyboard always winning
# the instant a key is actually held (see _physics_process()). click_to_
# move.gd is the one that decides WHAT x to move to (a plain ground click,
# or a walk-and-fire approach point beside an interactable), and field_
# room.gd itself drives it directly for the scripted room-transition beats
# (see its _play_walk_on_intro()/_on_exit_entered()); this script only
# knows "walk toward this x, arrive, done," identical to how it already
# only knows "which way, how fast" for keyboard input rather than anything
# about walls or rooms.
signal destination_set(x: float)
# Fired on every move_to() call, fresh OR retargeted - field_room.gd's
# click marker listens for this to show/reposition itself. Deliberately
# fired even when retargeting to the SAME x a moment later (no dedup) -
# the marker's own show_at() is idempotent (resets to full alpha, kills
# any fade) so a redundant call here is harmless, and guarding against it
# here would just be a second place that same idempotency lives.
signal destination_cleared()
# Fired exactly once per destination that goes away, whether by arrival
# OR by a keyboard key cancelling it (see _physics_process()) - the click
# marker doesn't care WHICH happened, only that it should fade out now,
# so one signal covers both rather than two the marker would have to
# treat identically anyway.

const ARRIVAL_THRESHOLD_PX := 6.0
# How close counts as "arrived" - without this, the player would
# overshoot-and-correct every frame trying to land on an exact float x,
# which reads as jitter right at the destination.

var _has_destination: bool = false
var _destination_x: float = 0.0

# --- Scripted movement lock (room-transition redesign, Option B) ---
#
# A general-purpose, reusable lock - NOT special-cased to room transitions,
# even though that's what first needed it. Setting this true stops
# keyboard input from being READ at all (see _physics_process() below);
# it does NOT stop a `move_to()` destination from being walked toward -
# that's the whole point: a caller sets this, then drives movement with
# the exact same move_to()/`velocity` path keyboard already uses, so
# footsteps (driven off `direction` below) and collision keep working
# identically to normal walking, just under scripted rather than player
# control. Callers are responsible for clearing it when the scripted
# moment ends; field_room.gd's click handlers separately check this
# before calling move_to() themselves, so a stray click during a locked
# moment can't retarget the scripted walk (this flag alone only blocks
# KEYBOARD input, not a caller choosing to call move_to() anyway).
var input_locked: bool = false

# Optional override for SPEED, used only while a caller is driving a
# scripted move_to() at a deliberately different pace than normal keyboard
# walking (see field_room.gd's walk_on_speed) - -1.0 (the default) means
# "use SPEED, unchanged." A caller sets this alongside input_locked and
# resets it back to -1.0 once the scripted move finishes; ordinary
# keyboard movement never touches this at all.
var scripted_speed: float = -1.0

func _current_speed() -> float:
	return SPEED if scripted_speed < 0.0 else scripted_speed

# --- Footstep cadence (2026-09-04, footstep-cadence pass) ---
#
# REPLACES the old single continuous LOOP (play_looping("walking")/stop_
# looping("walking")) - "walking" was found to be a genuine loop, not a
# per-step trigger (no cadence, no timer, one MP3 told to loop_mode/loop
# forever - see audio_manager.gd's own _looping_player_for()), so a pool
# of four per-step takes couldn't just swap into its existing hook; this
# is the approved rebuild. field/walking.wav.mp3 and its SFX_FILES/
# VOLUME_TRIM_DB entries are left in place, unreferenced - see their own
# notes in audio_manager.gd.
#
# Field-only: Player only exists in field_room.tscn (see this file's own
# header) - battle has no movement or footstep sound at all, so this
# cadence never runs there.
const FOOTSTEP_NAMES: Array[String] = ["footstep_1", "footstep_2", "footstep_3", "footstep_4"]

@export_group("Footsteps")
@export var footstep_interval_sec: float = 0.38
# Seconds between footfalls while moving - a plain tunable timer, NOT
# synced to the walk animation's own frame timing (explicitly out of
# scope for this pass). For reference while eyeballing this in the
# Inspector: the walk SpriteFrames animation (player_visual.tscn) runs
# 22 frames at an authored 20 fps, slowed by the Sprite's own speed_
# scale=0.6 to an effective ~12 fps - a full cycle takes ~1.83s. Read as
# two footfalls per cycle (one per stride), that's roughly ~0.92s apart -
# well over double this default, so 0.38s reads as a deliberately
# brisker cadence than the animation's own literal stride timing, not a
# derived match to it.
@export var footstep_pitch_min: float = 0.94
@export var footstep_pitch_max: float = 1.06
# Wider than battle.gd's own card-draw variance (0.95-1.05) - footsteps
# are the single most-repeated sound in the game, so they tolerate (and
# need) more spread to avoid a metronome feel.
@export var footstep_volume_db: float = -11.0
# Started at -12.0 (card_draw_single's own trim, exactly) - raised by
# +1.0dB (2026-09-04, live-feedback pass), a ~12% linear amplitude
# increase (20*log10(1.12) = 0.98dB), landing in the requested "10-15%
# louder" range - per-step footsteps read too quiet at the original
# trim once actually heard in-game. Still well under the old "walking"
# loop's -8 - a continuous loop and a per-step presence cue don't sit at
# the same level; -8 was tuned for a sound that's ALWAYS a little bit
# audible while moving, but individual footfalls firing every ~0.38s
# need to sit back further, at the same "frequent texture, not an event"
# level the draw cues already established.

var _footstep_timer: float = 0.0
# Counts DOWN by delta each moving physics frame; a footstep fires (see
# _play_footstep() below) whenever this reaches zero, then resets to
# footstep_interval_sec. Reset to 0.0 the instant movement stops (see
# _physics_process() below) - not just left to keep counting down - so
# the FIRST step after the next movement start fires immediately rather
# than waiting out whatever was left of the interval from before the
# player stopped. This is the entire lifecycle: no separate "is the
# cadence active" flag is needed, since direction==0.0 (checked fresh
# every physics frame, the same as the old play_looping()/stop_looping()
# check it replaces) is already the single source of truth for "moving
# right now," and a brand new Player instance (a fresh field room load)
# starts this at its own default 0.0 too - the exact same "fires
# immediately if still moving" behavior the OLD loop's own idempotent
# per-frame play_looping() call already gave for free across a scene
# transition, now reproduced by this timer's own default value rather
# than anything transition-aware.
var _last_footstep_name: String = ""
# The take _play_footstep() picked last, so the very next pick can
# exclude it - see that function's own doc. "" (no prior take) excludes
# nothing, since no FOOTSTEP_NAMES entry is ever the empty string.

# Uniform-random over FOOTSTEP_NAMES, excluding whichever take played
# last (2026-09-04) - "pick from the other three if the last take would
# repeat," per this pass's own brief: the difference between varied and
# almost-varied. Does NOT stop whatever the previous footstep's own
# AudioStreamPlayer is still doing - one-shots, played through the same
# shared POOL play_sfx() uses (see AudioManager.play_varied()), always
# ring out on their own regardless of what the cadence does next; that's
# what makes "stopping mid-decay on key release" a non-issue by
# construction, not something this function has to guard against.
func _play_footstep() -> void:
	var choices: Array[String] = FOOTSTEP_NAMES.filter(func(n: String) -> bool: return n != _last_footstep_name)
	var name: String = choices[randi() % choices.size()]
	_last_footstep_name = name
	AudioManager.play_varied(name, footstep_pitch_min, footstep_pitch_max, footstep_volume_db)

# Public entry point - field_room.gd calls this for every left-click that
# isn't on a UI element (see its own _unhandled_input()), already
# resolved to a final world x (clamped to the room's lane bounds for a
# plain ground click, or an interactable's own position for walk-and-
# fire). No queue: calling this while already walking toward a different
# x just overwrites it, same "last click wins" behavior a queue would
# need extra state to prevent anyway.
func move_to(x: float) -> void:
	_has_destination = true
	_destination_x = x
	destination_set.emit(x)

func _physics_process(delta: float) -> void:
	# WASD and arrow keys both move the player. Checking raw key state
	# directly like this (rather than Godot's built-in "ui_left" etc.
	# actions, which only cover arrow keys by default) keeps this
	# self-contained in this one script instead of also needing changes
	# to the project's global input map.
	# Horizontal-only, side-scroller-style movement - matches the battle
	# scene's spatial grammar (player and enemy laid out left-to-right).
	# No vertical input at all, so the player can't leave the ground line.
	var direction := 0.0
	if not input_locked:
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			direction -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			direction += 1

	if direction != 0.0:
		# Last input wins: a held movement key overrides an active click
		# destination on THIS frame, every frame, for as long as it's held -
		# not a one-time cancel that a click could then silently resume
		# from. Keyboard behaves exactly as it did before this feature
		# existed; this is the only new line on this path.
		if _has_destination:
			_has_destination = false
			destination_cleared.emit()
	elif _has_destination:
		var to_target := _destination_x - position.x
		if absf(to_target) <= ARRIVAL_THRESHOLD_PX:
			_has_destination = false
			destination_cleared.emit()
		else:
			direction = signf(to_target)

	velocity = Vector2(direction * _current_speed(), 0.0)

	# move_and_slide() is CharacterBody2D's built-in movement function:
	# it reads `velocity` (which we just set above) and moves the body
	# that far this physics step, automatically stopping at - and
	# sliding along - anything solid it bumps into, like the room's
	# walls. We only ever decide "how fast, which direction"; Godot
	# handles the actual collision response.
	move_and_slide()

	# Footsteps: a cadence tick for as long as a direction key is held,
	# silent (and reset - see _footstep_timer's own doc) the instant none
	# are. Reused as-is for click-to-move too - `direction` means
	# "actually moving this frame" regardless of which input set it, so
	# footsteps correctly keep firing while walking toward a click
	# destination, same as the old loop this replaces.
	if direction == 0.0:
		_footstep_timer = 0.0
	else:
		_footstep_timer -= delta
		if _footstep_timer <= 0.0:
			_play_footstep()
			_footstep_timer = footstep_interval_sec
