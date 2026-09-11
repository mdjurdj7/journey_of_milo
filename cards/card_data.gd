extends Resource
class_name CardData

enum TargetType { ENEMY, SELF, NONE }

@export var card_name: String = ""
@export var cost: int = 0
@export var target_type: TargetType = TargetType.NONE
@export_multiline var description: String = ""
