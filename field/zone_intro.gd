extends Node
class_name ZoneIntro

# The zone intro: the opening shot a new run's first floor plays before
# the field is handed over. A child of RegionField (process ALWAYS, so it
# runs through the field freeze it puts up), idle until RegionField.
# _ready() calls play() on a run's first floor (RunState.run_opening_
# pending - never a later floor, never a restart).
#
# The shot: the frame starts full fog colour and lifts; the camera stands
# in a FREE pose - pose_height up, pose_back_distance behind spawn along
# the view axis, near level, the tower at tower_frame_x of the frame
# width with open sky on the other side for the title - under a far fog
# (fog_depth_begin/end here) so the sea reads out to a dissolved horizon
# and the tower stands above the haze; the region's display_name fades
# in and out on the sky; then position, yaw, pitch, fov and fog all run
# on ONE smoothstep down onto the live follow pose (CameraRig.set_free_
# blend() - the end values are what the rig computes that frame, never
# stored, so the landing has no pop), and _finish() releases the freeze.
#
# "Fog" is two things driven as one: RegionSky's depth fog (fog_depth_
# begin/end) and the Sea's own copy of it (Sea.fog_near_distance/far_
# distance - its shader is fog_disabled and reproduces the same curve
# itself, see sea.gdshader). Both pairs are read at start, run on the
# same curve to the same values, and put back in _finish() - without the
# sea's, the water would keep dissolving at the region's 28 m while the
# sky and sand opened to 100.
#
# The freeze is the battle one (RegionField.process_mode DISABLED: no
# input, no click-to-move, approach areas and enemy contact out of the
# physics space, no world lines, no keeper prompt) plus the HUD hidden -
# with the Wanderer alone kept ALWAYS and input-locked (Wanderer.input_
# locked), so gravity and his foot grounding run and his feet are planted
# when the camera lands rather than snapping down on release.
#
# Both ends - the timeline's own, and a skip (any key/mouse/joypad button
# press after skip_lockout_seconds, blended out over skip_blend_seconds) -
# go through the one _finish(), so the end state is identical: fog back
# to the region's own values, free pose cleared, title and fade gone,
# Wanderer INHERIT and unlocked, HUD shown, field live.
#
# The title screen is this same frame zero, held (TITLE_HOLD, entered by
# hold_title() when the boot scene raised RunState.title_pending): the
# same freeze, the same pose from the same exports, the fog closed to
# title_fog_begin/end so only the unfogged tower survives, and the
# TitleMenu (ui/title_menu.tscn) over it owning input. Start
# (start_from_title()) fades the menu, then runs the ordinary timeline
# from t = 0 - with the fog opening from the title values to the intro's
# over title_fog_open_seconds where a play() would have had the fade
# lift - so the tower never moves and nothing loads between the press
# and the sea appearing. The three debug exports (debug_hold_opening,
# debug_replay, debug_title_hold) exist for tuning the held frames live
# from the Remote tab and replaying without a restart.

signal finished

const TITLE_FONT_PATH := "res://assets/fonts/Spectral-Light.ttf"
# Above FieldHUD (1) and BattleLayer (2), under the fade (FloorFade.LAYER).
const TITLE_LAYER := 3
# title_size_px is authored for this viewport height and scales with it.
const REFERENCE_VIEWPORT_HEIGHT := 1080.0

# Off: play() does nothing and the floor starts plain (a hard cut, as the
# first floor of a session always did).
@export var zone_intro_enabled: bool = true

@export_group("Paths")
@export var region_field_path: NodePath = ^".."
@export var camera_rig_path: NodePath = ^"../CameraPivot"
@export var tower_path: NodePath = ^"../Tower"
@export var sky_path: NodePath = ^"../WorldEnvironment"
@export var wanderer_path: NodePath = ^"../Wanderer"
@export var hud_path: NodePath = ^"../FieldHUD"
@export var sea_path: NodePath = ^"../Sea"

@export_group("Opening Pose")
# Every pose export re-applies live while the frame is held (before the
# move begins, or under debug_hold_opening) - see _apply_pose(). Metres
# above the Wanderer's spawn, and back from it along the view axis.
@export var pose_height: float = 14.0:
	set(value):
		pose_height = value
		_reapply_held_pose()
@export var pose_back_distance: float = 6.0:
	set(value):
		pose_back_distance = value
		_reapply_held_pose()
# Camera rotation.x, degrees: negative tilts down. -3 is near level with
# the sea dissolving into fog a few degrees under centre.
@export var pose_pitch_degrees: float = -3.0:
	set(value):
		pose_pitch_degrees = value
		_reapply_held_pose()
@export var pose_fov: float = 38.0:
	set(value):
		pose_fov = value
		_reapply_held_pose()
# Where the tower's base lands across the frame, 0 = left edge, 1 =
# right: the view yaw is the tower's bearing turned by however much puts
# it there at pose_fov (see _apply_pose()). 0.6 leaves the left 40 % open
# sky for the title.
@export var tower_frame_x: float = 0.6:
	set(value):
		tower_frame_x = value
		_reapply_held_pose()

@export_group("Fog")
# The far fog the shot opens under - applied to RegionSky's depth fog AND
# the Sea's own fog pair alike (see the class doc); the region's own
# values are read at play() and restored by _finish(). Both re-apply
# live while held. The sea plane is finite: from the default pose its
# inland edge enters the right of the frame at ~102 m, so an end past
# ~100 m shows the water stopping on bare sand.
@export var fog_depth_begin: float = 40.0:
	set(value):
		fog_depth_begin = value
		_reapply_held_fog()
@export var fog_depth_end: float = 100.0:
	set(value):
		fog_depth_end = value
		_reapply_held_fog()

@export_group("Timeline")
# Seconds from the first frame. The title fades in from title_in_start
# over title_in_seconds, holds, and fades out from move_start over
# title_out_seconds; the move runs move_start to move_start + move_
# seconds; _finish() comes release_delay_seconds after that. Defaults:
# fade 0.0-0.4, title in 0.3-0.9, hold to 1.6, title out 1.6-2.1, move
# 1.6-4.6, release 4.7.
@export var fade_in_seconds: float = 0.4
@export var title_in_start: float = 0.3
@export var title_in_seconds: float = 0.6
@export var move_start: float = 1.6
@export var title_out_seconds: float = 0.5
@export var move_seconds: float = 3.0
@export var release_delay_seconds: float = 0.1
# A press before this many seconds is ignored (the fade is still up).
@export var skip_lockout_seconds: float = 0.4
# A skip blends everything still in flight to the end state over this.
@export var skip_blend_seconds: float = 0.3

@export_group("Title")
# The region's display_name as authored (never re-cased here), in
# Spectral Light and the UI's ink, straight on the sky - no box, no
# scrim, no shadow. Size is pixels at a 1080-high viewport, scaled with
# the viewport height. The anchor is the label's centre as a fraction of
# the viewport: left side, upper third, opposite the tower - it must not
# cross the tower's column (checked once at play(), with a warning).
@export var title_font: Font = load(TITLE_FONT_PATH):
	set(value):
		title_font = value
		_reapply_title()
@export var title_color: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		title_color = value
		_reapply_title()
@export var title_size_px: float = 56.0:
	set(value):
		title_size_px = value
		_reapply_title()
@export var title_anchor: Vector2 = Vector2(0.25, 0.3):
	set(value):
		title_anchor = value
		_reapply_title()

@export_group("Title Hold")
# The fog the title screen holds under, both pairs alike: closed to a
# couple of metres, so every pixel but the fog-exempt tower is fog
# colour. Re-apply live while held.
@export var title_fog_begin: float = 0.5:
	set(value):
		title_fog_begin = value
		_reapply_held_fog()
@export var title_fog_end: float = 2.0:
	set(value):
		title_fog_end = value
		_reapply_held_fog()
# After Start, the fog opens from the title values to the intro's over
# this, from the timeline's t = 0 - in place of the fade a play() lifts.
@export var title_fog_open_seconds: float = 0.8
# The menu shown while the title is held (a TitleMenu CanvasLayer).
@export var title_menu_scene_path: String = "res://ui/title_menu.tscn"

@export_group("Debug")
# On: freeze and hold the opening frame - pose, intro fog, title fully
# shown, no fade - and keep it; the pose/fog/title exports update it
# live. Off again: _finish(), the field returns to play. A no-op unless
# this is a live field that isn't frozen by something else (a battle).
@export var debug_hold_opening: bool = false:
	set(value):
		var was: bool = debug_hold_opening
		debug_hold_opening = value
		if not _ready_done or value == was:
			return
		if value:
			if _can_start():
				_start(Phase.DEBUG_HOLD)
			else:
				debug_hold_opening = false
		elif _phase == Phase.DEBUG_HOLD:
			_finish()
# Set true: the whole intro again from t = 0 (a running one is finished
# first); resets itself to false.
@export var debug_replay: bool = false:
	set(value):
		debug_replay = false
		if value and _ready_done and _can_start():
			_start(Phase.PLAYING)
# On: back into the title screen's held frame from a running floor -
# the menu included, so Start plays the intro from it as at boot - to
# compose the type against the tower. Off again: _finish(). Same no-op
# rule as debug_hold_opening.
@export var debug_title_hold: bool = false:
	set(value):
		var was: bool = debug_title_hold
		debug_title_hold = value
		if not _ready_done or value == was:
			return
		if value:
			if _can_start():
				_start(Phase.TITLE_HOLD)
			else:
				debug_title_hold = false
		elif _phase == Phase.TITLE_HOLD:
			_finish()

enum Phase { IDLE, PLAYING, SKIPPING, DEBUG_HOLD, TITLE_HOLD }
var _phase: Phase = Phase.IDLE
var _ready_done: bool = false
# Seconds since the first frame of the current play.
var _clock: float = 0.0
# The region's own fog - RegionSky's pair and the Sea's - read at
# _start() and put back by _finish(): the intro only borrows them.
var _floor_fog_begin: float = 0.0
var _floor_fog_end: float = 0.0
var _floor_sea_fog_near: float = 0.0
var _floor_sea_fog_far: float = 0.0
# The skip's own blend: from wherever the move, fog and title were when
# the press landed, to the end state, over skip_blend_seconds.
var _skip_clock: float = 0.0
var _skip_from_blend: float = 0.0
var _skip_from_fog_begin: float = 0.0
var _skip_from_fog_end: float = 0.0
var _skip_from_sea_fog_near: float = 0.0
var _skip_from_sea_fog_far: float = 0.0
var _skip_from_title_alpha: float = 0.0

var _fade: FloorFade = null
var _title_layer: CanvasLayer = null
var _title: Label = null
# The title screen's menu while held, and whether Start has been taken
# and its fade is running.
var _menu: TitleMenu = null
var _title_starting: bool = false
# A play begun from the title: the fog opens from the title values over
# title_fog_open_seconds instead of a FloorFade lifting.
var _fog_from_title: bool = false

func _ready() -> void:
	# Belt and braces with the scene's own override: this node runs the
	# freeze it puts on its parent.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ready_done = true

# RegionField's entry point, from its _ready() on a run's first floor.
# False (and nothing happens) when the intro is off or the scene lacks
# what it needs; the floor then starts plain.
func play() -> bool:
	if not zone_intro_enabled or not _can_start():
		return false
	_start(Phase.PLAYING)
	return true

# RegionField's other entry point, when the boot scene raised RunState.
# title_pending: the title screen, held over this frame zero. Shown even
# with zone_intro_enabled off - Start then goes straight to the field.
func hold_title() -> bool:
	if not _can_start():
		return false
	_start(Phase.TITLE_HOLD)
	return true

# Start, from the menu: the menu locks and fades on its own start delay,
# then the ordinary timeline runs from t = 0 with the fog opening from
# the title values (see _apply_fog_at()) - or, with the intro off, the
# field simply begins. The press that started it was consumed by the
# menu; the skip lockout counts from this t = 0, so it can't skip.
func start_from_title() -> void:
	if _phase != Phase.TITLE_HOLD or _title_starting or _menu == null:
		return
	_title_starting = true
	_menu.lock()
	await _menu.fade_out()
	# A debug toggle or a finish could have landed during the fade.
	if _phase != Phase.TITLE_HOLD or not _title_starting:
		return
	_title_starting = false
	_free_menu()
	if not zone_intro_enabled:
		_finish()
		debug_title_hold = false
		return
	_phase = Phase.PLAYING
	_clock = 0.0
	_fog_from_title = true
	_set_title_alpha(0.0)
	# Cleared only now that the phase has moved on: its setter finishes a
	# hold that is still TITLE_HOLD.
	debug_title_hold = false

func _on_menu_exit_requested() -> void:
	get_tree().quit()

func is_playing() -> bool:
	return _phase != Phase.IDLE

# Every node the shot needs, and a field that isn't already frozen by
# something else (a battle, a reward screen, the floor transition) - the
# intro's own freeze is fine to restart over.
func _can_start() -> bool:
	if not is_inside_tree():
		return false
	var region_field := _region_field()
	if region_field == null or _camera_rig() == null or _tower() == null or _sky() == null or _wanderer() == null:
		return false
	return _phase != Phase.IDLE or region_field.process_mode == Node.PROCESS_MODE_INHERIT

# The first frame of a play or a debug hold: freeze, borrow the fog, put
# the camera in the opening pose, spawn the title (alpha 0 for a play,
# full for a hold) and the fade (a play only - a hold shows the frame
# outright). A play already running is finished first, so the fog read
# below is the region's own, not the intro's.
func _start(phase: Phase) -> void:
	if _phase != Phase.IDLE:
		_finish()
	_phase = phase
	_clock = 0.0

	var sky := _sky()
	_floor_fog_begin = sky.fog_depth_begin
	_floor_fog_end = sky.fog_depth_end
	var sea := _sea()
	if sea != null:
		_floor_sea_fog_near = sea.fog_near_distance
		_floor_sea_fog_far = sea.fog_far_distance

	_freeze()
	_apply_pose()
	_apply_held_fog()
	_spawn_title()
	if _title != null:
		_title.modulate.a = 1.0 if phase == Phase.DEBUG_HOLD else 0.0

	if phase == Phase.TITLE_HOLD:
		_spawn_menu()
	if phase == Phase.PLAYING:
		_fade = FloorFade.new()
		_fade.name = "IntroFade"
		add_child(_fade)
		_fade.set_opaque(sky.fog_color)
		_fade.fade_in(fade_in_seconds)

func _process(delta: float) -> void:
	match _phase:
		Phase.PLAYING:
			_clock += delta
			_set_title_alpha(_title_alpha_at(_clock))
			var move_end: float = move_start + move_seconds
			_apply_move(smoothstep(0.0, 1.0, _progress(_clock, move_start, move_seconds)))
			_apply_fog_at(_clock)
			if _clock >= move_end + release_delay_seconds:
				_finish()
		Phase.SKIPPING:
			_skip_clock += delta
			var s: float = smoothstep(0.0, 1.0, _progress(_skip_clock, 0.0, skip_blend_seconds))
			var camera_rig := _camera_rig()
			if camera_rig != null:
				camera_rig.set_free_blend(lerpf(_skip_from_blend, 0.0, s))
			_set_fog(lerpf(_skip_from_fog_begin, _floor_fog_begin, s), lerpf(_skip_from_fog_end, _floor_fog_end, s),
				lerpf(_skip_from_sea_fog_near, _floor_sea_fog_near, s), lerpf(_skip_from_sea_fog_far, _floor_sea_fog_far, s))
			_set_title_alpha(lerpf(_skip_from_title_alpha, 0.0, s))
			if _skip_clock >= skip_blend_seconds:
				_finish()
		_:
			pass

# 0 before `start`, 1 at start + seconds, linear between (a zero-length
# span is simply 1 once reached).
func _progress(t: float, start: float, seconds: float) -> float:
	if seconds <= 0.0:
		return 1.0 if t >= start else 0.0
	return clampf((t - start) / seconds, 0.0, 1.0)

# The move at smoothstep progress `s`: the camera's free-pose weight
# falls 1 -> 0 (CameraRig applies it over the live follow pose). At 1
# the rig clears the free pose itself. The fog goes with it - see
# _apply_fog_at(), on the same curve.
func _apply_move(s: float) -> void:
	var camera_rig := _camera_rig()
	if camera_rig != null:
		camera_rig.set_free_blend(1.0 - s)

# The fog at timeline time `t`: from the title, the first title_fog_open_
# seconds open it from the title values to the intro's (smoothstep);
# then, and always, the move runs it from the intro's to the region's on
# the move's own curve. Should the opening still be running at move_
# start, the move's segment simply takes over.
func _apply_fog_at(t: float) -> void:
	if _fog_from_title and t < title_fog_open_seconds and t < move_start:
		var s: float = smoothstep(0.0, 1.0, _progress(t, 0.0, title_fog_open_seconds))
		_set_fog(lerpf(title_fog_begin, fog_depth_begin, s), lerpf(title_fog_end, fog_depth_end, s),
			lerpf(title_fog_begin, fog_depth_begin, s), lerpf(title_fog_end, fog_depth_end, s))
		return
	_apply_fog(smoothstep(0.0, 1.0, _progress(t, move_start, move_seconds)))

# The fog a held frame shows: the title's under TITLE_HOLD, else the
# intro's own - what _start() sets and a fog export's setter re-applies.
func _apply_held_fog() -> void:
	if _phase == Phase.TITLE_HOLD:
		_set_fog(title_fog_begin, title_fog_end, title_fog_begin, title_fog_end)
	else:
		_apply_fog(0.0)

# The skip: everything still in flight - move, fog, title - captured
# where it stands and run to the end state over skip_blend_seconds, then
# the same _finish() the timeline reaches.
func _skip() -> void:
	_skip_clock = 0.0
	var camera_rig := _camera_rig()
	_skip_from_blend = 1.0 - smoothstep(0.0, 1.0, _progress(_clock, move_start, move_seconds))
	if camera_rig != null and not camera_rig.has_free_pose():
		_skip_from_blend = 0.0
	var sky := _sky()
	_skip_from_fog_begin = sky.fog_depth_begin if sky != null else _floor_fog_begin
	_skip_from_fog_end = sky.fog_depth_end if sky != null else _floor_fog_end
	var sea := _sea()
	_skip_from_sea_fog_near = sea.fog_near_distance if sea != null else _floor_sea_fog_near
	_skip_from_sea_fog_far = sea.fog_far_distance if sea != null else _floor_sea_fog_far
	_skip_from_title_alpha = _title.modulate.a if _title != null else 0.0
	_phase = Phase.SKIPPING

# The one end, for the timeline, the skip and both debug toggles: the
# end state in full, whatever was or wasn't still in flight.
func _finish() -> void:
	if _phase == Phase.IDLE:
		return
	_phase = Phase.IDLE

	var camera_rig := _camera_rig()
	if camera_rig != null:
		camera_rig.clear_free_pose()
	_set_fog(_floor_fog_begin, _floor_fog_end, _floor_sea_fog_near, _floor_sea_fog_far)
	if _fade != null:
		_fade.clear()
		_fade.queue_free()
		_fade = null
	if _title_layer != null:
		_title_layer.queue_free()
		_title_layer = null
		_title = null
	_free_menu()
	_title_starting = false
	_fog_from_title = false
	_release()
	finished.emit()

# Any key, mouse button or joypad button PRESS (no motion, no echo, no
# release) once the fade has lifted; consumed, so the click that skips
# never reaches click-to-move.
func _input(event: InputEvent) -> void:
	if _phase != Phase.PLAYING or _clock < skip_lockout_seconds:
		return
	if not _is_skip_press(event):
		return
	_skip()
	get_viewport().set_input_as_handled()

func _is_skip_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.is_pressed() and not event.is_echo()
	if event is InputEventMouseButton or event is InputEventJoypadButton:
		return event.is_pressed()
	return false

# --- the freeze ---------------------------------------------------------

# The battle freeze (RegionField.process_mode DISABLED) with the HUD
# hidden, and the Wanderer alone kept running ALWAYS with input locked -
# see the class doc. Idempotent.
func _freeze() -> void:
	var region_field := _region_field()
	if region_field != null:
		region_field.process_mode = Node.PROCESS_MODE_DISABLED
	var hud := _hud()
	if hud != null:
		hud.visible = false
	var wanderer := _wanderer()
	if wanderer != null:
		wanderer.input_locked = true
		wanderer.process_mode = Node.PROCESS_MODE_ALWAYS

func _release() -> void:
	var wanderer := _wanderer()
	if wanderer != null:
		wanderer.process_mode = Node.PROCESS_MODE_INHERIT
		wanderer.input_locked = false
	var hud := _hud()
	if hud != null:
		hud.visible = true
	var region_field := _region_field()
	if region_field != null:
		region_field.process_mode = Node.PROCESS_MODE_INHERIT

# --- the pose -----------------------------------------------------------

# True while the opening frame is the whole picture - before the move
# begins, or under a debug hold - which is when a pose/fog/title export
# edit should show at once.
func _is_holding() -> bool:
	if _phase == Phase.DEBUG_HOLD or _phase == Phase.TITLE_HOLD:
		return true
	return _phase == Phase.PLAYING and _clock < move_start

func _reapply_held_pose() -> void:
	if _ready_done and _is_holding():
		_apply_pose()

func _reapply_held_fog() -> void:
	if _ready_done and _is_holding():
		_apply_held_fog()

func _reapply_title() -> void:
	if _ready_done and _phase != Phase.IDLE:
		_layout_title()

# The free pose, from the field's own geometry: the view axis is the
# tower's bearing from spawn (never an assumed axis) turned so the base
# lands at tower_frame_x - the yaw that puts a direction at a fraction f
# of the frame width is atan((f - 0.5) * 2 * tan(hfov / 2)), and turning
# the view LEFT of the tower (a positive yaw about UP) puts the tower
# RIGHT of centre. The camera stands pose_back_distance behind spawn
# along that axis and pose_height above it, pitched pose_pitch_degrees,
# zero roll; CameraRig.set_free_pose() takes it from there.
func _apply_pose() -> void:
	var region_field := _region_field()
	var camera_rig := _camera_rig()
	var tower := _tower()
	if region_field == null or camera_rig == null or tower == null:
		return
	var spawn: Vector3 = region_field.get_spawn_position()
	var tower_base: Vector3 = tower.get_base_position()
	var to_tower := Vector3(tower_base.x - spawn.x, 0.0, tower_base.z - spawn.z)
	to_tower = to_tower.normalized() if to_tower.length() > 0.0001 else region_field.get_forward()

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
	var tan_half_horizontal: float = tan(deg_to_rad(pose_fov) * 0.5) * aspect
	var yaw_offset: float = atan((tower_frame_x - 0.5) * 2.0 * tan_half_horizontal)
	var view_dir: Vector3 = to_tower.rotated(Vector3.UP, yaw_offset)

	var camera_position: Vector3 = spawn - view_dir * pose_back_distance + Vector3.UP * pose_height
	var yaw: float = atan2(-view_dir.x, -view_dir.z)
	var pitch: float = deg_to_rad(pose_pitch_degrees)
	camera_rig.set_free_pose(camera_position, yaw, pitch, pose_fov)

# The fog at move progress `s`: 0 = the intro's own, 1 = the region's -
# the sky's pair and the sea's pair on the same lerp, the sea's from the
# intro's same begin/end to its own authored values.
func _apply_fog(s: float) -> void:
	_set_fog(lerpf(fog_depth_begin, _floor_fog_begin, s), lerpf(fog_depth_end, _floor_fog_end, s),
		lerpf(fog_depth_begin, _floor_sea_fog_near, s), lerpf(fog_depth_end, _floor_sea_fog_far, s))

# Both fog pairs at once - RegionSky's depth begin/end and the Sea's own
# near/far (each export's setter pushes it live).
func _set_fog(sky_begin: float, sky_end: float, sea_near: float, sea_far: float) -> void:
	var sky := _sky()
	if sky != null:
		sky.fog_depth_begin = sky_begin
		sky.fog_depth_end = sky_end
	var sea := _sea()
	if sea != null:
		sea.fog_near_distance = sea_near
		sea.fog_far_distance = sea_far

# --- the menu -----------------------------------------------------------

# The title screen's menu (TitleMenu), a child so it runs ALWAYS with
# this node through the freeze; Start and Exit come back as signals.
func _spawn_menu() -> void:
	_free_menu()
	var scene := load(title_menu_scene_path) as PackedScene
	if scene == null:
		push_warning("ZoneIntro: could not load %s; the title has no menu." % title_menu_scene_path)
		return
	_menu = scene.instantiate() as TitleMenu
	if _menu == null:
		push_warning("ZoneIntro: %s is not a TitleMenu; the title has no menu." % title_menu_scene_path)
		return
	_menu.start_requested.connect(start_from_title)
	_menu.exit_requested.connect(_on_menu_exit_requested)
	add_child(_menu)

func _free_menu() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null

# --- the title ----------------------------------------------------------

# Nothing unless the region names itself (RegionData.display_name). A
# Label on its own CanvasLayer under this node, laid out by
# _layout_title(); alpha is driven from _process().
func _spawn_title() -> void:
	var region_field := _region_field()
	if region_field == null or region_field.region == null or region_field.region.display_name.is_empty():
		return
	_title_layer = CanvasLayer.new()
	_title_layer.name = "IntroTitle"
	_title_layer.layer = TITLE_LAYER
	add_child(_title_layer)

	_title = Label.new()
	_title.name = "Title"
	_title.text = region_field.region.display_name
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_layer.add_child(_title)
	_layout_title()
	_warn_if_title_crosses_tower()

# Font, colour, size (scaled from 1080p by the viewport height) and the
# centre anchor, re-done whenever a title export changes.
func _layout_title() -> void:
	if _title == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var scale: float = viewport_size.y / REFERENCE_VIEWPORT_HEIGHT
	if title_font != null:
		_title.add_theme_font_override("font", title_font)
	_title.add_theme_color_override("font_color", title_color)
	_title.add_theme_font_size_override("font_size", maxi(int(round(title_size_px * scale)), 1))
	var label_size: Vector2 = _title.get_combined_minimum_size()
	_title.size = label_size
	_title.position = viewport_size * title_anchor - label_size * 0.5

# The tower's column, projected from the held pose, must not fall inside
# the title's rect - a loud check rather than a silent clamp, since the
# anchor is authored by eye.
func _warn_if_title_crosses_tower() -> void:
	var camera_rig := _camera_rig()
	var tower := _tower()
	if _title == null or camera_rig == null or tower == null or camera_rig.camera == null:
		return
	var tower_x: float = camera_rig.camera.unproject_position(tower.get_base_position()).x
	if tower_x >= _title.position.x and tower_x <= _title.position.x + _title.size.x:
		push_warning("ZoneIntro: the title (anchor %s) crosses the tower's column at x %.0f; move title_anchor or tower_frame_x." % [str(title_anchor), tower_x])

func _set_title_alpha(alpha: float) -> void:
	if _title != null:
		_title.modulate.a = clampf(alpha, 0.0, 1.0)

# In from title_in_start over title_in_seconds, out from move_start over
# title_out_seconds; whichever ramp is lower wins, so a title that hasn't
# finished arriving when the move begins simply turns round.
func _title_alpha_at(t: float) -> float:
	var alpha_in: float = _progress(t, title_in_start, title_in_seconds)
	var alpha_out: float = 1.0 - _progress(t, move_start, title_out_seconds)
	return minf(alpha_in, alpha_out)

# --- lookups ------------------------------------------------------------

func _region_field() -> RegionField:
	return get_node_or_null(region_field_path) as RegionField

func _camera_rig() -> CameraRig:
	return get_node_or_null(camera_rig_path) as CameraRig

func _tower() -> Tower:
	return get_node_or_null(tower_path) as Tower

func _sky() -> RegionSky:
	return get_node_or_null(sky_path) as RegionSky

func _wanderer() -> Wanderer:
	return get_node_or_null(wanderer_path) as Wanderer

func _hud() -> CanvasLayer:
	return get_node_or_null(hud_path) as CanvasLayer

func _sea() -> Sea:
	return get_node_or_null(sea_path) as Sea
