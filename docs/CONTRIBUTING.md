# Contributing

Read [the README](../README.md) first for how to run the project and its
tests. This file covers conventions and the pitfalls that have already cost
time here.

## Keeping cartridge data out

Nothing derived from a commercial cartridge may be committed: not the ROM, not
a `.sav`, not extracted sprites, text, maps or audio. Three independent layers
enforce this, and none of them should be weakened:

1. **`.gitignore`** blocks the known extensions, the `roms/` drop folder and
   the runtime cache directories.
2. **`.githooks/pre-commit`** checks what is actually *staged*: by extension,
   and by size for any blob ≥ 512 KiB outside `addons/` and `assets/`. That
   second check catches a renamed or trimmed dump that no extension rule would
   see. Enable it with `git config core.hooksPath .githooks`; Git does not
   clone hooks, so every clone needs it once.
3. **Tests never load a real cartridge.** `test_rom_verifier.gd` covers the
   import gate with synthetic files and a known SHA-1 vector, so the suite runs
   on any machine and in CI.

`roms/` additionally carries a `.gdignore`, which makes Godot's resource system
skip the directory entirely, so files there are never imported and never swept
into an export. `FileAccess` can still read them during development, which is
how `tools/verify_rom.gd` works. Do not delete that file.

## Architecture

The ROM layer is the model for the rest of the engine:

- `game/rom/rom_registry.gd`: the SHA-1 allowlist.
- `game/rom/rom_verifier.gd`: size pre-filter, then chunked SHA-1, then
  lookup.
- `game/rom/rom_file.gd`: a verified dump in memory, plus bank addressing.
- `game/rom/rom_header.gd`: the cartridge header, for diagnostics only.

All of them are `RefCounted` statics with no scene dependencies, so the import
gate is fully testable headlessly. Keep the engine core the same shape: rules
apart from content, and randomness injected as an explicit
`RandomNumberGenerator` rather than pulled from a global, so a whole battle can
play out inside a test.

The importer under `game/import/` decodes a verified cartridge into a cache:

| | |
|---|---|
| `lz_decompressor.gd` | The LZ variant every compressed graphic uses |
| `tile_codec.gd` | 2bpp and 1bpp tiles to colour indices; pic layout |
| `text_codec.gd` | The Generation 2 character encoding |
| `palette.gd` | 15-bit BGR colours |
| `rom_layout.gd` | Where each table lives, per game |
| `rom_cache.gd` | The `user://` cache: paths, formats, lifecycle |
| `rom_importer.gd` | Orchestration, and the layout self-check |

Each decoder takes bytes and returns data; none of them knows what a cartridge
is, so all of them are testable on a handful of hand-built bytes.

Above the cache, `game/data/game_data.gd` reads it back. It is the only thing
the engine uses to see cartridge content: nothing above it opens a ROM, and
nothing in it knows what a ROM is. It is also where JSON's single number type is
coerced back to int, once, rather than at every call site.

`game/data/learnset.gd` sits beside it and is the one rule that lives in this
layer rather than in the engine: what a Pokémon knows at a level. It is here
because a Pokémon is made outside a battle as well as inside one. It answers two
questions that are not each other's shortcut, because the cartridge asks them
with two different routines:

- **Filling a new Pokémon** walks the list from the start and stops at the first
  move above the level being filled for.
- **Levelling up** reads the whole list and takes the entries at exactly the
  level just reached.

Those give different answers for Muk, whose list is not in ascending order in any
of the three games. A Muk caught in the wild at 40 is genuinely missing three
moves that a Muk raised to 40 has, and that is the cartridge's behaviour rather
than an approximation of it.

The drawing layer is deliberately thin:

| | |
|---|---|
| `render/pic_image.gd` | Colour indices plus a palette to an `Image` |
| `render/gen2_screen.gd` | The 160x144 screen, scaled by a whole number |
| `render/font.gd` | Character codes to glyph tiles, blitted into a buffer |
| `render/text_layout.gd` | A string to the lines and pages a box can show |
| `render/text_box.gd` | The two of them, as a bordered window on the grid |
| `render/battle_tiles.gd` | The battle's tile page, assembled as the hardware does |
| `render/battle_hud.gd` | The two status panels, on the tile grid |

The battle engine is the same shape as the ROM layer: `RefCounted`, no scenes,
and randomness passed in as an explicit `RandomNumberGenerator`, so a whole
battle can be fought inside a test:

| | |
|---|---|
| `battle/stats.gd` | Base stats, DVs and stat experience into the six stats |
| `battle/damage.gd` | The damage formula, STAB, criticals and the spread |
| `battle/accuracy.gd` | Whether a move connects |
| `battle/battle_mon.gd` | One Pokémon: its stats, PP, health and stages |
| `battle/party.gd` | The six a side carries, and which of them is out |
| `battle/trainer_party.gd` | One of the cartridge's own trainers, built into a party |
| `battle/status.gd` | The status byte, and the four things it does |
| `battle/substatus.gd` | The second byte: confusion, flinching, a charge, a recharge |
| `battle/turn.gd` | One move being used, while it is being used |
| `battle/effect_commands.gd` | The steps a move is made of |
| `battle/move_effect.gd` | Which steps each effect byte is made of |
| `battle/battle.gd` | The turn: order, the switch, and running a move's steps |
| `battle/ai.gd` | A trainer class's own AI: scores each move slot off its AI flags |

Everything in there is integer arithmetic in the order the hardware does it.
That is not nostalgia. Every step truncates and the steps do not commute, so a
formula rearranged into something tidier gives a different answer often enough
to matter, and the Pokémon that survives on one hit point does so because of a
truncation somewhere in it. Two in particular are easy to write in a form that
is almost right:

- **The square root for stat experience is a ceiling.** The cartridge scans a
  table of squares for the first entry that is not smaller than the value, so
  an untrained Pokémon answers 1 and not 0. A floor puts a trained stat one out.
- **Type matchups are applied to the damage one type at a time.** That is not
  the same as applying the combined multiplier once, because each step
  truncates, and it is also not the same number the battle announces: the
  announced one is a separate accumulator that truncates in tenths. Ember on a
  Fire/Rock defender deals 6 and reports "not very effective" on the strength of
  a 2. `GameData.type_effectiveness` is for the message and
  `GameData.type_matchup` per type is for the damage.

Two things a battle cannot decide for itself are left to whoever is driving it,
because on the cartridge a person or an AI decides both: what a side does with
its turn, and who replaces a Pokémon that has fainted. A turn that ends with
somebody down stops there, says so through `must_replace`, and refuses to do
anything else until `send_out` has been called. Nothing else in the engine has
a policy hole in it, and this one is deliberate.

A switch is not a move with a very high priority. The cartridge settles it
before it looks at priority at all, so a switching side always acts first and
the other side's move hits whoever came in. That is why an action is
`use_move` or `switch_to` rather than a move number.

`Gen2TrainerParty.build` turns one of a trainer class's own trainers into a
`Gen2Party`, the same way `Gen2Learnset` turns a species' learnset into what a
level knows. It sits beside the rest of the battle engine rather than next to
`Gen2Learnset` because what it hands back is battle types, not cartridge data,
and it draws the same distinction the trainer party table itself draws
between a NORMAL or ITEM trainer's Pokémon (which knows what its level teaches
it, through `GameData.moves_at_level`, the same as a wild one) and a MOVES or
ITEM_MOVES trainer's (which knows exactly what is stored with it, zero slots
dropped rather than passed to `Gen2BattleMon` as a move). Its Pokémon carry
the class's own DVs (`GameData.trainer_dvs`, decoded out of a fifth trainer
table by `RomImporter.read_trainer_dvs`) rather than
`Gen2BattleMon.PERFECT_DVS`: a class's whole party shares one fixed
Attack/Defense/Speed/Special word on the real cartridge, which is why the
word is asked for once per class in `Gen2TrainerParty.build` rather than once
per Pokémon.

`Gen2BattleAI.choose_slot` picks a trainer's own move the way pokecrystal's
`AIChooseMove` does: every slot starts at a fixed score, unusable ones start
worse, and every bit set in the trainer class's own AI move weight word
(`GameData.trainer_attributes`, decoded by `RomImporter.read_trainer_attributes`
out of a third trainer table) runs one scoring layer that nudges a slot's
score up or down, in the cartridge's own bit order. The lowest score wins.
`_pick_lowest` is not the cartridge's own way of finding it: `AIChooseMove`
decrements every slot's counter once per pass until one reaches zero, then
walks backward correcting for the round-robin order so every slot tied for
the true minimum ends up equally eligible, before a final random pick. That
byte-level race is provably the same outcome as finding the minimum directly
and breaking ties at random, which is what this does instead, because the
race is how eight-bit hardware computes an argmin without a MIN instruction,
not a rule of its own worth reproducing. `AI_Smart`'s own per-effect handlers
(`AI_Smart_Toxic`, `AI_Smart_Sleep`, and the rest) are implemented only for
the effects `move_effect.gd` already gives a battle sequence: an effect this
engine cannot play out yet cannot be tested against a real cartridge's choice
either, so it falls to the generic layers alone, the same falling-back
discipline the move table itself uses. See `HANDOFF.md`'s "Deliberate" section
for what else the AI does not cover (a trainer's switch and item decisions,
Razor Wind/Solar Beam/Fly's own handlers, which read weather and a
semi-invulnerability substatus nothing here tracks).

**A move is a short program, not a special case.** The cartridge keeps a list of
commands per effect byte and runs them in order, and an ordinary attack is the
list that announces the move, spends the PP, works the damage out, rolls the
hit, applies it and checks for a faint. Almost every other move is that list
with a step added, removed or replaced. `move_effect.gd` is that table,
`effect_commands.gd` is the steps, `turn.gd` is what one step hands the next,
and `battle.gd` knows only how to run a list.

The status conditions are the first thing written that way, and they are spread
across the turn rather than gathered in one place, because that is where the
cartridge puts them:

- **Whether a Pokémon can move** is asked before the effect is looked up, so
  every move goes through it and no sequence has to remember to include it.
  Sleep, then freeze, then paralysis, in that order.
- **What a status does to a stat** is applied where the stat is read, after the
  stage and on the same copy. That is what decides that a critical hit, which
  reads the unmodified stat, is free of a burn as well as of the stages.
- **What a status takes each turn** is applied after both sides have acted, in
  the order they acted.

Two of those are worth knowing because they are the opposite of what is usually
assumed. A Pokémon that wakes up **does** move that turn: the cartridge counts
the sleep off, says it woke, and carries straight on into the rest of its
checks. That is Generation 2's rule and not Generation 1's. And a secondary
effect's roll sits *between* the hit and the status, so a failed roll costs the
status and nothing else; the damage in front of it has already happened.

Keep it that way. A burn is a command appended to a list, a move that cannot
miss is a list without the roll, and a two-turn move is a list that ends early
the first time. The moment an effect becomes a branch inside the turn loop, the
next hundred of them have nowhere to go. The command names are the cartridge's
own so a sequence can be read against `data/moves/effects.asm` line for line,
and an effect with no list of its own falls back to the ordinary attack, which
is why a move nobody has written yet behaves rather than doing nothing.

A multi-hit move is where that shape was tested hardest, because the
cartridge's own script does not run its commands once each: `BattleCommand_StartLoop`
and `BattleCommand_EndLoop` jump the instruction pointer backward until a hit
count decided on the first pass runs out. Giving `Gen2Battle._act` an
instruction pointer that can move backward would have been reproducing how
eight-bit hardware repeats a handful of steps without a real loop construct,
not what it repeats, so `Gen2EffectCommands.MULTI_HIT` is one command that
rolls and applies every hit itself, stopping early on a faint exactly the way
the cartridge's loop does by jumping past its own summary text. That is the
same move the whole design already made for `ALL_STATS_UP`, which loops over
five stats inside one command rather than five commands: a small loop *inside*
a step is still one step, and only a loop that reaches back across several
different steps would have needed the list itself to change shape. Drain and
the four fixed-damage effects (`FIXED_DAMAGE`, shared by Super Fang, Sonicboom,
Seismic Toss and Psywave the way the cartridge shares one `ConstantDamage`
routine between them) both overwrite what `DAMAGE_CALC` already worked out
rather than replacing it in the list, keeping only the one thing worth keeping
from that spent roll: whether the hit is immune at all. Drain is worth a second
look before assuming its shape follows recoil's: it heals off
`Gen2Turn.damage`, the number the formula calculated, not `Gen2Turn.dealt`, the
number that actually came off a target with less left than that, because the
cartridge's own `SapHealth` reads the same uncapped figure `ApplyDamage` reads
before clamping it. `Gen2EffectCommands._recoil` uses `Gen2Turn.dealt` instead,
which the disassembly's own `BattleCommand_Recoil` does not: it also reads the
uncapped `wCurDamage`. That divergence was not fixed here, since it was found
while writing an unrelated effect and touching an already-shipped, already-
tested one was outside what this change was for; whoever picks it up should
decide whether an overkill hit's recoil is worth correcting to match.

`battle/status.gd` is one status byte, one at a time, refusing a second rather
than adding it. `battle/substatus.gd` is everything that does not fit on that
byte because a Pokémon can carry several of it at once: confusion alongside a
burn, a two-turn move's charge alongside either. It is the same shape, flag
constants and pure arithmetic holding no state of its own, but the counters
that go with a flag (how many turns of confusion are left, which move was
charged, how ramped a Toxic is) live on `Gen2BattleMon` next to it rather than
packed into the byte, because `Gen2Turn` is discarded at the end of the move
that needed them and the byte alone cannot say "and three turns of it". All of
it clears on a switch, in `Gen2BattleMon.reset_volatile`, called from
`Gen2Party.send_out` alongside `reset_stages` rather than folded into it: Haze
resets stages on both sides without touching either one's volatiles, so the two
have to stay two calls. A flag added here and forgotten in `reset_volatile` is
a bug that only shows up after a switch, which is why one test exists purely to
set every volatile field and ask for a blank Pokémon back.

`Gen2Battle` answers a turn with a list of events rather than with a new state
or a string. An event says what happened and carries the numbers behind it, so a
battle can be asserted on rather than read, and turning one into a sentence, an
animation or a bar that drains stays the screen's job.

`game/battle/battle_screen.gd` is the first screen that is not a development
view. It draws what it is given and decides nothing: it takes every number it
draws out of the event it is showing, not out of the Pokémon, because a turn has
finished resolving before its first event is shown and reading the Pokémon would
draw the end of the turn during the middle of it.

`Gen2Screen` renders the game into a `SubViewport` the size of the real
hardware and blows it up by an integer factor, while the interface around it
stays at the window's own resolution. This is a `Control` and not a
project-wide stretch setting on purpose: a stretch would have made the menus
fuzzy to keep the game sharp, and any non-integer factor resamples an 8x8 tile
into something that crawls when it moves.

Text is not typeset, it is tilemapped. Every character is one 8x8 tile, a
character code is already the number of the tile that draws it, and a text box
is a border printed as box-drawing characters around lines that sit two rows
apart. `Gen2Font` does the copying, `Gen2TextLayout` decides where the lines
break, and only `Gen2TextBox` is a node. Two consequences worth knowing before
you add a screen:

- **Measure a line in tiles, never in characters.** The apostrophe ligatures
  ($D0-$D6) and PK/MN are two characters in one glyph, so `String.length()`
  overstates a line and wraps it a column early. `Gen2Text.encoded_length()` is
  the measure that matches the screen.
- **The space at $7F is not in the font.** It is below the first glyph, so it
  draws nothing, which is exactly right and is also why `Gen2Font` treats a code
  it has no tile for as a no-op rather than an error.

## Offsets, and why they are checked at runtime

`rom_layout.gd` is a table of absolute positions inside each supported dump. An
offset is a claim about a specific 2 MiB file, and a wrong one does not throw:
it decodes neighbouring data into something plausible. A palette table that was
one entire table too far along still produced 251 sprites (the right shapes in
the wrong colours) and every unit test stayed green.

So every offset ships with a check that would fail if it were wrong, and
`RomImporter.verify_layout()` runs all of them before a single byte is decoded:

- Species names are read through the text codec and compared against the first
  and last species, which pins the offset, the stride and the character map at
  once.
- Every base stats entry begins with its own Pokédex number, so the whole table
  self-checks in one pass.
- Palettes have no self-identifying field, so they are checked structurally: a
  colour is 15 bits, and no species is drawn in two blacks.
- Every move entry opens with its own animation number, which is its move
  number, so the move table self-checks in one pass exactly like the base
  stats. Its type byte is range-checked in the same loop, because it indexes
  the type name table.
- The move and item names are variable-length, terminated rather than padded,
  so a start that is one byte out slides every later entry and still reads as
  words. Both tables are checked at the far end as well as the near one, and
  the item table also at entry four, where a start that is right but a walk
  that is not shows up first.
- The font is checked against the charmap, because the two are the same claim
  seen twice: the font is indexed by character code, so the letters and digits
  `Gen2Text` says are there must have ink, and the runs it has no character for
  must be blank. Those runs sit between the alphabets, so an offset out by a
  single tile drags a blank onto "z" and a glyph onto a code that has none.
- The battle HUD's graphics are checked by the one thing they do that nothing
  around them does: they count. A bar's fill levels are consecutive tiles, each
  lighting one more column than the last, so the ink climbs by exactly two
  pixels a step, and no wrong offset lands on a run like that. The two HUD
  borders have no progression, so they are checked the way the text box frames
  are. The four palettes the bars are drawn in are known values, so they are
  checked against those values.
- The type matchup chart is checked by the shape a chart of exceptions has to
  have. Every row is two type numbers and a multiplier, the type numbers are
  sparse, and the multiplier is one of three values that never includes the
  neutral one, because a neutral matchup is an absent row. A wrong offset lands
  in the padding run between the two groups of type numbers almost immediately,
  since that run is most of the byte range. On top of that the walk has to reach
  `$FE` and then `$FF` at exactly the right distance, and both ends of the chart
  are content whose answer is known independently.
- The three trainer tables are checked against each other, because they are
  three views of one numbering and a mistake shows up as them disagreeing. The
  class names pin the ends and the middle of a terminated table the way the move
  names do; the palettes are checked structurally *and* one entry past the end,
  since the table is the player plus every class and something that is not a
  palette has to follow it; and the pic pointers have to address the banked
  window and decompress into a pic of the one size every trainer is drawn at.
- Evolutions and level-up moves are one table read through a table of two-byte
  pointers, and neither half says which species it belongs to, so what is
  checked is the shape: every pointer has to address the banked window, every
  evolution has to open with one of five methods and name a real species, and
  every level-up entry has to be a level from 1 to 100 teaching a real move. Most
  byte values are none of those, so a wrong pointer fails on its first byte. On
  top of that the levels ascend everywhere but Muk, whose list the cartridges
  themselves have out of order, and the total number of evolutions is the same
  known figure in all three games.
- The eight text box borders have no content to check, so they are checked by
  the shape a border has to have: inset from the top of its tile row, corners
  that carry the pattern of the side they hang from, and no two frames the
  same.
- The trainer party table is a second table indexed the same way as the trainer
  classes above, one pointer per class, and it is where the games' individual
  trainers actually live: "LEADER" is the class every gym leader shares, and
  "FALKNER" is stored inside class 1's own entry. Nothing inside a class's bytes
  says where its group ends, so a class's span is bounded by the *next* class's
  pointer, and the walk itself is the check: a span that does not land exactly
  on the next class's start cannot be right, the same argument the evolution
  and learnset table's pointers make. One class in every game shares its
  pointer with the class after it, and reads as an honestly empty group rather
  than a copy of somebody else's; see `RomLayout.EMPTY_TRAINER_CLASS`. On top
  of that the total trainer count is a known figure per game, and both ends of
  the table are content whose answer is known independently: Falkner's level 7
  Pidgey and level 9 Pidgeotto open it, and the last class's first trainer's
  name closes it.
- The trainer attributes table is a fourth trainer table, one fixed seven-byte
  entry per class rather than a pointer, so unlike the party table above there
  is no walk to be the check: what is checked is the shape every entry has to
  have. Two of its five fields are bit flags, and neither may carry a bit past
  what the cartridge defines, which a wrong offset fails almost immediately
  and has to pass 66 or 67 times running, once per class, to slip through by
  chance. On top of that class 1's own entry is content whose answer is known
  independently, the same anchor the class name table has in Falkner's own
  name.
- The trainer DVs table is a fifth trainer table, the same fixed-stride shape
  as the attributes table, but with nothing structural to check: every nibble
  is a legal DV, so a wrong offset produces just as plausible-looking a table
  as a right one would. What settles it is content whose answer is known
  independently at both ends, the same discipline the move and item name
  tables lean on: Falkner opens the table with his own known DVs, and the
  class that closes it (a different one per game, since Crystal alone carries
  MYSTICALMAN) carries its own. Both were confirmed against the entire
  published table, not only the two anchors the runtime check uses: the
  offset was pinned by computing what the whole table's bytes have to be from
  pret's own `TrainerClassDVs` and searching each dump for that exact
  sequence, the same technique the font, the matchup chart and the attributes
  table were found with, and it matched byte for byte across all 66 or 67
  classes in every game.

When you add an offset, add its check. "It produced output" is not evidence.

New offsets were found by searching the cartridge for content whose bytes are
known independently (the encoded string `BULBASAUR`, a species' published base
stats), and then confirming the *structure* against the
[pret](https://github.com/pret) disassemblies, which are the reference for how
these games are laid out. Do not copy an address out of a disassembly and
assume it applies: those are bank:address pairs for a build of the source, and
Gold, Silver and Crystal do not agree.

Graphics can be found the same way, more precisely, because pret keeps them as
PNGs. Encode the reference image to the format the cartridge stores (1bpp for
the font and the borders: one byte per row, bit 7 leftmost) and search the dump
for that exact byte sequence. It matches in one place, which settles the offset
with no guessing, and the section order in the disassembly then predicts where
the neighbouring blobs are, which is a second check for free. Nothing from pret
belongs in this repository; it is a way to locate data in your own dump, not a
source of data to commit.

## Seeing that a decode is right

For anything graphical, look at it. `tools/preview_pics.gd` applies a palette to
the cached indices and writes a PNG:

```bash
godot --headless --path . -s res://tools/preview_pics.gd -- gold /tmp/gold.png front
```

A contact sheet of all 251 species is the fastest correctness check the project
has: a bad decompressor, a wrong tile order, a wrong palette and an off-by-one
in a pointer table all look obviously wrong, and all of them look fine in a
manifest.

`trainers` does the same for the trainer classes, each drawn in its own class
palette, which is where a palette table that has slid by an entry becomes
obvious: the pics stay right and the colours move one class along.

The same tool takes `font` or `frames`, which it folds into rows of sixteen
tiles. That is the shape the charmap describes, so the alphabets, the gaps
between them and the digits at the end can be read off the image directly:

```bash
godot --headless --path . -s res://tools/preview_pics.gd -- crystal /tmp/font.png font
```

Text decodes get the same treatment from `tools/dump_tables.gd`, which prints a
cached table rather than drawing it:

```bash
godot --headless --path . -s res://tools/dump_tables.gd -- gold moves
```

A name table that has slid by a byte still decodes into words, so reading the
output is the check. Cross-check a handful of moves against published power,
accuracy and PP while you are there; the runtime checks pin the ends of a
table, not what is between them.

`learnsets` and `evolutions` are the same idea for the one table whose runtime
check can only prove the shape. Every level and every move number stays in range
whatever a wrong pointer does, so what settles it is reading Bulbasaur's list
back and finding Tackle at 1 and Growl at 4, and reading Eevee's five evolutions
and Tyrogue's three. Both resolve their numbers into names for that reason.

## Seeing the UI without pressing Play

`tools/screenshot.gd` renders a scene to a PNG:

```bash
godot --path . -s res://tools/screenshot.gd -- res://game/main/main.tscn /tmp/shot.png 20
```

An optional trailing `<method> <times> [int arg]` drives the scene before
capturing, so you can photograph a screen mid-interaction rather than only on
its first frame. This briefly opens a real window, because rendering needs a
display, so it cannot run under `--headless`.

Screens are built so this works on them. `pic_viewer.gd` reacts to keys, but
every one of those keys is also a plain method (`next_species`, `toggle_shiny`,
`toggle_back`), so a screen can be photographed in any state without a human at
the keyboard:

```bash
godot --path . -s res://tools/screenshot.gd -- res://game/render/pic_viewer.tscn /tmp/shot.png 20 show_species 1 249
```

`text_viewer.gd` is built the same way, and one of its methods exists only for
this: `finish` reveals the rest of the page at once, so a photograph of a text
box does not depend on how long the capture took to arrive.

```bash
godot --path . -s res://tools/screenshot.gd -- res://game/render/text_viewer.tscn /tmp/shot.png 24 finish 1
```

The battle screen is built the same way, and it is worth photographing in more
than one state: an HP bar changes colour as it empties, and the rule is about
how many pixels are lit rather than how many hit points are left.

```bash
godot --path . -s res://tools/screenshot.gd -- res://game/battle/battle_screen.tscn /tmp/shot.png 24 hurt_player 3
```

`advance` is the same button the player presses, so repeating it fights the
battle: it finishes the message on screen, then steps to the next event, then
takes another turn when there is nothing left to say. Enough of them and one of
the two faints, which is how the whole loop gets looked at without a keyboard.

```bash
godot --path . -s res://tools/screenshot.gd -- res://game/battle/battle_screen.tscn /tmp/shot.png 40 advance 26
```

Keep that property when you add a screen. A handler that only exists inside an
input match statement cannot be driven, and a screen that cannot be driven
cannot be checked without asking someone what they see.

## Pitfalls that cost real time

- **GUT silently skips test scripts that fail to parse.** A broken file shows
  up as a smaller run that still reports green, and the only tell is the script
  count. `test_smoke.gd` loads every script under `game/`, `autoload/`,
  `tests/` and `tools/` explicitly to turn that into a visible failure. Don't
  delete it.
- **A script that fails to parse does not load as null.** `load()` hands back a
  real `GDScript` with its source code attached, no methods on it and nothing
  behind it, so `assert_not_null(load(path))` passes on exactly the file it was
  written to catch. `can_instantiate()` is the question that answers honestly,
  and it is what `test_smoke.gd` asks. Loading with
  `ResourceLoader.CACHE_MODE_IGNORE` also sees it, and re-parses scripts that
  are running at the time, which corrupts them mid-call and takes the VM down
  with an opcode error; don't reach for it.
- **A newly created script is invisible until the editor scans it.** Plain
  `--headless` runs do *not* import new files, so a brand-new `class_name`
  fails with "not declared in the current scope" no matter how many times you
  re-run the tests. After adding any script:

  ```bash
  godot --headless --editor --path . --quit
  ```

  That generates the `.gd.uid` files and updates
  `.godot/global_script_class_cache.cfg`. A missing `.gd.uid` next to a script
  is the tell. Editing an *existing* script needs no scan pass. To rule out a
  real syntax problem: `godot --headless --check-only --script res://path.gd`.
- **Changing scene inside `_ready()` errors.** The tree is still adding
  children, so `change_scene_to_file` tries to remove them mid-pass. Use
  `change_scene_to_file.call_deferred(path)`.
- **A bare `PanelContainer` is transparent.** The default theme draws nothing,
  so a "panel" shows the scene straight through it. Give any modal a
  `theme_override_styles/panel` StyleBoxFlat.
- **A `.tscn` root node with no `script =` line fails quietly.** The scene
  loads and every node resolves; it just does nothing. If a screen is inert,
  check the root kept its script line.
- **JSON has one number type, so everything comes back as a float.** A species
  number written as `1` reads back as `1.0`, and `read["number"] == 1` is
  false. Anything loading the cache must coerce with `int()`; there is a test
  in `test_rom_cache.gd` that pins this down so nobody rediscovers it the hard
  way.
- **GDScript lambdas capture by value.** Assigning to a captured local inside a
  `func():` closure updates the copy, not the original, and the write silently
  vanishes. Append to an Array/Dictionary, or use a method.
- **A closure stored on the signal of an object it captures leaks that
  object.** The cycle is invisible until Godot prints "ObjectDB instances were
  leaked at exit". Connect a method rather than a capturing lambda; that
  warning at the end of a test run is worth chasing.
- Godot 4.8 is a *dev* build. If something behaves oddly, check it against 4.6
  stable before assuming the bug is ours.

## GDScript conventions

- Tabs for indentation (Godot default; don't reformat to spaces).
- Static typing everywhere practical: `var health: int = 10`,
  `func heal(amount: int) -> void:`.
- `snake_case` for variables, functions and files; `PascalCase` for classes and
  nodes.
- No comments explaining *what* code does, only *why*, for non-obvious
  constraints.

## Scenes

`.tscn` and `.tres` are plain text (format 3), so read and edit them directly
like source. Don't hand-invent `uid://` identifiers; Godot regenerates missing
or invalid ones on load, or omit the `uid` field on `ext_resource` lines and
let the editor fill it in.
