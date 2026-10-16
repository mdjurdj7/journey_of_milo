extends Control
class_name FindLine

# The field's find line: one sentence in the system voice when a fight
# leaves a worn piece - "You find a harness on the Wardling." - bottom-
# left, just above the HUD row, left-aligned with DECK. Alegreya Sans in
# the theme's Battle/ink at text_alpha, no box; the piece's name inline
# in its rarity finish, the cards' own (CardRarityFinish.name_material():
# flat common_ink for a Common, the RARE finish for a Rare) - the only
# place the sentence says rarity. It holds hold_seconds, then fades over
# fade_seconds; a new find restarts it.
#
# RegionField says it (say_find()) once the reward screen - and any
# keepsake offer after it - has closed, so it lands as the piece is seen
# on the sand. One per field, created under FieldHUD by on_hud() the
# first time, handed the row's first item to sit above (sit_above()).
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
@export var text_size_px: int = 17:
	set(value):
		text_size_px = value
		_relayout()
# The plain words' share of full ink - the muted register; the name is
# drawn at full value.
@export_range(0.0, 1.0) var text_alpha: float = 0.8:
	set(value):
		text_alpha = value
		queue_redraw()
# Between the line's bottom and the top of the item it sits above.
@export var gap_px: float = 10.0:
	set(value):
		gap_px = value
		_place()
@export_file("*.tres") var rarity_finish_path: String = "res://battle/card_rarity_finish.tres"
@export_file("*.gdshader") var name_finish_shader_path: String = "res://battle/card_name_finish.gdshader"

var _above: Control = null
var _font: Font = null
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

# The row item this line sits above - RegionField's DeckPanel, the row's
# first; its theme gives the ink.
func sit_above(item: Control) -> void:
	_above = item
	if item != null:
		theme = item.theme
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
	var name_w: float = InkType.width(_font, _name, text_size_px)
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

# Above the row's first item, left-aligned with it, whole pixels.
func _place() -> void:
	if _above == null or not is_instance_valid(_above):
		return
	var rect: Rect2 = _above.get_global_rect()
	position = Vector2(roundf(rect.position.x), roundf(rect.position.y - gap_px - size.y))

func _baseline() -> float:
	return _font.get_ascent(text_size_px) if _font != null else float(text_size_px)

func _draw() -> void:
	var color := Color(_ink, _ink.a * text_alpha)
	InkType.draw_run(self, _font, _before, Vector2(0.0, _baseline()), text_size_px, color)
	var after_x: float = roundf(InkType.width(_font, _before, text_size_px) + InkType.width(_font, _name, text_size_px))
	InkType.draw_run(self, _font, _after, Vector2(after_x, _baseline()), text_size_px, color)

func _draw_name() -> void:
	var color: Color = _ink
	if _name_layer.material == null and _finish != null:
		color = _finish.common_ink
	InkType.draw_run(_name_layer, _font, _name, Vector2(0.0, _baseline()), text_size_px, color)
