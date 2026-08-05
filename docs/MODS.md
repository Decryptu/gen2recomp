# Mods

A mod is interpreted GDScript in a directory under `user://mods/`. iOS forbids
JIT and loading native code at runtime, so a distributed mod cannot be a
compiled extension.

Mods never touch scene nodes or engine internals. A mod is handed
`Gen2ModHost`, registers what it provides, and returns. Everything it can reach
is cartridge content through `GameData` or live world state through
`Gen2WorldAPI`, both of which are scene-free.

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

`mod.gd` defines one method:

```gdscript
extends RefCounted

func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	host.register_world_renderer(manifest.id, load("%s/renderer.gd" % manifest.directory), "Voxel")
```

A mod that fails to load is reported through `Gen2ModHost.failures()` and
skipped. One broken mod does not stop the others and does not stop the game.

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

The host constructs a renderer per world, so `select_world_renderer()` can
switch between the built-in `gen2` renderer and a mod's while the game runs. A
renderer reads world state and must not write it: two views of one world have to
agree.

## Not built yet

Semver ranges and inter-mod dependencies, per-mod save data, event hooks beyond
the renderer, and `.zip`/`.pck` packs through
`ProjectSettings.load_resource_pack()`. Evaluate
[godot-mod-loader](https://github.com/GodotModding/godot-mod-loader) before
expanding the loader itself.
