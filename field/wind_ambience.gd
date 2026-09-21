extends Node
class_name WindAmbience

# The wind bed - the dry half of the field's ambience, against the
# Sea's own wet half (Sea._spawn_ambience()). A 2D AudioStreamPlayer on
# the Ambience bus, looping the beach wind at base_volume_db plus the
# floor's offset (FloorData.ambience_wind_db, pushed by RegionField in
# _enter_tree() before this exists, read at setup()), and otherwise
# constant: unlike the sea it doesn't fade with the Wanderer's distance
# from anything. Built purely in code - WindAmbience.new(), added under
# RegionField in its _ready() - and ALWAYS, so it plays on through the
# battle freeze the way the Sea does. Goes with the scene on a floor
# change, and the next floor's starts afresh under the fade, exactly as
# the sea bed does.
#
# The file is a 60 s loop cut from the old project's ambient_wind_beach
# (which faded in and out at its ends, so its MP3 wrap dipped to silence
# for ~100 ms): a 1 s equal-power crossfade folds the audio that followed
# the cut back over its start, so the wrap is a continuous sample. WAV,
# so the loop points are exact; set here rather than in the import, so
# a re-import can't lose them.

const BUS_NAME := &"Ambience"
const WIND_PATH := "res://assets/audio/ambient/wind_beach_loop.wav"

# A -6 dBFS bed at -26 sits under the sea's own -20 at the shore.
@export var base_volume_db: float = -26.0:
	set(value):
		base_volume_db = value
		_apply_volume()
# The floor's own shift on top of base_volume_db (FloorData.ambience_
# wind_db), set once at setup() by RegionField.
@export var floor_offset_db: float = 0.0:
	set(value):
		floor_offset_db = value
		_apply_volume()

var _player: AudioStreamPlayer = null

func setup(offset_db: float) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	floor_offset_db = offset_db
	var stream := load(WIND_PATH) as AudioStream
	if stream == null:
		push_warning("WindAmbience: %s failed to load; no wind bed." % WIND_PATH)
		return
	if stream is AudioStreamWAV:
		# The whole file, begin to end: loop_end in frames from the
		# stream's own length, not its data size - the import may have
		# compressed the data (QOA), so bytes are not frames.
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_player = AudioStreamPlayer.new()
	_player.name = "WindBed"
	_player.bus = BUS_NAME
	_player.stream = stream
	add_child(_player)
	_apply_volume()
	_player.play()

func _apply_volume() -> void:
	if _player != null:
		_player.volume_db = base_volume_db + floor_offset_db
