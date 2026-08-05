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

A native [Godot 4](https://godotengine.org) reimplementation of the Generation
2 Game Boy Color games, Gold, Silver and Crystal. It is written from scratch in
GDScript, not an emulator, static recompilation or disassembly. A user-supplied
cartridge dump is verified by SHA-1, decoded once into a cache, then released.
No game data ships here. Bring your own ROM.

Inspired by [gen1recomp](https://github.com/bryanthaboi/gen1recomp).

> ### Status: early
>
> The import gate and first importer half are tested. A verified cartridge
> decodes species, moves, items, types, the type chart, learnsets, evolutions,
> palettes, all Pokémon sprites, trainer pics and parties, the font, text-box
> borders and battle HUD. Battles support parties, switching, stats, damage,
> accuracy, turn order, status and substatus effects, trainer AI, experience,
> levelling and move learning on a real 160x144 screen. The launcher imports a
> verified dump, opens its cache's save screen, creates or imports a party, and
> starts the development battle. The first overworld runtime slice now renders
> real maps, moves through connected maps and hosts explicit script requests,
> including real trainer battles, imported win/loss text, map reloads and
> save-safe blackout recovery. The live overworld slice also covers scripted
> object lifecycle, bounded followers, map block edits, emotes, surf movement,
> normal and swarm grass and surf encounter tables, fishing groups, roaming state,
> repel checks, deterministic encounter resolution and movement-triggered wild
> battle requests. The importer also preserves referenced overworld menus, 34
> mart lists, phone contacts and music/SFX pointer records, and the scene-free
> host resolves those records without reopening the ROM. Party-owned overworld
> transactions now cover gifts, eggs, imported NPC trades, common HP/status
> items, repel and the core Poké Ball catch calculation behind a validated
> candidate-save boundary. Wild battle capture input now drives the production
> overlay through that transaction. Full story state, audio
> playback and the mod loader do not exist yet, so this is not a complete game.
> Scene-level
> integration tests also cover trainer sight through the real overworld battle
> overlay, imported terminal text, live object refresh, emote rendering, wild
> capture and save-backed blackout recovery.

## Getting started

You need Godot 4.8 or newer. After cloning, enable the commit guard once per
clone because Git does not clone hooks:

```bash
git config core.hooksPath .githooks
```

Put dumps in `roms/`, then verify them. See [roms/README.md](roms/README.md).

```bash
godot --headless --path . -s res://tools/verify_rom.gd
```

## Supported cartridges

Matching uses SHA-1, never filenames. Unknown hashes are refused because an
uncharacterised bank layout would produce corrupt assets.

| Game | SHA-1 |
|---|---|
| Gold (USA/Europe) | `d8b8a3600a465308c9953dfa04f0081c05bdcb94` |
| Silver (USA/Europe) | `49b163f7e57702bc939d642a18f591de55d92dae` |
| Crystal (USA/Europe Rev 1) | `f2f52230b536214ef7c9924f483392993e226cfb` |

## Importing

```bash
godot --headless --path . -s res://tools/import_rom.gd
```

Import normally takes a few seconds per game. The cache is keyed by game and
hash and stored in Godot's `user://`, never in the project or an export. Use
`--verify` to run checks without writing.

| Data | Contents |
|---|---|
| Species | Names, base stats, types, held items, egg groups, TM/HM flags |
| Learnsets | All 251 species' level-up moves, in cartridge order |
| Evolutions | Every evolution and its method/requirements |
| Moves | Names, power, type, accuracy, PP, effect and chance |
| Items, types | 255 item names plus imported prices, effects, menus, pockets and healing metadata; 28 type names |
| NPC trades | Gold/Silver six-row or Crystal seven-row trade records with requested/offered species, DVs, held item and OT data |
| Type chart | Every matchup and the two Foresight-cancelled entries |
| Trainers | Class names, pics, palettes, AI flags, DVs, and every party |
| Palettes | Normal and shiny, as the cartridge's 15-bit colours |
| Sprites | Front/back for 251 species and all 26 Unown forms |
| Font and borders | 128 glyphs and eight six-tile text-box frames |
| Battle HUD | HP/EXP bars, panel borders and their colours |
| Overworld | Maps, tilesets, collisions, events, scripts, movement, palettes, animation and object sprites |
| Wild encounters | Normal and swarm grass/water tables, 13 fishing groups with day/night substitutions, a 16-row roaming graph, map-linked rates and slots, time-of-day selection, surf level variance and repel checks |
| World services | Referenced menus, mart inventories, phone contacts, special calls, music pointers and sound-effect pointers |

Sprites remain colour indices and receive a palette at draw time, so shiny
rendering costs no duplicate images.

Preview decoded graphics:

```bash
godot --headless --path . -s res://tools/preview_pics.gd -- gold /tmp/gold.png front
```

Use `trainers`, `font` or `frames` instead of `front`. Dump decoded tables with
any of `species`, `moves`, `items`, `types`, `matchups`, `trainers`, `learnsets`,
`evolutions`, `growth` or `all`:

```bash
godot --headless --path . -s res://tools/dump_tables.gd -- gold moves
```

`matchups` prints a grid. `learnsets` and `evolutions` resolve numbers into
names. `growth` checks all 251 species against the six curves and base EXP.

## Running

Smoke test the main scene:

```bash
godot --headless --path . --quit-after 30
```

The launcher lists Gold, Silver and Crystal cache status, imports a selected
ROM, and opens its save screen. That screen offers three validated slots, new
games with Chikorita, Cyndaquil or Totodile at level 5, original `.sav` import,
party inspection and the development battle. New games carry the verified
Crystal home spawn and source starting money when that map exists in the
selected cache. Continue enters the overworld; F5 writes its map, inventory
and event snapshot back to the selected slot. See
[docs/SAVES.md](docs/SAVES.md) for the save contract and cartridge SRAM
boundary.

Development scenes:

- `game/render/pic_viewer.tscn`: Left/right changes species, `S` toggles shiny,
  `B` swaps front/back, and `T` selects trainer classes.
- `game/render/text_viewer.tscn`: Space advances, `F` cycles borders, and `C`
  shows every glyph.
- `game/battle/battle_screen.tscn`: `A` takes a turn, space advances events,
  `W` switches, left/right changes the matchup, and `S`/`D` damage either side
  without using a turn. In a wild overworld battle, `B` opens the owned-ball
  selector, left/right changes the ball and space throws it. The player currently
  chooses moves randomly; a full
  moveset's learn-offer is declined automatically because those menus do not
  exist yet. `show_trainer(trainer_class)` uses the real party and trainer AI;
  `show_matchup` uses a fallback invented pairing.
- `game/world/world_screen.tscn`: renders Route 29 by default with real
  palettes, animation and object sprites. Arrows/WASD move the player and roll
  imported encounters on maps with a table. Fishing selection is limited to
  owned rod items, and `F` starts a cast only when the player faces water.
  Space, Enter or Z advances the cast and bite states. F5 persists the current
  world snapshot. The live host clock advances one real-time game minute per
  minute and updates the source day boundaries. `preview_emote()` shows the
  live object-emote renderer path, while `preview_wild_encounter()` and
  `preview_fishing_battle()` open resolved imported battles through the
  production battle overlay. The scene-free world API also exposes explicit
  swarm and roaming schedule updates, repel countdowns and a JSON-safe world
  snapshot that can be carried by a validated project save.
  `preview_script_event()` exercises an imported map event, while
  `preview_battle_request()` exercises the battle overlay used by explicit
  overworld battle requests. The battle screen's
  `preview_world_battle_loss()` drives the recovery message for a visual smoke
  check. `preview_capture()` drives the real Master Ball throw message through
  the capture bridge. `preview_party_transaction()` runs an in-memory Potion transaction
  through the party host. The hint line also reports the imported world-service
  record counts.

  `tools/preview_fishing.gd` captures the fishing state from the normal
  renderer. With an imported cache, pass the game and map after the output
  path, for example `silver 2 5`; the one-argument form remains a deterministic
  integration-fixture smoke check.

## Tests

[GUT](https://github.com/bitwes/Gut) is in `addons/gut`; configuration is in
`.gutconfig.json`.

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

Exit code `0` means all tests passed. They use synthetic files and a known
SHA-1 vector, never a real cartridge. The overworld trainer integration suite
can be run on its own with `-gdir=res://tests/integration`.

## Layout

| Path | Contents |
|---|---|
| `game/` | Feature folders with colocated scenes and scripts |
| `autoload/` | Project singletons |
| `assets/` | Authored or freely licensed assets |
| `assets/brand/` | Logo and banner, see its README |
| `addons/` | Third-party plugins |
| `tests/` | GUT unit and integration tests |
| `tools/` | Headless developer scripts |
| `roms/` | User cartridges, excluded from Git and Godot imports |
| `docs/` | Contributor notes |

## Platforms

Windows, macOS, Linux, Android and iOS use the GL Compatibility renderer.
Export presets are not configured. iOS forbids JIT and runtime native code, so
mods will be interpreted GDScript, never compiled extensions. This is why the
project is GDScript-first.

## Contributing

Read [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md). No cartridge-derived data
may enter the repository: no ROM, `.sav`, extracted sprites, text, maps or
audio. `.gitignore`, the pre-commit hook and tests enforce this; do not weaken
them.

## Licence

[MIT](LICENSE) covers the engine source here, not the games or supplied dumps,
which remain the property of their respective owners.
