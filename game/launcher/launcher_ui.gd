class_name Gen2LauncherUI
extends RefCounted

## Small shared pieces every launcher page builds from: text, rows, and the two
## composite controls (segmented choice and slider) that replace Godot's own.

const GAP_XS: int = 4
const GAP_SM: int = 8
const GAP_MD: int = 14
const GAP_LG: int = 22


static func title(theme: Gen2LauncherTheme, text: String, size: int = Gen2LauncherTheme.FONT_TITLE) -> Label:
	return _label(text, size, theme.text)


static func body(theme: Gen2LauncherTheme, text: String) -> Label:
	return _label(text, Gen2LauncherTheme.FONT_BODY, theme.text)


static func muted(theme: Gen2LauncherTheme, text: String) -> Label:
	var label: Label = _label(text, Gen2LauncherTheme.FONT_SMALL, theme.muted)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## A section marker: small, spaced capitals in the faint colour.
static func caption(theme: Gen2LauncherTheme, text: String) -> Label:
	var label: Label = _label(text.to_upper(), Gen2LauncherTheme.FONT_TINY, theme.faint)
	label.add_theme_constant_override("outline_size", 0)
	return label


static func column(separation: int = GAP_MD) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func row(separation: int = GAP_MD) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func spacer() -> Control:
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


## Label on the left, control on the right, which is every settings line.
static func field(theme: Gen2LauncherTheme, text: String, control: Control) -> HBoxContainer:
	var line: HBoxContainer = row(GAP_MD)
	var label: Label = body(theme, text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(label)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(control)
	return line


## A row of choices in one track, the chosen one filled.
static func segmented(
	theme: Gen2LauncherTheme, choices: Array, selected: int, handler: Callable
) -> Control:
	var track: Gen2LauncherCard = Gen2LauncherCard.well(theme, Gen2LauncherTheme.RADIUS_SM, 3)
	var line: HBoxContainer = row(2)
	track.add_child(line)
	var buttons: Array[Gen2LauncherButton] = []
	for index: int in choices.size():
		var button: Gen2LauncherButton = Gen2LauncherButton.create(
			theme, String(choices[index]), Gen2LauncherButton.Variant.SEGMENT
		)
		button.custom_minimum_size = Vector2(0, 30)
		button.add_theme_font_size_override("font_size", Gen2LauncherTheme.FONT_SMALL)
		buttons.append(button)
		line.add_child(button)
		button.pressed.connect(func() -> void:
			for other: Gen2LauncherButton in buttons:
				other.set_active(false)
			button.set_active(true)
			handler.call(index)
		)
	if selected >= 0 and selected < buttons.size():
		buttons[selected].set_active(true)
	return track


static func slider(
	theme: Gen2LauncherTheme, value: int, minimum: int, maximum: int, handler: Callable
) -> Control:
	var line: HBoxContainer = row(GAP_MD)
	var bar := HSlider.new()
	bar.min_value = minimum
	bar.max_value = maximum
	bar.step = 1
	bar.value = value
	bar.custom_minimum_size = Vector2(170, 22)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var readout: Label = muted(theme, str(value))
	readout.custom_minimum_size = Vector2(30, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.value_changed.connect(func(changed: float) -> void:
		readout.text = str(int(changed))
		handler.call(int(changed))
	)
	line.add_child(bar)
	line.add_child(readout)
	return line


static func _label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label
