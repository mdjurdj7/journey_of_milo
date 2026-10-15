class_name ProbePlay
extends RefCounted

# The probes' wait after a real card play (BattleController.request_play()
# / confirm_target()). A play made while another is in flight, or while
# the Wanderer's Slash is short of its cancel point, is queued and not yet
# committed (BattleController._resolve_play(): _play_queued, not _input_
# locked) - so the wait is for both: the queue to commit (or give the card
# back) and that play to resolve. Untyped against BattleController, which
# names the RunState autoload.

# Whether the last play has committed and resolved: nothing queued and
# input unlocked.
static func is_settled(controller: Node) -> bool:
	return not bool(controller.get("_play_queued")) and not bool(controller.get("_input_locked"))

# Waits until is_settled() - by the clock, not frames, which run
# unthrottled headless - or until `stop` returns true (a fight that ends
# mid-play), then three frames more for what reacts to it.
static func settle(tree: SceneTree, controller: Node, stop: Callable = Callable(), timeout_ms: int = 10000) -> void:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if (stop.is_valid() and bool(stop.call())) or is_settled(controller):
			break
	for i in 3:
		await tree.process_frame
