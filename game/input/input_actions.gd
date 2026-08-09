class_name Gen2InputActions
extends RefCounted

## What a device has to do to produce a [Gen2Button], as data.
##
## A binding is a plain dictionary so the whole control scheme survives a trip
## through the options file, and so the remap UI can describe one without
## holding an [InputEvent]. Three kinds cover every device the engine reports:
##
## [codeblock]
## {"kind": "key",        "code": <physical keycode>}
## {"kind": "pad_button", "code": <JoyButton>}
## {"kind": "pad_axis",   "code": <JoyAxis>, "sign": -1 or 1}
## [/codeblock]
##
## Keys bind by physical keycode, so the d-pad keeps the WASD positions on a
## layout that does not spell WASD there. [method describe] asks the platform
## what the key in that position is actually labelled.
##
## Nothing here reads or writes the options file: [Gen2OptionsStore] owns that,
## and the runtime hands the result to [method install].

const KIND_KEY: StringName = &"key"
const KIND_PAD_BUTTON: StringName = &"pad_button"
const KIND_PAD_AXIS: StringName = &"pad_axis"
const KINDS: Array[StringName] = [KIND_KEY, KIND_PAD_BUTTON, KIND_PAD_AXIS]

const DEVICE_KEYBOARD: StringName = &"keyboard"
const DEVICE_GAMEPAD: StringName = &"gamepad"

## Past this much of its travel a stick counts as pressed. Godot applies it per
## action, so it is set here rather than left at the 0.2 default, which walks
## the player on a worn stick sitting still.
const DEADZONE: float = 0.5

## An [InputMap] event with this device matches every device, which is what a
## pad binding wants: the player should not have to rebind because they plugged
## the controller into the other port.
const ALL_DEVICES: int = -1

## How many bindings one button may carry. The remap UI shows a fixed number of
## slots, and an options file claiming hundreds is a file to clamp, not to obey.
const MAX_BINDINGS: int = 6

const DEFAULTS: Dictionary = {
	Gen2Button.UP: [
		{"kind": KIND_KEY, "code": KEY_UP},
		{"kind": KIND_KEY, "code": KEY_W},
		{"kind": KIND_PAD_BUTTON, "code": JOY_BUTTON_DPAD_UP},
		{"kind": KIND_PAD_AXIS, "code": JOY_AXIS_LEFT_Y, "sign": -1},
	],
	Gen2Button.DOWN: [
		{"kind": KIND_KEY, "code": KEY_DOWN},
		{"kind": KIND_KEY, "code": KEY_S},
		{"kind": KIND_PAD_BUTTON, "code": JOY_BUTTON_DPAD_DOWN},
		{"kind": KIND_PAD_AXIS, "code": JOY_AXIS_LEFT_Y, "sign": 1},
	],
	Gen2Button.LEFT: [
		{"kind": KIND_KEY, "code": KEY_LEFT},
		{"kind": KIND_KEY, "code": KEY_A},
		{"kind": KIND_PAD_BUTTON, "code": JOY_BUTTON_DPAD_LEFT},
		{"kind": KIND_PAD_AXIS, "code": JOY_AXIS_LEFT_X, "sign": -1},
	],
	Gen2Button.RIGHT: [
		{"kind": KIND_KEY, "code": KEY_RIGHT},
		{"kind": KIND_KEY, "code": KEY_D},
		{"kind": KIND_PAD_BUTTON, "code": JOY_BUTTON_DPAD_RIGHT},
		{"kind": KIND_PAD_AXIS, "code": JOY_AXIS_LEFT_X, "sign": 1},
	],
	Gen2Button.A: [
		{"kind": KIND_KEY, "code": KEY_Z},
		{"kind": KIND_KEY, "code": KEY_SPACE},
		{"kind": KIND_PAD_BUTTON, "code": JOY_BUTTON_A},
	],
	Gen2Button.B: [
		{"kind": KIND_KEY, "code": KEY_X},
		{"kind": KIND_KEY, "code": KEY_ESCAPE},
		{"kind": KIND_PAD_BUTTON, "code": JOY_BUTTON_B},
	],
	Gen2Button.START: [
		{"kind": KIND_KEY, "code": KEY_ENTER},
		{"kind": KIND_KEY, "code": KEY_KP_ENTER},
		{"kind": KIND_PAD_BUTTON, "code": JOY_BUTTON_START},
	],
	Gen2Button.SELECT: [
		{"kind": KIND_KEY, "code": KEY_BACKSPACE},
		{"kind": KIND_KEY, "code": KEY_TAB},
		{"kind": KIND_PAD_BUTTON, "code": JOY_BUTTON_BACK},
	],
}

## Godot names no joypad button, and the numbers are meaningless to a player.
## `core/input/input_enums.h` order, under the SDL layout every mapped pad is
## translated into, so these are the positions rather than the printed letters.
const PAD_BUTTON_NAMES: Dictionary = {
	JOY_BUTTON_A: "A (bottom)",
	JOY_BUTTON_B: "B (right)",
	JOY_BUTTON_X: "X (left)",
	JOY_BUTTON_Y: "Y (top)",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "Left stick press",
	JOY_BUTTON_RIGHT_STICK: "Right stick press",
	JOY_BUTTON_LEFT_SHOULDER: "L",
	JOY_BUTTON_RIGHT_SHOULDER: "R",
	JOY_BUTTON_DPAD_UP: "D-pad up",
	JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left",
	JOY_BUTTON_DPAD_RIGHT: "D-pad right",
	JOY_BUTTON_MISC1: "Share",
	JOY_BUTTON_PADDLE1: "Paddle 1",
	JOY_BUTTON_PADDLE2: "Paddle 2",
	JOY_BUTTON_PADDLE3: "Paddle 3",
	JOY_BUTTON_PADDLE4: "Paddle 4",
	JOY_BUTTON_TOUCHPAD: "Touchpad",
}

## Axis name by sign, negative first.
const PAD_AXIS_NAMES: Dictionary = {
	JOY_AXIS_LEFT_X: ["Left stick left", "Left stick right"],
	JOY_AXIS_LEFT_Y: ["Left stick up", "Left stick down"],
	JOY_AXIS_RIGHT_X: ["Right stick left", "Right stick right"],
	JOY_AXIS_RIGHT_Y: ["Right stick up", "Right stick down"],
	JOY_AXIS_TRIGGER_LEFT: ["L2", "L2"],
	JOY_AXIS_TRIGGER_RIGHT: ["R2", "R2"],
}


## The stock scheme, as a fresh copy the caller may edit.
static func defaults() -> Dictionary:
	var scheme: Dictionary = {}
	for button: int in Gen2Button.ALL:
		var bindings: Array = []
		for binding: Dictionary in DEFAULTS[button]:
			bindings.append(binding.duplicate())
		scheme[button] = bindings
	return scheme


## Replaces every `gen2_*` action in the [InputMap] with these bindings.
##
## Rebuilt rather than merged: a rebind that only added would leave the previous
## key working, and the player would have two keys where the screen says one.
static func install(scheme: Dictionary) -> void:
	for button: int in Gen2Button.ALL:
		var name: StringName = Gen2Button.action(button)
		if not InputMap.has_action(name):
			InputMap.add_action(name, DEADZONE)
		else:
			InputMap.action_set_deadzone(name, DEADZONE)
			InputMap.action_erase_events(name)
		for binding: Dictionary in scheme.get(button, []):
			var event: InputEvent = to_event(binding)
			if event != null:
				InputMap.action_add_event(name, event)


## Builds the [InputEvent] an [InputMap] entry needs, or null for a binding this
## build does not recognise.
static func to_event(binding: Dictionary) -> InputEvent:
	var code: int = int(binding.get("code", 0))
	match StringName(binding.get("kind", &"")):
		KIND_KEY:
			var key := InputEventKey.new()
			# Physical only. A binding that also carried a keycode would match
			# twice on a US layout and disagree with itself on any other.
			key.physical_keycode = code
			return key
		KIND_PAD_BUTTON:
			var pad := InputEventJoypadButton.new()
			pad.button_index = code
			pad.device = ALL_DEVICES
			return pad
		KIND_PAD_AXIS:
			var axis := InputEventJoypadMotion.new()
			axis.axis = code
			axis.axis_value = signf(float(binding.get("sign", 1)))
			axis.device = ALL_DEVICES
			return axis
	return null


## The binding an event stands for, or an empty dictionary if it is not one a
## player could have meant. This is what the remap UI captures with: it listens
## for anything and keeps whatever answers here.
static func from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key: InputEventKey = event
		var code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code == 0:
			return {}
		return {"kind": KIND_KEY, "code": code}
	if event is InputEventJoypadButton:
		return {"kind": KIND_PAD_BUTTON, "code": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		# A stick resting near zero reports motion constantly. Only a real push
		# past the same deadzone the action uses is a binding.
		if absf(motion.axis_value) < DEADZONE:
			return {}
		return {
			"kind": KIND_PAD_AXIS,
			"code": int(motion.axis),
			"sign": -1 if motion.axis_value < 0.0 else 1,
		}
	return {}


## The key actually printed where this physical one sits, as a keycode.
## `keyboard_get_label_from_physical` returns a key rather than a string, and
## refuses on a display server with no keyboard, which is every headless run.
static func _labelled_key(code: int) -> int:
	if DisplayServer.get_name() == "headless":
		return code
	var labelled: int = DisplayServer.keyboard_get_label_from_physical(code)
	return labelled if labelled != 0 else code


static func device_of(binding: Dictionary) -> StringName:
	return DEVICE_KEYBOARD if StringName(binding.get("kind", &"")) == KIND_KEY \
		else DEVICE_GAMEPAD


## What to print for a binding. Keys ask the platform for the label actually
## printed on the key in that physical position, so a French player rebinding
## the d-pad reads ZQSD rather than the WASD the binding is stored as.
static func describe(binding: Dictionary) -> String:
	var code: int = int(binding.get("code", 0))
	match StringName(binding.get("kind", &"")):
		KIND_KEY:
			return OS.get_keycode_string(_labelled_key(code))
		KIND_PAD_BUTTON:
			return PAD_BUTTON_NAMES.get(code, "Pad button %d" % code)
		KIND_PAD_AXIS:
			var names: Array = PAD_AXIS_NAMES.get(code, [])
			if names.is_empty():
				return "Pad axis %d%s" % [code, "-" if int(binding.get("sign", 1)) < 0 else "+"]
			return String(names[0 if int(binding.get("sign", 1)) < 0 else 1])
	return "Unbound"


## Reads a scheme back out of the options file.
##
## Clamped rather than refused, the way the rest of [Gen2Options] is: one
## unreadable binding should cost that binding, and a button left with none at
## all falls back to its default rather than becoming unpressable.
static func sanitize(raw: Variant) -> Dictionary:
	var scheme: Dictionary = defaults()
	if raw is not Dictionary:
		return scheme
	var stored: Dictionary = raw
	for button: int in Gen2Button.ALL:
		# JSON has no integer keys, so a scheme that has been through the
		# options file is keyed by the action name rather than the button.
		var entry: Variant = stored.get(String(Gen2Button.action(button)))
		if entry is not Array:
			continue
		var bindings: Array = []
		for row: Variant in entry:
			if row is not Dictionary:
				continue
			var binding: Dictionary = _sanitize_binding(row)
			if not binding.is_empty() and not bindings.has(binding):
				bindings.append(binding)
			if bindings.size() >= MAX_BINDINGS:
				break
		# An empty list is a button the player can no longer press. Every other
		# option clamps to something usable, and so does this.
		if not bindings.is_empty():
			scheme[button] = bindings
	return scheme


static func _sanitize_binding(row: Dictionary) -> Dictionary:
	var kind := StringName(String(row.get("kind", "")))
	if not KINDS.has(kind):
		return {}
	var code: int = int(row.get("code", 0))
	match kind:
		KIND_KEY:
			if code <= 0:
				return {}
			return {"kind": kind, "code": code}
		KIND_PAD_BUTTON:
			if code < 0 or code >= JOY_BUTTON_MAX:
				return {}
			return {"kind": kind, "code": code}
		KIND_PAD_AXIS:
			if code < 0 or code >= JOY_AXIS_MAX:
				return {}
			return {"kind": kind, "code": code, "sign": -1 if int(row.get("sign", 1)) < 0 else 1}
	return {}


## The scheme as the options file stores it: keyed by action name, because JSON
## has no integer keys and a round trip would otherwise turn one into a string.
static func to_dict(scheme: Dictionary) -> Dictionary:
	var row: Dictionary = {}
	for button: int in Gen2Button.ALL:
		var bindings: Array = []
		for binding: Dictionary in scheme.get(button, []):
			bindings.append(binding.duplicate())
		row[String(Gen2Button.action(button))] = bindings
	return row


## Whether a scheme is the stock one, which is what lets the settings page offer
## a reset only when there is something to reset.
static func is_default(scheme: Dictionary) -> bool:
	return to_dict(scheme) == to_dict(defaults())


## Every button already bound to this, other than [param excluding]. A rebind
## uses it to say what it would take away; nothing here refuses a duplicate,
## since one key doing two things is the player's call to make.
static func conflicts(scheme: Dictionary, binding: Dictionary, excluding: int) -> Array[int]:
	var found: Array[int] = []
	for button: int in Gen2Button.ALL:
		if button == excluding:
			continue
		for existing: Dictionary in scheme.get(button, []):
			if existing == binding:
				found.append(button)
				break
	return found
