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
> - **Import.** Species, moves, items, types, the type chart, learnsets,
>   evolutions, palettes, every Pokémon sprite, trainer pics and parties, the
>   font, text-box borders, the battle HUD, maps, overworld menus, 34 mart
>   lists, phone contacts, special calls and music/SFX pointers. A scene-free
>   host resolves all of it without reopening the ROM.
> - **Battles.** Parties, switching, running, stats, damage, accuracy, turn
>   order, status and substatus effects, trainer AI, experience, levelling, move
>   learning and capture input on a real 160x144 screen.
> - **Overworld.** Real maps, map connections, script requests, trainer battles
>   with imported win/loss text, map reloads, save-safe blackout recovery,
>   object lifecycle, followers, block edits, emotes, surf, ledge hops, grass,
>   fishing, roaming, repel and wild encounters. The service overlay covers
>   menu selection, mart dialog variants and quantity purchases, Kurt's Apricorn
>   errand, source-timed
>   phone dispatch and bounded music, effects and cries. Everything the overworld
>   times is a hardware frame count spent by one clock, so a seed, an input log
>   and a frame number reproduce a walk exactly, on any display.
> - **Saves.** Three slots, `.sav` import, and a 14-box PC model with 20 slots
>   per box. Gifts, eggs, NPC trades, HP/status items, repel and captures commit
>   through a validated candidate save; a full party routes into the first free
>   box slot and full storage refuses atomically. Format 1 saves migrate without
>   inventing a world position.
> - **Mods.** A mod under `user://mods/` can add a species, move, item or trainer
>   class, rebalance one the cartridge shipped, register a move effect and the
>   steps it is built from, watch the world and battle event channels, add a menu
>   entry, declare which cartridges it is for, declare controls of its own that
>   rebind and reach a touchscreen like the cartridge's eight, and replace the
>   world or battle renderer, which is what a 3D or HD view needs.
>
> The real-data story preview walks all three cartridges end to end, from Elm's
> lab to Red on Mt. Silver: every Johto badge with the errand behind it (the
> Mystery Egg, Slowpoke Well, HM01 Cut and the Farfetch'd hunt, the
> SquirtBottle and Sudowoodo, HM03 Surf from the Kimono Girls, the SecretPotion,
> a Union Cave Geodude taught HM04 Strength for Cianwood Gym's boulders, the
> Lake of Rage, both Rocket hideouts, Blackthorn's boulder puzzle, and the
> Rising Badge by Crystal's Dragon Shrine quiz or Gold and Silver's Dragon's Den
> ball), then Kanto, all sixteen badges and Red.
> Missing: full story state, the dex, the remaining special-call branches and
> story-driven permanent contacts.

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
| Copyright screen | The splash graphic, its tile-code string and the GameFreak logo background palette |
| Battle HUD | HP/EXP bars, panel borders and colours |
| Overworld | Maps, tilesets, collisions, events, scripts, movement, palettes, animation and object sprites |
| Wild encounters | Normal/swarm grass and water, 13 fishing groups with day/night substitutions, 16-row roaming graph, map-linked rates and slots, time-of-day selection, surf variance and repel checks |
| World services | Referenced menus, mart inventories, the thirty fruit trees' fruit, phone contacts, special calls, bounded scripts/text, music, SFX, cries and shared waveform assets |
| Battle animations | All 278 animation scripts, the 188 objects, 185 framesets and 216 OAM sets they are drawn from, 39 decompressed graphics sheets and the sine table the motion callbacks scale with |

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

The launcher is a shelf of three cartridges, the selected one at full size in
the middle. An unimported bay is drawn in the cartridge's own outline: drop a
dump onto it, or click it to browse. Left and right move along the shelf; mods,
settings and about are the round buttons in the dock underneath. It has a light
and a dark appearance, following `ui_theme` in the options file, and the same
layout works on a phone.

Play opens the save screen: validated save slots created as you need them,
naming, export and import, `.sav` import, party inspection and the development
battle, plus a save editor for party, boxes, bag, flags, position and dex that
cannot produce a save the game will not load. A new game opens on the
cartridge's own copyright screen, for the hundred and ten frames `SplashScreen`
gives it, then the gender question and Oak's speech; it starts with an empty
party at the Crystal home spawn with source starting money, and Elm's imported
lab scripts offer Chikorita, Cyndaquil or Totodile at level 5 holding Berry.
Continue enters the overworld, and the start menu's SAVE writes its map,
inventory, event and clock snapshot. See [docs/SAVES.md](docs/SAVES.md) for the
save and SRAM contract.

Settings are split into appearance, application values, controls and the
cartridge's own OPTION values. The mods page can switch a mod off without
uninstalling it. The button beside Play carries re-import, the cache folder and
cache deletion; the about page holds the on-demand release check.

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

Keys are bound to positions rather than letters, so WASD stays under the same
four fingers on a layout that spells them differently; the settings page shows
each binding as the key actually printed on it. Every button can be rebound
there, with as many keys and controller buttons as you like. A mod's own
controls appear in the same place and rebind the same way, and can be switched
on as extra on-screen buttons for a phone.

Any controller Godot recognises works without setup, and the launcher is fully
navigable with one: the focus ring appears on the first pad or key press and
stays out of a mouse's way.

The launcher is used directly on a touchscreen, with no on-screen buttons over
it. The games draw a d-pad, A, B, START and SELECT instead, which appear while
you are touching the screen and step aside on the next key or controller press.
Settings can pin them on, turn them off for a phone with a controller attached,
and arrange them: drag each group under your thumbs and set the size and
opacity, separately for upright and sideways. Three quick taps on the game
screen brings them back.

The screen fills whatever window or device it is given, in either orientation.
Upright puts the game at the top with the buttons underneath; sideways centres
the game and puts the buttons in the margins either side.

Development scenes and shortcuts:

| Scene | Keys |
|---|---|
| `game/render/pic_viewer.tscn` | left/right species, `S` shiny, `B` front/back, `T` trainer classes |
| `game/render/text_viewer.tscn` | Space advances, `F` cycles borders, `C` shows every glyph |
| `game/battle/battle_screen.tscn` | `T` turn, A advances events, `Y` switch, `R` run, `[`/`]` matchup, `G`/`H` damage either side; in wild battles B opens the ball selector, left/right changes ball, A throws |
| `game/world/world_screen.tscn` | `F` fishes while facing water with an owned rod, `1`/`2`/`3` pick a rod, `P` opens the phone list directly, `V` cycles world renderers, F5 writes a snapshot |

Everything in that table other than the cartridge's own buttons is debug-build
only, along with the map and cell readout above and below the screen. A release
export offers the eight buttons and nothing else; the methods behind each
shortcut stay public, which is how `tools/preview_*.gd` drives them.

Battle-screen moves are random and a full move set declines the learn offer; use
`show_trainer(trainer_class)` for a real party and trainer AI, or `show_matchup`
for a fallback pairing.

The world screen's start menu wires every source entry: Pokedex, Pokemon, Pack,
Pokegear, Player, Save, Options and Exit.

- **Options** is the cartridge's own seven-row OPTION screen over the same
  values the launcher's settings edit, so the two can never disagree.
- **Player** is the trainer card, drawn from the cartridge's own graphics with
  its badge pages and play timer.
- **Pokedex** lists species in the cartridge's NEW, OLD and A to Z orders,
  showing a name once seen and a caught mark once caught, and opens each seen
  species' entry with its category, height, weight and both description pages.
  SELECT changes the order and the mode is saved; START searches by one or two
  types over species already caught. The Unown dex and the entry screen's AREA,
  CRY and PRNT buttons are not built.
- **Pokegear** opens its card list in the source's clock, map, phone, radio
  order, showing only owned cards; the map card keeps its position marked
  unavailable. The radio card tunes with left and right over the cartridge's
  two-step dial, and a tuned station keeps playing after the Pokegear closes,
  which is how the Poke Flute channel wakes Vermilion's Snorlax.
- **Pack** opens each item's own source submenu and can use one: a Potion asks
  which Pokemon and heals it, a Repel sets its step count. GIVE, TOSS and SEL
  keep their source position marked unavailable.

The party submenu offers Cut, Surf, Strength, Whirlpool, Waterfall, Flash,
Headbutt and Rock Smash to a Pokemon that knows one; all eight show their
message first and change the world on the acknowledge, and stepping from water
back onto land stops surfing. The last two have no badge behind them: for
Headbutt, facing a tree and knowing the move is the whole gate, and the
acknowledge rolls the tree's own encounter, which on Crystal can arrive asleep.
Rock Smash asks the faced object rather than the ground, and a smashed rock is
gone until the map reloads unless it carries an event flag.

Facing something and pressing A is the other way to all of them: a cut tree, a
whirlpool, a waterfall, a headbutt tree and open water each offer their move and
ask before using it, in the cartridge's own order, refusing in the cartridge's
own words or, for Headbutt and Surf, saying nothing at all. A Waterfall climb
runs the whole column in one command and ends on the first cell above it that is
not a waterfall. Standing on a whirlpool, waterfall, door, staircase or cave
tile overrides the pressed direction as the cartridge does, which is also how a
waterfall is ridden back down.

A fruit tree bears its own berry or apricorn once a day, refilling for every
tree at once the first time one is touched after the day turns, which is how
Kurt gets his Apricorns.

Poké Balls on the ground are picked up by facing them, and so are the items
hidden in scenery: neither pointer is a script, so each is decoded and its item
received. A hidden item answers only while its own event flag is clear, and
picking it up sets that flag.
The imported Players House PC opens the embedded box storage screen. The host
clock advances one game minute per real minute and crosses source day
boundaries. `preview_emote()`, `preview_wild_encounter()`,
`preview_fishing_battle()`, `preview_script_event()`, `preview_battle_request()`,
`preview_world_battle_loss()`, `preview_capture()` and
`preview_party_transaction()` drive their live paths; the API also exposes
swarm/roaming updates, repel countdowns and a JSON-safe snapshot.

Headless tools, all against a real imported cache. Every `validate_*.gd` runs
all three games unless its row says otherwise:

| Tool | Checks |
|---|---|
| `preview_world_services.gd <png> [mart\|apricorn] [presses]` | the mart or Kurt's Apricorn overlay, over a deterministic integration cache. `presses` is a comma-separated button list driven into the overlay before the shot, which is how the second box is photographed |
| `preview_fishing.gd <png> [game map]` | fishing, for example `silver 2 5`; one-argument form is a fixture smoke test |
| `preview_intro.gd <game> <png> [copyright\|gender\|speech\|beat] [steps]` | the new game's opening screens at hardware resolution: the copyright screen by source frame, the gender question, and any frame of `OakSpeech` by source frame or by button press, so a fade or a pic move can be looked at one frame at a time |
| `preview_mom_scene.gd <game> [png] [frame]` | `MeetMomRightScript` through the real world screen, frame by frame: the script's state, the object `applymovement` is walking and whether the text box is up. The frames the emote, the walk and the box first appear on are pinned per profile, so a run that moves one exits non-zero. `frame` picks which one the `png` is of |
| `preview_hall_of_fame.gd <game> <png> [page]` | the Hall of Fame induction panel against a real cache; `page` is how many panels to advance past |
| `preview_world_story.gd` | map entry callbacks, event-flag visibility, facing interactions and the story route |
| `replay_world.gd [game ...] [frames]` | records `(frame, button)` from a run of the real world screen and replays it into a fresh world, over every map of the spawn group on each cartridge. The same seed and log must reach the same `Gen2WorldSnapshot` byte for byte, and must reach it whether the frames were pumped at 30 fps or at 144 |
| `preview_collision.gd <game> <group> <number> <png>` | one whole map as drawn, with every walk cell's permission checkerboarded over it: red is wall, blue is water. For a report that the player can stand where they should not |
| `preview_overworld_sprites.gd <game> <png>` | every overworld sprite in a cache as one contact sheet, four facings across by four frames down, for eyeballing offsets, mirroring and frame order |
| `render_audio.gd <game> <music\|sfx\|cry\|mon_cry> <id\|all> <frames> <prefix> [stereo]` | one record, or the whole table, run through the sound driver and the APU: a WAV to listen to and a per-frame hardware-register trace to diff |
| `validate_story_map_ids.gd` | the four maps the story route names by id rather than by cell, each against the map its number holds on the other profile |
| `validate_crystal_route30_trainer.gd` | trainer record, sight line, approach, battle request, beaten flag, later interaction |
| `validate_ledge_hops.gd` | the eight hop codes, accepted directions, Route 30's ledge record and the two-cell landing, in both games |
| `validate_side_walls.gd` | the side-wall/side-buoy codes, their face masks and map census, in both games; Celadon Mansion Roof's fence and staircase landings on Crystal |
| `validate_cut.gd` | the cut block tables, the profile-split tileset numbers and cuttable-cell census, and Ilex Forest's tree |
| `validate_drawn_blocks.gd` | every map's whole padded rectangle, drawn from a loaded world and from its record alone, and how many padded blocks came off a neighbour rather than off the border block |
| `validate_field_move_prompts.gd` | the faced-tile prompt chain, both gates and all three answers for Cut, Surf and Headbutt |
| `validate_rock_smash.gd` | the rock map table, the smashable-rock census and its one flagged rock, and Cianwood City's rock |
| `validate_headbutt.gd` | the treemon map tables and sets, the profile-split set numbering, the headbutt-tree census, and Ilex Forest's tree |
| `validate_surf.gd` | the surf sprites and music record, the surf-entry cell census, and New Bark Town's east shore |
| `validate_whirlpool.gd` | the whirlpool block table, the forced-tile cell census, and Dragon's Den B1F's whirlpool |
| `validate_strength.gd` | the strength-boulder census and Cianwood Gym's corridor push |
| `validate_battle_anims.gd` | all 278 battle animation scripts run to their own `anim_ret`, POUND command by command, both shapes of the profile split in TACKLE and BODY SLAM, the object, frameset and OAM tables, the sine table the motion callbacks scale with, the 39 graphics sheets, and every motion callback and background effect a real animation reaches |
| `validate_tmhm.gd` | the TM/HM move table, the item-number mapping past its two dummy items, the seven moves an HM teaches, and the whole species compatibility census |
| `validate_command_queues.gd` | the two `stonetable` command queues, their pit warps and boulders, and a real Blackthorn Gym 2F push firing its fall script |
| `validate_radio_tower.gd` | Blackthorn Gym's door and its only approach, Radio Tower 2F's stairs and 3F's card-key shutter, and the switch room's eleven doors and the one chain to the warehouse |
| `validate_rising_badge.gd` | Blackthorn Gym 2F's boulders and holes, the 1F block changes that open Clair's room, the lake crossing to the Dragon's Den door, and Dragon's Den B1F's whirlpool and shrine landfall |
| `validate_route_27.gd` | the forced step off a cave mouth, Route 27's sealed Kanto landfall and three seas, and the Tohjo Falls climb and ride back down |
| `validate_item_balls.gd` | Ice Path 1F's HM07 and Route 44's balls decoding from the `itemball` macro, and Route 45's PP Up and Cerulean Gym's machine part from the `hiddenitem` macro, all reaching the bag once |
| `validate_elite_four.gd` | the seven Indigo Plateau maps, the one door into the rooms, the prepare callback's flag reset, and each room's sealed entrance and boss-opened exit |
| `validate_ss_aqua.gd` | the S.S. Aqua's B1F sailors and the coord events that toggle them, 1F's deck and west wing, the lazy sailor and the granddaughter, and the corridor before and after the errand that opens it |
| `validate_vermilion.gd` | the Vermilion port passage's stair pair, the cut tree sealing the gym yard, the gym door's one approach, and the gym's own lack of a scene or callback |
| `validate_saffron.gd` | Route 6's dead-end north connection and the gate that carries the crossing, Saffron Gym's nine rooms and fifteen self-warp pairs, and the one chain of pads that reaches Sabrina |
| `validate_celadon.gd` | Saffron's dead-end west connection and its gate, Route 7's open connection onto Celadon, the city's only cut tree sealing the gym yard from either side, and Celadon Gym's three unavoidable sight lines |
| `validate_cerulean.gd` | the Route 5 gate out of Saffron, Cerulean's single east crossing, Route 9's entry pocket and the Pokecenter yard its one cut tree opens, the Power Plant's edgeless region, the buoy line that refuses a shore entry and the river that reaches it, and Cerulean Gym's pool with the three swimmer approaches that cross it |
| `validate_lavender.gd` | Saffron's east gate, Route 8's single east crossing and the eight ledges that leave only one of its five sight lines unavoidable, Lavender Town's flypoint and its two open edges, and the EXPN CARD the Kanto Radio Tower withholds until the Power Plant runs |
| `validate_fuchsia.gd` | the four connected routes south of Lavender and which of their eighteen sight lines each profile's walk cannot route around, the Route 15 gate, Fuchsia City's region behind it, and Fuchsia Gym's wall maze with no sight trainer in it |
| `validate_radio.gd` | the radio station table and its three profile splits, every station's music record, the two big objects either game ships, Vermilion City sealed at the Diglett's Cave mouth by the Snorlax's two-by-two body, the whole tune-and-wake chain, and the Route 2 pocket behind the cave that one cut tree opens onto Pewter and Viridian |
| `validate_pewter.gd` | Fuchsia's gate out and the five ungated connections back to Vermilion, the eight-cell pocket the Snorlax seals off the Route 11 crossing, Diglett's Cave's three regions and two ladders, Route 2's crossing onto Pewter once its tree is cut, and Pewter City's one south corridor and the gym sight line it owes |
| `validate_cinnabar.gd` | the four connections from Pewter down to Pallet, Pallet's pond and the south edge that only crosses while surfing, Route 21's sea, Cinnabar's two seamless land regions and which crossing reaches Blue, Route 20's sealed west channel and the east landfall behind it, Seafoam Gym, and Viridian Gym's two objects behind one event flag |
| `validate_magnet_train.gd` | the twelve doors over the lost-doll errand and both rides, the Copycat standing in her cell before any script has assigned her variable sprite, the Fan Club's Clefairy guy and the doll behind his own flag, and both Magnet Train stations as a lobby and a platform with no walkable seam between them |
| `validate_mt_silver.gd` | the nine doors from Viridian Gym to Silver Cave Room 3, Viridian's west connection and Route 28's, Oak's lab, the Victory Road Gate's three regions and the black belt standing in each of the two cells that join them across all four flag combinations, Silver Cave Outside and its flypoint, the Pokecenter counter, each cave room as one region, and Red behind his own hide flag |

```bash
# Crystal map 3/19: block edits, hidden object, facing interaction
godot --headless --path . -s res://tools/preview_world_story.gd -- crystal 3 19 3 5 1 37,1744
# bedroom PC and the bedroom-to-town warp chain
godot --headless --path . -s res://tools/preview_world_story.gd -- crystal 24 7 2 2 1 none home
# the full walked route: Johto, the Hall of Fame, every Kanto gym, and Red
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
| `mods/examples/` | Development-only example mods to copy into `user://mods/`; excluded from exports |
| `docs/` | Contributor notes |

## Platforms

Windows, macOS, Linux, Android and iOS use GL Compatibility.
`export_presets.cfg` covers all five and writes into `builds/`. Install the
matching export templates first, then:

```bash
godot --headless --path . --export-release "Linux" builds/linux/pokerecomp.x86_64
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
