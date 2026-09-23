extends RefCounted
class_name TakeFeedback

# What every take site does once the grant has gone through RunState:
# the take's one-shot sound, and - for a card - its flight to the
# Belongings panel. Shared by RewardScreen, WorldCard and LootScreen,
# which each keep their own paths, volumes and flight timings as exports
# and only hand them in here.

# The sound, on its own 2D player on the SFX bus - parented to the tree's
# ROOT with process ALWAYS and freed on its own `finished`, so it plays to
# the end whatever happens to the caller next: a screen closes and frees
# itself right after a take, a WorldCard frees itself after its flight,
# and RegionField stands DISABLED under a screen and under a field freeze
# (a battle contact, the floor transition). load() at the moment of
# taking, never a preloaded stream. `who` only names the caller in the
# warning.
static func play_sound(tree: SceneTree, path: String, volume_db: float, player_name: String, who: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("%s: take SFX failed to load (%s); silent." % [who, path])
		return
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = &"SFX"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.stream = stream
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	tree.root.add_child(player)
	player.play()

# The card shrinking and fading into `destination` (a screen point - the
# Belongings panel's centre). The tween belongs to `tween_owner`, so it
# lives and pauses with the caller exactly as its own create_tween()
# would; the caller chains whatever ends the take onto the returned
# tween (.chain().tween_callback(...)).
static func fly_to(tween_owner: Node, card_view: CardView, destination: Vector2, duration: float, end_scale: float) -> Tween:
	card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := tween_owner.create_tween()
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(card_view, "position", destination - card_view.card_size * end_scale / 2.0, duration)
	tween.tween_property(card_view, "scale", Vector2.ONE * end_scale, duration)
	tween.tween_property(card_view, "modulate:a", 0.0, duration)
	return tween
