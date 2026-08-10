extends SceneTree

## Draws a whole map as the game draws it, with every walk cell's permission
## checkerboarded over the top: red for WALL, blue for WATER, nothing for LAND.
##
## For a report that a player can stand somewhere they should not. The art and
## the permission come from the same two sources the runtime reads, the map's
## block grid and the tileset's four-bytes-per-block collision table, so a wall
## drawn without a red square is a real disagreement between what is drawn and
## what is walked, rather than a rendering offset.
##
## Objects are not drawn: this is the map's own answer. Use
## `Gen2WorldAPI.active_objects()` for who is standing on it.
##
##   Godot --headless --path . -s res://tools/preview_collision.gd -- crystal 26 2 /tmp/route31.png

const SCALE: int = 3
const WALL_TINT: Color = Color(1.0, 0.0, 0.0, 0.75)
const WATER_TINT: Color = Color(0.1, 0.3, 1.0, 0.35)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("Usage: -s tools/preview_collision.gd -- <game> <group> <number> <output.png>")
		quit(1)
		return
	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return
	var group: int = int(args[1])
	var number: int = int(args[2])
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, group, number, Vector2i.ZERO)
	if world == null:
		push_error("No map %d/%d in %s." % [group, number, args[0]])
		quit(1)
		return

	var map: Gen2WorldMap = world.current_map
	var tileset: Gen2WorldTileset = world.current_tileset
	var indices: PackedByteArray = data.world_tileset_indices(tileset.number)
	var palettes: Array = Gen2WorldPalette.tile_palettes(
		data, map, tileset, Gen2WorldPalette.TIME_DAY, -1, -1
	)
	var strip_width: int = tileset.tile_count * Gen2Tiles.TILE_WIDTH
	var image := Image.create(
		map.collision_width * 16, map.collision_height * 16, false, Image.FORMAT_RGBA8
	)

	for tile_y: int in map.height_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH:
		for tile_x: int in map.width_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH:
			@warning_ignore("integer_division")
			var block: int = map.block_at(
				tile_x / RomLayout.MAP_BLOCK_TILE_WIDTH, tile_y / RomLayout.MAP_BLOCK_TILE_WIDTH
			)
			var tile: int = tileset.tile_index(
				block, (tile_y % 4) * RomLayout.MAP_BLOCK_TILE_WIDTH + (tile_x % 4)
			)
			var palette: PackedColorArray = palettes[tile] if tile < palettes.size() \
				else PackedColorArray()
			for y: int in Gen2Tiles.TILE_HEIGHT:
				for x: int in Gen2Tiles.TILE_WIDTH:
					var index: int = int(indices[y * strip_width + tile * 8 + x])
					image.set_pixel(
						tile_x * 8 + x, tile_y * 8 + y,
						palette[index] if index < palette.size() else Color.MAGENTA
					)

	for cell_y: int in map.collision_height:
		for cell_x: int in map.collision_width:
			var permission: int = world.collision_permission_at(Vector2i(cell_x, cell_y))
			var tint := Color(0, 0, 0, 0)
			if permission == Gen2WorldCollision.WALL_TILE:
				tint = WALL_TINT
			elif permission == Gen2WorldCollision.WATER_TILE:
				tint = WATER_TINT
			if tint.a == 0.0:
				continue
			for y: int in 16:
				for x: int in 16:
					# A four-pixel checker, so the art underneath stays readable.
					if ((x >> 2) + (y >> 2)) % 2 != 0:
						continue
					var at := Vector2i(cell_x * 16 + x, cell_y * 16 + y)
					image.set_pixel(at.x, at.y, image.get_pixel(at.x, at.y).lerp(tint, tint.a))

	image.resize(image.get_width() * SCALE, image.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	if image.save_png(args[3]) != OK:
		push_error("Could not write %s" % args[3])
		quit(1)
		return
	print("%s map %d/%d: %d by %d cells." % [
		args[0], group, number, map.collision_width, map.collision_height,
	])
	quit(0)
