<p align="center">
  <img src="assets/brand/banner.png" alt="gen2recomp" width="820">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Godot-4.8.dev2-478CBF?style=flat-square&logo=godotengine&logoColor=white" alt="Godot 4.8.dev2">
  <img src="https://img.shields.io/badge/GDScript-355570?style=flat-square&logo=godotengine&logoColor=white" alt="GDScript">
  <img src="https://img.shields.io/badge/platforms-Windows%20%C2%B7%20macOS%20%C2%B7%20Linux%20%C2%B7%20Android%20%C2%B7%20iOS-8f8c98?style=flat-square" alt="Platforms">
  <img src="https://img.shields.io/badge/status-early-e0a138?style=flat-square" alt="Status: early">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licence-MIT-7d59d4?style=flat-square" alt="MIT licence"></a>
  <a href="http://discord.gg/twkrHkHprk"><img src="https://img.shields.io/badge/Discord-join%20the%20community-5865F2?style=flat-square&logo=discord&logoColor=white" alt="Discord"></a>
  <a href="https://x.com/DecryptTV"><img src="https://img.shields.io/badge/follow-%40DecryptTV-000000?style=flat-square&logo=x&logoColor=white" alt="X"></a>
</p>

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
> verified cartridge decodes into species data, moves, items, types, the type
> chart, learnsets, evolutions, palettes, every Pokémon sprite, every trainer
> pic, the font, the text box borders and the battle HUD. A battle can be
> fought: parties, switching, stats, damage, accuracy, turn order and the five
> status conditions, on a real 160x144 screen with the bars draining and the
> messages appearing. Every move effect other than the status ones is still an
> ordinary attack, and the overworld, audio and the mod loader do not exist.
> There is nothing playable here today.

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
| Learnsets | Every level-up move of all 251 species, in the cartridge's order |
| Evolutions | Every evolution, and what each one asks for |
| Moves | Names, power, type, accuracy, PP, effect and its chance |
| Items | All 255 names, indexed by item number |
| Types | All 28 names, indexed by type number |
| Type chart | Every matchup, and which two Foresight cancels |
| Trainers | Every trainer class: name, pic and palette |
| Palettes | Normal and shiny, as the cartridge's own 15-bit colours |
| Sprites | Front and back for all 251 species, plus all 26 Unown forms |
| Font | All 128 glyphs, indexed by character code |
| Borders | All eight text box frames, six tiles each |
| Battle HUD | The HP bar, the exp bar, both panel borders and the colours they are drawn in |

Sprites are stored as colour indices rather than as images, and a palette is
applied when they are drawn, which is the whole of what being shiny costs.

To look at what was decoded, as a contact sheet of sprites:

```bash
godot --headless --path . -s res://tools/preview_pics.gd -- gold /tmp/gold.png front
```

The same tool takes `trainers` for the trainer classes, or `font` or `frames` in
place of an atlas name, which is how you check that the glyphs are where the
character codes say they are.

or as text, for any of `species`, `moves`, `items`, `types`, `matchups`,
`trainers`, `learnsets`, `evolutions` or `all`:

```bash
godot --headless --path . -s res://tools/dump_tables.gd -- gold moves
```

`matchups` prints the type chart as a grid rather than as a list, because a grid
is the shape the published table has and a single wrong cell shows up in it.
`learnsets` and `evolutions` resolve their numbers into names, so a line reads
as "level 20, attack over defense -> HITMONLEE" rather than as three bytes.

## Running

```bash
godot --headless --path . --quit-after 30
```

Boots the main scene for 30 frames and exits, as a quick smoke check.

To see an imported sprite on a real screen, open
`game/render/pic_viewer.tscn` in the editor and press Play. Left and right
change species, `S` toggles shiny, `B` swaps the front pic for the back one, and
`T` switches to the trainer classes.
The game is drawn into a 160x144 viewport and scaled up by a whole number, so a
Game Boy pixel stays square; the interface around it is at the window's own
resolution.

`game/render/text_viewer.tscn` does the same for text: space advances the box,
`F` cycles through the eight borders, and `C` shows every glyph in the font at
once.

`game/battle/battle_screen.tscn` is the battle screen itself: two Pokémon, a
status panel each and a text box, where the hardware puts them, with a real
battle behind it. `A` takes a turn and space steps through what happened, so the
bars drain, the messages appear and one of the two eventually faints, whereupon
the next one out is sent in. `W` switches, which costs the turn: the other side
attacks whoever came in. Left and right change which Pokémon are on it, and `S`
and `D` take health off the player's and the enemy's without a turn, which is
the fastest way to see the bars change colour.

Both Pokémon know what their level says they know, out of the learnset, and both
pick at random from those moves: choosing one is a menu on the player's side and
an AI on the enemy's, and neither exists yet. Each side brings two Pokémon, made
up by the screen, because a real party comes from a save on one side and from
the trainer party tables on the other and neither is decoded yet.

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
| `assets/brand/` | Logo and banner; see [its README](assets/brand/README.md) |
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
