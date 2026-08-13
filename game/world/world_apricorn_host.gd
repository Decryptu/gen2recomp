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
	var committed: Dictionary = _commit(world, save, before, persist)
	if not bool(committed.get("ok", false)):
		return committed
	return resumed


## The same boundary every party- or bag-owned transaction here commits through:
## validate the save, rebuild it around the resumed world and write it, putting
## the live state back when any of the three refuses.
static func _commit(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	before: Gen2WorldSnapshot,
	persist: bool
) -> Dictionary:
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
	return {"ok": true}


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


static func _copy_save(target: Gen2SaveData, source: Gen2SaveData) -> void:
	target.format_version = source.format_version
	target.game_id = source.game_id
	target.rom_sha1 = source.rom_sha1
	target.slot = source.slot
	target.player_name = source.player_name
	target.party = source.party.duplicate(true)
	target.boxes = source.boxes
	target.world = source.world


static func _failure(reason: StringName, details: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"handled": false,
		"status": &"host_unavailable",
		"reason": reason,
		"details": details.duplicate(true),
	}
