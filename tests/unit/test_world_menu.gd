extends GutTest


func test_vertical_menu_uses_the_source_default_and_wrap_flag() -> void:
	var menu: Gen2WorldMenu = Gen2WorldMenu.from_input({
		"menu_kind": &"vertical",
		"header": {"data_flags": 1 << 5, "default": 2},
		"options": ["A", "B", "C"],
	})
	assert_eq(menu.selected_index(), 1)
	assert_true(menu.move(Vector2i.DOWN))
	assert_eq(menu.selected_index(), 2)
	assert_true(menu.move(Vector2i.DOWN))
	assert_eq(menu.selected_index(), 0)
	assert_true(menu.move(Vector2i.UP))
	assert_eq(menu.selected_index(), 2)


func test_vertical_menu_stops_at_the_ends_without_source_wrap() -> void:
	var menu: Gen2WorldMenu = Gen2WorldMenu.from_input({
		"menu_kind": &"vertical", "header": {"default": 1},
		"options": ["A", "B"],
	})
	assert_false(menu.move(Vector2i.UP))
	assert_eq(menu.selected_index(), 0)
	assert_true(menu.move(Vector2i.DOWN))
	assert_false(menu.move(Vector2i.DOWN))
	assert_eq(menu.selected_index(), 1)


func test_two_dimensional_menu_moves_by_rows_and_columns() -> void:
	var menu: Gen2WorldMenu = Gen2WorldMenu.from_input({
		"menu_kind": &"2d",
		"header": {"data_flags": 1 << 5, "rows": 2, "columns": 2, "default": 1},
		"options": ["A", "B", "C", "D"],
	})
	assert_eq(menu.row(), 0)
	assert_eq(menu.column(), 0)
	assert_true(menu.move(Vector2i.RIGHT))
	assert_eq(menu.selected_index(), 1)
	assert_true(menu.move(Vector2i.DOWN))
	assert_eq(menu.selected_index(), 3)
	assert_true(menu.move(Vector2i.RIGHT))
	assert_eq(menu.selected_index(), 2)
	assert_true(menu.move(Vector2i.UP))
	assert_eq(menu.selected_index(), 0)


func test_two_dimensional_menu_does_not_select_a_missing_cell() -> void:
	var menu: Gen2WorldMenu = Gen2WorldMenu.from_input({
		"menu_kind": &"2d",
		"header": {"rows": 2, "columns": 2, "default": 1},
		"options": ["A", "B", "C"],
	})
	assert_true(menu.move(Vector2i.DOWN))
	assert_eq(menu.selected_index(), 2)
	assert_false(menu.move(Vector2i.RIGHT))
	assert_eq(menu.selected_index(), 2)


## `Script_yesorno` loads no `LoadMenuHeader`, so a `choice` header is empty and
## the box falls back to `YesNoBox`'s own `lb bc, SCREEN_WIDTH - 6, 7`.
func test_choice_with_no_header_falls_back_to_the_yes_no_box() -> void:
	var menu: Gen2WorldMenu = Gen2WorldMenu.from_input({
		"menu_kind": &"vertical", "header": {}, "choices": [&"yes", &"no"],
	})
	var box: Gen2MenuBox = menu.box()
	assert_eq(box.left, 14)
	assert_eq(box.top, 7)
	assert_eq(box.right, 19)
	assert_eq(box.bottom, 11)


## `LoadMenuHeader`'s own `menu_coords`, carried through the importer's
## top/left/bottom/right and into the box a scripted `verticalmenu` draws.
func test_vertical_menu_carries_its_own_menu_coords() -> void:
	var menu: Gen2WorldMenu = Gen2WorldMenu.from_input({
		"menu_kind": &"vertical",
		"header": {"data_flags": 1 << 7, "left": 1, "top": 1, "right": 13, "bottom": 10},
		"options": ["A", "B"],
	})
	var box: Gen2MenuBox = menu.box()
	assert_eq(box.left, 1)
	assert_eq(box.top, 1)
	assert_eq(box.right, 13)
	assert_eq(box.bottom, 10)
	assert_eq(box.flags, 1 << 7)


## `Place2DMenuItemStrings`' column count and spacing carry into the box so a
## `2d` menu's items land where the grid puts them, not one under another.
func test_two_dimensional_menu_carries_columns_and_spacing_into_its_box() -> void:
	var menu: Gen2WorldMenu = Gen2WorldMenu.from_input({
		"menu_kind": &"2d",
		"header": {"rows": 2, "columns": 3, "spacing": 5, "default": 1},
		"options": ["A", "B", "C", "D", "E", "F"],
	})
	var box: Gen2MenuBox = menu.box()
	assert_eq(box.columns, 3)
	assert_eq(box.column_spacing, 5)


## `Script_yesorno` loads no menu header, so a `choice` arrives with none. The
## fallback is `YesNoMenuHeader`'s whole record and not just its coordinates:
## without STATICMENU_CURSOR nothing draws the arrow, so the box offered two
## answers with no mark on the one A would take.
func test_a_headerless_choice_wears_the_yes_no_menu_header() -> void:
	var menu: Gen2WorldMenu = Gen2WorldMenu.from_input({
		"type": &"choice", "command": &"yesorno", "choices": [&"yes", &"no"],
	})
	assert_eq(menu.options, ["YES", "NO"], "the strings are MenuData's own")
	assert_true(
		menu.box().has_flag(Gen2MenuBox.STATICMENU_CURSOR), "and the cursor is drawn"
	)
	assert_true(menu.box().has_flag(Gen2MenuBox.STATICMENU_NO_TOP_SPACING))
	assert_eq(menu.selected_index(), 0, "`db 1` is YES")
	assert_eq(menu.box().border_position(), Vector2i(14, 7), "_YesNoBox's own box")


## A header that names its flags still wins, zero included.
func test_a_loaded_header_keeps_its_own_flags() -> void:
	var menu: Gen2WorldMenu = Gen2WorldMenu.from_input({
		"menu_kind": &"vertical", "header": {"data_flags": 0, "default": 1},
		"options": ["A", "B"],
	})
	assert_eq(menu.flags, 0)
	assert_false(menu.box().has_flag(Gen2MenuBox.STATICMENU_CURSOR))
