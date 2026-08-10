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
| `voxel_preview/` | A world renderer. Press `V` in the overworld; it reads the same collision, block and palette data the 2D view reads and extrudes geometry from it, on the native layer with a translucent text box and one registered setting |
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

The box is drawn as the cartridge draws it, which means opaque: over the white
field that is invisible, and over a map it is a slab across the bottom third of
the screen. `interface_opacity()` is the renderer's request for the field to be
drawn through, and only the field. The frame's lines and the glyphs are ink and
stay fully opaque, so nothing a renderer can ask for makes text harder to read.
It is honoured only for a renderer that answered `uses_hardware_viewport()`
false: one drawing in hardware pixels paints the background the box sits on, and
a hole there would show the window behind the screen rather than the world.
Around 0.75 is what reads well over a map.

`set_text_box_rect` is the same box measured rather than styled, for a renderer
composing around it: the standard box is twenty by six at row twelve, but a box
can be any size and is not always up. It is pushed on every change, including
the empty rectangle when the box goes away, and again whenever a renderer is
swapped in mid-scene.

The world's own menus are not this box. The start menu, the pack, the party and
the PC are window-resolution panels over the whole screen with their own scrim,
not cartridge boxes on the hardware layer, so a renderer neither sees nor styles
them. `Gen2MenuPage` is the cartridge box path and is used by the naming and
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
forget-move list and ball selection each take their press first and what arrives
here is pointer and stick motion. Ball selection and the forget prompt also
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
- scripted movement progress, on the same two calls. An `applymovement` applies
  its whole stream at once, so every cell of the path commits together and the
  offset is as many cells behind as there are left to draw.
  `advance_scripted_steps(delta)` drains that trail and is the one mover a
  screen keeps calling while a script runs, since that is when a script runs
  one. Each step lasts its own command's duration: 16 frames for the slow
  commands, 8 for the plain ones, 4 for the bike-speed ones;
- a walking sprite. `Gen2WorldObject.frame` and `Gen2WorldAPI.player_walk_frame()`
  are the cartridge's `Facings` index, 0 to 3: two standing drawings and two
  walking ones, changing every four frames of a step the way
  `SetFacingStepAction` does. `Gen2WorldSprite.image_for()` composes the frame,
  and `frame_is_mirrored()` says when it is drawn flipped;
- a camera of its own, through `player_position_cells()` and
  `visible_origin_cells()` above, without inheriting the tile page's framing;
- steering that camera, through `handle_world_input`. `mods/examples/voxel_preview/`
  puts pitch on `Q` and `E`, two keys the world screen does not read.

What is still missing:

1. **The teleport, skyfall and dig step types.** `teleport_from`,
   `teleport_to`, `skyfall` and `step_dig` reach the caller as a
   `movement_command_requested` event and change nothing. None of them moves a
   cell on the cartridge either: each is a spin, a rise or a fall over a fixed
   count of frames (`StepFunction_TeleportFrom` and its neighbours in
   `engine/overworld/map_objects.asm`), so each is a pose a renderer has to be
   told about rather than an offset it can read.

**Per-block height is deliberately not a host boundary.** A renderer resolves
shape from the collision permissions, the block grid and the tileset, all of
which are already public, and keeps whatever table it needs beside its own
resolver. A host-side one would be a second place for the same facts.

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

`register_option(id, option)` describes one setting as a ladder of values. The
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
| `values` | The rungs, at least one. A toggle is a two-rung ladder |
| `labels` | Optional; what each rung is shown as, defaulting to the values |
| `default` | Optional; the rung used until the player picks one, defaulting to the first |

Read it back with `host.option(id, key)`, or `option_index(id, key)` for the rung.
A mod that has to rebuild something on a change connects to `option_changed(id,
key, value)` rather than polling: `mods/examples/voxel_preview/` registers a
camera setting in `mod.gd` and its renderer reads it once and then listens.

The two surfaces are a **MODS** entry in the start menu, beside the pack and the
save, and rows on that mod's card in the launcher's mods page. The entry appears
only when at least one loaded mod registered a setting, so a player with no mods
sees the cartridge's menu exactly.

A change is committed the moment it is made, the way the cartridge's own OPTION
menu writes each press to `wOptions`. Values live in `user://mod_options.json`,
keyed by mod id, because a draw distance is a property of this installation and
must not change when a save slot is loaded; per-mod *save* data is a separate
thing and is not built. Only values are stored, never what a setting means, so a
mod that drops a rung in a later version finds its stored value refused and its
default used instead, and uninstalling a mod drops what it stored.

## Not built yet

Semver ranges and inter-mod dependencies, per-mod save data, art for mod content,
mutation hooks on the event channels, entries in the party submenu or the mart,
and `.zip`/`.pck` packs through `ProjectSettings.load_resource_pack()`. A mod
species does not appear in the Pokedex either: both dex order tables are
cartridge data of exactly 251 entries, and nothing splices `defined_numbers()`
into them, though a mod species that replaces a cartridge one does carry its own
dex entry. Evaluate
[godot-mod-loader](https://github.com/GodotModding/godot-mod-loader) before
expanding the loader itself.
