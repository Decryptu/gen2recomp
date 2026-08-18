class_name Gen2LauncherIcon
extends TextureRect

## The launcher's custom filled icon set, rasterised from SVG at the size it is
## drawn. Source SVGs remain editable in `assets/launcher/icons`; their
## `currentColor` fill is replaced with the active palette colour at runtime.
##
## Each source carries `importer="keep"`, because this reads the SVG text rather
## than the texture Godot's own SVG importer makes: an imported `.svg` ships as
## its `.ctex` alone, so `_svg()` came back empty on every exported build and
## every glyph drew nothing. `test_launcher_ui.gd` asserts the importer.
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
	var source: String = _svg(glyph, colour)
	var error: int = OK if source.is_empty() else image.load_svg_from_string(
		source, side * 2.0 / float(GRID)
	)
	if source.is_empty() or error != OK or image.is_empty():
		# A TextureRect with no texture looks exactly like one that was never
		# asked for, so say which glyph failed rather than draw a hole.
		push_warning("Launcher icon '%s' did not rasterise (error %d)." % [glyph, error])
		return null
	var made: ImageTexture = ImageTexture.create_from_image(image)
	_cache[key] = made
	return made


## The file the glyph is drawn from, so a check can reach it without repeating
## the layout of `PATHS`.
static func source_path(glyph: StringName) -> String:
	var filename: String = PATHS.get(glyph, "")
	return "" if filename.is_empty() else "%s/%s" % [ICON_DIRECTORY, filename]


static func _svg(glyph: StringName, colour: Color) -> String:
	if source_path(glyph).is_empty():
		return ""
	var source: String = FileAccess.get_file_as_string(source_path(glyph))
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
