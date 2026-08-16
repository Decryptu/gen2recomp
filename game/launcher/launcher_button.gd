class_name Gen2LauncherButton
extends Button

## Every button the launcher draws, in the weights it uses.
##
## Godot lays out a button's own icon and label, so the glyph is handed over as
## a texture rather than parked by hand. What this class adds is the palette, the
## press sound and a hover that lifts the round dock buttons.

enum Variant {
	## The one action a screen is about: a filled accent pill.
	PRIMARY,
	## A chip that fills with the accent when it is reached.
	NEUTRAL,
	## No fill until hovered. Rows of these read as labels.
	QUIET,
	## Destructive, tinted with the error colour.
	DANGER,
	## One choice inside a segmented track.
	SEGMENT,
	## A round icon button, used along the bottom dock.
	DOCK,
	## The one thing a screen is for, written plainly until it is reached. It
	## carries no colour of its own so that hover, focus and the current choice
	## are the only accent on the page, which is what makes a pad legible.
	HERO,
}

const ICON_SIDE: float = 23.0
const DOCK_SIDE: float = 76.0
const DOCK_ICON_SHARE: float = 0.42

var variant: Variant = Variant.NEUTRAL
## Played on press. A cartridge action overrides it with its own clip.
var sound: StringName = &"click"

var _theme: Gen2LauncherTheme = null
var _glyph: StringName = &""
## Whether this is the current choice in its group. Kept here rather than on
## [member BaseButton.button_pressed], which only means anything to a toggle.
var _active: bool = false
## Whether a pointer is over the button or a pad is on it. The icon is a raster
## rather than a themed colour, so reaching a button has to repaint rather than
## swap a stylebox.
var _lit: bool = false
var _side: float = DOCK_SIDE


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
	button.set_side(side)
	return button


## Resizes a round or square icon button, keeping it circular. A [BoxContainer]
## stretches its children across the row, so without the shrink a disc beside a
## taller button is drawn as an ellipse.
func set_side(side: float) -> void:
	_side = side
	custom_minimum_size = Vector2(side, side)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	repaint()


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
	# Only enough room either side of the glyph to keep it off the edge: a button
	# is mostly icon, which is what makes one readable at a glance and at a
	# distance.
	var pad_x: int = 0 if text.is_empty() else 20
	var pad_y: int = 8
	var fill: Color = _theme.surface
	var border: Color = Color(0, 0, 0, 0)
	var ink: Color = _theme.on_surface
	# Reached means hovered, focused or the current choice. The three look the
	# same on purpose: a pad moving onto a control has to read exactly as a
	# pointer resting on it.
	var reached: bool = _lit or _active
	var icon_side: float = _side * DOCK_ICON_SHARE if variant == Variant.DOCK else ICON_SIDE

	match variant:
		Variant.PRIMARY:
			fill = _theme.accent
			ink = _theme.on_accent
		Variant.QUIET:
			fill = _theme.accent_wash(0.13) if _active else Color(0, 0, 0, 0)
			ink = _theme.accent if _active else _theme.muted
		Variant.DANGER:
			fill = _theme.with_alpha(_theme.error, 0.12)
			border = _theme.with_alpha(_theme.error, 0.40)
			ink = _theme.error
		# The chosen segment is a chip in its track, so which one is chosen reads
		# from the fill rather than from a hairline around it.
		Variant.SEGMENT:
			fill = _theme.surface if _active else Color(0, 0, 0, 0)
			ink = _theme.on_surface if _active else _theme.muted
			pad_x = 14
			pad_y = 7
		# A plain chip with no outline: reaching it fills it with the accent and
		# turns the glyph white, which is the whole of the state it carries.
		Variant.NEUTRAL, Variant.DOCK, Variant.HERO:
			fill = _theme.accent if reached else _theme.surface
			ink = _theme.on_accent if reached else _theme.on_surface

	_style("normal", fill, border, radius, pad_x, pad_y)
	_style("hover", _hovered(fill), _hovered(border), radius, pad_x, pad_y)
	_style("pressed", _pressed_fill(fill), _hovered(border), radius, pad_x, pad_y)
	_style("disabled", _theme.with_alpha(fill, 0.4), _theme.with_alpha(border, 0.4),
		radius, pad_x, pad_y)
	# Focus is not hover or the active value. A distinct, heavy accent ring is
	# always present so keyboard and controller users can locate the cursor even
	# on a filled primary button or the already-selected dock page.
	_style("focus", Color(0, 0, 0, 0), _theme.accent, radius, pad_x, pad_y, 3)

	for state: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color"]:
		add_theme_color_override(state, ink)
	add_theme_color_override("font_disabled_color", _theme.faint)
	add_theme_constant_override("icon_max_width", int(icon_side))
	if not _glyph.is_empty():
		icon = Gen2LauncherIcon.raster(
			_glyph, icon_side, _theme.faint if disabled else ink
		)
	# Godot gives the icon the left slot and the label the rest of the width, so
	# a button with no label leaves its icon hard against the left edge. Centring
	# the icon and dropping the separation is what puts it in the middle.
	icon_alignment = (
		HORIZONTAL_ALIGNMENT_LEFT if not text.is_empty() else HORIZONTAL_ALIGNMENT_CENTER
	)
	add_theme_constant_override("h_separation", 9 if not text.is_empty() else 0)


func _fills_on_focus() -> bool:
	return variant == Variant.NEUTRAL or variant == Variant.DOCK or variant == Variant.HERO


func set_disabled_state(off: bool) -> void:
	disabled = off
	repaint()


func _radius() -> float:
	match variant:
		Variant.PRIMARY, Variant.DANGER, Variant.HERO:
			return Gen2LauncherTheme.RADIUS_PILL
		Variant.DOCK:
			return _side * 0.5
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
	# Focus and the pointer both count as reached, so a button the mouse has left
	# stays lit while a pad is still on it.
	var reached: bool = entered or has_focus() or is_hovered()
	if reached != _lit:
		_lit = reached
		repaint()
	if entered:
		Gen2LauncherAudio.play(&"hover")
	if variant != Variant.DOCK or not is_inside_tree():
		return
	_centre_pivot()
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2.ONE * (1.12 if entered else 1.0), 0.18)
