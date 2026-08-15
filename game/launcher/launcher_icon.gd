class_name Gen2LauncherIcon
extends TextureRect

## The launcher's icon set, rasterised from SVG at the size it is drawn.
##
## Outlines come from Lucide (https://lucide.dev), ISC licensed; see
## `docs/THIRD_PARTY.md`. They are stored as path data rather than as files so a
## glyph can be recoloured per palette without shipping one image per tint.

## Lucide's own canvas and cap style. The stroke is a step over Lucide's own 2,
## because these are drawn small on a phone and read as hairlines at that size.
const GRID: int = 24
const STROKE: float = 2.4

## Path data only: `fill` icons carry their outline in the same `d` attribute.
const PATHS: Dictionary = {
	&"play": ["M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"],
	&"download": ["M12 15V3", "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4", "m7 10 5 5 5-5"],
	&"settings": [
		"M10 5H3", "M12 19H3", "M14 3v4", "M16 17v4", "M21 12h-9", "M21 19h-5", "M21 5h-7",
		"M8 10v4", "M8 12H3",
	],
	&"mods": [
		"M15.39 4.39a1 1 0 0 0 1.68-.474 2.5 2.5 0 1 1 3.014 3.015 1 1 0 0 0-.474 1.68l1.683"
		+ " 1.682a2.414 2.414 0 0 1 0 3.414L19.61 15.39a1 1 0 0 1-1.68-.474 2.5 2.5 0 1"
		+ " 0-3.014 3.015 1 1 0 0 1 .474 1.68l-1.683 1.682a2.414 2.414 0 0 1-3.414 0L8.61"
		+ " 19.61a1 1 0 0 0-1.68.474 2.5 2.5 0 1 1-3.014-3.015 1 1 0 0 0 .474-1.68l-1.683"
		+ "-1.682a2.414 2.414 0 0 1 0-3.414L4.39 8.61a1 1 0 0 1 1.68.474 2.5 2.5 0 1 0 3.014"
		+ "-3.015 1 1 0 0 1-.474-1.68l1.683-1.682a2.414 2.414 0 0 1 3.414 0z",
	],
	&"about": ["M12 16v-4", "M12 8h.01"],
	&"folder": [
		"m6 14 1.5-2.9A2 2 0 0 1 9.24 10H20a2 2 0 0 1 1.94 2.5l-1.54 6a2 2 0 0 1-1.95 1.5H4a2"
		+ " 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H18a2 2 0"
		+ " 0 1 2 2v2",
	],
	&"trash": [
		"M10 11v6", "M14 11v6", "M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6", "M3 6h18",
		"M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2",
	],
	&"refresh": [
		"M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8", "M21 3v5h-5",
		"M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16", "M8 16H3v5",
	],
	&"check": ["M20 6 9 17l-5-5"],
	&"warning": [
		"m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3", "M12 9v4",
		"M12 17h.01",
	],
	&"back": ["m12 19-7-7 7-7", "M19 12H5"],
	&"close": ["M18 6 6 18", "m6 6 12 12"],
	&"dots": ["M12 12h.01", "M19 12h.01", "M5 12h.01"],
	&"shelf": [
		"M17.32 5H6.68a4 4 0 0 0-3.978 3.59c-.006.052-.01.101-.017.152C2.604 9.416 2 14.456 2"
		+ " 16a3 3 0 0 0 3 3c1 0 1.5-.5 2-1l1.414-1.414A2 2 0 0 1 9.828 16h4.344a2 2 0 0 1"
		+ " 1.414.586L17 18c.5.5 1 1 2 1a3 3 0 0 0 3-3c0-1.545-.604-6.584-.685-7.258-.007-.05"
		+ "-.011-.1-.017-.151A4 4 0 0 0 17.32 5z",
		"M6 11h4", "M8 9v4", "M15 12h.01", "M18 10h.01",
	],
	&"plus": ["M5 12h14", "M12 5v14"],
	&"chevron": ["m9 18 6-6-6-6"],
	&"save": [
		"M15.2 3a2 2 0 0 1 1.4.6l3.8 3.8a2 2 0 0 1 .6 1.4V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2"
		+ " 2 0 0 1 2-2z",
		"M17 21v-7a1 1 0 0 0-1-1H8a1 1 0 0 0-1 1v7", "M7 3v4a1 1 0 0 0 1 1h7",
	],
	&"power": ["M12 2v10", "M18.4 6.6a9 9 0 1 1-12.77.04"],
}

## Icons that also carry a circle, which Lucide draws with its own element
## rather than as path data.
const CIRCLES: Dictionary = {
	&"about": [Vector2(12, 12), 10.0],
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
	var body: String = ""
	if CIRCLES.has(glyph):
		var ring: Array = CIRCLES[glyph]
		var centre: Vector2 = ring[0]
		body += '<circle cx="%s" cy="%s" r="%s"/>' % [centre.x, centre.y, ring[1]]
	for path: String in PATHS.get(glyph, []):
		body += '<path d="%s"/>' % path
	return (
		'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" fill="none"'
		+ ' stroke="#%s" stroke-width="%s" stroke-linecap="round"'
		+ ' stroke-linejoin="round">%s</svg>'
	) % [GRID, GRID, colour.to_html(false), STROKE, body]


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
