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

`mods/examples/voxel_preview/` is a working renderer: copy it into
`user://mods/` and press `V` in the overworld. It reads the same collision,
block and palette data the 2D view reads and extrudes geometry from it.

## Replacing the world renderer

The 2D renderer reads the world and draws it. Nothing about the world requires
that the drawing be 2D: maps are node-free `RefCounted` records, each tileset is
one addressable atlas, animated tiles replace atlas slots rather than map
rectangles, and collision is a raw permission byte per 2x2 walk cell. A renderer
that extrudes geometry from that same data is a registration, not a fork.

A registered renderer is a `Node` providing:

| Method | Called when |
|---|---|
| `set_world(world, animation)` | The map changed, or the view was created |
| `set_time_of_day(time_of_day)` | The clock crossed 04:00, 10:00 or 18:00 |
| `refresh()` | The player, an object or an event changed something |
| `refresh_animation()` | A tileset animation command changed tile data |

Registration is refused, by name, if any of these is missing or the script is
not a `Node`, rather than failing on the first drawn frame.

Two methods are optional:

| Method | Effect |
|---|---|
| `uses_hardware_viewport() -> bool` | Answering false moves the renderer off the 160x144 hardware viewport onto the screen's own rectangle at window resolution |
| `set_native_size(size: Vector2i)` | The native layer's size in window pixels, on creation and on every window change |

A view built out of geometry cannot be drawn into a 160x144 buffer and then
magnified, so the second layer is what makes a 3D or HD renderer possible at
all. Text boxes and menus keep being drawn in hardware pixels over the top,
which is what an HD presentation of these games wants: the world gains
resolution, the interface stays a Game Boy.

The host constructs a renderer per world, so `select_world_renderer()` can
switch between the built-in `gen2` renderer and a mod's while the game runs.
`Gen2WorldScreen.cycle_world_renderer()` is that switch, bound to `V`: the map,
the player and any running script are untouched, because a renderer reads world
state and must not write it. Two views of one world have to agree.

## Measured against the voxel mod

[DramaticShapeVoxelMod](https://github.com/DramaticShape/DramaticShapeVoxelMod)
is the reference for what a renderer mod has to be able to do. It turns
gen1recomp's overworld into a voxel diorama with selectable camera pitch,
first- and third-person free-roam, VR through OpenXR, water reflections and a
day cycle, and it ships no cartridge art: geometry is derived from the tile and
sprite data the host already has.

What the contract above already supports:

- deriving geometry from host data. Collision permissions, the block grid, the
  tileset atlas and its palettes are all reachable through `Gen2WorldAPI` and
  `GameData` with no cartridge access and no authored 3D assets;
- rendering at the window's resolution rather than the hardware's;
- switching views mid-session on a keybind, with no world state involved;
- a day cycle. `set_time_of_day` is called on the source 04:00, 10:00 and 18:00
  boundaries, and the palette rows behind it are the cartridge's own;
- animated tiles. `Gen2WorldAnimation` replaces atlas slots rather than map
  rectangles, so geometry textured from the atlas follows water and flowers
  without the renderer knowing an animation ran.

What is missing, in the order it blocks work:

1. **Sub-cell player position.** `Gen2WorldAPI` moves the player a whole walk
   cell at a time and holds no interpolation, so a free-roam or first-person
   camera has nothing to smooth against and a third-person one snaps. The API
   needs a movement progress value, or a renderer has to invent its own and
   drift from the world it is drawing.
2. **Per-tile height.** Extruded height here is a guess from the collision
   permission, which cannot tell a tree from a cliff from a building. Gen II
   has no height data; a renderer needs a per-block table it supplies itself,
   and the host should let a mod attach one rather than have each renderer
   hard-code Johto.
3. **Battles and interiors are not renderer-owned.** `Gen2BattleScreen` builds
   its own 160x144 presentation directly and does not go through the mod host,
   so the voxel mod's 3D battles have no equivalent here. Battle presentation
   needs the same registration the world renderer has.
4. **No camera boundary.** The screen decides the visible page through
   `Gen2WorldAPI.visible_origin_cell()`. A free camera would need the world to
   stop being the thing that frames the view.
5. **No input hook.** Camera pitch, first person and free-roam are all input a
   mod would have to receive, and the world screen currently reads keys itself.

Nothing in that list changes the world's own data, which is the part that
matters: they are all presentation boundaries that do not exist yet, not
decisions that have been made the wrong way.

## Not built yet

Semver ranges and inter-mod dependencies, per-mod save data, hooks beyond the
renderer, and `.zip`/`.pck` packs through
`ProjectSettings.load_resource_pack()`. Evaluate
[godot-mod-loader](https://github.com/GodotModding/godot-mod-loader) before
expanding the loader itself.
