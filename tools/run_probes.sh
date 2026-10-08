#!/usr/bin/env bash
# Runs the headless probes (tests/*_probe.gd) - all of them, an area's, or
# the ones a change touches - as parallel headless Godot processes, and
# says which passed. See CLAUDE.md's Probes section for when to run what.
#
#   tools/run_probes.sh --full                    every probe
#   tools/run_probes.sh --area keywords,face      an area's probes (--list-areas)
#   tools/run_probes.sh --changed [BASE]          the probes for the files changed
#                                                 since BASE (default HEAD)
#   tools/run_probes.sh --probe kill_order        named probes ("_probe" optional)
#
# Options:
#   -j N             parallel probes (default 4). Probes marked serial in
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
#   --moved A[..B]   with --list: also print what the HEAD-moved check
#                    would say had commits A..B (B default HEAD) landed
#                    during this run - a dry run of that check
#
# GODOT overrides the engine (default ../Godot_v4.7.1.exe beside the repo:
# the main executable, not the _console wrapper). Exit code 0 = every
# probe passed, 1 = a failure, 2 = usage, 3 = the worktree stayed busy.

set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GODOT=${GODOT:-$REPO/../Godot_v4.7.1.exe}
PROBE_TIMEOUT_SEC=600

# --- The probes: name, seconds on a serial run (2026-10-03), flags ---
# "serial": runs alone after the parallel batch - set for a probe that
# proved flaky in parallel. "fixed": run at --fixed-fps 60 (the probe's
# own header asks for it). The seconds only order the batch, longest first.
PROBE_TABLE="
keeper_keepsake_probe 75
collector_probe 30
elite_reward_probe 30
enemy_export_probe 8
belongings_choice_probe 51
kill_order_probe 42
blackback_probe 36
toll_carry_probe 35
trinket_probe 35
collateral_probe 29
blood_advance_probe 30
bide_probe 30
frayed_cord_probe 30
wear_path_probe 12
deny_probe 40
dying_light_probe 40
leverage_probe 29
glassbone_probe 27
run_log_probe 30
ransom_probe 26
gold_line_probe 19
armored_contact_probe 10
drain_probe 10 fixed
keyword_probe 9
come_due_face_probe 7
hold_line_probe 7 fixed
floor4_probe 40 fixed
floor5_probe 20 fixed
run_lost_probe 12
dunecur_probe 30
greyshelf_probe 45
card_rarity_probe 5
come_due_probe 4
starter_cards_probe 4
temper_probe 13
play_order_probe 28
grace_probe 3
pathing_probe 60
no_further_probe 3
sentence_probe 3
the_return_probe 3
bundle_roll_probe 2
critical_cards_probe 2
wardling_probe 2
siltjaw_probe 1
enemy_fog_probe 25
card_rarity_finish_probe 8
"

# --- Areas: which probes guard which part of the game ---
area_probes() {
	case "$1" in
		cards) echo "starter_cards card_rarity frayed_cord" ;;
		face) echo "starter_cards keyword come_due come_due_face critical_cards card_rarity_finish" ;;
		keywords) echo "keyword starter_cards the_return" ;;
		rules) echo "starter_cards critical_cards come_due come_due_face collateral leverage no_further ransom sentence the_return trinket keeper_keepsake toll_carry kill_order armored_contact bide deny dying_light run_log frayed_cord blood_advance dunecur blackback greyshelf play_order grace" ;;
		enemies) echo "blackback siltjaw wardling dunecur greyshelf sentence no_further critical_cards kill_order armored_contact deny enemy_export" ;;
		field) echo "kill_order drain hold_line toll_carry gold_line glassbone armored_contact run_log wear_path elite_reward run_lost pathing" ;;
		floor1) echo "kill_order drain" ;;
		floor2) echo "kill_order hold_line bundle_roll" ;;
		floor3) echo "kill_order blackback wardling temper" ;;
		floor4) echo "kill_order floor4 wear_path dunecur collector" ;;
		floor5) echo "kill_order floor5 wear_path greyshelf elite_reward" ;;
		floors) echo "kill_order drain hold_line bundle_roll blackback wardling wear_path floor4 dunecur floor5 greyshelf pathing" ;;
		run) echo "belongings_choice bundle_roll card_rarity glassbone trinket keeper_keepsake toll_carry run_log frayed_cord elite_reward run_lost temper" ;;
		hud) echo "gold_line glassbone trinket" ;;
		hp_bar) echo "kill_order" ;;
		ui_inspect) echo "keyword" ;;
		# The fight's own UI: every probe that plays a real fight (which
		# builds the battle overlay and its hand), plus the rules probes
		# whose readouts and faces it shows.
		battle_ui) echo "keyword no_further critical_cards come_due_face kill_order blackback dunecur collateral glassbone keeper_keepsake leverage ransom toll_carry trinket armored_contact bide deny dying_light run_log frayed_cord blood_advance greyshelf play_order" ;;
		*) return 1 ;;
	esac
}
AREAS_ALL="cards face keywords rules enemies field floor1 floor2 floor3 floor4 floor5 floors run hud hp_bar ui_inspect battle_ui"

# The probes for one changed path; FULL for a path no area covers, nothing
# for a path no probe can see (docs, tools, the bus layout).
path_probes() {
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
		# The Dunecur's crest and feeding head.
		field/dunecur_pose.*) out="$(area_probes field) dunecur" ;;
		field/collector.*) out="$(area_probes field) collector" ;;
		field/wagon.*) out="$(area_probes field) temper" ;;
		# The walk-up and click the collector, the trough and the wagon share.
		field/prop_approach.*) out="$(area_probes field) collector temper" ;;
		# The Greyshelf's head, rear and throat.
		field/greyshelf_*) out="$(area_probes field) greyshelf" ;;
		# The enemies' share of the depth fog.
		field/enemy_fog.*) out="$(area_probes field) enemy_fog" ;;
		field/*) out=$(area_probes field) ;;
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
		ui/gold_line.gd|ui/glassbone_line.gd|ui/keepsake_line.gd|ui/ink_line.gd|ui/hp_line.gd|ui/ink_glyph.gd|ui/hud_row_style.gd) out=$(area_probes hud) ;;
		# The field's DECK and the battle's DECK/DISCARD lines are all
		# DeckPanels.
		ui/deck_panel.gd) out="$(area_probes hud) $(area_probes battle_ui)" ;;
		ui/deck_view.*) out="$(area_probes ui_inspect) collector" ;;
		ui/card_compendium.*) out=$(area_probes ui_inspect) ;;
		# A play effect: the fight's UI probes, and starter_cards, which
		# checks Blood Arc's stroke.
		battle/effects/*) out="$(area_probes battle_ui) starter_cards" ;;
		battle/battle_overlay.*|battle/battle_feedback.*|battle/battle_intent.*|battle/battle_resources.*|battle/end_turn_button.*|battle/enemy_status.*|battle/floating_number.*|battle/hand_container.*|battle/take_feedback.*|battle/target_line.*) out=$(area_probes battle_ui) ;;
		*) echo FULL; return 0 ;;
	esac
	# The kill-order gate: any script under battle/ or field/.
	case "$path" in
		battle/*.gd|field/*.gd) out="$out kill_order" ;;
	esac
	echo "$out"
}

die() { echo "run_probes: $*" >&2; exit 2; }

MODE=""
AREAS=""
NAMES=""
BASE=""
JOBS=4
WORKTREE=""
REF=""
FILES=""
WAIT_MIN=30
PROJECT=""
DO_IMPORT=0
LOGS=""
LIST=0
MOVED=""

while [ $# -gt 0 ]; do
	case "$1" in
		--full) MODE=full ;;
		--area) MODE=area; AREAS="${2:?--area needs a list}"; shift ;;
		--changed) MODE=changed
			if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then BASE="$2"; shift; fi ;;
		--probe) MODE=probe; NAMES="${2:?--probe needs a list}"; shift ;;
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
		--list-areas) for a in $AREAS_ALL; do printf '%-11s %s\n' "$a" "$(area_probes "$a")"; done; exit 0 ;;
		-h|--help) sed -n '2,36p' "$0"; exit 0 ;;
		*) die "unknown option $1 (--help)" ;;
	esac
	shift
done
[ -n "$MODE" ] || die "say what to run: --full, --area, --changed or --probe (--help)"
[ -n "$WORKTREE" ] && [ -n "$PROJECT" ] && die "--worktree and --path are exclusive"
[ -n "$MOVED" ] && [ "$LIST" = 0 ] && die "--moved is a dry run of the HEAD-moved check: use it with --list"

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

table_seconds() { echo "$PROBE_TABLE" | awk -v n="$1" '$1 == n { print $2; f = 1 } END { if (!f) print 60 }'; }
table_flag() { echo "$PROBE_TABLE" | awk -v n="$1" -v f="$2" '$1 == n { for (i = 3; i <= NF; i++) if ($i == f) print "yes" }'; }

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
	trap 'rm -rf "$LOCK"' EXIT

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
	echo "run_probes: importing..."
	( cd "$PROJECT" && timeout 900 "$GODOT" --headless --path . --import > "$LOGS/_import.log" 2>&1 )
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
T0=$(date +%s)
for p in $PARALLEL; do
	while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
	run_one "$p" &
done
wait
for p in $SERIAL; do run_one "$p"; done
T1=$(date +%s)

FAILED=$(grep -c ' FAIL ' "$LOGS/_results.txt" 2>/dev/null)
echo "run_probes: $((COUNT - FAILED)) of $COUNT passed in $((T1 - T0))s"

# --- Did HEAD move under the run? ---
END_HEAD=$(git -C "$REPO" rev-parse HEAD)
TESTED_HEAD="${REF:+$(git -C "$REPO" rev-parse "$REF")}"
TESTED_HEAD="${TESTED_HEAD:-$START_HEAD}"
if [ "$END_HEAD" != "$TESTED_HEAD" ]; then
	report_head_moved "$TESTED_HEAD" "$END_HEAD"
fi

[ "$FAILED" = 0 ]
