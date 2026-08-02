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


func test_a_1bpp_strip_is_one_tile_tall_and_as_wide_as_it_needs() -> void:
	var data: PackedByteArray = PackedByteArray()
	data.resize(3 * Gen2Tiles.TILE_1BPP_BYTES)
	var strip: PackedByteArray = Gen2Tiles.decode_1bpp_strip(data, 0, 3)
	assert_eq(strip.size(), 3 * Gen2Tiles.TILE_WIDTH * Gen2Tiles.TILE_HEIGHT)


func test_a_set_1bpp_bit_decodes_to_ink_and_the_rest_to_the_background() -> void:
	# The hardware widens 1bpp by copying the byte into both planes, so a lit
	# pixel is index 3 and there are no middle colours to be had.
	var data: PackedByteArray = PackedByteArray([0b1000_0001, 0, 0, 0, 0, 0, 0, 0])
	var strip: PackedByteArray = Gen2Tiles.decode_1bpp_strip(data, 0, 1)
	assert_eq(strip[0], Gen2Tiles.INK, "bit 7 is the leftmost pixel")
	assert_eq(strip[7], Gen2Tiles.INK, "bit 0 is the rightmost")
	assert_eq(strip[1], 0)
	assert_eq(strip[Gen2Tiles.TILE_WIDTH], 0, "the second row is untouched")


func test_1bpp_tiles_sit_side_by_side_in_code_order() -> void:
	var data: PackedByteArray = PackedByteArray()
	for byte: int in [0xFF, 0x00]:
		for _row: int in Gen2Tiles.TILE_1BPP_BYTES:
			data.append(byte)

	var strip: PackedByteArray = Gen2Tiles.decode_1bpp_strip(data, 0, 2)
	assert_eq(strip[0], Gen2Tiles.INK, "the first tile is solid")
	assert_eq(strip[Gen2Tiles.TILE_WIDTH], 0, "the second starts eight pixels along")


func test_a_1bpp_strip_that_runs_out_of_data_keeps_its_size() -> void:
	# A hole is visible on screen; a short buffer is a crash somewhere later.
	var strip: PackedByteArray = Gen2Tiles.decode_1bpp_strip(PackedByteArray([0xFF]), 0, 2)
	assert_eq(strip.size(), 2 * Gen2Tiles.TILE_WIDTH * Gen2Tiles.TILE_HEIGHT)
	assert_eq(strip.count(0), strip.size())


func test_a_2bpp_strip_keeps_all_four_colours_where_a_1bpp_one_has_two() -> void:
	# The battle HUD is 2bpp, so its strips carry the middle indices the font
	# never produces.
	var data: PackedByteArray = PackedByteArray()
	data.resize(Gen2Tiles.TILE_BYTES)
	data[0] = 0xF0
	data[1] = 0xCC
	var strip: PackedByteArray = Gen2Tiles.decode_2bpp_strip(data, 0, 1)
	assert_eq(strip.size(), Gen2Tiles.TILE_PIXELS)
	assert_eq(strip[0], 3, "both planes set")
	assert_eq(strip[2], 1, "low plane only")
	assert_eq(strip[4], 2, "high plane only")
	assert_eq(strip[6], 0)


func test_a_2bpp_strip_that_runs_out_of_data_keeps_its_size() -> void:
	var strip: PackedByteArray = Gen2Tiles.decode_2bpp_strip(PackedByteArray(), 0, 4)
	assert_eq(strip.size(), 4 * Gen2Tiles.TILE_PIXELS)


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
