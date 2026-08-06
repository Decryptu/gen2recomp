# Contributing

Read [the README](../README.md) first. This file records project conventions,
architecture, verification methods and Godot pitfalls.

## Keep cartridge data out

Never commit a commercial cartridge or derived data: ROMs, `.sav` files,
sprites, text, maps or audio. Three layers enforce this:

1. `.gitignore` blocks known extensions, `roms/` and runtime caches.
2. `.githooks/pre-commit` checks staged blobs by extension and rejects any blob
   at least 512 KiB outside `addons/` and `assets/`, catching renamed or
   trimmed dumps. Enable it once per clone:
   `git config core.hooksPath .githooks`.
3. Tests use synthetic files and a known SHA-1 vector, never a real cartridge,
   so they run locally and in CI.

`roms/.gdignore` keeps Godot from importing or exporting that directory while
tools can still read it with `FileAccess`. Do not delete it.

## Architecture

### ROM and importer

The ROM layer is node-free and headless-testable. These `RefCounted` statics
keep rules separate from content and receive an injected
`RandomNumberGenerator`, never global randomness:

| File | Role |
|---|---|
| `game/rom/rom_registry.gd` | SHA-1 allowlist |
| `game/rom/rom_verifier.gd` | Size filter, chunked SHA-1 and lookup |
| `game/rom/rom_file.gd` | Verified in-memory dump and bank addressing |
| `game/rom/rom_header.gd` | Header diagnostics only |

`game/import/` decodes verified ROMs into `user://`:

| File | Role |
|---|---|
| `lz_decompressor.gd` | Cartridge LZ graphics |
| `tile_codec.gd` | 2bpp/1bpp tiles and pic layout |
| `text_codec.gd` | Generation 2 character encoding |
| `palette.gd` | 15-bit BGR colours |
| `rom_layout.gd` | Per-game table locations |
| `rom_cache.gd` | Cache paths, formats, payload blobs and lifecycle |
| `world_services_importer.gd` | Menus, marts, phone records, audio pointers, cries and shared waveforms |
| `rom_importer.gd` | Orchestration and layout checks |

Raw cartridge byte runs do not go into JSON. A decimal array costs about four
bytes on disk per cartridge byte and about twenty-six resident once parsed into
an Array of Variants, which made scripts, text and audio 96 MB of a 100 MB
cache. Write them with `RomCache.write_payload_map()` when the run is a whole
value in a pointer map, or `RomCache.write_section()` when it is a `bytes`
field of a record; both move the bytes into a `.bin` blob and leave an
`[offset, length]` span in the JSON. `GameData` reads the blob as a
`PackedByteArray` and hands the bytes back under `bytes`. Only a named `bytes`
field is moved: plenty of cached arrays are small numbers without being
payloads, and a mart list or an encounter rate must stay an array.

World sections load on first use. The launcher, the pic viewer and a battle
never read scripts, text or audio, and eagerly reading them made listing three
games cost more than entering one.

Decoders take bytes and return data, with no cartridge knowledge, so small
hand-built inputs can test them. `game/data/game_data.gd` is the sole
engine-facing cartridge-content API; it owns the cache and converts JSON's
single numeric type back to `int`. `game/data/learnset.gd` stays beside it
because Pokémon can be created outside battle. Do not sort learnsets:

- new-Pokémon filling stops at the first move above its level;
- levelling reads every entry at the newly reached level.

Muk is out of order in all three games, so these operations intentionally
differ.

`game/save/` owns project saves, not cartridge data. Keep its versioned model,
validator, store and battle adapter scene-free. It validates against
`GameData` and writes through a temporary file. Project save format 2 owns a
fixed fourteen-box, twenty-slot PC model, with migration from format 1 that
does not invent a world snapshot. Party-owned world transactions must update a
candidate save and live snapshot together, then restore both on a failed write.
`Gen2SaveStorage` applies the same candidate, validator and temporary-file
boundary to explicit party-to-box and box-to-party transfers; `box_screen.gd`
owns selection and presentation only. Keep box names, current-box UI state and
cartridge SRAM placement outside the model until their source ownership is
verified.
The original SRAM adapter is a separate, checksum-aware boundary and remains
party-focused until cartridge box ownership and layout are explicitly
researched.

`game/world/` separates request resolution from UI. `world_api.gd`,
`world_host.gd` and scene-free service helpers validate imported map records,
transactions and script result boundaries; `world_service_screen.gd` owns
labels, selection and input. Map reloads clear the source first eight temporary event flags, while
permanent event flags and engine flags remain separate. The script runner keeps
the source yes/no result order and commits clock/daylight-saving changes only
after the corresponding host prompt completes. Menu layout and
cursor behavior follow cached vertical or two-dimensional records. Mart dialog
variants and prices come from imported source lists, and purchases enforce the
source 99-item stack limit before passing candidate-save validation to writeback.
Crystal rooftop selection reads the persisted Hall of Fame engine flag. The
Goldenrod Underground bargain shop is opened by its imported Monday morning
script, sells one of each item per visit, and records the source daily
merchant-closed flag after a purchase.
Phone presentation lists registered
contacts, dispatches outgoing calls and confirms pending host requests; the world
runner executes the imported caller/callee script at the same transaction
boundary. Audio stays behind verified bounded decoder,
renderer and player layers, with imported records validated before success.

### Audio

| File | Role |
|---|---|
| `audio/gen2_audio_decoder.gd` | Bounded Gen II command streams to event tracks |
| `audio/gen2_audio_renderer.gd` | Deterministic event tracks to `AudioStreamWAV` |
| `audio/gen2_audio_player.gd` | Music/effect players, caching and fades |

`Gen2WorldAudioHost` composes these layers. The decoder stays independent of
scene nodes and audio devices so synthetic records can test headers, pointers,
loops, timing and truncation. The renderer is deterministic and bounded; do
not turn unsupported modulation into an unbounded stream or claim byte-level
hardware fidelity.

### Mods

`game/mods/mod_manifest.gd` validates a mod's `mod.json` without running any of
it; `game/mods/mod_host.gd` is the registry a mod is handed. The world screen
constructs its renderer through the host, so a registered renderer replaces the
view without the screen knowing what it draws with. Keep mods away from scene
nodes and engine internals: a mod reaches cartridge content through `GameData`
and world state through `Gen2WorldAPI`, both scene-free. See
[MODS.md](MODS.md) for the contract and why a renderer must not write world
state.

### Rendering and text

| File | Role |
|---|---|
| `render/pic_image.gd` | Colour indices plus palette to `Image` |
| `render/gen2_screen.gd` | 160x144 viewport and integer scaling |
| `render/font.gd` | Character codes to glyph tiles |
| `render/text_layout.gd` | Strings to box lines and pages |
| `render/text_box.gd` | Bordered text window |
| `render/battle_tiles.gd` | Hardware-order battle tile page |
| `render/battle_hud.gd` | Status panels on the tile grid |

`Gen2Screen` is a `Control` with a 160x144 `SubViewport` at integer scale;
surrounding UI uses window resolution. Project-wide stretch blurs menus and
fractional scale resamples 8x8 tiles. Battle rendering layers palettes with
index 0 transparent; use per-tile attributes when the overworld needs them.
Keep hardware tile numbers in `Gen2BattleTiles`, including deliberate
overwritten font tiles.

Text is tilemapped, not typeset: glyphs are 8x8 and the character byte is the
tile number. Measure with `Gen2Text.encoded_length()`, not `String.length()`:
apostrophe ligatures and PK/MN take two characters but one glyph. `$7F` is a
blank below the font and unknown codes are no-ops. Runtime wrapping honors
explicit newlines because cartridge author-time breaks cannot support mod text.

### Battle engine

The engine is scene-free, deterministic with a seeded RNG and keeps integer
operations in hardware order, including truncation:

- stat-experience square root is a ceiling, so untrained is 1, not 0;
- type damage multiplies one defender type at a time, truncating each step;
- announced effectiveness is a separate tenths accumulator: Ember against
  Fire/Rock deals 6 but reports 2/10. Use `GameData.type_matchup` for damage
  and `type_effectiveness` for the message;
- `Gen2Damage.calculate_with` receives critical/spread deterministically;
  `calculate` rolls them. Hand-worked tests should target the former;
- Struggle skips STAB and the type chart and has at least 1 recoil damage;
- accuracy is a byte out of 255; stored `$FF` never rolls. Accuracy/evasion
  stages use their own rounded table, not the stat-stage table.

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

Moves are command programs: `move_effect.gd` is the table,
`effect_commands.gd` the steps, `turn.gd` the handoff and `battle.gd` the
runner. Unimplemented effects fall back to an ordinary attack. Loops remain
inside one command, as with multi-hit and all-stat changes. Drain and recoil
use uncapped `Gen2Turn.damage`, not capped HP loss, so a move calculating 50
against 3 HP heals 25 or costs 12/13 as the cartridge does.

Status and substatus are separate. One status is allowed; several substatuses
and counters live on `Gen2BattleMon`. `CHECK_STATUS` order is recharge, sleep,
freeze, flinch, confusion, paralysis; waking up still permits movement.
Secondary effects roll after a hit and before applying status. `reset_volatile`
on switch clears every flag/counter separately from `reset_stages`; Haze resets
stages but not volatiles.

Two-turn moves use `Gen2BattleMon.charged_move`; `move_for` forces release and
`Gen2Turn.locked` prevents a second PP spend. Rollout/rampage use the same
forced-move point. Rollout scales 1, 2, 4, 8, 16 before variation, stops on
miss/immunity or its fifth hit, and doubles with Defense Curl. Thrash, Petal
Dance and Outrage continue for their rolled duration, then confuse. A status
interruption cancels chains; rampage remains active after a miss.

Switches happen before priority, so the incoming Pokémon takes the other
side's move. A fainted replacement is caller policy: the turn stops at
`must_replace` until `send_out`. A full moveset similarly uses
`must_learn_move`, `learn_move` and `decline_move`; the development screen
declines automatically.

Trainer details:

- trainer classes and individual trainers are separate tables; class names are
  shared by gym leaders, while parties store names and rosters;
- party pointers are walked in class order, not sorted. Class 10 is intentionally
  empty because its pointer equals class 11;
- one packed DVs word belongs to each class's whole party;
- `Gen2BattleAI` chooses the lowest-scored move with random tie-breaking. This
  matches the result, not the byte-level decrement race, and chooses no
  switches/items;
- only implemented `AI_Smart` handlers exist. Unsupported effects use generic
  scoring; weather-sensitive Razor Wind, Solar Beam and Fly remain absent;
- trainer experience uses six growth curves. Level 1 is zero, even for Medium
  Slow, whose literal formula underflows. Experience is not divided among
  participants, stat experience is, and only the player side receives it.
  Participants were sent out since the current opponent arrived, excluding
  fainted members at award time;
- experience and learning process one level at a time. Level-up HP gains the
  max-HP difference rather than refilling.

`Gen2Battle` returns event lists, not strings or final state. The screen draws
the event being shown because the turn has already resolved before display;
keep wording, animation and timing out of the engine.

## Offsets and runtime checks

`rom_layout.gd` contains absolute positions for each supported 2 MiB dump.
Because wrong offsets can decode plausible neighboring data,
`RomImporter.verify_layout()` must run every check before decoding:

- species names check first/last entries, stride and text mapping; base stats
  self-identify by Pokédex number;
- palettes are structurally checked as 15-bit colours, with no species drawn in
  two blacks; move entries self-identify by animation number and type bytes are
  range-checked;
- variable-length move/item names are checked near and far; items also check
  entry four. Item attributes, status-healing rows and HP-healing rows are
  checked before import. Keep placeholder names such as `TERU-SAMA` as direct
  item keys;
- NPC trades check bounded species, gender and reserved bytes. Their 32-byte
  shape includes the 11-byte nickname and OT fields, not the ten-byte species
  name table;
- font data checks the charmap, blank ranges and required ink. HUD bars must
  have consecutive fill levels increasing by two lit pixels; borders use text
  frame shape checks and known bar palettes are checked by value;
- the type chart checks sparse IDs, the three non-neutral multipliers, exact
  `$FE`/`$FF` terminators and known content at both ends. `$FE` rows are the
  Normal/Fighting versus Ghost entries cancelled by Foresight;
- trainer class name/pic/palette tables cross-check numbering, ends and pic
  pointers. Parties walk to the next class pointer, including empty class 10,
  and check counts/endpoints including Falkner's level 7 Pidgey and level 9
  Pidgeotto and the last class's first name. Attributes validate defined flags
  and class 1 bytes. DVs anchor both ends to known values; full tables match
  the published reference byte-for-byte;
- evolution/learnset pointers address the banked window; methods, species,
  moves and levels are valid, levels ascend except Muk, and evolution count is
  known. `EVOLVE_STAT` is four bytes, not three;
- growth rate and base EXP bytes are checked for all 251 species in all three
  games;
- world services check source counts, pointer widths, banked addresses, mart
  terminators, phone sizes, non-trainer caller-name pointer tables, packed audio
  headers, cry pointers, shared waves, drumkits and bounded bank-window payloads.
  Menu headers require valid data pointers and command-derived shape; the script
  collector validates `phonecall` text pointers and leaves `memcall`/`memjump`
  addresses to explicit runtime memory snapshots. Malformed bounded-script
  candidates are ignored.

When adding an offset, add its check. Find data by searching a dump for
independently known bytes, such as an encoded name or published base stats,
then confirm structure against [pret](https://github.com/pret) disassemblies.
Do not copy an address directly: bank/address pairs differ by game. For
graphics, encode the reference PNG as cartridge 1bpp, one byte per row with
bit 7 leftmost, and search for the exact sequence. Reference material locates
data but does not belong in this repository.

## Verify decoded output

Inspect graphics, not only manifests:

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
evolutions, Tyrogue's three and growth values against published data. Runtime
checks prove shape and endpoints, not every interior value.

## Inspect the UI without Play

`tools/screenshot.gd` renders a scene to PNG and cannot be headless because it
opens a window:

```bash
godot --path . -s res://tools/screenshot.gd -- res://game/main/main.tscn /tmp/shot.png 20
godot --path . -s res://tools/screenshot.gd -- res://game/render/pic_viewer.tscn /tmp/shot.png 20 show_species 1 249
godot --path . -s res://tools/screenshot.gd -- res://game/render/text_viewer.tscn /tmp/shot.png 24 finish 1
godot --path . -s res://tools/screenshot.gd -- res://game/battle/battle_screen.tscn /tmp/shot.png 24 hurt_player 3
godot --path . -s res://tools/screenshot.gd -- res://game/battle/battle_screen.tscn /tmp/shot.png 40 advance 26
godot --path . -s res://tools/preview_world_services.gd -- /tmp/world-mart.png
```

An optional `<method> <times> [int arg]` drives a scene before capture. Keep
state changes as callable methods, not only input branches, so screens remain
inspectable. `advance` completes the visible message, advances events and
starts the next turn when needed.

## Pitfalls

- GUT silently skips scripts that fail to parse. `test_smoke.gd` loads every
  script under `game/`, `autoload/`, `tests/` and `tools/` and calls
  `can_instantiate()`, not only `assert_not_null(load(path))`.
- Do not use `ResourceLoader.CACHE_MODE_IGNORE` on a running script; reparsing
  it during a call can corrupt the VM. Use
  `godot --headless --check-only --script res://path.gd` for syntax checks.
- New scripts need an editor scan; plain headless runs do not import them:

  ```bash
  godot --headless --editor --path . --quit
  ```

  This creates `.gd.uid` files and updates the script-class cache; existing
  script edits do not need it.
- Defer `_ready()` scene changes with `change_scene_to_file.call_deferred(path)`.
- A bare `PanelContainer` is transparent; give modals a
  `theme_override_styles/panel` `StyleBoxFlat`.
- A scene root without its `script =` line loads but does nothing.
- JSON numbers return as floats; cache readers must use `int()`.
- GDScript closures capture locals by value. Mutate an Array/Dictionary or use
  a method instead. A signal closure capturing its source can leak it; connect
  a method.
- Godot 4.8 is a dev build. Compare odd behavior with 4.6 stable before
  blaming project code.

## Style and scenes

- Tabs for indentation; static typing where practical.
- `snake_case` for variables, functions and files; `PascalCase` for classes and
  nodes.
- Comment only non-obvious constraints.
- `.tscn` and `.tres` are plain-text format 3. Edit them directly. Do not invent
  `uid://` values; omit invalid fields and let Godot regenerate them.
