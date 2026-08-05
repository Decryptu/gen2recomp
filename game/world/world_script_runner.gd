class_name Gen2WorldScriptRunner
extends RefCounted

## Bounded, scene-free execution of the supported overworld script commands.
##
## A runner owns one event invocation. It never opens a ROM and it never
## changes the world state until the invocation reaches END or ENDCALLBACK.
## Text and explicit warps are returned as structured pauses for the screen or
## another caller to acknowledge.

var data: GameData = null
var state: Gen2WorldState = null
var warp_validator: Callable = Callable()

var _request: Dictionary = {}
var _frames: Array = []
var _staged_flags: Dictionary = {}
var _staged_scenes: Dictionary = {}
var _events: Array = []
var _pending: Dictionary = {}
var _last_text: Dictionary = {}
var _last_talked_object_index: int = -1
var _staged_warp: Dictionary = {}
var _script_value: int = 0
var _command_count: int = 0
var _active: bool = false
var _completed: bool = false
var _failure: Dictionary = {}
var _finish_after_pending: bool = false


static func begin(
	game_data: GameData,
	world_state: Gen2WorldState,
	request: Dictionary,
	validator: Callable = Callable(),
) -> Gen2WorldScriptRunner:
	var runner := Gen2WorldScriptRunner.new()
	runner.data = game_data
	runner.state = world_state
	runner.warp_validator = validator
	runner._request = request.duplicate(true)
	runner._last_talked_object_index = int(request.get("object_index", -1))
	var bank: int = int(request.get("bank", 0))
	var address: int = int(request.get("script", request.get("address", 0)))
	if not runner._push_frame(bank, address):
		runner._fail(&"missing_script", {"bank": bank, "address": address})
	else:
		runner._active = true
	return runner


## Advances until a text/button pause, completion or a bounded failure.
func advance(acknowledge: bool = false, choice: int = -1) -> Dictionary:
	if _pending:
		if not acknowledge or (_pending.get("type", &"") == &"choice" and choice < 0):
			return _waiting_result()
		if _pending.get("type", &"") == &"choice":
			_script_value = choice
		var finish_after_pending: bool = _finish_after_pending
		_pending = {}
		_finish_after_pending = false
		if finish_after_pending:
			return _complete()

	if not _active:
		return _failure_result() if not _failure.is_empty() else _complete_result()

	while _active:
		if _command_count >= Gen2WorldScript.MAX_COMMANDS:
			return _fail(&"command_limit", {"limit": Gen2WorldScript.MAX_COMMANDS})
		if _frames.is_empty():
			return _complete()

		var frame: Dictionary = _frames[_frames.size() - 1]
		var command: Dictionary = Gen2WorldScript.command_at(
			frame["data"], int(frame["offset"]), _crystal_commands()
		)
		if not bool(command.get("ok", false)):
			return _fail(StringName(command.get("reason", &"invalid_command")), command)
		frame["offset"] = int(frame["offset"]) + int(command["width"])
		_frames[_frames.size() - 1] = frame
		_command_count += 1

		var outcome: Dictionary = _execute(command, frame)
		if not bool(outcome.get("ok", true)):
			return _fail(StringName(outcome.get("reason", &"script_failed")), outcome)
		if _pending:
			return _waiting_result()
		if _completed:
			return _complete_result()

	return _complete()


func is_waiting() -> bool:
	return not _pending.is_empty()


func is_finished() -> bool:
	return _completed or not _failure.is_empty()


func _execute(command: Dictionary, frame: Dictionary) -> Dictionary:
	var opcode: int = int(command["opcode"])
	var bank: int = int(frame["bank"])
	if opcode == Gen2WorldScript.FARJUMPTEXT:
		if _crystal_commands():
			return _show_text(int(command["bank"]), int(command["address"]), true)
		return _show_text(bank, int(command["address"]), true)
	if opcode == Gen2WorldScript.JUMPTEXT and _crystal_commands():
		return _show_text(bank, int(command["address"]), true)
	if Gen2WorldScript.is_waitbutton(opcode, _crystal_commands()) \
		or Gen2WorldScript.is_promptbutton(opcode, _crystal_commands()):
		return _stage_button(command)
	var source_opcode: int = opcode - 1 if _crystal_commands() and opcode >= 0x56 else opcode
	var object_result: Dictionary = _execute_object_command(source_opcode, command)
	if not object_result.is_empty():
		return object_result
	match opcode:
		Gen2WorldScript.SCALL:
			return {"ok": _push_frame(bank, int(command["address"]))}
		Gen2WorldScript.FARSCALL:
			return {"ok": _push_frame(int(command["bank"]), int(command["address"]))}
		Gen2WorldScript.MEMCALL, Gen2WorldScript.MEMJUMP:
			return {"ok": false, "reason": &"unsupported_runtime_command", "command": command}
		Gen2WorldScript.SJUMP:
			return _replace_frame(bank, int(command["address"]))
		Gen2WorldScript.FARSJUMP:
			return _replace_frame(int(command["bank"]), int(command["address"]))
		Gen2WorldScript.IFEQUAL:
			return _branch(int(_script_value) == int(command["value"]), bank, int(command["address"]))
		Gen2WorldScript.IFNOTEQUAL:
			return _branch(int(_script_value) != int(command["value"]), bank, int(command["address"]))
		Gen2WorldScript.IFFALSE:
			return _branch(_script_value == 0, bank, int(command["address"]))
		Gen2WorldScript.IFTRUE:
			return _branch(_script_value != 0, bank, int(command["address"]))
		Gen2WorldScript.IFGREATER:
			return _branch(_script_value > int(command["value"]), bank, int(command["address"]))
		Gen2WorldScript.IFLESS:
			return _branch(_script_value < int(command["value"]), bank, int(command["address"]))
		Gen2WorldScript.JUMPSTD:
			var jump_standard: Dictionary = _standard_script(int(command["address"]))
			if jump_standard.is_empty():
				return {
					"ok": false,
					"reason": &"missing_standard_script",
					"standard_index": int(command["address"]),
				}
			return _replace_frame(
				int(jump_standard["bank"]), int(jump_standard["address"]),
				jump_standard["data"]
			)
		Gen2WorldScript.CALLSTD:
			var call_standard: Dictionary = _standard_script(int(command["address"]))
			if call_standard.is_empty():
				return {
					"ok": false,
					"reason": &"missing_standard_script",
					"standard_index": int(command["address"]),
				}
			return {
				"ok": _push_frame(
					int(call_standard["bank"]), int(call_standard["address"]),
					call_standard["data"]
				)
			}
		Gen2WorldScript.CHECKMAPSCENE:
			_script_value = _map_scene_value(
				int(command["map_group"]), int(command["map_number"])
			)
		Gen2WorldScript.SETMAPSCENE:
			var target_key: String = Gen2WorldState.map_scene_key(
				int(command["map_group"]), int(command["map_number"])
			)
			_staged_scenes[target_key] = int(command["scene"])
		Gen2WorldScript.CHECKSCENE:
			_script_value = _map_scene_value(
				int(_request.get("map_group", 0)), int(_request.get("map_number", 0))
			)
		Gen2WorldScript.SETSCENE:
			var map_key: String = Gen2WorldState.map_scene_key(
				int(_request.get("map_group", 0)), int(_request.get("map_number", 0))
			)
			_staged_scenes[map_key] = int(command["scene"])
		Gen2WorldScript.CLEAREVENT:
			_staged_flags[int(command["flag"])] = false
		Gen2WorldScript.SETEVENT:
			_staged_flags[int(command["flag"])] = true
		Gen2WorldScript.CHECKEVENT:
			_script_value = 1 if _event_flag_active(int(command["flag"])) else 0
		Gen2WorldScript.WARP:
			return _stage_warp(command)
		Gen2WorldScript.OPENTEXT, Gen2WorldScript.REANCHORMAP, Gen2WorldScript.CLOSETEXT, Gen2WorldScript.WRITEUNUSEDBYTE, Gen2WorldScript.CLOSEWINDOW:
			pass
		Gen2WorldScript.WRITETEXT:
			return _show_text(bank, int(command["address"]), false)
		Gen2WorldScript.FARWRITETEXT:
			return _show_text(int(command["bank"]), int(command["address"]), false)
		Gen2WorldScript.JUMPTEXTFACEPLAYER:
			return _show_text(bank, int(command["address"]), true)
		Gen2WorldScript.REPEATTEXT:
			if int(command["value"]) == 0xFF and int(command["value_2"]) == 0xFF:
				if _last_text.is_empty():
					return {"ok": false, "reason": &"repeat_without_text"}
				return _show_text(int(_last_text["bank"]), int(_last_text["address"]), false)
		Gen2WorldScript.YESORNO:
			return _stage_choice(command, [&"yes", &"no"])
		Gen2WorldScript.LOADMENU:
			return {
				"ok": false,
				"reason": &"unsupported_runtime_command",
				"command": command,
			}
		Gen2WorldScript.GOLD_FACEPLAYER, Gen2WorldScript.FACEPLAYER:
			if Gen2WorldScript.is_faceplayer(opcode, _crystal_commands()):
				pass
		Gen2WorldScript.GOLD_ENDCALLBACK, Gen2WorldScript.ENDCALLBACK, Gen2WorldScript.END:
			if not Gen2WorldScript.is_terminal(opcode, _crystal_commands()):
				return {"ok": false, "reason": &"unsupported_runtime_command", "command": command}
			_frames.pop_back()
			if _frames.is_empty():
				return _complete()
	return {"ok": true}


func _execute_object_command(source_opcode: int, command: Dictionary) -> Dictionary:
	match source_opcode:
		0x67:
			_last_talked_object_index = _object_index_from_id(int(command["object_id"]))
		0x68:
			_emit_object_event(&"object_movement_requested", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"bank": int(_request.get("bank", 0)),
				"address": int(command.get("address", 0)),
			})
		0x69:
			_emit_object_event(&"object_movement_requested", {
				"object_index": _last_talked_object_index,
				"bank": int(_request.get("bank", 0)),
				"address": int(command.get("address", 0)),
			})
		0x6A:
			if _last_talked_object_index >= 0:
				_emit_object_event(&"object_face_player", {
					"object_index": _last_talked_object_index,
				})
		0x6B:
			var first_object: int = _object_index_from_id(int(command.get("object_id", 0)))
			var second_object: int = _object_index_from_id(int(command.get("object_id_2", 0)))
			if first_object >= 0 and second_object >= 0:
				_emit_object_event(&"object_face_object", {
					"object_index": first_object,
					"target_index": second_object,
				})
		0x6D:
			_emit_object_event(&"object_visibility", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"active": false,
			})
		0x6E:
			_emit_object_event(&"object_visibility", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"active": true,
			})
		0x6F, 0x76:
			_emit_object_event(&"object_follow", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"target_index": _object_index_from_id(int(command.get("object_id_2", 0))),
				"exact": source_opcode == 0x6F,
			})
		0x70:
			_emit_object_event(&"object_stop_follow", {})
		0x71:
			_emit_object_event(&"object_position", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"cell": Vector2i(int(command.get("x", 0)), int(command.get("y", 0))),
			})
		0x72:
			_emit_object_event(&"object_write_position", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
			})
		0x75:
			_emit_object_event(&"object_facing", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"facing": int(command.get("facing", Gen2WorldSprite.FACING_DOWN)),
			})
		_:
			return {}
	return {"ok": true}


func _object_index_from_id(object_id: int) -> int:
	if object_id == 0xFF:
		return _last_talked_object_index
	if object_id <= 0:
		return -1
	# object_const_def starts map-object constants at 2. The cache omits the
	# player object, so source id 2 is array index zero.
	return object_id - 2


func _emit_object_event(event_type: StringName, values: Dictionary) -> void:
	var event: Dictionary = {
		"type": event_type,
		"map_group": int(_request.get("map_group", 0)),
		"map_number": int(_request.get("map_number", 0)),
	}
	for key: Variant in values:
		event[key] = values[key]
	_events.append(event)


func _stage_button(command: Dictionary) -> Dictionary:
	_pending = {
		"type": &"button",
		"command": command.get("name", &"button"),
		"source": _request.duplicate(true),
	}
	return {"ok": true}


func _stage_choice(command: Dictionary, choices: Array) -> Dictionary:
	_pending = {
		"type": &"choice",
		"command": command.get("name", &"choice"),
		"choices": choices.duplicate(true),
		"source": _request.duplicate(true),
	}
	return {"ok": true}


func _show_text(bank: int, address: int, finish_after: bool) -> Dictionary:
	var raw: PackedByteArray = data.world_text(bank, address) if data != null else PackedByteArray()
	var decoded: Dictionary = Gen2WorldScript.decode_text(raw)
	if not bool(decoded.get("ok", false)):
		return {
			"ok": false,
			"reason": decoded.get("reason", &"invalid_text"),
			"bank": bank,
			"address": address,
		}
	_last_text = {"bank": bank, "address": address}
	_pending = {
		"type": &"text",
		"text": String(decoded.get("text", "")),
		"bank": bank,
		"address": address,
		"source": _request.duplicate(true),
	}
	_finish_after_pending = finish_after
	return {"ok": true}


func _stage_warp(command: Dictionary) -> Dictionary:
	var request: Dictionary = {
		"map_group": int(command["map_group"]),
		"map_number": int(command["map_number"]),
		"x": int(command["x"]),
		"y": int(command["y"]),
	}
	if warp_validator.is_valid():
		var validation: Variant = warp_validator.call(
			request["map_group"], request["map_number"], Vector2i(request["x"], request["y"])
		)
		if not validation is Dictionary or not bool((validation as Dictionary).get("ok", false)):
			return {
				"ok": false,
				"reason": &"invalid_warp",
				"warp": request,
				"validation": validation,
			}
	_staged_warp = request
	_events.append({"type": &"warp_requested", "warp": request.duplicate(true)})
	return {"ok": true}


func _push_frame(
	bank: int, address: int, raw_override: PackedByteArray = PackedByteArray()
) -> bool:
	if data == null or address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
		return false
	if _frames.size() >= Gen2WorldScript.MAX_CALL_DEPTH:
		_fail(&"call_depth_limit", {"limit": Gen2WorldScript.MAX_CALL_DEPTH})
		return false
	var raw: PackedByteArray = raw_override if not raw_override.is_empty() else data.world_script(bank, address)
	if raw.is_empty():
		return false
	_frames.append({"bank": bank, "address": address, "data": raw, "offset": 0})
	return true


func _standard_script(index: int) -> Dictionary:
	if data == null or index < 0:
		return {}
	var entry: Dictionary = data.world_standard_script(index)
	var raw: Variant = entry.get("data", PackedByteArray())
	if entry.is_empty() or not raw is PackedByteArray or (raw as PackedByteArray).is_empty():
		return {}
	return entry


func _branch(taken: bool, bank: int, address: int) -> Dictionary:
	if not taken:
		return {"ok": true}
	return _replace_frame(bank, address)


func _event_flag_active(flag: int) -> bool:
	if _staged_flags.has(flag):
		return bool(_staged_flags[flag])
	return state != null and state.is_event_flag_active(flag)


func _map_scene_value(map_group: int, map_number: int) -> int:
	var key: String = Gen2WorldState.map_scene_key(map_group, map_number)
	if _staged_scenes.has(key):
		return int(_staged_scenes[key])
	if state != null and state.map_scenes().has(key):
		return state.map_scene(map_group, map_number)
	return 0xFF


func _replace_frame(
	bank: int, address: int, raw_override: PackedByteArray = PackedByteArray()
) -> Dictionary:
	if data == null or address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
		return {"ok": false, "reason": &"missing_jump_target", "bank": bank, "address": address}
	var raw: PackedByteArray = raw_override if not raw_override.is_empty() else data.world_script(bank, address)
	if raw.is_empty():
		return {"ok": false, "reason": &"missing_jump_target", "bank": bank, "address": address}
	_frames[_frames.size() - 1] = {
		"bank": bank, "address": address, "data": raw, "offset": 0,
	}
	return {"ok": true}


func _complete() -> Dictionary:
	if _completed:
		return _complete_result()
	if state == null:
		return _fail(&"missing_world_state", {})
	var applied: Dictionary = state.apply_changes(_staged_flags, _staged_scenes)
	if not bool(applied.get("ok", false)):
		return _fail(StringName(applied.get("reason", &"state_transaction_failed")), applied)
	_completed = true
	_active = false
	if not _staged_flags.is_empty() or not _staged_scenes.is_empty():
		_events.append({
			"type": &"state_changed",
			"flags": _staged_flags.duplicate(true),
			"scenes": _staged_scenes.duplicate(true),
		})
	return _complete_result()


func _complete_result() -> Dictionary:
	return {
		"ok": true,
		"status": &"complete",
		"events": _events.duplicate(true),
		"source": _request.duplicate(true),
		"warp": _staged_warp.duplicate(true),
		"commands": _command_count,
	}


func _waiting_result() -> Dictionary:
	return {
		"ok": true,
		"status": &"waiting",
		"event": _pending.duplicate(true),
		"events": _events.duplicate(true),
		"source": _request.duplicate(true),
		"commands": _command_count,
	}


func _fail(reason: StringName, details: Dictionary) -> Dictionary:
	_active = false
	_failure = {"reason": reason, "details": details.duplicate(true)}
	return _failure_result()


func _failure_result() -> Dictionary:
	return {
		"ok": false,
		"status": &"failed",
		"reason": _failure.get("reason", &"script_failed"),
		"details": _failure.get("details", {}),
		"events": _events.duplicate(true),
		"source": _request.duplicate(true),
		"commands": _command_count,
	}


func _crystal_commands() -> bool:
	if data == null:
		return true
	return data.id != &"gold" and data.id != &"silver"
