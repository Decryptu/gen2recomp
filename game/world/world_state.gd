class_name Gen2WorldState
extends RefCounted

## Mutable state shared by the scene-free overworld systems.
##
## Cartridge-derived map records remain immutable in GameData. This record is
## the runtime boundary for event flags and can later be serialized by the
## save model without making Gen2WorldAPI own a save file.

signal changed

var _event_flags: Dictionary = {}


func _init(event_flags: Dictionary = {}) -> void:
	for flag: Variant in event_flags:
		if int(flag) > 0 and bool(event_flags[flag]):
			_event_flags[int(flag)] = true


func is_event_flag_active(flag: int) -> bool:
	return flag > 0 and bool(_event_flags.get(flag, false))


func set_event_flag(flag: int, active: bool = true) -> void:
	if flag <= 0:
		return
	var was_active: bool = is_event_flag_active(flag)
	if was_active == active:
		return
	if active:
		_event_flags[flag] = true
	else:
		_event_flags.erase(flag)
	changed.emit()


func clear_event_flag(flag: int) -> void:
	set_event_flag(flag, false)


func event_flags() -> Dictionary:
	return _event_flags.duplicate()
