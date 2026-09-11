extends Resource
class_name CardData

enum TargetType { ENEMY, SELF, NONE }

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
@export var target_type: TargetType = TargetType.NONE
@export_multiline var description: String = ""
@export var effects: Array[CardEffect] = []
@export var removal_scope: RemovalScope = RemovalScope.NONE
