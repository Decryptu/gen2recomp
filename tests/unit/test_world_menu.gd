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
