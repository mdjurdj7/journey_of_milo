extends SceneTree

# Headless probe for the enemies' share of the field's depth fog: every
# enemy body's material is out of the environment fog and ends its pass
# chain in an enemy_fog.gdshader overlay carrying RegionSky's fog and
# RegionField.enemy_fog_factor (0.4) - re-pushed live when the factor or
# the sky's fog depth changes, and replaced by an EnemyData.fog_factor_
# override >= 0. The dragonfly's wings get overlays that keep their alpha
# cut-out; the Blackback's sac pass stays on the chain, under the fog.
# Every pass on every enemy mesh - body, pose passes (the Greyshelf's
# throat, the Stork's sac), wings, overlays - has scene fog disabled, so
# the overlay is the only fog on an enemy. Scenery (the Ground) keeps the
# environment fog.
#
# The steady-state fog has one source, RegionSky's exports: after a floor
# load the Environment's depth fog and the Sea's own copy equal them (a
# floor's own pair where it names one); an edit to them shows at once and
# stays; the zone intro's override shows instead while it runs, leaves
# the exports alone, and on finishing hands back to the exports as they
# stand - an edit made under it included.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/enemy_fog_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Untyped against anything that names the RunState autoload (RegionField,
# FieldEnemy): a SceneTree script compiles before the autoloads register.

const CASES := 6
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FOG_SHADER_PATH := "res://field/enemy_fog.gdshader"
const SPUTTER_FLOOR := 0
const DRAGONFLY_FLOOR := 1
const BLACKBACK_FLOOR := 2
const GREYSHELF_FLOOR := 4
# Floor 4 names its own depth fog (20 / 40 in region1_floor4.tres).
const OWN_FOG_FLOOR := 3
const THROAT_SHADER_PATH := "res://field/greyshelf_throat.gdshader"
const SAC_SHADER_PATH := "res://field/stork_sac.gdshader"
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
	await _check_every_pass_unfogged()
	await _check_steady_state_fog(SPUTTER_FLOOR)
	await _check_steady_state_fog(OWN_FOG_FLOOR)
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

# Floors 1, 2, 3 and 5 (Sputter, dragonflies, Blackback, Greyshelf):
# every material pass on every mesh under each enemy model has scene fog
# off - disable_fog on a BaseMaterial3D, fog_disabled in a shader's
# render_mode - with the throat and sac passes among those checked.
func _check_every_pass_unfogged() -> void:
	var seen_shaders: Dictionary = {}
	var checked: int = 0
	for floor_index: int in [SPUTTER_FLOOR, DRAGONFLY_FLOOR, BLACKBACK_FLOOR, GREYSHELF_FLOOR]:
		await _load_field(floor_index)
		for enemy: Node in _field.get_tree().get_nodes_in_group("enemies"):
			var model := enemy.get("_model") as Node3D
			if model == null:
				continue
			for node in model.find_children("*", "MeshInstance3D", true, false):
				var mesh_instance := node as MeshInstance3D
				if mesh_instance.mesh == null:
					continue
				for surface in mesh_instance.mesh.get_surface_count():
					var pass_material: Material = mesh_instance.get_active_material(surface)
					while pass_material != null:
						checked += 1
						var shader_material := pass_material as ShaderMaterial
						if shader_material != null and shader_material.shader != null:
							seen_shaders[shader_material.shader.resource_path] = true
						_expect(_fog_off(pass_material), "Floor %d, %s: a pass on %s (%s) has scene fog disabled" % [floor_index + 1, (enemy.get("enemy_data") as Resource).resource_path.get_file(), mesh_instance.name, _describe(pass_material)])
						pass_material = pass_material.next_pass
		await _teardown()
	_expect(checked > 0, "Enemy passes were checked (%d)" % checked)
	_expect(seen_shaders.has(THROAT_SHADER_PATH), "...the Greyshelf's throat pass among them")
	_expect(seen_shaders.has(SAC_SHADER_PATH), "...the Stork's sac pass among them")
	_completed += 1

# --- Helpers ---

func _fog_off(material: Material) -> bool:
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).disable_fog
	var shader_material := material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return false
	var render_mode := RegEx.create_from_string("render_mode[^;]*[\\s,]fog_disabled[\\s,;]")
	return render_mode.search(shader_material.shader.code) != null

func _describe(material: Material) -> String:
	var shader_material := material as ShaderMaterial
	if shader_material != null and shader_material.shader != null:
		return shader_material.shader.resource_path
	return material.get_class()

func _is_fog(material: Material) -> bool:
	var shader_material := material as ShaderMaterial
	return shader_material != null and shader_material.shader != null and shader_material.shader.resource_path == FOG_SHADER_PATH

# The last pass on `material`'s chain, when it is the fog overlay.
func _fog_tail(material: Material) -> ShaderMaterial:
	var tail: Material = material
	while tail.next_pass != null:
		tail = tail.next_pass
	return tail as ShaderMaterial if _is_fog(tail) else null

# The one source: a floor load, a live edit, and the zone intro's override.
func _check_steady_state_fog(floor_index: int) -> void:
	await _load_field(floor_index)
	var label: String = "Floor %d" % (floor_index + 1)
	var sky: Node = _field.call("get_region_sky")
	var sea: Node = _field.get_node_or_null("Sea")
	var environment: Environment = sky.get("environment")
	var floor_data: Resource = _field.call("get_floor_data")
	var own_begin: float = float(floor_data.get("fog_depth_begin"))
	var own_end: float = float(floor_data.get("fog_depth_end"))
	if own_begin > 0.0 and own_end > own_begin:
		_expect_near(float(sky.get("fog_depth_begin")), own_begin, "%s: the floor's own fog begin on RegionSky" % label)
		_expect_near(float(sky.get("fog_depth_end")), own_end, "%s: ...and its end" % label)
	_expect_fog_is(environment, sea, float(sky.get("fog_depth_begin")), float(sky.get("fog_depth_end")), "%s: after load" % label)

	# A Remote-tab edit: on screen at once, and still there later.
	sky.set("fog_depth_begin", 30.0)
	sky.set("fog_depth_end", 50.0)
	_expect_fog_is(environment, sea, 30.0, 50.0, "%s: an edit to RegionSky" % label)
	for i in 10:
		await process_frame
	_expect_fog_is(environment, sea, 30.0, 50.0, "%s: ...still there ten frames on" % label)

	# The zone intro: its override on screen, the exports untouched; an
	# edit under it is where it lands.
	var intro: Node = _field.get_node_or_null("ZoneIntro")
	if intro != null and bool(intro.call("play")):
		for i in 3:
			await process_frame
		_expect(bool(sky.call("has_fog_override")), "%s: the intro borrows the fog through the override" % label)
		_expect(not is_equal_approx(environment.fog_depth_begin, 30.0), "%s: ...its fog on screen, not the region's" % label)
		_expect_near(float(sky.get("fog_depth_begin")), 30.0, "%s: ...the region's begin left alone" % label)
		sky.set("fog_depth_begin", 24.0)
		_expect(not is_equal_approx(environment.fog_depth_begin, 24.0), "%s: an edit under the intro waits for it" % label)
		intro.call("_finish")
		_expect(not bool(sky.call("has_fog_override")), "%s: the intro's finish clears the override" % label)
		_expect_fog_is(environment, sea, 24.0, 50.0, "%s: ...landing on the region's fog as edited under it" % label)
	else:
		_fail("%s: the zone intro would not play" % label)
	await _teardown()
	_completed += 1

func _expect_fog_is(environment: Environment, sea: Node, begin: float, end: float, label: String) -> void:
	_expect_near(environment.fog_depth_begin, begin, "%s: the Environment's fog begin" % label)
	_expect_near(environment.fog_depth_end, end, "%s: the Environment's fog end" % label)
	if sea != null:
		_expect_near(float(sea.get("fog_near_distance")), begin, "%s: the Sea's fog near" % label)
		_expect_near(float(sea.get("fog_far_distance")), end, "%s: the Sea's fog far" % label)

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
