# Project Context

This is a single-hero roguelike deckbuilder (Slay the Spire-style card
combat) built in **Godot 4** with **GDScript**. See DESIGN.md for the full
design document, pillars, and current scope.

## Environment

Godot executable (mdjur, this machine): C:/Users/mdjur/Desktop/GameDev/Godot_v4.7.1-stable_win64_console.exe
Godot executable (gevic's machine): C:/Users/gevic/OneDrive/Desktop/Godot_v4.7.1-stable_win64.exe

Use whichever path matches the current machine's user account. Prefer the
`_console.exe` build for headless/CLI runs — it's the one guaranteed to
print to stdout in a terminal.

Do not search the filesystem for the Godot binary. If neither path is right or
missing, ask rather than running find/where across the drive — a recursive
find from / under Git Bash on Windows will hang for hours.

## How to work with me

- I'm a beginner relearning to code — explanations should be patient and
  jargon-light. Introduce a term before assuming I know it.
- Work in small incremental steps. Implement one small, working piece at
  a time.
- Commit with git after each working change, before moving to the next
  step.

## Headless verification scenes

- Any throwaway `.gd`/`.tscn` scene built to verify behavior via a
  headless Godot run MUST explicitly call `get_tree().quit()` once its
  checks are done. Without it, headless Godot has nothing to exit for
  and keeps running indefinitely, burning CPU with no way to tell
  "still working" apart from "hung forever." This alone isn't
  sufficient, either: a runtime error anywhere earlier in the same
  `_ready()` skips every line after it, `get_tree().quit()` included -
  a script that errors partway through still hangs forever even though
  the quit call is right there in the file. Keep verification scripts
  simple enough that this isn't a live risk (see the screenshot rule
  below for the one way this has actually happened).
- NEVER attempt screenshot capture (`get_viewport().get_texture()...
  save_png()`) in a `--headless` run. Headless Godot uses a dummy
  rendering backend - `get_viewport().get_texture()` returns null
  there, `.get_image()`/`.save_png()` on that null throws mid-`_ready()`,
  and per the point above, that error silently skips the `get_tree().
  quit()` call later in the same function - the process then hangs
  forever with no further output and no crash, which is exactly what
  happened three times in one session before this was diagnosed.
- More generally: don't attempt screenshot-based self-verification at
  all anymore, headless or not. For anything visual, describe
  precisely what to look for (which node, what state, what it should
  look like) and let the user check it live in the editor - faster,
  more reliable, and it's how they've been verifying visual changes
  anyway.
- When running a headless scene, don't pipe through `tail` (or
  anything else that buffers) - it hides output until the process
  exits, which is exactly backwards when the process might be the one
  that's stuck.
- Delete these temp scenes (and their `.uid`/`.import` companions) once
  done with them - they're throwaway, not part of the project, and
  shouldn't accumulate in the repo root.
