class_name Gen2SaveStorage
extends RefCounted

## Atomic party and PC-box transactions for a validated project save.
##
## Each operation edits a deep candidate, validates it against the selected
## cartridge cache, writes it through the save store, and only then updates the
## shared runtime save object. A failed write or validation therefore leaves
## both the in-memory and on-disk save untouched.


static func deposit_party_to_box(
	save: Gen2SaveData,
	data: GameData,
	party_index: int,
	box_index: int = -1,
	box_slot: int = -1,
) -> Dictionary:
	var candidate_result: Dictionary = _candidate(save, data)
	if not bool(candidate_result.get("ok", false)):
		return candidate_result
	var candidate: Gen2SaveData = candidate_result["save"]
	if party_index < 0 or party_index >= candidate.party.size():
		return _failure(&"invalid_party_index")
	if candidate.party.size() <= 1:
		return _failure(&"last_party_member")
	var mon: Gen2SaveMon = candidate.party[party_index]
	if mon == null:
		return _failure(&"missing_pokemon")
	var destination: Dictionary = _box_destination(candidate, box_index, box_slot)
	if not bool(destination.get("ok", false)):
		return destination
	var box: Gen2SaveBox = candidate.boxes[int(destination["box"])]
	var placed: Dictionary = box.put(mon, int(destination["slot"]))
	if not bool(placed.get("ok", false)):
		return _failure(StringName(placed.get("reason", &"box_insert_failed")))
	candidate.party.remove_at(party_index)
	return _commit(save, data, candidate, {
		"kind": &"party_to_box",
		"party_index": party_index,
		"box": int(destination["box"]),
		"slot": int(destination["slot"]),
	})


static func withdraw_box_to_party(
	save: Gen2SaveData,
	data: GameData,
	box_index: int,
	box_slot: int,
) -> Dictionary:
	var candidate_result: Dictionary = _candidate(save, data)
	if not bool(candidate_result.get("ok", false)):
		return candidate_result
	var candidate: Gen2SaveData = candidate_result["save"]
	if box_index < 0 or box_index >= candidate.boxes.size():
		return _failure(&"invalid_box_index")
	if box_slot < 0 or box_slot >= Gen2SaveBox.CAPACITY:
		return _failure(&"invalid_box_slot")
	if candidate.party.size() >= Gen2SaveData.MAX_PARTY:
		return _failure(&"party_full")
	var box: Gen2SaveBox = candidate.boxes[box_index]
	if box == null or box_slot >= box.slots.size():
		return _failure(&"invalid_box_shape")
	var mon: Gen2SaveMon = box.slots[box_slot]
	if mon == null:
		return _failure(&"empty_box_slot")
	box.slots[box_slot] = null
	candidate.party.append(mon)
	return _commit(save, data, candidate, {
		"kind": &"box_to_party",
		"party_index": candidate.party.size() - 1,
		"box": box_index,
		"slot": box_slot,
	})


static func _candidate(save: Gen2SaveData, data: GameData) -> Dictionary:
	if save == null or data == null:
		return _failure(&"missing_save_context")
	var candidate: Gen2SaveData = Gen2SaveData.from_dict(save.to_dict())
	if candidate == null:
		return _failure(&"invalid_save_shape")
	var validation: Dictionary = Gen2SaveValidator.validate(save, data)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"reason": &"invalid_save",
			"message": validation.get("message", "save validation failed"),
		}
	return {"ok": true, "save": candidate}


static func _box_destination(
	save: Gen2SaveData, box_index: int, box_slot: int
) -> Dictionary:
	if box_index < 0:
		return save.first_empty_box_slot()
	if box_index >= save.boxes.size():
		return _failure(&"invalid_box_index")
	var box: Gen2SaveBox = save.boxes[box_index]
	if box == null:
		return _failure(&"invalid_box_shape")
	var target_slot: int = box_slot if box_slot >= 0 else box.first_empty_slot()
	if target_slot < 0:
		return _failure(&"box_full")
	if target_slot >= Gen2SaveBox.CAPACITY:
		return _failure(&"invalid_box_slot")
	if target_slot >= box.slots.size():
		return _failure(&"invalid_box_shape")
	if box.slots[target_slot] != null:
		return _failure(&"box_slot_occupied")
	return {"ok": true, "box": box_index, "slot": target_slot}


static func _commit(
	source: Gen2SaveData,
	data: GameData,
	candidate: Gen2SaveData,
	transaction: Dictionary,
) -> Dictionary:
	var write: Dictionary = Gen2SaveStore.save(candidate, data)
	if not bool(write.get("ok", false)):
		return {
			"ok": false,
			"reason": &"save_failed",
			"message": write.get("message", "save failed"),
		}
	source.copy_from(candidate)
	var result: Dictionary = {"ok": true, "message": ""}
	for key: Variant in transaction:
		result[key] = transaction[key]
	return result


static func _failure(reason: StringName) -> Dictionary:
	return {"ok": false, "reason": reason, "message": String(reason)}
