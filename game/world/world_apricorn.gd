class_name Gen2WorldApricorn
extends RefCounted

## `SelectApricornForKurt` (`engine/events/kurt.asm`) as a scene-free state
## machine: `FindApricornsInBag`'s list, `Kurt_SelectApricorn`'s scrolling menu,
## and the loop that puts the player back on the list when
## `Kurt_SelectQuantity` is backed out of. The screen owns the two boxes; this
## owns the cursor and the answer. [Gen2WorldApricornHost] owns the transaction.

## `data/items/apricorn_balls.asm`. Kurt's list order is this table's, not the
## item numbers'. The second column is the ball each apricorn becomes, which is
## what `KurtsHouse.asm`'s seven `verbosegiveitemvar` branches hand back.
## Both columns hold the same numbers on all three cartridges.
const APRICORN_BALLS: Array[Array] = [
	[0x55, 0x9F], # RED, LEVEL_BALL
	[0x59, 0xA0], # BLU, LURE_BALL
	[0x5C, 0xA5], # YLW, MOON_BALL
	[0x5D, 0xA4], # GRN, FRIEND_BALL
	[0x61, 0xA1], # WHT, FAST_BALL
	[0x63, 0x9D], # BLK, HEAVY_BALL
	[0x65, 0xA6], # PNK, LOVE_BALL
]

## `Kurt_GetQuantityOfApricorn`'s own ceiling, which is not the pocket's.
const MAX_QUANTITY: int = 99

## `.MenuData`'s `db 4, 7`: four visible rows, seven characters to the quantity
## column. Only the height decides selection.
const MENU_HEIGHT: int = 4

const SELECT_APRICORN: StringName = &"select_apricorn"
const SELECT_QUANTITY: StringName = &"select_quantity"
const DONE: StringName = &"done"

var entries: Array = []
## `wMenuScrollPosition`, which `SelectApricornForKurt` zeroes once and then
## leaves alone, so a backed-out quantity reopens the list where it was.
var scroll: int = 0
## `wMenuCursorY`, the 1-based row inside the window rather than an index.
var cursor_y: int = 1
var phase: StringName = DONE
var prompt: Gen2WorldQuantityPrompt = null
var selected_item: int = 0
var selected_quantity: int = 0


static func open(data: GameData, state: Gen2WorldState) -> Gen2WorldApricorn:
	var selection := Gen2WorldApricorn.new()
	selection.entries = find_in_bag(data, state)
	## `FindApricornsInBag` returns carry on an empty list, which
	## `Kurt_SelectApricorn` turns into the same zero a B press gives.
	if not selection.entries.is_empty():
		selection._open_list(1)
	return selection


## `FindApricornsInBag` (`engine/menus/menu_2.asm`): the `ApricornBalls` table
## filtered by `CheckItem`, in table order.
static func find_in_bag(data: GameData, state: Gen2WorldState) -> Array:
	var out: Array = []
	if data == null or state == null:
		return out
	for row: Array in APRICORN_BALLS:
		var item: int = int(row[0])
		if state.item_quantity(item) <= 0:
			continue
		out.append({
			"item": item,
			"ball": int(row[1]),
			"name": data.item_name(item),
			"quantity": quantity_of(state, item),
		})
	return out


## `Kurt_GetQuantityOfApricorn`. The source walks every stack of the item and
## clamps the total; the flat item model holds one stack, so only the clamp is
## left. See HANDOFF's item-stack divergence.
static func quantity_of(state: Gen2WorldState, item: int) -> int:
	if state == null:
		return 0
	return mini(state.item_quantity(item), MAX_QUANTITY)


static func is_apricorn(item: int) -> bool:
	for row: Array in APRICORN_BALLS:
		if int(row[0]) == item:
			return true
	return false


func is_done() -> bool:
	return phase == DONE


## The visible rows `ScrollingMenu_InitFlags` asks `_2DMenu` for: the window's
## own height, or the whole list plus the CANCEL row when it is shorter.
func rows() -> int:
	return MENU_HEIGHT if MENU_HEIGHT <= entries.size() else entries.size() + 1


## `ScrollingMenu_GetListItemCoordAndFunctionArgs`' index. An index at or past
## the list is the `-1` the item buffer is filled with, drawn as CANCEL.
func selected_index() -> int:
	return scroll + cursor_y - 1


func selected_entry() -> Dictionary:
	var index: int = selected_index()
	return entries[index] if index >= 0 and index < entries.size() else {}


func press(button: int) -> void:
	match phase:
		SELECT_APRICORN:
			_press_list(button)
		SELECT_QUANTITY:
			_press_quantity(button)


## The answer `wScriptVar` and `wKurtApricornQuantity` carry once the special
## returns. Backing out of either box is `wScriptVar = 0`.
func result() -> Dictionary:
	return {"item": selected_item, "quantity": selected_quantity}


func _press_list(button: int) -> void:
	match button:
		Gen2Button.UP:
			## `_2DMenu` moves inside the window and hands the edge to
			## `ScrollingMenuJoyAction`, which scrolls instead of wrapping.
			if cursor_y > 1:
				cursor_y -= 1
			elif scroll > 0:
				scroll -= 1
		Gen2Button.DOWN:
			if cursor_y < rows():
				cursor_y += 1
			elif scroll + MENU_HEIGHT <= entries.size():
				scroll += 1
		Gen2Button.A:
			var entry: Dictionary = selected_entry()
			if entry.is_empty():
				_cancel()
				return
			selected_item = int(entry.get("item", 0))
			var available: int = int(entry.get("quantity", 0))
			## `Kurt_SelectQuantity` leaves without carry when the bag holds
			## none, which is the same path a backed-out box takes.
			if available <= 0:
				_open_list(cursor_y)
				return
			prompt = Gen2WorldQuantityPrompt.open(available)
			phase = SELECT_QUANTITY
		Gen2Button.B:
			_cancel()


func _press_quantity(button: int) -> void:
	if prompt == null:
		_cancel()
		return
	match prompt.press(button):
		Gen2WorldQuantityPrompt.CONFIRMED:
			selected_quantity = prompt.value
			prompt = null
			phase = DONE
		Gen2WorldQuantityPrompt.CANCELLED:
			prompt = null
			_open_list(cursor_y)


## `InitScrollingMenuCursor` then `ScrollingMenu_InitFlags`' cursor placement,
## over the row `SelectApricornForKurt` carries back into `wMenuSelection`.
func _open_list(position: int) -> void:
	var end: int = entries.size() + 1
	if end < MENU_HEIGHT + scroll:
		scroll = maxi(0, end - MENU_HEIGHT)
	var next_position: int = position
	if end < scroll + next_position:
		scroll = 0
		next_position = 1
	cursor_y = next_position if next_position >= 1 and next_position <= rows() else 1
	phase = SELECT_APRICORN


func _cancel() -> void:
	selected_item = 0
	selected_quantity = 0
	prompt = null
	phase = DONE
