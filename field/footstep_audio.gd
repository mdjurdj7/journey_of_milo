extends Node
class_name FootstepAudio

# Plays a footstep clip on every FootprintSpawner.footfall - a random
# clip from the wet or dry pool (chosen by Ground.get_wetness_at() at the
# foot's own position, independent of FootprintSpawner's own dry/wet/
# water tiers, which only govern the visual mark), on one shared
# AudioStreamPlayer3D repositioned to the foot each time rather than a
# separate player per foot - footfalls don't overlap in time closely
# enough for that to matter, and it matches "one AudioStreamPlayer3D"
# exactly as asked.
#
# Built purely in code - instantiated via FootstepAudio.new() and added
# as a child of the Wanderer via setup(), not part of any .tscn.

# NOTE: the actual footstep clips currently live under
# assets/audio/Wanderer/Movement/ (only step_wet_01..04.mp3 exist so
# far, no step_dry_* yet), not assets/audio/footsteps/ as specced -
# pointed the loader at the real directory rather than one that doesn't
# exist. If assets/audio/footsteps/ is meant to be the actual future
# home for these, move the files and update FOOTSTEPS_DIR to match.
const FOOTSTEPS_DIR := "res://assets/audio/Wanderer/Movement/"
const DRY_PREFIX := "step_dry_"
const WET_PREFIX := "step_wet_"

@export var wet_threshold: float = 0.5
# Tuned by ear against actual footfall volume in play (was -8.0).
@export var base_volume_db: float = -5.0
@export var volume_variance_db: float = 2.0
# pitch_scale resamples the clip, so it sets played-back SPEED as well as
# pitch - lower than 1.0 slows playback down as well as deepening the
# pitch, which is what makes a quick/sharp foley clip read as a heavier,
# slower sand contact instead. Tuned by ear (was 0.85). pitch_variance
# still applies on top of this, not of 1.0.
@export var base_pitch: float = 0.82
@export var pitch_variance: float = 0.06

var _ground: Ground
var _footprint_spawner: FootprintSpawner
var _player: AudioStreamPlayer3D
var _dry_clips: Array[AudioStream] = []
var _wet_clips: Array[AudioStream] = []
var _last_clip: AudioStream = null

func setup(footprint_spawner: FootprintSpawner, ground: Ground) -> void:
	_footprint_spawner = footprint_spawner
	_ground = ground

	_load_clips()

	_player = AudioStreamPlayer3D.new()
	add_child(_player)

	if _footprint_spawner:
		_footprint_spawner.footfall.connect(_on_footfall)
	else:
		push_warning("FootstepAudio: no FootprintSpawner given; footstep audio disabled.")

# Every file directly under FOOTSTEPS_DIR, sorted into dry/wet pools by
# filename prefix. Anything not starting with either prefix is ignored,
# not an error - the directory can hold other assets alongside these.
func _load_clips() -> void:
	var dir := DirAccess.open(FOOTSTEPS_DIR)
	if dir == null:
		push_warning("FootstepAudio: could not open '%s'; no footstep clips loaded." % FOOTSTEPS_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and not file_name.ends_with(".import"):
			var stream := load(FOOTSTEPS_DIR + file_name) as AudioStream
			if stream != null:
				if file_name.begins_with(DRY_PREFIX):
					_dry_clips.append(stream)
				elif file_name.begins_with(WET_PREFIX):
					_wet_clips.append(stream)
		file_name = dir.get_next()
	dir.list_dir_end()

	if _dry_clips.is_empty() and _wet_clips.is_empty():
		push_warning("FootstepAudio: no '%s'/'%s' files found under '%s'." % [DRY_PREFIX, WET_PREFIX, FOOTSTEPS_DIR])

func _on_footfall(world_position: Vector3) -> void:
	if _ground == null or _player == null:
		return

	var local_xz: Vector3 = _ground.to_local(Vector3(world_position.x, 0.0, world_position.z))
	var wetness: float = _ground.get_wetness_at(Vector2(local_xz.x, local_xz.z))
	var want_wet: bool = wetness > wet_threshold

	var pool: Array[AudioStream] = _wet_clips if want_wet else _dry_clips
	if pool.is_empty():
		pool = _dry_clips if want_wet else _wet_clips
	if pool.is_empty():
		return

	var clip: AudioStream = _pick_clip(pool)
	if clip == null:
		return
	_last_clip = clip

	_player.global_position = world_position
	_player.stream = clip
	_player.pitch_scale = base_pitch + randf_range(-pitch_variance, pitch_variance)
	_player.volume_db = base_volume_db + randf_range(-volume_variance_db, volume_variance_db)
	_player.play()

# Never the same clip twice in a row - a single-entry pool always repeats
# by necessity (nothing else to pick), everything else re-rolls a few
# times to avoid a back-to-back repeat without risking an infinite loop.
func _pick_clip(pool: Array[AudioStream]) -> AudioStream:
	if pool.size() == 1:
		return pool[0]
	var clip: AudioStream = pool[randi() % pool.size()]
	var attempts := 0
	while clip == _last_clip and attempts < 8:
		clip = pool[randi() % pool.size()]
		attempts += 1
	return clip
