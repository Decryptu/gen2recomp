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
var _staged_engine_flags: Dictionary = {}
var _staged_scenes: Dictionary = {}
var _staged_day_of_week: int = -1
var _staged_dst_enabled: bool = false
var _has_staged_dst: bool = false
var _staged_items: Dictionary = {}
var _staged_money: Dictionary = {}
var _staged_coins: int = -1
var _staged_phone_contacts: Dictionary = {}
var _staged_script_memory: Dictionary = {}
var _staged_just_battled: bool = false
var _has_staged_just_battled: bool = false
var _staged_swarm: Dictionary = {}
var _has_staged_swarm: bool = false
var _has_staged_special_phone_call: bool = false
var _staged_special_phone_call: int = 0
var _reset_phone_receive_timer: bool = false
var _events: Array = []
var _pending: Dictionary = {}
var _last_text: Dictionary = {}
var _last_talked_object_index: int = -1
var _last_item: int = 0
var _staged_warp: Dictionary = {}
var _script_value: int = 0
var _command_count: int = 0
var _active: bool = false
var _completed: bool = false
var _failure: Dictionary = {}
var _finish_after_pending: bool = false
var _loaded_menu: Dictionary = {}
var _loaded_emote: int = -1
var _trainer_intro_approach_pending: bool = false
var _battle_setup: Dictionary = {}
var _loaded_battle_type: int = -1
var _phone_context: Dictionary = {}
var _phone_started: bool = false
var _text_buffers: Dictionary = {}
var _rival_name: String = "???"
## Everything this invocation rolls: the source RANDOM command and the phone
## routines that pick a caller line or an unseen species. Injected like the rest
## of the project's randomness, so a caller can reproduce a branch; a runner
## started without one randomizes its own rather than reaching for the engine's
## global generator, which no seed can reach.
var _random := RandomNumberGenerator.new()

const PHONE_CONTACT_GOT: int = 0
const PHONE_CONTACTS_FULL: int = 1
const PHONE_CONTACT_REFUSED: int = 2
const SPECIAL_ACTIVATE_FISHING_SWARM: int = 72
const SPECIAL_TOGGLE_MAPTILE_DECORATIONS: int = 73
const SPECIAL_TOGGLE_DECORATIONS_VISIBILITY: int = 74
const SPECIAL_POKEMON_CENTER_PC: int = 28
const SPECIAL_PLAYERS_HOUSE_PC: int = 29
const SPECIAL_SET_DAY_OF_WEEK: int = 37
const SPECIAL_PLAY_MAP_MUSIC: int = 60
const SPECIAL_RESTART_MAP_MUSIC: int = 61
const SPECIAL_HEAL_MACHINE_ANIM: int = 62
const SPECIAL_CHECK_POKERUS: int = 78
const SPECIAL_RANDOM_UNSEEN_WILD_MON: int = 91
const SPECIAL_RANDOM_PHONE_WILD_MON: int = 92
const SPECIAL_RANDOM_PHONE_MON: int = 93
const SPECIAL_INITIAL_SET_DST_FLAG: int = 166
const SPECIAL_INITIAL_CLEAR_DST_FLAG: int = 167
const SPECIAL_FADE_OUT_MUSIC: int = 106
const SPECIAL_INIT_ROAM_MONS: int = 105
## wBattleResult, which startbattle copies into wScriptVar
## (constants/battle_constants.asm).
const BATTLE_RESULT_WIN: int = 0
const BATTLE_RESULT_LOSE: int = 1
const BATTLE_RESULT_DRAW: int = 2
const TEXT_STRING_BUFFER: int = 0x14
const WEEKDAY_NAMES: Array[StringName] = [
	&"Sunday", &"Monday", &"Tuesday", &"Wednesday", &"Thursday", &"Friday", &"Saturday",
]

## Crystal event flags used by the player's room decoration callbacks. The
## importer keeps raw cartridge flag numbers, so these values match the
## source event flag table rather than a project-local enum.
const EVENT_TEMPORARY_UNTIL_MAP_RELOAD_8: int = 7
const EVENT_PLAYERS_ROOM_POSTER: int = 716
const EVENT_PLAYERS_HOUSE_2F_CONSOLE: int = 1857
const EVENT_PLAYERS_HOUSE_2F_DOLL_1: int = 1858
const EVENT_PLAYERS_HOUSE_2F_DOLL_2: int = 1859
const EVENT_PLAYERS_HOUSE_2F_BIG_DOLL: int = 1860
const VARIABLE_SPRITE_BASE: int = 0xF0


static func begin(
	game_data: GameData,
	world_state: Gen2WorldState,
	request: Dictionary,
	validator: Callable = Callable(),
	random: RandomNumberGenerator = null,
) -> Gen2WorldScriptRunner:
	var runner := Gen2WorldScriptRunner.new()
	runner.data = game_data
	runner.state = world_state
	runner.warp_validator = validator
	runner._request = request.duplicate(true)
	runner._phone_context = request.get("phone", {}).duplicate(true)
	if random != null:
		runner._random = random
	else:
		runner._random.randomize()
	runner._reset_phone_receive_timer = bool(request.get("reset_receive_timer", false))
	runner._last_talked_object_index = int(request.get("object_index", -1))
	runner._last_item = int(request.get("item", 0))
	var bank: int = int(request.get("bank", 0))
	var address: int = int(request.get("script", request.get("address", 0)))
	var trainer_phase: StringName = StringName(request.get("trainer_phase", &""))
	var trainer: Variant = request.get("trainer", {})
	var started: bool = false
	if trainer_phase == &"initial" and trainer is Dictionary:
		started = runner._push_frame(
			bank, address, runner._trainer_intro_script(trainer as Dictionary)
		)
		## Only SeenByTrainerScript shows the shock emote and walks the trainer
		## over; TalkToTrainerScript is faceplayer, the flag check and
		## encountermusic, then the same StartBattleWithMapTrainerScript
		## (engine/events/trainer_scripts.asm). A sight request is the one that
		## carries the direction the trainer saw along, so it is the one that
		## approaches.
		runner._trainer_intro_approach_pending = request.get("direction", Vector2i.ZERO) \
			in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	else:
		started = runner._push_frame(bank, address)
	if not started:
		runner._fail(&"missing_script", {"bank": bank, "address": address})
	else:
		runner._active = true
	return runner


## Advances until a text/button pause, completion or a bounded failure.
func advance(acknowledge: bool = false, choice: int = -1) -> Dictionary:
	if not _phone_context.is_empty() and not _phone_started:
		_phone_started = true
		_emit_runtime_event(&"phone_call_started", _phone_context)
	if _pending:
		var pending_request: Dictionary = _pending.get("request", {})
		if _pending.get("type", &"") == &"runtime_request" \
			and StringName(pending_request.get("kind", &"")) == &"battle_requested":
			return _waiting_result()
		if not acknowledge:
			return _waiting_result()
		var pending_type: StringName = StringName(_pending.get("type", &""))
		if pending_type == &"menu" and _pending.get("special", &"") == &"set_day_of_week":
			if choice < 0:
				return _waiting_result()
			var selected_day: int = posmod(choice, WEEKDAY_NAMES.size())
			_pending = {
				"type": &"text",
				"text": "%s,\nis it?" % String(WEEKDAY_NAMES[selected_day]),
				"special": &"set_day_of_week_confirmation",
				"day": selected_day,
				"source": _request.duplicate(true),
			}
			return _waiting_result()
		if pending_type == &"text" and _pending.get("special", &"") == &"set_day_of_week_confirmation":
			var confirmation_day: int = int(_pending.get("day", 0))
			_stage_day_of_week_confirmation(confirmation_day)
			return _waiting_result()
		if pending_type == &"choice" and _pending.get("special", &"") == &"set_day_of_week_confirmation":
			if choice < 0:
				return _waiting_result()
			var confirmed_day: int = int(_pending.get("day", 0))
			_pending = {}
			if choice == 0:
				_staged_day_of_week = confirmed_day
				_script_value = 1
				return advance()
			_stage_day_of_week_menu()
			return _waiting_result()
		if pending_type in [&"choice", &"menu"]:
			if choice < 0:
				return _waiting_result()
			if pending_type == &"choice" \
				and _pending.get("choices", []) == [&"yes", &"no"]:
				_script_value = 1 if choice == 0 else 0
			else:
				_script_value = choice
		if pending_type == &"choice" and _pending.has("contact"):
			var contact: int = int(_pending.get("contact", -1))
			if choice == 0:
				var phone_result: Dictionary = _stage_phone_contact(contact)
				if not bool(phone_result.get("ok", false)):
					return _fail(
						StringName(phone_result.get("reason", &"phone_contact_failed")),
						phone_result
					)
			else:
				_script_value = PHONE_CONTACT_REFUSED
			_emit_runtime_event(&"phone_number_result", {
				"contact": contact,
				"accepted": choice == 0 and _script_value == PHONE_CONTACT_GOT,
				"result": _script_value,
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
## result. A confirmed loss ends this invocation through the explicit blackout
## recovery result without committing its staged world state.
func complete_runtime_request(result: Dictionary) -> Dictionary:
	if _pending.is_empty() or _pending.get("type", &"") != &"runtime_request":
		return {
			"ok": false, "status": &"failed", "reason": &"runtime_request_not_pending",
			"details": result.duplicate(true),
		}
	var request: Dictionary = _pending.get("request", {})
	var kind: StringName = StringName(request.get("kind", &""))
	if kind == &"catch_tutorial_requested":
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", &"catch_tutorial_failed")), result
			)
		var outcome: StringName = StringName(result.get("outcome", &""))
		if outcome != Gen2WorldBattleAdapter.OUTCOME_CAUGHT:
			return _fail(&"invalid_catch_tutorial_outcome", result)
		_script_value = 1
		_events.append({
			"type": &"catch_tutorial_completed",
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_events.append({"type": &"battle_map_reload_requested", "tutorial": true})
		_pending = {}
		return advance()
	if kind == &"swarm_requested":
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", &"swarm_request_failed")), result
			)
		var values: Dictionary = request.get("values", {})
		var active: bool = bool(result.get("active", true))
		var map_group: int = int(result.get("map_group", values.get("map_group", -1)))
		var map_number: int = int(result.get("map_number", values.get("map_number", -1)))
		var fishing_species: int = int(result.get("fishing_species", 0))
		if active and (map_group < 0 or map_number < 0):
			return _fail(&"invalid_swarm_map", result)
		if fishing_species not in [0, 0xD3, 0xDF]:
			return _fail(&"invalid_fishing_swarm_species", result)
		_staged_swarm = {
			"active": active,
			"map_group": map_group,
			"map_number": map_number,
			"fishing_species": fishing_species,
		}
		_has_staged_swarm = true
		_events.append({
			"type": &"swarm_changed",
			"map_group": map_group,
			"map_number": map_number,
			"active": active,
			"fishing_species": fishing_species,
		})
		_pending = {}
		return advance()
	if kind in [&"phone_call_requested", &"special_phone_call_requested"]:
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", "runtime_request_failed")), result
			)
		var phone_data: Dictionary = result.get("data", {})
		_events.append({
			"type": &"runtime_request_completed",
			"kind": kind,
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_pending = {}
		if bool(phone_data.get("clear", false)):
			_phone_context = {}
			_script_value = 1
			return advance()
		var phone_script: Dictionary = phone_data.get("script", {})
		if phone_script.is_empty():
			_script_value = int(result.get("script_value", 1))
			return advance()
		_phone_context = phone_data.get("phone", {}).duplicate(true)
		_phone_started = false
		if not _push_frame(
			int(phone_script.get("bank", -1)), int(phone_script.get("address", -1))
		):
			return _fail(&"phone_script_missing", phone_script)
		return advance()
	if kind == &"trainer_approach_requested":
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", &"trainer_approach_failed")), result
			)
		_events.append({
			"type": &"trainer_approach_completed",
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_pending = {}
		return advance()
	if kind in [
		&"mart_requested", &"audio_requested", &"pokemon_requested", &"trade_requested",
		&"pc_requested", &"party_heal_requested",
	]:
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", "runtime_request_failed")), result
			)
		_script_value = int(result.get("script_value", 1))
		_events.append({
			"type": &"runtime_request_completed",
			"kind": kind,
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		var approach_after_audio: bool = kind == &"audio_requested" \
			and StringName((request.get("values", {}) as Dictionary).get("kind", &"")) \
			== &"encounter_music" and _trainer_intro_approach_pending
		_pending = {}
		if approach_after_audio:
			_trainer_intro_approach_pending = false
			_stage_trainer_approach()
		return advance()
	if kind == &"rival_name_requested":
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", &"runtime_request_failed")), result
			)
		var default_name: String = String(
			(request.get("values", {}) as Dictionary).get("default_name", "SILVER")
		)
		_rival_name = String(result.get("name", default_name)).strip_edges()
		if _rival_name.is_empty():
			_rival_name = default_name
		_script_value = 1
		_events.append({"type": &"rival_name_changed", "name": _rival_name})
		_pending = {}
		return advance()
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
	var battle_values: Dictionary = request.get("values", {})
	if outcome == Gen2WorldBattleAdapter.OUTCOME_LOST and bool(battle_values.get("can_lose", false)):
		_script_value = 0
		_events.append({
			"type": &"battle_lost",
			"outcome": outcome,
			"can_lose": true,
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_pending = {}
		return advance()
	if outcome == Gen2WorldBattleAdapter.OUTCOME_LOST:
		var recovery: Variant = result.get("recovery", {})
		if not recovery is Dictionary or not bool((recovery as Dictionary).get("ok", false)):
			return _fail(&"battle_recovery_failed", result)
		_events.append({
			"type": &"battle_lost",
			"outcome": outcome,
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_events.append({
			"type": &"blackout",
			"recovery": (recovery as Dictionary).duplicate(true),
		})
		_pending = {}
		_active = false
		_completed = true
		return _recovered_result(recovery as Dictionary)
	if outcome == Gen2WorldBattleAdapter.OUTCOME_CAUGHT:
		_script_value = BATTLE_RESULT_WIN
		_events.append({
			"type": &"battle_captured",
			"outcome": outcome,
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_pending = {}
		return advance()
	if outcome != Gen2WorldBattleAdapter.OUTCOME_WON:
		return _fail(StringName("battle_%s" % outcome), result)

	_stage_just_battled(true)
	## Script_startbattle leaves `wBattleResult & ~BATTLERESULT_BITMASK` in
	## wScriptVar, and WIN is zero there, so the eight corpus scripts that put
	## an `iftrue` straight after `startbattle` are asking "did I not win".
	## Catching masks its own bit off and also reads as WIN.
	_script_value = BATTLE_RESULT_WIN
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
	var request: Dictionary = (_pending.get("request", {}) as Dictionary).duplicate(true)
	request["source"] = (_pending.get("source", {}) as Dictionary).duplicate(true)
	return request


func pending_input() -> Dictionary:
	return _pending.duplicate(true)


## Cancels a pending menu or choice without inventing a cartridge option. The
## script receives zero, matching the false branch used by yes/no commands.
func cancel_input() -> Dictionary:
	if _pending.is_empty() or StringName(_pending.get("type", &"")) not in [&"choice", &"menu"]:
		return {
			"ok": false,
			"status": &"failed",
			"reason": &"script_input_not_cancellable",
		}
	var pending_type: StringName = StringName(_pending.get("type", &""))
	if pending_type == &"choice" and _pending.has("contact"):
		_emit_runtime_event(&"phone_number_result", {
			"contact": int(_pending.get("contact", -1)), "accepted": false,
		})
	_script_value = 0
	var finish_after_pending: bool = _finish_after_pending
	_pending = {}
	_finish_after_pending = false
	if finish_after_pending:
		return _complete()
	return advance()


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
	var later_result: Dictionary = _execute_later_command(source_opcode, command, bank)
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
			var runtime_pointer: Dictionary = _runtime_memory_pointer(
				int(command.get("address", 0))
			)
			if runtime_pointer.is_empty():
				return {
					"ok": false, "reason": &"missing_runtime_pointer",
					"address": int(command.get("address", 0)), "command": command,
				}
			var pointer_bank: int = int(runtime_pointer.get("bank", -1))
			var pointer_address: int = int(runtime_pointer.get("address", -1))
			if opcode == Gen2WorldScript.MEMCALL:
				if not _push_frame(pointer_bank, pointer_address):
					return {
						"ok": false, "reason": &"missing_runtime_script",
						"bank": pointer_bank, "address": pointer_address,
					}
				return {"ok": true}
			var jump_result: Dictionary = _replace_frame(pointer_bank, pointer_address)
			return jump_result
		Gen2WorldScript.BLACKOUTMOD:
			## BLACKOUTMOD changes the cartridge's recovery destination. The current
			## save boundary does not yet relocate a player on ordinary blackout, so
			## retain the source value as an explicit event rather than discarding it.
			_emit_runtime_event(&"blackout_destination_changed", {
				"map": int(command.get("value", 0)),
			})
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
		Gen2WorldScript.READMEM:
			_script_value = _script_memory_value(int(command["address"]))
		Gen2WorldScript.WRITEMEM:
			return _stage_script_memory(int(command["address"]), _script_value)
		Gen2WorldScript.LOADMEM:
			return _stage_script_memory(int(command["address"]), int(command["value"]))
		Gen2WorldScript.READVAR:
			return _read_runtime_variable(int(command["value"]))
		Gen2WorldScript.LOADVAR:
			return _load_runtime_variable(
				int(command["value"]), int(command["value_2"])
			)
		Gen2WorldScript.CHECKTIME:
			_script_value = 1 if Gen2WorldPhoneHost.time_mask_matches(
				int(command["value"]), _clock_hour()
			) else 0
		Gen2WorldScript.ADDCELLNUM:
			return _stage_phone_contact(int(command["value"]))
		Gen2WorldScript.DELCELLNUM:
			return _stage_phone_contact(int(command["value"]), false)
		Gen2WorldScript.CHECKCELLNUM:
			_script_value = 1 if _phone_contact_registered(int(command["value"])) else 0
		Gen2WorldScript.SPECIAL:
			return _execute_special(
				Gen2WorldScript.special_index(int(command["value"]), _crystal_commands())
			)
		Gen2WorldScript.RANDOM:
			var maximum: int = int(command["value"])
			_script_value = _random.randi_range(0, maximum - 1) if maximum > 0 else 0
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
			var money: int = _money_balance(int(command["account"]))
			_set_text_buffer(int(command["string_buffer"]), str(money), &"money")
			_emit_runtime_event(&"text_value_requested", {
				"value_kind": &"money", "account": int(command["account"]),
				"value": money,
				"string_buffer": int(command["string_buffer"]),
			})
		Gen2WorldScript.GETCOINS:
			var coins: int = _coins_value()
			_set_text_buffer(int(command["string_buffer"]), str(coins), &"coins")
			_emit_runtime_event(&"text_value_requested", {
				"value_kind": &"coins", "value": coins,
				"string_buffer": int(command["string_buffer"]),
			})
		Gen2WorldScript.GETITEMNAME:
			_set_text_buffer(
				int(command["string_buffer"]),
				data.item_name(int(command["item"])) if data != null else "",
				&"item_name",
				{"item": int(command["item"])}
			)
			_emit_runtime_event(&"text_buffer_requested", command)
		Gen2WorldScript.GETMONNAME:
			_set_text_buffer(
				int(command["string_buffer"]),
				String(data.species(int(command["pokemon"])).get("name", "")) if data != null else "",
				&"mon_name",
				{"pokemon": int(command["pokemon"])}
			)
			_emit_runtime_event(&"text_buffer_requested", command)
		Gen2WorldScript.GETTRAINERNAME:
			var trainer_name: String = ""
			if data != null:
				trainer_name = String(data.trainer_party(
					int(command["trainer_group"]), int(command["trainer_id"]) - 1
				).get("name", ""))
			_set_text_buffer(
				int(command["string_buffer"]), trainer_name, &"trainer_name",
				{"trainer_group": int(command["trainer_group"]), "trainer_id": int(command["trainer_id"])}
			)
			_emit_runtime_event(&"text_buffer_requested", command)
		Gen2WorldScript.GETSTRING:
			var string_text: String = ""
			if data != null:
				var string_data: PackedByteArray = data.world_text(
					int(_request.get("bank", 0)), int(command["address"])
				)
				var string_decoded: Dictionary = _decode_text_with_buffers(string_data)
				if bool(string_decoded.get("ok", false)):
					string_text = String(string_decoded.get("text", ""))
			_set_text_buffer(int(command["string_buffer"]), string_text, &"string", {
				"bank": int(_request.get("bank", 0)), "address": int(command["address"]),
			})
			_emit_runtime_event(&"text_buffer_requested", command)
		Gen2WorldScript.CLEAREVENT:
			_staged_flags[int(command["flag"])] = false
		Gen2WorldScript.SETEVENT:
			_staged_flags[int(command["flag"])] = true
		Gen2WorldScript.CHECKEVENT:
			_script_value = 1 if _event_flag_active(int(command["flag"])) else 0
		Gen2WorldScript.CLEARFLAG:
			_staged_engine_flags[int(command["flag"])] = false
		Gen2WorldScript.SETFLAG:
			_staged_engine_flags[int(command["flag"])] = true
		Gen2WorldScript.CHECKFLAG:
			_script_value = 1 if _engine_flag_active(int(command["flag"])) else 0
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
			if data != null:
				var cached_menu: Dictionary = data.world_menu(
					int(_request.get("bank", 0)), int(command["address"])
				)
				for key: String in cached_menu:
					_loaded_menu[key] = cached_menu[key]
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
		Gen2WorldScript.CHECKFLAG, Gen2WorldScript.CLEARFLAG, Gen2WorldScript.SETFLAG,
		Gen2WorldScript.READMEM,
		Gen2WorldScript.READVAR, Gen2WorldScript.LOADVAR,
		Gen2WorldScript.CHECKTIME, Gen2WorldScript.SPECIAL,
		Gen2WorldScript.CHECKITEM,
		Gen2WorldScript.ADDCELLNUM, Gen2WorldScript.DELCELLNUM,
		Gen2WorldScript.CHECKCELLNUM,
		Gen2WorldScript.GOLD_FACEPLAYER, Gen2WorldScript.FACEPLAYER,
		Gen2WorldScript.OPENTEXT, Gen2WorldScript.REANCHORMAP,
		Gen2WorldScript.CLOSETEXT, Gen2WorldScript.WRITEUNUSEDBYTE,
		Gen2WorldScript.CLOSEWINDOW,
		Gen2WorldScript.ITEMNOTIFY,
		Gen2WorldScript.LOADMENU,
		Gen2WorldScript.GETMONEY, Gen2WorldScript.GETCOINS, Gen2WorldScript.GETNUM,
		Gen2WorldScript.GETMONNAME, Gen2WorldScript.GETITEMNAME,
		Gen2WorldScript.GETCURLANDMARKNAME, Gen2WorldScript.GETTRAINERNAME,
		Gen2WorldScript.GETSTRING, Gen2WorldScript.BLACKOUTMOD,
	]
	if opcode in handled_base:
		return {"ok": true}
	return {
		"ok": false,
		"reason": &"unsupported_runtime_command",
		"command": command,
	}


func _execute_later_command(source_opcode: int, command: Dictionary, bank: int) -> Dictionary:
	match source_opcode:
		0x55:
			_emit_runtime_event(&"pokemon_picture_requested", {
				"pokemon": int(command.get("pokemon", 0)),
			})
		0x56:
			_emit_runtime_event(&"pokemon_picture_closed", {})
		0x57, 0x58:
			return _stage_menu(source_opcode == 0x57, command)
		0x5B:
			var trainer_value: Variant = _request.get("trainer", {})
			if trainer_value is Dictionary and not (trainer_value as Dictionary).is_empty():
				var trainer: Dictionary = trainer_value as Dictionary
				_battle_setup = _new_battle_setup({
					"kind": &"trainer",
					"trainer_group": int(trainer.get("trainer_group", 0)),
					"trainer_id": maxi(int(trainer.get("trainer_id", 0)) - 1, 0),
					"trainer_flag": int(trainer.get("event_flag", -1)),
					"win_text": _trainer_text_pointer(trainer, "win_text", bank),
					"loss_text": _trainer_text_pointer(trainer, "loss_text", bank),
				})
				_emit_runtime_event(&"battle_setup_changed", _battle_setup)
		0x5C:
			_battle_setup = _new_battle_setup({
				"kind": &"wild", "pokemon": int(command.get("pokemon", 0)),
				"level": int(command.get("level", 0)),
			})
			_emit_runtime_event(&"battle_setup_changed", _battle_setup)
		0x5D:
			_loaded_battle_type = -1
			_battle_setup = _new_battle_setup({
				"kind": &"trainer", "trainer_group": int(command.get("trainer_group", 0)),
				# The cartridge's loadtrainer operand is one-based; the imported
				# party table API is zero-based.
				"trainer_id": maxi(int(command.get("trainer_id", 0)) - 1, 0),
			})
			_emit_runtime_event(&"battle_setup_changed", _battle_setup)
		0x5E:
			if _battle_setup.is_empty():
				return {
					"ok": false, "reason": &"battle_setup_missing", "command": command,
				}
			return _stage_runtime_request(&"battle_requested", _battle_request_values())
		0x5F:
			_emit_runtime_event(&"battle_map_reload_requested", {"requested": true})
		0x60:
			var tutorial_setup: Dictionary = _battle_setup.duplicate(true)
			if tutorial_setup.is_empty() or StringName(tutorial_setup.get("kind", &"")) != &"wild":
				return {"ok": false, "reason": &"tutorial_battle_setup_missing"}
			tutorial_setup["tutorial"] = true
			tutorial_setup["battle_type"] = int(command.get("value", 0))
			tutorial_setup["can_lose"] = false
			return _stage_runtime_request(&"catch_tutorial_requested", tutorial_setup)
		0x61:
			return _stage_runtime_request(&"trainer_text_requested", {
				"text_id": int(command.get("value", 0)),
				"setup": _battle_setup.duplicate(true),
			})
		0x62:
			var trainer_event: Dictionary = _request.get("event", {})
			var trainer_data: Variant = _request.get("trainer", {})
			var trainer_flag: int = int(trainer_event.get("event_flag", 0))
			if trainer_data is Dictionary and not (trainer_data as Dictionary).is_empty():
				trainer_flag = int((trainer_data as Dictionary).get("event_flag", -1))
			var action: int = int(command.get("value", 0))
			if action == 0:
				_staged_flags[trainer_flag] = false
			elif action == 1:
				_staged_flags[trainer_flag] = true
			elif action == 2:
				_script_value = 1 if _event_flag_active(trainer_flag) else 0
			else:
				return {"ok": false, "reason": &"unsupported_trainer_flag_action", "action": action}
			_emit_runtime_event(&"trainer_flag_action", {
				"action": action, "event_flag": trainer_flag,
				"script_value": _script_value,
			})
		0x63:
			_battle_setup["win_text"] = {
				"bank": bank, "address": int(command.get("win_address", 0)),
			}
			_battle_setup["loss_text"] = {
				"bank": bank, "address": int(command.get("loss_address", 0)),
			}
		0x64:
			## Script_scripttalkafter jumps to wScriptAfterPointer in
			## wSeenTrainerBank, which is the map's own script bank here. A
			## record without one leaves the script to end, since the source
			## always writes the pointer the trainer macro carries.
			var after_trainer: Variant = _request.get("trainer", {})
			var after_address: int = int((after_trainer as Dictionary).get("after_script", 0)) \
				if after_trainer is Dictionary else 0
			_emit_runtime_event(&"trainer_talk_after_requested", {
				"bank": bank, "address": after_address,
			})
			if after_address > 0:
				_frames.clear()
				if not _push_frame(bank, after_address):
					return {
						"ok": false, "reason": &"missing_trainer_after_script",
						"bank": bank, "address": after_address,
					}
		0x65:
			if _has_staged_just_battled or (state != null and state.just_battled()):
				_frames.clear()
		0x66:
			_script_value = 1 if _has_staged_just_battled or (
				state != null and state.just_battled()
			) else 0
		0x73:
			_loaded_emote = int(command.get("value", -1))
			if _loaded_emote == 0xFF:
				_loaded_emote = _script_value
			_emit_runtime_event(&"emote_loaded", {"emote_id": _loaded_emote})
		0x74:
			var emote_id: int = int(command.get("value", _loaded_emote))
			if emote_id == 0xFF:
				emote_id = _loaded_emote
			_emit_object_event(&"object_emote", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"emote_id": emote_id,
				"visible": true,
				"duration": int(command.get("value_2", 0)),
			})
		0x77:
			_emit_runtime_event(&"earthquake_requested", {
				"strength": int(command.get("value", 0)),
			})
		0x78:
			_emit_runtime_event(&"map_blocks_requested", {
				"bank": bank, "address": int(command.get("address", 0)),
			})
		0x79:
			_emit_runtime_event(&"map_block_changed", {
				"x": int(command.get("x", 0)), "y": int(command.get("y", 0)),
				"block": int(command.get("block", 0)),
			})
		0x7A:
			_emit_runtime_event(&"map_reload_requested", {})
		0x7B:
			_emit_runtime_event(&"map_refresh_requested", {})
		0x7C:
			_emit_runtime_event(&"command_queue_written", {
				"bank": bank, "address": int(command.get("address", 0)),
			})
		0x7D:
			_script_value = 1
			_emit_runtime_event(&"command_queue_deleted", {
				"queue_id": int(command.get("value", -1)),
			})
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
			return _stage_audio_request(&"sound_wait", {})
		0x86:
			return _stage_audio_request(&"warp_sound", {
				"collision": int(_request.get("collision", -1)),
			})
		0x87:
			return _stage_audio_request(&"special_sound", {"item": _last_item})
		0x6C:
			## variablesprite stores a sprite id in the source's variable-sprite
			## table. The first operand is an index relative to SPRITE_VARS.
			_emit_runtime_event(&"variable_sprite_changed", {
				"variable_sprite": VARIABLE_SPRITE_BASE + int(command.get("value", 0)),
				"sprite": int(command.get("value_2", 0)),
			})
		0x8A, 0x8B:
			_emit_runtime_event(&"script_timing_requested", {
				"kind": &"pause" if source_opcode == 0x8A else &"deactivate_facing",
				"value": int(command.get("value", 0)),
			})
		0x8C:
			if not _push_frame(bank, int(command.get("address", 0))):
				return {
					"ok": false, "reason": &"missing_deferred_script",
					"bank": bank, "address": int(command.get("address", 0)),
				}
		0x8D:
			## Script_warpcheck runs WarpCheck against the cell the player is
			## standing on, so the destination is the world's to resolve, not
			## the script's. Burned Tower's rival scene opens the hole under the
			## player and then relies on this to drop them through it.
			_emit_runtime_event(&"warp_check_requested", {})
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
			## The cartridge uses specialphonecall to store the pending special
			## call. Imported phone scripts also use SPECIALCALL_NONE to clear it.
			## This command never starts the call directly. CheckSpecialPhoneCall
			## consumes the staged value during a later step.
			var special_call_id: int = int(command.get("address", 0))
			if not _phone_context.is_empty():
				_phone_context["special_call_id"] = special_call_id
			_staged_special_phone_call = special_call_id
			_has_staged_special_phone_call = true
			_script_value = 1
			_emit_runtime_event(&"special_phone_call_changed", {
				"call_id": special_call_id,
			})
			return {"ok": true}
		0x9C:
			_script_value = 1 if _current_special_phone_call() != 0 else 0
		0x9D:
			return _stage_item_delta(int(command.get("item", 0)), int(command.get("quantity", 1)))
		0x9E:
			return _stage_runtime_request(&"swarm_requested", {
				"map_group": int(command.get("map_group", 0)),
				"map_number": int(command.get("map_number", 0)),
			})
		0x9F:
			_staged_engine_flags[Gen2WorldState.ENGINE_HALL_OF_FAME] = true
			_events.append({"type": &"hall_of_fame_requested"})
		0xA1:
			return _stage_warp_facing_request(command)
	var handled_sources: Array = [
		0x55, 0x56, 0x57, 0x58, 0x5B, 0x5C, 0x5D, 0x5F, 0x60, 0x61, 0x62, 0x63, 0x64,
		0x65, 0x66, 0x7F, 0x81, 0x82, 0x85, 0x8A, 0x8B, 0x8D, 0x98,
		0x8C,
		0x6C, 0x73, 0x74, 0x77, 0x78, 0x79, 0x7A, 0x7B, 0x7C, 0x7D, 0x9C, 0x9F,
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
			var first_object_id: int = int(command.get("object_id", 0))
			var first_object: int = _object_index_from_id(first_object_id)
			var second_object: int = _object_index_from_id(int(command.get("object_id_2", 0)))
			if first_object_id == 0 and second_object >= 0:
				# faceobject PLAYER, LAST_TALKED faces the player toward the
				# trainer. The cache omits PLAYER from its object array.
				_emit_object_event(&"player_face_object", {
					"target_index": second_object,
				})
			elif first_object >= 0 and second_object >= 0:
				_emit_object_event(&"object_face_object", {
					"object_index": first_object,
					"target_index": second_object,
				})
		0x6D:
			_emit_object_event(&"object_visibility", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"active": false,
			})
			_emit_object_event(&"object_event_flag", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"active": true,
			})
		0x6E:
			_emit_object_event(&"object_visibility", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"active": true,
			})
			_emit_object_event(&"object_event_flag", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"active": false,
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
	if item > 0:
		_last_item = item
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
	if _loaded_menu.has("decode_error"):
		return {
			"ok": false,
			"reason": &"menu_data_invalid",
			"details": _loaded_menu.get("decode_error", ""),
		}
	_pending = {
		"type": &"menu",
		"menu_kind": &"2d" if two_dimensional else &"vertical",
		"header": _loaded_menu.duplicate(true),
		"options": _loaded_menu.get("options", []).duplicate(true),
		"source": _request.duplicate(true),
	}
	return {"ok": true}


func _stage_audio_request(kind: StringName, values: Dictionary) -> Dictionary:
	var event: Dictionary = {"kind": kind}
	for key: Variant in values:
		event[key] = values[key]
	return _stage_runtime_request(&"audio_requested", event)


func _phone_contact_registered(contact: int) -> bool:
	if _staged_phone_contacts.has(contact):
		return bool(_staged_phone_contacts[contact])
	return state != null and state.has_phone_contact(contact)


func _phone_contact_candidate() -> Dictionary:
	var candidate: Dictionary = state.phone_contacts() if state != null else {}
	for raw_contact: Variant in _staged_phone_contacts:
		var contact: int = int(raw_contact)
		if bool(_staged_phone_contacts[raw_contact]):
			candidate[contact] = true
		else:
			candidate.erase(contact)
	return candidate


func _stage_phone_contact(contact: int, add: bool = true) -> Dictionary:
	if data == null or contact < 0 or contact >= data.world_phone_contact_count():
		return {"ok": false, "reason": &"invalid_phone_contact", "contact": contact}
	if add:
		if _phone_contact_registered(contact):
			_script_value = PHONE_CONTACTS_FULL
			_emit_runtime_event(&"phone_contact_changed", {
				"contact": contact, "added": false, "result": _script_value,
			})
			return {"ok": true, "added": false, "result": _script_value}
		var candidate: Dictionary = _phone_contact_candidate()
		if candidate.size() >= Gen2WorldState.PHONE_CONTACT_CAPACITY:
			_script_value = PHONE_CONTACTS_FULL
			_emit_runtime_event(&"phone_contact_changed", {
				"contact": contact, "added": false, "result": _script_value,
			})
			return {"ok": true, "added": false, "result": _script_value}
		_staged_phone_contacts[contact] = true
		_script_value = PHONE_CONTACT_GOT
		_emit_runtime_event(&"phone_contact_changed", {
			"contact": contact, "added": true, "result": _script_value,
		})
		return {"ok": true, "added": true, "result": _script_value}
	if not _phone_contact_registered(contact):
		_script_value = 1
		_emit_runtime_event(&"phone_contact_changed", {
			"contact": contact, "added": false, "removed": false, "result": _script_value,
		})
		return {"ok": true, "removed": false, "result": _script_value}
	_staged_phone_contacts[contact] = false
	_script_value = 0
	_emit_runtime_event(&"phone_contact_changed", {
		"contact": contact, "added": false, "removed": true, "result": _script_value,
	})
	return {"ok": true, "removed": true, "result": _script_value}


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


func _stage_trainer_approach() -> void:
	_stage_runtime_request(&"trainer_approach_requested", {
		"object_index": int(_request.get("object_index", -1)),
		"distance": int(_request.get("distance", 0)),
		"direction": _request.get("direction", Vector2i.ZERO),
	})


func _read_runtime_variable(variable: int) -> Dictionary:
	var clock: Dictionary = _request.get("clock", {})
	var hour: int = int(clock.get("hour", _clock_hour()))
	var day: int = int(clock.get("day", 0))
	match variable:
		0x01: # VAR_PARTYCOUNT
			var party: Dictionary = _request.get("party", {})
			if party.is_empty():
				return {
					"ok": false, "reason": &"missing_party_summary", "variable": variable,
				}
			_script_value = int(party.get("count", 0))
		0x04: # VAR_TIMEOFDAY
			_script_value = Gen2WorldClock.new(hour, 0, day).time_of_day()
		0x07: # VAR_BADGES
			_script_value = state.badge_count(_crystal_commands()) if state != null else 0
		0x0A: # VAR_HOUR
			_script_value = hour
		0x0B: # VAR_WEEKDAY
			_script_value = day
		0x09: # VAR_FACING
			_script_value = int(_request.get("facing", -1))
		0x0C: # VAR_MAPGROUP
			_script_value = int(_request.get("map_group", -1))
		0x0D: # VAR_MAPNUMBER
			_script_value = int(_request.get("map_number", -1))
		0x0F: # VAR_ENVIRONMENT
			_script_value = int(_request.get("environment", -1))
		0x14: # VAR_SPECIALPHONECALL
			_script_value = _current_special_phone_call()
		0x17: # VAR_CALLERID
			_script_value = int(_phone_context.get("caller_id", -1))
		_:
			return {
				"ok": false,
				"reason": &"unsupported_runtime_variable",
				"variable": variable,
			}
	return {"ok": true}


func _load_runtime_variable(variable: int, value: int) -> Dictionary:
	## Phone scripts use LOADVAR for the two runtime values that are not
	## ordinary world-state variables. Battles also load VAR_BATTLETYPE before
	## STARTBATTLE so a source can explicitly permit a non-blackout loss.
	match variable:
		0x03: # VAR_BATTLETYPE
			if _battle_setup.is_empty():
				_loaded_battle_type = value
			else:
				_battle_setup["battle_type"] = value
				_battle_setup["can_lose"] = value == 1
		0x14: # VAR_SPECIALPHONECALL
			if not _phone_context.is_empty():
				_phone_context["special_call_id"] = value
			_staged_special_phone_call = value
			_has_staged_special_phone_call = true
		0x17: # VAR_CALLERID
			_phone_context["caller_id"] = value
		_:
			return {
				"ok": false,
				"reason": &"unsupported_runtime_loadvar",
				"variable": variable,
				"value": value,
			}
	return {"ok": true}


func _current_special_phone_call() -> int:
	## A staged specialphonecall updates the script-visible variable before
	## the transaction commits, just as the source WRAM byte does.
	if _has_staged_special_phone_call:
		return _staged_special_phone_call
	var context_value: int = int(_phone_context.get("special_call_id", 0))
	if context_value != 0:
		return context_value
	var request_value: Variant = _request.get("special_phone_call", 0)
	if request_value is int or request_value is float:
		if int(request_value) != 0:
			return int(request_value)
	return state.pending_special_phone_call() if state != null else 0


func _clock_hour() -> int:
	var clock: Dictionary = _request.get("clock", {})
	return clampi(int(clock.get("hour", 0)), 0, 23)


func _clock_minute() -> int:
	var clock: Dictionary = _request.get("clock", {})
	return clampi(int(clock.get("minute", 0)), 0, 59)


## [param special] is the Crystal-canonical index from
## Gen2WorldScript.special_index(), not the raw stream byte, so the payloads
## below report that index on both profiles.
func _execute_special(special: int) -> Dictionary:
	## SPECIAL is a shared cartridge dispatch table. Phone routines are only one
	## part of it; map callbacks and the new-game clock setup use the same table.
	match special:
		SPECIAL_PLAYERS_HOUSE_PC:
			return _stage_runtime_request(&"pc_requested", {
				"special": special,
				"mode": &"players_house",
			})
		SPECIAL_POKEMON_CENTER_PC:
			return _stage_runtime_request(&"pc_requested", {
				"special": special,
				"mode": &"pokemon_center",
			})
		SPECIAL_SET_DAY_OF_WEEK:
			_stage_day_of_week_menu()
			return {"ok": true}
		SPECIAL_INITIAL_SET_DST_FLAG:
			_staged_dst_enabled = true
			_has_staged_dst = true
			_stage_dst_confirmation_text(true)
			return {"ok": true}
		SPECIAL_INITIAL_CLEAR_DST_FLAG:
			_staged_dst_enabled = false
			_has_staged_dst = true
			_stage_dst_confirmation_text(false)
			return {"ok": true}
		SPECIAL_PLAY_MAP_MUSIC, SPECIAL_RESTART_MAP_MUSIC:
			# Entering a map with the music already playing does not restart it,
			# which is why crossing a route boundary is one continuous track.
			# RestartMapMusic exists to override exactly that, so it says so.
			return _stage_audio_request(&"map_music", {
				"special": special,
				"restart": special == SPECIAL_RESTART_MAP_MUSIC,
			})
		SPECIAL_FADE_OUT_MUSIC:
			_emit_runtime_event(&"music_fadeout_requested", {"special": special})
		36:
			return _stage_runtime_request(&"rival_name_requested", {
				"special": special, "default_name": "SILVER",
			})
		27:
			## HealParty is a save-owned transaction. It is deliberately a host
			## request so HP, status and PP are changed together with the selected
			## project save.
			return _stage_runtime_request(&"party_heal_requested", {"special": special})
		SPECIAL_HEAL_MACHINE_ANIM:
			## wScriptVar selects the machine's screen position: 0 Pokemon Center,
			## 1 Elm's Lab, 2 Hall of Fame. A preceding SETVAL loads it, so it is
			## carried through as presentation only; nothing here changes state.
			_emit_runtime_event(&"presentation_special_applied", {
				"special": special, "kind": &"heal_machine_anim",
				"machine_type": _script_value,
			})
		SPECIAL_CHECK_POKERUS:
			var party: Dictionary = _request.get("party", {})
			if party.is_empty():
				return {"ok": false, "reason": &"missing_party_summary", "special": special}
			_script_value = 1 if bool(party.get("pokerus", false)) else 0
		46, 48, 49, 50, 51, 94, 157, 158:
			## Fade, sprite reload and the dummied trainer-ranking bookkeeping
			## affect presentation or source-only counters, not scene-free state.
			## `FadeOutToWhite` is 46 in both pins, since Crystal's inserted
			## `BattleTowerFade` sits at 47, so it needs no profile split;
			## `FadeInFromWhite` is 49 here and 48 in Gold/Silver, which
			## special_index() already normalizes (maps/OlivineLighthouse6F.asm's
			## Amphy cure runs 46 then 49); `LoadUsedSpritesGFX` (94) and
			## `RefreshSprites` (158) reload the sprite set a `variablesprite`
			## just changed.
			_emit_runtime_event(&"presentation_special_applied", {"special": special})
		SPECIAL_INIT_ROAM_MONS:
			## InitRoamMons seeds the roam structs with Raikou and Entei at
			## level 40 on their starting maps. Gen2WorldAPI.open() already
			## seeds the same imported records, and ensure_roaming_mons() keeps
			## positions a player has already moved, so this reports rather than
			## resetting a beast that is already loose.
			if state != null and data != null:
				state.ensure_roaming_mons(data.world_roaming_mons())
			_emit_runtime_event(&"roaming_mons_initialized", {
				"special": special,
				"count": state.roaming_mons().size() if state != null else 0,
			})
		SPECIAL_ACTIVATE_FISHING_SWARM:
			_emit_runtime_event(&"phone_special_requested", {
				"special": special, "kind": &"activate_fishing_swarm",
				"species": _script_value,
			})
		SPECIAL_TOGGLE_MAPTILE_DECORATIONS:
			## A fresh project save has no imported bedroom decoration selection.
			## Crystal's default decoration values are zero, which leaves the
			## decoration blocks unchanged and hides the room poster.
			_staged_flags[EVENT_PLAYERS_ROOM_POSTER] = false
			_emit_runtime_event(&"decoration_callback_applied", {
				"special": special,
				"kind": &"toggle_maptile_decorations",
				"defaults": true,
			})
		SPECIAL_TOGGLE_DECORATIONS_VISIBILITY:
			## With the default zero decoration selections, ToggleDecorationVisibility
			## sets each object event flag and the renderer removes those objects.
			for flag: int in [
				EVENT_PLAYERS_HOUSE_2F_CONSOLE,
				EVENT_PLAYERS_HOUSE_2F_DOLL_1,
				EVENT_PLAYERS_HOUSE_2F_DOLL_2,
				EVENT_PLAYERS_HOUSE_2F_BIG_DOLL,
			]:
				_staged_flags[flag] = true
			_emit_runtime_event(&"decoration_callback_applied", {
				"special": special,
				"kind": &"toggle_decorations_visibility",
				"defaults": true,
			})
		SPECIAL_RANDOM_UNSEEN_WILD_MON:
			var rare_species: int = _phone_unseen_rare_species()
			if rare_species <= 0:
				_emit_runtime_event(&"phone_special_requested", {
					"special": special, "kind": &"random_unseen_wild_mon",
					"internal_text": false, "script_value": 1,
				})
				_script_value = 1
			else:
				var rare_name: String = String(data.species(rare_species).get("name", ""))
				_set_text_buffer(1, rare_name, &"phone_unseen_wild_mon", {
					"special": special, "species": rare_species,
				})
				_emit_runtime_event(&"phone_special_requested", {
					"special": special, "kind": &"random_unseen_wild_mon",
					"internal_text": true, "buffer": 1, "value": rare_name,
					"species": rare_species, "script_value": 0,
				})
				_script_value = 0
		SPECIAL_RANDOM_PHONE_WILD_MON:
			var wild_name: String = _phone_wild_mon_name()
			_set_text_buffer(1, wild_name, &"phone_wild_mon", {"special": special})
			_emit_runtime_event(&"phone_special_requested", {
				"special": special, "kind": &"random_phone_wild_mon",
				"buffer": 1, "value": wild_name,
			})
		SPECIAL_RANDOM_PHONE_MON:
			var trainer_mon_name: String = _phone_trainer_mon_name()
			_set_text_buffer(1, trainer_mon_name, &"phone_mon", {"special": special})
			_emit_runtime_event(&"phone_special_requested", {
				"special": special, "kind": &"random_phone_mon",
				"buffer": 1, "value": trainer_mon_name,
			})
		_:
			return {
				"ok": false,
				"reason": &"unsupported_phone_special",
				"special": special,
			}
	return {"ok": true}


func _stage_day_of_week_menu() -> void:
	_pending = {
		"type": &"menu",
		"menu_kind": &"vertical",
		"command": &"set_day_of_week",
		"options": WEEKDAY_NAMES.duplicate(),
		"header": {"default": 1, "data_flags": 1 << 5},
		"special": &"set_day_of_week",
		"source": _request.duplicate(true),
	}


func _stage_day_of_week_confirmation(day: int) -> void:
	_pending = {
		"type": &"choice",
		"command": &"set_day_of_week_confirmation",
		"choices": [&"yes", &"no"],
		"special": &"set_day_of_week_confirmation",
		"day": posmod(day, WEEKDAY_NAMES.size()),
		"source": _request.duplicate(true),
	}


func _stage_dst_confirmation_text(enabled: bool) -> void:
	var clock: Dictionary = _request.get("clock", {})
	var hour: int = clampi(int(clock.get("hour", 0)), 0, 23)
	var minute: int = clampi(int(clock.get("minute", 0)), 0, 59)
	var time_text: String = "%02d:%02d" % [hour, minute]
	_pending = {
		"type": &"text",
		"text": "%s%s,\nis that OK?" % [time_text, " DST" if enabled else ""],
		"special": &"initial_dst_confirmation",
		"source": _request.duplicate(true),
	}


func _phone_contact() -> Dictionary:
	if data == null:
		return {}
	var contact_id: int = int(_phone_context.get(
		"caller_id", _phone_context.get("contact_id", -1)
	))
	return data.world_phone_contact(contact_id)


func _phone_wild_mon_name() -> String:
	var contact: Dictionary = _phone_contact()
	var record: Dictionary = data.world_encounter(
		Gen2WorldEncounter.METHOD_GRASS,
		int(contact.get("map_group", -1)), int(contact.get("map_number", -1))
	) if data != null else {}
	var slots: Variant = record.get("slots", [])
	var hour: int = int((_request.get("clock", {}) as Dictionary).get("hour", 0))
	var time_of_day: int = Gen2WorldClock.new(hour).time_of_day()
	if not slots is Array or time_of_day < 0 or time_of_day >= (slots as Array).size():
		return ""
	var selected: Variant = (slots as Array)[time_of_day]
	if not selected is Array or (selected as Array).size() < 4:
		return ""
	## RandomPhoneWildMon masks the cartridge RNG to select one of the first
	## four grass slots, rather than using the ordinary weighted encounter roll.
	var raw_slot: Variant = (selected as Array)[_random.randi_range(0, 3)]
	if not raw_slot is Dictionary:
		return ""
	var species: int = int((raw_slot as Dictionary).get("species", 0))
	if species <= 0 or data.species(species).is_empty():
		return ""
	return String(data.species(species).get("name", ""))


func _phone_unseen_rare_species() -> int:
	var contact: Dictionary = _phone_contact()
	var record: Dictionary = data.world_encounter(
		Gen2WorldEncounter.METHOD_GRASS,
		int(contact.get("map_group", -1)), int(contact.get("map_number", -1))
	) if data != null else {}
	var slots: Variant = record.get("slots", [])
	if not slots is Array or (slots as Array).is_empty():
		return 0
	## Crystal's routine reads wTimeOfDay but fails to use it when applying
	## the table offset, so the shipped game always examines the morning row.
	var morning: Variant = (slots as Array)[0]
	if not morning is Array or (morning as Array).size() < RomLayout.WILD_GRASS_SLOT_COUNT:
		return 0
	var common_species: Array[int] = []
	for index: int in 4:
		var common: Variant = (morning as Array)[index]
		if common is Dictionary:
			common_species.append(int((common as Dictionary).get("species", 0)))
	for _attempt: int in 128:
		var roll: int = _random.randi() & 0x03
		if roll == 0:
			continue
		var slot_index: int = 4 + roll - 1
		var rare: Variant = (morning as Array)[slot_index]
		if not rare is Dictionary:
			return 0
		var species: int = int((rare as Dictionary).get("species", 0))
		if species <= 0 or common_species.has(species):
			return 0
		if state != null and state.has_seen_species(species):
			return 0
		if data == null or data.species(species).is_empty():
			return 0
		return species
	return 0


func _phone_trainer_mon_name() -> String:
	var contact: Dictionary = _phone_contact()
	var trainer_group: int = int(contact.get("trainer_class", 0))
	var trainer_id: int = int(contact.get("trainer_number", 0)) - 1
	var party: Array = data.trainer_party(trainer_group, trainer_id).get("party", []) if data != null else []
	var candidates: Array[int] = []
	for mon: Dictionary in party:
		var species: int = int(mon.get("species", 0))
		if species > 0 and data.species(species).size() > 0:
			candidates.append(species)
	if candidates.is_empty():
		return ""
	var species: int = candidates[_random.randi_range(0, candidates.size() - 1)]
	return String(data.species(species).get("name", ""))


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


## The byte a script memory address holds, staged writes first. Reading an
## address never written answers zero, the way cleared WRAM does.
func _script_memory_value(address: int) -> int:
	if _staged_script_memory.has(address):
		return int(_staged_script_memory[address])
	return state.script_memory(address) if state != null else 0


func _stage_script_memory(address: int, value: int) -> Dictionary:
	if address <= 0:
		return {"ok": false, "reason": &"invalid_script_memory_address", "address": address}
	_staged_script_memory[address] = value & 0xFF
	_emit_runtime_event(&"script_memory_changed", {
		"address": address, "value": value & 0xFF,
	})
	return {"ok": true}


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
	var decoded: Dictionary = _decode_text_with_buffers(raw)
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


func _set_text_buffer(
	buffer: int, value: String, kind: StringName, details: Dictionary = {}
) -> void:
	_text_buffers[buffer] = value
	var event: Dictionary = {
		"buffer": buffer, "value": value, "kind": kind,
	}
	for key: Variant in details:
		event[key] = details[key]
	_emit_runtime_event(&"text_buffer_changed", event)


func _decode_text_with_buffers(raw: PackedByteArray) -> Dictionary:
	if raw.is_empty():
		return {"ok": false, "reason": &"missing_text"}
	var at: int = 1 if raw[0] == Gen2WorldScript.TEXT_START else 0
	var out: String = ""
	while at < raw.size():
		var byte: int = int(raw[at])
		if byte == Gen2WorldScript.TEXT_TERMINATOR:
			return {"ok": true, "text": out, "bytes": at + 1}
		if byte == TEXT_STRING_BUFFER:
			if at + 1 >= raw.size():
				return {"ok": false, "reason": &"truncated_text_buffer", "text": out}
			var buffer: int = int(raw[at + 1])
			out += String(_text_buffers.get(buffer, "<BUFFER_%d>" % buffer))
			at += 2
			continue
		out += _rival_name if byte == 0x53 else Gen2Text.character(byte)
		at += 1
	return {"ok": false, "reason": &"missing_text_terminator", "text": out}


func _runtime_memory_pointer(address: int) -> Dictionary:
	## memcall and memjump read a three-byte far pointer from a live RAM
	## address. The host supplies that RAM snapshot explicitly because the
	## runner does not emulate the cartridge's whole WRAM address space.
	var pointers: Variant = _request.get("memory_pointers", {})
	if not pointers is Dictionary:
		return {}
	var value: Variant = null
	if (pointers as Dictionary).has(address):
		value = (pointers as Dictionary)[address]
	else:
		for raw_address: Variant in pointers as Dictionary:
			if _runtime_memory_address(raw_address) == address:
				value = (pointers as Dictionary)[raw_address]
				break
	if not value is Dictionary:
		return {}
	var pointer: Dictionary = value as Dictionary
	var bank: int = int(pointer.get("bank", -1))
	var target: int = int(pointer.get("address", -1))
	if bank < 0 or target < RomFile.BANK_SIZE or target >= RomFile.BANK_SIZE * 2:
		return {}
	return {"bank": bank, "address": target}


static func _runtime_memory_address(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	var text: String = String(value).strip_edges()
	if text.begins_with("0x") or text.begins_with("0X"):
		return text.substr(2).hex_to_int()
	return text.to_int()


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


func _engine_flag_active(flag: int) -> bool:
	if _staged_engine_flags.has(flag):
		return bool(_staged_engine_flags[flag])
	return state != null and state.is_engine_flag_active(flag)


func _map_scene_value(map_group: int, map_number: int) -> int:
	var key: String = Gen2WorldState.map_scene_key(map_group, map_number)
	if _staged_scenes.has(key):
		return int(_staged_scenes[key])
	if state != null and state.map_scenes().has(key):
		return state.map_scene(map_group, map_number)
	if data != null:
		var map: Gen2WorldMap = data.world_map(map_group, map_number)
		if map != null and not (map.scripts.get("scenes", []) as Array).is_empty():
			# Crystal clears the map-scene table on a new game. Maps with scene
			# records therefore start at scene 0; maps without records use the
			# source no-scene sentinel below.
			return 0
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
	if not _staged_script_memory.is_empty():
		runtime_changes["script_memory"] = _staged_script_memory.duplicate()
	if _has_staged_just_battled:
		runtime_changes["just_battled"] = _staged_just_battled
	if _has_staged_swarm:
		runtime_changes["swarm"] = _staged_swarm.duplicate()
	if _has_staged_special_phone_call:
		runtime_changes["pending_special_phone_call"] = _staged_special_phone_call
	if not _staged_engine_flags.is_empty():
		runtime_changes["engine_flags"] = _staged_engine_flags.duplicate()
	if _reset_phone_receive_timer:
		runtime_changes["phone_receive_cycle"] = 0
		runtime_changes["phone_receive_minutes"] = Gen2WorldState.PHONE_RECEIVE_DELAYS[0]
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
	if _staged_day_of_week >= 0:
		_events.append({
			"type": &"world_clock_changed",
			"day": _staged_day_of_week,
			"hour": _clock_hour(),
			"minute": _clock_minute(),
		})
	if _has_staged_dst:
		_events.append({"type": &"dst_changed", "enabled": _staged_dst_enabled})
	return _complete_result()


func _complete_result() -> Dictionary:
	var result: Dictionary = {
		"ok": true,
		"status": &"complete",
		"events": _events.duplicate(true),
		"source": _request.duplicate(true),
		"warp": _staged_warp.duplicate(true),
		"commands": _command_count,
	}
	if _staged_day_of_week >= 0:
		result["clock"] = {
			"day": _staged_day_of_week,
			"hour": _clock_hour(),
			"minute": _clock_minute(),
		}
	if _has_staged_dst:
		result["dst_enabled"] = _staged_dst_enabled
	return result


func _recovered_result(recovery: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"status": &"recovered",
		"events": _events.duplicate(true),
		"source": _request.duplicate(true),
		"recovery": recovery.duplicate(true),
		"commands": _command_count,
	}


func _new_battle_setup(base: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	if _loaded_battle_type >= 0:
		out["battle_type"] = _loaded_battle_type
		out["can_lose"] = _loaded_battle_type == 1
	for key: String in ["win_text", "loss_text"]:
		if _battle_setup.has(key):
			out[key] = (_battle_setup[key] as Dictionary).duplicate(true)
	return out


func _trainer_text_pointer(trainer: Dictionary, key: String, default_bank: int) -> Dictionary:
	var raw: Variant = trainer.get(key, {})
	if raw is Dictionary:
		var pointer: Dictionary = (raw as Dictionary).duplicate(true)
		pointer["bank"] = int(pointer.get("bank", default_bank))
		pointer["address"] = int(pointer.get("address", 0))
		return pointer
	return {"bank": default_bank, "address": 0}


## Builds the source SeenByTrainerScript/StartBattleWithMapTrainerScript
## sequence: loadtemptrainer, encountermusic, farwritetext, waitbutton,
## loadtemptrainer, startbattle, reloadmapafterbattle, trainerflagaction, end.
## The sequence is identical between profiles at the source-opcode level;
## only the raw bytes differ, so every command goes through
## Gen2WorldScript.raw_opcode() rather than hard-coding either profile's byte.
func _trainer_intro_script(trainer: Dictionary) -> PackedByteArray:
	var seen: Dictionary = _trainer_text_pointer(
		trainer, "seen_text", int(_request.get("bank", 0))
	)
	var bank: int = int(seen.get("bank", _request.get("bank", 0)))
	var address: int = int(seen.get("address", 0))
	var crystal: bool = _crystal_commands()
	var raw: Callable = func(source_opcode: int) -> int:
		return Gen2WorldScript.raw_opcode(source_opcode, crystal)
	var bytes: Array = [
		# loadtemptrainer points at the request's trainer record.
		raw.call(Gen2WorldScript.GOLD_LOADTEMPTRAINER),
		raw.call(Gen2WorldScript.GOLD_ENCOUNTERMUSIC),
		Gen2WorldScript.FARWRITETEXT, bank, address & 0xFF, address >> 8,
		raw.call(0x53), # waitbutton
		raw.call(Gen2WorldScript.GOLD_LOADTEMPTRAINER),
		raw.call(Gen2WorldScript.GOLD_STARTBATTLE),
		raw.call(Gen2WorldScript.GOLD_RELOADMAPAFTERBATTLE),
		raw.call(Gen2WorldScript.GOLD_TRAINERFLAGACTION), 1,
		# StartBattleWithMapTrainerScript falls through into
		# AlreadyBeatenTrainerScript's scripttalkafter, with
		# wRunningTrainerBattleScript already set, so the after-battle script
		# runs now and its own endifjustbattled is what usually ends it. A
		# trainer that omits that command keeps going: Slowpoke Well's
		# TrainerGruntM1 clears the well from there.
		raw.call(Gen2WorldScript.GOLD_SCRIPTTALKAFTER),
		raw.call(Gen2WorldScript.GOLD_END),
	]
	return PackedByteArray(bytes)


func _battle_request_values() -> Dictionary:
	var out: Dictionary = _battle_setup.duplicate(true)
	var source_event: Variant = _request.get("event", {})
	if source_event is Dictionary:
		out["event"] = (source_event as Dictionary).duplicate(true)
	for key: String in [
		"map_group", "map_number", "object_index", "distance", "direction", "trigger",
	]:
		if _request.has(key):
			out[key] = _request[key]
	return out


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
