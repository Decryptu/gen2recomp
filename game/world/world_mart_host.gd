class_name Gen2WorldMartHost
extends RefCounted

## Scene-free mart transactions over imported lists and mutable world state.
## The UI owns selection; this class owns validation, money, inventory and save
## writeback for one purchase.

const MONEY_ACCOUNT: int = 0


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
		out.append({
			"item": item,
			"name": String(definition.get("name", "UNKNOWN")),
			"price": price,
			"pocket": int(definition.get("pocket", 0)),
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
	var selected: Dictionary = {}
	for entry: Dictionary in entries(world.data, mart):
		if int(entry.get("item", 0)) == item:
			selected = entry
			break
	if selected.is_empty():
		return _failure(&"item_not_in_mart", {"item": item})
	var price: int = int(selected.get("price", 0))
	var total: int = price * quantity
	var balance: int = world.state.money(MONEY_ACCOUNT)
	if total < 0 or total > balance:
		return _failure(&"insufficient_money", {
			"item": item, "price": price, "quantity": quantity,
			"total": total, "balance": balance,
		})
	var next_quantity: int = world.state.item_quantity(item) + quantity
	var before: Gen2WorldSnapshot = world.snapshot()
	var applied: Dictionary = world.state.apply_changes({}, {}, {
		"items": {item: next_quantity},
		"money": {MONEY_ACCOUNT: balance - total},
	})
	if not bool(applied.get("ok", false)):
		return _failure(&"purchase_state_failed", applied)
	if save != null:
		var validation: Dictionary = Gen2SaveValidator.validate(save, world.data)
		if not bool(validation.get("ok", false)):
			world.state.restore_from_dict(before.world_state.to_dict())
			return _failure(&"invalid_save", {"message": validation.get("message", "")})
		var candidate: Gen2SaveData = Gen2SaveData.from_dict(save.to_dict())
		candidate.world = world.snapshot()
		var candidate_validation: Dictionary = Gen2SaveValidator.validate(candidate, world.data)
		if not bool(candidate_validation.get("ok", false)):
			world.state.restore_from_dict(before.world_state.to_dict())
			return _failure(&"candidate_save_invalid", candidate_validation)
		if persist:
			var write_result: Dictionary = Gen2SaveStore.save(candidate, world.data)
			if not bool(write_result.get("ok", false)):
				world.state.restore_from_dict(before.world_state.to_dict())
				return _failure(&"save_failed", write_result)
		_copy_save(save, candidate)
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


static func _copy_save(target: Gen2SaveData, source: Gen2SaveData) -> void:
	target.format_version = source.format_version
	target.game_id = source.game_id
	target.rom_sha1 = source.rom_sha1
	target.slot = source.slot
	target.player_name = source.player_name
	target.party = source.party.duplicate(true)
	target.world = source.world


static func _failure(reason: StringName, details: Dictionary) -> Dictionary:
	return {"ok": false, "reason": reason, "details": details.duplicate(true)}
