extends RefCounted
class_name RunLogger

# Stub - not wired up for real logging this pass (see GAME_FRAMEWORK.md's
# own open-questions note). Every method below is a no-op with the old
# project's own method names (static, so callers never need an instance -
# RunLogger.log_card_played(...) reads the same as the old autoload did),
# so call sites can be written against the real eventual API now rather
# than needing every one touched again once this is actually implemented.

static func log_battle_start(_enemy_names: Array[String]) -> void:
	pass

static func log_battle_end(_outcome: String, _energy_left: int) -> void:
	pass

static func log_card_played(_card_name: String) -> void:
	pass

static func log_damage_dealt(_amount: int) -> void:
	pass

static func log_damage_taken(_amount: int) -> void:
	pass

static func log_damage_blocked(_amount: int) -> void:
	pass

static func log_toll_change(_new_toll: int) -> void:
	pass

static func begin_turn(_turn_number: int, _hp: int) -> void:
	pass

static func end_turn(_hp_after: int, _energy_left: int) -> void:
	pass
