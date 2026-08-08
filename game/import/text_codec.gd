class_name Gen2Text
extends RefCounted

## The Generation 2 character encoding, for the international ROMs.
##
## One byte per character, terminated by $50, the alphabet in runs: $80 is "A",
## $A0 is "a", $F6 is "0". Some codes expand to whole words ($5D is "TRAINER") or
## name the player at print time ($52); those stay bracketed markers so a caller
## can substitute them and nothing is silently lost.
##
## The Japanese cartridges reuse most of this range for kana. They are not in
## [RomRegistry], and this table would decode them into nonsense.
##
## A byte does not name a character on its own. `constants/charmap.asm` maps the
## $60 to $7F run twice over, once from `gfx/font/font.png` and again from
## `gfx/font/font_battle_extra.png` under its own "Actual characters" heading,
## and $6e three times; the byte means whichever strip the hardware last loaded
## into video memory. Every entry point here takes the strip, defaulting to the
## main font, which is what all but the battle and Hall of Fame screens have up.

const TERMINATOR: int = 0x50
const SPACE: int = 0x7F

## Which strip is loaded. [constant FONT_MAIN] is `_LoadStandardFont`'s;
## [constant FONT_BATTLE_EXTRA] is what `_LoadFontsBattleExtra` leaves behind,
## which `engine/events/halloffame.asm` calls before it prints a panel.
const FONT_MAIN: StringName = &"main"
const FONT_BATTLE_EXTRA: StringName = &"battle_extra"

## The run `_LoadFontsBattleExtra` overwrites: twenty-five tiles from $60, which
## is `ld hl, vTiles2 tile $60` and `lb bc, BANK(FontBattleExtra), 25`. Outside
## it the main font is still up, so letters, digits and the box-drawing codes
## mean what they always did.
const BATTLE_EXTRA_FIRST_CODE: int = 0x60
const BATTLE_EXTRA_LAST_CODE: int = 0x78

## What that run says. The rest of it is the HP bar's fill levels and the two HUD
## borders, which are graphics rather than characters, so a code in the run and
## not in here has no character at all: falling back to the main font's would
## decode $75 as an ellipsis when the tile in memory is a piece of a bar.
const BATTLE_EXTRA_CHARACTERS: Dictionary = {
	0x6E: "<LV>",
	0x70: "<DO>",
	0x71: "◀",
	0x72: "『",
	0x73: "<ID>",
	0x74: "№",
}

## The lowest code the font has a tile for. Everything below it is a space, a
## border, a control code or a name substituted at print time, so it is also the
## line between what [method encode] will produce and what only [method decode]
## understands.
const FIRST_PRINTABLE: int = 0x80

## What an unencodable character becomes: "?", because a question mark on screen
## is a bug someone will report and a dropped character is not.
const UNKNOWN: int = 0xE6

## The longest character sequence one tile can stand for: the apostrophe
## ligatures ('s, 't) and PK/MN are two characters in a single glyph, because
## the font has no room for a free-standing apostrophe followed by a letter.
## The longer word codes $54 ("POKé") and $4a ("PKMN") are not reachable through
## this: they sit below FIRST_PRINTABLE and so are decode-only by design. Write
## "#" for $54 the way the source charmap does.
const MAX_LIGATURE: int = 2

static var _table: Dictionary = {}
static var _codes: Dictionary = {}
static var _battle_extra_codes: Dictionary = {}


## Decodes bytes from [param offset] up to a terminator or [param max_length]
## characters, whichever comes first.
static func decode(
	data: PackedByteArray, offset: int, max_length: int, font: StringName = FONT_MAIN
) -> String:
	var out: String = ""
	for i: int in max_length:
		var at: int = offset + i
		if at < 0 or at >= data.size():
			break
		var byte: int = data[at]
		if byte == TERMINATOR:
			break
		out += character(byte, font)
	return out


## A fixed-width field: the game pads names with $50 and reads a known number of
## bytes, so trailing padding is stripped rather than treated as a terminator
## mid-string.
static func decode_fixed(data: PackedByteArray, offset: int, length: int) -> String:
	return decode(data, offset, length)


## Walks [param count] consecutive terminated strings starting at [param offset].
##
## Species names are fixed-width, but move and item names are not: each entry
## ends at its terminator and the next begins on the very next byte. Nothing
## announces a length, so one wrong byte slides every name after it, which is why
## the importer checks such a table's last entry as well as its first.
##
## [param max_length] is a runaway guard, not a field width: without it a table
## read past its end would scan the remaining megabyte for a terminator that is
## not coming.
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


## Turns a string into the codes that draw it, one code per tile.
##
## The inverse of [method decode] over the printable range only: a name read back
## out of the cache is a Godot [String] and has to become tiles again. Control
## codes and print-time name codes are decode-only, since they are not glyphs and
## the layout layer handles line breaks itself.
##
## Anything the font cannot draw becomes [constant UNKNOWN] rather than being
## dropped, like an unrecognised byte on the way in.
## [param font] adds the strip's own single characters. Its bracketed markers
## (`<LV>`, `<ID>`, `<DO>`) stay decode-only, the way `<PLAYER>` and the word
## codes already are: a marker is not a character someone types, and the callers
## that place one place the code itself.
static func encode(text: String, font: StringName = FONT_MAIN) -> PackedByteArray:
	var codes: Dictionary = _encodings() if font == FONT_MAIN else _battle_extra_encodings()
	var out: PackedByteArray = PackedByteArray()
	var at: int = 0

	while at < text.length():
		var taken: int = 0
		# Longest first, so "'s" wins over "'" followed by an "s" that has no
		# code of its own.
		for length: int in range(mini(MAX_LIGATURE, text.length() - at), 0, -1):
			var candidate: String = text.substr(at, length)
			if codes.has(candidate):
				out.append(codes[candidate])
				taken = length
				break
		if taken == 0:
			out.append(UNKNOWN)
			taken = 1
		at += taken

	return out


## How many tiles a string occupies, which is not its length: a ligature is two
## characters in one tile, so anything laying text out has to ask.
static func encoded_length(text: String, font: StringName = FONT_MAIN) -> int:
	return encode(text, font).size()


static func character(byte: int, font: StringName = FONT_MAIN) -> String:
	if font == FONT_BATTLE_EXTRA \
		and byte >= BATTLE_EXTRA_FIRST_CODE and byte <= BATTLE_EXTRA_LAST_CODE:
		# The run this strip owns answers only from its own table, never from the
		# main font's meaning for the same byte.
		return BATTLE_EXTRA_CHARACTERS.get(byte, "<%02X>" % byte)
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


## The printable table inverted. Built in ascending code order and never
## overwritten, so where two codes draw the same character the lower one wins:
## the only such pair is the full stop at $E8 and the narrower decimal point at
## $F2, and $E8 is the one sentences end with.
static func _encodings() -> Dictionary:
	if not _codes.is_empty():
		return _codes

	var out: Dictionary = {" ": SPACE}
	var table: Dictionary = _characters()
	var codes: Array = table.keys()
	codes.sort()
	for code: int in codes:
		if code < FIRST_PRINTABLE:
			continue
		var text: String = table[code]
		if not out.has(text):
			out[text] = code

	# constants/charmap.asm maps "#" to $54, the POKé ligature, which is how every
	# source text writes it. Encode only: decoding $54 stays "POKé", so a round
	# trip through the cartridge's own shorthand is not silently rewritten.
	# Without this a synthesized literal such as "a #MON!" encodes "#" as UNKNOWN
	# and draws a question mark.
	out["#"] = 0x54

	# charmap.asm maps "…" to $75, which is likewise below FIRST_PRINTABLE and so
	# decode-only. Source text writes the character itself (Text_MoveForgetCount's
	# "1, 2 and…"), so a synthesized line quoting that wording needs it to encode
	# rather than draw a question mark. $56 is "……" and stays decode-only: two
	# $75s draw the same thing, and nothing has to choose between them.
	out["…"] = 0x75

	_codes = out
	return _codes


## The main font's encodings with the battle-extra run replaced.
##
## The main table's entries for $60 to $78 are dropped rather than kept
## alongside: with that strip loaded there is no tile drawing an ellipsis, so
## encoding one would place a byte that draws part of an HP bar.
static func _battle_extra_encodings() -> Dictionary:
	if not _battle_extra_codes.is_empty():
		return _battle_extra_codes

	var out: Dictionary = {}
	var main: Dictionary = _encodings()
	for text: String in main:
		var code: int = main[text]
		if code < BATTLE_EXTRA_FIRST_CODE or code > BATTLE_EXTRA_LAST_CODE:
			out[text] = code
	for code: int in BATTLE_EXTRA_CHARACTERS:
		var character_text: String = BATTLE_EXTRA_CHARACTERS[code]
		if character_text.length() <= MAX_LIGATURE:
			out[character_text] = code

	_battle_extra_codes = out
	return _battle_extra_codes
