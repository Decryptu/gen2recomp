extends SceneTree

## Renders one imported map's expanded 4x4-tile blocks to a PNG.
##
##   Godot --headless --path . -s res://tools/preview_world.gd -- gold 1 1 /tmp/world.png

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("Usage: preview_world.gd -- <game> <group> <map> <output.png>")
		quit(1)
		return

	var data: GameData = GameData.open(StringName(args[0]))
	var map: Gen2WorldMap = data.world_map(int(args[1]), int(args[2])) if data != null else null
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset) if map != null else null
	if data == null or map == null or tileset == null:
		push_error("The requested imported map is not available.")
		quit(1)
		return

	var image: Image = _render(data, map, tileset)
	var error: int = image.save_png(args[3])
	if error != OK:
		push_error("Could not write %s (error %d)." % [args[3], error])
		quit(1)
		return

	print("Wrote %s (%dx%d), tileset %d, %d warps, %d objects." % [
		args[3], image.get_width(), image.get_height(), map.tileset,
		(map.events.get("warps", []) as Array).size(),
		(map.events.get("objects", []) as Array).size(),
	])
	quit(0)


func _render(data: GameData, map: Gen2WorldMap, tileset: Gen2WorldTileset) -> Image:
	var width: int = map.width_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH * Gen2Tiles.TILE_WIDTH
	var height: int = map.height_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH * Gen2Tiles.TILE_HEIGHT
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var pixels: PackedByteArray = data.world_tileset_indices(tileset.number)
	var atlas_width: int = tileset.tile_count * Gen2Tiles.TILE_WIDTH
	var palettes: Array = Gen2WorldPalette.tile_palettes(data, map, tileset)

	for tile_y: int in map.height_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH:
		for tile_x: int in map.width_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH:
			var block: int = map.block_at(tile_x >> 2, tile_y >> 2)
			var tile: int = tileset.tile_index(block, (tile_y & 3) * 4 + (tile_x & 3))
			for pixel_y: int in Gen2Tiles.TILE_HEIGHT:
				for pixel_x: int in Gen2Tiles.TILE_WIDTH:
					var color_index: int = 0
					var palette := PackedColorArray()
					if tile < tileset.tile_count:
						color_index = pixels[pixel_y * atlas_width + tile * 8 + pixel_x]
						palette = palettes[tile]
					var color: Color = palette[color_index] if color_index < palette.size() else Color.MAGENTA
					image.set_pixel(
						tile_x * 8 + pixel_x, tile_y * 8 + pixel_y,
						color
					)

	# Mark event coordinates in a restrained red so the screenshot shows that
	# geometry and event data come from the same imported map record.
	for event: Dictionary in map.events.get("warps", []):
		_draw_marker(image, int(event["x"]), int(event["y"]), Color("#d34a5a"))
	for event: Dictionary in map.events.get("objects", []):
		var x: int = int(event["x"])
		var y: int = int(event["y"])
		if x >= 0 and y >= 0 and x < map.collision_width and y < map.collision_height:
			_draw_marker(image, x, y, Color("#3e6ed8"))
	return image


func _draw_marker(image: Image, cell_x: int, cell_y: int, color: Color) -> void:
	var pixel_x: int = cell_x * 16 + 4
	var pixel_y: int = cell_y * 16 + 4
	for y: int in 8:
		for x: int in 8:
			if pixel_x + x < image.get_width() and pixel_y + y < image.get_height():
				image.set_pixel(pixel_x + x, pixel_y + y, color)
