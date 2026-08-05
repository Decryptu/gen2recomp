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
var _actor_textures: Dictionary = {}


func set_world(world: Gen2WorldAPI, animation: Gen2WorldAnimation = null) -> void:
	_world = world
	_animation = animation
	_actor_textures.clear()
	_rebuild_atlas()
	queue_redraw()


func set_time_of_day(time_of_day: int) -> void:
	_time_of_day = clampi(time_of_day, 0, 3)
	if _world != null:
		_world.set_object_time(_world.object_hour, _time_of_day)
	_actor_textures.clear()
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

	var actors: Array = _world.visible_objects()
	actors.sort_custom(_sort_objects)
	for object: Gen2WorldObject in actors:
		var pixel: Vector2i = (object.cell - _world.visible_origin_cell()) * Gen2WorldAPI.CELL_PIXELS
		var texture: Texture2D = _actor_texture(object.sprite, object.palette, object.facing, object.frame)
		if texture != null:
			draw_texture(texture, Vector2(pixel))

	var player: Vector2i = _world.player_pixel_position()
	var player_texture: Texture2D = _actor_texture(
		_world.player_sprite(), 0, _world.player_facing, 0
	)
	if player_texture != null:
		draw_texture(player_texture, Vector2(player))
	else:
		var marker := Rect2(Vector2(player.x, player.y), Vector2(16, 16))
		draw_rect(marker, PLAYER_COLOR, false, 1.0)
		draw_line(marker.position, marker.end, PLAYER_COLOR, 1.0)
		draw_line(Vector2(marker.end.x, marker.position.y), Vector2(marker.position.x, marker.end.y), PLAYER_COLOR, 1.0)


func _actor_texture(
	sprite: Gen2WorldSprite,
	palette_override: int,
	facing: int,
	frame: int,
) -> Texture2D:
	if sprite == null or _world == null or _world.data == null:
		return null
	var palette: int = palette_override if palette_override != 0 else sprite.default_palette
	var key: String = "%d:%d:%d:%d:%d" % [sprite.number, palette, facing, frame, _time_of_day]
	if _actor_textures.has(key):
		return _actor_textures[key]
	var indices: PackedByteArray = _world.data.overworld_sprite_indices(sprite.number)
	var colors: PackedColorArray = _world.data.overworld_sprite_palette(palette, _time_of_day)
	var image: Image = Gen2WorldSprite.image_for(sprite, indices, colors, facing, frame)
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_actor_textures[key] = texture
	return texture


func _sort_objects(first: Gen2WorldObject, second: Gen2WorldObject) -> bool:
	if first.cell.y == second.cell.y:
		return first.index < second.index
	return first.cell.y < second.cell.y
