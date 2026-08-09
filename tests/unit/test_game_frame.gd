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
