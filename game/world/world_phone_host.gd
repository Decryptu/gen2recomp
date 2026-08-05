class_name Gen2WorldPhoneHost
extends RefCounted

## Source-faithful phone policy and presentation data. The host does not mutate
## world state. It selects a cartridge script, and the script runner commits any
## resulting flags or phone registrations at its normal transaction boundary.

const TIME_MORNING: int = 1
const TIME_DAY: int = 2
const TIME_NIGHT: int = 4
const TIME_ANY: int = TIME_MORNING | TIME_DAY | TIME_NIGHT
const ENVIRONMENT_TOWN: int = 1
const ENVIRONMENT_ROUTE: int = 2

const CONDITION_OUTSIDE: StringName = &"outside"
const CONDITION_ANYWHERE: StringName = &"anywhere"


static func time_mask_for_hour(hour: int) -> int:
	var normalized: int = posmod(hour, 24)
	if normalized < 4:
		return TIME_NIGHT
	if normalized < 10:
		return TIME_MORNING
	if normalized < 18:
		return TIME_DAY
	return TIME_NIGHT


static func time_mask_matches(mask: int, hour: int) -> bool:
	return (mask & time_mask_for_hour(hour) & TIME_ANY) != 0


static func map_has_phone_service(map: Gen2WorldMap) -> bool:
	## Map macro comment: TRUE prevents phone calls. The importer stores this
	## field as phone_flag, so zero is the service-enabled state.
	return map != null and map.phone_flag == 0


static func is_outside_environment(environment: int) -> bool:
	return environment in [ENVIRONMENT_TOWN, ENVIRONMENT_ROUTE]


static func contact_summary(data: GameData, contact: Dictionary) -> Dictionary:
	if data == null or contact.is_empty():
		return {}
	var trainer_class: int = int(contact.get("trainer_class", 0))
	return {
		"index": int(contact.get("index", -1)),
		"trainer_class": trainer_class,
		"trainer_name": data.trainer_name(trainer_class),
		"trainer_number": int(contact.get("trainer_number", 0)),
		"map_group": int(contact.get("map_group", -1)),
		"map_number": int(contact.get("map_number", -1)),
		"callee_time": int(contact.get("callee_time", 0)),
		"caller_time": int(contact.get("caller_time", 0)),
		"callee_script": (contact.get("callee_script", {}) as Dictionary).duplicate(true),
		"caller_script": (contact.get("caller_script", {}) as Dictionary).duplicate(true),
	}


static func special_call_summary(data: GameData, call: Dictionary) -> Dictionary:
	if data == null or call.is_empty():
		return {}
	return {
		"index": int(call.get("index", -1)),
		"condition": int(call.get("condition", 0)),
		"condition_kind": StringName(call.get("condition_kind", &"unknown")),
		"contact": int(call.get("contact", -1)),
		"script": (call.get("script", {}) as Dictionary).duplicate(true),
	}


static func available_incoming_contacts(
	data: GameData, state: Gen2WorldState, map: Gen2WorldMap, hour: int
) -> Array:
	if data == null or state == null or not map_has_phone_service(map):
		return []
	var available: Array = []
	for index: int in data.world_phone_contact_count():
		if not state.has_phone_contact(index):
			continue
		var contact: Dictionary = data.world_phone_contact(index)
		if contact.is_empty() or not time_mask_matches(int(contact.get("callee_time", 0)), hour):
			continue
		if int(contact.get("map_group", -1)) == map.group \
			and int(contact.get("map_number", -1)) == map.number:
			continue
		available.append(contact)
	return available


static func resolve_incoming(
	data: GameData,
	state: Gen2WorldState,
	map: Gen2WorldMap,
	hour: int,
	standing_on_entrance: bool = true,
	timer_ready: bool = true,
	random_byte: int = 0,
	force: bool = false,
	selection_byte: int = 0,
) -> Dictionary:
	if data == null or state == null or not map_has_phone_service(map):
		return _phone_unavailable(&"phone_service_unavailable")
	if not standing_on_entrance:
		return _phone_unavailable(&"not_on_entrance")
	if not timer_ready:
		return _phone_unavailable(&"receive_timer_not_ready")
	## CheckPhoneCall accepts only a random byte with its high bit clear, which
	## is the source's 50 percent test after masking the comparison value.
	if not force and (random_byte & 0x80) != 0:
		return _phone_unavailable(&"incoming_roll_failed")
	var available: Array = available_incoming_contacts(data, state, map, hour)
	if available.is_empty():
		return _phone_unavailable(&"no_available_caller")
	var selected: Dictionary = available[posmod(selection_byte, available.size())]
	return {
		"ok": true,
		"contact": selected.duplicate(true),
		"contact_id": int(selected.get("index", -1)),
		"role": &"callee",
		"script": (selected.get("callee_script", {}) as Dictionary).duplicate(true),
		"phone": {
			"contact_id": int(selected.get("index", -1)),
			"caller_id": int(selected.get("index", -1)),
			"role": &"incoming",
		},
	}


static func resolve_outgoing(
	data: GameData, state: Gen2WorldState, map: Gen2WorldMap, contact_id: int, hour: int
) -> Dictionary:
	if data == null or state == null or not map_has_phone_service(map):
		return _phone_unavailable(&"phone_service_unavailable")
	if contact_id < 0 or not state.has_phone_contact(contact_id):
		return _phone_unavailable(&"phone_number_not_registered")
	var contact: Dictionary = data.world_phone_contact(contact_id)
	if contact.is_empty():
		return _phone_unavailable(&"phone_contact_missing")
	if not time_mask_matches(int(contact.get("caller_time", 0)), hour):
		return _phone_unavailable(&"caller_unavailable_at_this_time")
	if int(contact.get("map_group", -1)) == map.group \
		and int(contact.get("map_number", -1)) == map.number:
		## The cartridge routes this case to PhoneScript_JustTalkToThem. That
		## standard script is not part of the phone table, so keep the boundary
		## explicit until the standard-script host exposes it.
		return _phone_unavailable(&"same_map_phone_script_unavailable")
	return {
		"ok": true,
		"contact": contact.duplicate(true),
		"contact_id": contact_id,
		"role": &"caller",
		"script": (contact.get("caller_script", {}) as Dictionary).duplicate(true),
		"phone": {
			"contact_id": contact_id,
			"caller_id": contact_id,
			"role": &"outgoing",
		},
	}


static func resolve_special(
	data: GameData, map: Gen2WorldMap, call_id: int, hour: int
) -> Dictionary:
	## SPECIALCALL_NONE clears the pending special-call variable and does not
	## ring or run another phone script.
	if call_id == 0:
		return {"ok": true, "clear": true, "call_id": 0}
	if data == null or not map_has_phone_service(map):
		return _phone_unavailable(&"phone_service_unavailable")
	var call: Dictionary = data.world_special_phone_call(call_id - 1)
	if call.is_empty():
		return _phone_unavailable(&"special_phone_call_missing")
	var condition: StringName = StringName(call.get("condition_kind", &"unknown"))
	if condition == &"unknown":
		return _phone_unavailable(&"unknown_special_call_condition")
	if condition == CONDITION_OUTSIDE and not is_outside_environment(map.environment):
		return _phone_unavailable(&"special_call_requires_outside")
	if condition != CONDITION_OUTSIDE and condition != CONDITION_ANYWHERE:
		return _phone_unavailable(&"unsupported_special_call_condition")
	var contact_id: int = int(call.get("contact", -1))
	var contact: Dictionary = data.world_phone_contact(contact_id)
	var script: Dictionary = call.get("script", {})
	if contact.is_empty() or script.is_empty():
		return _phone_unavailable(&"special_phone_call_data_missing")
	return {
		"ok": true,
		"call_id": call_id,
		"special_call": call.duplicate(true),
		"contact": contact,
		"contact_id": contact_id,
		"role": &"callee",
		"script": script.duplicate(true),
		"phone": {
			"contact_id": contact_id,
			"caller_id": contact_id,
			"special_call_id": call_id,
			"role": &"special",
		},
	}


static func _phone_unavailable(reason: StringName) -> Dictionary:
	return {"ok": false, "reason": reason}
