extends Node
class_name AttackAudio

# Plays the Wanderer's own sword-impact sound at whatever moment
# BattleController decides a card's swing has landed (see BattleController.
# card_impact and Wanderer._on_card_impact()) - one shared
# AudioStreamPlayer3D, same "single player retriggered on demand" shape
# FootstepAudio already uses for footfalls. Built purely in code -
# instantiated via AttackAudio.new() and added as a child of the Wanderer
# via setup(), not part of any .tscn.

const SLASH_CLIP_PATH := "res://assets/audio/Wanderer/Combat/Slash.mp3"

@export var base_volume_db: float = -4.4
@export var volume_variance_db: float = 2.0
@export var base_pitch: float = 1.0
@export var pitch_variance: float = 0.05

var _player: AudioStreamPlayer3D
var _slash_clip: AudioStream

func setup() -> void:
	# RegionField freezes the whole Wanderer subtree (PROCESS_MODE_DISABLED)
	# on battle contact - exactly when play_slash() actually needs to fire -
	# so this (and, by inheritance, _player below) needs the same ALWAYS
	# override every other in-battle node here already carries (the model,
	# its AnimationPlayer, ContactShadow).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_slash_clip = load(SLASH_CLIP_PATH) as AudioStream
	if _slash_clip == null:
		push_warning("AttackAudio: slash clip failed to load (%s); attack audio disabled." % SLASH_CLIP_PATH)

	_player = AudioStreamPlayer3D.new()
	add_child(_player)

func play_slash() -> void:
	if _slash_clip == null or _player == null:
		return
	_player.stream = _slash_clip
	_player.pitch_scale = base_pitch + randf_range(-pitch_variance, pitch_variance)
	_player.volume_db = base_volume_db + randf_range(-volume_variance_db, volume_variance_db)
	_player.play()
