extends SceneTree

## Renders an imported pic atlas to a PNG so it can be looked at.
##
##   Godot --headless --path . -s res://tools/preview_pics.gd -- <game> <out.png> [atlas] [--shiny]
##
## e.g. gold /tmp/gold_front.png front
##
## The cache stores colour indices, not pixels; a palette is applied at draw
## time so that shiny is free. This applies one and writes the result out, which
## is the only way to tell a correct decode from a plausible-looking wrong one.
## Runs headless: it writes an image, it does not open a window.

const ATLASES: PackedStringArray = ["front", "back", "unown_front", "unown_back"]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var shiny: bool = args.has("--shiny")

	var positional: PackedStringArray = []
	for arg: String in args:
		if not arg.begins_with("--"):
			positional.append(arg)

	if positional.size() < 2:
		push_error("Usage: <game> <out.png> [%s] [--shiny]" % "|".join(ATLASES))
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
	if not atlases.has(atlas_name):
		push_error("No atlas named %s." % atlas_name)
		quit(1)
		return

	var image: Image = _render(directory, manifest, atlases[atlas_name], atlas_name, shiny)
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


func _render(
	directory: String, manifest: Dictionary, atlas: Dictionary, name: String, shiny: bool
) -> Image:
	var indices: PackedByteArray = RomCache.read_indices(RomCache.pic_path(directory, name))
	var width: int = int(atlas["width"])
	var height: int = int(atlas["height"])
	if indices.size() != width * height:
		push_error("%s holds %d bytes, expected %d." % [name, indices.size(), width * height])
		return null

	var species: Array = RomCache.read_json(RomCache.species_path(directory))
	var cell: int = int(atlas["cell"])
	var columns: int = int(atlas["columns"])
	var key: String = "shiny" if shiny else "normal"

	var image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for y: int in height:
		for x: int in width:
			var slot: int = (y / cell) * columns + (x / cell)
			# Unown's atlas is one cell per letter, all of them the same species.
			var entry: Dictionary = species[
				RomLayout.UNOWN_SPECIES - 1 if name.begins_with("unown") else mini(slot, species.size() - 1)
			]
			var packed: Array = entry["palette"][key]
			var palette: PackedColorArray = Gen2Palette.pic_palette(PackedColorArray([
				Gen2Palette.from_packed(int(packed[0])),
				Gen2Palette.from_packed(int(packed[1])),
			]))
			image.set_pixel(x, y, palette[indices[y * width + x]])

	return image
