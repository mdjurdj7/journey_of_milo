extends SceneTree

# Renders the Siltjaw's intent display - the charge and its threshold
# gauge - as three PNG stills, from the live data (battle/rules/enemies/
# siltjaw.tres through EnemyTurn.preview_intent(), the same dictionary
# the overlay hands BattleIntent): nothing dealt yet, half the threshold
# dealt, and the threshold met (gauge full, attack pair dimmed). On the
# pale-world value set of the real BattleTheme, over a flat sand ground,
# magnified so the strokes can be judged.
#
# Needs a renderer, so not --headless (the dummy renderer draws nothing):
#
#   Godot_v4.7.1.exe --path . -s res://tests/intent_gauge_stills.gd -- --out=<dir>
#
# A window opens for the second or two it takes; the frames come from an
# offscreen SubViewport, not the window.
#
# Writes intent_gauge_1_empty.png, _2_mid.png, _3_full.png into <dir>
# (default user://intent_gauge_stills). Exit code 0 = all three written.
# BattleIntent is reached through load()/call() only: it names FieldEnemy,
# which names RunState, and a script typed against it here compiles before
# the autoloads register (see kill_order_probe.gd's own note).

const SILTJAW_PATH := "res://battle/rules/enemies/siltjaw.tres"
const THEME_PATH := "res://ui/battle_theme.tres"
const BATTLE_INTENT_PATH := "res://battle/battle_intent.gd"
const FRAME_SIZE := Vector2i(420, 420)
const MAGNIFY := 3.0
const GROUND_COLOR := Color(0.86, 0.82, 0.72)
const PLAYER_HP := 70
const SAFETY_SECONDS := 30.0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	var out_dir: String = "user://intent_gauge_stills"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)

	# Its own fixed-size viewport, so the project's window stretch settings
	# never touch the frame.
	var viewport := SubViewport.new()
	viewport.size = FRAME_SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var theme := load(THEME_PATH) as BattleTheme
	theme.apply_value_set(false)
	var stage := Control.new()
	stage.theme = theme
	stage.size = Vector2(FRAME_SIZE)
	viewport.add_child(stage)
	var ground := ColorRect.new()
	ground.color = GROUND_COLOR
	ground.size = Vector2(FRAME_SIZE)
	stage.add_child(ground)
	var intent: Control = (load(BATTLE_INTENT_PATH) as GDScript).new()
	stage.add_child(intent)
	await process_frame
	intent.scale = Vector2(MAGNIFY, MAGNIFY)
	intent.call("set_revealed", true)

	var data := load(SILTJAW_PATH) as EnemyData
	var siltjaw := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(siltjaw, data)
	var player := Combatant.new(PLAYER_HP)
	var threshold: int = EnemyTurn.current_intent(siltjaw, data).interrupt_threshold
	var frames: Array[Dictionary] = [
		{"name": "intent_gauge_1_empty.png", "dealt": 0},
		{"name": "intent_gauge_2_mid.png", "dealt": threshold / 2},
		{"name": "intent_gauge_3_full.png", "dealt": threshold},
	]
	var written: int = 0
	for frame in frames:
		siltjaw.damage_taken_this_turn = int(frame["dealt"])
		var preview: Dictionary = EnemyTurn.preview_intent(siltjaw, data, player)
		intent.call("show_intent", preview)
		# Centred in the frame. BattleIntent scales about its own centre
		# (pivot_offset = size / 2), so the magnification doesn't move it.
		intent.position = ((Vector2(FRAME_SIZE) - intent.size) * 0.5).round()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String = out_dir.path_join(String(frame["name"]))
		var image: Image = viewport.get_texture().get_image()
		if image != null and image.save_png(path) == OK:
			written += 1
			print("wrote %s (dealt %d of %d, numeral %s, interrupted %s)" % [path, int(frame["dealt"]), threshold, str(preview.get("threshold_left")), str(preview.get("interrupted"))])
		else:
			print("FAIL: couldn't write ", path)
	quit(0 if written == frames.size() else 1)
