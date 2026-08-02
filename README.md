# gen2recomp

A native [Godot 4](https://godotengine.org) reimplementation of the Generation 2
Game Boy Color games: Gold, Silver and Crystal.

**Not an emulator, not a static recompilation, not a disassembly.** The engine
is written from scratch in GDScript. Your own cartridge dump is used as an
*asset database*: verified by SHA-1, decoded once into a cache, then released.

No game data ships in this repository. **Bring your own ROM.**

Inspired by [gen1recomp](https://github.com/bryanthaboi/gen1recomp), which does
the same thing for Generation 1.

> ### Status: early
>
> The import gate and the first half of the importer exist and are tested: a
> verified cartridge decodes into species data, moves, items, types, palettes
> and every Pokémon sprite. The renderer, overworld, battle system, audio and
> mod loader do not exist yet. There is nothing playable here today.

## Getting started

You need Godot 4.8 or newer. Clone the repo, then enable the commit guard
(Git does not clone hooks, so this is once per clone):

```bash
git config core.hooksPath .githooks
```

Put your cartridge dumps in `roms/`; see [roms/README.md](roms/README.md).
That folder is gitignored and carries a `.gdignore`, so its contents are
excluded from both commits and builds.

Verify them:

```bash
godot --headless --path . -s res://tools/verify_rom.gd
```

## Supported cartridges

Matching is by SHA-1, never by filename.

| Game | SHA-1 |
|---|---|
| Gold (USA/Europe) | `d8b8a3600a465308c9953dfa04f0081c05bdcb94` |
| Silver (USA/Europe) | `49b163f7e57702bc939d642a18f591de55d92dae` |
| Crystal (USA/Europe Rev 1) | `f2f52230b536214ef7c9924f483392993e226cfb` |

An unrecognised hash is refused outright rather than imported on a best-effort
basis: a cartridge whose bank layout has not been characterised produces
corrupt assets instead of an honest error.

## Importing

Decoding a cartridge into the cache:

```bash
godot --headless --path . -s res://tools/import_rom.gd
```

Takes under a second per game. The cache lands in Godot's `user://` directory,
never inside the project, because it is cartridge-derived data and subject to
exactly the same rule as the ROM itself. Add `--verify` to run the checks
without writing anything.

Each import is keyed by game and hash, so two revisions never share a cache.
What comes out today:

| | |
|---|---|
| Species | Names, base stats, types, held items, egg groups, TM/HM flags |
| Moves | Names, power, type, accuracy, PP, effect and its chance |
| Items | All 255 names, indexed by item number |
| Types | All 28 names, indexed by type number |
| Palettes | Normal and shiny, as the cartridge's own 15-bit colours |
| Sprites | Front and back for all 251 species, plus all 26 Unown forms |

Sprites are stored as colour indices rather than as images, and a palette is
applied when they are drawn, which is the whole of what being shiny costs.

To look at what was decoded, as a contact sheet of sprites:

```bash
godot --headless --path . -s res://tools/preview_pics.gd -- gold /tmp/gold.png front
```

or as text, for any of `species`, `moves`, `items`, `types` or `all`:

```bash
godot --headless --path . -s res://tools/dump_tables.gd -- gold moves
```

## Running

```bash
godot --headless --path . --quit-after 30
```

Boots the main scene for 30 frames and exits, as a quick smoke check.

## Tests

[GUT](https://github.com/bitwes/Gut) lives in `addons/gut`; configuration is in
`.gutconfig.json`.

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

Exit code `0` means everything passed. Tests never load a real cartridge;
they use synthetic files and a known SHA-1 vector, so the suite runs anywhere.

## Layout

| Path | |
|---|---|
| `game/` | Feature folders, scene and script colocated |
| `autoload/` | Singletons registered in Project Settings |
| `assets/` | Only assets we authored or that are freely licensed |
| `addons/` | Third-party plugins |
| `tests/` | GUT unit and integration tests |
| `tools/` | Headless developer scripts, not shipped game code |
| `roms/` | Your cartridges (gitignored) |
| `docs/` | Contributor notes |

## Platforms

Windows, macOS, Linux, Android and iOS, using the GL Compatibility renderer for
the widest hardware reach. Export presets are not configured yet.

Note that iOS forbids JIT compilation and loading native code at runtime. Mods
are therefore GDScript interpreted by the shipped VM, never compiled
extensions. That is why the project is GDScript-first.

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for conventions and the Godot
pitfalls that have cost real time on this project.

**The one rule that matters:** no cartridge-derived data enters this
repository. Not a ROM, not a `.sav`, not extracted sprites, text, maps or
audio. Three layers enforce it: `.gitignore`, the pre-commit hook, and tests
that never touch a real file. Please do not weaken any of them.

## Licence

[MIT](LICENSE). This covers the engine source in this repository and nothing
else: the games themselves are not included, not redistributed, and remain the
property of their respective owners. You supply your own cartridge dump.
