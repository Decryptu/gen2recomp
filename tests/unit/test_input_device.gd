extends GutTest

## Which device an event says the player is using.


func test_each_event_kind_names_its_device() -> void:
	assert_eq(Gen2InputDevice.kind_of(InputEventKey.new()), Gen2InputDevice.KEYBOARD)
	assert_eq(Gen2InputDevice.kind_of(InputEventJoypadButton.new()), Gen2InputDevice.GAMEPAD)
	assert_eq(Gen2InputDevice.kind_of(InputEventJoypadMotion.new()), Gen2InputDevice.GAMEPAD)
	assert_eq(Gen2InputDevice.kind_of(InputEventScreenTouch.new()), Gen2InputDevice.TOUCH)
	assert_eq(Gen2InputDevice.kind_of(InputEventScreenDrag.new()), Gen2InputDevice.TOUCH)
	assert_eq(Gen2InputDevice.kind_of(InputEventMouseButton.new()), Gen2InputDevice.MOUSE)


func test_an_event_that_names_no_device_answers_nothing() -> void:
	assert_eq(Gen2InputDevice.kind_of(InputEventAction.new()), &"")


## `emulate_mouse_from_touch` is on by default, which is what makes the launcher
## work under a finger. Without this the answer would flip back to mouse on every
## tap and the on-screen controller would vanish mid-press.
func test_a_mouse_event_emulated_from_a_touch_reads_as_touch() -> void:
	var click := InputEventMouseButton.new()
	click.device = InputEvent.DEVICE_ID_EMULATION
	assert_eq(Gen2InputDevice.kind_of(click), Gen2InputDevice.TOUCH)


func test_pointers_are_the_kinds_that_need_no_focus_ring() -> void:
	assert_true(Gen2InputDevice.is_pointer(Gen2InputDevice.MOUSE))
	assert_true(Gen2InputDevice.is_pointer(Gen2InputDevice.TOUCH))
	assert_false(Gen2InputDevice.is_pointer(Gen2InputDevice.KEYBOARD))
	assert_false(Gen2InputDevice.is_pointer(Gen2InputDevice.GAMEPAD))


func test_every_kind_is_named() -> void:
	for kind: StringName in Gen2InputDevice.KINDS:
		assert_false(Gen2InputDevice.label(kind).is_empty(), String(kind))
	assert_eq(Gen2InputDevice.label(&"nothing"), "")
