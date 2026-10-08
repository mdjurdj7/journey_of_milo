extends Resource
class_name ScatterSet

# A floor's group of ScatterEntry kinds placed together - floor 1's wet
# set: casts, shells, stones, samphire. FloorData.scatter_sets lists the
# sets a floor uses; FieldScatter places every entry of every set.
# `changed` follows any entry's own, so a live edit to one rebuilds the
# floor's scatter.

@export var entries: Array[ScatterEntry] = []:
	set(value):
		for entry in entries:
			if entry != null and entry.changed.is_connected(emit_changed):
				entry.changed.disconnect(emit_changed)
		entries = value
		for entry in entries:
			if entry != null and not entry.changed.is_connected(emit_changed):
				entry.changed.connect(emit_changed)
		emit_changed()
