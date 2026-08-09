extends GutTest

## The live scheme and the active device, driven the way the game drives them.

var _runtime: Gen2InputRuntime = null


func before_each() -> void:
	_runtime = Gen2InputRuntime.instance()
	_runtime.apply_options(Gen2Options.new())


func after_each() -> void:
	for button: int in Gen2Button.ALL:
		_runtime.release(button)
	await get_tree().process_frame
	_runtime.apply_options(Gen2Options.new())
	Gen2OptionsStore.forget_cached()


## Two frames: one for the synthesised event to reach the input state, one for
## the runtime's own poll to see it.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_the_autoload_is_reachable_without_the_global_name() -> void:
	assert_not_null(_runtime, "a preview tool has to be able to find it")
	assert_same(_runtime, get_tree().root.get_node("/root/InputRuntime"))


## A synthesised press has to arrive both at the event handlers and at the polled
## state, or a screen would see the button and the walk would not.
func test_a_pressed_button_reaches_the_polled_input_state() -> void:
	_runtime.press(Gen2Button.A)
	await _settle()
	assert_true(Input.is_action_pressed(&"gen2_a"))

	_runtime.release(Gen2Button.A)
	await _settle()
	assert_false(Input.is_action_pressed(&"gen2_a"))


func test_pressing_nothing_is_harmless() -> void:
	_runtime.press(Gen2Button.NONE)
	await _settle()
	assert_eq(_runtime.held_direction(), Gen2Button.NONE)


## Turning a corner means pressing the next direction before releasing the last,
## so the newest held one wins and the walk turns rather than stalling.
func test_the_newest_held_direction_wins_and_the_older_one_survives_it() -> void:
	_runtime.press(Gen2Button.UP)
	await _settle()
	assert_eq(_runtime.held_direction(), Gen2Button.UP)

	_runtime.press(Gen2Button.LEFT)
	await _settle()
	assert_eq(_runtime.held_direction(), Gen2Button.LEFT)

	_runtime.release(Gen2Button.LEFT)
	await _settle()
	assert_eq(_runtime.held_direction(), Gen2Button.UP)

	_runtime.release(Gen2Button.UP)
	await _settle()
	assert_eq(_runtime.held_direction(), Gen2Button.NONE)


func test_the_active_device_follows_the_events() -> void:
	_runtime._input(InputEventKey.new())
	assert_eq(_runtime.device(), Gen2InputDevice.KEYBOARD)

	_runtime._input(InputEventJoypadButton.new())
	assert_eq(_runtime.device(), Gen2InputDevice.GAMEPAD)

	_runtime._input(InputEventScreenTouch.new())
	assert_eq(_runtime.device(), Gen2InputDevice.TOUCH)


## A knocked desk should not hide the interface a pad player is looking at.
func test_mouse_motion_alone_does_not_change_the_device() -> void:
	_runtime._input(InputEventJoypadButton.new())
	_runtime._input(InputEventMouseMotion.new())
	assert_eq(_runtime.device(), Gen2InputDevice.GAMEPAD)

	_runtime._input(InputEventMouseButton.new())
	assert_eq(_runtime.device(), Gen2InputDevice.MOUSE)


func test_automatic_shows_the_controller_only_while_a_finger_is_on_the_screen() -> void:
	var options := Gen2Options.new()
	options.touch_mode = Gen2Options.TOUCH_AUTO
	_runtime.apply_options(options)

	_runtime._input(InputEventKey.new())
	assert_false(_runtime.touch_controls_shown())

	_runtime._input(InputEventScreenTouch.new())
	assert_true(_runtime.touch_controls_shown())

	_runtime._input(InputEventJoypadButton.new())
	assert_false(_runtime.touch_controls_shown(), "a pad puts them away")


func test_the_pinned_modes_ignore_the_device() -> void:
	for pair: Array in [[Gen2Options.TOUCH_ALWAYS, true], [Gen2Options.TOUCH_NEVER, false]]:
		var options := Gen2Options.new()
		options.touch_mode = pair[0]
		_runtime.apply_options(options)
		for event: InputEvent in [
			InputEventKey.new(), InputEventScreenTouch.new(), InputEventJoypadButton.new(),
		]:
			_runtime._input(event)
			assert_eq(_runtime.touch_controls_shown(), pair[1], String(pair[0]))


func test_applying_a_scheme_installs_it_in_the_input_map() -> void:
	var options := Gen2Options.new()
	options.controls[Gen2Button.START] = [
		{"kind": Gen2InputActions.KIND_KEY, "code": KEY_F9},
	]
	_runtime.apply_options(options)

	var key := InputEventKey.new()
	key.physical_keycode = KEY_F9
	key.pressed = true
	assert_true(key.is_action_pressed(&"gen2_start"))
	assert_eq(_runtime.scheme(), options.controls)


func test_reveal_does_nothing_unless_the_controller_is_switched_off() -> void:
	var options := Gen2Options.new()
	options.touch_mode = Gen2Options.TOUCH_AUTO
	_runtime.apply_options(options)
	assert_false(_runtime.reveal_touch_controls(), "there is nothing to reveal")
