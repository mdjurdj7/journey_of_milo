extends Resource
# "extends Resource" means this isn't a node that lives in a scene - it's
# a data container, the same "define once as a .tres, reference it from
# anywhere" shape as CardData/EnemyData/StatusEffectData. This file is
# the STATIC definition of one NPC only - who she is, what she says, what
# she gives - never her runtime state. Whether THIS run's player has
# already talked to her lives on RunState instead (a future npc_
# interacted-style dictionary, keyed by npc_id below, mirroring RoomState.
# structure_resolved's own shape) - same "static Resource vs. per-run
# mutable state" split EnemyData/EnemyCombatant and StatusEffectData/
# ActiveStatus already use. Nothing on this resource ever changes at
# runtime; two different NPCs (or the same NPC placed in two different
# rooms, once that's a real thing) safely share nothing by reference
# here, since there's no mutable per-instance state to collide over.

class_name NPCData
# Lets us use "NPCData" as a type name elsewhere in the project, and lets
# Godot list it as a resource type we can create in the editor - exactly
# like CardData/EnemyData already do for their own kind of thing.

@export var npc_id: String = ""
# Which entry of RunState's own future "have I talked to this NPC"
# dictionary this specific NPC is tracked under - mirrors EnemyData's
# implicit identity-by-resource and, more directly, field_blob.gd's own
# blob_id/field_structure.gd's own structure_id (both String keys into a
# RoomState dictionary). This one's the RUN-scoped version of that same
# idea (see this file's own header) rather than room-scoped, since an
# NPC's own resolved state is meant to survive independent of whether her
# room ever gets revisited - not built yet, but this is the field that
# handoff will key off of once it exists.

@export var npc_name: String = ""
# The name shown for her, e.g. above her silhouette or as a dialogue
# speaker label once that UI exists - same role CardData.card_name/
# EnemyData.enemy_name already play for their own kind of thing.

@export var dialogue_text: String = ""
# What she says on contact BEFORE RunState.npc_interacted has her - the
# offer line, shown alongside her card (see field_room.gd's own _on_npc_
# entered()). A single flat string, the same "start with the simplest
# shape that holds real content" instinct EnemyData's own flavor_text
# field already follows for enemies - two lines (this one and post_
# interaction_text below) turned out to be exactly what a second NPC's
# needs would have demanded anyway, not more.

@export var post_interaction_text: String = ""
# What she says on contact AFTER RunState.npc_interacted has her
# (2026-08-27) - a SEPARATE line, not a second read of dialogue_text
# above, since "here's what I'm offering" and "you've already taken it"
# are different beats, not the same line replayed. No card appears
# alongside this one (see field_room.gd's own _on_npc_entered() - the
# already-interacted branch never calls _show_npc_offer_card()). Shown
# EVERY time she's re-approached after accepting, not just once - same
# "no first-time-only gating" shape dialogue_text's own display already
# has. Same OfferLabel, same Spectral world-voice styling, same fade
# timing (offer_fade_in_sec/_out_sec) as dialogue_text - only WHICH
# string gets shown depends on npc_interacted, nothing about how it's
# shown differs.

@export var granted_cards: Array[CardData] = []
# REPLACED a single `granted_card: CardData` field (2026-08-27, offer-
# pool pass) - one entry means the same "always this exact card" she's
# always offered; more than one means field_room.gd picks ONE at random
# when her offer first shows (see its own _show_npc_offer_card()), the
# same "flat @export array of resources, not a nested pool structure"
# shape EncounterData.enemies/CardData.upgrades above already use for
# their own "pick/use one of several" cases. The pick itself is NOT
# stored here - this Resource is still the static, never-mutated
# definition of who she is (see this file's own header); which specific
# card she's ALREADY OFFERING this visit is per-run interaction state,
# and lives on field_room.gd instead (see its own _npc_offer_picked_card
# doc for exactly why and how that stays stable across a walk-away/
# return cycle). Empty is a legitimate value (an NPC who has nothing to
# give, or whose interaction hasn't been designed yet) - _show_npc_
# offer_card() simply has nothing to pick from and shows no card, same
# permissive stance the old null case already took.

@export var visual_scene: PackedScene = null
# Her field silhouette - same "one hand-drawn Polygon2D scene, referenced
# by a data resource rather than baked into the trigger that uses it"
# shape EnemyData.visual_scene already establishes, instantiated by
# whatever Area2D trigger holds this NPCData (see field_npc.gd) the same
# way field_blob.gd instantiates an EnemyData's own visual_scene. Null
# is handled the same permissive way EnemyData's own field is - left
# empty, nothing crashes, it just has nothing to show yet. Not every
# NPC's own visual scene has to be vector art the way every enemy
# silhouette so far happens to be - Keeper (see npc_visual_keeper.tscn)
# is this project's first raster sprite outside the player character,
# a plain Sprite2D wrapped in a Node2D root, same shape as this field's
# own vector-based precedent.

@export var visual_scale: float = 1.0
# Per-NPC multiplier on top of field_npc.gd's own instantiation of
# visual_scene above - same role and same reasoning as EnemyData's own
# field_visual_scale (see enemy_data.gd): every silhouette/sprite is
# authored at its own arbitrary coordinate scale, so a flat "instantiate
# at 1:1" would render two different NPCs at wildly different real
# sizes. 1.0 means no adjustment. Keeper's own visual (a real-world
# painted sprite, not a hand-drawn silhouette placed at field scale by
# eye) needed a real value here - see field_npc.gd's own _ready() for
# where this actually gets applied, and this NPC's own .tres for the
# tuned number and its own note on how it compares to the Wanderer's.
