class_name Gen2LauncherIcon
extends TextureRect

## The launcher's custom filled icon set, rasterised from SVG at the size it is
## drawn. Source SVGs remain editable in `assets/launcher/icons`; their
## `currentColor` fill is replaced with the active palette colour at runtime.
const GRID: int = 24

const ICON_DIRECTORY: String = "res://assets/launcher/icons"
const PATHS: Dictionary = {
	&"about": "about.svg",
	&"back": "back.svg",
	&"check": "check.svg",
	&"chevron": "chevron.svg",
	&"close": "close.svg",
	&"dots": "dots.svg",
	&"download": "download.svg",
	&"folder": "folder.svg",
	&"mods": "mods.svg",
	&"play": "play.svg",
	&"plus": "plus.svg",
	&"power": "power.svg",
	&"refresh": "refresh.svg",
	&"refresh_square": "refresh-square.svg",
	&"save": "save.svg",
	&"settings": "settings.svg",
	&"shelf": "shelf.svg",
	&"trash": "trash.svg",
	&"warning": "warning.svg",
}

## Rasterised once per glyph, size and tint, because the launcher rebuilds its
## whole tree on a palette change and would otherwise re-parse every path.
static var _cache: Dictionary = {}


static func create(glyph: StringName, side: float, colour: Color) -> Gen2LauncherIcon:
	var icon := Gen2LauncherIcon.new()
	icon.custom_minimum_size = Vector2(side, side)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# The raster is drawn at twice its size, which would otherwise be the
	# minimum this node reports.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.set_glyph(glyph, side, colour)
	return icon


## The same drawing as a plain texture, for the places Godot wants an icon
## rather than a node: window titles, tree cells and stock buttons.
static func raster(glyph: StringName, side: float, colour: Color) -> Texture2D:
	var key: String = "%s|%d|%s" % [glyph, int(side), colour.to_html()]
	if _cache.has(key):
		return _cache[key]
	var image: Image = Image.new()
	# Rendered at twice the drawn size: the launcher scales with the window, and
	# a stroke resampled up from its exact size frays.
	var error: int = image.load_svg_from_string(_svg(glyph, colour), side * 2.0 / float(GRID))
	if error != OK or image.is_empty():
		return null
	var made: ImageTexture = ImageTexture.create_from_image(image)
	_cache[key] = made
	return made


static func _svg(glyph: StringName, colour: Color) -> String:
	var filename: String = PATHS.get(glyph, "")
	if filename.is_empty():
		return ""
	var source: String = FileAccess.get_file_as_string("%s/%s" % [ICON_DIRECTORY, filename])
	return source.replace("currentColor", "#%s" % colour.to_html(false))


var glyph: StringName = &""
var tint: Color = Color.WHITE
var side: float = 24.0


func set_glyph(name: StringName, drawn_side: float, colour: Color) -> void:
	glyph = name
	tint = colour
	side = drawn_side
	custom_minimum_size = Vector2(drawn_side, drawn_side)
	texture = Gen2LauncherIcon.raster(name, drawn_side, colour)



## Whether a name is one the set actually draws, so a typo fails a test rather
## than silently drawing nothing.
static func has_glyph(name: StringName) -> bool:
	return PATHS.has(name)
