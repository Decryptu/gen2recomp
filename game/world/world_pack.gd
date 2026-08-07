class_name Gen2WorldPack
extends RefCounted

## Scene-free grouping of owned items into the cartridge's four pack pockets.
##
## `Gen2WorldState` stores items as a flat item-to-quantity map; this is
## presentation only and does not change that. Classification uses the item type
## byte GameData imports under the confusingly-named `pocket` field
## (`data/items/attributes.asm`'s `item_attribute` macro calls it "pocket";
## `constants/item_data_constants.asm` names the same values
## `ITEM`/`KEY_ITEM`/`BALL`/`TM_HM`), which is what decides a real item's pocket.
## Source capacities (`MAX_ITEMS` 20, `MAX_BALLS` 12, `MAX_KEY_ITEMS` 25,
## `MAX_PC_ITEMS` 50) are recorded but not enforced, since enforcing them would
## change the save's item storage shape.
##
## Pockets registered on `Gen2ModHost` follow the four source ones, and the item
## submenu below is `engine/items/pack.asm`'s own header selection.

const TYPE_ITEM: int = 1
const TYPE_KEY_ITEM: int = 2
const TYPE_BALL: int = 3
const TYPE_TM_HM: int = 4

const MAX_ITEMS: int = 20
const MAX_BALLS: int = 12
const MAX_KEY_ITEMS: int = 25
const MAX_ITEM_STACK: int = 99

## `engine/items/pack.asm`'s own left/right pocket cycle
## (`.ItemsPocketMenu` -> `.BallsPocketMenu` -> `.KeyItemsPocketMenu` ->
## `.TMHMPocketMenu` -> back to Items), not the item type's numeric order.
const POCKET_ORDER: Array[int] = [TYPE_ITEM, TYPE_BALL, TYPE_KEY_ITEM, TYPE_TM_HM]
const POCKET_NAMES: Dictionary = {
	TYPE_ITEM: "Items",
	TYPE_BALL: "Balls",
	TYPE_KEY_ITEM: "Key Items",
	TYPE_TM_HM: "TMs/HMs",
}

## `ITEMATTR_PERMISSIONS` bits and the field-menu nibble `CheckItemMenu` returns,
## named here in this file's own terms but valued from the import layer, so the
## numbers stay defined once. A set permission bit is what the item *cannot* do,
## which is why the source's own branch labels around
## `.ItemBallsKey_LoadSubmenu` read backwards.
const CANT_SELECT: int = RomLayout.ITEM_ATTRIBUTE_CANT_SELECT
const CANT_TOSS: int = RomLayout.ITEM_ATTRIBUTE_CANT_TOSS
const ITEMMENU_NOUSE: int = RomLayout.ITEMMENU_NOUSE
const ITEMMENU_CURRENT: int = RomLayout.ITEMMENU_CURRENT
const ITEMMENU_PARTY: int = RomLayout.ITEMMENU_PARTY
const ITEMMENU_CLOSE: int = RomLayout.ITEMMENU_CLOSE

const ACTION_USE: StringName = &"use"
const ACTION_GIVE: StringName = &"give"
const ACTION_TOSS: StringName = &"toss"
const ACTION_SELECT: StringName = &"select"
const ACTION_QUIT: StringName = &"quit"

## The six field submenu headers `.ItemBallsKey_LoadSubmenu` chooses between,
## plus the TM/HM pocket's own two. Keyed by [can toss, can select, can use] for
## the first six; the header names in the source are as inverted as its branch
## labels, so the action lists are what to read here, not the names.
const SUBMENU_USE_GIVE_TOSS_SELECT_QUIT: Array[StringName] = [
	ACTION_USE, ACTION_GIVE, ACTION_TOSS, ACTION_SELECT, ACTION_QUIT,
]
const SUBMENU_USE_GIVE_TOSS_QUIT: Array[StringName] = [
	ACTION_USE, ACTION_GIVE, ACTION_TOSS, ACTION_QUIT,
]
const SUBMENU_GIVE_TOSS_SELECT_QUIT: Array[StringName] = [
	ACTION_GIVE, ACTION_TOSS, ACTION_SELECT, ACTION_QUIT,
]
const SUBMENU_GIVE_TOSS_QUIT: Array[StringName] = [
	ACTION_GIVE, ACTION_TOSS, ACTION_QUIT,
]
const SUBMENU_USE_SELECT_QUIT: Array[StringName] = [ACTION_USE, ACTION_SELECT, ACTION_QUIT]
const SUBMENU_USE_QUIT: Array[StringName] = [ACTION_USE, ACTION_QUIT]
const SUBMENU_TMHM_USE_GIVE_QUIT: Array[StringName] = [
	ACTION_USE, ACTION_GIVE, ACTION_QUIT,
]

const ACTION_LABELS: Dictionary = {
	ACTION_USE: "USE",
	ACTION_GIVE: "GIVE",
	ACTION_TOSS: "TOSS",
	ACTION_SELECT: "SEL",
	ACTION_QUIT: "QUIT",
}

## GIVE needs a held-item model, TOSS a quantity prompt and SEL the Select-button
## registration; none exists yet, so all three keep their source position and are
## marked unavailable, the way the party submenu carries STATS, SWITCH and MOVE.
const IMPLEMENTED_ACTIONS: Array[StringName] = [ACTION_USE, ACTION_QUIT]


## One entry per pocket in source display order, each carrying only the items
## currently owned in that pocket. An unknown item number, or a quantity of
## zero, is dropped rather than shown.
static func build(data: GameData, state: Gen2WorldState) -> Array:
	var pockets: Array = []
	if data == null or state == null:
		return pockets
	var owned: Dictionary = state.items()
	for pocket_type: int in pocket_order():
		var pocket_items: Array = []
		var item_numbers: Array = owned.keys()
		item_numbers.sort()
		for raw_item: Variant in item_numbers:
			var item: int = int(raw_item)
			var quantity: int = int(owned[raw_item])
			if quantity <= 0:
				continue
			var definition: Dictionary = data.item(item)
			if definition.is_empty() or int(definition.get("pocket", 0)) != pocket_type:
				continue
			pocket_items.append({
				"item": item,
				"name": String(definition.get("name", "UNKNOWN")),
				"quantity": quantity,
				"field_menu": int(definition.get("field_menu", 0)),
			})
		pockets.append({
			"pocket": pocket_type,
			"name": pocket_name(pocket_type),
			"items": pocket_items,
		})
	return pockets


## The source pocket cycle followed by whatever a mod registered, so a mod pocket
## is reached by continuing right past TMs/HMs rather than displacing a
## cartridge one.
static func pocket_order() -> Array[int]:
	var order: Array[int] = POCKET_ORDER.duplicate()
	for entry: Dictionary in Gen2ModHost.instance().menu_entries(Gen2ModHost.MENU_PACK_POCKET):
		var pocket: int = int(entry.get("pocket", 0))
		if pocket > 0 and not order.has(pocket):
			order.append(pocket)
	return order


static func pocket_name(pocket_type: int) -> String:
	if POCKET_NAMES.has(pocket_type):
		return String(POCKET_NAMES[pocket_type])
	for entry: Dictionary in Gen2ModHost.instance().menu_entries(Gen2ModHost.MENU_PACK_POCKET):
		if int(entry.get("pocket", 0)) == pocket_type:
			return String(entry.get("label", ""))
	return ""


## `.ItemBallsKey_LoadSubmenu` and `.TMHMPocketMenu`'s own two-way split, as the
## action list the chosen header carries. The three checks the source makes are
## all inverted, so this reads them once into positive terms and branches in the
## source's order: tossable first, then selectable, then usable.
static func item_submenu(data: GameData, item: int) -> Array:
	if data == null:
		return []
	var definition: Dictionary = data.item(item)
	if definition.is_empty():
		return []
	var permissions: int = int(definition.get("permissions", 0))
	var can_toss: bool = (permissions & CANT_TOSS) == 0
	var can_select: bool = (permissions & CANT_SELECT) == 0
	# CheckItemMenu tests the nibble against zero, not against ITEMMENU_CURRENT,
	# so a value of 1 to 3 would offer USE and then reach .Oak's refusal. No
	# cartridge item carries one; all 256 rows are NOUSE, CURRENT, PARTY or CLOSE.
	var can_use: bool = int(definition.get("field_menu", 0)) != 0
	var actions: Array[StringName] = SUBMENU_USE_QUIT
	if int(definition.get("pocket", 0)) == TYPE_TM_HM:
		actions = SUBMENU_USE_QUIT if not can_toss else SUBMENU_TMHM_USE_GIVE_QUIT
	elif not can_toss:
		actions = SUBMENU_USE_QUIT if not can_select else SUBMENU_USE_SELECT_QUIT
	elif not can_select:
		actions = SUBMENU_USE_GIVE_TOSS_QUIT if can_use else SUBMENU_GIVE_TOSS_QUIT
	else:
		actions = SUBMENU_USE_GIVE_TOSS_SELECT_QUIT if can_use else SUBMENU_GIVE_TOSS_SELECT_QUIT
	var entries: Array = []
	for action: StringName in actions:
		entries.append({
			"action": action,
			"label": String(ACTION_LABELS.get(action, "")),
			"available": IMPLEMENTED_ACTIONS.has(action),
		})
	return entries


## `UseItem`'s jumptable index: which of `.Oak`, `.Current`, `.Party` and
## `.Field` a USE reaches. Everything below `ITEMMENU_CURRENT` is `.Oak`.
static func field_use_kind(data: GameData, item: int) -> int:
	if data == null:
		return ITEMMENU_NOUSE
	var menu: int = int(data.item(item).get("field_menu", 0))
	return menu if menu >= ITEMMENU_CURRENT else ITEMMENU_NOUSE


## The pack pocket a cartridge item number belongs to, or 0 when the item is
## unknown. Matches `ItemAttributes`' per-item type byte, not a guess from the
## item number's range.
static func pocket_for(data: GameData, item: int) -> int:
	if data == null:
		return 0
	return int(data.item(item).get("pocket", 0))
