extends GutTest

## Addressing and header parsing, on a synthetic cartridge. No real dump is
## involved — the bytes here are built to exercise the arithmetic, not to
## resemble a game.

const SCRATCH_DIR: String = "user://test_roms"

var _made: PackedStringArray = []


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	_made = []


func after_each() -> void:
	for path: String in _made:
		DirAccess.remove_absolute(path)


func _blank_cartridge() -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(RomRegistry.EXPECTED_SIZE)
	return data


func test_reads_are_little_endian() -> void:
	var rom: RomFile = RomFile.from_bytes(PackedByteArray([0x34, 0x12]))
	assert_eq(rom.u8(0), 0x34)
	assert_eq(rom.u16le(0), 0x1234)


func test_a_far_pointer_is_bank_then_address() -> void:
	var rom: RomFile = RomFile.from_bytes(PackedByteArray([0x1E, 0x6C, 0x6D]))
	assert_eq(rom.far_pointer(0), {"bank": 0x1E, "address": 0x6D6C})


func test_reads_past_the_end_return_zero_rather_than_faulting() -> void:
	# Decoders walk data whose length they only learn by decoding it.
	var rom: RomFile = RomFile.from_bytes(PackedByteArray([0x01]))
	assert_eq(rom.u8(99), 0)
	assert_eq(rom.u16le(0), 0, "a two-byte read needs two bytes")
	assert_eq(rom.slice(0, 4), PackedByteArray())
	assert_false(rom.in_bounds(1))


func test_negative_offsets_are_out_of_bounds() -> void:
	var rom: RomFile = RomFile.from_bytes(PackedByteArray([0x01, 0x02]))
	assert_false(rom.in_bounds(-1))
	assert_eq(rom.u8(-1), 0)


func test_slice_takes_a_length_not_an_end() -> void:
	var rom: RomFile = RomFile.from_bytes(PackedByteArray([1, 2, 3, 4, 5]))
	assert_eq(rom.slice(1, 3), PackedByteArray([2, 3, 4]))


func test_bank_zero_addresses_are_left_alone() -> void:
	assert_eq(RomFile.linear(0, 0x0100), 0x0100)


func test_the_switchable_window_folds_onto_its_bank() -> void:
	# $4000-$7FFF is a window: only the low 14 bits give a position in the bank.
	assert_eq(RomFile.linear(1, 0x4000), 0x4000)
	assert_eq(RomFile.linear(0x1E, 0x6D6C), 0x7AD6C)
	assert_eq(RomFile.linear(2, 0x4000), RomFile.linear(2, 0x0000))


func test_the_last_bank_of_a_cartridge_still_fits() -> void:
	var banks: int = RomRegistry.EXPECTED_SIZE / RomFile.BANK_SIZE
	assert_eq(RomFile.linear(banks - 1, 0x7FFF), RomRegistry.EXPECTED_SIZE - 1)


func test_an_unverified_file_is_refused() -> void:
	var path: String = "%s/not_a_game.gbc" % SCRATCH_DIR
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(_blank_cartridge())
	file.close()
	_made.append(path)

	# Right size, unknown contents: the offset tables would be meaningless.
	assert_null(RomFile.open_verified(path))


func test_a_missing_file_is_refused() -> void:
	assert_null(RomFile.open_verified("user://definitely_absent.gbc"))


func test_header_fields_are_read_from_their_documented_places() -> void:
	var data: PackedByteArray = _blank_cartridge()
	var title: String = "POKEMON_GLD"
	for i: int in title.length():
		data[RomHeader.TITLE_START + i] = title.unicode_at(i)
	data[RomHeader.CGB_FLAG] = RomHeader.CGB_COMPATIBLE
	data[RomHeader.CART_TYPE] = 0x10
	data[RomHeader.ROM_SIZE_CODE] = 0x06
	data[RomHeader.VERSION] = 0x01

	var header: RomHeader = RomHeader.parse(RomFile.from_bytes(data))
	assert_eq(header.title, title)
	assert_eq(header.cgb_flag, RomHeader.CGB_COMPATIBLE)
	assert_eq(header.cart_type, 0x10)
	assert_eq(header.version, 1)
	assert_eq(header.declared_rom_size(), RomRegistry.EXPECTED_SIZE)
	assert_true(header.is_color_game())


func test_the_title_stops_at_the_first_padding_byte() -> void:
	# Later cartridges reused the tail of the field, so it is not a plain string.
	var data: PackedByteArray = _blank_cartridge()
	for i: int in "PM_CRYSTAL".length():
		data[RomHeader.TITLE_START + i] = "PM_CRYSTAL".unicode_at(i)
	data[RomHeader.TITLE_START + 10] = 0x00
	data[RomHeader.TITLE_START + 11] = 0x42

	assert_eq(RomHeader.parse(RomFile.from_bytes(data)).title, "PM_CRYSTAL")


func test_the_global_checksum_is_the_one_big_endian_field() -> void:
	var data: PackedByteArray = _blank_cartridge()
	data[RomHeader.GLOBAL_CHECKSUM] = 0x68
	data[RomHeader.GLOBAL_CHECKSUM + 1] = 0x2D
	assert_eq(RomHeader.parse(RomFile.from_bytes(data)).global_checksum, 0x682D)


func test_the_header_checksum_matches_when_it_is_written_correctly() -> void:
	var data: PackedByteArray = _blank_cartridge()
	data[RomHeader.CART_TYPE] = 0x10
	var rom: RomFile = RomFile.from_bytes(data)

	var computed: int = RomHeader.compute_header_checksum(rom)
	data[RomHeader.HEADER_CHECKSUM] = computed
	assert_eq(RomHeader.parse(RomFile.from_bytes(data)).header_checksum, computed)

	# Changing any covered byte must change the result — the boot ROM's check.
	data[RomHeader.CART_TYPE] = 0x11
	assert_ne(RomHeader.compute_header_checksum(RomFile.from_bytes(data)), computed)


func test_the_global_checksum_excludes_its_own_bytes() -> void:
	var data: PackedByteArray = _blank_cartridge()
	data[0x200] = 0x10
	var without: int = RomHeader.compute_global_checksum(RomFile.from_bytes(data))

	data[RomHeader.GLOBAL_CHECKSUM] = 0xFF
	data[RomHeader.GLOBAL_CHECKSUM + 1] = 0xFF
	assert_eq(RomHeader.compute_global_checksum(RomFile.from_bytes(data)), without)
	assert_eq(without, 0x10)
