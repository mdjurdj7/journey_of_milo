extends SceneTree

# Headless probe for the enemies' share of the field's depth fog: every
# enemy body's material is out of the environment fog and ends its pass
# chain in an enemy_fog.gdshader overlay carrying RegionSky's fog and
# RegionField.enemy_fog_factor (0.4) - re-pushed live when the factor or
# the sky's fog depth changes, and replaced by an EnemyData.fog_factor_
# override >= 0. The dragonfly's wings get overlays that keep their alpha
# cut-out; the Blackback's sac pass stays on the chain, under the fog.
# Scenery (the Ground) keeps the environment fog.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/enemy_fog_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Untyped against anything that names the RunState autoload (RegionField,
# FieldEnemy): a SceneTree script compiles before the autoloads register.

const CASES := 3
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FOG_SHADER_PATH := "res://field/enemy_fog.gdshader"
const SPUTTER_FLOOR := 0
const DRAGONFLY_FLOOR := 1
const BLACKBACK_FLOOR := 2
const SAFETY_SECONDS := 180.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	await _check_sputter()
	await _check_dragonfly_wings()
	await _check_blackback_chain()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("enemy_fog_probe: PASSED")
		quit(0)
	else:
		print("enemy_fog_probe: %d FAILED" % _failures)
		quit(1)

# Floor 1's Sputter: out of the environment fog, the overlay last on its
# chain with the sky's fog and the 0.4 share; a factor edit, a fog-depth
# edit and a per-enemy override all reach it live.
func _check_sputter() -> void:
	await _load_field(SPUTTER_FLOOR)
	var enemy: Node = _first_enemy()
	if enemy == null:
		_fail("Floor 1 has an enemy")
		await _teardown()
		_completed += 1
		return
	var body := enemy.get("_model_material") as BaseMaterial3D
	_expect(body != null and body.disable_fog, "The Sputter's body material is out of the environment fog")
	var overlay: ShaderMaterial = _fog_tail(body)
	_expect(overlay != null, "...and ends its pass chain in the fog overlay")
	if overlay == null:
		await _teardown()
		_completed += 1
		return
	var sky: Node = _field.call("get_region_sky")
	_expect_near(float(overlay.get_shader_parameter("fog_factor")), 0.4, "...at the field's 0.4 share")
	_expect_near(float(overlay.get_shader_parameter("fog_begin")), float(sky.get("fog_depth_begin")), "...from the sky's fog_depth_begin")
	_expect_near(float(overlay.get_shader_parameter("fog_end")), float(sky.get("fog_depth_end")), "...to its fog_depth_end")
	_expect_eq(overlay.get_shader_parameter("fog_color"), sky.get("fog_color"), "...in its fog colour")
	_expect(not bool(overlay.get_shader_parameter("use_alpha_texture")), "...no alpha cut-out on an opaque body")

	_field.set("enemy_fog_factor", 0.7)
	_expect_near(float(overlay.get_shader_parameter("fog_factor")), 0.7, "An enemy_fog_factor edit reaches it live (0.7)")
	_field.set("enemy_fog_factor", 0.4)
	sky.set("fog_depth_begin", 20.0)
	sky.set("fog_depth_end", 40.0)
	_expect_near(float(overlay.get_shader_parameter("fog_begin")), 20.0, "A fog-depth edit on the sky reaches it live (begin 20)")
	_expect_near(float(overlay.get_shader_parameter("fog_end")), 40.0, "...(end 40)")

	var data: Resource = enemy.get("enemy_data")
	data.set("fog_factor_override", 0.0)
	_expect_near(float(overlay.get_shader_parameter("fog_factor")), 0.0, "EnemyData.fog_factor_override 0 wins over the field's 0.4")
	data.set("fog_factor_override", -1.0)
	_expect_near(float(overlay.get_shader_parameter("fog_factor")), 0.4, "...and -1 hands it back to the field's")

	var ground := _field.get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
	if ground != null:
		var ground_material := ground.get_active_material(0) as Material
		_expect(not (ground_material is BaseMaterial3D and (ground_material as BaseMaterial3D).disable_fog), "The ground keeps the environment fog")
	await _teardown()
	_completed += 1

# Floor 2's dragonflies: each wing material out of the environment fog
# with an overlay that keeps the wing's alpha cut-out.
func _check_dragonfly_wings() -> void:
	await _load_field(DRAGONFLY_FLOOR)
	var checked: int = 0
	for enemy: Node in _field.get_tree().get_nodes_in_group("enemies"):
		var attachment: Node = enemy.get("_attachment")
		if attachment == null or not attachment.has_method("get_tint_materials"):
			continue
		var wings: Array[BaseMaterial3D] = attachment.call("get_tint_materials")
		for wing in wings:
			checked += 1
			var overlay: ShaderMaterial = _fog_tail(wing)
			_expect(wing.disable_fog and overlay != null, "A wing material is out of the fog with its own overlay")
			if overlay == null:
				continue
			_expect(bool(overlay.get_shader_parameter("use_alpha_texture")), "...cutting out where the wing does")
			_expect_eq(overlay.get_shader_parameter("alpha_texture"), wing.albedo_texture, "...from the wing's own texture")
			_expect_near(float(overlay.get_shader_parameter("fog_factor")), 0.4, "...at the field's 0.4 share")
	_expect(checked > 0, "Floor 2 has dragonfly wings to check (%d)" % checked)
	await _teardown()
	_completed += 1

# Floor 3's Blackback: the Stork's sac pass stays on the body's chain,
# with the fog overlay after it, last.
func _check_blackback_chain() -> void:
	await _load_field(BLACKBACK_FLOOR)
	var found: bool = false
	for enemy: Node in _field.get_tree().get_nodes_in_group("enemies"):
		var body := enemy.get("_model_material") as BaseMaterial3D
		if body == null or body.next_pass == null or _is_fog(body.next_pass):
			continue
		found = true
		_expect(_fog_tail(body) != null, "A pose's own pass on the body (%s) is followed by the fog overlay" % (body.next_pass as ShaderMaterial).shader.resource_path)
	_expect(found, "Floor 3 has a body with its own pass before the fog")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _is_fog(material: Material) -> bool:
	var shader_material := material as ShaderMaterial
	return shader_material != null and shader_material.shader != null and shader_material.shader.resource_path == FOG_SHADER_PATH

# The last pass on `material`'s chain, when it is the fog overlay.
func _fog_tail(material: Material) -> ShaderMaterial:
	var tail: Material = material
	while tail.next_pass != null:
		tail = tail.next_pass
	return tail as ShaderMaterial if _is_fog(tail) else null

func _first_enemy() -> Node:
	var enemies: Array[Node] = _field.get_tree().get_nodes_in_group("enemies")
	return enemies[0] if not enemies.is_empty() else null

func _load_field(floor_index: int) -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", floor_index)
	# No zone intro: it holds the field frozen for its length.
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 5:
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, actual, expected])

func _expect_near(actual: float, expected: float, message: String) -> void:
	if absf(actual - expected) > 0.001:
		_fail("%s - got %.3f, expected %.3f" % [message, actual, expected])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: " + message)
