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
| `entry` | A `.gd` path inside the mod directory |
| `description` | Optional |

An entry that is absolute, contains `..` or is not GDScript is refused before
anything runs. Manifests are read without executing mod code, so a launcher can
list what is installed and say why something was rejected.

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
| `voxel_preview/` | A world renderer. Press `V` in the overworld; it reads the same collision, block and palette data the 2D view reads and extrudes geometry from it |
| `new_content/` | A species, a move, a move effect, two rebalancing patches and both event channels |

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
binary tokens. An installed mod loads immediately, without a restart.

`user://mods/` is the platform's `app_userdata/gen2recomp/mods` on desktop, the
app's `Documents/mods` on iOS (reachable in the Files app, since the export sets
`UIFileSharingEnabled`), and internal app storage on Android, where the system
file picker is how an archive gets in.

## Publishing an index

An index is a JSON feed listing mods that stay in their authors' own
repositories. Anyone can publish one, and the game follows none until a player
adds it, because following an index is trusting whoever publishes it.

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

## Adding content

`mods/examples/new_content/` registers a species, a move, a move effect and two
rebalancing patches, and watches both event channels. Copy it and read it beside
this section.

A content number is per kind and starts at `Gen2ContentOverlay.FIRST_MOD_NUMBER`,
which is 256. Every cartridge number fits in a byte, so a number that does not is
unambiguously not the cartridge's, and a mod's own numbers mean the same thing on
Gold, Silver and Crystal. Four kinds are reachable: `KIND_SPECIES`, `KIND_MOVE`,
`KIND_ITEM` and `KIND_TRAINER`. Types are not, because the matchup lookup keys on
the type count and a twenty-ninth type would renumber every pair in the chart.

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
Rollout and Selfdestruct bytes are read back off the turn by their own commands,
so replacing one would leave that command answering for a list it is no longer
in.

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

A view built out of geometry cannot be drawn into a 160x144 buffer and then
magnified, so the second layer is what makes a 3D or HD renderer possible at
all. Text boxes and menus stay hardware pixels over the top: the world gains
resolution, the interface stays a Game Boy.

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
`enemy_level`, `player_level`, `enemy_hp`, `enemy_max_hp`, `player_hp`,
`player_max_hp` and `exp_fraction`: plain values read out of a resolved battle
event, never the battle engine itself, the same rule `Gen2BattleScreen`'s own
setters already followed.

Registration uses the same refusal rules as a world renderer, and shares both
optional methods (`uses_hardware_viewport()`, `set_native_size()`) and the `V`
cycle, bound in `Gen2BattleScreen` the way `Gen2WorldScreen` binds it.

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
is the reference for what a renderer mod has to be able to do. It turns
gen1recomp's overworld into a voxel diorama with selectable camera pitch,
first- and third-person free-roam, VR through OpenXR, water reflections and a
day cycle, shipping no cartridge art: geometry is derived from the tile and
sprite data the host already has.

Supported by the contract above:

- deriving geometry from host data. Collision permissions, the block grid, the
  tileset atlas and its palettes are all reachable through `Gen2WorldAPI` and
  `GameData`, with no cartridge access and no authored 3D assets;
- rendering at the window's resolution rather than the hardware's;
- switching views mid-session on a keybind, with no world state involved;
- a day cycle, through `set_time_of_day` on the source 04:00, 10:00 and 18:00
  boundaries, over the cartridge's own palette rows;
- animated tiles, because `Gen2WorldAnimation` replaces atlas slots rather than
  map rectangles, so geometry textured from the atlas follows water and flowers
  without the renderer knowing an animation ran;
- movement progress. `Gen2WorldAPI.player_step_offset_cells()` and
  `Gen2WorldObject.step_offset_cells()` return an in-flight step as a fractional
  cell, from one cell behind the committed cell down to zero, paced by
  `advance_player_step(delta)` and `advance_object_steps()` at the hardware
  frame rate and stall cap `Gen2WorldAnimation` uses. The logical cell still
  commits at the start of the step; the fraction is presentation only and never
  reaches collision, events or the world snapshot.
  `mods/examples/voxel_preview/` reads both;
- a camera of its own, through `player_position_cells()` and
  `visible_origin_cells()` above, without inheriting the tile page's framing;
- steering that camera, through `handle_world_input`. `mods/examples/voxel_preview/`
  puts pitch on `Q` and `E`, two keys the world screen does not read.

What is still missing, in the order it blocks work:

1. **Per-tile height.** Extruded height is a guess from the collision
   permission, which cannot tell a tree from a cliff from a building. Gen II
   has no height data, so a renderer needs a per-block table it supplies
   itself, and the host should let a mod attach one rather than have every
   renderer hard-code Johto.
2. **Interiors are not renderer-owned.** Only the overworld and battle are
   registered; a 3D interior view has no equivalent boundary here.
3. **Scripted movement does not interpolate.** `applymovement` streams, and the
   jump, teleport and boulder step types, still place objects a whole cell at a
   time. The wandering, spinning, following, player and trainer-approach paths
   all carry the sub-cell offset.

All three are presentation boundaries that do not exist yet; none of them
changes the world's own data.

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

A start-menu entry without a handler still appears, marked unavailable, which is
what Pokedex, Player and Options already do. A pocket's number has to be at or
above `Gen2ModHost.FIRST_MOD_POCKET`: 1 to 4 are the cartridge's ITEM, KEY_ITEM,
BALL and TM_HM, and an item joins the pocket its own definition names. Two mods
claiming the same entry id is refused with `duplicate_menu_entry` rather than one
silently winning.

## Not built yet

Semver ranges and inter-mod dependencies, per-mod save data, art for mod content,
mutation hooks on the event channels, entries in the party submenu or the mart,
and `.zip`/`.pck` packs through `ProjectSettings.load_resource_pack()`. Evaluate
[godot-mod-loader](https://github.com/GodotModding/godot-mod-loader) before
expanding the loader itself.
