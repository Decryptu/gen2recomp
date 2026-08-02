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

The drawing layer is deliberately thin:

| | |
|---|---|
| `render/pic_image.gd` | Colour indices plus a palette to an `Image` |
| `render/gen2_screen.gd` | The 160x144 screen, scaled by a whole number |
| `render/font.gd` | Character codes to glyph tiles, blitted into a buffer |
| `render/text_layout.gd` | A string to the lines and pages a box can show |
| `render/text_box.gd` | The two of them, as a bordered window on the grid |

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
- The eight text box borders have no content to check, so they are checked by
  the shape a border has to have: inset from the top of its tile row, corners
  that carry the pattern of the side they hang from, and no two frames the
  same.

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

Keep that property when you add a screen. A handler that only exists inside an
input match statement cannot be driven, and a screen that cannot be driven
cannot be checked without asking someone what they see.

## Pitfalls that cost real time

- **GUT silently skips test scripts that fail to parse.** A broken file shows
  up as a smaller run that still reports green. `test_smoke.gd` loads every
  script under `game/`, `autoload/`, `tests/` and `tools/` explicitly to turn
  that into a visible failure. Don't delete it.
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
