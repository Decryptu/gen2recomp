# Mods

A mod is interpreted GDScript in a directory under `user://mods/`. iOS forbids
JIT and loading native code at runtime, so a distributed mod cannot be a
compiled extension.

Mods never touch scene nodes or engine internals. A mod is handed
`Gen2ModHost`, registers what it provides, and returns. Everything it can reach
is cartridge content through `GameData` or live world state through
`Gen2WorldAPI`, both of which are scene-free.

`GameRuntime` discovers and loads every installed mod before the first screen
exists, creating `user://mods/` when it is absent. The launcher lists what
loaded and names anything it refused.

A mod can be switched off without uninstalling it. `Gen2ModState` keeps the
disabled ids in `user://mods_disabled.json`, and only `load_discovered()`
consults them: a disabled mod is still discovered and still listed, it just
does not run, and that is not a refusal. Disabled ids are stored rather than
enabled ones, so a newly installed mod runs without an entry being written for
it and a damaged file means everything runs rather than nothing. Uninstalling
drops the id, so reinstalling later does not find it silently off.

## Layout

```
user://mods/<id>/
  mod.json
  mod.gd
```

`mod.json`:

| Field | Meaning |
|---|---|
| `id` | Lowercase `[a-z0-9][a-z0-9_-]*`; addresses the directory and registry keys |
| `name` | Shown to the player |
| `version` | The mod's own version, not the host's |
| `api_version` | Must equal `Gen2ModManifest.API_VERSION` |
| `entry` | A `.gd` path inside the mod directory, or inside the pack when there is one |
| `pack` | Optional `.pck` or `.zip` beside `mod.json`, holding the mod's files |
| `description` | Optional |
| `dependencies` | Optional object from required mod ids to SemVer ranges |
| `games` | Optional list of cartridge ids the mod is for |

`version` is a strict `major.minor.patch` number. Dependency ranges accept an
exact version, `*`, component wildcards such as `1.x` or `1.4.*`, comparison
chains such as `>=1.2.0 <2.0.0`, and caret or tilde ranges such as `^1.2.3` and
`~1.2.3`. Dependencies load first. A missing, disabled, incompatible or failed
dependency, and every member of a dependency cycle, is refused by name before
the dependent entry script runs.

`games` is `RomRegistry` ids: `["gold", "silver", "crystal"]`. Absent or empty
means every cartridge the host knows, which is what a manifest written before
this existed says. A cartridge the mod does not name refuses the mod at load, by
name, and the launcher's card prints what a mod is for before Play is pressed.
Ids the host has never heard of are not refused when the manifest is read: a mod
that also names a cartridge a later launcher will ship has to install today, and
naming only such an id simply means it never runs here. There is no generation
shorthand, because a generation is not a fact the registry holds about a dump,
and a list of ids stays right when the launcher gains one.

An entry that is absolute, contains `..` or is not GDScript is refused before
anything runs. Manifests are read without executing mod code, so a launcher can
list what is installed and say why something was rejected.

A mod may ship its scripts and resources in a resource pack instead of loose
files. `pack` names a `.pck` or `.zip` beside `mod.json`, exported from
`res://mods/<id>/`, and `entry` is then a path inside that root:

```
user://mods/voxel/
  mod.json      { "pack": "content.zip", "entry": "mod.gd", ... }
  content.zip   mods/voxel/mod.gd, mods/voxel/renderer.gd, ...
```

`mod.json` itself stays a plain file, so the launcher lists a packed mod and can
refuse it without mounting anything. The pack is mounted only when the mod
actually loads, with `replace_files` false, so it can add paths and never land on
one the game itself ships. A pack that names a path rather than a file beside the
manifest, or that is neither `.pck` nor `.zip`, is refused when the manifest is
read.

```gdscript
extends RefCounted

func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	host.register_world_renderer(manifest.id, load("%s/renderer.gd" % manifest.directory), "Voxel")
```

A mod that fails to load is reported through `Gen2ModHost.failures()` and
skipped. One broken mod does not stop the others and does not stop the game.

Two example mods are in `mods/examples/`, to copy into `user://mods/`:

| Mod | Shows |
|---|---|
| `voxel_preview/` | A world renderer. Press `V` in the overworld; it reads the same collision, block and palette data the 2D view reads and extrudes geometry from it, on the native layer with a translucent text box and one registered setting |
| `new_content/` | A species, a move, a move effect, two rebalancing patches and both event channels |

The repository examples are development material and are excluded from every
export preset. A distributed build contains the loader but no preinstalled mod;
players install their own copies under `user://mods/`.

## Installing

The launcher takes a `.zip` on every platform, through **Install** on its mods
page or by dropping the archive on the window where the OS offers that. The archive holds
one mod, at its root or in a single folder:

```
voxel_preview.zip
  voxel_preview/
    mod.json
    mod.gd
```

An archive is refused whole if it has no `mod.json`, holds more than one mod
folder, declares another `api_version`, or names a path that would write outside
its own folder. Nothing is written until all of that passes, so a refusal leaves
what is already installed untouched. Reimporting a mod that is present asks
first, and replacing one removes files the new version dropped rather than
leaving them behind.

Mods load the same way in an exported build as in the editor: the entry script
is plain GDScript read at runtime, even though the game's own scripts ship as
binary tokens. An installed mod loads immediately, without a restart, and so
does a change to the list: switching one on or off, deleting one, or choosing a
different cartridge reloads every mod against a fresh host.

`user://mods/` is the platform's `app_userdata/pokerecomp/mods` on desktop, the
app's `Documents/mods` on iOS (reachable in the Files app, since the export sets
`UIFileSharingEnabled`), and internal app storage on Android, where the system
file picker is how an archive gets in.

## Publishing a source

A source is a JSON feed listing mods that stay in their authors' own
repositories. Anyone can publish one, and the game follows none until a player
adds it, because following a source is trusting whoever publishes it.

```json
{
  "schema_version": 1,
  "name": "Example mods",
  "mods": [
    {
      "id": "voxel_preview",
      "name": "Voxel Preview",
      "version": "1.0.0",
      "description": "Draws the map as geometry.",
      "download": "https://example.com/voxel_preview-1.0.0.zip"
    }
  ]
}
```

`schema_version` must be exactly the version the build reads, because a later
format may reuse a field name for something else. Feeds and downloads are https
only: over plain http anyone on the path could rewrite where a download points.
A row with no `id`, no usable `download`, or an id that is not a legal mod id is
dropped, and the rest of the listing still works.

Pasting `owner/repo`, the repository page, a site root or the feed file all
resolve to the same feed, `https://<owner>.github.io/<repo>/index.json` for a
GitHub slug.

A listed mod installs through the same path an imported `.zip` does, and its
manifest id must match the one the feed advertised, so a listing grants a mod
nothing that picking the same file by hand would not.

A row whose `version` is newer than the installed copy's says so and offers
**Update** rather than **Reinstall**, and the status line counts how many the
listing offers. Both sides have to be strict `major.minor.patch` numbers to be
compared: a version a feed made up is reported as uncomparable rather than
guessed at, and a listing older than the installed copy is neither an update nor
an error.

Each feed's last listing that parsed is kept under `user://mod_index_cache/`. It
is what the mod list is built from, so the list opens instantly and offline and
the network is only ever asked when the player asks for it, on **Sources**. A
fetch that fails leaves the copy on disk up with its age said on the status
line. Unfollowing a source drops its cached copy with it.

The launcher's mod list is grouped by where each mod came from: a source that
lists a mod's id owns it, and a mod no source lists came from a file. That is
the whole rule and nothing records it, which is what makes removal mean two
different things. Removing a mod a source lists uninstalls it and leaves the row
behind offering the download again; removing one that came from a file deletes
the only copy there was, and is confirmed first. A mod listed by two sources
belongs to the first one followed, so it is on screen once.

## Adding content

`mods/examples/new_content/` registers a species, a move, a move effect and two
rebalancing patches, and watches both event channels. Copy it and read it beside
this section.

A content number is per kind and starts at `Gen2ContentOverlay.FIRST_MOD_NUMBER`,
which is 256. Every cartridge number fits in a byte, so a number that does not is
unambiguously not the cartridge's, and a mod's own numbers mean the same thing on
Gold, Silver and Crystal. Four kinds are numbered this way: `KIND_SPECIES`,
`KIND_MOVE`, `KIND_ITEM` and `KIND_TRAINER`. Types are not reachable at all,
because the matchup lookup keys on the type count and a twenty-ninth type would
renumber every pair in the chart.

```gdscript
host.register_content(Gen2ContentOverlay.KIND_SPECIES, manifest.id, 256, {
	"name": "VOLTLING",
	"stats": {"speed": 115},
	"learnset": [{"level": 1, "move": 33}, {"level": 36, "move": 85}],
})
```

A definition is partial. Whatever it leaves out comes from the kind's defaults,
which exist because readers index these rows directly: `palette.normal` and
`front_tiles` are read without asking whether they are there, so a definition
that omitted either would crash the reader rather than draw wrong.

Everything a species carries is a field on the one row, so a learnset, an
evolution and TM compatibility are part of the definition rather than three more
registrations. The engine then reads them the way it reads Pikachu's, because
every content read in the game goes through one place, `GameData._content()`.

`patch_content()` changes a row the cartridge does have. Only the fields named
change, and a Dictionary field merges, so patching one stat leaves the other five
alone. A patch of a number this cartridge lacks changes nothing rather than
inventing a row, which is what keeps a mod that patches Crystal's MYSTICALMAN
from conjuring one on Gold.

`KIND_ENCOUNTER` and `KIND_FISHING` are the cartridge's wild tables. They are
patched and never defined, since a mod can add neither a map nor a map header,
and their numbers are table coordinates rather than content numbers. Patch them
through the two helpers rather than counting the coordinate out yourself:

```gdscript
host.patch_encounter(manifest.id, &"grass", 3, 2, {
	"rate": 20,
	"slots": [[{"level": 50, "species": 1}], [], []],
})
host.patch_fishing_group(manifest.id, 1, {"rods": [...]})
```

An encounter row is what `GameData.world_encounter(method, group, number)`
answers, and the patched row is what every reader gets, including the region
walk `FindNest` uses. The method is one of `grass`, `surf`, `swarm_grass` and
`swarm_water`. `slots` and `rates` are arrays and replace whole; patching a map
this cartridge lacks changes nothing, exactly as a species patch does. The
treemon sets, the Bug Contest list and the roaming mons are not patchable yet.

Counts: `species_count()`, `move_count()` and `trainer_count()` are the
cartridge's own runs. Mod numbers are not part of them and are enumerated with
`Gen2ContentOverlay.defined_numbers(kind)`.

Two mods claiming one number is refused and named, rather than decided by load
order. `Gen2ContentOverlay.owner_of()` says which mod won a number.

What content does not get: a pic. The atlases are decoded from the cartridge and
hold its own 251 slots, so a defined species draws nothing until a renderer draws
it. `Gen2SramAdapter` cannot export a mod species to a real `.sav` either, since
the cartridge stores a species in one byte; the project's own save is JSON and
carries them fine.

## Adding a move effect

A move's effect byte is a number until something answers for it.
`Gen2MoveEffect` holds the cartridge's lists and `Gen2EffectCommands` the steps
one is built from; a registration is a list of those steps.

```gdscript
host.register_move_effect(manifest.id, 0xF0, [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.RECOIL,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.END_MOVE,
])
```

A list naming a step nobody wrote is refused at registration, where the mod's id
is still in hand, rather than pushing an error in the middle of a turn.
`register_effect_command()` adds a step of your own, as a Callable taking the
`Gen2Turn`; it cannot take a name the engine already uses, so a registration can
never quietly change what every move in the game does.

A registered effect replaces the cartridge's list for that byte, which is how a
mod rewrites Sleep rather than only adding to the table.
`Gen2MoveEffect.RESERVED_EFFECTS` is the exception: the multi-hit, fixed-damage,
Rollout, Selfdestruct, time-based heal and the two screen bytes are read back off
the turn by their own commands, so replacing one would leave that command
answering for a list it is no longer in.

## Watching what happens

`subscribe(channel, id, handler)` on `Gen2ModHost.CHANNEL_WORLD` or
`CHANNEL_BATTLE` calls `handler` with each event dictionary as the screen showing
it reads it, so a subscriber sees what the player sees, in that order.

Reading only. The handler is given a copy and nothing reads its return value:
observation cannot make two mods fight over the same state, which is what makes
this safe to hand out before any mutation hook exists. Events are published from
the screens, so a headless tool or a test driving the engine directly fires none.

## Replacing the world renderer

Nothing about the world requires that the drawing be 2D: maps are node-free
`RefCounted` records, each tileset is one addressable atlas, animated tiles
replace atlas slots rather than map rectangles, and collision is a raw
permission byte per 2x2 walk cell. A renderer that extrudes geometry from that
same data is a registration, not a fork.

A registered renderer is a `Node` providing:

| Method | Called when |
|---|---|
| `set_world(world, animation)` | The map changed, or the view was created |
| `set_time_of_day(time_of_day)` | The clock crossed 04:00, 10:00 or 18:00 |
| `refresh()` | The player, an object or an event changed something |
| `refresh_animation()` | A tileset animation command changed tile data |

Registration is refused, by name, if any of these is missing or the script is
not a `Node`, rather than failing on the first drawn frame.

Two methods are optional, on either renderer kind:

| Method | Effect |
|---|---|
| `uses_hardware_viewport() -> bool` | Answering false moves the renderer off the 160x144 hardware viewport onto the screen's own rectangle at window resolution |
| `set_native_size(size: Vector2i)` | The native layer's size in window pixels, on creation and on every window change |
| `interface_opacity() -> float` | How opaque the screen draws the field of its own text box, 0 to 1 |
| `set_text_box_rect(rect: Rect2i)` | Where that box is, in hardware pixels, on every change and empty when none is on screen |

A view built out of geometry cannot be drawn into a 160x144 buffer and then
magnified, so the second layer is what makes a 3D or HD renderer possible at
all. Text boxes and menus stay hardware pixels over the top: the world gains
resolution, the interface stays a Game Boy.

The box is drawn opaque, as the cartridge draws it. `interface_opacity()` asks
for the field behind it to be drawn through, and only the field: the frame and
the glyphs stay ink, so nothing a renderer asks for makes text harder to read.
Around 0.75 reads well over a map. It is honoured only for a renderer that
answered `uses_hardware_viewport()` false, since one drawing in hardware pixels
paints the background itself and a hole would show the window behind the screen.

`set_text_box_rect` is the same box measured rather than styled, pushed on every
change including the empty rectangle when it goes away. The standard box is
twenty by six at row twelve, but a box can be any size and is not always up.

The world's own menus are not this box: the start menu, pack, party and PC are
window-resolution panels with their own scrim, so a renderer neither sees nor
styles them. `Gen2MenuPage` is the cartridge box path, used by the naming and
gender screens, neither of which is ever over a renderer.

A world renderer has a third:

| Method | Effect |
|---|---|
| `handle_world_input(event: InputEvent) -> bool` | Every input event the world screen did not use. Answering true consumes it |

The screen claims what it needs and offers the rest, so camera pitch, first
person and free-roam are all reachable while a movement or interaction key never
arrives: a renderer reads world state and must not write it, and moving the
player is writing it. Free-roam movement is the pose layer below, not this. An
open overlay, a running script, a battle or a trainer approach takes the event
first, exactly as it does for the screen's own keys.

Implement this rather than Godot's `_input` or `_unhandled_input`. A node in the
tree is offered events before the screen decides what it needs, so a renderer
reading them directly races the gameplay keys instead of taking what is left of
them.

### The tileset atlas

`GameData.world_tileset_indices(number)` is one tileset's graphics as a single
indexed strip, `Gen2WorldTileset.tile_count` tiles wide and eight tall, one byte
of colour index per pixel. Every number a block can name indexes it directly:
`Gen2WorldTileset.tile_index(block, tile)` is the strip slot, and
`Gen2WorldPalette.tile_palettes()` answers one palette per slot in the same
order.

The cartridge loads a tileset's graphics as two blocks of 96 tiles into separate
VRAM banks, and a metatile byte with the high bit set names the second. The strip
carries both, at the cartridge's own numbering: block 0 at 0 to 95, block 1 at
128 to 223, and the 32 tiles between them are the font's, always blank here. A
tileset that ships only one block leaves 128 to 223 blank. Nothing needs to know
which block a tile came from; the number is enough.

`Gen2WorldAnimation` rewrites slots in this strip, so a renderer texturing from
it follows water and flowers without knowing an animation ran. That is also why
geometry cut from the strip is cut from one arbitrary frame:
`tile_frames(tile)` answers every frame a tile is ever drawn as, in play order,
each entry that tile's sixty-four palette indices row by row, with the tileset's
own tile first and an empty array for a tile no command touches. It does not
advance the live sequence, since the running game shares the object. Ask it once
per animated tile when a map resolves, and let a mesh span the union.

### Asking what a cell is

`Gen2WorldAPI.collision_code_at(cell)` is the raw cartridge byte, and
`Gen2WorldCollision` answers what the source asks of it. Read a predicate rather
than a tile number: a pin by drawing is per tile id and per tileset, and the
cartridge's own answer is per cell.

| Call | Source |
|---|---|
| `permission_for(code)`, `is_walkable(code)` | `CollisionPermissionTable` |
| `talks(code)` | The same table's `TALK` bit |
| `grass_kind(code)`, `is_grass(code)`, `is_long_grass(code)` | `SetTallGrassFlags`, which is `CheckSuperTallGrassTile` then `CheckGrassTile` |
| `allows_hop(code, direction)` | `.TryJump` |
| `is_warp_tile(code)`, `is_pit_tile(code)` | `CheckWarpCollision`, `CheckPitTile` |
| `side_wall_face_mask(code)` | `GetMovementPermissions` |

`grass_kind` returns `GRASS_NONE`, `GRASS_TALL` or `GRASS_LONG`, because the
cartridge keeps the two apart: the long grass is its own pair of codes and the
Bug Contest doubles its encounter rate. It is `IN_GRASS_F`, not the encounter
gate; `CheckGrassCollision` is that one and it includes water, since one routine
gates a surf roll too.

### The drawn block of a map that is not open

`Gen2WorldAPI.drawn_block_at(x, y)` is the block a coordinate is drawn from
rather than the block that is stored there: `LoadMetatiles` substitutes the
map's border block for a `$00` byte, and `FillMapConnections` fills three blocks
of padding around the map with a neighbour's art where a connection reaches.

A caller with no world reads the same fold through
`Gen2WorldAPI.drawn_block_for(data, map, x, y)`. That is what a battle has: a
`Gen2BattleWorldContext` names the map and hands over no world, deliberately, so
an arena built from `GameData` records asks the static. The instance method calls
through to it, so the strip geometry and the north/south/west/east order at an
overlapping corner exist once. `tools/checks/drawn_blocks.gd` sweeps every map
of every cache over its whole padded rectangle and refuses a disagreement.

Live `changeblock` edits are the loaded world's own and are not visible to the
static form, which is correct for a map nobody is standing on.

## Framing the view

`Gen2WorldAPI` offers a camera; it does not impose one.

| Method | Value |
|---|---|
| `player_position_cells() -> Vector2` | The committed cell plus any in-flight step, in walk cells |
| `visible_origin_cells() -> Vector2` | The framed view's top-left in fractional walk cells, centred on that position and clamped to the map |
| `visible_origin_cell() -> Vector2i` | The hardware page origin, which follows the committed cell |

`player_cell` commits at the start of a step, so the hardware page origin moves a
whole cell the instant one begins. That is what the 160x144 tile page wants and
what a camera does not: following it pans a step early.
`visible_origin_cells()` frames the interpolated position instead, and the two
agree whenever no step is in flight. A renderer that frames its own view, which
is what a free camera is, can ignore all three and read
`player_position_cells()` and `map_size_cells()` directly.

The host constructs a renderer per world, so `select_world_renderer()` can
switch between the built-in `gen2` renderer and a mod's while the game runs.
`Gen2WorldScreen.cycle_world_renderer()` is that switch, bound to `V`: the map,
the player and any running script are untouched, because a renderer reads world
state and must not write it. Two views of one world have to agree.

## Replacing the battle renderer

The same boundary covers battle presentation. `Gen2BattleScreen` owns the
battle, the events and the text box; it decides nothing about how a Pokémon,
a panel or a bar is drawn. A registered battle renderer is a `Node` providing:

| Method | Called when |
|---|---|
| `set_battle_data(data) -> bool` | The screen is ready, before the first view; a false return leaves the screen not ready |
| `set_view(view: Dictionary)` | The screen has new plain display values to show |
| `refresh()` | The renderer should redraw its current view |

`view` carries `enemy_species`, `player_species`, `enemy_name`, `player_name`,
`enemy_level`, `player_level`, `battle_kind`, `trainer_class`, `trainer_index`,
`trainer_name`, `enemy_hp`, `enemy_max_hp`, `player_hp`,
`player_max_hp`, `exp_pixels`, `raster_scx`, `raster_scy`, `player_pic_visible`,
`bg_map`, `bg_palette_maps`, `ob_palette_maps`, `anim_sprites`, `anim_tiles` and
`hud_visible`: plain values read out of a resolved battle event, never the
battle engine itself, the same rule `Gen2BattleScreen`'s own setters already
followed.

`battle_kind` is `wild` or `trainer` and the three fields after it say who the
fight is against, which the species and levels do not. A wild battle carries
class 0, index 0 and an empty name, the way `wOtherTrainerClass` is zero there.
A class number is what `GameData.trainer_pic()` and `trainer_name()` take, so a
renderer standing the opponent behind their Pokémon draws the cartridge's own
picture of them; `trainer_name` is the trainer's own name from the party record,
not the class name. `exp_pixels` is a
count out of 64, which is `PlaceExpBar`'s own unit; the exp bar is never a
ratio, because `CalcExpBar` has already done the division and rounded it the
cartridge's way.

`raster_scx` is the background's own horizontal scroll, one value per scanline
in the order the hardware draws them, and empty whenever the background is
sitting still, which is every frame outside the opening slide. An offset is a
distance to look *right* into a background map 256 pixels wide against the
screen's 160, so a larger one puts the drawn content further left and the map's
blank columns wrap in behind it. `Gen2Raster.scroll(image, offsets, 256)` is
that operation and is what the built-in renderer applies to each of its layers;
a renderer that ignores the field simply draws no slide. `player_pic_visible`
is false for exactly that stretch, because `InitBattleDisplay` places the
player's back pic with `PlaceGraphic` only after `BattleIntroSlidingPics` has
returned, so during the slide it is not on the map to be scrolled. `raster_scy`
is the same thing vertically, which only a battle animation ever asks for;
`Gen2Raster.scroll_rows(image, offsets, 256)` is that operation.

The last six fields are the battle animation layer. `bg_map` is `wTilemap`, a
20 by 18 grid of tile ids naming which tile of which battler's picture sits in
each cell: `$00` up is the enemy's front pic and `$31` up the player's back pic,
each `base + column * side + row`, and everything else is blank. A renderer
draws the two pictures out of that map rather than at a fixed corner, because
the map is what a battle animation edits, and `Gen2BattleScreenMap` is where the
constants and the plain seeding live. `bg_palette_maps` and `ob_palette_maps`
are eight DMG palette bytes each: colour `i` of palette `n` is drawn as colour
`(byte >> i * 2) & 3` of whatever the battle loaded, which is `CopyPals`. A
renderer that ignores all of it draws a battle with no animation in it.

`anim_sprites` is `wShadowOAM` as the animation left it, up to forty
`{ y, x, tile, attributes }` entries with the hardware's own byte values: OAM
subtracts sixteen and eight, so a `y` or `x` of zero is off screen, and the
attributes carry the x and y flips and the object palette slot. `anim_tiles`
says where each tile of the animation window came from, as
`{ gfx, tile }` counted from `Gen2BattleAnimObject.BASE_TILE`, so an OAM tile id
below that base is not an animation tile at all. `hud_visible` is false for the
length of a move animation, which is `BattleAnimClearHud` taking the panels and
both bars off the map and `BattleAnimRestoreHuds` putting them back.

The two HP values and `exp_pixels` are the *drawn* ones, not the committed ones:
a hit drains the bar over roughly a second the way the cartridge does, an award
fills the exp bar over one, and `set_view` is called again on every step of
either. A renderer that wants a bar to move needs no work; one that wants the
final number should wait for the animation to end rather than reading the view,
since mid-animation it is deliberately not the real value.

Registration uses the same refusal rules as a world renderer, and shares both
optional methods (`uses_hardware_viewport()`, `set_native_size()`) and the `V`
cycle, bound in `Gen2BattleScreen` the way `Gen2WorldScreen` binds it.

A battle renderer has two optional methods of its own:

| Method | Effect |
|---|---|
| `set_world_context(context: Gen2BattleWorldContext)` | Where the battle is being fought, once per battle, after `set_battle_data` and before the first view |
| `handle_battle_input(event: InputEvent) -> bool` | Every input event the battle screen did not use. Answering true consumes it |

`handle_battle_input` is `handle_world_input`'s twin and follows the same rule:
the screen claims what it needs and offers the rest, so a renderer can steer a
camera and can never take a gameplay press. A `Gen2Button` is routed to whatever
owns the screen before this is reached, on both sides, so the text box, the
forget-move list, the pack's own rows and ball selection each take their press
first and what arrives here is pointer and stick motion. Those three also
withhold everything else while they are up, because a press there means
something by itself. A draining bar, the opening slide and a move animation do
not: none of them reads input, and a camera that stalls whenever a bar drains is
not a camera.

`view` says what is on the field and nothing about the place, which is right for
the cartridge's white field and leaves a renderer staging the fight on the map
with nowhere to stage it. `Gen2BattleWorldContext` is that place, and it carries
`map_id` (group and number), `tileset`, `player_cell`, `player_facing` and
`time_of_day`, the last being the row the world was *drawn* with rather than the
clock's, so a battle entered from an unlit cave is staged in the dark.

It is a copy taken when the battle starts, not a handle on the world: a renderer
cannot reach live world state through it, and the two screens stay independent.
The map and tileset are numbers, which is what `GameData.world_map()` and
`world_tileset()` take, so a renderer resolves whatever records it wants through
the `GameData` it already has. A battle started outside the world, which is
every development driver, supplies none and the method is not called.

## Logical world state and optional mod pose

The game stays logically grid-based. The player and NPCs occupy walk cells,
movement commits one cell at a time in the four cardinal directions, and
interactions use the current logical cell plus one cardinal facing. Animating a
sprite between cells does not change that model.

A movement mod may add a more precise pose for smooth, analog, first-person or
3D movement, with a sub-cell position and an arbitrary facing angle. It is an
extra layer, not a replacement: the core world stays responsible for collision,
cell transitions, map triggers, warps and script or NPC interactions, and a mod
must not overwrite the authoritative cell or bypass those boundaries.

When a mod requests an interaction it projects its pose back onto the normal
rules: resolve a deterministic logical cell, quantize the facing angle to one of
the four source directions using the source tie-breaking, and pass both to the
existing interaction path. Smooth movement then leaves an NPC in the
neighbouring cell interacting exactly as it would on the cartridge.

## Measured against the voxel mod

[DramaticShapeVoxelMod](https://github.com/DramaticShape/DramaticShapeVoxelMod)
is the reference for what a renderer mod has to be able to do: a voxel diorama
with selectable camera pitch, first and third person, VR, reflections and a day
cycle, shipping no cartridge art. Everything it needs is in the contract above.
Geometry comes from collision permissions, the block grid and the tileset atlas;
the view runs at window resolution; animated tiles follow because
`Gen2WorldAnimation` replaces atlas slots rather than map rectangles.

Movement is the one part worth naming. `Gen2WorldAPI.player_step_offset_cells()`
and `Gen2WorldObject.step_offset_cells()` return an in-flight step as a
fractional cell, from one cell behind the committed cell down to zero. The
logical cell commits at the start of the step; the fraction is presentation only
and never reaches collision, events or the snapshot. `applymovement` applies its
whole stream at once, so a scripted path commits together and the offset trails
by as many cells as are left to draw; `advance_scripted_steps_frame()` drains
that trail, 16 frames a step for the slow commands, 8 for plain, 4 for bike
speed. `Gen2WorldObject.frame` is the cartridge's `Facings` index, 0 to 3,
changing every four frames the way `SetFacingStepAction` does.
`mods/examples/voxel_preview/` reads all of it.

Not covered: the teleport, skyfall and dig step types. `teleport_from`,
`teleport_to`, `skyfall` and `step_dig` reach the caller as a
`movement_command_requested` event and change nothing. None moves a cell on the
cartridge either, each being a spin, a rise or a fall over a fixed frame count
(`StepFunction_TeleportFrom` and its neighbours), so each is a pose a renderer
has to be told about rather than an offset it can read.

**Per-block height is deliberately not a host boundary.** A renderer resolves
shape from the collision permissions, the block grid and the tileset, all
already public, and keeps whatever table it needs beside its own resolver. A
host-side one would be a second place for the same facts.

## Adding a menu entry

`register_menu_entry(menu, id, entry)` appends to a menu the game builds. The
cartridge's own entries are never registered, so a mod can add but not reorder
or remove them.

| Menu | Where the entry lands | `entry` keys |
|---|---|---|
| `Gen2ModHost.MENU_START` | the start menu, immediately before EXIT | `label`, optional `handler: Callable` |
| `Gen2ModHost.MENU_PACK_POCKET` | after the pack's four source pockets | `label`, `pocket` |

```gdscript
func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	host.register_menu_entry(Gen2ModHost.MENU_START, manifest.id, {
		"label": "Atlas",
		"handler": func() -> void: print("opened"),
	})
```

A start-menu entry without a handler still appears, marked unavailable. A
pocket's number has to be at or
above `Gen2ModHost.FIRST_MOD_POCKET`: 1 to 4 are the cartridge's ITEM, KEY_ITEM,
BALL and TM_HM, and an item joins the pocket its own definition names. Two mods
claiming the same entry id is refused with `duplicate_menu_entry` rather than one
silently winning.

## Adding a setting

`register_option(id, option)` describes one setting: a ladder of values, a
number in a range, or a button. The
game and the launcher each build a surface from that one registration, so a mod
writes no settings screen and the two can never disagree.

```gdscript
host.register_option(manifest.id, {
	"key": "draw_distance", "label": "DISTANCE",
	"values": [8, 16, 24, 0], "labels": ["8", "16", "24", "FULL"],
	"default": 16,
})
```

| Key | Meaning |
|---|---|
| `key` | Addresses the setting within the mod |
| `label` | Shown to the player |
| `kind` | Optional; `Gen2ModHost.OPTION_LADDER` (the default), `OPTION_NUMBER` or `OPTION_BUTTON` |
| `values` | The rungs, at least one. A toggle is a two-rung ladder. Ladder only |
| `labels` | Optional; what each rung is shown as, defaulting to the values |
| `minimum`, `maximum` | The range, inclusive. Number only |
| `step` | Optional; what one press moves the value by, defaulting to 1. Number only |
| `default` | Optional; the rung or the number used until the player picks one, defaulting to the first rung or the minimum |
| `press_label` | Optional; what a button setting's control reads, defaulting to `Go`. Button only |

A **number** setting is one whole value in a range rather than a ladder with
every rung written out: a randomizer's seed is one field with ten thousand
values, and dialling it as four one-digit ladders spends four menu rows on one
value. Set it with `set_option(id, key, value)`, clamped into the range as
registered now, or step it with `adjust_option(id, key, delta)`, which is what
both surfaces call and which steps a ladder just as well. The launcher draws it
as a field that can be typed into; the start menu steps it left and right.

A **button** setting is a press rather than a ladder, for something with no value
to keep: "recentre the camera now" is an action, not a rung. It stores nothing,
`press_option(id, key)` is what both surfaces call, and `option_changed` carries
a null value to say the press is the whole setting.

Read it back with `host.option(id, key)`, or `option_index(id, key)` for the
rung, which is -1 for anything that is not a ladder.
A mod that has to rebuild something on a change connects to `option_changed(id,
key, value)` rather than polling. The host keeps the entry object `register` was
called on for as long as the mod is loaded, so connecting a signal to it is safe
and a mod does not have to hold itself in a static variable: `mods/examples/voxel_preview/` registers a
camera setting in `mod.gd` and its renderer reads it once and then listens.

The two surfaces are a **MODS** entry in the start menu, beside the pack and the
save, and rows on that mod's card in the launcher's mods page. The entry appears
only when at least one loaded mod registered a setting, so a player with no mods
sees the cartridge's menu exactly.

A change is committed the moment it is made, the way the cartridge's own OPTION
menu writes each press to `wOptions`. Values live in `user://mod_options.json`,
keyed by mod id, because a draw distance is a property of this installation and
must not change when a save slot is loaded. Only values are stored, never what a setting means, so a
mod that drops a rung in a later version finds its stored value refused and its
default used instead, and uninstalling a mod drops what it stored.

Per-slot state belongs in the save instead. A discovered manifest can use
`host.read_save_data(manifest, save)` and
`host.write_save_data(manifest, save, value)` to access only its own namespace.
Both sides deep-copy dictionaries, and writes larger than 64 KiB of UTF-8 JSON
are refused. The manifest object itself is the capability: constructing another
manifest with the same id does not grant access to that mod's state.

## Adding a control

`register_action(id, action)` declares a control of the mod's own. A mod cannot
see the cartridge's eight, and the screen claims every one of them before a
renderer is offered anything, so reading raw keycodes out of
`handle_world_input` produces controls that cannot be rebound, collide silently
with the d-pad, and do not exist on a touchscreen at all.

```gdscript
host.register_action(manifest.id, {
	"key": "pitch_up", "label": "Camera up",
	"default": [{"kind": "key", "code": KEY_F}],
})
```

| Key | Meaning |
|---|---|
| `key` | Addresses the control within the mod |
| `label` | Shown wherever the control is listed or drawn |
| `default` | Optional; bindings in `Gen2InputActions`' own shape |

`default` takes the same three kinds the eight take, so a mod's control binds to
a key by physical position, a pad button, or a stick axis past the same deadzone:

```gdscript
{"kind": "key",        "code": <physical keycode>}
{"kind": "pad_button", "code": <JoyButton>}
{"kind": "pad_axis",   "code": <JoyAxis>, "sign": -1 or 1}
```

A default already bound to one of the eight is **dropped and reported**, because
such a binding would never once fire: the screen takes those first. The action
still registers, unbound on that slot, and the refusal reaches
`Gen2ModHost.failures()` and the launcher. `W`, `A`, `S` and `D` are the d-pad's
own default keys.

Three ways to read one, none of them an `InputEvent`:

| Call | For |
|---|---|
| `action_changed(id, key, pressed)` | The edge. A signal, like `option_changed` |
| `action_held(id, key) -> bool` | The poll a camera wants |
| `action_strength(id, key) -> float` | The same as a magnitude, 0 to 1 |

`action_strength` is what makes an analogue control analogue: a stick bound to an
action answers its travel past the deadzone, so a camera on the right stick moves
at the rate the player is pushing it, while a key answers 0 or 1. For motion
nothing can name, a two-finger drag and raw stick movement are still the
leftovers `handle_world_input` and `handle_battle_input` are offered.

Everything a registered control reaches is reachable without a keyboard:

- the launcher's **controls** card lists a loaded mod's actions in their own
  group under the eight, and rebinds them through the same sheet;
- the on-screen controller can carry them. Off by default, because a mod must
  not cover the screen of a player who never asked for one; switched on from the
  same card, each is a pill the player drags where they like, per orientation,
  beside A and B.

An event reaches a mod's action only where the screen would have offered a
renderer one, so an open menu, a running script, a battle or a trainer approach
takes the press first.

## Not built yet

Art for mod content, mutation hooks on the event channels, entries in the party submenu or the mart,
and `.zip`/`.pck` packs through `ProjectSettings.load_resource_pack()`. A mod
species does not appear in the Pokedex either: both dex order tables are
cartridge data of exactly 251 entries, and nothing splices `defined_numbers()`
into them, though a mod species that replaces a cartridge one does carry its own
dex entry. Evaluate
[godot-mod-loader](https://github.com/GodotModding/godot-mod-loader) before
expanding the loader itself.
