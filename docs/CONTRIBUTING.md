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
2. **`.githooks/pre-commit`** checks what is actually *staged* — by extension,
   and by size for any blob ≥ 512 KiB outside `addons/` and `assets/`. That
   second check catches a renamed or trimmed dump that no extension rule would
   see. Enable it with `git config core.hooksPath .githooks`; Git does not
   clone hooks, so every clone needs it once.
3. **Tests never load a real cartridge.** `test_rom_verifier.gd` covers the
   import gate with synthetic files and a known SHA-1 vector, so the suite runs
   on any machine and in CI.

`roms/` additionally carries a `.gdignore`, which makes Godot's resource system
skip the directory entirely — files there are never imported and never swept
into an export. `FileAccess` can still read them during development, which is
how `tools/verify_rom.gd` works. Do not delete that file.

## Architecture

The ROM layer is the model for the rest of the engine:

- `game/rom/rom_registry.gd` — the SHA-1 allowlist.
- `game/rom/rom_verifier.gd` — size pre-filter, then chunked SHA-1, then
  lookup.

Both are `RefCounted` statics with no scene dependencies, so the import gate is
fully testable headlessly. Keep the engine core the same shape: rules apart
from content, and randomness injected as an explicit `RandomNumberGenerator`
rather than pulled from a global, so a whole battle can play out inside a test.

## Seeing the UI without pressing Play

`tools/screenshot.gd` renders a scene to a PNG:

```bash
godot --path . -s res://tools/screenshot.gd -- res://game/main/main.tscn /tmp/shot.png 20
```

An optional trailing `<method> <times> [int arg]` drives the scene before
capturing, so you can photograph a screen mid-interaction rather than only on
its first frame. This briefly opens a real window — rendering needs a display,
so it cannot run under `--headless`.

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
- **GDScript lambdas capture by value.** Assigning to a captured local inside a
  `func():` closure updates the copy, not the original — the write silently
  vanishes. Append to an Array/Dictionary, or use a method.
- **A closure stored on the signal of an object it captures leaks that
  object.** The cycle is invisible until Godot prints "ObjectDB instances were
  leaked at exit". Connect a method rather than a capturing lambda; that
  warning at the end of a test run is worth chasing.
- Godot 4.8 is a *dev* build. If something behaves oddly, check it against 4.6
  stable before assuming the bug is ours.

## GDScript conventions

- Tabs for indentation (Godot default — don't reformat to spaces).
- Static typing everywhere practical: `var health: int = 10`,
  `func heal(amount: int) -> void:`.
- `snake_case` for variables, functions and files; `PascalCase` for classes and
  nodes.
- No comments explaining *what* code does — only *why*, for non-obvious
  constraints.

## Scenes

`.tscn` and `.tres` are plain text (format 3) — read and edit them directly
like source. Don't hand-invent `uid://` identifiers; Godot regenerates missing
or invalid ones on load, or omit the `uid` field on `ext_resource` lines and
let the editor fill it in.
