# Contributing

Read [the README](../README.md) first. This file holds the rules and the traps.
It does not describe the architecture: every source finding, constant and
contract lives next to the code that enforces it, and a second copy here would
only go stale.

## Keep cartridge data out

Never commit a commercial cartridge or derived data: ROMs, `.sav` files,
sprites, text, maps or audio. Three layers enforce it:

1. `.gitignore` blocks known extensions, `roms/` and runtime caches.
2. `.githooks/pre-commit` checks staged blobs by extension and rejects any blob
   at least 512 KiB outside `addons/` and `assets/`, catching renamed or
   trimmed dumps. Enable once per clone: `git config core.hooksPath .githooks`.
3. Tests use synthetic files and a known SHA-1 vector, never a real cartridge.

`roms/.gdignore` keeps Godot from importing or exporting that directory while
tools still read it with `FileAccess`. Do not delete it.

## Map

| Path | Owns |
|---|---|
| `game/rom/` | SHA-1 allowlist, verification, bank addressing. Node-free statics |
| `game/import/` | Decoders and the `user://` cache. Take bytes, return data |
| `game/data/` | `game_data.gd`, the sole engine-facing cartridge-content API |
| `game/save/` | Project saves, versioned and scene-free. See [SAVES.md](SAVES.md) |
| `game/world/` | Request resolution, separate from the screens that draw it |
| `game/battle/` | Scene-free engine, seeded RNG, hardware integer order |
| `game/render/` | Tile-grid pages; a `*_page.gd` draws, its model decides |
| `game/mods/` | Manifest validation and the registry. See [MODS.md](MODS.md) |
| `audio/` | The cartridge's own driver over an emulated APU |

Four boundaries are load-bearing and not obvious from one file:

- **Raw byte runs never go into JSON.** A decimal array costs ~4 bytes on disk
  and ~26 resident per cartridge byte. Use `RomCache.write_payload_map()` or
  `write_section()`; both leave an `[offset, length]` span and move the bytes to
  a `.bin` blob. Only a named `bytes` field moves.
- **World sections load on first use.** The launcher, pic viewer and battle
  never read scripts, text or audio.
- **Never match a keycode in a screen; match a `Gen2Button`.** An embedded host
  takes `handle_button(button)`, so a test presses a button, not a key.
- **Reach an autoload by its static accessor**, `Gen2InputRuntime.instance()` or
  `Gen2GameRuntime.instance()`, never the `InputRuntime`/`GameRuntime` global. A
  script handed to `-s` compiles before the tree exists, so naming one by
  identifier takes down every tool that loads it.

The engine returns event lists, not strings or final state. Keep wording,
animation and timing out of it.

## Audio parity

Nothing between the stream bytes and the samples decides what a note sounds
like: vibrato, slides, duty rotation, envelopes, drum kits and effects stealing
channels are all the driver's per-frame state. Behaviour belongs in the engine
only when `audio/engine.asm` puts it there, and cartridge quirks are reproduced,
not corrected.

`tools/render_audio.gd` dumps any record to a WAV plus a per-frame register
trace. That trace is the parity artefact: any faithful implementation of the
same driver writes the same registers in the same order on the same frames.

## Offsets

`rom_layout.gd` holds absolute positions per dump, and wrong offsets decode
plausible neighbouring data, so `RomImporter.verify_layout()` runs every check
before decoding. **When you add an offset, add its check** in the same commit;
the checks themselves are the list, and they are in that function.

Find data by searching a dump for independently known bytes (an encoded name,
published base stats), then confirm structure against
[pret](https://github.com/pret). Never copy an address across games: bank and
address pairs differ. For graphics, encode the reference PNG as cartridge 1bpp,
one byte per row with bit 7 leftmost, and search for the exact sequence.

## Verifying

Runtime checks prove shape and endpoints, not interior values.

```bash
godot --headless --path . -s res://tools/dump_tables.gd -- gold moves
godot --headless --path . -s res://tools/preview_pics.gd -- gold /tmp/gold.png front
godot --headless --path . -s res://tools/validate.gd -- all
```

Contact sheets expose decompression, tile order, palette and pointer errors.
`tools/validate.gd` is the real-cache suite; see the README for its topics.

`tools/screenshot.gd` renders a scene to PNG and cannot be headless:

```bash
godot --path . -s res://tools/screenshot.gd -- res://game/main/main.tscn /tmp/shot.png 20
```

An optional `<method> <times> [int arg]` drives a scene before capture. Keep
state changes as callable methods, not only input branches, so screens stay
inspectable without a key press.

The GDScript analyzer runs only inside the editor: no CLI mode prints its
warnings, `--check-only` suppresses them, and file logging records the running
game rather than the editor. Read them with `tools/dump_editor_errors.gd` from
Editor > File > Run, which writes `user://editor_errors.txt` and tallies the
warning codes; the panel holds what the session has analysed, so reload the
project first for a full sweep. The tree stays at zero entries.

`integer_division` is the one warning turned off in `project.godot`: this is
8-bit hardware arithmetic throughout, where `a / b` on two integers is the
intended operation, and a float result is written with an explicit `float()`.

Before rewriting or finishing a subsystem, read the verification method: port
the state machine rather than approximating its output, find a second executable
implementation to diff against, pick an artefact that compares exactly, sweep
the whole corpus, and settle every disagreement against pret.

## Pitfalls

- GUT silently skips scripts that fail to parse. `test_smoke.gd` loads every
  script and calls `can_instantiate()`, not only `assert_not_null(load(path))`.
- Do not use `ResourceLoader.CACHE_MODE_IGNORE` on a running script; reparsing
  during a call can corrupt the VM. Use
  `godot --headless --check-only --script res://path.gd`.
- New scripts need an editor scan before they resolve; edits to existing ones do
  not: `godot --headless --editor --path . --quit`.
- Defer `_ready()` scene changes with `change_scene_to_file.call_deferred(path)`.
- A bare `PanelContainer` is transparent; give modals a
  `theme_override_styles/panel` `StyleBoxFlat`.
- A scene root without its `script =` line loads but does nothing.
- JSON numbers return as floats; cache readers must use `int()`.
- GDScript closures capture locals by value. Mutate an Array/Dictionary or use a
  method. A signal closure capturing its source can leak it; connect a method.
- A screen counting hardware frames off `_process` delta spends an unknown
  number of them across an `await`. Take its processing away with
  `set_process(false)` before sampling a value that is still moving.
- Godot 4.8 is a dev build. Compare odd behaviour with 4.6 stable before blaming
  project code.

## Style

- Tabs for indentation; static typing where practical.
- `snake_case` for variables, functions and files; `PascalCase` for classes and
  nodes.
- `.tscn` and `.tres` are plain-text format 3. Edit them directly. Do not invent
  `uid://` values; omit invalid fields and let Godot regenerate them.
- No em-dashes. Check with
  `grep -rn $'\u2014' . --exclude-dir=.git --exclude-dir=addons`.

## Writing and file budget

The repository is kept small on purpose. A reader's time and a machine's are
both finite, and both were being spent on restatement.

**Extend, do not add.** A new feature belongs in the file that already owns its
subject. Before creating any file, name the existing one it cannot go in.

- **Tools.** Do not add a script per feature. `tools/validate.gd` takes a new
  topic as a table entry; `tools/preview_*.gd` are per screen, not per scene or
  per check. A one-off you ran once is not a tool: delete it.
- **Tests.** One file per subject, not per behaviour. Add cases to the existing
  file. A behaviour is tested once, at the layer that owns it; re-asserting it
  at a second layer buys nothing and costs the suite. Keep slow work
  (real caches, whole-movie runs, frame sweeps) out of the default suite.
- **Docs.** State each fact once, where it is enforced, and link instead of
  repeating. Source findings and constants go next to the code, contracts in
  `docs/`, status in `HANDOFF.md`.
- **Comments.** A source symbol plus a one-line reason. Comment non-obvious
  constraints and quirks; never restate the line below. No section banners, no
  doc comment on a self-evident function. Net new comment lines should stay a
  small fraction of net new code lines. `rom_layout.gd` is the one exemption and
  says why in its own header: a comment recording how an offset was located is
  the evidence for that number, not an explanation of the code.

When something changes, replace the old text. Never append a correction, and
never let a file grow just because work happened.
