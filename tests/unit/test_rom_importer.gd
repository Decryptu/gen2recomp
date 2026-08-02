extends GutTest

## The font, border and trainer layout checks, against dumps this test builds.
##
## No cartridge is opened here. What is being tested is not where the font is,
## which only a real dump can settle, but that the checks would notice if it
## were somewhere else: the whole value of a runtime check is that it fails, and
## a check nobody has ever seen fail is a comment.

## Where the synthetic trainer pics are put: a bank the layout passes through
## unpatched, so the check sees the same bank repair a real pointer gets.
const PIC_BANK: int = 0x21
const PIC_ADDRESS: int = 0x4010

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


## Names, palettes and pic pointers for every class, all three agreeing.
func _trainer_dump() -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_class_names(data, int(_layout["trainer_class_names"]))
	_write_trainer_palettes(data, true)
	_write_trainer_pointers(data)
	_write(data, RomFile.linear(PIC_BANK, PIC_ADDRESS), _trainer_pic())
	return data


func _write_class_names(data: PackedByteArray, at: int) -> void:
	var count: int = RomLayout.trainer_class_count(_layout)
	var cursor: int = at
	for trainer_class: int in range(1, count + 1):
		var name: String = "LASS"
		if trainer_class == 1:
			name = RomImporter.TRAINER_FIRST_CLASS
		elif trainer_class == RomImporter.TRAINER_MIDDLE_CLASS:
			name = RomImporter.TRAINER_MIDDLE_CLASS_NAME
		elif trainer_class == count:
			name = String(_layout["trainer_last_class"])
		var encoded: PackedByteArray = Gen2Text.encode(name)
		encoded.append(Gen2Text.TERMINATOR)
		_write(data, cursor, encoded)
		cursor += encoded.size()


## The player's entry plus one per class, and then something that is not a
## palette, because the table ending where it should is half of what is checked.
func _write_trainer_palettes(data: PackedByteArray, ends: bool) -> void:
	var count: int = RomLayout.trainer_class_count(_layout)
	for trainer_class: int in range(0, count + 2):
		var at: int = RomLayout.trainer_palette_offset(_layout, trainer_class)
		var high: int = 0x80 if ends and trainer_class == count + 1 else 0x00
		_write(data, at, PackedByteArray([0x34, 0x12, 0x78, 0x56 | high]))


func _write_trainer_pointers(data: PackedByteArray) -> void:
	for trainer_class: int in range(1, RomLayout.trainer_class_count(_layout) + 1):
		_write(
			data, RomLayout.trainer_pic_pointer_offset(_layout, trainer_class),
			PackedByteArray([PIC_BANK, PIC_ADDRESS & 0xFF, PIC_ADDRESS >> 8])
		)


## A long-form zero fill of exactly one trainer pic, then the terminator. The
## pixels do not matter here; the length is what the check reads.
func _trainer_pic() -> PackedByteArray:
	var pixels: int = RomLayout.TRAINER_PIC_TILES * RomLayout.TRAINER_PIC_TILES \
		* Gen2Tiles.TILE_BYTES
	var length: int = pixels - 1
	return PackedByteArray([
		0xE0 | (Gen2Lz.Op.ZERO << 2) | (length >> 8), length & 0xFF, Gen2Lz.TERMINATOR,
	])


func test_a_plausible_trainer_table_verifies() -> void:
	var result: Dictionary = RomImporter.verify_trainers(_rom(_trainer_dump()), _layout)
	assert_true(result["ok"], result["message"])


func test_class_names_that_slid_by_a_byte_fail() -> void:
	# The failure the far-end check exists for: the entries are terminated rather
	# than padded, so a start that is one byte out still reads as words.
	var data: PackedByteArray = _trainer_dump()
	_write_class_names(data, int(_layout["trainer_class_names"]) + 1)
	assert_false(RomImporter.verify_trainers(_rom(data), _layout)["ok"])


func test_a_palette_table_that_does_not_end_where_the_classes_do_fails() -> void:
	var data: PackedByteArray = _trainer_dump()
	_write_trainer_palettes(data, false)
	var result: Dictionary = RomImporter.verify_trainers(_rom(data), _layout)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "entry")


func test_a_blank_trainer_palette_fails() -> void:
	var data: PackedByteArray = _trainer_dump()
	_write(data, RomLayout.trainer_palette_offset(_layout, 3), PackedByteArray([0, 0, 0, 0]))
	assert_false(RomImporter.verify_trainers(_rom(data), _layout)["ok"])


func test_a_pointer_outside_the_banked_window_fails() -> void:
	# $0000-$3FFF is the fixed bank, which no pic pointer addresses: a pointer
	# that lands there means the table is not a pointer table.
	var data: PackedByteArray = _trainer_dump()
	_write(
		data, RomLayout.trainer_pic_pointer_offset(_layout, 5),
		PackedByteArray([PIC_BANK, 0x00, 0x20])
	)
	assert_false(RomImporter.verify_trainers(_rom(data), _layout)["ok"])


func test_a_pic_that_is_short_of_a_full_trainer_fails() -> void:
	var data: PackedByteArray = _trainer_dump()
	_write(
		data, RomFile.linear(PIC_BANK, PIC_ADDRESS),
		PackedByteArray([0x60 | 0x02, Gen2Lz.TERMINATOR])
	)
	assert_false(RomImporter.verify_trainers(_rom(data), _layout)["ok"])


func test_a_dump_with_no_trainers_in_it_fails() -> void:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	assert_false(RomImporter.verify_trainers(_rom(data), _layout)["ok"])


## A battle sheet at every offset the layout claims: two bars that count up, and
## two HUD borders whose tiles all differ.
func _battle_dump() -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_bar(data, int(_layout["battle_font"]), RomLayout.HP_BAR_FIRST_TILE, RomLayout.HP_BAR_LEVELS)
	_write_bar(data, int(_layout["exp_bar"]), 0, RomLayout.EXP_BAR_LEVELS)
	_write_hud(data, int(_layout["enemy_hud"]), RomLayout.ENEMY_HUD_TILES)
	_write_hud(data, int(_layout["player_hud"]), RomLayout.PLAYER_HUD_TILES)
	return data


## Fill levels as 2bpp tiles, each one two pixels fuller than the last.
func _write_bar(data: PackedByteArray, at: int, first: int, levels: int) -> void:
	for level: int in levels:
		_write(
			data, at + (first + level) * Gen2Tiles.TILE_BYTES,
			_lit_tile(Gen2Tiles.TILE_WIDTH + level * RomLayout.BAR_STEP_PIXELS)
		)


## A 2bpp tile with [param pixels] lit, filled row by row.
func _lit_tile(pixels: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(Gen2Tiles.TILE_BYTES)
	for pixel: int in pixels:
		@warning_ignore("integer_division")
		var row: int = pixel / Gen2Tiles.TILE_WIDTH
		out[row * 2] |= 1 << (7 - pixel % Gen2Tiles.TILE_WIDTH)
	return out


## 1bpp tiles that all have ink and none of which repeats another.
func _write_hud(data: PackedByteArray, at: int, tiles: int) -> void:
	for tile: int in tiles:
		var bytes: PackedByteArray = PackedByteArray()
		bytes.resize(Gen2Tiles.TILE_1BPP_BYTES)
		bytes[0] = 0xFF << (7 - tile) & 0xFF
		bytes[1] = 0x18
		_write(data, at + tile * Gen2Tiles.TILE_1BPP_BYTES, bytes)


func test_battle_graphics_that_count_up_verify() -> void:
	var result: Dictionary = RomImporter.verify_battle_graphics(_rom(_battle_dump()), _layout)
	assert_true(result["ok"], result["message"])


func test_a_bar_whose_levels_do_not_climb_fails() -> void:
	# The check the bars exist for: neither has a name or a number in the
	# cartridge, and a run of tiles that counts up is what says it is a bar.
	var data: PackedByteArray = _battle_dump()
	_write(
		data,
		int(_layout["battle_font"]) + (RomLayout.HP_BAR_FIRST_TILE + 4) * Gen2Tiles.TILE_BYTES,
		_lit_tile(Gen2Tiles.TILE_WIDTH)
	)
	assert_false(RomImporter.verify_battle_graphics(_rom(data), _layout)["ok"])


func test_an_exp_bar_that_is_not_there_fails() -> void:
	var data: PackedByteArray = _battle_dump()
	for i: int in RomLayout.EXP_BAR_TILES * Gen2Tiles.TILE_BYTES:
		data[int(_layout["exp_bar"]) + i] = 0
	assert_false(RomImporter.verify_battle_graphics(_rom(data), _layout)["ok"])


func test_a_blank_hud_tile_fails() -> void:
	var data: PackedByteArray = _battle_dump()
	for row: int in Gen2Tiles.TILE_1BPP_BYTES:
		data[int(_layout["player_hud"]) + 2 * Gen2Tiles.TILE_1BPP_BYTES + row] = 0
	assert_false(RomImporter.verify_battle_graphics(_rom(data), _layout)["ok"])


func test_hud_tiles_that_repeat_mean_it_is_not_the_border() -> void:
	var data: PackedByteArray = _battle_dump()
	_write(
		data, int(_layout["enemy_hud"]) + Gen2Tiles.TILE_1BPP_BYTES,
		data.slice(int(_layout["enemy_hud"]), int(_layout["enemy_hud"]) + Gen2Tiles.TILE_1BPP_BYTES)
	)
	assert_false(RomImporter.verify_battle_graphics(_rom(data), _layout)["ok"])
