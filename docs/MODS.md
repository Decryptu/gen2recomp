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

Two methods are optional:

| Method | Effect |
|---|---|
| `uses_hardware_viewport() -> bool` | Answering false moves the renderer off the 160x144 hardware viewport onto the screen's own rectangle at window resolution |
| `set_native_size(size: Vector2i)` | The native layer's size in window pixels, on creation and on every window change |

A view built out of geometry cannot be drawn into a 160x144 buffer and then
magnified, so the second layer is what makes a 3D or HD renderer possible at
all. Text boxes and menus stay hardware pixels over the top: the world gains
resolution, the interface stays a Game Boy.

The host constructs a renderer per world, so `select_world_renderer()` can
switch between the built-in `gen2` renderer and a mod's while the game runs.
`Gen2WorldScreen.cycle_world_renderer()` is that switch, bound to `V`: the map,
the player and any running script are untouched, because a renderer reads world
state and must not write it. Two views of one world have to agree.

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
  `mods/examples/voxel_preview/` reads both.

What is still missing, in the order it blocks work:

1. **Per-tile height.** Extruded height is a guess from the collision
   permission, which cannot tell a tree from a cliff from a building. Gen II
   has no height data, so a renderer needs a per-block table it supplies
   itself, and the host should let a mod attach one rather than have every
   renderer hard-code Johto.
2. **Battles and interiors are not renderer-owned.** `Gen2BattleScreen` builds
   its own 160x144 presentation directly instead of going through the mod host,
   so the voxel mod's 3D battles have no equivalent here. Battle presentation
   needs the same registration the world renderer has.
3. **No camera boundary.** `Gen2WorldAPI.visible_origin_cell()` still follows
   the committed cell rather than the interpolated one, so a free camera pans a
   step early. A free camera needs the world to stop framing the view.
4. **No input hook.** Camera pitch, first person and free-roam are all input a
   mod would have to receive, and the world screen reads keys itself.
5. **Scripted movement does not interpolate.** `applymovement` streams, and the
   jump, teleport and boulder step types, still place objects a whole cell at a
   time. The wandering, spinning, following, player and trainer-approach paths
   all carry the sub-cell offset.

All five are presentation boundaries that do not exist yet; none of them
changes the world's own data.

## Not built yet

Semver ranges and inter-mod dependencies, per-mod save data, hooks beyond the
renderer, and `.zip`/`.pck` packs through
`ProjectSettings.load_resource_pack()`. Evaluate
[godot-mod-loader](https://github.com/GodotModding/godot-mod-loader) before
expanding the loader itself.
