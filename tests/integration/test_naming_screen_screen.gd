extends GutTest

## The naming screen as a node: the buttons `.ReadButtons` reads, the redraw
## behind them, and the one press that ends it.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const TILE: int = Gen2Font.TILE
const WIDTH: int = Gen2Screen.WIDTH

var _screen: Gen2NamingScreenScreen = null
var _closed: Array = []


func before_each() -> void:
	Fixture.build()
	_closed = []
	_screen = Gen2NamingScreenScreen.new()
	add_child_autofree(_screen)
	_screen.open(GameData.open_directory(Fixture.directory()), "YOUR NAME?")
	_screen.closed.connect(func(value: String) -> void: _closed.append(value))


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func _model() -> Gen2NamingScreen:
	return _screen.model()


func _to_end() -> void:
	_screen.handle_button(Gen2Button.START)


func test_it_opens_on_the_upper_keyboard_with_an_empty_entry() -> void:
	assert_eq(_model().keyboard(), Gen2NamingScreen.Keyboard.NAME_UPPER)
	assert_eq(_model().length, 0)
	assert_eq(_model().column, 0)
	assert_eq(_model().row, 0)


func test_the_dpad_moves_the_cursor_and_never_ends_the_screen() -> void:
	assert_true(_screen.handle_button(Gen2Button.RIGHT))
	assert_eq(_model().column, 1)
	assert_true(_screen.handle_button(Gen2Button.DOWN))
	assert_eq(_model().row, 1)
	assert_eq(_closed.size(), 0)


func test_a_types_a_letter_and_b_takes_it_back() -> void:
	_screen.handle_button(Gen2Button.A)
	assert_eq(_model().length, 1)
	_screen.handle_button(Gen2Button.B)
	assert_eq(_model().length, 0)
	assert_eq(_closed.size(), 0)


func test_select_flips_the_case() -> void:
	_screen.handle_button(Gen2Button.SELECT)
	assert_eq(_model().keyboard(), Gen2NamingScreen.Keyboard.NAME_LOWER)


## `.start` puts the cursor on END, so START then A is the shortest way out.
func test_start_then_a_closes_with_what_was_typed() -> void:
	_screen.handle_button(Gen2Button.A)
	_screen.handle_button(Gen2Button.RIGHT)
	_screen.handle_button(Gen2Button.A)
	var typed: String = _model().stored_name()
	_to_end()
	assert_eq(_closed.size(), 0, "START alone does not end the screen")
	_screen.handle_button(Gen2Button.A)
	assert_eq(_closed, [typed])
	assert_eq(typed.length(), 2)


## `NamingScreen_StoreEntry` runs on END and nowhere else, so an empty entry is
## an empty name and it is the caller that decides what to do with one.
func test_ending_with_nothing_typed_reports_an_empty_name() -> void:
	_to_end()
	_screen.handle_button(Gen2Button.A)
	assert_eq(_closed, [""])


## The page is a real 160x144 buffer, so the screen can be photographed and read
## back without a window.
func test_the_page_is_drawn_at_the_hardware_size() -> void:
	var page := Gen2NamingScreenPage.from_data(GameData.open_directory(Fixture.directory()))
	assert_true(page.ready(), "every naming sheet is in the cache")
	var indices: PackedByteArray = page.draw(_model(), "YOUR NAME?")
	assert_eq(indices.size(), WIDTH * Gen2Screen.HEIGHT)


## `.OAMData_TextEntryCursor` is four 8x8 sprites at pixel (-1,-1), (0,-1),
## (-1,0) and (0,0), each drawing only its own top row and left column, so the
## bracket is a one-pixel 9x9 ring around a single letter tile. Drawn on the tile
## grid instead it was a 16x16 box with the letter in one quadrant.
func test_the_letter_bracket_is_a_nine_by_nine_ring_around_one_tile() -> void:
	var page := Gen2NamingScreenPage.from_data(GameData.open_directory(Fixture.directory()))
	var indices: PackedByteArray = page.draw(_model(), "YOUR NAME?")
	## `hlcoord 2, 8` puts the first letter at tile (2, 8), so the ring runs from
	## pixel (15, 63) to (23, 71) inclusive.
	for offset: int in range(0, 9):
		assert_ne(indices[63 * WIDTH + 15 + offset], 0, "top edge at x %d" % (15 + offset))
		assert_ne(indices[71 * WIDTH + 15 + offset], 0, "bottom edge at x %d" % (15 + offset))
		assert_ne(indices[(63 + offset) * WIDTH + 15], 0, "left edge at y %d" % (63 + offset))
		assert_ne(indices[(63 + offset) * WIDTH + 23], 0, "right edge at y %d" % (63 + offset))
	## The ring belongs to the cursor rather than to the keyboard under it, and it
	## steps a whole cell: both corners change when the cursor moves one column,
	## which is what pins the -1 offset without depending on the fixture's font.
	_screen.handle_button(Gen2Button.RIGHT)
	var moved: PackedByteArray = page.draw(_model(), "YOUR NAME?")
	assert_ne(moved[63 * WIDTH + 15], indices[63 * WIDTH + 15], "top-left corner moved")
	assert_ne(moved[71 * WIDTH + 23], indices[71 * WIDTH + 23], "bottom-right corner moved")
	assert_ne(moved[63 * WIDTH + 31], 0, "the ring is one cell to the right")


## The cursor is a bracket around the cell it is on, so moving it changes the
## page even when nothing has been typed.
func test_moving_the_cursor_redraws_the_page() -> void:
	var page := Gen2NamingScreenPage.from_data(GameData.open_directory(Fixture.directory()))
	var before: PackedByteArray = page.draw(_model(), "YOUR NAME?")
	_screen.handle_button(Gen2Button.RIGHT)
	assert_ne(page.draw(_model(), "YOUR NAME?"), before)
