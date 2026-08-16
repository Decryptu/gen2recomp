extends GutTest

## `home/text.asm`'s two layers, checked against byte sequences taken from the
## pinned sources rather than invented.

const PARA: String = Gen2TextStream.PAGE_BREAK
const SCROLL: String = Gen2TextStream.SCROLL_BREAK


func test_a_literal_ends_at_the_at_sign_and_the_command_loop_goes_on() -> void:
	## `text "A@"` then `text "B"` then `done`: the $50 closes the first literal,
	## it does not end the text, and $57 is what ends it.
	var decoded: Dictionary = Gen2TextStream.decode(
		PackedByteArray([0x00, 0x80, 0x50, 0x00, 0x81, 0x57])
	)
	assert_true(decoded["ok"])
	assert_eq(decoded["text"], "AB")


func test_the_oak_speech_beats_stop_where_their_own_text_does() -> void:
	## `_OakText2` ends `cont "#MON.@"` + `text_end`, and `_OakText3` is a bare
	## `text_promptbutton`. Reading $50 as a page break walked into it and drew
	## the command bytes as `?06?` and `?00?`.
	var decoded: Dictionary = Gen2TextStream.decode(PackedByteArray([
		0x00, 0x82, 0x55, 0x83, 0x50, 0x50,
		0x06, 0x50,
		0x00, 0x84, 0x50,
	]))
	assert_true(decoded["ok"])
	assert_eq(decoded["text"], "C" + SCROLL + "D")
	assert_eq(decoded["bytes"], 6)


func test_text_commands_are_not_characters() -> void:
	for command: int in [0x06, 0x0D]:
		var decoded: Dictionary = Gen2TextStream.decode(PackedByteArray([command, 0x50]))
		assert_true(decoded["ok"], "command %02X" % command)
		assert_eq(decoded["text"], PARA, "command %02X" % command)
		assert_true(bool(decoded["prompt"]), "command %02X" % command)


func test_the_received_item_text_reads_its_ram_pointer() -> void:
	## `_ReceivedItemText`: text "<PLAYER> received" / line "@" /
	## text_ram wStringBuffer4 / text "." / done. Drawn without the command
	## layer this was `?PLAYER? received` then `?50??01?e?CF??00?.`.
	var decoded: Dictionary = Gen2TextStream.decode(
		PackedByteArray([
			0x00, 0x52, 0x7F, 0x8B, 0x4F, 0x50,
			0x01, 0xA4, 0xCF,
			0x00, 0xE8, 0x57,
		]),
		0,
		{"player": "GOLD", "ram": {0xCFA4: "POTION"}},
	)
	assert_true(decoded["ok"])
	assert_eq(decoded["text"], "GOLD L\nPOTION.")


func test_the_print_time_names_are_substituted() -> void:
	var decoded: Dictionary = Gen2TextStream.decode(
		PackedByteArray([0x00, 0x52, 0x53, 0x49, 0x50]),
		0,
		{"player": "A", "rival": "B", "mom": "C"},
	)
	assert_eq(decoded["text"], "ABC")


func test_a_name_with_nobody_to_ask_stays_a_marker() -> void:
	var decoded: Dictionary = Gen2TextStream.decode(PackedByteArray([0x00, 0x52, 0x50]))
	assert_eq(decoded["text"], "<PLAYER>")


func test_the_same_byte_is_a_buffer_command_and_the_player_inside_a_literal() -> void:
	# Elm's "#MON's first partner, <PLAY_G>!": $14 after TX_START is a character
	# `CheckDict` sends to `PlaceGenderedPlayerName`, not a second command.
	var literal: Dictionary = Gen2TextStream.decode(
		PackedByteArray([0x00, 0x14, 0xE7, 0x50]), 0, {"player": "GOLD"}
	)
	assert_eq(literal["text"], "GOLD!")
	var command: Dictionary = Gen2TextStream.decode(
		PackedByteArray([0x14, 0x03, 0x50]), 0, {"player": "GOLD", "buffers": {3: "TM24"}}
	)
	assert_eq(command["text"], "TM24")


func test_a_string_buffer_is_read_by_number() -> void:
	var decoded: Dictionary = Gen2TextStream.decode(
		PackedByteArray([0x14, 0x03, 0x50]), 0, {"buffers": {3: "TM24"}}
	)
	assert_eq(decoded["text"], "TM24")


func test_text_far_runs_the_target_as_a_text_of_its_own() -> void:
	var far: Callable = func(bank: int, address: int) -> PackedByteArray:
		if bank == 0x21 and address == 0x4321:
			return PackedByteArray([0x00, 0x80, 0x57])
		return PackedByteArray()
	var decoded: Dictionary = Gen2TextStream.decode(
		PackedByteArray([0x16, 0x21, 0x43, 0x21]), 0, {"far": far}
	)
	assert_true(decoded["ok"])
	assert_eq(decoded["text"], "A")


func test_para_and_cont_are_different_breaks() -> void:
	var decoded: Dictionary = Gen2TextStream.decode(
		PackedByteArray([0x00, 0x80, 0x51, 0x81, 0x55, 0x82, 0x57])
	)
	assert_eq(decoded["text"], "A" + PARA + "B" + SCROLL + "C")


func test_a_text_that_never_terminates_is_refused() -> void:
	var decoded: Dictionary = Gen2TextStream.decode(PackedByteArray([0x00, 0x80]))
	assert_false(decoded["ok"])
	assert_eq(decoded["reason"], &"missing_text_terminator")


func test_an_unknown_command_byte_is_refused_rather_than_drawn() -> void:
	var decoded: Dictionary = Gen2TextStream.decode(PackedByteArray([0x30, 0x50]))
	assert_false(decoded["ok"])
	assert_eq(decoded["reason"], &"unknown_text_command")


## `Paragraph` clears the box; `_ContText` scrolls, so the line above survives.
func test_the_layout_carries_a_line_over_a_scroll_but_not_a_paragraph() -> void:
	var scrolled: Array = Gen2TextLayout.lay_out("one\ntwo" + SCROLL + "three", 20, 2)
	assert_eq(scrolled.size(), 2)
	assert_eq(Array(scrolled[0]), ["one", "two"])
	assert_eq(Array(scrolled[1]), ["two", "three"])

	var paged: Array = Gen2TextLayout.lay_out("one\ntwo" + PARA + "three", 20, 2)
	assert_eq(paged.size(), 2)
	assert_eq(Array(paged[1]), ["three"])
