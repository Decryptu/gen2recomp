extends GutTest

## The trainer card's tile layout (engine/menus/trainer_card.asm), checked as
## the tile map rather than as pixels: the fixture's card sheets are flat fills,
## so what a page is worth testing for is where each thing lands.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _page: Gen2TrainerCardPage = null


func before_each() -> void:
	_data = Fixture.build()
	_page = Gen2TrainerCardPage.from_data(_data, false, true)
	_page.load_page_tiles(_data, Gen2TrainerCardPage.PAGE_1)


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func _card(page_number: int = Gen2TrainerCardPage.PAGE_1) -> Dictionary:
	return {
		"page": page_number,
		"player_name": "GOLD",
		"player_id": 54321,
		"money": 12345,
		"pokedex": true,
		"caught": 3,
		"hours": "  37",
		"minutes": "08",
		"separator": true,
	}


func test_a_cache_with_the_card_sheets_is_ready() -> void:
	assert_not_null(_page)
	assert_true(_page.ready())


func test_the_page_is_the_hardware_screen() -> void:
	var indices: PackedByteArray = _page.draw(_card())
	assert_eq(indices.size(), Gen2Screen.WIDTH * Gen2Screen.HEIGHT)


## `_CGB_TrainerCard`: the card takes the opposite gender's palette and the pic
## area the player's own, the leader boxes take one palette each, Clair's box is
## filled for Kris alone, and the corner keeps the border's.
func test_the_attribute_map_is_the_source_layout() -> void:
	var male: PackedInt32Array = _page.attributes()
	assert_eq(male[0], 1, "Chris's card is drawn in Kris's palette")
	assert_eq(_at(male, Gen2TrainerCardPage.PIC_AT), 0)
	assert_eq(_at(male, Gen2TrainerCardPage.CORNER_AT), 1)
	assert_eq(_at(male, Vector2i(2, 11)), 1)
	assert_eq(_at(male, Vector2i(10, 14)), 7)
	assert_eq(_at(male, Gen2TrainerCardPage.CLAIR_BOX_AT), 1 as int, "unfilled, so the border's")

	var female: PackedInt32Array = Gen2TrainerCardPage.from_data(_data, true, true).attributes()
	assert_eq(female[0], 0)
	assert_eq(_at(female, Gen2TrainerCardPage.PIC_AT), 1)
	assert_eq(_at(female, Gen2TrainerCardPage.CORNER_AT), 0)
	assert_eq(_at(female, Gen2TrainerCardPage.CLAIR_BOX_AT), 1)


## Crystal loads a tile of its own over the pic's $1c; Gold and Silver point at
## $04, inside the pic, instead.
func test_the_border_corner_tile_is_profile_split() -> void:
	assert_eq(_page.corner_tile(), Gen2TrainerCardPage.CORNER_TILE_CRYSTAL)
	var gold: Gen2TrainerCardPage = Gen2TrainerCardPage.from_data(_data, false, false)
	assert_eq(gold.corner_tile(), Gen2TrainerCardPage.CORNER_TILE_GOLD_SILVER)


## A page drawn twice with the same values is the same page; drawn with the
## separator off it differs, and only in that one tile's column.
func test_the_blinking_separator_is_the_only_difference_a_frame_makes() -> void:
	var on: PackedByteArray = _page.draw(_card())
	assert_eq(_page.draw(_card()), on)
	var card: Dictionary = _card()
	card["separator"] = false
	var off: PackedByteArray = _page.draw(card)
	assert_ne(off, on)
	assert_eq(
		_changed_tiles(on, off), [Gen2TrainerCardPage.SEPARATOR_AT],
		"only the colon's own tile changes"
	)


## The dex row is not printed at all without STATUSFLAGS_POKEDEX_F, which is
## what the source's own ClearBox leaves behind.
func test_the_dex_count_is_absent_without_the_pokedex() -> void:
	var card: Dictionary = _card()
	card["pokedex"] = false
	var changed: Array = _changed_tiles(_page.draw(_card()), _page.draw(card))
	assert_false(changed.is_empty())
	for at: Vector2i in changed:
		assert_eq(at.y, Gen2TrainerCardPage.DEX_COUNT_AT.y)


## Page 2 replaces the status box with the leaders' faces, and the top half of
## the card is untouched between them.
func test_the_badge_page_keeps_the_top_half_and_changes_the_bottom() -> void:
	var page_one: PackedByteArray = _page.draw(_card())
	_page.load_page_tiles(_data, Gen2TrainerCardPage.PAGE_2)
	var page_two: PackedByteArray = _page.draw(_card(Gen2TrainerCardPage.PAGE_2))
	for at: Vector2i in _changed_tiles(page_one, page_two):
		assert_true(
			at.y >= Gen2TrainerCardPage.BOTTOM_BORDER_AT.y,
			"only the lower box changes, not %s" % at
		)


func _at(map: PackedInt32Array, cell: Vector2i) -> int:
	return map[cell.y * Gen2TrainerCardPage.COLUMNS + cell.x]


## Which tile cells differ between two drawn pages.
func _changed_tiles(before: PackedByteArray, after: PackedByteArray) -> Array:
	var tile: int = Gen2TrainerCardPage.TILE
	var out: Array = []
	for row: int in Gen2TrainerCardPage.ROWS:
		for column: int in Gen2TrainerCardPage.COLUMNS:
			for y: int in tile:
				var start: int = (row * tile + y) * Gen2Screen.WIDTH + column * tile
				if before.slice(start, start + tile) != after.slice(start, start + tile):
					out.append(Vector2i(column, row))
					break
	return out
