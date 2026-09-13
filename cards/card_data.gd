extends Resource
class_name CardData

enum TargetType { ENEMY, SELF, NONE }

# Drives CardView's own art-fill/border color (see its own art_color_attack/
# art_color_skill exports) - no gameplay effect of its own. STANCE isn't
# added here yet since no card needs it; add it alongside CardView's own
# third color export once one does.
enum CardType { ATTACK, SKILL }

enum RemovalScope { NONE, SPENT, CONSUMED }
# NONE: goes to the discard pile, reshuffles back in for the rest of the
# fight like any other card. SPENT and CONSUMED both leave this fight's
# draw/hand/discard rotation for good (Deck.exhaust_pile) - the old
# project's further split (CONSUMED also removes the card from the run's
# deck forever) needs RunState, which isn't ported this pass, so the two
# behave identically here. See Deck.exhaust()'s own doc.

# Chain roles (Opener/Closer/chain payoffs) are deliberately not ported -
# see DESIGN.md's own parked-items note. No current card needs them.

@export var card_name: String = ""
@export var cost: int = 0
@export var card_type: CardType = CardType.ATTACK
@export var target_type: TargetType = TargetType.NONE
@export_multiline var description: String = ""
@export var effects: Array[CardEffect] = []
@export var removal_scope: RemovalScope = RemovalScope.NONE

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
