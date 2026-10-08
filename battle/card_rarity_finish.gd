extends Resource
class_name CardRarityFinish

# A card name's finish by its rarity (CardData.rarity), Yu-Gi-Oh style but
# kept legible on bone: one shared resource, battle/card_rarity_finish.tres,
# read by every CardView (and the offer screens' tier labels), so a
# Remote-tab edit here moves every face at once - each setter emits
# `changed`.
#
#   COMMON      flat ink, no finish, no sheen
#   UNCOMMON    dark pewter, a pewter sheen
#   RARE        dark gold, a gold sheen
#   ULTRA_RARE  dark gold, a sheen band of three muted hues
#
# At rest the name is its base colour with a faint fixed gradient toward
# the tier's highlight across the word (rest_gradient_strength); nothing
# moves. A sheen - a narrow highlight band left to right over
# sheen_duration_sec - plays once on hover and once when the card arrives
# in an offer (CardView.play_name_sheen()), never looping. No glow.
#
# Legibility: every base keeps at least min_contrast against bone
# (contrast_ratio(); card_rarity_finish_probe holds it). The highlights
# don't - they only ever show in the narrow passing band.
#
# The finish itself is battle/card_name_finish.gdshader on the name.

@export_group("Common")
# CardView.ink_color's value: a Common (or untagged) name is this, flat.
@export var common_ink: Color = Color(0.165, 0.165, 0.18):
	set(value):
		common_ink = value
		emit_changed()

@export_group("Uncommon")
@export var uncommon_base: Color = Color(0.29, 0.31, 0.34):
	set(value):
		uncommon_base = value
		emit_changed()
@export var uncommon_highlight: Color = Color(0.55, 0.58, 0.61):
	set(value):
		uncommon_highlight = value
		emit_changed()

@export_group("Rare")
@export var rare_base: Color = Color(0.42, 0.33, 0.13):
	set(value):
		rare_base = value
		emit_changed()
@export var rare_highlight: Color = Color(0.69, 0.56, 0.27):
	set(value):
		rare_highlight = value
		emit_changed()

@export_group("Ultra Rare")
@export var ultra_base: Color = Color(0.42, 0.33, 0.13):
	set(value):
		ultra_base = value
		emit_changed()
# The rest gradient's far end - the sheen itself is the three hues.
@export var ultra_highlight: Color = Color(0.69, 0.56, 0.27):
	set(value):
		ultra_highlight = value
		emit_changed()
@export var ultra_hue_rose: Color = Color(0.55, 0.44, 0.50):
	set(value):
		ultra_hue_rose = value
		emit_changed()
@export var ultra_hue_teal: Color = Color(0.37, 0.49, 0.53):
	set(value):
		ultra_hue_teal = value
		emit_changed()
@export var ultra_hue_olive: Color = Color(0.54, 0.54, 0.32):
	set(value):
		ultra_hue_olive = value
		emit_changed()

@export_group("Finish")
# How far the name runs from its base toward its highlight across the
# word at rest, left (base) to right. Subtle - the base carries the tier.
@export_range(0.0, 1.0) var rest_gradient_strength: float = 0.12:
	set(value):
		rest_gradient_strength = value
		emit_changed()
@export var sheen_duration_sec: float = 0.9:
	set(value):
		sheen_duration_sec = value
		emit_changed()
# The band's half-width, as a fraction of the name's width.
@export_range(0.01, 1.0) var sheen_width: float = 0.16:
	set(value):
		sheen_width = value
		emit_changed()
# How much of the half-width is soft falloff (0 = a hard edge).
@export_range(0.0, 1.0) var sheen_softness: float = 0.75:
	set(value):
		sheen_softness = value
		emit_changed()
# The band's mix toward its highlight at its centre.
@export_range(0.0, 1.0) var sheen_strength: float = 0.85:
	set(value):
		sheen_strength = value
		emit_changed()

@export_group("Legibility")
# The card's bone - what every base is held against.
@export var bone: Color = Color(0.94, 0.91, 0.86):
	set(value):
		bone = value
		emit_changed()
@export var min_contrast: float = 4.5:
	set(value):
		min_contrast = value
		emit_changed()

@export_group("Tier Label")
# The tier named under an offered card (RewardScreen, CollectorScreen):
# Alegreya Sans Bold caps, tracked; Common and Uncommon dim, Rare and
# Ultra Rare at full bone, over the screens' own ink outline.
@export var tier_label_size_px: int = 11:
	set(value):
		tier_label_size_px = value
		emit_changed()
@export var tier_label_tracking_em: float = 0.16:
	set(value):
		tier_label_tracking_em = value
		emit_changed()
@export_range(0.0, 1.0) var tier_label_dim_alpha: float = 0.6:
	set(value):
		tier_label_dim_alpha = value
		emit_changed()
# Between the card's bottom edge and the label's top.
@export var tier_label_gap_px: float = 8.0:
	set(value):
		tier_label_gap_px = value
		emit_changed()
@export_group("")

# Whether `rarity` wears a finish at all - Uncommon and up. Common (and an
# untagged card) stays plain ink, with no material on its name.
func has_finish(rarity: CardData.CardRarity) -> bool:
	return rarity == CardData.CardRarity.UNCOMMON or rarity == CardData.CardRarity.RARE or rarity == CardData.CardRarity.ULTRA_RARE

func base_color(rarity: CardData.CardRarity) -> Color:
	match rarity:
		CardData.CardRarity.UNCOMMON:
			return uncommon_base
		CardData.CardRarity.RARE:
			return rare_base
		CardData.CardRarity.ULTRA_RARE:
			return ultra_base
	return common_ink

func highlight_color(rarity: CardData.CardRarity) -> Color:
	match rarity:
		CardData.CardRarity.UNCOMMON:
			return uncommon_highlight
		CardData.CardRarity.RARE:
			return rare_highlight
		CardData.CardRarity.ULTRA_RARE:
			return ultra_highlight
	return common_ink

func is_rainbow(rarity: CardData.CardRarity) -> bool:
	return rarity == CardData.CardRarity.ULTRA_RARE

# The tier's name under an offered card; "" for an untagged card.
func tier_label_text(rarity: CardData.CardRarity) -> String:
	match rarity:
		CardData.CardRarity.COMMON:
			return "COMMON"
		CardData.CardRarity.UNCOMMON:
			return "UNCOMMON"
		CardData.CardRarity.RARE:
			return "RARE"
		CardData.CardRarity.ULTRA_RARE:
			return "ULTRA RARE"
	return ""

# Common and Uncommon name themselves in dim bone, Rare and up in full.
func tier_label_dimmed(rarity: CardData.CardRarity) -> bool:
	return rarity != CardData.CardRarity.RARE and rarity != CardData.CardRarity.ULTRA_RARE

# WCAG 2 contrast ratio between two opaque colours (sRGB), 1..21.
static func contrast_ratio(a: Color, b: Color) -> float:
	var la: float = _relative_luminance(a)
	var lb: float = _relative_luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

static func _relative_luminance(c: Color) -> float:
	return 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)

static func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)
