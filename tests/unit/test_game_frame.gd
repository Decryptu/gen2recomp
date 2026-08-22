extends GutTest

## How a game screen splits between the hardware screen and the controller.


func _screen(area: Vector2, controls: bool) -> Rect2:
	return Gen2GameFrame.split(area, controls)["screen"]


func _controls(area: Vector2, controls: bool) -> Rect2:
	return Gen2GameFrame.split(area, controls)["controls"]


## With nothing to place, both cases are the same and a desktop window is
## exactly what it was.
func test_without_a_controller_the_screen_takes_the_whole_frame() -> void:
	for area: Vector2 in [Vector2(1152, 648), Vector2(480, 960)]:
		assert_eq(_screen(area, false), Rect2(Vector2.ZERO, area))


## Landscape centres the screen and overlays the controller on the margins,
## which is where the thumbs already are.
func test_landscape_centres_the_screen_and_shares_the_frame() -> void:
	var area := Vector2(1152, 648)
	assert_eq(_screen(area, true), Rect2(Vector2.ZERO, area))
	assert_eq(_controls(area, true), Rect2(Vector2.ZERO, area))


func test_portrait_puts_the_screen_at_the_top_and_the_controller_under_it() -> void:
	var area := Vector2(480, 960)
	var screen: Rect2 = _screen(area, true)
	var controls: Rect2 = _controls(area, true)

	assert_eq(screen.position.y, 0.0, "top aligned")
	assert_eq(screen.get_center().x, area.x * 0.5, "centred across the width")
	assert_eq(controls.position.y, screen.end.y, "the controller starts where the screen ends")
	assert_eq(controls.end.y, area.y)
	assert_gt(controls.size.y, 0.0)


## A hardware pixel has to stay square, so the screen is always a whole number of
## them and never the height the split asked for.
func test_the_portrait_screen_is_a_whole_number_of_hardware_pixels() -> void:
	for height: int in [700, 800, 960, 1280]:
		var area := Vector2(480, height)
		var screen: Rect2 = _screen(area, true)
		var factor: float = screen.size.y / Gen2Screen.HEIGHT
		assert_eq(factor, floorf(factor), "%dpx tall" % height)
		assert_eq(screen.size.x, Gen2Screen.WIDTH * factor)


func test_the_portrait_screen_leaves_the_controller_its_share() -> void:
	var area := Vector2(480, 960)
	assert_lt(
		_screen(area, true).size.y,
		area.y * (1.0 - Gen2GameFrame.PORTRAIT_CONTROL_SHARE) + 1.0,
	)


## A window too small for one whole hardware pixel still draws one, rather than
## collapsing to nothing.
func test_a_tiny_frame_keeps_the_screen_at_one_to_one() -> void:
	var screen: Rect2 = _screen(Vector2(120, 300), true)
	assert_eq(screen.size, Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT))


## The split above is only reachable if the device is allowed to turn: Godot's
## default locks every handheld to landscape, and nothing else here sets it.
func test_a_handheld_may_turn_into_the_portrait_layout() -> void:
	assert_eq(
		int(ProjectSettings.get_setting("display/window/handheld/orientation")),
		DisplayServer.SCREEN_SENSOR,
	)


## SCREEN FILL: an expanded screen is given the whole portrait share instead of
## the 10:9 rectangle inside it, since the leftover is void it can draw map into.
func test_an_expanded_portrait_screen_takes_the_whole_share() -> void:
	var area := Vector2(480, 960)
	var framed: Rect2 = Gen2GameFrame.split(area, true)["screen"]
	var filled: Rect2 = Gen2GameFrame.split(area, true, true)["screen"]
	assert_eq(filled.position, Vector2.ZERO)
	assert_eq(filled.size.x, area.x)
	assert_gt(filled.size.y, framed.size.y)
	assert_eq(
		Gen2GameFrame.split(area, true, true)["controls"].position.y,
		filled.end.y,
		"the controller still starts where the screen ends",
	)


## Landscape and a screen with no controller are unchanged either way: the
## screen already had the whole frame and fills it itself.
func test_expanding_changes_nothing_where_the_screen_had_the_frame() -> void:
	for area: Vector2 in [Vector2(1152, 648), Vector2(480, 960)]:
		assert_eq(
			Gen2GameFrame.split(area, false, true)["screen"],
			Gen2GameFrame.split(area, false)["screen"],
		)


## The zoom ladder: whole pixels per hardware pixel on the way in, halves on the
## way out once one pixel each is reached, and never past the survey floor.
func test_the_zoom_ladder_steps_whole_pixels_then_halves() -> void:
	assert_eq(Gen2Screen.scale_at(4, 0), 4.0, "no step is the fitting scale")
	assert_eq(Gen2Screen.scale_at(4, 2), 6.0)
	assert_eq(Gen2Screen.scale_at(4, -3), 1.0, "one pixel each is the last whole step")
	assert_eq(Gen2Screen.scale_at(4, -4), 0.5)
	assert_eq(Gen2Screen.scale_at(4, -5), 0.25)
	assert_eq(Gen2Screen.scale_at(4, -9), Gen2Screen.MIN_SCALE, "the survey floor")


## The expanded buffer covers the window and grows by whole map blocks, so half
## the difference from the hardware screen is a whole tile and the interface
## rectangle inside it lands on the grid every screen is laid out against.
func test_the_expanded_buffer_covers_the_window_on_a_block_grid() -> void:
	for area: Vector2 in [Vector2(1152, 648), Vector2(1920, 1080), Vector2(430, 932)]:
		for scale: float in [1.0, 2.0, 4.0, 0.5]:
			var view: Vector2i = Gen2Screen.buffer_for(area, scale)
			assert_gte(float(view.x) * scale, area.x, "%s at %sx covers the width" % [area, scale])
			assert_gte(float(view.y) * scale, area.y, "%s at %sx covers the height" % [area, scale])
			assert_eq((view.x - Gen2Screen.WIDTH) % Gen2Screen.BUFFER_STEP, 0)
			assert_eq((view.y - Gen2Screen.HEIGHT) % Gen2Screen.BUFFER_STEP, 0)


## A window smaller than the hardware screen still gets the hardware screen:
## there is nothing to fill and a smaller buffer would crop the game.
func test_the_expanded_buffer_never_shrinks_below_the_hardware_screen() -> void:
	assert_eq(
		Gen2Screen.buffer_for(Vector2(100, 100), 4.0),
		Vector2i(Gen2Screen.WIDTH, Gen2Screen.HEIGHT),
	)
