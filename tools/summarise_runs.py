#!/usr/bin/env python3
"""Summarise the run logs RunLogger writes (one JSON-lines file per run).

    python tools/summarise_runs.py                  every run in the runs folder
    python tools/summarise_runs.py --since 2026-10-01
    python tools/summarise_runs.py --since f582d6b  runs on that commit or later
    python tools/summarise_runs.py --dir PATH       another folder
    python tools/summarise_runs.py --include-debug  count debug-ended fights too

Prints, as plain text:
  - per encounter: fights, average damage taken, average turns, loss rate
  - per card, fight rewards: offered, taken, skipped (offered, not taken),
    pick rate - with belongings, bundle and find offers in their own columns
  - per card: plays per fight it was in the deck for
  - HP at each floor entered, per run and on average

The runs folder defaults to user://runs/ for this project:
%APPDATA%\\Godot\\app_userdata\\Journey of Milo\\runs on Windows,
~/.local/share/godot/app_userdata/Journey of Milo/runs elsewhere.

--since takes a date (YYYY-MM-DD, compared with run_start's ts) or a commit.
A commit keeps the runs whose version is that commit or a descendant of it,
asked of git in this script's repo; without git, the runs from the first one
on that commit onward, by date. Fights a debug button ended are left out
unless --include-debug. Standard library only.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict

PROJECT_NAME = "Journey of Milo"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def default_runs_dir():
    if os.name == "nt":
        base = os.environ.get("APPDATA", os.path.expanduser("~"))
        return os.path.join(base, "Godot", "app_userdata", PROJECT_NAME, "runs")
    base = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
    return os.path.join(base, "godot", "app_userdata", PROJECT_NAME, "runs")


def load_runs(folder):
    runs = []
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".jsonl"):
            continue
        events = []
        with open(os.path.join(folder, name), encoding="utf-8") as handle:
            for number, raw in enumerate(handle, 1):
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    events.append(json.loads(raw))
                except json.JSONDecodeError:
                    # A crash can leave a half-written last line.
                    print("warning: %s line %d is not JSON; skipped" % (name, number), file=sys.stderr)
        if events and events[0].get("ev") == "run_start":
            runs.append({"name": name, "events": events, "start": events[0]})
    return runs


def descendants_of(commit):
    """Short hashes of `commit` and every commit after it, or None without git."""
    try:
        out = subprocess.run(
            ["git", "-C", REPO, "rev-list", "--ancestry-path", "--all", "^" + commit],
            capture_output=True, text=True, check=True).stdout
        found = {line.strip()[:7] for line in out.split()}
        full = subprocess.run(["git", "-C", REPO, "rev-parse", "--verify", commit + "^{commit}"],
                              capture_output=True, text=True, check=True).stdout.strip()
        found.add(full[:7])
        return found
    except (OSError, subprocess.CalledProcessError):
        return None


def filter_since(runs, since):
    if since is None:
        return runs
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", since):
        return [run for run in runs if str(run["start"].get("ts", "")) >= since]
    commits = descendants_of(since)
    if commits is not None:
        return [run for run in runs if str(run["start"].get("version", ""))[:7] in commits]
    ordered = sorted(runs, key=lambda run: str(run["start"].get("ts", "")))
    for index, run in enumerate(ordered):
        if str(run["start"].get("version", "")).startswith(since[:7]):
            return ordered[index:]
    return []


def rate(part, whole):
    return "%5.1f%%" % (100.0 * part / whole) if whole else "     -"


def avg(values):
    return "%6.1f" % (sum(values) / len(values)) if values else "     -"


def table(headers, rows, align_left=1):
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(str(cell)))
    def fmt(row):
        cells = []
        for i, cell in enumerate(row):
            text = str(cell)
            cells.append(text.ljust(widths[i]) if i < align_left else text.rjust(widths[i]))
        return "  ".join(cells).rstrip()
    lines = [fmt(headers), "  ".join("-" * w for w in widths)]
    lines += [fmt(row) for row in rows]
    return "\n".join(lines)


def summarise(runs, include_debug):
    encounters = defaultdict(lambda: {"fights": 0, "losses": 0, "taken": [], "turns": []})
    reward = defaultdict(lambda: defaultdict(int))  # card -> counter
    plays = defaultdict(int)
    fights_in_deck = defaultdict(int)
    skipped_choices = 0
    fight_choices = 0
    floor_rows = []
    floor_hp = defaultdict(list)
    causes = defaultdict(int)
    debug_left_out = 0

    for run in runs:
        deck_at_fight = {}
        hp_path = []
        ended = False
        for event in run["events"]:
            ev = event.get("ev")
            if ev == "floor_entered":
                key = (event.get("lap", 0), event.get("region", 0), event.get("floor", 0))
                hp_path.append("L%dF%d %d/%d" % (key[0], key[2] + 1, event.get("hp", 0), event.get("max_hp", 0)))
                floor_hp[key].append(event.get("hp", 0))
            elif ev == "fight_start":
                deck_at_fight[event.get("fight")] = event.get("deck", {})
            elif ev == "fight_end":
                if event.get("debug") and not include_debug:
                    debug_left_out += 1
                    continue
                stats = encounters[event.get("encounter", "?")]
                stats["fights"] += 1
                stats["losses"] += 1 if event.get("result") == "lose" else 0
                stats["taken"].append(event.get("damage_taken", {}).get("total", 0))
                stats["turns"].append(event.get("turns", 0))
                for card in deck_at_fight.get(event.get("fight"), {}):
                    fights_in_deck[card] += 1
                for played in event.get("cards", []):
                    plays[played.get("card")] += 1
            elif ev == "reward_cards":
                source = event.get("source", "fight")
                taken = event.get("taken")
                if source == "fight":
                    fight_choices += 1
                    if taken is None:
                        skipped_choices += 1
                for card in event.get("offered", []):
                    reward[card][source + "_offered"] += 1
                    if card != taken:
                        reward[card][source + "_skipped"] += 1
                if taken is not None:
                    reward[taken][source + "_taken"] += 1
            elif ev == "belongings":
                offered_card = (event.get("offered") or {}).get("card")
                if offered_card:
                    reward[offered_card]["belongings_offered"] += 1
                    if event.get("taken") == "card":
                        reward[offered_card]["belongings_taken"] += 1
            elif ev == "run_end":
                causes[event.get("cause", "?")] += 1
                ended = True
        if not ended:
            causes["unfinished"] += 1
        floor_rows.append((run["name"], str(run["start"].get("version", "?")), "  ".join(hp_path)))

    out = []
    out.append("%d run(s): %s" % (len(runs), ", ".join("%s %d" % (k, v) for k, v in sorted(causes.items())) or "none"))
    if debug_left_out:
        out.append("(%d debug-ended fight(s) left out; --include-debug counts them)" % debug_left_out)

    out.append("\nENCOUNTERS")
    rows = []
    for name, stats in sorted(encounters.items()):
        rows.append((name, stats["fights"], avg(stats["taken"]), avg(stats["turns"]), rate(stats["losses"], stats["fights"])))
    out.append(table(("encounter", "fights", "avg taken", "avg turns", "loss rate"), rows) if rows else "(no fights)")

    out.append("\nCARD REWARDS - fight offers: %d choice(s), %d skipped outright" % (fight_choices, skipped_choices))
    rows = []
    for card in sorted(reward):
        c = reward[card]
        rows.append((card, c["fight_offered"], c["fight_taken"], c["fight_skipped"], rate(c["fight_taken"], c["fight_offered"]),
                     "%d/%d" % (c["belongings_taken"], c["belongings_offered"]),
                     "%d/%d" % (c["bundle_taken"], c["bundle_offered"]),
                     "%d/%d" % (c["find_taken"], c["find_offered"])))
    out.append(table(("card", "offered", "taken", "skipped", "pick rate", "belongings", "bundle", "find"), rows) if rows else "(no card offers)")
    out.append("(skipped: offered and not taken. belongings/bundle/find: taken/offered; a bundle or a find is logged only when taken.)")

    out.append("\nCARD PLAYS - per fight the card was in the deck for")
    rows = []
    for card in sorted(set(plays) | set(fights_in_deck)):
        in_deck = fights_in_deck.get(card, 0)
        rows.append((card, in_deck, plays.get(card, 0), "%5.2f" % (plays.get(card, 0) / in_deck) if in_deck else "    -"))
    out.append(table(("card", "fights in deck", "plays", "plays/fight"), rows) if rows else "(no fights)")

    out.append("\nHP AT EACH FLOOR ENTERED (L = lap, F = floor)")
    rows = []
    for key in sorted(floor_hp):
        values = floor_hp[key]
        rows.append(("L%d F%d" % (key[0], key[2] + 1), len(values), avg(values), min(values), max(values)))
    out.append(table(("floor", "runs", "avg hp", "min", "max"), rows) if rows else "(no floors)")
    out.append("")
    for name, version, path in floor_rows:
        out.append("%s [%s]  %s" % (name, version, path))
    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser(description="Summarise RunLogger's run logs.")
    parser.add_argument("--dir", default=default_runs_dir(), help="the runs folder (default: %(default)s)")
    parser.add_argument("--since", help="a date (YYYY-MM-DD) or a commit: only runs from then on")
    parser.add_argument("--include-debug", action="store_true", help="count fights a debug button ended")
    args = parser.parse_args()
    if not os.path.isdir(args.dir):
        print("no runs folder at %s" % args.dir, file=sys.stderr)
        return 1
    runs = filter_since(load_runs(args.dir), args.since)
    print(summarise(runs, args.include_debug))
    return 0


if __name__ == "__main__":
    sys.exit(main())
