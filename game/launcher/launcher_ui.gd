class_name Gen2LauncherUI
extends RefCounted

## Small shared pieces every launcher page builds from: text, rows, and the
## composite controls (segmented choice, number and slider) that replace Godot's
## own.

const GAP_XS: int = 4
const GAP_SM: int = 8
const GAP_MD: int = 14
const GAP_LG: int = 22
## Empty scroll tail that lets the final control rise clear of the floating dock.
const DOCK_SAFE_BOTTOM: float = 132.0


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


## A row of buttons that wraps onto a second line rather than widening its page.
## A narrow window is the ordinary case on a phone held upright, and the launcher
## pages scroll vertically only.
static func actions(separation: int = GAP_SM) -> HFlowContainer:
	var box := HFlowContainer.new()
	box.add_theme_constant_override("h_separation", separation)
	box.add_theme_constant_override("v_separation", separation)
	return box


static func row(separation: int = GAP_MD) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


## Empties a container that is about to be rebuilt.
##
## Every launcher pane is rebuilt from a button inside it, so the node emitting
## `pressed` is one of the children being removed and `free()` there destroys an
## object the signal is still walking. Detaching first takes the child out of the
## rebuilt list at once and leaves the deletion to the end of the frame.
static func clear(container: Node) -> void:
	if container == null:
		return
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


static func spacer() -> Control:
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


static func dock_safe_space() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = DOCK_SAFE_BOTTOM
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


## How wide a control wants to be, which is its minimum unless it holds a row
## that wraps: such a row measures as one column, so a [FieldRow] would squeeze a
## whole track into a column even where it fits unwrapped. A control that wraps
## points at the row with `wrapping_row`, and this adds back what wrapping hid.
## Measured on the call rather than stored, because a minimum is not settled
## until the control is in a tree with a font.
static func preferred_width(control: Control) -> float:
	var minimum: float = control.get_combined_minimum_size().x
	if not control.has_meta(&"wrapping_row"):
		return minimum
	var flow := control.get_meta(&"wrapping_row") as HFlowContainer
	if flow == null:
		return minimum
	var wanted: float = 0.0
	var widest: float = 0.0
	var counted: int = 0
	for child: Node in flow.get_children():
		var item := child as Control
		if item == null or not item.visible:
			continue
		var item_wide: float = item.get_combined_minimum_size().x
		wanted += item_wide
		widest = maxf(widest, item_wide)
		counted += 1
	if counted == 0:
		return minimum
	wanted += float((counted - 1) * flow.get_theme_constant(&"h_separation", &"HFlowContainer"))
	return minimum - widest + wanted


## Label on the left, control on the right, which is every settings line.
static func field(theme: Gen2LauncherTheme, text: String, control: Control) -> Container:
	var line := FieldRow.new()
	var label: Label = body(theme, text)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(label)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(control)
	return line


## The two halves of a [method field], side by side while they both fit and
## stacked when they do not.
##
## Every launcher page scrolls vertically only, so a row wider than the window is
## cut off rather than reachable, and a settings row is exactly the shape that
## outgrows a portrait phone: the label wants its whole text and the control
## carries its own minimum width. Stacking is what keeps the control on screen.
class FieldRow extends Container:
	func _init() -> void:
		resized.connect(update_minimum_size)

	func _halves() -> Array[Control]:
		var found: Array[Control] = []
		for child: Node in get_children():
			var control := child as Control
			if control != null and control.visible:
				found.append(control)
		return found

	## Measured against the width actually given, which is why the row asks to be
	## re-measured whenever it is resized.
	func _stacks(halves: Array[Control]) -> bool:
		var wanted: float = halves[0].get_combined_minimum_size().x \
			+ float(GAP_MD) + Gen2LauncherUI.preferred_width(halves[1])
		return size.x > 0.0 and size.x < wanted

	func _get_minimum_size() -> Vector2:
		var halves: Array[Control] = _halves()
		if halves.size() < 2:
			return Vector2.ZERO
		var label: Vector2 = halves[0].get_combined_minimum_size()
		var control: Vector2 = halves[1].get_combined_minimum_size()
		# The width asked for is the control's alone, never the whole row's: a row
		# that asked for both halves would be granted them, and would then always
		# measure as fitting and never stack. The label is what gives instead.
		if _stacks(halves):
			return Vector2(control.x, label.y + float(GAP_XS) + control.y)
		return Vector2(control.x, maxf(label.y, control.y))

	func _notification(what: int) -> void:
		if what != NOTIFICATION_SORT_CHILDREN:
			return
		var halves: Array[Control] = _halves()
		if halves.size() < 2:
			return
		var label: Vector2 = halves[0].get_combined_minimum_size()
		if _stacks(halves):
			fit_child_in_rect(halves[0], Rect2(0.0, 0.0, size.x, label.y))
			fit_child_in_rect(halves[1], Rect2(
				0.0, label.y + float(GAP_XS), size.x, size.y - label.y - float(GAP_XS)
			))
			return
		var control_width: float = Gen2LauncherUI.preferred_width(halves[1])
		var label_width: float = maxf(size.x - control_width - float(GAP_MD), 0.0)
		fit_child_in_rect(halves[0], Rect2(0.0, 0.0, label_width, size.y))
		fit_child_in_rect(halves[1], Rect2(
			label_width + float(GAP_MD), 0.0, control_width, size.y
		))


## A row of choices in one track, the chosen one filled.
static func segmented(
	theme: Gen2LauncherTheme, choices: Array, selected: int, handler: Callable
) -> Control:
	var track: Gen2LauncherCard = Gen2LauncherCard.well(theme, Gen2LauncherTheme.RADIUS_SM, 3)
	# Wraps for the same reason [FieldRow] stacks: a five-choice track is wider
	# than a phone held upright, and the page it sits in has no second axis.
	var line: HFlowContainer = actions(2)
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
	track.set_meta(&"wrapping_row", line)
	return track


## One whole number, typed or stepped. A slider is the wrong shape for a value
## whose range is wide and whose exact digits matter, which is what a mod's
## number setting usually is.
static func number(
	theme: Gen2LauncherTheme, value: int, minimum: int, maximum: int, step: int,
	handler: Callable,
) -> Control:
	var box := SpinBox.new()
	box.min_value = minimum
	box.max_value = maximum
	box.step = maxi(step, 1)
	box.value = value
	box.select_all_on_focus = true
	box.custom_minimum_size = Vector2(120, 0)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var field_edit: LineEdit = box.get_line_edit()
	field_edit.add_theme_font_size_override("font_size", Gen2LauncherTheme.FONT_SMALL)
	field_edit.add_theme_color_override("font_color", theme.text)
	box.value_changed.connect(func(changed: float) -> void: handler.call(int(changed)))
	return box


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


## The one file picker every launcher dialog is built from.
##
## `use_native_dialog` is asked for unconditionally rather than gated on
## `FEATURE_NATIVE_DIALOG_FILE`: [FileDialog] already makes that exact test
## before it goes native and falls back to its own window when the platform says
## no, so a second gate here can only refuse a picker the platform would have
## given us. That is what left iOS on the built-in browser, which lists paths
## `FileAccess.open()` then refuses on every sandboxed platform. Any new
## file-picking UI goes through here rather than building its own [FileDialog].
static func file_picker(
	theme: Gen2LauncherTheme,
	title_text: String,
	mode: FileDialog.FileMode,
	filters: PackedStringArray
) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = filters
	dialog.title = title_text
	dialog.use_native_dialog = true
	dialog.theme = theme.control_theme()
	return dialog


static func _label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label
