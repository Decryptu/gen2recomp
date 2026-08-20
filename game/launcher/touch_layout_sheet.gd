class_name Gen2TouchLayoutSheet
extends Control

## Arranging the on-screen controller: drag each cluster where a thumb wants it,
## and set how large and how solid it is.
##
## Full screen rather than a card, because the thing being arranged is measured
## against the whole screen and a preview in a box would place it against the
## wrong rectangle.
##
## The layout is per orientation, and this edits the one the window is currently
## in. On the device that matters, turning it sideways is how the other is
## reached, which is also the only way to see what that one will look like.

signal closed()

const SCALE_STEPS: int = 100
const OPACITY_STEPS: int = 100

var _theme: Gen2LauncherTheme = null
var _options: Gen2Options = null
var _pad: Gen2TouchPad = null
var _orientation: Label = null


static func create(palette: Gen2LauncherTheme, options: Gen2Options) -> Gen2TouchLayoutSheet:
	var sheet := Gen2TouchLayoutSheet.new()
	sheet._theme = palette
	sheet._options = options
	sheet._build()
	return sheet


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = _theme.control_theme()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_pad = Gen2TouchPad.new()
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The live layout, not a copy: a drag edits the options object directly, so
	# there is nothing to write back when the editor closes.
	_pad.set_layout(_options.touch_layout)
	_pad.set_edit_mode(true)
	add_child(_pad)

	add_child(_toolbar())
	resized.connect(_refresh_orientation)
	_refresh_orientation()


func _toolbar() -> Control:
	var host := MarginContainer.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	host.add_theme_constant_override("margin_left", 24)
	host.add_theme_constant_override("margin_right", 24)
	host.add_theme_constant_override("margin_top", 20)
	var card: Gen2LauncherCard = Gen2LauncherCard.floating(
		_theme, Gen2LauncherTheme.RADIUS_LG, 18, 30
	)
	host.add_child(card)
	var column: VBoxContainer = Gen2LauncherUI.column(Gen2LauncherUI.GAP_SM)
	card.add_child(column)

	var head: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_MD)
	column.add_child(head)
	var heading: Label = Gen2LauncherUI.title(_theme, "Arrange the buttons")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	var done: Gen2LauncherButton = Gen2LauncherButton.create(
		_theme, "Done", Gen2LauncherButton.Variant.PRIMARY, &"check"
	)
	done.pressed.connect(close)
	head.add_child(done)

	_orientation = Gen2LauncherUI.muted(_theme, "")
	column.add_child(_orientation)

	column.add_child(Gen2LauncherUI.field(_theme, "Size", Gen2LauncherUI.slider(
		_theme,
		int(roundf(_options.touch_layout.scale * SCALE_STEPS)),
		int(Gen2TouchLayout.MIN_SCALE * SCALE_STEPS),
		int(Gen2TouchLayout.MAX_SCALE * SCALE_STEPS),
		func(value: int) -> void:
			_options.touch_layout.scale = float(value) / SCALE_STEPS
			_pad.queue_redraw()
	)))
	column.add_child(Gen2LauncherUI.field(_theme, "Opacity", Gen2LauncherUI.slider(
		_theme,
		int(roundf(_options.touch_layout.opacity * OPACITY_STEPS)),
		int(Gen2TouchLayout.MIN_OPACITY * OPACITY_STEPS),
		int(Gen2TouchLayout.MAX_OPACITY * OPACITY_STEPS),
		func(value: int) -> void:
			_options.touch_layout.opacity = float(value) / OPACITY_STEPS
			_pad.queue_redraw()
	)))
	return host


func _refresh_orientation() -> void:
	if _orientation == null:
		return
	var landscape: bool = Gen2TouchLayout.orientation_of(size) \
		== Gen2TouchLayout.ORIENTATION_LANDSCAPE
	_orientation.text = (
		"Drag each group. This is the %s arrangement; turn the device to set the other."
		% ("sideways" if landscape else "upright")
	)


func open(host: Control) -> void:
	host.add_child(self)


## The layout being edited is the live one, so nothing has to be copied back.
## Writing it is the caller's, on [signal closed]: a slider dragged across its
## track would otherwise be one disk write per pixel.
func close() -> void:
	_pad.set_edit_mode(false)
	Gen2InputRuntime.instance().apply_options(_options)
	closed.emit()
	Gen2Screen.drop(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		close()
