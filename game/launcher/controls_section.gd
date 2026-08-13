class_name Gen2ControlsSection
extends VBoxContainer

## The controls card in the launcher's settings: what each of the eight buttons
## is bound to, and how the on-screen controller behaves.
##
## Every change is written straight to the options file and installed in the
## live [InputMap], the same as the rest of the settings page: there is no state
## here worth an apply button.

## Emitted after a change that the page has to write.
signal changed()
## Emitted when the layout editor should be opened, since a full-screen modal is
## the launcher's to place rather than a card's.
signal arrange_requested()

var _theme: Gen2LauncherTheme = null
var _options: Gen2Options = null
var _host: Control = null
var _rows: Dictionary = {}


static func create(
	palette: Gen2LauncherTheme, options: Gen2Options, host: Control
) -> Gen2ControlsSection:
	var section := Gen2ControlsSection.new()
	section._theme = palette
	section._options = options
	section._host = host
	section._build()
	return section


func _build() -> void:
	add_theme_constant_override("separation", Gen2LauncherUI.GAP_MD)
	add_child(Gen2LauncherUI.muted(
		_theme,
		"Keyboard, controller and the on-screen buttons all press the same eight."
	))
	for button: int in Gen2Button.ALL:
		add_child(_binding_row(button))
	_build_mod_actions()

	add_child(Gen2LauncherUI.field(_theme, "On-screen buttons", Gen2LauncherUI.segmented(
		_theme,
		["Automatic", "Always", "Never"],
		maxi(Gen2Options.TOUCH_MODES.find(_options.touch_mode), 0),
		func(index: int) -> void:
			_options.touch_mode = Gen2Options.TOUCH_MODES[index]
			changed.emit()
	)))
	add_child(Gen2LauncherUI.muted(
		_theme,
		"Automatic shows them while you are using the touchscreen. If you turn "
		+ "them off and need them back, tap the game screen three times quickly."
	))

	var actions: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
	add_child(actions)
	var arrange: Gen2LauncherButton = Gen2LauncherButton.create(
		_theme, "Arrange on-screen buttons", Gen2LauncherButton.Variant.NEUTRAL, &"settings"
	)
	arrange.pressed.connect(func() -> void: arrange_requested.emit())
	actions.add_child(arrange)
	actions.add_child(Gen2LauncherUI.spacer())
	var reset: Gen2LauncherButton = Gen2LauncherButton.create(
		_theme, "Reset controls", Gen2LauncherButton.Variant.QUIET
	)
	reset.pressed.connect(_reset)
	actions.add_child(reset)


## A loaded mod's own controls, in their own group under the eight. Absent
## entirely when no mod registered one, so a player with no mods sees the page
## they always saw.
func _build_mod_actions() -> void:
	var actions: Array = Gen2ModHost.instance().actions()
	if actions.is_empty():
		return
	add_child(Gen2LauncherUI.muted(
		_theme, "Mods add their own controls. These are bound the same way."
	))
	for action: Dictionary in actions:
		add_child(_mod_row(action))
	add_child(Gen2LauncherUI.field(_theme, "Mod buttons on screen", Gen2LauncherUI.segmented(
		_theme,
		["Off", "On"],
		1 if _options.touch_layout.mod_buttons_shown else 0,
		func(index: int) -> void:
			_options.touch_layout.mod_buttons_shown = index == 1
			changed.emit()
	)))
	add_child(Gen2LauncherUI.muted(
		_theme,
		"Off by default so a mod cannot cover the screen. Switch them on and "
		+ "arrange them beside A and B."
	))


func _mod_row(action: Dictionary) -> HBoxContainer:
	var name: StringName = action["name"]
	var value: Label = Gen2LauncherUI.body(_theme, "")
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var edit: Gen2LauncherButton = Gen2LauncherButton.create(
		_theme, "Change", Gen2LauncherButton.Variant.QUIET
	)
	edit.pressed.connect(func() -> void: _open_mod_editor(action))
	var row: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
	# Wider than the eight's column: a mod names a control in words rather than
	# with a letter, so "Raise the camera" has to fit beside them.
	var label: Label = Gen2LauncherUI.body(_theme, String(action["label"]))
	label.custom_minimum_size = Vector2(160, 0)
	row.add_child(label)
	row.add_child(value)
	row.add_child(edit)
	_rows[name] = value
	_refresh_mod_row(name)
	return row


func _refresh_mod_row(name: StringName) -> void:
	var label: Label = _rows.get(name)
	if label == null:
		return
	# What is actually bound, which is the mod's own default until the player
	# overrides it. Reading only the override would say "Unbound" for every mod
	# control nobody has touched.
	label.text = describe(_mod_bindings(name))
	label.add_theme_color_override("font_color", _theme.muted)


func _mod_bindings(name: StringName) -> Array:
	if _options.mod_controls.has(String(name)):
		return _options.mod_controls[String(name)]
	for action: Dictionary in Gen2ModHost.instance().actions():
		if StringName(action["name"]) == name:
			return action["default"]
	return []


func _open_mod_editor(action: Dictionary) -> void:
	var name: StringName = action["name"]
	var sheet: Gen2BindingSheet = Gen2BindingSheet.for_mod_action(
		_theme, _options, name, String(action["label"])
	)
	sheet.bindings_changed.connect(func() -> void:
		_refresh_mod_row(name)
		changed.emit()
	)
	sheet.open(_host)


func _binding_row(button: int) -> HBoxContainer:
	var value: Label = Gen2LauncherUI.body(_theme, "")
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var edit: Gen2LauncherButton = Gen2LauncherButton.create(
		_theme, "Change", Gen2LauncherButton.Variant.QUIET
	)
	edit.pressed.connect(func() -> void: _open_editor(button))
	var row: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
	row.add_child(_label_for(button))
	row.add_child(value)
	row.add_child(edit)
	_rows[button] = value
	_refresh_row(button)
	return row


func _label_for(button: int) -> Label:
	var label: Label = Gen2LauncherUI.body(_theme, Gen2Button.label(button))
	label.custom_minimum_size = Vector2(90, 0)
	return label


func _refresh_row(button: int) -> void:
	var label: Label = _rows.get(button)
	if label == null:
		return
	label.text = describe(_options.controls.get(button, []))
	label.add_theme_color_override("font_color", _theme.muted)


## What one button's bindings read as, keyboard first. Static so a test can
## check the wording without building a page.
static func describe(bindings: Array) -> String:
	var keys: Array[String] = []
	var pads: Array[String] = []
	for binding: Dictionary in bindings:
		var text: String = Gen2InputActions.describe(binding)
		if Gen2InputActions.device_of(binding) == Gen2InputActions.DEVICE_KEYBOARD:
			keys.append(text)
		else:
			pads.append(text)
	var parts: Array[String] = []
	if not keys.is_empty():
		parts.append(", ".join(keys))
	if not pads.is_empty():
		parts.append("Pad: %s" % ", ".join(pads))
	return "   ".join(parts) if not parts.is_empty() else "Unbound"


func _open_editor(button: int) -> void:
	var sheet: Gen2BindingSheet = Gen2BindingSheet.for_button(_theme, _options, button)
	sheet.bindings_changed.connect(func() -> void:
		_refresh_row(button)
		changed.emit()
	)
	sheet.open(_host)


func _reset() -> void:
	_options.controls = Gen2InputActions.defaults()
	# A mod's own bindings go back to what it declared, which is what an empty
	# override means: the install falls through to the registered default.
	_options.mod_controls = {}
	_options.touch_layout = Gen2TouchLayout.new()
	for button: int in Gen2Button.ALL:
		_refresh_row(button)
	for action: Dictionary in Gen2ModHost.instance().actions():
		_refresh_mod_row(action["name"])
	changed.emit()
