extends Node

## The live control scheme, and which device the player is actually using.
##
## Two things need one owner. Bindings, because the [InputMap] is engine state
## with no memory of where it came from, so something has to hold the scheme the
## options file describes and put it back after every rebind. And the active
## device, because "is a controller plugged in" is not the question any screen
## asks: what decides whether an on-screen d-pad is drawn is whether the player
## is touching the screen right now.
##
## Screens read this; only the settings page writes to it.

signal device_changed(kind: StringName)
## The effective answer, after both the setting and the active device. A screen
## that draws the controller listens for this rather than polling.
signal touch_controls_changed(shown: bool)
## A rebind landed. What is bound has already been installed in the [InputMap]
## by the time this arrives; a screen only needs it to redraw a legend.
signal scheme_changed()

var _scheme: Dictionary = {}
var _touch_mode: StringName = Gen2Options.TOUCH_AUTO
var _layout: Gen2TouchLayout = Gen2TouchLayout.new()
var _device: StringName = Gen2InputDevice.KEYBOARD
var _touch_shown: bool = false
## Held directions in the order they were pressed, so the newest wins. Two
## directions at once is normal play, not an error: a player turning a corner
## presses the next one before releasing the last.
var _direction_order: Array[int] = []


func _ready() -> void:
	# Before any event has arrived the only evidence is the hardware. A phone
	# should show its controller on the first frame rather than after the first
	# tap, and a desktop should not show one at all.
	_device = Gen2InputDevice.TOUCH if DisplayServer.is_touchscreen_available() \
		else Gen2InputDevice.KEYBOARD
	apply_options(Gen2OptionsStore.current())


## Installs an options object's control scheme and touch settings. The settings
## page calls this after every change; nothing else needs to.
func apply_options(options: Gen2Options) -> void:
	if options == null:
		return
	_scheme = options.controls
	_touch_mode = options.touch_mode
	_layout = options.touch_layout
	Gen2InputActions.install(_scheme)
	scheme_changed.emit()
	_refresh_touch_controls()


func scheme() -> Dictionary:
	return _scheme


func touch_layout() -> Gen2TouchLayout:
	return _layout


func touch_mode() -> StringName:
	return _touch_mode


func device() -> StringName:
	return _device


## Whether the on-screen controller should be drawn right now.
func touch_controls_shown() -> bool:
	return _touch_shown


## Turns the on-screen controller back on and writes it to the options file.
##
## The escape from [constant Gen2Options.TOUCH_NEVER], which is the one setting
## that can leave a touch-only player with nothing to press. It restores `auto`
## rather than `always`, so a pad the player picks up again still hides it.
func reveal_touch_controls() -> bool:
	if _touch_mode != Gen2Options.TOUCH_NEVER:
		return false
	var options: Gen2Options = Gen2OptionsStore.current()
	options.touch_mode = Gen2Options.TOUCH_AUTO
	Gen2OptionsStore.save(options)
	_touch_mode = Gen2Options.TOUCH_AUTO
	# The gesture is a touch, so the device is a touchscreen whatever was last
	# used. Saying so is what makes `auto` resolve to shown on this same frame.
	_set_device(Gen2InputDevice.TOUCH)
	_refresh_touch_controls()
	return true


## Presses a button from something that is not a device: the on-screen
## controller, a preview, or a test.
##
## Sent as an [InputEventAction] through [method Input.parse_input_event] rather
## than delivered to a screen directly, so it takes the same path a key does and
## arrives at both the event handlers and [method Input.is_action_pressed].
func press(button: int) -> void:
	_send(button, true)


func release(button: int) -> void:
	_send(button, false)


func _send(button: int, pressed: bool) -> void:
	var action: StringName = Gen2Button.action(button)
	if action.is_empty():
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


## The direction currently held, most recently pressed first, or [constant
## Gen2Button.NONE]. Polled rather than read off events, because walking
## continues while a direction is held and the operating system's key repeat is
## not the rate the hardware walked at.
func held_direction() -> int:
	return _direction_order.back() if not _direction_order.is_empty() else Gen2Button.NONE


func _process(_delta: float) -> void:
	for button: int in Gen2Button.DIRECTIONS:
		var held: bool = Gen2Button.held(button)
		var at: int = _direction_order.find(button)
		if held and at < 0:
			_direction_order.append(button)
		elif not held and at >= 0:
			_direction_order.remove_at(at)


## Watches every event and consumes none. Device recon has to see input the
## screens never get, including the mouse motion that says the player has put
## the pad down.
func _input(event: InputEvent) -> void:
	var kind: StringName = Gen2InputDevice.kind_of(event)
	if kind.is_empty():
		return
	# Mouse motion alone is not evidence: a desk knocked while the player holds
	# a pad would hide the interface they are looking at. A click is.
	if kind == Gen2InputDevice.MOUSE and event is InputEventMouseMotion:
		return
	_set_device(kind)


func _set_device(kind: StringName) -> void:
	if kind == _device:
		return
	_device = kind
	device_changed.emit(kind)
	_refresh_touch_controls()


func _refresh_touch_controls() -> void:
	var shown: bool = false
	match _touch_mode:
		Gen2Options.TOUCH_ALWAYS:
			shown = true
		Gen2Options.TOUCH_NEVER:
			shown = false
		_:
			shown = _device == Gen2InputDevice.TOUCH
	if shown == _touch_shown:
		return
	_touch_shown = shown
	touch_controls_changed.emit(shown)
