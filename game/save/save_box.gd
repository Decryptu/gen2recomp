class_name Gen2SaveBox
extends RefCounted

## One persistent Generation 2 PC box.
##
## A box is deliberately only a fixed ordered set of save Pokémon. Box names,
## current-box UI state and cartridge SRAM placement remain outside this
## project model until they have a canonical owner.

const CAPACITY: int = 20

var slots: Array = []
var shape_valid: bool = true


func _init() -> void:
	slots.resize(CAPACITY)
	slots.fill(null)


static func from_dict(raw: Variant) -> Gen2SaveBox:
	if not raw is Array:
		return null
	var source: Array = raw as Array
	var out := Gen2SaveBox.new()
	out.shape_valid = source.size() == CAPACITY
	for index: int in CAPACITY:
		if index >= source.size():
			continue
		var raw_mon: Variant = source[index]
		if raw_mon == null:
			continue
		if not raw_mon is Dictionary:
			out.shape_valid = false
			continue
		out.slots[index] = Gen2SaveMon.from_dict(raw_mon)
	return out


func to_dict() -> Array:
	var out: Array = []
	for index: int in CAPACITY:
		var mon: Gen2SaveMon = slots[index] if index < slots.size() else null
		out.append(mon.to_dict() if mon != null else null)
	return out


func first_empty_slot() -> int:
	for index: int in CAPACITY:
		if index >= slots.size() or slots[index] == null:
			return index
	return -1


func put(mon: Gen2SaveMon, slot: int = -1) -> Dictionary:
	if mon == null:
		return {"ok": false, "reason": &"missing_pokemon"}
	var target: int = slot if slot >= 0 else first_empty_slot()
	if target < 0 or target >= CAPACITY:
		return {"ok": false, "reason": &"box_full"}
	if target >= slots.size():
		return {"ok": false, "reason": &"invalid_box_shape"}
	if slots[target] != null:
		return {"ok": false, "reason": &"box_slot_occupied", "slot": target}
	slots[target] = mon
	return {"ok": true, "slot": target}


func occupied_count() -> int:
	var count: int = 0
	for slot: Variant in slots:
		if slot != null:
			count += 1
	return count
