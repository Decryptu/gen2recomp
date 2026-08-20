class_name Gen2BindingSheet
extends Gen2LauncherSheet

## What one button is bound to, and how to change it.
##
## A button carries several bindings at once, normally a key or two and a pad
## button, so this lists them rather than offering a single slot. The last one
## cannot be removed: a button with nothing bound is a button the player cannot
## press, and the options file would silently put the default back on the next
## load anyway.

signal bindings_changed()

var _options: Gen2Options = null
var _button: int = Gen2Button.NONE
## The [InputMap] name of a mod's action while this sheet is editing one, empty
## while it is editing one of the eight. A mod's bindings live in their own
## namespace, so which list is being edited is which of these is set.
var _action: StringName = &""
var _label: String = ""
var _list: VBoxContainer = null
var _prompt: Label = null
var _add: Gen2LauncherButton = null
var _capturing: bool = false
## The binding being held, and when it went down. A capture reads a press and
## acts on the release, which is what makes a hold mean something other than a
## binding.
var _pending: Dictionary = {}
var _pending_since: int = 0


## Named for the button rather than `create`, since the base sheet's own factory
## takes a title and a static method may not be replaced by a different one.
static func for_button(
	palette: Gen2LauncherTheme, options: Gen2Options, button: int
) -> Gen2BindingSheet:
	var sheet := Gen2BindingSheet.new()
	sheet._theme = palette
	sheet._options = options
	sheet._button = button
	sheet._label = Gen2Button.label(button)
	sheet._build(sheet._label)
	sheet._build_rows()
	return sheet


## The same sheet for a mod's own action. Its last binding may be removed, unlike
## one of the eight: a mod's control the player never wants is legitimately
## unbound, and nothing puts a default back for it.
static func for_mod_action(
	palette: Gen2LauncherTheme, options: Gen2Options, action: StringName, label: String
) -> Gen2BindingSheet:
	var sheet := Gen2BindingSheet.new()
	sheet._theme = palette
	sheet._options = options
	sheet._action = action
	sheet._label = label
	sheet._build(label)
	sheet._build_rows()
	return sheet


func _build_rows() -> void:
	_list = Gen2LauncherUI.column(Gen2LauncherUI.GAP_SM)
	body().add_child(_list)
	_prompt = Gen2LauncherUI.muted(_theme, "")
	body().add_child(_prompt)
	_add = Gen2LauncherButton.create(
		_theme, "Add a key or button", Gen2LauncherButton.Variant.PRIMARY, &"plus"
	)
	_add.pressed.connect(_start_capture)
	add_action(_add)
	_refresh()


## The stored array itself, not a copy: removing a binding edits the options in
## place, so a button with no entry yet is given one first.
func _bindings() -> Array:
	if _action != &"":
		var action_name: String = String(_action)
		if not _options.mod_controls.has(action_name):
			# Seeded from what the mod declared, so editing starts from what is
			# bound rather than from nothing.
			_options.mod_controls[action_name] = _registered_default()
		return _options.mod_controls[action_name]
	if not _options.controls.has(_button):
		_options.controls[_button] = []
	return _options.controls[_button]


## Whether the last binding is the one thing this row may not lose. One of the
## eight is a button the player could no longer press; a mod's action is not.
func _keeps_one() -> bool:
	return _action == &""


func _registered_default() -> Array:
	for action: Dictionary in Gen2ModHost.instance().actions():
		if StringName(action["name"]) == _action:
			return (action["default"] as Array).duplicate(true)
	return []


func _refresh() -> void:
	Gen2LauncherUI.clear(_list)
	var bindings: Array = _bindings()
	for index: int in bindings.size():
		var row: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
		var description: Label = Gen2LauncherUI.body(_theme, Gen2InputActions.describe(bindings[index]))
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(description)
		var remove: Gen2LauncherButton = Gen2LauncherButton.icon_only(
			_theme, &"trash", Gen2LauncherButton.Variant.DANGER, 36.0
		)
		remove.tooltip_text = "Remove"
		remove.set_disabled_state(_keeps_one() and bindings.size() <= 1)
		remove.pressed.connect(func() -> void: _remove(index))
		row.add_child(remove)
		_list.add_child(row)
	_add.set_disabled_state(bindings.size() >= Gen2InputActions.MAX_BINDINGS)


func _remove(index: int) -> void:
	var bindings: Array = _bindings()
	if index < 0 or index >= bindings.size() or (_keeps_one() and bindings.size() <= 1):
		return
	bindings.remove_at(index)
	_refresh()
	bindings_changed.emit()


## How long a key or pad button has to be held for the capture to cancel instead
## of binding. Long enough that a normal press cannot reach it, short enough to
## find by accident.
const HOLD_CANCEL_MSEC: int = 700


func _start_capture() -> void:
	_capturing = true
	_pending = {}
	_prompt.text = "Tap a key or a controller button. Hold one to cancel."
	_prompt.add_theme_color_override("font_color", _theme.accent)
	set_process(true)


## The hold cancels the moment it passes the threshold rather than on release,
## so a player who is holding one down sees the sheet close under their thumb
## instead of wondering how long is long enough.
func _process(_delta: float) -> void:
	if not _capturing or _pending.is_empty():
		return
	if Time.get_ticks_msec() - _pending_since < HOLD_CANCEL_MSEC:
		return
	_capturing = false
	_pending = {}
	set_process(false)
	close()


func _finish_capture(binding: Dictionary) -> void:
	_capturing = false
	_pending = {}
	set_process(false)
	_prompt.add_theme_color_override("font_color", _theme.muted)
	var bindings: Array = _bindings()
	if bindings.has(binding):
		_prompt.text = "%s is already on %s." % [
			Gen2InputActions.describe(binding), _label
		]
		return
	var taken: Array[int] = Gen2InputActions.conflicts(
		_options.controls, binding, _button
	)
	bindings.append(binding)
	if _action != &"":
		_options.mod_controls[String(_action)] = bindings
	else:
		_options.controls[_button] = bindings
	_prompt.text = ""
	if not taken.is_empty():
		var names: Array[String] = []
		for other: int in taken:
			names.append(Gen2Button.label(other))
		# Not refused: one key doing two things is the player's call, and a
		# refusal here would be the settings page overruling them.
		_prompt.text = "Also on %s." % ", ".join(names)
	_refresh()
	bindings_changed.emit()


## While capturing, every key and pad event belongs to the binding rather than to
## the sheet, so the parent's cancel is deliberately not reached. That used to
## leave a player on a pad alone with no way out but to bind something and then
## remove it, so a capture now reads the press and acts on the release: a tap
## binds, and holding past [constant HOLD_CANCEL_MSEC] closes the sheet instead.
## The mouse and a finger still work as they did.
func _unhandled_input(event: InputEvent) -> void:
	if not _capturing:
		super._unhandled_input(event)
		return
	if event is InputEventMouse or event is InputEventScreenTouch \
		or event is InputEventScreenDrag or event is InputEventAction:
		return
	if event.is_echo():
		return
	if _pending.is_empty():
		_begin_hold(event)
		return
	if _is_release_of_pending(event):
		accept_event()
		_finish_capture(_pending)


func _begin_hold(event: InputEvent) -> void:
	var binding: Dictionary = Gen2InputActions.from_event(event)
	if binding.is_empty() or not _is_pressed(event):
		return
	accept_event()
	_pending = binding
	_pending_since = Time.get_ticks_msec()


## A key or a pad button releases; a stick releases by falling back inside the
## deadzone, which is the same value [method Gen2InputActions.from_event] refuses
## to read as a binding at all.
func _is_release_of_pending(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		return StringName(_pending.get("kind", &"")) == Gen2InputActions.KIND_PAD_AXIS \
			and int(_pending.get("code", -1)) == int(motion.axis) \
			and absf(motion.axis_value) < Gen2InputActions.DEADZONE
	return not _is_pressed(event) and Gen2InputActions.from_event(event) == _pending


## `InputEventJoypadMotion` has no pressed state; every other event this reads
## does.
static func _is_pressed(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		return not Gen2InputActions.from_event(event).is_empty()
	return event.is_pressed()
