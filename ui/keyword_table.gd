extends Resource
class_name KeywordTable

# The rules keywords, in one place: every word here is set in bold on a
# card face (CardView.KEYWORDS) and in a status reveal, and hovering it
# on a card shows its definition above the card. A new keyword is one
# entry here and nothing else. Each matches as a whole word and as its
# plural ("Drains"), which resolves to the same entry - see pattern().
#
# Definitions are templates, filled from the live rules numbers by
# Status.fill_template() - so they move when the character's numbers do:
#   {threshold}  the Critical line, as a percent of max HP
#   {carry}      the Toll a fight's end carries over (toll_carry_cap)
# Both read the run's character, or the Wanderer's data outside a run
# (the title's compendium).

const TABLE_PATH := "res://ui/keywords.tres"
const FALLBACK_CHARACTER_PATH := "res://run/data/wanderer.tres"

# Keyword -> definition template, in the order a reader meets them. Whole
# words, case-sensitive, as they're written in rules text.
@export var entries: Dictionary[String, String] = {}

static var _shared: KeywordTable = null
var _pattern: RegEx = null

# The table every face and reveal reads - loaded once.
static func shared() -> KeywordTable:
	if _shared == null:
		_shared = load(TABLE_PATH) as KeywordTable
		if _shared == null:
			push_error("KeywordTable: could not load %s" % TABLE_PATH)
			_shared = KeywordTable.new()
	return _shared

func keywords() -> Array[String]:
	var words: Array[String] = []
	words.assign(entries.keys())
	return words

# The one pattern every reader of the keywords matches with - the face's
# bolding, its hover rects, the rules fit's shaping and the status reveal:
# any keyword as a whole word, case-sensitive, with an optional plural
# "s". The whole match is the text as written ("Drains"); group 1 is
# the keyword it resolves to ("Drain"). Compiled once.
func pattern() -> RegEx:
	if _pattern == null:
		_pattern = RegEx.new()
		# No keywords matches nothing, not every empty string.
		if entries.is_empty():
			_pattern.compile("(?!)")
			return _pattern
		_pattern.compile("\\b(%s)s?\\b" % "|".join(PackedStringArray(keywords())))
	return _pattern

# `keyword`'s definition with its numbers filled in - a plural ("Drains")
# reads its keyword's - and "" for a word that isn't a keyword.
func definition(keyword: String) -> String:
	if not entries.has(keyword) and keyword.ends_with("s"):
		keyword = keyword.left(-1)
	if not entries.has(keyword):
		return ""
	return Status.fill_template(entries[keyword], live_values())

# The numbers the templates read, from the run's character - or the
# Wanderer's data when no run has started. The autoload is looked up by
# path, not named: CardView compiles this class, and a headless script
# can compile CardView before the autoloads exist.
static func live_values() -> Dictionary:
	var character: CharacterData = null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var run_state: Node = tree.root.get_node_or_null(^"RunState") if tree != null else null
	if run_state != null:
		character = run_state.get(&"character") as CharacterData
	if character == null:
		character = load(FALLBACK_CHARACTER_PATH) as CharacterData
	if character == null:
		return {}
	return {
		"threshold": roundi(character.critical_hp_fraction * 100.0),
		"carry": character.toll_carry_cap,
	}
