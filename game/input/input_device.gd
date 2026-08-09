class_name Gen2InputDevice
extends RefCounted

## Which kind of device an event came from.
##
## The engine reports what happened, never what the player is holding, and the
## two questions have different answers: a phone with a pad plugged in has a
## touchscreen it is not using, and a laptop with a touchscreen has one the
## player touches once an hour. Only the device actually in use should decide
## whether on-screen controls are drawn or a focus ring is shown, so
## [InputRuntime] keeps the last answer this gives and publishes it.

const KEYBOARD: StringName = &"keyboard"
const MOUSE: StringName = &"mouse"
const TOUCH: StringName = &"touch"
const GAMEPAD: StringName = &"gamepad"
const KINDS: Array[StringName] = [KEYBOARD, MOUSE, TOUCH, GAMEPAD]

const LABELS: Dictionary = {
	KEYBOARD: "Keyboard",
	MOUSE: "Mouse",
	TOUCH: "Touchscreen",
	GAMEPAD: "Controller",
}


## The device kind an event came from, or an empty name for an event that says
## nothing about one.
##
## Mouse events emulated from a touch carry [constant
## InputEvent.DEVICE_ID_EMULATION] and are reported as touch. Without that,
## `emulate_mouse_from_touch` (on by default, and what makes the launcher work
## under a finger) would flip the answer back to mouse on every tap.
static func kind_of(event: InputEvent) -> StringName:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return TOUCH
	if event is InputEventKey:
		return KEYBOARD
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return GAMEPAD
	if event is InputEventMouse:
		return TOUCH if event.device == InputEvent.DEVICE_ID_EMULATION else MOUSE
	return &""


static func label(kind: StringName) -> String:
	return LABELS.get(kind, "")


## Whether a kind drives the interface by pointing at it. These are the two that
## need no focus ring in the launcher, and the two an on-screen d-pad would be
## in the way of everywhere else.
static func is_pointer(kind: StringName) -> bool:
	return kind == MOUSE or kind == TOUCH
