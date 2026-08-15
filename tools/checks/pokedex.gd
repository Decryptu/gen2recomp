extends RefCounted

var _r: RefCounted = null

## Verifies the Pokedex's own graphics against freshly imported real caches, on
## all three cartridges.
##
## The expected values come from the pinned sources: `Pokedex_LoadGFX`'s two LZ
## runs, `gfx/footprints.asm`'s 16x64-tile grid, `Pokedex_LoadUnownFont` and
## `_CGB_Pokedex`'s three palettes.
##
## The real-cartridge counterpart to tests/unit/test_pokedex.gd, which uses a
## synthetic cache. What only a real cache can say is that the runs decompressed
## to exactly the tiles the source asks for, that all three dumps carry the same
## art, that every one of the 251 footprints is a real picture rather than the
## blank the grid's tail is, and that every species draws an entry screen whose
## own four footprint cells resolve.
##
##   Godot --headless --path . -s res://tools/validate.gd -- pokedex

## `Pokedex_LoadGFX` decompresses `PokedexLZ` to `vTiles2 tile $31`, so the sheet
## number a layout writes is offset by this and the last one it can name is
## `$6a`.
const SHEET_FIRST: int = Gen2PokedexPage.SHEET_FIRST_TILE

## Every species has a footprint, so a slot with no lit pixel at all is a defect
## rather than a species that has none.
const SPECIES: int = RomLayout.FOOTPRINT_SPECIES


func run(r: RefCounted) -> void:
	_r = r
	var digests: Dictionary = {}
	for game_id: StringName in _r.GAME_IDS:
		var digest: String = _validate(game_id)
		if digest.is_empty():
			_r.fail("%s: the Pokedex graphics did not check out." % game_id)
			continue
		digests[game_id] = digest
	var unique: Dictionary = {}
	for game_id: Variant in digests:
		unique[digests[game_id]] = true
	if digests.size() == _r.GAME_IDS.size() and unique.size() != 1:
		_r.fail("The three dumps do not carry the same Pokedex art: %s" % digests)
	else:
		print("  art identical on all three: %s" % [unique.keys()])


## Answers a digest of the three sheets, or "" when the cache failed a check.
func _validate(game_id: StringName) -> String:
	var data: GameData = GameData.open(game_id)
	if data == null:
		print("FAIL %s: cache is not usable" % game_id)
		return ""

	var ok: bool = true
	for sheet: Array in [
		["pokedex", RomLayout.POKEDEX_TILES],
		["pokedex_slowpoke", RomLayout.POKEDEX_SLOWPOKE_TILES],
		["unown_font", RomLayout.UNOWN_FONT_TILES],
		["footprints", RomLayout.FOOTPRINT_SLOTS * RomLayout.FOOTPRINT_TILES],
	]:
		var name: String = String(sheet[0])
		var wanted: int = int(sheet[1])
		var entry: Dictionary = data.tile_sheet(name)
		if int(entry.get("tiles", 0)) != wanted:
			print("FAIL %s: %s is %d tiles, wanted %d" % [
				game_id, name, int(entry.get("tiles", 0)), wanted,
			])
			ok = false
	if not ok:
		return ""

	for name: String in ["interface", "question_mark", "cursor"]:
		if data.pokedex_palette(name).size() != Gen2Palette.COLORS_PER_PIC:
			print("FAIL %s: the %s palette is not four colours" % [game_id, name])
			return ""

	var page: Gen2PokedexPage = Gen2PokedexPage.from_data(data)
	if page == null or not page.ready():
		print("FAIL %s: the page would not build" % game_id)
		return ""

	# Every species' four footprint tiles, checked for being inside the strip and
	# for carrying a picture: the grid's own tail is blank, and a species landing
	# in it would be a stride error rather than an absent footprint.
	var indices: PackedByteArray = data.tile_indices("footprints")
	@warning_ignore("integer_division")
	var width: int = indices.size() / Gen2Tiles.TILE_HEIGHT
	var blank: Array[int] = []
	for species: int in range(1, SPECIES + 1):
		var tiles: PackedInt32Array = data.footprint_tiles(species)
		if tiles.size() != RomLayout.FOOTPRINT_TILES:
			print("FAIL %s: species %d has no footprint" % [game_id, species])
			return ""
		var lit: int = 0
		for tile: int in tiles:
			if (tile + 1) * Gen2Tiles.TILE_WIDTH > width:
				print("FAIL %s: footprint tile %d of species %d is off the strip" % [
					game_id, tile, species,
				])
				return ""
			for y: int in Gen2Tiles.TILE_HEIGHT:
				for x: int in Gen2Tiles.TILE_WIDTH:
					if indices[y * width + tile * Gen2Tiles.TILE_WIDTH + x] != 0:
						lit += 1
		if lit == 0:
			blank.append(species)
	if not blank.is_empty():
		print("FAIL %s: %d species have a blank footprint: %s" % [
			game_id, blank.size(), blank.slice(0, 8),
		])
		return ""

	# Every entry screen, so a species whose dex record is short or whose pic is
	# missing is found here rather than on the screen.
	var short_entries: Array[int] = []
	for species: int in range(1, RomLayout.SPECIES_COUNT + 1):
		var entry: Dictionary = data.dex_entry(species)
		if entry.is_empty() or String(entry.get("category", "")).is_empty():
			short_entries.append(species)
			continue
		page.load_footprint(data, species)
		var map: PackedInt32Array = page.entry_map(
			species, String(data.species(species).get("name", "")), entry, true, Gen2Pokedex.PAGE_1, 0
		)
		if map.size() != Gen2PokedexPage.COLUMNS * Gen2PokedexPage.ROWS:
			print("FAIL %s: species %d drew no entry screen" % [game_id, species])
			return ""
	if not short_entries.is_empty():
		print("FAIL %s: %d species carry no dex entry: %s" % [
			game_id, short_entries.size(), short_entries.slice(0, 8),
		])
		return ""

	print("%s: sheet=%d slowpoke=%d unown_font=%d footprints=%d species=%d" % [
		game_id, RomLayout.POKEDEX_TILES, RomLayout.POKEDEX_SLOWPOKE_TILES,
		RomLayout.UNOWN_FONT_TILES, SPECIES, RomLayout.SPECIES_COUNT,
	])
	return "%s/%s/%s" % [
		indices.slice(0, 4096).hex_encode().sha1_text().substr(0, 8),
		data.tile_indices("pokedex").slice(0, 928).hex_encode().sha1_text().substr(0, 8),
		data.tile_indices("unown_font").hex_encode().sha1_text().substr(0, 8),
	]
