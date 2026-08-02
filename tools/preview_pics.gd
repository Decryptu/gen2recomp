extends SceneTree

## Renders an imported pic atlas or tile sheet to a PNG so it can be looked at.
##
##   Godot --headless --path . -s res://tools/preview_pics.gd -- <game> <out.png> [what] [--shiny]
##
## e.g. gold /tmp/gold_front.png front
##
## The cache stores colour indices, not pixels; a palette is applied at draw
## time so that shiny is free. This applies one and writes the result out, which
## is the only way to tell a correct decode from a plausible-looking wrong one.
## Runs headless: it writes an image, it does not open a window.
##
## The font and the borders come out too. They are one row of tiles rather than
## a grid, so the font is folded to sixteen tiles a row on the way out: that is
## the shape the charmap describes, and it puts the alphabets, the gaps between
## them and the digits where they can be read at a glance.

const ATLASES: PackedStringArray = ["front", "back", "unown_front", "unown_back", "trainers"]
const SHEETS: PackedStringArray = ["font", "frames"]

## Tiles per row when a strip is folded for viewing.
const SHEET_COLUMNS: int = 16


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var shiny: bool = args.has("--shiny")

	var positional: PackedStringArray = []
	for arg: String in args:
		if not arg.begins_with("--"):
			positional.append(arg)

	if positional.size() < 2:
		push_error("Usage: <game> <out.png> [%s|%s] [--shiny]" % [
			"|".join(ATLASES), "|".join(SHEETS),
		])
		quit(1)
		return

	var game: StringName = StringName(positional[0])
	var out_path: String = positional[1]
	var atlas_name: String = positional[2] if positional.size() > 2 else "front"

	var directory: String = _find_cache(game)
	if directory.is_empty():
		push_error("No cache for %s. Run tools/import_rom.gd first." % game)
		quit(1)
		return

	var manifest: Dictionary = RomCache.read_manifest(directory)
	var atlases: Dictionary = manifest.get("atlases", {})
	var sheets: Dictionary = manifest.get("tiles", {})

	var image: Image = null
	if sheets.has(atlas_name):
		image = _render_sheet(directory, sheets[atlas_name], atlas_name)
	elif atlases.has(atlas_name):
		image = _render(directory, manifest, atlases[atlas_name], atlas_name, shiny)
	else:
		push_error("Nothing named %s in this cache." % atlas_name)
		quit(1)
		return

	if image == null:
		quit(1)
		return

	if image.save_png(out_path) != OK:
		push_error("Could not write %s." % out_path)
		quit(1)
		return

	print("%s %s%s -> %s (%dx%d)" % [
		game, atlas_name, " shiny" if shiny else "", out_path,
		image.get_width(), image.get_height(),
	])
	quit(0)


func _find_cache(game: StringName) -> String:
	var sha1: String = RomRegistry.sha1_for(game)
	if sha1.is_empty():
		return ""
	var directory: String = RomCache.directory_for(game, sha1)
	return directory if RomCache.is_usable(directory) else ""


## A 1bpp strip, folded into rows of [constant SHEET_COLUMNS] tiles. There is no
## palette to choose: 1bpp graphics are black on white and nothing else.
func _render_sheet(directory: String, sheet: Dictionary, name: String) -> Image:
	var indices: PackedByteArray = RomCache.read_indices(RomCache.tile_path(directory, name))
	var strip_width: int = int(sheet["width"])
	var tiles: int = int(sheet["tiles"])
	if indices.size() != strip_width * int(sheet["height"]):
		push_error("%s holds %d bytes, expected %d." % [
			name, indices.size(), strip_width * int(sheet["height"]),
		])
		return null

	var columns: int = mini(SHEET_COLUMNS, tiles)
	var rows: int = ceili(float(tiles) / columns)
	var width: int = columns * Gen2Tiles.TILE_WIDTH
	var folded: PackedByteArray = PackedByteArray()
	folded.resize(width * rows * Gen2Tiles.TILE_HEIGHT)

	for tile: int in tiles:
		@warning_ignore("integer_division")
		var at_y: int = (tile / columns) * Gen2Tiles.TILE_HEIGHT
		var at_x: int = (tile % columns) * Gen2Tiles.TILE_WIDTH
		for y: int in Gen2Tiles.TILE_HEIGHT:
			var from: int = y * strip_width + tile * Gen2Tiles.TILE_WIDTH
			var to: int = (at_y + y) * width + at_x
			for x: int in Gen2Tiles.TILE_WIDTH:
				folded[to + x] = indices[from + x]

	return Gen2PicImage.from_indices(
		folded, width, rows * Gen2Tiles.TILE_HEIGHT,
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	)


func _render(
	directory: String, manifest: Dictionary, atlas: Dictionary, name: String, shiny: bool
) -> Image:
	var indices: PackedByteArray = RomCache.read_indices(RomCache.pic_path(directory, name))
	var width: int = int(atlas["width"])
	var height: int = int(atlas["height"])
	if indices.size() != width * height:
		push_error("%s holds %d bytes, expected %d." % [name, indices.size(), width * height])
		return null

	var cell: int = int(atlas["cell"])
	var columns: int = int(atlas["columns"])
	var palettes: Array = _palettes(directory, name, shiny)
	if palettes.is_empty():
		push_error("No palettes for %s." % name)
		return null

	var image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for y: int in height:
		for x: int in width:
			var slot: int = (y / cell) * columns + (x / cell)
			var palette: PackedColorArray = palettes[mini(slot, palettes.size() - 1)]
			image.set_pixel(x, y, palette[indices[y * width + x]])

	return image


## One palette per cell of an atlas, in slot order.
##
## The three kinds of atlas are indexed differently: a species atlas by species,
## the trainer atlas by class, and Unown's by letter form, all twenty-six of
## which are the one species and so share its colours.
func _palettes(directory: String, name: String, shiny: bool) -> Array:
	var out: Array = []

	if name == "trainers":
		for entry: Dictionary in RomCache.read_json(RomCache.trainers_path(directory)):
			out.append(_palette_of(entry["palette"]))
		return out

	var species: Array = RomCache.read_json(RomCache.species_path(directory))
	var key: String = "shiny" if shiny else "normal"
	if name.begins_with("unown"):
		var unown: Dictionary = species[RomLayout.UNOWN_SPECIES - 1]
		for form: int in RomLayout.UNOWN_FORMS:
			out.append(_palette_of(unown["palette"][key]))
		return out

	for entry: Dictionary in species:
		out.append(_palette_of(entry["palette"][key]))
	return out


func _palette_of(packed: Array) -> PackedColorArray:
	return Gen2Palette.pic_palette(PackedColorArray([
		Gen2Palette.from_packed(int(packed[0])),
		Gen2Palette.from_packed(int(packed[1])),
	]))
