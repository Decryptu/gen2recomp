<p align="center">
  <img src="assets/brand/banner.png" alt="pokerecomp" width="820">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Godot-4.8.dev3-478CBF?style=flat-square&logo=godotengine&logoColor=white" alt="Godot 4.8.dev3">
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
> - **Import.** Every table below, resolved by a scene-free host without
>   reopening the ROM.
> - **Battles.** Parties, switching, running, stats, damage, accuracy, turn
>   order, status and substatus effects, trainer AI, experience, levelling, move
>   learning and capture, on a real 160x144 screen and the hardware tile grid.
> - **Overworld.** Real maps and connections, scripts, trainer battles, save-safe
>   blackout recovery, object lifecycle, followers, block edits, emotes, surf,
>   ledge hops, grass, fishing, roaming, repel and wild encounters, plus the
>   service overlay (marts, Kurt's errand, phone dispatch, music and cries).
>   Everything the overworld times is a hardware frame count spent by one clock,
>   so a seed, an input log and a frame number reproduce a walk exactly.
> - **A screen that fills the window.** The map is drawn past the Game Boy's
>   160x144 to whatever shape the window is, with the connected maps around it
>   drawn seamlessly and no black bars. Zoom out far enough and a region is on
>   screen at once. See [Screen fill](#screen-fill).
> - **Saves.** Three slots, `.sav` import, and a 14-box PC with 20 slots a box.
>   Every party transaction commits through a validated candidate save.
> - **Mods.** A mod under `user://mods/` can add or rebalance content, register
>   move effects, watch the world and battle event channels, add menu entries and
>   controls, and replace the world or battle renderer, which is what a 3D or HD
>   view needs.
>
> The story preview walks all three cartridges from Elm's lab to Red on Mt.
> Silver: every Johto badge with the errand behind it, then Kanto, all sixteen
> badges, the Hall of Fame with Prof Oak's rating, and the credits.
>
> Missing: link play, item mail and Mystery Gift, the Battle Tower, and a
> handful of pixel-level divergences still being chased in the opening movies
> and title screen against a real cartridge.

## Getting started

You need Godot 4.8 or newer. Enable the commit guard once per clone:

```bash
git config core.hooksPath .githooks
```

Put dumps in `roms/`, then verify them. See [roms/README.md](roms/README.md).

```bash
godot --headless --path . -s res://tools/verify_rom.gd
```

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

A few seconds per game. The cache is keyed by game and hash and lives in Godot's
`user://`, never in the project or an export. `--verify` checks without writing.

A cache is never migrated. An update that changes its format discards the old
one, and the launcher's manage sheet says so: import the same dump again. Saves
live under their own root and are not touched.

| Data | Contents |
|---|---|
| Species | Names, base stats, types, held items, egg groups, TM/HM flags |
| Learnsets, evolutions | All 251 species' level-up moves in cartridge order; every evolution and its method |
| Egg moves | Every species' inherited moves: 478 across 106 species on Gold and Silver, 480 across 105 on Crystal |
| Moves, TM/HM | Power, type, accuracy, PP, effect and chance; the 57 or 60 TM, HM and tutor rows; the happiness table teaching one moves |
| Items, types | 255 items with prices, effects, pockets and healing metadata; 28 type names |
| Type chart | Every matchup and the two Foresight-cancelled entries |
| Trainers, NPC trades | Class names, pics, palettes, AI flags, DVs and parties; trade records with DVs and OT data |
| Sprites, palettes | Front/back for 251 species and 26 Unown forms; normal and shiny 15-bit colours |
| Font, borders, HUD | 128 glyphs, eight text-box frames, HP/EXP bars and panels |
| Splash, title, intro | Each cartridge's opening art, tilemaps and palette runs, including Crystal's 35-entry intro section |
| Region map | Three graphics sheets, both region tilemaps, the per-tile palette map and 96 landmarks |
| Prof Oak's PC, credits | The 19 `OakRatings` rows and their texts; `CreditsScript`'s whole command stream |
| Overworld | Maps, tilesets, collisions, events, scripts, movement, palettes, animation and object sprites |
| Wild encounters | Grass, water and swarm tables, 13 fishing groups, the roaming graph, rates, slots and repel checks |
| World services | Menus, marts, fruit trees, phone contacts, special calls, bounded scripts and text, music, SFX and cries |
| Battle animations | 278 scripts, 188 objects, 185 framesets, 216 OAM sets, 39 graphics sheets and the sine table |

Sprites stay colour indices and receive a palette at draw time, so shiny
rendering needs no duplicate images.

## Running

```bash
godot --headless --path . --quit-after 30
```

The launcher is a shelf of three cartridges. An unimported bay is drawn in the
cartridge's own outline: drop a dump on it, or click to browse. Mods, settings
and about are in the dock underneath. It has a light and a dark appearance and
the same layout works on a phone.

Play opens the save screen: validated slots, naming, export and import, `.sav`
import, party inspection, and a save editor that cannot produce a save the game
will not load. A new game opens on the cartridge's own splash, GameFreak
animation, intro movie and title screen, then the gender question and Oak's
speech. Continue enters the overworld, where the start menu's SAVE writes its
map, inventory, event and clock snapshot. See [docs/SAVES.md](docs/SAVES.md).

The start menu wires every source entry: Pokedex, Pokemon, Pack, Pokegear,
Player, Save, Options and Exit. Options is the cartridge's own seven-row OPTION
screen over the same values the launcher's settings edit, so the two cannot
disagree. Pokedex has the three source orderings, type search and the
`<MON>'S NEST` area map. Pokegear draws all four of its cards on the hardware
tile grid, clock, map, phone and radio, each with its own dial, list and mode
arrow, and a tuned station keeps playing after it closes, which is how the Poke
Flute channel wakes Vermilion's Snorlax. Pack opens each item's own submenu: USE,
GIVE, TOSS and SEL, which registers an item to the SELECT button and uses it
from the map. The party submenu offers all eight field moves to a Pokemon that
knows one, and ITEM gives or takes what it holds.

Facing something and pressing A is the other way to every field move: a cut
tree, a whirlpool, a waterfall, a headbutt tree and open water each offer their
move in the cartridge's own order and words. Fruit trees bear once a day, Poke
Balls and hidden items are picked up by facing them, and the imported Players
House PC opens box storage. Walking into a new area raises Crystal's own map name
sign for sixty frames, which Gold and Silver never had.

Icons come from [Lucide](https://lucide.dev). See
[docs/THIRD_PARTY.md](docs/THIRD_PARTY.md).

## Controls

The games are played with the eight buttons the hardware had. A key, a
controller and the on-screen buttons all produce the same eight, so nothing in
the game knows which one you used.

| Button | Keyboard | Controller |
|---|---|---|
| Up, Down, Left, Right | Arrows, WASD | D-pad, left stick |
| A | `Z`, Space | Bottom face button |
| B | `X`, Escape | Right face button |
| START | Enter | Start |
| SELECT | Backspace, Shift | Back |

Keys bind by physical position, so WASD stays under the same four fingers on a
layout that spells them differently; settings shows each binding as the key
actually printed on it. Everything can be rebound, with as many keys and
controller buttons as you like, and a mod's own controls rebind the same way.

Any controller Godot recognises works without setup. On a touchscreen the games
draw a d-pad, A, B, START and SELECT, which appear while you touch the screen and
step aside on the next key press; settings can pin them on, turn them off and
arrange them separately for upright and sideways. Three quick taps brings them
back. The screen fills whatever window or device it is given, in either
orientation.

### Screen fill

A window is not the Game Boy's 10:9, and the black bars around a framed screen
are room the overworld can draw into. Settings > Application > Screen offers
two answers:

| Screen | What it draws |
|---|---|
| Fill (default) | The map covers the whole window at any shape, and the maps connected to this one are drawn around it |
| Framed | The 160x144 screen at a whole scale, centred, with black bars, as the hardware had |

Everything laid out on the screen -- text boxes, menus, the start menu, the
cursor -- stays inside the 160x144 rectangle in the middle of it, exactly where
the cartridge put it. Only the surround grows.

While walking, `+` and `-` zoom, `0` returns to the fitting scale, and the mouse
wheel does the same. Zooming out past one screen pixel per map pixel is a survey
of the region: the connection graph places the maps around this one and the map
header's own border block fills what no map covers. The maps around you are a
picture. Their people stand where their map puts them and nothing else about
them runs: no scripts, no walking, no wild encounters, no collision. Only the map
you are on is live, exactly as on the cartridge, where a connected map is three
blocks of scenery copied into the buffer and nothing more.

Development shortcuts are debug-build only, along with the map and cell readout:

| Scene | Keys |
|---|---|
| `game/render/pic_viewer.tscn` | left/right species, `S` shiny, `B` front/back, `T` trainer classes |
| `game/render/text_viewer.tscn` | Space advances, `F` cycles borders, `C` shows every glyph |
| `game/battle/battle_screen.tscn` | `T` turn, A advances, `Y` switch, `R` run, `[`/`]` matchup, `G`/`H` damage; in wild battles B opens the ball selector |
| `game/world/world_screen.tscn` | `F` fishes with an owned rod, `1`/`2`/`3` pick a rod, `P` opens the phone, `V` cycles views, F5 writes a snapshot |

Zoom is not one of these: `+`, `-` and `0` are player controls and work in a
release export.

A release export offers the eight buttons and nothing else. The method behind
each shortcut stays public, which is how `tools/preview_*.gd` drives them.

## Tools

Headless, and all against a real imported cache.

```bash
godot --headless --path . -s res://tools/validate.gd -- all
```

`tools/validate.gd` is the check suite: one topic per subject under
`tools/checks/`, each run against all three cartridges. Name topics or a group,
or `all`; with no argument it lists them.

| Group | Topics |
|---|---|
| `field_moves` | Cut, Surf, Whirlpool, Strength, Headbutt, Rock Smash and the faced-tile prompt chain |
| `terrain` | Ledge hops, side walls, every map's drawn blocks, the story's map ids |
| `johto` | Radio Tower, the Rising Badge, command queues, item balls, Route 27, the Magnet Train and long scripted scenes |
| `kanto` | Each city, its gym and the way in, from Vermilion to Mt. Silver |
| `art` | Both intro movies, the credits, the region map, all 278 battle animations, the map name sign |
| `tables` | TM/HM, naming, world scripts, the opening lane |
| `trainers` | The Route 30 trainer on each profile |

The rest are previews and dumps, each driving a real screen or table:

| Tool | Does |
|---|---|
| `dump_tables.gd <game> <table>` | Prints a decoded table: `species`, `moves`, `items`, `types`, `matchups`, `trainers`, `learnsets`, `egg_moves`, `evolutions`, `growth` or `all` |
| `preview_pics.gd <game> <png> [kind]` | Contact sheet of `front`, `trainers`, `font` or `frames` |
| `preview_*.gd` | One per screen: the intro, title, credits, Hall of Fame, region map, party, marts, fishing, battle switch and animations, overworld sprites and collision |
| `preview_world_story.gd` | Map entry callbacks, event-flag visibility, facing interactions and the whole story route |
| `replay_world.gd [game ...] [frames]` | Records `(frame, button)` from a real run and replays it into a fresh world; the same seed and log must reach the same snapshot, party and battle outcome byte for byte, at 30 fps and at 144. One route fights: a wild battle is spent from the world's own pump and steered through its own funnel |
| `render_audio.gd <game> <kind> <id> <frames> <prefix>` | One record or a whole table through the driver and APU: a WAV plus a per-frame register trace to diff |
| `screenshot.gd <scene> <png> [frames] [method]` | Any scene to PNG. Opens a window, so it is not headless |

```bash
# the full walked route: Johto, the Hall of Fame, every Kanto gym, and Red
godot --headless --path . -s res://tools/preview_world_story.gd -- crystal 24 7 2 2 1 none home story
```

## Tests

[GUT](https://github.com/bitwes/Gut) is in `addons/gut`; configuration is in
`.gutconfig.json`. Tests use synthetic files and a known SHA-1 vector, never a
real cartridge, so they run anywhere.

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gexit
```

That is the unit tier, and the default: more than 2,700 tests in well under a
minute. The scene integration tier drives real screens and is slower, so it is
asked for explicitly, which is how CI runs both:

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

Exit code `0` means all tests passed. Run one script with `-gselect=<name>`.

## Layout

| Path | Contents |
|---|---|
| `game/` | Feature folders with colocated scenes and scripts |
| `autoload/` | Project singletons |
| `assets/` | Authored or freely licensed assets; `assets/brand/` has its own README |
| `addons/` | Third-party plugins |
| `tests/` | `unit/` is the fast tier, `integration/` drives real screens |
| `tools/` | Headless developer scripts; `tools/checks/` are validate topics |
| `roms/` | User cartridges, excluded from Git and Godot imports |
| `mods/examples/` | Development-only example mods, excluded from exports |
| `docs/` | Contributor notes |

## Platforms

Windows, macOS, Linux, Android and iOS use GL Compatibility.
`export_presets.cfg` covers all five and writes into `builds/`. Install the
matching export templates first, then:

```bash
godot --headless --path . --export-release "Linux" builds/linux/pokerecomp.x86_64
```

Tests, tools and GUT are excluded, and `roms/` and the `user://` cache are not
reachable from an export. Signing identities are placeholders: set the bundle
identifiers, Android SDK paths and Apple team ID before publishing.

iOS forbids JIT and runtime native code, so mods must be interpreted GDScript,
not compiled extensions. The project is therefore GDScript-first. See
[docs/MODS.md](docs/MODS.md).

## Contributing

Read [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md). No cartridge-derived data may
enter the repository: no ROM, `.sav`, extracted sprites, text, maps or audio.
`.gitignore`, the pre-commit hook and tests enforce this; do not weaken them.
For reproducible comparisons with the upstream disassemblies, see
[docs/REFERENCES.md](docs/REFERENCES.md).

## Licence

[MIT](LICENSE) covers the engine source here, not the games or supplied dumps,
which remain the property of their respective owners.
