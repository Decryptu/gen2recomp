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
var _repel_steps: int = 0
var _swarm_map: Vector2i = Vector2i(-1, -1)
var _fishing_swarm_species: int = 0
var _roaming_mons: Array = []


func _init(
	event_flags: Dictionary = {}, map_scenes: Dictionary = {}, items: Dictionary = {},
	money: Dictionary = {}, coins: int = 0, phone_contacts: Dictionary = {},
	repel_steps: int = 0, swarm_map: Vector2i = Vector2i(-1, -1),
	fishing_swarm_species: int = 0, roaming_mons: Array = [],
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
	_repel_steps = maxi(0, repel_steps)
	_swarm_map = swarm_map
	_fishing_swarm_species = fishing_swarm_species if fishing_swarm_species in [0, 0xD3, 0xDF] else 0
	_roaming_mons = _copy_roaming_mons(roaming_mons)


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


func repel_steps() -> int:
	return _repel_steps


func set_repel_steps(steps: int) -> void:
	var next_steps: int = maxi(0, steps)
	if next_steps == _repel_steps:
		return
	_repel_steps = next_steps
	changed.emit()


func consume_repel_step() -> void:
	if _repel_steps <= 0:
		return
	_repel_steps -= 1
	changed.emit()


func swarm_map() -> Vector2i:
	return _swarm_map


func set_swarm_map(map_id: Vector2i, active: bool = true, fishing_species: int = 0) -> void:
	var next_map: Vector2i = map_id if active else Vector2i(-1, -1)
	var next_species: int = fishing_species if fishing_species in [0, 0xD3, 0xDF] else 0
	if _swarm_map == next_map and _fishing_swarm_species == next_species:
		return
	_swarm_map = next_map
	_fishing_swarm_species = next_species
	changed.emit()


func swarm_active_on(map_group: int, map_number: int) -> bool:
	return _swarm_map == Vector2i(map_group, map_number)


func fishing_swarm_species() -> int:
	return _fishing_swarm_species


func ensure_roaming_mons(source: Array) -> void:
	if not _roaming_mons.is_empty() or source.is_empty():
		return
	_roaming_mons = _copy_roaming_mons(source)
	changed.emit()


func roaming_mons() -> Array:
	return _copy_roaming_mons(_roaming_mons)


func roaming_mons_on(map_group: int, map_number: int) -> Array:
	var out: Array = []
	for index: int in _roaming_mons.size():
		var mon: Dictionary = _roaming_mons[index]
		if int(mon.get("map_group", -1)) != map_group or int(mon.get("map_number", -1)) != map_number:
			continue
		var value: Dictionary = mon.duplicate(true)
		value["index"] = index
		out.append(value)
	return out


## Advances each active roaming Pokémon using the source's connected-map
## selection. A zero in the source's five-bit mask performs a random jump to a
## roaming map; otherwise the low two bits select one of the current row's
## connections and retry when that index is absent.
func advance_roaming(map_rows: Array, random: RandomNumberGenerator = null) -> Array:
	if _roaming_mons.is_empty() or map_rows.is_empty():
		return []
	var generator := random if random != null else RandomNumberGenerator.new()
	if random == null:
		generator.randomize()
	var moved: Array = []
	var changed_state: bool = false
	for index: int in _roaming_mons.size():
		var mon: Dictionary = _roaming_mons[index]
		var current := Vector2i(int(mon.get("map_group", -1)), int(mon.get("map_number", -1)))
		var target: Vector2i = _roaming_target(map_rows, current, generator)
		if target == Vector2i(-1, -1):
			continue
		if target == current:
			continue
		mon["map_group"] = target.x
		mon["map_number"] = target.y
		changed_state = true
		moved.append({
			"index": index,
			"species": int(mon.get("species", 0)),
			"from": current,
			"to": target,
		})
	if changed_state:
		changed.emit()
	return moved


static func map_scene_key(map_group: int, map_number: int) -> String:
	return "%d:%d" % [map_group, map_number]


func map_scene(map_group: int, map_number: int) -> int:
	return int(_map_scenes.get(map_scene_key(map_group, map_number), 0))


func map_scenes() -> Dictionary:
	return _map_scenes.duplicate()


func _copy_roaming_mons(source: Array) -> Array:
	var out: Array = []
	for raw: Variant in source:
		if raw is Dictionary:
			out.append((raw as Dictionary).duplicate(true))
	return out


func _roaming_target(
	map_rows: Array, current: Vector2i, random: RandomNumberGenerator
) -> Vector2i:
	for _attempt: int in 128:
		var roll: int = random.randi_range(0, 255)
		if (roll & 0x1F) == 0:
			for _jump_attempt: int in 128:
				var random_row: Dictionary = map_rows[random.randi_range(0, map_rows.size() - 1)]
				var jump := Vector2i(
					int(random_row.get("map_group", -1)), int(random_row.get("map_number", -1))
				)
				if jump != current:
					return jump
			continue
		var row: Dictionary = {}
		for raw: Variant in map_rows:
			if not raw is Dictionary:
				continue
			if int(raw.get("map_group", -1)) == current.x \
				and int(raw.get("map_number", -1)) == current.y:
				row = raw
				break
		var connections: Variant = row.get("connections", [])
		var connection_index: int = roll & 0x03
		if not connections is Array or connection_index >= (connections as Array).size():
			continue
		var target: Dictionary = (connections as Array)[connection_index]
		var next := Vector2i(
			int(target.get("map_group", -1)), int(target.get("map_number", -1))
		)
		if next != current:
			return next
	return Vector2i(-1, -1)


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
