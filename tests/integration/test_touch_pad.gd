extends GutTest

## The on-screen controller under real fingers.
##
## The pad is driven with the touch events a device sends rather than through
## its own helpers, so what is checked is the path a player takes.

const AREA := Vector2(480, 700)

var _pad: Gen2TouchPad = null
var _options: Gen2Options = null


func before_each() -> void:
	_options = Gen2Options.new()
	_options.touch_mode = Gen2Options.TOUCH_ALWAYS
	Gen2InputRuntime.instance().apply_options(_options)
	_pad = Gen2TouchPad.new()
	_pad.size = AREA
	add_child_autofree(_pad)


func after_each() -> void:
	if _pad != null and is_instance_valid(_pad):
		_pad.release_all()
	Gen2InputRuntime.instance().apply_options(Gen2Options.new())
	Gen2OptionsStore.use_test_path()


func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	_pad._input(event)


func _drag(index: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	_pad._input(event)


func _centre_of(button: int) -> Vector2:
	return (_pad.layout().button_rects(_pad.area())[button] as Rect2).get_center()


func _dpad(offset: Vector2) -> Vector2:
	var rect: Rect2 = _pad.layout().group_rect(Gen2TouchLayout.GROUP_PAD, _pad.area())
	return rect.get_center() + offset * rect.size * 0.45


## What the pad is holding, back in [Gen2Button] terms. The pad itself holds
## [InputMap] action names, because a mod's own on-screen button is one of the
## things a finger can be on and it is not one of the eight.
func _held() -> Dictionary:
	var out: Dictionary = {}
	for action: StringName in (_pad.get("_held") as Dictionary):
		var button: int = Gen2Button.from_action(action)
		if button != Gen2Button.NONE:
			out[button] = true
		else:
			out[action] = true
	return out


func test_the_pad_is_shown_when_the_setting_pins_it_on() -> void:
	assert_true(_pad.visible)
	assert_true(_pad.is_active())


## The whole point: a finger produces the same action a key does, so nothing
## downstream knows a touchscreen was involved.
func test_a_touch_on_the_dpad_presses_that_direction() -> void:
	_touch(0, _dpad(Vector2.LEFT), true)
	assert_true(_held().has(Gen2Button.LEFT))

	await get_tree().process_frame
	assert_true(Input.is_action_pressed(Gen2Button.action(Gen2Button.LEFT)))

	_touch(0, _dpad(Vector2.LEFT), false)
	await get_tree().process_frame
	assert_false(Input.is_action_pressed(Gen2Button.action(Gen2Button.LEFT)))


func test_lifting_a_finger_releases_only_that_button() -> void:
	_touch(0, _dpad(Vector2.UP), true)
	_touch(1, _centre_of(Gen2Button.A), true)
	assert_eq(_held().size(), 2)

	_touch(1, _centre_of(Gen2Button.A), false)
	assert_true(_held().has(Gen2Button.UP))
	assert_false(_held().has(Gen2Button.A))


## Rolling a thumb around the d-pad without lifting is how anyone turns a corner.
func test_sliding_across_the_dpad_swaps_the_direction() -> void:
	_touch(0, _dpad(Vector2.LEFT), true)
	_drag(0, _dpad(Vector2.RIGHT))

	assert_true(_held().has(Gen2Button.RIGHT))
	assert_false(_held().has(Gen2Button.LEFT))


## A thumb that drifts a few pixels past the edge mid-step should not stop the
## walk, so leaving the controller keeps the last button held.
func test_sliding_off_the_controller_keeps_the_button_held() -> void:
	_touch(0, _dpad(Vector2.DOWN), true)
	_drag(0, Vector2(-200, -200))
	assert_true(_held().has(Gen2Button.DOWN))


func test_a_touch_on_nothing_presses_nothing() -> void:
	_touch(0, Vector2(2, 2), true)
	assert_true(_held().is_empty())


func test_two_fingers_on_one_button_hold_it_until_both_lift() -> void:
	var at: Vector2 = _centre_of(Gen2Button.A)
	_touch(0, at, true)
	_touch(1, at, true)
	_touch(0, at, false)
	assert_true(_held().has(Gen2Button.A))

	_touch(1, at, false)
	assert_false(_held().has(Gen2Button.A))


## A button still held when the screen changes would walk the player into a wall
## for as long as the next screen was up.
func test_leaving_the_tree_lets_go_of_everything() -> void:
	_touch(0, _dpad(Vector2.UP), true)
	await get_tree().process_frame
	assert_true(Input.is_action_pressed(Gen2Button.action(Gen2Button.UP)))

	remove_child(_pad)
	await get_tree().process_frame
	assert_false(Input.is_action_pressed(Gen2Button.action(Gen2Button.UP)))
	add_child(_pad)


## A battle opened over the map brings its own controller. Only the one in front
## may draw or answer a finger, or one press would arrive twice.
func test_only_the_frontmost_controller_answers() -> void:
	var front := Gen2TouchPad.new()
	front.size = AREA
	add_child_autofree(front)

	assert_true(front.is_active())
	assert_false(_pad.is_active())
	assert_false(_pad.visible)

	_touch(0, _dpad(Vector2.UP), true)
	assert_true(_held().is_empty(), "the covered controller stays out of it")

	remove_child(front)
	assert_true(_pad.is_active())
	assert_true(_pad.visible)


func test_hiding_the_controller_lets_go_of_what_it_held() -> void:
	_touch(0, _dpad(Vector2.RIGHT), true)
	assert_false(_held().is_empty())

	var hidden := Gen2Options.new()
	hidden.touch_mode = Gen2Options.TOUCH_NEVER
	Gen2InputRuntime.instance().apply_options(hidden)

	assert_false(_pad.visible)
	assert_true(_held().is_empty())


## In edit mode the pad is a preview being arranged, so a drag moves a cluster
## and nothing is ever pressed.
func test_edit_mode_drags_a_group_instead_of_pressing_it() -> void:
	_pad.set_edit_mode(true)
	var before: Vector2 = _pad.layout().anchor(
		Gen2TouchLayout.ORIENTATION_PORTRAIT, Gen2TouchLayout.GROUP_PAD
	)

	_touch(0, _dpad(Vector2.ZERO), true)
	assert_true(_held().is_empty())
	_drag(0, _dpad(Vector2.ZERO) + Vector2(0, -120))
	_touch(0, _dpad(Vector2.ZERO), false)

	var after: Vector2 = _pad.layout().anchor(
		Gen2TouchLayout.ORIENTATION_PORTRAIT, Gen2TouchLayout.GROUP_PAD
	)
	assert_lt(after.y, before.y)
	assert_eq(after.x, before.x)
