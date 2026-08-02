class_name Gen2Text
extends RefCounted

## The Generation 2 character encoding, for the international ROMs.
##
## One byte per character, terminated by $50, with the alphabet laid out in
## runs: $80 is "A", $A0 is "a", $F6 is "0". Several codes expand to whole
## words ($5D is "TRAINER") or name the player at print time ($52); those are
## kept as bracketed markers so a caller can substitute them, and so nothing is
## silently lost.
##
## The Japanese cartridges reuse most of this range for kana. They are not in
## [RomRegistry] and this table would decode them into nonsense, which is the
## same reason the import gate refuses an unknown hash.

const TERMINATOR: int = 0x50
const SPACE: int = 0x7F

static var _table: Dictionary = {}


## Decodes bytes from [param offset] up to a terminator or [param max_length]
## characters, whichever comes first.
static func decode(data: PackedByteArray, offset: int, max_length: int) -> String:
	var out: String = ""
	for i: int in max_length:
		var at: int = offset + i
		if at < 0 or at >= data.size():
			break
		var byte: int = data[at]
		if byte == TERMINATOR:
			break
		out += character(byte)
	return out


## A fixed-width field: the game pads names with $50 and reads a known number of
## bytes, so trailing padding is stripped rather than treated as a terminator
## mid-string.
static func decode_fixed(data: PackedByteArray, offset: int, length: int) -> String:
	return decode(data, offset, length)


## Walks [param count] consecutive terminated strings starting at [param offset].
##
## The species names are a fixed-width table, but the move and item names are
## not: each entry ends at its terminator and the next one begins on the very
## next byte. Nothing announces how long an entry is, so a single wrong byte
## slides every name after it, which is why the importer checks the last entry
## of such a table and not only the first.
##
## [param max_length] is a runaway guard rather than a field width. Without it, a
## table read past its own end would scan the remaining megabyte looking for a
## terminator that is not coming.
static func decode_sequence(
	data: PackedByteArray, offset: int, count: int, max_length: int
) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var at: int = offset
	for i: int in count:
		if at < 0 or at >= data.size():
			break
		out.append(decode(data, at, max_length))
		var end: int = at
		while end < data.size() and data[end] != TERMINATOR and end - at < max_length:
			end += 1
		at = end + 1
	return out


static func character(byte: int) -> String:
	var table: Dictionary = _characters()
	if table.has(byte):
		return table[byte]
	# Never silently drop a byte we do not understand: an unrecognised code in a
	# name means the offset table is wrong, and that should be visible.
	return "<%02X>" % byte


static func _characters() -> Dictionary:
	if not _table.is_empty():
		return _table

	var table: Dictionary = {}
	for i: int in 26:
		table[0x80 + i] = char("A".unicode_at(0) + i)
		table[0xA0 + i] = char("a".unicode_at(0) + i)
	for i: int in 10:
		table[0xF6 + i] = char("0".unicode_at(0) + i)

	table[SPACE] = " "
	table[0x9A] = "("
	table[0x9B] = ")"
	table[0x9C] = ":"
	table[0x9D] = ";"
	table[0x9E] = "["
	table[0x9F] = "]"
	table[0xC0] = "Ä"
	table[0xC1] = "Ö"
	table[0xC2] = "Ü"
	table[0xC3] = "ä"
	table[0xC4] = "ö"
	table[0xC5] = "ü"
	table[0xE0] = "'"
	table[0xE3] = "-"
	table[0xE6] = "?"
	table[0xE7] = "!"
	table[0xE8] = "."
	table[0xE9] = "&"
	table[0xEA] = "é"
	table[0xEB] = "→"
	table[0xEC] = "▷"
	table[0xED] = "▶"
	table[0xEE] = "▼"
	table[0xEF] = "♂"
	table[0xF0] = "¥"
	table[0xF1] = "×"
	table[0xF2] = "."
	table[0xF3] = "/"
	table[0xF4] = ","
	table[0xF5] = "♀"
	table[0x6D] = ":"
	table[0x72] = "“"
	table[0x73] = "”"
	table[0x74] = "·"
	table[0x75] = "…"
	table[0x79] = "┌"
	table[0x7A] = "─"
	table[0x7B] = "┐"
	table[0x7C] = "│"
	table[0x7D] = "└"
	table[0x7E] = "┘"

	# Apostrophe ligatures: one tile each, because the font has no room for a
	# free-standing apostrophe followed by a letter.
	table[0xD0] = "'d"
	table[0xD1] = "'l"
	table[0xD2] = "'m"
	table[0xD3] = "'r"
	table[0xD4] = "'s"
	table[0xD5] = "'t"
	table[0xD6] = "'v"

	# Codes that stand for whole words at print time.
	table[0x24] = "POKé"
	table[0x4A] = "PKMN"
	table[0x54] = "POKé"
	table[0x5B] = "PC"
	table[0x5C] = "TM"
	table[0x5D] = "TRAINER"
	table[0x5E] = "ROCKET"
	table[0xE1] = "PK"
	table[0xE2] = "MN"

	# Substituted from RAM when the game prints them.
	table[0x14] = "<PLAYER>"
	table[0x38] = "<RED>"
	table[0x39] = "<GREEN>"
	table[0x3F] = "<ENEMY>"
	table[0x49] = "<MOM>"
	table[0x52] = "<PLAYER>"
	table[0x53] = "<RIVAL>"
	table[0x59] = "<TARGET>"
	table[0x5A] = "<USER>"

	# Line and box control.
	table[0x16] = "\n"
	table[0x22] = "\n"
	table[0x4B] = "\n"
	table[0x4C] = "\n"
	table[0x4E] = "\n"
	table[0x4F] = "\n"
	table[0x51] = "\n\n"
	table[0x55] = "\n"
	table[0x56] = "……"
	table[0x57] = ""
	table[0x58] = ""

	_table = table
	return _table
