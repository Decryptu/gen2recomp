extends RefCounted

## A cache carrying a full species range and both dex order tables, written in
## the same files the importer writes.
##
## The dex is the one screen that needs all 251 species: the order tables are
## that long and [method Gen2Pokedex.order_by_mode] fills the whole listing, so
## the battle fixture's short table cannot stand in. Names, types and entry text
## are generated rather than published values, since nothing here checks content
## against a cartridge; [method RomImporter.verify_pokedex] does that.

const GAME_ID: StringName = &"pokedexfixture"
const SHA1: String = "0123456789abcdef"

## Deliberately unlike the species range and unlike each other, so a test that
## passes under the wrong table fails: NEW runs backwards, and ABC lists the
## even numbers before the odd ones.
static func new_order() -> Array:
	var out: Array = []
	for number: int in range(RomLayout.SPECIES_COUNT, 0, -1):
		out.append(number)
	return out


static func alpha_order() -> Array:
	var out: Array = []
	for number: int in range(2, RomLayout.SPECIES_COUNT + 1, 2):
		out.append(number)
	for number: int in range(1, RomLayout.SPECIES_COUNT + 1, 2):
		out.append(number)
	return out


static func species_name(number: int) -> String:
	return "MON%03d" % number


## Species cycle through the search order's own types, so a search for the type
## at a given search position has a known set of species behind it: species N
## carries SEARCH_TYPES[(N - 1) % 17] in both slots, except the multiples of ten,
## which carry FIRE in the second slot so a two-type search has something to
## find.
static func types_for(number: int) -> Array:
	var first: int = Gen2Pokedex.SEARCH_TYPES[(number - 1) % Gen2Pokedex.SEARCH_TYPES.size()]
	var second: int = RomLayout.TYPE_FIRE if number % 10 == 0 else first
	return [first, second]


## One word per Unown form, each opening on its own letter the way the
## cartridge's do, so a test can tell which form the dex is showing.
static func unown_words() -> Array:
	var out: Array = []
	for form: int in RomLayout.UNOWN_FORMS:
		out.append("%sWORD" % char("A".unicode_at(0) + form))
	return out


static func directory() -> String:
	return RomCache.directory_for(GAME_ID, SHA1)


static func build() -> GameData:
	var path: String = directory()
	RomCache.clear(path)
	RomCache.prepare(path)
	RomCache.write_json(RomCache.species_path(path), _species())
	RomCache.write_json(RomCache.dex_orders_path(path), {
		"new": new_order(), "alpha": alpha_order(),
	})
	RomCache.write_json(RomCache.manifest_path(path), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": String(GAME_ID),
		"sha1": SHA1,
		"complete": true,
		"unown_words": unown_words(),
		"tiles": _tiles(path),
		## `_CGB_Pokedex`'s three, at their real values so a page test reads the
		## colours the screen actually draws through.
		"pokedex_palettes": {
			"interface": [0x7FFF, 0x2A9F, 0x195A, 0x0000],
			"question_mark": [0x2EB, 0x227, 0xCC6, 0x584],
			"cursor": [0x0000, 0x2EB, 0x227, 0x0000],
		},
	})
	return GameData.open_directory(path)


## Heights and weights are the species number and twice it, so a formatting test
## can pick a number and know what it should read without a table here.
static func _species() -> Array:
	var out: Array = []
	for number: int in range(1, RomLayout.SPECIES_COUNT + 1):
		out.append({
			"number": number,
			"name": species_name(number),
			"types": types_for(number),
			"dex": {
				"category": "CAT%03d" % number,
				"height": number,
				"weight": number * 2,
				"pages": ["page one %d" % number, "page two %d" % number],
			},
		})
	return out


## `Pokedex_LoadGFX`'s sheets and the font the page draws characters with, each
## at its real length and filled with its own index, so a test can say which
## sheet a cell came from by reading one pixel.
static func _tiles(path: String) -> Dictionary:
	var sheets: Dictionary = {}
	for entry: Array in [
		["font", RomLayout.FONT_TILES, 3, RomLayout.FONT_FIRST_CODE],
		["pokedex", RomLayout.POKEDEX_TILES, 1, 0],
		["pokedex_slowpoke", RomLayout.POKEDEX_SLOWPOKE_TILES, 2, 0],
		["unown_font", RomLayout.UNOWN_FONT_TILES, 3, 0],
		["footprints", RomLayout.FOOTPRINT_SLOTS * RomLayout.FOOTPRINT_TILES, 1, 0],
	]:
		var name: String = String(entry[0])
		var count: int = int(entry[1])
		var indices := PackedByteArray()
		indices.resize(count * Gen2Tiles.TILE_PIXELS)
		indices.fill(int(entry[2]))
		RomCache.write_indices(RomCache.tile_path(path, name), indices)
		sheets[name] = {
			"width": count * Gen2Tiles.TILE_WIDTH,
			"height": Gen2Tiles.TILE_HEIGHT,
			"tiles": count,
			"first_code": int(entry[3]),
			"bits": 1,
		}
	return sheets
