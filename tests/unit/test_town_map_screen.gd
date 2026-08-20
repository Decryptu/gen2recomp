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
## blanks, which is what leaves the Pokegear's own card standing.
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



## `Pokedex_GetArea`'s own loop: A leaves as well as B, and the region walk is
## left and right rather than the cursor's up and down.
func test_the_dex_area_opens_on_johto_and_leaves_on_a() -> void:
	assert_true(_screen.open_dex_area(_data, Fixture.TRAINER_SPECIES, [[1], [47]], 1, true))
	assert_eq(_screen.map().region(), Gen2TownMap.REGION_JOHTO)
	assert_eq(_screen.current_nests(), [1])
	_screen.handle_button(Gen2Button.RIGHT)
	assert_eq(_screen.current_nests(), [47])
	watch_signals(_screen)
	_screen.handle_button(Gen2Button.A)
	assert_signal_emitted(_screen, "closed")


## `.BlinkNestIcons` reads `hVBlankCounter`, so the set is only written on every
## sixteenth frame and holds whatever it was in between.
func test_the_nest_icons_blink_every_sixteen_frames() -> void:
	_screen.open_dex_area(_data, Fixture.TRAINER_SPECIES, [[1], []], 1)
	var lit: Color = _nest_pixel()
	_advance(Gen2TownMapScreen.NEST_BLINK_FRAMES)
	assert_eq(_screen.shadow_oam(), Gen2TownMapScreen.OAM_NESTS)
	assert_eq(_nest_pixel(), lit)
	_advance(Gen2TownMapScreen.NEST_BLINK_FRAMES)
	assert_eq(_screen.shadow_oam(), Gen2TownMapScreen.OAM_CLEARED)
	assert_ne(_nest_pixel(), lit, "the icon is off its landmark")
	_advance(Gen2TownMapScreen.NEST_BLINK_FRAMES)
	assert_eq(_nest_pixel(), lit)


## `.HideNestsShowPlayer` runs instead of the blink while SELECT is down, and
## `.CheckPlayerLocation` empties OAM when the player is in the other region.
func test_select_replaces_the_nests_with_the_player_icon() -> void:
	_screen.open_dex_area(_data, Fixture.TRAINER_SPECIES, [[1], []], 1, true)
	var lit: Color = _nest_pixel()
	_screen.handle_button(Gen2Button.SELECT)
	assert_eq(_screen.shadow_oam(), Gen2TownMapScreen.OAM_PLAYER)
	assert_ne(_nest_pixel(), lit, "the nests went with it")

	_screen.handle_button(Gen2Button.RIGHT)
	_screen.advance_frame()
	assert_eq(_screen.shadow_oam(), Gen2TownMapScreen.OAM_CLEARED, "the player is in Johto")

	_screen.release_button(Gen2Button.SELECT)
	_screen.handle_button(Gen2Button.LEFT)
	assert_eq(_screen.shadow_oam(), Gen2TownMapScreen.OAM_NESTS)
	assert_eq(_nest_pixel(), lit)


func _advance(frames: int) -> void:
	for _frame: int in frames:
		_screen.advance_frame()


## The middle of the nest icon landmark 1 takes, which is its own point less
## four: the fixture's icon is one inked tile, so the pixel is the icon or it is
## the map underneath.
func _nest_pixel() -> Color:
	return _screen.render().get_pixel(Fixture.NEST_ICON_PIXEL.x, Fixture.NEST_ICON_PIXEL.y)
