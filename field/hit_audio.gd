extends Node
class_name HitAudio

# The Wanderer being hit - an enemy's attack costing HP, sounded from the
# Wanderer himself (BattleFeedback._react_to_enemy_attack(), the same
# beat as the flash and recoil; see Wanderer.play_hit_audio()). Never
# for HP he spends himself (card costs, a stance's price, status ticks,
# wading) and never for a hit block took entirely - the report that
# reaches BattleFeedback only exists when an enemy's blow got through
# (BattleController._run_enemy_turn()). One AudioStreamPlayer3D on the
# SFX bus, retriggered on demand, takes dealt round-robin from a
# SoundPool (one take today - drop Hit_2 into hit_clips and it rotates).
# Built purely in code, the same shape as AttackAudio: instantiated via
# HitAudio.new() and added under the Wanderer via setup(), not part of
# any .tscn. Not a shared base with AttackAudio yet - two of a kind is
# not three.
#
# Levels: the takes are normalised to -6 dBFS; at the battle camera's
# ~10.6 m the 3D attenuation takes ~0.5 dB, so base_volume_db -4 peaks
# about -10.5 dBFS at the listener - the enemy contact's own tier, the
# loudest thing in an exchange, above the swing and the card play.

const BUS_NAME := &"SFX"

@export var hit_clips: Array[AudioStream] = [load("res://assets/audio/Wanderer/Combat/Hit_1.wav") as AudioStream]
@export var base_volume_db: float = -4.0
@export var volume_variance_db: float = 1.0
@export var base_pitch: float = 1.0
@export var pitch_variance: float = 0.04

var _player: AudioStreamPlayer3D
var _pool := SoundPool.new()

func setup() -> void:
	# RegionField freezes the whole Wanderer subtree (PROCESS_MODE_DISABLED)
	# on battle contact - exactly when this needs to sound - so this (and,
	# by inheritance, _player below) carries the same ALWAYS override the
	# model, its AnimationPlayer and AttackAudio already do.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_pool.set_clips(hit_clips)
	if _pool.is_empty():
		push_warning("HitAudio: no hit clips; hit audio disabled.")

	_player = AudioStreamPlayer3D.new()
	_player.bus = BUS_NAME
	add_child(_player)

func play_hit() -> void:
	var clip: AudioStream = _pool.next()
	if clip == null or _player == null:
		return
	_player.stream = clip
	_player.pitch_scale = base_pitch + randf_range(-pitch_variance, pitch_variance)
	_player.volume_db = base_volume_db + randf_range(-volume_variance_db, volume_variance_db)
	_player.play()
