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


## One entry per pocket in source display order, each carrying only the items
## currently owned in that pocket. An unknown item number, or a quantity of
## zero, is dropped rather than shown.
static func build(data: GameData, state: Gen2WorldState) -> Array:
	var pockets: Array = []
	if data == null or state == null:
		return pockets
	var owned: Dictionary = state.items()
	for pocket_type: int in POCKET_ORDER:
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
			"name": String(POCKET_NAMES.get(pocket_type, "")),
			"items": pocket_items,
		})
	return pockets


## The pack pocket a cartridge item number belongs to, or 0 when the item is
## unknown. Matches `ItemAttributes`' per-item type byte, not a guess from the
## item number's range.
static func pocket_for(data: GameData, item: int) -> int:
	if data == null:
		return 0
	return int(data.item(item).get("pocket", 0))
