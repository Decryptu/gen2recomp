extends GutTest

## The font and border layout checks, against dumps this test builds.
##
## No cartridge is opened here. What is being tested is not where the font is,
## which only a real dump can settle, but that the checks would notice if it
## were somewhere else: the whole value of a runtime check is that it fails, and
## a check nobody has ever seen fail is a comment.

var _layout: Dictionary = RomLayout.for_id(RomRegistry.GOLD)


## A dump with a plausible font and eight plausible borders at the offsets the
## layout claims, and nothing else in it.
func _dump() -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write(data, RomLayout.font_offset(_layout), _font())
	for frame: int in RomLayout.FRAME_COUNT:
		_write(data, RomLayout.frame_offset(_layout, frame), _frame(frame))
	return data


func _write(data: PackedByteArray, at: int, bytes: PackedByteArray) -> void:
	for i: int in bytes.size():
		data[at + i] = bytes[i]


## Ink everywhere the charmap has a character, blank in the runs where it does
## not. The glyphs themselves are nonsense; only their presence is checked.
func _font() -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(RomLayout.FONT_TILES * Gen2Tiles.TILE_1BPP_BYTES)
	for tile: int in RomLayout.FONT_TILES:
		if _is_blank_code(RomLayout.FONT_FIRST_CODE + tile):
			continue
		for row: int in Gen2Tiles.TILE_1BPP_BYTES:
			out[tile * Gen2Tiles.TILE_1BPP_BYTES + row] = 0x7E
	return out


func _is_blank_code(code: int) -> bool:
	for run: Array in RomLayout.FONT_BLANK_RUNS:
		if code >= run[0] and code <= run[1]:
			return true
	return false


## Six tiles: a top edge inset by two rows, a vertical side, and two bottom
## corners that carry the side's pattern into their first row.
func _frame(number: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(RomLayout.FRAME_TILES * Gen2Tiles.TILE_1BPP_BYTES)

	for tile: int in [
		RomLayout.FRAME_TOP_LEFT, RomLayout.FRAME_HORIZONTAL, RomLayout.FRAME_TOP_RIGHT
	]:
		for row: int in range(2, Gen2Tiles.TILE_1BPP_BYTES):
			out[tile * Gen2Tiles.TILE_1BPP_BYTES + row] = 0x3C

	for row: int in Gen2Tiles.TILE_1BPP_BYTES:
		out[RomLayout.FRAME_VERTICAL * Gen2Tiles.TILE_1BPP_BYTES + row] = 0x18

	for tile: int in [RomLayout.FRAME_BOTTOM_LEFT, RomLayout.FRAME_BOTTOM_RIGHT]:
		out[tile * Gen2Tiles.TILE_1BPP_BYTES] = 0x18
		out[tile * Gen2Tiles.TILE_1BPP_BYTES + 1] = 0x3C

	# So that no two frames are the same, which is itself a check.
	out[RomLayout.FRAME_TOP_LEFT * Gen2Tiles.TILE_1BPP_BYTES + 7] = 0x10 + number
	return out


func _rom(data: PackedByteArray) -> RomFile:
	return RomFile.from_bytes(data, RomRegistry.GOLD)


func test_a_plausible_font_and_borders_verify() -> void:
	var data: PackedByteArray = _dump()
	assert_true(RomImporter.verify_font(_rom(data), _layout)["ok"])
	assert_true(RomImporter.verify_frames(_rom(data), _layout)["ok"])


func test_a_font_one_tile_out_fails() -> void:
	# The failure this check exists for. A shifted font still draws letters, so
	# nothing downstream would report it.
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write(data, RomLayout.font_offset(_layout) + Gen2Tiles.TILE_1BPP_BYTES, _font())
	assert_false(RomImporter.verify_font(_rom(data), _layout)["ok"])


func test_a_font_with_a_missing_letter_fails() -> void:
	var data: PackedByteArray = _dump()
	var at: int = RomLayout.font_offset(_layout) + (0x99 - RomLayout.FONT_FIRST_CODE) \
		* Gen2Tiles.TILE_1BPP_BYTES
	for row: int in Gen2Tiles.TILE_1BPP_BYTES:
		data[at + row] = 0
	var result: Dictionary = RomImporter.verify_font(_rom(data), _layout)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "$99")


func test_a_glyph_where_the_charmap_has_no_character_fails() -> void:
	var data: PackedByteArray = _dump()
	var at: int = RomLayout.font_offset(_layout) + (0xBA - RomLayout.FONT_FIRST_CODE) \
		* Gen2Tiles.TILE_1BPP_BYTES
	data[at] = 0x18
	assert_false(RomImporter.verify_font(_rom(data), _layout)["ok"])


func test_a_solid_row_means_it_is_not_a_font() -> void:
	# No glyph fills eight pixels: every character leaves the spacing column
	# clear. A run of $FF is graphics.
	var data: PackedByteArray = _dump()
	data[RomLayout.font_offset(_layout)] = 0xFF
	assert_false(RomImporter.verify_font(_rom(data), _layout)["ok"])


func test_blank_space_where_the_font_should_be_fails() -> void:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	assert_false(RomImporter.verify_font(_rom(data), _layout)["ok"])


func test_a_border_with_ink_on_its_top_scanlines_fails() -> void:
	# A box border is inset from the top of its tile row. Ink there means the
	# offset landed on something that is not a frame.
	var data: PackedByteArray = _dump()
	data[RomLayout.frame_offset(_layout, 0)] = 0x18
	assert_false(RomImporter.verify_frames(_rom(data), _layout)["ok"])


func test_corners_that_do_not_meet_their_sides_fail() -> void:
	var data: PackedByteArray = _dump()
	data[
		RomLayout.frame_offset(_layout, 3)
		+ RomLayout.FRAME_BOTTOM_RIGHT * Gen2Tiles.TILE_1BPP_BYTES
	] = 0x81
	assert_false(RomImporter.verify_frames(_rom(data), _layout)["ok"])


func test_a_side_that_never_draws_what_its_corners_do_fails() -> void:
	var data: PackedByteArray = _dump()
	var at: int = RomLayout.frame_offset(_layout, 2) \
		+ RomLayout.FRAME_VERTICAL * Gen2Tiles.TILE_1BPP_BYTES
	for row: int in Gen2Tiles.TILE_1BPP_BYTES:
		data[at + row] = 0x24
	assert_false(RomImporter.verify_frames(_rom(data), _layout)["ok"])


func test_eight_identical_borders_mean_it_is_not_the_table() -> void:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	for frame: int in RomLayout.FRAME_COUNT:
		_write(data, RomLayout.frame_offset(_layout, frame), _frame(0))
	assert_false(RomImporter.verify_frames(_rom(data), _layout)["ok"])


func test_a_dump_too_short_to_hold_the_font_fails_rather_than_reading_past_it() -> void:
	assert_false(RomImporter.verify_font(_rom(PackedByteArray()), _layout)["ok"])
	assert_false(RomImporter.verify_frames(_rom(PackedByteArray()), _layout)["ok"])
