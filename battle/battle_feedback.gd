extends Node
class_name BattleFeedback

# Reacts to BattleController.damage_dealt only - by the time that signal
# fires, BattleController has already awaited the card's own impact_time
# (or the enemy's own attack-snap) before resolving/reporting the hit
# (see _resolve_play()/_run_enemy_turn()'s own doc), so everything below
# already lands in sync with the swing without needing any timing/replay
# logic of its own here - this owns the tunables and the "which effects
# for which side" branching only.
#
# The one exception is a card with a play effect (CardData.play_effect_
# scene_path - Blood Arc's ink stroke): on_card_impact() lays it over the
# fight, and each enemy's reaction to that card's hit waits until the
# stroke reaches it (reaction_delay(), the effect's arrival_delay()) - on
# scaled time, so a hit-stop holds stroke and reactions alike. The hits
# themselves, HP and kills, still land at the impact; only how they look
# is paced. Such a card's hits draw no slash mark: the stroke is its mark.

const BATTLE_THEME_PATH := "res://ui/battle_theme.tres"

@export_group("Impact Flash")
@export var flash_color: Color = Color(0.95, 0.94, 0.9, 1.0)
@export var flash_rise_time: float = 0.06
@export var flash_fall_time: float = 0.12

@export_group("Recoil")
@export var recoil_distance: float = 0.25
@export var recoil_tilt_degrees: float = 8.0
@export var recoil_out_time: float = 0.08
@export var recoil_return_time: float = 0.25

@export_group("Slash Mark")
@export var slash_mark_length: float = 1.2
@export var slash_mark_width: float = 0.12
@export var slash_mark_chest_height: float = 1.3
@export var slash_mark_grow_time: float = 0.05
@export var slash_mark_fade_time: float = 0.2

@export_group("Sand Puff")
@export_range(10, 16) var sand_puff_particle_count: int = 12
@export var sand_puff_lifetime: float = 0.6
@export var sand_puff_velocity: float = 1.0
@export var sand_puff_spread_degrees: float = 45.0

@export_group("Hit-stop")
@export var hit_stop_threshold: int = 10
@export var hit_stop_time_scale: float = 0.05
@export var hit_stop_duration_sec: float = 0.06

@export_group("Camera Shake")
@export var camera_shake_max_offset: float = 0.05
@export var camera_shake_reference_damage: float = 15.0

var _wanderer: Wanderer = null
var _on_dark_world: bool = false
# The play effect of the card resolving right now - set at its impact and
# cleared at the end of that frame, so only that card's own hits (which
# all report in the same frame) are paced by it.
var _effect: Node3D = null

func setup(wanderer: Wanderer, on_dark_world: bool) -> void:
	_wanderer = wanderer
	_on_dark_world = on_dark_world

# source/target mirror BattleController.damage_dealt's own doc exactly:
# each is either the String "player" or a FieldEnemy - which one is the
# FieldEnemy says which side got hit. Slash mark and hit-stop are card-hit
# only (2, 3, 5, 7 mirror onto the Wanderer for an enemy attack; 4 and 6
# don't) - camera shake alone applies to both, so it's the one call left
# outside the branch below.
func on_damage_dealt(source: Variant, target: Variant, amount: int, _kind: String) -> void:
	if amount <= 0:
		return

	if target is FieldEnemy:
		# Read now, in the hit's own frame - the effect lets go at its end.
		var slash: bool = not _effect_active()
		var delay: float = reaction_delay(target)
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
			if not is_instance_valid(target):
				return
		_react_to_card_hit(target as FieldEnemy, slash)
		if amount >= hit_stop_threshold:
			_apply_hit_stop()
	elif source is FieldEnemy:
		_react_to_enemy_attack(source as FieldEnemy)

	_shake_camera(amount)

# A card has landed (BattleController.card_impact, before its effects
# resolve): its play effect, if it names one, is laid over `targets` from
# the Wanderer, and paces this frame's hit reactions.
func on_card_impact(card: CardData, targets: Array[FieldEnemy]) -> void:
	if card == null or card.play_effect_scene_path.is_empty() or _wanderer == null:
		return
	var scene := load(card.play_effect_scene_path) as PackedScene
	if scene == null:
		push_warning("BattleFeedback: could not load %s; no play effect." % card.play_effect_scene_path)
		return
	var effect := scene.instantiate() as Node3D
	if effect == null:
		return
	# Under this node, not the field's: RegionField is frozen through a
	# fight, and the stroke's tweens have to run. It goes with the fight.
	add_child(effect)
	var struck: Array[Node3D] = []
	for enemy in targets:
		if is_instance_valid(enemy):
			struck.append(enemy)
	effect.call("setup", _wanderer, struck)
	_effect = effect
	_release_effect.call_deferred()

# Seconds after the impact `target`'s reaction to this frame's hit waits:
# the play effect's arrival at it, 0 with none.
func reaction_delay(target: Variant) -> float:
	if not _effect_active() or not (target is FieldEnemy):
		return 0.0
	return float(_effect.call("arrival_delay", target))

func _effect_active() -> bool:
	return _effect != null and is_instance_valid(_effect)

func _release_effect() -> void:
	_effect = null

func _react_to_card_hit(enemy: FieldEnemy, slash: bool = true) -> void:
	if _wanderer == null:
		return
	var attack_direction: Vector3 = enemy.global_position - _wanderer.global_position
	enemy.play_contact_sound()
	enemy.play_hit_flash(flash_color, flash_rise_time, flash_fall_time)
	enemy.play_hit_recoil(attack_direction, recoil_distance, recoil_tilt_degrees, recoil_out_time, recoil_return_time)
	enemy.spawn_sand_puff(sand_puff_particle_count, sand_puff_lifetime, sand_puff_velocity, sand_puff_spread_degrees)
	if slash:
		enemy.spawn_slash_mark(attack_direction, _slash_mark_color(), slash_mark_length, slash_mark_width, slash_mark_chest_height, slash_mark_grow_time, slash_mark_fade_time)

func _react_to_enemy_attack(enemy: FieldEnemy) -> void:
	if _wanderer == null:
		return
	var attack_direction: Vector3 = _wanderer.global_position - enemy.global_position
	_wanderer.play_hit_audio()
	_wanderer.play_hit_flash(flash_color, flash_rise_time, flash_fall_time)
	_wanderer.play_hit_recoil(attack_direction, recoil_distance, recoil_tilt_degrees, recoil_out_time, recoil_return_time)
	_wanderer.spawn_sand_puff(sand_puff_particle_count, sand_puff_lifetime, sand_puff_velocity, sand_puff_spread_degrees)

# "The theme's light tone" - CardFace's own panel_light_color token
# (BattleTheme.on_pale_panel_light_color/on_dark_panel_light_color), read
# straight off the resource rather than through a Control's get_theme_
# color() the way FloatingNumber does, since this has no Control of its
# own to read it through. Loaded at runtime (never a hardcoded default
# res:// reference kept around) per this project's own load() convention.
func _slash_mark_color() -> Color:
	var theme := load(BATTLE_THEME_PATH) as BattleTheme
	if theme == null:
		return flash_color
	return theme.on_dark_panel_light_color if _on_dark_world else theme.on_pale_panel_light_color

# ignore_time_scale=true on this one timer only: it's what restores
# Engine.time_scale, so it has to keep running at real speed regardless
# of the very time_scale it just set - every other tween/timer this pass
# adds deliberately keeps respecting time_scale so it visibly freezes
# during the stutter, which is the whole point of a hit-stop.
func _apply_hit_stop() -> void:
	Engine.time_scale = hit_stop_time_scale
	get_tree().create_timer(hit_stop_duration_sec, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0
	)

# CameraRig isn't threaded through as a reference anywhere in this chain -
# found via the active camera's own parent instead, the same "reach the
# live camera through the viewport" idiom BattleController._screen_pos_
# for()/_raycast_enemy() and BattleOverlay._screen_pos_for_damage_target()
# already use.
func _shake_camera(amount: int) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var camera_rig := camera.get_parent() as CameraRig
	if camera_rig == null:
		return
	var magnitude: float = camera_shake_max_offset * clampf(float(amount) / camera_shake_reference_damage, 0.0, 1.0)
	camera_rig.micro_shake(magnitude)
