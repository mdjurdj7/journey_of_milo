extends Resource
class_name BiomeData
# A biome's identity as data, not scattered constants baked into whatever
# scene happens to need them - the single source both the battle scene's
# backdrop (see battle.gd's _apply_battle_backdrop()) and a future map
# header (not built yet - DESIGN.md's Biomes section covers the biome's
# design identity; no UI reads it today) would read from. Same "plain
# Resource container, one instance per thing it describes" shape as
# CardData/EnemyData/CharacterData - see character_data.gd's own header
# comment for why that's a Resource and not a Node.

@export var biome_name: String = ""
# e.g. "The Sunken Works" - matches DESIGN.md's Biomes section entry
# name exactly. Not displayed anywhere yet (no map header exists), same
# "no UI yet, but the data needs an identifier" reasoning CharacterData.
# character_name already has for classes.

@export var battle_backdrop: Texture2D = null
# The static rendered image shown behind a battle fought against this
# biome's enemies (see battle.gd) - optional, same "empty means fall
# back gracefully, not broken" shape as CardData.art_texture/EnemyData.
# visual_scene. Left null, the battle screen falls back to Battle
# Background's own palette-driven sky/ground/shadow instead (see
# battle_background.gd) - a battle backdrop is fixed-size, non-
# interactive, and static, so unlike the field room's generated parallax
# background (which has no planned art replacement), a placeholder here
# is expected to be superseded by real art eventually, same as this
# biome's own (SunkenWorks1.png). Expected to live in assets/biomes/
# <biome_folder>/ - the same "assets live outside resources/, the .tres
# just points at them" split CardData.art_texture already established
# for assets/cards/art/.
#
# backdrop_fallback_color (a flat per-biome tone) used to live here and
# drive that fallback instead - removed 2026-08-27 when Battle
# Background replaced it with something biome-agnostic (SunkenWorks
# Palette, an autoload) rather than a per-BiomeData color. A second
# biome needing its OWN fallback palette is what would bring a field
# like this back, parametrized differently next time - not before.

@export var boss_battle_backdrop: Texture2D = null
# Same shape as battle_backdrop, shown instead of it specifically for
# the biome's boss room (see battle.gd's _apply_battle_backdrop(),
# which checks RoomState.current_room_type == RoomType.Kind.BOSS - the
# same check _on_post_battle_button_pressed() already uses to route a
# boss win differently). Left null, boss fights just use battle_backdrop
# like any other room - a biome isn't required to give its boss a
# distinct look.

@export var battle_backdrop_wet: Texture2D = null
@export var battle_backdrop_dry: Texture2D = null
# Region 1's wet-to-dry gradient (docs/REGION_01_v1.md §3), extended to
# the battle backdrop (2026-09-01, wet/dry backdrop pass) - the field
# ground already interpolates along RoomState.region_progress (see field_
# room.gd's ground_color_wet/_dry), this is the same depth signal applied
# to a fixed battle image instead of a runtime color lerp, since a
# backdrop is a rendered picture, not a shader-tinted plane - there's no
# in-between image to interpolate toward, only a threshold pick between
# two. See battle.gd's _apply_battle_backdrop() and battle_backdrop_
# crossover for the actual selection.
#
# battle_backdrop above stays the FALLBACK for both, not replaced by
# them - if either of these two is unset, battle.gd falls back to it
# exactly as before this pass. This keeps a future biome that only ever
# authors ONE backdrop (no wet/dry split at all) working with zero extra
# wiring - same "empty means fall back gracefully, not broken" shape
# battle_backdrop's own doc above already establishes for itself against
# BattleBackground's palette fallback, just one level up the chain.
# boss_battle_backdrop is UNCHANGED and untouched by any of this - the
# boss override still wins outright over wet/dry/fallback alike.

@export var ground_color_wet: Color = Color(0.71, 0.68, 0.65, 1)
@export var ground_color_dry: Color = Color(0.65, 0.59, 0.52, 1)
# The battle-side ground tint (2026-09-01, battle grounding pass) - named to
# match field_room.gd's own ground_color_wet/_dry exactly, same interpolation
# by RoomState.region_progress (see battle.gd's Grounding consumers), just a
# per-biome DATA field here instead of a field-room @export, since BiomeData
# (not field_room.gd) is what battle actually reads for everything else
# backdrop-related. Sampled directly off THIS biome's own battle_backdrop_
# wet/_dry plates (a pixel average across the ground band where a combatant's
# feet actually sit, ~62% down the frame - see battle.gd's combatant_top_
# offset_px/bar_top_px/bar_gap_px) rather than picked by eye or copied from
# SunkenWorksPalette.GROUND, which this deliberately does NOT read from - that
# palette only ever feeds BattleBackground's fallback layer, fully covered
# whenever real backdrop art exists (which it does here), so it has no
# relationship to what's actually on screen. A biome with no wet/dry plates
# (battle_backdrop_wet/_dry both null, using the single battle_backdrop
# fallback instead) still has these two fields available to author by hand -
# nothing here derives them automatically from battle_backdrop itself.

@export var ambient_loop_name: String = ""
# The region's continuous ambient bed (a wind/environment loop that plays
# for as long as the player is in a field room belonging to this biome) -
# read by field_room.gd's _ready() every room load, same per-run (not
# per-room) home battle_backdrop already established above: RunState.
# current_biome is the seam both read from, and it persists for the whole
# run while RoomState is rebuilt fresh per room (see RoomState's own
# header). Region 1 wants this in place of continuous music, not layered
# under it - see MusicManager's own header for why looping background
# MUSIC stays a separate, single-track concern this field has nothing to
# do with.
#
# A NAME into AudioManager.SFX_FILES, NOT a direct AudioStream reference
# the way battle_backdrop above is a direct Texture2D - deliberately
# different from that field's shape, not an oversight: audio in this
# project is always routed through a name -> file dictionary (SFX_FILES
# here, MUSIC_FILES for MusicManager - see audio_manager.gd's own header
# for why: "swapping which file plays... is a one-line edit [there],
# nothing else in the game hardcodes a path"). A raw AudioStream field
# here would be a second, competing source of truth for the same file.
# Empty means "no ambient bed for this biome" - same fall-back-gracefully
# convention battle_backdrop's own null already uses, just spelled with
# String's natural empty value since this holds a name, not a resource.

@export var field_music_track: String = ""
# The region's continuous field MUSIC bed (2026-09-03, Region 1 field
# music pass) - reverses this file's own earlier ambient_loop_name note
# above ("Region 1 wants [the ambient SFX loop] in place of continuous
# music, not layered under it"): a real music asset now exists for
# Region 1, so this plays ALONGSIDE ambient_loop_name, not instead of it
# - two separate mixes (AudioManager's SFX loop vs. MusicManager's own
# single track), same split that comment already describes. Read by
# field_room.gd's own _start_region_field_music() every room load,
# mirroring _start_region_ambient_bed()'s exact shape one field over -
# RunState.current_biome is the same per-run (not per-room) home both
# already share. A NAME into MusicManager.MUSIC_FILES, not a direct
# AudioStream, same "always routed through a name -> file dictionary"
# reasoning ambient_loop_name's own doc gives for itself. Empty means "no
# continuous field music for this biome" - same fall-back-gracefully
# convention as every other optional field here.
