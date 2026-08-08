class_name Gen2LauncherButton
extends Button

## Every button the launcher draws, in the five weights it uses.
##
## Godot lays out a button's own icon and label, so the glyph is handed over as
## a texture rather than parked by hand. What this class adds is the palette, the
## press sound and a hover that lifts the round dock buttons.

enum Variant {
	## The one action a screen is about: a filled accent pill.
	PRIMARY,
	## A card-coloured button with a hairline.
	NEUTRAL,
	## No fill until hovered. Rows of these read as labels.
	QUIET,
	## Destructive, tinted with the error colour.
	DANGER,
	## One choice inside a segmented track.
	SEGMENT,
	## A round icon button, used along the bottom dock.
	DOCK,
}

const ICON_SIDE: float = 18.0
const DOCK_SIDE: float = 52.0

var variant: Variant = Variant.NEUTRAL
## Played on press. A cartridge action overrides it with its own clip.
var sound: StringName = &"click"

var _theme: Gen2LauncherTheme = null
var _glyph: StringName = &""
## Whether this is the current choice in its group. Kept here rather than on
## [member BaseButton.button_pressed], which only means anything to a toggle.
var _active: bool = false


static func create(
	theme: Gen2LauncherTheme,
	label: String,
	kind: Variant = Variant.NEUTRAL,
	glyph: StringName = &"",
) -> Gen2LauncherButton:
	var button := Gen2LauncherButton.new()
	button._theme = theme
	button.variant = kind
	button.text = label
	button._glyph = glyph
	button.custom_minimum_size = Vector2(0, 42)
	button.repaint()
	return button


## A square button carrying only an icon.
static func icon_only(
	theme: Gen2LauncherTheme,
	glyph: StringName,
	kind: Variant = Variant.QUIET,
	side: float = 42.0,
) -> Gen2LauncherButton:
	var button: Gen2LauncherButton = create(theme, "", kind, glyph)
	button.custom_minimum_size = Vector2(side, side)
	return button


## A round dock button with its name written underneath by the caller.
static func dock(theme: Gen2LauncherTheme, glyph: StringName) -> Gen2LauncherButton:
	return icon_only(theme, glyph, Variant.DOCK, DOCK_SIDE)


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	add_theme_font_size_override("font_size", Gen2LauncherTheme.FONT_BODY)
	add_theme_constant_override("h_separation", 9)
	add_theme_constant_override("icon_max_width", int(ICON_SIDE))
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	focus_entered.connect(_on_hover.bind(true))
	focus_exited.connect(_on_hover.bind(false))
	pressed.connect(func() -> void: Gen2LauncherAudio.play(sound))
	resized.connect(_centre_pivot)


func set_glyph(glyph: StringName) -> void:
	_glyph = glyph
	repaint()


func is_active() -> bool:
	return _active


## Marks the button as the current choice in its group.
func set_active(active: bool) -> void:
	_active = active
	repaint()


func repaint() -> void:
	if _theme == null:
		return
	var radius: float = _radius()
	var pad_x: int = 0 if text.is_empty() else 18
	var pad_y: int = 10
	var fill: Color = _theme.surface
	var border: Color = _theme.line
	var ink: Color = _theme.text

	match variant:
		Variant.PRIMARY:
			fill = _theme.accent
			border = Color(0, 0, 0, 0)
			ink = _theme.on_accent
		Variant.NEUTRAL:
			ink = _theme.text
		Variant.QUIET:
			fill = _theme.accent_wash(0.13) if _active else Color(0, 0, 0, 0)
			border = Color(0, 0, 0, 0)
			ink = _theme.accent if _active else _theme.muted
		Variant.DANGER:
			fill = _theme.with_alpha(_theme.error, 0.10)
			border = _theme.with_alpha(_theme.error, 0.35)
			ink = _theme.error
		Variant.SEGMENT:
			fill = _theme.surface if _active else Color(0, 0, 0, 0)
			border = Color(0, 0, 0, 0)
			ink = _theme.text if _active else _theme.muted
			pad_x = 14
			pad_y = 7
		Variant.DOCK:
			fill = _theme.accent_wash(0.16) if _active else _theme.surface
			border = _theme.accent if _active else _theme.line
			ink = _theme.accent if _active else _theme.muted

	_style("normal", fill, border, radius, pad_x, pad_y)
	_style("hover", _hovered(fill), _hovered(border), radius, pad_x, pad_y)
	_style("pressed", _pressed_fill(fill), _hovered(border), radius, pad_x, pad_y)
	_style("disabled", _theme.with_alpha(fill, 0.4), _theme.with_alpha(border, 0.4),
		radius, pad_x, pad_y)
	_style("focus", Color(0, 0, 0, 0), _theme.accent, radius, pad_x, pad_y, 2)

	for state: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color"]:
		add_theme_color_override(state, ink)
	add_theme_color_override("font_disabled_color", _theme.faint)
	if not _glyph.is_empty():
		icon = Gen2LauncherIcon.raster(
			_glyph, ICON_SIDE, _theme.faint if disabled else ink
		)
	# Godot gives the icon the left slot and the label the rest of the width, so
	# a button with no label leaves its icon hard against the left edge. Centring
	# the icon and dropping the separation is what puts it in the middle.
	icon_alignment = (
		HORIZONTAL_ALIGNMENT_LEFT if not text.is_empty() else HORIZONTAL_ALIGNMENT_CENTER
	)
	add_theme_constant_override("h_separation", 9 if not text.is_empty() else 0)


func set_disabled_state(off: bool) -> void:
	disabled = off
	repaint()


func _radius() -> float:
	match variant:
		Variant.PRIMARY, Variant.DANGER:
			return Gen2LauncherTheme.RADIUS_PILL
		Variant.DOCK:
			return DOCK_SIDE * 0.5
		Variant.SEGMENT:
			return Gen2LauncherTheme.RADIUS_SM - 2.0
	return Gen2LauncherTheme.RADIUS_SM


func _style(
	state: String, fill: Color, border: Color, radius: float, pad_x: int, pad_y: int,
	border_width: int = 1,
) -> void:
	add_theme_stylebox_override(
		state, _theme.padded(_theme.box(fill, radius, border, border_width), pad_x, pad_y)
	)


func _hovered(colour: Color) -> Color:
	if colour.a <= 0.0:
		return _theme.accent_wash(0.10) if variant != Variant.PRIMARY else colour
	return colour.lerp(_theme.text if variant == Variant.PRIMARY else _theme.accent, 0.14)


func _pressed_fill(colour: Color) -> Color:
	if colour.a <= 0.0:
		return _theme.accent_wash(0.18)
	return colour.darkened(0.10) if not _theme.is_dark() else colour.lightened(0.08)


func _centre_pivot() -> void:
	pivot_offset = size * 0.5


## Only the round dock buttons move: a row of them is the launcher's one place
## where a pointer wants to feel the target.
func _on_hover(entered: bool) -> void:
	if disabled:
		return
	if entered:
		Gen2LauncherAudio.play(&"hover")
	if variant != Variant.DOCK or not is_inside_tree():
		return
	_centre_pivot()
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2.ONE * (1.12 if entered else 1.0), 0.18)
