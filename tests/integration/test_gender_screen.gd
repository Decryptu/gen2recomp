extends GutTest

## `engine/menus/init_gender.asm`: the two-option menu, its wrap, the gender it
## writes and the cartridges that have no such screen at all.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const QUESTION: String = "Are you a boy?\nOr are you a girl?"

var _screen: Gen2GenderScreen = null
var _chosen: Array = []


func before_each() -> void:
	Fixture.build()
	_chosen = []
	_screen = Gen2GenderScreen.new()
	add_child_autofree(_screen)
	_screen.open(GameData.open_directory(Fixture.directory()))
	_screen.closed.connect(func(value: int) -> void: _chosen.append(value))


func after_each() -> void:
	RomCache.clear(Fixture.directory())


## A Gold or Silver cache, which carries every Oak text and no gender one.
func _drop_gender_text() -> void:
	var text: Variant = RomCache.read_json(RomCache.intro_text_path(Fixture.directory()))
	var without: Dictionary = text if text is Dictionary else {}
	without.erase("gender")
	RomCache.write_json(RomCache.intro_text_path(Fixture.directory()), without)


## `.MenuHeader`'s `db 1`, one-based, so Boy is the option the cursor opens on.
func test_it_opens_on_boy() -> void:
	assert_eq(_screen.menu().selected_index(), 0)
	assert_eq(_screen.menu().options.size(), 2)


func test_a_answers_with_the_gender_the_cursor_is_on() -> void:
	_screen.handle_button(Gen2Button.A)
	assert_eq(_chosen, [Gen2SaveData.GENDER_MALE])


func test_moving_down_then_a_answers_girl() -> void:
	_screen.handle_button(Gen2Button.DOWN)
	assert_eq(_screen.menu().selected_index(), 1)
	_screen.handle_button(Gen2Button.A)
	assert_eq(_chosen, [Gen2SaveData.GENDER_FEMALE])


## STATICMENU_WRAP is on `.MenuData`, so the cursor wraps at both ends.
func test_the_cursor_wraps() -> void:
	_screen.handle_button(Gen2Button.UP)
	assert_eq(_screen.menu().selected_index(), 1, "up off the first wraps to the last")
	_screen.handle_button(Gen2Button.DOWN)
	assert_eq(_screen.menu().selected_index(), 0)


## STATICMENU_DISABLE_B keeps B out of `wMenuJoypadFilter`, so there is no way
## out of this screen but a choice.
func test_b_does_nothing() -> void:
	assert_false(_screen.handle_button(Gen2Button.B))
	assert_eq(_chosen, [])


## pokegold ships neither the routine nor its text, so the screen refuses to
## open rather than asking a question that cartridge never asks.
func test_a_cartridge_without_the_text_has_no_gender_screen() -> void:
	_drop_gender_text()
	var absent := Gen2GenderScreen.new()
	add_child_autofree(absent)
	assert_false(absent.open(GameData.open_directory(Fixture.directory())))


## The page is a real 160x144 buffer with the question in the text box and the
## menu over it, so both can be read back without a window.
func test_the_page_draws_the_question_and_the_menu() -> void:
	var page := Gen2GenderScreenPage.from_data(GameData.open_directory(Fixture.directory()))
	var indices: PackedByteArray = page.draw(QUESTION, 0)
	assert_eq(indices.size(), Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	assert_true(_ink(indices, Vector2i(1, 14)), "the first line of the question")
	assert_true(_ink(indices, Vector2i(1, 16)), "the second line, two rows down")
	assert_true(_ink(indices, Vector2i(6, 4)), "the menu's own top-left corner")
	assert_true(_ink(indices, Vector2i(7, 6)), "the cursor on Boy")
	assert_false(_ink(indices, Vector2i(7, 8)), "no cursor on Girl")


## `InitGenderScreen` fills the whole tilemap with tile $00, which
## `LoadGenderScreenLightBlueTile` has just filled with one index, so the field
## is that index and only the boxes drawn over it are blank.
func test_the_page_fills_the_field_with_the_light_blue_tile() -> void:
	var page := Gen2GenderScreenPage.from_data(GameData.open_directory(Fixture.directory()))
	var indices: PackedByteArray = page.draw(QUESTION, 0)
	assert_eq(indices[0], RomLayout.GENDER_SCREEN_FILL_INDEX, "the top-left corner of the field")
	assert_eq(
		_at(indices, Vector2i(2, 11)),
		RomLayout.GENDER_SCREEN_FILL_INDEX,
		"and the row above the text box, which no box reaches"
	)
	# `TextboxBorder` runs ' ' across the interior rows, so the field does not
	# show through the question.
	assert_eq(_at(indices, Vector2i(10, 13)), 0, "the text box interior is blank")
	assert_eq(_at(indices, Vector2i(9, 5)), 0, "and so is the menu's")


## The four colours are the cartridge's own, so the field is the light blue
## `gfx/new_game/gender_screen.pal` names rather than a chosen one.
func test_the_page_carries_the_source_palette() -> void:
	var page := Gen2GenderScreenPage.from_data(GameData.open_directory(Fixture.directory()))
	assert_eq(page.palette.size(), RomLayout.GENDER_SCREEN_PALETTE_COLORS)
	assert_eq(page.palette[0], Color.WHITE)
	assert_eq(page.palette[1], Gen2Palette.from_packed(0x7FC9))
	assert_eq(page.palette[3], Color.BLACK)


## A cache written before the tile was imported has no fill and no palette, and
## draws the black-on-white every other 1bpp page here uses rather than refusing.
func test_a_cache_without_the_tile_draws_the_plain_page() -> void:
	var directory: String = Fixture.directory()
	var manifest: Dictionary = RomCache.read_manifest(directory)
	var sheets: Dictionary = manifest["tiles"]
	sheets.erase("gender_screen")
	manifest["tiles"] = sheets
	manifest["gender_screen_palette"] = []
	RomCache.write_json(RomCache.manifest_path(directory), manifest)

	var page := Gen2GenderScreenPage.from_data(GameData.open_directory(directory))
	assert_eq(page.palette.size(), 0)
	assert_eq(page.draw(QUESTION, 0)[0], 0, "the field falls back to blank")


func _at(indices: PackedByteArray, tile: Vector2i) -> int:
	return indices[
		(tile.y * Gen2Font.TILE + 4) * Gen2Screen.WIDTH + tile.x * Gen2Font.TILE + 4
	]


func _ink(indices: PackedByteArray, tile: Vector2i) -> bool:
	for row: int in Gen2Font.TILE:
		for column: int in Gen2Font.TILE:
			var at: int = (tile.y * Gen2Font.TILE + row) * Gen2Screen.WIDTH \
				+ tile.x * Gen2Font.TILE + column
			if at < indices.size() and indices[at] != 0:
				return true
	return false
