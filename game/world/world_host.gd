class_name Gen2WorldHost
extends RefCounted

## Scene-free policy boundary for requests that need a host subsystem.
## Battle and swarm have mutable runtime adapters. Read-only mart, audio and
## phone requests resolve through imported cache records. Other requests remain
## pending with a specific reason rather than being guessed or acknowledged as
## if the subsystem had run.

static func complete_runtime_request(
	world: Gen2WorldAPI,
	result: Dictionary,
	save: Gen2SaveData = null,
	persist: bool = true,
	random: RandomNumberGenerator = null
) -> Dictionary:
	if world == null:
		return _unavailable(&"missing_world", {})
	var request: Dictionary = world.pending_runtime_request()
	if request.is_empty():
		return _unavailable(&"runtime_request_not_pending", {})
	var kind: StringName = StringName(request.get("kind", &""))
	if kind in [&"pokemon_requested", &"trade_requested"]:
		return Gen2WorldPartyHost.complete_runtime_request(
			world, result, save, persist, random
		)
	if kind == &"party_heal_requested":
		return Gen2WorldPartyHost.heal_party(world, save, persist)
	if kind == &"rival_name_requested":
		var completion: Dictionary = {"ok": true}
		for key: Variant in result:
			completion[key] = result[key]
		if not completion.has("name"):
			completion["name"] = String(request.get("values", {}).get("default_name", "SILVER"))
		var resumed: Array = world.complete_runtime_request(completion)
		if resumed.is_empty() or not bool(resumed[0].get("ok", false)):
			return _unavailable(&"rival_name_request_failed", {
				"request": request, "results": resumed,
			})
		return {
			"ok": true,
			"handled": true,
			"request": request.duplicate(true),
			"results": resumed,
		}
	if kind in [&"battle_requested", &"swarm_requested"]:
		return {"ok": true, "handled": true, "results": world.complete_runtime_request(result)}
	var resolved: Dictionary = resolve_runtime_request(world, request)
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
		for key: Variant in result:
			if key == "ok":
				continue
			completion[key] = result[key]
		return {
			"ok": true,
			"handled": true,
			"request": request.duplicate(true),
			"data": resolved.get("data", {}).duplicate(true),
			"results": world.complete_runtime_request(completion),
		}
	return _unavailable(_reason_for(kind), request)


## Resolves one pending cached-service request without completing its script.
## Scene hosts use this to build their presentation from cartridge data while
## keeping script state suspended until the host returns an explicit result.
static func resolve_runtime_request(
	world: Gen2WorldAPI, request: Dictionary = {}
) -> Dictionary:
	if world == null:
		return _unavailable(&"missing_world", request)
	var pending: Dictionary = request.duplicate(true)
	if pending.is_empty():
		pending = world.pending_runtime_request()
	if pending.is_empty():
		return _unavailable(&"runtime_request_not_pending", {})
	var kind: StringName = StringName(pending.get("kind", &""))
	var resolved: Dictionary = _resolve_data_request(world, pending)
	if resolved.is_empty():
		return _unavailable(_reason_for(kind), pending)
	if not bool(resolved.get("ok", false)):
		return _unavailable(
			StringName(resolved.get("reason", &"runtime_data_unavailable")), pending
		)
	return {
		"ok": true,
		"handled": false,
		"request": pending.duplicate(true),
		"data": resolved.get("data", {}).duplicate(true),
	}


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
		&"party_heal_requested":
			return &"party_host_unavailable"
	return &"runtime_host_unavailable"


static func _resolve_data_request(world: Gen2WorldAPI, request: Dictionary) -> Dictionary:
	if world.data == null:
		return {}
	var kind: StringName = StringName(request.get("kind", &""))
	var values: Dictionary = request.get("values", {})
	match kind:
		&"mart_requested":
			var dialog_id: int = int(values.get("dialog", 0))
			var mart_id: int = int(values.get("address", 0)) & 0xFF
			var mart_result: Dictionary = Gen2WorldMartHost.resolve_mart(
				world.data, dialog_id, mart_id, world.state.hall_of_fame(), world.state
			)
			if not bool(mart_result.get("ok", false)):
				return {
					"ok": false,
					"reason": StringName(mart_result.get("reason", &"mart_data_unavailable")),
				}
			return {
				"ok": true,
				"data": {
					"mart": mart_result["mart"], "mart_id": mart_id,
					"dialog": dialog_id,
				},
			}
		&"special_phone_call_requested":
			var call_id: int = int(values.get("address", 0))
			var special: Dictionary = Gen2WorldPhoneHost.resolve_special(
				world.data, world.current_map, call_id, world.world_hour
			)
			if not bool(special.get("ok", false)):
				return {
					"ok": false,
					"reason": StringName(special.get("reason", &"phone_data_unavailable")),
				}
			return {"ok": true, "data": special}
		&"phone_call_requested":
			var source: Dictionary = request.get("source", {})
			var address: int = int(values.get("address", 0))
			if values.has("contact"):
				var outgoing: Dictionary = Gen2WorldPhoneHost.resolve_outgoing(
					world.data, world.state, world.current_map,
					int(values.get("contact", -1)), world.world_hour
				)
				if not bool(outgoing.get("ok", false)):
					return {
						"ok": false,
						"reason": StringName(outgoing.get("reason", &"phone_data_unavailable")),
					}
				return {"ok": true, "data": outgoing}
			var bank: int = int(source.get("bank", -1))
			var caller_name_raw: PackedByteArray = world.data.world_text(bank, address)
			var caller_name: Dictionary = Gen2WorldScript.decode_text(caller_name_raw)
			if not bool(caller_name.get("ok", false)):
				return {"ok": false, "reason": &"phone_caller_name_unavailable"}
			## The source phonecall command passes a text pointer directly to
			## PhoneCall. It does not identify a phone contact or dispatch a
			## contact script.
			return {
				"ok": true,
				"data": {
					"phone_call": {
						"caller_name_pointer": {"bank": bank, "address": address},
						"caller_name": String(caller_name.get("text", "")),
					},
					"phone": source.get("phone", {}).duplicate(true),
				},
			}
		&"audio_requested":
			var audio: Dictionary = _audio_for_request(world, request)
			var audio_kind: StringName = StringName(request.get("values", {}).get("kind", &""))
			if audio.is_empty() and audio_kind != &"sound_wait":
				return {"ok": false, "reason": &"audio_data_unavailable"}
			return {"ok": true, "data": {"audio": audio}}
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
			var sound: Dictionary = data.world_audio_pointer(&"sfx", bank, address)
			if sound.is_empty() and address >= 0:
				sound = data.world_audio(&"sfx", address)
			return sound
		&"cry":
			return data.world_audio(&"cries", int(values.get("cry_id", -1)))
		&"warp_sound":
			var collision: int = int(values.get("collision", -1))
			var warp_sfx: int = 0x23
			if collision == 0x71:
				warp_sfx = 0x1F
			elif collision == 0x7C:
				warp_sfx = 0x13
			return data.world_audio(&"sfx", warp_sfx)
		&"special_sound":
			var item: Dictionary = data.item(int(values.get("item", 0)))
			var item_sfx: int = 0x9B if int(item.get("pocket", 0)) == 4 else 0x01
			return data.world_audio(&"sfx", item_sfx)
		&"sound_wait":
			return {"kind": &"sound_wait"}
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
