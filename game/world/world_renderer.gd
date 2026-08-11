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
var _atlas: ImageTexture = null
## Kept beside the texture so an animation frame can repaint the one or two
## tiles it rewrote instead of recolouring the whole strip.
var _atlas_image: Image = null
var _background_color: Color = FALLBACK_BACKGROUND
var _actor_textures: Dictionary = {}


func set_world(world: Gen2WorldAPI, animation: Gen2WorldAnimation = null) -> void:
	_world = world
	_animation = animation
	_actor_textures.clear()
	_rebuild_atlas()
	queue_redraw()


## Selects the palette rows this view draws with. The world owns the clock and
## object visibility; a renderer only reads them, so a second view of the same
## world cannot change what the first one sees.
func set_time_of_day(time_of_day: int) -> void:
	_time_of_day = clampi(time_of_day, 0, 3)
	_actor_textures.clear()
	_rebuild_atlas()
	queue_redraw()


## Repaints the tiles the last animation frame rewrote.
##
## The sequence touches one or two of a tileset's tiles per frame, so recolouring
## the whole strip was almost all of the frame's cost. A palette
## command is the exception: it changes every tile drawn with that row, so it
## still rebuilds.
func refresh_animation() -> void:
	if _animation == null or _atlas == null or _atlas_image == null \
		or _animation.palette_changed():
		_rebuild_atlas()
		queue_redraw()
		return
	var changed: PackedInt32Array = _animation.changed_tiles()
	if changed.is_empty():
		return
	var indices: PackedByteArray = _animation.current_indices()
	var palettes: Array = _tile_palettes()
	for tile: int in changed:
		_paint_tile(_atlas_image, indices, palettes, tile)
	_atlas.update(_atlas_image)
	queue_redraw()


func _rebuild_atlas() -> void:
	_atlas = null
	_atlas_image = null
	if _world == null or _world.data == null or _world.current_tileset == null:
		return
	var indices: PackedByteArray = _world.data.world_tileset_indices(_world.current_tileset.number)
	if _animation != null and not _animation.current_indices().is_empty():
		indices = _animation.current_indices()
	var palettes: Array = _tile_palettes()
	if not palettes.is_empty() and (palettes[0] as PackedColorArray).size() >= 1:
		_background_color = (palettes[0] as PackedColorArray)[0]
	else:
		_background_color = FALLBACK_BACKGROUND
	var tile_count: int = _world.current_tileset.tile_count
	if indices.size() < tile_count * Gen2Tiles.TILE_PIXELS:
		return
	_atlas_image = Image.create(
		tile_count * Gen2Tiles.TILE_WIDTH, Gen2Tiles.TILE_HEIGHT, false, Image.FORMAT_RGBA8
	)
	for tile: int in tile_count:
		_paint_tile(_atlas_image, indices, palettes, tile)
	_atlas = ImageTexture.create_from_image(_atlas_image)


func _tile_palettes() -> Array:
	return Gen2WorldPalette.tile_palettes(
		_world.data,
		_world.current_map,
		_world.current_tileset,
		_time_of_day,
		_animation.water_palette_color() if _animation != null else -1,
		_animation.cave_palette_color() if _animation != null else -1,
	)


## One tile of the strip, coloured. Index 0 is a colour here rather than a hole:
## the atlas is the background layer, and the cartridge's transparent index
## belongs to sprites.
func _paint_tile(image: Image, indices: PackedByteArray, palettes: Array, tile: int) -> void:
	var width: int = image.get_width()
	var palette: PackedColorArray = palettes[tile] if tile < palettes.size() else PackedColorArray()
	var left: int = tile * Gen2Tiles.TILE_WIDTH
	for y: int in Gen2Tiles.TILE_HEIGHT:
		var row: int = y * width + left
		for x: int in Gen2Tiles.TILE_WIDTH:
			var color_index: int = indices[row + x]
			image.set_pixel(
				left + x, y,
				palette[color_index] if color_index < palette.size() else _background_color
			)


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

	var camera_pixels: Vector2 = _world.visible_origin_cells() * Gen2WorldAPI.CELL_PIXELS
	var tile_origin := Vector2i(
		floori(camera_pixels.x / float(Gen2Tiles.TILE_WIDTH)),
		floori(camera_pixels.y / float(Gen2Tiles.TILE_HEIGHT)),
	)
	var tile_offset: Vector2 = camera_pixels - Vector2(
		tile_origin.x * Gen2Tiles.TILE_WIDTH,
		tile_origin.y * Gen2Tiles.TILE_HEIGHT,
	)
	var window_size: Vector2i = Gen2WorldAPI.VIEW_TILES + Vector2i.ONE
	var page: PackedInt32Array = _world.tile_indices_in_window(tile_origin, window_size)
	for y: int in window_size.y:
		for x: int in window_size.x:
			var tile: int = page[y * window_size.x + x]
			if _atlas == null or tile < 0 or tile >= _world.current_tileset.tile_count:
				continue
			draw_texture_rect_region(
				_atlas,
				Rect2(
					Vector2(x * Gen2Tiles.TILE_WIDTH, y * Gen2Tiles.TILE_HEIGHT) - tile_offset,
					Vector2(8, 8),
				),
				Rect2(Vector2(tile * Gen2Tiles.TILE_WIDTH, 0), Vector2(8, 8)),
			)

	var actors: Array = _world.visible_objects()
	actors.sort_custom(_sort_objects)
	for object: Gen2WorldObject in actors:
		var pixel: Vector2 = Vector2(object.cell * Gen2WorldAPI.CELL_PIXELS) \
			+ Vector2(object.step_offset(Gen2WorldAPI.CELL_PIXELS)) - camera_pixels
		var texture: Texture2D = _actor_texture(object.sprite, object.palette, object.facing, object.frame)
		if texture != null:
			draw_texture(texture, pixel)
		if object.emote_visible:
			_draw_emote(object.emote_id, pixel)

	var player: Vector2 = Vector2(_world.player_pixel_position())
	var player_texture: Texture2D = _actor_texture(
		_world.player_sprite(), _world.player_palette(), _world.player_facing,
		_world.player_walk_frame()
	)
	if player_texture != null:
		draw_texture(player_texture, player)
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


func _draw_emote(emote_id: int, pixel: Vector2) -> void:
	var bubble := Rect2(pixel + Vector2(4, -10), Vector2(8, 8))
	draw_rect(bubble, Color("#fff8d6"), true)
	draw_rect(bubble, Color("#18243a"), false, 1.0)
	draw_colored_polygon(
		PackedVector2Array([
			pixel + Vector2(6, -2), pixel + Vector2(8, 2), pixel + Vector2(10, -2),
		]),
		Color("#fff8d6")
	)
	var style: int = posmod(emote_id, 3)
	if style == 0:
		draw_circle(pixel + Vector2(8, -6), 2.0, Color("#d34a5a"))
	elif style == 1:
		draw_line(pixel + Vector2(6, -8), pixel + Vector2(10, -4), Color("#3d6fd6"), 1.5)
		draw_line(pixel + Vector2(10, -8), pixel + Vector2(6, -4), Color("#3d6fd6"), 1.5)
	else:
		draw_rect(Rect2(pixel + Vector2(6, -8), Vector2(4, 4)), Color("#d69b2f"), true)
