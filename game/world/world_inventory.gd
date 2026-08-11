class_name Gen2WorldInventory
extends RefCounted

## Scene-free access to the mutable item and currency state owned by a world.
## Cartridge item definitions still come from GameData; this class only
## validates and applies changes to the save-safe Gen2WorldState.

const ITEM_OLD_ROD: int = 0x3A
const ITEM_GOOD_ROD: int = 0x3B
const ITEM_SUPER_ROD: int = 0x3D
const MAX_MONEY: int = 999999
const MAX_COINS: int = 9999

var data: GameData = null
var state: Gen2WorldState = null


func _init(game_data: GameData, world_state: Gen2WorldState) -> void:
	data = game_data
	state = world_state


static func item_for_rod(rod: StringName) -> int:
	match rod:
		Gen2WorldEncounter.METHOD_OLD_ROD:
			return ITEM_OLD_ROD
		Gen2WorldEncounter.METHOD_GOOD_ROD:
			return ITEM_GOOD_ROD
		Gen2WorldEncounter.METHOD_SUPER_ROD:
			return ITEM_SUPER_ROD
	return 0


static func rod_for_item(item: int) -> StringName:
	match item:
		ITEM_OLD_ROD:
			return Gen2WorldEncounter.METHOD_OLD_ROD
		ITEM_GOOD_ROD:
			return Gen2WorldEncounter.METHOD_GOOD_ROD
		ITEM_SUPER_ROD:
			return Gen2WorldEncounter.METHOD_SUPER_ROD
	return &""


func owned_rods() -> Array[StringName]:
	var out: Array[StringName] = []
	for rod: StringName in [
		Gen2WorldEncounter.METHOD_OLD_ROD,
		Gen2WorldEncounter.METHOD_GOOD_ROD,
		Gen2WorldEncounter.METHOD_SUPER_ROD,
	]:
		if owns_rod(rod):
			out.append(rod)
	return out


func owns_rod(rod: StringName) -> bool:
	var item: int = item_for_rod(rod)
	return item > 0 and item_quantity(item) > 0


func item_quantity(item: int) -> int:
	return state.item_quantity(item) if state != null else 0


func item_name(item: int) -> String:
	if data == null:
		return ""
	return data.item_name(item)


func set_item_quantity(item: int, quantity: int) -> Dictionary:
	if data == null or state == null:
		return _failure(&"missing_inventory")
	if item <= 0 or data.item(item).is_empty():
		return _failure(&"unknown_item")
	if quantity < 0:
		return _failure(&"invalid_item_quantity")
	var current: int = item_quantity(item)
	if quantity > current:
		var receive: Dictionary = Gen2WorldPack.receive_check(
			data, state.items(), item, quantity - current
		)
		if not bool(receive.get("ok", false)):
			return receive
	var result: Dictionary = state.apply_changes({}, {}, {"items": {item: quantity}})
	if not bool(result.get("ok", false)):
		return result
	result["kind"] = &"item_quantity_changed"
	result["item"] = item
	result["quantity"] = quantity
	return result


func change_item_quantity(item: int, delta: int) -> Dictionary:
	var next: int = item_quantity(item) + delta
	if next < 0:
		return _failure(&"insufficient_item_quantity")
	return set_item_quantity(item, next)


func set_money(account: int, balance: int) -> Dictionary:
	if state == null:
		return _failure(&"missing_inventory")
	if account < 0 or balance < 0 or balance > MAX_MONEY:
		return _failure(&"invalid_money_balance")
	var result: Dictionary = state.apply_changes({}, {}, {"money": {account: balance}})
	if not bool(result.get("ok", false)):
		return result
	result["kind"] = &"money_balance_changed"
	result["account"] = account
	result["balance"] = balance
	return result


func change_money(account: int, delta: int) -> Dictionary:
	return set_money(account, state.money(account) + delta) if state != null else _failure(&"missing_inventory")


func set_coins(balance: int) -> Dictionary:
	if state == null:
		return _failure(&"missing_inventory")
	if balance < 0 or balance > MAX_COINS:
		return _failure(&"invalid_coins")
	var result: Dictionary = state.apply_changes({}, {}, {"coins": balance})
	if not bool(result.get("ok", false)):
		return result
	result["kind"] = &"coins_balance_changed"
	result["balance"] = balance
	return result


func change_coins(delta: int) -> Dictionary:
	return set_coins(state.coins() + delta) if state != null else _failure(&"missing_inventory")


static func _failure(reason: StringName) -> Dictionary:
	return {"ok": false, "reason": reason}
