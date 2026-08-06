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

A native [Godot 4](https://godotengine.org) reimplementation of Generation 2
Game Boy Color games Gold, Silver and Crystal. It is written from scratch in
GDScript, not an emulator, static recompilation or disassembly. A user-supplied
cartridge dump is SHA-1 verified, decoded once into a cache, then released. No
game data ships here: bring your own ROM.

Inspired by [gen1recomp](https://github.com/bryanthaboi/gen1recomp).

> ### Status: early
>
> The importer gate and first importer half are tested. A verified cartridge
> decodes species, moves, items, types, the type chart, learnsets, evolutions,
> palettes, all Pokémon sprites, trainer pics and parties, the font, text-box
> borders and battle HUD. Battles support parties, switching, stats, damage,
> accuracy, turn order, status and substatus effects, trainer AI, experience,
> levelling and move learning on a real 160x144 screen.
>
> The launcher imports a verified dump, opens its cache's save screen, creates
> or imports a party, and starts the development battle. The overworld slice
> renders real maps, enters the imported Crystal home callbacks from a new
> game, traverses connected maps, runs explicit script requests,
> handles trainer battles, imported win/loss text, map reloads and save-safe
> blackout recovery, and covers object lifecycle, bounded followers, block
> edits, emotes, surf, grass, fishing, roaming, repel and deterministic wild
> battle requests. The real-data story preview now follows the post-starter
> route through Elm's aide Potion, Route 29, Cherrygrove, Route 30, Mr. Pokémon's
> Mystery Egg event, the first rival battle and the return to Elm's Lab for the
> Egg and Poké Ball handoffs.
>
> The importer also preserves referenced overworld menus, 34 mart lists, phone
> contacts, special-call records and music/SFX pointer records. The scene-free
> host resolves them without reopening the ROM. The production service overlay
> supports cached vertical and two-dimensional menu selection, source mart dialog
> variants, bounded quantity purchases, source-timed phone caller/callee dispatch
> and bounded Gen II music, effects and cries. Party transactions cover
> gifts, eggs, imported NPC trades, common HP/status items, repel and the core
> Poké Ball catch calculation behind a validated candidate-save boundary; wild
> capture input uses that transaction.

The party screen opens a first PC storage presentation with fourteen numbered
boxes and twenty fixed slots per box. It can deposit into the current box's
first free slot and withdraw into a party with room. Each transfer validates and
writes a candidate save atomically, and the last party member cannot be boxed.
The imported Players House PC now reaches this same storage screen as an
embedded overworld overlay. Closing it resumes the source script, while
selected saves persist transfers and injected or development saves remain
memory-only.
> Crystal rooftop stock switches from the imported first list after the Hall of
> Fame engine flag is committed. The imported bargain shop keeps its Monday
> morning, one-item-per-visit and daily close behavior in the world snapshot.
>
> Project saves now have a validated 14-box PC model with 20 slots per box.
> Full parties route gifts, eggs and successful captures into the first free
> box slot, while full storage refuses the transaction atomically. Format 1
> project saves migrate without inventing a world position.
>
> Full story state and complete phone presentation do not exist yet, so this is not
> a complete game. Source two-ring timing, contact registration commands,
> non-trainer caller labels, seen-species phone text and bounded phone pointer
> semantics are implemented. The remaining source special-call condition branches
> and story-driven permanent-contact setup are still pending. The mod boundary is
> in: a mod under `user://mods/` can register
> a replacement world renderer, which is what a 3D or HD view needs. Scene-level integration tests cover trainer sight,
> imported terminal text, live object refresh, emotes, wild capture, save-backed
> blackout recovery and all four service overlay modes.

## Getting started

You need Godot 4.8 or newer. Enable the commit guard once per clone:

```bash
git config core.hooksPath .githooks
```

Put dumps in `roms/`, then verify them. See [roms/README.md](roms/README.md).

```bash
godot --headless --path . -s res://tools/verify_rom.gd
```

## Supported cartridges

Matching uses SHA-1, never filenames. Unknown hashes are refused because an
uncharacterised bank layout could produce corrupt assets.

| Game | SHA-1 |
|---|---|
| Gold (USA/Europe) | `d8b8a3600a465308c9953dfa04f0081c05bdcb94` |
| Silver (USA/Europe) | `49b163f7e57702bc939d642a18f591de55d92dae` |
| Crystal (USA/Europe Rev 1) | `f2f52230b536214ef7c9924f483392993e226cfb` |

## Importing

```bash
godot --headless --path . -s res://tools/import_rom.gd
```

Import takes a few seconds per game. The cache is keyed by game and hash and
lives in Godot's `user://`, never in the project or an export. Use `--verify`
to check without writing.

| Data | Contents |
|---|---|
| Species | Names, base stats, types, held items, egg groups and TM/HM flags |
| Learnsets | All 251 species' level-up moves in cartridge order |
| Evolutions | Every evolution and method/requirements |
| Moves | Names, power, type, accuracy, PP, effect and chance |
| Items, types | 255 item names, prices, effects, menus, pockets, healing metadata and 28 type names |
| NPC trades | Gold/Silver six-row or Crystal seven-row records with requested/offered species, DVs, held item and OT data |
| Type chart | Every matchup and the two Foresight-cancelled entries |
| Trainers | Class names, pics, palettes, AI flags, DVs and every party |
| Palettes | Normal and shiny 15-bit cartridge colours |
| Sprites | Front/back for 251 species and all 26 Unown forms |
| Font and borders | 128 glyphs and eight six-tile text-box frames |
| Battle HUD | HP/EXP bars, panel borders and colours |
| Overworld | Maps, tilesets, collisions, events, scripts, movement, palettes, animation and object sprites |
| Wild encounters | Normal/swarm grass and water, 13 fishing groups with day/night substitutions, 16-row roaming graph, map-linked rates and slots, time-of-day selection, surf variance and repel checks |
| World services | Referenced menus, mart inventories, phone contacts, special calls, bounded scripts/text, music, SFX, cries and shared waveform assets |

Sprites remain colour indices and receive a palette at draw time, so shiny
rendering needs no duplicate images.

Preview decoded graphics:

```bash
godot --headless --path . -s res://tools/preview_pics.gd -- gold /tmp/gold.png front
```

Use `trainers`, `font` or `frames` instead of `front`. Dump decoded tables
with `species`, `moves`, `items`, `types`, `matchups`, `trainers`, `learnsets`,
`evolutions`, `growth` or `all`:

```bash
godot --headless --path . -s res://tools/dump_tables.gd -- gold moves
```

`matchups` prints a grid; `learnsets` and `evolutions` resolve numbers into
names; `growth` checks all 251 species against the six curves and base EXP.

## Running

Smoke test the main scene:

```bash
godot --headless --path . --quit-after 30
```

The launcher lists Gold, Silver and Crystal cache status, imports a selected
ROM, and opens its save screen. It provides three validated slots, new games
with an empty party until Professor Elm's imported lab handoff, original `.sav`
import, party inspection and the development battle. The lab scripts then offer
Chikorita, Cyndaquil or Totodile at level 5 with Berry, using the verified Crystal
home spawn and source starting money when that map exists. Continue enters the
overworld; F5 saves its map, inventory, event and clock snapshot. See
[docs/SAVES.md](docs/SAVES.md) for the save and SRAM contract.

Development scenes:

- `game/render/pic_viewer.tscn`: left/right species, `S` shiny, `B` front/back,
  `T` trainer classes.
- `game/render/text_viewer.tscn`: Space advances, `F` cycles borders, `C` shows
  every glyph.
- `game/battle/battle_screen.tscn`: `A` turn, Space events, `W` switch,
  left/right matchup, `S`/`D` damage either side. In wild battles, `B` opens
  the owned-ball selector, left/right changes the ball and Space throws it.
  Moves are currently random; full move sets decline the learn offer. Use
  `show_trainer(trainer_class)` for a real party and trainer AI, or
  `show_matchup` for a fallback pairing.
- `game/world/world_screen.tscn`: arrows/WASD move Route 29, encounters use
  imported tables, and `F` fishes only while facing water with an owned rod.
  Space, Enter or `Z` advances casting and bites; F5 saves. The host clock
  advances one real-time game minute per minute and updates source day
  boundaries. `P` opens the registered Pokegear phone list. The imported
  Players House PC opens the embedded numbered box storage screen and `Esc`
  closes it. `preview_emote()`, `preview_wild_encounter()`,
  `preview_fishing_battle()`, `preview_script_event()`,
  `preview_battle_request()`, `preview_world_battle_loss()`,
  `preview_capture()` and `preview_party_transaction()` exercise their live
  paths. The API also exposes swarm/roaming updates, repel countdowns and a
  JSON-safe snapshot. `V` cycles the registered world renderers. The hint line
  reports imported service counts.

  `tools/preview_world_services.gd` captures the production mart overlay with
  the deterministic integration cache. `tools/preview_fishing.gd` captures
  fishing; with an imported cache pass game and map after the output path, such
  as `silver 2 5`. Its one-argument form remains a fixture smoke test.

  `tools/preview_world_story.gd` exercises real imported map entry callbacks,
  event-flag object visibility and a facing object interaction without opening
  the cartridge at runtime. The Crystal home map also covers source decoration
  callbacks and the long initial event setup script. For example:

  ```bash
  godot --headless --path . -s res://tools/preview_world_story.gd -- \
    crystal 3 19 3 5 1 37,1744
  ```

  The real Crystal bedroom PC and the validated bedroom-to-town warp chain can
  be checked with:

  ```bash
  godot --headless --path . -s res://tools/preview_world_story.gd -- \
    crystal 24 7 2 2 1 none home
  ```

  The bounded story preview follows production movement from the bedroom to
  Players House 1F, executes the imported Mom setup with weekday and
  daylight-saving prompts, reaches the imported New Bark Town teacher scene,
  enters Elm's lab, completes the source starter and aide Potion events, crosses
  Route 29 and Cherrygrove to Route 30, runs Mr. Pokémon's Mystery Egg event,
  resolves the can-lose rival battle and party heal, then returns to Elm's lab
  for the officer, Egg and five Poké Ball handoffs:

  ```bash
  godot --headless --path . -s res://tools/preview_world_story.gd -- \
    crystal 24 7 2 2 1 none home story
  ```

  A freshly imported Crystal cache can verify the first Route 30 trainer's
  source record, sight line, approach, battle request, beaten flag and later
  interaction without reopening the cartridge:

  ```bash
  godot --headless --path . -s res://tools/validate_crystal_route30_trainer.gd
  ```

  World text follows the cartridge command stream: `$50` is a page break,
  `$57` ends a text box and `$58` pauses for a prompt. The story runner keeps
  the source yes/no order, weekday wrapping and first eight temporary event
  flags, which reset on a map reload.

## Tests

[GUT](https://github.com/bitwes/Gut) is in `addons/gut`; configuration is in
`.gutconfig.json`.

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

Exit code `0` means all tests passed. They use synthetic files and a known
SHA-1 vector, never a real cartridge. Overworld integration suites can run
alone with `-gdir=res://tests/integration`; service coverage includes menus,
marts, phone calls and audio requests.

## Layout

| Path | Contents |
|---|---|
| `game/` | Feature folders with colocated scenes and scripts |
| `autoload/` | Project singletons |
| `assets/` | Authored or freely licensed assets |
| `assets/brand/` | Logo and banner; see its README |
| `addons/` | Third-party plugins |
| `tests/` | GUT unit and integration tests |
| `tools/` | Headless developer scripts |
| `roms/` | User cartridges, excluded from Git and Godot imports |
| `game/mods/` | Mod manifest and host |
| `mods/examples/` | Example mods to copy into `user://mods/` |
| `docs/` | Contributor notes |

## Platforms

Windows, macOS, Linux, Android and iOS use GL Compatibility.
`export_presets.cfg` covers all five and writes into `builds/`. Install the
matching export templates first, then:

```bash
godot --headless --path . --export-release "Linux" builds/linux/gen2recomp.x86_64
```

Tests, tools and GUT are excluded, and `roms/` and the `user://` cache are not
reachable from an export at all. Signing identities are placeholders: set the
bundle identifiers, Android SDK paths and Apple team ID before publishing.

iOS forbids JIT and runtime native code, so mods must be interpreted GDScript,
not compiled extensions. The project is therefore GDScript-first. See
[docs/MODS.md](docs/MODS.md).

## Contributing

Read [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md). No cartridge-derived data
may enter the repository: no ROM, `.sav`, extracted sprites, text, maps or
audio. `.gitignore`, the pre-commit hook and tests enforce this; do not weaken
them. For reproducible comparisons with the upstream disassemblies, see
[docs/REFERENCES.md](docs/REFERENCES.md).

## Licence

[MIT](LICENSE) covers the engine source here, not the games or supplied dumps,
which remain the property of their respective owners.
