extends Node2D
class_name PlayerVisual
# Everything about how the player LOOKS lives here, entirely separate
# from player.gd (which only owns movement, input, and the physics
# collision shape - see field_room.tscn, where this is a sibling of
# Player/CollisionShape2D, not a wrapper around it). This node doesn't
# get told anything by player.gd; it just watches its own parent
# CharacterBody2D's velocity every frame and reacts on its own. Swapping
# in real character art later (or a per-character sprite, once playable
# characters beyond the placeholder exist - see DESIGN.md's open
# question on this) means replacing this one node and its script -
# player.gd, the collision shape, and everything else that only cares
# WHERE the player is never need to change.
#
# The figure is one AnimatedSprite2D playing hand-drawn walk-cycle
# frames (see assets/characters/wanderer/walk/) - NOT the earlier
# cut-out rig (a static Torso plus a 2-bone Thigh/Shin chain per leg,
# hand-posed in the Animation panel). That rig's full derivation - the
# per-piece Position/Offset numbers, the weighted-step keyframe timing,
# the TorsoBack layering trick for the waist fabric - isn't lost; it's
# in this file's and player_visual.tscn's git history (search for
# "extend thigh coverage at knee, add TorsoBack layer" and everything
# before it) as a reference if a rigged approach is ever needed again.
#
# walk is 22 frames now, cropped as 256x256 AtlasTexture regions out
# of ONE trimmed sprite sheet (Wanderer-walk-trimmed.png, a 1280x1280
# 5x5 grid with 3 unused trailing cells) - not separate per-pose PNG
# files the way every earlier version of this animation worked. The
# SpriteFrames frame order follows the sheet's own snake layout (row 0
# left-to-right, row 1 right-to-left, row 2 left-to-right, ...), not a
# left-to-right reading order, because that's how the sheet itself was
# packed. Everything from the earlier hand-authored 4-and 8-frame sets
# (contact/down/passing/up and their opposite-leg counterparts, the
# fractional-duration engine bug, the gait-weighted-vs-even timing
# experiment, the ground-contact misalignment fixes) is superseded by
# this sheet, but not lost - it's in this file's and player_visual.
# tscn's git history, most recently "Complete the walk cycle: add
# opposite-leg frames" and the commits before it, useful background if
# a hand-authored set is ever needed again. EVEN timing carries over
# unchanged: every frame's duration is the default 1.0, speed=8.0fps.
#
# idle reuses walk's own frame 0 (the top-left sheet cell) as a frozen
# placeholder, rather than separate idle art or a leftover frame from
# an older set - same "pick something reasonable, not dedicated art"
# placeholder philosophy as every earlier version of idle here, just
# now literally the same texture object walk's own frame 0 already
# uses (see SpriteFrames in player_visual.tscn - idle's one frame and
# walk's first frame both point at SubResource("AtlasTexture_2v4le")).
# Switching between "walk" and "idle" is an instant cut, not a
# crossfade: AnimatedSprite2D.play() has no blend_time the way
# AnimationPlayer.play() did, so stopping mid-stride will pop rather
# than ease. Worth revisiting once real idle art makes it worth
# building (two overlapping sprites cross-modulated, most likely) -
# not built speculatively for a placeholder frame.
#
# _sprite's offset (Vector2(0, -97.5)) is measured, not guessed, same
# method as every earlier frame set: all 22 sheet cells' lowest opaque
# pixel lands within a 1px band (local rows 225-226 of each 256-tall
# cell) - by far the tightest ground-contact consistency any frame set
# used here has had (compare the hand-authored sets' 6px and 28-32px
# spreads) since this sheet was built with consistent alignment baked
# in, not assembled from independently-exported frames. offset.y
# targets the band's average (local row 225.5) at this node's local
# y=0: 128 (half the 256px cell height, since centered=true) - 225.5.
# Because every cell already agrees this tightly, idle can safely
# reuse ANY walk frame without introducing its own alignment mismatch
# - frame 0 was picked for simplicity, not because it's specially
# aligned relative to the other 21.
#
# _sprite's scale (3, 3) - lives on THIS node rather than self
# (PlayerVisual) on purpose, mirroring flip_h - keeps self free for
# whatever external code might want to scale the whole node someday
# (see PlayerBattleVisual/enemy.gd's shared visual_scene pattern),
# same reasoning that used to require FigureRoot's separate scale.

const FACING_DEADZONE := 1.0 # px/sec of horizontal velocity below which facing doesn't update.

const WALK_ANIM := "walk"
const IDLE_ANIM := "idle"

var _parent_body: CharacterBody2D
var _facing: float = 1.0 # 1 = facing right (the frames' authored orientation), -1 = mirrored.

@onready var _sprite: AnimatedSprite2D = $Sprite

func _ready() -> void:
	_parent_body = get_parent() as CharacterBody2D
	# Explicitly starts playback rather than leaving it to _update_motion()'s
	# _process() guard - that guard only calls play() when _sprite.animation
	# CHANGES, but the .tscn serializes animation = &"idle" as a static
	# property (whatever the editor happened to have selected when last
	# saved), which selects a clip without actually playing it. At spawn,
	# before movement, is_moving is false and target_anim is already
	# "idle" - so the guard sees no change and never calls play(), and the
	# figure sits frozen on whatever frame/frame_progress got serialized
	# until the first real walk transition. This call is what actually
	# starts the timer, independent of whatever static frame the .tscn
	# happened to save.
	_sprite.play(IDLE_ANIM)

func _process(_delta: float) -> void:
	# _parent_body is null wherever this is instanced WITHOUT a
	# CharacterBody2D parent. Nothing does that today - the battle-scene
	# reuse this comment used to describe was retired when battle got
	# its own dedicated wanderer_battle_visual.tscn (see
	# player_battle_visual.gd) - but the fallback stays as cheap
	# insurance rather than an early-return, so a future no-parent
	# instantiation degrades to a frozen idle figure instead of a crash.
	var velocity: Vector2 = _parent_body.velocity if _parent_body else Vector2.ZERO
	var is_moving := velocity.length() > FACING_DEADZONE

	_update_facing(velocity)
	_update_motion(is_moving)

# Flips the whole figure to face whichever way the player last moved
# horizontally, and holds that facing while idle or moving purely
# vertically - "facing persists when idle," per spec. Sets flip_h
# directly rather than a scale.x mirror - AnimatedSprite2D's flip_h is
# built for exactly this and, like the scale.x trick it replaces,
# doesn't touch self.scale, so nothing here can collide with
# PlayerBattleVisual-style external scaling of the whole node (moot
# today since battle no longer instances this scene at all, but kept
# for the same reason the old scale-isolation was: cheap to preserve,
# expensive to rediscover why it mattered).
func _update_facing(velocity: Vector2) -> void:
	if absf(velocity.x) > FACING_DEADZONE:
		_facing = 1.0 if velocity.x > 0.0 else -1.0
	_sprite.flip_h = _facing < 0.0

# Switches the AnimatedSprite2D between "walk" and "idle" (see
# SpriteFrames in player_visual.tscn). is_moving alone decides the
# clip - whatever timing each animation carries is entirely up to how
# its frame durations were authored; this function doesn't know or
# care about individual frames, just which of the two named animations
# should be playing.
func _update_motion(is_moving: bool) -> void:
	var target_anim := WALK_ANIM if is_moving else IDLE_ANIM
	if _sprite.animation != target_anim:
		_sprite.play(target_anim)
