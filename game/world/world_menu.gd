class_name Gen2WorldMenu
extends RefCounted

## Scene-free cursor state for the bounded menu layouts imported from a
## cartridge. The screen owns labels and input; this record owns only the
## source selection rules and the returned option index.

## The two flags that decide selection. [Gen2MenuBox] owns the whole set, since
## it is the layer that reads all of them.
const STATICMENU_ENABLE_LEFT_RIGHT: int = Gen2MenuBox.STATICMENU_ENABLE_LEFT_RIGHT
const STATICMENU_WRAP: int = Gen2MenuBox.STATICMENU_WRAP

## `YesNoBox`'s own `lb bc, SCREEN_WIDTH - 6, 7`, which `_YesNoBox` turns into
## the five-wide, four-tall box at (14,7). A `choice` pending value carries no
## `loadmenu` header, since `Script_yesorno` never loads one, so this is the
## box every such prompt falls back to.
const YES_NO_LEFT: int = 14
const YES_NO_TOP: int = 7
const YES_NO_RIGHT: int = 19
const YES_NO_BOTTOM: int = 11
## `YesNoMenuHeader.MenuData`'s own `db STATICMENU_CURSOR |
## STATICMENU_NO_TOP_SPACING`. A `choice` with no `loadmenu` header behind it is
## a `Script_yesorno`, so it inherits these rather than no flags at all: without
## STATICMENU_CURSOR [Gen2MenuPage] draws no arrow, and the box said YES and NO
## with nothing marking which one A would answer.
## `YesNoMenuHeader.MenuData`'s own `db "YES@"` / `db "NO@"`. The runner names
## the two answers with internal keys, which every branch reading a choice
## compares against; those keys are not what the cartridge prints.
const YES_NO_KEYS: Array = [&"yes", &"no"]
const YES_NO_OPTIONS: Array = ["YES", "NO"]
const YES_NO_FLAGS: int = (
	Gen2MenuBox.STATICMENU_CURSOR | Gen2MenuBox.STATICMENU_NO_TOP_SPACING
)

var kind: StringName = &"vertical"
var options: Array = []
var flags: int = 0
var rows: int = 0
var columns: int = 1
var cursor: int = 0
## `menu_coords x1, y1, x2, y2`, imported off the `LoadMenuHeader` a scripted
## `verticalmenu`/`2dmenu` reads. [const YES_NO_LEFT] and its three siblings
## when there is no such header.
var box_left: int = YES_NO_LEFT
var box_top: int = YES_NO_TOP
var box_right: int = YES_NO_RIGHT
var box_bottom: int = YES_NO_BOTTOM
## `Place2DMenuItemStrings`' own column spacing, a `2d` menu's `db spacing`.
var _spacing: int = 0


static func from_input(input: Dictionary) -> Gen2WorldMenu:
	var menu := Gen2WorldMenu.new()
	var header: Dictionary = input.get("header", {})
	menu.kind = StringName(input.get("menu_kind", header.get("kind", &"vertical")))
	menu.options = input.get(
		"options", input.get("choices", header.get("options", []))
	).duplicate(true)
	if menu.options == YES_NO_KEYS:
		menu.options = YES_NO_OPTIONS.duplicate()
	menu.flags = int(header.get("data_flags", YES_NO_FLAGS))
	menu.rows = maxi(1, int(header.get("rows", menu.options.size())))
	menu.columns = maxi(1, int(header.get("columns", 1)))
	if menu.kind == &"2d":
		menu.rows = maxi(1, int(header.get("rows", menu.rows)))
		menu.columns = maxi(1, int(header.get("columns", menu.columns)))
		menu._spacing = int(header.get("spacing", 0))
	var default_position: int = int(header.get("default", 1)) - 1
	menu.cursor = menu._clamp_position(default_position)
	menu.box_left = int(header.get("left", YES_NO_LEFT))
	menu.box_top = int(header.get("top", YES_NO_TOP))
	menu.box_right = int(header.get("right", YES_NO_RIGHT))
	menu.box_bottom = int(header.get("bottom", YES_NO_BOTTOM))
	return menu


## The box the source's own `menu_coords` puts this menu in, for a renderer
## that draws it over the map the way `MenuBox` does. `Place2DMenuItemStrings`'
## own column count and spacing carry over for a `2d` menu; every list menu
## here is one column with no spacing.
func box() -> Gen2MenuBox:
	var out := Gen2MenuBox.from_coords(box_left, box_top, box_right, box_bottom, flags)
	if kind == &"2d":
		out.columns = maxi(1, columns)
		out.column_spacing = _spacing
	return out


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
	var wraps: bool = (flags & STATICMENU_WRAP) != 0
	if next_row < 0 or next_row >= rows:
		if not wraps:
			return false
		next_row = rows - 1 if next_row < 0 else 0
	if next_column < 0 or next_column >= columns:
		if not wraps:
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
