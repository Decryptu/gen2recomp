extends GutTest

## `menu_coords`, `GetMenuBoxDims`, `GetMenuTextStartCoord` and
## `_InitVerticalMenuCursor`, checked against the two real menu headers this
## project builds a screen from.

## `engine/menus/init_gender.asm`'s .MenuHeader: `menu_coords 6, 4, 12, 9` with
## STATICMENU_CURSOR | STATICMENU_WRAP | STATICMENU_DISABLE_B.
const GENDER_FLAGS: int = (
	Gen2MenuBox.STATICMENU_CURSOR | Gen2MenuBox.STATICMENU_WRAP
	| Gen2MenuBox.STATICMENU_DISABLE_B
)


func _gender_box() -> Gen2MenuBox:
	return Gen2MenuBox.from_coords(6, 4, 12, 9, GENDER_FLAGS)


func test_dims_are_the_span_between_the_corners() -> void:
	assert_eq(_gender_box().dims(), Vector2i(6, 5))


## `MenuBox` decrements both dims before calling `Textbox`, so the interior is
## one less than the span in each direction.
func test_interior_is_what_textbox_is_asked_for() -> void:
	assert_eq(_gender_box().interior(), Vector2i(5, 4))


func test_border_is_the_interior_plus_its_two_edges() -> void:
	assert_eq(_gender_box().border_size(), Vector2i(7, 6))
	assert_eq(_gender_box().border_position(), Vector2i(6, 4))


## One in from the corner, one row further down for the top spacing, one column
## further right to leave room for the cursor.
func test_text_starts_inside_the_border_with_room_for_the_cursor() -> void:
	assert_eq(_gender_box().text_start(), Vector2i(8, 6))


func test_no_top_spacing_keeps_the_first_row() -> void:
	var box: Gen2MenuBox = Gen2MenuBox.from_coords(
		6, 4, 12, 9, GENDER_FLAGS | Gen2MenuBox.STATICMENU_NO_TOP_SPACING
	)
	assert_eq(box.text_start(), Vector2i(8, 5))
	assert_eq(box.cursor_start(), Vector2i(7, 5))


## Without STATICMENU_CURSOR the text keeps the column the arrow would have had.
func test_a_menu_without_a_cursor_reclaims_the_column() -> void:
	var box: Gen2MenuBox = Gen2MenuBox.from_coords(6, 4, 12, 9, Gen2MenuBox.STATICMENU_WRAP)
	assert_eq(box.text_start(), Vector2i(7, 6))


## The source writes wMenuBorderLeftCoord + 1 outright, so the position exists
## whether or not an arrow is ever drawn there.
func test_cursor_sits_one_column_left_of_the_text() -> void:
	var box: Gen2MenuBox = _gender_box()
	assert_eq(box.cursor_start(), Vector2i(7, 6))
	assert_eq(box.cursor_start().x, box.text_start().x - 1)
	assert_eq(box.cursor_start().y, box.text_start().y)


## `PlaceVerticalMenuItems` advances by 2 * SCREEN_WIDTH and the cursor by
## `ln a, 2, 0`, so both step two rows per item.
func test_items_and_cursor_step_two_rows_each() -> void:
	var box: Gen2MenuBox = _gender_box()
	assert_eq(box.item_position(0), Vector2i(8, 6))
	assert_eq(box.item_position(1), Vector2i(8, 8))
	assert_eq(box.cursor_position(0), Vector2i(7, 6))
	assert_eq(box.cursor_position(1), Vector2i(7, 8))


## `data/player_names.asm`'s ChrisNameMenuHeader, the other real header:
## `menu_coords 0, 0, 10, TEXTBOX_Y - 1` with a title indented two columns.
func test_title_prints_on_the_box_top_row_at_its_indent() -> void:
	var box: Gen2MenuBox = Gen2MenuBox.from_coords(
		0, 0, 10, 11, Gen2MenuBox.STATICMENU_CURSOR | Gen2MenuBox.STATICMENU_PLACE_TITLE
	)
	assert_eq(box.title_position(2), Vector2i(2, 0))
	assert_eq(box.border_size(), Vector2i(11, 12))


func test_flags_answer_by_bit() -> void:
	var box: Gen2MenuBox = _gender_box()
	assert_true(box.has_flag(Gen2MenuBox.STATICMENU_CURSOR))
	assert_true(box.has_flag(Gen2MenuBox.STATICMENU_DISABLE_B))
	assert_false(box.has_flag(Gen2MenuBox.STATICMENU_PLACE_TITLE))


## The selection model reads its two flags from here, so the two cannot drift.
func test_world_menu_shares_this_flag_set() -> void:
	assert_eq(Gen2WorldMenu.STATICMENU_WRAP, Gen2MenuBox.STATICMENU_WRAP)
	assert_eq(
		Gen2WorldMenu.STATICMENU_ENABLE_LEFT_RIGHT, Gen2MenuBox.STATICMENU_ENABLE_LEFT_RIGHT
	)


## `BattleMenuHeader`'s own `dn 2, 2` and `db 6`, which is the one two-column
## menu here: FIGHT and PACK share a column, PKMN and RUN sit six to the right,
## and the rows are two apart like every other menu's.
func test_a_two_column_menu_walks_its_row_before_dropping() -> void:
	var box: Gen2MenuBox = Gen2BattleMenu.main_box()
	assert_eq(box.text_start(), Vector2i(10, 14))
	assert_eq(box.item_position(0), Vector2i(10, 14), "FIGHT")
	assert_eq(box.item_position(1), Vector2i(16, 14), "PKMN")
	assert_eq(box.item_position(2), Vector2i(10, 16), "PACK")
	assert_eq(box.item_position(3), Vector2i(16, 16), "RUN")
	assert_eq(box.cursor_position(3), Vector2i(15, 16))
	assert_eq(box.border_size(), Vector2i(12, 6))


## `MoveSelectionScreen`'s own `Textbox`: `hlcoord 4, 12` with `b, 4` and
## `c, 14`, its rows one apart rather than two, and its cursor column 5.
func test_the_move_list_is_a_one_row_step_box() -> void:
	var box: Gen2MenuBox = Gen2BattleMenu.move_box()
	assert_eq(box.interior(), Vector2i(14, 4))
	assert_eq(box.item_position(0), Vector2i(6, 13))
	assert_eq(box.item_position(3), Vector2i(6, 16))
	assert_eq(box.cursor_position(0), Vector2i(5, 13))


## `MoveInfoBox`'s `hlcoord 0, 8` with `b, 3` and `c, 9`.
func test_the_move_info_box_is_the_source_rectangle() -> void:
	var box: Gen2MenuBox = Gen2BattleMenu.info_box()
	assert_eq(box.interior(), Vector2i(9, 3))
	assert_eq(box.border_position(), Vector2i(0, 8))
	assert_eq(box.border_size(), Vector2i(11, 5))


## `.skip_exp_bar_animation`'s `hlcoord 9, 0` with `b, 10` and `c, 9`, and the
## `PrintTempMonStats` at `hlcoord 11, 1` whose spacing of four puts the numbers
## two columns further left than the stats screen's six does.
func test_the_level_up_stats_box_is_the_source_rectangle() -> void:
	var box: Gen2MenuBox = Gen2BattleMenu.level_up_box()
	assert_eq(box.interior(), Vector2i(9, 10))
	assert_eq(box.border_position(), Vector2i(9, 0))
	assert_eq(box.border_size(), Vector2i(11, 12))
	var placements: Array = Gen2StatsScreenPage.stats_placements(
		Gen2BattleMenu.LEVEL_UP_STATS_AT, {"attack": 12, "speed": 7},
		Gen2BattleMenu.LEVEL_UP_STATS_SPACING
	)
	assert_eq(placements.size(), 10)
	assert_eq(placements[0], {"text": "ATTACK", "at": Vector2i(11, 1)})
	assert_eq(placements[4], {"text": "SPEED", "at": Vector2i(11, 9)})
	assert_eq(placements[5], {"text": " 12", "at": Vector2i(15, 2)})
	assert_eq(placements[9], {"text": "  7", "at": Vector2i(15, 10)})


## `MenuHeaders_UnownWalls`' `menu_coords 9 - n, 4, 10 + n, 9`: the box is built
## around the word, so "ESCAPE" and "HO-OH" are different sizes and both are
## centred on the same two columns.
func test_an_unown_wall_box_is_built_around_its_word() -> void:
	var escape: Gen2MenuBox = Gen2UnownWall.menu_box("ESCAPE")
	assert_eq(escape.border_position(), Vector2i(3, 4))
	assert_eq(escape.border_size(), Vector2i(14, 6))
	var ho_oh: Gen2MenuBox = Gen2UnownWall.menu_box("HO-OH")
	assert_eq(ho_oh.border_position(), Vector2i(4, 4))
	assert_eq(ho_oh.border_size(), Vector2i(12, 6))
	## `MenuBoxCoord2Tile`, `inc hl` and two rows down, then two columns a letter.
	assert_eq(Gen2UnownWall.block_position(escape, 0), Vector2i(4, 6))
	assert_eq(Gen2UnownWall.block_position(escape, 5), Vector2i(14, 6))


## The `unown` charmap's `$10 * (i / 8) + 2 * i`: eight letters to a row of the
## sheet, each two tiles wide and two rows tall, so I opens a new row rather than
## following H.
func test_the_unown_charmap_steps_a_row_every_eighth_letter() -> void:
	assert_eq(Gen2UnownWall.char_code("A"), 0x00)
	assert_eq(Gen2UnownWall.char_code("H"), 0x0E)
	assert_eq(Gen2UnownWall.char_code("I"), 0x20)
	assert_eq(Gen2UnownWall.char_code("X"), 0x4E)
	assert_eq(Gen2UnownWall.char_code(" "), -1)


## `_DisplayUnownWords_CopyWord`: a letter is the computed tile, the one after
## it, and the two a whole sheet row below. `.ConvertChar` branches away from
## that arithmetic for the last three characters, whose tiles sit in the other
## graphics block, which is what `_DisplayUnownWords_FillAttr`'s `cp 'Y'` splits.
func test_a_letter_block_is_four_tiles_and_the_last_three_are_the_exception() -> void:
	var word: Array = Gen2UnownWall.blocks("AYZ-")
	assert_eq(word[0]["tiles"], [0x00, 0x01, 0x10, 0x11])
	assert_true(bool(word[0]["bank1"]), "A is drawn out of the second block")
	assert_eq(word[1]["tiles"], [0x5B, 0x5C, 0x4D, 0x5D], "Y")
	assert_eq(word[2]["tiles"], [0x4E, 0x4F, 0x5E, 0x5F], "Z")
	assert_eq(word[3]["tiles"], [0x02, 0x03, 0x03, 0x02], "the dash is one tile twice")
	for index: int in [1, 2, 3]:
		assert_false(bool(word[index]["bank1"]), "the last three are in the first block")
	assert_eq(Gen2UnownWall.blocks("ESCAPE!"), [], "a character with no tile")
