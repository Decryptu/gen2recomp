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


## A plausible trainer party table for the real GOLD layout: Falkner's own team
## at class 1, the one empty class genuinely empty, a filler trainer in every
## other class, and the last class carrying whatever name the layout expects,
## the whole table adding up to the exact total the layout knows.
##
## The known facts (Falkner's team, the empty class, the total, the last
## trainer's name) are the same kind pinned elsewhere here: real content
## hand-verified against the cartridges once, not bytes copied out of one.
func _trainer_party_dump() -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_trainer_parties(data, _trainer_party_classes())
	return data


func _trainer_party_classes() -> Array:
	var count: int = RomLayout.trainer_class_count(_layout)
	var total: int = int(_layout["trainer_party_total"])
	var last_name: String = String(_layout["trainer_party_last_trainer"])

	var classes: Array = []
	classes.resize(count)
	for i: int in count:
		classes[i] = []

	classes[0] = [{
		"name": RomImporter.TRAINER_PARTY_FIRST_NAME, "type": RomLayout.TRAINER_MON_NORMAL,
		"party": [
			{"level": RomImporter.TRAINER_PARTY_FIRST_LEVEL_1,
				"species": RomImporter.TRAINER_PARTY_FIRST_SPECIES_1},
			{"level": RomImporter.TRAINER_PARTY_FIRST_LEVEL_2,
				"species": RomImporter.TRAINER_PARTY_FIRST_SPECIES_2},
		],
	}]
	# RomLayout.EMPTY_TRAINER_CLASS is left as the empty Array _trainer_party_classes()
	# already gave it.
	classes[count - 1] = [{
		"name": last_name, "type": RomLayout.TRAINER_MON_NORMAL,
		"party": [{"level": 5, "species": 1}],
	}]

	# Every other class gets one filler trainer each, and the remaining total is
	# spread across them as evenly as a per-class cap allows, the same way
	# _evos_entries() pads out the evolution count.
	var filler_classes: Array = []
	for trainer_class: int in range(1, count + 1):
		if trainer_class != 1 and trainer_class != RomLayout.EMPTY_TRAINER_CLASS \
			and trainer_class != count:
			filler_classes.append(trainer_class)

	var remaining: int = total - 2
	var base: int = remaining / filler_classes.size()
	var extra: int = remaining % filler_classes.size()
	for i: int in filler_classes.size():
		var trainer_class: int = filler_classes[i]
		var mine: int = base + (1 if i < extra else 0)
		var trainers: Array = []
		for _n: int in mine:
			trainers.append({
				"name": "FILLER", "type": RomLayout.TRAINER_MON_NORMAL,
				"party": [{"level": 5, "species": 1}],
			})
		classes[trainer_class - 1] = trainers

	return classes


## Writes the pointer table and, right behind it in the same bank, every
## class's trainers back to back in class order. An empty class writes nothing
## at all, so its pointer ends up equal to the next class's: the same thing the
## real cartridge does for the one class with no party of its own.
func _write_trainer_parties(data: PackedByteArray, classes: Array) -> void:
	var table: int = int(_layout["trainer_parties"])
	var bank: int = RomLayout.bank_of(table)
	var at: int = table + classes.size() * RomLayout.TRAINER_PARTY_POINTER_SIZE

	for i: int in classes.size():
		var address: int = RomFile.BANK_SIZE + (at % RomFile.BANK_SIZE)
		var pointer: int = table + i * RomLayout.TRAINER_PARTY_POINTER_SIZE
		data[pointer] = address & 0xFF
		data[pointer + 1] = address >> 8

		for trainer: Dictionary in (classes[i] as Array):
			var encoded: PackedByteArray = Gen2Text.encode(String(trainer["name"]))
			encoded.append(Gen2Text.TERMINATOR)
			_write(data, at, encoded)
			at += encoded.size()
			data[at] = int(trainer["type"])
			at += 1
			for mon: Dictionary in (trainer["party"] as Array):
				data[at] = int(mon["level"])
				data[at + 1] = int(mon["species"])
				at += 2
			data[at] = RomLayout.TRAINER_PARTY_END
			at += 1

	assert(RomLayout.bank_of(at) == bank, "the filler table overran its own bank")


func test_a_plausible_trainer_party_table_verifies() -> void:
	var result: Dictionary = RomImporter.verify_trainer_parties(_rom(_trainer_party_dump()), _layout)
	assert_true(result["ok"], result["message"])


func test_falkners_team_reads_back() -> void:
	var result: Dictionary = RomImporter.read_trainer_parties(_rom(_trainer_party_dump()), _layout)
	assert_true(result["ok"], result["message"])
	var falkner: Dictionary = result["classes"][0][0]
	assert_eq(String(falkner["name"]), "FALKNER")
	assert_eq((falkner["party"] as Array).size(), 2)
	assert_eq(int(falkner["party"][1]["species"]), RomImporter.TRAINER_PARTY_FIRST_SPECIES_2)


func test_the_one_class_with_no_party_reads_back_empty() -> void:
	var result: Dictionary = RomImporter.read_trainer_parties(_rom(_trainer_party_dump()), _layout)
	assert_true(result["ok"], result["message"])
	var empty_class: Array = result["classes"][RomLayout.EMPTY_TRAINER_CLASS - 1]
	assert_eq(empty_class.size(), 0)


func test_a_trainer_class_that_is_not_empty_where_the_layout_says_it_is_fails() -> void:
	var classes: Array = _trainer_party_classes()
	classes[RomLayout.EMPTY_TRAINER_CLASS - 1] = [{
		"name": "OOPS", "type": RomLayout.TRAINER_MON_NORMAL, "party": [{"level": 5, "species": 1}],
	}]
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_trainer_parties(data, classes)
	var result: Dictionary = RomImporter.verify_trainer_parties(_rom(data), _layout)
	assert_false(result["ok"])


func test_a_trainer_party_with_the_wrong_total_fails() -> void:
	var classes: Array = _trainer_party_classes()
	classes[1] = []
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_trainer_parties(data, classes)
	var result: Dictionary = RomImporter.verify_trainer_parties(_rom(data), _layout)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "trainers")


func test_falkners_team_not_matching_what_is_known_fails() -> void:
	var classes: Array = _trainer_party_classes()
	classes[0][0]["party"][0]["species"] = 99
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_trainer_parties(data, classes)
	var result: Dictionary = RomImporter.verify_trainer_parties(_rom(data), _layout)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "Falkner")


func test_a_stored_moves_trainer_reads_its_moves_and_item() -> void:
	var classes: Array = _trainer_party_classes()
	classes[1] = [{
		"name": "PICKY", "type": RomLayout.TRAINER_MON_ITEM_MOVES,
		"party": [{"level": 20, "species": 4, "item": 5, "moves": [10, 20, 0, 0]}],
	}]
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_full_trainer_parties(data, classes)
	var result: Dictionary = RomImporter.read_trainer_parties(_rom(data), _layout)
	assert_true(result["ok"], result["message"])
	var mon: Dictionary = result["classes"][1][0]["party"][0]
	assert_eq(int(mon["item"]), 5)
	assert_eq(mon["moves"], [10, 20, 0, 0])


## The general form of [method _write_trainer_parties], which only ever wrote
## the type byte, level and species: this one also writes an item byte and four
## move bytes when the type says a Pokémon carries them, for the one test that
## needs a MOVES or ITEM trainer rather than a plain one.
func _write_full_trainer_parties(data: PackedByteArray, classes: Array) -> void:
	var table: int = int(_layout["trainer_parties"])
	var at: int = table + classes.size() * RomLayout.TRAINER_PARTY_POINTER_SIZE

	for i: int in classes.size():
		var address: int = RomFile.BANK_SIZE + (at % RomFile.BANK_SIZE)
		var pointer: int = table + i * RomLayout.TRAINER_PARTY_POINTER_SIZE
		data[pointer] = address & 0xFF
		data[pointer + 1] = address >> 8

		for trainer: Dictionary in (classes[i] as Array):
			var mon_type: int = int(trainer["type"])
			var encoded: PackedByteArray = Gen2Text.encode(String(trainer["name"]))
			encoded.append(Gen2Text.TERMINATOR)
			_write(data, at, encoded)
			at += encoded.size()
			data[at] = mon_type
			at += 1
			for mon: Dictionary in (trainer["party"] as Array):
				data[at] = int(mon["level"])
				data[at + 1] = int(mon["species"])
				at += 2
				if mon_type == RomLayout.TRAINER_MON_ITEM \
					or mon_type == RomLayout.TRAINER_MON_ITEM_MOVES:
					data[at] = int(mon.get("item", 0))
					at += 1
				if mon_type == RomLayout.TRAINER_MON_MOVES \
					or mon_type == RomLayout.TRAINER_MON_ITEM_MOVES:
					for move: Variant in (mon.get("moves", [0, 0, 0, 0]) as Array):
						data[at] = int(move)
						at += 1
			data[at] = RomLayout.TRAINER_PARTY_END
			at += 1


func test_a_trainer_pointer_outside_the_banked_window_fails() -> void:
	var data: PackedByteArray = _trainer_party_dump()
	data[int(_layout["trainer_parties"]) + 1] = 0x20
	assert_false(RomImporter.verify_trainer_parties(_rom(data), _layout)["ok"])


func test_a_trainer_party_pointer_table_with_no_terminator_anywhere_fails() -> void:
	# The failure the last class's own walk exists for: nothing bounds it but a
	# padding byte, and a dump with none reads on into whatever comes next.
	var data: PackedByteArray = _trainer_party_dump()
	var count: int = RomLayout.trainer_class_count(_layout)
	var last_pointer: int = int(_layout["trainer_parties"]) \
		+ (count - 1) * RomLayout.TRAINER_PARTY_POINTER_SIZE
	var address: int = data[last_pointer] | (data[last_pointer + 1] << 8)
	var bank: int = RomLayout.bank_of(int(_layout["trainer_parties"]))
	var at: int = RomFile.linear(bank, address)
	for i: int in RomFile.BANK_SIZE - (at % RomFile.BANK_SIZE):
		data[at + i] = 0x41
	assert_false(RomImporter.verify_trainer_parties(_rom(data), _layout)["ok"])


## Every class carrying Falkner's own known entry, which is a plausible table:
## every flag word is in range and class 1 matches what is known of it.
func _trainer_attributes_dump() -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_trainer_attributes(data, _trainer_attributes_entries())
	return data


func _trainer_attributes_entries() -> Array:
	var count: int = RomLayout.trainer_class_count(_layout)
	var entries: Array = []
	for _i: int in count:
		entries.append({
			"item1": 0, "item2": 0,
			"base_reward": RomImporter.TRAINER_ATTR_FIRST_REWARD,
			"ai_move_weights": RomImporter.TRAINER_ATTR_FIRST_AI_MOVE_WEIGHTS,
			"ai_item_switch": RomImporter.TRAINER_ATTR_FIRST_AI_ITEM_SWITCH,
		})
	return entries


func _write_trainer_attributes(data: PackedByteArray, entries: Array) -> void:
	for trainer_class: int in range(1, entries.size() + 1):
		var entry: Dictionary = entries[trainer_class - 1]
		var at: int = RomLayout.trainer_attributes_offset(_layout, trainer_class)
		data[at + RomLayout.ATTR_ITEM1] = int(entry["item1"])
		data[at + RomLayout.ATTR_ITEM2] = int(entry["item2"])
		data[at + RomLayout.ATTR_BASE_REWARD] = int(entry["base_reward"])
		var weights: int = int(entry["ai_move_weights"])
		data[at + RomLayout.ATTR_AI_MOVE_WEIGHTS] = weights & 0xFF
		data[at + RomLayout.ATTR_AI_MOVE_WEIGHTS + 1] = (weights >> 8) & 0xFF
		var switch_flags: int = int(entry["ai_item_switch"])
		data[at + RomLayout.ATTR_AI_ITEM_SWITCH] = switch_flags & 0xFF
		data[at + RomLayout.ATTR_AI_ITEM_SWITCH + 1] = (switch_flags >> 8) & 0xFF


func test_a_plausible_trainer_attributes_table_verifies() -> void:
	var result: Dictionary = RomImporter.verify_trainer_attributes(_rom(_trainer_attributes_dump()), _layout)
	assert_true(result["ok"], result["message"])


## Twins carry no AI at all in the real cartridge (their flag word is zero), and
## that is not a decoding failure: a class is allowed to score nothing.
func test_a_zero_ai_move_weight_is_allowed() -> void:
	var entries: Array = _trainer_attributes_entries()
	entries[1]["ai_move_weights"] = RomLayout.NO_AI
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_trainer_attributes(data, entries)
	assert_true(RomImporter.verify_trainer_attributes(_rom(data), _layout)["ok"])


func test_an_ai_move_weight_with_an_undefined_bit_fails() -> void:
	var entries: Array = _trainer_attributes_entries()
	entries[1]["ai_move_weights"] = RomLayout.AI_MOVE_WEIGHTS_MASK + 1
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_trainer_attributes(data, entries)
	assert_false(RomImporter.verify_trainer_attributes(_rom(data), _layout)["ok"])


func test_an_item_switch_word_with_an_undefined_bit_fails() -> void:
	var entries: Array = _trainer_attributes_entries()
	# Bit 3 is skipped in the cartridge's own numbering, so it is never legal.
	entries[1]["ai_item_switch"] = 1 << 3
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_trainer_attributes(data, entries)
	assert_false(RomImporter.verify_trainer_attributes(_rom(data), _layout)["ok"])


func test_falkners_attributes_not_matching_what_is_known_fails() -> void:
	var entries: Array = _trainer_attributes_entries()
	entries[0]["base_reward"] = 99
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_trainer_attributes(data, entries)
	assert_false(RomImporter.verify_trainer_attributes(_rom(data), _layout)["ok"])


func test_trainer_attributes_read_back_by_class() -> void:
	var entries: Array = _trainer_attributes_entries()
	entries[4]["item1"] = 0x10 # HYPER POTION, Pryce's own entry on the real cartridge.
	entries[4]["base_reward"] = 42
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_trainer_attributes(data, entries)

	var pryce: Dictionary = RomImporter.read_trainer_attributes(_rom(data), _layout, 5)
	assert_eq(int(pryce["item1"]), 0x10)
	assert_eq(int(pryce["base_reward"]), 42)

	var falkner: Dictionary = RomImporter.read_trainer_attributes(_rom(data), _layout, 1)
	assert_eq(int(falkner["ai_move_weights"]), RomImporter.TRAINER_ATTR_FIRST_AI_MOVE_WEIGHTS)


## A plausible trainer DVs table: Falkner's own known word at class 1, and the
## layout's own known word at the last class.
func _write_trainer_dvs(data: PackedByteArray, entries: Dictionary = {}) -> void:
	var count: int = RomLayout.trainer_class_count(_layout)
	for trainer_class: int in range(1, count + 1):
		var word: int = int(entries.get(
			trainer_class,
			RomImporter.TRAINER_DVS_FIRST if trainer_class == 1 else int(_layout["trainer_dvs_last"])
		))
		var at: int = RomLayout.trainer_dvs_offset(_layout, trainer_class)
		data[at] = (word >> 8) & 0xFF
		data[at + 1] = word & 0xFF


func test_a_plausible_trainer_dvs_table_verifies() -> void:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_trainer_dvs(data)
	var result: Dictionary = RomImporter.verify_trainer_dvs(_rom(data), _layout)
	assert_true(result["ok"], result["message"])


## The failure this check exists for: nothing about a nibble's shape can catch a
## wrong offset, since every nibble is a legal DV, so a wrong Falkner has to be
## what fails it.
func test_falkners_dvs_not_matching_what_is_known_fails() -> void:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_trainer_dvs(data, {1: 0x0000})
	assert_false(RomImporter.verify_trainer_dvs(_rom(data), _layout)["ok"])


func test_the_last_classs_dvs_not_matching_what_is_known_fails() -> void:
	var count: int = RomLayout.trainer_class_count(_layout)
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_trainer_dvs(data, {count: 0x0000})
	assert_false(RomImporter.verify_trainer_dvs(_rom(data), _layout)["ok"])


func test_trainer_dvs_read_back_by_class() -> void:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_trainer_dvs(data, {5: 0x7C33}) # Pryce, made up: attack 7, defense 12, speed 3, special 3.
	assert_eq(RomImporter.read_trainer_dvs(_rom(data), _layout, 5), 0x7C33)
	assert_eq(RomImporter.read_trainer_dvs(_rom(data), _layout, 1), RomImporter.TRAINER_DVS_FIRST)


## A battle sheet at every offset the layout claims: two bars that count up, and
## two HUD borders whose tiles all differ.
func _battle_dump() -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_bar(data, int(_layout["battle_font"]), RomLayout.HP_BAR_FIRST_TILE, RomLayout.HP_BAR_LEVELS)
	_write_bar(data, int(_layout["exp_bar"]), 0, RomLayout.EXP_BAR_LEVELS)
	_write_hud(data, int(_layout["enemy_hud"]), RomLayout.ENEMY_HUD_TILES)
	_write_hud(data, int(_layout["player_hud"]), RomLayout.PLAYER_HUD_TILES)
	_write_bar_palettes(data)
	_write_battle_object_palettes(data)
	return data


## The four bar palettes, whose values are the check on where they are.
func _write_bar_palettes(data: PackedByteArray) -> void:
	for index: int in RomLayout.BAR_PALETTE_NAMES.size():
		var at: int = RomLayout.bar_palette_offset(_layout, index)
		_write_palette(data, at, RomLayout.BAR_PALETTES[index])


## The six `BattleObjectPals`, checked the same way and for the same reason.
func _write_battle_object_palettes(data: PackedByteArray) -> void:
	var at: int = int(_layout["battle_object_palettes"])
	for index: int in RomLayout.BATTLE_OBJECT_PALETTES_STORED:
		_write_palette(
			data,
			at + index * RomLayout.BATTLE_OBJECT_PALETTE_COLORS * Gen2Palette.COLOR_BYTES,
			RomLayout.BATTLE_OBJECT_PALETTES[index]
		)


func _write_palette(data: PackedByteArray, at: int, colours: Array) -> void:
	for colour: int in colours.size():
		var packed: int = int(colours[colour])
		_write(
			data, at + colour * Gen2Palette.COLOR_BYTES,
			PackedByteArray([packed & 0xFF, packed >> 8])
		)


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


## A palette table one table out still decodes into colours, so the check is the
## values rather than the shape.
func test_a_battle_object_palette_that_is_not_the_pinned_one_fails() -> void:
	var data: PackedByteArray = _battle_dump()
	data[int(_layout["battle_object_palettes"])] = 0x00
	var result: Dictionary = RomImporter.verify_battle_graphics(_rom(data), _layout)
	assert_false(result["ok"])
	assert_string_contains(String(result["message"]), "Battle object palette gray")


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


func test_a_bar_palette_that_is_not_the_colour_it_should_be_fails() -> void:
	# These are known values rather than a shape, so a wrong offset is caught by
	# the colours themselves.
	var data: PackedByteArray = _battle_dump()
	_write(data, RomLayout.bar_palette_offset(_layout, 2), PackedByteArray([0x00, 0x00]))
	var result: Dictionary = RomImporter.verify_battle_graphics(_rom(data), _layout)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "hp_red")


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


## A matchup chart of the right length with the right ends: the four rows whose
## content is known, filler that is valid but says nothing, and both terminators.
func _matchup_dump() -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write(data, int(_layout["type_matchups"]), _matchup_table())
	return data


func _matchup_table() -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.append_array(_row(
		RomLayout.TYPE_NORMAL, RomLayout.TYPE_ROCK, RomLayout.MATCHUP_NOT_VERY_EFFECTIVE
	))
	for _filler: int in RomLayout.MATCHUP_COUNT - 2:
		out.append_array(_row(
			RomLayout.TYPE_FIGHTING, RomLayout.TYPE_NORMAL, RomLayout.MATCHUP_SUPER_EFFECTIVE
		))
	out.append_array(_row(
		RomLayout.TYPE_STEEL, RomLayout.TYPE_STEEL, RomLayout.MATCHUP_NOT_VERY_EFFECTIVE
	))
	out.append(RomLayout.MATCHUP_END_FORESIGHT)
	out.append_array(_row(
		RomLayout.TYPE_NORMAL, RomLayout.TYPE_GHOST, RomLayout.MATCHUP_NO_EFFECT
	))
	out.append_array(_row(
		RomLayout.TYPE_FIGHTING, RomLayout.TYPE_GHOST, RomLayout.MATCHUP_NO_EFFECT
	))
	out.append(RomLayout.MATCHUP_END)
	return out


func _row(attacker: int, defender: int, multiplier: int) -> PackedByteArray:
	return PackedByteArray([attacker, defender, multiplier])


func test_a_plausible_matchup_chart_verifies() -> void:
	var result: Dictionary = RomImporter.verify_matchups(_rom(_matchup_dump()), _layout)
	assert_true(result["ok"], result["message"])


func test_the_chart_reads_back_as_rows_with_the_foresight_ones_flagged() -> void:
	var rows: Array = RomImporter.read_matchups(_rom(_matchup_dump()), _layout)
	assert_eq(rows.size(), RomLayout.MATCHUP_COUNT + RomLayout.FORESIGHT_MATCHUP_COUNT)
	assert_false(rows[0]["negated_by_foresight"], "the chart proper is not conditional")
	assert_true(rows[rows.size() - 1]["negated_by_foresight"], "past $FE it is")
	assert_eq(int(rows[0]["multiplier"]), RomLayout.MATCHUP_NOT_VERY_EFFECTIVE)


func test_a_chart_one_byte_out_fails() -> void:
	# The failure this check exists for. Three-byte rows mean a slide of one byte
	# still reads as rows, and every one of them is then a lie.
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write(data, int(_layout["type_matchups"]) + 1, _matchup_table())
	assert_false(RomImporter.verify_matchups(_rom(data), _layout)["ok"])


func test_a_multiplier_the_chart_never_stores_fails() -> void:
	# A neutral matchup is an absent row, so a ten here means the walk has left
	# the table and is reading something else.
	var data: PackedByteArray = _matchup_dump()
	data[int(_layout["type_matchups"]) + RomLayout.MATCHUP_MULTIPLIER] = RomLayout.MATCHUP_EFFECTIVE
	var result: Dictionary = RomImporter.verify_matchups(_rom(data), _layout)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "multiplier")


func test_a_type_number_in_the_padding_run_fails() -> void:
	# $0A to $13 have names but no matchups. Landing on one is what a wrong
	# offset does almost immediately, because it is most of the byte range.
	var data: PackedByteArray = _matchup_dump()
	data[int(_layout["type_matchups"]) + RomLayout.MATCHUP_DEFENDER] = 0x0E
	assert_false(RomImporter.verify_matchups(_rom(data), _layout)["ok"])


func test_a_chart_of_the_wrong_length_fails() -> void:
	var data: PackedByteArray = _matchup_dump()
	var short: PackedByteArray = _matchup_table()
	short.resize(short.size() - RomLayout.MATCHUP_ENTRY_SIZE)
	short[short.size() - 1] = RomLayout.MATCHUP_END
	_write(data, int(_layout["type_matchups"]), short)
	var result: Dictionary = RomImporter.verify_matchups(_rom(data), _layout)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "rows")


func test_a_chart_with_no_terminator_fails_rather_than_running_away() -> void:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	for i: int in RomLayout.MAX_MATCHUPS * RomLayout.MATCHUP_ENTRY_SIZE:
		data[int(_layout["type_matchups"]) + i] = RomLayout.TYPE_NORMAL
	assert_false(RomImporter.verify_matchups(_rom(data), _layout)["ok"])


## A plausible evolution and learnset table: 251 entries laid out one after
## another behind their pointer table, in the same bank the pointers can reach.
##
## The contents are the ones the check knows independently, plus filler that is
## valid and says nothing. Only the first species, Tyrogue and the last are real.
func _evos_dump() -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_evos(data, _evos_entries())
	return data


func _evos_entries() -> Array:
	var out: Array = []
	for _species: int in RomLayout.SPECIES_COUNT:
		out.append({"evolutions": [], "learnset": [[1, 33]]})

	out[0]["evolutions"] = [[RomLayout.EVOLVE_LEVEL, RomImporter.FIRST_EVOLUTION_LEVEL, 0, 2]]
	out[0]["learnset"] = [[1, RomImporter.FIRST_LEARNSET_MOVE], [7, 45]]

	out[RomImporter.STAT_EVOLUTION_SPECIES - 1]["evolutions"] = [
		[RomLayout.EVOLVE_STAT, 20, RomLayout.ATTACK_OVER_DEFENSE, 106],
		[RomLayout.EVOLVE_STAT, 20, RomLayout.ATTACK_UNDER_DEFENSE, 107],
		[RomLayout.EVOLVE_STAT, 20, RomLayout.ATTACK_EQUALS_DEFENSE, 237],
	]

	# Enough ordinary evolutions elsewhere to reach the total the check knows,
	# kept well clear of the three species that are checked by name.
	var filler: int = RomLayout.EVOLUTION_COUNT - 1 - RomImporter.STAT_EVOLUTION_COUNT
	for species: int in range(2, 2 + filler):
		out[species - 1]["evolutions"] = [[RomLayout.EVOLVE_LEVEL, 20, 0, species + 1]]

	return out


func _write_evos(data: PackedByteArray, entries: Array) -> void:
	var table: int = int(_layout["evos_attacks"])
	var at: int = table + RomLayout.SPECIES_COUNT * RomLayout.EVOS_ATTACKS_POINTER_SIZE

	for species: int in RomLayout.SPECIES_COUNT:
		# A two-byte pointer carries an address and no bank, so it is written the
		# way the cartridge writes one: an offset into the bank it is already in.
		var address: int = RomFile.BANK_SIZE + (at % RomFile.BANK_SIZE)
		var pointer: int = table + species * RomLayout.EVOS_ATTACKS_POINTER_SIZE
		data[pointer] = address & 0xFF
		data[pointer + 1] = address >> 8

		var entry: Dictionary = entries[species]
		for evolution: Array in entry["evolutions"]:
			var size: int = RomLayout.evolution_size(int(evolution[0]))
			data[at] = evolution[0]
			data[at + 1] = evolution[1]
			if int(evolution[0]) == RomLayout.EVOLVE_STAT:
				data[at + 2] = evolution[2]
			data[at + size - 1] = evolution[3]
			at += size
		data[at] = RomLayout.EVOS_ATTACKS_END
		at += 1

		for move: Array in entry["learnset"]:
			data[at] = move[0]
			data[at + 1] = move[1]
			at += 2
		data[at] = RomLayout.EVOS_ATTACKS_END
		at += 1


func test_a_plausible_evolution_and_learnset_table_verifies() -> void:
	var result: Dictionary = RomImporter.verify_evos_attacks(_rom(_evos_dump()), _layout)
	assert_true(result["ok"], result["message"])


func test_an_entry_reads_back_as_its_two_halves() -> void:
	var entry: Dictionary = RomImporter.read_evos_attacks(_rom(_evos_dump()), _layout, 1)
	assert_eq((entry["evolutions"] as Array).size(), 1)
	assert_eq(int(entry["evolutions"][0]["target"]), 2)
	assert_eq(int(entry["evolutions"][0]["parameter"]), RomImporter.FIRST_EVOLUTION_LEVEL)
	assert_eq((entry["learnset"] as Array).size(), 2)
	assert_eq(int(entry["learnset"][0]["move"]), RomImporter.FIRST_LEARNSET_MOVE)


func test_the_four_byte_method_keeps_the_walk_in_step() -> void:
	# The failure this check exists for. Every evolution is three bytes except the
	# stat one, so a decoder that assumes three reads Tyrogue's second and third
	# entries out of the middle of the first and comes out somewhere else entirely.
	var entry: Dictionary = RomImporter.read_evos_attacks(
		_rom(_evos_dump()), _layout, RomImporter.STAT_EVOLUTION_SPECIES
	)
	var evolutions: Array = entry["evolutions"]
	assert_eq(evolutions.size(), RomImporter.STAT_EVOLUTION_COUNT)
	assert_eq(int(evolutions[0]["condition"]), RomLayout.ATTACK_OVER_DEFENSE)
	assert_eq(int(evolutions[2]["target"]), 237)
	assert_eq(int(entry["learnset"][0]["level"]), 1, "the moves still start where they should")


func test_a_pointer_table_one_byte_out_fails() -> void:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_evos(data, _evos_entries())
	# Slide every pointer by a byte, which is what a wrong offset looks like: the
	# addresses stay inside the bank and point at nothing in particular.
	var table: int = int(_layout["evos_attacks"])
	for species: int in RomLayout.SPECIES_COUNT:
		var at: int = table + species * RomLayout.EVOS_ATTACKS_POINTER_SIZE
		data[at] = (data[at] + 1) & 0xFF
	assert_false(RomImporter.verify_evos_attacks(_rom(data), _layout)["ok"])


func test_an_entry_pointer_outside_the_banked_window_fails() -> void:
	var data: PackedByteArray = _evos_dump()
	data[int(_layout["evos_attacks"]) + 1] = 0x20
	assert_false(RomImporter.verify_evos_attacks(_rom(data), _layout)["ok"])


func test_a_byte_that_is_not_an_evolution_method_fails() -> void:
	var entries: Array = _evos_entries()
	entries[9]["evolutions"] = [[0x42, 20, 0, 11]]
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_evos(data, entries)
	assert_false(RomImporter.verify_evos_attacks(_rom(data), _layout)["ok"])


func test_an_evolution_into_a_species_that_does_not_exist_fails() -> void:
	var entries: Array = _evos_entries()
	entries[9]["evolutions"] = [[RomLayout.EVOLVE_LEVEL, 20, 0, 255]]
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_evos(data, entries)
	var result: Dictionary = RomImporter.verify_evos_attacks(_rom(data), _layout)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "does not exist")


func test_a_happiness_evolution_with_no_such_trigger_fails() -> void:
	var entries: Array = _evos_entries()
	entries[9]["evolutions"] = [[RomLayout.EVOLVE_HAPPINESS, 9, 0, 11]]
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_evos(data, entries)
	assert_false(RomImporter.verify_evos_attacks(_rom(data), _layout)["ok"])


func test_a_move_learned_above_the_level_cap_fails() -> void:
	var entries: Array = _evos_entries()
	entries[9]["learnset"] = [[1, 33], [200, 45]]
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_evos(data, entries)
	var result: Dictionary = RomImporter.verify_evos_attacks(_rom(data), _layout)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "level 200")


func test_a_species_that_learns_nothing_fails() -> void:
	var entries: Array = _evos_entries()
	entries[9]["learnset"] = []
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_evos(data, entries)
	assert_false(RomImporter.verify_evos_attacks(_rom(data), _layout)["ok"])


func test_levels_out_of_order_fail_everywhere_but_the_one_species() -> void:
	# Muk's list really is out of order in all three cartridges, so the check has
	# to let that one through and nothing else. Both halves are tested here,
	# because an exception nobody has seen close is a hole.
	var entries: Array = _evos_entries()
	var scrambled: Array = [[1, 33], [40, 45], [20, 46]]

	entries[RomLayout.UNSORTED_LEARNSET_SPECIES - 1]["learnset"] = scrambled
	var allowed: PackedByteArray = PackedByteArray()
	allowed.resize(RomRegistry.EXPECTED_SIZE)
	_write_evos(allowed, entries)
	assert_true(RomImporter.verify_evos_attacks(_rom(allowed), _layout)["ok"])

	entries[9]["learnset"] = scrambled
	var refused: PackedByteArray = PackedByteArray()
	refused.resize(RomRegistry.EXPECTED_SIZE)
	_write_evos(refused, entries)
	assert_false(RomImporter.verify_evos_attacks(_rom(refused), _layout)["ok"])


func test_a_table_with_the_wrong_number_of_evolutions_fails() -> void:
	var entries: Array = _evos_entries()
	entries[9]["evolutions"] = []
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	_write_evos(data, entries)
	var result: Dictionary = RomImporter.verify_evos_attacks(_rom(data), _layout)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "evolutions")


func test_a_learnset_with_no_terminator_fails_rather_than_running_away() -> void:
	var data: PackedByteArray = _evos_dump()
	var at: int = int(_layout["evos_attacks"]) \
		+ RomLayout.SPECIES_COUNT * RomLayout.EVOS_ATTACKS_POINTER_SIZE
	for i: int in RomLayout.MAX_LEVEL_UP_MOVES * 2 + 8:
		data[at + i] = 1
	assert_false(RomImporter.verify_evos_attacks(_rom(data), _layout)["ok"])
