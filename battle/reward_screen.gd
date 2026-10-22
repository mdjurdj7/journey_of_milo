extends CanvasLayer
class_name RewardScreen

# What the fight left. Shown once the battle framing has blended back to
# the follow camera, over the live field dimmed behind it - an interim
# screen standing in for the world-placed RewardSpread, which is kept and
# still selectable (see RegionField.reward_mode).
#
# Two states in one column, swapped in place rather than stacked as two
# screens: the LIST of what's on offer, and the card CHOICE. Taking a
# line strikes it through; the screen closes itself when every line is
# taken, or when WALK ON is pressed, whichever comes first. Skipping is
# final - NONE OF THESE strikes the card line exactly as taking it does,
# because the offer is spent either way.
#
# Everything here is bone on the dimmed field: the world is the dark
# element now, so this reads with the theme's ON-DARK values rather than
# the ink the field HUD uses. That inversion is why the colours are this
# node's own exports rather than theme lookups - the theme's value set
# follows the WORLD's lightness (see BattleTheme.apply_value_set()), and
# this screen is over a scrim, not over the world.

signal closed()
# The weapon line's plate has opened (RegionField plays its reveal), and
# the weapon answered - TAKE or LEAVE on that plate, or left behind on WALK
# ON (taken false). RegionField carries it and logs it.
signal weapon_shown(weapon: WeaponData)
signal weapon_answered(weapon: WeaponData, taken: bool)

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const TAKE_SFX_PATH := "res://assets/audio/cards/card_take.wav"
const GOLD_SFX_PATH := "res://assets/audio/ui/gold_take.wav"
const CHOICE_OPEN_SFX_PATH := "res://assets/audio/ui/3_card_reward.mp3"

@export var scrim_color: Color = Color(0.165, 0.165, 0.18, 0.40)
# Bone - the on-dark ink of the theme's own pair.
@export var bone: Color = Color(0.94, 0.91, 0.86, 1.0)
# Every bone run is drawn over a 1px outline in this, the same
# legibility treatment FloatingNumber and BattleIntent use for text
# sitting directly over the world - the scrim alone doesn't save bone
# text where the sand under it is nearly bone itself. Those two do it
# with Label theme overrides; this screen draws its text, so it draws
# the outline too (see _text()).
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0)
@export var text_outline_px: int = 1
# The card choice names each card's tier under it (COMMON .. ULTRA RARE),
# its size, tracking, gap and dim from this shared CardRarityFinish - see
# _draw_tier_labels().
@export_file("*.tres") var rarity_finish_path: String = "res://battle/card_rarity_finish.tres"

# The list's caps - LEFT BEHIND, each line's TAKE/CHOOSE and WALK ON -
# are the card choice's own tracked caps (22 px at 0.16 em), and the
# actions and WALK ON share its focus language: the utility grey at rest
# (choice_unfocused_color), full bone with the short hairline to the
# left when focused. The mouse focuses by hovering and activates by
# clicking; ui_up/ui_down move through the untaken lines and WALK ON
# (wrapping), ui_accept activates. Nothing is focused until the mouse or
# a key says so. WALK ON is the list's last row, its caps where the
# actions sit; the whole list lifts clear of the Wanderer rather than
# cross him (see _above_wanderer()).
@export_group("Column")
# Wide enough for the Greyshelf's Tail's line on one row - its art, its
# name and CHOOSE in its column.
@export var column_width: float = 420.0:
	set(value):
		column_width = value
		_redraw()
@export var header_text: String = "LEFT BEHIND"
@export var header_size_px: int = 22
@export_range(0.0, 1.0) var header_tracking_em: float = 0.16
@export var header_gap_px: float = 28.0
# Each line: Spectral item text on the left, a tracked caps action on the
# right, a hairline under both. The action has a column of its own,
# action_column_px wide at the column's right (its label right-aligned in
# it, the focus hairline's room included), that the item text never
# enters: the text wraps in what is left, to item_max_lines and then an
# ellipsis, and a wrapped line's row grows by its extra lines - nothing
# overlaps, nothing is squeezed.
@export var line_height_px: float = 44.0:
	set(value):
		line_height_px = value
		_redraw()
@export var action_column_px: float = 152.0:
	set(value):
		action_column_px = value
		_redraw()
@export var item_max_lines: int = 2:
	set(value):
		item_max_lines = value
		_redraw()
@export var item_size_px: int = 26
@export var action_size_px: int = 22
@export_range(0.0, 1.0) var action_tracking_em: float = 0.16
@export var rule_px: float = 1.0
@export var rule_hover_px: float = 2.0
@export_range(0.0, 1.0) var rule_alpha: float = 0.45
@export var strike_px: float = 1.0
@export_range(0.0, 1.0) var taken_alpha: float = 0.45
@export var dismiss_text: String = "WALK ON"
# DECK, on WALK ON's row at the column's left (and on NONE OF THESE's row
# at the cards' left while a choice is open): the deck viewer over the
# screen, deck_view_layer_offset layers up (DeckPanel.open_view()) - the
# screen deaf to its own input while it is open, and the same list or
# choice still there when it closes. The dismiss line's face and size.
@export var deck_text: String = "DECK":
	set(value):
		deck_text = value
		if _draw_layer != null:
			_draw_layer.queue_redraw()
@export var deck_view_layer_offset: int = 1
@export var dismiss_size_px: int = 22
@export_range(0.0, 1.0) var dismiss_tracking_em: float = 0.16
@export_group("")

@export_group("Card Choice")
# The cards: a level row, no container, positioned outright under the
# Column control (see _layout_choice()) - equal size, no rotation, at
# choice_card_scale with card_gap_fraction of a card's width between
# them, centred on the viewport's width with the row's centre line at
# choice_row_centre_fraction of its height. TAKE ONE sits above the row
# (baseline reward_header_gap above the cards' top edge), NONE OF THESE
# below it (reward_decline_gap of clear space under the cards' bottom
# edge - room for a hovered card's growth and its keyword's definition:
# 152 holds the longest, Not So's note, 5 lines on its slip, 12px clear -
# dropping further only to clear the Wanderer, and never past twice that
# gap - see _decline_top()), both centred on the row, both in the
# tracked caps the loot window's choices use. While the choice is open
# the scrim deepens to choice_scrim_alpha, so the cards are the
# foreground; the list keeps scrim_color.
#
# Every size here is at 1080p. The whole offer - cards, gaps, labels -
# scales by one fit factor: the window's height over choice_reference_
# height, held lower where the row would pass choice_max_width_fraction
# of the width or the offer choice_max_height_fraction of the height
# (_choice_fit()), so it stays centred and whole at any window size.
#
# NONE OF THESE and the three cards are one focus set in the title
# menu's language: the decline line in the utility grey at rest, full
# bone with a short hairline to its left when focused (bone, not ink -
# this screen is over the scrim); a card focused is a card hovered.
# The mouse focuses by hovering and activates by clicking; ui_left/
# ui_right move between the cards (wrapping), ui_down drops to the
# decline line and ui_up returns to the cards, ui_accept activates.
# Nothing is focused until the mouse or a key says so.
@export var choice_header_text: String = "TAKE ONE"
@export var choice_count: int = 3
@export_range(1.0, 2.2) var choice_card_scale: float = 1.7:
	set(value):
		choice_card_scale = value
		_relayout_choice()
@export_range(0.0, 1.0) var card_gap_fraction: float = 0.33:
	set(value):
		card_gap_fraction = value
		_relayout_choice()
@export_range(0.0, 1.0) var choice_row_centre_fraction: float = 0.46:
	set(value):
		choice_row_centre_fraction = value
		_relayout_choice()
@export var reward_header_gap: float = 48.0:
	set(value):
		reward_header_gap = value
		_relayout_choice()
@export var reward_decline_gap: float = 152.0:
	set(value):
		reward_decline_gap = value
		_relayout_choice()
@export_range(0.0, 1.0) var choice_scrim_alpha: float = 0.62:
	set(value):
		choice_scrim_alpha = value
		_apply_scrim()
@export var choice_reference_height: float = 1080.0:
	set(value):
		choice_reference_height = value
		_relayout_choice()
@export_range(0.1, 1.0) var choice_max_width_fraction: float = 0.9:
	set(value):
		choice_max_width_fraction = value
		_relayout_choice()
@export_range(0.1, 1.0) var choice_max_height_fraction: float = 0.92:
	set(value):
		choice_max_height_fraction = value
		_relayout_choice()
@export var choice_dismiss_text: String = "NONE OF THESE"
@export var choice_label_size_px: int = 22:
	set(value):
		choice_label_size_px = value
		_relayout_choice()
@export_range(0.0, 1.0) var choice_label_tracking_em: float = 0.16
# The title menu's unfocused item: CardView's keyline_utility.
@export var choice_unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0)
@export var choice_hairline_length_px: float = 28.0
@export var choice_hairline_gap_px: float = 14.0
@export var choice_hairline_thickness_px: float = 1.0
# Where NONE OF THESE would cross the Wanderer's projected silhouette, it
# drops to this far below his feet - never up, and never further than
# twice reward_decline_gap below the row (see _below_wanderer()). Where
# the list would, it lifts to this far above his head (_above_wanderer()).
@export var decline_wanderer_clearance_px: float = 16.0
# His height, for the projected silhouette the decline line must clear.
@export var wanderer_height_m: float = 1.8
@export var card_flight_duration_sec: float = 0.45
# The card being taken (see TakeFeedback.play_sound()) - once, on the choice
# itself, never on hover, the gold line or a skip. A -6 dBFS take at -18
# sits just under the battle's card-play cue (-16).
@export var take_volume_db: float = -18.0
# The gold being taken - once, on the gold line itself, never on hover or
# on any other change to the run's gold. Its file is denser than the
# card take (RMS about -23 against -26 at the same -6 dBFS peak), so -20
# sits it at or just under the card take by ear.
@export var gold_volume_db: float = -20.0
# The card choice opening - once, as TAKE ONE and its cards appear; never
# for the LEFT BEHIND list, and not on NONE OF THESE. 2D on the SFX bus,
# under the battle's card-play cue (-16) at the same -6 dBFS peak.
@export var choice_open_volume_db: float = -20.0:
	set(value):
		choice_open_volume_db = value
		if _choice_open_player != null:
			_choice_open_player.volume_db = choice_open_volume_db
@export var card_flight_end_scale: float = 0.12
@export_group("")

@export_group("Glassbone")
# "Glassbone ×1": the material a win can leave (EnemyData.glassbone_
# reward), its own TAKE line under the gold; left behind on WALK ON.
@export var glassbone_item_format: String = "Glassbone ×%d"
# The art drawn before the line's text, at its own colours and aspect
# (only the line's fade reaches it); empty = the placeholder shard, a
# hairline outline in the line's own colour.
@export var glassbone_icon_path: String = "res://assets/ui/Rewards/Glassbone.png"
# The icon's (or shard's) height as a fraction of item_size_px, and the
# gap between it and the text. 1.25 of the 26 px item is about 32 px at
# 1080p: the sliver runs corner to corner, so its square reads smaller
# than a glyph of the same height.
@export_range(0.2, 2.0) var glassbone_icon_size_em: float = 1.25
@export var glassbone_icon_gap_px: float = 10.0
@export var glassbone_glyph_width_px: float = 1.0
# The gold take's sound, under it - there is no Glassbone take of its own
# yet.
@export var glassbone_volume_db: float = -24.0
@export_group("")

@export_group("Offers")
# A weapon the win left (the Greyshelf's Tail) and a keepsake it left (an
# enemy's drop, or a pack felled together): each its own line, its name
# and art / CHOOSE. CHOOSE opens its offer - the weapon's plate
# (ArmorExamine.setup_weapon(), TAKE and LEAVE, "REPLACES" the weapon
# carried), the keepsake's KeepsakeOffer - offer_layer_offset layers over
# this screen, the screen deaf to its own input until it is answered.
# Either answer strikes the line; WALK ON leaves it behind.
@export var offer_action_text: String = "CHOOSE":
	set(value):
		offer_action_text = value
		for line in _lines:
			if line.id == "weapon" or line.id == "keepsake":
				line.action = offer_action_text
		if _draw_layer != null:
			_draw_layer.queue_redraw()
@export var offer_layer_offset: int = 1:
	set(value):
		offer_layer_offset = value
		var open: CanvasLayer = _open_offer()
		if open != null:
			open.layer = layer + offer_layer_offset
@export_group("")

@export_group("Extra")
# An optional basic fight's extra (EncounterRewards), a Samphire: its own
# line under the gold, its card's name / TAKE - left behind on WALK ON.
# Taken, its face flies to the deck from the line, at samphire_flight_
# start_scale of a card.
@export_range(0.05, 1.0) var samphire_flight_start_scale: float = 0.4
# The Samphire row focused (hovered, or reached by ui_up/ui_down): the card
# it grants shown beside the column - a CardView at samphire_preview_scale,
# samphire_preview_gap_px right of the column, centred on the row. It never
# takes the mouse. Each re-applies live.
@export_range(0.2, 2.0) var samphire_preview_scale: float = 1.0:
	set(value):
		samphire_preview_scale = value
		_sync_samphire_preview()
@export var samphire_preview_gap_px: float = 32.0:
	set(value):
		samphire_preview_gap_px = value
		_sync_samphire_preview()
@export_group("")

enum Mode { LIST, CHOICE }

# One offer. `taken` covers skipped too: an offer that has been answered,
# however it was answered, is struck and cannot be answered again.
class RewardLine:
	var id: String
	var item: String
	var action: String
	# Drawn before the item text: a texture, or the drawn shard when
	# shard_glyph is set and there is none. Neither = text only.
	var icon: Texture2D = null
	var shard_glyph: bool = false
	var taken: bool = false
	var rect: Rect2 = Rect2()

var _lines: Array[RewardLine] = []
var _gold: int = 0
var _glassbone: int = 0
var _pool: RewardPool = null
var _elite_rates: bool = false
var _top_tier: bool = false
# The floor's rates for a normal fight's offer (FightRarityTable, through
# RegionField); null rolls the pool's own. Never read at the elite rates
# or for the top tier first.
var _rarity_rates: RarityRates = null
# The fight's role offers the card choice (RoleReward.offers_cards); its
# extra beside the gold (EncounterRewards.Extra), and the card a Samphire
# extra is.
var _offers_cards: bool = true
var _extra: EncounterRewards.Extra = EncounterRewards.Extra.NONE
var _extra_card: CardData = null
# A Samphire in flight holds the list's own input.
var _samphire_flying: bool = false
# The Samphire row's card, shown while the row is focused (_sync_samphire_
# preview()); made the first time.
var _samphire_preview: CardView = null
# The weapon on offer (offer_weapon()), and its plate while it is open.
var _weapon: WeaponData = null
var _weapon_offer: ArmorExamine = null
# The keepsake on offer (offer_keepsake()), who left it, the offer's scene,
# and that offer while it is open.
var _keepsake: TrinketData = null
var _keepsake_source: String = ""
var _keepsake_offer_scene_path: String = ""
var _keepsake_offer: KeepsakeOffer = null
# The deck viewer opened from DECK (_open_deck_view()), while it is open;
# and whether DECK is under the cursor.
var _deck_view: DeckView = null
var _deck_hovered: bool = false
var _deck_panel: Control = null
var _mode: int = Mode.LIST
var _hovered: int = -1
var _card_views: Array[CardView] = []
var _taking_card: bool = false
# The cards the open choice rolled, for the run log.
var _offered: Array[CardData] = []
# The card row's rect in Column pixels while a choice is open - what the
# choice header, its dismiss and the dismiss hit-test hang off.
var _choice_row: Rect2 = Rect2()
# The open choice's fit factor (_choice_fit()) and what it makes of the
# 1080p sizes: the labels' pixel size and the two gaps.
var _choice_fit_scale: float = 1.0
var _choice_label_px: int = 22
# Each choice card's face rect in Column pixels, in _card_views' order.
var _choice_faces: Array[Rect2] = []
# The tier labels: the shared finish, and its font and size at the fit.
var _rarity_finish: CardRarityFinish = null
var _tier_font: Font = null
var _tier_px: int = 11
var _header_gap_px: float = 48.0
var _decline_gap_px: float = 100.0

var _draw_layer: Control = null
var _scrim: ColorRect = null
# The choice-opening cue's player (choice_open_volume_db) - one, kept, so
# the volume's setter reaches it.
var _choice_open_player: AudioStreamPlayer = null
var _item_font: Font = null
var _header_font: Font = null
var _action_font: Font = null
var _dismiss_font: Font = null
var _choice_font: Font = null
# The card choice's focus: 0..cards-1 a card, _decline_index() the
# decline line, -1 nothing. _decline_hovered is whether the MOUSE is on
# the decline line, so leaving it clears only a mouse focus.
var _choice_focus: int = -1
var _decline_hovered: bool = false
# The list's own: which line (or WALK ON, _walk_on_index()) the mouse is
# on, so leaving it clears only a mouse focus - _hovered is the focus.
var _list_mouse_on: int = -1
# The decline line's top in Column pixels, fixed when the choice opens -
# the field (and its camera) is frozen under this screen.
var _decline_top_px: float = 0.0

# gold is what this fight rolled; pool is the floor's own, already
# chosen; deck_panel is where a taken card flies to; glassbone is what
# the fight's enemies left (0 = no line); elite_rates rolls the card at
# the pool's elite rarity rates; top_tier offers it from the highest tier
# down instead (the region-end fight - RewardPool.roll_top_tier()).
# offers_cards false leaves the card line out (RoleReward.offers_cards -
# every role offers it today); extra is what its role rolled beside the
# gold (an optional basic fight's Samphire - EncounterRewards), and
# extra_card the Samphire a SAMPHIRE extra offers. Called by RegionField
# before the screen is added to the tree.
func setup(gold: int, pool: RewardPool, deck_panel: Control, glassbone: int = 0, elite_rates: bool = false, top_tier: bool = false, offers_cards: bool = true, extra: EncounterRewards.Extra = EncounterRewards.Extra.NONE, extra_card: CardData = null, rarity_rates: RarityRates = null) -> void:
	_gold = gold
	_glassbone = glassbone
	_pool = pool
	_deck_panel = deck_panel
	_elite_rates = elite_rates
	_top_tier = top_tier
	_offers_cards = offers_cards
	_extra = extra
	_extra_card = extra_card
	_rarity_rates = rarity_rates

# The weapon the win left, on a line of its own - never the one carried.
# Called before the screen is added to the tree.
func offer_weapon(weapon: WeaponData) -> void:
	_weapon = weapon if weapon != RunState.weapon else null

# The keepsake the win left, on a line of its own; `source` names who left
# it (KeepsakeOffer's source line), `scene_path` is the offer opened over
# the screen. Called before the screen is added to the tree.
func offer_keepsake(trinket: TrinketData, source: String, scene_path: String) -> void:
	_keepsake = trinket
	_keepsake_source = source
	_keepsake_offer_scene_path = scene_path

func _ready() -> void:
	# The field is frozen under this (RegionField goes back to
	# PROCESS_MODE_DISABLED while the screen is up), which is also what
	# stops click-to-move and WASD - both live on frozen nodes. This layer
	# has to opt out of that freeze or it would stop with them.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_item_font = InkType.numeral_font()
	_header_font = InkType.tracked(InkType.text_bold_font(), header_size_px, header_tracking_em)
	_action_font = InkType.tracked(InkType.text_bold_font(), action_size_px, action_tracking_em)
	_dismiss_font = InkType.tracked(InkType.text_bold_font(), dismiss_size_px, dismiss_tracking_em)
	_choice_font = InkType.tracked(InkType.text_bold_font(), choice_label_size_px, choice_label_tracking_em)
	if not rarity_finish_path.is_empty():
		_rarity_finish = load(rarity_finish_path) as CardRarityFinish
		if _rarity_finish != null:
			_rarity_finish.changed.connect(_relayout_choice)

	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = scrim_color
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: the scrim is what keeps a click from reaching the
	# field underneath and ordering the Wanderer somewhere.
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	_draw_layer = Control.new()
	_draw_layer.name = "Column"
	# The Glassbone art is drawn far under its source size - sampled from
	# its mipmaps, like the card and keepsake art.
	_draw_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw_layer.gui_input.connect(_on_gui_input)
	_draw_layer.draw.connect(_draw_column)
	add_child(_draw_layer)
	# A window resized under an open choice lays it out again.
	_draw_layer.resized.connect(_relayout_choice)

	_build_lines()

func _build_lines() -> void:
	_lines.clear()
	if _gold > 0:
		var gold_line := RewardLine.new()
		gold_line.id = "gold"
		gold_line.item = "%d gold" % _gold
		gold_line.action = "TAKE"
		_lines.append(gold_line)
	if _glassbone > 0:
		var glassbone_line := RewardLine.new()
		glassbone_line.id = "glassbone"
		glassbone_line.item = glassbone_item_format % _glassbone
		glassbone_line.action = "TAKE"
		if not glassbone_icon_path.is_empty():
			glassbone_line.icon = load(glassbone_icon_path) as Texture2D
		glassbone_line.shard_glyph = glassbone_line.icon == null
		_lines.append(glassbone_line)
	if _extra == EncounterRewards.Extra.SAMPHIRE and _extra_card != null:
		var samphire_line := RewardLine.new()
		samphire_line.id = "samphire"
		samphire_line.item = _extra_card.card_name
		samphire_line.action = "TAKE"
		_lines.append(samphire_line)
	if _offers_cards and _pool != null and _pool.has_cards(RunState.character):
		var card_line := RewardLine.new()
		card_line.id = "card"
		card_line.item = "A card"
		card_line.action = "CHOOSE"
		_lines.append(card_line)
	if _keepsake != null:
		var keepsake_line := RewardLine.new()
		keepsake_line.id = "keepsake"
		keepsake_line.item = _keepsake.display_name
		keepsake_line.action = offer_action_text
		keepsake_line.icon = _keepsake.art
		_lines.append(keepsake_line)
	if _weapon != null:
		var weapon_line := RewardLine.new()
		weapon_line.id = "weapon"
		weapon_line.item = _weapon.display_name
		weapon_line.action = offer_action_text
		weapon_line.icon = _weapon.art
		_lines.append(weapon_line)
	if _lines.is_empty():
		close()

# --- Layout ---

func _column_left() -> float:
	return (_draw_layer.size.x - column_width) / 2.0

# Centred on the window, header to WALK ON's row - lifted clear of the
# Wanderer where it would cross him.
func _column_top() -> float:
	var rows_height: float = _rows_height() + line_height_px
	var total: float = float(header_size_px) + header_gap_px + rows_height
	return _above_wanderer((_draw_layer.size.y - total) / 2.0, total)

# The dismiss line's hit rect - WALK ON under the list, or NONE OF THESE
# under the card row while a choice is open.
func _dismiss_rect() -> Rect2:
	if _mode == Mode.CHOICE:
		return _decline_rect()
	return _walk_on_rect()

func _last_line_bottom() -> float:
	return _column_top() + float(header_size_px) + header_gap_px + _rows_height()

# WALK ON's label, right-aligned on the column as the lines' actions are.
func _walk_on_label_left() -> float:
	return roundf(_column_left() + column_width - InkType.width(_dismiss_font, dismiss_text, dismiss_size_px))

# WALK ON's row: the one under the last line, a line tall.
func _walk_on_top() -> float:
	return _last_line_bottom()

# WALK ON's hit rect: the label and the hairline's room to its left, the
# row's height.
func _walk_on_rect() -> Rect2:
	var label_left: float = _walk_on_label_left()
	var left: float = label_left - choice_hairline_gap_px - choice_hairline_length_px
	var right: float = label_left + InkType.width(_dismiss_font, dismiss_text, dismiss_size_px)
	return Rect2(left, _walk_on_top(), right - left, line_height_px)

func _walk_on_index() -> int:
	return _lines.size()

# --- Draw ---

# One bone run with its ink outline under it. The outline carries the
# text's own alpha, so a struck-through line fades as one thing rather
# than leaving a hard outline around faded letters. Returns the advance
# width, like InkType.draw_run(), so callers can still run text along a
# baseline.
func _text(font: Font, text: String, origin: Vector2, size_px: int, color: Color) -> float:
	if font == null or text.is_empty():
		return 0.0
	if text_outline_px > 0:
		var outline: Color = ink
		outline.a = ink.a * color.a
		_draw_layer.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, text_outline_px, outline)
	return InkType.draw_run(_draw_layer, font, text, origin, size_px, color)

func _draw_column() -> void:
	if _mode == Mode.CHOICE:
		_draw_choice()
		return
	var left: float = _column_left()
	var top: float = _column_top()
	var baseline: float = top + float(header_size_px)
	_text(_header_font, header_text, Vector2(left, baseline), header_size_px, bone)

	var y: float = top + float(header_size_px) + header_gap_px
	for index in _lines.size():
		var line: RewardLine = _lines[index]
		var paragraph: TextParagraph = _item_paragraph(line)
		var row_height: float = _row_height(paragraph)
		line.rect = Rect2(left, y, column_width, row_height)
		var text_baseline: float = y + line_height_px * 0.62
		var color: Color = bone
		if line.taken:
			color.a = taken_alpha
		var item_left: float = left + _draw_line_icon(line, left, text_baseline, color)
		var item_origin := Vector2(item_left, text_baseline - paragraph.get_line_ascent(0))
		if text_outline_px > 0:
			var outline: Color = ink
			outline.a = ink.a * color.a
			paragraph.draw_outline(_draw_layer.get_canvas_item(), item_origin, text_outline_px, outline)
		paragraph.draw(_draw_layer.get_canvas_item(), item_origin, color)
		# The action centred on the row - on the text's baseline when it is
		# one line.
		var action_baseline: float = y + (row_height - line_height_px) * 0.5 + line_height_px * 0.62
		var action_width: float = InkType.width(_action_font, line.action, action_size_px)
		var action_left: float = left + column_width - action_width
		var focused: bool = _hovered == index and not line.taken
		var action_color: Color = color
		if not line.taken:
			action_color = bone if focused else choice_unfocused_color
		_text(_action_font, line.action, Vector2(action_left, action_baseline), action_size_px, action_color)
		if focused:
			_draw_hairline(action_left, action_baseline, action_size_px)

		var rule_color: Color = bone
		rule_color.a = rule_alpha * (taken_alpha if line.taken else 1.0)
		var thickness: float = rule_hover_px if (_hovered == index and not line.taken) else rule_px
		_draw_layer.draw_rect(Rect2(left, y + row_height - thickness, column_width, thickness), rule_color)

		if line.taken:
			# Struck through the text itself, not the rule - the offer is
			# crossed off, the line it sat on is still there. A strike for
			# each line of a wrapped one.
			var line_top: float = item_origin.y
			for text_line in _shown_lines(paragraph):
				var strike_y: float = line_top + paragraph.get_line_ascent(text_line) - float(item_size_px) * 0.3
				_draw_layer.draw_rect(Rect2(left, strike_y, column_width, strike_px), color)
				line_top += paragraph.get_line_size(text_line).y
		y += row_height

	var walk_on_focused: bool = _hovered == _walk_on_index()
	var walk_on_left: float = _walk_on_label_left()
	var walk_on_baseline: float = _walk_on_top() + line_height_px * 0.62
	_text(_dismiss_font, dismiss_text, Vector2(walk_on_left, walk_on_baseline), dismiss_size_px, bone if walk_on_focused else choice_unfocused_color)
	if walk_on_focused:
		_draw_hairline(walk_on_left, walk_on_baseline, dismiss_size_px)
	_draw_deck_action()

# A line's icon, centred on the text's caps, or its placeholder shard,
# sitting on the text's baseline, at `left`. Returns how far the text
# moves right for it: 0 when the line has neither.
func _draw_line_icon(line: RewardLine, left: float, baseline: float, color: Color) -> float:
	var height: float = float(item_size_px) * glassbone_icon_size_em
	var top: float = baseline - height
	if line.icon != null:
		var icon_size: Vector2 = line.icon.get_size()
		var width: float = height * (icon_size.x / maxf(icon_size.y, 1.0))
		var mid: float = baseline - float(item_size_px) * 0.35
		# The art keeps its own colours; a taken line fades it with the text.
		var tint := Color(1.0, 1.0, 1.0, color.a)
		_draw_layer.draw_texture_rect(line.icon, Rect2(left, mid - height * 0.5, width, height), false, tint)
		return width + glassbone_icon_gap_px
	if not line.shard_glyph:
		return 0.0
	# A narrow, uneven splinter in outline - drawn in the same hand as the
	# other glyphs, filled by nothing, lit by nothing.
	var width: float = height * 0.5
	var points := PackedVector2Array([
		Vector2(left + width * 0.45, top),
		Vector2(left + width, top + height * 0.3),
		Vector2(left + width * 0.7, top + height),
		Vector2(left, top + height * 0.66),
		Vector2(left + width * 0.45, top),
	])
	_draw_layer.draw_polyline(points, color, glassbone_glyph_width_px, true)
	return width + glassbone_icon_gap_px

# How far a line's text sits right of the column's left for its icon or
# shard - _draw_line_icon()'s return, without drawing.
func _icon_advance(line: RewardLine) -> float:
	var height: float = float(item_size_px) * glassbone_icon_size_em
	if line.icon != null:
		var icon_size: Vector2 = line.icon.get_size()
		return height * (icon_size.x / maxf(icon_size.y, 1.0)) + glassbone_icon_gap_px
	if line.shard_glyph:
		return height * 0.5 + glassbone_icon_gap_px
	return 0.0

# A line's item text, wrapped in the room its icon and the action column
# leave, to item_max_lines and then an ellipsis.
func _item_paragraph(line: RewardLine) -> TextParagraph:
	var paragraph := TextParagraph.new()
	paragraph.width = maxf(column_width - action_column_px - _icon_advance(line), 1.0)
	paragraph.max_lines_visible = maxi(item_max_lines, 1)
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	paragraph.add_string(line.item, _item_font, item_size_px)
	return paragraph

func _shown_lines(paragraph: TextParagraph) -> int:
	return maxi(mini(paragraph.get_line_count(), paragraph.max_lines_visible), 1)

# A row: line_height_px, grown by each line its text wraps onto.
func _row_height(paragraph: TextParagraph) -> float:
	var height: float = line_height_px
	for text_line in range(1, _shown_lines(paragraph)):
		height += paragraph.get_line_size(text_line).y
	return height

func _rows_height() -> float:
	var height: float = 0.0
	for line in _lines:
		height += _row_height(_item_paragraph(line))
	return height

func _redraw() -> void:
	if _draw_layer != null:
		_draw_layer.queue_redraw()

# The focus hairline: choice_hairline_length_px long, choice_hairline_
# gap_px left of a label starting at label_left, at the caps' middle.
func _draw_hairline(label_left: float, baseline: float, size_px: int) -> void:
	var mid: float = baseline - float(size_px) * 0.35
	var hairline_left: float = label_left - choice_hairline_gap_px - choice_hairline_length_px
	_draw_layer.draw_rect(Rect2(hairline_left, mid - choice_hairline_thickness_px * 0.5, choice_hairline_length_px, choice_hairline_thickness_px), bone)

func _draw_choice() -> void:
	var width: float = InkType.width(_choice_font, choice_header_text, _choice_label_px)
	var baseline: float = roundf(_choice_row.position.y - _header_gap_px)
	_text(_choice_font, choice_header_text, Vector2(roundf(_choice_row.position.x + (_choice_row.size.x - width) / 2.0), baseline), _choice_label_px, bone)

	var focused: bool = _choice_focus == _decline_index()
	var label_left: float = _decline_label_left()
	var decline_baseline: float = _decline_top_px + float(_choice_label_px)
	_text(_choice_font, choice_dismiss_text, Vector2(label_left, decline_baseline), _choice_label_px, bone if focused else choice_unfocused_color)
	if focused:
		_draw_hairline(label_left, decline_baseline, _choice_label_px)
	if not _taking_card:
		_draw_deck_action()
	_draw_tier_labels()

# Each offered card's tier, centred under its face (CardRarityFinish):
# Common and Uncommon in dim bone, Rare and Ultra Rare in full, over the
# screen's ink outline. Gone with the row once a card is being taken.
func _draw_tier_labels() -> void:
	if _tier_font == null or _taking_card:
		return
	for index in _choice_faces.size():
		var text: String = tier_label_at(index)
		if text.is_empty():
			continue
		var colour: Color = bone
		if _rarity_finish.tier_label_dimmed(_offered[index].rarity):
			colour.a *= _rarity_finish.tier_label_dim_alpha
		_text(_tier_font, text, tier_label_origin(index), _tier_px, colour)

# The tier named under choice card `index`, "" where there's none.
func tier_label_at(index: int) -> String:
	if _rarity_finish == null or index < 0 or index >= _offered.size() or _offered[index] == null:
		return ""
	return _rarity_finish.tier_label_text(_offered[index].rarity)

# Where that label's run starts: its left edge and baseline, centred under
# the face, tier_label_gap_px (fitted) below it.
func tier_label_origin(index: int) -> Vector2:
	if index < 0 or index >= _choice_faces.size() or _tier_font == null:
		return Vector2.ZERO
	var face: Rect2 = _choice_faces[index]
	var width: float = InkType.width(_tier_font, tier_label_at(index), _tier_px)
	return Vector2(roundf(face.get_center().x - width / 2.0), roundf(face.end.y + _rarity_finish.tier_label_gap_px * _choice_fit_scale + float(_tier_px)))

# The tier line's room under the row at `fit`: its gap and a line and a
# third of its size. 0 with no finish to name tiers from.
func _tier_line_height(fit: float) -> float:
	if _rarity_finish == null:
		return 0.0
	return (_rarity_finish.tier_label_gap_px + float(_rarity_finish.tier_label_size_px) * 1.3) * fit

# The decline label is centred on the row; its hairline hangs off to the
# left of that.
func _decline_label_left() -> float:
	var label_width: float = InkType.width(_choice_font, choice_dismiss_text, _choice_label_px)
	return roundf(_choice_row.position.x + (_choice_row.size.x - label_width) / 2.0)

# The decline line's hit rect: the label and the hairline's room to its
# left, a line and a third tall.
func _decline_rect() -> Rect2:
	var label_left: float = _decline_label_left()
	var left: float = label_left - choice_hairline_gap_px - choice_hairline_length_px
	var right: float = label_left + InkType.width(_choice_font, choice_dismiss_text, _choice_label_px)
	return Rect2(left, _decline_top_px, right - left, float(_choice_label_px) * 1.3)

# reward_decline_gap (fitted) under the row, kept clear of the Wanderer -
# only within the space under the row, never back up onto the cards.
func _decline_top() -> float:
	var bottom: float = _choice_row.end.y + _tier_line_height(_choice_fit_scale)
	return _below_wanderer(bottom + _decline_gap_px, float(_choice_label_px) * 1.3, bottom + _decline_gap_px * 2.0)

# A line of caps `line_height` tall, wanted at `top`: where it would cross
# the Wanderer's projected silhouette (feet to wanderer_height_m, grown by
# decline_wanderer_clearance_px), it drops to that far below his feet -
# only ever down, never above him - but no lower than max_top, so it
# stays with what it belongs to even if that leaves it on his feet.
func _below_wanderer(top: float, line_height: float, max_top: float) -> float:
	var span: Vector2 = _wanderer_span()
	var crosses: bool = span != Vector2.ZERO and top < span.y and top + line_height > span.x
	if crosses:
		top = maxf(top, minf(span.y, max_top))
	return roundf(top)

# A block `height` tall, wanted at `top`: where it would cross the
# Wanderer's projected silhouette (grown by decline_wanderer_clearance_
# px), it lifts to end that far above his head - only ever up, and never
# off the top of the window.
func _above_wanderer(top: float, height: float) -> float:
	var span: Vector2 = _wanderer_span()
	if span != Vector2.ZERO and top < span.y and top + height > span.x:
		top = maxf(minf(top, span.x - height), 0.0)
	return roundf(top)

# The Wanderer's projected silhouette as (top, bottom) in screen y, his
# head to his feet, grown by decline_wanderer_clearance_px; ZERO when
# there is no camera or no Wanderer in front of it.
func _wanderer_span() -> Vector2:
	var camera := get_viewport().get_camera_3d()
	var found: Array[Node] = get_tree().get_nodes_in_group("wanderer")
	var wanderer: Node3D = found[0] as Node3D if not found.is_empty() else null
	if camera == null or wanderer == null:
		return Vector2.ZERO
	var feet: Vector3 = wanderer.global_position
	var head: Vector3 = feet + Vector3.UP * wanderer_height_m
	if camera.is_position_behind(feet) or camera.is_position_behind(head):
		return Vector2.ZERO
	var feet_y: float = camera.unproject_position(feet).y
	var head_y: float = camera.unproject_position(head).y
	return Vector2(head_y - decline_wanderer_clearance_px, feet_y + decline_wanderer_clearance_px)

# --- Input ---

func _on_gui_input(event: InputEvent) -> void:
	if _extra_busy():
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		var over_deck: bool = _deck_rect().has_point(motion.position) and not _taking_card
		if over_deck != _deck_hovered:
			_deck_hovered = over_deck
			_draw_layer.queue_redraw()
		if _mode == Mode.CHOICE:
			var over: bool = _decline_rect().has_point(motion.position)
			if over and not _decline_hovered:
				_set_choice_focus(_decline_index())
			elif not over and _decline_hovered and _choice_focus == _decline_index():
				_set_choice_focus(-1)
			_decline_hovered = over
			return
		var under: int = _line_at(motion.position)
		if under < 0 and _walk_on_rect().has_point(motion.position):
			under = _walk_on_index()
		if under != _list_mouse_on:
			if under >= 0:
				_set_list_focus(under)
			elif _hovered == _list_mouse_on:
				_set_list_focus(-1)
			_list_mouse_on = under
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	if _deck_rect().has_point(button.position) and not _taking_card:
		_open_deck_view()
		_draw_layer.accept_event()
		return
	if _dismiss_rect().has_point(button.position):
		_on_dismiss()
		_draw_layer.accept_event()
		return
	if _mode != Mode.LIST:
		return
	var index: int = _line_at(button.position)
	if index >= 0:
		_take_line(index)
		_draw_layer.accept_event()

# --- Card choice focus ---

func _decline_index() -> int:
	return _card_views.size()

# One focus across the cards and the decline line: a focused card shows
# as hovered (CardView.set_hovered()), the decline line lights.
func _set_choice_focus(index: int) -> void:
	if index == _choice_focus:
		return
	if _choice_focus >= 0 and _choice_focus < _card_views.size() and is_instance_valid(_card_views[_choice_focus]):
		_card_views[_choice_focus].set_hovered(false)
	_choice_focus = index
	if _choice_focus >= 0 and _choice_focus < _card_views.size() and is_instance_valid(_card_views[_choice_focus]):
		_card_views[_choice_focus].set_hovered(true)
	_draw_layer.queue_redraw()

func _on_choice_card_mouse_entered(index: int) -> void:
	if not _taking_card and not _deck_view_open():
		_set_choice_focus(index)

func _on_choice_card_mouse_exited(index: int) -> void:
	if not _taking_card and _choice_focus == index:
		_set_choice_focus(-1)

func _set_list_focus(index: int) -> void:
	if index == _hovered:
		return
	_hovered = index
	_draw_layer.queue_redraw()
	_sync_samphire_preview()

# The Samphire row's card beside the column while that row is focused in
# the list and not yet taken; hidden otherwise.
func _sync_samphire_preview() -> void:
	if _draw_layer == null:
		return
	var line: RewardLine = _lines[_hovered] if _hovered >= 0 and _hovered < _lines.size() else null
	var wanted: bool = _mode == Mode.LIST and line != null and line.id == "samphire" and not line.taken and _extra_card != null
	if not wanted:
		if _samphire_preview != null and is_instance_valid(_samphire_preview):
			_samphire_preview.visible = false
		return
	if _samphire_preview == null or not is_instance_valid(_samphire_preview):
		var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
		if scene == null:
			return
		_samphire_preview = scene.instantiate() as CardView
		_samphire_preview.hover_enabled = false
		_draw_layer.add_child(_samphire_preview)
		_samphire_preview.set_card_data(_extra_card)
		_ignore_mouse(_samphire_preview)
	_samphire_preview.pivot_offset = Vector2.ZERO
	_samphire_preview.scale = Vector2.ONE * samphire_preview_scale
	var shown_size: Vector2 = _samphire_preview.card_size * samphire_preview_scale
	_samphire_preview.position = Vector2(line.rect.end.x + samphire_preview_gap_px, line.rect.get_center().y - shown_size.y * 0.5).round()
	_samphire_preview.visible = true

# `node` and everything under it let the mouse through.
func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

# The untaken lines, then WALK ON - what ui_up/ui_down move through.
func _list_focusable() -> Array[int]:
	var indices: Array[int] = []
	for index in _lines.size():
		if not _lines[index].taken:
			indices.append(index)
	indices.append(_walk_on_index())
	return indices

func _list_input(event: InputEvent) -> void:
	var focusable: Array[int] = _list_focusable()
	var at: int = focusable.find(_hovered)
	if event.is_action_pressed("ui_down"):
		_set_list_focus(focusable[posmod(at + 1, focusable.size())] if at >= 0 else focusable[0])
	elif event.is_action_pressed("ui_up"):
		_set_list_focus(focusable[posmod(at - 1, focusable.size())] if at >= 0 else focusable[focusable.size() - 1])
	elif event.is_action_pressed("ui_accept"):
		if _hovered == _walk_on_index():
			_on_dismiss()
		elif at >= 0:
			_take_line(_hovered)
	else:
		return
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _extra_busy():
		return
	if _mode == Mode.LIST:
		_list_input(event)
		return
	if _mode != Mode.CHOICE or _taking_card or _card_views.is_empty():
		return
	var cards: int = _card_views.size()
	var on_card: bool = _choice_focus >= 0 and _choice_focus < cards
	if event.is_action_pressed("ui_right"):
		_set_choice_focus(posmod(_choice_focus + 1, cards) if on_card else 0)
	elif event.is_action_pressed("ui_left"):
		_set_choice_focus(posmod(_choice_focus - 1, cards) if on_card else cards - 1)
	elif event.is_action_pressed("ui_down"):
		_set_choice_focus(_decline_index())
	elif event.is_action_pressed("ui_up"):
		if not on_card:
			_set_choice_focus(int(float(cards) / 2.0))
	elif event.is_action_pressed("ui_accept"):
		if on_card:
			var card_view: CardView = _card_views[_choice_focus]
			_on_choice_clicked(card_view.card_data, card_view)
		elif _choice_focus == _decline_index():
			_on_dismiss()
	else:
		return
	get_viewport().set_input_as_handled()

func _line_at(position: Vector2) -> int:
	for index in _lines.size():
		if _lines[index].rect.has_point(position) and not _lines[index].taken:
			return index
	return -1

func _on_dismiss() -> void:
	if _mode == Mode.CHOICE:
		# Skipping is final: the offer is spent whether or not a card was
		# taken, so the line is struck exactly as taking would.
		if not _taking_card:
			RunLogger.reward_cards("fight", _offered, null)
		_finish_card_line()
		return
	close()

func _take_line(index: int) -> void:
	var line: RewardLine = _lines[index]
	if line.taken or _extra_busy():
		return
	match line.id:
		"gold":
			RunState.add_gold(_gold)
			RunLogger.event("reward_gold", {"source": "fight", "amount": _gold, "gold_after": RunState.gold})
			TakeFeedback.play_sound(get_tree(), GOLD_SFX_PATH, gold_volume_db, "GoldTakeAudio", "RewardScreen")
			print("RewardScreen: took %d gold (run total %d)." % [_gold, RunState.gold])
			line.taken = true
			_hovered = -1
			_draw_layer.queue_redraw()
			_close_if_spent()
		"glassbone":
			RunState.add_glassbone(_glassbone)
			RunLogger.event("reward_glassbone", {"source": "fight", "amount": _glassbone, "glassbone_after": RunState.glassbone})
			TakeFeedback.play_sound(get_tree(), GOLD_SFX_PATH, glassbone_volume_db, "GlassboneTakeAudio", "RewardScreen")
			print("RewardScreen: took %d Glassbone (run total %d)." % [_glassbone, RunState.glassbone])
			line.taken = true
			_hovered = -1
			_draw_layer.queue_redraw()
			_close_if_spent()
		"card":
			_open_choice()
		"samphire":
			_take_samphire(line)
		"weapon":
			_open_weapon_offer(line)
		"keepsake":
			_open_keepsake_offer(line)

# --- Extra ---

# The Samphire is on its way to the deck, or a view is open over the screen.
func _extra_busy() -> bool:
	return _samphire_flying or _deck_view_open() or _open_offer() != null

func _weapon_offer_open() -> bool:
	return _weapon_offer != null and is_instance_valid(_weapon_offer)

func _keepsake_offer_open() -> bool:
	return _keepsake_offer != null and is_instance_valid(_keepsake_offer)

# The weapon's plate or the keepsake's offer, whichever is open over the
# screen; null with neither.
func _open_offer() -> CanvasLayer:
	if _weapon_offer_open():
		return _weapon_offer
	if _keepsake_offer_open():
		return _keepsake_offer
	return null

# The weapon's plate over the screen, first loot's reveal; answered, its
# line is struck.
func _open_weapon_offer(line: RewardLine) -> void:
	if _weapon == null or _open_offer() != null:
		return
	_weapon_offer = ArmorExamine.new()
	_weapon_offer.name = "WeaponOffer"
	_weapon_offer.setup_weapon(_weapon, Rect2(), RunState.weapon, true, true)
	_weapon_offer.closed.connect(_on_weapon_offer_closed.bind(line))
	add_child(_weapon_offer)
	# Its own _ready() puts it on layer 100 - this screen's.
	_weapon_offer.layer = layer + offer_layer_offset
	_set_list_focus(-1)
	_list_mouse_on = -1
	weapon_shown.emit(_weapon)

func _on_weapon_offer_closed(taken: bool, line: RewardLine) -> void:
	_weapon_offer = null
	line.taken = true
	weapon_answered.emit(_weapon, taken)
	_draw_layer.queue_redraw()
	_close_if_spent()

# For probes: the weapon's plate while it is open, else null.
func get_weapon_offer() -> ArmorExamine:
	return _weapon_offer if _weapon_offer_open() else null

# The keepsake's offer over the screen - TAKE / LEAVE, or TAKE / KEEP
# CURRENT on a full slot; it takes, logs and sounds the choice itself.
# Answered, its line is struck.
func _open_keepsake_offer(line: RewardLine) -> void:
	if _keepsake == null or _open_offer() != null:
		return
	var scene := load(_keepsake_offer_scene_path) as PackedScene
	if scene == null:
		push_warning("RewardScreen: could not load %s; no keepsake offer." % _keepsake_offer_scene_path)
		return
	_keepsake_offer = scene.instantiate() as KeepsakeOffer
	_keepsake_offer.setup(_keepsake, RunState.keepsake, _keepsake_source)
	_keepsake_offer.closed.connect(_on_keepsake_offer_closed.bind(line))
	add_child(_keepsake_offer)
	# Its own _ready() puts it on layer 100 - this screen's.
	_keepsake_offer.layer = layer + offer_layer_offset
	_set_list_focus(-1)
	_list_mouse_on = -1

func _on_keepsake_offer_closed(_taken: bool, line: RewardLine) -> void:
	_keepsake_offer = null
	line.taken = true
	_draw_layer.queue_redraw()
	_close_if_spent()

# For probes: the keepsake's offer while it is open, else null.
func get_keepsake_offer() -> KeepsakeOffer:
	return _keepsake_offer if _keepsake_offer_open() else null

func _deck_view_open() -> bool:
	return _deck_view != null and is_instance_valid(_deck_view)

# DECK's label: on WALK ON's row at the column's left, or - a choice
# open - on NONE OF THESE's row at the cards' left. Its baseline-left.
func _deck_label_origin() -> Vector2:
	if _mode == Mode.CHOICE:
		return Vector2(roundf(_choice_row.position.x), _decline_top_px + float(_choice_label_px))
	return Vector2(roundf(_column_left()), _walk_on_top() + line_height_px * 0.62)

func _deck_font() -> Font:
	return _choice_font if _mode == Mode.CHOICE else _dismiss_font

func _deck_size() -> int:
	return _choice_label_px if _mode == Mode.CHOICE else dismiss_size_px

# DECK's hit rect: its label and the hairline's room to its right, its row's
# height.
func _deck_rect() -> Rect2:
	var origin: Vector2 = _deck_label_origin()
	var width: float = InkType.width(_deck_font(), deck_text, _deck_size())
	var height: float = float(_deck_size()) * 1.3 if _mode == Mode.CHOICE else line_height_px
	var top: float = _decline_top_px if _mode == Mode.CHOICE else _walk_on_top()
	return Rect2(origin.x, top, width + choice_hairline_gap_px + choice_hairline_length_px, height)

func _draw_deck_action() -> void:
	var origin: Vector2 = _deck_label_origin()
	_text(_deck_font(), deck_text, origin, _deck_size(), bone if _deck_hovered else choice_unfocused_color)
	if _deck_hovered:
		_draw_hairline(origin.x, origin.y, _deck_size())

# The whole deck, over this screen; the list or choice left as it was.
func _open_deck_view() -> void:
	if _deck_view_open():
		return
	var title: Variant = _deck_panel.get("deck_title") if _deck_panel != null else null
	_deck_view = DeckPanel.open_view(get_tree(), RunState.deck, str(title) if title != null else deck_text.capitalize(), layer + deck_view_layer_offset)
	_deck_view.closed.connect(func() -> void:
		_deck_view = null
		_deck_hovered = false
		_draw_layer.queue_redraw())
	_deck_hovered = false
	if _mode == Mode.CHOICE:
		_set_choice_focus(-1)
	else:
		_set_list_focus(-1)
	_draw_layer.queue_redraw()

# The Samphire into the deck: its face, from the line, flies to the deck
# readout; the screen closes, if this was the last line, once it lands.
func _take_samphire(line: RewardLine) -> void:
	var card: CardData = RunState.add_card(_extra_card)
	RunLogger.event("reward_samphire", {"source": "fight", "card": card.card_name, "deck_size": RunState.deck.size()})
	TakeFeedback.play_sound(get_tree(), TAKE_SFX_PATH, take_volume_db, "SamphireTakeAudio", "RewardScreen")
	print("RewardScreen: took '%s' (deck now %d)." % [card.card_name, RunState.deck.size()])
	line.taken = true
	_hovered = -1
	_draw_layer.queue_redraw()
	_sync_samphire_preview()
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		_close_if_spent()
		return
	var card_view := scene.instantiate() as CardView
	card_view.hover_enabled = false
	_draw_layer.add_child(card_view)
	card_view.set_card_data(card)
	card_view.pivot_offset = Vector2.ZERO
	card_view.scale = Vector2.ONE * samphire_flight_start_scale
	card_view.position = line.rect.get_center() - card_view.card_size * samphire_flight_start_scale / 2.0
	_samphire_flying = true
	var tween: Tween = TakeFeedback.fly_to(self, card_view, _deck_panel_centre(), card_flight_duration_sec, card_flight_end_scale)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(card_view):
			card_view.queue_free()
		_samphire_flying = false
		_close_if_spent())

# --- Card choice ---

func _open_choice() -> void:
	# A fight's reward, so tier first - see RewardPool.roll_by_rarity() -
	# or, for the region-end fight, the highest tier down (roll_top_tier()).
	var rolled: Array[CardData] = _pool.roll_top_tier(choice_count, RunState.rng, null, RunState.character) if _top_tier else _pool.roll_by_rarity(choice_count, RunState.rng, null, _elite_rates, RunState.character, _rarity_rates)
	_offered = rolled.duplicate()
	if rolled.is_empty():
		_finish_card_line()
		return
	_mode = Mode.CHOICE
	_sync_samphire_preview()
	_hovered = -1
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("RewardScreen: could not load %s; skipping the choice." % CARD_VIEW_SCENE_PATH)
		_finish_card_line()
		return
	for index in rolled.size():
		var card_view := scene.instantiate() as CardView
		# Hover grows the card in place, about its own centre, and moves
		# nothing: no lift (a hand card's hover_lift is a position.y tween
		# measured from its rest offset - here rest IS the row), and the
		# pivot set AFTER add_child(), since CardView._ready() puts a
		# hover-enabled card's pivot at its bottom centre for the hand.
		# Placed and scaled by _layout_choice(), below.
		card_view.hover_lift = 0.0
		_draw_layer.add_child(card_view)
		card_view.pivot_offset = card_view.card_size / 2.0
		card_view.set_card_data(rolled[index])
		# The choice is an inspection: its keywords define themselves on
		# hover.
		card_view.set_keyword_inspect(true)
		card_view.clicked.connect(_on_choice_clicked.bind(card_view))
		card_view.mouse_entered.connect(_on_choice_card_mouse_entered.bind(index))
		card_view.mouse_exited.connect(_on_choice_card_mouse_exited.bind(index))
		_card_views.append(card_view)
	_choice_focus = -1
	_decline_hovered = false
	_layout_choice()
	_apply_scrim()
	_play_choice_open()
	# The offer arriving: each card's name sheens once (a Common's doesn't).
	for card_view in _card_views:
		card_view.play_name_sheen()

# The choice-opening cue, once per choice opened. Made on first use.
func _play_choice_open() -> void:
	if _choice_open_player == null:
		var stream := load(CHOICE_OPEN_SFX_PATH) as AudioStream
		if stream == null:
			push_warning("RewardScreen: choice cue failed to load (%s); silent." % CHOICE_OPEN_SFX_PATH)
			return
		_choice_open_player = AudioStreamPlayer.new()
		_choice_open_player.name = "ChoiceOpenAudio"
		_choice_open_player.bus = &"SFX"
		_choice_open_player.stream = stream
		_choice_open_player.volume_db = choice_open_volume_db
		add_child(_choice_open_player)
	_choice_open_player.play()

# The open choice laid out for the window it's in: the fit factor, the
# cards placed and scaled (their base scale, so a hover grows from it),
# the labels' size and gaps, and NONE OF THESE's place. Whole pixels,
# so the card faces don't land on half-pixel edges.
func _layout_choice() -> void:
	if _card_views.is_empty() or _draw_layer == null:
		return
	var card_size: Vector2 = _card_views[0].card_size
	var count: int = _card_views.size()
	_choice_fit_scale = _choice_fit(card_size, count)
	var card_scale: float = choice_card_scale * _choice_fit_scale
	var card: Vector2 = card_size * card_scale
	var gap: float = card.x * card_gap_fraction
	var span: float = float(count) * card.x + float(count - 1) * gap
	var start_x: float = roundf((_draw_layer.size.x - span) / 2.0)
	var top: float = roundf(_draw_layer.size.y * choice_row_centre_fraction - card.y * 0.5)
	_choice_row = Rect2(start_x, top, span, card.y)
	# A card scales about its centre (its pivot), so its control sits that
	# far up and in from the rect the scaled face fills.
	var pivot_shift: Vector2 = (card_size * 0.5) * (card_scale - 1.0)
	_choice_faces.clear()
	for index in count:
		var face_left: float = roundf(start_x + float(index) * (card.x + gap))
		_choice_faces.append(Rect2(face_left, top, card.x, card.y))
		var card_view: CardView = _card_views[index]
		if not is_instance_valid(card_view):
			continue
		card_view.position = Vector2(face_left, top) + pivot_shift
		card_view.set_rest_offset(card_view.position.y)
		card_view.set_base_scale(card_scale)
	_choice_label_px = maxi(roundi(float(choice_label_size_px) * _choice_fit_scale), 1)
	_choice_font = InkType.tracked(InkType.text_bold_font(), _choice_label_px, choice_label_tracking_em)
	if _rarity_finish != null:
		_tier_px = maxi(roundi(float(_rarity_finish.tier_label_size_px) * _choice_fit_scale), 1)
		_tier_font = InkType.tracked(InkType.text_bold_font(), _tier_px, _rarity_finish.tier_label_tracking_em)
	_header_gap_px = reward_header_gap * _choice_fit_scale
	_decline_gap_px = reward_decline_gap * _choice_fit_scale
	_decline_top_px = _decline_top()
	_draw_layer.queue_redraw()

# The one factor the whole offer scales by: the window's height against
# choice_reference_height, held lower where the row would be wider than
# choice_max_width_fraction of the window, or the offer - TAKE ONE, its
# gap, the row, NONE OF THESE at its furthest - taller than choice_max_
# height_fraction of it.
func _choice_fit(card_size: Vector2, count: int) -> float:
	var window: Vector2 = _draw_layer.size
	var fit: float = window.y / maxf(choice_reference_height, 1.0)
	var card: Vector2 = card_size * choice_card_scale
	var span: float = float(count) * card.x + float(count - 1) * card.x * card_gap_fraction
	if span > 0.0:
		fit = minf(fit, window.x * choice_max_width_fraction / span)
	var stack: float = float(choice_label_size_px) + reward_header_gap + card.y + _tier_line_height(1.0) + reward_decline_gap * 2.0 + float(choice_label_size_px) * 1.3
	if stack > 0.0:
		fit = minf(fit, window.y * choice_max_height_fraction / stack)
	return maxf(fit, 0.01)

func _relayout_choice() -> void:
	if is_node_ready() and _mode == Mode.CHOICE and not _taking_card:
		_layout_choice()

# The scrim: deeper while the card choice is open, the list's own
# otherwise.
func _apply_scrim() -> void:
	if _scrim == null:
		return
	var colour: Color = scrim_color
	if _mode == Mode.CHOICE:
		colour.a = choice_scrim_alpha
	_scrim.color = colour

func _on_choice_clicked(card_data: CardData, card_view: CardView) -> void:
	if _taking_card or _deck_view_open():
		return
	_taking_card = true
	RunState.add_card(card_data)
	RunLogger.reward_cards("fight", _offered, card_data)
	TakeFeedback.play_sound(get_tree(), TAKE_SFX_PATH, take_volume_db, "CardTakeAudio", "RewardScreen")
	print("RewardScreen: took '%s' (deck now %d)." % [card_data.card_name, RunState.deck.size()])
	for other in _card_views:
		if other != card_view and is_instance_valid(other):
			other.queue_free()
	_fly_to_deck(card_view)

# The flight itself is TakeFeedback's; what ends it is this screen's -
# back to the list with the card line struck.
func _fly_to_deck(card_view: CardView) -> void:
	var tween: Tween = TakeFeedback.fly_to(self, card_view, _deck_panel_centre(), card_flight_duration_sec, card_flight_end_scale)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(card_view):
			card_view.queue_free()
		_finish_card_line())

func _deck_panel_centre() -> Vector2:
	if _deck_panel == null:
		push_warning("RewardScreen: no DeckPanel to fly to; dropping the card off-screen instead.")
		return Vector2(_draw_layer.size.x * 0.5, _draw_layer.size.y + 200.0)
	return _deck_panel.get_global_rect().get_center()

# Back to the list with the card line struck - the same ending whether a
# card was taken or the choice was declined.
func _finish_card_line() -> void:
	for view in _card_views:
		if is_instance_valid(view):
			view.queue_free()
	_card_views.clear()
	_choice_focus = -1
	_decline_hovered = false
	_hovered = -1
	_list_mouse_on = -1
	_taking_card = false
	_mode = Mode.LIST
	_apply_scrim()
	for line in _lines:
		if line.id == "card":
			line.taken = true
	_draw_layer.queue_redraw()
	_close_if_spent()

func _close_if_spent() -> void:
	for line in _lines:
		if not line.taken:
			return
	close()

func close() -> void:
	# A weapon or keepsake left on the list is left behind - logged as the
	# keepsake's own offer logs a LEAVE.
	for line in _lines:
		if line.taken:
			continue
		if line.id == "weapon":
			line.taken = true
			weapon_answered.emit(_weapon, false)
		elif line.id == "keepsake":
			line.taken = true
			RunLogger.event("keepsake_offer", {
				"source": RunLogger.or_null(_keepsake_source),
				"offered": RunLogger.keepsake_id(_keepsake),
				"held": RunLogger.keepsake_id(RunState.keepsake),
				"taken": false,
			})
			print("RewardScreen: left the keepsake '%s'." % _keepsake.display_name)
	closed.emit()
	queue_free()
