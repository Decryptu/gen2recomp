extends GutTest


func test_town_map_uses_source_region_bounds_and_cursor_order() -> void:
	var screen := Gen2TownMapScreen.new()
	screen.open(47)
	assert_true(screen.visible)
	assert_eq(screen.cursor_landmark(), 47)
	assert_eq(screen.cursor_name(), "PALLET TOWN")

	screen.handle_button(Gen2Button.UP)
	assert_eq(screen.cursor_landmark(), 48)
	screen.handle_button(Gen2Button.DOWN)
	assert_eq(screen.cursor_landmark(), 47)

	screen.handle_button(Gen2Button.DOWN)
	assert_eq(screen.cursor_landmark(), 47)
	for _step: int in 60:
		screen.handle_button(Gen2Button.UP)
	assert_eq(screen.cursor_landmark(), 94)
	screen.free()


func test_special_and_fast_ship_landmarks_open_on_johto() -> void:
	var special := Gen2TownMapScreen.new()
	special.open(Gen2WorldRadio.LANDMARK_SPECIAL)
	assert_eq(special.cursor_landmark(), Gen2TownMapScreen.JOHTO_START)

	var fast_ship := Gen2TownMapScreen.new()
	fast_ship.open(Gen2TownMapScreen.FAST_SHIP)
	assert_eq(fast_ship.cursor_landmark(), Gen2TownMapScreen.JOHTO_START)
	special.free()
	fast_ship.free()


func test_b_closes_the_map_without_leaving_it_visible() -> void:
	var screen := Gen2TownMapScreen.new()
	screen.open(1)
	screen.handle_button(Gen2Button.B)
	assert_false(screen.visible)
	screen.free()
