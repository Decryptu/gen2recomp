class_name Gen2WorldHost
extends RefCounted

## Scene-free policy boundary for requests that need a host subsystem.
## Battle and swarm have mutable runtime adapters. Read-only mart, audio and
## phone requests resolve through imported cache records. Other requests remain
## pending with a specific reason rather than being guessed or acknowledged as
## if the subsystem had run.

static func complete_runtime_request(world: Gen2WorldAPI, result: Dictionary) -> Dictionary:
	if world == null:
		return _unavailable(&"missing_world", {})
	var request: Dictionary = world.pending_runtime_request()
	if request.is_empty():
		return _unavailable(&"runtime_request_not_pending", {})
	var kind: StringName = StringName(request.get("kind", &""))
	if kind in [&"battle_requested", &"swarm_requested"]:
		return {"ok": true, "handled": true, "results": world.complete_runtime_request(result)}
	var resolved: Dictionary = _resolve_data_request(world, request)
	if not resolved.is_empty():
		if not bool(resolved.get("ok", false)):
			return _unavailable(
				StringName(resolved.get("reason", &"runtime_data_unavailable")), request
			)
		var completion: Dictionary = {
			"ok": true,
			"kind": kind,
			"data": resolved.get("data", {}).duplicate(true),
		}
		return {
			"ok": true,
			"handled": true,
			"request": request.duplicate(true),
			"data": resolved.get("data", {}).duplicate(true),
			"results": world.complete_runtime_request(completion),
		}
	return _unavailable(_reason_for(kind), request)


static func choose_script_input(world: Gen2WorldAPI, choice: int) -> Array:
	if world == null:
		return [{"ok": false, "status": &"failed", "reason": &"missing_world"}]
	var pending: Dictionary = world.pending_script_input()
	if pending.is_empty():
		return [{"ok": false, "status": &"failed", "reason": &"script_input_not_pending"}]
	if StringName(pending.get("type", &"")) not in [&"choice", &"menu"]:
		return [{"ok": false, "status": &"failed", "reason": &"script_choice_not_pending"}]
	if choice < 0:
		return [{"ok": false, "status": &"failed", "reason": &"invalid_script_choice"}]
	return world.choose_script_input(choice)


static func _reason_for(kind: StringName) -> StringName:
	match kind:
		&"audio_requested":
			return &"audio_host_unavailable"
		&"mart_requested":
			return &"mart_data_unavailable"
		&"phone_call_requested", &"special_phone_call_requested":
			return &"phone_host_unavailable"
		&"pokemon_requested", &"trade_requested":
			return &"party_host_unavailable"
	return &"runtime_host_unavailable"


static func _resolve_data_request(world: Gen2WorldAPI, request: Dictionary) -> Dictionary:
	if world.data == null:
		return {}
	var kind: StringName = StringName(request.get("kind", &""))
	var values: Dictionary = request.get("values", {})
	match kind:
		&"mart_requested":
			var mart_id: int = int(values.get("address", 0)) & 0xFF
			var mart: Dictionary = world.data.world_mart(mart_id)
			if mart.is_empty():
				return {"ok": false, "reason": &"mart_data_unavailable"}
			return {"ok": true, "data": {"mart": mart, "mart_id": mart_id}}
		&"special_phone_call_requested":
			var call_id: int = int(values.get("address", 0))
			var call: Dictionary = world.data.world_special_phone_call(call_id)
			if call.is_empty():
				return {"ok": false, "reason": &"phone_data_unavailable"}
			return {"ok": true, "data": {"special_call": call, "call_id": call_id}}
		&"phone_call_requested":
			var source: Dictionary = request.get("source", {})
			var address: int = int(values.get("address", 0))
			var contact: Dictionary = _phone_contact_for_script(
				world.data, int(source.get("bank", -1)), address
			)
			if contact.is_empty():
				return {"ok": false, "reason": &"phone_data_unavailable"}
			return {"ok": true, "data": {"contact": contact}}
		&"audio_requested":
			var audio: Dictionary = _audio_for_request(world, request)
			if audio.is_empty():
				return {"ok": false, "reason": &"audio_data_unavailable"}
			return {"ok": true, "data": {"audio": audio}}
	return {}


static func _phone_contact_for_script(data: GameData, bank: int, address: int) -> Dictionary:
	for index: int in data.world_phone_contact_count():
		var contact: Dictionary = data.world_phone_contact(index)
		for key: String in ["caller_script", "callee_script"]:
			var script: Dictionary = contact.get(key, {})
			if int(script.get("bank", -1)) == bank and int(script.get("address", -1)) == address:
				return contact
	return {}


static func _audio_for_request(world: Gen2WorldAPI, request: Dictionary) -> Dictionary:
	var values: Dictionary = request.get("values", {})
	var audio_kind: StringName = StringName(values.get("kind", &""))
	var data: GameData = world.data
	var source: Dictionary = request.get("source", {})
	var bank: int = int(source.get("bank", -1))
	var address: int = int(values.get("address", values.get("music", -1)))
	match audio_kind:
		&"music":
			var music: Dictionary = data.world_audio_pointer(&"music", bank, address)
			if music.is_empty() and address >= 0:
				music = data.world_audio(&"music", address)
			return music
		&"music_fadeout":
			return data.world_audio(&"music", int(values.get("music", -1)))
		&"sound":
			return data.world_audio_pointer(&"sfx", bank, address)
		&"map_music", &"encounter_music":
			if world.current_map == null:
				return {}
			return data.world_audio(&"music", world.current_map.music)
	return {}


static func _unavailable(reason: StringName, request: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"handled": false,
		"status": &"host_unavailable",
		"reason": reason,
		"request": request.duplicate(true),
	}
