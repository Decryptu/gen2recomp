class_name Gen2WorldState
extends RefCounted

## Mutable state shared by the scene-free overworld systems.
##
## Cartridge-derived map records remain immutable in GameData. This record is
## the runtime boundary for event flags and can later be serialized by the
## save model without making Gen2WorldAPI own a save file.

signal changed

var _event_flags: Dictionary = {}
var _map_scenes: Dictionary = {}


func _init(event_flags: Dictionary = {}, map_scenes: Dictionary = {}) -> void:
	for flag: Variant in event_flags:
		if int(flag) > 0 and bool(event_flags[flag]):
			_event_flags[int(flag)] = true
	for map_key: Variant in map_scenes:
		var scene: int = int(map_scenes[map_key])
		if scene >= 0:
			_map_scenes[String(map_key)] = scene


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


static func map_scene_key(map_group: int, map_number: int) -> String:
	return "%d:%d" % [map_group, map_number]


func map_scene(map_group: int, map_number: int) -> int:
	return int(_map_scenes.get(map_scene_key(map_group, map_number), 0))


func map_scenes() -> Dictionary:
	return _map_scenes.duplicate()


## Applies a script's staged state as one transaction. Validation happens before
## either dictionary is replaced, so a failed script cannot leave half a flag
## transition behind.
func apply_changes(flag_changes: Dictionary, scene_changes: Dictionary) -> Dictionary:
	for raw_flag: Variant in flag_changes:
		if int(raw_flag) <= 0:
			return {"ok": false, "reason": &"invalid_event_flag"}
	for raw_map: Variant in scene_changes:
		if String(raw_map).is_empty() or int(scene_changes[raw_map]) < 0:
			return {"ok": false, "reason": &"invalid_scene"}

	var next_flags: Dictionary = _event_flags.duplicate()
	for raw_flag: Variant in flag_changes:
		var flag: int = int(raw_flag)
		if bool(flag_changes[raw_flag]):
			next_flags[flag] = true
		else:
			next_flags.erase(flag)
	var next_scenes: Dictionary = _map_scenes.duplicate()
	for raw_map: Variant in scene_changes:
		next_scenes[String(raw_map)] = int(scene_changes[raw_map])

	var did_change: bool = next_flags != _event_flags or next_scenes != _map_scenes
	_event_flags = next_flags
	_map_scenes = next_scenes
	if did_change:
		changed.emit()
	return {"ok": true, "changed": did_change}
