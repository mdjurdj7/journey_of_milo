extends RefCounted
class_name SoundPool

# A handful of takes of one sound, dealt round-robin: next() walks the
# list in order and wraps, so no take ever plays twice in a row once
# there are two or more (a single take is all there is to play today -
# drop _02/_03 into the array and the rotation just starts). Owned by
# AttackAudio (the swing) and FieldEnemy (its contact sound).

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
