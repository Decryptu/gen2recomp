extends RefCounted

var _r: RefCounted = null

## Verifies `_CGB_StatsScreenHPPals` and `_CGB_MoveList` against freshly imported
## real caches: every species, every page, on all three cartridges.
##
## What a sampled case cannot say: the two screens are drawn in six palettes at
## once and every one of them is a different table. A page drawn in one palette
## is right about the text and wrong about everything else, and a slot one out
## still produces a legible screen, so what is checked here is CONTAINMENT: the
## colours a region is drawn in have to come from the palette its attrmap slot
## names and from no other. The regions differ per species (the mon palette),
## per page (the tint) and per hit points (the HP palette), which is why the
## sweep is the corpus rather than one Pokémon.
##
## `LoadStatsScreenPals` writes the open page's colour over colour 0 of the HP
## and exp palettes alone, so the tint is checked as an identity as well: the
## lower half's background IS `StatsScreenPals`' own entry for that page.
##
##   Godot --headless --path . -s res://tools/validate.gd -- screen_palettes

## `data/pokemon/base_stats/`'s own range.
const FIRST_SPECIES: int = 1
const LAST_SPECIES: int = 251

const TILE: int = Gen2Font.TILE
const COLUMNS: int = Gen2StatsScreenPage.COLUMNS
const ROWS: int = Gen2StatsScreenPage.ROWS

## `_CGB_StatsScreenHPPals`' own `hlcoord` and `lb bc` operands, transcribed
## here rather than taken from the page: a check that reads the implementation's
## own attrmap agrees with it however wrong it is. `FillBoxCGB` takes (rows,
## columns) and `ByteFill` a length, so the exp bar's ten cells are one row.
const SOURCE_BOXES: Array = [
	[0, 0, 20, 8, 1],
	[10, 16, 10, 1, 2],
	[13, 5, 2, 2, 3],
	[15, 5, 2, 2, 4],
	[17, 5, 2, 2, 5],
]

## `_CGB_MoveList`'s one `FillBoxCGB`, the same way.
const SOURCE_MOVE_BOXES: Array = [[11, 1, 9, 2, 1]]

## Hit points to draw each page with, so all three `GetHPPal` bands are swept:
## full is green, `HP_YELLOW_PIXELS` of the bar is yellow and one is red.
const HP_FRACTIONS: Array[float] = [1.0, 0.3, 0.05]


func run(r: RefCounted) -> void:
	_r = r
	_r.each_game(_check_game)


func _check_game() -> void:
	var page: Gen2StatsScreenPage = Gen2StatsScreenPage.from_data(_r.data)
	if not _r.check(page != null, "the stats screen page will not build."):
		return
	var pages: int = Gen2StatsScreenPage.page_count()
	if not _r.check(
		pages == Gen2StatsScreenPage.NUM_PAGES,
		"a mod is registering stats pages, so the source's attrmap is not the one drawn."
	):
		return
	if not _r.check(
		Array(Gen2StatsScreenPage.attributes(pages)) == Array(_source_slots()),
		"the stats screen's attrmap is not `_CGB_StatsScreenHPPals`'."
	):
		return
	var drawn: int = 0
	for species: int in range(FIRST_SPECIES, LAST_SPECIES + 1):
		for number: int in range(
			Gen2StatsScreenPage.PINK_PAGE, Gen2StatsScreenPage.PINK_PAGE + pages
		):
			var hp: float = HP_FRACTIONS[(species + number) % HP_FRACTIONS.size()]
			if not _check_page(page, species, number, hp, pages):
				return
			drawn += 1
	_check_egg(page)
	_check_move_screen()
	_r.note("screen_palettes %d stats pages over %d species and %d pages" % [
		drawn, LAST_SPECIES - FIRST_SPECIES + 1, pages,
	])


## One page, region by region. Returns false on the first failure so a broken
## rule reports once rather than 753 times.
func _check_page(
	page: Gen2StatsScreenPage, species: int, number: int, hp_fraction: float, pages: int
) -> bool:
	var max_hp: int = 100
	var hp: int = maxi(int(round(max_hp * hp_fraction)), 1)
	var snapshot: Dictionary = {
		"egg": false, "page": number, "species": species, "dex_number": species,
		"species_name": "X", "nickname": "X", "level": 5, "hp": hp, "max_hp": max_hp,
		"moves": [], "types": ["NORMAL"], "item_name": "---",
	}
	var image: Image = page.render(snapshot, _r.data)
	if not _r.check(image != null, "species %d page %d draws nothing." % [species, number]):
		return false

	var tint: Color = _r.data.stats_page_tint(number)
	var palettes: Array = _palettes(species, hp, max_hp, tint, pages)
	var slots: PackedInt32Array = _source_slots()
	for row: int in ROWS:
		for column: int in COLUMNS:
			var slot: int = slots[row * COLUMNS + column]
			var allowed: PackedColorArray = palettes[slot]
			for y: int in TILE:
				for x: int in TILE:
					var colour: Color = image.get_pixel(column * TILE + x, row * TILE + y)
					if allowed.has(colour):
						continue
					_r.check(false, (
						"species %d page %d cell %d,%d is %s, "
						+ "which palette %d does not hold."
					) % [species, number, column, row, colour, slot])
					return false

	## The identity `LoadStatsScreenPals` writes: colour 0 of the HP palette, and
	## so the background of every cell the attrmap left on slot 0.
	if not _r.check(
		image.get_pixel(0, (Gen2StatsScreenPage.MON_ROWS + 1) * TILE) == _quantised(
			PackedColorArray([tint]))[0],
		"species %d page %d does not tint the lower half." % [species, number]
	):
		return false
	return true


## The palette per attrmap slot, built here off [GameData] rather than taken from
## the page, so a page that names the wrong table has nothing to agree with.
func _palettes(
	species: int, hp: int, max_hp: int, tint: Color, pages: int
) -> Array:
	var lit: int = Gen2BattleHud.bar_pixels(hp, max_hp, Gen2BattleHud.HP_BAR_TILES * TILE)
	var out: Array = [
		_tinted(_r.data.bar_palette(GameData.hp_bar_palette_name(lit)), tint),
		_quantised(_r.data.palette(species) if species > 0 else _r.data.egg_palette()),
		_tinted(_r.data.bar_palette(GameData.EXP_BAR_PALETTE), tint),
	]
	for index: int in pages:
		out.append(_quantised(
			_r.data.stats_page_palette(Gen2StatsScreenPage.PINK_PAGE + index)
		))
	return out


func _tinted(palette: PackedColorArray, colour: Color) -> PackedColorArray:
	var out: PackedColorArray = palette.duplicate()
	if not out.is_empty():
		out[0] = colour
	return _quantised(out)


## The source's own boxes, flattened the way `WipeAttrmap` plus `FillBoxCGB`
## leaves them.
func _source_slots() -> PackedInt32Array:
	return Gen2PicImage.attribute_boxes(SOURCE_BOXES, COLUMNS, ROWS)


## A 15-bit colour is stored as a float and read back through an eight-bit
## image, so the comparison is made where the picture is: `Color8`'s own
## rounding, which is what [method Gen2PicImage.from_attributes] wrote.
func _quantised(palette: PackedColorArray) -> PackedColorArray:
	var out := PackedColorArray()
	for colour: Color in palette:
		out.append(Color8(
			int(roundf(colour.r * 255.0)), int(roundf(colour.g * 255.0)),
			int(roundf(colour.b * 255.0)), int(roundf(colour.a * 255.0))
		))
	return out


## `EggStatsInit` jumps past `StatsScreen_LoadPage`, so an egg reaches
## `LoadStatsScreenPals` on no cartridge and its screen keeps the white both
## palettes were loaded with. The picture is the egg's own palette, not a
## species'.
func _check_egg(page: Gen2StatsScreenPage) -> void:
	var image: Image = page.render(
		{"egg": true, "page": Gen2StatsScreenPage.PINK_PAGE, "species": 0, "egg_message": "X"},
		_r.data
	)
	if not _r.check(image != null, "the egg stats screen draws nothing."):
		return
	_r.check(
		image.get_pixel(0, (Gen2StatsScreenPage.MON_ROWS + 1) * TILE) == Color.WHITE,
		"an egg's stats screen is tinted, and no cartridge tints one."
	)
	var slots: PackedInt32Array = _source_slots()
	var egg: PackedColorArray = _quantised(_r.data.egg_palette())
	for row: int in Gen2StatsScreenPage.MON_ROWS:
		for column: int in COLUMNS:
			if slots[row * COLUMNS + column] != Gen2StatsScreenPage.MON_SLOT:
				continue
			for y: int in TILE:
				for x: int in TILE:
					if egg.has(image.get_pixel(column * TILE + x, row * TILE + y)):
						continue
					_r.check(false, "the egg screen's cell %d,%d is not the egg's own colour." % [
						column, row,
					])
					return


## `_CGB_MoveList`: `PREDEFPAL_GOLDENROD` everywhere and the Pokémon's own HP
## palette on the nine cells beside the nickname.
func _check_move_screen() -> void:
	var page: Gen2MoveScreenPage = Gen2MoveScreenPage.from_data(_r.data)
	if not _r.check(page != null, "the move screen page will not build."):
		return
	var goldenrod: PackedColorArray = _quantised(_r.data.move_screen_palette())
	_r.check(
		goldenrod.size() == RomLayout.PREDEF_PALETTE_COLORS,
		"the move screen's palette is %d colours, not %d." % [
			goldenrod.size(), RomLayout.PREDEF_PALETTE_COLORS,
		]
	)
	var image: Image = page.render(
		{
			"species": FIRST_SPECIES, "nickname": "X", "level": 5, "hp": 1, "max_hp": 100,
			"moves": [], "cursor": 0, "held": -1,
		},
		_r.data
	)
	if not _r.check(image != null, "the move screen draws nothing."):
		return
	if not _r.check(
		Array(Gen2MoveScreenPage.attributes()) == Array(
			Gen2PicImage.attribute_boxes(SOURCE_MOVE_BOXES, COLUMNS, ROWS)
		),
		"the move screen's attrmap is not `_CGB_MoveList`'."
	):
		return
	var slots: PackedInt32Array = Gen2PicImage.attribute_boxes(
		SOURCE_MOVE_BOXES, COLUMNS, ROWS
	)
	var hp: PackedColorArray = _quantised(_r.data.bar_palette(
		GameData.hp_bar_palette_name(Gen2BattleHud.bar_pixels(
			1, 100, Gen2BattleHud.HP_BAR_TILES * TILE
		))
	))
	for row: int in ROWS:
		for column: int in COLUMNS:
			var allowed: PackedColorArray = hp \
				if slots[row * COLUMNS + column] == 1 else goldenrod
			for y: int in TILE:
				for x: int in TILE:
					var colour: Color = image.get_pixel(column * TILE + x, row * TILE + y)
					if allowed.has(colour):
						continue
					_r.check(false, "move screen cell %d,%d is %s, off its own palette." % [
						column, row, colour,
					])
					return
