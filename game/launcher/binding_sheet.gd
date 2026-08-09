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
var _list: VBoxContainer = null
var _prompt: Label = null
var _add: Gen2LauncherButton = null
var _capturing: bool = false


## Named for the button rather than `create`, since the base sheet's own factory
## takes a title and a static method may not be replaced by a different one.
static func for_button(
	palette: Gen2LauncherTheme, options: Gen2Options, button: int
) -> Gen2BindingSheet:
	var sheet := Gen2BindingSheet.new()
	sheet._theme = palette
	sheet._options = options
	sheet._button = button
	sheet._build(Gen2Button.label(button))
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
	if not _options.controls.has(_button):
		_options.controls[_button] = []
	return _options.controls[_button]


func _refresh() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var bindings: Array = _bindings()
	for index: int in bindings.size():
		var row: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
		var name: Label = Gen2LauncherUI.body(_theme, Gen2InputActions.describe(bindings[index]))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var remove: Gen2LauncherButton = Gen2LauncherButton.icon_only(
			_theme, &"trash", Gen2LauncherButton.Variant.DANGER, 36.0
		)
		remove.tooltip_text = "Remove"
		remove.set_disabled_state(bindings.size() <= 1)
		remove.pressed.connect(func() -> void: _remove(index))
		row.add_child(remove)
		_list.add_child(row)
	_add.set_disabled_state(bindings.size() >= Gen2InputActions.MAX_BINDINGS)


func _remove(index: int) -> void:
	var bindings: Array = _bindings()
	if index < 0 or index >= bindings.size() or bindings.size() <= 1:
		return
	bindings.remove_at(index)
	_refresh()
	bindings_changed.emit()


func _start_capture() -> void:
	_capturing = true
	_prompt.text = "Press a key or a controller button. Close this to cancel."
	_prompt.add_theme_color_override("font_color", _theme.accent)


func _finish_capture(binding: Dictionary) -> void:
	_capturing = false
	_prompt.add_theme_color_override("font_color", _theme.muted)
	var bindings: Array = _bindings()
	if bindings.has(binding):
		_prompt.text = "%s is already on %s." % [
			Gen2InputActions.describe(binding), Gen2Button.label(_button)
		]
		return
	var taken: Array[int] = Gen2InputActions.conflicts(_options.controls, binding, _button)
	bindings.append(binding)
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


## While capturing, every key and pad event is the binding rather than a control
## of the sheet, so the parent's cancel is deliberately not reached. The mouse
## and a finger still work, which is what closes the sheet without binding.
func _unhandled_input(event: InputEvent) -> void:
	if not _capturing:
		super._unhandled_input(event)
		return
	if event is InputEventMouse or event is InputEventScreenTouch \
		or event is InputEventScreenDrag or event is InputEventAction:
		return
	if not event.is_pressed() or event.is_echo():
		return
	var binding: Dictionary = Gen2InputActions.from_event(event)
	if binding.is_empty():
		return
	accept_event()
	_finish_capture(binding)
