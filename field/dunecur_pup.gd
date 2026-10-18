extends Node3D
class_name DunecurPup

# Floor 4's event (its "pup" event slot, FloorData.event_slots): a
# Dunecur pup half buried in the sand beside a damp patch, in a ring of
# brush on the faint side of the loop. The Adder bit it - the line's
# punctures imply it, nothing names it (nor the pup's kind).
#
# Lying, it breathes (a slow swell of breath_scale at breath_hz) on its
# side (lying_roll_degrees), sunk sink_m into the sand. The walk-up and
# the click are the trough's (PropApproach, TroughChoice - this is the
# choice's host): inside approach_radius the line shows once per visit -
# find_line, two short lines and nothing more. A click in reach opens the
# choices: give_text and leave_text, always both - give_text shown but
# not on offer (is_choice_enabled()) while the deck holds no card tagged
# remedy_tag (CardData.tags - never a card's name, so a rename changes
# nothing here). Giving removes one - a plain one before a tempered one -
# says saved_line, one line, and the pup gets up and follows; leaving changes nothing, and it lies there until the floor
# ends. Each is logged (RunLogger "pup": found / remedy_given / left).
#
# Following: it walks the Wanderer's own trail (his positions, every
# trail_step_m), keeping follow_distance_m of trail behind him and
# stopping when he stops - so it goes round whatever he went round and
# needs no collision of its own (it has none once up). It trots faster
# the further it falls behind. While a fight is open (RegionField.is_
# battle_open()) it backs off along the way it came until it is
# battle_wait_distance_m from him, waits, and takes up the trail again
# after.
#
# The meeting (RegionField._try_reunion(), on contact with an enemy in
# reunite_slot while this follows): no fight. The adult's crest rises
# (FieldEnemy.set_alert(adult_alarm_stacks)) and it looks round; the pup
# trots to it, the crest settles (set_alert(0)), reunion_line is said
# over them, and the two turn and walk off together, away from the
# Wanderer, and are freed once out of the camera's view (or after
# walk_off_max_seconds). reunion_released fires reunion_hold_seconds after
# the contact - the field's hold ends and the gate opens there, whatever
# the walk has reached; walked_off once both are gone.
#
# Once per run: a pup that has stood on its floor this run never stands
# there again (the region can wrap round to floor 4) - the second visit
# has no pup, and the Dunecur fights. Static, keyed by pup_id; cleared by
# RunState.new_run() through reset_run().
#
# The model is the adult's (model_scene_path, its painted map and its
# DunecurPose - the crest lies flat out of a fight) at model_scale - a
# stand-in until a pup of its own exists; a path swap. Its walk is a
# tweened bob and sway (the traveller's way), no rig. The damp patch is
# a Decal of a soft radial fill, darker and wetter, left where the pup
# lay when it gets up (top_level), cast on everything but the pup itself
# (layer PUP_LAYER) and faded off anything that doesn't face up (the
# Wanderer's legs, walking through it).

signal reunion_released(adult: FieldEnemy)
signal walked_off(adult: FieldEnemy)

const GROUP := &"pups"
const CHOICE_SCENE_PATH := "res://battle/trough_choice.tscn"
# The render layer the pup's own meshes are moved to, so its damp patch
# (cull_mask without it) never darkens it.
const PUP_LAYER := 1 << 19

enum State { LYING, RISING, FOLLOWING, REUNITING, GONE }
enum Meet { TROT, GREET, WALK }

@export_group("Model")
@export_file("*.glb") var model_scene_path: String = "res://assets/models/enemies/Dunecur/Dunecur.glb":
	set(value):
		model_scene_path = value
		_rebuild_model()
@export_file("*.jpg", "*.png") var painted_albedo_path: String = "res://assets/models/enemies/Dunecur/Dunecur_Image_0.jpg":
	set(value):
		painted_albedo_path = value
		_rebuild_model()
@export_file("*.tscn") var attachment_scene_path: String = "res://field/dunecur_pose.tscn":
	set(value):
		attachment_scene_path = value
		_rebuild_model()
# The adult's 1.34 x 0.45.
@export var model_scale: float = 0.6:
	set(value):
		model_scale = value
		_rebuild_model()
# The scale the attachment's metres were tuned at (the adult's EnemyData.
# model_scale): its skin is built in a frame shrunk by model_scale over
# this, so its crest and head regions land on the same parts of the body.
@export var attachment_tuned_scale: float = 1.34:
	set(value):
		attachment_tuned_scale = value
		_rebuild_model()
# The glb's facing onto the body's -Z (EnemyData.model_yaw_offset_degrees).
@export var model_yaw_offset_degrees: float = 180.0:
	set(value):
		model_yaw_offset_degrees = value
		_rebuild_model()
@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_apply_tint()
# Its share of the depth fog, as an enemy's (RegionField.enemy_fog_factor).
@export_range(0.0, 1.0, 0.01) var fog_factor: float = 0.4:
	set(value):
		fog_factor = value
		_push_fog()
# The facing it lies in, degrees, on top of the FloorProp's yaw.
@export var lying_yaw_degrees: float = 0.0:
	set(value):
		lying_yaw_degrees = value
		if _state == State.LYING:
			_apply_yaw(0.0)
@export_group("")

@export_group("Lying")
# On its side: the roll about its own length, degrees.
@export_range(0.0, 100.0, 0.5) var lying_roll_degrees: float = 82.0:
	set(value):
		lying_roll_degrees = value
		_apply_pose()
# How far it lies sunk into the sand, metres.
@export var sink_m: float = 0.1:
	set(value):
		sink_m = value
		_apply_pose()
# The breath: a swell of the body by this fraction, this often.
@export var breath_scale: float = 0.035
@export var breath_hz: float = 0.22
# Getting up once saved, seconds.
@export var rise_seconds: float = 1.2
@export_group("")

@export_group("Damp Patch")
# Its size on the sand, metres (across, along), and where its middle lies
# from the pup's own spot, in the pup's frame (x across, y along).
@export var damp_size_m: Vector2 = Vector2(1.7, 1.2):
	set(value):
		damp_size_m = value
		_apply_damp()
@export var damp_offset_m: Vector2 = Vector2(-0.9, 0.2):
	set(value):
		damp_offset_m = value
		_apply_damp()
# Its footprint radius for the pool under it (ContactShadow.footprint),
# metres - its own, since the stand-in model lies on its side and its box
# says nothing about what it covers.
@export var contact_footprint_m: float = 0.45:
	set(value):
		contact_footprint_m = value
		if _shadow != null:
			_shadow.footprint = Vector2(value, value)
# The patch's colour at its middle (alpha its strength), fading out to
# its edge.
@export var damp_color: Color = Color(0.36, 0.33, 0.27, 0.55):
	set(value):
		damp_color = value
		_apply_damp()
# The decal's reach up and down from the sand, metres, and how much it
# fades off faces turned from straight up (Decal.normal_fade).
@export var damp_depth_m: float = 0.5:
	set(value):
		damp_depth_m = value
		_apply_damp()
@export_range(0.0, 1.0, 0.01) var damp_normal_fade: float = 0.6:
	set(value):
		damp_normal_fade = value
		_apply_damp()
@export_group("")

@export_group("Approach")
@export var approach_radius: float = 2.6:
	set(value):
		approach_radius = value
		_apply_approach_radius()
# Two lines, each read in about two seconds - what's there, and the bite
# it implies.
@export_multiline var find_line: String = "A pup lies curled in the brush.\nTwo small punctures on its foreleg. It's swelling."
@export_multiline var saved_line: String = "It takes it slowly. After a while, it stands."
# Its find and saved lines are said over it, this far above its model's
# top - WorldVoiceLine lifts them clear of the brush round it.
@export var line_clearance_m: float = 0.4
@export var hold_seconds: float = 4.0
@export var fade_seconds: float = 0.5
@export_group("")

@export_group("Choice")
# The card kind it needs (CardData.tags).
@export var remedy_tag: StringName = &"field_remedy"
@export var give_text: String = "Give it Samphire"
@export var leave_text: String = "Leave it"
@export_group("")

@export_group("Follow")
# Trail kept between him and it, metres.
@export var follow_distance_m: float = 2.0
@export var trail_step_m: float = 0.3
# Its trot, and how much faster it goes when catch_up_m of trail further
# back than follow_distance_m.
@export var follow_speed: float = 4.2
@export var catch_up_m: float = 4.0
@export_range(0.0, 2.0, 0.05) var catch_up_boost: float = 0.6
@export var turn_speed: float = 6.0
# The Wanderer's own trail kept behind it for backing off, metres.
@export var walked_keep_m: float = 40.0
@export_group("")

@export_group("Fights")
# How far from him it waits out a fight he is in.
@export var battle_wait_distance_m: float = 8.0
@export var retreat_speed: float = 4.5
@export_group("")

@export_group("Trot")
# The step's lift, metres, at full trot; strides per metre covered; the
# sway either side, degrees.
@export var bob_m: float = 0.05
@export var strides_per_m: float = 1.1
@export var sway_degrees: float = 2.5
@export_group("")

@export_group("Reunion")
# The EncounterSlot.slot_id of the adult it belongs to.
@export var reunite_slot: StringName = &"dunecur"
# Further back than this along the ground when he reaches it, it isn't
# with him: the fight goes on as ever.
@export var reunite_max_distance_m: float = 12.0
@export var reunion_hold_seconds: float = 3.5
@export var adult_alarm_stacks: int = 4
@export var adult_turn_seconds: float = 0.5
# The pup stops this far from the adult's middle, on its own side.
@export var reunite_gap_m: float = 1.7
@export var reunite_speed: float = 3.5
@export var greet_seconds: float = 0.9
@export_multiline var reunion_line: String = "The big one lowers its head to it. They go together."
@export var reunion_line_seconds: float = 4.0
# Away from the Wanderer, turned this many degrees.
@export var walk_off_turn_degrees: float = 0.0
@export var walk_off_speed: float = 1.8
@export var walk_off_side_m: float = 1.1
@export var walk_off_max_seconds: float = 20.0
@export_group("")

# Set by RegionField._spawn_prop_list(): the slot, the option and the
# prop's index. Empty = the floor's path and this node's name.
@export var pup_id: String = ""
@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."

# pup_id -> true once it has stood on its floor this run.
static var _stood: Dictionary = {}

static func reset_run() -> void:
	_stood.clear()

var _state: State = State.LYING
var _placement_yaw: float = 0.0
# Yaw carries the facing; Pose the lie, the breath and the step; the
# model sits grounded under Pose.
var _pose: Node3D = null
var _model: Node3D = null
var _model_aabb: AABB = AABB()
var _material: ShaderMaterial = null
var _fog: ShaderMaterial = null
var _sky: RegionSky = null
var _damp: Decal = null
# Where it lies - the damp patch stays there.
var _lying_transform: Transform3D = Transform3D.IDENTITY
var _shadow: ContactShadow = null
var _collision_body: StaticBody3D = null
var _approach: PropApproach = null
var _ground: Ground = null
var _choice: Control = null
var _found_logged: bool = false
# 1 lying, 0 standing - the rise eases it down.
var _lie: float = 1.0
var _breath_phase: float = 0.0
var _stride_phase: float = 0.0
var _speed_now: float = 0.0
# His positions ahead of it, oldest first; behind it, newest last.
var _trail: Array[Vector3] = []
var _walked: Array[Vector3] = []
# The meeting.
var _adult: FieldEnemy = null
var _meet: Meet = Meet.TROT
var _meet_time: float = 0.0
var _meet_spot: Vector3 = Vector3.ZERO
var _away: Vector3 = Vector3.ZERO
var _meet_time_mark: float = 0.0
var _released: bool = false
var _unseen_for: float = 0.0
var _adult_stride_phase: float = 0.0

# FloorProp's placement (RegionField._spawn_prop_list()): XZ here, Y from
# the relief; the entry's yaw under lying_yaw_degrees.
func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	_placement_yaw = yaw
	_apply_yaw(0.0)

func _ready() -> void:
	if _stood.has(_pup_id()):
		queue_free()
		return
	_stood[_pup_id()] = true
	add_to_group(GROUP)
	_apply_yaw(0.0)
	_rebuild_model()
	_spawn_collision()
	_spawn_approach()
	_shadow = ContactShadow.new()
	_shadow.name = "ContactShadow"
	_shadow.footprint = Vector2(contact_footprint_m, contact_footprint_m)
	add_child(_shadow)
	_ground = get_node_or_null(ground_path) as Ground
	_shadow.set_ground(_ground)
	if _ground == null:
		push_warning("DunecurPup '%s': ground_path did not resolve to a Ground; not grounded." % name)
	else:
		_ground.relief_rebuilt.connect(_ground_to_relief)
		_ground_to_relief()
	_lying_transform = global_transform
	_spawn_damp()
	var region_field := _region_field()
	if region_field != null:
		_sky = region_field.get_region_sky()
		if _sky != null:
			_sky.fog_changed.connect(_push_fog)
	_push_fog()
	# The trot and the backing off run off the tree's own physics tick, so
	# they carry on through the fight's freeze (the field's PROCESS_MODE_
	# DISABLED); the walk-up and the click don't - they stay with this
	# node, under the field.
	get_tree().physics_frame.connect(_on_physics_frame)

func _exit_tree() -> void:
	if get_tree() != null and get_tree().physics_frame.is_connected(_on_physics_frame):
		get_tree().physics_frame.disconnect(_on_physics_frame)

func _region_field() -> RegionField:
	return get_node_or_null(region_field_path) as RegionField

func _wanderer() -> Node3D:
	var region_field := _region_field()
	return region_field.wanderer if region_field != null else null

# --- Model ---

func _rebuild_model() -> void:
	if not is_inside_tree():
		return
	if _pose != null:
		_pose.queue_free()
	_pose = Node3D.new()
	_pose.name = "Pose"
	add_child(_pose)
	_model = null
	_model_aabb = AABB()
	var scene := load(model_scene_path) as PackedScene
	if scene == null:
		push_warning("DunecurPup '%s': could not load %s; no model." % [name, model_scene_path])
		return
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	_model.scale = Vector3.ONE * model_scale
	_model.rotation.y = deg_to_rad(model_yaw_offset_degrees)
	_pose.add_child(_model)
	_material = PaintedProp.material(painted_albedo_path, tint)
	_fog = null
	if _material != null:
		_fog = PaintedProp.fog_pass()
		_material.next_pass = _fog
		_model_aabb = PaintedProp.dress_model(_model, _material, _pose)
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).layers = PUP_LAYER
	if _model_aabb.size != Vector3.ZERO:
		_model.position.y = -_model_aabb.position.y
		_model_aabb.position.y = 0.0
	if not attachment_scene_path.is_empty():
		var attachment_scene := load(attachment_scene_path) as PackedScene
		if attachment_scene != null:
			var attachment := attachment_scene.instantiate()
			# The skin's axes from a frame on this node - never the rolled
			# Pose - at the scale its metres were tuned for.
			if "frame" in attachment:
				var skin_frame := Node3D.new()
				skin_frame.name = "SkinFrame"
				skin_frame.scale = Vector3.ONE * (model_scale / maxf(attachment_tuned_scale, 0.001))
				_pose.add_child(skin_frame)
				attachment.set("frame", skin_frame)
			_model.add_child(attachment)
		else:
			push_warning("DunecurPup '%s': could not load %s; no pose." % [name, attachment_scene_path])
	_apply_pose()
	_push_fog()

func _apply_tint() -> void:
	if _material != null:
		_material.set_shader_parameter("albedo_tint", tint)

func _push_fog() -> void:
	PaintedProp.push_fog(_fog, _sky, fog_factor)

# Pose: the roll on its side about its own length (local Z) through its
# middle, the middle set down to half its width less sink_m - eased
# toward standing by _lie - then the breath's swell and the step's lift
# and sway.
func _apply_pose() -> void:
	if _pose == null or _model_aabb.size == Vector3.ZERO:
		return
	var centre: Vector3 = _model_aabb.get_center()
	var standing_y: float = centre.y
	var lying_y: float = _model_aabb.size.x * 0.5 - sink_m
	var roll: float = deg_to_rad(lying_roll_degrees) * _lie
	var sway: float = deg_to_rad(sway_degrees) * sin(_stride_phase * PI) * _trot_share()
	var basis := Basis(Vector3.BACK, roll + sway)
	var middle_y: float = lerpf(standing_y, lying_y, _lie) + _step_lift(_stride_phase, _trot_share())
	var breath: float = 1.0 + breath_scale * sin(_breath_phase * TAU) * _lie
	basis = basis * Basis.from_scale(Vector3(breath, breath, 1.0))
	_pose.transform = Transform3D(basis, Vector3(0.0, middle_y, 0.0) - basis * centre)

# The step's lift at `phase` (strides), at `share` of a full trot.
func _step_lift(phase: float, share: float) -> float:
	return absf(sin(phase * PI)) * bob_m * share

func _trot_share() -> float:
	return clampf(_speed_now / maxf(follow_speed, 0.01), 0.0, 1.0)

func _apply_yaw(extra: float) -> void:
	rotation = Vector3(0.0, deg_to_rad(lying_yaw_degrees + _placement_yaw) + extra, 0.0)

# --- The hollow ---

func _spawn_damp() -> void:
	_damp = Decal.new()
	_damp.name = "DampPatch"
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.55, Color(1.0, 1.0, 1.0, 0.8))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 128
	texture.height = 128
	_damp.texture_albedo = texture
	_damp.cull_mask = 0xFFFFF & ~PUP_LAYER
	_damp.top_level = true
	add_child(_damp)
	_apply_damp()

func _apply_damp() -> void:
	if _damp == null:
		return
	_damp.size = Vector3(damp_size_m.x, maxf(damp_depth_m, 0.01) * 2.0, damp_size_m.y)
	_damp.global_transform = _lying_transform * Transform3D(Basis.IDENTITY, Vector3(damp_offset_m.x, 0.0, damp_offset_m.y))
	_damp.modulate = damp_color
	_damp.albedo_mix = 1.0
	_damp.normal_fade = damp_normal_fade

# A box round it lying, so he walks round it and the brush keeps off it
# (FieldScatter excludes static footprints). MAKE_STATIC, the trough's
# reason. Gone once it stands - it walks with him then.
func _spawn_collision() -> void:
	if _model_aabb.size == Vector3.ZERO:
		return
	_collision_body = StaticBody3D.new()
	_collision_body.name = "Collision"
	_collision_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	var box := BoxShape3D.new()
	var height: float = maxf(_model_aabb.size.x - sink_m, 0.1)
	box.size = Vector3(_model_aabb.size.y, height, _model_aabb.size.z)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, height * 0.5, _model_aabb.get_center().z)
	_collision_body.add_child(shape)
	add_child(_collision_body)

func _ground_to_relief() -> void:
	if _ground == null:
		return
	global_position.y = _height_at(global_position.x, global_position.z)

func _height_at(x: float, z: float) -> float:
	if _ground == null:
		return global_position.y
	var local_xz: Vector3 = _ground.to_local(Vector3(x, 0.0, z))
	return _ground.get_height_at(Vector2(local_xz.x, local_xz.z))

# --- The walk-up and the choice ---

func _spawn_approach() -> void:
	_approach = PropApproach.new()
	_approach.name = "Approach"
	_approach.warning_label = "DunecurPup"
	_approach.can_speak = func() -> bool: return _state == State.LYING
	_approach.on_visit = _on_visit
	_approach.can_open_from = can_open_from
	_approach.screen_rect = get_screen_rect
	_approach.open_requested.connect(_on_open_requested)
	add_child(_approach)
	_apply_approach_radius()

# Where its own lines sit: over its model's top, line_clearance_m up.
func _line_offset() -> Vector3:
	return Vector3.UP * (_model_aabb.size.y + line_clearance_m)

func _apply_approach_radius() -> void:
	if _approach != null:
		_approach.set_radius(approach_radius)

func _on_visit() -> void:
	var remedy: bool = find_remedy() != null
	_approach.say_near(find_line, hold_seconds, fade_seconds, self, _line_offset())
	if not _found_logged:
		_found_logged = true
		RunLogger.event("pup", {"outcome": "found", "has_remedy": remedy})

# The card it would be given: the deck's first tagged remedy_tag that can
# still be tempered (a plain one), else its first tempered one. Null with
# none in the deck.
func find_remedy() -> CardData:
	var tempered: CardData = null
	for card in RunState.deck:
		if card == null or not card.has_tag(remedy_tag):
			continue
		if card.tempered != null:
			return card
		if tempered == null:
			tempered = card
	return tempered

func can_open_from(from: Vector3) -> bool:
	if _state != State.LYING:
		return false
	var offset := Vector3(from.x - global_position.x, 0.0, from.z - global_position.z)
	return offset.length() <= approach_radius

func _on_open_requested() -> void:
	if _choice != null and is_instance_valid(_choice):
		return
	var region_field := _region_field()
	var hud: Node = region_field.get_node_or_null(^"FieldHUD") if region_field != null else null
	if hud == null:
		push_warning("DunecurPup '%s': FieldHUD not found; no choice." % name)
		return
	var scene := load(CHOICE_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("DunecurPup '%s': could not load %s; no choice." % [name, CHOICE_SCENE_PATH])
		return
	_choice = scene.instantiate() as Control
	_choice.call("setup", self, region_field.wanderer, region_field)
	hud.add_child(_choice)

# TroughChoice's items: the giving and the leaving, always both.
func get_choice_labels() -> Array[String]:
	return [give_text, leave_text]

# TroughChoice's gate: the giving is on offer only with a remedy in the
# deck; leaving always is.
func is_choice_enabled(index: int) -> bool:
	return index != 0 or find_remedy() != null

# TroughChoice's pick: the last item leaves it.
func choose(index: int) -> void:
	var remedy: bool = find_remedy() != null
	if index == 0 and remedy:
		give_remedy()
	elif index != 0:
		RunLogger.event("pup", {"outcome": "left", "has_remedy": remedy})

# One remedy out of the deck, the line, and up it gets.
func give_remedy() -> void:
	var card: CardData = find_remedy()
	if card == null or _state != State.LYING:
		return
	RunState.remove_card(card)
	RunLogger.event("pup", {"outcome": "remedy_given", "card": card.card_name})
	if _approach != null:
		_approach.mark_said()
		_approach.say_near(saved_line, hold_seconds, fade_seconds, self, _line_offset())
	_state = State.RISING
	if _collision_body != null:
		_collision_body.queue_free()
		_collision_body = null
	var wanderer := _wanderer()
	_trail.clear()
	_walked.clear()
	if wanderer != null:
		_trail.append(_flat(wanderer.global_position))

func is_saved() -> bool:
	return _state == State.RISING or _state == State.FOLLOWING or _state == State.REUNITING

func is_following() -> bool:
	return _state == State.FOLLOWING

# Whether he reaching `enemy` now is the meeting: it follows, the enemy is
# its adult's, and it isn't too far back.
func can_reunite_with(enemy: FieldEnemy) -> bool:
	if _state != State.FOLLOWING or enemy == null or enemy.slot_id != reunite_slot or enemy.is_defeated():
		return false
	return _trail_length() <= reunite_max_distance_m

# The model's lying bbox on screen, grown by padding_px.
func get_screen_rect(camera: Camera3D, padding_px: float) -> Rect2:
	if camera == null or _pose == null or _model_aabb.size == Vector3.ZERO:
		return Rect2()
	# _model_aabb is in Pose's space (the grounding shift is the model's
	# own position under it), so Pose carries it to the world, lie and all.
	var to_world: Transform3D = _pose.global_transform
	var rect := Rect2()
	for i in 8:
		var corner: Vector3 = to_world * _model_aabb.get_endpoint(i)
		if camera.is_position_behind(corner):
			return Rect2()
		var point: Vector2 = camera.unproject_position(corner)
		rect = Rect2(point, Vector2.ZERO) if i == 0 else rect.expand(point)
	return rect.grow(padding_px)

# --- The tick (through the fight's freeze) ---

func _on_physics_frame() -> void:
	if not is_inside_tree():
		return
	var delta: float = get_physics_process_delta_time()
	_breath_phase = fposmod(_breath_phase + delta * breath_hz, 1.0)
	match _state:
		State.RISING:
			_lie = maxf(_lie - delta / maxf(rise_seconds, 0.01), 0.0)
			_record_trail()
			if _lie <= 0.0:
				_state = State.FOLLOWING
		State.FOLLOWING:
			_record_trail()
			var region_field := _region_field()
			if region_field != null and region_field.is_battle_open():
				_tick_retreat(delta)
			else:
				_tick_follow(delta)
		State.REUNITING:
			_tick_meeting(delta)
	_apply_pose()

func _flat(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)

func _here() -> Vector3:
	return _flat(global_position)

# His position onto the trail, every trail_step_m he moves.
func _record_trail() -> void:
	var wanderer := _wanderer()
	if wanderer == null:
		return
	var at: Vector3 = _flat(wanderer.global_position)
	if not _trail.is_empty():
		var last: Vector3 = _trail.back()
		if last.distance_to(at) < trail_step_m:
			return
	_trail.append(at)

# Along the trail from here to him, metres.
func _trail_length() -> float:
	var wanderer := _wanderer()
	var length: float = 0.0
	var from: Vector3 = _here()
	for point in _trail:
		length += from.distance_to(point)
		from = point
	if wanderer != null:
		length += from.distance_to(_flat(wanderer.global_position))
	return length

func _tick_follow(delta: float) -> void:
	var wanderer := _wanderer()
	if wanderer == null:
		_speed_now = 0.0
		return
	# Points already reached go behind it.
	while not _trail.is_empty() and _here().distance_to(_trail[0]) < trail_step_m * 0.5:
		var reached: Vector3 = _trail.pop_front()
		_walked.append(reached)
	_trim_walked()
	var slack: float = _trail_length() - follow_distance_m
	if slack <= 0.0:
		_speed_now = move_toward(_speed_now, 0.0, follow_speed * 4.0 * delta)
		_face_toward(_flat(wanderer.global_position), delta)
		return
	var target: Vector3 = _trail[0] if not _trail.is_empty() else _flat(wanderer.global_position)
	var speed: float = follow_speed * (1.0 + catch_up_boost * clampf(slack / maxf(catch_up_m, 0.01), 0.0, 1.0))
	_speed_now = move_toward(_speed_now, speed, follow_speed * 4.0 * delta)
	_step_toward(target, minf(_speed_now * delta, slack), delta)

# A fight is open: back along the way it came until battle_wait_distance_m
# from him, the points it backs over put on the trail again in front.
func _tick_retreat(delta: float) -> void:
	var wanderer := _wanderer()
	if wanderer == null:
		return
	var him: Vector3 = _flat(wanderer.global_position)
	if _here().distance_to(him) >= battle_wait_distance_m:
		_speed_now = move_toward(_speed_now, 0.0, retreat_speed * 4.0 * delta)
		_face_toward(him, delta)
		return
	var target: Vector3
	if not _walked.is_empty():
		target = _walked.back()
		if _here().distance_to(target) < trail_step_m * 0.5:
			var backed: Vector3 = _walked.pop_back()
			_trail.push_front(backed)
			return
	else:
		var away: Vector3 = _here() - him
		target = _here() + (away.normalized() if away.length() > 0.01 else -global_transform.basis.z) * trail_step_m
	_speed_now = move_toward(_speed_now, retreat_speed, retreat_speed * 4.0 * delta)
	_step_toward(target, _speed_now * delta, delta)

func _trim_walked() -> void:
	var limit: int = int(ceilf(walked_keep_m / maxf(trail_step_m, 0.05)))
	while _walked.size() > limit:
		_walked.pop_front()

# `distance` toward `target` on the ground, turning to face the way it
# goes; the stride counted.
func _step_toward(target: Vector3, distance: float, delta: float) -> void:
	var to_target: Vector3 = target - _here()
	if to_target.length() < 0.0001 or distance <= 0.0:
		return
	var step: Vector3 = to_target.normalized() * minf(distance, to_target.length())
	var next: Vector3 = _here() + step
	global_position = Vector3(next.x, _height_at(next.x, next.z), next.z)
	_stride_phase = fposmod(_stride_phase + step.length() * strides_per_m, 2.0)
	_face_toward(target, delta)

func _face_toward(point: Vector3, delta: float) -> void:
	var to_point: Vector3 = point - _here()
	if to_point.length() < 0.05:
		return
	var angle: float = atan2(-to_point.x, -to_point.z)
	rotation.y = rotate_toward(rotation.y, angle, turn_speed * delta)

# --- The meeting ---

# RegionField._try_reunion(): the meeting starts. The adult's crest up and
# it turns to the pup; the pup sets off to it.
func reunite(adult: FieldEnemy) -> void:
	_adult = adult
	_state = State.REUNITING
	_meet = Meet.TROT
	_meet_time = 0.0
	_released = false
	_unseen_for = 0.0
	adult.set_alert(adult_alarm_stacks)
	adult.face_toward_point(global_position, adult_turn_seconds)
	var from_adult: Vector3 = _here() - _flat(adult.global_position)
	if from_adult.length() < 0.01:
		from_adult = Vector3.BACK
	_meet_spot = _flat(adult.global_position) + from_adult.normalized() * reunite_gap_m
	var wanderer := _wanderer()
	var away: Vector3 = _flat(adult.global_position) - (_flat(wanderer.global_position) if wanderer != null else _here())
	if away.length() < 0.01:
		away = -adult.global_transform.basis.z
	_away = away.normalized().rotated(Vector3.UP, deg_to_rad(walk_off_turn_degrees))

func _tick_meeting(delta: float) -> void:
	_meet_time += delta
	if not _released and _meet_time >= reunion_hold_seconds:
		_released = true
		reunion_released.emit(_adult)
	if _adult == null or not is_instance_valid(_adult):
		_finish_meeting()
		return
	match _meet:
		Meet.TROT:
			_speed_now = move_toward(_speed_now, reunite_speed, reunite_speed * 4.0 * delta)
			_step_toward(_meet_spot, _speed_now * delta, delta)
			if _here().distance_to(_meet_spot) < 0.1:
				_meet = Meet.GREET
				_meet_time_mark = _meet_time
				_speed_now = 0.0
				_adult.set_alert(0)
				_say_reunion()
		Meet.GREET:
			_face_toward(_flat(_adult.global_position), delta)
			if _meet_time - _meet_time_mark >= greet_seconds:
				_meet = Meet.WALK
				_adult.face_toward_point(_adult.global_position + _away * 5.0, adult_turn_seconds)
		Meet.WALK:
			_tick_walk_off(delta)

func _say_reunion() -> void:
	if reunion_line.is_empty() or _adult == null:
		return
	var region_field := _region_field()
	var line := WorldVoiceLine.on_hud(region_field.get_node_or_null(^"FieldHUD") if region_field != null else null)
	if line == null:
		return
	line.fade_in_seconds = fade_seconds
	line.fade_out_seconds = fade_seconds
	line.show_line_near(reunion_line, reunion_line_seconds, _adult, Vector3.UP * (_adult.get_head_height() + 0.6))

# Both along _away at walk_off_speed, the pup a little behind and beside
# the adult, each with its step; gone once neither is in the camera's
# view, or after walk_off_max_seconds.
func _tick_walk_off(delta: float) -> void:
	var adult_step: float = walk_off_speed * delta
	var next: Vector3 = _flat(_adult.global_position) + _away * adult_step
	_adult_stride_phase = fposmod(_adult_stride_phase + adult_step * strides_per_m * 0.6, 2.0)
	_adult.walk_to_xz(next.x, next.z, _step_lift(_adult_stride_phase, 1.0) * 1.6)
	var side: Vector3 = _away.cross(Vector3.UP).normalized()
	if side.dot(_here() - next) < 0.0:
		side = -side
	var spot: Vector3 = next + side * walk_off_side_m - _away * 0.4
	_speed_now = minf(walk_off_speed * 1.6, follow_speed)
	_step_toward(spot, minf(_speed_now * delta, _here().distance_to(spot)), delta)
	_face_toward(_here() + _away, delta)
	var camera := get_viewport().get_camera_3d()
	var seen: bool = camera != null and (_in_view(camera, _adult.global_position) or _in_view(camera, global_position))
	_unseen_for = 0.0 if seen else _unseen_for + delta
	if _unseen_for >= 0.3 or _meet_time >= walk_off_max_seconds:
		_finish_meeting()

func _in_view(camera: Camera3D, point: Vector3) -> bool:
	return camera.is_position_in_frustum(point + Vector3.UP * 0.5)

func _finish_meeting() -> void:
	if _state == State.GONE:
		return
	_state = State.GONE
	if not _released:
		_released = true
		reunion_released.emit(_adult)
	walked_off.emit(_adult)
	queue_free()

# pup_id if the spawner set one; else the floor's path and this node's
# name.
func _pup_id() -> String:
	if not pup_id.is_empty():
		return pup_id
	var region_field := _region_field()
	var floor_data: FloorData = region_field.get_floor_data() if region_field != null else null
	return "%s:%s" % [floor_data.resource_path if floor_data != null else "", name]
