class_name Gen2WorldState
extends RefCounted

## Mutable state shared by the scene-free overworld systems.
##
## Cartridge-derived map records remain immutable in GameData. This record is
## the runtime boundary for event flags and can later be serialized by the
## save model without making Gen2WorldAPI own a save file.

signal changed

const PHONE_CONTACT_CAPACITY: int = 10
const PHONE_RECEIVE_DELAYS: Array[int] = [20, 10, 5, 3]
const TEMPORARY_MAP_RELOAD_FLAGS: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
## Crystal maps STATUSFLAGS_HALL_OF_FAME_F through the source engine flag
## table to ENGINE_CREDITS_SKIP, and the Goldenrod bargain merchant uses the
## daily ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED flag. Both names are
## Crystal indices, called out explicitly because pokegold's shorter engine
## flag table (see the badge comment below) puts the same symbol one index
## lower there.
const ENGINE_CREDITS_SKIP: int = 15
const ENGINE_HALL_OF_FAME: int = ENGINE_CREDITS_SKIP
const ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED: int = 86
const ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED_GOLD_SILVER: int = 85

## wBadges spans wJohtoBadges then wKantoBadges as one contiguous flag_array;
## VAR_BADGES counts both bytes together, not Johto alone. These are Crystal
## indices. pokegold's constants/engine_flags.asm has no ENGINE_MOBILE_SYSTEM
## entry, which pokecrystal inserts ahead of the badge section, so every
## pokegold badge (and the merchant flag above) sits exactly one index lower
## than the same symbol here; `_GetVarAction.CountBadges` and the flag order
## are otherwise identical between the two games.
const ENGINE_ZEPHYRBADGE: int = 27
const ENGINE_HIVEBADGE: int = 28
const ENGINE_PLAINBADGE: int = 29
const ENGINE_FOGBADGE: int = 30
const ENGINE_MINERALBADGE: int = 31
const ENGINE_STORMBADGE: int = 32
const ENGINE_GLACIERBADGE: int = 33
const ENGINE_RISINGBADGE: int = 34
const ENGINE_BOULDERBADGE: int = 35
const ENGINE_CASCADEBADGE: int = 36
const ENGINE_THUNDERBADGE: int = 37
const ENGINE_RAINBOWBADGE: int = 38
const ENGINE_SOULBADGE: int = 39
const ENGINE_MARSHBADGE: int = 40
const ENGINE_VOLCANOBADGE: int = 41
const ENGINE_EARTHBADGE: int = 42
const BADGE_ENGINE_FLAGS: Array[int] = [
	ENGINE_ZEPHYRBADGE, ENGINE_HIVEBADGE, ENGINE_PLAINBADGE, ENGINE_FOGBADGE,
	ENGINE_MINERALBADGE, ENGINE_STORMBADGE, ENGINE_GLACIERBADGE, ENGINE_RISINGBADGE,
	ENGINE_BOULDERBADGE, ENGINE_CASCADEBADGE, ENGINE_THUNDERBADGE, ENGINE_RAINBOWBADGE,
	ENGINE_SOULBADGE, ENGINE_MARSHBADGE, ENGINE_VOLCANOBADGE, ENGINE_EARTHBADGE,
]
const BADGE_ENGINE_FLAGS_GOLD_SILVER: Array[int] = [
	ENGINE_ZEPHYRBADGE - 1, ENGINE_HIVEBADGE - 1, ENGINE_PLAINBADGE - 1, ENGINE_FOGBADGE - 1,
	ENGINE_MINERALBADGE - 1, ENGINE_STORMBADGE - 1, ENGINE_GLACIERBADGE - 1, ENGINE_RISINGBADGE - 1,
	ENGINE_BOULDERBADGE - 1, ENGINE_CASCADEBADGE - 1, ENGINE_THUNDERBADGE - 1, ENGINE_RAINBOWBADGE - 1,
	ENGINE_SOULBADGE - 1, ENGINE_MARSHBADGE - 1, ENGINE_VOLCANOBADGE - 1, ENGINE_EARTHBADGE - 1,
]

var _event_flags: Dictionary = {}
var _engine_flags: Dictionary = {}
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
var _seen_species: Dictionary = {}
var _phone_receive_cycle: int = 0
var _phone_receive_minutes: int = PHONE_RECEIVE_DELAYS[0]
var _pending_special_phone_call: int = 0


func _init(
	initial_event_flags: Dictionary = {}, initial_map_scenes: Dictionary = {},
	initial_items: Dictionary = {}, initial_money: Dictionary = {}, initial_coins: int = 0,
	initial_phone_contacts: Dictionary = {}, initial_repel_steps: int = 0,
	initial_swarm_map: Vector2i = Vector2i(-1, -1), initial_fishing_swarm_species: int = 0,
	initial_roaming_mons: Array = [], initial_just_battled: bool = false,
	initial_phone_receive_cycle: int = 0, initial_phone_receive_minutes: int = PHONE_RECEIVE_DELAYS[0],
	initial_pending_special_phone_call: int = 0,
	initial_seen_species: Dictionary = {},
	initial_engine_flags: Dictionary = {},
) -> void:
	for flag: Variant in initial_event_flags:
		if int(flag) >= 0 and bool(initial_event_flags[flag]):
			_event_flags[int(flag)] = true
	for flag: Variant in initial_engine_flags:
		if int(flag) >= 0 and bool(initial_engine_flags[flag]):
			_engine_flags[int(flag)] = true
	for map_key: Variant in initial_map_scenes:
		var scene: int = int(initial_map_scenes[map_key])
		if scene >= 0:
			_map_scenes[String(map_key)] = scene
	for raw_item: Variant in initial_items:
		var item: int = int(raw_item)
		var quantity: int = int(initial_items[raw_item])
		if item > 0 and quantity > 0:
			_items[item] = quantity
	for raw_account: Variant in initial_money:
		var account: int = int(raw_account)
		var balance: int = int(initial_money[raw_account])
		if account >= 0 and balance > 0:
			_money[account] = balance
	_coins = maxi(0, initial_coins)
	for raw_contact: Variant in initial_phone_contacts:
		if bool(initial_phone_contacts[raw_contact]) and _phone_contacts.size() < PHONE_CONTACT_CAPACITY:
			_phone_contacts[int(raw_contact)] = true
	_repel_steps = maxi(0, initial_repel_steps)
	_swarm_map = initial_swarm_map
	_fishing_swarm_species = initial_fishing_swarm_species if initial_fishing_swarm_species in [0, 0xD3, 0xDF] else 0
	_roaming_mons = _copy_roaming_mons(initial_roaming_mons)
	for raw_species: Variant in initial_seen_species:
		if int(raw_species) > 0 and bool(initial_seen_species[raw_species]):
			_seen_species[int(raw_species)] = true
	_just_battled = initial_just_battled
	_phone_receive_cycle = clampi(initial_phone_receive_cycle, 0, PHONE_RECEIVE_DELAYS.size() - 1)
	_phone_receive_minutes = maxi(0, initial_phone_receive_minutes)
	_pending_special_phone_call = maxi(0, initial_pending_special_phone_call)


## JSON-safe representation of the mutable overworld state. Cartridge records
## are deliberately absent because they belong to GameData, not a save.
func to_dict() -> Dictionary:
	return {
		"event_flags": _event_flags.duplicate(),
		"engine_flags": _engine_flags.duplicate(),
		"map_scenes": _map_scenes.duplicate(),
		"items": _items.duplicate(),
		"money": _money.duplicate(),
		"coins": _coins,
		"phone_contacts": _phone_contacts.duplicate(),
		"just_battled": _just_battled,
		"repel_steps": _repel_steps,
		"swarm_map": [_swarm_map.x, _swarm_map.y],
		"fishing_swarm_species": _fishing_swarm_species,
		"roaming_mons": _copy_roaming_mons(_roaming_mons),
		"seen_species": _seen_species.duplicate(),
		"phone_receive_cycle": _phone_receive_cycle,
		"phone_receive_minutes": _phone_receive_minutes,
		"pending_special_phone_call": _pending_special_phone_call,
	}


## Rehydrates only the bounded state shape. The selected GameData remains
## responsible for validating map, item and species references at save load.
static func from_dict(raw: Variant) -> Gen2WorldState:
	if not raw is Dictionary:
		return Gen2WorldState.new()
	var source: Dictionary = raw
	var swarm: Vector2i = _vector_from_value(source.get("swarm_map", [-1, -1]))
	return Gen2WorldState.new(
		source.get("event_flags", {}) if source.get("event_flags", {}) is Dictionary else {},
		source.get("map_scenes", {}) if source.get("map_scenes", {}) is Dictionary else {},
		source.get("items", {}) if source.get("items", {}) is Dictionary else {},
		source.get("money", {}) if source.get("money", {}) is Dictionary else {},
		int(source.get("coins", 0)),
		source.get("phone_contacts", {}) if source.get("phone_contacts", {}) is Dictionary else {},
		int(source.get("repel_steps", 0)), swarm,
		int(source.get("fishing_swarm_species", 0)),
		source.get("roaming_mons", []) if source.get("roaming_mons", []) is Array else [],
		bool(source.get("just_battled", false)),
		int(source.get("phone_receive_cycle", 0)),
		int(source.get("phone_receive_minutes", PHONE_RECEIVE_DELAYS[0])),
		int(source.get("pending_special_phone_call", 0)),
		source.get("seen_species", {}) if source.get("seen_species", {}) is Dictionary else {},
		source.get("engine_flags", {}) if source.get("engine_flags", {}) is Dictionary else {},
	)


## Restores the mutable state after a host transaction could not be persisted.
## The state object stays alive so existing world systems keep their signal
## connection.
func restore_from_dict(raw: Variant) -> void:
	var restored: Gen2WorldState = Gen2WorldState.from_dict(raw)
	if restored == null:
		return
	_event_flags = restored._event_flags.duplicate()
	_engine_flags = restored._engine_flags.duplicate()
	_map_scenes = restored._map_scenes.duplicate()
	_items = restored._items.duplicate()
	_money = restored._money.duplicate()
	_coins = restored._coins
	_phone_contacts = restored._phone_contacts.duplicate()
	_just_battled = restored._just_battled
	_repel_steps = restored._repel_steps
	_swarm_map = restored._swarm_map
	_fishing_swarm_species = restored._fishing_swarm_species
	_roaming_mons = _copy_roaming_mons(restored._roaming_mons)
	_seen_species = restored._seen_species.duplicate()
	_phone_receive_cycle = restored._phone_receive_cycle
	_phone_receive_minutes = restored._phone_receive_minutes
	_pending_special_phone_call = restored._pending_special_phone_call
	changed.emit()


static func _vector_from_value(value: Variant) -> Vector2i:
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	if value is Dictionary:
		return Vector2i(int((value as Dictionary).get("x", -1)), int((value as Dictionary).get("y", -1)))
	return Vector2i(-1, -1)


func is_event_flag_active(flag: int) -> bool:
	return flag >= 0 and bool(_event_flags.get(flag, false))


func set_event_flag(flag: int, active: bool = true) -> void:
	if flag < 0:
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


func is_engine_flag_active(flag: int) -> bool:
	return flag >= 0 and bool(_engine_flags.get(flag, false))


func set_engine_flag(flag: int, active: bool = true) -> void:
	if flag < 0:
		return
	var was_active: bool = is_engine_flag_active(flag)
	if was_active == active:
		return
	if active:
		_engine_flags[flag] = true
	else:
		_engine_flags.erase(flag)
	changed.emit()


func clear_engine_flag(flag: int) -> void:
	set_engine_flag(flag, false)


func engine_flags() -> Dictionary:
	return _engine_flags.duplicate()


func hall_of_fame() -> bool:
	return is_engine_flag_active(ENGINE_HALL_OF_FAME)


func set_hall_of_fame(active: bool = true) -> void:
	set_engine_flag(ENGINE_HALL_OF_FAME, active)


## `crystal` selects which game's engine flag table this state's raw flag
## numbers were written against; pass [method is_crystal_profile] with the
## active GameData. Defaults to Crystal, matching every existing caller.
func bargain_merchant_closed(crystal: bool = true) -> bool:
	return is_engine_flag_active(_merchant_closed_flag(crystal))


## Mirrors _GetVarAction's .CountBadges: a popcount over both badge bytes.
func badge_count(crystal: bool = true) -> int:
	var count: int = 0
	for flag: int in (BADGE_ENGINE_FLAGS if crystal else BADGE_ENGINE_FLAGS_GOLD_SILVER):
		if is_engine_flag_active(flag):
			count += 1
	return count


## Clears only source daily engine flags. Story flags such as Hall of Fame
## survive the day boundary.
func reset_daily_flags(crystal: bool = true) -> bool:
	var did_change: bool = false
	for flag: int in [_merchant_closed_flag(crystal)]:
		if not _engine_flags.has(flag):
			continue
		_engine_flags.erase(flag)
		did_change = true
	if did_change:
		changed.emit()
	return did_change


func _merchant_closed_flag(crystal: bool) -> int:
	return ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED if crystal \
		else ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED_GOLD_SILVER


## True unless [param data] is a verified Gold or Silver cache, matching
## Gen2WorldScriptRunner._crystal_commands(). Both engine flag tables and
## `_GetVarAction.CountBadges` agree on everything except this table's
## offset, so every profile-dependent flag lookup here keys off the same
## question the script command-width split already answers.
static func is_crystal_profile(data: GameData) -> bool:
	return data == null or (data.id != &"gold" and data.id != &"silver")


## The source resets its first eight event flags whenever a map reloads. These
## flags are used for temporary movement and scene branches, so they are not
## part of a permanent story save.
func reset_map_reload_flags() -> bool:
	var did_change: bool = false
	for flag: int in TEMPORARY_MAP_RELOAD_FLAGS:
		if not _event_flags.has(flag):
			continue
		_event_flags.erase(flag)
		did_change = true
	if did_change:
		changed.emit()
	return did_change


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


func phone_contact_count() -> int:
	return _phone_contacts.size()


func has_phone_contact(contact: int) -> bool:
	return bool(_phone_contacts.get(contact, false))


func phone_receive_cycle() -> int:
	return _phone_receive_cycle


func phone_receive_minutes() -> int:
	return _phone_receive_minutes


func pending_special_phone_call() -> int:
	return _pending_special_phone_call


func reset_phone_receive_delay() -> void:
	_phone_receive_cycle = 0
	_phone_receive_minutes = PHONE_RECEIVE_DELAYS[0]
	changed.emit()


func advance_phone_receive_timer(minutes: int) -> bool:
	if _phone_receive_minutes <= 0:
		return false
	var ready: bool = false
	for _minute: int in maxi(0, minutes):
		_phone_receive_minutes = maxi(0, _phone_receive_minutes - 1)
		if _phone_receive_minutes > 0:
			continue
		ready = true
	if ready:
		changed.emit()
	return ready


func phone_receive_ready() -> bool:
	return _phone_receive_minutes <= 0


func consume_phone_receive_timer() -> bool:
	if not phone_receive_ready():
		return false
	_phone_receive_cycle = mini(_phone_receive_cycle + 1, PHONE_RECEIVE_DELAYS.size() - 1)
	_phone_receive_minutes = PHONE_RECEIVE_DELAYS[_phone_receive_cycle]
	changed.emit()
	return true


func set_pending_special_phone_call(call_id: int) -> bool:
	var next_call_id: int = maxi(0, call_id)
	if next_call_id == _pending_special_phone_call:
		return false
	_pending_special_phone_call = next_call_id
	changed.emit()
	return true


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


func has_seen_species(species: int) -> bool:
	return species > 0 and bool(_seen_species.get(species, false))


func seen_species() -> Dictionary:
	return _seen_species.duplicate()


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
		if int(raw_flag) < 0:
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
	var engine_flag_changes: Dictionary = runtime_changes.get("engine_flags", {})
	if not engine_flag_changes is Dictionary:
		return {"ok": false, "reason": &"invalid_engine_flags"}
	for raw_flag: Variant in engine_flag_changes:
		if int(raw_flag) < 0:
			return {"ok": false, "reason": &"invalid_engine_flag"}
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
	var next_receive_cycle: int = int(
		runtime_changes.get("phone_receive_cycle", _phone_receive_cycle)
	)
	if next_receive_cycle < 0 or next_receive_cycle >= PHONE_RECEIVE_DELAYS.size():
		return {"ok": false, "reason": &"invalid_phone_receive_cycle"}
	var next_receive_minutes: int = int(
		runtime_changes.get("phone_receive_minutes", _phone_receive_minutes)
	)
	if next_receive_minutes < 0:
		return {"ok": false, "reason": &"invalid_phone_receive_minutes"}
	var next_special_phone_call: int = int(
		runtime_changes.get("pending_special_phone_call", _pending_special_phone_call)
	)
	if next_special_phone_call < 0:
		return {"ok": false, "reason": &"invalid_special_phone_call"}
	var swarm_change: Variant = runtime_changes.get("swarm", null)
	if swarm_change != null and not swarm_change is Dictionary:
		return {"ok": false, "reason": &"invalid_swarm"}
	var next_swarm_map: Vector2i = _swarm_map
	var next_fishing_swarm_species: int = _fishing_swarm_species
	if swarm_change is Dictionary:
		var swarm: Dictionary = swarm_change
		var swarm_active: bool = bool(swarm.get("active", true))
		var swarm_group: int = int(swarm.get("map_group", -1))
		var swarm_number: int = int(swarm.get("map_number", -1))
		if swarm_active and (swarm_group < 0 or swarm_number < 0):
			return {"ok": false, "reason": &"invalid_swarm_map"}
		var swarm_species: int = int(swarm.get("fishing_species", 0))
		if swarm_species not in [0, 0xD3, 0xDF]:
			return {"ok": false, "reason": &"invalid_fishing_swarm_species"}
		next_swarm_map = Vector2i(swarm_group, swarm_number) if swarm_active else Vector2i(-1, -1)
		next_fishing_swarm_species = swarm_species
	var next_repel_steps: int = int(runtime_changes.get("repel_steps", _repel_steps))
	if next_repel_steps < 0:
		return {"ok": false, "reason": &"invalid_repel_steps"}
	var seen_changes: Dictionary = runtime_changes.get("seen_species", {})
	if not seen_changes is Dictionary:
		return {"ok": false, "reason": &"invalid_seen_species"}
	for raw_species: Variant in seen_changes:
		if int(raw_species) <= 0:
			return {"ok": false, "reason": &"invalid_seen_species"}

	var next_flags: Dictionary = _event_flags.duplicate()
	for raw_flag: Variant in flag_changes:
		var flag: int = int(raw_flag)
		if bool(flag_changes[raw_flag]):
			next_flags[flag] = true
		else:
			next_flags.erase(flag)
	var next_engine_flags: Dictionary = _engine_flags.duplicate()
	for raw_flag: Variant in engine_flag_changes:
		var engine_flag: int = int(raw_flag)
		if bool(engine_flag_changes[raw_flag]):
			next_engine_flags[engine_flag] = true
		else:
			next_engine_flags.erase(engine_flag)
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
	var next_seen_species: Dictionary = _seen_species.duplicate()
	for raw_species: Variant in seen_changes:
		var species: int = int(raw_species)
		if bool(seen_changes[raw_species]):
			next_seen_species[species] = true
		else:
			next_seen_species.erase(species)
	var next_contacts: Dictionary = _phone_contacts.duplicate()
	for raw_contact: Variant in phone_changes:
		var contact: int = int(raw_contact)
		if bool(phone_changes[raw_contact]):
			next_contacts[contact] = true
		else:
			next_contacts.erase(contact)
	if next_contacts.size() > PHONE_CONTACT_CAPACITY:
		return {"ok": false, "reason": &"phone_contact_capacity"}
	var next_just_battled: bool = bool(
		runtime_changes.get("just_battled", _just_battled)
	)

	var did_change: bool = next_flags != _event_flags or next_engine_flags != _engine_flags \
		or next_scenes != _map_scenes \
		or next_items != _items or next_money != _money or next_coins != _coins \
		or next_contacts != _phone_contacts or next_just_battled != _just_battled \
		or next_seen_species != _seen_species \
		or next_repel_steps != _repel_steps or next_swarm_map != _swarm_map \
		or next_fishing_swarm_species != _fishing_swarm_species \
		or next_receive_cycle != _phone_receive_cycle \
		or next_receive_minutes != _phone_receive_minutes \
		or next_special_phone_call != _pending_special_phone_call
	_event_flags = next_flags
	_engine_flags = next_engine_flags
	_map_scenes = next_scenes
	_items = next_items
	_money = next_money
	_seen_species = next_seen_species
	_coins = next_coins
	_phone_contacts = next_contacts
	_just_battled = next_just_battled
	_repel_steps = next_repel_steps
	_swarm_map = next_swarm_map
	_fishing_swarm_species = next_fishing_swarm_species
	_phone_receive_cycle = next_receive_cycle
	_phone_receive_minutes = next_receive_minutes
	_pending_special_phone_call = next_special_phone_call
	if did_change:
		changed.emit()
	return {"ok": true, "changed": did_change}
