extends Node
# Another autoload (see run_state.gd for the fuller explanation of what
# that means). Owns background music - a looping track that persists
# across scene changes until explicitly stopped, unlike AudioManager's
# one-shot SFX pool (see its own header comment on why that's a separate
# concern: different lifetime rules - a track keeps playing through
# whatever's happening on screen rather than firing once per moment).
# The whole game calls MusicManager.play_music("some_name")/stop_music()
# and never touches an AudioStreamPlayer directly, same "one place owns
# the how" split AudioManager already established for SFX.
#
# Only one track plays at a time (no crossfading, no layering) - two
# tracks exist so far (the title theme, the opening room's coastal
# ambience - see MUSIC_FILES), and this stays exactly as simple as
# what's actually needed until something asks for more (a battle theme,
# crossfading between rooms).

const MUSIC_FOLDER := "res://assets/audio/music/"
# Its own subfolder, alongside AudioManager's SFX categories (cards/
# combat/enemies/field/ui) under assets/audio/ - music is never a
# per-trigger SFX cue, so it gets one folder for everything this manager
# owns rather than being sorted into any of those.

# THE ONE PLACE a track's name maps to a file - same shape as AudioManager's
# SFX_FILES, for the same reason: callers name a track ("title_theme"),
# never a path, so swapping the file later is a one-line edit here.
const MUSIC_FILES := {
	"title_theme": "Title_theme.mp3",
	"room1_waves": "Room1_Waves.mp3",
	# The opening room's coastal ambience (see field_room.gd's
	# _apply_coastal_opening_room_layout()) - the second track this
	# manager has ever needed, and the first one gated to a specific
	# ROOM rather than a whole screen.
	"room1_alt_drone": "Room1_Alt_Drone.mp3",
	# The industrial/space variant's own ambience (EXPERIMENTAL - see
	# field_room.gd's _apply_industrial_opening_room_layout()) - same
	# room, same "one specific room, not a whole screen" gating as
	# room1_waves above, just the alternate variant's own mood.
	"boss_01": "The_Works_Boss_Music_1.mp3",
	# BOSS_01's own battle theme (see battle.gd's _apply_boss_music(),
	# gated the same way _apply_battle_backdrop() already gates the boss
	# backdrop: RoomState.current_room_type == RoomType.Kind.BOSS).
	# Moved here from assets/audio/enemies/Works_Boss/ where it was first
	# dropped - that folder mirrors AudioManager's per-CATEGORY SFX
	# layout (cards/combat/enemies/field/ui), which is exactly the split
	# this file's own header says music does NOT use.
	"region_1_field": "region_1_background.mp3",
	# Region 1's continuous field ambience (2026-09-03, Region 1 field
	# music pass) - moved here from assets/audio/ambient/, where it was
	# first dropped alongside this same region's ambient SFX loop
	# (ambient_wind_beach.mp3), same "relocate into this folder for
	# consistency" precedent boss_01's own entry above already set. Read
	# via BiomeData.field_music_track (SunkenWorks' own value), by field_
	# room.gd's own _start_region_field_music() - see that field's own
	# doc for why this reverses the "ambient SFX instead of music" note
	# on BiomeData.ambient_loop_name.
}

# Per-track volume trims, in dB, layered on top of master_volume below -
# same shape as AudioManager's own VOLUME_TRIM_DB, for the same reason:
# not every track should play at the same level. The first track this
# manager has ever needed one for - boss_01 was explicitly called out as
# ambient/background, not a foreground theme, so it gets pulled down
# rather than playing at the same level as the coastal/industrial room
# ambience above. No MP3 decoder is available in this environment to
# measure its actual loudness (same limitation AudioManager's own header
# notes for its untrimmed MP3 entries) - this is a starting guess, meant
# to be retuned by ear once heard in-game, not a measured value.
const VOLUME_TRIM_DB := {
	"boss_01": -7.0,
	"region_1_field": -18.0,
	# Ambient BED, not a foreground theme - explicitly asked to sit quiet,
	# below every SFX (this pass's own brief) rather than compete with
	# boss_01's own "pulled down from a full theme" register. Combines
	# with master_volume below (linear_to_db(0.7) ~= -3.1dB) for ~-21dB
	# actual output - a starting guess, same "meant to be retuned by ear
	# once heard live" caveat boss_01's own entry above already carries.
}

@export_range(0.0, 1.0, 0.01) var master_volume: float = 0.7
# Independent of AudioManager's own master_volume - music and SFX are
# separate mixes, same as any game with more than a placeholder audio
# setup. No shared "master" concept exists yet (see DESIGN.md's Audio
# section: no settings menu), so this is its own knob for now.

var _player: AudioStreamPlayer
var _current_track: String = ""

# Resume state (2026-09-03, Region 1 field music pass) - which track was
# playing, and how far into it, at the moment stop_music() last actually
# stopped something. Lets battle.gd's field->battle->field round trip
# (via scene_transition.gd's own stop_music() call on the way into
# battle.tscn) pick the field ambience back up where it left off instead
# of restarting, without a general per-track position table: only ONE
# track is ever playing at a time by this whole file's own design (see
# this file's own header), so there's only ever one position worth
# remembering. play_music() consumes (and clears) this ONLY when the
# track it's about to start is the exact one that was stopped - starting
# a DIFFERENT track (boss_01, say) leaves it untouched, so a boss fight
# sandwiched between two stop_music()/play_music() calls for the field
# track still resumes correctly afterward; starting the SAME track
# again later (a second stop_music() call, or a fresh run reaching this
# same biome) naturally goes through play_music() first and clears it,
# so no stale position can leak across a full stop/restart or into a
# later run.
var _resume_track: String = ""
var _resume_position: float = 0.0

const STOP_FADE_SEC := 0.3
# Matches scene_transition.gd's own FADE_DURATION (the visual fade-to-
# black every transition already plays) - not read from there directly
# (this file has no reason to depend on that one's constant), just tuned
# to the same rough beat so an audio cut doesn't finish audibly faster
# or slower than the screen it's covering.
var _fade_tween: Tween

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)

# Starts track_name looping if it isn't already the one playing - safe to
# call from a scene's _ready() every time that scene loads (see title_
# screen.gd), since it no-ops rather than restarting from the beginning
# if this exact track is already what's playing. Resumes from _resume_
# position (see its own doc above) if track_name is the exact track a
# stop_music() call most recently interrupted, otherwise starts fresh
# from 0.0 - either way, the resume state is cleared immediately after,
# so it's only ever good for the ONE play_music() call right after the
# stop that set it.
func play_music(track_name: String) -> void:
	if _current_track == track_name and _player.playing:
		return
	if _fade_tween != null:
		# A stop_music() fade still animating when a new track starts (a
		# battle beginning before the field music finished fading out,
		# say) - kill it before it can call _player.stop() out from under
		# the track that's about to start playing.
		_fade_tween.kill()
		_fade_tween = null
	var stream := _resolve_stream(track_name)
	if stream == null:
		return
	var start_position := 0.0
	if track_name == _resume_track:
		start_position = _resume_position
		_resume_track = ""
		_resume_position = 0.0
	_player.stream = stream
	_player.volume_db = _volume_db_for(track_name)
	_player.play(start_position)
	_current_track = track_name

# Safety net for scene changes, same spirit as AudioManager's stop_all_
# looping() - see scene_transition.gd, which calls this at the start of
# every go_to() so a track started in one scene (the title theme) can
# never bleed into whatever comes next (a run in progress). Fades out
# over fade_sec (a brief tween on the player's own volume_db, not a
# crossfade - nothing else plays during it) rather than cutting instantly,
# so entering battle from the field doesn't hard-clip the ambience
# mid-note. Pass 0.0 for the old instant-stop behavior if some future
# caller ever needs it; every caller today uses the default. Stashes the
# interrupted track's name/position into _resume_track/_resume_position
# first (see their own doc above) - a no-op read if nothing was actually
# playing.
func stop_music(fade_sec: float = STOP_FADE_SEC) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
	if _player == null or not _player.playing:
		_current_track = ""
		return
	_resume_track = _current_track
	_resume_position = _player.get_playback_position()
	_current_track = ""
	if fade_sec <= 0.0:
		_player.stop()
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", -80.0, fade_sec)
	_fade_tween.finished.connect(_player.stop)

func _volume_db_for(track_name: String) -> float:
	var trim_db: float = VOLUME_TRIM_DB.get(track_name, 0.0)
	return trim_db + linear_to_db(master_volume)

func _resolve_stream(track_name: String) -> AudioStream:
	if not MUSIC_FILES.has(track_name):
		push_warning("MusicManager: '%s' isn't a known track name." % track_name)
		return null
	var file_name: String = MUSIC_FILES[track_name]
	if file_name == "":
		push_warning("MusicManager: no audio file mapped for '%s' yet." % track_name)
		return null
	var path := MUSIC_FOLDER + file_name
	if not ResourceLoader.exists(path):
		push_error("MusicManager: missing audio file '%s'." % path)
		return null
	var stream: AudioStream = load(path)
	# Looping has to be set on the stream itself, format-specific - same
	# handling AudioManager's _looping_player_for() already needs for SFX,
	# duplicated here rather than shared since this is the one place a
	# stream is ever played more than once through by design (AudioManager's
	# SFX pool is one-shot only).
	if stream is AudioStreamMP3:
		var looping_mp3: AudioStreamMP3 = (stream as AudioStreamMP3).duplicate()
		looping_mp3.loop = true
		stream = looping_mp3
	elif stream is AudioStreamWAV:
		var looping_wav: AudioStreamWAV = (stream as AudioStreamWAV).duplicate()
		looping_wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream = looping_wav
	return stream
