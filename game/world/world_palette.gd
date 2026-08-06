class_name Gen2WorldPalette
extends RefCounted

## Cartridge background palette selection for the overworld.
##
## The ROM stores 42 actual colour groups and a separate environment/time table
## selects eight of them for the hardware's background palette slots. The
## values below are the table from the map palette loader, kept here as data so
## the renderer does not silently substitute a modern colour scheme.

const TIME_MORNING: int = 0
const TIME_DAY: int = 1
const TIME_NIGHT: int = 2
const TIME_DARK: int = 3

const PALETTE_ROWS: Array = [
	[
		[0, 1, 2, 40, 4, 5, 6, 7],
		[8, 9, 10, 40, 12, 13, 14, 15],
		[16, 17, 18, 41, 20, 21, 22, 23],
		[24, 25, 26, 27, 28, 29, 30, 31],
	],
	[
		[0, 1, 2, 40, 4, 5, 6, 7],
		[8, 9, 10, 40, 12, 13, 14, 15],
		[16, 17, 18, 41, 20, 21, 22, 23],
		[24, 25, 26, 27, 28, 29, 30, 31],
	],
	[
		[0, 1, 2, 40, 4, 5, 6, 7],
		[8, 9, 10, 40, 12, 13, 14, 15],
		[16, 17, 18, 41, 20, 21, 22, 23],
		[24, 25, 26, 27, 28, 29, 30, 31],
	],
	[
		[32, 33, 34, 35, 36, 37, 38, 7],
		[32, 33, 34, 35, 36, 37, 38, 7],
		[16, 17, 18, 19, 20, 21, 22, 7],
		[24, 25, 26, 27, 28, 29, 30, 7],
	],
	[
		[0, 1, 2, 3, 4, 5, 6, 7],
		[8, 9, 10, 11, 12, 13, 14, 15],
		[16, 17, 18, 19, 20, 21, 22, 23],
		[24, 25, 26, 27, 28, 29, 30, 31],
	],
	[
		[0, 1, 2, 3, 4, 5, 6, 7],
		[8, 9, 10, 11, 12, 13, 14, 15],
		[16, 17, 18, 19, 20, 21, 22, 23],
		[24, 25, 26, 27, 28, 29, 30, 31],
	],
	[
		[32, 33, 34, 35, 36, 37, 38, 7],
		[32, 33, 34, 35, 36, 37, 38, 7],
		[16, 17, 18, 19, 20, 21, 22, 7],
		[24, 25, 26, 27, 28, 29, 30, 7],
	],
	[
		[0, 1, 2, 3, 4, 5, 6, 7],
		[8, 9, 10, 11, 12, 13, 14, 15],
		[16, 17, 18, 19, 20, 21, 22, 23],
		[24, 25, 26, 27, 28, 29, 30, 31],
	],
]


static func palette_slots(environment: int, time_of_day: int) -> Array:
	var environment_index: int = clampi(environment, 0, PALETTE_ROWS.size() - 1)
	var time_index: int = clampi(time_of_day, 0, 3)
	return (PALETTE_ROWS[environment_index] as Array)[time_index]


## One palette per tile of [param tileset], in tile order.
##
## A tileset's ninety-six tiles share eight palette slots, so the eight are
## resolved once and the same one is handed to every tile that uses it. This runs
## again on every frame an animated tileset changes a tile, and building
## ninety-six copies of eight palettes was most of that frame's cost.
static func tile_palettes(
	data: GameData,
	map: Gen2WorldMap,
	tileset: Gen2WorldTileset,
	time_of_day: int = TIME_MORNING,
	water_color: int = -1,
	cave_color: int = -1,
) -> Array:
	var slots: Array = palette_slots(map.environment, time_of_day)
	var resolved: Array = []
	for slot: int in slots.size():
		var base: PackedColorArray = data.world_palette(int(slots[slot]))
		var palette := PackedColorArray()
		palette.append_array(base)
		if slot == 3 and water_color >= 0 and base.size() >= 4:
			palette[0] = base[clampi(water_color, 0, 2)]
		elif slot == 4 and cave_color >= 0 and base.size() >= 2:
			palette[0] = base[clampi(cave_color, 0, 1)]
		resolved.append(palette)
	var fallback: PackedColorArray = data.world_palette(0)
	var out: Array = []
	out.resize(tileset.tile_count)
	for tile: int in tileset.tile_count:
		var slot: int = tileset.palette_index(tile)
		out[tile] = resolved[slot] if slot >= 0 and slot < resolved.size() else fallback
	return out
