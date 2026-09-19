extends Node
class_name AttackAudio

# The Wanderer's own swing - the blade's whoosh, played just ahead of a
# card's impact (BattleController.card_swing, swing_lead_seconds before
# card_impact; see Wanderer._on_card_swing()). The contact sound is the
# enemy's own (FieldEnemy.play_contact_sound()), not this. One
# AudioStreamPlayer3D on the SFX bus, retriggered on demand, same shape
# FootstepAudio uses for footfalls; takes dealt round-robin from a
# SoundPool (one take today - see swing_clips). Built purely in code -
# instantiated via AttackAudio.new() and added as a child of the Wanderer
# via setup(), not part of any .tscn.
#
# Levels: the takes are normalised to -6 dBFS; at the battle camera's
# ~10.6 m the 3D attenuation (unit_size 10, inverse distance) takes ~0.5
# dB, so base_volume_db -13.5 peaks about -20 dBFS at the listener -
# felt more than heard under the enemy's contact crack.

const BUS_NAME := &"SFX"

@export var swing_clips: Array[AudioStream] = [load("res://assets/audio/Wanderer/Combat/Swing_whoosh_1.mp3") as AudioStream]
@export var base_volume_db: float = -13.5
@export var volume_variance_db: float = 1.0
@export var base_pitch: float = 1.0
@export var pitch_variance: float = 0.05

var _player: AudioStreamPlayer3D
var _pool := SoundPool.new()

func setup() -> void:
	# RegionField freezes the whole Wanderer subtree (PROCESS_MODE_DISABLED)
	# on battle contact - exactly when play_swing() actually needs to fire -
	# so this (and, by inheritance, _player below) needs the same ALWAYS
	# override every other in-battle node here already carries (the model,
	# its AnimationPlayer, ContactShadow).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_pool.set_clips(swing_clips)
	if _pool.is_empty():
		push_warning("AttackAudio: no swing clips; swing audio disabled.")

	_player = AudioStreamPlayer3D.new()
	_player.bus = BUS_NAME
	add_child(_player)

func play_swing() -> void:
	var clip: AudioStream = _pool.next()
	if clip == null or _player == null:
		return
	_player.stream = clip
	_player.pitch_scale = base_pitch + randf_range(-pitch_variance, pitch_variance)
	_player.volume_db = base_volume_db + randf_range(-volume_variance_db, volume_variance_db)
	_player.play()
