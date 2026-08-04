class_name Gen2WorldRenderer
extends Node2D

## Draws the visible map page and the development player marker in hardware
## pixels. It does not own map state; call [method set_world] when the API
## changes or [method refresh] after a movement.

var _palette: PackedColorArray = PackedColorArray([
	Color("#f5f1d8"), Color("#b6c7a2"), Color("#6f8f78"), Color("#273647"),
])
const PLAYER_COLOR: Color = Color("#d34a5a")
const BACKGROUND_COLOR: Color = Color("#f5f1d8")

var _world: Gen2WorldAPI = null
var _atlas: Texture2D = null


func set_world(world: Gen2WorldAPI) -> void:
	_world = world
	_atlas = null
	if _world != null and _world.data != null and _world.current_tileset != null:
		var indices: PackedByteArray = _world.data.world_tileset_indices(
			_world.current_tileset.number
		)
		var expected: int = _world.current_tileset.tile_count * Gen2Tiles.TILE_PIXELS
		if indices.size() >= expected:
			var image: Image = Gen2PicImage.from_indices(
				indices,
				_world.current_tileset.tile_count * Gen2Tiles.TILE_WIDTH,
				Gen2Tiles.TILE_HEIGHT,
				_palette,
			)
			_atlas = ImageTexture.create_from_image(image)
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(
		Rect2(Vector2.ZERO, Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)),
		BACKGROUND_COLOR,
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
