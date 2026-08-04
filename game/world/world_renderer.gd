class_name Gen2WorldRenderer
extends Node2D

## Draws the visible map page and the development player marker in hardware
## pixels. It does not own map state; call [method set_world] when the API
## changes or [method refresh] after a movement.

const PLAYER_COLOR: Color = Color("#d34a5a")
const FALLBACK_BACKGROUND: Color = Color("#f5f1d8")

var _world: Gen2WorldAPI = null
var _animation: Gen2WorldAnimation = null
var _time_of_day: int = Gen2WorldPalette.TIME_MORNING
var _atlas: Texture2D = null
var _background_color: Color = FALLBACK_BACKGROUND


func set_world(world: Gen2WorldAPI, animation: Gen2WorldAnimation = null) -> void:
	_world = world
	_animation = animation
	_rebuild_atlas()
	queue_redraw()


func set_time_of_day(time_of_day: int) -> void:
	_time_of_day = clampi(time_of_day, 0, 3)
	_rebuild_atlas()
	queue_redraw()


func refresh_animation() -> void:
	_rebuild_atlas()
	queue_redraw()


func _rebuild_atlas() -> void:
	_atlas = null
	if _world == null or _world.data == null or _world.current_tileset == null:
		return
	var indices: PackedByteArray = _world.data.world_tileset_indices(_world.current_tileset.number)
	if _animation != null and not _animation.current_indices().is_empty():
		indices = _animation.current_indices()
	var palettes: Array = Gen2WorldPalette.tile_palettes(
		_world.data,
		_world.current_map,
		_world.current_tileset,
		_time_of_day,
		_animation.water_palette_color() if _animation != null else -1,
		_animation.cave_palette_color() if _animation != null else -1,
	)
	if not palettes.is_empty() and (palettes[0] as PackedColorArray).size() >= 1:
		_background_color = (palettes[0] as PackedColorArray)[0]
	else:
		_background_color = FALLBACK_BACKGROUND
	if indices.size() >= _world.current_tileset.tile_count * Gen2Tiles.TILE_PIXELS:
		var image: Image = _image_from_tiles(indices, palettes, _world.current_tileset.tile_count)
		_atlas = ImageTexture.create_from_image(image)


func _image_from_tiles(indices: PackedByteArray, palettes: Array, tile_count: int) -> Image:
	var width: int = tile_count * Gen2Tiles.TILE_WIDTH
	var image := Image.create(width, Gen2Tiles.TILE_HEIGHT, false, Image.FORMAT_RGBA8)
	for tile: int in tile_count:
		var palette: PackedColorArray = palettes[tile] if tile < palettes.size() else PackedColorArray()
		for y: int in Gen2Tiles.TILE_HEIGHT:
			for x: int in Gen2Tiles.TILE_WIDTH:
				var color_index: int = int(indices[y * width + tile * Gen2Tiles.TILE_WIDTH + x])
				var color: Color = palette[color_index] if color_index < palette.size() else _background_color
				image.set_pixel(tile * Gen2Tiles.TILE_WIDTH + x, y, color)
	return image


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(
		Rect2(Vector2.ZERO, Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)),
		_background_color,
		true,
	)
	if _world == null:
		return

	var page: PackedInt32Array = _world.visible_tile_indices()
	for y: int in Gen2WorldAPI.VIEW_TILES.y:
		for x: int in Gen2WorldAPI.VIEW_TILES.x:
			var tile: int = page[y * Gen2WorldAPI.VIEW_TILES.x + x]
			if _atlas == null or tile < 0 or tile >= _world.current_tileset.tile_count:
				continue
			draw_texture_rect_region(
				_atlas,
				Rect2(Vector2(x * Gen2Tiles.TILE_WIDTH, y * Gen2Tiles.TILE_HEIGHT), Vector2(8, 8)),
				Rect2(Vector2(tile * Gen2Tiles.TILE_WIDTH, 0), Vector2(8, 8)),
			)

	var player: Vector2i = _world.player_pixel_position()
	var marker := Rect2(Vector2(player.x, player.y), Vector2(16, 16))
	draw_rect(marker, PLAYER_COLOR, false, 1.0)
	draw_line(marker.position, marker.end, PLAYER_COLOR, 1.0)
	draw_line(Vector2(marker.end.x, marker.position.y), Vector2(marker.position.x, marker.end.y), PLAYER_COLOR, 1.0)
