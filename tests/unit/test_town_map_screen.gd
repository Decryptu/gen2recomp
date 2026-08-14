extends GutTest

## The overlay around [Gen2TownMap] and [Gen2TownMapPage]: what a cache without
## the region map answers, and where the two objects land.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _screen: Gen2TownMapScreen = null


func before_each() -> void:
	_data = Fixture.build()
	_screen = Gen2TownMapScreen.new()
	add_child_autofree(_screen)


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func test_the_screen_opens_on_the_landmark_it_is_given() -> void:
	assert_true(_screen.open(_data, 1))
	assert_true(_screen.visible)
	assert_eq(_screen.cursor_landmark(), 1)
	assert_eq(_screen.cursor_name(), "NEW BARK TOWN")


func test_b_closes_the_map_without_leaving_it_visible() -> void:
	_screen.open(_data, 1)
	watch_signals(_screen)
	_screen.handle_button(Gen2Button.B)
	assert_false(_screen.visible)
	assert_signal_emitted(_screen, "closed")


func test_the_d_pad_walks_the_window_and_everything_else_is_swallowed() -> void:
	_screen.open(_data, 1)
	_screen.handle_button(Gen2Button.UP)
	assert_eq(_screen.cursor_landmark(), 2)
	assert_true(_screen.handle_button(Gen2Button.A))
	assert_eq(_screen.cursor_landmark(), 2)


## A cache with no region map answers false rather than drawing a screen of
## blanks, which is what keeps the Pokegear's card list open over it.
func test_a_cache_without_the_region_map_refuses_to_open() -> void:
	assert_false(_screen.open(null, 1))
	assert_false(_screen.visible)


## `data/maps/landmarks.asm`'s `db x + 8, y + 16` is undone at import, so a
## landmark's stored point is the centre of its 16x16 icon.
func test_the_screen_renders_both_objects_on_their_landmarks() -> void:
	_screen.open(_data, 1)
	_screen.handle_button(Gen2Button.UP)
	var image: Image = _screen.render()
	assert_eq(image.get_width(), Gen2Screen.WIDTH)
	assert_eq(image.get_height(), Gen2Screen.HEIGHT)
	assert_eq(_screen.map().player_landmark, 1)
	assert_eq(_screen.map().cursor, 2)
