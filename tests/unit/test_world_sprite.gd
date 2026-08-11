extends GutTest


func _sprite() -> Gen2WorldSprite:
	return Gen2WorldSprite.from_cache({
		"number": 1, "bytes": 384, "tiles": 24,
		"type": Gen2WorldSprite.TYPE_WALKING, "palette": 0,
	})


func test_walking_frames_use_down_up_left_and_flipped_right_groups() -> void:
	var sprite: Gen2WorldSprite = _sprite()
	assert_eq(sprite.frame_tile_offset(Gen2WorldSprite.FACING_DOWN, 0), 0)
	assert_eq(sprite.frame_tile_offset(Gen2WorldSprite.FACING_UP, 0), 4)
	assert_eq(sprite.frame_tile_offset(Gen2WorldSprite.FACING_LEFT, 0), 8)
	assert_eq(sprite.frame_tile_offset(Gen2WorldSprite.FACING_RIGHT, 0), 8)


## Facings gives each direction two standing frames and two walking ones, and
## the walking ones come from the second half of the strip: GetUsedSprite copies
## that half to vTiles1, which is the $80 those rows add to the base tile.
func test_the_two_walking_frames_come_from_the_second_half_of_the_strip() -> void:
	var sprite: Gen2WorldSprite = _sprite()
	for facing: int in [
		Gen2WorldSprite.FACING_DOWN, Gen2WorldSprite.FACING_UP, Gen2WorldSprite.FACING_LEFT,
	]:
		var standing: int = sprite.frame_tile_offset(facing, 0)
		assert_eq(sprite.frame_tile_offset(facing, 2), standing)
		assert_eq(sprite.frame_tile_offset(facing, 1), standing + 12)
		assert_eq(sprite.frame_tile_offset(facing, 3), standing + 12)
	assert_eq(sprite.frame_tile_offset(Gen2WorldSprite.FACING_RIGHT, 1), 20)


## FacingStepDown3 is FacingStepDown1 with OAM_XFLIP on every tile and its two
## columns swapped, which mirrors the whole 16x16. Left and right have no such
## pair: FacingStepLeft1 and FacingStepLeft3 are one label.
func test_frame_three_mirrors_down_and_up_but_not_left_or_right() -> void:
	assert_false(Gen2WorldSprite.frame_is_mirrored(Gen2WorldSprite.FACING_DOWN, 1))
	assert_true(Gen2WorldSprite.frame_is_mirrored(Gen2WorldSprite.FACING_DOWN, 3))
	assert_true(Gen2WorldSprite.frame_is_mirrored(Gen2WorldSprite.FACING_UP, 3))
	assert_false(Gen2WorldSprite.frame_is_mirrored(Gen2WorldSprite.FACING_LEFT, 3))
	assert_true(Gen2WorldSprite.frame_is_mirrored(Gen2WorldSprite.FACING_RIGHT, 0))
	assert_true(Gen2WorldSprite.frame_is_mirrored(Gen2WorldSprite.FACING_RIGHT, 3))


## A still sprite is one four-tile picture whatever it is asked for, and a
## standing sprite has no walking half to reach.
func test_a_still_sprite_answers_one_picture_for_every_frame() -> void:
	var still: Gen2WorldSprite = Gen2WorldSprite.from_cache({
		"number": 2, "bytes": 64, "tiles": 4,
		"type": Gen2WorldSprite.TYPE_STILL, "palette": 0,
	})
	assert_eq(still.frame_tile_offset(Gen2WorldSprite.FACING_UP, 3), 0)
	var standing: Gen2WorldSprite = Gen2WorldSprite.from_cache({
		"number": 3, "bytes": 192, "tiles": 12,
		"type": Gen2WorldSprite.TYPE_STANDING, "palette": 0,
	})
	assert_eq(standing.frame_tile_offset(Gen2WorldSprite.FACING_UP, 1), 4)


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


func test_symmetric_big_object_uses_the_source_sixteen_tile_layout() -> void:
	var sprite := Gen2WorldSprite.from_cache({"number": 33, "tiles": 8, "type": 3})
	var indices := PackedByteArray()
	indices.resize(8 * Gen2Tiles.TILE_PIXELS)
	for y: int in Gen2Tiles.TILE_HEIGHT:
		for tile: int in 8:
			for x: int in Gen2Tiles.TILE_WIDTH:
				indices[y * 8 * Gen2Tiles.TILE_WIDTH + tile * Gen2Tiles.TILE_WIDTH + x] = tile + 1
	var palette := PackedColorArray()
	palette.resize(9)
	for color: int in palette.size():
		palette[color] = Color(float(color) / 8.0, 0.0, 0.0, 1.0)
	var image := Gen2WorldSprite.big_image_for(
		sprite, indices, palette, Gen2WorldSprite.BIG_SHAPE_SYMMETRIC
	)
	assert_eq(image.get_size(), Vector2i(32, 32))
	assert_almost_eq(image.get_pixel(1, 1).r, palette[1].r, 0.01)
	assert_almost_eq(image.get_pixel(9, 1).r, palette[3].r, 0.01)
	assert_almost_eq(image.get_pixel(1, 25).r, palette[1].r, 0.01)
	assert_almost_eq(image.get_pixel(25, 25).r, palette[7].r, 0.01)


func test_asymmetric_big_object_keeps_source_holes_and_flips() -> void:
	var sprite := Gen2WorldSprite.from_cache({"number": 0, "tiles": 12, "type": 3})
	var indices := PackedByteArray()
	indices.resize(12 * Gen2Tiles.TILE_PIXELS)
	for y: int in Gen2Tiles.TILE_HEIGHT:
		for tile: int in 12:
			for x: int in Gen2Tiles.TILE_WIDTH:
				indices[y * 12 * Gen2Tiles.TILE_WIDTH + tile * Gen2Tiles.TILE_WIDTH + x] = tile + 1
	var palette := PackedColorArray()
	palette.resize(13)
	for color: int in palette.size():
		palette[color] = Color(float(color) / 12.0, 0.0, 0.0, 1.0)
	var image := Gen2WorldSprite.big_image_for(
		sprite, indices, palette, Gen2WorldSprite.BIG_SHAPE_ASYMMETRIC
	)
	assert_eq(image.get_pixel(24, 0).a, 0.0)
	assert_almost_eq(image.get_pixel(8, 24).r, palette[3].r, 0.01)
	assert_almost_eq(image.get_pixel(15, 24).r, palette[3].r, 0.01)


func test_pokemon_sprite_bytes_resolve_to_the_source_icon_shape() -> void:
	assert_eq(Gen2WorldSprite.mon_icon_for_sprite(Gen2WorldSprite.SPRITE_POKEMON), 25)
	assert_eq(Gen2WorldSprite.mon_icon_for_sprite(0x82), 15)
	assert_eq(Gen2WorldSprite.mon_icon_for_sprite(0xA2), 33)
	assert_eq(Gen2WorldSprite.mon_icon_for_sprite(0x7F), 0)


func test_big_doll_shape_follows_the_source_sprite_selection() -> void:
	var snorlax := Gen2WorldObject.from_event(0, {
		"sprite": 33, "movement": Gen2WorldObject.MOVEMENT_BIGDOLL,
	})
	var onix := Gen2WorldObject.from_event(1, {
		"sprite": 50, "movement": Gen2WorldObject.MOVEMENT_BIGDOLL,
	})
	assert_eq(snorlax.big_object_shape(), Gen2WorldSprite.BIG_SHAPE_SYMMETRIC)
	assert_eq(onix.big_object_shape(), Gen2WorldSprite.BIG_SHAPE_ASYMMETRIC)
