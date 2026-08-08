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
> Not a complete game yet. What works today:
>
> - **Import.** Species, moves, items, types, the type chart, learnsets,
>   evolutions, palettes, every Pokémon sprite, trainer pics and parties, the
>   font, text-box borders, the battle HUD, maps, overworld menus, 34 mart
>   lists, phone contacts, special calls and music/SFX pointers. A scene-free
>   host resolves all of it without reopening the ROM.
> - **Battles.** Parties, switching, stats, damage, accuracy, turn order, status
>   and substatus effects, trainer AI, experience, levelling, move learning and
>   capture input on a real 160x144 screen.
> - **Overworld.** Real maps, map connections, script requests, trainer battles
>   with imported win/loss text, map reloads, save-safe blackout recovery,
>   object lifecycle, followers, block edits, emotes, surf, ledge hops, grass,
>   fishing, roaming, repel and wild encounters. The service overlay covers
>   menu selection, mart dialog variants and quantity purchases, source-timed
>   phone dispatch and bounded music, effects and cries.
> - **Saves.** Three slots, `.sav` import, and a 14-box PC model with 20 slots
>   per box. Gifts, eggs, NPC trades, HP/status items, repel and captures commit
>   through a validated candidate save; a full party routes into the first free
>   box slot and full storage refuses atomically. Format 1 saves migrate without
>   inventing a world position.
> - **Mods.** A mod under `user://mods/` can add a species, move, item or trainer
>   class, rebalance one the cartridge shipped, register a move effect and the
>   steps it is built from, watch the world and battle event channels, add a menu
>   entry, and replace the world or battle renderer, which is what a 3D or HD
>   view needs.
>
> The real-data story preview walks the Crystal route from Elm's lab through
> Route 29, Cherrygrove, Route 30 and Mr. Pokémon's Mystery Egg event to the
> Zephyr Badge, then on through the Togepi egg, Route 32, Union Cave, Route 33,
> Kurt and Slowpoke Well to the Hive Badge, and through Ilex Forest's Farfetch'd
> hunt, HM01 Cut, Route 34 and Whitney to the Plain Badge, then the SquirtBottle
> errand, Sudowoodo, the Burned Tower beasts and Morty to the Fog Badge, and on
> through the Dance Theatre's Kimono Girls for HM03 Surf, Routes 38 and 39, the
> Olivine Lighthouse, Routes 40 and 41 surfed to Cianwood for the SecretPotion,
> and Jasmine to the Mineral Badge, catching a Geodude in Union Cave on the way
> and teaching it HM04 Strength to push Cianwood Gym's boulders aside for the
> Storm Badge, then east across Route 42's lakes to Mahogany, the Lake of Rage's
> Red Gyarados and Lance, the Rocket hideout's three floors and Pryce to the
> Glacier Badge, back west for the Goldenrod Radio Tower's basement and card
> keys and its Rocket boss, then Route 44 and the Ice Path to Blackthorn, its
> gym's boulder puzzle and Clair, and the Dragon Shrine's quiz for the Rising
> Badge.
> Missing: full story state, dex, trainer card, options, the remaining
> special-call branches and story-driven permanent contacts.

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
| TM/HM moves | The 57 Gold/Silver or 60 Crystal TM, HM and move-tutor rows, which is what turns a TM in the bag into a move |
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
ROM, and opens its save screen: three validated slots, `.sav` import, party
inspection and the development battle. A new game starts with an empty party at
the Crystal home spawn with source starting money; Elm's imported lab scripts
offer Chikorita, Cyndaquil or Totodile at level 5 holding Berry. Continue enters
the overworld and F5 saves its map, inventory, event and clock snapshot. See
[docs/SAVES.md](docs/SAVES.md) for the save and SRAM contract.

Development scenes:

| Scene | Keys |
|---|---|
| `game/render/pic_viewer.tscn` | left/right species, `S` shiny, `B` front/back, `T` trainer classes |
| `game/render/text_viewer.tscn` | Space advances, `F` cycles borders, `C` shows every glyph |
| `game/battle/battle_screen.tscn` | `A` turn, Space events, `W` switch, left/right matchup, `S`/`D` damage either side; in wild battles `B` opens the ball selector, left/right changes ball, Space throws |
| `game/world/world_screen.tscn` | arrows/WASD move, Space or `Z` confirms, `F` fishes while facing water with an owned rod, `P` opens the phone list, `Enter`/`Tab` opens the start menu, `Esc` closes an overlay, `V` cycles world renderers, F5 saves |

Battle-screen moves are random and a full move set declines the learn offer; use
`show_trainer(trainer_class)` for a real party and trainer AI, or `show_matchup`
for a fallback pairing.

The world screen's start menu wires Pokemon, Pack, Pokegear, Save and Exit;
Pokedex, Player and Options appear in their source position but do nothing yet.
The Pack opens each item's own source submenu and can use one: a Potion asks
which Pokemon and heals it, a Repel sets its step count, and GIVE, TOSS and SEL
keep their source position marked unavailable.
The party submenu offers Cut, Surf, Strength, Whirlpool and Waterfall to a
Pokemon that knows one; all five show their message first and change the world
on the acknowledge, and stepping from water back onto land stops surfing. A
Waterfall climb runs the whole column in one command and ends on the first cell
above it that is not a waterfall. Standing on a whirlpool, waterfall, door,
staircase or cave tile overrides the pressed direction the way the cartridge
does, which is also how a waterfall is ridden back down.
Poké Balls on the ground are picked up by facing them, and so are the items
hidden in scenery: neither an item ball's pointer nor a hidden item's is a
script, so each is decoded and its item received. A hidden item answers only
while its own event flag is clear, and picking it up is what sets that flag.
The imported Players House PC opens the embedded box storage screen. The host
clock advances one game minute per real minute and crosses source day
boundaries. `preview_emote()`, `preview_wild_encounter()`,
`preview_fishing_battle()`, `preview_script_event()`, `preview_battle_request()`,
`preview_world_battle_loss()`, `preview_capture()` and
`preview_party_transaction()` drive their live paths; the API also exposes
swarm/roaming updates, repel countdowns and a JSON-safe snapshot.

Headless tools, all against a real imported cache:

| Tool | Checks |
|---|---|
| `preview_world_services.gd <png>` | mart overlay, deterministic integration cache |
| `preview_fishing.gd <png> [game map]` | fishing, for example `silver 2 5`; one-argument form is a fixture smoke test |
| `preview_hall_of_fame.gd <game> <png> [page]` | the Hall of Fame induction panel against a real cache; `page` is how many panels to advance past |
| `preview_world_story.gd` | map entry callbacks, event-flag visibility, facing interactions and the story route |
| `validate_crystal_route30_trainer.gd` | trainer record, sight line, approach, battle request, beaten flag, later interaction |
| `validate_ledge_hops.gd` | the eight hop codes, accepted directions, Route 30's ledge record and the two-cell landing, in both games |
| `validate_side_walls.gd` | the side-wall/side-buoy codes, their face masks and map census, in both games; Celadon Mansion Roof's fence and staircase landings on Crystal |
| `validate_cut.gd` | the cut block tables, the profile-split tileset numbers and cuttable-cell census, and Ilex Forest's tree, in all three games |
| `validate_surf.gd` | the surf sprites and music record, the surf-entry cell census, and New Bark Town's east shore, in all three games |
| `validate_whirlpool.gd` | the whirlpool block table, the forced-tile cell census, and Dragon's Den B1F's whirlpool, in all three games |
| `validate_strength.gd` | the strength-boulder census and Cianwood Gym's corridor push, in all three games |
| `validate_tmhm.gd` | the TM/HM move table, the item-number mapping past its two dummy items, the seven moves an HM teaches, and the whole species compatibility census, in all three games |
| `validate_command_queues.gd` | the two `stonetable` command queues, their pit warps and boulders, and a real Blackthorn Gym 2F push firing its fall script, in all three games |
| `validate_radio_tower.gd` | Blackthorn Gym's door and its only approach, Radio Tower 2F's stairs and 3F's card-key shutter, and the switch room's eleven doors and the one chain to the warehouse, in all three games |
| `validate_rising_badge.gd` | Blackthorn Gym 2F's boulders and holes, the 1F block changes that open Clair's room, the lake crossing to the Dragon's Den door, and Dragon's Den B1F's whirlpool and shrine landfall, in all three games |
| `validate_route_27.gd` | the forced step off a cave mouth, Route 27's sealed Kanto landfall and three seas, and the Tohjo Falls climb and ride back down, in all three games |
| `validate_item_balls.gd` | Ice Path 1F's HM07 and Route 44's balls decoding from the `itemball` macro, and Route 45's PP Up and Cerulean Gym's machine part from the `hiddenitem` macro, all reaching the bag once, in all three games |
| `validate_elite_four.gd` | the seven Indigo Plateau maps, the one door into the rooms, the prepare callback's flag reset, and each room's sealed entrance and boss-opened exit, in all three games |
| `validate_ss_aqua.gd` | the S.S. Aqua's B1F sailors and the coord events that toggle them, 1F's deck and west wing, the lazy sailor and the granddaughter, and the corridor before and after the errand that opens it, in all three games |
| `validate_vermilion.gd` | the Vermilion port passage's stair pair, the cut tree sealing the gym yard, the gym door's one approach, and the gym's own lack of a scene or callback, in all three games |
| `validate_saffron.gd` | Route 6's dead-end north connection and the gate that carries the crossing, Saffron Gym's nine rooms and fifteen self-warp pairs, and the one chain of pads that reaches Sabrina, in all three games |
| `validate_celadon.gd` | Saffron's dead-end west connection and its gate, Route 7's open connection onto Celadon, the city's only cut tree sealing the gym yard from either side, and Celadon Gym's three unavoidable sight lines, in all three games |
| `validate_cerulean.gd` | the Route 5 gate out of Saffron, Cerulean's single east crossing, Route 9's entry pocket and the Pokecenter yard its one cut tree opens, and the Power Plant's edgeless region, the buoy line that refuses a shore entry and the river that reaches it, in all three games |

```bash
# Crystal map 3/19: block edits, hidden object, facing interaction
godot --headless --path . -s res://tools/preview_world_story.gd -- crystal 3 19 3 5 1 37,1744
# bedroom PC and the bedroom-to-town warp chain
godot --headless --path . -s res://tools/preview_world_story.gd -- crystal 24 7 2 2 1 none home
# the full walked route, ending in the Hall of Fame
godot --headless --path . -s res://tools/preview_world_story.gd -- crystal 24 7 2 2 1 none home story
```

World text follows the cartridge command stream: `$50` is a page break, `$57`
ends a text box and `$58` pauses for a prompt. The story runner keeps the source
yes/no order, weekday wrapping and first eight temporary event flags, which
reset on a map reload.

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
| `game/mods/` | Mod manifest, host, installer and refusal wording |
| `mods/examples/` | Example mods to copy into `user://mods/`: a world renderer and a content mod |
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
