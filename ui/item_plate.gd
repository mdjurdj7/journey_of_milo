extends Control
class_name ItemPlate

# One piece of equipment - the run's weapon, a worn piece or a keepsake -
# shown the one way all three are shown, everywhere: a portrait plate in
# the card family - the card's paper (card_paper_material), a thin
# charcoal frame, a soft shadow - the same shape, frame and size for every
# kind. Top to bottom:
#   the object    its art, centred, in a square window - or, with no art,
#                 a flat tone panel with the name's initial: a placeholder
#   its name      Spectral SemiBold, centred, in its rarity's finish - the
#                 cards' own (CardRarityFinish, card_name_finish.gdshader):
#                 flat ink for COMMON and for anything with no rarity (a
#                 keepsake), a piece's or weapon's tier base with its faint
#                 gradient, a sheen once when the plate opens (play_name_
#                 sheen()). Nothing else says rarity.
#   its type      a small line drawing and a caps label, centred: a sword
#                 and WEAPON, a shield and WORN, a tag and KEEPSAKE
#                 (InkGlyph), one ink and one spacing for all three
#   (a stat row)  the hook for a later piece that changes your attacks'
#                 damage or your defence cards' block: set_stat_row() puts
#                 one centred line under the type line. Nothing sets it
#                 yet, and while it is empty it takes no room
#   what it does  TrinketData.describe() / WeaponData.describe() in the
#                 cards' rules voice (Alegreya Sans, full ink, centred), in
#                 a block always rules_lines tall - left blank when the
#                 piece does nothing, so nothing below it moves. With
#                 card_links_enabled, each card the piece names (Weapon-
#                 Data.named_cards() - the Tail's Lash) is set in the
#                 rules bold, as a card's keywords are, and hovering it
#                 shows that card (a CardView) beside the plate - never
#                 over the strip
#   its lore      under a short centred hairline, in Spectral Italic at
#                 full ink, in a block always lore_lines tall - no lore,
#                 no hairline (never a rule alone)
# Every plate is the same height whatever it says; fits() says whether its
# text stays inside those blocks (the probes check every piece).
#
# An offer - with show_actions, or a piece already worn (or, for a weapon,
# the weapon carried) that taking this would replace - adds a strip of the same paper and frame strip_gap_px
# below the plate, the plate itself unchanged: "REPLACES" in the type
# label's voice and the worn piece's (or weapon's) name in Spectral, in its own rarity
# finish (its own canvas item, as the name's), that piece's effect in grey
# under them; then TAKE and LEAVE side by side - the title menu's
# treatment (TitleMenu, WorldKeepsake): plain tracked caps, the focused
# one in ink with a short hairline to its left, the other in the utility
# grey. No buttons, no boxes, no glow.
#
# Drawn at plate_scale, not scaled: every size and gap multiplied out, so a
# large plate is as crisp as a small one. Hosts - the HUD's equipment
# slots' hovers (KeepsakeLine), the battle row's hover (KeepsakeRow), the
# examine views (ArmorExamine, KeepsakeExamine), the offers
# (KeepsakeOffer, BelongingsScreen, the Keeper's WorldKeepsake) - place it
# and choose its scale; with show_actions it takes the mouse and says
# `chosen`, otherwise it ignores it.

signal chosen(take: bool)

enum Choice { TAKE, LEAVE }

const PAPER_MATERIAL_PATH := "res://battle/card_paper_material.tres"
const LORE_FONT_PATH := "res://assets/fonts/Spectral-Italic.ttf"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"

@export var plate_width: float = 300.0:
	set(value):
		plate_width = value
		_relayout()
@export var plate_scale: float = 1.0:
	set(value):
		plate_scale = maxf(value, 0.1)
		_relayout()
@export_file("*.tres") var rarity_finish_path: String = "res://battle/card_rarity_finish.tres"
@export_file("*.gdshader") var name_finish_shader_path: String = "res://battle/card_name_finish.gdshader"

@export_group("Look")
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		ink = value
		_redraw()
@export var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0):
	set(value):
		unfocused_color = value
		_redraw()
@export var corner_radius_px: int = 6:
	set(value):
		corner_radius_px = value
		_relayout()
@export_range(0.0, 1.0) var frame_alpha: float = 0.85:
	set(value):
		frame_alpha = value
		_redraw()
@export var shadow_size_px: int = 12:
	set(value):
		shadow_size_px = value
		_relayout()
@export_range(0.0, 1.0) var shadow_alpha: float = 0.2:
	set(value):
		shadow_alpha = value
		_relayout()
@export var shadow_offset_px: float = 4.0:
	set(value):
		shadow_offset_px = value
		_relayout()
# Round the plate's edge, inside the frame.
@export var padding_px: float = 16.0:
	set(value):
		padding_px = value
		_relayout()
@export_range(0.0, 1.0) var hairline_alpha: float = 0.35:
	set(value):
		hairline_alpha = value
		_redraw()
# The lore's hairline, as a share of the plate's width.
@export_range(0.0, 1.0) var hairline_width_fraction: float = 0.3:
	set(value):
		hairline_width_fraction = value
		_redraw()
@export_group("")

@export_group("Art")
@export var art_size_px: float = 114.0:
	set(value):
		art_size_px = value
		_relayout()
@export var placeholder_color: Color = Color(0.80, 0.77, 0.71, 1.0):
	set(value):
		placeholder_color = value
		_redraw()
@export var placeholder_initial_size_px: int = 72:
	set(value):
		placeholder_initial_size_px = value
		_redraw()
@export_range(0.0, 1.0) var placeholder_initial_alpha: float = 0.45:
	set(value):
		placeholder_initial_alpha = value
		_redraw()
@export_group("")

@export_group("Name and Type")
@export var name_size_px: int = 22:
	set(value):
		name_size_px = value
		_relayout()
# Between the art and the name - tight, so no empty band opens between.
@export var name_gap_px: float = 4.0:
	set(value):
		name_gap_px = value
		_relayout()
@export var weapon_label_text: String = "WEAPON":
	set(value):
		weapon_label_text = value
		_relayout()
@export var worn_label_text: String = "WORN":
	set(value):
		worn_label_text = value
		_relayout()
@export var keepsake_label_text: String = "KEEPSAKE":
	set(value):
		keepsake_label_text = value
		_relayout()
# The Bedroll's kind (set_bedroll()) - a rest, used in the field.
@export var rest_label_text: String = "REST":
	set(value):
		rest_label_text = value
		_relayout()
# The type label - and REPLACES - in the HUD row's label voice: small
# tracked Alegreya Sans Bold caps, ink at type_alpha; its glyph in the
# same ink.
@export var type_size_px: int = 11:
	set(value):
		type_size_px = value
		_label_font = null
		_relayout()
@export var type_tracking_em: float = 0.16:
	set(value):
		type_tracking_em = value
		_label_font = null
		_relayout()
@export_range(0.0, 1.0) var type_alpha: float = 0.62:
	set(value):
		type_alpha = value
		_redraw()
# Between the name and the type line.
@export var type_gap_px: float = 6.0:
	set(value):
		type_gap_px = value
		_relayout()
# The glyph's square, its stroke, and the room between it and the label.
@export var type_glyph_px: float = 12.0:
	set(value):
		type_glyph_px = value
		_relayout()
@export var type_glyph_stroke_px: float = 1.2:
	set(value):
		type_glyph_stroke_px = value
		_redraw()
@export var type_glyph_gap_px: float = 6.0:
	set(value):
		type_glyph_gap_px = value
		_relayout()
# The stat row's text (set_stat_row()), and its gap under the type line.
@export var stat_row_size_px: int = 13:
	set(value):
		stat_row_size_px = value
		_relayout()
@export var stat_row_gap_px: float = 6.0:
	set(value):
		stat_row_gap_px = value
		_relayout()
@export_group("")

@export_group("Effect and Lore")
@export var rules_size_px: int = 15:
	set(value):
		rules_size_px = value
		_relayout()
# The effect's block, in lines - the same height with one line, two, or
# none.
@export var rules_lines: int = 2:
	set(value):
		rules_lines = maxi(value, 1)
		_relayout()
# Between the type line (or stat row) and the effect's block.
@export var rules_gap_px: float = 12.0:
	set(value):
		rules_gap_px = value
		_relayout()
@export var lore_size_px: int = 16:
	set(value):
		lore_size_px = value
		_relayout()
@export var lore_lines: int = 2:
	set(value):
		lore_lines = maxi(value, 1)
		_relayout()
# Between the effect's block and the hairline, and the hairline and the
# lore.
@export var lore_gap_px: float = 10.0:
	set(value):
		lore_gap_px = value
		_relayout()
@export var line_pitch_em: float = 1.3:
	set(value):
		line_pitch_em = value
		_relayout()
@export_group("")

@export_group("Card Links")
# The card a hovered name shows: a CardView at this scale (its own, not
# times plate_scale), card_link_gap_px beside the plate's card - right of
# it, or left where the screen has no room - centred on it, kept on
# screen. It never takes the mouse. Each re-applies live.
@export_range(0.2, 2.0) var card_link_preview_scale: float = 1.0:
	set(value):
		card_link_preview_scale = value
		_place_link_preview()
@export var card_link_gap_px: float = 24.0:
	set(value):
		card_link_gap_px = value
		_place_link_preview()
@export_group("")

@export_group("Offer")
# Between the plate and the offer's strip under it.
@export var strip_gap_px: float = 10.0:
	set(value):
		strip_gap_px = value
		_relayout()
@export var replaces_label_text: String = "REPLACES":
	set(value):
		replaces_label_text = value
		_relayout()
# The worn piece's name after REPLACES.
@export var replaced_name_size_px: int = 15:
	set(value):
		replaced_name_size_px = value
		_relayout()
# Between REPLACES and the worn piece's name.
@export var replaces_label_gap_px: float = 6.0:
	set(value):
		replaces_label_gap_px = value
		_relayout()
# The worn piece's effect, under its name.
@export var replaces_size_px: int = 13:
	set(value):
		replaces_size_px = value
		_relayout()
@export var replaces_color: Color = Color(0.45, 0.45, 0.47, 1.0):
	set(value):
		replaces_color = value
		_redraw()
# A worn piece's offer that would change max HP (set_max_hp()): one line,
# "Max HP 86 → 80", at replaces_size_px in replaces_color, under the
# replaced piece's effect - or alone above the choices with nothing worn.
# None when taking it leaves max HP as it is.
@export var max_hp_format: String = "Max HP %d → %d":
	set(value):
		max_hp_format = value
		_relayout()
@export var take_text: String = "TAKE":
	set(value):
		take_text = value
		_relayout()
@export var leave_text: String = "LEAVE":
	set(value):
		leave_text = value
		_relayout()
@export var action_size_px: int = 15:
	set(value):
		action_size_px = value
		_action_font = null
		_relayout()
@export_range(0.0, 1.0) var caps_tracking_em: float = 0.16:
	set(value):
		caps_tracking_em = value
		_action_font = null
		_relayout()
# Between the REPLACES lines and the choices.
@export var actions_gap_px: float = 8.0:
	set(value):
		actions_gap_px = value
		_relayout()
@export var action_row_height_px: float = 30.0:
	set(value):
		action_row_height_px = value
		_relayout()
# The focus hairline: the title menu's, in proportion (WorldKeepsake's).
@export var focus_hairline_length_px: float = 18.0:
	set(value):
		focus_hairline_length_px = value
		_redraw()
@export var focus_hairline_gap_px: float = 9.0:
	set(value):
		focus_hairline_gap_px = value
		_redraw()
@export var hairline_thickness_px: float = 1.0:
	set(value):
		hairline_thickness_px = value
		_redraw()
# Off (a price the run can't pay - CollectorScreen): TAKE in inert_color,
# never focused in ink, and choosing it does nothing; LEAVE as ever.
@export var take_enabled: bool = true:
	set(value):
		take_enabled = value
		_redraw()
@export var inert_color: Color = Color(0.58, 0.58, 0.60, 0.45):
	set(value):
		inert_color = value
		_redraw()
@export_group("")

# A worn piece or a keepsake (by its slot).
var _piece: TrinketData = null
# The weapon shown instead of a piece (set_weapon()); null while a piece is.
var _weapon: WeaponData = null
# The Bedroll shown instead (set_bedroll()); null otherwise. It has no art
# of its own: its ink glyph stands in for one, on the placeholder's tone.
var _bedroll: BedrollData = null
# The Warped Shell shown instead (set_shell()), and the card in the deck it
# would change; null otherwise. Its art is what that card becomes.
var _shell: WarpedShellData = null
var _shell_host: CardData = null
# A card shown beside the plate whatever the mouse does (the shell's
# Stoneshell) - a hovered name shows its own over it while hovered.
var _pinned_link: CardData = null
var _replaced: TrinketData = null
# The weapon carried that taking the one shown would replace (set_
# weapon()'s offer) - in _replaced's place in the strip; null otherwise.
var _replaced_weapon: WeaponData = null
var _show_actions: bool = false
# Set by a host the player looks at closely (ArmorExamine): the names of
# the cards the piece names are inked and hoverable. Off everywhere else
# (the HUD's hovers, the battle row), where they read as plain text.
var card_links_enabled: bool = false:
	set(value):
		card_links_enabled = value
		_apply_mouse_filter()
		_relayout()
var _focus: int = Choice.TAKE
var _stat_text: String = ""

var _shadow: Panel = null
var _strip_shadow: Panel = null
var _paper: Control = null
var _face: Control = null
# The name on its own canvas item: the finish shader reads its local x.
var _name_layer: Control = null
# The worn piece's name after REPLACES, on its own for the same reason.
var _replaced_name_layer: Control = null
var _paper_seed: float = 0.0
# Held: a TextParagraph keeps only its fonts' RIDs, and a font nothing
# else holds is freed before the paragraph shapes.
var _lore_font: Font = null
var _rules_font: Font = null
var _rules_bold_font: Font = null
# The name's face (Spectral SemiBold), loaded once and kept: drawn from
# the draw callbacks, a font loaded there and dropped is freed with its
# glyphs as the callback returns - its text drawn as solid ink boxes.
var _numeral_font: Font = null
var _action_font: Font = null
# The type label's tracked face, built for _label_font_px (scaled).
var _label_font: Font = null
var _label_font_px: int = 0
var _finish: CardRarityFinish = null
var _name_finish: ShaderMaterial = null
var _replaced_name_finish: ShaderMaterial = null
var _sheen_tween: Tween = null

# Laid out, in scaled pixels.
var _card_rect: Rect2 = Rect2()
var _strip_rect: Rect2 = Rect2()
var _plate_size: Vector2 = Vector2.ZERO
var _art_rect: Rect2 = Rect2()
var _name_baseline: float = 0.0
var _type_baseline: float = 0.0
var _type_glyph_rect: Rect2 = Rect2()
var _type_label_left: float = 0.0
var _stat_baseline: float = -1.0
var _rules: TextParagraph = null
var _rules_top: float = 0.0
var _hairline_y: float = 0.0
var _lore: TextParagraph = null
var _lore_top: float = 0.0
var _replaces_baseline: float = 0.0
var _replaces_label_left: float = 0.0
var _replaces: TextParagraph = null
var _replaces_top: float = 0.0
# The run's max HP as it stands (set_max_hp(); -1 = not given, no line),
# and its line in the strip while taking the offer would change it.
var _max_hp: int = -1
var _max_hp_line: TextParagraph = null
var _max_hp_top: float = 0.0
var _action_rects: Array[Rect2] = []
# The named cards in the effect: {"card", "start", "end"} by character in
# its text; and laid out, {"rect", "card"} per line a name sits on.
var _links: Array[Dictionary] = []
var _link_rects: Array[Dictionary] = []
var _hovered_link: CardData = null
var _link_preview: CardView = null

func _init() -> void:
	_numeral_font = InkType.numeral_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow = _new_shadow("Shadow")
	_strip_shadow = _new_shadow("StripShadow")
	_paper = Control.new()
	_paper.name = "Paper"
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.material = load(PAPER_MATERIAL_PATH) as Material
	_paper.draw.connect(_draw_paper)
	add_child(_paper)
	_face = Control.new()
	_face.name = "Face"
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The art is drawn well under its size, like a card's.
	_face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_face.draw.connect(_draw_face)
	add_child(_face)
	_name_layer = Control.new()
	_name_layer.name = "Name"
	_name_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_layer.draw.connect(_draw_name)
	add_child(_name_layer)
	_replaced_name_layer = Control.new()
	_replaced_name_layer.name = "ReplacedName"
	_replaced_name_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_replaced_name_layer.draw.connect(_draw_replaced_name)
	add_child(_replaced_name_layer)
	gui_input.connect(_on_gui_input)
	mouse_exited.connect(func() -> void: _set_hovered_link(null))

func _new_shadow(shadow_name: String) -> Panel:
	var shadow := Panel.new()
	shadow.name = shadow_name
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)
	return shadow

func _ready() -> void:
	_relayout()

# A worn piece or a keepsake; for an offer, the piece worn now it would
# replace (null: none - no line) and whether TAKE and LEAVE are offered.
func set_piece(piece: TrinketData, replaced: TrinketData = null, show_actions: bool = false) -> void:
	_piece = piece
	_weapon = null
	_replaced_weapon = null
	_bedroll = null
	_shell = null
	_shell_host = null
	_pinned_link = null
	_replaced = replaced if replaced != piece else null
	_show_actions = show_actions
	_max_hp = -1
	_focus = Choice.TAKE
	# The paper's grain from the piece's id: the same plate wherever it is
	# shown, and no draw on the global generator a run's shuffles use.
	_paper_seed = float(absi(hash(piece.id)) % 1000) / 1000.0 if piece != null else 0.0
	_apply_mouse_filter()
	_apply_finish()
	_relayout()

# For a worn piece's offer, after set_piece(): the run's max HP now, so
# the strip says what taking it makes that (max_hp_format) - the worn
# piece's max_hp_bonus off, the offered one's on, as RunState.equip_worn()
# does. -1 shows no line.
func set_max_hp(max_hp: int) -> void:
	_max_hp = max_hp
	_relayout()

# Max HP once the offered piece is taken - the same as now with nothing
# to say (no offer, no max HP given, or no change).
func max_hp_after() -> int:
	if _max_hp < 0 or _piece == null or not _show_actions:
		return _max_hp
	var worn_bonus: int = maxi(_replaced.max_hp_bonus, 0) if _replaced != null else 0
	return _max_hp - worn_bonus + maxi(_piece.max_hp_bonus, 0)

# The strip's max HP line, "" when there is none.
func max_hp_text() -> String:
	var after: int = max_hp_after()
	if _max_hp < 0 or after == _max_hp:
		return ""
	return max_hp_format % [_max_hp, after]

# A keepsake: set_piece() with no offer of its own (its hosts draw theirs).
func set_keepsake(keepsake: TrinketData) -> void:
	set_piece(keepsake)

func get_piece() -> TrinketData:
	return _piece

func get_keepsake() -> TrinketData:
	return _piece

# A weapon, in place of a piece: the run's own, with no choice and no
# REPLACES line - or, for an offer (the Greyshelf's), the weapon carried
# now it would replace (null: no line) and whether TAKE and LEAVE are
# offered.
func set_weapon(weapon: WeaponData, replaced: WeaponData = null, show_actions: bool = false) -> void:
	set_piece(null, null, show_actions)
	_weapon = weapon
	_replaced_weapon = replaced if replaced != weapon else null
	_paper_seed = float(absi(hash(weapon.id)) % 1000) / 1000.0 if weapon != null else 0.0
	_apply_mouse_filter()
	_apply_finish()
	_relayout()

func get_weapon() -> WeaponData:
	return _weapon

# The Bedroll, in place of a piece: its plate_name, its REST kind and
# glyph, its plate_text as the effect, its lore; plain ink. With
# show_actions (the collector's), TAKE and LEAVE under it - nothing it
# would replace.
func set_bedroll(bedroll: BedrollData, show_actions: bool = false) -> void:
	set_piece(null, null, show_actions)
	_bedroll = bedroll
	_paper_seed = float(absi(hash(bedroll.plate_name)) % 1000) / 1000.0 if bedroll != null else 0.0
	_relayout()

func get_bedroll() -> BedrollData:
	return _bedroll

# The Warped Shell's change: `host` (the card in the deck) and what it
# becomes, named in the effect and that card shown beside the plate;
# with show_actions, TAKE and LEAVE.
func set_shell(shell: WarpedShellData, host: CardData, show_actions: bool = false) -> void:
	set_piece(null, null, show_actions)
	_shell = shell
	_shell_host = host
	_paper_seed = float(absi(hash(shell.plate_name)) % 1000) / 1000.0 if shell != null else 0.0
	_apply_mouse_filter()
	_relayout()
	_pinned_link = shell.result_for(host) if shell != null else null
	_set_hovered_link(_pinned_link)

func get_shell() -> WarpedShellData:
	return _shell

# The stat row's line under the type line - "" (the default) shows none
# and takes no room. For a later piece that changes your attacks' damage
# or your defence cards' block; nothing sets it yet.
func set_stat_row(text: String) -> void:
	_stat_text = text
	_relayout()

func get_stat_row() -> String:
	return _stat_text

# Whether the effect's block holds anything - false for a weapon (or
# piece) with nothing to say. For probes.
func shows_rules() -> bool:
	return _rules != null

# The type label shown (WEAPON, WORN, KEEPSAKE) - for probes.
func get_type_label() -> String:
	if _shell != null:
		return _shell.plate_label
	if _bedroll != null:
		return rest_label_text
	if _weapon != null:
		return weapon_label_text
	if _piece != null and _piece.slot == TrinketData.Slot.WORN:
		return worn_label_text
	return keepsake_label_text

func _type_glyph() -> InkGlyph.Kind:
	if _shell != null:
		return InkGlyph.Kind.DECK
	if _bedroll != null:
		return InkGlyph.Kind.BEDROLL
	if _weapon != null:
		return InkGlyph.Kind.SWORD
	if _piece != null and _piece.slot == TrinketData.Slot.WORN:
		return InkGlyph.Kind.SHIELD
	return InkGlyph.Kind.TAG

# What the plate shows, from the piece or the weapon, whichever it holds.
func _shown_name() -> String:
	if _shell != null:
		return _shell.plate_name
	if _bedroll != null:
		return _bedroll.plate_name
	if _weapon != null:
		return _weapon.display_name
	return _piece.display_name if _piece != null else ""

func _shown_art() -> Texture2D:
	if _shell != null:
		var into: CardData = _shell.result_for(_shell_host)
		return into.art if into != null else null
	if _bedroll != null:
		return null
	if _weapon != null:
		return _weapon.art
	return _piece.art if _piece != null else null

func _shown_rules() -> String:
	if _shell != null:
		return _shell.describe(_shell_host)
	if _bedroll != null:
		return _bedroll.describe_plate()
	if _weapon != null:
		return _weapon.describe()
	return _piece.describe() if _piece != null else ""

func _shown_lore() -> String:
	if _shell != null:
		return _shell.lore
	if _bedroll != null:
		return _bedroll.lore
	if _weapon != null:
		return _weapon.lore
	return _piece.flavor_text if _piece != null else ""

# The cards the piece shown names in its effect - a weapon's (WeaponData.
# named_cards()), the Warped Shell's card and what it becomes; a worn
# piece or keepsake names none yet.
func _named_cards() -> Array[CardData]:
	if _shell != null:
		var named: Array[CardData] = []
		for card: CardData in [_shell_host, _shell.result_for(_shell_host)]:
			if card != null:
				named.append(card)
		return named
	if _weapon != null and _bedroll == null:
		return _weapon.named_cards()
	return []

# An offer takes the mouse (STOP); a plate whose names are hoverable
# watches it but lets a click through to its host (PASS); else IGNORE.
func _apply_mouse_filter() -> void:
	if _show_actions:
		mouse_filter = Control.MOUSE_FILTER_STOP
	elif card_links_enabled and not _named_cards().is_empty():
		mouse_filter = Control.MOUSE_FILTER_PASS
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

# Whether the plate holds an item - a piece, a weapon, a Bedroll, a
# shell: what its hosts ask, so a new kind is counted here alone.
func has_item() -> bool:
	return _piece != null or _weapon != null or _bedroll != null or _shell != null

func get_replaced() -> TrinketData:
	return _replaced

func get_replaced_weapon() -> WeaponData:
	return _replaced_weapon

# What an offer would replace, piece or weapon: whether there is one, its
# name and its effect - the strip's three readings.
func _has_replaced() -> bool:
	return _replaced != null or _replaced_weapon != null

func _replaced_name() -> String:
	if _replaced_weapon != null:
		return _replaced_weapon.display_name
	return _replaced.display_name if _replaced != null else ""

func _replaced_rules() -> String:
	if _replaced_weapon != null:
		return _replaced_weapon.describe()
	return _replaced.describe() if _replaced != null else ""

# The whole on screen: the plate, and an offer's strip under it.
func get_plate_size() -> Vector2:
	return _plate_size

# The plate alone - the same for every piece at one scale.
func get_card_size() -> Vector2:
	return _card_rect.size

# Whether every line stays inside its block: the effect in rules_lines,
# the lore in lore_lines, and the name on one line inside the padding.
func fits() -> bool:
	if get_rules_line_count() > rules_lines or get_lore_line_count() > lore_lines:
		return false
	var name_width: float = InkType.width(_numeral_font, _shown_name(), _font_px(name_size_px))
	return name_width <= _card_rect.size.x - _px(padding_px) * 2.0 + 0.5

func get_rules_line_count() -> int:
	return _rules.get_line_count() if _rules != null else 0

func get_lore_line_count() -> int:
	return _lore.get_line_count() if _lore != null else 0

# The REPLACES line as shown ("REPLACES <name>"), "" with nothing worn -
# for probes.
func replaces_text() -> String:
	if not _has_replaced():
		return ""
	return "%s %s" % [replaces_label_text, _replaced_name()]

# The name's finish material while it wears one, else null - for probes.
func get_name_finish() -> ShaderMaterial:
	return _name_layer.material as ShaderMaterial if _name_layer != null else null

# The worn piece's name's finish after REPLACES, else null - for probes.
func get_replaced_name_finish() -> ShaderMaterial:
	return _replaced_name_layer.material as ShaderMaterial if _replaced_name_layer != null else null

func uses_placeholder() -> bool:
	return has_item() and _shown_art() == null

# One sweep of the finish's sheen across the name - CardView's, played
# once as the plate opens. Nothing for a name with no finish.
func play_name_sheen() -> void:
	if _name_finish == null or _name_layer.material != _name_finish or not is_inside_tree():
		return
	if _sheen_tween != null and _sheen_tween.is_valid():
		_sheen_tween.kill()
	_sheen_tween = create_tween()
	_sheen_tween.tween_method(_set_sheen, 0.0, 1.0, maxf(_finish.sheen_duration_sec, 0.01))
	_sheen_tween.tween_callback(_set_sheen.bind(-1.0))

func _set_sheen(t: float) -> void:
	if _name_finish != null:
		_name_finish.set_shader_parameter("sheen_t", t)

# The choice under focus, and moving it - the keys' way (ArmorExamine).
func get_focus() -> int:
	return _focus

func set_focus(index: int) -> void:
	if not _show_actions or index == _focus or index < 0 or index > Choice.LEAVE:
		return
	_focus = index
	_redraw()

# What a click or a key resolves: TAKE or LEAVE, said once - nothing for
# a TAKE that isn't enabled.
func activate(index: int) -> void:
	if not _show_actions or index < 0 or index > Choice.LEAVE:
		return
	if index == Choice.TAKE and not take_enabled:
		return
	chosen.emit(index == Choice.TAKE)

# --- The finish ---

func _apply_finish() -> void:
	if _finish == null and not rarity_finish_path.is_empty():
		_finish = load(rarity_finish_path) as CardRarityFinish
	_name_finish = _finish_on(_name_layer, _shown_rarity(), _name_finish)
	_replaced_name_finish = _finish_on(_replaced_name_layer, _replaced_rarity(), _replaced_name_finish)
	_redraw()

# The shown item's rarity - a weapon's or a piece's; UNSET for the rest.
func _shown_rarity() -> CardData.CardRarity:
	if _weapon != null:
		return _weapon.rarity
	return _piece.rarity if _piece != null else CardData.CardRarity.UNSET

func _replaced_rarity() -> CardData.CardRarity:
	if _replaced_weapon != null:
		return _replaced_weapon.rarity
	return _replaced.rarity if _replaced != null else CardData.CardRarity.UNSET

# Puts `rarity`'s finish on `layer` (reusing `material`), or takes it off
# for one with none. Returns the material to keep.
func _finish_on(layer: Control, rarity: CardData.CardRarity, material: ShaderMaterial) -> ShaderMaterial:
	if _finish == null or not _finish.has_finish(rarity):
		layer.material = null
		return material
	var finished: ShaderMaterial = _finish.name_material(rarity, material, name_finish_shader_path)
	layer.material = finished
	return finished if finished != null else material

# --- Layout ---

func _px(value: float) -> float:
	return value * plate_scale

func _font_px(value: int) -> int:
	return maxi(roundi(float(value) * plate_scale), 1)

func _pitch(font_px: int) -> float:
	return roundf(float(font_px) * line_pitch_em)

func _paragraph(text: String, font: Font, font_px: int, width: float) -> TextParagraph:
	var paragraph := TextParagraph.new()
	paragraph.width = width
	paragraph.add_string(text, font, font_px)
	return paragraph

# The effect, with each card it names (card_links_enabled) in the rules
# bold and its characters noted in _links. Without links, _paragraph().
func _rules_paragraph(text: String, font_px: int, width: float) -> TextParagraph:
	_links.clear()
	var cards: Array[CardData] = _named_cards() if card_links_enabled else ([] as Array[CardData])
	if cards.is_empty():
		return _paragraph(text, _rules_font, font_px, width)
	if _rules_bold_font == null:
		_rules_bold_font = InkType.text_bold_font()
	var paragraph := TextParagraph.new()
	paragraph.width = width
	var at: int = 0
	while at < text.length():
		var found: int = -1
		var found_card: CardData = null
		for card in cards:
			var index: int = _find_word(text, card.card_name, at)
			if index >= 0 and (found < 0 or index < found):
				found = index
				found_card = card
		if found < 0:
			paragraph.add_string(text.substr(at), _rules_font, font_px)
			break
		if found > at:
			paragraph.add_string(text.substr(at, found - at), _rules_font, font_px)
		var end: int = found + found_card.card_name.length()
		paragraph.add_string(found_card.card_name, _rules_bold_font, font_px)
		_links.append({"card": found_card, "start": found, "end": end})
		at = end
	return paragraph

# `word` in `text` from `from`, standing alone (no letter either side) -
# "Lash", never the lash in "Slashes"; -1 for none.
static func _find_word(text: String, word: String, from: int) -> int:
	if word.is_empty():
		return -1
	var index: int = text.find(word, from)
	while index >= 0:
		var before: bool = index == 0 or not _is_letter(text[index - 1])
		var after_index: int = index + word.length()
		var after: bool = after_index >= text.length() or not _is_letter(text[after_index])
		if before and after:
			return index
		index = text.find(word, index + 1)
	return -1

static func _is_letter(character: String) -> bool:
	return character.to_lower() != character.to_upper()

# Each named card's box on each line it sits on, where _draw_paragraph()
# draws it: the line centred, the box its pitch tall.
func _place_links() -> void:
	_link_rects.clear()
	if _rules == null or _links.is_empty():
		return
	var server: TextServer = TextServerManager.get_primary_interface()
	var pitch: float = _pitch(_font_px(rules_size_px))
	var left: float = _px(padding_px)
	for line in _rules.get_line_count():
		var span: Vector2i = _rules.get_line_range(line)
		var line_left: float = left + roundf((_rules.width - _rules.get_line_width(line)) / 2.0)
		var top: float = _rules_top + pitch * float(line)
		for link: Dictionary in _links:
			var start: int = maxi(int(link["start"]), span.x)
			var end: int = mini(int(link["end"]), span.y)
			if start >= end:
				continue
			for run: Vector2 in server.shaped_text_get_selection(_rules.get_line_rid(line), start, end):
				_link_rects.append({"rect": Rect2(line_left + run.x, top, run.y - run.x, pitch), "card": link["card"]})

# For probes: each named card's box, {"rect", "card"}, in plate pixels.
func get_link_rects() -> Array[Dictionary]:
	return _link_rects

# For probes: the card shown for a hovered name, or null.
func get_link_preview() -> CardView:
	return _link_preview if _link_preview != null and _link_preview.visible else null

func _link_at(at: Vector2) -> CardData:
	for link: Dictionary in _link_rects:
		if (link["rect"] as Rect2).has_point(at):
			return link["card"]
	return null

# Shows `card` beside the plate (null: the pinned card, else nothing).
func _set_hovered_link(card: CardData) -> void:
	if card == null:
		card = _pinned_link
	if card == _hovered_link:
		return
	_hovered_link = card
	if card == null:
		if _link_preview != null:
			_link_preview.visible = false
		return
	if _link_preview == null:
		var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
		if scene == null:
			return
		_link_preview = scene.instantiate() as CardView
		_link_preview.name = "CardLinkPreview"
		_link_preview.hover_enabled = false
		add_child(_link_preview)
		_ignore_mouse(_link_preview)
	_link_preview.set_card_data(card)
	_link_preview.visible = true
	_place_link_preview()

func _place_link_preview() -> void:
	if _link_preview == null or not _link_preview.visible or not is_inside_tree():
		return
	_link_preview.pivot_offset = Vector2.ZERO
	_link_preview.scale = Vector2.ONE * card_link_preview_scale
	var shown: Vector2 = _link_preview.card_size * card_link_preview_scale
	var screen: Rect2 = get_viewport_rect()
	var origin: Vector2 = get_global_transform().origin
	var at := Vector2(_card_rect.end.x + card_link_gap_px, _card_rect.get_center().y - shown.y * 0.5)
	if origin.x + at.x + shown.x > screen.end.x:
		at.x = _card_rect.position.x - card_link_gap_px - shown.x
	at.y = clampf(at.y, screen.position.y - origin.y, screen.end.y - origin.y - shown.y)
	_link_preview.position = at.round()

# `node` and everything under it let the mouse through.
static func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

func _paragraph_height(paragraph: TextParagraph, font_px: int) -> float:
	return _pitch(font_px) * float(paragraph.get_line_count()) if paragraph != null else 0.0

func _relayout() -> void:
	if _face == null:
		return
	if _rules_font == null:
		_rules_font = InkType.text_font()
	if _lore_font == null:
		_lore_font = load(LORE_FONT_PATH) as Font
	var width: float = roundf(_px(plate_width))
	var pad: float = _px(padding_px)
	var text_width: float = width - pad * 2.0
	var art: float = roundf(_px(art_size_px))
	_art_rect = Rect2(roundf((width - art) / 2.0), roundf(pad), art, art)
	var name_px: int = _font_px(name_size_px)
	var name_font: Font = _numeral_font
	_name_baseline = roundf(_art_rect.end.y + _px(name_gap_px) + name_font.get_ascent(name_px))
	var y: float = _name_baseline + name_font.get_descent(name_px)
	# The type line: glyph and label centred together, the glyph's middle
	# on the label's cap middle.
	var label_px: int = _font_px(type_size_px)
	if _label_font == null or _label_font_px != label_px:
		_label_font = InkType.tracked(InkType.text_bold_font(), label_px, type_tracking_em)
		_label_font_px = label_px
	_type_baseline = roundf(y + _px(type_gap_px) + _label_font.get_ascent(label_px))
	var glyph: float = roundf(_px(type_glyph_px))
	var label_width: float = InkType.width(_label_font, get_type_label(), label_px)
	var row_width: float = glyph + _px(type_glyph_gap_px) + label_width
	var row_left: float = roundf((width - row_width) / 2.0)
	var cap_middle: float = _type_baseline - float(label_px) * 0.36
	_type_glyph_rect = Rect2(row_left, roundf(cap_middle - glyph / 2.0), glyph, glyph)
	_type_label_left = roundf(row_left + glyph + _px(type_glyph_gap_px))
	y = maxf(_type_baseline + _label_font.get_descent(label_px), _type_glyph_rect.end.y)
	# The stat row: no room at all while it says nothing.
	_stat_baseline = -1.0
	if not _stat_text.is_empty():
		var stat_px: int = _font_px(stat_row_size_px)
		_stat_baseline = roundf(y + _px(stat_row_gap_px) + _rules_font.get_ascent(stat_px))
		y = _stat_baseline + _rules_font.get_descent(stat_px)
	# The effect's block, rules_lines tall whatever it holds.
	var rules_px: int = _font_px(rules_size_px)
	_rules_top = roundf(y + _px(rules_gap_px))
	_rules = null
	var rules_text: String = _shown_rules()
	if not rules_text.is_empty():
		_rules = _rules_paragraph(rules_text, rules_px, text_width)
	_place_links()
	y = _rules_top + _pitch(rules_px) * float(rules_lines)
	# The hairline, then the lore's block, lore_lines tall.
	_hairline_y = roundf(y + _px(lore_gap_px))
	_lore_top = _hairline_y + _px(lore_gap_px)
	var lore_px: int = _font_px(lore_size_px)
	_lore = null
	if not _shown_lore().is_empty():
		_lore = _paragraph(_shown_lore(), _lore_font, lore_px, text_width)
	y = _lore_top + _pitch(lore_px) * float(lore_lines)
	_card_rect = Rect2(Vector2.ZERO, Vector2(width, roundf(y + pad)))
	_layout_strip(width, pad, text_width, label_px, name_font)
	_plate_size = Vector2(width, _strip_rect.end.y if _strip_rect.has_area() else _card_rect.end.y)
	size = _plate_size
	custom_minimum_size = _plate_size
	for child: Control in [_paper, _face]:
		child.position = Vector2.ZERO
		child.size = _plate_size
	_place_shadow(_shadow, _card_rect)
	_strip_shadow.visible = _strip_rect.has_area()
	if _strip_rect.has_area():
		_place_shadow(_strip_shadow, _strip_rect)
	# The name's own box: from its left edge, so the finish's u runs over
	# the word itself.
	var name_text: String = _shown_name()
	var name_width: float = InkType.width(name_font, name_text, name_px)
	_name_layer.position = Vector2(roundf((width - name_width) / 2.0), 0.0)
	_name_layer.size = Vector2(maxf(name_width, 1.0), _plate_size.y)
	if _name_finish != null:
		_name_finish.set_shader_parameter("text_width_px", name_width)
	_place_link_preview()
	_redraw()

# An offer's strip under the plate: REPLACES <name> on one baseline,
# centred together, the worn piece's effect under it; then the choices.
# No strip (an empty rect) when the plate offers nothing.
func _layout_strip(width: float, pad: float, text_width: float, label_px: int, name_font: Font) -> void:
	_strip_rect = Rect2()
	_replaces = null
	_max_hp_line = null
	_action_rects.clear()
	var replaced_name_left: float = 0.0
	var replaced_name_width: float = 0.0
	if _has_replaced() or _show_actions:
		var top: float = roundf(_card_rect.end.y + _px(strip_gap_px))
		var y: float = top + pad * 0.75
		if _has_replaced():
			var replaced_px: int = _font_px(replaced_name_size_px)
			var label_width: float = InkType.width(_label_font, replaces_label_text, label_px)
			replaced_name_width = InkType.width(name_font, _replaced_name(), replaced_px)
			var row_width: float = label_width + _px(replaces_label_gap_px) + replaced_name_width
			_replaces_label_left = roundf((width - row_width) / 2.0)
			replaced_name_left = roundf(_replaces_label_left + label_width + _px(replaces_label_gap_px))
			_replaces_baseline = roundf(y + maxf(_label_font.get_ascent(label_px), name_font.get_ascent(replaced_px)))
			_replaces_top = _replaces_baseline + maxf(_label_font.get_descent(label_px), name_font.get_descent(replaced_px))
			var replaces_px: int = _font_px(replaces_size_px)
			_replaces = _paragraph(_replaced_rules(), _rules_font, replaces_px, text_width)
			y = _replaces_top + _paragraph_height(_replaces, replaces_px)
		var max_hp_text_now: String = max_hp_text()
		if not max_hp_text_now.is_empty():
			var max_hp_px: int = _font_px(replaces_size_px)
			_max_hp_line = _paragraph(max_hp_text_now, _rules_font, max_hp_px, text_width)
			_max_hp_top = y
			y += _paragraph_height(_max_hp_line, max_hp_px)
		if _show_actions:
			if _action_font == null:
				_action_font = InkType.tracked(InkType.text_bold_font(), action_size_px, caps_tracking_em)
			var row_top: float = roundf(y + (_px(actions_gap_px) if _has_replaced() or _max_hp_line != null else 0.0))
			var row_height: float = _px(action_row_height_px)
			var half: float = text_width / 2.0
			_action_rects.append(Rect2(pad, row_top, half, row_height))
			_action_rects.append(Rect2(pad + half, row_top, half, row_height))
			y = row_top + row_height
		_strip_rect = Rect2(0.0, top, width, roundf(y + pad * 0.75 - top))
	_replaced_name_layer.position = Vector2(replaced_name_left, 0.0)
	_replaced_name_layer.size = Vector2(maxf(replaced_name_width, 1.0), maxf(_strip_rect.end.y, 1.0))
	if _replaced_name_finish != null:
		_replaced_name_finish.set_shader_parameter("text_width_px", replaced_name_width)

func _place_shadow(shadow: Panel, rect: Rect2) -> void:
	shadow.position = rect.position
	shadow.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.94, 0.91, 0.86, 0.0)
	style.set_corner_radius_all(roundi(_px(corner_radius_px)))
	style.shadow_color = Color(0.0, 0.0, 0.0, shadow_alpha)
	style.shadow_size = roundi(_px(shadow_size_px))
	style.shadow_offset = Vector2(0.0, _px(shadow_offset_px))
	shadow.add_theme_stylebox_override("panel", style)

# The choice's label.
func _choice_label(index: int) -> String:
	return take_text if index == Choice.TAKE else leave_text

# --- Draw ---

func _redraw() -> void:
	for layer: Control in [_paper, _face, _name_layer, _replaced_name_layer]:
		if layer != null:
			layer.queue_redraw()

func _draw_paper() -> void:
	# The card's own trick: the paper shader reads its seed from red.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(_paper_seed, 0.0, 0.0, 1.0)
	style.set_corner_radius_all(roundi(_px(corner_radius_px)))
	_paper.draw_style_box(style, _card_rect)
	if _strip_rect.has_area():
		_paper.draw_style_box(style, _strip_rect)

func _draw_face() -> void:
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_border_width_all(maxi(roundi(plate_scale), 1))
	frame.border_color = Color(ink, frame_alpha)
	frame.set_corner_radius_all(roundi(_px(corner_radius_px)))
	_face.draw_style_box(frame, _card_rect)
	if _strip_rect.has_area():
		_face.draw_style_box(frame, _strip_rect)
	if not has_item():
		return
	var art: Texture2D = _shown_art()
	if art != null:
		_face.draw_texture_rect(art, _art_rect, false)
	else:
		_face.draw_rect(_art_rect, placeholder_color)
		# The Bedroll: its own ink glyph on the tone, for art.
		if _bedroll != null:
			var side: float = minf(_art_rect.size.x, _art_rect.size.y) * 0.6
			var glyph_rect := Rect2(_art_rect.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
			InkGlyph.draw(_face, InkGlyph.Kind.BEDROLL, glyph_rect, maxf(_px(type_glyph_stroke_px) * 2.0, 1.0), Color(ink, maxf(placeholder_initial_alpha, 0.7)))
		var initial: String = "" if _bedroll != null else _shown_name().left(1).to_upper()
		var initial_px: int = _font_px(placeholder_initial_size_px)
		var font: Font = _numeral_font
		var initial_width: float = InkType.width(font, initial, initial_px)
		var baseline: float = _art_rect.get_center().y + (font.get_ascent(initial_px) - font.get_descent(initial_px)) * 0.5
		InkType.draw_run(_face, font, initial, Vector2(roundf(_art_rect.get_center().x - initial_width / 2.0), roundf(baseline)), initial_px, Color(ink, placeholder_initial_alpha))
	var label_px: int = _font_px(type_size_px)
	var type_color := Color(ink, ink.a * type_alpha)
	InkGlyph.draw(_face, _type_glyph(), _type_glyph_rect, maxf(_px(type_glyph_stroke_px), 1.0), type_color)
	InkType.draw_run(_face, _label_font, get_type_label(), Vector2(_type_label_left, _type_baseline), label_px, type_color)
	if _stat_baseline >= 0.0:
		var stat_px: int = _font_px(stat_row_size_px)
		var stat_width: float = InkType.width(_rules_font, _stat_text, stat_px)
		InkType.draw_run(_face, _rules_font, _stat_text, Vector2(roundf((_plate_size.x - stat_width) / 2.0), _stat_baseline), stat_px, ink)
	_draw_paragraph(_rules, _rules_top, _pitch(_font_px(rules_size_px)), ink)
	# The hairline separates the effect from the lore - none with no lore,
	# never a rule alone.
	if _lore != null:
		var hairline_width: float = roundf(_plate_size.x * hairline_width_fraction)
		_face.draw_rect(Rect2(roundf((_plate_size.x - hairline_width) / 2.0), _hairline_y, hairline_width, maxf(roundf(plate_scale), 1.0)), Color(ink, hairline_alpha))
	_draw_paragraph(_lore, _lore_top, _pitch(_font_px(lore_size_px)), ink)
	if _replaces != null:
		InkType.draw_run(_face, _label_font, replaces_label_text, Vector2(_replaces_label_left, _replaces_baseline), label_px, type_color)
		_draw_paragraph(_replaces, _replaces_top, _pitch(_font_px(replaces_size_px)), replaces_color)
	_draw_paragraph(_max_hp_line, _max_hp_top, _pitch(_font_px(replaces_size_px)), replaces_color)
	_draw_actions()

# The name at the layer's own origin - its finish (or flat ink) is the
# layer's material's to colour.
func _draw_name() -> void:
	if not has_item():
		return
	var color: Color = ink
	if _name_layer.material == null and _finish != null:
		color = _finish.common_ink
	InkType.draw_run(_name_layer, _numeral_font, _shown_name(), Vector2(0.0, _name_baseline), _font_px(name_size_px), color)

# The worn piece's (or carried weapon's) name after REPLACES, the same
# way.
func _draw_replaced_name() -> void:
	if not _has_replaced():
		return
	var color: Color = ink
	if _replaced_name_layer.material == null and _finish != null:
		color = _finish.common_ink
	InkType.draw_run(_replaced_name_layer, _numeral_font, _replaced_name(), Vector2(0.0, _replaces_baseline), _font_px(replaced_name_size_px), color)

# The title menu's treatment: each choice centred in its half in tracked
# caps, the focused one in ink with a short hairline to its left, the
# other in the utility grey.
func _draw_actions() -> void:
	if _action_font == null:
		return
	var action_px: int = _font_px(action_size_px)
	for index in _action_rects.size():
		var row: Rect2 = _action_rects[index]
		var label: String = _choice_label(index)
		var label_width: float = InkType.width(_action_font, label, action_px)
		var left: float = roundf(row.get_center().x - label_width / 2.0)
		var baseline: float = roundf(row.get_center().y + float(action_px) * 0.35)
		var inert: bool = index == Choice.TAKE and not take_enabled
		var focused: bool = index == _focus and not inert
		InkType.draw_run(_face, _action_font, label, Vector2(left, baseline), action_px, inert_color if inert else (ink if focused else unfocused_color))
		if focused:
			var thickness: float = maxf(roundf(_px(hairline_thickness_px)), 1.0)
			var hairline_y: float = roundf(baseline - float(action_px) * 0.35 - thickness * 0.5)
			var length: float = _px(focus_hairline_length_px)
			_face.draw_rect(Rect2(left - _px(focus_hairline_gap_px) - length, hairline_y, length, thickness), ink)

# A paragraph line by line at a fixed pitch, each line centred.
func _draw_paragraph(paragraph: TextParagraph, top: float, pitch: float, color: Color) -> void:
	if paragraph == null:
		return
	var left: float = _px(padding_px)
	var y: float = top
	for line in paragraph.get_line_count():
		var line_left: float = left + roundf((paragraph.width - paragraph.get_line_width(line)) / 2.0)
		var baseline_shift: float = pitch - paragraph.get_line_ascent(line) - paragraph.get_line_descent(line)
		paragraph.draw_line(_face.get_canvas_item(), Vector2(line_left, roundf(y + baseline_shift * 0.5)), line, color)
		y += pitch

# --- Input ---

func _hit(position: Vector2) -> int:
	for index in _action_rects.size():
		if _action_rects[index].has_point(position):
			return index
	return -1

func _on_gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		_set_hovered_link(_link_at(motion.position))
	if not _show_actions:
		return
	if motion != null:
		var under: int = _hit(motion.position)
		if under >= 0:
			set_focus(under)
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	var index: int = _hit(button.position)
	if index >= 0:
		activate(index)
