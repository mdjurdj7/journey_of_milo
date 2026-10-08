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
#
# With --glyphs it renders every intent glyph instead: two sheets, one
# row per intent type (a single attack, a multi-hit one, a threshold one,
# then each other EnemyIntent type) and one column per state (normal,
# dimmed - interrupted - and lethal), from hand-made previews in
# EnemyTurn.preview_intent()'s shape. intent_glyphs_3x.png is magnified
# GLYPH_MAGNIFY times, intent_glyphs_1x.png is at the game's own size.
# The spearhead points right: there is no Wanderer here to point at.
#
#   Godot_v4.7.1.exe --path . -s res://tests/intent_gauge_stills.gd -- --glyphs --out=<dir>
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
# The --glyphs sheets: each display centred in a cell this big at 1x,
# with its row's and column's name in the cell's corner.
const GLYPH_MAGNIFY := 3.0
const GLYPH_CELL := Vector2(120.0, 130.0)
const GLYPH_STATES: Array[String] = ["normal", "dimmed", "lethal"]

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
	if OS.get_cmdline_user_args().has("--glyphs"):
		var sheets: int = 0
		for magnify: float in [GLYPH_MAGNIFY, 1.0]:
			if await _render_glyph_sheet(out_dir.path_join("intent_glyphs_%dx.png" % int(magnify)), magnify):
				sheets += 1
		quit(0 if sheets == 2 else 1)
		return

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
	# It opens on Snap, which can't be broken - the gauge is the Charge's,
	# so step the loop on to it.
	while EnemyTurn.current_intent(siltjaw, data).interrupt_threshold <= 0:
		siltjaw.current_intent_index += 1
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

# The --glyphs rows: a name and the preview each state starts from.
func _glyph_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		{"name": "attack", "preview": {"type": EnemyIntent.IntentType.ATTACK, "per_hit": 5}},
		{"name": "multi-hit", "preview": {"type": EnemyIntent.IntentType.ATTACK, "hits": 3, "per_hit": 4}},
		{"name": "threshold", "preview": {"type": EnemyIntent.IntentType.ATTACK, "per_hit": 20, "threshold": 16, "threshold_left": 9}},
		{"name": "defend", "preview": {"type": EnemyIntent.IntentType.DEFEND, "per_hit": 6}},
		{"name": "burrow", "preview": {"type": EnemyIntent.IntentType.BURROW}},
		{"name": "heal_ally", "preview": {"type": EnemyIntent.IntentType.HEAL_ALLY, "per_hit": 3}},
		{"name": "watch", "preview": {"type": EnemyIntent.IntentType.WATCH}},
		{"name": "settle", "preview": {"type": EnemyIntent.IntentType.SETTLE}},
	]
	return rows

# One sheet: a fresh viewport of the grid's size, one BattleIntent per
# cell, scaled about its centre by `magnify`. True once written.
func _render_glyph_sheet(path: String, magnify: float) -> bool:
	var rows: Array[Dictionary] = _glyph_rows()
	var cell: Vector2 = GLYPH_CELL * magnify
	var frame := Vector2i(int(cell.x) * GLYPH_STATES.size(), int(cell.y) * rows.size())
	var viewport := SubViewport.new()
	viewport.size = frame
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var theme := load(THEME_PATH) as BattleTheme
	theme.apply_value_set(false)
	var stage := Control.new()
	stage.theme = theme
	stage.size = Vector2(frame)
	viewport.add_child(stage)
	var ground := ColorRect.new()
	ground.color = GROUND_COLOR
	ground.size = Vector2(frame)
	stage.add_child(ground)
	var placed: Array[Dictionary] = []
	for row in rows.size():
		for column in GLYPH_STATES.size():
			var preview: Dictionary = (rows[row]["preview"] as Dictionary).duplicate()
			match GLYPH_STATES[column]:
				"dimmed":
					preview["interrupted"] = true
				"lethal":
					preview["lethal"] = true
			var intent: Control = (load(BATTLE_INTENT_PATH) as GDScript).new()
			stage.add_child(intent)
			var tag := Label.new()
			tag.text = "%s / %s" % [String(rows[row]["name"]), GLYPH_STATES[column]]
			tag.position = Vector2(cell.x * float(column), cell.y * float(row)) + Vector2(4.0, 2.0)
			tag.add_theme_font_size_override("font_size", 12)
			tag.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 0.5))
			stage.add_child(tag)
			placed.append({"intent": intent, "preview": preview, "centre": Vector2(cell.x * (float(column) + 0.5), cell.y * (float(row) + 0.5))})
	await process_frame
	for entry in placed:
		var intent: Control = entry["intent"]
		intent.call("set_revealed", true)
		intent.call("show_intent", entry["preview"])
		intent.scale = Vector2(magnify, magnify)
		intent.position = (Vector2(entry["centre"]) - intent.size * 0.5).round()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	viewport.queue_free()
	if image != null and image.save_png(path) == OK:
		print("wrote %s (%d intent types x %d states)" % [path, rows.size(), GLYPH_STATES.size()])
		return true
	print("FAIL: couldn't write ", path)
	return false
