#!/usr/bin/env bash
# The overnight full probe set: a clean worktree off current main, the
# whole suite at -j 2 there, and a summary to read in the morning.
#
#   tools/nightly_probes.sh            from Git Bash, in the main tree
#
# Or from PowerShell, in a window of its own that outlives the terminal
# it was started from (run_probes.sh stops if the shell under it goes):
#
#   Start-Process "C:\Program Files\Git\bin\bash.exe" -ArgumentList "tools/nightly_probes.sh"
#
# Steps:
# - Waits (polling every POLL_SEC, up to WAIT_MAX_SEC) while any other
#   Godot probe run or import is going - another session's - then gives
#   up and says so in the summary rather than run alongside it.
# - Makes NIGHTLY_DIR (../journey-of-milo-nightly) afresh, detached at
#   main: a worktree left from last night is removed first; a folder
#   there that isn't one of this repo's worktrees stops the run.
# - tools/run_probes.sh --path <it> --import --full -j 2, its logs kept.
#   The import is from scratch (no .godot copied in), so nothing stale is
#   tested; it takes a few minutes.
# - Writes REPORT_DIR/<date>-<time>.txt and copies it to REPORT_DIR/
#   latest.txt: main's commit, the start and end, total time, the passed
#   count, each probe's PASS/FAIL and seconds (longest first), and each
#   failure's first FAIL lines.
# - Removes the worktree; the logs stay in REPORT_DIR.
#
# REPORT_DIR defaults to ../probe-nightly beside the repo, outside git.
# Exit code: run_probes.sh's (0 all passed, 1 a failure, 4 memory stayed
# short), or 3 when another run never cleared, 2 when the worktree
# couldn't be made.

set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NIGHTLY_DIR=${NIGHTLY_DIR:-$(cd "$REPO/.." && pwd)/journey-of-milo-nightly}
REPORT_DIR=${REPORT_DIR:-$(cd "$REPO/.." && pwd)/probe-nightly}
POLL_SEC=60
WAIT_MAX_SEC=10800

mkdir -p "$REPORT_DIR"
STAMP=$(date +%Y-%m-%d-%H%M)
REPORT="$REPORT_DIR/$STAMP.txt"
LOGS="$REPORT_DIR/logs-$STAMP"
RUNNER_LOG="$REPORT_DIR/runner-$STAMP.log"
START=$(date +%s)

# The summary so far, written whatever the outcome.
report() {
	local code="$1" note="$2" end
	end=$(date +%s)
	{
		echo "Nightly probe run, $STAMP"
		echo "main:     ${COMMIT:-?}"
		echo "started:  $(date -d "@$START" '+%Y-%m-%d %H:%M:%S')"
		echo "ended:    $(date -d "@$end" '+%Y-%m-%d %H:%M:%S')"
		echo "total:    $(( (end - START) / 60 )) min $(( (end - START) % 60 )) s, waiting and import included"
		[ -n "$note" ] && echo "note:     $note"
		echo "exit:     $code"
		if [ -f "$LOGS/_results.txt" ]; then
			echo "probes:   $(grep -c ' PASS ' "$LOGS/_results.txt") passed, $(grep -c ' FAIL ' "$LOGS/_results.txt") failed, of $(wc -l < "$LOGS/_results.txt")"
			grep -E '^run_probes: [0-9]+ of [0-9]+ passed in [0-9]+s$' "$RUNNER_LOG" 2>/dev/null | sed 's/^run_probes: /the set:  /; s/$/ (the probes alone)/'
			echo
			sort -k3,3nr "$LOGS/_results.txt" | awk '{ printf "%-28s %s %5s\n", $1, $2, $3 }'
			for p in $(awk '$2 == "FAIL" { print $1 }' "$LOGS/_results.txt"); do
				echo
				echo "== $p"
				grep -E '^FAIL|FAIL:|SCRIPT ERROR|Parse Error' "$LOGS/$p.log" 2>/dev/null | head -8
			done
		fi
		echo
		echo "logs:     $LOGS"
		echo "runner:   $RUNNER_LOG"
	} > "$REPORT"
	cp "$REPORT" "$REPORT_DIR/latest.txt"
	echo "nightly_probes: summary in $REPORT"
}

# Other sessions' probe processes or imports (CLAUDE.md's check).
others() {
	powershell.exe -NoProfile -Command "@(Get-CimInstance Win32_Process -Filter \"Name='Godot_v4.7.1.exe'\" | Where-Object { \$_.CommandLine -match '-s res://tests/' -or \$_.CommandLine -match '--headless --path \. --import' }).Count" 2>/dev/null | tr -d '\r'
}

waited=0
while [ "$(others)" != "0" ]; do
	if [ "$waited" -ge "$WAIT_MAX_SEC" ]; then
		report 3 "another session's probes were still running after $((WAIT_MAX_SEC / 60)) min - nothing run"
		exit 3
	fi
	[ "$waited" = 0 ] && echo "nightly_probes: another probe run is going - waiting for it"
	sleep "$POLL_SEC"
	waited=$((waited + POLL_SEC))
done

# The worktree, afresh at main.
if [ -e "$NIGHTLY_DIR" ]; then
	if git -C "$REPO" worktree list --porcelain | grep -qxF "worktree $(cd "$NIGHTLY_DIR" && pwd -W 2>/dev/null || pwd)"; then
		git -C "$REPO" worktree remove --force "$NIGHTLY_DIR" || { report 2 "couldn't remove last night's worktree at $NIGHTLY_DIR"; exit 2; }
	else
		report 2 "$NIGHTLY_DIR exists and isn't one of this repo's worktrees - left alone, nothing run"
		exit 2
	fi
fi
git -C "$REPO" worktree prune
COMMIT=$(git -C "$REPO" log -1 --format='%h %s' main)
git -C "$REPO" worktree add --detach "$NIGHTLY_DIR" main > /dev/null 2>&1 || { report 2 "git worktree add failed"; exit 2; }

echo "nightly_probes: running the full set at -j 2 in $NIGHTLY_DIR (main $COMMIT)"
"$NIGHTLY_DIR/tools/run_probes.sh" --path "$NIGHTLY_DIR" --import --full -j 2 --logs "$LOGS" > "$RUNNER_LOG" 2>&1
CODE=$?
NOTE=""
[ "$CODE" = 4 ] && NOTE="memory stayed short - the run stopped; see the runner log"
report "$CODE" "$NOTE"
git -C "$REPO" worktree remove --force "$NIGHTLY_DIR" > /dev/null 2>&1
exit "$CODE"
