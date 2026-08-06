class_name Gen2WorldMenu
extends RefCounted

## Scene-free cursor state for the bounded menu layouts imported from a
## cartridge. The screen owns labels and input; this record owns only the
## source selection rules and the returned option index.

const STATICMENU_ENABLE_LEFT_RIGHT: int = 1 << 2
const STATICMENU_WRAP: int = 1 << 5

var kind: StringName = &"vertical"
var options: Array = []
var flags: int = 0
var rows: int = 0
var columns: int = 1
var cursor: int = 0


static func from_input(input: Dictionary) -> Gen2WorldMenu:
	var menu := Gen2WorldMenu.new()
	var header: Dictionary = input.get("header", {})
	menu.kind = StringName(input.get("menu_kind", header.get("kind", &"vertical")))
	menu.options = input.get(
		"options", input.get("choices", header.get("options", []))
	).duplicate(true)
	menu.flags = int(header.get("data_flags", 0))
	menu.rows = maxi(1, int(header.get("rows", menu.options.size())))
	menu.columns = maxi(1, int(header.get("columns", 1)))
	if menu.kind == &"2d":
		menu.rows = maxi(1, int(header.get("rows", menu.rows)))
		menu.columns = maxi(1, int(header.get("columns", menu.columns)))
	var default_position: int = int(header.get("default", 1)) - 1
	menu.cursor = menu._clamp_position(default_position)
	return menu


func move(direction: Vector2i) -> bool:
	if options.is_empty():
		return false
	if kind == &"2d":
		return _move_2d(direction)
	if direction.x != 0:
		return false
	return _move_vertical(direction.y)


func selected_index() -> int:
	return cursor


func selected_value() -> Variant:
	if cursor < 0 or cursor >= options.size():
		return null
	return options[cursor]


func row() -> int:
	return cursor / columns if columns > 0 else 0


func column() -> int:
	return cursor % columns if columns > 0 else 0


func horizontal_enabled() -> bool:
	return kind == &"2d" or (flags & STATICMENU_ENABLE_LEFT_RIGHT) != 0


func _move_vertical(delta: int) -> bool:
	if delta == 0:
		return false
	var next: int = cursor + signi(delta)
	if next < 0 or next >= options.size():
		if (flags & STATICMENU_WRAP) != 0:
			next = options.size() - 1 if next < 0 else 0
		else:
			return false
	cursor = next
	return true


func _move_2d(direction: Vector2i) -> bool:
	var next_row: int = row() + signi(direction.y)
	var next_column: int = column() + signi(direction.x)
	var wrap: bool = (flags & STATICMENU_WRAP) != 0
	if next_row < 0 or next_row >= rows:
		if not wrap:
			return false
		next_row = rows - 1 if next_row < 0 else 0
	if next_column < 0 or next_column >= columns:
		if not wrap:
			return false
		next_column = columns - 1 if next_column < 0 else 0
	var next: int = next_row * columns + next_column
	if next < 0 or next >= options.size():
		return false
	cursor = next
	return true


func _clamp_position(position: int) -> int:
	if options.is_empty():
		return 0
	return clampi(position, 0, options.size() - 1)
