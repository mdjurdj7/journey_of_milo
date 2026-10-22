extends Resource
class_name WarpedShellData

# The Warped Shell: a piece of a Sputter's shell that turns one Endure into
# Stoneshell for the rest of the run. One drop, built for itself - not a
# creature-part system. Each kill of source_enemy rolls drop_chance on the
# run's generator (RegionField._roll_warped_shell()), at most one drop a
# run (RunState.warped_shell_dropped), and never while the deck holds no
# from_card to change. It lies on the sand where the crab fell (WorldShell)
# and its plate shows the change (ItemPlate.set_shell()): TAKE makes it
# (RunState.warp_card()), LEAVE leaves it lying. One of these,
# run/data/warped_shell.tres.

# The enemy whose kills roll for it - the Sputter, the tutorial crab too.
@export var source_enemy: EnemyData = null
# The chance each such kill drops it.
@export_range(0.0, 1.0, 0.01) var drop_chance: float = 0.25
# The card it changes, and what that becomes. A tempered from_card
# (from_card.tempered) becomes to_card.tempered.
@export var from_card: CardData = null
@export var to_card: CardData = null
# The find line: "You find <find_article> <find_name> on the <find_creature>."
@export var find_article: String = "a"
@export var find_name: String = "piece of shell"
@export var find_creature: String = "crab"
# Its plate: the name, the type line's label, the effect ({from} and {to}
# the card names) and the lore line.
@export var plate_name: String = "Warped Shell"
@export var plate_label: String = "DECK"
@export var plate_text: String = "One {from} becomes {to}."
@export var lore: String = "Grown hard around something soft."

# The card in `deck` the shell would change: the first plain from_card,
# else the first tempered one - null with neither.
func host_in(deck: Array[CardData]) -> CardData:
	if from_card == null:
		return null
	var tempered_name: String = from_card.tempered.card_name if from_card.tempered != null else ""
	var tempered_host: CardData = null
	for card in deck:
		if card == null:
			continue
		if card.card_name == from_card.card_name:
			return card
		if tempered_host == null and not tempered_name.is_empty() and card.card_name == tempered_name:
			tempered_host = card
	return tempered_host

# What `host` becomes: to_card, or to_card.tempered for a tempered host.
func result_for(host: CardData) -> CardData:
	if host == null or from_card == null or to_card == null:
		return null
	if host.card_name == from_card.card_name:
		return to_card
	return to_card.tempered

# plate_text for `host` and what it becomes.
func describe(host: CardData) -> String:
	var into: CardData = result_for(host)
	if host == null or into == null:
		return ""
	return plate_text.replace("{from}", host.card_name).replace("{to}", into.card_name)
