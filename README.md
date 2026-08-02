# gen2recomp

A native [Godot 4](https://godotengine.org) reimplementation of the Generation 2
Game Boy Color games — Gold, Silver and Crystal.

**Not an emulator, not a static recompilation, not a disassembly.** The engine
is written from scratch in GDScript. Your own cartridge dump is used as an
*asset database*: verified by SHA-1, decoded once into a cache, then released.

No game data ships in this repository. **Bring your own ROM.**

Inspired by [gen1recomp](https://github.com/bryanthaboi/gen1recomp), which does
the same thing for Generation 1.

> ### Status: early
>
> The project skeleton and the ROM import gate exist and are tested. The
> importer, renderer, overworld, battle system, audio and mod loader do not
> exist yet. There is nothing playable here today.

## Getting started

You need Godot 4.8 or newer. Clone the repo, then enable the commit guard
(Git does not clone hooks, so this is once per clone):

```bash
git config core.hooksPath .githooks
```

Put your cartridge dumps in `roms/` — see [roms/README.md](roms/README.md).
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

## Running

```bash
godot --headless --path . --quit-after 30
```

Boots the main scene for 30 frames and exits — a quick smoke check.

## Tests

[GUT](https://github.com/bitwes/Gut) lives in `addons/gut`; configuration is in
`.gutconfig.json`.

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

Exit code `0` means everything passed. Tests never load a real cartridge —
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
extensions — this is why the project is GDScript-first.

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for conventions and the Godot
pitfalls that have cost real time on this project.

**The one rule that matters:** no cartridge-derived data enters this
repository. Not a ROM, not a `.sav`, not extracted sprites, text, maps or
audio. Three layers enforce it — `.gitignore`, the pre-commit hook, and tests
that never touch a real file. Please do not weaken any of them.

## Licence

[MIT](LICENSE). This covers the engine source in this repository and nothing
else: the games themselves are not included, not redistributed, and remain the
property of their respective owners. You supply your own cartridge dump.
