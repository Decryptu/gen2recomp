extends GutTest

## Wrapping, pagination, and the box walking the pages they make. No font and no
## screen are needed for any of it: [method Gen2TextBox._redraw] draws nothing
## without a font, so the paging and the scroll can be driven frame by frame
## here rather than photographed.

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


## `Paragraph`, `_ContText` and `_ContTextNoPause` are three different ways into
## the next page, and only the box can tell them apart from the lines.
func test_a_page_says_how_it_was_reached() -> void:
	var text: String = "a" + Gen2TextStream.PAGE_BREAK + "b" \
		+ Gen2TextStream.SCROLL_BREAK + "c" + Gen2TextStream.SCROLL_NOWAIT_BREAK + "d"
	var pages: Array = Gen2TextLayout.lay_out_pages(text, COLUMNS, ROWS)
	assert_eq(pages.size(), 4)
	assert_eq(StringName(pages[0]["enter"]), &"start")
	assert_eq(StringName(pages[1]["enter"]), &"page")
	assert_eq(StringName(pages[2]["enter"]), &"scroll")
	assert_eq(StringName(pages[3]["enter"]), &"scroll_nowait")
	## Both scrolls keep the line that was underneath, which a cleared page does
	## not.
	assert_eq(pages[1]["lines"], PackedStringArray(["b"]))
	assert_eq(pages[2]["lines"], PackedStringArray(["b", "c"]))


const FRAME: float = 1.0 / 60.0


func _box() -> Gen2TextBox:
	var box: Gen2TextBox = autofree(Gen2TextBox.new())
	box.columns = Gen2TextBox.STANDARD_COLUMNS
	box.rows = Gen2TextBox.STANDARD_ROWS
	# Nothing to reveal a tile at a time: this is about the waits between pages.
	box.reveal_speed = 0.0
	return box


## `PrintLetterDelay` is the only thing a button reaches while a text is still
## printing, and the most it does there is one letter a frame. There is no path
## from a press to the end of a page, so a repeated press cannot tear through a
## text: it is spent and the page keeps printing at its own rate.
func test_a_press_cannot_finish_a_printing_page() -> void:
	var box: Gen2TextBox = _box()
	box.reveal_speed = 30.0
	box.show_text("hello there" + Gen2TextStream.PAGE_BREAK + "second")
	assert_true(box.is_revealing())

	for _press: int in 20:
		assert_true(box.advance(), "the press is spent on the box")
	assert_true(box.is_revealing(), "and the page is still printing")
	assert_true(box.has_pages_left(), "so no page was turned")

	# It finishes on frames, and only then does a press turn the page.
	var owed: int = box.frames_left()
	assert_gt(owed, 0)
	for _frame: int in owed:
		box.advance_frame()
	assert_false(box.is_revealing(), "frames_left() is enough to finish the page")
	assert_true(box.advance())
	assert_false(box.has_pages_left())


## `PrintLetterDelay` answers a HELD A or B with a single `DelayFrame`, whatever
## TEXT SPEED says, so holding one prints at the fastest the setting reaches and
## never faster.
func test_holding_a_button_prints_one_letter_a_frame() -> void:
	var slow: Gen2TextBox = _box()
	slow.reveal_speed = 12.0
	slow.show_text("hello there")
	var patient: int = slow.frames_left()

	var held: Gen2TextBox = _box()
	held.reveal_speed = 12.0
	held.show_text("hello there")
	held.accelerated = true
	assert_lt(held.frames_left(), patient, "a held button is faster than TEXT SPEED slow")

	for _frame: int in held.frames_left():
		held.advance_frame()
	assert_false(held.is_revealing())
	assert_eq(held.frames_left(), 0)


## `_ContText` is `PromptButton` and then `TextScroll` twice, five frames each,
## so a continuation costs one press and ten frames rather than a page turn.
func test_a_continuation_scrolls_for_ten_frames_after_its_press() -> void:
	var box: Gen2TextBox = _box()
	box.show_text("a" + Gen2TextStream.SCROLL_BREAK + "b")
	assert_true(box.has_pages_left())
	assert_false(box.is_revealing(), "the first page is up and waiting")

	assert_true(box.advance(), "the press starts the scroll rather than the page")
	assert_true(box.is_revealing(), "and nothing is waited for while it runs")
	for _frame: int in Gen2TextBox.SCROLL_STEP_FRAMES * Gen2TextBox.SCROLL_STEPS - 1:
		box._process(FRAME)
		assert_true(box.is_revealing(), "still scrolling")
	box._process(FRAME)
	assert_false(box.is_revealing())
	assert_false(box.has_pages_left(), "the second page is up")


## `_ContTextNoPause` has no `PromptButton` in front of those two scrolls, so
## `<SCROLL>` rolls the box on with no press at all.
func test_a_no_pause_scroll_runs_itself() -> void:
	var box: Gen2TextBox = _box()
	box.show_text("a" + Gen2TextStream.SCROLL_NOWAIT_BREAK + "b")
	assert_true(box.has_pages_left())

	for _frame: int in Gen2TextBox.SCROLL_STEP_FRAMES * Gen2TextBox.SCROLL_STEPS + 1:
		box._process(FRAME)
	assert_false(box.has_pages_left(), "the second page arrived without a press")
	assert_false(box.is_revealing())


## `LoadBlinkingCursor` is reached by `Paragraph`, `_ContText` and `PromptText`
## and by nothing else, and `WaitPressAorB_BlinkCursor` says so itself: "The
## cursor has to be shown before calling this function or no cursor will be shown
## at all." So a text ending in `done` prints its last page with no arrow and the
## caller runs on, which is `SendOutMonText`'s "Go! <MON>!"; and a caller waiting
## with `JoyWaitAorB` shows none either way, which is every page of
## `ProfOaksPCBoot` including the one ending in `prompt`.
func test_a_text_nothing_loaded_a_cursor_for_draws_no_arrow() -> void:
	var waiting: Gen2TextBox = _box()
	waiting.show_text("hello there")
	assert_false(waiting.is_revealing())
	assert_true(waiting.cursor_visible(), "a prompt text blinks its arrow")

	var running_on: Gen2TextBox = _box()
	running_on.show_text("hello there", false)
	assert_false(running_on.is_revealing())
	assert_false(running_on.cursor_visible())


## Only the *last* page is exempt: a page with another behind it is reached
## through `Paragraph` or `_ContText`, both of which load the cursor whatever
## ends the text.
func test_a_page_break_blinks_even_when_the_text_runs_on() -> void:
	var box: Gen2TextBox = _box()
	box.show_text("first" + Gen2TextStream.PAGE_BREAK + "second", false)
	assert_true(box.has_pages_left())
	assert_true(box.cursor_visible(), "the page break waits like any other")
	assert_true(box.advance())
	assert_false(box.has_pages_left())
	assert_false(box.cursor_visible(), "and the last page does not")
