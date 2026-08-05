# Contributing

Read [the README](../README.md) first. This file records project conventions,
architecture, verification methods, and Godot pitfalls.

## Keep cartridge data out

Never commit a commercial cartridge or anything derived from one: ROMs, `.sav`
files, sprites, text, maps or audio. Three independent layers enforce this:

1. `.gitignore` blocks known extensions, `roms/` and runtime caches.
2. `.githooks/pre-commit` checks staged blobs by extension and rejects any blob
   at least 512 KiB outside `addons/` and `assets/`, catching renamed or
   trimmed dumps. Enable it once per clone:
   `git config core.hooksPath .githooks`.
3. Tests use synthetic files and a known SHA-1 vector, never a real cartridge,
   so they run locally and in CI.

`roms/.gdignore` keeps Godot from importing or exporting that directory, while
development tools can still read it with `FileAccess`. Do not delete it.

## Architecture

### ROM and importer

The ROM layer is node-free and fully headless-testable:

| File | Role |
|---|---|
| `game/rom/rom_registry.gd` | SHA-1 allowlist |
| `game/rom/rom_verifier.gd` | Size filter, chunked SHA-1, lookup |
| `game/rom/rom_file.gd` | Verified in-memory dump and bank addressing |
| `game/rom/rom_header.gd` | Header diagnostics only |

These are `RefCounted` statics. Keep rules separate from content and inject a
`RandomNumberGenerator`; do not use global randomness.

`game/import/` decodes verified ROMs into the `user://` cache:

| File | Role |
|---|---|
| `lz_decompressor.gd` | Cartridge LZ graphics |
| `tile_codec.gd` | 2bpp/1bpp tiles and pic layout |
| `text_codec.gd` | Generation 2 character encoding |
| `palette.gd` | 15-bit BGR colours |
| `rom_layout.gd` | Per-game table locations |
| `rom_cache.gd` | Cache paths, formats and lifecycle |
| `world_services_importer.gd` | Menus, marts, phone records and audio pointer tables |
| `rom_importer.gd` | Orchestration and layout checks |

Decoders take bytes and return data, with no cartridge knowledge, so they can
be tested on small hand-built inputs. `game/data/game_data.gd` is the only
engine-facing cartridge-content API. It alone knows the cache and converts
JSON's single numeric type back to `int`. `game/data/learnset.gd` stays beside
it because a Pokémon can be created outside battle. Do not sort learnsets:

- filling a new Pokémon stops at the first move above its level;
- levelling up reads every entry at the newly reached level.

Muk is out of order in all three games, so these operations intentionally
differ.

`game/save/` owns project saves, not cartridge data. Keep its versioned model,
validator, store and battle adapter scene-free. It validates against `GameData`,
writes through a temporary file, and must not parse original SRAM until a
checksum-aware adapter has been researched and tested against the real layout.
The project world snapshot now owns canonical map, inventory and event state;
the original SRAM adapter remains party-focused. Do not add box or unsupported
cartridge fields before those models are canonical.

### Rendering and text

The drawing layer is intentionally thin:

| File | Role |
|---|---|
| `render/pic_image.gd` | Colour indices plus palette to `Image` |
| `render/gen2_screen.gd` | 160x144 viewport, integer scaling |
| `render/font.gd` | Character codes to glyph tiles |
| `render/text_layout.gd` | Strings to box lines and pages |
| `render/text_box.gd` | Bordered text window |
| `render/battle_tiles.gd` | Hardware-order battle tile page |
| `render/battle_hud.gd` | Status panels on the tile grid |

`Gen2Screen` is a `Control` with a 160x144 `SubViewport`, scaled by an integer;
the surrounding UI uses the window resolution. Project-wide stretch would blur
menus, and fractional scaling resamples 8x8 tiles. Battle rendering is layered
by palette with index 0 transparent, preserving per-tile colours; replace this
with a per-tile-attribute tilemap when the overworld needs one. Keep the
hardware tile numbers in `Gen2BattleTiles`, including deliberate overwritten
font tiles.

Text is tilemapped, not typeset: every glyph is 8x8 and its character byte is
its tile number. Measure with `Gen2Text.encoded_length()`, not
`String.length()`, because apostrophe ligatures and PK/MN occupy two characters
but one glyph. `$7F` is a blank below the font and unknown codes are no-ops.
`Gen2TextLayout` wraps at runtime and honours explicit newlines; the cartridge's
author-time breaks cannot support mod-added text.

### Battle engine

The engine is `RefCounted`, scene-free and deterministic when given a seeded
RNG. Keep integer operations in hardware order, including truncation. In
particular:

- stat-experience square root is a ceiling, so untrained is 1, not 0;
- type damage multiplies one defender type at a time, truncating each step;
- announced effectiveness is a separate tenths accumulator. For example,
  Ember against Fire/Rock deals 6 but reports 2/10. Use
  `GameData.type_matchup` for damage and `type_effectiveness` for the message;
- `Gen2Damage.calculate_with` is deterministic and receives critical/spread;
  `calculate` rolls them. Hand-worked tests should target the deterministic
  function rather than reproducing the implementation's formula;
- Struggle skips STAB and the type chart, and has at least 1 recoil damage;
- accuracy is a byte out of 255. Stored `$FF` never rolls. Accuracy/evasion
  stages use their own rounded table, not the stat-stage table.

The core battle files are:

| File | Role |
|---|---|
| `battle/stats.gd` | Base stats, DVs and stat experience |
| `battle/damage.gd` | Damage, STAB, criticals and spread |
| `battle/accuracy.gd` | Accuracy and evasion |
| `battle/battle_mon.gd` | Pokémon stats, PP, HP and stages |
| `battle/party.gd` | Six-member party and active member |
| `battle/trainer_party.gd` | Cartridge trainer to battle party |
| `battle/status.gd` | One packed status byte |
| `battle/substatus.gd` | Confusion, flinch, charge and recharge flags |
| `battle/turn.gd` | Current move and command state |
| `battle/effect_commands.gd` | Move steps |
| `battle/move_effect.gd` | Effect byte to step-list table |
| `battle/battle.gd` | Order, switches and command execution |
| `battle/ai.gd` | Trainer-class move scoring |
| `battle/experience.gd` | Growth curves, faint value and stat EXP |

Moves are short command programs. `move_effect.gd` is the table,
`effect_commands.gd` the steps, `turn.gd` the handoff, and `battle.gd` only runs
the list. Unimplemented effects fall back to an ordinary attack. A loop inside
one command is fine, as with multi-hit and all-stat changes; changing the turn
runner to jump backward would reproduce hardware implementation rather than
game behavior. Drain and recoil use the formula's uncapped `Gen2Turn.damage`,
not capped HP loss, so a move calculating 50 against 3 HP heals 25 or costs
12/13 as the cartridge does.

Status and substatus are separate. One status is allowed; multiple substatuses
can coexist, with counters on `Gen2BattleMon`. `CHECK_STATUS` follows the
cartridge order: recharge, sleep, freeze, flinch, confusion, paralysis. A
Pokémon that wakes up moves that turn. Secondary effects roll after a hit and
before applying the status. `reset_volatile`, called on switch separately from
`reset_stages`, must clear every flag and counter. Haze resets stages but not
volatiles.

Two-turn moves use `Gen2BattleMon.charged_move`: `move_for` forces the release
move and `Gen2Turn.locked` prevents a second PP spend. Rollout and rampage use
the same forced-move point. Rollout scales 1, 2, 4, 8, 16 before variation,
stops on miss/immunity or its fifth hit, and Defense Curl doubles it. Thrash,
Petal Dance and Outrage continue for their rolled duration, then confuse. A
status interruption cancels chains; rampage remains active after a miss.

Switches happen before priority, so the incoming Pokémon takes the other side's
move. A fainted replacement is a caller policy: the turn stops at
`must_replace` until `send_out`. A full move set during levelling creates the
same deliberate policy hole with `must_learn_move`, `learn_move` and
`decline_move`; the development screen declines automatically.

Trainer details matter:

- trainer classes and individual trainers are separate tables. The class name
  is shared by gym leaders, while the party table stores names and rosters;
- party pointers are walked in class order, not sorted by address. Class 10 is
  intentionally empty because its pointer equals class 11;
- a class owns one packed DVs word for its whole party;
- `Gen2BattleAI` directly finds the lowest scored move with random tie-breaking.
  This matches the cartridge's result, although not its byte-level decrement
  race. It chooses moves only, not switches or items;
- only implemented `AI_Smart` handlers are present. Unsupported effects fall
  back to generic scoring. Weather-sensitive Razor Wind, Solar Beam and Fly
  handlers remain absent;
- trainer experience uses the cartridge's six growth curves. Level 1 is zero
  even for Medium Slow, whose literal formula underflows. Experience is not
  divided among participants, stat experience is, and only the player's side
  receives experience. Participants are those sent out since the current
  opponent arrived, excluding fainted members at award time;
- experience and learning are processed one level at a time. Level-up HP gains
  the difference in max HP rather than refilling.

`Gen2Battle` returns event lists, not strings or final state. The screen must
draw values from the event being shown, since the turn has finished resolving
before the first event is displayed. Keep wording, animation and timing out of
the engine.

## Offsets and runtime checks

`rom_layout.gd` contains absolute positions for each supported 2 MiB dump.
Wrong offsets often decode plausible neighbouring data, so every offset needs a
check and `RomImporter.verify_layout()` must run all checks before decoding.

- Species names check first/last entries, stride and text mapping; base-stat
  entries self-identify by Pokédex number.
- Palettes are structurally checked as 15-bit colours with no species drawn in
  two blacks. Move entries self-identify by animation number and type bytes are
  range-checked.
- Variable-length move/item names are checked at the near and far ends; items
  are also checked at entry four to catch an incorrect walk. Item attributes,
  status-healing rows and HP-healing rows are checked before import. The item
  table retains placeholder names such as `TERU-SAMA` so numbers remain direct
  keys.
- NPC trade records are checked for bounded species, gender and reserved bytes.
  Their 32-byte shape includes the cartridge's 11-byte nickname and OT fields;
  do not reduce those fields to the ten-byte species-name table.
- Font data is checked against the charmap, including blank ranges and the
  character codes that must have ink. Battle HUD bars must have consecutive
  fill levels increasing by two lit pixels per step; borders use the same shape
  checks as text frames; known bar palettes are checked by value.
- The type chart checks sparse type IDs, the three non-neutral multipliers,
  exact `$FE` and `$FF` terminators, and independently known content at both
  ends. The `$FE` rows are the Normal/Fighting versus Ghost entries cancelled
  by Foresight.
- Trainer class name, pic and palette tables cross-check numbering, ends and
  pic pointers. Parties are walked to the next class pointer, including the
  intentional empty class, and checked against known count and endpoints
  (Falkner's level 7 Pidgey/level 9 Pidgeotto and the last class's first name).
  Attribute entries validate defined flag bits and class 1's known bytes.
  DVs have no structural invalid value, so both table ends are anchored to
  known class values; the complete tables were also compared byte-for-byte
  against the published reference.
- Evolution/learnset pointers must address the banked window; methods, species,
  moves and levels must be valid, levels ascend except Muk, and evolution count
  matches the known value. `EVOLVE_STAT` is four bytes, not three.
- Growth rate and base EXP bytes are checked against all 251 species in all
  three games, not just a few plausible values.
- World service tables check their source counts, pointer widths, banked
  addresses, mart terminators, phone record sizes and bounded audio payloads.
  Referenced menu headers are accepted only when their data pointer and
  command-derived shape are valid; malformed candidates in bounded script
  tails are ignored rather than becoming runtime records.

When adding an offset, add its check. Find new data by searching a dump for
independently known bytes, such as an encoded name or published base stats,
then confirm structure against [pret](https://github.com/pret) disassemblies.
Do not copy a disassembly address directly: bank/address pairs differ by game.
For graphics, encode the reference PNG into cartridge 1bpp format (one byte
per row, bit 7 leftmost) and search for the exact sequence. Reference material
locates data, but does not belong in this repository.

## Verify decoded output

For graphics, inspect the output, not only a manifest:

```bash
godot --headless --path . -s res://tools/preview_pics.gd -- gold /tmp/gold.png front
godot --headless --path . -s res://tools/preview_pics.gd -- crystal /tmp/font.png font
```

Species contact sheets expose decompression, tile order, palettes and pointer
errors. `trainers` exposes class palette shifts; `font` and `frames` expose
charmap gaps. Dump tables for text checks:

```bash
godot --headless --path . -s res://tools/dump_tables.gd -- gold moves
```

Cross-check move properties, Bulbasaur's Tackle/Growl, Eevee's five
evolutions, Tyrogue's three, and growth values against published data. The
runtime checks prove shape and endpoints, not every interior value.

## Inspect the UI without Play

`tools/screenshot.gd` renders a scene to PNG and cannot be headless because it
opens a window:

```bash
godot --path . -s res://tools/screenshot.gd -- res://game/main/main.tscn /tmp/shot.png 20
godot --path . -s res://tools/screenshot.gd -- res://game/render/pic_viewer.tscn /tmp/shot.png 20 show_species 1 249
godot --path . -s res://tools/screenshot.gd -- res://game/render/text_viewer.tscn /tmp/shot.png 24 finish 1
godot --path . -s res://tools/screenshot.gd -- res://game/battle/battle_screen.tscn /tmp/shot.png 24 hurt_player 3
godot --path . -s res://tools/screenshot.gd -- res://game/battle/battle_screen.tscn /tmp/shot.png 40 advance 26
```

An optional `<method> <times> [int arg]` drives a scene before capture. Keep
state changes as callable methods, not only input branches, so every screen is
automatically inspectable. `advance` completes the visible message, advances
events, and starts the next turn when needed.

## Pitfalls

- GUT silently skips scripts that fail to parse. `test_smoke.gd` explicitly
  loads every script under `game/`, `autoload/`, `tests/` and `tools/`, and uses
  `can_instantiate()`, not `assert_not_null(load(path))`.
- Do not use `ResourceLoader.CACHE_MODE_IGNORE` on a running script: reparsing
  it during a call can corrupt the VM. Use `godot --headless --check-only
  --script res://path.gd` for syntax checks.
- New scripts need an editor scan; plain headless runs do not import them:

  ```bash
  godot --headless --editor --path . --quit
  ```

  This generates `.gd.uid` files and updates the script-class cache. Existing
  script edits do not need the scan.
- Defer `change_scene_to_file` from `_ready()` with
  `change_scene_to_file.call_deferred(path)`.
- A bare `PanelContainer` is transparent; give modals a
  `theme_override_styles/panel` `StyleBoxFlat`.
- A scene root without its `script =` line loads but does nothing.
- JSON numbers return as floats; cache readers must use `int()`.
- GDScript closures capture locals by value. Mutate an Array/Dictionary or use
  a method instead. A signal closure capturing its source can also leak it;
  connect a method.
- Godot 4.8 is a dev build. Compare odd behavior with 4.6 stable before
  blaming project code.

## Style and scenes

- Tabs for indentation; static typing where practical.
- `snake_case` for variables, functions and files; `PascalCase` for classes
  and nodes.
- Comment only non-obvious constraints, not what code plainly does.
- `.tscn` and `.tres` are plain text format 3. Edit them directly. Do not
  invent `uid://` values; omit invalid `uid` fields and let Godot regenerate
  them.
