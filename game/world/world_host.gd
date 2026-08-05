class_name Gen2WorldHost
extends RefCounted

## Scene-free policy boundary for requests that need a host subsystem.
## Only battle and swarm currently have complete runtime adapters. All other
## requests remain pending with a specific reason rather than being guessed or
## acknowledged as if the subsystem had run.

static func complete_runtime_request(world: Gen2WorldAPI, result: Dictionary) -> Dictionary:
	if world == null:
		return _unavailable(&"missing_world", {})
	var request: Dictionary = world.pending_runtime_request()
	if request.is_empty():
		return _unavailable(&"runtime_request_not_pending", {})
	var kind: StringName = StringName(request.get("kind", &""))
	if kind in [&"battle_requested", &"swarm_requested"]:
		return {"ok": true, "handled": true, "results": world.complete_runtime_request(result)}
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


static func _unavailable(reason: StringName, request: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"handled": false,
		"status": &"host_unavailable",
		"reason": reason,
		"request": request.duplicate(true),
	}
