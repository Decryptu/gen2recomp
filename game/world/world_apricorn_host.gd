class_name Gen2WorldApricornHost
extends RefCounted

## `Kurt_GiveUpSelectedQuantityOfSelectedApricorn` (`engine/events/kurt.asm`) as
## a validated candidate-save transaction. The selection itself is
## [Gen2WorldApricorn]; this only takes the apricorns and resumes the script.
##
## The source routine collects every bag stack of the item, sorts them and
## empties them in turn ("Compatible with multiple stacks"). The flat item model
## holds one stack per item, so the walk collapses to a single `Kurt_GetRidOfItem`.
## HANDOFF's item-stack divergence covers it.

static func complete_runtime_request(
	world: Gen2WorldAPI,
	result: Dictionary,
	save: Gen2SaveData = null,
	persist: bool = true
) -> Dictionary:
	if world == null or world.data == null or world.state == null:
		return _failure(&"missing_world", {})
	var item: int = int(result.get("item", 0))
	var quantity: int = int(result.get("quantity", 0))
	if item == 0:
		return _resume(world, {"ok": true, "item": 0, "quantity": 0})
	if not Gen2WorldApricorn.is_apricorn(item):
		return _failure(&"invalid_apricorn", {"item": item})
	if quantity < 1 or quantity > Gen2WorldApricorn.quantity_of(world.state, item):
		return _failure(&"invalid_apricorn_quantity", {
			"item": item, "quantity": quantity,
			"owned": world.state.item_quantity(item),
		})
	var before: Gen2WorldSnapshot = world.snapshot()
	var applied: Dictionary = world.state.apply_changes({}, {}, {
		"items": {item: world.state.item_quantity(item) - quantity},
	})
	if not bool(applied.get("ok", false)):
		return _failure(&"apricorn_state_failed", applied)
	var resumed: Dictionary = _resume(world, {
		"ok": true, "item": item, "quantity": quantity,
	})
	if not bool(resumed.get("ok", false)):
		world.state.restore_from_dict(before.world_state.to_dict())
		return resumed
	if save == null:
		return resumed
	var committed: Dictionary = Gen2WorldTransaction.run(world, save, before, persist)
	if not bool(committed.get("ok", false)):
		return _failure(StringName(committed.get("reason", &"")), committed.get("details", {}))
	return resumed


static func _resume(world: Gen2WorldAPI, completion: Dictionary) -> Dictionary:
	var resumed: Array = world.complete_runtime_request(completion)
	if resumed.is_empty() or not bool(resumed[0].get("ok", false)):
		return _failure(&"apricorn_request_failed", {"results": resumed})
	return {
		"ok": true,
		"handled": true,
		"item": int(completion.get("item", 0)),
		"quantity": int(completion.get("quantity", 0)),
		"results": resumed,
	}


static func _failure(reason: StringName, details: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"handled": false,
		"status": &"host_unavailable",
		"reason": reason,
		"details": details.duplicate(true),
	}
