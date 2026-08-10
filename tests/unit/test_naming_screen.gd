extends GutTest

## `engine/menus/naming_screen.asm`'s walk: the wrapping cursor, the command row
## read by column, TryAddCharacter, DeleteCharacter, the case switch and what
## comes out of StoreEntry.
##
## The keyboards are the synthetic ones this file writes, with the real block's
## shape and the real command row. What is under a letter key does not matter to
## any rule here, only that the cursor reads the cell it is standing on, so the
## letters are generated and their codes are what the tests assert against.

const TABLE_ROWS: Array[int] = [5, 6, 5, 6]
const SPACE: int = 0x7F
const NAME_ROWS: int = 5
const BOX_ROWS: int = 6

var _directory: String = ""
var _data: GameData = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"testnamescreen", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()
	_data = GameData.open_directory(_directory)


func after_each() -> void:
	RomCache.clear(_directory)


func _write_cache() -> void:
	var tables: Array = []
	for table: int in TABLE_ROWS.size():
		var first: int = RomLayout.NAME_INPUT_LOWER_A if table < 2 else RomLayout.NAME_INPUT_UPPER_A
		var rows: Array = []
		for row: int in TABLE_ROWS[table]:
			if row == TABLE_ROWS[table] - 1:
				rows.append(Array(
					RomLayout.NAME_INPUT_COMMAND_LOWER if table < 2
					else RomLayout.NAME_INPUT_COMMAND_UPPER
				))
				continue
			var codes: Array[int] = []
			for column: int in RomLayout.NAME_INPUT_COLUMNS:
				codes.append(first + row * RomLayout.NAME_INPUT_COLUMNS + column)
			rows.append(_spread(codes))
		tables.append(rows)
	RomCache.write_json(RomCache.name_input_chars_path(_directory), tables)
	for path: String in [
		RomCache.species_path(_directory), RomCache.moves_path(_directory),
		RomCache.items_path(_directory), RomCache.types_path(_directory),
		RomCache.matchups_path(_directory), RomCache.trainers_path(_directory),
	]:
		RomCache.write_json(path, [])
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"complete": true,
		"game_id": "testnamescreen",
	})


func _spread(values: Array) -> Array:
	var row: Array[int] = []
	for column: int in RomLayout.NAME_INPUT_COLUMNS:
		row.append(int(values[column]))
		if column < RomLayout.NAME_INPUT_COLUMNS - 1:
			row.append(SPACE)
	return row


func _screen() -> Gen2NamingScreen:
	return Gen2NamingScreen.for_player(_data)


## The code the generated keyboard puts at a cell, so a test can say which key
## the cursor is standing on.
func _letter(upper: bool, row: int, column: int) -> int:
	var first: int = RomLayout.NAME_INPUT_UPPER_A if upper else RomLayout.NAME_INPUT_LOWER_A
	return first + row * RomLayout.NAME_INPUT_COLUMNS + column


func _type(screen: Gen2NamingScreen, cells: Array) -> void:
	for cell: Vector2i in cells:
		screen.column = cell.x
		screen.row = cell.y
		screen.press_a()


# --- the keyboard the cursor reads -------------------------------------------

## NamingScreen_InitText loads NameInputUpper before anything is pressed, and
## NamingScreen_ApplyTextInputMode picks the box table out of the same pair.
func test_the_upper_name_keyboard_is_live_first() -> void:
	assert_eq(_screen().keyboard(), Gen2NamingScreen.Keyboard.NAME_UPPER)
	assert_eq(Gen2NamingScreen.for_box(_data).keyboard(), Gen2NamingScreen.Keyboard.BOX_UPPER)


func test_the_case_switch_swaps_the_table_and_leaves_the_cursor_alone() -> void:
	var screen: Gen2NamingScreen = _screen()
	screen.column = 4
	screen.row = 1
	screen.press_select()
	assert_eq(screen.keyboard(), Gen2NamingScreen.Keyboard.NAME_LOWER)
	assert_eq(screen.column, 4)
	assert_eq(screen.row, 1)
	screen.press_select()
	assert_eq(screen.keyboard(), Gen2NamingScreen.Keyboard.NAME_UPPER)


## NamingScreen_GetLastCharacter reads every second byte of the row, so column
## n is byte 2n and the blank between two letters is never reachable.
func test_the_cursor_reads_the_cell_it_stands_on() -> void:
	var screen: Gen2NamingScreen = _screen()
	assert_eq(screen.last_character(), _letter(true, 0, 0))
	screen.column = 3
	screen.row = 2
	assert_eq(screen.last_character(), _letter(true, 2, 3))
	screen.press_select()
	assert_eq(screen.last_character(), _letter(false, 2, 3))


# --- the cursor walk ----------------------------------------------------------

func test_a_letter_row_wraps_in_both_directions() -> void:
	var screen: Gen2NamingScreen = _screen()
	screen.move(Vector2i.LEFT)
	assert_eq(screen.column, Gen2NamingScreen.LAST_COLUMN, "left off column 0 wraps to the last")
	screen.move(Vector2i.RIGHT)
	assert_eq(screen.column, 0, "right off the last wraps to 0")
	screen.move(Vector2i.RIGHT)
	assert_eq(screen.column, 1)


## `.down`'s `cp $4` against `cp $5`: a name keyboard has five rows and a box
## keyboard six, and both wrap to the top.
func test_rows_wrap_at_the_keyboards_own_height() -> void:
	var screen: Gen2NamingScreen = _screen()
	for row: int in NAME_ROWS - 1:
		screen.move(Vector2i.DOWN)
	assert_eq(screen.row, NAME_ROWS - 1)
	screen.move(Vector2i.DOWN)
	assert_eq(screen.row, 0, "down off the command row wraps to the top")
	screen.move(Vector2i.UP)
	assert_eq(screen.row, NAME_ROWS - 1, "up off the top wraps to the command row")

	var box: Gen2NamingScreen = Gen2NamingScreen.for_box(_data)
	box.move(Vector2i.UP)
	assert_eq(box.row, BOX_ROWS - 1, "a box keyboard wraps one row lower")


# --- the command row ----------------------------------------------------------

## NamingScreen_GetCursorPosition reads the last row by column: under 3 is the
## case switch, under 6 is DEL, otherwise END.
func test_the_command_row_is_read_by_column() -> void:
	var screen: Gen2NamingScreen = _screen()
	screen.row = screen.command_row()
	var expected: Array[int] = [
		Gen2NamingScreen.COMMAND_CASE, Gen2NamingScreen.COMMAND_CASE,
		Gen2NamingScreen.COMMAND_CASE, Gen2NamingScreen.COMMAND_DELETE,
		Gen2NamingScreen.COMMAND_DELETE, Gen2NamingScreen.COMMAND_DELETE,
		Gen2NamingScreen.COMMAND_END, Gen2NamingScreen.COMMAND_END,
		Gen2NamingScreen.COMMAND_END,
	]
	for column: int in expected.size():
		screen.column = column
		assert_eq(screen.cursor_command(), expected[column], "column %d" % column)


func test_no_other_row_answers_a_command() -> void:
	var screen: Gen2NamingScreen = _screen()
	for row: int in NAME_ROWS - 1:
		screen.row = row
		for column: int in Gen2NamingScreen.COLUMNS:
			screen.column = column
			assert_eq(screen.cursor_command(), Gen2NamingScreen.COMMAND_NONE)


## `.target_right` and `.target_left` step between the three commands and snap
## the column to the group, so the raw column an arrival left behind is dropped.
func test_horizontal_movement_on_the_command_row_steps_between_commands() -> void:
	var screen: Gen2NamingScreen = _screen()
	screen.row = screen.command_row()
	screen.column = 0
	screen.move(Vector2i.RIGHT)
	assert_eq(screen.cursor_command(), Gen2NamingScreen.COMMAND_DELETE)
	assert_eq(screen.column, 3)
	screen.move(Vector2i.RIGHT)
	assert_eq(screen.cursor_command(), Gen2NamingScreen.COMMAND_END)
	assert_eq(screen.column, 6)
	screen.move(Vector2i.RIGHT)
	assert_eq(screen.cursor_command(), Gen2NamingScreen.COMMAND_CASE, "END wraps to the switch")
	assert_eq(screen.column, 0)

	screen.move(Vector2i.LEFT)
	assert_eq(screen.cursor_command(), Gen2NamingScreen.COMMAND_END, "the switch wraps to END")
	assert_eq(screen.column, 6)
	screen.move(Vector2i.LEFT)
	assert_eq(screen.cursor_command(), Gen2NamingScreen.COMMAND_DELETE)
	assert_eq(screen.column, 3)


## Arriving from a letter row keeps the raw column, so column 8 reads as END
## until a horizontal press snaps it back to 6.
func test_arriving_on_the_command_row_keeps_the_column_it_came_with() -> void:
	var screen: Gen2NamingScreen = _screen()
	screen.column = 8
	screen.row = NAME_ROWS - 2
	screen.move(Vector2i.DOWN)
	assert_eq(screen.column, 8)
	assert_eq(screen.cursor_command(), Gen2NamingScreen.COMMAND_END)
	screen.move(Vector2i.LEFT)
	assert_eq(screen.column, 3, "the first press snaps to the group")


func test_a_on_the_command_row_answers_the_command_rather_than_a_letter() -> void:
	var screen: Gen2NamingScreen = _screen()
	screen.row = screen.command_row()
	screen.column = 0
	assert_eq(screen.press_a(), Gen2NamingScreen.RESULT_CASE)
	assert_eq(screen.keyboard(), Gen2NamingScreen.Keyboard.NAME_LOWER)
	screen.column = 6
	assert_eq(screen.press_a(), Gen2NamingScreen.RESULT_END)


# --- typing -------------------------------------------------------------------

func test_a_new_entry_is_an_underline_then_middlelines_then_the_terminator() -> void:
	var screen: Gen2NamingScreen = _screen()
	assert_eq(screen.length, 0)
	assert_eq(screen.buffer[0], Gen2NamingScreen.UNDERLINE)
	for index: int in range(1, Gen2NamingScreen.PLAYER_MAX_LENGTH):
		assert_eq(screen.buffer[index], Gen2NamingScreen.MIDDLELINE, "slot %d" % index)
	assert_eq(screen.buffer[Gen2NamingScreen.PLAYER_MAX_LENGTH], Gen2NamingScreen.TERMINATOR)
	assert_eq(screen.stored_name(), "")


## TryAddCharacter writes the code and moves the underline on to the next slot.
func test_adding_a_character_moves_the_underline_along() -> void:
	var screen: Gen2NamingScreen = _screen()
	assert_eq(screen.press_a(), Gen2NamingScreen.RESULT_LETTER)
	assert_eq(screen.length, 1)
	assert_eq(screen.buffer[0], _letter(true, 0, 0))
	assert_eq(screen.buffer[1], Gen2NamingScreen.UNDERLINE)
	assert_eq(screen.buffer[2], Gen2NamingScreen.MIDDLELINE)


## DeleteCharacter puts the underline back and turns the one it left behind into
## a middleline again, so the entry looks untouched.
func test_delete_puts_the_markers_back() -> void:
	var screen: Gen2NamingScreen = _screen()
	screen.press_a()
	screen.press_a()
	assert_eq(screen.length, 2)
	screen.press_b()
	assert_eq(screen.length, 1)
	assert_eq(screen.buffer[1], Gen2NamingScreen.UNDERLINE)
	assert_eq(screen.buffer[2], Gen2NamingScreen.MIDDLELINE)
	screen.press_b()
	assert_eq(screen.length, 0)
	assert_eq(screen.buffer[0], Gen2NamingScreen.UNDERLINE)
	assert_eq(screen.buffer[1], Gen2NamingScreen.MIDDLELINE)


func test_delete_on_an_empty_entry_does_nothing() -> void:
	var screen: Gen2NamingScreen = _screen()
	screen.press_b()
	assert_eq(screen.length, 0)
	assert_eq(screen.buffer[0], Gen2NamingScreen.UNDERLINE)


## StoreEntry turns every marker still in the buffer into a terminator, so the
## name is what was typed and nothing behind it.
func test_the_stored_name_stops_where_the_typing_did() -> void:
	var screen: Gen2NamingScreen = _screen()
	# Row 0 of the upper keyboard is A to I, so columns 0, 1 and 2 are ABC.
	_type(screen, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	assert_eq(screen.length, 3)
	assert_eq(screen.stored_name(), "ABC")
	assert_eq(screen.stored_codes().size(), 3)


func test_the_case_switch_reaches_the_other_keyboards_letters() -> void:
	var screen: Gen2NamingScreen = _screen()
	_type(screen, [Vector2i(0, 0)])
	screen.press_select()
	_type(screen, [Vector2i(1, 0), Vector2i(2, 0)])
	assert_eq(screen.stored_name(), "Abc")


## `.a`'s `ret nc` after TryAddCharacter's own: the tenth character fills the
## entry, and the carry falls straight into `.start`, which puts the cursor on
## END rather than leaving it on a letter.
func test_filling_the_name_moves_the_cursor_to_end() -> void:
	var screen: Gen2NamingScreen = _screen()
	for _index: int in Gen2NamingScreen.PLAYER_MAX_LENGTH:
		screen.column = 0
		screen.row = 0
		screen.press_a()
	assert_eq(screen.length, Gen2NamingScreen.PLAYER_MAX_LENGTH)
	assert_eq(screen.row, screen.command_row())
	assert_eq(screen.column, Gen2NamingScreen.LAST_COLUMN)
	assert_eq(screen.cursor_command(), Gen2NamingScreen.COMMAND_END)
	assert_eq(screen.stored_name().length(), Gen2NamingScreen.PLAYER_MAX_LENGTH)


## Once the entry is full, TryAddCharacter returns before writing anything, so
## a further press on a letter is read and does nothing.
func test_a_full_name_refuses_another_character() -> void:
	var screen: Gen2NamingScreen = _screen()
	for _index: int in Gen2NamingScreen.PLAYER_MAX_LENGTH:
		screen.column = 0
		screen.row = 0
		screen.press_a()
	var before: String = screen.stored_name()
	screen.column = 4
	screen.row = 1
	assert_eq(screen.press_a(), Gen2NamingScreen.RESULT_FULL)
	assert_eq(screen.length, Gen2NamingScreen.PLAYER_MAX_LENGTH)
	assert_eq(screen.stored_name(), before)


func test_start_jumps_the_cursor_to_end_on_either_keyboard() -> void:
	var screen: Gen2NamingScreen = _screen()
	screen.press_start()
	assert_eq(screen.row, NAME_ROWS - 1)
	assert_eq(screen.column, Gen2NamingScreen.LAST_COLUMN)

	var box: Gen2NamingScreen = Gen2NamingScreen.for_box(_data)
	box.press_start()
	assert_eq(box.row, BOX_ROWS - 1)


## BOX_NAME_LENGTH - 1 against PLAYER_NAME_LENGTH - 1.
func test_a_box_name_has_its_own_length() -> void:
	var box: Gen2NamingScreen = Gen2NamingScreen.for_box(_data)
	assert_eq(box.max_length, Gen2NamingScreen.BOX_MAX_LENGTH)
	assert_eq(box.buffer.size(), Gen2NamingScreen.BOX_MAX_LENGTH + 1)
	assert_eq(box.buffer[Gen2NamingScreen.BOX_MAX_LENGTH], Gen2NamingScreen.TERMINATOR)


## A cache with no keyboards builds a screen that reads nothing rather than one
## with invented letters.
func test_a_screen_without_keyboards_reads_no_character() -> void:
	var screen: Gen2NamingScreen = Gen2NamingScreen.for_player(null)
	assert_eq(screen.rows(), [])
	assert_eq(screen.last_character(), 0)
	assert_eq(screen.press_a(), Gen2NamingScreen.RESULT_LETTER)
	assert_eq(screen.length, 0, "nothing is added when there is nothing to read")
