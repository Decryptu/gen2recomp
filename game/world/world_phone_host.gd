class_name Gen2WorldPhoneHost
extends RefCounted

## Read-only presentation data for imported phone requests. Registration itself
## remains a script choice, so the runner owns the event-flag transaction.


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
	}


static func special_call_summary(data: GameData, call: Dictionary) -> Dictionary:
	if data == null or call.is_empty():
		return {}
	return {
		"index": int(call.get("index", -1)),
		"condition": int(call.get("condition", 0)),
		"contact": int(call.get("contact", -1)),
		"script": (call.get("script", {}) as Dictionary).duplicate(true),
	}
