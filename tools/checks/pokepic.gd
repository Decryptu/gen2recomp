extends RefCounted

var _r: RefCounted = null

## Verifies `PadFrontpic`'s placement against freshly imported real caches: the
## whole species corpus on all three cartridges, through both boxes a front pic
## is drawn in, `Script_pokepic`'s [Gen2PokepicPage] and the battle screen's own
## 7x7 block.
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
		_check_battle_block(pic, species, tiles)
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


## The same pad in the battle screen's block. `PlaceGraphic` numbers the enemy's
## 7x7 box column-major from its own first tile, so the tile numbers a fight and
## an animation write only land on the pic if the pixels sit where `PadFrontpic`
## put them: bottom-aligned, one column in. A pic left at the block's corner is
## drawn a column left and a row or two high, which is what this catches.
func _check_battle_block(pic: Dictionary, species: int, tiles: Vector2i) -> void:
	var side: int = Gen2BattleScreenMap.ENEMY_SIDE
	var box: int = side * Gen2Font.TILE
	var block: PackedByteArray = Gen2BattleRenderer.padded_pic(_r.data, pic, side, true)
	if not _r.check(block.size() == box * box, "species %d has no battle block." % species):
		return
	var at := Vector2i(
		Gen2PicImage.frontpic_pad_columns(tiles.x), Gen2PicImage.frontpic_pad_rows(tiles.y)
	) * Gen2Font.TILE
	var area := Rect2i(at, tiles * Gen2Font.TILE)
	_r.check(
		_block_ink(block, box, area),
		"species %d draws nothing where PadFrontpic puts it in the battle block." % species
	)
	## And nowhere else: every pixel outside the pic's own rectangle is the pad,
	## which the hardware leaves as the blank tile the block was filled with.
	var outside: bool = false
	for y: int in box:
		for x: int in box:
			if area.has_point(Vector2i(x, y)):
				continue
			outside = outside or block[y * box + x] != 0
	_r.check(
		not outside,
		"species %d draws outside its own pic in the battle block." % species
	)


## Whether [param area] of a battle block holds a pixel that is not colour 0.
func _block_ink(block: PackedByteArray, box: int, area: Rect2i) -> bool:
	for y: int in area.size.y:
		for x: int in area.size.x:
			if block[(area.position.y + y) * box + area.position.x + x] != 0:
				return true
	return false
