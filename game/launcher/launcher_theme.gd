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

## One accent in both appearances. A control that is reached looks the same
## whichever way round the page is, which is what makes a pad legible.
const ACCENT: Color = Color("#4756e7")

const RADIUS_LG: float = 22.0
const RADIUS_MD: float = 14.0
const RADIUS_SM: float = 10.0
const RADIUS_PILL: float = 999.0

## The clear space between a control's own edge and the focus ring around it. A
## ring drawn flush on an accent button only makes the button look bigger; a
## ring standing off it reads as a ring in every palette.
const FOCUS_GAP: int = 3

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
## The chip colour: buttons, the toast, anything that reads as a solid object
## laid on the page. It is the opposite of the page, so a control is legible
## without an outline and a filled one says so from across the room.
var surface: Color
## What is written or drawn on [member surface].
var on_surface: Color
## A content card: the same side of the page as the backdrop, because the text
## inside one is page text.
var panel: Color
## A step back from [member panel]: tracks, wells and unselected segments.
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
		theme.backdrop_top = Color("#1c1c1e")
		theme.backdrop_bottom = Color("#131314")
		theme.surface = Color("#f2f2f2")
		theme.on_surface = Color("#333333")
		theme.panel = Color("#232324")
		theme.surface_alt = Color("#1a1a1b")
		theme.line = Color("#3a3a3c")
		theme.shadow = Color(0, 0, 0, 0.55)
		theme.text = Color("#f2f2f2")
		theme.muted = Color("#a3a3a5")
		theme.faint = Color("#76767a")
		theme.on_accent = Color("#ffffff")
		theme.success = Color("#43c98a")
		theme.warning = Color("#e0a94f")
		theme.error = Color("#ef7f79")
	else:
		theme.backdrop_top = Color("#f7f7f8")
		theme.backdrop_bottom = Color("#eaeaec")
		theme.surface = Color("#464445")
		theme.on_surface = Color("#f2f2f2")
		theme.panel = Color("#ffffff")
		theme.surface_alt = Color("#eeeeef")
		theme.line = Color("#dededf")
		theme.shadow = Color(0.10, 0.10, 0.11, 0.16)
		theme.text = Color("#252525")
		theme.muted = Color("#5c5c5e")
		theme.faint = Color("#909093")
		theme.on_accent = Color("#ffffff")
		theme.success = Color("#1c9b62")
		theme.warning = Color("#b97c25")
		theme.error = Color("#cf4a45")
	theme.accent = ACCENT
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


## A status colour taken far enough towards [member on_surface] to be read on a
## chip. One rule serves both appearances, because the chip is the opposite side
## of the page from the backdrop in each of them.
func on_chip(colour: Color) -> Color:
	return colour.lerp(on_surface, 0.45)


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


## The ring that says a keyboard or a pad is on a control, drawn clear of it by
## [constant FOCUS_GAP]. Expand margins draw outside the control's rect without
## touching its layout, so nothing moves when focus arrives.
func focus_ring(radius: float = RADIUS_SM, width: int = 2) -> StyleBoxFlat:
	# A border is drawn inside its box, so the box has to clear the control by the
	# gap and the stroke together for the gap to survive.
	var reach: float = float(FOCUS_GAP + width)
	var style: StyleBoxFlat = box(Color(0, 0, 0, 0), radius + reach, accent, width)
	style.set_expand_margin_all(reach)
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
	theme.set_stylebox("focus", "LineEdit", padded(focus_ring(RADIUS_SM), 12, 9))
	theme.set_stylebox("read_only", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", text)
	theme.set_color("font_placeholder_color", "LineEdit", faint)
	theme.set_color("caret_color", "LineEdit", accent)
	theme.set_color("selection_color", "LineEdit", accent_wash(0.30))

	for type: String in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		theme.set_stylebox("normal", type, padded(box(panel, RADIUS_SM, line), 14, 9))
		theme.set_stylebox(
			"hover", type, padded(box(panel.lerp(accent, 0.07), RADIUS_SM, accent_wash(0.4)), 14, 9)
		)
		theme.set_stylebox("pressed", type, padded(box(surface_alt, RADIUS_SM, line), 14, 9))
		theme.set_stylebox("focus", type, padded(focus_ring(RADIUS_SM), 14, 9))
		theme.set_stylebox("disabled", type, padded(box(surface_alt, RADIUS_SM, line), 14, 9))
		theme.set_color("font_color", type, text)
		theme.set_color("font_hover_color", type, text)
		theme.set_color("font_pressed_color", type, accent)
		theme.set_color("font_disabled_color", type, faint)

	theme.set_stylebox("panel", "PopupMenu", padded(floating(panel, RADIUS_SM, 18), 8))
	theme.set_color("font_color", "PopupMenu", text)
	theme.set_color("font_hover_color", "PopupMenu", accent)
	theme.set_stylebox("hover", "PopupMenu", padded(box(accent_wash(0.14), RADIUS_SM), 8, 4))

	theme.set_stylebox("panel", "Panel", box(panel, RADIUS_MD, line))
	theme.set_stylebox("panel", "PanelContainer", box(panel, RADIUS_MD, line))
	theme.set_stylebox("panel", "AcceptDialog", padded(box(backdrop_top, 0.0), 18))
	# Tooltips are launcher surfaces too, not the platform's stock grey popup.
	theme.set_stylebox(
		"panel", "TooltipPanel", padded(floating(surface, RADIUS_SM, 12), 12, 8)
	)
	theme.set_color("font_color", "TooltipLabel", on_surface)
	theme.set_font_size("font_size", "TooltipLabel", FONT_SMALL)
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
		theme.set_stylebox("focus", type, padded(focus_ring(RADIUS_SM), 4, 4))
		theme.set_icon("grabber", type, _knob(accent))
		theme.set_icon("grabber_highlight", type, _knob(accent.lightened(0.15)))
		theme.set_icon("grabber_disabled", type, _knob(faint))

	theme.set_stylebox("background", "ProgressBar", box(surface_alt, 4.0))
	theme.set_stylebox("fill", "ProgressBar", box(accent, 4.0))
	theme.set_stylebox("panel", "Tree", box(panel, RADIUS_SM, line))
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
			var colour: Color = panel if distance > centre - 3.5 else fill
			colour.a = clampf(centre - distance, 0.0, 1.0)
			image.set_pixel(x, y, colour)
	return ImageTexture.create_from_image(image)
