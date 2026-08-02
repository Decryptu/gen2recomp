extends GutTest

## Wrapping and pagination. No font, no screen: the whole of what a text box
## decides about a string can be settled here.

const COLUMNS: int = 18
const ROWS: int = 2


func test_a_short_line_is_left_alone() -> void:
	assert_eq(Gen2TextLayout.wrap_lines("HELLO", COLUMNS), PackedStringArray(["HELLO"]))


func test_a_line_breaks_at_a_space() -> void:
	var lines: PackedStringArray = Gen2TextLayout.wrap_lines("BULBASAUR used TACKLE", COLUMNS)
	assert_eq(lines, PackedStringArray(["BULBASAUR used", "TACKLE"]))


func test_a_line_is_filled_to_the_last_column() -> void:
	var lines: PackedStringArray = Gen2TextLayout.wrap_lines("aaa bbb ccc ddd eee", 11)
	assert_eq(lines[0], "aaa bbb ccc")


func test_wrapping_counts_tiles_not_characters() -> void:
	# "It's" is four characters and three tiles, so counting characters wraps a
	# column early and the box looks narrower than it is.
	var text: String = "It's it's it's"
	assert_eq(Gen2TextLayout.wrap_lines(text, 11).size(), 1)
	assert_eq(text.length(), 14, "which would not have fit")


func test_an_explicit_newline_is_obeyed() -> void:
	# A caller that has already decided where a line ends is not second-guessed.
	assert_eq(Gen2TextLayout.wrap_lines("A\nB", COLUMNS), PackedStringArray(["A", "B"]))


func test_a_word_longer_than_a_line_is_cut_rather_than_overflowing() -> void:
	# Nothing in the cartridges is this long. A mod's text is not the
	# cartridge's, and text running off the edge of the screen is worse.
	var lines: PackedStringArray = Gen2TextLayout.wrap_lines("abcdefghij", 4)
	assert_eq(lines, PackedStringArray(["abcd", "efgh", "ij"]))


func test_no_line_is_wider_than_the_box() -> void:
	var text: String = "There's a time and place for everything, but not now."
	for line: String in Gen2TextLayout.wrap_lines(text, COLUMNS):
		assert_lte(Gen2Text.encoded_length(line), COLUMNS, "'%s' is too wide" % line)


func test_zero_columns_lays_nothing_out_rather_than_looping() -> void:
	assert_eq(Gen2TextLayout.wrap_lines("HELLO", 0).size(), 0)


func test_pages_hold_as_many_lines_as_the_box_shows() -> void:
	var lines := PackedStringArray(["a", "b", "c", "d"])
	assert_eq(Gen2TextLayout.paginate(lines, ROWS).size(), 2)


func test_a_part_full_last_page_is_kept() -> void:
	var pages: Array = Gen2TextLayout.paginate(PackedStringArray(["a", "b", "c"]), ROWS)
	assert_eq(pages.size(), 2)
	assert_eq(pages[1], PackedStringArray(["c"]))


func test_laying_out_gives_pages_of_lines_that_all_fit() -> void:
	var text: String = "BULBASAUR used TACKLE! It's not very effective against a GHOST."
	var pages: Array = Gen2TextLayout.lay_out(text, COLUMNS, ROWS)
	assert_gt(pages.size(), 1, "more than one box full")
	for page: PackedStringArray in pages:
		assert_lte(page.size(), ROWS)
		for line: String in page:
			assert_lte(Gen2Text.encoded_length(line), COLUMNS)


func test_nothing_is_lost_between_the_string_and_the_pages() -> void:
	var text: String = "The quick brown fox jumps over the lazy dog"
	var words: PackedStringArray = PackedStringArray()
	for page: PackedStringArray in Gen2TextLayout.lay_out(text, COLUMNS, ROWS):
		for line: String in page:
			words.append_array(line.split(" ", false))
	assert_eq(" ".join(words), text)
