class_name Gen2WorldFishing
extends RefCounted

## Scene-free host boundary for the Generation 2 fishing interaction.
##
## The cartridge rolls the fishing result before it queues the cast script. The
## pending result is therefore resolved in begin(), while the host advances
## through the visible cast and bite pauses without owning encounter rules.

const STATE_IDLE: StringName = &"idle"
const STATE_CASTING: StringName = &"casting"
const STATE_BITE: StringName = &"bite"

const _RODS: Array[StringName] = [
	Gen2WorldEncounter.METHOD_OLD_ROD,
	Gen2WorldEncounter.METHOD_GOOD_ROD,
	Gen2WorldEncounter.METHOD_SUPER_ROD,
]

var _state: StringName = STATE_IDLE
var _pending_encounter: Dictionary = {}
var _context: Dictionary = {}


static func rods() -> Array[StringName]:
	return _RODS.duplicate()


static func is_rod(value: StringName) -> bool:
	return _RODS.has(value)


static func rod_label(value: StringName) -> String:
	match value:
		Gen2WorldEncounter.METHOD_OLD_ROD:
			return "OLD ROD"
		Gen2WorldEncounter.METHOD_GOOD_ROD:
			return "GOOD ROD"
		Gen2WorldEncounter.METHOD_SUPER_ROD:
			return "SUPER ROD"
	return "UNKNOWN ROD"


func state() -> StringName:
	return _state


func is_busy() -> bool:
	return _state != STATE_IDLE


func begin(
	rod: StringName,
	record: Dictionary,
	fish_group: int,
	selected_fish_group: int,
	time_of_day: int,
	time_groups: Array,
	map_id: Vector2i,
	cell: Vector2i,
	facing: int,
	facing_cell: Vector2i,
	movement: StringName,
	random: RandomNumberGenerator = null,
	force_encounter: bool = false,
) -> Dictionary:
	if is_busy():
		return _failure(&"fishing_in_progress")
	if not is_rod(rod):
		return _failure(&"invalid_rod")
	if fish_group <= 0 or selected_fish_group <= 0 or record.is_empty():
		return _failure(&"no_fishing_group")

	_context = {
		"rod": rod,
		"map": map_id,
		"cell": cell,
		"facing": facing,
		"facing_cell": facing_cell,
		"fish_group": fish_group,
		"selected_fish_group": selected_fish_group,
		"movement": movement,
	}
	_pending_encounter = Gen2WorldEncounter.resolve_fishing(
		record, rod, time_of_day, time_groups, random, force_encounter
	)
	_state = STATE_CASTING
	return {
		"ok": true,
		"kind": &"fishing_started",
		"state": _state,
		"rod": rod,
		"rod_label": rod_label(rod),
		"map": map_id,
		"cell": cell,
		"facing": facing,
		"facing_cell": facing_cell,
		"fish_group": fish_group,
		"selected_fish_group": selected_fish_group,
		"movement": movement,
	}


## Advances the source cast pause. A bite remains pending until reel_in().
func advance() -> Dictionary:
	if _state == STATE_CASTING:
		if _pending_encounter.is_empty():
			var no_bite := _result_context()
			_reset()
			no_bite["ok"] = true
			no_bite["kind"] = &"fishing_no_bite"
			no_bite["state"] = STATE_IDLE
			return no_bite
		_state = STATE_BITE
		var bite := _result_context()
		bite["ok"] = true
		bite["kind"] = &"fishing_bite"
		bite["state"] = _state
		bite["encounter"] = _pending_encounter.duplicate(true)
		return bite
	if _state == STATE_BITE:
		var encounter: Dictionary = _pending_encounter.duplicate(true)
		var result := _result_context()
		result["ok"] = true
		result["kind"] = &"battle_requested"
		result["state"] = STATE_IDLE
		result["encounter"] = encounter
		result["values"] = encounter.get("values", {})
		_reset()
		return result
	return _failure(&"fishing_not_started")


func cancel() -> Dictionary:
	if not is_busy():
		return {"ok": true, "kind": &"fishing_cancelled", "state": STATE_IDLE}
	var result := _result_context()
	_reset()
	result["ok"] = true
	result["kind"] = &"fishing_cancelled"
	result["state"] = STATE_IDLE
	return result


func _result_context() -> Dictionary:
	return _context.duplicate(true)


func _reset() -> void:
	_state = STATE_IDLE
	_pending_encounter.clear()
	_context.clear()


static func _failure(reason: StringName) -> Dictionary:
	return {"ok": false, "kind": &"fishing_failed", "reason": reason, "state": STATE_IDLE}
