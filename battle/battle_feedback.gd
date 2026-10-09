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
# reacts here - the armored contact sound and a reduced recoil, nothing
# else (no flash, number, hit-stop or shake). One that breaks through
# reacts as any hit does, with the armored sound.
#
# The heavy tier: a card hit of heavy_min_damage or more, by that one
# hit's damage, is weightier - a hit-stop (hitstop_min_ms at
# heavy_min_damage rising to hitstop_max_ms at heavy_max_damage, never
# above HITSTOP_CAP_MS), a deep impact layered under the contact sound
# (heavy_impact_clips dealt in turn, silent at heavy_min_damage rising to
# heavy_impact_max_volume_db), and the recoil and the damage number grown
# up to their max multipliers. A card that spends Toll as its blow
# (CardEffect TOLL_DAMAGE - Reckoning) always counts as at least
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

@export_group("Heavy Hit")
@export var heavy_hit_enabled: bool = true
# The tier's range, in one hit's damage: its light end and its full one.
@export var heavy_min_damage: int = 10
@export var heavy_max_damage: int = 35
# The hit-stop at either end, in real milliseconds.
@export var hitstop_min_ms: float = 40.0
@export var hitstop_max_ms: float = 140.0
# How slow the world runs through a hit-stop.
@export_range(0.01, 1.0, 0.01) var hit_stop_time_scale: float = 0.05
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

@export_group("Killing Blow")
# A hit that kills holds at least this long (real seconds): the heavy
# tier's own stop when that is longer, this when it's shorter or there is
# none (Blood Arc's 9). Capped like any stop (HITSTOP_CAP_MS).
@export var kill_hitstop_min: float = 0.05

# A hit-stop never runs longer than this, whatever the tunables say.
const HITSTOP_CAP_MS: float = 160.0
# The impact layer's volume for "not at all".
const SILENT_DB: float = -80.0

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
# When the hit-stop running now ends, in real microseconds (0 = none).
var _stop_until_usec: int = 0

func _init() -> void:
	_heavy_pool.set_clips(heavy_impact_clips)

# A fight that ends mid-stop leaves the world at full speed.
func _exit_tree() -> void:
	if _stop_until_usec != 0:
		_stop_until_usec = 0
		Engine.time_scale = 1.0

func setup(wanderer: Wanderer, on_dark_world: bool) -> void:
	_wanderer = wanderer
	_on_dark_world = on_dark_world

# source/target mirror BattleController.damage_dealt's own doc exactly:
# each is either the String "player" or a FieldEnemy - which one is the
# FieldEnemy says which side got hit. The heavy tier, the slash mark, the
# hit-stop and the camera jolt are card-hit only; an enemy's hit on the
# Wanderer gets its sound, flash, recoil and puff.
func on_damage_dealt(source: Variant, target: Variant, amount: int, _kind: String) -> void:
	if amount <= 0:
		return

	if target is FieldEnemy:
		# Read now, in the hit's own frame - the effect lets go at its end.
		var slash: bool = not _effect_active()
		var armored: bool = _met_block.has(target)
		_met_block.erase(target)
		var heavy: float = heavy_level(heavy_damage(amount))
		var killing: bool = battle_controller != null and battle_controller.is_dying(target)
		var delay: float = reaction_delay(target)
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
			if not is_instance_valid(target):
				return
		_react_to_card_hit(target as FieldEnemy, slash, armored, heavy)
		_apply_hit_stop(stop_ms(heavy, killing))
		if jolts_camera(amount):
			_jolt_camera()
	elif source is FieldEnemy:
		_react_to_enemy_attack(source as FieldEnemy)

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

# A hit's stop at heavy_level() `level`, in real milliseconds; 0 below
# the tier.
func hitstop_ms(level: float) -> float:
	if level < 0.0:
		return 0.0
	return minf(lerpf(hitstop_min_ms, hitstop_max_ms, level), HITSTOP_CAP_MS)

# A card hit's stop, in real milliseconds: the heavy tier's (hitstop_ms()),
# and a killing hit's held to kill_hitstop_min at the least.
func stop_ms(level: float, killing: bool) -> float:
	var ms: float = hitstop_ms(level)
	if killing:
		ms = minf(maxf(ms, kill_hitstop_min * 1000.0), HITSTOP_CAP_MS)
	return ms

# How long a killing hit of `amount` on `target` takes to show in full, in
# real seconds from its own frame: the play effect reaching it, then the
# longest of its flash, recoil and slash mark, with its hit-stop on top -
# or the play effect running to its end, if that's later. Read in the
# hit's frame (BattleOverlay, for BattleController.kill_presentation_time).
func kill_presentation_time(target: FieldEnemy, amount: int) -> float:
	var reaction: float = maxf(flash_rise_time + flash_fall_time, recoil_out_time + recoil_return_time)
	reaction = maxf(reaction, slash_mark_grow_time + slash_mark_fade_time)
	var stop: float = stop_ms(heavy_level(heavy_damage(amount)), true) / 1000.0
	return maxf(reaction_delay(target) + reaction + stop, effect_remaining_time())

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
	var delay: float = reaction_delay(enemy)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if not is_instance_valid(enemy):
			return
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

# The world at hit_stop_time_scale for `ms` real milliseconds. Hits
# landing together (one card, several enemies) make one stop, as long as
# the longest of them: a stop only ever extends the one running. The
# timer that ends it ignores time scale - it has to run at real speed
# under the very time_scale it set; every other tween and timer keeps
# respecting it, so the world visibly holds.
func _apply_hit_stop(ms: float) -> void:
	if ms <= 0.0:
		return
	var until: int = Time.get_ticks_usec() + int(ms * 1000.0)
	if until <= _stop_until_usec:
		return
	_stop_until_usec = until
	Engine.time_scale = hit_stop_time_scale
	get_tree().create_timer(ms / 1000.0, true, false, true).timeout.connect(_end_hit_stop.bind(until))

# Ends the stop that ran to `until` - unless a longer one has taken over.
func _end_hit_stop(until: int) -> void:
	if until != _stop_until_usec:
		return
	_stop_until_usec = 0
	Engine.time_scale = 1.0

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
