extends Control
class_name HPBar

# The player's own HP readout, floating just under the Wanderer's feet in
# both field and battle (one persistent instance, living in FieldHUD -
# see region_field.gd's own set_target() call). Repositioned every physics
# tick via unproject, the same shape EnemyStatus already uses for enemies
# (see that script's own doc). In the field the bar's top centre sits
# field_offset_px straight down the screen from the Wanderer's feet, at a
# constant screen size; in battle the HP numeral's baseline, centred on
# the HP block, sits on his feet plus ground_offset (a world-space drop)
# at battle_scale, so the Battle Style's pixel sizes are what actually
# lands on screen - kept min_energy_clearance_px off the energy readout.
#
# Two styles, blended over the battle transition time rather than
# snapped, both drawn by _draw() below: field (the Field Style group - a
# bare ink bar with a Spectral numeral and " / max" centred beneath it,
# ink straight on the world) and battle
# (the Battle Style group - ink on the world: a Spectral
# numeral row - block's shield and value while any is up, the HP numeral,
# " / max" - on one baseline, a 3px ink bar beneath over an ink track,
# the standing row under it, and - while show_toll() has it on - a Toll
# block off the bar's right end: a Spectral numeral with "TOLL" beside it
# on one baseline and a rule in the toll keyline colour beneath, sitting
# on the HP bar's own rows; nothing boxed). The two cross-fade: the field
# drawing fades out as the battle drawing fades in, and this control's
# own size eases between the two layouts' sizes; the HP block stays
# centred on the anchor in both, with Toll hanging off to the right (see
# _anchor_offset()). See enter_battle()/exit_battle() and _battle_blend's
# own doc.
#
# Reads RunState.player_hp/player_max_hp directly and updates on RunState.
# player_hp_changed - the only HP source this bar ever reads, in field or
# battle alike. Block is battle-only, pushed by BattleOverlay on the
# controller's status_changed (see set_block()); so is Toll, shown by
# show_toll()/update_toll() and taken off by hide_toll() (BattleOverlay's
# enter/finish), with a short pop of the numeral on every change.
#
# Field visibility (see HoverFadeVisibility): hidden by default, fades in
# on mouse hover over the Wanderer or on any HP change (held briefly, then
# faded back out), stays visible below low_hp_fraction, and is always
# fully visible in battle (see enter_battle()/exit_battle()).

# The battle style's anchor: the Wanderer's feet plus this world-space
# drop (the field style's is field_offset_px). Read every tick.
@export var ground_offset: Vector3 = Vector3(0.0, -0.45, 0.0)
@export var bar_tween_time: float = 0.25
@export var fade_time: float = 0.15
@export var hp_change_hold_time: float = 1.5
@export_range(0.0, 1.0) var low_hp_fraction: float = 0.3

# The field readout: the bar on top, the numeral row centred under it -
# current HP in Spectral at field_numeral_size_px in full ink, " / max"
# in the battle style's smaller secondary ink (battle_max_size_px at
# battle_secondary_alpha) - ink on the world, no halo (field_halo_px 0; a
# positive value puts a bone halo under both runs' ink, as the Block
# readout's value has). The bar is ink over the battle bar's track
# (battle_track_alpha). Pixel sizes at 1080p, never scaled by distance.
@export_group("Field Style")
@export var field_numeral_size_px: int = 20:
	set(value):
		field_numeral_size_px = value
		_relayout_if_ready()
@export var field_halo_px: float = 0.0:
	set(value):
		field_halo_px = value
		_relayout_if_ready()
@export var field_halo_color: Color = Color(0.94, 0.91, 0.86, 1.0):
	set(value):
		field_halo_color = value
		queue_redraw()
@export var field_bar_width: float = 90.0:
	set(value):
		field_bar_width = value
		_relayout_if_ready()
@export var field_bar_height: float = 3.0:
	set(value):
		field_bar_height = value
		_relayout_if_ready()
# Between the bar's bottom and the numeral row's ascent.
@export var field_row_gap_px: float = 4.0:
	set(value):
		field_row_gap_px = value
		_relayout_if_ready()
# How far down the screen from the Wanderer's feet the bar's top centre
# sits - clear of his contact shadow. 20 is where the old world-space drop
# (0.45 m under the feet, ~33 px at the field camera's 13 m) put the
# bar's top at scale 1.0.
@export var field_offset_px: float = 20.0:
	set(value):
		field_offset_px = value
		_relayout_if_ready()

@export_group("Battle Style")
# The readout's width - numeral row and bar alike.
@export var battle_width: float = 190.0:
	set(value):
		battle_width = value
		_relayout_if_ready()
@export var numeral_font: Font = load("res://assets/fonts/Spectral-SemiBold.ttf"):
	set(value):
		numeral_font = value
		_relayout_if_ready()
# The TOLL label's face (toll_label_size_px, toll_label_tracking_em).
@export var name_font: Font = load("res://assets/fonts/AlegreyaSans-Bold.ttf"):
	set(value):
		name_font = value
		_restyle_if_ready()
# The HP numeral - the readout's largest figure, over Toll's
# (toll_numeral_size_px) - and the " / max" after it, small.
@export var battle_numeral_size_px: int = 34:
	set(value):
		battle_numeral_size_px = value
		_relayout_if_ready()
@export var battle_max_size_px: int = 14:
	set(value):
		battle_max_size_px = value
		_relayout_if_ready()
# " / max", ink at this alpha; the numeral is full ink.
@export_range(0.0, 1.0) var battle_secondary_alpha: float = 0.6:
	set(value):
		battle_secondary_alpha = value
		queue_redraw()
@export var battle_max_prefix: String = " / ":
	set(value):
		battle_max_prefix = value
		_relayout_if_ready()
# Row gap between the numeral row's descent and the bar's top.
@export var battle_row_gap: float = 6.0:
	set(value):
		battle_row_gap = value
		_relayout_if_ready()
@export var battle_bar_height: float = 3.0:
	set(value):
		battle_bar_height = value
		_relayout_if_ready()
@export_range(0.0, 1.0) var battle_track_alpha: float = 0.22:
	set(value):
		battle_track_alpha = value
		queue_redraw()
# Grace (the Wanderer's passive - see CharacterData): HP an enemy took
# that is still reclaimable this turn, drawn INSIDE the bar immediately
# right of the filled HP, in ink at grace_alpha - part of the bar,
# because it is literally the stretch of HP you could still get back. No
# numeral: the HP numeral keeps reading current HP, which is what you
# have.
@export_range(0.0, 1.0) var grace_alpha: float = 0.3:
	set(value):
		grace_alpha = value
		queue_redraw()
# The battle energy readout's right edge on screen (set_energy_clearance_
# x(), from BattleOverlay): the HP numeral's left edge - the HP block's,
# where a block readout spills leftward from - never comes closer to it
# than this. The readout rides with the Wanderer otherwise; this only
# pushes it right when the two would crowd. Today's gap in the Sputter
# fight, so it never fires there.
@export var min_energy_clearance_px: float = 170.0:
	set(value):
		min_energy_clearance_px = value
		_relayout_if_ready()

# --- The standing row: stance first, then statuses ---
#
# The player's first status display of any kind. Enemies have had one
# since the start (EnemyStatus); the player's own Braced has been
# applying and expiring invisibly. Built as the general row rather than
# as a stance widget, so a status only has to exist to be shown.
#
# One line per live effect, top to bottom, in the order BattleOverlay
# hands them over (the stance, then the powers and statuses, then the
# counters). A stance shows its own glyph and name; a status its label;
# a counter its n/m with a progress hairline under it; a spent once-per-
# combat effect stays as a line at row_spent_alpha. No rules text at
# rest - hovering one line reveals what that one does.
@export_group("Standing Row")
@export var row_font_size_px: int = 10:
	set(value):
		row_font_size_px = value
		_refresh_row_font()
@export_range(0.0, 1.0) var row_tracking_em: float = 0.16:
	set(value):
		row_tracking_em = value
		_refresh_row_font()
@export_range(0.0, 1.0) var row_alpha: float = 0.7:
	set(value):
		row_alpha = value
		queue_redraw()
@export var row_gap_px: float = 6.0:
	set(value):
		row_gap_px = value
		_relayout_if_ready()
# Between one line's descent and the next line's ascent.
@export var row_line_gap_px: float = 5.0:
	set(value):
		row_line_gap_px = value
		_relayout_if_ready()
# A spent guard's line ink (Refuse the End fired) - grey, still there.
@export_range(0.0, 1.0) var row_spent_alpha: float = 0.32:
	set(value):
		row_spent_alpha = value
		queue_redraw()
# A counter line's progress: a hairline the readout's width this far under
# its text, the track at battle_track_alpha (the HP track's), filled to
# n/m in the line's ink.
@export var counter_hairline_gap_px: float = 3.0:
	set(value):
		counter_hairline_gap_px = value
		_relayout_if_ready()
@export var counter_hairline_px: float = 1.0:
	set(value):
		counter_hairline_px = value
		_relayout_if_ready()
@export var row_glyph_size_px: float = 9.0:
	set(value):
		row_glyph_size_px = value
		queue_redraw()
@export var row_glyph_gap_px: float = 5.0:
	set(value):
		row_glyph_gap_px = value
		queue_redraw()
@export var row_glyph_line_width_px: float = 1.3:
	set(value):
		row_glyph_line_width_px = value
		queue_redraw()
# The drop (Venom's mark) is solid ink in the battle UI's pen (InkPen):
# drop_width of row_glyph_size_px across its round end, a bone outline
# this wide round it - 0, as the row's lines have none - and the pen's
# antialiased edge.
@export_range(0.2, 1.0) var row_drop_width: float = 0.72:
	set(value):
		row_drop_width = value
		queue_redraw()
@export var row_drop_outline_px: float = 0.0:
	set(value):
		row_drop_outline_px = value
		queue_redraw()
@export var row_drop_edge_px: float = 1.0:
	set(value):
		row_drop_edge_px = value
		queue_redraw()

@export_group("Status Reveal")
# Hovering one line of the standing row in battle shows what that one
# effect does, this far under the whole readout and wrapped at
# battle_width, fading in and out over reveal_fade_time, ink at
# reveal_line_alpha, in the card's rules type at reveal_font_size_px (the
# faces are StatusReveal's - see the "StatusReveal" child's doc). When
# that would leave less than min_hand_clearance_px above the resting hand
# (set_hand_top_y()), it goes to the readout's LEFT instead: right-
# aligned, ending side_gap_px short of the readout's left edge, top-
# aligned with the hovered line - never above, over the Wanderer.
@export var reveal_gap_px: float = 6.0:
	set(value):
		reveal_gap_px = value
		if is_node_ready():
			_apply_layout()
@export var reveal_fade_time: float = 0.12:
	set(value):
		reveal_fade_time = value
		if _reveal != null:
			_reveal.set_fade_time(value)
@export_range(0.0, 1.0) var reveal_line_alpha: float = 0.92:
	set(value):
		reveal_line_alpha = value
		if _reveal != null:
			_reveal.set_line_alpha(value)
@export var reveal_font_size_px: int = 13:
	set(value):
		reveal_font_size_px = value
		if _reveal != null:
			_reveal.set_font_size_px(value)
# Line pitch in ems, as CardView.keyword_reveal_line_height.
@export var reveal_line_height: float = 1.28:
	set(value):
		reveal_line_height = value
		if _reveal != null:
			_reveal.set_line_height(value)
# Extra space between two entries, on top of the line pitch.
@export var reveal_entry_gap_px: float = 4.0:
	set(value):
		reveal_entry_gap_px = value
		if _reveal != null:
			_reveal.set_entry_gap_px(value)
@export var min_hand_clearance_px: float = 8.0:
	set(value):
		min_hand_clearance_px = value
		_place_reveal()
@export var side_gap_px: float = 12.0:
	set(value):
		side_gap_px = value
		_place_reveal()
@export_group("")
@export var battle_scale: float = 1.0

@export_group("Critical")
# While the Wanderer is Critical (Combatant.critical_at(), read with the
# character's own critical_hp_fraction - the fight's rule, not a copy),
# the HP numeral and the bar's fill turn this colour, in both styles -
# the field's numeral with them. Everything else on the
# readout stays ink. Eased over critical_fade_time on a crossing either
# way; no pulse, no glow.
@export var critical_color: Color = Color(0.46, 0.14, 0.13):
	set(value):
		critical_color = value
		_apply_critical_colors()
# A hairline across the bar at the Critical line, shown at every HP, in
# the track's ink at this alpha. It overhangs the bar by critical_tick_
# overhang_px above and below, so it still reads where the fill covers it.
@export_range(0.0, 1.0) var critical_tick_alpha: float = 0.5:
	set(value):
		critical_tick_alpha = value
		_apply_critical_colors()
@export var critical_tick_overhang_px: float = 2.0:
	set(value):
		critical_tick_overhang_px = value
		if is_node_ready():
			_apply_layout()
# Read at each crossing, so an edit takes on the next one.
@export var critical_fade_time: float = 0.2:
	set(value):
		critical_fade_time = maxf(value, 0.0)

@export_group("Block Readout")
# While block is up it reads in the HP row, LEFT of the HP numeral: the
# card's open-shield glyph, then the block value beside it in Spectral at
# the HP numeral's own size, full ink, on the same baseline. Hidden at 0.
# The readout grows leftward for it - the HP block stays put on the
# anchor.
#
# The shield's size: its height is ~1.85 x half of this.
@export var block_glyph_size_px: float = 28.0:
	set(value):
		block_glyph_size_px = value
		_relayout_block()
# The intent glyphs' stroke (BattleIntent.glyph_line_width_px).
@export var block_glyph_line_width_px: float = 3.5:
	set(value):
		block_glyph_line_width_px = value
		_relayout_block()
# The shield's centre sits this fraction of the HP numeral's size above
# the HP baseline - level with the numeral's cap centre.
@export var block_glyph_baseline_lift: float = 0.33:
	set(value):
		block_glyph_baseline_lift = value
		_relayout_block()
# The value's size; 0 = the HP numeral's (battle_numeral_size_px).
@export var block_value_size_px: int = 0:
	set(value):
		block_value_size_px = value
		_relayout_block()
# Between the shield and the value after it.
@export var block_glyph_value_gap_px: float = 6.0:
	set(value):
		block_glyph_value_gap_px = value
		_relayout_block()
# The shield's ink alpha; the value is always full ink.
@export_range(0.0, 1.0) var block_readout_alpha: float = 0.7:
	set(value):
		block_readout_alpha = value
		_relayout_block()
# Between the block value and the HP numeral.
@export var block_hp_gap_px: float = 16.0:
	set(value):
		block_hp_gap_px = value
		_relayout_block()
# A changed value crossfades from the old over this long.
@export var block_crossfade_time: float = 0.12

@export_group("Toll")
@export var toll_label_text: String = "TOLL":
	set(value):
		toll_label_text = value
		_relayout_if_ready()
# Under the HP numeral (battle_numeral_size_px), so the two read apart.
@export var toll_numeral_size_px: int = 22:
	set(value):
		toll_numeral_size_px = value
		_relayout_if_ready()
@export var toll_label_size_px: int = 10:
	set(value):
		toll_label_size_px = value
		_restyle_if_ready()
@export var toll_label_tracking_em: float = 0.16:
	set(value):
		toll_label_tracking_em = value
		_restyle_if_ready()
# Space between the HP bar's right end and the block - what keeps the HP
# row and Toll two clusters - between numeral and label, and between the
# numeral's baseline and the rule's top. The rule is toll_rule_px thick
# and sits on the HP bar's own rows (same top).
@export var toll_gap_px: float = 22.0:
	set(value):
		toll_gap_px = value
		_relayout_if_ready()
@export var toll_label_gap_px: float = 6.0:
	set(value):
		toll_label_gap_px = value
		_relayout_if_ready()
@export var toll_rule_gap_px: float = 4.0:
	set(value):
		toll_rule_gap_px = value
		_relayout_if_ready()
@export var toll_rule_px: float = 3.0:
	set(value):
		toll_rule_px = value
		queue_redraw()
@export var toll_pop_scale: float = 1.15
@export var toll_pop_time: float = 0.22
# A Toll blow's count down from the Toll it spent (drain_toll()), in real
# seconds - it runs through the hit-stop.
@export var toll_drain_time: float = 0.25

var _wanderer: Wanderer = null
# The battle energy readout's right edge on screen (set_energy_clearance_
# x()), NAN out of battle.
var _energy_right_x: float = NAN
var _current_hp: int = 0
var _max_hp: int = 1
var _block: int = 0
# The value fading out under a crossfade (0: none), and how far the new
# one has faded in (1: done) - see set_block().
var _block_prev: int = 0
var _block_fade: float = 1.0
var _block_tween: Tween = null
var _grace: int = 0
# The row's contents, as flat display data rather than rules objects -
# this node never reaches into a Stance or a Status, it is handed what to
# draw. Each entry - see set_standing_row().
var _row_items: Array[Dictionary] = []
var _row_font_tracked: Font = null
# What the hovered line's entry does - see _update_reveal().
var _reveal: StatusReveal = null
# The row line under the cursor, or -1.
var _hovered_line: int = -1
# The resting hand's top edge in canvas pixels, or < 0 unknown (always
# under the readout then) - see set_hand_top_y().
var _hand_top_y: float = -1.0
var _toll: int = 0
var _toll_visible: bool = false
var _toll_pop: float = 1.0
var _pop_tween: Tween = null
var _drain_tween: Tween = null
var _toll_rule_color: Color = Color.WHITE
var _toll_label_tracked: Font = null
var _current_fraction: float = 1.0
var _displayed_fraction: float = 1.0
var _fraction_tween: Tween = null
var _in_battle: bool = false
var _visibility: HoverFadeVisibility = null
# Cached theme ink/bone (see refresh_style()).
var _ink: Color = Color.BLACK
# Critical now (see _refresh_critical()), and how far the numeral and
# fill have eased toward critical_color: 0 ink, 1 critical_color.
var _critical: bool = false
var _critical_blend: float = 0.0
var _critical_tween: Tween = null

# 0 = field style, 1 = battle style. Tweened by enter_battle()/exit_battle()
# over the battle transition time (passed in by BattleOverlay, which reads
# it off CameraRig - see BattleOverlay.enter_battle()'s own doc), not
# snapped, so the style change reads as part of the same transition as
# the camera swing and the Wanderer's stance step rather than a separate,
# independent pop. Every relayout (_apply_layout()) reads this fresh, so
# a mid-transition HP change (its own independent _displayed_fraction
# tween - see that var's own doc) composes correctly instead of the two
# tweens fighting over the fill's width.
var _battle_blend: float = 0.0
var _blend_tween: Tween = null

func _ready() -> void:
	# FieldHUD (this panel's parent) already sets PROCESS_MODE_ALWAYS, so
	# this is inherited already - set explicitly anyway so _physics_process()
	# below is guaranteed to keep tracking the Wanderer through RegionField's
	# own battle-contact freeze (including the stance-tween-in step)
	# regardless of where this node ever ends up parented.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# CameraRig has no explicit priority of its own (default 0), and neither
	# does Wanderer - this only has to beat that default to guarantee both
	# have already moved/repositioned the camera THIS physics tick before
	# _physics_process() below reads either one; without it, whichever of
	# the three happened to run first each tick was a coin flip, and a bar
	# reading a not-yet-updated camera is exactly what read as jitter.
	process_physics_priority = 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_visibility = HoverFadeVisibility.new(self, fade_time, hp_change_hold_time)

	RunState.player_hp_changed.connect(_on_player_hp_changed)
	_current_hp = RunState.player_hp
	_max_hp = RunState.player_max_hp
	_current_fraction = _hp_fraction(_current_hp, _max_hp)
	_displayed_fraction = _current_fraction
	# Arrives already in the right colour - a run that loads Critical
	# doesn't fade into it.
	_critical = _is_critical()
	_critical_blend = 1.0 if _critical else 0.0

	_reveal = StatusReveal.new()
	_reveal.name = "StatusReveal"
	_reveal.set_fade_time(reveal_fade_time)
	_reveal.set_line_alpha(reveal_line_alpha)
	_reveal.set_font_size_px(reveal_font_size_px)
	_reveal.set_line_height(reveal_line_height)
	_reveal.set_entry_gap_px(reveal_entry_gap_px)
	add_child(_reveal)

	_apply_layout()
	refresh_style()

# --- Field layout (drawn) ---

func _field_numeral_ascent() -> float:
	return numeral_font.get_ascent(field_numeral_size_px) if numeral_font != null else float(field_numeral_size_px)

func _field_numeral_descent() -> float:
	return numeral_font.get_descent(field_numeral_size_px) if numeral_font != null else 0.0

# The numeral row's width: current HP, then " / max" at the battle
# style's smaller size.
func _field_row_width() -> float:
	return InkType.width(numeral_font, str(_current_hp), field_numeral_size_px) + InkType.width(numeral_font, battle_max_prefix + str(_max_hp), battle_max_size_px)

# The bar or the row with its halo either side, whichever is wider; the
# bar, the gap, and the row with its halo under the descent.
func _field_content_size() -> Vector2:
	var halo: float = maxf(field_halo_px, 0.0)
	var width: float = maxf(field_bar_width, _field_row_width() + halo * 2.0)
	return Vector2(width, field_bar_height + field_row_gap_px + _field_numeral_ascent() + _field_numeral_descent() + halo)

# The bar's top centre - what sits field_offset_px under the feet.
func _field_anchor() -> Vector2:
	return Vector2(roundf(_field_content_size().x * 0.5), 0.0)

# Bar on top, the row centred under it: the halo (when it has one) under
# both runs first, then the ink. The numeral and the fill take the Critical blend; the
# tick overhangs the bar as the battle style's does. `alpha` is the
# field style's share of the cross-fade.
func _draw_field(alpha: float) -> void:
	var ink: Color = _ink
	ink.a = alpha
	var hp_ink: Color = ink.lerp(Color(critical_color, ink.a), _critical_blend)
	var secondary: Color = _ink
	secondary.a = battle_secondary_alpha * alpha
	var track: Color = _ink
	track.a = battle_track_alpha * alpha

	var width: float = _field_content_size().x
	var bar_left: float = roundf((width - field_bar_width) * 0.5)
	draw_rect(Rect2(bar_left, 0.0, field_bar_width, field_bar_height), track)
	draw_rect(Rect2(bar_left, 0.0, field_bar_width * _displayed_fraction, field_bar_height), hp_ink)
	var tick_color: Color = _ink
	tick_color.a = critical_tick_alpha * alpha
	var tick_x: float = roundf(bar_left + field_bar_width * _critical_fraction())
	draw_rect(Rect2(tick_x, -critical_tick_overhang_px, 1.0, field_bar_height + critical_tick_overhang_px * 2.0), tick_color)

	var numeral_text: String = str(_current_hp)
	var max_text: String = battle_max_prefix + str(_max_hp)
	var left: float = roundf((width - _field_row_width()) * 0.5)
	var baseline: float = field_bar_height + field_row_gap_px + _field_numeral_ascent()
	var max_left: float = left + InkType.width(numeral_font, numeral_text, field_numeral_size_px)
	if field_halo_px > 0.0:
		var halo: Color = field_halo_color
		halo.a *= alpha
		var halo_size: int = roundi(field_halo_px * 2.0)
		draw_string_outline(numeral_font, Vector2(left, baseline), numeral_text, HORIZONTAL_ALIGNMENT_LEFT, -1, field_numeral_size_px, halo_size, halo)
		draw_string_outline(numeral_font, Vector2(max_left, baseline), max_text, HORIZONTAL_ALIGNMENT_LEFT, -1, battle_max_size_px, halo_size, halo)
	InkType.draw_run(self, numeral_font, numeral_text, Vector2(left, baseline), field_numeral_size_px, hp_ink)
	InkType.draw_run(self, numeral_font, max_text, Vector2(max_left, baseline), battle_max_size_px, secondary)

# --- Battle layout (drawn) ---

func _numeral_ascent() -> float:
	return numeral_font.get_ascent(battle_numeral_size_px) if numeral_font != null else float(battle_numeral_size_px)

func _numeral_descent() -> float:
	return numeral_font.get_descent(battle_numeral_size_px) if numeral_font != null else 0.0

func _toll_ascent() -> float:
	return numeral_font.get_ascent(toll_numeral_size_px) if numeral_font != null else float(toll_numeral_size_px)

func _toll_block_width() -> float:
	return InkType.width(numeral_font, str(_toll), toll_numeral_size_px) + toll_label_gap_px + InkType.width(_toll_label_tracked, toll_label_text, toll_label_size_px)

# The Toll numeral is taller than the HP row above the bar; whatever it
# needs beyond that pushes the whole battle drawing down by this much so
# nothing pokes above the control.
func _battle_top_pad() -> float:
	if not _toll_visible:
		return 0.0
	var hp_rows: float = _numeral_ascent() + _numeral_descent() + battle_row_gap
	return maxf(0.0, _toll_ascent() + toll_rule_gap_px - hp_rows)

func _battle_bar_top() -> float:
	return _battle_top_pad() + _numeral_ascent() + _numeral_descent() + battle_row_gap

# The block readout's width including its gap to the HP numeral - the
# HP block's own left edge; 0 while no block is up.
func _block_readout_width() -> float:
	if _block <= 0:
		return 0.0
	return _block_group_width() + block_hp_gap_px

# The group's own width: the shield, its gap, and the value - the wider
# of the value and the one fading out while a crossfade runs, so neither
# ever reaches toward the HP numeral.
func _block_group_width() -> float:
	var value_width: float = _block_value_width(_block)
	if _block_prev > 0 and _block_fade < 1.0:
		value_width = maxf(value_width, _block_value_width(_block_prev))
	return block_glyph_size_px + block_glyph_value_gap_px + value_width

# The value's size: block_value_size_px, or the HP numeral's.
func _block_value_size() -> int:
	return block_value_size_px if block_value_size_px > 0 else battle_numeral_size_px

func _block_value_width(value: int) -> float:
	return InkType.width(numeral_font, str(value), _block_value_size())

# Shield glyph (the card's guard glyph, CardView._draw_glyph()) at the
# group's left, level with the HP numeral's cap centre, at block_readout_
# alpha; the value after it on the HP baseline - the one fading out under
# the new one while a crossfade runs.
func _draw_block_readout(baseline: float, ink: Color) -> void:
	if _block <= 0:
		return
	var color: Color = ink
	color.a *= block_readout_alpha
	var r: float = block_glyph_size_px * 0.5
	var centre := Vector2(r, baseline - float(battle_numeral_size_px) * block_glyph_baseline_lift)
	var shield := PackedVector2Array([
		centre + Vector2(-r * 0.8, -r * 0.9), centre + Vector2(r * 0.8, -r * 0.9), centre + Vector2(r * 0.8, r * 0.1),
		centre + Vector2(0.0, r * 0.95), centre + Vector2(-r * 0.8, r * 0.1), centre + Vector2(-r * 0.8, -r * 0.9),
	])
	draw_polyline(shield, color, block_glyph_line_width_px, true)
	var value_left: float = block_glyph_size_px + block_glyph_value_gap_px
	if _block_prev > 0 and _block_fade < 1.0:
		_draw_block_value(_block_prev, Vector2(value_left, baseline), ink, 1.0 - _block_fade)
	_draw_block_value(_block, Vector2(value_left, baseline), ink, _block_fade)

# One value, its baseline-left at `origin`, at `alpha`.
func _draw_block_value(value: int, origin: Vector2, ink: Color, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var fill: Color = ink
	fill.a *= alpha
	InkType.draw_run(self, numeral_font, str(value), origin, _block_value_size(), fill)

func _relayout_block() -> void:
	if is_node_ready():
		_apply_layout()

func _battle_content_size() -> Vector2:
	var width: float = _block_readout_width() + battle_width
	if _toll_visible:
		width += toll_gap_px + _toll_block_width()
	return Vector2(width, _row_top() + _row_height())

func _row_top() -> float:
	return _battle_bar_top() + battle_bar_height + row_gap_px

func _line_text_height() -> float:
	return _row_font_tracked.get_height(row_font_size_px) if _row_font_tracked != null else float(row_font_size_px)

# One line's own height: its text, and a counter's hairline under it.
func _line_height(item: Dictionary) -> float:
	var height: float = _line_text_height()
	if int(item.get("count", 0)) > 0:
		height += counter_hairline_gap_px + counter_hairline_px
	return height

# Every line and the gaps between them. With none, minus row_gap_px -
# nothing reserved under the bar.
func _row_height() -> float:
	if _row_items.is_empty():
		return -row_gap_px
	var height: float = 0.0
	for item: Dictionary in _row_items:
		height += _line_height(item)
	return height + row_line_gap_px * float(_row_items.size() - 1)

# Each line's band, readout-wide, half a line gap above and below so the
# bands meet and the cursor never falls between two lines.
func _line_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var y: float = _row_top()
	var left: float = _block_readout_width()
	for item: Dictionary in _row_items:
		var height: float = _line_height(item)
		rects.append(Rect2(left, y - row_line_gap_px * 0.5, battle_width, height + row_line_gap_px))
		y += height + row_line_gap_px
	return rects

# The point of this control that sits on the screen anchor (and that
# battle_scale scales about): the field bar's top centre, or in battle
# the HP block's centre on the HP numeral's baseline - Toll hangs off to
# the right of it, never shifting the bar off the Wanderer, and the
# standing row grows downward from under the bar, so a line coming or
# going never moves the numeral or the bar.
func _anchor_offset() -> Vector2:
	var battle_offset := Vector2(_block_readout_width() + battle_width / 2.0, _battle_top_pad() + _numeral_ascent())
	return _field_anchor().lerp(battle_offset, _battle_blend)

# This control's size eases between the two layouts' sizes with the
# blend (see the class doc) - pivot_offset centres scale on the anchor
# rather than the top-left corner. Re-run on every _battle_blend/
# _displayed_fraction tween step (see their own doc), not just once.
func _apply_layout() -> void:
	var content_size: Vector2 = _field_content_size().lerp(_battle_content_size(), _battle_blend)
	size = content_size
	pivot_offset = _anchor_offset()

	if _reveal != null:
		_reveal.set_wrap_width(battle_width)
		_place_reveal()

	queue_redraw()

# Where a standing row's bottom sits in canvas pixels, whether or not one
# is up yet - for BattleOverlay's one-shot clearance print, which runs
# before any stance or status lands.
func get_status_row_bottom_y() -> float:
	var bottom: float = _row_top() + _row_height()
	if _row_items.is_empty():
		bottom += row_gap_px + _line_text_height()
	return (get_global_transform() * Vector2(0.0, bottom)).y

# Which row line the cursor is on, or -1 - polled, never a mouse event,
# so the targeting raycast underneath gets every click. A card or button
# under the cursor wins.
func _line_under_mouse() -> int:
	if get_viewport().gui_get_hovered_control() != null:
		return -1
	var mouse: Vector2 = get_local_mouse_position()
	var rects: Array[Rect2] = _line_rects()
	for i in rects.size():
		if rects[i].has_point(mouse):
			return i
	return -1

# The field readout fading out under the battle readout fading in.
func _draw() -> void:
	if numeral_font == null:
		return
	if _battle_blend < 1.0:
		_draw_field(1.0 - _battle_blend)
	if _battle_blend > 0.0:
		_draw_battle()

# The battle readout, at _battle_blend alpha.
# One baseline for the row: block (shield and value, while any is up),
# the numeral, then " / max" run on at its smaller size. The bar sits
# battle_row_gap under the numeral's descent.
func _draw_battle() -> void:
	var ink: Color = _ink
	ink.a = _battle_blend
	var secondary: Color = _ink
	secondary.a = battle_secondary_alpha * _battle_blend
	var track: Color = _ink
	track.a = battle_track_alpha * _battle_blend

	# The numeral and the fill only: ink eased toward critical_color.
	var hp_ink: Color = ink.lerp(Color(critical_color, ink.a), _critical_blend)

	var baseline: float = _battle_top_pad() + _numeral_ascent()
	_draw_block_readout(baseline, ink)
	var left: float = _block_readout_width()
	var x: float = left + InkType.draw_run(self, numeral_font, str(_current_hp), Vector2(left, baseline), battle_numeral_size_px, hp_ink)
	InkType.draw_run(self, numeral_font, battle_max_prefix + str(_max_hp), Vector2(x, baseline), battle_max_size_px, secondary)

	var bar_top: float = _battle_bar_top()
	draw_rect(Rect2(left, bar_top, battle_width, battle_bar_height), track)
	draw_rect(Rect2(left, bar_top, battle_width * _displayed_fraction, battle_bar_height), hp_ink)
	# The Critical line, after the fill, overhanging the bar.
	var tick_color: Color = _ink
	tick_color.a = critical_tick_alpha * _battle_blend
	var tick_x: float = roundf(left + battle_width * _critical_fraction())
	draw_rect(Rect2(tick_x, bar_top - critical_tick_overhang_px, 1.0, battle_bar_height + critical_tick_overhang_px * 2.0), tick_color)

	# Pinned to _displayed_fraction, so it stays welded to the filled end
	# while the bar eases toward a new HP value rather than briefly
	# overlapping or detaching from it.
	if _grace > 0 and _max_hp > 0:
		var grace_left: float = left + battle_width * _displayed_fraction
		var grace_length: float = battle_width * clampf(float(_grace) / float(_max_hp), 0.0, 1.0)
		# Never past the bar's own right end, however much is open.
		grace_length = minf(grace_length, left + battle_width - grace_left)
		if grace_length > 0.0:
			var grace_color: Color = _ink
			grace_color.a = grace_alpha * _battle_blend
			draw_rect(Rect2(grace_left, bar_top, grace_length, battle_bar_height), grace_color)

	if _toll_visible:
		_draw_toll(bar_top, ink)

	_draw_standing_row(bar_top + battle_bar_height + row_gap_px, left)

# The Toll block, off the bar's right end: numeral and "TOLL" on one
# baseline toll_rule_gap_px above the rule, the rule on the bar's rows,
# as wide as the block. The numeral pops about its baseline-left corner
# on a change so the label and rule hold still.
# One line per entry, top to bottom under the bar. Nothing at all when
# empty - no label, no placeholder, no reserved gap.
func _draw_standing_row(top: float, left: float) -> void:
	if _row_items.is_empty() or _row_font_tracked == null:
		return
	var ascent: float = _row_font_tracked.get_ascent(row_font_size_px)
	var y: float = top
	for item: Dictionary in _row_items:
		var color: Color = _ink
		color.a = (row_spent_alpha if item.get("spent", false) else row_alpha) * _battle_blend
		var baseline: float = y + ascent
		var x: float = left
		var glyph: StringName = item.get("glyph", &"")
		if glyph == &"stance":
			_draw_stance_glyph(Vector2(x, baseline - ascent * 0.5), color)
			x += row_glyph_size_px + row_glyph_gap_px
		elif glyph == &"drop":
			_draw_drop_glyph(Vector2(x + row_glyph_size_px * 0.5, baseline - ascent * 0.5), color.a)
			x += row_glyph_size_px + row_glyph_gap_px
		InkType.draw_run(self, _row_font_tracked, String(item.get("text", "")), Vector2(x, baseline), row_font_size_px, color)
		var count: int = int(item.get("count", 0))
		if count > 0:
			var fraction: float = float(int(item.get("progress", 0))) / float(count)
			_draw_counter_hairline(y + _line_text_height() + counter_hairline_gap_px, left, fraction, color)
		y += _line_height(item) + row_line_gap_px

# The readout-wide progress hairline under a counter line: the track at
# the HP track's alpha, filled to `fraction` in the line's ink.
func _draw_counter_hairline(top: float, left: float, fraction: float, color: Color) -> void:
	var track: Color = _ink
	track.a = battle_track_alpha * _battle_blend
	draw_rect(Rect2(left, top, battle_width, counter_hairline_px), track)
	var filled: float = battle_width * clampf(fraction, 0.0, 1.0)
	if filled > 0.0:
		draw_rect(Rect2(left, top, filled, counter_hairline_px), color)

# The stance mark: a ring with a bite out of its lower right - a thing
# consuming itself. Drawn rather than authored so it scales with the row
# and needs no texture; one shape for every stance, since what makes them
# different is the name beside it.
func _draw_stance_glyph(centre: Vector2, color: Color) -> void:
	var r: float = row_glyph_size_px * 0.5
	var points: PackedVector2Array = PackedVector2Array()
	var steps: int = 18
	for i in steps + 1:
		# Open between 300 and 30 degrees - the bite.
		var t: float = 30.0 + 270.0 * float(i) / float(steps)
		points.append(centre + Vector2(cos(deg_to_rad(t)), sin(deg_to_rad(t))) * r)
	draw_polyline(points, color, row_glyph_line_width_px, true)

# Venom's mark: a drop, point up and its round end down, row_glyph_size_px
# tall about `centre` - one solid shape in the tapered pen's ink (InkPen.
# draw_ink()), at the line's alpha.
func _draw_drop_glyph(centre: Vector2, alpha: float) -> void:
	var r: float = row_glyph_size_px * 0.5
	var half_width: float = r * row_drop_width
	var drop := PackedVector2Array()
	var steps: int = 24
	for i in steps:
		# The teardrop x = sin t sin(t/2), y = -cos t: pointed at t = 0 (the
		# top), round through t = PI (the bottom).
		var t: float = TAU * float(i) / float(steps)
		drop.append(centre + Vector2(half_width * sin(t) * sin(t * 0.5), -r * cos(t)))
	var shapes: Array[PackedVector2Array] = [drop]
	InkPen.draw_ink(self, shapes, _ink, get_theme_color("bone", "Battle"), row_drop_outline_px, row_drop_edge_px, alpha)

func _draw_toll(bar_top: float, ink: Color) -> void:
	var left: float = _block_readout_width() + battle_width + toll_gap_px
	var baseline: float = bar_top - toll_rule_gap_px
	var numeral_text: String = str(_toll)
	var numeral_width: float = InkType.width(numeral_font, numeral_text, toll_numeral_size_px)
	if _toll_pop != 1.0:
		draw_set_transform(Vector2(left, baseline), 0.0, Vector2.ONE * _toll_pop)
		InkType.draw_run(self, numeral_font, numeral_text, Vector2.ZERO, toll_numeral_size_px, ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		InkType.draw_run(self, numeral_font, numeral_text, Vector2(left, baseline), toll_numeral_size_px, ink)
	InkType.draw_run(self, _toll_label_tracked, toll_label_text, Vector2(left + numeral_width + toll_label_gap_px, baseline), toll_label_size_px, ink)
	var rule_color: Color = _toll_rule_color
	rule_color.a = _battle_blend
	draw_rect(Rect2(left, bar_top, _toll_block_width(), toll_rule_px), rule_color)

# Called once by region_field.gd - the Wanderer this bar tracks. Safe to
# call before or after _ready(); _physics_process() below just no-ops
# until it's set.
func set_target(wanderer: Wanderer) -> void:
	_wanderer = wanderer

# Re-reads this panel's theme colours - called by RegionField right after
# it applies the region's on-pale/on-dark value set to the shared
# BattleTheme resource (and by BattleOverlay's F2 flip), same "cached
# once, refreshed on demand" shape EnemyStatus/DeckPanel/CardView already
# use rather than tracking the theme resource live. Both styles draw with
# the Battle ink token.
func refresh_style() -> void:
	_ink = get_theme_color("ink", "Battle")
	_toll_rule_color = get_theme_color("toll_rule", "Battle")
	# Alegreya Bold, tracked - the same treatment the card's own type label
	# uses, so the row reads as the same voice as "STRIKE"/"GUARD".
	_row_font_tracked = InkType.tracked(InkType.text_bold_font(), row_font_size_px, row_tracking_em)
	_toll_label_tracked = InkType.tracked(name_font, toll_label_size_px, toll_label_tracking_em)
	if _reveal != null:
		_reveal.set_ink(_ink)
	_apply_critical_colors()
	_apply_layout()

# The row's tracked face, rebuilt for a live edit of its size or tracking
# (refresh_style() builds it the first time).
func _refresh_row_font() -> void:
	if not is_node_ready():
		return
	_row_font_tracked = InkType.tracked(InkType.text_bold_font(), row_font_size_px, row_tracking_em)
	_apply_layout()

func _relayout_if_ready() -> void:
	if is_node_ready():
		_apply_layout()

# A live edit of a tracked face's size or tracking: rebuilt, then laid out.
func _restyle_if_ready() -> void:
	if is_node_ready():
		refresh_style()

# The battle energy readout's right edge on screen, from BattleOverlay -
# what min_energy_clearance_px keeps the HP numeral off. NAN = none (out
# of battle).
func set_energy_clearance_x(right_x: float) -> void:
	_energy_right_x = right_x

func _physics_process(delta: float) -> void:
	if _wanderer == null or not is_instance_valid(_wanderer):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	# The field anchor is field_offset_px down the screen from the feet;
	# the battle anchor is the feet plus ground_offset in the world. The
	# two ease into each other with the styles.
	var feet: Vector3 = _wanderer.global_position
	var field_pos: Vector2 = camera.unproject_position(feet) + Vector2(0.0, field_offset_px)
	var battle_pos: Vector2 = camera.unproject_position(feet + ground_offset)
	var screen_pos: Vector2 = field_pos.lerp(battle_pos, _battle_blend)
	# Whole pixels only - a fractional Control position on a bare bar (no
	# panel background to visually absorb it) reads as shimmer/jitter on
	# thin edges, most visibly on the halo's edge.
	# A constant screen size in the field; battle_scale in battle.
	scale = Vector2.ONE * lerpf(1.0, battle_scale, _battle_blend)
	var placed: Vector2 = screen_pos - _anchor_offset()
	# Kept off the energy readout: the HP numeral's left edge (on screen,
	# scaled about the pivot) never within min_energy_clearance_px of its
	# right edge - eased in with the battle style.
	if not is_nan(_energy_right_x):
		var hp_left: float = placed.x + pivot_offset.x + (_block_readout_width() - pivot_offset.x) * scale.x
		var crowding: float = _energy_right_x + min_energy_clearance_px - hp_left
		if crowding > 0.0:
			placed.x += crowding * _battle_blend
	position = placed.round()

	var hovered: bool = not _in_battle and HoverRaycast.is_hovering(get_viewport(), _wanderer)
	var low_hp: bool = _current_fraction <= low_hp_fraction
	_visibility.update(delta, hovered, low_hp, _in_battle)

	# Only once the battle style is fully in - never mid-transition.
	_update_reveal(_line_under_mouse() if _in_battle and _battle_blend >= 1.0 else -1)

# Shows the hovered line's entry alone, or nothing. Re-placed every tick
# while shown - the bar follows the camera, and with it the clearance.
func _update_reveal(line: int) -> void:
	if line >= _row_items.size():
		line = -1
	if line != _hovered_line:
		_hovered_line = line
		if line >= 0:
			var item: Dictionary = _row_items[line]
			_reveal.set_lines(PackedStringArray([String(item.get("name", ""))]), PackedStringArray([String(item.get("rules", ""))]))
	if _hovered_line >= 0:
		_place_reveal()
	_reveal.set_revealed(_hovered_line >= 0 and not String(_row_items[_hovered_line].get("rules", "")).is_empty())

# Under the whole readout when it clears the resting hand by
# min_hand_clearance_px; otherwise to its left, beside the hovered line
# (see the Status Reveal group's doc).
func _place_reveal() -> void:
	if _reveal == null or not is_node_ready():
		return
	var below := Vector2(_block_readout_width(), _battle_content_size().y + reveal_gap_px)
	var fits: bool = true
	if _hand_top_y >= 0.0:
		var bottom: float = (get_global_transform() * Vector2(0.0, below.y + _reveal.size.y)).y
		fits = _hand_top_y - bottom >= min_hand_clearance_px
	var rects: Array[Rect2] = _line_rects()
	if fits or _hovered_line < 0 or _hovered_line >= rects.size():
		_reveal.set_align_right(false)
		_reveal.position = below
		return
	_reveal.set_align_right(true)
	var line_top: float = rects[_hovered_line].position.y + row_line_gap_px * 0.5
	_reveal.position = Vector2(-side_gap_px - battle_width, line_top)

func _hp_fraction(current: int, max_hp: int) -> float:
	if max_hp <= 0:
		return 0.0
	return clampf(float(current) / float(max_hp), 0.0, 1.0)

func _on_player_hp_changed(current: int, max_hp: int) -> void:
	_current_hp = current
	_max_hp = max_hp
	# The field row's width follows the digits.
	_relayout_if_ready()
	_current_fraction = _hp_fraction(current, max_hp)
	_tween_bar_to(_current_fraction)
	_visibility.notify_hp_changed()
	_refresh_critical()

# Whether the Wanderer is Critical at the HP the run holds now - the
# fight's own rule (Combatant.critical_at()) with the character's own
# fraction, so this can't drift from what the cards read.
func _is_critical() -> bool:
	if RunState.character == null:
		return false
	return Combatant.critical_at(RunState.player_hp, RunState.player_max_hp, RunState.character.critical_hp_fraction)

# Where the Critical line sits along the bar: max HP x the character's
# fraction, over max HP.
func _critical_fraction() -> float:
	if RunState.character == null:
		return 0.0
	return clampf(RunState.character.critical_hp_fraction, 0.0, 1.0)

# Re-read on every HP or max-HP change: a crossing either way eases the
# numeral and fill over critical_fade_time; no crossing, nothing moves.
func _refresh_critical() -> void:
	var critical: bool = _is_critical()
	if critical == _critical:
		return
	_critical = critical
	if _critical_tween != null:
		_critical_tween.kill()
	var target: float = 1.0 if critical else 0.0
	if critical_fade_time <= 0.0:
		_set_critical_blend(target)
		return
	_critical_tween = create_tween()
	_critical_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_critical_tween.tween_method(_set_critical_blend, _critical_blend, target, critical_fade_time)

func _set_critical_blend(value: float) -> void:
	_critical_blend = value
	_apply_critical_colors()

# The Critical blend and the tick, applied - both styles read them in
# _draw().
func _apply_critical_colors() -> void:
	if not is_node_ready():
		return
	queue_redraw()

# Animates _displayed_fraction (not the fill's width directly - see that
# var's own doc) toward `fraction` over bar_tween_time; _apply_layout(),
# called every step, is what actually applies it to both bars' fills.
func _tween_bar_to(fraction: float) -> void:
	if _fraction_tween != null:
		_fraction_tween.kill()
	_fraction_tween = create_tween()
	_fraction_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fraction_tween.tween_method(_set_displayed_fraction, _displayed_fraction, fraction, bar_tween_time)

func _set_displayed_fraction(value: float) -> void:
	_displayed_fraction = value
	_apply_layout()

# Called by BattleOverlay on the controller's status_changed with the
# player's current block (0 clears the segment) - battle-only; the field
# style never shows it.
#
# A changed value crossfades from the old over block_crossfade_time - no
# pulse, no colour. Appearing and going (to or from 0) are immediate, and
# the HP numeral never moves for any of it (_anchor_offset()).
func set_block(block: int) -> void:
	var value: int = maxi(block, 0)
	if value == _block:
		return
	if _block_tween != null and _block_tween.is_valid():
		_block_tween.kill()
	var crossfade: bool = _block > 0 and value > 0 and block_crossfade_time > 0.0
	_block_prev = _block if crossfade else 0
	_block = value
	if crossfade:
		_block_fade = 0.0
		_block_tween = create_tween()
		_block_tween.tween_method(_set_block_fade, 0.0, 1.0, block_crossfade_time)
	else:
		_block_fade = 1.0
	_apply_layout()

func _set_block_fade(value: float) -> void:
	_block_fade = value
	if _block_fade >= 1.0:
		_block_prev = 0
	_apply_layout()

# Grace changed (opened by an enemy turn, spent by a hit, or lost when
# the window closed). 0 simply draws nothing.
func update_grace(grace: int) -> void:
	_grace = maxi(grace, 0)
	queue_redraw()

func hide_grace() -> void:
	update_grace(0)

# The standing row's lines, top to bottom, pushed by BattleOverlay on the
# controller's stance_changed/status_changed. This node does no rules
# reading of its own - it is handed what to draw, which is why it needs
# no knowledge of stacking rules or status categories. Each entry:
#   "text"           the line as drawn ("The Return 2/5")
#   "glyph"          the mark before it: &"stance" (the bitten ring) or
#                    &"drop" (Venom's); none without one
#   "count"          > 0 for a counter, with "progress" of it - the hairline
#   "spent"          a guard spent this fight, at row_spent_alpha
#   "name", "rules"  its hover reveal: the name and what it does now
#                    (Stance.describe()/Status.describe())
func set_standing_row(items: Array[Dictionary]) -> void:
	_row_items = items.duplicate()
	# Re-read on the next tick, against the new lines - the same line may
	# now say something else. A reveal already up stays up meanwhile.
	_hovered_line = -1
	_apply_layout()

func clear_standing_row() -> void:
	set_standing_row([] as Array[Dictionary])
	if _reveal != null:
		_reveal.set_lines(PackedStringArray(), PackedStringArray())

# The resting hand's top edge in canvas pixels (HandContainer.get_rest_
# top_y()), which the reveal under the readout keeps clear of - pushed by
# BattleOverlay.
func set_hand_top_y(y: float) -> void:
	_hand_top_y = y
	_place_reveal()

# Called by BattleOverlay.enter_battle()/_finish_battle() - bypasses the
# field hover/hold/low-hp visibility rules entirely while true (see
# HoverFadeVisibility.update()), and tweens _battle_blend to/from 1 over
# `duration` (BattleOverlay's own camera_rig.battle_transition_time - see
# its own doc) so the style change reads as part of the same transition
# as the camera swing.
func enter_battle(duration: float) -> void:
	_in_battle = true
	_tween_battle_blend(1.0, duration)

func exit_battle(duration: float) -> void:
	_in_battle = false
	_energy_right_x = NAN
	_block = 0
	_block_prev = 0
	_block_fade = 1.0
	if _reveal != null:
		_reveal.clear()
	_tween_battle_blend(0.0, duration)

# Called by BattleOverlay.enter_battle() - puts the Toll block on. The
# initial value shows immediately; BattleController.setup() emits the
# real one synchronously right after (see BattleOverlay.enter_battle()'s
# own connect-then-setup order), so there's no stale-number frame.
func show_toll(initial_toll: int) -> void:
	_toll = maxi(initial_toll, 0)
	_toll_visible = true
	_apply_layout()

func update_toll(new_toll: int) -> void:
	if not _toll_visible:
		return
	if _drain_tween != null:
		_drain_tween.kill()
		_drain_tween = null
	var changed: bool = new_toll != _toll
	_toll = maxi(new_toll, 0)
	if changed:
		_pop_toll()
	_apply_layout()

# A Toll blow (Reckoning): the numeral counts down from `from`, the Toll
# it spent, to `to`, what is left, over toll_drain_time - on real time,
# so it pours on through the hit-stop its blow makes. Popped as it
# starts, like any change. A later update_toll() cuts it short.
func drain_toll(from: int, to: int) -> void:
	if not _toll_visible:
		return
	if _drain_tween != null:
		_drain_tween.kill()
	_toll = maxi(from, 0)
	_pop_toll()
	_apply_layout()
	_drain_tween = create_tween()
	_drain_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_drain_tween.set_ignore_time_scale(true)
	_drain_tween.tween_method(_set_drained_toll, float(from), float(maxi(to, 0)), toll_drain_time)

func _set_drained_toll(value: float) -> void:
	var shown: int = roundi(value)
	if shown == _toll:
		return
	_toll = shown
	_apply_layout()

func hide_toll() -> void:
	_toll_visible = false
	if _drain_tween != null:
		_drain_tween.kill()
		_drain_tween = null
	if _pop_tween != null:
		_pop_tween.kill()
	_toll_pop = 1.0
	_apply_layout()

func _pop_toll() -> void:
	if _pop_tween != null:
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_pop_tween.tween_method(_set_toll_pop, 1.0, toll_pop_scale, toll_pop_time * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_pop_tween.tween_method(_set_toll_pop, toll_pop_scale, 1.0, toll_pop_time * 0.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

func _set_toll_pop(value: float) -> void:
	_toll_pop = value
	queue_redraw()

func _tween_battle_blend(target: float, duration: float) -> void:
	if _blend_tween != null:
		_blend_tween.kill()
	if duration <= 0.0:
		_set_battle_blend(target)
		return
	_blend_tween = create_tween()
	_blend_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_blend_tween.tween_method(_set_battle_blend, _battle_blend, target, duration)

func _set_battle_blend(value: float) -> void:
	_battle_blend = value
	_apply_layout()
