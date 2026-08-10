extends GutTest

## The four name-input keyboards read back off a built cache.
##
## The cache is synthetic and has the real block's shape rather than its
## contents: four tables of 5, 6, 5 and 6 rows, every row 17 bytes, with the
## letter rows generated and the command row taken from [RomLayout]'s own
## constant. The real cartridge bytes are the job of `tools/validate_naming.gd`,
## which decodes all four tables out of all three dumps.

const TABLE_ROWS: Array[int] = [5, 6, 5, 6]
const SPACE: int = 0x7F

## data/text/name_input_chars.asm's symbol row for NameInputLower, at its own
## cursor columns: × ( ) : ; [ ] PK MN.
const SYMBOL_ROW: Array[int] = [0xF1, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F, 0xE1, 0xE2]

var _directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"testnaming", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()


func after_each() -> void:
	RomCache.clear(_directory)


func _write_cache() -> void:
	var tables: Array = []
	for table: int in TABLE_ROWS.size():
		var first: int = RomLayout.NAME_INPUT_LOWER_A if table < 2 else RomLayout.NAME_INPUT_UPPER_A
		var rows: Array = []
		for row: int in TABLE_ROWS[table]:
			if row == TABLE_ROWS[table] - 1:
				rows.append(_command_row(table))
				continue
			if row == 3:
				rows.append(_spread(SYMBOL_ROW))
				continue
			rows.append(_letter_row(first, row))
		tables.append(rows)
	RomCache.write_json(RomCache.name_input_chars_path(_directory), tables)
	RomCache.write_json(RomCache.species_path(_directory), [])
	RomCache.write_json(RomCache.moves_path(_directory), [])
	RomCache.write_json(RomCache.items_path(_directory), [])
	RomCache.write_json(RomCache.types_path(_directory), [])
	RomCache.write_json(RomCache.matchups_path(_directory), [])
	RomCache.write_json(RomCache.trainers_path(_directory), [])
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"complete": true,
		"game_id": "testnaming",
	})


## Nine letters at cursor columns, blanks in the odd bytes between them, the way
## the cartridge stores a row the cursor reads every second byte of.
func _letter_row(first: int, row: int) -> Array:
	var codes: Array[int] = []
	for column: int in RomLayout.NAME_INPUT_COLUMNS:
		codes.append(first + row * RomLayout.NAME_INPUT_COLUMNS + column)
	return _spread(codes)


func _command_row(table: int) -> Array:
	var source: Array[int] = (
		RomLayout.NAME_INPUT_COMMAND_LOWER if table < 2 else RomLayout.NAME_INPUT_COMMAND_UPPER
	)
	return Array(source)


## Nine values into a 17-byte row at the cursor's own stride.
func _spread(values: Array) -> Array:
	var row: Array[int] = []
	for column: int in RomLayout.NAME_INPUT_COLUMNS:
		row.append(int(values[column]))
		if column < RomLayout.NAME_INPUT_COLUMNS - 1:
			row.append(SPACE)
	return row


func _data() -> GameData:
	return GameData.open_directory(_directory)


func test_every_table_has_its_source_row_count() -> void:
	var data: GameData = _data()
	for table: int in TABLE_ROWS.size():
		assert_eq(
			data.name_input_chars(table).size(), TABLE_ROWS[table],
			"Table %d row count" % table
		)


func test_every_row_is_seventeen_bytes() -> void:
	var data: GameData = _data()
	for table: int in TABLE_ROWS.size():
		for row: Array in data.name_input_chars(table):
			assert_eq(row.size(), RomLayout.NAME_INPUT_ROW_BYTES)


func test_a_table_outside_the_block_reads_empty() -> void:
	var data: GameData = _data()
	assert_eq(data.name_input_chars(TABLE_ROWS.size()), [])
	assert_eq(data.name_input_chars(-1), [])


func test_letter_rows_read_back_at_the_cursor_stride() -> void:
	var data: GameData = _data()
	var rows: Array = data.name_input_chars(0)
	assert_eq(int(rows[0][0]), RomLayout.NAME_INPUT_LOWER_A)
	# Column 1 is byte 2, not byte 1: the cursor steps two tiles.
	assert_eq(int(rows[0][RomLayout.NAME_INPUT_COLUMN_STRIDE]), RomLayout.NAME_INPUT_LOWER_A + 1)
	assert_eq(int(rows[0][1]), SPACE)
	assert_eq(int(data.name_input_chars(2)[0][0]), RomLayout.NAME_INPUT_UPPER_A)


func test_symbol_row_keeps_its_text_codes() -> void:
	var data: GameData = _data()
	var row: Array = data.name_input_chars(0)[3]
	for column: int in SYMBOL_ROW.size():
		assert_eq(
			int(row[column * RomLayout.NAME_INPUT_COLUMN_STRIDE]), SYMBOL_ROW[column],
			"Symbol column %d" % column
		)


## The last row of every table, which NamingScreen_GetCursorPosition reads by
## column rather than as a character.
func test_command_row_is_the_last_row_of_every_table() -> void:
	var data: GameData = _data()
	for table: int in TABLE_ROWS.size():
		var rows: Array = data.name_input_chars(table)
		var expected: Array[int] = (
			RomLayout.NAME_INPUT_COMMAND_LOWER if table < 2
			else RomLayout.NAME_INPUT_COMMAND_UPPER
		)
		assert_eq(Array(rows[rows.size() - 1]), Array(expected), "Table %d command row" % table)


func test_block_is_the_pinned_length() -> void:
	var data: GameData = _data()
	var total: int = 0
	for table: int in TABLE_ROWS.size():
		for row: Array in data.name_input_chars(table):
			total += row.size()
	assert_eq(total, RomLayout.NAME_INPUT_BLOCK_BYTES)
