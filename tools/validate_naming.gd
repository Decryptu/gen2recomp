extends SceneTree

## Verifies the four name-input keyboards against freshly imported real caches,
## in all three games.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## data/text/name_input_chars.asm's NameInputLower, BoxNameInputLower,
## NameInputUpper and BoxNameInputUpper, read by engine/menus/naming_screen.asm's
## NamingScreen_ApplyTextInputMode and NamingScreen_GetLastCharacter.
##
## The block is one contiguous 374-byte run with every row 17 bytes, so a wrong
## offset slides every table after it. What pins it is the content: the letter
## rows, the symbol rows and the command row are all checked by value, and the
## whole block is compared between the three games, which ship it byte identical.
##
##   Godot --headless --path . -s res://tools/validate_naming.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## Rows per table, in block order. A name keyboard is 5 rows and a box keyboard
## 6, which is NamingScreen_IsTargetBox's `ld b, $5` / `ld b, $6` split.
const EXPECTED_ROWS: Array[int] = [5, 6, 5, 6]

## The symbol row of each table, by value, as the row index and its nine cursor
## columns. These are text codes rather than letters, so they are the one part of
## the block a plausible neighbouring run of text would not reproduce.
const EXPECTED_SYMBOL_ROWS: Array = [
	# NameInputLower row 3: × ( ) : ; [ ] PK MN
	[0, 3, [0xF1, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F, 0xE1, 0xE2]],
	# BoxNameInputLower row 3: é and the seven apostrophe ligatures, then 0
	[1, 3, [0xEA, 0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xF6]],
	# NameInputUpper row 3: - ? ! / . , and three blanks
	[2, 3, [0xE3, 0xE6, 0xE7, 0xF3, 0xE8, 0xF4, 0x7F, 0x7F, 0x7F]],
	# BoxNameInputUpper row 3 repeats NameInputLower's symbols
	[3, 3, [0xF1, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F, 0xE1, 0xE2]],
	# BoxNameInputUpper row 4: - ? ! ♂ ♀ / . , &
	[3, 4, [0xE3, 0xE6, 0xE7, 0xEF, 0xF5, 0xF3, 0xE8, 0xF4, 0xE9]],
]

const SPACE: int = 0x7F
const LOWER_A: int = 0xA0
const UPPER_A: int = 0x80

var _failures: PackedStringArray = []
var _blocks: Dictionary = {}


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_shape(game_id, data)
		_verify_letters(game_id, data)
		_verify_symbols(game_id, data)
		_verify_command_row(game_id, data)
		_blocks[game_id] = _flatten(data)
	_verify_identical()
	_finish()


func _verify_shape(game_id: StringName, data: GameData) -> void:
	for table: int in EXPECTED_ROWS.size():
		var rows: Array = data.name_input_chars(table)
		if not _check(
			rows.size() == EXPECTED_ROWS[table],
			"%s: table %d has %d rows, not the pinned %d." % [
				game_id, table, rows.size(), EXPECTED_ROWS[table],
			]
		):
			continue
		for row: Array in rows:
			_check(
				row.size() == RomLayout.NAME_INPUT_ROW_BYTES,
				"%s: table %d has a %d-byte row, not %d." % [
					game_id, table, row.size(), RomLayout.NAME_INPUT_ROW_BYTES,
				]
			)
	_check(
		data.name_input_chars(EXPECTED_ROWS.size()).is_empty(),
		"%s: a fifth keyboard was read out of a four-table block." % game_id
	)


## The three letter rows of every table, by cursor column. Rows 0 to 2 spell the
## alphabet nine, nine and eight letters at a time, with the twenty-sixth column
## blank in every table.
func _verify_letters(game_id: StringName, data: GameData) -> void:
	for table: int in EXPECTED_ROWS.size():
		var first: int = LOWER_A if table < 2 else UPPER_A
		for row: int in 3:
			for column: int in RomLayout.NAME_INPUT_COLUMNS:
				var letter: int = row * RomLayout.NAME_INPUT_COLUMNS + column
				var expected: int = SPACE if letter >= 26 else first + letter
				var stored: int = _cell(data, table, row, column)
				_check(
					stored == expected,
					"%s: table %d cell (%d,%d) is $%02X, not $%02X." % [
						game_id, table, row, column, stored, expected,
					]
				)


func _verify_symbols(game_id: StringName, data: GameData) -> void:
	for entry: Array in EXPECTED_SYMBOL_ROWS:
		var table: int = int(entry[0])
		var row: int = int(entry[1])
		var codes: Array = entry[2]
		for column: int in codes.size():
			var stored: int = _cell(data, table, row, column)
			_check(
				stored == int(codes[column]),
				"%s: table %d symbol cell (%d,%d) is $%02X, not $%02X." % [
					game_id, table, row, column, stored, int(codes[column]),
				]
			)


## NamingScreen_GetCursorPosition reads the last row by column: under 3 is the
## case switch, under 6 is DEL, otherwise END. So the row is checked in those
## three groups rather than cell by cell.
func _verify_command_row(game_id: StringName, data: GameData) -> void:
	for table: int in EXPECTED_ROWS.size():
		var rows: Array = data.name_input_chars(table)
		if rows.is_empty():
			continue
		var row: Array = rows[rows.size() - 1]
		var expected: Array[int] = (
			RomLayout.NAME_INPUT_COMMAND_LOWER if table < 2
			else RomLayout.NAME_INPUT_COMMAND_UPPER
		)
		_check(
			Array(row) == Array(expected),
			"%s: table %d's last row is not the command row." % [game_id, table]
		)


## The whole block, so the three games can be compared as one value.
func _flatten(data: GameData) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	for table: int in EXPECTED_ROWS.size():
		for row: Array in data.name_input_chars(table):
			out.append_array(PackedByteArray(row))
	return out


## The block offset is profile split but the bytes are not, in any of the three
## dumps, so a decode that differs anywhere means one offset is wrong.
func _verify_identical() -> void:
	var reference: StringName = &""
	for game_id: StringName in _blocks:
		var block: PackedByteArray = _blocks[game_id]
		_check(
			block.size() == RomLayout.NAME_INPUT_BLOCK_BYTES,
			"%s: block is %d bytes, not the pinned %d." % [
				game_id, block.size(), RomLayout.NAME_INPUT_BLOCK_BYTES,
			]
		)
		if reference == &"":
			reference = game_id
			continue
		_check(
			block == PackedByteArray(_blocks[reference]),
			"%s: block differs from %s, which ships it byte identical." % [game_id, reference]
		)
	if not _blocks.is_empty():
		print("Name input block: %d bytes, identical in %d games." % [
			RomLayout.NAME_INPUT_BLOCK_BYTES, _blocks.size(),
		])


func _cell(data: GameData, table: int, row: int, column: int) -> int:
	var rows: Array = data.name_input_chars(table)
	if row < 0 or row >= rows.size():
		return -1
	var codes: Array = rows[row]
	var at: int = column * RomLayout.NAME_INPUT_COLUMN_STRIDE
	return int(codes[at]) if at < codes.size() else -1


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS naming: four keyboards, letters, symbols and command rows verified.")
		quit(0)
		return
	for message: String in _failures:
		print("FAIL %s" % message)
	quit(1)
