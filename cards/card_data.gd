extends Resource
class_name CardData

enum TargetType { ENEMY, SELF, NONE }

# ATTACK is what a stance's on-attack hook fires on (see StanceData), so
# this is no longer display-only: getting a card's type wrong now changes
# what it costs to play. Appended, never reordered - the integers are
# baked into every .tres.
# POWER: a lasting effect that is not a stance - it applies a status that
# stays for the fight (Dying Light, Refuse the End), coexists with the
# stance and with other powers, and leaves the deck's rotation for the
# rest of the fight once played (BattleController._on_play_animation_
# finished()), whatever removal_scope says.
enum CardType { ATTACK, SKILL, STANCE, POWER }

# How often a fight's reward offers this card (RewardPool.roll_by_
# rarity()). A property of the card, not of any pool: a pool decides
# WHETHER a card can drop, rarity only how often among the ones that can.
# Four tiers, COMMON to ULTRA_RARE. UNSET is not a fifth - it is the
# default so a card nobody tagged reads as untagged rather than silently
# Common; no reward roll ever picks it and tests/card_rarity_probe.gd
# fails on it. ULTRA_RARE is a real tier with no cards yet, reserved for
# cards that change a class rule (two stances at once, Toll or Grace
# rewritten). Integers are explicit: they're baked into every .tres, so
# a new tier is appended with its own number, never inserted.
enum CardRarity { UNSET = 0, COMMON = 1, UNCOMMON = 2, RARE = 3, ULTRA_RARE = 4 }

enum RemovalScope { NONE, SPENT, CONSUMED }
# NONE: goes to the discard pile, reshuffles back in for the rest of the
# fight like any other card. SPENT and CONSUMED both leave this fight's
# draw/hand/discard rotation for good once played (Deck.exhaust_pile -
# see Deck.exhaust()'s own doc); a SPENT card is back next fight. A
# CONSUMED one also leaves RunState.deck for the rest of the run, when
# the fight it was played in ends, whatever the outcome (RegionField._
# apply_consumed_removals()). Rules text ends on "Spent." or "Consumed."

# Chain roles (Opener/Closer/chain payoffs) are deliberately not ported -
# see DESIGN.md's own parked-items note. No current card needs them.

@export var card_name: String = ""
@export var cost: int = 0
@export var card_type: CardType = CardType.ATTACK
@export var rarity: CardRarity = CardRarity.UNSET
@export var target_type: TargetType = TargetType.NONE
@export_multiline var description: String = ""
@export var effects: Array[CardEffect] = []
@export var removal_scope: RemovalScope = RemovalScope.NONE

# The illustration in the face's art field (CardView), shown as a centred
# cover crop over the type-coloured field. Null is fine and expected for
# most cards today: the face keeps its type glyph instead. A reference in
# the .tres, so the art is imported (with mipmaps - it's reduced heavily
# in the hand) and loaded like any other resource.
@export var art: Texture2D = null

# Which Wanderer battle clip to play once (LOOP_NONE) when this card
# resolves - empty (default) means no swing. Set per-card in the
# Inspector (e.g. "Slash" on the current attack cards) rather than
# inferred from card_type, since not every ATTACK card is guaranteed to
# want the same swing forever. See Wanderer._on_card_played().
@export var battle_animation: StringName = &""

# Seconds into battle_animation's clip at which BattleController delays
# damage resolution/reporting until (see its own _resolve_play() doc) -
# clamped there against the clip's actual length, so a shorter clip still
# fires at its own end rather than after it's already finished playing.
# Ignored entirely when battle_animation is empty (resolves immediately).
@export var impact_time: float = 0.4

# This card's own sound on being played, INSTEAD of the shared card-play
# cue (see BattleOverlay._on_card_played()) - empty (default) means the
# shared one. A path, loaded with load() at play time, never a preloaded
# stream. Fires once, at commit, like the cue it replaces: not on
# anything the card goes on to do (Self-Eater's per-Attack HP loss, a
# stance ending), and never outside a battle hand.
@export_file("*.wav", "*.mp3", "*.ogg") var play_sound_path: String = ""
# Read with play_sound_path only: played while the card's condition is
# live (CardBonus.state() LIVE - Critical for Claw Back's deeper, louder
# take; Toll spent this turn for Gnaw's), the card's own sound takes this
# pitch and this many dB on top of its usual level. Named for the first
# card that used them. Judged as it plays, at commit - before the card
# resolves, so an HP price paid then (Self-Eater's, Collateral's) that
# tips the player into Critical doesn't count. 1.0 and 0: unchanged.
@export var critical_sound_pitch: float = 1.0
@export var critical_sound_volume_db: float = 0.0

# This card's play effect: a scene (a BrushStrokeEffect - an ink stroke
# over the fight) BattleFeedback instances at the card's impact; it paces
# the enemies' hit reactions as it passes them, and the card's hits skip
# the per-enemy slash mark. Empty (default) means none - the slash marks
# as before. A path, loaded with load() at play time.
@export_file("*.tscn") var play_effect_scene_path: String = ""

# The authored, stronger version Glassbone works this card into at the
# wagon (RunState.temper_card()): a card of its own under cards/tempered/
# - in no pool and no folder scan - its name carrying a "+", its rarity,
# type and removal scope the original's. Null: this card can't be
# tempered. Every tempered version leaves its own null, so a card is
# tempered once only.
@export var tempered: CardData = null

# The four real tiers, lowest first - UNSET left out. What a rarity roll
# walks and what a probe checks a card's tag against.
static func rarity_tiers() -> Array[CardRarity]:
	return [CardRarity.COMMON, CardRarity.UNCOMMON, CardRarity.RARE, CardRarity.ULTRA_RARE]
