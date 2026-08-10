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
