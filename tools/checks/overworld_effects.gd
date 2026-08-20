extends RefCounted

var _r: RefCounted = null

## Verifies the sprites the overworld draws over an object rather than as one,
## against freshly imported real caches: `data/sprites/emotes.asm`'s twelve
## sheets and ShakeHeadbuttTree's own.
##
## Every expectation comes from the pinned sources: the emote table's tile
## numbers are `Facings`' own ($f8 for the four-tile bubbles, $fc for the jump
## shadow and the fishing rod, $fe for the boulder dust and the grass rustle),
## and all three cartridges ship the art itself byte identical, which is what
## the cross-cartridge comparison checks. A sheet read at the wrong offset
## decodes neighbouring code into legal-looking pixels, so shape alone would not
## catch it.
##
##   Godot --headless --path . -s res://tools/validate.gd -- overworld_effects

## The names Gen2WorldImporter writes, with the tile count and VRAM tile each
## record must name.
const EXPECTED: Array = [
	["shock", 4, 0xF8], ["question", 4, 0xF8], ["happy", 4, 0xF8], ["sad", 4, 0xF8],
	["heart", 4, 0xF8], ["bolt", 4, 0xF8], ["sleep", 4, 0xF8], ["fish", 4, 0xF8],
	["shadow", 1, 0xFC], ["rod", 2, 0xFC], ["boulder_dust", 2, 0xFE],
	["grass_rustle", 1, 0xFE], ["headbutt_tree", 8, 0x84], ["cut_tree", 4, 0x84],
	["cut_grass", 4, 0x80], ["heal_machine", 2, 0x7C],
]

## `gfx/overworld/heal_machine.pal`, the one sheet that carries a palette of its
## own instead of wearing an overworld one: `RGB 31, 31, 31`, `RGB 31, 19, 10`,
## `RGB 31, 07, 01` and black, packed the way the cartridge stores them and
## identical on all three.
const HEAL_MACHINE_COLORS: Array[int] = [0x7FFF, 0x2A7F, 0x04FF, 0x0000]

var _first: Dictionary = {}


func run(r: RefCounted) -> void:
	_r = r
	_first = {}
	_r.each_game(_check_game)


func _check_game() -> void:
	var lit: int = 0
	for row: Array in EXPECTED:
		var name: String = String(row[0])
		var sheet: Dictionary = _r.data.overworld_effect(name)
		if not _r.check(not sheet.is_empty(), "the %s sheet is not in the cache." % name):
			continue
		_r.check(
			int(sheet["tiles"]) == int(row[1]),
			"%s is %d tiles, not the source's %d." % [name, int(sheet["tiles"]), int(row[1])]
		)
		_r.check(
			int(sheet["vtile"]) == int(row[2]),
			"%s loads to tile $%02X, not $%02X." % [name, int(sheet["vtile"]), int(row[2])]
		)
		var indices: PackedByteArray = sheet["indices"]
		if not _r.check(
			indices.size() == int(row[1]) * Gen2Tiles.TILE_PIXELS,
			"%s decoded %d pixels, not %d." % [
				name, indices.size(), int(row[1]) * Gen2Tiles.TILE_PIXELS,
			]
		):
			continue
		var drawn: int = 0
		for index: int in indices:
			_r.check(index <= 3, "%s holds colour index %d." % [name, index])
			if index != 0:
				drawn += 1
		# Index 0 is the transparent one, so a sheet of nothing but zeroes is a
		# sheet that would draw nothing at all.
		_r.check(drawn > 0, "%s is blank." % name)
		lit += drawn
		if _first.has(name):
			_r.check(
				_first[name] == indices,
				"%s differs from the same sheet on the other cartridges." % name
			)
		else:
			_first[name] = indices
		var colors: PackedColorArray = sheet.get("colors", PackedColorArray())
		if name == "heal_machine":
			if _r.check(
				colors.size() == HEAL_MACHINE_COLORS.size(),
				"the heal machine carries %d colours, not four." % colors.size()
			):
				for slot: int in colors.size():
					var want: Color = Gen2Palette.from_packed(HEAL_MACHINE_COLORS[slot])
					_r.check(
						colors[slot].is_equal_approx(want),
						"heal machine colour %d is %s, not the source's %s." % [
							slot, colors[slot], want,
						]
					)
		else:
			_r.check(colors.is_empty(), "%s carries a palette it has no source for." % name)
	_r.note("overworld effects: %d sheets, %d drawn pixels." % [EXPECTED.size(), lit])
