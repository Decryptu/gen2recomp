extends RefCounted

var _r: RefCounted = null

## Verifies `Script_pokepic`'s box against freshly imported real caches: the
## whole species corpus on all three cartridges, drawn through the same
## [Gen2PokepicPage] the world screen displays.
##
## What a sampled case cannot say: `PadFrontpic` gives a 5x5, a 6x6 and a 7x7
## three different corners inside `PlaceGraphic`'s block, so a page that centres
## a pic instead is right about roughly half the corpus. Every species is drawn
## and its ink is required to sit inside the frame and above the interior's last
## row, which is the row `lb bc, 7, 7` leaves empty in an eight-row interior.
##
##   Godot --headless --path . -s res://tools/validate.gd -- pokepic

## `data/pokemon/base_stats/`'s own range.
const FIRST_SPECIES: int = 1
const LAST_SPECIES: int = 251

## New Bark Town, whose group is untouched by the Gold and Silver map-id shifts
## (`HANDOFF.md`, "What a Gold/Silver leg costs"). Any map would do: what the
## box reads off one is its eight background palettes.
const MAP_GROUP: int = 24
const MAP_NUMBER: int = 4


func run(r: RefCounted) -> void:
	_r = r
	_r.each_game(_check_game)


func _check_game() -> void:
	var map: Gen2WorldMap = _r.data.world_map(MAP_GROUP, MAP_NUMBER)
	if not _r.check(map != null, "map %d/%d is missing." % [MAP_GROUP, MAP_NUMBER]):
		return
	var box: Gen2MenuBox = Gen2PokepicPage.menu_box()
	var size: Vector2i = box.border_size() * Gen2Font.TILE
	var sizes: Dictionary = {}
	var drawn: int = 0
	for species: int in range(FIRST_SPECIES, LAST_SPECIES + 1):
		var image: Image = Gen2PokepicPage.render(_r.data, species, map)
		if not _r.check(image != null, "species %d draws no box." % species):
			continue
		if not _r.check(
			image.get_size() == size,
			"species %d draws %s, not the header's %s." % [species, image.get_size(), size]
		):
			continue
		drawn += 1
		var pic: Dictionary = _r.data.species_pic(species)
		var tiles := Vector2i(
			int(pic["width"]) / Gen2Font.TILE, int(pic["height"]) / Gen2Font.TILE
		)
		sizes[tiles] = int(sizes.get(tiles, 0)) + 1
		_check_placement(image, species, tiles)
	_r.note("pokepic %d of %d species, sizes %s" % [
		drawn, LAST_SPECIES - FIRST_SPECIES + 1, sizes
	])


## Where `PadFrontpic` says the pic is, and where it says it is not: the ink runs
## to the block's own bottom-right corner, and the interior row below it is the
## blank the box was filled with.
func _check_placement(image: Image, species: int, tiles: Vector2i) -> void:
	var at: Vector2i = Gen2PokepicPage.pic_position(tiles.x, tiles.y)
	var blank: Color = image.get_pixel(1, 1 + Gen2Font.TILE)
	var interior_rows: int = Gen2PokepicPage.menu_box().interior().y
	_r.check(
		_ink(image, Rect2i(at, Vector2i(tiles.x, tiles.y) * Gen2Font.TILE), blank),
		"species %d draws nothing where PadFrontpic puts its pic." % species
	)
	_r.check(
		not _ink(image, Rect2i(
			Vector2i(Gen2Font.TILE, interior_rows * Gen2Font.TILE),
			Vector2i(Gen2PicImage.FRONTPIC_TILES, 1) * Gen2Font.TILE
		), blank),
		"species %d draws on the interior row `lb bc, 7, 7` leaves empty." % species
	)


## Whether [param area] holds a pixel that is not the box's own blank.
func _ink(image: Image, area: Rect2i, blank: Color) -> bool:
	for y: int in area.size.y:
		for x: int in area.size.x:
			if image.get_pixel(area.position.x + x, area.position.y + y) != blank:
				return true
	return false
