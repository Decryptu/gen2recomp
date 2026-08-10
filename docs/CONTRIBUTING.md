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

Raw cartridge byte runs do not go into JSON: a decimal array costs about four
bytes on disk per cartridge byte and about twenty-six resident once parsed into
an Array of Variants, which made scripts, text and audio 96 MB of a 100 MB
cache. Write them with `RomCache.write_payload_map()` when the run is a whole
value in a pointer map, or `RomCache.write_section()` when it is a `bytes`
field of a record; both move the bytes into a `.bin` blob and leave an
`[offset, length]` span in the JSON, which `GameData` reads back as a
`PackedByteArray` under `bytes`. Only a named `bytes` field is moved: a mart
list or an encounter rate is a small number array, not a payload.

World sections load on first use. The launcher, the pic viewer and a battle
never read scripts, text or audio, and eagerly reading them made listing three
games cost more than entering one.

Decoders take bytes and return data, with no cartridge knowledge, so small
hand-built inputs can test them. `game/data/game_data.gd` is the sole
engine-facing cartridge-content API; it owns the cache and converts JSON's
single numeric type back to `int`. `game/data/learnset.gd` stays beside it
because Pokémon can be created outside battle. Do not sort learnsets: filling a
new Pokémon stops at the first move above its level, while levelling reads every
entry at the newly reached level, and Muk is out of order in all three games.

`game/save/` owns project saves, not cartridge data. Keep its versioned model,
validator, store and battle adapter scene-free; it validates against `GameData`
and writes through a temporary file. Format 2 owns a fixed fourteen-box,
twenty-slot PC model, migrating from format 1 without inventing a world
snapshot. Party-owned world transactions update a candidate save and live
snapshot together and restore both on a failed write; `Gen2SaveStorage` applies
the same boundary to explicit box transfers, and `box_screen.gd` owns selection
and presentation only. Box names, current-box UI state and cartridge SRAM
placement stay outside the model until their source ownership is verified; the
checksum-aware SRAM adapter is a separate boundary and stays party-focused for
the same reason.

`game/world/` separates request resolution from UI. `world_api.gd`,
`world_host.gd` and scene-free service helpers validate imported map records,
transactions and script result boundaries; `world_service_screen.gd` owns
labels, selection and input. Map reloads clear the source first eight temporary
event flags; permanent event flags and engine flags stay separate. The script
runner keeps the source yes/no result order and commits clock/daylight-saving
changes only after the corresponding host prompt completes. Menus follow cached
vertical or two-dimensional records. Mart dialog variants and prices come from
imported lists, purchases enforce the source 99-item stack limit before
candidate-save validation, Crystal rooftop selection reads the persisted Hall of
Fame engine flag, and the Goldenrod Underground bargain shop sells one of each
item per visit and records the daily merchant-closed flag. Phone presentation
lists contacts and dispatches calls, with the world runner executing the
imported caller/callee script at the same transaction boundary. Audio stays
behind bounded decoder, renderer and player layers.

`world_start_menu.gd` models `engine/menus/start_menu.asm`'s item list: source
Pokedex/Pokemon/Pokegear gating and the `STATICMENU_WRAP` cursor.
`pokedex.gd` models `engine/pokedex/pokedex.asm`'s listing: the three orderings
`Pokedex_OrderMonsByMode` builds, `.FindLastSeen`'s listing end, `.PrintEntry`'s
per-row decision and `Pokedex_ListingHandleDPadInput`'s cursor and paging walk.
It also models `Pokedex_SearchForMons`, whose two type rows wrap differently and
whose passes filter the listing in place, so two types narrow rather than widen.
`pokedex_screen.gd` is its listing, entry, OPTION, SEARCH and results states;
the entry's two measurements go through `_PrintNum`'s own blanking rather than a
format string.
`world_options_menu.gd` models `engine/menus/options_menu.asm` over
[Gen2Options], seven value rows plus CANCEL, and leaves persistence to
`Gen2OptionsStore`. `trainer_card.gd` and `render/trainer_card_page.gd` are
`engine/menus/trainer_card.asm`: the page keeps the cartridge's own VRAM window
and writes tile numbers into a map, since the card is a tilemap screen rather
than a text one, and `trainer_card_screen.gd` colours it through
`_CGB_TrainerCard`'s palettes and draws the badge objects over it.
`world_pack.gd` groups owned items into the four cartridge pockets by the item
type byte `GameData` imports under the confusingly-named `pocket` field. It is
presentation only: item counts stay a flat map on `Gen2WorldState` and pocket
capacities are not enforced. `start_menu_screen.gd` is the overlay, owning Pack,
a Save confirmation and the OPTION menu as internal modes the way
`world_service_screen.gd` owns a mart mode, and delegating Pokemon and Pokegear
to the existing screens. `Gen2PartyScreen` and `Gen2BoxScreen` share one
embedded-mode shape, a `set_context(..., embedded)` flag and a `closed(result)`
signal, so the overworld can stack them above the running world instead of
tearing it down with `change_scene_to_file`.

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
and world state through `Gen2WorldAPI`, both scene-free. [MODS.md](MODS.md) has
the contract and why a renderer must not write world state.

### Rendering and text

| File | Role |
|---|---|
| `render/pic_image.gd` | Colour indices plus palette to `Image` |
| `render/gen2_screen.gd` | 160x144 viewport and integer scaling |
| `render/game_frame.gd` | Where the screen and the on-screen controller sit |
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

### Input and controls

Every screen that reads the cartridge's controls speaks one vocabulary. Never
match a keycode in a screen: match a `Gen2Button`.

| File | Role |
|---|---|
| `input/button.gd` | The eight hardware buttons and their actions |
| `input/input_actions.gd` | Bindings as data, and installing them in the `InputMap` |
| `input/input_device.gd` | Which device an event came from |
| `input/touch_layout.gd` | Where the on-screen groups sit, and what a point presses |
| `input/touch_pad.gd` | The on-screen controller |
| `input/tap_gesture.gd` | The taps that bring hidden controls back |
| `input/focus_guard.gd` | The first control a pad lands on |
| `input/debug_keys.gd` | Whether the development shortcuts are live |
| `autoload/input_runtime.gd` | The live scheme, the active device, the controller stack |

A screen reads a press with `Gen2Button.pressed_in(event)` and a held direction
with `Gen2InputRuntime.instance().held_direction()`, polled rather than driven by
key repeat. An embedded host takes `handle_button(button)`; there is no keycode
entry point, so a test presses a button rather than a key.

Reach the runtime with `Gen2InputRuntime.instance()`, not the `InputRuntime`
global: a script handed to `-s` compiles before the tree that owns the autoloads
exists, so a preview tool naming a screen by type would fail to load it.
`Gen2WorldScreen` reaches GameRuntime by path for the same reason.

A key binds by physical keycode, so a d-pad on WASD stays under the same four
fingers on a layout that spells them differently; describe one with
`Gen2InputActions.describe()`, which asks the platform what is printed there.

Anything that is not one of the eight buttons goes behind
`Gen2DebugKeys.enabled()`, and keeps a public method beside it so the preview
tools reach the same path without a key press.

### Battle engine

The engine is scene-free, deterministic with a seeded RNG and keeps integer
operations in hardware order, including truncation:

- stat-experience square root is a ceiling, so untrained is 1, not 0;
- type damage multiplies one defender type at a time, truncating each step;
- announced effectiveness is a separate tenths accumulator: Ember against
  Fire/Rock deals 6 but reports 2/10. Use `GameData.type_matchup` for damage
  and `type_effectiveness` for the message;
- the formula is four steps, not one: `Gen2Damage.damage_stats`, `damage_calc`,
  `stab_damage` and `apply_variation`, which are the cartridge's own commands and
  are what `effect_commands.gd` runs, because Present, Triple Kick, Fury Cutter
  and Rollout each write something between two of them.
  `Gen2Damage.calculate_with` composes all four and receives critical/spread
  deterministically; `calculate` rolls them. Hand-worked tests should target
  `calculate_with`;
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
runner. Unimplemented effects fall back to an ordinary attack;
`Gen2MoveEffect.is_written` is what tells the two apart. A step that needs to
write over the move's own power or type writes `Gen2Turn.power_override` and
`type_override` rather than the move Dictionary, which is `GameData`'s cached
row and not a copy. Loops stay inside
one command, as with multi-hit and all-stat changes. Drain and recoil use
uncapped `Gen2Turn.damage`, not capped HP loss, so a move calculating 50 against
3 HP heals 25 or costs 12/13 as the cartridge does.

Status and substatus are separate. One status is allowed; several substatuses
and counters live on `Gen2BattleMon`. `CHECK_STATUS` order is recharge, sleep,
freeze, flinch, confusion, paralysis; waking up still permits movement. Snore
and Sleep Talk are used through a sleep and Flame Wheel and Sacred Fire through
a freeze, all four by move number; the thaw itself is the `defrost` step in the
two fire moves' own lists, not the status check.
Secondary effects roll after a hit and before applying status. `reset_volatile`
on switch clears every flag/counter separately from `reset_stages`; Haze resets
stages but not volatiles.

Two-turn moves use `Gen2BattleMon.charged_move`; `move_for` forces release and
`Gen2Turn.locked` prevents a second PP spend. Rollout/rampage use the same
forced-move point. Rollout scales 1, 2, 4, 8, 16 before variation, stops on
miss/immunity or its fifth hit, and doubles with Defense Curl. Thrash, Petal
Dance and Outrage continue for their rolled duration, then confuse. A status
interruption cancels chains; rampage remains active after a miss.

Fury Cutter's and Protect's counters are chains of a different kind: they are
kept only while the move feeding them is the move being used, so
`Gen2Battle._reset_action_counters` empties them on every other action, which is
what `ParsePlayerAction` and `ParseEnemyAction` do. Protect, Detect and Endure
share one counter. `Gen2Battle.opponent_went_first` is `CheckOpponentWentFirst`,
and each action runs inside an open/close pair that clears the mover's own
Destiny Bond in front and the opponent's Protect, Endure and Destiny Bond behind;
the player's pair runs on every action and the enemy's only on a move.

`Gen2Battle.send_out` is the one entrance, and a command can call it: Whirlwind
and Roar drag the target's side out through it, and `BreakAttraction` inside it
clears the flag on both sides rather than only the incoming Pokémon's. In a wild
battle the same two moves end the battle instead, through
`Gen2Battle.force_out`, which is `wForcedSwitch` and `SetBattleDraw` together
and leaves both parties standing with no winner.

Switches happen before priority, so the incoming Pokémon takes the other
side's move. A fainted replacement is caller policy: the turn stops at
`must_replace` until `send_out`. A full moveset similarly uses
`must_learn_move`, `learn_move` and `decline_move`; the development screen
declines automatically.

Trainer details:

- trainer classes and individual trainers are separate tables. Class names are
  shared by gym leaders; parties store names and rosters, and their pointers are
  walked in class order, not sorted. Class 10 is intentionally empty because its
  pointer equals class 11. One packed DVs word covers each class's whole party;
- `Gen2BattleAI` picks the lowest-scored move with random tie-breaking, matching
  the result rather than the byte-level decrement race, and switches and uses
  items through `Gen2AISwitch` and `Gen2AIItems`. Only implemented `AI_Smart`
  handlers exist; unsupported effects use generic scoring, and Razor Wind and the
  Fly handlers are absent;
- experience uses six growth curves and level 1 is zero, even for Medium Slow,
  whose literal formula underflows. Experience and stat experience are both
  divided among participants, since the division lands on the base EXP byte
  inside the same block as the base stats, and only the player side receives it.
  Participants were sent out since the current opponent arrived, excluding
  members fainted at award time. Levels process one at a time, and a level-up
  adds the max-HP difference rather than refilling.

`Gen2Battle` returns event lists, not strings or final state. The screen draws
the event being shown because the turn has already resolved before display;
keep wording, animation and timing out of the engine.

## Offsets and runtime checks

`rom_layout.gd` contains absolute positions for each supported 2 MiB dump.
Because wrong offsets can decode plausible neighboring data,
`RomImporter.verify_layout()` must run every check before decoding:

| Data | Checks |
|---|---|
| Species | First/last names, stride and text mapping; base stats self-identify by Pokédex number |
| Palettes | Structurally 15-bit colours, no species drawn in two blacks |
| Moves | Entries self-identify by animation number; type bytes range-checked |
| Names | Variable-length move/item names near and far; items also check entry four. Item attributes, status-healing and HP-healing rows. Placeholders such as `TERU-SAMA` stay direct item keys |
| NPC trades | Bounded species, gender and reserved bytes. The 32-byte shape includes the 11-byte nickname and OT fields, not the ten-byte species name table |
| Font and HUD | Charmap, blank ranges and required ink. HUD bar fill levels increase by two lit pixels; borders use text frame shape checks and bar palettes are checked by value |
| Type chart | Sparse IDs, the three non-neutral multipliers, exact `$FE`/`$FF` terminators and known content at both ends. `$FE` rows are the Normal/Fighting versus Ghost entries cancelled by Foresight |
| Trainers | Class name/pic/palette numbering, ends and pic pointers. Parties walk to the next class pointer, including empty class 10, checking counts and endpoints (Falkner's level 7 Pidgey and level 9 Pidgeotto, the last class's first name). Attributes validate defined flags and class 1 bytes; DVs anchor both ends and match the published tables byte-for-byte |
| Evolutions, learnsets | Pointers address the banked window; methods, species, moves and levels valid, levels ascending except Muk, evolution count known. `EVOLVE_STAT` is four bytes, not three |
| Growth | Growth rate and base EXP for all 251 species in all three games |
| World services | Source counts, pointer widths, banked addresses, mart terminators, phone sizes, non-trainer caller-name pointer tables, packed audio headers, cry pointers, shared waves, drumkits and bounded bank-window payloads. Menu headers need valid data pointers and command-derived shape; the script collector validates `phonecall` text pointers, leaves `memcall`/`memjump` to runtime memory snapshots, and ignores malformed candidates |

When adding an offset, add its check. Find data by searching a dump for
independently known bytes, such as an encoded name or published base stats,
then confirm structure against [pret](https://github.com/pret) disassemblies.
Do not copy an address directly: bank/address pairs differ by game. For
graphics, encode the reference PNG as cartridge 1bpp, one byte per row with
bit 7 leftmost, and search for the exact sequence. Reference material locates
data but does not belong in this repository.

## Verify decoded output

Runtime checks prove shape and endpoints, not every interior value, so inspect
graphics and tables too:

```bash
godot --headless --path . -s res://tools/preview_pics.gd -- gold /tmp/gold.png front
godot --headless --path . -s res://tools/preview_pics.gd -- crystal /tmp/font.png font
godot --headless --path . -s res://tools/dump_tables.gd -- gold moves
```

Species contact sheets expose decompression, tile order, palette and pointer
errors; `trainers` exposes class palette shifts; `font` and `frames` expose
charmap gaps. Cross-check move properties, Bulbasaur's Tackle/Growl, Eevee's
five evolutions, Tyrogue's three and growth values against published data.

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
godot --path . --resolution 480x960 -s res://tools/preview_controls.gd -- /tmp/portrait.png
godot --path . --resolution 1152x648 -s res://tools/preview_controls.gd -- /tmp/landscape.png
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
- `.tscn` and `.tres` are plain-text format 3. Edit them directly. Do not invent
  `uid://` values; omit invalid fields and let Godot regenerate them.

## Writing

Comments and docs earn their length. Comment non-obvious constraints, source
quirks and the disassembly symbol a rule came from; do not restate what the code
says or argue at length that a decision was right. A source symbol plus a
one-line reason is the target.

State each fact once, where it is enforced, and link rather than repeat: source
findings and constants near the code, contracts in `docs/`. When something
changes, replace the old text instead of appending a correction to it.
