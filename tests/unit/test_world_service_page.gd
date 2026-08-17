extends GutTest

## `MenuTextbox` over the map: the caller's own `menu_coords` box and its
## `MenuTextbox`-shaped message strip, against a synthetic cache.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const TILE: int = Gen2Font.TILE

var _page: Gen2WorldServicePage = null


func before_each() -> void:
	Fixture.build()
	_page = Gen2WorldServicePage.from_data(GameData.open_directory(Fixture.directory()))


func after_each() -> void:
	RomCache.clear(Fixture.directory())


## The page draws onto a transparent buffer and only `blit_rect`s the boxes it
## actually places, so a tile with nothing on it stays fully transparent.
func _ink(image: Image, tile: Vector2i) -> bool:
	for row: int in TILE:
		for column: int in TILE:
			if image.get_pixel(tile.x * TILE + column, tile.y * TILE + row).a > 0.0:
				return true
	return false


## `MENU_BACKUP_TILES` keeps the map behind the box; nothing here fills the
## screen white the way the old `full_screen` flag did.
func test_no_box_leaves_the_map_area_untouched() -> void:
	var image: Image = _page.render("PC", "", [], -1, "")
	assert_eq(image.get_size(), Vector2i(Gen2Screen.WIDTH, Gen2Screen.HEIGHT))
	assert_false(_ink(image, Vector2i(0, 0)), "no rows and no message draws nothing")


## `PokemonCenterPC.TopMenu`'s own `menu_coords 0, 0, 15, 12`: the frame's
## corner is drawn there and nothing spills into the four columns the source
## leaves for the map.
func test_a_row_box_draws_at_the_coords_it_is_given() -> void:
	var box := Gen2MenuBox.from_coords(0, 0, 15, 12, Gen2MenuBox.STATICMENU_CURSOR)
	var image: Image = _page.render("", "", ["BILL's PC"], 0, "", box)
	assert_true(_ink(image, Vector2i(0, 0)), "the box's own corner is drawn")
	assert_false(_ink(image, Vector2i(16, 0)), "nothing right of the source's own box")
	assert_false(_ink(image, Vector2i(0, 13)), "nothing below the source's own box")


## A `message` (or a `prompt` behind it) always draws `MenuTextbox`'s own
## bottom strip at rows 12 to 17, whether or not a row box is also up.
func test_the_message_draws_menu_textboxs_own_bottom_strip() -> void:
	var image: Image = _page.render("PC", "", [], -1, "Welcome.")
	assert_true(_ink(image, Vector2i(1, 13)), "the bottom strip prints inside its frame")
	assert_false(_ink(image, Vector2i(1, 11)), "and nothing above row 12")
