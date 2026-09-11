# Design decisions log

Parked decisions and deferred items - see CLAUDE.md's own pointer to this
file. Not a full design document, just what's been consciously set aside
so it doesn't get silently reinvented or silently forgotten.

## Parked

- **Chain roles (Opener/Closer, chain payoffs).** The old project's
  `CardData.chain_role`/`chain_followup_effect` are not ported to the new
  rules layer (`cards/card_data.gd`). No current card needs them - revisit
  once a real card actually wants a chain-shaped payoff, not before.
  (2026-09-11, rules-layer port.)
