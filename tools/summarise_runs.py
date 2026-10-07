#!/usr/bin/env python3
"""Summarise the run logs RunLogger writes (one JSON-lines file per run).

    python tools/summarise_runs.py                  every run in the runs folder
    python tools/summarise_runs.py --since 2026-10-01
    python tools/summarise_runs.py --since f582d6b  runs on that commit or later
    python tools/summarise_runs.py --dir PATH       another folder
    python tools/summarise_runs.py --include-debug  keep debug runs and fights

Prints, as plain text:
  - per encounter: fights, average damage taken, average turns, loss rate
  - per card, fight rewards: offered, taken, skipped (offered, not taken),
    pick rate - with belongings, bundle and find offers in their own columns
  - per card: plays per fight it was in the deck for
  - HP at each floor entered, per run and on average
  - wins: how many runs were won, and each win's tally (run_end cause "won")
  - format 2 on (RunLogger.FORMAT_VERSION 2, 2026-10-07):
    - fights by role (basic, required, elite, region_end): turns, HP lost
      to enemies and to self, loss rate
    - threshold intents (the Gape, the Siltjaw's Charge): break rate, and
      the average attack-card stacks (Goaded) at resolution
    - kill order: which enemy died first, per multi-enemy encounter
    - escalation: the highest stage each escalating enemy's fights reached
    - heals by source, Toll gained and spent by source, and average
      unspent Energy per turn
    Older logs lack these fields; each section says what it saw.

The runs folder defaults to user://runs/ for this project:
%APPDATA%\\Godot\\app_userdata\\Journey of Milo\\runs on Windows,
~/.local/share/godot/app_userdata/Journey of Milo/runs elsewhere.

--since takes a date (YYYY-MM-DD, compared with run_start's ts) or a commit.
A commit keeps the runs whose version is that commit or a descendant of it,
asked of git in this script's repo; without git, the runs from the first one
on that commit onward, by date. Fights a debug button ended are left out
unless --include-debug; so are whole runs marked debug - run_end's
debug_run, or (older logs) any debug_* event or debug-ended fight in them.
Runs ended "stopped" (killed without a run_end - RunLogger closes them on
the next run) are reported apart from died/won/quit. Standard library only.
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


SELF_SOURCES = ("self", "status")


def is_debug_run(run):
    for event in run["events"]:
        ev = event.get("ev", "")
        if ev == "run_end" and event.get("debug_run"):
            return True
        if ev.startswith("debug_") or (ev == "fight_end" and event.get("debug")):
            return True
    return False


def summarise(runs, include_debug):
    debug_runs = 0
    if not include_debug:
        kept = [run for run in runs if not is_debug_run(run)]
        debug_runs = len(runs) - len(kept)
        runs = kept
    encounters = defaultdict(lambda: {"fights": 0, "losses": 0, "taken": [], "turns": []})
    reward = defaultdict(lambda: defaultdict(int))  # card -> counter
    plays = defaultdict(int)
    fights_in_deck = defaultdict(int)
    skipped_choices = 0
    fight_choices = 0
    floor_rows = []
    floor_hp = defaultdict(list)
    causes = defaultdict(int)
    wins = []
    debug_left_out = 0
    # Format 2.
    roles = defaultdict(lambda: {"fights": 0, "losses": 0, "turns": [], "enemy": [], "self": []})
    no_role = 0
    thresholds = defaultdict(lambda: {"broken": 0, "landed": 0, "other": 0, "stacks": []})
    first_deaths = defaultdict(lambda: defaultdict(int))
    escalation = defaultdict(lambda: defaultdict(int))
    heals = defaultdict(int)
    toll_gained = defaultdict(int)
    toll_spent = defaultdict(int)
    unspent = []
    v2_fights = 0

    for run in runs:
        deck_at_fight = {}
        role_at_fight = {}
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
                role_at_fight[event.get("fight")] = event.get("role")
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
                taken_by = event.get("damage_taken", {}).get("by_source", {})
                role = role_at_fight.get(event.get("fight"))
                if role is None:
                    no_role += 1
                else:
                    r = roles[role]
                    r["fights"] += 1
                    r["losses"] += 1 if event.get("result") == "lose" else 0
                    r["turns"].append(event.get("turns", 0))
                    r["self"].append(sum(v for k, v in taken_by.items() if k in SELF_SOURCES))
                    r["enemy"].append(sum(v for k, v in taken_by.items() if k not in SELF_SOURCES))
                if "turn_log" in event:
                    v2_fights += 1
                    for turn in event.get("turn_log", []):
                        if turn.get("energy_left") is not None:
                            unspent.append(turn["energy_left"])
                    deaths = event.get("deaths", [])
                    if len(deaths) > 1:
                        first_deaths[event.get("encounter", "?")][deaths[0]] += 1
                    for enemy, stage in event.get("escalation_max", {}).items():
                        escalation[enemy][stage] += 1
                    toll = event.get("toll", {})
                    for source, amount in toll.get("gained_by_source", {}).items():
                        toll_gained[source] += amount
                    for source, amount in toll.get("spent_by_source", {}).items():
                        toll_spent[source] += amount
            elif ev == "heal":
                heals[event.get("source", "?")] += event.get("amount", 0)
            elif ev == "mechanic" and event.get("kind") == "threshold_resolved":
                t = thresholds["%s %s" % (event.get("enemy", "?"), event.get("intent", "?"))]
                outcome = event.get("outcome")
                t[outcome if outcome in ("broken", "landed") else "other"] += 1
                t["stacks"].append(event.get("stacks", 0))
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
                if event.get("cause") == "won":
                    wins.append((run["name"], event))
        if not ended:
            causes["unfinished (no run_end yet)"] += 1
        floor_rows.append((run["name"], str(run["start"].get("version", "?")), "  ".join(hp_path)))

    out = []
    out.append("%d run(s): %s" % (len(runs), ", ".join("%s %d" % (k, v) for k, v in sorted(causes.items()) if k != "stopped") or "none"))
    out.append("stopped (killed without a run_end, closed later): %d" % causes.get("stopped", 0))
    if debug_runs:
        out.append("(%d debug run(s) left out; --include-debug keeps them)" % debug_runs)
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

    out.append("\nWINS - %d of %d run(s)" % (len(wins), len(runs)))
    rows = []
    for name, end in wins:
        rows.append((name, end.get("floors_crossed", "?"), end.get("fights_won", "?"),
                     "%s/%s" % (end.get("hp", "?"), end.get("max_hp", "?")), end.get("deck_size", "?"), end.get("keepsake") or "-"))
    out.append(table(("run", "floors", "fights won", "hp", "deck", "keepsake"), rows) if rows else "(no wins)")

    out.append("\nFIGHTS BY ROLE - HP lost to enemies and to self, per fight")
    rows = []
    for role in ("basic", "required", "elite", "region_end"):
        r = roles.get(role)
        if r is None:
            continue
        rows.append((role, r["fights"], avg(r["turns"]), avg(r["enemy"]), avg(r["self"]), rate(r["losses"], r["fights"])))
    out.append(table(("role", "fights", "avg turns", "enemy hp", "self hp", "loss rate"), rows) if rows else "(no fights with a role)")
    if no_role:
        out.append("(%d fight(s) predate format 2 and carry no role)" % no_role)

    out.append("\nTHRESHOLD INTENTS - broken or landed (stacks: the attack-card stacks it carried - Goaded)")
    rows = []
    for name, t in sorted(thresholds.items()):
        decided = t["broken"] + t["landed"]
        rows.append((name, t["broken"], t["landed"], t["other"], rate(t["broken"], decided), avg(t["stacks"])))
    out.append(table(("intent", "broken", "landed", "other", "break rate", "avg stacks"), rows) if rows else "(none seen - logged from format 2 on)")

    out.append("\nKILL ORDER - the first to die, per multi-enemy encounter")
    rows = []
    for name, firsts in sorted(first_deaths.items()):
        total = sum(firsts.values())
        rows.append((name, total, ", ".join("%s %d (%s)" % (k, v, rate(v, total).strip()) for k, v in sorted(firsts.items(), key=lambda kv: -kv[1]))))
    out.append(table(("encounter", "fights", "first death"), rows) if rows else "(none seen - logged from format 2 on)")

    out.append("\nESCALATION - the highest stage reached (0-based), fights per stage")
    rows = []
    for enemy, stages in sorted(escalation.items()):
        rows.append((enemy, sum(stages.values()), ", ".join("stage %s: %d" % (k, v) for k, v in sorted(stages.items()))))
    out.append(table(("enemy", "fights", "reached"), rows) if rows else "(none seen - logged from format 2 on)")

    out.append("\nHEALS BY SOURCE (HP)")
    rows = [(k, v) for k, v in sorted(heals.items(), key=lambda kv: -kv[1])]
    out.append(table(("source", "hp"), rows) if rows else "(none seen - logged from format 2 on)")

    out.append("\nTOLL BY SOURCE")
    rows = []
    for source in sorted(set(toll_gained) | set(toll_spent)):
        rows.append((source, toll_gained.get(source, 0), toll_spent.get(source, 0)))
    out.append(table(("source", "gained", "spent"), rows) if rows else "(none seen - logged from format 2 on)")

    out.append("\nENERGY - average unspent per turn: %s over %d turn(s), %d format-2 fight(s)" % (avg(unspent).strip(), len(unspent), v2_fights))

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
