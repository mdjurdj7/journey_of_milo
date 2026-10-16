extends Control
class_name FindLine

# The field's find line: one sentence in the system voice when a fight
# leaves a worn piece - "You find a harness on the Wardling." - centred
# in the lower third, just under WorldVoiceLine's band (its centre at
# 0.88 of the height, its box 40 px either side) so the two never meet.
# Alegreya Sans at full Battle/ink, no box; the piece's name inline and
# one step stronger, in Alegreya Sans Bold: a Common in a deeper ink
# (name_ink_strength toward full contrast), a Rare in the cards' RARE
# finish (CardRarityFinish.name_material()) - the only place the sentence
# says rarity. It holds hold_seconds, then fades over fade_seconds; a new
# find restarts it.
#
# RegionField says it (say_find()) once the reward screen - and any
# keepsake offer after it - has closed, so it lands as the piece is seen
# on the sand. One per field, created under FieldHUD by on_hud() the
# first time, handed the HUD's theme for its ink (use_theme()).
#
# The name is its own child canvas item, so the finish's shader colours
# it alone and its gradient runs over the name's own width (the shader
# reads the item's local x from 0). The fade is this line's modulate,
# which reaches the name through its alpha. Runs ALWAYS, so it fades
# over a frozen field. Clicks pass through.

const NODE_NAME := "FindLine"

@export var hold_seconds: float = 4.0
@export var fade_seconds: float = 0.6
@export var fade_in_seconds: float = 0.2
@export var text_size_px: int = 26:
	set(value):
		text_size_px = value
		_relayout()
# A Common name's ink: the line's own ink taken this far toward full
# contrast (black on the pale world, white on a dark one).
@export_range(0.0, 1.0) var name_ink_strength: float = 0.5:
	set(value):
		name_ink_strength = value
		if _name_layer != null:
			_name_layer.queue_redraw()
# The line's top, as a fraction of the viewport height: WorldVoiceLine's
# band ends at 0.88 + 40 px (990 at 1080p); this sits a few px under it.
@export var top_fraction: float = 0.922:
	set(value):
		top_fraction = value
		_place()
@export_file("*.tres") var rarity_finish_path: String = "res://battle/card_rarity_finish.tres"
@export_file("*.gdshader") var name_finish_shader_path: String = "res://battle/card_name_finish.gdshader"

var _font: Font = null
var _name_font: Font = null
var _ink: Color = Color.BLACK
var _finish: CardRarityFinish = null
var _name_layer: Control = null
var _name_finish: ShaderMaterial = null
var _piece: TrinketData = null
var _before: String = ""
var _name: String = ""
var _after: String = ""
var _tween: Tween = null

# The field's one FindLine, under `hud` (the FieldHUD CanvasLayer): an
# existing one by name, else a new one. Null if hud is null.
static func on_hud(hud: Node) -> FindLine:
	if hud == null:
		return null
	var existing := hud.get_node_or_null(NODE_NAME) as FindLine
	if existing != null:
		return existing
	var line := FindLine.new()
	line.name = NODE_NAME
	hud.add_child(line)
	return line

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = InkType.text_font()
	_name_font = InkType.text_bold_font()
	_name_layer = Control.new()
	_name_layer.name = "Name"
	_name_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_layer.draw.connect(_draw_name)
	add_child(_name_layer)
	if not rarity_finish_path.is_empty():
		_finish = load(rarity_finish_path) as CardRarityFinish
	refresh_style()
	modulate.a = 0.0
	visible = false

# The theme whose Battle/ink the line reads - the field HUD's.
func use_theme(hud_theme: Theme) -> void:
	theme = hud_theme
	refresh_style()

func refresh_style() -> void:
	if not is_inside_tree():
		return
	_ink = get_theme_color("ink", "Battle")
	queue_redraw()
	if _name_layer != null:
		_name_layer.queue_redraw()

# "You find <article> <name> on the <creature>." - the name lowercased
# after an article (TrinketData.find_name()), in its finish.
func say_find(piece: TrinketData, creature: String) -> void:
	if piece == null:
		return
	_piece = piece
	_before = "You find %s" % (piece.article + " " if not piece.article.is_empty() else "")
	_name = piece.find_name()
	_after = " on the %s." % creature if not creature.is_empty() else "."
	_apply_finish()
	_relayout()
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, maxf(fade_in_seconds, 0.0))
	_tween.tween_interval(maxf(hold_seconds, 0.0))
	_tween.tween_property(self, "modulate:a", 0.0, maxf(fade_seconds, 0.01))
	_tween.tween_callback(func() -> void: visible = false)

# The whole sentence as said (for probes).
func get_sentence() -> String:
	return _before + _name + _after

# The name's finish material while it wears one, else null (for probes).
func get_name_finish() -> ShaderMaterial:
	return _name_layer.material as ShaderMaterial if _name_layer != null else null

func is_showing() -> bool:
	return visible and modulate.a > 0.0

func _apply_finish() -> void:
	var rarity: CardData.CardRarity = _piece.rarity if _piece != null else CardData.CardRarity.UNSET
	var material: ShaderMaterial = null
	if _finish != null:
		material = _finish.name_material(rarity, _name_finish, name_finish_shader_path)
	if material != null:
		_name_finish = material
	_name_layer.material = material

func _relayout() -> void:
	if _name_layer == null:
		return
	var before_w: float = InkType.width(_font, _before, text_size_px)
	var name_w: float = InkType.width(_name_font, _name, text_size_px)
	var after_w: float = InkType.width(_font, _after, text_size_px)
	var height: float = ceilf(_font.get_height(text_size_px)) if _font != null else float(text_size_px)
	size = Vector2(ceilf(before_w + name_w + after_w), height)
	_name_layer.position = Vector2(roundf(before_w), 0.0)
	_name_layer.size = Vector2(ceilf(name_w), height)
	if _name_finish != null:
		_name_finish.set_shader_parameter("text_width_px", name_w)
	_place()
	queue_redraw()
	_name_layer.queue_redraw()

func _process(_delta: float) -> void:
	if visible:
		_place()

# Centred across the viewport, its top at top_fraction - whole pixels.
func _place() -> void:
	if not is_inside_tree():
		return
	var view: Vector2 = get_viewport_rect().size
	position = Vector2(roundf((view.x - size.x) / 2.0), roundf(view.y * top_fraction))

func _baseline() -> float:
	return _font.get_ascent(text_size_px) if _font != null else float(text_size_px)

func _draw() -> void:
	InkType.draw_run(self, _font, _before, Vector2(0.0, _baseline()), text_size_px, _ink)
	var after_x: float = roundf(InkType.width(_font, _before, text_size_px) + InkType.width(_name_font, _name, text_size_px))
	InkType.draw_run(self, _font, _after, Vector2(after_x, _baseline()), text_size_px, _ink)

# A Rare's colour is its finish's (the shader replaces it); a Common's is
# the line's ink pushed toward full contrast.
func _draw_name() -> void:
	var toward: Color = Color.BLACK if _ink.get_luminance() < 0.5 else Color.WHITE
	var color: Color = _ink.lerp(Color(toward, _ink.a), name_ink_strength)
	InkType.draw_run(_name_layer, _name_font, _name, Vector2(0.0, _baseline()), text_size_px, color)
