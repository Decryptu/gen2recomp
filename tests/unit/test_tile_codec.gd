extends GutTest

## 2bpp decoding and pic layout, on hand-built tiles.


func _solid_tile(index: int) -> PackedByteArray:
	var low: int = 0xFF if index & 1 else 0x00
	var high: int = 0xFF if index & 2 else 0x00
	var out: PackedByteArray = PackedByteArray()
	for _row: int in Gen2Tiles.TILE_HEIGHT:
		out.append(low)
		out.append(high)
	return out


func test_a_tile_is_sixty_four_pixels() -> void:
	assert_eq(Gen2Tiles.decode_tile(_solid_tile(0), 0).size(), Gen2Tiles.TILE_PIXELS)


func test_each_index_round_trips() -> void:
	for index: int in 4:
		var pixels: PackedByteArray = Gen2Tiles.decode_tile(_solid_tile(index), 0)
		for pixel: int in pixels:
			assert_eq(pixel, index, "solid tile of index %d decoded a %d" % [index, pixel])


func test_the_two_bytes_of_a_row_are_low_then_high_bitplane() -> void:
	var data: PackedByteArray = PackedByteArray()
	data.append(0b1000_0000)
	data.append(0b0100_0000)
	for _i: int in 14:
		data.append(0x00)
	var pixels: PackedByteArray = Gen2Tiles.decode_tile(data, 0)
	assert_eq(pixels[0], 1, "bit 7 of the first byte is the leftmost low bit")
	assert_eq(pixels[1], 2, "bit 6 of the second byte is the next high bit")
	assert_eq(pixels[2], 0)


func test_bit_seven_is_the_leftmost_pixel() -> void:
	var data: PackedByteArray = PackedByteArray([0b0000_0001, 0x00])
	data.resize(Gen2Tiles.TILE_BYTES)
	assert_eq(Gen2Tiles.decode_tile(data, 0)[7], 1)


func test_out_of_range_offset_yields_a_blank_tile() -> void:
	var pixels: PackedByteArray = Gen2Tiles.decode_tile(PackedByteArray([0x01]), 0)
	assert_eq(pixels.size(), Gen2Tiles.TILE_PIXELS)
	assert_eq(pixels.count(0), Gen2Tiles.TILE_PIXELS)


func test_pic_tiles_are_stored_column_major() -> void:
	# Two columns of two tiles. Storage order is top-left, bottom-left,
	# top-right, bottom-right, down the columns and not across the rows.
	var data: PackedByteArray = PackedByteArray()
	for index: int in [1, 2, 3, 1]:
		data.append_array(_solid_tile(index))

	var pixels: PackedByteArray = Gen2Tiles.decode_pic(data, 2, 2)
	var width: int = 16
	assert_eq(pixels.size(), 16 * 16)
	assert_eq(pixels[0], 1, "top-left")
	assert_eq(pixels[8], 3, "top-right")
	assert_eq(pixels[8 * width], 2, "bottom-left")
	assert_eq(pixels[8 * width + 8], 1, "bottom-right")


func test_pic_ignores_trailing_data() -> void:
	# Crystal's front pics carry Pokédex animation frames after the still image.
	var data: PackedByteArray = _solid_tile(2)
	data.append_array(_solid_tile(3))
	var pixels: PackedByteArray = Gen2Tiles.decode_pic(data, 1, 1)
	assert_eq(pixels.size(), Gen2Tiles.TILE_PIXELS)
	assert_eq(pixels.count(2), Gen2Tiles.TILE_PIXELS)


func test_pic_with_too_little_data_is_blank_rather_than_partial() -> void:
	var pixels: PackedByteArray = Gen2Tiles.decode_pic(_solid_tile(3), 2, 2)
	assert_eq(pixels.size(), 16 * 16)
	assert_eq(pixels.count(0), 16 * 16)


func test_blit_places_a_small_pic_inside_a_cell() -> void:
	var source: PackedByteArray = PackedByteArray([1, 2, 3, 4])
	var destination: PackedByteArray = PackedByteArray()
	destination.resize(16)

	Gen2Tiles.blit(source, 2, destination, 4, 1, 1)

	assert_eq(destination[5], 1)
	assert_eq(destination[6], 2)
	assert_eq(destination[9], 3)
	assert_eq(destination[10], 4)
	assert_eq(destination[0], 0, "the rest of the cell is untouched")
