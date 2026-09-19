extends Node3D
class_name Keeper

# NOTE on the wind masks: she has TWO, hem and hair. The hair one is
# selected by three conditions at once (height band, radius from the
# head's own axis, albedo luma) - every single-condition version of that
# test picks the wrong geometry on this asset, and an earlier pass of this
# file wrongly concluded there was no hair to move at all. The
# measurements that settle it live in keeper_wind.gdshader's header; read
# them before changing any hair_* default.
#
# The Keeper (Region 1 doc, section 6): a hooded figure standing at the
# shoreline of the opening room, facing the sea. She never turns, never
# follows. Loads Keeper_texture.glb (1.65 m, origin already at the feet,
# front on the model's +Z - same yaw-offset idiom as the Wanderer/
# FieldEnemy rigs) under this node, applies her own textured material per
# instance (see _build_material()), seats her feet on the relief via
# Ground.get_height_at() and re-seats on every relief_rebuilt, and stands
# a small capsule StaticBody3D so the Wanderer walks around her, not
# through.
#
# Her act: she holds a card out. One is rolled from keeper_pool per run
# (_pool_pick) and spawned as a WorldCard in her hand at keeper_hand_
# offset - small and unreadable from a distance, lifting and becoming
# readable when the Wanderer comes inside its own lift_radius, and
# granted by clicking it. See field/world_card.gd for all of that; this
# node only decides WHICH card and what taking means.
#
# Taking is the offer. The static seen-set (_offers_made, cleared by
# RunState.new_run() via reset_offers()) is written when the card is
# TAKEN, not when she is approached, so a player who walks away finds it
# still in her hand - on this floor and on any later one - and only
# taking it ever ends the offer.
#
# Her line follows the same fact: approach_line while the card is still
# there, return_line once it's gone, on every approach either way. Two
# different beats rather than one line replayed - the shape the old
# project's NPCData.dialogue_text/post_interaction_text established (see
# reference/old_project/deck-builder/npc_data.gd) - shown through the
# field's WorldVoiceLine with the same fade-hold-fade a Hull's own
# finding uses. No sound yet.

const MODEL_SCENE_PATH := "res://assets/models/keeper/Keeper_texture.glb"
# The glb's own base-colour map, extracted beside it at import (gltf/
# embedded_image_handling=1). Named for the glTF image's name, NOT its
# index: glTF image 1 is the one baseColorTexture points at and it is
# named "Image_0", which is why the albedo is _Image_0 and not _Image_1.
# The siblings _Image_1 (metallicRoughness) and _Image_2 (normal) are
# deliberately unused - see _build_material().
const ALBEDO_TEXTURE_PATH := "res://assets/models/keeper/Keeper_texture_Image_0.jpg"
# Her material AND the hem wind, in one shader - StandardMaterial3D has no
# vertex stage, which is the only reason she isn't still on one. See the
# shader's own header for what it re-expresses and why the hem is the only
# mask.
const WIND_SHADER_PATH := "res://field/keeper_wind.gdshader"

enum FaceDirection { SEAWARD, INLAND, LEFT, RIGHT }

# Yaw of the model under this node so its front lies on the node's local
# -Z, the direction _apply_facing() points. The glb's hood leads on +Z,
# so 180 turns it round; flip to 0 if she stands with her back to the sea.
@export var model_yaw_offset_degrees: float = 180.0:
	set(value):
		model_yaw_offset_degrees = value
		_apply_model_transform()
# A MULTIPLY over the albedo texture, not a flat colour of its own -
# Godot's spatial shader multiplies albedo_color into albedo_texture, so
# white (the default) renders her exactly as the texture was painted.
# Darken toward grey to sit her back against the sand; saturating it
# tints her. Was the flat matte tint before she was textured, which is
# why this stayed a Color rather than a brightness scalar.
@export var keeper_tint: Color = Color(1.0, 1.0, 1.0):
	set(value):
		keeper_tint = value
		_apply_tint()
# Relative to RegionField.get_forward() (spawn -> Tower): SEAWARD is
# -forward. Applied once at _ready(); she never rotates at runtime.
@export var face_direction: FaceDirection = FaceDirection.SEAWARD:
	set(value):
		face_direction = value
		_apply_facing()
@export var face_yaw_offset_degrees: float = 0.0:
	set(value):
		face_yaw_offset_degrees = value
		_apply_facing()

@export_group("Collision")
@export var collision_radius: float = 0.35:
	set(value):
		collision_radius = value
		_apply_collision()
@export var collision_height: float = 1.65:
	set(value):
		collision_height = value
		_apply_collision()

@export_group("Offer")
@export var approach_radius: float = 2.5:
	set(value):
		approach_radius = value
		if _approach_shape != null:
			_approach_shape.radius = maxf(approach_radius, 0.0)
# What she can hold out. One is rolled per RUN (not per floor - see
# _pool_pick) and held in her hand as a WorldCard; taking it is the
# grant. Class-agnostic resources, so they live in cards/neutral/ rather
# than under any class folder.
@export var keeper_pool: Array[CardData] = []
# Forces which card she holds instead of rolling from keeper_pool. Null
# (the default) rolls. This used to be the card she granted on approach;
# approaching no longer grants anything, so it is a dev/authoring
# override now, not the mechanism.
@export var offered_card: CardData = null
# Where the card sits, in THIS node's space - not the model's. The model
# child carries model_yaw_offset_degrees (180), so a point measured off
# the mesh has to be turned through that to get here: (x, y, z) becomes
# (-x, y, -z). Getting this wrong is what put the previous value in open
# air beside her.
#
# Measured, not eyeballed: her hand is a small pale bump proud of the
# torso at model (-0.213, 1.126, +0.342) - the y 1.10-1.15 band reaches
# z +0.358 where the bands above and below stop near +0.27. Turned into
# node space that is the value below. It is NOT the -X extreme: that end
# of the model (x -0.392) is the hair, and there is no outstretched arm
# on +X at all - the +X side only reaches x +0.19 at this height, which
# is body width.
#
# Deliberately NOT sitting on that measured point any more: at the
# field camera's 44 deg the card read as pinned against her chest. It is
# dropped to 0.80 (waist) and pushed out to 0.45 along her facing, which
# reads as held beside her from that angle. Staging over anatomy - the
# measurement above is still what the number is derived FROM, so put it
# back if the camera pitch ever changes.
@export var keeper_hand_offset: Vector3 = Vector3(0.213, 0.80, -0.45)
@export var world_card_scene_path: String = "res://field/world_card.tscn"
@export_group("")

# World voice, not dialogue: no quotes, no name label, no speech framing
# - a line sitting near her the way a Hull's own world_line does (see
# ui/world_voice_line.gd). Both carried over verbatim from the old
# project's opening_room_npc.tres, where they were NPCData.dialogue_text
# and .post_interaction_text. Worth knowing: that repo's own DESIGN.md
# marks the first one a placeholder, so it's inherited text rather than
# settled text. Empty either line and that beat stays silent.
@export_group("World Voice")
# The first approach of the run - shown with the card offer.
@export_multiline var approach_line: String = "She holds something out. It was not hers."
# Every approach after the first. No seen-set of its own, on purpose:
# "you've already taken it" is a standing state, not a one-off event, so
# she says it every time the Wanderer comes back rather than once.
@export_multiline var return_line: String = "Still facing out."
# Matched to Hull's own defaults so a finding and a Keeper line hold and
# fade identically - they share the one WorldVoiceLine instance.
@export var hold_seconds: float = 4.0
@export var fade_seconds: float = 0.5
@export_group("")

# A slow wind on the cloak hem - the only part of her that moves. See
# keeper_wind.gdshader for the mask and the gust shape, and this class's
# own history for why there's no hair mask (the luminance mask that was
# specced for one selects her boots on this asset, and the head is a
# smooth hood with no hair geometry on it).
@export_group("Wind")
# The band, in local metres above her feet: nothing moves at or below
# boot_top, the throw peaks at hem_height, and it's still again by
# waist_height. See the shader's own hem_band() for the curve and for why
# this is a band rather than the ramp it started as (the ramp moved her
# boots most, which is backwards).
@export var boot_top: float = 0.18:
	set(value):
		boot_top = value
		_apply_wind()
@export var hem_height: float = 0.45:
	set(value):
		hem_height = value
		_apply_wind()
@export var waist_height: float = 0.95:
	set(value):
		waist_height = value
		_apply_wind()
# Metres at full weight and a full gust. 0.08 rather than the 0.02 this
# started at because she is normally seen from ~16 m, where 0.02 is under
# 2 px of travel - see this pass's own report.
@export var wind_amplitude: float = 0.08:
	set(value):
		wind_amplitude = value
		_apply_wind()
@export var wind_speed: float = 0.4:
	set(value):
		wind_speed = value
		_apply_wind()
# World space. ZERO (the default) means "the way she faces" - resolved in
# _apply_wind() from her own facing, so it follows face_direction and
# never hardcodes an axis. Set it non-zero to aim the wind independently.
@export var wind_direction: Vector3 = Vector3.ZERO:
	set(value):
		wind_direction = value
		_apply_wind()
# How much the gust's phase varies across the hem, so the skirt ripples
# rather than sliding as one rigid piece. 0 moves the whole hem together.
@export var wind_phase_scale: float = 0.6:
	set(value):
		wind_phase_scale = value
		_apply_wind()
@export_group("")

# The hair. Selected by three conditions at once - local height band,
# radius from the HEAD's own axis, and albedo luma - because no single
# one of them isolates it on this asset; see keeper_wind.gdshader's own
# header for the measurements behind every default here, including why
# the radius is taken about head_axis_xz rather than the model origin.
@export_group("Hair Wind")
@export var hair_y_min: float = 1.05:
	set(value):
		hair_y_min = value
		_apply_wind()
@export var hair_y_max: float = 1.55:
	set(value):
		hair_y_max = value
		_apply_wind()
# 0.14 clears the hood dome (inside ~0.12); the tips reach 0.386.
@export var hair_radial_min: float = 0.14:
	set(value):
		hair_radial_min = value
		_apply_wind()
@export var hair_radial_tip: float = 0.38:
	set(value):
		hair_radial_tip = value
		_apply_wind()
# sRGB, the space it was measured in - the shader converts before
# comparing (see hair_weight()).
@export var hair_luma_threshold: float = 0.35:
	set(value):
		hair_luma_threshold = value
		_apply_wind()
# XZ centroid of the vertices above y 1.40, in model space. Measured off
# the glb; re-measure if the model is ever replaced.
@export var head_axis_xz: Vector2 = Vector2(-0.031, 0.128):
	set(value):
		head_axis_xz = value
		_apply_wind()
@export var hair_amplitude: float = 0.06:
	set(value):
		hair_amplitude = value
		_apply_wind()
# The hair runs through the same gust this much faster than the hem.
@export var hair_gust_scale: float = 1.4:
	set(value):
		hair_gust_scale = value
		_apply_wind()
@export_group("")

# Instances live under RegionField directly.
@export var ground_path: NodePath = ^"../Ground"
@export var region_field_path: NodePath = ^".."

# Keepers whose card has been TAKEN this run, keyed by _offer_id() -
# static so it survives the reload_current_scene() a floor exit does.
# Cleared by RunState.new_run() via reset_offers() (kept that name: it's
# what run_state.gd calls). Taking is what writes this, not approaching:
# the card sits in her hand until the player actually takes it, so a
# player who walks away still finds it there, and her line still says she
# is holding something out.
static var _offers_made: Dictionary = {}

# The card rolled for THIS run, shared by every Keeper instance and held
# across the scene reload a floor exit does - roll once per run, not once
# per _ready(), or walking out and back would reroll her offer.
static var _pool_pick: CardData = null

static func reset_offers() -> void:
	_offers_made.clear()
	_pool_pick = null

var _model: Node3D = null
# Normally the ShaderMaterial from keeper_wind.gdshader; a plain
# StandardMaterial3D on the fallback path (see _build_material()), which
# is why this is typed Material and every write to it branches - the same
# shape Wanderer._active_material already uses for its own two-kinds-of-
# material case.
var _material: Material = null
var _ground: Ground = null
var _collision_body: StaticBody3D = null
var _collision_shape: CapsuleShape3D = null
var _collision_shape_node: CollisionShape3D = null
var _approach_area: Area3D = null
var _approach_shape: SphereShape3D = null
# The card in her hand this run, or null once taken (or never spawned).
var _world_card: WorldCard = null
var _ready_done: bool = false

func _ready() -> void:
	_spawn_model()
	_spawn_collision()
	_spawn_approach_area()
	_spawn_contact_shadow()
	_spawn_world_card()
	_ready_done = true
	_apply_facing()

	# Ground precedes this node in the scene, so its first relief_rebuilt
	# has already fired - the manual call covers the initial grounding,
	# the connection every live relief edit after it (same as Hull).
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("Keeper: ground_path did not resolve to a Ground; not grounded.")
		return
	_ground.relief_rebuilt.connect(_ground_to_relief)
	_ground_to_relief()

func _spawn_model() -> void:
	var scene := load(MODEL_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("Keeper: could not load %s; no model." % MODEL_SCENE_PATH)
		return
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	add_child(_model)

	_material = _build_material()
	_apply_tint()
	_apply_wind()
	for mesh_instance in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		mi.material_override = _material
		# DOUBLE_SIDED, not ON, because the material culls nothing (see
		# _build_material()): ON casts from front faces only, which on a
		# doubleSided mesh drops whatever the author left single-sided and
		# thins the silhouette the shadow is drawn from.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_apply_model_transform()

# Characters in this project are textured, props are flat: the Wanderer
# reads her own albedo off a jpg (Wanderer._build_textured_material()),
# the hulls and the bird stay a flat tint. She's a character, so this is
# the Wanderer's recipe rather than Hull's - the same "roughness 1,
# specular 0" matte shape either way, only with a texture in the albedo
# slot and keeper_tint demoted to a multiply over it.
#
# Only the base colour is wired. The glb also ships a normal map and a
# metallicRoughness map (see ALBEDO_TEXTURE_PATH's own doc); both are
# deliberately left out - flat matte, no normal map, is the look, and the
# override replaces the imported material wholesale so neither is ever
# reached.
#
# Culling off because the glb's own material declares doubleSided: true.
# A fresh StandardMaterial3D defaults to back-face culling, which would
# punch holes in whatever single-sided geometry the author relied on that
# flag for (hood lining, cloak).
#
# Falls back to the shared flat material if the texture can't load, so a
# missing or not-yet-imported jpg degrades to a solid tinted figure
# rather than a white untextured one - same guarded shape Wanderer._
# build_textured_material() uses for its own fallback.
#
# The shader is what actually carries all of that now (see WIND_SHADER_
# PATH) - it exists because the hem wind needs a vertex stage, which
# StandardMaterial3D doesn't have. If either the shader or the texture
# won't load, this degrades one step at a time: a missing shader still
# gets her textured on a StandardMaterial3D (no wind), a missing texture
# on top of that gets her the flat tint.
func _build_material() -> Material:
	var texture := load(ALBEDO_TEXTURE_PATH) as Texture2D
	if texture == null:
		push_warning("Keeper: albedo texture failed to load (%s); using the flat tinted fallback material." % ALBEDO_TEXTURE_PATH)
		return Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	var shader := load(WIND_SHADER_PATH) as Shader
	if shader == null:
		push_warning("Keeper: wind shader failed to load (%s); using a plain textured material, no hem wind." % WIND_SHADER_PATH)
		var fallback := StandardMaterial3D.new()
		fallback.albedo_texture = texture
		fallback.roughness = 1.0
		fallback.metallic_specular = 0.0
		fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
		return fallback
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_texture", texture)
	return material

# keeper_tint reaches the two material kinds by different names - the
# shader's own `tint` uniform, or albedo_color on either fallback.
func _apply_tint() -> void:
	if _material is ShaderMaterial:
		(_material as ShaderMaterial).set_shader_parameter("tint", keeper_tint)
	elif _material is StandardMaterial3D:
		(_material as StandardMaterial3D).albedo_color = keeper_tint

# Pushes every wind uniform, including the resolved direction: wind_
# direction ZERO means "the way she faces", which is her own -Z in world
# space once _apply_facing() has set her rotation. Called from there too,
# so re-aiming her re-aims the wind with nothing else to touch. No-ops on
# the fallback materials, which have no wind to drive.
func _apply_wind() -> void:
	var material := _material as ShaderMaterial
	if material == null:
		return
	var direction: Vector3 = wind_direction
	if direction.length() < 0.0001:
		direction = -global_transform.basis.z
	direction = Vector3(direction.x, 0.0, direction.z)
	material.set_shader_parameter("boot_top", boot_top)
	material.set_shader_parameter("hem_height", hem_height)
	material.set_shader_parameter("waist_height", waist_height)
	material.set_shader_parameter("wind_amplitude", wind_amplitude)
	material.set_shader_parameter("wind_speed", wind_speed)
	material.set_shader_parameter("wind_phase_scale", wind_phase_scale)
	material.set_shader_parameter("hair_y_min", hair_y_min)
	material.set_shader_parameter("hair_y_max", hair_y_max)
	material.set_shader_parameter("hair_radial_min", hair_radial_min)
	material.set_shader_parameter("hair_radial_tip", hair_radial_tip)
	material.set_shader_parameter("hair_luma_threshold", hair_luma_threshold)
	material.set_shader_parameter("head_axis_xz", head_axis_xz)
	material.set_shader_parameter("hair_amplitude", hair_amplitude)
	material.set_shader_parameter("hair_gust_scale", hair_gust_scale)
	material.set_shader_parameter("wind_direction_world", direction.normalized() if direction.length() > 0.0001 else Vector3.FORWARD)

func _apply_model_transform() -> void:
	if _model == null:
		return
	_model.rotation = Vector3(0.0, deg_to_rad(model_yaw_offset_degrees), 0.0)
	_model.position = Vector3.ZERO

# The soft disc under her feet - the SAME ContactShadow the Wanderer and
# every FieldEnemy already carry (see field/contact_shadow.gd), and the
# thing she was actually missing: the real directional shadow alone is
# faint under this overcast light (OvercastLight.shadow_darkness is 0.35
# in region_field.tscn, well under the script's own 0.6 default), and it
# lands on the wet, already-darkened sand she stands on. Every other
# figure in the field is grounded by this blob rather than by the light;
# she was the only one without it, which is why she read as floating
# while the hulls - big, and on dry sand - did not.
#
# Defaults as-is (radius 0.5, opacity 0.25), same as the Wanderer's and
# the enemies': it's tuned by selecting the child node in the Remote tab,
# not by exports here. ContactShadow's own ground_path (^"../Ground")
# resolves correctly from here for the same reason it does for the
# Wanderer - both are direct children of RegionField.
func _spawn_contact_shadow() -> void:
	var contact_shadow := ContactShadow.new()
	contact_shadow.name = "ContactShadow"
	add_child(contact_shadow)

# A capsule standing on the node origin (her feet), default physics
# layer/mask like the walls and hulls.
func _spawn_collision() -> void:
	_collision_body = StaticBody3D.new()
	_collision_body.name = "Collision"
	# Same reasoning as Ground's/FieldEnemy's own override: RegionField's
	# battle freeze would otherwise remove her from the physics space
	# entirely (disable_mode's default, REMOVE), and a click on her during
	# a fight would fall straight through to the sand behind her - the
	# point-to-move raycast takes whatever body it hits (see RegionField._
	# unhandled_input()). MAKE_STATIC keeps her solid while frozen.
	_collision_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	_collision_shape = CapsuleShape3D.new()
	_collision_shape_node = CollisionShape3D.new()
	_collision_shape_node.shape = _collision_shape
	_collision_body.add_child(_collision_shape_node)
	add_child(_collision_body)
	_apply_collision()

func _apply_collision() -> void:
	if _collision_shape == null:
		return
	_collision_shape.radius = maxf(collision_radius, 0.01)
	_collision_shape.height = maxf(collision_height, collision_radius * 2.0)
	_collision_shape_node.position = Vector3(0.0, _collision_shape.height * 0.5, 0.0)

# The approach trigger, same shape as Hull's/Bird's.
func _spawn_approach_area() -> void:
	_approach_area = Area3D.new()
	_approach_area.name = "ApproachArea"
	_approach_area.monitorable = false
	_approach_shape = SphereShape3D.new()
	_approach_shape.radius = maxf(approach_radius, 0.0)
	var shape_node := CollisionShape3D.new()
	shape_node.shape = _approach_shape
	_approach_area.add_child(shape_node)
	add_child(_approach_area)
	_approach_area.body_entered.connect(_on_approach_body_entered)

# Scene file + path from the scene root - the same keeper on a reloaded
# floor has the same id.
func _offer_id() -> String:
	var root: Node = owner if owner != null else self
	return "%s:%s" % [root.scene_file_path, str(root.get_path_to(self))]

# Which line she says follows whether the card is still in her hand, not
# how many times she has been approached: approach_line while the offer
# stands, return_line once it has been taken. So a player who walks away
# without taking hears "she holds something out" again on their way back,
# which is true - she is still holding it - and only taking it ever
# switches her to "still facing out".
func _on_approach_body_entered(body: Node3D) -> void:
	if not body.is_in_group("wanderer"):
		return
	_show_line(return_line if _offers_made.has(_offer_id()) else approach_line)

# Her line on the field's one WorldVoiceLine - the same lazy on_hud()
# lookup, the same fade-hold-fade, the same FieldHUD a Hull's finding
# uses (see Hull._on_approach_body_entered()). A line arriving while
# another is still showing restarts the fade with the new text, which is
# show_line()'s own behaviour and the right one here: she and a hull
# beside her can both be in range.
func _show_line(line_text: String) -> void:
	if line_text.is_empty():
		return
	var region_field := get_node_or_null(region_field_path) as Node
	var hud: Node = region_field.get_node_or_null(^"FieldHUD") if region_field != null else null
	var line := WorldVoiceLine.on_hud(hud)
	if line == null:
		push_warning("Keeper '%s': no FieldHUD to show its world line on." % name)
		return
	line.fade_in_seconds = fade_seconds
	line.fade_out_seconds = fade_seconds
	line.show_line(line_text, hold_seconds)

# The card in her hand, if this run's hasn't been taken yet. Spawned as a
# WorldCard child so it inherits her transform - keeper_hand_offset is
# then a plain local position, and re-facing her carries the card round
# with her for free.
func _spawn_world_card() -> void:
	if _offers_made.has(_offer_id()):
		return
	var picked: CardData = _pick_card()
	if picked == null:
		push_warning("Keeper '%s': keeper_pool is empty and offered_card is null; nothing to hold out." % name)
		return
	var scene := load(world_card_scene_path) as PackedScene
	if scene == null:
		push_warning("Keeper '%s': could not load %s; no card in hand." % [name, world_card_scene_path])
		return
	_world_card = scene.instantiate() as WorldCard
	_world_card.name = "WorldCard"
	_world_card.card = picked
	_world_card.position = keeper_hand_offset
	# WorldCard resolves FieldHUD/DeckPanel from here; it sits one level
	# deeper than this node, so its own default (^"../..") already lands on
	# RegionField - passed explicitly anyway so re-parenting her doesn't
	# silently break the card's flight target.
	_world_card.region_field_path = ^"../.."
	_world_card.taken.connect(_on_world_card_taken)
	add_child(_world_card)

# offered_card forces the pick; otherwise roll once per run and remember
# it. Draws from RunState.rng, the run's own seeded generator, so which
# card she holds belongs to the run's sequence rather than to whenever
# the scene happened to load.
func _pick_card() -> CardData:
	if offered_card != null:
		return offered_card
	if _pool_pick != null:
		return _pool_pick
	if keeper_pool.is_empty():
		return null
	_pool_pick = keeper_pool[RunState.rng.randi() % keeper_pool.size()]
	return _pool_pick

# Taking is the offer: RunState.add_card() already ran inside WorldCard
# (the run's one card-grant path - the starting Belongings come from
# CharacterData.starting_deck_counts in RunState.new_run(), and the battle
# hand is dealt from the deck by BattleController.setup(), so the card is
# in the deck for the next fight and shows in the field DeckPanel at once
# via deck_changed). All that's left here is to remember it happened, so
# her line switches and the card doesn't come back on the next floor.
func _on_world_card_taken(card_data: CardData) -> void:
	_offers_made[_offer_id()] = true
	_world_card = null
	# The card that was actually taken - NOT offered_card, which is the
	# optional authoring override and is null on every normal run, since
	# the card comes from keeper_pool.
	print("Keeper '%s': offered '%s'." % [name, card_data.card_name])

# The facing yaw: face_direction relative to the field's forward, plus
# face_yaw_offset_degrees - same direction<->angle convention as Hull.
func _facing_yaw() -> float:
	var forward := Vector3.FORWARD
	var region_field := get_node_or_null(region_field_path) as RegionField
	if region_field != null:
		forward = region_field.get_forward()
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	if forward.length() < 0.0001:
		forward = Vector3.FORWARD
	var direction: Vector3
	match face_direction:
		FaceDirection.INLAND:
			direction = forward
		FaceDirection.LEFT:
			direction = Vector3.UP.cross(forward)
		FaceDirection.RIGHT:
			direction = forward.cross(Vector3.UP)
		_:
			direction = -forward
	return atan2(-direction.x, -direction.z) + deg_to_rad(face_yaw_offset_degrees)

func _apply_facing() -> void:
	if not _ready_done:
		return
	rotation = Vector3(0.0, _facing_yaw(), 0.0)
	# The wind's default direction IS her facing, so it has to be re-pushed
	# whenever that moves - see _apply_wind().
	_apply_wind()

# Feet on the relief at her own XZ (get_height_at() is in Ground's local
# frame - to_local() first, same as Hull/FieldEnemy).
func _ground_to_relief() -> void:
	if not _ready_done or _ground == null:
		return
	var local_xz: Vector3 = _ground.to_local(Vector3(global_position.x, 0.0, global_position.z))
	global_position.y = _ground.get_height_at(Vector2(local_xz.x, local_xz.z))
