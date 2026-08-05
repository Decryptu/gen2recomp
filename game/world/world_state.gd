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
var _items: Dictionary = {}
var _money: Dictionary = {}
var _coins: int = 0
var _phone_contacts: Dictionary = {}
var _just_battled: bool = false


func _init(
	event_flags: Dictionary = {}, map_scenes: Dictionary = {}, items: Dictionary = {},
	money: Dictionary = {}, coins: int = 0, phone_contacts: Dictionary = {},
) -> void:
	for flag: Variant in event_flags:
		if int(flag) > 0 and bool(event_flags[flag]):
			_event_flags[int(flag)] = true
	for map_key: Variant in map_scenes:
		var scene: int = int(map_scenes[map_key])
		if scene >= 0:
			_map_scenes[String(map_key)] = scene
	for raw_item: Variant in items:
		var item: int = int(raw_item)
		var quantity: int = int(items[raw_item])
		if item > 0 and quantity > 0:
			_items[item] = quantity
	for raw_account: Variant in money:
		var account: int = int(raw_account)
		var balance: int = int(money[raw_account])
		if account >= 0 and balance > 0:
			_money[account] = balance
	_coins = maxi(0, coins)
	for raw_contact: Variant in phone_contacts:
		if bool(phone_contacts[raw_contact]):
			_phone_contacts[int(raw_contact)] = true


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


func item_quantity(item: int) -> int:
	return int(_items.get(item, 0))


func items() -> Dictionary:
	return _items.duplicate()


func money(account: int = 0) -> int:
	return int(_money.get(account, 0))


func money_balances() -> Dictionary:
	return _money.duplicate()


func coins() -> int:
	return _coins


func phone_contacts() -> Dictionary:
	return _phone_contacts.duplicate()


func has_phone_contact(contact: int) -> bool:
	return bool(_phone_contacts.get(contact, false))


func just_battled() -> bool:
	return _just_battled


static func map_scene_key(map_group: int, map_number: int) -> String:
	return "%d:%d" % [map_group, map_number]


func map_scene(map_group: int, map_number: int) -> int:
	return int(_map_scenes.get(map_scene_key(map_group, map_number), 0))


func map_scenes() -> Dictionary:
	return _map_scenes.duplicate()


## Applies a script's staged state as one transaction. Validation happens before
## either dictionary is replaced, so a failed script cannot leave half a flag
## transition behind.
func apply_changes(
	flag_changes: Dictionary, scene_changes: Dictionary, runtime_changes: Dictionary = {}
) -> Dictionary:
	for raw_flag: Variant in flag_changes:
		if int(raw_flag) <= 0:
			return {"ok": false, "reason": &"invalid_event_flag"}
	for raw_map: Variant in scene_changes:
		if String(raw_map).is_empty() or int(scene_changes[raw_map]) < 0:
			return {"ok": false, "reason": &"invalid_scene"}
	var item_changes: Dictionary = runtime_changes.get("items", {})
	if not item_changes is Dictionary:
		return {"ok": false, "reason": &"invalid_items"}
	for raw_item: Variant in item_changes:
		if int(raw_item) <= 0 or int(item_changes[raw_item]) < 0:
			return {"ok": false, "reason": &"invalid_item_quantity"}
	var money_changes: Dictionary = runtime_changes.get("money", {})
	if not money_changes is Dictionary:
		return {"ok": false, "reason": &"invalid_money"}
	for raw_account: Variant in money_changes:
		if int(raw_account) < 0 or int(money_changes[raw_account]) < 0:
			return {"ok": false, "reason": &"invalid_money_balance"}
	var next_coins: int = int(runtime_changes.get("coins", _coins))
	if next_coins < 0:
		return {"ok": false, "reason": &"invalid_coins"}
	var phone_changes: Dictionary = runtime_changes.get("phone_contacts", {})
	if not phone_changes is Dictionary:
		return {"ok": false, "reason": &"invalid_phone_contacts"}
	for raw_contact: Variant in phone_changes:
		if int(raw_contact) < 0:
			return {"ok": false, "reason": &"invalid_phone_contact"}

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
	var next_items: Dictionary = _items.duplicate()
	for raw_item: Variant in item_changes:
		var item: int = int(raw_item)
		var quantity: int = int(item_changes[raw_item])
		if quantity == 0:
			next_items.erase(item)
		else:
			next_items[item] = quantity
	var next_money: Dictionary = _money.duplicate()
	for raw_account: Variant in money_changes:
		var account: int = int(raw_account)
		var balance: int = int(money_changes[raw_account])
		if balance == 0:
			next_money.erase(account)
		else:
			next_money[account] = balance
	var next_contacts: Dictionary = _phone_contacts.duplicate()
	for raw_contact: Variant in phone_changes:
		var contact: int = int(raw_contact)
		if bool(phone_changes[raw_contact]):
			next_contacts[contact] = true
		else:
			next_contacts.erase(contact)
	var next_just_battled: bool = bool(
		runtime_changes.get("just_battled", _just_battled)
	)

	var did_change: bool = next_flags != _event_flags or next_scenes != _map_scenes \
		or next_items != _items or next_money != _money or next_coins != _coins \
		or next_contacts != _phone_contacts or next_just_battled != _just_battled
	_event_flags = next_flags
	_map_scenes = next_scenes
	_items = next_items
	_money = next_money
	_coins = next_coins
	_phone_contacts = next_contacts
	_just_battled = next_just_battled
	if did_change:
		changed.emit()
	return {"ok": true, "changed": did_change}
