extends Node
class_name BattleAudio

# Plays a short impact clip for every BattleController.damage_dealt -
# self_damage takes priority for kind == "self" (self-damage always
# reports target == "player" too, per battle_controller.gd's own
# _report_damage(), but reads as a different sound than an enemy's
# attack landing), otherwise enemy_hit when the target is a FieldEnemy
# and player_hit when it's the literal string "player" (battle_
# controller.gd's own convention for "the player got hit", not a
# Combatant reference). Card play/draw/shuffle are explicitly out of
# scope - this only ever listens for damage.
#
# Created by BattleOverlay.enter_battle() via setup() and freed on
# battle_finished - not part of any .tscn.

# NOTE: these three are a best guess picked by filename alone from
# reference/old_project/deck-builder/assets/audio/combat/ (hit.wav,
# hp_loss_breath.mp3, wanderer_selfeater.mp3, copied unrenamed into
# assets/audio/battle/) - I can't listen to audio to confirm they're the
# right fit. Reassign any of the three in the inspector if they're wrong.
@export var enemy_hit_clip: AudioStream = load("res://assets/audio/battle/hit.wav")
@export var player_hit_clip: AudioStream = load("res://assets/audio/battle/hp_loss_breath.mp3")
@export var self_damage_clip: AudioStream = load("res://assets/audio/battle/wanderer_selfeater.mp3")

@export var base_volume_db: float = 0.0
@export var pitch_variance: float = 0.05

var _player: AudioStreamPlayer

func setup(battle_controller: BattleController) -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	battle_controller.damage_dealt.connect(_on_damage_dealt)

func _on_damage_dealt(_source: Variant, target: Variant, _amount: int, kind: String) -> void:
	var clip: AudioStream = null
	if kind == "self":
		clip = self_damage_clip
	elif target is FieldEnemy:
		clip = enemy_hit_clip
	elif target is String and target == "player":
		clip = player_hit_clip

	if clip == null:
		return # no clip assigned for this case - play nothing, per spec

	_player.stream = clip
	_player.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	_player.volume_db = base_volume_db
	_player.play()
