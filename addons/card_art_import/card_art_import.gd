@tool
extends EditorPlugin

# Card art imports with the card-art settings, whoever drops it in: any
# image under res://cards/art/ is set to Lossless, no size limit and
# mipmaps on (it's drawn far under its size in the hand) the moment it's
# imported, and imported again with them - nothing else in the project
# is touched. Godot has no per-folder import defaults, and the project-
# wide ones would change every texture.
#
# Watches EditorFileSystem.resources_reimported: an image there whose
# .import says otherwise has its params set and is reimported. That also
# puts back a card's settings if the editor rewrites its .import with
# defaults. The pre-commit hook rejects a card's .import that still
# slipped through (.githooks/pre-commit).

const CARD_ART_DIR := "res://cards/art/"
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp"]
# The texture importer's params every card image takes.
const CARD_ART_PARAMS: Dictionary = {
	"compress/mode": 0,
	"process/size_limit": 0,
	"mipmaps/generate": true,
}

func _enter_tree() -> void:
	var filesystem: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if not filesystem.resources_reimported.is_connected(_on_resources_reimported):
		filesystem.resources_reimported.connect(_on_resources_reimported)

func _exit_tree() -> void:
	var filesystem: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if filesystem.resources_reimported.is_connected(_on_resources_reimported):
		filesystem.resources_reimported.disconnect(_on_resources_reimported)

func _on_resources_reimported(paths: PackedStringArray) -> void:
	var to_fix := PackedStringArray()
	for path in paths:
		if path.begins_with(CARD_ART_DIR) and IMAGE_EXTENSIONS.has(path.get_extension().to_lower()) and _apply_card_art_params(path):
			to_fix.append(path)
	# Deferred: not from inside the import that just finished. A reimport
	# with the right params changes nothing here, so it can't loop.
	if not to_fix.is_empty():
		_reimport.call_deferred(to_fix)

# Writes the card-art params into `path`'s .import; true if any changed.
func _apply_card_art_params(path: String) -> bool:
	var config := ConfigFile.new()
	if config.load(path + ".import") != OK:
		return false
	var changed: bool = false
	for key: String in CARD_ART_PARAMS:
		if config.get_value("params", key, null) != CARD_ART_PARAMS[key]:
			config.set_value("params", key, CARD_ART_PARAMS[key])
			changed = true
	if changed:
		config.save(path + ".import")
		print("Card art import: %s set to Lossless, no size limit, mipmaps on." % path)
	return changed

func _reimport(paths: PackedStringArray) -> void:
	EditorInterface.get_resource_filesystem().reimport_files(paths)
