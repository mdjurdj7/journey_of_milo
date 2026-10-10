#!/usr/bin/env bash
# Runs the headless probes (tests/*_probe.gd) - all of them, an area's, or
# the ones a change touches - as parallel headless Godot processes, and
# says which passed. See CLAUDE.md's Probes section for when to run what.
#
#   tools/run_probes.sh --full                    every probe
#   tools/run_probes.sh --fast                    the fast tier (tools/probe_times.txt)
#   tools/run_probes.sh --prepush                 before a push: the probes for the files
#                                                 changed in origin/main..HEAD, plus the
#                                                 fast tier - listed first
#   tools/run_probes.sh --area keywords,face      an area's probes (--list-areas)
#   tools/run_probes.sh --changed [BASE]          the probes for the files changed
#                                                 since BASE (default HEAD)
#   tools/run_probes.sh --probe kill_order,floor4 named probes ("_probe" optional);
#                                                 repeat --probe or comma-separate,
#                                                 or both - every name runs
#
# Options:
#   -j N             parallel probes (default: 1 while under JOBS_TWO_MIN_FREE_MB,
#                    6 GB, is free at the start, else 2). Probes marked serial in
#                    the table below always run alone, after the rest.
#   --worktree [DIR] run in the persistent probe worktree (default
#                    ../journey-of-milo-probe), not this tree: take its lock,
#                    check out --ref, copy --files over it, and import only
#                    when .import files or new files came in. Made, with a
#                    copy of this tree's .godot, the first time.
#   --ref REF        what the worktree checks out (default: this tree's HEAD)
#   --files a,b      with --worktree: these working-tree files are copied
#                    over the checkout (a deleted one is deleted there) - the
#                    uncommitted change under test. With --changed and no
#                    --files, the changed files are copied.
#   --wait MIN       how long to wait for a busy worktree (default 30)
#   --path DIR       run in DIR instead of this tree (no worktree handling)
#   --import         run Godot's --import first (--path or this tree)
#   --logs DIR       where the logs go (default: a fresh temp folder)
#   --list           print the plan and stop
#   --refresh-times  copy the local measured times (tools/probe_times.local.txt,
#                    what runs write) over tools/probe_times.txt, to commit
#   --mapping-gaps   each probe, and the paths it loads (res:// in its
#                    source) that its areas don't map to it
#   --batch K/N      run group K of the selection split into N groups of
#                    near-equal measured time (tools/probe_times.txt):
#                    --full --batch 1/4 ... 4/4 is the whole suite, a
#                    group at a time
#   --moved A[..B]   with --list: also print what the HEAD-moved check
#                    would say had commits A..B (B default HEAD) landed
#                    during this run - a dry run of that check
#
# GODOT overrides the engine (default ../Godot_v4.7.1.exe beside the repo:
# the main executable, not the _console wrapper). Exit code 0 = every
# probe passed, 1 = a failure, 2 = usage, 3 = the worktree stayed busy,
# 4 = memory stayed short (see the memory guard below).

set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GODOT=${GODOT:-$REPO/../Godot_v4.7.1.exe}
PROBE_TIMEOUT_SEC=600

# --- Memory guard ---
# A probe - a headless Godot - takes up to about PROBE_MEM_MB, and none is
# started (nor the import) while that would leave under MIN_FREE_MB free:
# the run waits for memory instead (await_memory()). With none of its own
# probes running to give any back, it waits MEM_WAIT_MAX_SEC at most, then
# stops (exit 4). A probe started under PROBE_RAMP_SEC ago is still
# loading, its memory not yet taken: it counts as if it had. Free is
# MemAvailable where the system gives it, else MemFree - Git Bash's,
# which is Windows' available memory.
MIN_FREE_MB=2000
PROBE_MEM_MB=1024
MEM_WAIT_MAX_SEC=600
PROBE_RAMP_SEC=10
# The default -j (none given): 2 when at least this much is free at the
# start, else 1.
JOBS_TWO_MIN_FREE_MB=6144
LAST_START=0
free_mb() {
	awk '/^MemAvailable:/ { a = $2 } /^MemFree:/ { f = $2 } END { v = a ? a : f; if (v) print int(v / 1024) }' /proc/meminfo 2>/dev/null
}
await_memory() {
	local free need idle=0 told=0
	while :; do
		free=$(free_mb)
		[ -n "$free" ] || return 0
		need=$((MIN_FREE_MB + PROBE_MEM_MB))
		[ $(( $(date +%s) - LAST_START )) -lt "$PROBE_RAMP_SEC" ] && need=$((need + PROBE_MEM_MB))
		[ "$free" -ge "$need" ] && return 0
		if [ "$told" = 0 ]; then
			echo "run_probes: $free MB free - waiting for $need MB before the next probe"
			told=1
		fi
		if [ -z "$(jobs -rp)" ]; then
			idle=$((idle + 1))
			if [ "$idle" -ge "$MEM_WAIT_MAX_SEC" ]; then
				echo "run_probes: still $free MB free after ${MEM_WAIT_MAX_SEC}s with none of its probes running - stopping" >&2
				exit 4
			fi
		fi
		tick
	done
}

# --- Cleanup: nothing this run starts outlives it ---
# However it ends - done, Ctrl+C, a TERM, or the shell that started it
# gone (a session stopped under it sends no signal: tick() notices) -
# every child's whole process tree is ended, the Godot processes under
# timeout included, and a held worktree lock released. The tree is the
# process table's own (ps -ef's parent links, which under MSYS reach the
# native Godot under timeout where Windows' own parentage, taskkill /T,
# doesn't); each process in it is ended by its Windows PID, which also
# reaches a native process MSYS signals don't.
#
# The run never blocks in bash's wait, which under MSYS a signal doesn't
# interrupt: it waits in one-second sleeps (tick(), await_pid()), so a
# stop lands within a second.
LOCK_HELD=""
PARENT=$PPID
# `pid` and everything under it, by the process table's parent links -
# gathered first, so nothing is lost to reparenting while they're ended.
tree_of() {
	local kid
	echo "$1"
	for kid in $(ps -ef | awk -v p="$1" 'NR > 1 && $3 == p { print $2 }'); do
		tree_of "$kid"
	done
}
kill_tree() {
	local pid
	for pid in $(tree_of "$1"); do
		if [ -r "/proc/$pid/winpid" ] && command -v taskkill > /dev/null; then
			taskkill //F //PID "$(cat "/proc/$pid/winpid")" > /dev/null 2>&1
		fi
		kill -9 "$pid" 2>/dev/null
	done
}
cleanup() {
	local code=$? pid mark
	trap - EXIT INT TERM HUP
	for pid in $(jobs -p); do kill_tree "$pid"; done
	# A probe launched at the instant of the stop can slip the first
	# sweep - its subshell ended under it, it reparented. A moment, then
	# a second: the jobs again, and anything still carrying one of this
	# run's run-log folders (<logs>/runlog.<probe>.*) in its command line.
	if [ -n "${LOGS:-}" ]; then
		sleep 1
		for pid in $(jobs -p); do kill_tree "$pid"; done
		mark="$(basename "$LOGS")/runlog."
		for pid in $(ps -ef | grep -F -- "$mark" | grep -v grep | awk '{ print $2 }'); do
			[ "$pid" != "$$" ] && kill_tree "$pid"
		done
	fi
	[ -n "$LOCK_HELD" ] && rm -rf "$LOCK_HELD"
	exit "$code"
}
stopped() {
	echo "run_probes: stopped ($1) - ending its probes" >&2
	exit "$2"
}
trap cleanup EXIT
trap 'stopped INT 130' INT
trap 'stopped TERM 143' TERM
trap 'stopped HUP 129' HUP
# One second of waiting - and the parent shell checked: gone, the run
# stops. Only with a real parent (one started straight from a native
# process sees PPID 1).
tick() {
	if [ "$PARENT" -gt 1 ] && ! kill -0 "$PARENT" 2>/dev/null; then
		stopped "its shell is gone" 143
	fi
	sleep 1
}
# Until `pid` (a child) ends, then its status.
await_pid() {
	while kill -0 "$1" 2>/dev/null; do tick; done
	wait "$1" 2>/dev/null
}

# --- The probes' flags, and their times ---
# "serial": runs alone after the parallel batch - set for a probe that
# proved flaky in parallel. "fixed": run at --fixed-fps 60 (the probe's
# own header asks for it). A probe not listed has neither.
PROBE_FLAGS="
drain_probe fixed
hold_line_probe fixed
floor4_probe fixed
floor5_probe fixed
"
# Measured seconds per probe: what orders a run, longest first, and tiers
# it. TIMES_FILE (tools/probe_times.txt) is the committed copy - --batch
# splits by it as it stands at HEAD, so the N batches of a run split
# alike. Runs write what they measure to LOCAL_TIMES_FILE (tools/
# probe_times.local.txt, git-ignored; record_times()), never to the
# tracked one, and read it when it's there. --refresh-times copies the
# local averages over TIMES_FILE, to commit when chosen.
TIMES_FILE="$REPO/tools/probe_times.txt"
LOCAL_TIMES_FILE="$REPO/tools/probe_times.local.txt"
if [ -f "$LOCAL_TIMES_FILE" ]; then TIMES_READ="$LOCAL_TIMES_FILE"; else TIMES_READ="$TIMES_FILE"; fi
refresh_times() {
	if [ ! -f "$LOCAL_TIMES_FILE" ]; then
		echo "run_probes: no local times yet ($LOCAL_TIMES_FILE) - nothing to refresh"
		return 0
	fi
	cp "$LOCAL_TIMES_FILE" "$TIMES_FILE"
	echo "run_probes: tools/probe_times.txt now holds the local averages - commit it when you choose"
}
# A probe's tier (TIMES_FILE's third column): slow when it measured over
# SLOW_SEC or loads the field or the battle scene (SLOW_SCENES - most of
# a probe's start-up), fast otherwise. Stored once it's timed, so a time
# drifting across the line doesn't move it; a probe with none yet is
# derived now - from its time, or slow while it has none.
SLOW_SEC=30
SLOW_SCENES='res://field/region_field\.tscn|res://battle/battle_overlay\.tscn'
derive_tier() {
	if [ "$2" -gt "$SLOW_SEC" ] || grep -qE "\"($SLOW_SCENES)\"" "$REPO/tests/$1.gd" 2>/dev/null; then
		echo slow
	else
		echo fast
	fi
}
probe_tier() {
	local stored
	stored=$(awk -v n="$1" '$1 == n && NF >= 3 { print $3; f = 1 } END { if (!f) print "" }' "$TIMES_READ" 2>/dev/null)
	if [ -n "$stored" ]; then
		echo "$stored"
	elif awk -v n="$1" '$1 == n { f = 1 } END { exit !f }' "$TIMES_READ" 2>/dev/null; then
		derive_tier "$1" "$(awk -v n="$1" '$1 == n { print $2 }' "$TIMES_READ")"
	else
		echo slow
	fi
}

# --- Areas: which probes guard which part of the game ---
area_probes() {
	case "$1" in
		cards) echo "starter_cards card_rarity frayed_cord" ;;
		face) echo "starter_cards keyword come_due come_due_face critical_cards card_rarity_finish second_swing" ;;
		keywords) echo "keyword starter_cards the_return" ;;
		rules) echo "starter_cards critical_cards come_due come_due_face collateral leverage no_further ransom sentence the_return trinket keeper_keepsake toll_carry kill_order armored_contact bide deny dying_light run_log frayed_cord blood_advance dunecur blackback greyshelf underfoot play_order grace second_swing garnish claw_back gnaw settled_account devour adder killing_blow" ;;
		enemies) echo "blackback siltjaw wardling dunecur greyshelf underfoot sentence no_further critical_cards kill_order armored_contact deny enemy_export adder glassbone" ;;
		field) echo "kill_order drain hold_line toll_carry gold_line glassbone armored_contact run_log wear_path elite_reward run_lost pathing scatter killing_blow" ;;
		floor1) echo "kill_order drain scatter" ;;
		floor2) echo "kill_order hold_line bundle_roll underfoot scatter" ;;
		floor3) echo "kill_order blackback wardling temper" ;;
		floor4) echo "kill_order floor4 wear_path dunecur collector adder" ;;
		floor5) echo "kill_order floor5 wear_path greyshelf elite_reward" ;;
		floors) echo "kill_order drain hold_line bundle_roll blackback wardling wear_path floor4 dunecur adder floor5 greyshelf underfoot pathing scatter encounter_slots" ;;
		run) echo "belongings_choice bundle_roll card_rarity glassbone trinket keeper_keepsake keepsake_tile toll_carry run_log frayed_cord elite_reward run_lost temper reward_roles" ;;
		hud) echo "gold_line glassbone trinket keepsake_tile" ;;
		hp_bar) echo "kill_order adder" ;;
		ui_inspect) echo "keyword" ;;
		# The fight's own UI: every probe that plays a real fight (which
		# builds the battle overlay and its hand), plus the rules probes
		# whose readouts and faces it shows.
		battle_ui) echo "keyword no_further critical_cards come_due_face kill_order blackback dunecur collateral glassbone keeper_keepsake leverage ransom toll_carry trinket armored_contact bide deny dying_light run_log frayed_cord blood_advance greyshelf underfoot play_order second_swing heavy_hit garnish claw_back gnaw settled_account devour adder killing_blow" ;;
		*) return 1 ;;
	esac
}
AREAS_ALL="cards face keywords rules enemies field floor1 floor2 floor3 floor4 floor5 floors run hud hp_bar ui_inspect battle_ui"

# The probes for one changed path; FULL for a path no area covers, nothing
# for a path no probe can see (docs, tools, the bus layout).
path_probes_hand() {
	local path="${1%.uid}"
	path="${path%.import}"
	local out=""
	case "$path" in
		# The enemy export, its generator and what it reads.
		docs/enemy_export.json|tests/enemy_export.gd) echo enemy_export; return 0 ;;
		default_bus_layout.tres|docs/*|*.md|reference/*|tools/*|.githooks/*|.gitignore|.gitattributes) return 0 ;;
		tests/*_probe.gd) basename "$path" .gd; return 0 ;;
		tests/*) return 0 ;;
		cards/data/*.tres|cards/neutral/*.tres)
			# The starters' probes, and every probe that names this card.
			local id
			id=$(basename "$path" .tres)
			out="$(area_probes cards) $(grep -lw "$id" "$REPO"/tests/*_probe.gd 2>/dev/null | xargs -r -n1 basename | sed 's/\.gd$//')" ;;
		cards/reward_pool.gd) out="$(area_probes cards) elite_reward" ;;
		# The collector's stock pool, and its screen.
		cards/pools/collector_pool.tres) out="$(area_probes cards) collector" ;;
		battle/collector_screen.*) out=collector ;;
		# Tempering: the wagon's screen, the tempered versions, the field
		# that names them.
		battle/wagon_screen.*) out=temper ;;
		cards/tempered/*) out="$(area_probes cards) temper" ;;
		cards/card_data.gd) out="$(area_probes cards) temper" ;;
		cards/card_effect.gd|cards/deck.gd) out=$(area_probes rules) ;;
		cards/*) out=$(area_probes cards) ;;
		battle/card_view.*|battle/card_paper*|battle/card_art*) out=$(area_probes face) ;;
		# The name's rarity finish: the face, and the two offers that name
		# the tiers from the same resource.
		battle/card_rarity_finish.*|battle/card_name_finish.*) out="$(area_probes face) collector elite_reward" ;;
		ui/keyword_table.gd|ui/keywords.tres|ui/status_reveal.gd) out=$(area_probes keywords) ;;
		battle/rules/enemies/*|battle/rules/enemy_turn.gd|battle/rules/enemy_intent.gd) out=$(area_probes enemies) ;;
		battle/rules/statuses/*|battle/rules/enemy_data.gd|battle/rules/status.gd|battle/rules/status_data.gd) out="$(area_probes rules) enemy_export" ;;
		# The Adder's own table: the probe that wins its fight.
		run/keepsakes/adder_keepsakes.tres) out="$(area_probes run) enemy_export adder" ;;
		run/keepsakes/*) out="$(area_probes run) enemy_export" ;;
		battle/rules/*|battle/battle_controller.gd) out=$(area_probes rules) ;;
		# The run's end screens (run_end.gd, its won and lost scenes): the run
		# probes - run_lost_probe among them, losing both ways - and
		# floor5_probe, which wins floor 5 and takes its exit into it.
		run/run_end.*|run/run_over.*) out="$(area_probes run) floor5" ;;
		battle/reward_screen.*|battle/belongings_screen.*|battle/loot_screen.*|battle/keepsake_offer.*|battle/keepsake_row.*|battle/trough_choice.*|run/*) out=$(area_probes run) ;;
		# Keepsake art: the probes that load keepsakes and their art.
		assets/textures/keepsakes/*) out="keeper_keepsake trinket belongings_choice" ;;
		# Enemy bodies: the probes that fight them.
		assets/models/enemies/*) out=$(area_probes enemies) ;;
		# The Wanderer's body, clips and sword: the field probes, and his rig's.
		field/wanderer.*|assets/models/wanderer/*) out="$(area_probes field) wanderer_rig" ;;
		# The Dunecur's crest and feeding head.
		field/dunecur_pose.*) out="$(area_probes field) dunecur" ;;
		field/collector.*) out="$(area_probes field) collector" ;;
		field/wagon.*) out="$(area_probes field) temper" ;;
		# The walk-up and click the collector, the trough and the wagon share.
		field/prop_approach.*) out="$(area_probes field) collector temper" ;;
		# The Greyshelf's head, rear and throat.
		field/greyshelf_*) out="$(area_probes field) greyshelf" ;;
		# The Underfoot's cover, barb and tilt.
		field/underfoot_*) out="$(area_probes field) underfoot" ;;
		# The enemies' share of the depth fog.
		field/enemy_fog.*) out="$(area_probes field) enemy_fog" ;;
		# The Keeper's plaque: her probe and the tile's.
		field/world_keepsake.*) out="$(area_probes field) keeper_keepsake keepsake_tile" ;;
		field/*) out=$(area_probes field) ;;
		# The ground scatter's sets: the floors that lay them.
		floors/scatter/*) out="$(area_probes floor1) $(area_probes floor2) scatter" ;;
		floors/region1_floor1.tres) out="$(area_probes floor1) enemy_export" ;;
		floors/region1_floor2.tres) out="$(area_probes floor2) enemy_export" ;;
		floors/region1_floor3.tres) out="$(area_probes floor3) enemy_export" ;;
		floors/region1_floor4.tres) out="$(area_probes floor4) enemy_export" ;;
		floors/region1_floor5.tres) out="$(area_probes floor5) enemy_export" ;;
		floors/*.tres) out="$(area_probes floors) enemy_export" ;;
		floors/*) out=$(area_probes floors) ;;
		# Prop and environment models stand on the floors that place them.
		assets/models/props/*|assets/Environment/*) out=$(area_probes floors) ;;
		# Floor 3's generated ground and the generator's sources.
		assets/field/masks/region1_floor3_*|assets/field/masks/source/floor3/*) out=$(area_probes floor3) ;;
		assets/field/masks/region1_floor4_*|assets/field/masks/source/floor4/*) out=$(area_probes floor4) ;;
		assets/field/masks/region1_floor5_*|assets/field/masks/source/floor5/*) out=$(area_probes floor5) ;;
		ui/hp_bar.*) out=$(area_probes hp_bar) ;;
		# The world-voice line: the hold line (hold_line), the collector's
		# and the wagon's approach lines (collector, temper), and the
		# Wardling's defeat line over a won fight (elite_reward, glassbone).
		ui/world_voice_line.gd) out="hold_line collector temper elite_reward glassbone" ;;
		# The keepsake's tile and examine view: every probe that shows one.
		ui/keepsake_tile.*|ui/keepsake_examine.*) out="keepsake_tile trinket keeper_keepsake belongings_choice" ;;
		ui/gold_line.gd|ui/glassbone_line.gd|ui/keepsake_line.gd|ui/ink_line.gd|ui/hp_line.gd|ui/ink_glyph.gd|ui/hud_row_style.gd) out=$(area_probes hud) ;;
		# The field's DECK and the battle's DECK/DISCARD lines are all
		# DeckPanels.
		ui/deck_panel.gd) out="$(area_probes hud) $(area_probes battle_ui)" ;;
		ui/deck_view.*) out="$(area_probes ui_inspect) collector" ;;
		ui/card_compendium.*) out=$(area_probes ui_inspect) ;;
		# A play effect: the fight's UI probes, and starter_cards, which
		# checks Blood Arc's stroke.
		battle/effects/*) out="$(area_probes battle_ui) starter_cards" ;;
		battle/battle_overlay.*|battle/battle_feedback.*|battle/battle_intent.*|battle/battle_resources.*|battle/end_turn_button.*|battle/enemy_status.*|battle/floating_number.*|battle/hand_container.*|battle/take_feedback.*|battle/target_line.*|battle/devour_button.*|ui/ink_pen.gd) out=$(area_probes battle_ui) ;;
		*) echo FULL; return 0 ;;
	esac
	# The kill-order gate: any script under battle/ or field/.
	case "$path" in
		battle/*.gd|field/*.gd) out="$out kill_order" ;;
	esac
	echo "$out"
}

# --- What each probe loads ---
# Each probe's source scanned for the res:// files and folders it names
# (a format string - one with a % - is skipped): SCAN_INDEX, a line per
# path and probe, a folder's path ending in /. A changed path maps to
# every probe that loads it, or a folder holding it, as well as to its
# hand-written areas (path_probes_hand()) - so a probe reading enemy data
# runs on a change to it whether or not an area says so. Built once, in
# the main shell (scan_index()), before anything maps a path.
SCAN_INDEX=""
scan_index() {
	[ -n "$SCAN_INDEX" ] && return 0
	local f p r
	SCAN_INDEX=$(for f in "$REPO"/tests/*_probe.gd; do
		p=$(basename "$f" .gd)
		grep -o '"res://[^"%]*"' "$f" | tr -d '"' | sed 's|^res://||; s|/$||' | sort -u | while IFS= read -r r; do
			case "$r" in tests/*|"") continue ;; esac
			if [ -d "$REPO/$r" ]; then
				printf '%s/\t%s\n' "$r" "$p"
			elif [ -e "$REPO/$r" ]; then
				printf '%s\t%s\n' "$r" "$p"
			fi
		done
	done)
}
# The probes that load `path` (scan_index()), one per line.
scanned_probes() {
	local path="${1%.uid}"
	path="${path%.import}"
	echo "$SCAN_INDEX" | awk -F'\t' -v p="$path" '$1 == p || ($1 ~ /\/$/ && index(p, $1) == 1) { print $2 }'
}
# The probes for one changed path: its areas', and every probe that loads
# it. FULL stays FULL - no area covers it, so everything runs.
path_probes() {
	local hand
	hand=$(path_probes_hand "$1")
	if [ "$hand" = FULL ]; then
		echo FULL
		return 0
	fi
	echo "$hand" $(scanned_probes "$1")
}
# --mapping-gaps: each probe and the paths it loads that its areas don't
# map to it - a file it names, or each tracked file under a folder it
# names. A path no area covers (FULL) runs every probe, so isn't a gap.
mapping_gaps() {
	local path probe file files hand missed example found=0 last=""
	while IFS=$'\t' read -r path probe; do
		[ -n "$path" ] || continue
		if [ "${path%/}" != "$path" ]; then
			files=$(git -C "$REPO" ls-files -- "$path" | grep -v '\.uid$\|\.import$')
		else
			files="$path"
		fi
		missed=0
		example=""
		while IFS= read -r file; do
			[ -n "$file" ] || continue
			hand=" $(echo $(path_probes_hand "$file")) "
			[ "$hand" = " FULL " ] && continue
			case "$hand" in *" ${probe%_probe} "*|*" $probe "*) continue ;; esac
			missed=$((missed + 1))
			[ -n "$example" ] || example="$file"
		done <<< "$files"
		[ "$missed" -gt 0 ] || continue
		[ "$probe" = "$last" ] || echo "$probe:"
		last="$probe"
		if [ "${path%/}" != "$path" ]; then
			echo "    $path ($missed file(s) not mapped to it, e.g. $example)"
		else
			echo "    $path"
		fi
		found=1
	done <<< "$(echo "$SCAN_INDEX" | sort -t$'\t' -k2,2 -k1,1)"
	[ "$found" = 1 ] || echo "(none)"
}

die() { echo "run_probes: $*" >&2; exit 2; }

MODE=""
AREAS=""
NAMES=""
BASE=""
JOBS=""
WORKTREE=""
REF=""
FILES=""
WAIT_MIN=30
PROJECT=""
DO_IMPORT=0
LOGS=""
LIST=0
MOVED=""
BATCH=""

while [ $# -gt 0 ]; do
	case "$1" in
		--full) MODE=full ;;
		--fast) MODE=fast ;;
		--prepush) MODE=prepush ;;
		--area) MODE=area; AREAS="${2:?--area needs a list}"; shift ;;
		--changed) MODE=changed
			if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then BASE="$2"; shift; fi ;;
		--probe) MODE=probe; NAMES="$NAMES,${2:?--probe needs a list}"; shift ;;
		-j) JOBS="${2:?-j needs a number}"; shift ;;
		--worktree)
			WORKTREE="$REPO/../journey-of-milo-probe"
			if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then WORKTREE="$2"; shift; fi ;;
		--ref) REF="${2:?--ref needs a commit}"; shift ;;
		--files) FILES="${2:?--files needs a list}"; shift ;;
		--wait) WAIT_MIN="${2:?--wait needs minutes}"; shift ;;
		--path) PROJECT="${2:?--path needs a folder}"; shift ;;
		--import) DO_IMPORT=1 ;;
		--logs) LOGS="${2:?--logs needs a folder}"; shift ;;
		--list) LIST=1 ;;
		--moved) MOVED="${2:?--moved needs a commit or range}"; shift ;;
		--batch) BATCH="${2:?--batch needs K/N}"; shift ;;
		--list-areas) for a in $AREAS_ALL; do printf '%-11s %s\n' "$a" "$(area_probes "$a")"; done; exit 0 ;;
		--mapping-gaps) scan_index; mapping_gaps; exit 0 ;;
		--refresh-times) refresh_times; exit 0 ;;
		-h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
		*) die "unknown option $1 (--help)" ;;
	esac
	shift
done
[ -n "$MODE" ] || die "say what to run: --full, --fast, --prepush, --area, --changed or --probe (--help)"
# No -j: 1 on a machine short of memory, 2 with room for two.
if [ -z "$JOBS" ]; then
	FREE_AT_START=$(free_mb)
	if [ -n "$FREE_AT_START" ] && [ "$FREE_AT_START" -lt "$JOBS_TWO_MIN_FREE_MB" ]; then JOBS=1; else JOBS=2; fi
fi
[ -n "$WORKTREE" ] && [ -n "$PROJECT" ] && die "--worktree and --path are exclusive"
[ -n "$MOVED" ] && [ "$LIST" = 0 ] && die "--moved is a dry run of the HEAD-moved check: use it with --list"
if [ -n "$BATCH" ]; then
	case "$BATCH" in
		[1-9]*/[1-9]*) ;;
		*) die "--batch takes K/N, 1 <= K <= N" ;;
	esac
	[ "${BATCH%/*}" -le "${BATCH#*/}" ] 2>/dev/null || die "--batch takes K/N, 1 <= K <= N"
fi

# --- What changed (for --changed, and for the HEAD-moved check) ---
# Every path list below is one path per line - never split on spaces, so
# a path with one ("cards/art/Wanderer/Hold Fast.png") stays whole: read
# with `while IFS= read -r`, never `for f in $LIST`. git is asked not to
# quote unusual paths (core.quotePath), so they come out as on disk.
gitq() { git -c core.quotePath=false "$@"; }
START_HEAD=$(git -C "$REPO" rev-parse HEAD)
CHANGED=""
if [ "$MODE" = changed ]; then
	CHANGED=$( { gitq -C "$REPO" diff --name-only "${BASE:-HEAD}"; gitq -C "$REPO" ls-files --others --exclude-standard; } | sort -u)
elif [ "$MODE" = prepush ]; then
	# What a push would carry: the commits on HEAD not yet on origin/main.
	git -C "$REPO" rev-parse -q --verify origin/main > /dev/null || die "--prepush: no origin/main to compare with (git fetch?)"
	CHANGED=$(gitq -C "$REPO" diff --name-only origin/main...HEAD | sort -u)
fi
if [ -n "$FILES" ]; then
	CHANGED=$(printf '%s\n%s\n' "$CHANGED" "$(echo "$FILES" | tr ',' '\n')" | sed '/^$/d' | sort -u)
fi

# --- Which probes ---
ALL_PROBES=$(cd "$REPO/tests" && ls *_probe.gd | sed 's/\.gd$//')

# Probe names as *_probe, one per line, sorted, no duplicates.
normalise_probes() { for p in "$@"; do p="${p%.gd}"; p="${p%_probe}_probe"; echo "$p"; done | sort -u; }

# The probes a list of paths (one per line) maps to, by path_probes() -
# what --changed runs and what the HEAD-moved check asks about. Sets
# MAPPED (normalised) and MAPPED_FULL: the first path no area covers,
# which maps to the full suite, or empty.
map_paths() {
	scan_index
	MAPPED=""
	MAPPED_FULL=""
	local f p all=""
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		p=$(path_probes "$f")
		if [ "$p" = FULL ]; then
			MAPPED_FULL="$f"
			MAPPED=$(normalise_probes $ALL_PROBES)
			return
		fi
		all="$all $p"
	done <<< "$1"
	MAPPED=$(normalise_probes $all)
}

SELECTED=""
case "$MODE" in
	full) SELECTED="$ALL_PROBES" ;;
	area)
		for a in $(echo "$AREAS" | tr ',' ' '); do
			p=$(area_probes "$a") || die "no area '$a' (--list-areas)"
			SELECTED="$SELECTED $p"
		done ;;
	probe) SELECTED=$(echo "$NAMES" | tr ',' ' ') ;;
	fast)
		for p in $ALL_PROBES; do
			[ "$(probe_tier "$p")" = fast ] && SELECTED="$SELECTED $p"
		done ;;
	prepush)
		map_paths "$CHANGED"
		FAST=""
		for p in $ALL_PROBES; do
			[ "$(probe_tier "$p")" = fast ] && FAST="$FAST $p"
		done
		echo "run_probes: prepush - changed in origin/main..HEAD:"
		if [ -n "$CHANGED" ]; then echo "$CHANGED" | sed 's/^/    /'; else echo "    (nothing)"; fi
		[ -n "$MAPPED_FULL" ] && echo "run_probes: $MAPPED_FULL is in no area - the full suite"
		echo "run_probes: mapped to them:" $MAPPED
		echo "run_probes: and the fast tier:" $FAST
		SELECTED="$MAPPED $FAST" ;;
	changed)
		[ -n "$CHANGED" ] || { echo "run_probes: nothing changed since ${BASE:-HEAD} - no probes to run"; exit 0; }
		map_paths "$CHANGED"
		[ -n "$MAPPED_FULL" ] && echo "run_probes: $MAPPED_FULL is in no area - running the full suite"
		SELECTED="$MAPPED" ;;
esac
# Normalise to *_probe names, drop duplicates, check each exists.
SELECTED=$(normalise_probes $SELECTED)
for p in $SELECTED; do
	echo "$ALL_PROBES" | grep -qx "$p" || die "no probe tests/$p.gd"
done
[ -n "$SELECTED" ] || { echo "run_probes: no probe covers the changed files - nothing to run"; exit 0; }

# Commits TESTED..END landed while this run tested TESTED. Their files are
# mapped the way --changed maps them (map_paths()); if any maps to a probe
# in this run, that probe's result is for an older tree - rerun it on the
# new HEAD. A file no probe can see (docs, *.md) never asks for one; a
# file in no area maps to every probe, so it always does.
report_head_moved() {
	local tested="$1" end="$2" new_files hit
	new_files=$(gitq -C "$REPO" diff --name-only "$tested" "$end")
	echo "run_probes: HEAD moved: $(git -C "$REPO" rev-parse --short "$tested") -> $(git -C "$REPO" rev-parse --short "$end"); the new commits touch:"
	echo "$new_files" | sed 's/^/    /'
	map_paths "$new_files"
	hit=$(comm -12 <(echo "$SELECTED" | sed '/^$/d') <(echo "$MAPPED" | sed '/^$/d'))
	if [ -z "$hit" ]; then
		echo "run_probes: none of them map to a probe in this run - no rerun needed"
	else
		[ -n "$MAPPED_FULL" ] && echo "run_probes: $MAPPED_FULL is in no area, so it maps to every probe"
		echo "run_probes: rerun needed on the new HEAD - they map to these probes in this run:"
		echo "$hit" | sed 's/^/    /'
	fi
}

table_seconds() { awk -v n="$1" '$1 == n { print $2; f = 1 } END { if (!f) print 60 }' "$TIMES_READ" 2>/dev/null || echo 60; }
table_flag() { echo "$PROBE_FLAGS" | awk -v n="$1" -v f="$2" '$1 == n { for (i = 2; i <= NF; i++) if ($i == f) print "yes" }'; }

# --batch K/N: the selection split into N groups of near-equal measured
# time - each probe, longest first, to the group with the least so far -
# and only group K run. The split reads the times as committed at HEAD,
# not the working copy each run writes back to, so batch 2 splits the
# same way batch 1 did and every probe runs in exactly one of the N.
if [ -n "$BATCH" ]; then
	BATCH_K=${BATCH%/*}
	BATCH_N=${BATCH#*/}
	BATCH_TIMES=$(git -C "$REPO" show HEAD:tools/probe_times.txt 2>/dev/null || cat "$TIMES_FILE" 2>/dev/null)
	SELECTED=$(for p in $SELECTED; do echo "$(echo "$BATCH_TIMES" | awk -v n="$p" '$1 == n { print $2; f = 1 } END { if (!f) print 60 }') $p"; done \
		| sort -k1,1rn -k2,2 \
		| awk -v k="$BATCH_K" -v n="$BATCH_N" '{ b = 1; for (i = 2; i <= n; i++) if (t[i] < t[b]) b = i; t[b] += $1; if (b == k) print $2 }')
	echo "run_probes: batch $BATCH_K/$BATCH_N:" $SELECTED
	[ -n "$SELECTED" ] || { echo "run_probes: batch $BATCH is empty - nothing to run"; exit 0; }
fi

# Longest first; serial ones apart.
PARALLEL=""
SERIAL=""
for p in $(for p in $SELECTED; do echo "$(table_seconds "$p") $p"; done | sort -rn | awk '{ print $2 }'); do
	if [ "$(table_flag "$p" serial)" = yes ]; then SERIAL="$SERIAL $p"; else PARALLEL="$PARALLEL $p"; fi
done

# --- Where ---
if [ -n "$WORKTREE" ]; then
	PROJECT="$WORKTREE"
	REF="${REF:-$START_HEAD}"
	# With --changed and no --files, the change under test is what changed.
	[ -z "$FILES" ] && [ "$MODE" = changed ] && FILES=$(echo "$CHANGED" | grep -vx 'default_bus_layout.tres' | tr '\n' ',')
fi
PROJECT="${PROJECT:-$REPO}"

if [ "$LIST" = 1 ]; then
	echo "project:  $PROJECT"
	[ -n "$WORKTREE" ] && echo "worktree: check out $(git -C "$REPO" rev-parse --short "$REF"), copy over: ${FILES:-nothing}"
	[ -n "$CHANGED" ] && echo "changed:  $(while IFS= read -r f; do printf "'%s' " "$f"; done <<< "$CHANGED")"
	echo "parallel (-j $JOBS):$PARALLEL"
	[ -n "$SERIAL" ] && echo "serial:  $SERIAL"
	if [ -n "$MOVED" ]; then
		from="${MOVED%%..*}"
		to=HEAD
		[ "$from" != "$MOVED" ] && to="${MOVED#*..}"
		git -C "$REPO" rev-parse -q --verify "$from^{commit}" > /dev/null || die "--moved: no commit '$from'"
		git -C "$REPO" rev-parse -q --verify "${to:-HEAD}^{commit}" > /dev/null || die "--moved: no commit '$to'"
		echo "if $from..${to:-HEAD} landed during this run:"
		report_head_moved "$from" "${to:-HEAD}"
	fi
	exit 0
fi

[ -x "$GODOT" ] || [ -f "$GODOT" ] || die "no Godot at $GODOT (set GODOT)"

# --- The persistent worktree: lock, check out, copy, import if needed ---
if [ -n "$WORKTREE" ]; then
	LOCK="$WORKTREE.lock"
	waited=0
	while ! mkdir "$LOCK" 2>/dev/null; do
		holder=$(cat "$LOCK/owner" 2>/dev/null)
		pid=$(echo "$holder" | awk '{ print $1 }')
		if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
			echo "run_probes: clearing a stale lock ($holder)"
			rm -rf "$LOCK"
			continue
		fi
		if [ "$waited" -ge $((WAIT_MIN * 60)) ]; then
			echo "run_probes: $WORKTREE is busy ($holder) - gave up after $WAIT_MIN min" >&2
			exit 3
		fi
		[ "$waited" = 0 ] && echo "run_probes: $WORKTREE is busy ($holder) - waiting up to $WAIT_MIN min"
		sleep 10
		waited=$((waited + 10))
	done
	echo "$$ $(date '+%Y-%m-%d %H:%M:%S') $(basename "$REPO") ref $(git -C "$REPO" rev-parse --short "$REF")" > "$LOCK/owner"
	LOCK_HELD="$LOCK"

	NEED_IMPORT=0
	STALE_IMPORTS=""
	if [ ! -d "$WORKTREE/.git" ] && [ ! -f "$WORKTREE/.git" ]; then
		echo "run_probes: making $WORKTREE (one-time: a worktree and a copy of .godot)"
		git -C "$REPO" worktree add --detach "$WORKTREE" "$REF" >/dev/null || die "could not add the worktree"
		cp -r "$REPO/.godot" "$WORKTREE/" || die "could not copy .godot"
		NEED_IMPORT=1
		OLD=$(git -C "$REPO" rev-parse "$REF")
	else
		OLD=$(git -C "$WORKTREE" rev-parse HEAD)
	fi
	# Back to a clean checkout of REF: last run's copied files go - and
	# count as changed, since their imported copies are last run's.
	LEFTOVER=$(gitq -C "$WORKTREE" status --porcelain -z --untracked-files=all 2>/dev/null | tr '\0' '\n' | cut -c4-)
	git -C "$WORKTREE" checkout -q -f --detach "$REF" || die "could not check out $REF"
	git -C "$WORKTREE" clean -fdq
	MOVED=$(gitq -C "$WORKTREE" diff --name-only "$OLD" HEAD)
	MOVED=$(printf '%s\n%s' "$MOVED" "$LEFTOVER")
	ADDED=$(gitq -C "$WORKTREE" diff --name-only --diff-filter=A "$OLD" HEAD)
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		if [ -e "$REPO/$f" ]; then
			mkdir -p "$WORKTREE/$(dirname "$f")"
			cp "$REPO/$f" "$WORKTREE/$f"
			git -C "$WORKTREE" cat-file -e "HEAD:$f" 2>/dev/null || ADDED=$(printf '%s\n%s' "$ADDED" "$f")
		else
			rm -f "$WORKTREE/$f"
		fi
		MOVED=$(printf '%s\n%s' "$MOVED" "$f")
	done <<< "$(echo "$FILES" | tr ',' '\n')"
	# Import when an import setting, an imported asset's contents or a new
	# file came in. A changed .import's cached output is deleted first, or
	# the stale one stays; a changed asset under an unchanged .import is
	# re-imported by Godot itself (its source md5 no longer matches).
	while IFS= read -r f; do
		case "$f" in
			*.import)
				NEED_IMPORT=1
				STALE_IMPORTS=$(printf '%s\n%s' "$STALE_IMPORTS" "$(basename "${f%.import}")") ;;
			*.png|*.jpg|*.jpeg|*.webp|*.svg|*.exr|*.hdr|*.glb|*.gltf|*.fbx|*.blend|*.obj|*.wav|*.mp3|*.ogg|*.ttf|*.otf|*.csv) NEED_IMPORT=1 ;;
		esac
	done <<< "$MOVED"
	# A new file only matters if Godot scans it: a resource, a script (the
	# class cache) or an asset - not docs, and not tools/ (.gdignore).
	while IFS= read -r f; do
		case "$f" in
			tools/*|docs/*|reference/*|*.md) ;;
			*.gd|*.gdshader|*.gdshaderinc|*.tscn|*.tres|*.res|*.png|*.jpg|*.svg|*.glb|*.gltf|*.fbx|*.wav|*.ogg|*.mp3|*.ttf|*.otf) NEED_IMPORT=1 ;;
		esac
	done <<< "$ADDED"
	while IFS= read -r a; do
		[ -n "$a" ] && rm -f "$WORKTREE/.godot/imported/$a"-*
	done <<< "$STALE_IMPORTS"
	[ "$NEED_IMPORT" = 1 ] && DO_IMPORT=1
	echo "run_probes: worktree at $(git -C "$WORKTREE" rev-parse --short HEAD)${FILES:+, with $(echo "$FILES" | tr ',' '\n' | while IFS= read -r f; do [ -n "$f" ] && printf "'%s' " "$f"; done)}"
fi

LOGS="${LOGS:-$(mktemp -d "${TMPDIR:-/tmp}/run_probes.XXXXXX")}"
mkdir -p "$LOGS"
: > "$LOGS/_results.txt"

if [ "$DO_IMPORT" = 1 ]; then
	await_memory
	echo "run_probes: importing..."
	# In the background and waited on, so a stop reaches the trap at once.
	( cd "$PROJECT" && timeout 900 "$GODOT" --headless --path . --import > "$LOGS/_import.log" 2>&1 ) &
	await_pid $!
fi

# --- Run ---
# Each probe process gets a run-log folder of its own (RunLogger's
# --runlog-dir user argument), deleted when it ends: user:// is shared by
# every checkout and session, so a probe that writes and reads run logs
# would otherwise see another copy's files.
run_one() {
	local p="$1" ff="" start code dur verdict runlog runlog_arg
	[ "$(table_flag "$p" fixed)" = yes ] && ff="--fixed-fps 60"
	runlog=$(mktemp -d "$LOGS/runlog.$p.XXXXXX")
	runlog_arg="$runlog"
	command -v cygpath > /dev/null && runlog_arg=$(cygpath -m "$runlog")
	start=$(date +%s)
	( cd "$PROJECT" && timeout "$PROBE_TIMEOUT_SEC" "$GODOT" --headless $ff --path . -s "res://tests/$p.gd" -- "--runlog-dir=$runlog_arg" > "$LOGS/$p.log" 2>&1 )
	code=$?
	rm -rf "$runlog"
	dur=$(( $(date +%s) - start ))
	if [ "$code" = 0 ] && grep -q "^$p: PASSED" "$LOGS/$p.log"; then verdict=PASS; else verdict=FAIL; fi
	printf '%-26s %s %4ss%s\n' "$p" "$verdict" "$dur" "$([ "$verdict" = FAIL ] && echo "  (exit $code, $LOGS/$p.log)")" | tee -a "$LOGS/_results.txt"
}

COUNT=$(echo $SELECTED | wc -w)
echo "run_probes: $COUNT probe(s) in $PROJECT, -j $JOBS, logs in $LOGS"
echo "run_probes: running:$PARALLEL$SERIAL"
T0=$(date +%s)
for p in $PARALLEL; do
	while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do tick; done
	await_memory
	run_one "$p" &
	LAST_START=$(date +%s)
done
while [ -n "$(jobs -rp)" ]; do tick; done
wait
for p in $SERIAL; do await_memory; run_one "$p" & await_pid $!; done
T1=$(date +%s)

FAILED=$(grep -c ' FAIL ' "$LOGS/_results.txt" 2>/dev/null)

# What this run measured, into LOCAL_TIMES_FILE (started from TIMES_FILE
# the first time), never the tracked TIMES_FILE: each probe that passed, its
# new time averaged with the one there (or as measured, if it's new). A
# failed probe's time stays - a failure can end early.
record_times() {
	local tmp="$LOCAL_TIMES_FILE.$$"
	[ -f "$LOCAL_TIMES_FILE" ] || cp "$TIMES_FILE" "$LOCAL_TIMES_FILE" 2>/dev/null || return 0
	awk 'FNR == NR { if ($2 == "PASS") { t = $3; sub(/s$/, "", t); m[$1] = t }; next }
		/^#/ || NF < 2 { print; next }
		($1 in m) { $2 = int(($2 + m[$1]) / 2 + 0.5); seen[$1] = 1 }
		{ print }
		END { for (p in m) if (!(p in seen)) print p, m[p] }' "$LOGS/_results.txt" "$LOCAL_TIMES_FILE" > "$tmp" \
		&& { grep '^#' "$tmp"; grep -v '^#' "$tmp" | sort; } > "$tmp.sorted" \
		&& awk 'NF == 2 && $1 !~ /^#/ { print $1, $2 }' "$tmp.sorted" > "$tmp.new" && mv "$tmp.sorted" "$LOCAL_TIMES_FILE"
	# A probe timed for the first time gets its tier.
	local p s
	while read -r p s; do
		[ -n "$p" ] && sed -i "s/^$p $s$/$p $s $(derive_tier "$p" "$s")/" "$LOCAL_TIMES_FILE"
	done < "$tmp.new" 2>/dev/null
	rm -f "$tmp" "$tmp.sorted" "$tmp.new"
}
record_times
echo "run_probes: $((COUNT - FAILED)) of $COUNT passed in $((T1 - T0))s"

# --- Did HEAD move under the run? ---
END_HEAD=$(git -C "$REPO" rev-parse HEAD)
TESTED_HEAD="${REF:+$(git -C "$REPO" rev-parse "$REF")}"
TESTED_HEAD="${TESTED_HEAD:-$START_HEAD}"
if [ "$END_HEAD" != "$TESTED_HEAD" ]; then
	report_head_moved "$TESTED_HEAD" "$END_HEAD"
fi

[ "$FAILED" = 0 ]
