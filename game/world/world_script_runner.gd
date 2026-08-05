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
var _staged_items: Dictionary = {}
var _staged_money: Dictionary = {}
var _staged_coins: int = -1
var _staged_phone_contacts: Dictionary = {}
var _staged_just_battled: bool = false
var _has_staged_just_battled: bool = false
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
var _loaded_menu: Dictionary = {}
var _battle_setup: Dictionary = {}


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
		var pending_request: Dictionary = _pending.get("request", {})
		if _pending.get("type", &"") == &"runtime_request" \
			and StringName(pending_request.get("kind", &"")) == &"battle_requested":
			return _waiting_result()
		if not acknowledge or (_pending.get("type", &"") == &"choice" and choice < 0):
			return _waiting_result()
		var pending_type: StringName = StringName(_pending.get("type", &""))
		if pending_type in [&"choice", &"menu"]:
			if pending_type == &"menu" and choice < 0:
				choice = 0
			_script_value = choice
		if pending_type == &"choice" and _pending.has("contact"):
			var contact: int = int(_pending.get("contact", -1))
			if choice == 0 and contact >= 0:
				_staged_phone_contacts[contact] = true
			_emit_runtime_event(&"phone_number_result", {
				"contact": contact, "accepted": choice == 0,
			})
		if pending_type == &"battle":
			_stage_just_battled(true)
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


## Completes a host-owned runtime request without treating a button press as its
## result. Battle loss is deliberately a structured failure until blackout and
## save-backed recovery have a canonical host model.
func complete_runtime_request(result: Dictionary) -> Dictionary:
	if _pending.is_empty() or _pending.get("type", &"") != &"runtime_request":
		return {
			"ok": false, "status": &"failed", "reason": &"runtime_request_not_pending",
			"details": result.duplicate(true),
		}
	var request: Dictionary = _pending.get("request", {})
	var kind: StringName = StringName(request.get("kind", &""))
	if kind != &"battle_requested":
		return {
			"ok": false, "status": &"failed", "reason": &"runtime_request_kind_mismatch",
			"details": {"kind": kind},
		}
	if not bool(result.get("ok", false)):
		return _fail(
			StringName(result.get("reason", &"runtime_request_failed")), result
		)
	var outcome: StringName = StringName(result.get("outcome", &""))
	if String(outcome).is_empty():
		return _fail(&"invalid_battle_outcome", result)
	if outcome != Gen2WorldBattleAdapter.OUTCOME_WON:
		return _fail(StringName("battle_%s" % outcome), result)

	_stage_just_battled(true)
	_script_value = 1
	_events.append({
		"type": &"battle_completed",
		"outcome": outcome,
		"request": request.duplicate(true),
		"result": result.duplicate(true),
	})
	_pending = {}
	return advance()


func pending_runtime_request() -> Dictionary:
	if _pending.get("type", &"") != &"runtime_request":
		return {}
	return (_pending.get("request", {}) as Dictionary).duplicate(true)


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
	var later_result: Dictionary = _execute_later_command(source_opcode, command)
	if not later_result.is_empty():
		return later_result
	if Gen2WorldScript.is_terminal(opcode, _crystal_commands()):
		_frames.pop_back()
		if _frames.is_empty():
			return _complete()
		return {"ok": true}
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
		Gen2WorldScript.SETVAL:
			_script_value = int(command["value"])
		Gen2WorldScript.ADDVAL:
			_script_value += int(command["value"])
		Gen2WorldScript.RANDOM:
			var maximum: int = int(command["value"])
			_script_value = randi_range(0, maximum - 1) if maximum > 0 else 0
		Gen2WorldScript.GIVEITEM:
			return _stage_item_delta(int(command["value"]), int(command["value_2"]))
		Gen2WorldScript.TAKEITEM:
			return _stage_item_delta(int(command["value"]), -int(command["value_2"]))
		Gen2WorldScript.CHECKITEM:
			_script_value = 1 if _item_quantity(int(command["value"])) > 0 else 0
		Gen2WorldScript.GIVEMONEY, Gen2WorldScript.TAKEMONEY:
			return _stage_money_delta(
				int(command["account"]), _decode_bcd(command["amount_bytes"]),
				opcode == Gen2WorldScript.GIVEMONEY
			)
		Gen2WorldScript.CHECKMONEY:
			_script_value = _compare_amount(
				_money_balance(int(command["account"])),
				_decode_bcd(command["amount_bytes"])
			)
		Gen2WorldScript.GIVECOINS, Gen2WorldScript.TAKECOINS:
			return _stage_coins_delta(
				int(command["value"]), opcode == Gen2WorldScript.GIVECOINS
			)
		Gen2WorldScript.CHECKCOINS:
			_script_value = _compare_amount(_coins_value(), int(command["value"]))
		Gen2WorldScript.GETMONEY:
			_emit_runtime_event(&"text_value_requested", {
				"value_kind": &"money", "account": int(command["account"]),
				"value": _money_balance(int(command["account"])),
				"string_buffer": int(command["string_buffer"]),
			})
		Gen2WorldScript.GETCOINS:
			_emit_runtime_event(&"text_value_requested", {
				"value_kind": &"coins", "value": _coins_value(),
				"string_buffer": int(command["string_buffer"]),
			})
		Gen2WorldScript.GETITEMNAME, Gen2WorldScript.GETMONNAME, Gen2WorldScript.GETTRAINERNAME, Gen2WorldScript.GETSTRING:
			_emit_runtime_event(&"text_buffer_requested", command)
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
			_loaded_menu = {
				"bank": int(_request.get("bank", 0)),
				"address": int(command["address"]),
			}
			_emit_runtime_event(&"menu_loaded", _loaded_menu)
		Gen2WorldScript.GIVEPOKE, Gen2WorldScript.GIVEEGG:
			return _stage_runtime_request(&"pokemon_requested", command)
		Gen2WorldScript.GIVEPOKEMAIL, Gen2WorldScript.CHECKPOKEMAIL:
			return _stage_runtime_request(&"mail_requested", command)
		Gen2WorldScript.GOLD_FACEPLAYER, Gen2WorldScript.FACEPLAYER:
			if Gen2WorldScript.is_faceplayer(opcode, _crystal_commands()):
				pass
	var handled_base: Array = [
		Gen2WorldScript.CHECKMAPSCENE, Gen2WorldScript.SETMAPSCENE,
		Gen2WorldScript.CHECKSCENE, Gen2WorldScript.SETSCENE,
		Gen2WorldScript.SETVAL, Gen2WorldScript.ADDVAL, Gen2WorldScript.RANDOM,
		Gen2WorldScript.CHECKEVENT, Gen2WorldScript.CLEAREVENT, Gen2WorldScript.SETEVENT,
		Gen2WorldScript.GOLD_FACEPLAYER, Gen2WorldScript.FACEPLAYER,
		Gen2WorldScript.OPENTEXT, Gen2WorldScript.REANCHORMAP,
		Gen2WorldScript.CLOSETEXT, Gen2WorldScript.WRITEUNUSEDBYTE,
		Gen2WorldScript.CLOSEWINDOW,
		Gen2WorldScript.LOADMENU,
		Gen2WorldScript.GETMONEY, Gen2WorldScript.GETCOINS, Gen2WorldScript.GETNUM,
		Gen2WorldScript.GETMONNAME, Gen2WorldScript.GETITEMNAME,
		Gen2WorldScript.GETCURLANDMARKNAME, Gen2WorldScript.GETTRAINERNAME,
		Gen2WorldScript.GETSTRING,
	]
	if opcode in handled_base:
		return {"ok": true}
	return {
		"ok": false,
		"reason": &"unsupported_runtime_command",
		"command": command,
	}


func _execute_later_command(source_opcode: int, command: Dictionary) -> Dictionary:
	match source_opcode:
		0x57, 0x58:
			return _stage_menu(source_opcode == 0x57, command)
		0x5C:
			_battle_setup = {
				"kind": &"wild", "pokemon": int(command.get("pokemon", 0)),
				"level": int(command.get("level", 0)),
			}
			_emit_runtime_event(&"battle_setup_changed", _battle_setup)
		0x5D:
			_battle_setup = {
				"kind": &"trainer", "trainer_group": int(command.get("trainer_group", 0)),
				"trainer_id": int(command.get("trainer_id", 0)),
			}
			_emit_runtime_event(&"battle_setup_changed", _battle_setup)
		0x5E:
			if _battle_setup.is_empty():
				return {
					"ok": false, "reason": &"battle_setup_missing", "command": command,
				}
			return _stage_runtime_request(&"battle_requested", _battle_setup)
		0x5F:
			_emit_runtime_event(&"battle_map_reload_requested", {})
		0x60:
			return _stage_runtime_request(&"catch_tutorial_requested", {
				"value": int(command.get("value", 0)),
			})
		0x61:
			return _stage_runtime_request(&"trainer_text_requested", {
				"text_id": int(command.get("value", 0)),
				"setup": _battle_setup.duplicate(true),
			})
		0x62:
			var trainer_event: Dictionary = _request.get("event", {})
			var trainer_flag: int = int(trainer_event.get("event_flag", 0))
			_script_value = 1 if _event_flag_active(trainer_flag) else 0
			_emit_runtime_event(&"trainer_flag_action", {
				"action": int(command.get("value", 0)), "event_flag": trainer_flag,
				"script_value": _script_value,
			})
		0x63:
			_battle_setup["win_address"] = int(command.get("win_address", 0))
			_battle_setup["loss_address"] = int(command.get("loss_address", 0))
		0x64:
			_emit_runtime_event(&"trainer_talk_after_requested", {})
		0x65:
			if _has_staged_just_battled or (state != null and state.just_battled()):
				_frames.clear()
		0x66:
			_script_value = 1 if _has_staged_just_battled or (
				state != null and state.just_battled()
			) else 0
		0x7E:
			return _stage_audio_request(&"music", {
				"address": int(command.get("address", 0)),
			})
		0x7F:
			return _stage_audio_request(&"encounter_music", {})
		0x80:
			return _stage_audio_request(&"music_fadeout", {
				"music": int(command.get("value", 0)),
				"fade_time": int(command.get("value_2", 0)),
			})
		0x81:
			return _stage_audio_request(&"map_music", {})
		0x82:
			_emit_runtime_event(&"map_music_restart_disabled", {})
		0x83:
			return _stage_audio_request(&"cry", {"cry_id": int(command.get("value", 0))})
		0x84:
			return _stage_audio_request(&"sound", {"address": int(command.get("value", 0))})
		0x85:
			_emit_runtime_event(&"sound_wait_requested", {})
		0x86:
			return _stage_audio_request(&"warp_sound", {})
		0x87:
			return _stage_audio_request(&"special_sound", {})
		0x8A, 0x8B:
			_emit_runtime_event(&"script_timing_requested", {
				"kind": &"pause" if source_opcode == 0x8A else &"deactivate_facing",
				"value": int(command.get("value", 0)),
			})
		0x93:
			return _stage_runtime_request(&"mart_requested", {
				"dialog": int(command.get("value", 0)),
				"address": int(command.get("address", 0)),
			})
		0x94:
			return _stage_runtime_request(&"elevator_requested", {
				"address": int(command.get("address", 0)),
			})
		0x95:
			return _stage_runtime_request(&"trade_requested", {
				"trade_id": int(command.get("value", 0)),
			})
		0x96:
			return _stage_phone_choice(int(command.get("value", 0)))
		0x97:
			return _stage_runtime_request(&"phone_call_requested", {
				"address": int(command.get("address", 0)),
			})
		0x98:
			_emit_runtime_event(&"phone_hangup", {})
		0x99:
			return _stage_runtime_request(&"decoration_requested", {
				"value": int(command.get("value", 0)),
			})
		0x9A:
			return _stage_runtime_request(&"fruit_tree_requested", {
				"tree_id": int(command.get("value", 0)),
			})
		0x9B:
			return _stage_runtime_request(&"special_phone_call_requested", {
				"address": int(command.get("address", 0)),
			})
		0x9C:
			_script_value = 1 if _request.get("special_phone_call", false) else 0
		0x9D:
			return _stage_item_delta(int(command.get("item", 0)), int(command.get("quantity", 1)))
		0x9E:
			return _stage_runtime_request(&"swarm_requested", {
				"map_group": int(command.get("map_group", 0)),
				"map_number": int(command.get("map_number", 0)),
			})
		0xA1:
			return _stage_warp_facing_request(command)
	var handled_sources: Array = [
		0x57, 0x58, 0x5C, 0x5D, 0x5F, 0x60, 0x61, 0x62, 0x63, 0x64,
		0x65, 0x66, 0x7F, 0x81, 0x82, 0x85, 0x8A, 0x8B, 0x98,
	]
	if source_opcode in handled_sources:
		return {"ok": true}
	return {}


func _execute_object_command(source_opcode: int, command: Dictionary) -> Dictionary:
	match source_opcode:
		0x67:
			_last_talked_object_index = _object_index_from_id(int(command["object_id"]))
		0x68:
			var movement_event_type: StringName = &"player_movement_requested" \
				if int(command.get("object_id", 0)) == 0 else &"object_movement_requested"
			var movement_values: Dictionary = {
				"bank": int(_request.get("bank", 0)),
				"address": int(command.get("address", 0)),
			}
			if movement_event_type == &"object_movement_requested":
				movement_values["object_index"] = _object_index_from_id(
					int(command.get("object_id", 0))
				)
			_emit_object_event(movement_event_type, movement_values)
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


func _stage_item_delta(item: int, delta: int) -> Dictionary:
	if item <= 0 or delta == 0:
		_script_value = 1 if delta >= 0 else 0
		return {"ok": true}
	var current: int = _item_quantity(item)
	var next: int = current + delta
	if next < 0:
		_script_value = 0
		_emit_runtime_event(&"item_change_rejected", {
			"item": item, "quantity": abs(delta), "available": current,
		})
		return {"ok": true}
	_staged_items[item] = next
	_script_value = 1
	_emit_runtime_event(&"item_changed", {
		"item": item, "quantity": abs(delta), "total": next,
		"direction": &"give" if delta > 0 else &"take",
	})
	return {"ok": true}


func _stage_money_delta(account: int, amount: int, give: bool) -> Dictionary:
	if account < 0 or amount < 0:
		return {"ok": false, "reason": &"invalid_money_command"}
	var current: int = _money_balance(account)
	var next: int = current + amount if give else current - amount
	if next < 0:
		_script_value = 0
		_emit_runtime_event(&"money_change_rejected", {
			"account": account, "amount": amount, "available": current,
		})
		return {"ok": true}
	_staged_money[account] = next
	_script_value = 1
	_emit_runtime_event(&"money_changed", {
		"account": account, "amount": amount, "balance": next,
		"direction": &"give" if give else &"take",
	})
	return {"ok": true}


func _stage_coins_delta(amount: int, give: bool) -> Dictionary:
	if amount < 0:
		return {"ok": false, "reason": &"invalid_coins_command"}
	var current: int = _coins_value()
	var next: int = current + amount if give else current - amount
	if next < 0:
		_script_value = 0
		_emit_runtime_event(&"coins_change_rejected", {
			"amount": amount, "available": current,
		})
		return {"ok": true}
	_staged_coins = next
	_script_value = 1
	_emit_runtime_event(&"coins_changed", {
		"amount": amount, "balance": next,
		"direction": &"give" if give else &"take",
	})
	return {"ok": true}


func _stage_menu(two_dimensional: bool, command: Dictionary) -> Dictionary:
	if _loaded_menu.is_empty():
		return {"ok": false, "reason": &"menu_header_missing", "command": command}
	_pending = {
		"type": &"menu",
		"menu_kind": &"2d" if two_dimensional else &"vertical",
		"header": _loaded_menu.duplicate(true),
		"options": [],
		"source": _request.duplicate(true),
	}
	return {"ok": true}


func _stage_audio_request(kind: StringName, values: Dictionary) -> Dictionary:
	var event: Dictionary = {"kind": kind}
	for key: Variant in values:
		event[key] = values[key]
	return _stage_runtime_request(&"audio_requested", event)


func _stage_phone_choice(contact: int) -> Dictionary:
	_pending = {
		"type": &"choice",
		"command": &"askforphonenumber",
		"choices": [&"accept", &"refuse"],
		"contact": contact,
		"source": _request.duplicate(true),
	}
	return {"ok": true}


func _stage_runtime_request(kind: StringName, values: Dictionary) -> Dictionary:
	_pending = {
		"type": &"runtime_request",
		"request": {"kind": kind, "values": values.duplicate(true)},
		"source": _request.duplicate(true),
	}
	return {"ok": true}


func _stage_warp_facing_request(command: Dictionary) -> Dictionary:
	var warp: Dictionary = {
		"facing": int(command.get("facing", Gen2WorldSprite.FACING_DOWN)),
		"map_group": int(command.get("map_group", 0)),
		"map_number": int(command.get("map_number", 0)),
		"x": int(command.get("x", 0)), "y": int(command.get("y", 0)),
	}
	_events.append({"type": &"player_facing_requested", "facing": warp["facing"]})
	return _stage_warp(command)


func _stage_just_battled(value: bool) -> void:
	_staged_just_battled = value
	_has_staged_just_battled = true


func _item_quantity(item: int) -> int:
	if _staged_items.has(item):
		return int(_staged_items[item])
	return state.item_quantity(item) if state != null else 0


func _money_balance(account: int) -> int:
	if _staged_money.has(account):
		return int(_staged_money[account])
	return state.money(account) if state != null else 0


func _coins_value() -> int:
	return _staged_coins if _staged_coins >= 0 else (state.coins() if state != null else 0)


func _compare_amount(current: int, requested: int) -> int:
	return 0 if current < requested else (1 if current == requested else 2)


func _decode_bcd(bytes: PackedByteArray) -> int:
	var value: int = 0
	for byte: int in bytes:
		value = value * 100 + ((byte >> 4) * 10) + (byte & 0x0F)
	return value


func _emit_runtime_event(kind: StringName, values: Dictionary) -> void:
	var event: Dictionary = {
		"type": kind,
		"map_group": int(_request.get("map_group", 0)),
		"map_number": int(_request.get("map_number", 0)),
	}
	for key: Variant in values:
		event[key] = values[key]
	_events.append(event)


func _object_index_from_id(object_id: int) -> int:
	if object_id in [0xFE, 0xFF]:
		return _last_talked_object_index
	if object_id == 0:
		return -1
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
	var runtime_changes: Dictionary = {}
	if not _staged_items.is_empty():
		runtime_changes["items"] = _staged_items.duplicate()
	if not _staged_money.is_empty():
		runtime_changes["money"] = _staged_money.duplicate()
	if _staged_coins >= 0:
		runtime_changes["coins"] = _staged_coins
	if not _staged_phone_contacts.is_empty():
		runtime_changes["phone_contacts"] = _staged_phone_contacts.duplicate()
	if _has_staged_just_battled:
		runtime_changes["just_battled"] = _staged_just_battled
	var applied: Dictionary = state.apply_changes(
		_staged_flags, _staged_scenes, runtime_changes
	)
	if not bool(applied.get("ok", false)):
		return _fail(StringName(applied.get("reason", &"state_transaction_failed")), applied)
	_completed = true
	_active = false
	if not _staged_flags.is_empty() or not _staged_scenes.is_empty() \
		or not runtime_changes.is_empty():
		_events.append({
			"type": &"state_changed",
			"flags": _staged_flags.duplicate(true),
			"scenes": _staged_scenes.duplicate(true),
			"runtime": runtime_changes.duplicate(true),
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
