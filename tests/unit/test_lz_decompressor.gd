extends GutTest

## Every command is exercised against a stream built here, so a failure points
## at one opcode rather than at "graphics are broken". No cartridge is involved.

var _lz: Gen2Lz


func before_each() -> void:
	_lz = Gen2Lz.new()


func _stream(bytes: Array) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray(bytes)
	out.append(Gen2Lz.TERMINATOR)
	return out


func test_literal_copies_verbatim() -> void:
	# 000 with length 4, then the bytes.
	var data: PackedByteArray = _stream([0x03, 0xDE, 0xAD, 0xBE, 0xEF])
	assert_eq(_lz.decompress(data, 0), PackedByteArray([0xDE, 0xAD, 0xBE, 0xEF]))
	assert_false(_lz.failed)


func test_iterate_repeats_one_byte() -> void:
	var data: PackedByteArray = _stream([0x20 | 0x04, 0xAB])
	assert_eq(_lz.decompress(data, 0), PackedByteArray([0xAB, 0xAB, 0xAB, 0xAB, 0xAB]))


func test_alternate_repeats_a_pair() -> void:
	var data: PackedByteArray = _stream([0x40 | 0x03, 0x11, 0x22])
	assert_eq(_lz.decompress(data, 0), PackedByteArray([0x11, 0x22, 0x11, 0x22]))


func test_zero_fill_needs_no_operand() -> void:
	var data: PackedByteArray = _stream([0x60 | 0x02])
	assert_eq(_lz.decompress(data, 0), PackedByteArray([0x00, 0x00, 0x00]))


func test_repeat_reads_back_with_a_relative_offset() -> void:
	# Literal "AB", then repeat 2 bytes starting 2 back.
	var data: PackedByteArray = _stream([0x01, 0x41, 0x42, 0x80 | 0x01, 0x81])
	assert_eq(_lz.decompress(data, 0), PackedByteArray([0x41, 0x42, 0x41, 0x42]))


func test_repeat_reads_back_with_an_absolute_offset() -> void:
	# The two-byte form addresses from the start of the output, not the head.
	var data: PackedByteArray = _stream([0x01, 0x41, 0x42, 0x80 | 0x01, 0x00, 0x00])
	assert_eq(_lz.decompress(data, 0), PackedByteArray([0x41, 0x42, 0x41, 0x42]))


func test_repeat_may_overlap_the_bytes_it_is_writing() -> void:
	# Source one byte back, length four: the format's way of spelling a run.
	var data: PackedByteArray = _stream([0x00, 0x07, 0x80 | 0x03, 0x80])
	assert_eq(_lz.decompress(data, 0), PackedByteArray([0x07, 0x07, 0x07, 0x07, 0x07]))


func test_flipped_repeat_reverses_each_byte() -> void:
	var data: PackedByteArray = _stream([0x00, 0b0000_0001, 0xA0 | 0x00, 0x80])
	assert_eq(_lz.decompress(data, 0), PackedByteArray([0b0000_0001, 0b1000_0000]))


func test_reversed_repeat_walks_backwards() -> void:
	var data: PackedByteArray = _stream([0x02, 0x01, 0x02, 0x03, 0xC0 | 0x02, 0x80])
	assert_eq(_lz.decompress(data, 0), PackedByteArray([0x01, 0x02, 0x03, 0x03, 0x02, 0x01]))


func test_long_command_borrows_two_length_bits() -> void:
	# 111 escapes; the opcode moves to bits 4-2 and the length grows to 10 bits.
	# Here: zero fill, length 0x101 + 1.
	var command: int = 0xE0 | (Gen2Lz.Op.ZERO << 2) | 0x01
	var data: PackedByteArray = _stream([command, 0x01])
	var out: PackedByteArray = _lz.decompress(data, 0)
	assert_false(_lz.failed)
	assert_eq(out.size(), 0x102)


func test_short_command_length_maxes_at_32() -> void:
	var data: PackedByteArray = _stream([0x60 | 0x1F])
	assert_eq(_lz.decompress(data, 0).size(), Gen2Lz.MAX_SHORT_LENGTH)


func test_consumed_counts_the_terminator() -> void:
	var data: PackedByteArray = _stream([0x01, 0x41, 0x42])
	_lz.decompress(data, 0)
	assert_eq(_lz.consumed, 4)


func test_decoding_can_start_partway_in() -> void:
	var data: PackedByteArray = PackedByteArray([0xFF, 0xFF, 0x00, 0x77, Gen2Lz.TERMINATOR])
	assert_eq(_lz.decompress(data, 2), PackedByteArray([0x77]))


func test_truncated_stream_fails_rather_than_returning_short() -> void:
	# Literal claiming four bytes with only two present, and no terminator.
	var data: PackedByteArray = PackedByteArray([0x03, 0xDE, 0xAD])
	assert_eq(_lz.decompress(data, 0), PackedByteArray())
	assert_true(_lz.failed)


func test_missing_terminator_fails() -> void:
	assert_eq(_lz.decompress(PackedByteArray([0x00, 0x41]), 0), PackedByteArray())
	assert_true(_lz.failed)


func test_back_reference_past_the_start_fails() -> void:
	# Nothing has been written yet, so there is nothing to copy.
	assert_eq(_lz.decompress(_stream([0x80 | 0x01, 0x80]), 0), PackedByteArray())
	assert_true(_lz.failed)


func test_failure_clears_on_the_next_run() -> void:
	_lz.decompress(PackedByteArray([0x00]), 0)
	assert_true(_lz.failed)
	_lz.decompress(_stream([0x00, 0x01]), 0)
	assert_false(_lz.failed, "state from a failed run leaked into the next")


func test_static_helper_matches_the_instance() -> void:
	var data: PackedByteArray = _stream([0x01, 0x41, 0x42])
	assert_eq(Gen2Lz.unpack(data, 0), _lz.decompress(data, 0))
