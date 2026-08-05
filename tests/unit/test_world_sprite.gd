extends GutTest


func _sprite() -> Gen2WorldSprite:
	return Gen2WorldSprite.from_cache({
		"number": 1, "bytes": 192, "tiles": 12,
		"type": Gen2WorldSprite.TYPE_WALKING, "palette": 0,
	})


func test_walking_frames_use_down_up_left_and_flipped_right_groups() -> void:
	var sprite: Gen2WorldSprite = _sprite()
	assert_eq(sprite.frame_tile_offset(Gen2WorldSprite.FACING_DOWN, 0), 0)
	assert_eq(sprite.frame_tile_offset(Gen2WorldSprite.FACING_UP, 0), 4)
	assert_eq(sprite.frame_tile_offset(Gen2WorldSprite.FACING_LEFT, 0), 8)
	assert_eq(sprite.frame_tile_offset(Gen2WorldSprite.FACING_RIGHT, 0), 8)


func test_image_composition_applies_palette_and_transparency() -> void:
	var sprite: Gen2WorldSprite = Gen2WorldSprite.from_cache({
		"number": 1, "bytes": 64, "tiles": 4,
		"type": Gen2WorldSprite.TYPE_STILL, "palette": 0,
	})
	var indices := PackedByteArray()
	indices.resize(4 * Gen2Tiles.TILE_PIXELS)
	for index: int in indices.size():
		indices[index] = index % 4
	var palette := PackedColorArray([Color.WHITE, Color.RED, Color.BLUE, Color.BLACK])
	var image: Image = Gen2WorldSprite.image_for(sprite, indices, palette)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_eq(image.get_pixel(1, 0), Color.RED)
	assert_eq(image.get_pixel(2, 0), Color.BLUE)
	assert_eq(image.get_pixel(3, 0), Color.BLACK)
