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
