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

## `wMapTimeOfDay`, the low nibble of the map header's seventh byte and already
## on [member Gen2WorldMap.palette]. It says which of the four rows above a map
## uses, and whether the clock gets a say at all.
const PALETTE_AUTO: int = 0
const PALETTE_DAY: int = 1
const PALETTE_NITE: int = 2
const PALETTE_MORN: int = 3
const PALETTE_DARK: int = 4

## `.BrightnessLevels`, one row per [constant PALETTE_AUTO] and its four
## neighbours, read by the clock's own time of day. The cartridge packs each row
## into a byte two bits at a time and `GetTimePalette` picks the pair back out;
## the byte is not kept here because nothing else reads it.
const BRIGHTNESS_LEVELS: Array = [
	[TIME_MORNING, TIME_DAY, TIME_NIGHT, TIME_DARK],
	[TIME_DAY, TIME_DAY, TIME_DAY, TIME_DAY],
	[TIME_NIGHT, TIME_NIGHT, TIME_NIGHT, TIME_NIGHT],
	[TIME_MORNING, TIME_MORNING, TIME_MORNING, TIME_MORNING],
	[TIME_DARK, TIME_DARK, TIME_DARK, TIME_DARK],
]


## Which of the four palette rows a map draws with right now.
##
## `ReplaceTimeOfDayPals` and `GetTimePalette` together. A
## [constant PALETTE_DARK] map is the only one the clock cannot reach: it is
## [constant TIME_DARK] until Flash has been used and [constant TIME_NIGHT]
## afterwards, which is why a lit cave still looks like a cave.
static func map_time_of_day(
	map_palette: int, clock_time_of_day: int, used_flash: bool = false
) -> int:
	if map_palette == PALETTE_DARK:
		return TIME_NIGHT if used_flash else TIME_DARK
	var row: Array = BRIGHTNESS_LEVELS[clampi(map_palette, 0, BRIGHTNESS_LEVELS.size() - 1)]
	return int(row[clampi(clock_time_of_day, 0, row.size() - 1)])


## Whether a map is one of the caves Flash is for.
static func is_dark(map_palette: int) -> bool:
	return map_palette == PALETTE_DARK

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


## `.cgbfade`, the seven rows `GetTimePalFade` answers with on a CGB, each
## packed the way `dc` packs one: colour j of the result is colour
## `(order >> 2j) & 3` of the palette it is applied to, which is what
## `DmgToCgbTimePals` does with it. Row 3 is the identity, row 6 is every colour
## flattened onto colour 0.
const FADE_ORDERS: Array[int] = [0xFF, 0xFE, 0xF9, 0xE4, 0x90, 0x40, 0x00]
## `RotatePalettesRight`'s and the two map fades' own starting rows.
const FADE_IDENTITY: int = 0xE4

## `FadeOutToWhite`: `ld c, $9` is row 3, and `ConvertTimePalsIncHL` walks four
## rows forward, two frames each. `FadeInFromWhite` is `ld c, $12`, row 6, and
## `ConvertTimePalsDecHL` walks the same four back.
const FADE_OUT_ORDERS: Array[int] = [0xE4, 0x90, 0x40, 0x00]
const FADE_IN_ORDERS: Array[int] = [0x00, 0x40, 0x90, 0xE4]
## `DelayFrames`' own `ld c, 2` inside either loop.
const FADE_STEP_FRAMES: int = 2


## One step of a palette fade: `CopyPals`' rule, which every `DmgToCgb*Pals`
## caller shares. The identity order answers the palette it was handed.
static func fade_palette(palette: PackedColorArray, order: int) -> PackedColorArray:
	if order == FADE_IDENTITY or palette.size() < 4:
		return palette
	var out := PackedColorArray()
	out.resize(palette.size())
	for index: int in palette.size():
		out[index] = palette[(order >> (2 * mini(index, 3))) & 3] if index < 4 			else palette[index]
	return out


static func palette_slots(environment: int, time_of_day: int) -> Array:
	var environment_index: int = clampi(environment, 0, PALETTE_ROWS.size() - 1)
	var time_index: int = clampi(time_of_day, 0, 3)
	return (PALETTE_ROWS[environment_index] as Array)[time_index]


## One palette per tile of [param tileset], in tile order.
##
## Every tile of the strip shares eight palette slots, so the eight are resolved
## once and the same one is handed to every tile that uses it. This runs again on
## every frame an animated tileset changes a tile, and building one palette copy
## per tile was most of that frame's cost.
static func tile_palettes(
	data: GameData,
	map: Gen2WorldMap,
	tileset: Gen2WorldTileset,
	time_of_day: int = TIME_MORNING,
	water_color: int = -1,
	cave_color: int = -1,
	fade_order: int = FADE_IDENTITY,
	white_fill: bool = false,
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
	# `FillWhiteBGColor`, which only the fade out of the map runs: every
	# background palette takes palette 0's own colour 0, so the order that
	# flattens a palette onto it flattens the screen onto one white.
	if white_fill and not resolved.is_empty():
		var white: Color = (resolved[0] as PackedColorArray)[0]
		for slot: int in range(1, resolved.size()):
			var palette: PackedColorArray = resolved[slot]
			palette[0] = white
			resolved[slot] = palette
	if fade_order != FADE_IDENTITY:
		for slot: int in resolved.size():
			resolved[slot] = fade_palette(resolved[slot], fade_order)
	var fallback: PackedColorArray = fade_palette(data.world_palette(0), fade_order)
	var out: Array = []
	out.resize(tileset.tile_count)
	for tile: int in tileset.tile_count:
		var slot: int = tileset.palette_index(tile)
		out[tile] = resolved[slot] if slot >= 0 and slot < resolved.size() else fallback
	return out
