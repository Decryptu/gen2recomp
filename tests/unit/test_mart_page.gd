extends GutTest

## `BuyMenu`'s screen on the tile grid, against a synthetic cache.
##
## The fixture fills each sheet with an index of its own, so a drawn pixel says
## which strip it came from and an untouched one reads 0: that is what tells the
## arrow's own tile from a glyph without a real cartridge.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const TILE: int = Gen2Font.TILE

var _page: Gen2MartPage = null


func before_each() -> void:
	Fixture.build()
	_page = Gen2MartPage.from_data(GameData.open_directory(Fixture.directory()))


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func _state(overrides: Dictionary = {}) -> Dictionary:
	var state: Dictionary = {
		"money": 3000,
		"rows": [
			{"name": "POTION", "price": 300},
			{"name": "ANTIDOTE", "price": 100},
			{"cancel": true},
		],
		"cursor": 0,
		"scrolled": false,
		"text": "A spray-type\nmedicine.",
		"quantity": -1,
		"subtotal": 0,
	}
	state.merge(overrides, true)
	return state


func _ink(image: Image, tile: Vector2i) -> bool:
	for row: int in TILE:
		for column: int in TILE:
			if image.get_pixel(tile.x * TILE + column, tile.y * TILE + row) != Color.WHITE:
				return true
	return false


func test_the_money_box_stands_in_the_top_right_corner() -> void:
	var image: Image = _page.render(_state())
	assert_eq(image.get_size(), Vector2i(Gen2Screen.WIDTH, Gen2Screen.HEIGHT))
	assert_true(_ink(image, Gen2MartPage.MONEY_AT), "the box's own corner is drawn")
	## `PlaceMoneyTextbox` prints seven cells from (12,1), and the two rows above
	## the list are otherwise empty.
	assert_true(_ink(image, Gen2MartPage.MONEY_TEXT_AT + Vector2i(6, 0)))
	assert_false(_ink(image, Vector2i(0, 1)), "nothing is drawn left of the box")


func test_a_row_prints_its_price_on_the_row_below_its_name() -> void:
	var image: Image = _page.render(_state())
	assert_true(_ink(image, Gen2MartPage.NAME_AT), "the first name is drawn")
	## The price is seven cells right aligned from its own column, so what says
	## it landed is its last digit rather than the column it starts in.
	var price_at := Vector2i(
		Gen2MartPage.PRICE_COLUMN + Gen2MartPage.MONEY_CELLS - 1, Gen2MartPage.NAME_AT.y + 1
	)
	assert_true(_ink(image, price_at), "its price is one row below it")
	assert_false(
		_ink(image, price_at - Vector2i(0, 1)), "and not beside it"
	)
	## `Place2DMenuCursor` writes on the list's own left border coordinate.
	assert_true(_ink(image, Vector2i(Gen2MartPage.LIST_AT.x, Gen2MartPage.NAME_AT.y)))
	assert_false(
		_ink(image, Vector2i(Gen2MartPage.LIST_AT.x, Gen2MartPage.NAME_AT.y + 2)),
		"the arrow is on one row only"
	)


func test_the_down_arrow_is_always_drawn_and_the_up_one_waits_for_a_scroll() -> void:
	var image: Image = _page.render(_state())
	assert_true(
		_ink(image, Vector2i(Gen2MartPage.LIST_RIGHT, Gen2MartPage.LIST_BOTTOM)),
		"SCROLLINGMENU_DISPLAY_ARROWS draws the down arrow whatever the scroll is"
	)
	assert_false(_ink(image, Vector2i(Gen2MartPage.LIST_RIGHT, Gen2MartPage.LIST_AT.y)))
	var scrolled: Image = _page.render(_state({"scrolled": true}))
	assert_true(_ink(scrolled, Vector2i(Gen2MartPage.LIST_RIGHT, Gen2MartPage.LIST_AT.y)))


func test_the_quantity_box_stands_over_the_speech_box() -> void:
	var plain: Image = _page.render(_state())
	assert_false(_ink(plain, Gen2MartPage.QUANTITY_AT), "no frame until one is asked for")
	var asked: Image = _page.render(_state({"quantity": 2, "subtotal": 600}))
	assert_true(_ink(asked, Gen2MartPage.QUANTITY_TEXT_AT), "×02 is drawn")
	assert_true(
		_ink(asked, Gen2MartPage.SUBTOTAL_AT + Vector2i(Gen2MartPage.MONEY_CELLS - 1, 0)),
		"and the subtotal beside it"
	)
	assert_true(_ink(asked, Gen2MartPage.QUANTITY_AT), "inside its own frame")


func test_money_is_right_aligned_against_its_own_yen_sign() -> void:
	assert_eq(Gen2MartPage.money_string(200), "   ¥200")
	assert_eq(Gen2MartPage.money_string(999999), "¥999999")
	assert_eq(Gen2MartPage.money_string(0), "     ¥0")


func test_the_speech_box_prints_its_lines_two_rows_apart() -> void:
	var image: Image = _page.render(_state())
	assert_true(_ink(image, Gen2MartPage.TEXT_AT))
	assert_true(_ink(image, Gen2MartPage.TEXT_AT + Vector2i(0, Gen2MartPage.TEXT_SPACING)))
	assert_false(
		_ink(image, Gen2MartPage.TEXT_AT + Vector2i(0, 1)),
		"the row between them is the box's own spacing"
	)
