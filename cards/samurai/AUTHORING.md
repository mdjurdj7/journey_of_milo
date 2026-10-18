# Authoring Samurai cards

Every card in this folder is one of the Samurai's cards. A card saved here
joins her reward pool on the next run; there is no list to edit.

## Make a card

1. In the FileSystem dock, right-click `cards/samurai/` and choose
   **Create New > Resource**. Pick **CardData** and save it as
   `snake_case_name.tres`, for example `drawn_breath.tres`.
   - Or duplicate a card in `cards/neutral/` (right-click > Duplicate) and
     move the copy here. If you do, clear its **Tempered** field. Otherwise
     your card tempers into the original's tempered version.
2. Select the new file and fill it in, in the Inspector.

## Fields

Required:

| Field | What to put |
|---|---|
| **Card Name** | The name on the card. Must be unique across all cards. |
| **Cost** | Energy to play. |
| **Card Type** | Attack, Skill, Stance or Power. Attack matters to the rules: stances react to Attacks. |
| **Rarity** | Common, Uncommon, Rare or Ultra Rare. **Never leave it Unset.** An Unset card is never offered as a reward, and the card rarity check fails on it. |
| **Target Type** | Enemy (the player picks one), Self or None. |
| **Description** | The rules text. Numbers come from the effects through tokens such as `{damage}`, `{block}` and `{draw}`, so the text always matches. Copy the pattern from a similar card in `cards/neutral/`. |
| **Effects** | One or more CardEffect entries: click the array, **Add Element**, **New CardEffect**. Set **Effect Type** (Damage, Block, Draw, Heal and so on), **Value** and, if needed, **Condition** and **Target Scope**. |

Optional:

| Field | What to put |
|---|---|
| **Removal Scope** | None: back to the discard pile. Spent: gone for this fight. Consumed: gone for the run. The rules text should end on "Spent." or "Consumed." to match. |
| **Art** | The card illustration. Empty is fine; the face shows its type glyph. |
| **Play Sound Path** | A sound for this card instead of the shared one. |
| **Tempered** | The stronger version the wagon makes. It is its own CardData, saved in `cards/tempered/`, named with a `+`, with the same rarity and type. Leave it empty if the card can't be tempered. |
| **Battle Animation** | **Leave empty.** The names in use (Slash, Brace) are the Wanderer's rig clips. She has no rig yet, so an empty field is right. |
| **Impact Time** | Ignored while Battle Animation is empty: the card resolves at once. |

## Things that won't work for her

Toll, Grace and Critical are the Wanderer's. She gains no Toll, has no
Grace, and her HP bar shows no Critical line. Conditions and effects built
on them (Toll at least, Has Grace, Critical, the Toll damage effects) do
nothing useful on her cards. Ask before using one.

## Her pool

Her reward pool is `cards/pools/samurai_pool.tres`. It names two folders:
this one and `cards/neutral/`. Every CardData directly in either can drop,
at an even weight, by its rarity. Subfolders are not read, and nor is
`cards/tempered/`.

To shelve a card without deleting it, move it out of this folder.

## Testing a card

- In a run (debug build), the F1 row's card picker lists this folder.
  Pick a card to put it in the deck.
- The card compendium shows it under SAMURAI.
- To play as her, select the RegionField root in
  `field/region_field.tscn` and set **Starting Character** to
  `run/data/samurai.tres`. Put it back to `wanderer.tres` before you
  commit the scene.
