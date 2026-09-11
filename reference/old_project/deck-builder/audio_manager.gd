extends Node
# Another autoload (see run_state.gd for the fuller explanation of what
# that means). Owns playing sound effects - the whole game calls
# AudioManager.play_sfx("some_name") and never touches an AudioStreamPlayer
# or a file path directly. That's the seam: every sound-triggering hook
# in the game (battle.gd, reward_screen.gd, field_room.gd, ...) just names
# a moment ("card_play", "victory"); this script is the only place that
# knows which .wav that name currently means, or how loud it plays.
#
# Music isn't handled here on purpose (see DESIGN.md's Audio section) -
# looping background music wants different lifetime rules (survive scene
# changes without restarting, cross-fade between tracks) that would only
# complicate this pool. MusicManager (music_manager.gd) is that sibling
# autoload, following the same "one dictionary, one folder constant"
# shape as this file.

const SFX_FOLDER := "res://assets/audio/"

# THE ONE PLACE a sound's name maps to a file. Every hook in the game
# calls play_sfx() with a name from the left column - swapping which file
# plays for it (or handing a placeholder its real sound once one exists)
# is a one-line edit here, nothing else in the game ever hardcodes a path.
# An empty string means "this sound is wired up everywhere it should
# play, but no audio file exists for it yet" - see DESIGN.md's Audio
# section for the current list of gaps. play_sfx() treats that as a
# silent no-op (with a warning), not an error, so hooks can be wired
# ahead of the art existing. Each real filename below includes its own
# CATEGORY subfolder (cards/combat/enemies/field/ui - see assets/audio/'s
# own layout) rather than SFX_FOLDER pointing at one flat directory - the
# folder is grouped by what TRIGGERS the sound (a card action, a combat
# exchange, an enemy-specific moment, a field interaction, a UI/meta
# action), not by file format or any other property, so a new sound's
# home is always obvious from what's calling play_sfx() for it.
const SFX_FILES := {
	"card_play": "cards/card_play.wav",
	"card_refused": "",
	"damage_enemy": "combat/Slash.mp3", # The CHARACTER's own hits landing (see battle.gd's _deal_damage_to_enemy()) - split off from the shared hit.wav (2026-08-27) so the player's attacks have their own distinct texture; enemies landing hits on the player still play damage_player below unchanged, which stays on hit.wav for now. SWAPPED (2026-09-07) from combat/Strike.mp3 to the new combat/Slash.mp3 - same role (the default/primary impact sound - see _damage_enemy_sfx_name()'s own doc in battle.gd), just a new recording; combat/Strike.mp3 itself is left on disk, now unreferenced. "selfeater_strike" below plays its own separate file (Selfeater_Strike.mp3, not this one) and is a DELIBERATELY distinct texture for the Selfeater-Mark-active override - not touched by this swap.
	"damage_player": "combat/hit.wav",
	"hp_loss_breath": "combat/hp_loss_breath.mp3", # The Wanderer's own "paying HP" cue (2026-09-07, self-damage-sound pass) - fires on every self-inflicted HP loss (see battle.gd's _deal_self_damage(), the one function every SELF_DAMAGE/SELF_DAMAGE_TOLL card effect and Selfeater's own per-attack drain all route through - RunLogger.TollSource.SELF is what marks a loss as self-inflicted there). Layered ON TOP of the existing damage_player cue at that same call site, not a replacement for it - same "distinct additional texture" shape chain_impact/weapon_reflect use elsewhere in this file. NEVER played for damage_player's OTHER trigger (an enemy's hit landing, _enemy_attack_player()) - that path doesn't call _deal_self_damage() and has no reason to. Volume is NOT read from VOLUME_TRIM_DB below (see play_hp_loss_breath()/hp_loss_breath_volume_offset_db's own doc for why this one sound gets a dedicated export instead) - registered here only so it flows through the same _resolve_stream()/pool/cache path as every other sound.
	"block_gained": "combat/wanderer_guard.mp3", # Any BLOCK/TOLL_BLOCK effect resolving (see battle.gd's _apply_card_effects()) - Guard is the starting-deck card this is heard on most, but it's the generic mechanic cue, shared by Guard+/Ballast/Iron Will/Retaliation/every other block-granting card, same "generic mechanic slot" shape heal/wind_up already use. Previously empty - see DESIGN.md's Audio section (an earlier file, blocking.wav, was sourced for this slot and reverted; this is a different, new file).
	"gold_claimed": "field/gold.wav",
	"add_card": "field/add_card.mp3", # Every player-facing card-acquisition moment EXCEPT the Keeper's own card handover, which plays this same file today too but is wired at its own independent call site (field_room.gd's _on_npc_offer_card_clicked()) on purpose - she's slated for a distinct sound later, and that separate wiring is the seam for that swap. Everyone else - the cache/TREASURE chest (_on_chest_offer_card_clicked(), field_room.gd), post-battle reward pick and rare drop (reward_screen.gd), a shop purchase (shop_window.gd), and a Sift GRANT_CARD outcome (sift_outcome_resolver.gd, shared by field_heap.gd's pull and field_curio.gd's investigate) - each has its OWN independent play_sfx call at its own grant moment (2026-09-03), not a shared hook, matching the Keeper's own precedent. The dev Add Card button (battle.gd) stays silent, also on purpose - a test tool, not a real acquisition.
	"card_upgrade": "field/Forge.mp3", # The forge's own upgrade reveal, at the exact moment the presented card's values swap to the upgraded version (see field_forge.gd's _play_upgrade_reveal()) - hooked at the FORGE's own call site only, not inside CardUpgradeService.offer_upgrade() itself, so the shop purchase and the battle dev-upgrade button (both sharing that same function) stay silent.
	"card_draw_hand": "ui/Hand draw.mp3", # The turn-start hand draw (battle.gd's _start_battle()/_start_player_turn(), both routing through _draw_cards()) - a composite riffle of several cards, played ONCE per turn since the hand appears all at once (no per-card arrival animation exists to time single-card plays against - see _draw_cards()'s own DrawSoundMode doc). Filed in ui/, not cards/ or field/ - like select_card/game_start, this is a meta/UI cue about the DRAW moment itself, not a specific card's own play/effect.
	"card_draw_single": "ui/one card draw.mp3", # One card arriving - played once per card for every draw that ISN'T the turn-start hand (a DRAW card effect resolving mid-turn - see _draw_cards()'s own DrawSoundMode.PER_CARD branch). A quiet, frequent texture cue (plays on every single-card draw, every battle), so both this and card_draw_hand above get randomized pitch_scale per play (battle.gd's _play_draw_sfx()) so repeated plays don't read as identical - the ONLY two sounds in SFX_FILES that vary pitch at all today.
	"deck_reshuffle": "ui/shuffle.mp3", # The discard pile turning back into the draw pile MID-battle - see battle.gd's _reshuffle_discard_into_draw(), the only caller, hooked right at its own top. Distinct from battle-start's own draw_pile.shuffle() (a separate, unrelated code path in _start_battle() that builds the pile fresh from RunState.deck - see that function's own doc) - this cue marks the mid-battle discard turnover specifically, never the fresh-run setup.
	"door_opened": "field/open_door.wav",
	"door_unlock": "", # See DESIGN.md's Audio section - needs a short lock-disengaging cue, distinct from door_opened's creak.
	"victory": "",
	"defeat": "",
	"escape": "", # A combat node resolving via escape (see battle.gd's _on_battle_escaped()) - same "no file recorded yet" placeholder as victory/defeat above.
	# walking.wav was replaced with walking.wav.mp3 - only the .mp3 exists
	# on disk now, so this has to point there or every play_looping/
	# play_sfx("walking") call fails (ResourceLoader.exists() false).
	"walking": "field/walking.wav.mp3",
	"combat_start": "combat/combat_start.mp3",
	"select_card": "cards/select_card.wav",
	"game_start": "ui/game_start.mp3",
	"rare_drop": "cards/ultra_rare.mp3",
	"heal": "cards/Kept_warmth.mp3", # A HEAL card effect actually restoring HP (see battle.gd's _heal_player()) - Kept Warmth is the only card using HEAL today, so this doubles as its own dedicated cue; a future second heal card would share it too, same "generic mechanic slot" shape wind_up/debris_spawn already use.
	"full_block": "combat/full_block.mp3", # An enemy attack fully absorbed by player block - zero HP lost. Not played on a PARTIAL block, which still plays damage_player instead (see battle.gd's _enemy_attack_player()).
	"weapon_equipped": "ui/Wanderer_Equip_Sword.mp3", # Played by reward_screen.gd's _on_weapon_pickup_resolved() when the player takes the offered weapon.
	"chain_impact": "combat/chain_burst.mp3", # The chain payoff landing (see battle.gd's _deal_damage_to_enemy()) - played layered ON TOP of damage_enemy, not instead of it, both firing the same frame chain_payoff_delay_sec after the Closer's own hit (see _trigger_chain_payoff()). ~2s, distinct texture (a boom/crack with tail) from hit.wav's own punchy ~0.17s - the two never overlap: the Closer's own hit.wav has long finished (0.17s < the 0.3s gap) before this ever starts.
	"debris_spawn": "enemies/Beachwrack/Tideworn spawn.mp3", # The Beachwrack's Knocks Something Loose - a second enemy joining the fight (see battle.gd's _spawn_additional_enemy()). TODO: Beachwrack's debris_spawn_enemy now points at Sputter (Tideworn's retirement pass), so this cue's own filename no longer names the enemy it plays for - placeholder audio, retargeting it is out of scope for that pass.
	"wind_up": "enemies/Beachwrack/Beachwrack Wind Up.mp3", # Any WIND_UP intent resolving (see battle.gd's _resolve_enemy_intent() and enemy_intent.gd's WIND_UP doc) - generic over the mechanic, not Beachwrack-specific code, even though it's the only enemy using it today.
	"beachwrack_impact": "enemies/Beachwrack/Beachwrack Impact.mp3", # The Beachwrack's own landed-hit sound, wired via EnemyData.attack_impact_sfx (see battle.gd's _enemy_attack_player()) instead of the shared damage_player cue - a creature this size shouldn't sound like every other enemy's hit.
	"chain_refund": "combat/hp_loss_card_heartbeat.mp3", # A HEAL-type chain payoff's own cue, not a hit (see battle.gd's _heal_player()'s chain_payoff parameter and PlayerBattleVisual.play_chain_refund_aura()) - built for Bite Down's own refund, removed 2026-08-26 (see DESIGN.md's Wanderer entry), so unused by any card today but left wired for whatever uses that payoff shape next. Layered ON TOP of "heal" above, same "distinct texture, additional cue" pairing chain_impact/damage_enemy already use. A heartbeat, not an impact - blood staying in the body, paired with the aura's own pulse.
	"weapon_reflect": "combat/wanderer_creditor_weapon.mp3", # The Creditor's own reflected hit (see battle.gd's _deal_damage_to_enemy()'s weapon_reflect parameter) - played layered ON TOP of damage_enemy, same pairing shape as chain_impact.
	"retaliation_hit": "", # Retaliation's own reflected hit (see battle.gd's _deal_damage_to_enemy()'s retaliation parameter) - played layered ON TOP of damage_enemy, same pairing shape as weapon_reflect above. No file recorded yet, same placeholder convention.
	"chain_stoppage": "combat/stoppage_chain.mp3", # Guillotine's chain payoff (see card_effect.gd's STUN and battle.gd's _resolve_card_effect()) landing on the target.
	"guillotine_play": "combat/Guillotine.mp3", # Guillotine's own per-card override (see CardData.play_sfx and battle.gd's _apply_card_effects()) - distinct from the shared "card_play" cue every other card still uses, and from "chain_stoppage" above, which is the SEPARATE cue for its chain payoff landing a beat later. Re-recorded (2026-08-26) alongside Guillotine's single-instance rework - the old guillotine.wav was cut for a 3-hit flurry; this is a single heavier blow instead. combat/multi_hit_attack.wav was added in the same pass, reserved for whichever future card actually needs a multi-hit cue - not wired to anything today. Fires alongside Guillotine's own impact_delay wind-up (CardData.impact_delay - see that field's own doc), not the instant the card is played. Re-trimmed (2026-08-27, same filename - Godot picks up the new content automatically) after the first version of this file turned out to carry ~1.2s of leading silence before its actual impact sound, which read as the sound starting over a second late even though the CODE was already firing play_sfx at the correct moment (verified) - the delay was in the audio asset, not the timing logic.
	"rally_recover": "combat/Rally.mp3", # The Wanderer's Rally passive actually paying out (see battle.gd's _deal_damage_to_enemy()'s rally_payoff parameter to _heal_player()) - REPLACES "heal" above for that one heal, rather than layering on top of it (unlike chain_refund/heal, which do layer) - a Rally recovery is its own moment, not a variant of an ordinary heal card landing.
	"siphon_play": "combat/Siphon.mp3", # Siphon's own per-card override (see CardData.play_sfx and battle.gd's _play_card()) - same shape as guillotine_play above: distinct from the shared "card_play" cue every other card still uses, fires the instant the card is played, not tied to either of its two effects (DAMAGE/HEAL) resolving.
	"selfeater_play": "combat/wanderer_selfeater.mp3", # Selfeater's own per-card override (see CardData.play_sfx and battle.gd's _play_card()) - same shape as guillotine_play/siphon_play above: distinct from the shared "card_play" cue, fires on activation (the instant the card is played), not tied to the status it applies or anything that status later does. Selfeater is STANCE-typed, which _play_card() treats as skill-shaped (see the STANCE-plumbing pass) - this still fires exactly once, just on the deferred skill-shaped timing (after the commit push lands), not the ATTACK-only immediate branch.
	"selfeater_strike": "combat/Selfeater_Strike.mp3", # NOT "selfeater_play" above - that one fires once, when the Selfeater card itself is played (activation). This is the ongoing REPLACEMENT for "damage_enemy" for every hit landed on an enemy while Selfeater's Mark is active (see battle.gd's _damage_enemy_sfx_name(), the only place that reads this key) - a distinct texture for the character's attacks while under the effect, not a layered addition on top of the normal hit like chain_impact/weapon_reflect above.
	"gun_attack_with_supply": "enemies/Works_Gun/Attack_with_supply.mp3", # Gun's own landed-hit sound while Supply (its damage_source_enemy) is still alive - wired via EnemyData.damage_source_alive_sfx, read by battle.gd's _encounter_linked_impact_sfx() the same way attack_impact_sfx overrides the shared damage_player cue above, just conditioned on the encounter-link mechanic's own live state instead of being a flat per-enemy override.
	"gun_attack_without_supply": "enemies/Works_Gun/Attack_without_supply.mp3", # Gun's own landed-hit sound once Supply is defeated (the fallback-damage state, EnemyData.damage_source_dead_value) - EnemyData.damage_source_dead_sfx's own cue, same read site as gun_attack_with_supply above.
	"mushroom_growth": "enemies/Works_Mushroom/Mushroom Growth.mp3", # Played once per NON-erupting growth-stage advance (see battle.gd's _advance_growth_stage()) - every turn the Mushroom's own stage track ticks forward except the very last, which plays mushroom_explosion below instead, never both.
	"mushroom_explosion": "enemies/Works_Mushroom/Mushroom Explosion.mp3", # The Mushroom's own landed-hit sound when its growth track completes (see EnemyData.attack_impact_sfx, read by battle.gd's _enemy_attack_player() the same way beachwrack_impact overrides the shared damage_player cue) - a fixed override, not conditional like gun_attack_with/without_supply above, since an eruption only ever happens one way.
	"ragged_breath": "enemies/Works_Wardling/Ragged Breath.mp3", # The Wardling's own pain-turn cue - wired via EnemyData.pain_turn_sfx, read by battle.gd's _check_pain_turn_trigger() the instant the HP-threshold pain turn actually fires. No shared/generic pain-turn sound exists to fall back to (see that field's own doc) - every other enemy with no pain_turn_sfx authored stays silent for this beat.
	"supply_death": "enemies/Works_Gun/Supply_death.mp3", # Supply's own death cue - wired via EnemyData.defeat_sfx, read by battle.gd's _on_enemy_defeated() the instant this combatant is confirmed defeated. No shared/generic defeat sound exists to fall back to (same shape as ragged_breath above) - every other enemy with no defeat_sfx authored stays silent on death.
	"ambient_wind_beach": "ambient/ambient_wind_beach.mp3", # A region's continuous ambient bed, not a triggered SFX - wired via BiomeData.ambient_loop_name (see that field's own doc) and started/stopped through play_looping()/stop_looping() below, never play_sfx(). Lives in its own ambient/ subfolder rather than one of the per-trigger-category folders (cards/combat/enemies/field/ui) the rest of this dictionary uses, since nothing "triggers" it - assets/audio/ambient/ has been reserved for exactly this since the folder layout was decided (see DESIGN.md's Audio section). Filed here anyway, not in a second dictionary, because the looping API below is already generic over any name in THIS dictionary - a second registry would mean duplicating _resolve_stream()/_get_stream() for no benefit.
	"water_drink": "field/drink.mp3", # The Dunes heap's Cold Water card actually being drunk (see field_heap.gd's _play_water_reveal()) - fires once, at the click, the same moment the HP change lands and the pulled signal's own HUD refresh fires. Distinct from "heal" above (Kept Warmth's own card-play cue) - this is a field interaction's own moment, not a battle card effect, same "a different context gets its own cue even for a similar mechanic" split rally_recover already carries against heal.
	"sift_dig": "field/sift through dune.mp3", # The wreckage heap's own dig moment (2026-09-04) - fires once per commit to Sift (field_heap.gd's _on_sift_pressed()), the instant the HP cost is paid, before whatever outcome.text/effect actually resolves. Not played on the exhausted branch (no real dig happens there - Sift itself is hidden once _exhausted is true, see _show_prompt()).
	"shard_collected": "", # The heap's own buried shard, clicked once fully revealed (see field_heap.gd's _on_shard_clicked()) - the FIRST real world shard pickup in the game (see run_state.gd's `shards` field's own doc: no world shard-pickup source existed before this). No file recorded yet - same empty-string "wired everywhere it should play, no audio file exists yet" placeholder convention this dictionary's own header comment describes (door_unlock/victory/defeat/escape/retaliation_hit above are the same shape) - play_sfx() no-ops silently (with a warning) until one is authored.
	"footstep_1": "field/Region 1 Walking/Footstep1.mp3",
	"footstep_2": "field/Region 1 Walking/Footstep2.mp3",
	"footstep_3": "field/Region 1 Walking/Footstep3.mp3",
	"footstep_4": "field/Region 1 Walking/Footstep4.mp3",
	# The per-step footstep pool (2026-09-04, footstep-cadence pass) -
	# REPLACES "walking" (field/walking.wav.mp3, still registered below,
	# still a real file - just unreferenced now, see player.gd's own
	# _play_footstep()) as the field's own footstep sound. "walking" was
	# a single continuous LOOP (play_looping()/stop_looping()); these four
	# are one-shots instead, one per footfall, picked by player.gd's own
	# cadence timer and played through play_varied() below - no VOLUME_
	# TRIM_DB entries for these four (see that dict's own note by "walking"
	# right below) since play_varied() takes its volume from the CALLER's
	# own export, never this dictionary. No per-region table - these are
	# simply "the walk sound" everywhere for now (see player.gd's own doc);
	# a future second region's own set would hook in wherever player.gd
	# picks FOOTSTEP_NAMES, keyed off the current biome/region, not here.
}

# Per-sound volume trims, in dB, layered on top of master_volume below.
# These exist because the placeholder files are wildly inconsistent in
# loudness - measuring each one (peak and RMS level, via a quick Python
# script over the raw WAV data) found card_play/hit/gold/coin all sitting
# within a hair of full-scale (~-1 dBFS RMS - essentially as loud as a
# digital signal gets), select_card sitting much quieter (~-31 dBFS RMS,
# with headroom to spare). combat_start was replaced (now a .wav, not the
# original .mp3) and re-measured at ~-13.4 dBFS RMS with 0 dBFS peak (no
# headroom at all) - trimmed down toward the ~-18 dBFS RMS target since
# it can't be boosted without clipping. game_start is an MP3, like
# walking - no MP3 decoder is available in this environment (no
# ffmpeg/pydub) to measure it the same way, so its trim is left at 0.0
# until it's been heard in-game and tuned by ear. The trims below started
# as a pull toward a common ~-18 dBFS RMS target, capped so nothing
# pushes past 0 dBFS and clips - door_opened and walking have since been
# retuned by ear after playtesting (the measurement is a starting point,
# not the final word). Re-measure and re-tune whenever a placeholder file
# gets replaced with real art - these numbers describe THESE files, not
# some universal constant.
const VOLUME_TRIM_DB := {
	"card_play": -17.3,
	"damage_enemy": -3.7, # Trimmed (2026-09-07) - -3.7dB is a ~35% cut in linear amplitude (20*log10(0.65)), same "not a from-measurement value" shape the old Strike.mp3 trim used (20*log10(0.7) for its own 30% cut) - no decoder available here to measure combat/Slash.mp3 directly. Retune by ear again if 35% wasn't enough or overshot.
	"damage_player": -17.1,
	"gold_claimed": -17.4,
	"add_card": 0.0, # An MP3, same "no decoder available here" placeholder as chain_impact/rally_recover/guillotine_play/block_gained above - left untrimmed until it's been heard in-game and tuned by ear.
	"door_opened": 3.0,
	"walking": -8, # UNREFERENCED (2026-09-04, footstep-cadence pass) - "walking" (field/walking.wav.mp3) is no longer played anywhere; player.gd's own footstep cadence plays footstep_1..4 through play_varied() instead, which never reads this dictionary. Left in place, not deleted, per that pass's own brief - the asset and this entry are simply dead now, not removed.
	"combat_start": -4.5,
	"select_card": 10.5,
	"game_start": 0.0,
	"chain_impact": 0.0, # An MP3, like game_start/walking - no decoder available here to measure it the same way as the WAVs above. Left untrimmed until it's been heard in-game and tuned by ear (same "measurement is a starting point" note above).
	"rally_recover": 0.0, # An MP3, same "no decoder available here" placeholder as chain_impact/game_start above. Left untrimmed until it's been heard in-game and tuned by ear.
	"guillotine_play": 0.0, # RESET (2026-08-26) - the old -1.94dB trim was tuned by ear for the previous guillotine.wav specifically; it describes THAT file, not the new Guillotine.mp3 that replaced it (see SFX_FILES's own note). An MP3, like chain_impact/rally_recover/game_start above - no decoder available here to measure it - left untrimmed until it's been heard in-game and tuned by ear.
	"block_gained": 0.0, # An MP3, same "no decoder available here" placeholder as chain_impact/rally_recover/guillotine_play above - left untrimmed until it's been heard in-game and tuned by ear.
	"card_upgrade": 0.0, # An MP3, same "no decoder available here" placeholder as add_card above - left untrimmed until it's been heard in-game and tuned by ear.
	"card_draw_hand": -12.0, # Deliberately quieter than every trim above, not a placeholder awaiting a decoder - draws happen every single turn of every battle (unlike a one-off keeper/forge/rare-drop moment), so this needs to sit back as texture rather than announce itself as an event. -12dB chosen as a starting "noticeably quieter, still audible" pull; re-tune by ear once heard in-game, same as any other trim here.
	"card_draw_single": -12.0, # Same reasoning and same starting value as card_draw_hand above - this one plays even MORE often (once per card on every mid-turn DRAW effect), so it gets the identical quiet treatment rather than a separate, harder-to-justify number.
	"deck_reshuffle": -8.0, # Quiet, but not as far back as the draw cues above (-12dB) - a reshuffle is rarer (once every few turns, not every draw) and a bigger physical event than a single card sliding, so it sits between the draw texture and the untrimmed 0dB keeper/forge one-off events, closer to the draw end of that range. Starting point, same "tune by ear once heard in-game" caveat every trim here carries.
	"water_drink": 0.0, # An MP3, same "no decoder available here" placeholder as add_card/card_upgrade above - left untrimmed until it's been heard in-game and tuned by ear. A one-off field interaction, not a per-turn texture cue, so it starts at the same untrimmed baseline every other one-off event sound here does, not the draw cues' quieter -12dB.
	"sift_dig": 0.0, # An MP3, same "no decoder available here" placeholder as water_drink above - left untrimmed until it's been heard in-game and tuned by ear.
}

@export_range(0.0, 1.0, 0.01) var master_volume: float = 0.7

@export var hp_loss_breath_volume_offset_db: float = -7.0
# hp_loss_breath's own volume (2026-09-07, self-damage-sound pass) - a
# dedicated export, not a VOLUME_TRIM_DB entry like every other sound
# above, since this one plays LAYERED alongside whatever impact sound
# follows it (see hp_loss_breath_impact_delay_sec below and battle.gd's
# _deal_self_damage()) and is tuned to sit quieter/behind that impact,
# not at an independent flat level picked in isolation - same "a caller
# needs its own exported, live-tunable volume rather than a shared
# dictionary entry" shape play_varied()'s own doc already establishes
# for player.gd's footsteps. -7dB relative to impact-sound loudness is a
# starting point (no MP3 decoder available here to measure either file
# directly) - retune by ear once heard in-game.

@export var hp_loss_breath_impact_delay_sec: float = 0.11
# How long battle.gd's own _deal_self_damage() waits, after playing the
# breath cue, before anything else in that function continues (see its
# own doc) - "pay, then hit" instead of the two sounds landing on top of
# each other. AudioManager doesn't sequence card effects itself (see
# this file's own header) - this export is only the tunable NUMBER;
# battle.gd is what actually awaits it, and only within _deal_self_
# damage()'s own tail, never gating anything upstream of it (see that
# function's own doc for the exact boundary and why it stops there).

const POOL_SIZE := 8
# How many sounds can genuinely overlap before the oldest playing one
# gets reused - see _next_free_player(). 8 comfortably covers anything
# this game currently does in one moment (a card play plus a couple of
# hit sounds plus a UI sound, with room to spare).

var _players: Array[AudioStreamPlayer] = []
var _next_player_index: int = 0
var _stream_cache: Dictionary = {} # file name -> loaded AudioStream (or null if missing).
var _warned_missing: Dictionary = {} # sound name -> true, so a missing sound only warns once.

func _ready() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)

# The main entry point for one-shot sounds - a click, a hit, a claim.
# Looks up sound_name in SFX_FILES, grabs a free player from the pool,
# and plays it at that sound's trimmed, master-scaled volume. Silently
# (but loudly, in the console) does nothing if sound_name isn't mapped to
# a real file yet.
#
# pitch_scale defaults to 1.0 (unchanged pitch) - the ONLY callers that
# pass anything else today are battle.gd's draw sounds (_play_draw_sfx()),
# which need per-play variance so a sound heard every turn of every battle
# doesn't read as identical each time (see card_draw_hand/card_draw_single's
# own SFX_FILES doc). Set UNCONDITIONALLY on every call, not just when a
# caller passes a non-default value - this._players is a small round-robin
# POOL (see _next_free_player()), so a player last used for a varied draw
# sound would otherwise leave ITS pitch_scale sitting non-1.0 on the node
# itself, silently bleeding into whatever unrelated sound reuses that same
# player next.
func play_sfx(sound_name: String, pitch_scale: float = 1.0) -> void:
	var stream := _resolve_stream(sound_name)
	if stream == null:
		return
	var player := _next_free_player()
	player.stream = stream
	player.volume_db = _volume_db_for(sound_name)
	player.pitch_scale = pitch_scale
	player.play()

# One-shot play with a RANDOM per-play pitch (drawn fresh from [pitch_
# min, pitch_max] each call, unlike play_sfx()'s own pitch_scale, which
# the CALLER rolls ahead of time) and an explicit volume trim that
# bypasses VOLUME_TRIM_DB entirely (2026-09-04, footstep-cadence pass) -
# built for player.gd's own footstep cadence, the one caller that needs
# its own exported, live-tunable volume rather than a shared dictionary
# entry every OTHER sound reads. Scoped to exactly that need - one
# method, not a general pooled-cadence framework: it doesn't know what a
# "footstep" is, doesn't pick between takes, doesn't track repeats -
# sound_name is a single, already-chosen SFX_FILES entry, same as play_
# sfx() takes. Still master_volume-scaled, still drawn from the same
# POOL_SIZE players play_sfx() uses - only the volume SOURCE and the
# pitch-randomization differ.
func play_varied(sound_name: String, pitch_min: float, pitch_max: float, volume_db_trim: float) -> void:
	var stream := _resolve_stream(sound_name)
	if stream == null:
		return
	var player := _next_free_player()
	player.stream = stream
	player.volume_db = volume_db_trim + linear_to_db(master_volume)
	player.pitch_scale = randf_range(pitch_min, pitch_max)
	player.play()

# The one call site for hp_loss_breath (2026-09-07, self-damage-sound
# pass) - battle.gd's _deal_self_damage() is the only caller. Same shape
# as play_varied() above (its own exported, live-tunable volume, not
# VOLUME_TRIM_DB), minus the pitch randomization - this sound has no
# per-play-variance need play_varied()'s repeated-every-turn footsteps
# do. Un-pooled-player-agnostic like every other one-shot here (still
# drawn from the shared POOL_SIZE players) - only the volume source
# differs from plain play_sfx().
func play_hp_loss_breath() -> void:
	var stream := _resolve_stream("hp_loss_breath")
	if stream == null:
		return
	var player := _next_free_player()
	player.stream = stream
	player.volume_db = hp_loss_breath_volume_offset_db + linear_to_db(master_volume)
	player.pitch_scale = 1.0
	player.play()

# Shared by play_sfx() and the looping API below: sound_name -> the
# AudioStream to play, or null (with a console warning) if sound_name
# isn't a known name or has no file mapped to it yet.
func _resolve_stream(sound_name: String) -> AudioStream:
	if not SFX_FILES.has(sound_name):
		push_warning("AudioManager: '%s' isn't a known sound name." % sound_name)
		return null
	var file_name: String = SFX_FILES[sound_name]
	if file_name == "":
		if not _warned_missing.has(sound_name):
			_warned_missing[sound_name] = true
			push_warning("AudioManager: no audio file mapped for '%s' yet - add one to SFX_FILES." % sound_name)
		return null
	return _get_stream(file_name)

func _get_stream(file_name: String) -> AudioStream:
	if _stream_cache.has(file_name):
		return _stream_cache[file_name]
	var path := SFX_FOLDER + file_name
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
		if stream == null:
			push_error("AudioManager: '%s' exists but didn't load as an AudioStream." % path)
	else:
		# Usually means SFX_FILES points at a filename that doesn't match
		# what's actually in assets/audio/ anymore - e.g. a file got
		# replaced with a different extension (.wav -> .mp3) without the
		# mapping being updated to match.
		push_error("AudioManager: missing audio file '%s'." % path)
	_stream_cache[file_name] = stream
	return stream

# --- Looping sounds ---
#
# Everything above is one-shot: fire it, forget it, the pool hands the
# next call whichever player is free. A looping sound (right now, just
# footsteps - see player.gd) is a state instead of a moment: it should be
# playing for as long as something is true and silent otherwise, which
# means something has to be able to start AND stop this specific sound on
# demand. That doesn't fit the pool (any of its players could be holding
# the loop, and stopping "the walking sound" would mean hunting for
# which one) - so looping sounds each get their own dedicated player
# instead, created the first time they're needed and kept in
# _looping_players by name.

var _looping_players: Dictionary = {} # sound name -> AudioStreamPlayer

# Starts sound_name looping if it isn't already playing - safe to call
# every frame something is true (see player.gd calling this every
# physics frame the player is moving), since it no-ops once the loop is
# already running instead of restarting it from the beginning each time.
func play_looping(sound_name: String) -> void:
	var player := _looping_player_for(sound_name)
	if player != null and not player.playing:
		player.play()

func stop_looping(sound_name: String) -> void:
	if _looping_players.has(sound_name):
		_looping_players[sound_name].stop()

# Safety net for scene changes: a looping sound started in one scene
# (walking, in a field room) has no reason to know or care that the
# scene it started in is about to disappear - see scene_transition.gd,
# which calls this at the start of every go_to() so a loop can never
# bleed into whatever scene comes next (a battle, the title screen, ...).
func stop_all_looping() -> void:
	for player in _looping_players.values():
		player.stop()

# Same sweep as stop_all_looping() above, except one named loop is left
# running - the region ambient bed's own way of surviving a field-room-to-
# field-room scene swap without an audible cut (see scene_transition.gd's
# go_to(), the only caller: it already knows, from the destination path
# alone, whether the scene it's swapping to is another field room, and
# passes that room's own BiomeData.ambient_loop_name here instead of
# calling stop_all_looping() plain). A NEW method, not a parameter added
# to stop_all_looping() itself - stop_all_looping() has exactly two
# callers today (both in scene_transition.gd, at the two points documented
# there) and both keep their exact current unconditional behavior for
# every OTHER transition; adding this alongside it, rather than changing
# its signature, means neither of those calls (nor any future one) has to
# reason about an exemption it doesn't need. except_name = "" behaves
# identically to stop_all_looping() - callers don't need to branch on
# whether they have an exemption to apply.
func stop_all_looping_except(except_name: String) -> void:
	for sound_name in _looping_players:
		if sound_name != except_name:
			_looping_players[sound_name].stop()

func _looping_player_for(sound_name: String) -> AudioStreamPlayer:
	if _looping_players.has(sound_name):
		return _looping_players[sound_name]
	var stream := _resolve_stream(sound_name)
	if stream == null:
		return null
	# The stream itself has to be told to loop - an AudioStreamPlayer just
	# plays whatever its stream does once through and stops. Duplicated
	# first, NOT the shared _stream_cache instance - flipping the loop
	# setting on that would make any future play_sfx() call using the same
	# file loop forever too. WAV and MP3 each expose looping differently
	# (loop_mode enum vs. a plain loop bool) - handled per format here
	# since this project's audio files aren't all one type (see SFX_FILES,
	# where "walking" is currently an MP3).
	if stream is AudioStreamWAV:
		var looping_wav: AudioStreamWAV = (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		looping_wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream = looping_wav
	elif stream is AudioStreamMP3:
		var looping_mp3: AudioStreamMP3 = (stream as AudioStreamMP3).duplicate() as AudioStreamMP3
		looping_mp3.loop = true
		stream = looping_mp3
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = stream
	player.volume_db = _volume_db_for(sound_name)
	_looping_players[sound_name] = player
	return player

# Round-robin pool: each call takes the next player in line that isn't
# currently playing, so overlapping sounds each get their own voice
# instead of a new sound cutting an already-playing one off. If every
# player in the pool is busy (more overlap than POOL_SIZE at once - not
# something this game currently produces), it steals the next one in
# rotation rather than dropping the new sound entirely.
func _next_free_player() -> AudioStreamPlayer:
	for i in _players.size():
		var index := (_next_player_index + i) % _players.size()
		if not _players[index].playing:
			_next_player_index = (index + 1) % _players.size()
			return _players[index]
	var stolen := _players[_next_player_index]
	_next_player_index = (_next_player_index + 1) % _players.size()
	return stolen

func _volume_db_for(sound_name: String) -> float:
	var trim_db: float = VOLUME_TRIM_DB.get(sound_name, 0.0)
	return trim_db + linear_to_db(master_volume)
