extends GutTest

## Synthetic byte strings only. The encoding is a fixed table, so it can be
## checked without a cartridge, and the importer's own layout check re-tests it
## against real data by insisting species 1 decodes to BULBASAUR.


func _encode(letters: String) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	for i: int in letters.length():
		out.append(0x80 + letters.unicode_at(i) - "A".unicode_at(0))
	return out


func test_uppercase_run_starts_at_0x80() -> void:
	assert_eq(Gen2Text.decode(_encode("ABZ"), 0, 10), "ABZ")


func test_lowercase_run_starts_at_0xa0() -> void:
	assert_eq(Gen2Text.decode(PackedByteArray([0xA0, 0xA1, 0xB9]), 0, 10), "abz")


func test_digits_run_starts_at_0xf6() -> void:
	assert_eq(Gen2Text.decode(PackedByteArray([0xF6, 0xF7, 0xFF]), 0, 10), "019")


func test_space_and_punctuation() -> void:
	assert_eq(Gen2Text.decode(PackedByteArray([0x7F, 0xE3, 0xF4, 0xE7]), 0, 10), " -,!")


func test_terminator_ends_the_string() -> void:
	var data: PackedByteArray = PackedByteArray([0x80, Gen2Text.TERMINATOR, 0x81])
	assert_eq(Gen2Text.decode(data, 0, 10), "A")


func test_max_length_is_respected_without_a_terminator() -> void:
	assert_eq(Gen2Text.decode(_encode("ABCDE"), 0, 3), "ABC")


func test_decoding_can_start_partway_in() -> void:
	assert_eq(Gen2Text.decode(_encode("ABC"), 1, 10), "BC")


func test_reading_past_the_end_stops_rather_than_faulting() -> void:
	assert_eq(Gen2Text.decode(_encode("AB"), 0, 64), "AB")
	assert_eq(Gen2Text.decode(PackedByteArray(), 0, 8), "")


func test_word_codes_expand() -> void:
	assert_eq(Gen2Text.decode(PackedByteArray([0x5D]), 0, 4), "TRAINER")
	assert_eq(Gen2Text.decode(PackedByteArray([0xE1, 0xE2]), 0, 4), "PKMN")


## constants/charmap.asm maps "#" to $54, so a synthesized literal writes the
## POKé ligature the way every source text does. Spelling it out instead is legal
## but costs three extra tiles, because $54 is below FIRST_PRINTABLE and so
## decode-only.
func test_hash_encodes_the_poke_ligature_the_source_charmap_names() -> void:
	assert_eq(Gen2Text.encode("#"), PackedByteArray([0x54]))
	assert_eq(Gen2Text.encoded_length("a #MON!"), 7)
	assert_eq(Gen2Text.decode(Gen2Text.encode("#MON"), 0, 16), "POKéMON")
	# Without the alias this drew UNKNOWN, the question-mark glyph.
	assert_ne(Gen2Text.encode("#")[0], Gen2Text.UNKNOWN)
	assert_eq(Gen2Text.encoded_length("POKéMON"), 7)


## $75 is decode-only for the same reason $54 is, and source text writes the
## character itself, so a synthesized line quoting it has to encode.
func test_ellipsis_encodes_the_source_charmap_code() -> void:
	assert_eq(Gen2Text.encode("…"), PackedByteArray([0x75]))
	assert_ne(Gen2Text.encode("…")[0], Gen2Text.UNKNOWN)
	assert_eq(Gen2Text.decode(Gen2Text.encode("1, 2 and…"), 0, 16), "1, 2 and…")
	## One tile, so a message using it is laid out at its real width.
	assert_eq(Gen2Text.encoded_length("and…"), 4)


func test_apostrophe_ligatures_expand_to_two_characters() -> void:
	# One tile in the font, two letters on screen.
	assert_eq(Gen2Text.decode(PackedByteArray([0x88, 0xD5]), 0, 4), "I't")


func test_unknown_byte_is_visible_rather_than_dropped() -> void:
	# A silently skipped byte would turn a wrong offset into a plausible name.
	assert_eq(Gen2Text.decode(PackedByteArray([0x80, 0x01]), 0, 4), "A<01>")


func test_a_sequence_walks_past_each_terminator() -> void:
	var data: PackedByteArray = _encode("AB")
	data.append(Gen2Text.TERMINATOR)
	data.append_array(_encode("CD"))
	data.append(Gen2Text.TERMINATOR)
	assert_eq(Gen2Text.decode_sequence(data, 0, 2, 8), PackedStringArray(["AB", "CD"]))


func test_a_sequence_stops_at_the_end_of_the_data() -> void:
	# Short is a failure the caller must be able to see: the move and item
	# tables are variable-length, so a wrong start runs off the end rather than
	# landing on a boundary.
	var data: PackedByteArray = _encode("AB")
	data.append(Gen2Text.TERMINATOR)
	assert_eq(Gen2Text.decode_sequence(data, 0, 4, 8).size(), 1)


func test_a_sequence_gives_up_on_an_entry_with_no_terminator() -> void:
	# The guard, not a field width: without it this walks the rest of the dump.
	var result: PackedStringArray = Gen2Text.decode_sequence(_encode("ABCDEFGH"), 0, 2, 3)
	assert_eq(result[0], "ABC")


func test_an_empty_entry_is_kept_rather_than_skipped() -> void:
	# Dropping it would shift every later name down by one.
	var data: PackedByteArray = PackedByteArray([Gen2Text.TERMINATOR, 0x80, Gen2Text.TERMINATOR])
	assert_eq(Gen2Text.decode_sequence(data, 0, 2, 8), PackedStringArray(["", "A"]))


func test_a_real_species_name_round_trips() -> void:
	# The bytes of "MEWTWO@" as they sit in the cartridge.
	var data: PackedByteArray = PackedByteArray([0x8C, 0x84, 0x96, 0x93, 0x96, 0x8E, 0x50])
	assert_eq(Gen2Text.decode(data, 0, 10), "MEWTWO")


func test_encoding_is_the_inverse_of_decoding_over_the_printable_range() -> void:
	for code: int in range(Gen2Text.FIRST_PRINTABLE, 0x100):
		var text: String = Gen2Text.character(code)
		if text.begins_with("<"):
			continue
		var codes: PackedByteArray = Gen2Text.encode(text)
		assert_eq(codes.size(), 1, "$%02X (%s) is one tile" % [code, text])
		assert_eq(Gen2Text.character(codes[0]), text, "$%02X did not round-trip" % code)


func test_a_ligature_is_two_characters_in_one_tile() -> void:
	# The font has no free-standing apostrophe followed by a letter, so anything
	# measuring a line has to ask rather than count characters.
	assert_eq(Gen2Text.encode("'s"), PackedByteArray([0xD4]))
	assert_eq(Gen2Text.encoded_length("It's"), 3)
	assert_eq("It's".length(), 4, "which is not what the string says")


func test_only_the_lowercase_ligatures_exist() -> void:
	# The font has "'s" as one tile and no "'S", so a name in capitals costs a
	# tile more than the same name in lower case.
	assert_eq(Gen2Text.encoded_length("IT'S"), 4)


func test_a_ligature_wins_over_the_characters_it_is_made_of() -> void:
	# Longest match first, or "'s" encodes as an apostrophe and a lowercase s.
	assert_eq(Gen2Text.encoded_length("It's not"), 7)


func test_the_full_stop_beats_the_decimal_point() -> void:
	# Two codes draw a dot. $E8 is the one sentences end with; $F2 is narrower
	# and belongs between digits.
	assert_eq(Gen2Text.encode("."), PackedByteArray([0xE8]))


func test_a_character_the_font_cannot_draw_becomes_a_question_mark() -> void:
	# Visible rather than dropped, on the same principle as an unrecognised byte
	# on the way in.
	assert_eq(Gen2Text.encode("~"), PackedByteArray([Gen2Text.UNKNOWN]))
	assert_eq(Gen2Text.encoded_length("a~b"), 3, "and it still takes a tile")


func test_control_codes_are_decode_only() -> void:
	# A newline is a layout decision here, not a byte, and a name substituted at
	# print time is not a glyph.
	assert_eq(Gen2Text.encode("\n"), PackedByteArray([Gen2Text.UNKNOWN]))
	for code: int in Gen2Text.encode("<PLAYER>"):
		assert_true(code >= Gen2Text.FIRST_PRINTABLE or code == Gen2Text.SPACE)


func test_a_space_encodes_even_though_the_font_has_no_tile_for_it() -> void:
	assert_eq(Gen2Text.encode(" "), PackedByteArray([Gen2Text.SPACE]))
	assert_true(Gen2Text.SPACE < Gen2Text.FIRST_PRINTABLE, "so it draws nothing")
