class_name Gen2UnownWall
extends RefCounted

## `DisplayUnownWords` (engine/events/unown_walls.asm): the word a Ruins of Alph
## chamber wall spells, as the box it is drawn in and the tiles that draw it.
##
## The letters are not font glyphs and are not `UnownFont`, which is the
## Pokedex's own sheet: `_DisplayUnownWords_CopyWord` computes a tile number
## from the character itself and places a 2x2 block of the *tileset's* own tiles,
## which is why the chambers ship a tileset holding an alphabet
## (gfx/tilesets/ruins_of_alph.png). So this needs no import: the word comes from
## `UnownWalls`, which [method GameData.unown_wall_word] already carries, and the
## tiles come from the tileset the chamber is already drawn with.
##
## Scene-free arithmetic. [Gen2UnownWallPage] draws what this places.

## `constants/charmap.asm`'s `unown` charmap, `$10 * (i / 8) + 2 * i` over
## "ABCDEFGHIJKLMNOPQRSTUVWXYZ-": eight letters to a row of the sheet, each two
## tiles wide and two rows tall, so a row of letters steps a whole $10.
const ALPHABET: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ-"
const LETTERS_PER_ROW: int = 8

## `_DisplayUnownWords_FillAttr`'s split: everything below 'Y' is drawn out of
## VRAM bank 1 with `OAM_BANK1`, and the last three letters out of bank 0.
const BANK_SPLIT: int = 0x60

## `constants/tileset_constants.asm`: the palette both halves of the word are
## given, whatever the tileset's own palette map says about those tiles.
const PALETTE_BROWN: int = 5

## The three characters `.ConvertChar` branches away from the arithmetic for,
## because their tiles do not sit in the alphabet block: top-left, top-right,
## bottom-left, bottom-right.
const SPECIAL_TILES: Dictionary = {
	"Y": [0x5B, 0x5C, 0x4D, 0x5D],
	"Z": [0x4E, 0x4F, 0x5E, 0x5F],
	"-": [0x02, 0x03, 0x03, 0x02],
}

## `MenuHeaders_UnownWalls`' `menu_coords 9 - n, 4, 10 + n, 9`, where n is the
## word's length: the box is built around the word rather than the word fitted
## into a box.
const BOX_TOP: int = 4
const BOX_BOTTOM: int = 9
const BOX_CENTRE: int = 9

## `MenuBoxCoord2Tile`, `inc hl` and `add hl, 2 * SCREEN_WIDTH`: the word starts
## one column in from the frame and two rows down from it.
const WORD_OFFSET: Vector2i = Vector2i(1, 2)


## The `unown` charmap value of [param letter], or -1 for anything else.
static func char_code(letter: String) -> int:
	var index: int = ALPHABET.find(letter)
	if index < 0:
		return -1
	@warning_ignore("integer_division")
	return 0x10 * (index / LETTERS_PER_ROW) + 2 * index


## The box `MenuHeaders_UnownWalls` gives [param word]. Its flags byte is
## `MENU_BACKUP_TILES`, which restores the map behind the box when it closes;
## an overlay that is removed does that by existing, so no flag is carried.
static func menu_box(word: String) -> Gen2MenuBox:
	var length: int = word.length()
	return Gen2MenuBox.from_coords(
		BOX_CENTRE - length, BOX_TOP, BOX_CENTRE + 1 + length, BOX_BOTTOM, 0
	)


## One entry per letter of [param word], in order:
## [code]{"tiles": [tl, tr, bl, br], "bank1": bool, "palette": int}[/code].
##
## `tiles` are tile numbers in the chamber's own tileset. `bank1` says which of
## the two graphics blocks they are in, which is `OAM_BANK1` in the attribute
## map and [constant RomLayout.TILESET_BLOCK_STRIDE] into the flat strip here.
## Empty when the word holds a character the charmap has no tile for.
static func blocks(word: String) -> Array:
	var out: Array = []
	for index: int in word.length():
		var letter: String = word[index]
		var code: int = char_code(letter)
		if code < 0:
			return []
		var tiles: Array = SPECIAL_TILES.get(letter, []) as Array
		if tiles.is_empty():
			tiles = [code, code + 1, code + 0x10, code + 0x11]
		out.append({
			"tiles": tiles,
			"bank1": code < BANK_SPLIT,
			"palette": PALETTE_BROWN,
		})
	return out


## Where the block for letter [param index] sits, in tiles, given the box
## [method menu_box] built.
static func block_position(box: Gen2MenuBox, index: int) -> Vector2i:
	return box.border_position() + WORD_OFFSET + Vector2i(index * 2, 0)
