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
#
# The other: a card hit that meets an enemy's block (BattleController.
# enemy_hit_blocked). One the block takes whole reports no damage, so it
# reacts here - the armored contact sound, a reduced recoil and the
# blocked hit's stop, nothing else (no flash, number or shake). One that
# breaks through reacts as any hit does, with the armored sound. An enemy
# hit the player's Block or absorb takes whole (BattleController.player_
# hit_blocked) gets the same stop and that enemy's armored contact sound.
#
# The hit-stop: every contact - a card's hit, an enemy's attack, a strike
# back, the worn piece's hit back - freezes the two fighters in it, the
# attacker and the one struck, and nothing else: FieldEnemy.hold_for()
# and Wanderer.hold_animation() put their motion at speed 0 and back. The
# camera, the UI and the damage number keep running; nothing touches
# Engine.time_scale. How long (stop_ms()): normal_hitstop_ms, or
# big_hitstop_ms for a hit of big_hit_min_damage or more or a kill,
# multi_hit_hitstop_ms for each hit of an enemy's multi-hit attack (a
# kill still the big one), blocked_hitstop_ms for a hit taken whole by a
# block. The number, the contact sound and the HP bar land in the frame
# it starts. Damage with no contact - a countdown going off, a tick, a
# Drain, a self-inflicted cost - stops nothing. hitstop_enabled off: no
# stops at all. Each stop runs on a SceneTreeTimer, so under the probes'
# fixed frame rate it is the same frames every run.
#
# The heavy tier: a card hit of heavy_min_damage or more, by that one
# hit's damage, is weightier - a deep impact layered under the contact
# sound (heavy_impact_clips dealt in turn, silent at heavy_min_damage
# rising to heavy_impact_max_volume_db), and the recoil and the damage
# number grown up to their max multipliers. A card that spends Toll as
# its blow (CardEffect TOLL_DAMAGE - Reckoning) always counts as at least
# heavy_min_damage. A card hit of shake_min_damage or more also jolts the
# camera once (CameraRig.jolt()) - the only camera movement a hit makes,
# off with camera_shake_enabled. Presentation only: nothing here touches
# the rules, and heavy_hit_enabled off gives the plain reaction, no jolt
# either. Every tunable is read as the hit lands, so a Remote-tab edit
# takes effect on the next.

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
# A hit the enemy's block takes whole recoils this fraction of a full
# hit's distance and tilt.
@export_range(0.0, 1.0, 0.05) var absorbed_recoil_fraction: float = 0.5

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
# Multiplied onto the ground colour the grains take - a step darker than
# lit sand, kicked grains in shadow, so a puff reads against the sand it
# rises from. Every puff here: a hit on an enemy or on him, and the
# draw's ground strike. Read at each puff; BattleOverlay sets it from its
# own sand_puff_tint.
@export var sand_puff_tint: float = 0.75

@export_group("Hit-Stop")
@export var hitstop_enabled: bool = true
# The stops, in milliseconds of game time (see the header).
@export var normal_hitstop_ms: float = 70.0
@export var big_hitstop_ms: float = 110.0
# The least one hit's damage that takes big_hitstop_ms.
@export var big_hit_min_damage: int = 15
@export var multi_hit_hitstop_ms: float = 40.0
@export var blocked_hitstop_ms: float = 40.0

@export_group("Heavy Hit")
@export var heavy_hit_enabled: bool = true
# The tier's range, in one hit's damage: its light end and its full one.
@export var heavy_min_damage: int = 10
@export var heavy_max_damage: int = 35
# The impact layer's takes, dealt in turn (never the same one twice
# running), and its volume at heavy_max_damage.
@export var heavy_impact_clips: Array[AudioStream] = [
	load("res://assets/audio/sfx/heavy_impact_01.mp3") as AudioStream,
	load("res://assets/audio/sfx/heavy_impact_02.mp3") as AudioStream,
]:
	set(value):
		heavy_impact_clips = value
		_heavy_pool.set_clips(heavy_impact_clips)
@export var heavy_impact_max_volume_db: float = -14.0
# The recoil's distance and the damage number's size at heavy_max_damage.
@export var heavy_recoil_max_multiplier: float = 1.6
@export var heavy_number_max_multiplier: float = 1.4

@export_group("Camera Jolt")
@export var camera_shake_enabled: bool = true
# The least damage one card hit needs to jolt the camera.
@export var shake_min_damage: int = 30
# The jolt's offset, in metres, and how long it takes to settle.
@export var camera_jolt_amplitude: float = 0.05
@export var camera_jolt_duration: float = 0.15

# The impact layer's volume for "not at all".
const SILENT_DB: float = -80.0
# The damage kinds (BattleController.damage_dealt's `kind`) that are a
# contact, and stop the fighters in it.
const CONTACT_KINDS: Array[String] = ["card", "attack", "hit_back"]

var _wanderer: Wanderer = null
# The fight's controller, set by BattleOverlay: whether a hit kills
# (BattleController.is_dying()), read in its own frame.
var battle_controller: BattleController = null
var _on_dark_world: bool = false
# The play effect of the card resolving right now - set at its impact and
# cleared at the end of that frame, so only that card's own hits (which
# all report in the same frame) are paced by it.
var _effect: Node3D = null
# Enemies whose next reported hit met their block (enemy_hit_blocked,
# not absorbed) - set and read in the same call, so never stale.
var _met_block: Dictionary[FieldEnemy, bool] = {}
# The card resolving right now - set at its impact and cleared at the end
# of that frame, like _effect: whether its blow counts as heavy at least.
var _impact_card: CardData = null
var _heavy_pool := SoundPool.new()

func _init() -> void:
	_heavy_pool.set_clips(heavy_impact_clips)

func setup(wanderer: Wanderer, on_dark_world: bool) -> void:
	_wanderer = wanderer
	_on_dark_world = on_dark_world
	if _wanderer != null:
		_wanderer.draw_strike.connect(_on_draw_strike)

# source/target mirror BattleController.damage_dealt's own doc exactly:
# each is either the String "player" or a FieldEnemy - which one is the
# FieldEnemy says which side got hit. The heavy tier, the slash mark and
# the camera jolt are card-hit only; an enemy's hit on the Wanderer gets
# its sound, flash, recoil and puff. Either side's contact stops the two
# fighters in it (the header's hit-stop): the Wanderer at once, the
# enemy struck as its reaction lands - with a play effect, as the stroke
# reaches it.
func on_damage_dealt(source: Variant, target: Variant, amount: int, kind: String) -> void:
	if amount <= 0:
		return
	var contact: bool = CONTACT_KINDS.has(kind)

	if target is FieldEnemy:
		# Read now, in the hit's own frame - the effect lets go at its end.
		var slash: bool = not _effect_active()
		var armored: bool = _met_block.has(target)
		_met_block.erase(target)
		var heavy: float = heavy_level(heavy_damage(amount))
		var killing: bool = battle_controller != null and battle_controller.is_dying(target)
		var hold: float = stop_ms(amount, killing) / 1000.0 if contact else 0.0
		_hold_wanderer(hold)
		var delay: float = reaction_delay(target)
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
			if not is_instance_valid(target):
				return
		(target as FieldEnemy).hold_for(hold)
		_react_to_card_hit(target as FieldEnemy, slash, armored, heavy)
		if jolts_camera(amount):
			_jolt_camera()
	elif source is FieldEnemy:
		var attacker := source as FieldEnemy
		if contact:
			# Read in the hit's own frame: one of a multi-hit, and whether
			# this hit is the one that leaves the player at 0.
			var multi: bool = battle_controller != null and battle_controller.is_multi_hit_report()
			var killing: bool = battle_controller != null and battle_controller.shown_player_hp() <= 0
			var hold: float = stop_ms(amount, killing, multi) / 1000.0
			attacker.hold_for(hold)
			_hold_wanderer(hold)
		_react_to_enemy_attack(attacker)

# BattleController.player_hit_blocked: an enemy's hit the player's Block
# or absorb took whole - the blocked stop on both, and that enemy's
# armored contact sound; no number, flash or recoil.
func on_player_hit_blocked(enemy: FieldEnemy) -> void:
	if not is_instance_valid(enemy):
		return
	var hold: float = blocked_stop_ms() / 1000.0
	enemy.hold_for(hold)
	_hold_wanderer(hold)
	enemy.play_contact_sound(true)

# A card has landed (BattleController.card_impact, before its effects
# resolve): its play effect, if it names one, is laid over `targets` from
# the Wanderer, kept under `ceiling_y` (the lowest intent readout's world
# height), and paces this frame's hit reactions.
func on_card_impact(card: CardData, targets: Array[FieldEnemy], ceiling_y: float = INF) -> void:
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
	effect.call("setup", _wanderer, struck, ceiling_y)
	_effect = effect
	_release_effect.call_deferred()

# Every card's impact (BattleController.card_impact, before its effects
# resolve): which card this frame's hits belong to, for heavy_damage().
func set_impact_card(card: CardData) -> void:
	_impact_card = card
	_release_impact_card.call_deferred()

func _release_impact_card() -> void:
	_impact_card = null

# --- Heavy tier ---

# Whether `card`'s blow is its Toll, spent whole (CardEffect TOLL_DAMAGE -
# Reckoning): its hit counts as heavy at least, and BattleOverlay pours
# the spent Toll into it.
static func is_toll_blow(card: CardData) -> bool:
	if card == null:
		return false
	for effect in card.effects:
		if effect != null and effect.effect_type == CardEffect.EffectType.TOLL_DAMAGE:
			return true
	return false

# The damage the heavy tier reads for a hit of `amount` this frame: the
# hit's own, or at least heavy_min_damage for a Toll blow.
func heavy_damage(amount: int) -> int:
	if is_toll_blow(_impact_card):
		return maxi(amount, heavy_min_damage)
	return amount

# Where `damage` sits in the tier: -1 below it (or with the tier off), 0
# at heavy_min_damage rising to 1 at heavy_max_damage, and held there.
func heavy_level(damage: int) -> float:
	if not heavy_hit_enabled or damage < heavy_min_damage:
		return -1.0
	if heavy_max_damage <= heavy_min_damage:
		return 1.0
	return clampf(float(damage - heavy_min_damage) / float(heavy_max_damage - heavy_min_damage), 0.0, 1.0)

# A contact's stop, in milliseconds of game time, for a hit of `amount`:
# big for a kill or big_hit_min_damage and up, the multi-hit stop for one
# hit of several (a kill excepted), normal otherwise; 0 with the stop off.
func stop_ms(amount: int, killing: bool = false, multi: bool = false) -> float:
	if not hitstop_enabled:
		return 0.0
	if killing:
		return maxf(big_hitstop_ms, 0.0)
	if multi:
		return maxf(multi_hit_hitstop_ms, 0.0)
	if amount >= big_hit_min_damage:
		return maxf(big_hitstop_ms, 0.0)
	return maxf(normal_hitstop_ms, 0.0)

# A hit a block took whole: its stop, in milliseconds; 0 with the stop off.
func blocked_stop_ms() -> float:
	return maxf(blocked_hitstop_ms, 0.0) if hitstop_enabled else 0.0

# How long a killing hit of `amount` on `target` takes to show in full, in
# seconds from its own frame: the play effect reaching it, then the
# longest of its flash, recoil (held back by its hit-stop) and slash
# mark - or the play effect running to its end, if that's later. Read in
# the hit's frame (BattleOverlay, for BattleController.kill_presentation_
# time).
func kill_presentation_time(target: FieldEnemy, amount: int) -> float:
	var hold: float = stop_ms(amount, true) / 1000.0
	var reaction: float = maxf(flash_rise_time + flash_fall_time, hold + recoil_out_time + recoil_return_time)
	reaction = maxf(reaction, slash_mark_grow_time + slash_mark_fade_time)
	return maxf(reaction_delay(target) + reaction, effect_remaining_time())

# How much longer this frame's play effect runs (its stroke's sweep, hold
# and fade), 0 with none.
func effect_remaining_time() -> float:
	if not _effect_active() or not _effect.has_method("remaining_time"):
		return 0.0
	return float(_effect.call("remaining_time"))

# The impact layer's volume: silent at the tier's light end, rising in
# amplitude to heavy_impact_max_volume_db at its full one.
func heavy_impact_volume_db(level: float) -> float:
	if level <= 0.0:
		return SILENT_DB
	return heavy_impact_max_volume_db + linear_to_db(level)

func recoil_multiplier(level: float) -> float:
	return 1.0 if level < 0.0 else lerpf(1.0, heavy_recoil_max_multiplier, level)

func number_multiplier(level: float) -> float:
	return 1.0 if level < 0.0 else lerpf(1.0, heavy_number_max_multiplier, level)

# The damage number's size for a hit of `amount` on `target` this frame:
# grown for a heavy card hit, 1 for anything else.
func number_scale(target: Variant, amount: int) -> float:
	if not (target is FieldEnemy):
		return 1.0
	return number_multiplier(heavy_level(heavy_damage(amount)))

# Whether a card hit of `amount` jolts the camera.
func jolts_camera(amount: int) -> bool:
	return heavy_hit_enabled and camera_shake_enabled and amount >= shake_min_damage

# The next impact-layer take - in turn, so two heavy hits in a row never
# share one.
func next_heavy_take() -> AudioStream:
	return _heavy_pool.next()

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

# BattleController.enemy_hit_blocked: a hit that broke through is marked
# for its damage_dealt, which follows at once; one the block took whole
# reacts here, paced by a play effect like any hit.
func on_enemy_hit_blocked(enemy: FieldEnemy, absorbed: bool) -> void:
	if not absorbed:
		_met_block[enemy] = true
		return
	var hold: float = blocked_stop_ms() / 1000.0
	_hold_wanderer(hold)
	var delay: float = reaction_delay(enemy)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if not is_instance_valid(enemy):
			return
	enemy.hold_for(hold)
	_react_to_absorbed_hit(enemy)

func _react_to_absorbed_hit(enemy: FieldEnemy) -> void:
	if _wanderer == null:
		return
	var attack_direction: Vector3 = enemy.global_position - _wanderer.global_position
	enemy.play_contact_sound(true)
	enemy.play_hit_recoil(attack_direction, recoil_distance * absorbed_recoil_fraction, recoil_tilt_degrees * absorbed_recoil_fraction, recoil_out_time, recoil_return_time)

# `heavy`: the hit's heavy_level() - -1 for an ordinary hit.
func _react_to_card_hit(enemy: FieldEnemy, slash: bool = true, armored: bool = false, heavy: float = -1.0) -> void:
	if _wanderer == null:
		return
	var attack_direction: Vector3 = enemy.global_position - _wanderer.global_position
	enemy.play_contact_sound(armored)
	if heavy > 0.0:
		enemy.play_heavy_impact(next_heavy_take(), heavy_impact_volume_db(heavy))
	enemy.play_hit_flash(flash_color, flash_rise_time, flash_fall_time)
	enemy.play_hit_recoil(attack_direction, recoil_distance * recoil_multiplier(heavy), recoil_tilt_degrees, recoil_out_time, recoil_return_time)
	enemy.spawn_sand_puff(sand_puff_particle_count, sand_puff_lifetime, sand_puff_velocity, sand_puff_spread_degrees, sand_puff_tint)
	if slash:
		enemy.spawn_slash_mark(attack_direction, _slash_mark_color(), slash_mark_length, slash_mark_width, slash_mark_chest_height, slash_mark_grow_time, slash_mark_fade_time)

# The draw's ground strike (Wanderer.draw_strike): a slash hit's sand puff
# on the sand under the sword tip, Wanderer.draw_strike_puff_scale its
# size and speed.
func _on_draw_strike(_tip: Vector3, ground_point: Vector3) -> void:
	if _wanderer == null:
		return
	var puff_scale: float = maxf(_wanderer.draw_strike_puff_scale, 0.0)
	_wanderer.spawn_sand_puff_at(ground_point, sand_puff_particle_count, sand_puff_lifetime, sand_puff_velocity * puff_scale, sand_puff_spread_degrees, puff_scale, sand_puff_tint)

func _react_to_enemy_attack(enemy: FieldEnemy) -> void:
	if _wanderer == null:
		return
	var attack_direction: Vector3 = _wanderer.global_position - enemy.global_position
	_wanderer.play_hit_audio()
	_wanderer.play_hit_flash(flash_color, flash_rise_time, flash_fall_time)
	_wanderer.play_hit_recoil(attack_direction, recoil_distance, recoil_tilt_degrees, recoil_out_time, recoil_return_time)
	_wanderer.spawn_sand_puff(sand_puff_particle_count, sand_puff_lifetime, sand_puff_velocity, sand_puff_spread_degrees, sand_puff_tint)

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

# The Wanderer's side of a contact's stop (Wanderer.hold_animation()):
# hits landing together (one card, several enemies) make one stop, as
# long as the longest of them.
func _hold_wanderer(seconds: float) -> void:
	if _wanderer != null and seconds > 0.0:
		_wanderer.hold_animation(seconds)

# CameraRig isn't threaded through as a reference anywhere in this chain -
# found via the active camera's own parent instead, the same "reach the
# live camera through the viewport" idiom BattleController._screen_pos_
# for()/_raycast_enemy() and BattleOverlay._screen_pos_for_damage_target()
# already use.
func _jolt_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var camera_rig := camera.get_parent() as CameraRig
	if camera_rig == null:
		return
	camera_rig.jolt(camera_jolt_amplitude, camera_jolt_duration)
