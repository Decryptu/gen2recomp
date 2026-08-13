class_name Gen2WorldMartHost
extends RefCounted

## Scene-free mart transactions over imported lists and mutable world state.
## The UI owns selection; this class owns validation, money, inventory and save
## writeback for one purchase.

const MONEY_ACCOUNT: int = 0
const MAX_ITEM_STACK: int = 99

const MARTTYPE_STANDARD: int = 0
const MARTTYPE_BITTER: int = 1
const MARTTYPE_BARGAIN: int = 2
const MARTTYPE_PHARMACY: int = 3
const MARTTYPE_ROOFTOP: int = 4


## Resolves the source pokemart dialog before the UI is opened. Standard,
## bitter and pharmacy shops use the indexed pointer; bargain and rooftop
## shops use their imported priced records.
static func resolve_mart(
	data: GameData, dialog_id: int, mart_id: int, rooftop_after_hall: bool = false,
	world_state: Gen2WorldState = null
) -> Dictionary:
	if data == null:
		return _failure(&"missing_data", {})
	var mart: Dictionary = {}
	var variant: StringName = &"standard"
	var label: String = "MART"
	match dialog_id:
		MARTTYPE_STANDARD:
			mart = data.world_mart(mart_id)
			variant = &"standard"
			label = "MART"
		MARTTYPE_BITTER:
			mart = data.world_mart(mart_id)
			variant = &"bitter"
			label = "HERB SHOP"
		MARTTYPE_BARGAIN:
			mart = data.world_mart_special(&"bargain")
			variant = &"bargain"
			label = "BARGAIN SHOP"
		MARTTYPE_PHARMACY:
			mart = data.world_mart(mart_id)
			variant = &"pharmacy"
			label = "PHARMACY"
		MARTTYPE_ROOFTOP:
			variant = &"rooftop_mart_2" if rooftop_after_hall else &"rooftop_mart_1"
			mart = data.world_mart_special(variant)
			label = "ROOFTOP SALE"
		_:
			return _failure(&"unsupported_mart_dialog", {"dialog": dialog_id})
	if variant == &"bargain" and world_state != null \
		and world_state.bargain_merchant_closed(Gen2WorldState.is_crystal_profile(data)):
		return _failure(&"bargain_mart_closed", {"dialog": dialog_id})
	if mart.is_empty() or not mart.has("items") or not mart["items"] is Array \
		or (mart["items"] as Array).is_empty():
		return _failure(&"mart_variant_unavailable", {
			"dialog": dialog_id, "variant": variant, "mart_id": mart_id,
		})
	mart["dialog_id"] = dialog_id
	mart["mart_id"] = mart_id
	mart["variant"] = variant
	mart["label"] = label
	return {"ok": true, "mart": mart}


static func entries(data: GameData, mart: Dictionary) -> Array:
	var out: Array = []
	if data == null:
		return out
	var raw_items: Variant = mart.get("items", [])
	if not raw_items is Array:
		return out
	for raw: Variant in raw_items as Array:
		var item: int = int(raw) if not raw is Dictionary else int((raw as Dictionary).get("item", 0))
		if item <= 0:
			continue
		var definition: Dictionary = data.item(item)
		if definition.is_empty():
			continue
		var price: int = int(definition.get("price", 0))
		if raw is Dictionary and (raw as Dictionary).has("price"):
			price = int((raw as Dictionary).get("price", price))
		if price < 0:
			continue
		var sold_out: bool = false
		var sold_items: Variant = mart.get("_sold_items", {})
		if sold_items is Dictionary:
			sold_out = bool((sold_items as Dictionary).get(item, false))
		out.append({
			"item": item,
			"name": String(definition.get("name", "UNKNOWN")),
			"price": price,
			"pocket": int(definition.get("pocket", 0)),
			"sold_out": sold_out,
		})
	return out


static func purchase(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	mart: Dictionary,
	item: int,
	quantity: int = 1,
	persist: bool = true
) -> Dictionary:
	if world == null or world.data == null or world.state == null:
		return _failure(&"missing_world", {})
	if quantity <= 0:
		return _failure(&"invalid_purchase_quantity", {"quantity": quantity})
	var is_bargain: bool = StringName(mart.get("variant", &"")) == &"bargain"
	if is_bargain and quantity != 1:
		return _failure(&"bargain_quantity_must_be_one", {"quantity": quantity})
	if is_bargain:
		var sold_items: Variant = mart.get("_sold_items", {})
		if sold_items is Dictionary and bool((sold_items as Dictionary).get(item, false)):
			return _failure(&"bargain_item_sold_out", {"item": item})
	var selected: Dictionary = {}
	for entry: Dictionary in entries(world.data, mart):
		if int(entry.get("item", 0)) == item:
			selected = entry
			break
	if selected.is_empty():
		return _failure(&"item_not_in_mart", {"item": item})
	var price: int = int(selected.get("price", 0))
	var total: int = price * quantity
	var owned: int = world.state.item_quantity(item)
	var next_quantity: int = owned + quantity
	if next_quantity > MAX_ITEM_STACK:
		return _failure(&"item_stack_full", {
			"item": item, "quantity": quantity, "owned": owned,
			"maximum": MAX_ITEM_STACK,
		})
	var balance: int = world.state.money(MONEY_ACCOUNT)
	if total < 0 or total > balance:
		return _failure(&"insufficient_money", {
			"item": item, "price": price, "quantity": quantity,
			"total": total, "balance": balance,
		})
	var merchant_closed_flag: int = Gen2WorldState.ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED \
		if Gen2WorldState.is_crystal_profile(world.data) \
		else Gen2WorldState.ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED_GOLD_SILVER
	var before: Gen2WorldSnapshot = world.snapshot()
	var applied: Dictionary = world.state.apply_changes({}, {}, {
		"items": {item: next_quantity},
		"money": {MONEY_ACCOUNT: balance - total},
		"engine_flags": {
			merchant_closed_flag: true,
		} if is_bargain else {},
	})
	if not bool(applied.get("ok", false)):
		return _failure(&"purchase_state_failed", applied)
	var committed: Dictionary = Gen2WorldTransaction.run(world, save, before, persist)
	if not bool(committed.get("ok", false)):
		return committed
	if is_bargain:
		var next_sold_items: Dictionary = {}
		var previous_sold_items: Variant = mart.get("_sold_items", {})
		if previous_sold_items is Dictionary:
			next_sold_items = (previous_sold_items as Dictionary).duplicate()
		next_sold_items[item] = true
		mart["_sold_items"] = next_sold_items
	return {
		"ok": true,
		"item": item,
		"name": selected.get("name", "UNKNOWN"),
		"quantity": quantity,
		"price": price,
		"total": total,
		"balance": balance - total,
		"owned": next_quantity,
	}


static func _failure(reason: StringName, details: Dictionary) -> Dictionary:
	return Gen2WorldTransaction.failure(reason, details)
