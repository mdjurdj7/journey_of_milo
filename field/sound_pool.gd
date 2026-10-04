extends RefCounted
class_name SoundPool

# A handful of takes of one sound. next() deals them round-robin: it
# walks the list in order and wraps (AttackAudio's swing, HitAudio).
# next_random() picks uniformly from every take but the last one played
# (FieldEnemy's contact sounds). Either way no take plays twice in a row
# once there are two or more; a single take just plays.

var _clips: Array[AudioStream] = []
var _index: int = -1

func set_clips(clips: Array[AudioStream]) -> void:
	_clips.clear()
	for clip in clips:
		if clip != null:
			_clips.append(clip)
	_index = -1

func is_empty() -> bool:
	return _clips.is_empty()

func next() -> AudioStream:
	if _clips.is_empty():
		return null
	_index = (_index + 1) % _clips.size()
	return _clips[_index]

func next_random() -> AudioStream:
	if _clips.is_empty():
		return null
	if _clips.size() == 1:
		_index = 0
		return _clips[0]
	if _index < 0:
		_index = randi_range(0, _clips.size() - 1)
		return _clips[_index]
	# One of the other size - 1 takes: draw among them, then step over
	# the last one's slot.
	var pick: int = randi_range(0, _clips.size() - 2)
	if pick >= _index:
		pick += 1
	_index = pick
	return _clips[_index]
