class_name Gen2NamingScreen
extends RefCounted

## `engine/menus/naming_screen.asm`'s model: which keyboard is live, where the
## cursor is, what a press does to the name being typed and what comes out at
## the end.
##
## Scene-free, so the whole walk can be tested without drawing it.
## `Gen2NamingScreenPage` draws what this holds. The name is kept as the
## cartridge keeps it, a fixed buffer of raw codes seeded with
## NAMINGSCREEN_UNDERLINE and NAMINGSCREEN_MIDDLELINE rather than a String,
## because every routine here reads and writes those two markers.

## The four keyboards in block order, which is the order they are imported in.
enum Keyboard {
	NAME_LOWER,
	BOX_LOWER,
	NAME_UPPER,
	BOX_UPPER,
}

## `naming_screen.asm`'s own three: the cursor under the entry, the dashes it
## has not reached yet, and the terminator behind them.
const UNDERLINE: int = 0xF2
const MIDDLELINE: int = 0xEB
const TERMINATOR: int = Gen2Text.TERMINATOR

## What `NamingScreen_GetCursorPosition` answers. 0 is a letter; the other three
## are the command row read by column, under 3, under 6 and the rest.
const COMMAND_NONE: int = 0
const COMMAND_CASE: int = 1
const COMMAND_DELETE: int = 2
const COMMAND_END: int = 3

## `.a`'s outcomes, for the caller that has to know whether the screen is done.
const RESULT_LETTER: StringName = &"letter"
const RESULT_CASE: StringName = &"case"
const RESULT_DELETE: StringName = &"delete"
const RESULT_END: StringName = &"end"
## TryAddCharacter's `ret nc` when the name is already at its length: the press
## is read and nothing happens.
const RESULT_FULL: StringName = &"full"

## `PLAYER_NAME_LENGTH - 1`, which `.StoreSpriteIconParams` writes into
## wNamingScreenMaxNameLength.
const PLAYER_MAX_LENGTH: int = Gen2SaveData.MAX_PLAYER_NAME
## `BOX_NAME_LENGTH - 1`.
const BOX_MAX_LENGTH: int = 8

## The cursor's own columns, which is every second byte of a row.
const COLUMNS: int = RomLayout.NAME_INPUT_COLUMNS
const COLUMN_STRIDE: int = RomLayout.NAME_INPUT_COLUMN_STRIDE
## `.LetterEntries` has nine entries, so the last column is 8.
const LAST_COLUMN: int = COLUMNS - 1
## `.CaseDelEnd` snaps the cursor to three groups three columns apart.
const COMMAND_GROUP: int = 3

## `NamingScreen_IsTargetBox`: a box keyboard is six rows and a name keyboard
## five, so the command row is row 5 or row 4.
var is_box: bool = false
## wNamingScreenLetterCase. 0 is upper, which is what NamingScreen_InitText
## loads before anything has been pressed.
var upper_case: bool = true
var max_length: int = PLAYER_MAX_LENGTH

## SPRITEANIMSTRUCT_VAR1 and VAR2, the cursor's column and row.
var column: int = 0
var row: int = 0

## wNamingScreenCurNameLength and the buffer at wNamingScreenDestinationPointer.
var length: int = 0
var buffer: Array[int] = []

var _tables: Array = []


## [param data] supplies the four imported keyboards. A cache without them
## builds a screen that draws nothing rather than one with invented letters.
static func for_player(data: GameData) -> Gen2NamingScreen:
	return _build(data, false, PLAYER_MAX_LENGTH)


static func for_box(data: GameData) -> Gen2NamingScreen:
	return _build(data, true, BOX_MAX_LENGTH)


static func _build(data: GameData, box: bool, limit: int) -> Gen2NamingScreen:
	var screen := Gen2NamingScreen.new()
	screen.is_box = box
	screen.max_length = limit
	if data != null:
		for table: int in Keyboard.size():
			screen._tables.append(data.name_input_chars(table))
	screen.init_name_entry()
	screen.init_cursor()
	return screen


## `.InitCursor`'s `depixel 10, 3`, which is column 0 of row 0 on either
## keyboard once the offsets are subtracted back off.
func init_cursor() -> void:
	column = 0
	row = 0


## `NamingScreen_InitNameEntry`: an underline where the next character goes,
## middlelines behind it, and the terminator on the last byte.
func init_name_entry() -> void:
	buffer = []
	buffer.resize(max_length + 1)
	buffer.fill(MIDDLELINE)
	buffer[0] = UNDERLINE
	buffer[max_length] = TERMINATOR
	length = 0


## `NamingScreen_ApplyTextInputMode`'s table selection: the case picks the pair
## and NamingScreen_IsTargetBox picks which of the pair.
func keyboard() -> int:
	var table: int = Keyboard.NAME_UPPER if upper_case else Keyboard.NAME_LOWER
	return table + 1 if is_box else table


## The live keyboard's rows, as raw cartridge codes.
func rows() -> Array:
	if keyboard() >= _tables.size():
		return []
	return _tables[keyboard()]


## `ld b, $5` / `ld b, $6`: the number of rows the live keyboard has.
func row_count() -> int:
	return 6 if is_box else 5


## Which row the case switch, DEL and END sit on.
func command_row() -> int:
	return row_count() - 1


## `NamingScreen_GetCursorPosition`. Off the command row every column is a
## letter; on it the column decides which of the three commands.
func cursor_command() -> int:
	if row != command_row():
		return COMMAND_NONE
	if column < COMMAND_GROUP:
		return COMMAND_CASE
	if column < COMMAND_GROUP * 2:
		return COMMAND_DELETE
	return COMMAND_END


## `NamingScreen_GetLastCharacter`: the code under the cursor, read off the
## tilemap at the cursor's own stride. Returns 0 on the command row, which the
## caller never reaches because `.a` answers the command first.
func last_character() -> int:
	var table: Array = rows()
	if row < 0 or row >= table.size():
		return 0
	var codes: Array = table[row]
	var at: int = column * COLUMN_STRIDE
	return int(codes[at]) if at >= 0 and at < codes.size() else 0


## `NamingScreen_AnimateCursor`'s `.GetDPad`. Horizontal movement on the command
## row steps between the three commands rather than between columns, and both
## axes wrap.
func move(direction: Vector2i) -> void:
	if direction.y < 0:
		_up()
	elif direction.y > 0:
		_down()
	elif direction.x < 0:
		_left()
	elif direction.x > 0:
		_right()


## `.ReadButtons`' `.a`. The command row answers first, so a press there never
## reads a character.
func press_a() -> StringName:
	match cursor_command():
		COMMAND_CASE:
			press_select()
			return RESULT_CASE
		COMMAND_DELETE:
			press_b()
			return RESULT_DELETE
		COMMAND_END:
			return RESULT_END
	if length >= max_length:
		return RESULT_FULL
	if _add_character(last_character()):
		# TryAddCharacter's carry falls straight into `.start`, so filling the
		# last slot puts the cursor on END rather than leaving it on a letter.
		press_start()
	return RESULT_LETTER


## `.b`, which is `NamingScreen_DeleteCharacter`.
func press_b() -> void:
	if length <= 0:
		return
	length -= 1
	buffer[length] = UNDERLINE
	if length + 1 < buffer.size() and buffer[length + 1] == UNDERLINE:
		buffer[length + 1] = MIDDLELINE


## `.start`: the cursor jumps to END, which is the last column of the command
## row.
func press_start() -> void:
	column = LAST_COLUMN
	row = command_row()


## `.select`, which flips the case and reloads the keyboard under the cursor.
## The cursor itself does not move.
func press_select() -> void:
	upper_case = not upper_case


## `NamingScreen_StoreEntry`: every marker still in the buffer becomes a
## terminator, so the name is what was typed and nothing behind it.
func stored_codes() -> PackedByteArray:
	var out := PackedByteArray()
	for index: int in max_length:
		var code: int = buffer[index]
		if code == MIDDLELINE or code == UNDERLINE:
			break
		out.append(code)
	return out


## The stored entry as text. PK, MN and the two gender signs come back as the
## project's own decoded forms; see [Gen2Text].
func stored_name() -> String:
	var codes: PackedByteArray = stored_codes()
	return Gen2Text.decode(codes, 0, codes.size())


## `NamingScreen_TryAddCharacter` plus
## `NamingScreen_AdvanceCursor_CheckEndOfString`. Returns true when the entry
## reached the terminator, which is the source's carry.
func _add_character(code: int) -> bool:
	if code <= 0:
		return false
	buffer[length] = code
	length += 1
	if buffer[length] == TERMINATOR:
		return true
	buffer[length] = UNDERLINE
	return false


func _right() -> void:
	var command: int = cursor_command()
	if command != COMMAND_NONE:
		# `.target_right`: END wraps round to the case switch.
		var next: int = 0 if command == COMMAND_END else command
		column = next * COMMAND_GROUP
		return
	column = 0 if column >= LAST_COLUMN else column + 1


func _left() -> void:
	var command: int = cursor_command()
	if command != COMMAND_NONE:
		# `.target_left`: the case switch wraps back round to END.
		var next: int = 4 if command == COMMAND_CASE else command
		column = (next - 2) * COMMAND_GROUP
		return
	column = LAST_COLUMN if column <= 0 else column - 1


func _down() -> void:
	row = 0 if row >= command_row() else row + 1


func _up() -> void:
	row = command_row() if row <= 0 else row - 1
