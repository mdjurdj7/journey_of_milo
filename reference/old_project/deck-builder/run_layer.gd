extends RefCounted
class_name RunLayer
# A tiny wrapper around one layer's nodes - exists only because GDScript
# doesn't support nested typed arrays (Array[Array[RunNode]] is a parser
# error: "Nested typed collections are not supported"). Array[RunLayer]
# keeps run_state.gd's run_graph statically typed down to RunNode instead
# of falling back to a bare, unchecked Array[Array]. Same "small
# RefCounted class whose only job is holding one thing" shape as
# RunNode/WeightedRandom/LootEntry.

var nodes: Array[RunNode] = []
