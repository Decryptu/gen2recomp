class_name Gen2LauncherTheme
extends RefCounted

## Colours, metrics and a stock-control [Theme] for every launcher screen.
##
## One instance describes one appearance. Screens read [method active], which
## follows `ui_theme` in the options file, and rebuild themselves when it
## changes: everything the launcher draws is built in code, so a rebuild is
## cheaper and more reliable than repainting live nodes.
##
## Depth is carried by fills and hairlines, not by shadows. Only what genuinely
## floats over the page casts one, which is why a shadow is never cut off by the
## scroll or margin container it happens to sit in.

const LIGHT: StringName = &"light"
const DARK: StringName = &"dark"
const MODES: Array[StringName] = [LIGHT, DARK]

const RADIUS_LG: float = 22.0
const RADIUS_MD: float = 14.0
const RADIUS_SM: float = 10.0
const RADIUS_PILL: float = 999.0

const FONT_HERO: int = 40
const FONT_DISPLAY: int = 28
const FONT_TITLE: int = 19
const FONT_BODY: int = 15
const FONT_SMALL: int = 13
const FONT_TINY: int = 11

## The three cartridges, tinted so the stage lights up in the colour of whatever
## is selected. Keys match [RomRegistry.ORDER].
const GAME_TINTS: Dictionary = {
	&"gold": Color("#dfa63a"),
	&"silver": Color("#93a6bd"),
	&"crystal": Color("#3ab9bf"),
}

var mode: StringName = LIGHT
var backdrop_top: Color
var backdrop_bottom: Color
## The colour a card or a bar is filled with.
var surface: Color
## A step back from [member surface]: tracks, wells and unselected segments.
var surface_alt: Color
## The hairline that separates one surface from another.
var line: Color
var shadow: Color
var text: Color
var muted: Color
var faint: Color
var accent: Color
var on_accent: Color
var success: Color
var warning: Color
var error: Color


static func for_mode(wanted: StringName) -> Gen2LauncherTheme:
	var theme := Gen2LauncherTheme.new()
	theme.mode = wanted if MODES.has(wanted) else LIGHT
	if theme.mode == DARK:
		theme.backdrop_top = Color("#1b1f27")
		theme.backdrop_bottom = Color("#101318")
		theme.surface = Color("#232935")
		theme.surface_alt = Color("#1a1e27")
		theme.line = Color("#333b4a")
		theme.shadow = Color(0, 0, 0, 0.55)
		theme.text = Color("#edf1f8")
		theme.muted = Color("#9aa5b8")
		theme.faint = Color("#6b7688")
		theme.accent = Color("#8f7cf8")
		theme.on_accent = Color("#12141a")
		theme.success = Color("#42cf90")
		theme.warning = Color("#e6ab4c")
		theme.error = Color("#f2837c")
	else:
		theme.backdrop_top = Color("#f5f7fb")
		theme.backdrop_bottom = Color("#e6eaf2")
		theme.surface = Color("#ffffff")
		theme.surface_alt = Color("#eef1f7")
		theme.line = Color("#dde2ec")
		theme.shadow = Color(0.12, 0.15, 0.20, 0.16)
		theme.text = Color("#1f2530")
		theme.muted = Color("#5d6778")
		theme.faint = Color("#98a2b3")
		theme.accent = Color("#6a5ae6")
		theme.on_accent = Color("#ffffff")
		theme.success = Color("#1c9b62")
		theme.warning = Color("#b97c25")
		theme.error = Color("#d2504b")
	return theme


## The appearance the player chose, or the light one when no options file has
## been written yet.
static func active() -> Gen2LauncherTheme:
	return for_mode(Gen2OptionsStore.current().ui_theme)


func is_dark() -> bool:
	return mode == DARK


func other_mode() -> StringName:
	return LIGHT if is_dark() else DARK


## The colour the stage is lit in while [param game_id] is selected.
func tint_for(game_id: StringName) -> Color:
	return GAME_TINTS.get(game_id, accent)


## A translucent accent wash, used behind a selected control.
func accent_wash(alpha: float = 0.14) -> Color:
	var wash: Color = accent
	wash.a = alpha
	return wash


func with_alpha(colour: Color, alpha: float) -> Color:
	var out: Color = colour
	out.a = alpha
	return out


## A filled rectangle with an optional hairline. Used for every card, bar and
## well the launcher draws.
func box(
	fill: Color,
	radius: float = RADIUS_MD,
	border: Color = Color(0, 0, 0, 0),
	border_width: int = 1,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(int(radius))
	style.corner_detail = 12
	if border.a > 0.0:
		style.border_color = border
		style.set_border_width_all(border_width)
	return style


## A card that reads as sitting on the page rather than printed on it. Reserved
## for the few things that really float, because a shadow is drawn outside the
## control and any clipping ancestor would cut it.
func floating(fill: Color, radius: float = RADIUS_MD, spread: int = 22) -> StyleBoxFlat:
	var style: StyleBoxFlat = box(fill, radius)
	style.shadow_color = shadow
	style.shadow_size = spread
	style.shadow_offset = Vector2(0, maxf(2.0, float(spread) * 0.32))
	return style


func padded(style: StyleBoxFlat, pad_x: int, pad_y: int = -1) -> StyleBoxFlat:
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	style.content_margin_top = pad_y if pad_y >= 0 else pad_x
	style.content_margin_bottom = pad_y if pad_y >= 0 else pad_x
	return style


## Styling for the stock controls the launcher still uses: text fields, drop
## downs, scroll bars and the file dialogs it cannot draw itself.
func control_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_BODY

	var field: StyleBoxFlat = padded(box(surface_alt, RADIUS_SM, line), 12, 9)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", padded(box(surface_alt, RADIUS_SM, accent, 2), 12, 9))
	theme.set_stylebox("read_only", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", text)
	theme.set_color("font_placeholder_color", "LineEdit", faint)
	theme.set_color("caret_color", "LineEdit", accent)
	theme.set_color("selection_color", "LineEdit", accent_wash(0.30))

	for type: String in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		theme.set_stylebox("normal", type, padded(box(surface, RADIUS_SM, line), 14, 9))
		theme.set_stylebox(
			"hover", type, padded(box(surface.lerp(accent, 0.07), RADIUS_SM, accent_wash(0.4)), 14, 9)
		)
		theme.set_stylebox("pressed", type, padded(box(surface_alt, RADIUS_SM, line), 14, 9))
		theme.set_stylebox(
			"focus", type, padded(box(Color(0, 0, 0, 0), RADIUS_SM, accent, 2), 14, 9)
		)
		theme.set_stylebox("disabled", type, padded(box(surface_alt, RADIUS_SM, line), 14, 9))
		theme.set_color("font_color", type, text)
		theme.set_color("font_hover_color", type, text)
		theme.set_color("font_pressed_color", type, accent)
		theme.set_color("font_disabled_color", type, faint)

	theme.set_stylebox("panel", "PopupMenu", padded(floating(surface, RADIUS_SM, 18), 8))
	theme.set_color("font_color", "PopupMenu", text)
	theme.set_color("font_hover_color", "PopupMenu", accent)
	theme.set_stylebox("hover", "PopupMenu", padded(box(accent_wash(0.14), RADIUS_SM), 8, 4))

	theme.set_stylebox("panel", "Panel", box(surface, RADIUS_MD, line))
	theme.set_stylebox("panel", "PanelContainer", box(surface, RADIUS_MD, line))
	theme.set_stylebox("panel", "AcceptDialog", padded(box(backdrop_top, 0.0), 18))
	theme.set_color("font_color", "Label", text)
	theme.set_color("default_color", "RichTextLabel", text)

	for type: String in ["HScrollBar", "VScrollBar"]:
		theme.set_stylebox("scroll", type, box(Color(0, 0, 0, 0), 4.0))
		theme.set_stylebox("grabber", type, box(with_alpha(faint, 0.5), 4.0))
		theme.set_stylebox("grabber_highlight", type, box(with_alpha(faint, 0.8), 4.0))
		theme.set_stylebox("grabber_pressed", type, box(accent, 4.0))
	for type: String in ["HSlider", "VSlider"]:
		theme.set_stylebox("slider", type, padded(box(surface_alt, 3.0, line), 0, 3))
		theme.set_stylebox("grabber_area", type, padded(box(accent, 3.0), 0, 3))
		theme.set_stylebox("grabber_area_highlight", type, padded(box(accent, 3.0), 0, 3))
		theme.set_icon("grabber", type, _knob(accent))
		theme.set_icon("grabber_highlight", type, _knob(accent.lightened(0.15)))
		theme.set_icon("grabber_disabled", type, _knob(faint))

	theme.set_stylebox("background", "ProgressBar", box(surface_alt, 4.0))
	theme.set_stylebox("fill", "ProgressBar", box(accent, 4.0))
	theme.set_stylebox("panel", "Tree", box(surface, RADIUS_SM, line))
	theme.set_color("font_color", "Tree", text)
	theme.set_color("separator", "HSeparator", line)
	return theme


## A slider knob: the accent disc a stock [HSlider] draws as an icon rather than
## as a stylebox.
func _knob(fill: Color) -> ImageTexture:
	var side: int = 18
	var image: Image = Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var centre: float = float(side) * 0.5
	for y: int in side:
		for x: int in side:
			var distance: float = Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(
				Vector2(centre, centre)
			)
			var colour: Color = surface if distance > centre - 3.5 else fill
			colour.a = clampf(centre - distance, 0.0, 1.0)
			image.set_pixel(x, y, colour)
	return ImageTexture.create_from_image(image)
