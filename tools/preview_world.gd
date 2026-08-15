extends SceneTree

## Renders one imported map's expanded 4x4-tile blocks to a PNG.
##
##   Godot --headless --path . -s res://tools/preview_world.gd -- gold 1 1 /tmp/world.png
##
## A fifth `live` argument photographs the real screen on that map instead, with
## the sprites the engine draws over an object staged on it: an emote over the
## first visible object, the boulder dust, the grass rustle and the headbutt
## tree. That mode drives the screen's own path and needs a display, so it runs
## without `--headless`:
##
##   Godot --path . -s res://tools/preview_world.gd -- crystal 26 2 /tmp/out.png live [kind] [x y]
##
## `kind` is `effects` (the emote, the dust, the rustle and the headbutt tree),
## `cut` (`OWCutAnimation`'s two halves and the jump shadow) or `field_item` (the
## pack's own USE on the Itemfinder, which closes the pack over the world's
## answer). The two numbers are the cell the player stands on, which is how the
## grass a standing object is drawn behind is photographed.

const WINDOW_SIZE := Vector2i(1152, 648)
## Hardware frames spent after the sprites are staged. Two puts the grass rustle
## on its first facing and the boulder dust on its second, so every one of them
## is up and none is on the frame it was spawned. Cut needs more: its tree stands
## for three frames before it splits, and its leaves open on top of each other.
const STAGED_FRAMES: int = 2
const STAGED_FRAMES_CUT: int = 12

var _screen: Gen2WorldScreen = null
var _output_path: String = ""
var _frames: int = 0
var _kind: StringName = &"effects"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("Usage: preview_world.gd -- <game> <group> <map> <output.png> [live]")
		quit(1)
		return

	var data: GameData = GameData.open(StringName(args[0]))
	if args.size() >= 5 and args[4] == "live":
		if data == null:
			push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
			quit(1)
			return
		_output_path = args[3]
		_kind = StringName(args[5]) if args.size() >= 6 else &"effects"
		_build_live(
			data, int(args[1]), int(args[2]),
			Vector2i(int(args[6]), int(args[7])) if args.size() >= 8 else Vector2i(-1, -1),
		)
		return
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


## The production screen on a real map, with every effect sprite running at
## once. Each is started through the same call the game makes, so what is
## photographed is the renderer's own path rather than a drawing of it.
func _build_live(data: GameData, group: int, number: int, cell: Vector2i) -> void:
	root.set_content_scale_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_screen = packed.instantiate() as Gen2WorldScreen
	_screen.map_group = group
	_screen.map_number = number
	if cell.x >= 0:
		_screen.start_cell = cell
	## Pinned so two captures of the same map are the same picture: the seed the
	## screen resolves is what a wandering NPC's own generator is built from.
	_screen.encounter_seed = 1
	_screen.set_data(data)
	root.add_child(_screen)
	current_scene = _screen
	## The screen counts hardware frames off wall-clock delta, so a capture that
	## let it run would photograph a different frame of each animation every
	## time. It owns none of them here: the staged frames below are spent by
	## hand.
	_screen.set_process(false)


func _process(_delta: float) -> bool:
	if _screen == null:
		return false
	_frames += 1
	if _frames == 2:
		if _kind == &"field_item":
			_screen.preview_field_item()
		else:
			_screen.preview_effect_sprites(_kind)
		for _frame: int in (STAGED_FRAMES_CUT if _kind == &"cut" else STAGED_FRAMES):
			_screen.advance_frame()
	if _frames < 18:
		return false
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(_output_path)
	if error != OK:
		push_error("Could not write %s (error %d)" % [_output_path, error])
		quit(1)
		return true
	print("Wrote %s (%dx%d)" % [_output_path, image.get_width(), image.get_height()])
	quit(0)
	return true


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
