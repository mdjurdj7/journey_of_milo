# Game framework (working)

## Shape of a run
- A run is a sequence of floors. Each floor is a navigable 3D field
  (top-down, Dreams-style camera) the player walks freely.
- A floor holds a set of encounters (enemies visible in the field),
  events (findings, not incidents), and objectives. Some subset must
  be cleared to open the way to the next floor; the rest is optional.
- Floors group into regions. Each region has its own palette, ground,
  weather, and roster. Region 1 is the tidal flat; the tower is the
  destination and grows with depth.
- Combat happens in place: contact with an enemy freezes the field,
  the camera swings to a side-on battle frame, and the card battle
  plays over the 3D scene. Win/Lose/Escape resume the field.

## Systems
- HP is the currency in and out of combat. Walking costs it (wading,
  crossing), cards spend it, Rally recovers it. Toll accrues and
  cashes out.
- The deck is built from what the field yields: belongings found,
  cards earned from encounters, secrets that cost HP with no Toll.
- Enemies are things that stayed: legible in Region 1, stranger with
  depth. They are placed, mostly still, and the player chooses which
  to approach.

## What is settled
- 3D field in Godot 4.7.1, flat-shaded, no textures, fog-driven
  atmosphere. Card rules port from the old project; the view is new.
- Dark figures on pale ground. No warm light in Region 1.
- Nothing in a floor is arranged for the player.

## What is open
- Floor size and count per region.
- What "clear" means per floor: kill count, objective, or reaching a
  threshold.
- Whether floors are authored maps with procedural population or
  fully generated.
- How events are represented in the field.
- Rest without fire.
