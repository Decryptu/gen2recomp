class_name Gen2WorldState
extends RefCounted

## Mutable state shared by the scene-free overworld systems.
##
## Cartridge-derived map records remain immutable in GameData. This record is
## the runtime boundary for event flags and can later be serialized by the
## save model without making Gen2WorldAPI own a save file.

signal changed

const PHONE_CONTACT_CAPACITY: int = 10
## constants/music_constants.asm. `wMapMusic` starts here and TryRestartMapMusic
## puts it back when a map asks not to restart its own track.
const MUSIC_NONE: int = 0
## `readmem`/`writemem`/`loadmem` address plain WRAM bytes. Only a bounded
## handful of them carry script state (`wFarfetchdPosition`,
## `wUndergroundSwitchPositions`, the phone rematch counters), so they are
## kept as an address-keyed byte map rather than a WRAM image.
const SCRIPT_MEMORY_CAPACITY: int = 64
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
## `CheckReceivedDex`'s own flag, which is what the Pokemon Center PC's list
## selection reads before the Hall of Fame one.
const ENGINE_POKEDEX: int = 11
## The next bit of the same `wStatusFlags` byte, `STATUSFLAGS_UNOWN_DEX_F`, which
## `Pokedex_CheckUnlockedUnownMode` reads and only the Ruins of Alph research
## centre's scientist sets. Ahead of ENGINE_MOBILE_SYSTEM, so it is one index on
## every profile.
const ENGINE_UNOWN_DEX: int = 12
## The one entry pokegold does not ship, and so the index every profile split in
## this table is measured from. See engine_flag().
const ENGINE_MOBILE_SYSTEM: int = 16
## The three wPokegearFlags/wStatusFlags bits the radio card reads
## (data/events/engine_flags.asm). Only the last is profile split, since it sits
## in the wStatusFlags2 run after Crystal's extra entry.
const ENGINE_RADIO_CARD: int = 0
const ENGINE_MAP_CARD: int = 1
const ENGINE_PHONE_CARD: int = 2
const ENGINE_EXPN_CARD: int = 3
const ENGINE_ROCKET_SIGNAL: int = 14
const ENGINE_ROCKETS_IN_RADIO_TOWER: int = 19
const ENGINE_ROCKETS_IN_RADIO_TOWER_GOLD_SILVER: int = 18
const ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED: int = 86
const ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED_GOLD_SILVER: int = 85
## The first entry in the same `wDailyFlags1` byte. `KurtsHouse.asm` sets it
## when the apricorns are handed over and reads it to decide whether the ball is
## ready, so the day boundary is the whole of the errand's wait.
const ENGINE_KURT_MAKING_BALLS: int = 80
## Also `wDailyFlags1`. Not "every tree has fruit" but "the trees have already
## been refilled today": `TryResetFruitTrees` refills them only while this is
## clear, and `ResetFruitTrees` sets it behind itself.
const ENGINE_ALL_FRUIT_TREES: int = 84

## wBikeFlags' BIKEFLAGS_STRENGTH_ACTIVE_F, three engine flags ahead of the badge
## section and so profile split the same way. Nothing in the pinned engine/ or
## home/ ever clears it: SetStrengthFlag is the only writer, so it persists for
## the save across maps, warps and snapshots.
const ENGINE_STRENGTH_ACTIVE: int = 24
const ENGINE_STRENGTH_ACTIVE_GOLD_SILVER: int = 23
## The next flag in the same byte: `BIKEFLAGS_ALWAYS_ON_BIKE_F`, which is the
## whole of `.CantGetOffBike`. `BIKEFLAGS_DOWNHILL_F` follows it and is read by
## `DoPlayerMovement` alone, which no map ever sets.
const ENGINE_ALWAYS_ON_BIKE: int = 25
const ENGINE_ALWAYS_ON_BIKE_GOLD_SILVER: int = 24

## wBadges spans wJohtoBadges then wKantoBadges as one contiguous flag_array, and
## VAR_BADGES counts both bytes, not Johto alone. These are Crystal indices:
## pokegold's constants/engine_flags.asm has no ENGINE_MOBILE_SYSTEM, which
## pokecrystal inserts ahead of the badge section, so every pokegold badge (and
## the merchant flag above) sits one index lower. `_GetVarAction.CountBadges` and
## the flag order are otherwise identical.
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
## `wPCItems`, which is its own array on the cartridge rather than a pocket of
## the bag: `PlayersPC` moves stacks between the two and nothing else reads it.
## Absent in a state written before the item PC existed, which restores as an
## empty PC and needs no migration.
var _pc_items: Dictionary = {}
var _money: Dictionary = {}
var _coins: int = 0
var _phone_contacts: Dictionary = {}
var _just_battled: bool = false
var _repel_steps: int = 0
## `wWildEncounterCooldown`, which `EnterMap` sets to five and every step
## decrements. Scratch on the cartridge rather than saved data, kept here
## because this is where the world's own per-step counters live; a state written
## before it existed restores as zero, which is the value a walk reaches after
## its first four steps anyway.
var _wild_encounter_cooldown: int = 0
## `wStatusFlags`' `STATUSFLAGS_NO_WILD_ENCOUNTERS_F`, which `wildoff` sets and
## `wildon` clears around a scripted sequence.
var _wild_encounters_off: bool = false
## The Bug Catching Contest's own counters. `wParkBallsRemaining` and the clock
## reading `StartBugContestTimer` copies to `wBugContestStartTime`; whether a
## contest is running at all is `ENGINE_BUG_CONTEST_TIMER`, which is an engine
## flag and lives with the rest of them.
var _park_balls: int = 0
var _bug_contest_started: Dictionary = {}
## `wContestMon`, the party-struct-shaped Pokemon `BugContest_SetCaughtContestMon`
## generates. Kept as the fields `ContestScore` reads rather than a whole
## [Gen2BattleMon], because judging is all anything does with it.
var _contest_mon: Dictionary = {}
## `wBugContestSecondPartySpecies`: the byte `ContestDropOffMons` moves out of
## the way so the party is one Pokemon long, and `ContestReturnMons` puts back.
var _contest_second_party_species: int = 0
var _swarm_map: Vector2i = Vector2i(-1, -1)
var _fishing_swarm_species: int = 0
var _roaming_mons: Array = []
var _seen_species: Dictionary = {}
## wPokedexCaught, the second half of `SetSeenAndCaughtMon`. Kept beside the
## seen array rather than derived from the party, because the cartridge's own
## flag survives releasing, trading away or boxing the Pokemon that set it.
var _caught_species: Dictionary = {}
## `wUnownDex`: the Unown forms caught, in catching order rather than by letter,
## and only the ones that reached the party. Twenty-six slots on the cartridge,
## where an empty one is a zero; here the list is as long as it is full, so its
## size is `.count_unown`'s own answer.
var _unown_dex: Array[int] = []
var _phone_receive_cycle: int = 0
var _phone_receive_minutes: int = PHONE_RECEIVE_DELAYS[0]
var _pending_special_phone_call: int = 0
var _script_memory: Dictionary = {}
## `wMapMusic`, `wRadioTuningKnob` and `wCurRadioLine`. The music is state rather
## than something derived from the current map because `PlayMapMusic` writes it
## and compares against it, and because a tuned radio station overwrites it and
## survives the Pokegear closing. `SnorlaxAwake` reads exactly that byte.
## `wStatusFlags`' `STATUSFLAGS_FLASH_F`. Its own byte on the cartridge rather
## than an engine flag, and it does not survive walking out into the open:
## `ResetFlashIfOutOfCave` clears it on entering a ROUTE or a TOWN, so a lit cave
## goes dark again the moment the player leaves and comes back.
var _used_flash: bool = false

var _map_music: int = MUSIC_NONE
var _radio_knob: int = Gen2WorldRadio.KNOB_MIN
var _radio_channel: int = -1
## `wLastDexMode`, which sits in the saved player data beside `wPokegearFlags`
## and `wRadioTuningKnob` rather than in the Pokedex's own cleared block: the
## dex takes its mode from here on opening and writes the mode back on exit.
var _last_dex_mode: int = RomLayout.DEXMODE_NEW
## wDecoBed, wDecoCarpet, wDecoPlant and wDecoPoster. Values are decoration
## ids from data/decorations/decorations.asm, not the blocks they stamp.
var _maptile_decorations: Dictionary = {}
## `wKurtApricornQuantity`. Saved player data, not scratch: `SelectApricornForKurt`
## writes it and `VAR_KURT_APRICORNS` is read a day later, by a different script
## invocation, to size the balls Kurt hands back.
var _kurt_apricorn_quantity: int = 0
## `wFruitTreeFlags`, one bit per `FRUITTREE_*` constant, set by `PickedFruitTree`
## and cleared for every tree at once by `ResetFruitTrees`. Kept as the set of
## picked tree ids because the source's own question is per tree.
var _picked_fruit_trees: Dictionary = {}
## `wRegisteredItem`. `wWhichRegisteredItem`'s pocket and slot number have no
## counterpart in the flat item model: `CheckRegisteredItem` uses them to find
## the entry again in its packed pocket array and clears both when the item is
## not there, which here is the quantity the item number already answers.
var _registered_item: int = 0


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
	initial_script_memory: Dictionary = {},
	initial_caught_species: Dictionary = {},
	initial_maptile_decorations: Dictionary = {},
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
	## Caught implies seen, the way `SetSeenAndCaughtMon` falls through, so a
	## restored state cannot hold a caught species it has not seen.
	for raw_species: Variant in initial_caught_species:
		if int(raw_species) > 0 and bool(initial_caught_species[raw_species]):
			_caught_species[int(raw_species)] = true
			_seen_species[int(raw_species)] = true
	_just_battled = initial_just_battled
	_phone_receive_cycle = clampi(initial_phone_receive_cycle, 0, PHONE_RECEIVE_DELAYS.size() - 1)
	_phone_receive_minutes = maxi(0, initial_phone_receive_minutes)
	_pending_special_phone_call = maxi(0, initial_pending_special_phone_call)
	for raw_address: Variant in initial_script_memory:
		var address: int = int(raw_address)
		var value: int = int(initial_script_memory[raw_address]) & 0xFF
		if address > 0 and value != 0 and _script_memory.size() < SCRIPT_MEMORY_CAPACITY:
			_script_memory[address] = value
	for category: StringName in [&"bed", &"carpet", &"plant", &"poster"]:
		var decoration: int = int(initial_maptile_decorations.get(category, 0))
		if decoration > 0 and decoration <= 0xFF:
			_maptile_decorations[category] = decoration


## JSON-safe representation of the mutable overworld state. Cartridge records
## are deliberately absent because they belong to GameData, not a save.
func to_dict() -> Dictionary:
	return {
		"event_flags": _event_flags.duplicate(),
		"engine_flags": _engine_flags.duplicate(),
		"map_scenes": _map_scenes.duplicate(),
		"items": _items.duplicate(),
		"pc_items": _pc_items.duplicate(),
		"money": _money.duplicate(),
		"coins": _coins,
		"phone_contacts": _phone_contacts.duplicate(),
		"just_battled": _just_battled,
		"repel_steps": _repel_steps,
		"wild_encounter_cooldown": _wild_encounter_cooldown,
		"wild_encounters_off": _wild_encounters_off,
		"park_balls": _park_balls,
		"bug_contest_started": _bug_contest_started.duplicate(),
		"contest_mon": _contest_mon.duplicate(),
		"contest_second_party_species": _contest_second_party_species,
		"swarm_map": [_swarm_map.x, _swarm_map.y],
		"fishing_swarm_species": _fishing_swarm_species,
		"roaming_mons": _copy_roaming_mons(_roaming_mons),
		"seen_species": _seen_species.duplicate(),
		"caught_species": _caught_species.duplicate(),
		"unown_dex": _unown_dex.duplicate(),
		"phone_receive_cycle": _phone_receive_cycle,
		"phone_receive_minutes": _phone_receive_minutes,
		"pending_special_phone_call": _pending_special_phone_call,
		"script_memory": _script_memory.duplicate(),
		"map_music": _map_music,
		"radio_knob": _radio_knob,
		"radio_channel": _radio_channel,
		"last_dex_mode": _last_dex_mode,
		"maptile_decorations": _maptile_decorations.duplicate(),
		"kurt_apricorn_quantity": _kurt_apricorn_quantity,
		"picked_fruit_trees": _picked_fruit_trees.duplicate(),
		"registered_item": _registered_item,
	}


## Rehydrates only the bounded state shape. The selected GameData remains
## responsible for validating map, item and species references at save load.
static func from_dict(raw: Variant) -> Gen2WorldState:
	if not raw is Dictionary:
		return Gen2WorldState.new()
	var source: Dictionary = raw
	var swarm: Vector2i = _vector_from_value(source.get("swarm_map", [-1, -1]))
	var restored: Gen2WorldState = Gen2WorldState.new(
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
		source.get("script_memory", {}) if source.get("script_memory", {}) is Dictionary else {},
		source.get("caught_species", {}) if source.get("caught_species", {}) is Dictionary else {},
		source.get("maptile_decorations", {}) if source.get("maptile_decorations", {}) is Dictionary else {},
	)
	## Absent in a state written before the radio existed. Zero is the same
	## MUSIC_NONE a fresh state starts on, and the next map load writes the real
	## track, so an old save needs no migration.
	var stored_pc_items: Variant = source.get("pc_items", {})
	if stored_pc_items is Dictionary:
		for raw_item: Variant in stored_pc_items as Dictionary:
			var pc_item: int = int(raw_item)
			var pc_quantity: int = int((stored_pc_items as Dictionary)[raw_item])
			if pc_item > 0 and pc_quantity > 0 \
				and restored._pc_items.size() < Gen2WorldPack.MAX_PC_ITEMS:
				restored._pc_items[pc_item] = pc_quantity
	restored._map_music = maxi(0, int(source.get("map_music", MUSIC_NONE)))
	restored.set_radio_knob(int(source.get("radio_knob", Gen2WorldRadio.KNOB_MIN)))
	restored._radio_channel = int(source.get("radio_channel", -1))
	restored.set_last_dex_mode(int(source.get("last_dex_mode", RomLayout.DEXMODE_NEW)))
	restored.set_kurt_apricorn_quantity(int(source.get("kurt_apricorn_quantity", 0)))
	var picked: Variant = source.get("picked_fruit_trees", {})
	if picked is Dictionary:
		for raw_tree: Variant in picked as Dictionary:
			if int(raw_tree) > 0 and bool((picked as Dictionary)[raw_tree]):
				restored._picked_fruit_trees[int(raw_tree)] = true
	## Absent in a state written before the Unown dex, which reads as an empty
	## one: the flag that unlocks the mode is an engine flag and survives on its
	## own, so an old save shows the mode with nothing listed under it, which is
	## what a player who has caught none would see anyway.
	var stored_unown: Variant = source.get("unown_dex", [])
	if stored_unown is Array:
		for raw_form: Variant in stored_unown as Array:
			restored.update_unown_dex(int(raw_form))
	restored.set_registered_item(int(source.get("registered_item", 0)))
	restored.set_wild_encounter_cooldown(int(source.get("wild_encounter_cooldown", 0)))
	restored.set_wild_encounters_off(bool(source.get("wild_encounters_off", false)))
	restored.set_park_balls(int(source.get("park_balls", 0)))
	var started: Variant = source.get("bug_contest_started", {})
	if started is Dictionary:
		restored._bug_contest_started = _clock_dict(started as Dictionary)
	var caught: Variant = source.get("contest_mon", {})
	if caught is Dictionary and int((caught as Dictionary).get("species", 0)) > 0:
		restored._contest_mon = (caught as Dictionary).duplicate()
	restored.set_contest_second_party_species(
		int(source.get("contest_second_party_species", 0))
	)
	return restored


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
	_pc_items = restored._pc_items.duplicate()
	_money = restored._money.duplicate()
	_coins = restored._coins
	_phone_contacts = restored._phone_contacts.duplicate()
	_just_battled = restored._just_battled
	_repel_steps = restored._repel_steps
	_wild_encounter_cooldown = restored._wild_encounter_cooldown
	_wild_encounters_off = restored._wild_encounters_off
	_park_balls = restored._park_balls
	_bug_contest_started = restored._bug_contest_started.duplicate()
	_contest_mon = restored._contest_mon.duplicate()
	_contest_second_party_species = restored._contest_second_party_species
	_swarm_map = restored._swarm_map
	_fishing_swarm_species = restored._fishing_swarm_species
	_roaming_mons = _copy_roaming_mons(restored._roaming_mons)
	_seen_species = restored._seen_species.duplicate()
	_caught_species = restored._caught_species.duplicate()
	_unown_dex = restored._unown_dex.duplicate()
	_phone_receive_cycle = restored._phone_receive_cycle
	_phone_receive_minutes = restored._phone_receive_minutes
	_pending_special_phone_call = restored._pending_special_phone_call
	_script_memory = restored._script_memory.duplicate()
	_map_music = restored._map_music
	_radio_knob = restored._radio_knob
	_radio_channel = restored._radio_channel
	_last_dex_mode = restored._last_dex_mode
	_maptile_decorations = restored._maptile_decorations.duplicate()
	_kurt_apricorn_quantity = restored._kurt_apricorn_quantity
	_picked_fruit_trees = restored._picked_fruit_trees.duplicate()
	_registered_item = restored._registered_item
	changed.emit()


func maptile_decoration(category: StringName) -> int:
	return int(_maptile_decorations.get(category, 0))


func maptile_decorations() -> Dictionary:
	return _maptile_decorations.duplicate()


func set_maptile_decoration(category: StringName, decoration: int) -> bool:
	if category not in [&"bed", &"carpet", &"plant", &"poster"] \
		or decoration < 0 or decoration > 0xFF:
		return false
	if maptile_decoration(category) == decoration:
		return true
	if decoration == 0:
		_maptile_decorations.erase(category)
	else:
		_maptile_decorations[category] = decoration
	changed.emit()
	return true


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
	return is_engine_flag_active(
		engine_flag(ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED, crystal)
	)


## The engine flag one badge occupies on the table [param crystal] selects,
## indexed in source badge order: 0 is ZEPHYRBADGE and 15 EARTHBADGE. Out of
## range answers -1, which is_engine_flag_active() reads as inactive. This is
## what a CheckBadge caller uses, so no caller indexes the two arrays itself.
static func badge_flag(badge: int, crystal: bool = true) -> int:
	var flags: Array[int] = BADGE_ENGINE_FLAGS if crystal else BADGE_ENGINE_FLAGS_GOLD_SILVER
	return flags[badge] if badge >= 0 and badge < flags.size() else -1


## [param crystal_index] resolved onto the table [param crystal] selects. The
## two tables differ only in that pokegold ships no ENGINE_MOBILE_SYSTEM, so
## everything past that one index sits one lower there. The named pairs above
## are this same shift written out for the flags a runtime path reads; a caller
## holding a Crystal index and no pair asks here. ENGINE_MOBILE_SYSTEM itself
## answers -1 off Crystal, which is_engine_flag_active() reads as inactive,
## since Gold and Silver have no flag to map it onto.
static func engine_flag(crystal_index: int, crystal: bool = true) -> int:
	if crystal or crystal_index < ENGINE_MOBILE_SYSTEM:
		return crystal_index
	return crystal_index - 1 if crystal_index > ENGINE_MOBILE_SYSTEM else -1


## The `ENGINE_FLYPOINT_*` run, which is `wVisitedSpawns` a bit at a time: the
## flag `CheckIfVisitedFlypoint` tests for spawn [param spawn], as a Crystal
## index resolved onto [param crystal]'s own table.
##
## The rows are the spawns in order with one hole in them: `SPAWN_UNION_CAVE`
## has no flag of its own (`data/events/engine_flags.asm`), so every spawn past
## it sits one row lower than its own number. -1 for the Union Cave spawn and for
## anything outside the run, which [method is_engine_flag_active] reads as
## inactive.
static func flypoint_flag(spawn: int, crystal: bool = true) -> int:
	if spawn < 0 or spawn >= NUM_SPAWNS or spawn == SPAWN_UNION_CAVE:
		return -1
	var index: int = ENGINE_FLYPOINT_FIRST + spawn
	if spawn > SPAWN_UNION_CAVE:
		index -= 1
	return engine_flag(index, crystal)


## `ENGINE_FLYPOINT_PLAYERS_HOUSE`, where the run starts, and the one spawn the
## run skips.
const ENGINE_FLYPOINT_FIRST: int = 51
const SPAWN_UNION_CAVE: int = 17
const NUM_SPAWNS: int = RomLayout.SPAWN_COUNT


## The engine flag SetStrengthFlag sets and TryStrengthOW and
## DoPlayerMovement.CheckStrengthBoulder read, resolved for [param crystal] the
## way badge_flag() resolves a badge.
static func strength_active_flag(crystal: bool = true) -> int:
	return ENGINE_STRENGTH_ACTIVE if crystal else ENGINE_STRENGTH_ACTIVE_GOLD_SILVER


## `.GetOffBike`'s own `bit BIKEFLAGS_ALWAYS_ON_BIKE_F`, resolved for the profile
## [param data] names the way strength_active_flag() resolves its own.
static func always_on_bike_flag(data: GameData) -> int:
	return ENGINE_ALWAYS_ON_BIKE if is_crystal_profile(data) \
		else ENGINE_ALWAYS_ON_BIKE_GOLD_SILVER


## Mirrors _GetVarAction's .CountBadges: a popcount over both badge bytes.
func badge_count(crystal: bool = true) -> int:
	var count: int = 0
	for flag: int in (BADGE_ENGINE_FLAGS if crystal else BADGE_ENGINE_FLAGS_GOLD_SILVER):
		if is_engine_flag_active(flag):
			count += 1
	return count


## The source badge bytes as one mask in badge order, for the battle engine's
## `DoBadgeTypeBoosts` and `BadgeStatBoosts` readers.
func badge_mask(crystal: bool = true) -> int:
	var mask: int = 0
	var flags: Array[int] = BADGE_ENGINE_FLAGS if crystal else BADGE_ENGINE_FLAGS_GOLD_SILVER
	for badge: int in flags.size():
		if is_engine_flag_active(flags[badge]):
			mask |= 1 << badge
	return mask


## Clears only source daily engine flags. Story flags such as Hall of Fame
## survive the day boundary.
##
## `CheckDailyResetTimer` (`engine/overworld/time.asm`) zeroes the whole
## `wDailyFlags1` byte, so every flag in it goes together. Listed by Crystal
## index because only the ones this project writes are modelled; add a flag
## here as soon as something sets it, or it survives the day the cartridge
## clears it on.
const DAILY_ENGINE_FLAGS: Array[int] = [
	ENGINE_KURT_MAKING_BALLS, ENGINE_ALL_FRUIT_TREES,
	ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED,
]


func reset_daily_flags(crystal: bool = true) -> bool:
	var did_change: bool = false
	for crystal_index: int in DAILY_ENGINE_FLAGS:
		var flag: int = engine_flag(crystal_index, crystal)
		if not _engine_flags.has(flag):
			continue
		_engine_flags.erase(flag)
		did_change = true
	if did_change:
		changed.emit()
	return did_change


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


func pc_item_quantity(item: int) -> int:
	return int(_pc_items.get(item, 0))


func pc_items() -> Dictionary:
	return _pc_items.duplicate()


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


## The byte a script memory address holds. An address never written reads zero,
## the way the cartridge's cleared WRAM does.
func script_memory(address: int) -> int:
	return int(_script_memory.get(address, 0))


func script_memory_values() -> Dictionary:
	return _script_memory.duplicate()


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


## `wMapMusic`: the track that is playing, not the track the current map asks
## for. The two differ whenever a radio station is tuned.
func used_flash() -> bool:
	return _used_flash


## `BlindingFlash`'s own `set STATUSFLAGS_FLASH_F`.
func set_used_flash(value: bool) -> void:
	if _used_flash == value:
		return
	_used_flash = value
	changed.emit()


## `ResetFlashIfOutOfCave`, called on entering a map: only a route or a town puts
## the light out, so walking from one cave room into another keeps it.
func clear_flash_if_outdoors(environment: int) -> void:
	if Gen2WorldPhoneHost.is_outside_environment(environment):
		set_used_flash(false)


func map_music() -> int:
	return _map_music


func set_map_music(music: int) -> void:
	var next_music: int = maxi(0, music)
	if next_music == _map_music:
		return
	_map_music = next_music
	changed.emit()


## PlayMapMusic: a map that asks for the track already playing does not restart
## it, which is what makes crossing a route boundary one continuous piece and
## what keeps a tuned station playing across a map reload. Answers whether the
## track changed, so a caller knows whether to restart playback.
func play_map_music(music: int) -> bool:
	if maxi(0, music) == _map_music:
		return false
	set_map_music(music)
	return true


func radio_knob() -> int:
	return _radio_knob


## Clamped and snapped to the source's own two-step dial.
func last_dex_mode() -> int:
	return _last_dex_mode


## `.exit`'s `ld a, [wCurDexMode]; ld [wLastDexMode], a`. A mode outside the
## three the listing can be in is refused rather than stored: the fourth,
## DEXMODE_UNOWN, is the Unown dex, which never becomes `wCurDexMode`.
func set_last_dex_mode(mode: int) -> void:
	if mode not in [
		RomLayout.DEXMODE_NEW, RomLayout.DEXMODE_OLD, RomLayout.DEXMODE_ABC,
	] or mode == _last_dex_mode:
		return
	_last_dex_mode = mode
	changed.emit()


func set_radio_knob(knob: int) -> void:
	var next_knob: int = clampi(knob, Gen2WorldRadio.KNOB_MIN, Gen2WorldRadio.KNOB_MAX)
	next_knob -= next_knob % Gen2WorldRadio.KNOB_STEP
	if next_knob == _radio_knob:
		return
	_radio_knob = next_knob
	changed.emit()


## `wCurRadioLine`, or -1 while the dial sits on dead air.
func radio_channel() -> int:
	return _radio_channel


func set_radio_channel(channel: int) -> void:
	var next_channel: int = channel if channel >= 0 else -1
	if next_channel == _radio_channel:
		return
	_radio_channel = next_channel
	changed.emit()


func wild_encounter_cooldown() -> int:
	return _wild_encounter_cooldown


## `SetUpFiveStepWildEncounterCooldown`'s own write, which `EnterMap` makes on
## every map entry, `reloadmapafterbattle` included.
const WILD_ENCOUNTER_COOLDOWN_STEPS: int = 5


func set_wild_encounter_cooldown(steps: int) -> void:
	var next_steps: int = clampi(steps, 0, 0xFF)
	if next_steps == _wild_encounter_cooldown:
		return
	_wild_encounter_cooldown = next_steps
	changed.emit()


## `CheckWildEncounterCooldown`: zero lets the step through, and so does the step
## that takes the counter to zero. Answers whether this step is blocked.
func consume_wild_encounter_cooldown() -> bool:
	if _wild_encounter_cooldown <= 0:
		return false
	_wild_encounter_cooldown -= 1
	changed.emit()
	return _wild_encounter_cooldown > 0


## `ENGINE_BUG_CONTEST_TIMER`, the flag `Route35NationalParkGate` sets on the
## way in and `BugContestResultsWarpScript` clears on the way out. It is
## `wStatusFlags2`' own bit, so it sits past `ENGINE_MOBILE_SYSTEM` and shifts on
## Gold and Silver like every other flag there.
const ENGINE_BUG_CONTEST_TIMER: int = 17
## `ENGINE_DAILY_BUG_CONTEST`, the once-a-day flag the officer checks.
const ENGINE_DAILY_BUG_CONTEST: int = 81
## `BugCatchingContestantEventFlagTable`, whose ten entries are the same numbers
## in both pins. A set flag is a contestant who is not in this contest.
const EVENT_BUG_CATCHING_CONTESTANT_FIRST: int = 1814


## [param crystal] the way every other profile-shifted flag takes it: the state
## holds no GameData of its own, so the caller resolves the profile.
func bug_contest_active(crystal: bool = true) -> bool:
	return is_engine_flag_active(engine_flag(ENGINE_BUG_CONTEST_TIMER, crystal))


func park_balls() -> int:
	return _park_balls


func set_park_balls(count: int) -> void:
	var next_count: int = clampi(count, 0, 0xFF)
	if next_count == _park_balls:
		return
	_park_balls = next_count
	changed.emit()


## The clock `StartBugContestTimer` copied, as `{day, hour, minute}`, or an empty
## Dictionary when no contest has been started.
func bug_contest_started() -> Dictionary:
	return _bug_contest_started.duplicate()


func set_bug_contest_started(clock: Dictionary) -> void:
	_bug_contest_started = _clock_dict(clock)
	changed.emit()


static func _clock_dict(clock: Dictionary) -> Dictionary:
	if clock.is_empty():
		return {}
	return {
		"day": int(clock.get("day", 0)),
		"hour": int(clock.get("hour", 0)),
		"minute": int(clock.get("minute", 0)),
	}


func contest_mon() -> Dictionary:
	return _contest_mon.duplicate()


func set_contest_mon(mon: Dictionary) -> void:
	_contest_mon = mon.duplicate() if int(mon.get("species", 0)) > 0 else {}
	changed.emit()


func contest_second_party_species() -> int:
	return _contest_second_party_species


func set_contest_second_party_species(species: int) -> void:
	var next_species: int = clampi(species, 0, 0xFF)
	if next_species == _contest_second_party_species:
		return
	_contest_second_party_species = next_species
	changed.emit()


## Which of the ten contestants are not in this contest, as
## `{index: true}`, read off the event flags
## `SelectRandomBugContestContestants` set.
func withdrawn_bug_contestants() -> Dictionary:
	var out: Dictionary = {}
	for index: int in Gen2WorldBugContest.NUM_CONTESTANTS:
		if is_event_flag_active(EVENT_BUG_CATCHING_CONTESTANT_FIRST + index):
			out[index] = true
	return out


func wild_encounters_off() -> bool:
	return _wild_encounters_off


func set_wild_encounters_off(value: bool) -> void:
	if _wild_encounters_off == value:
		return
	_wild_encounters_off = value
	changed.emit()


func repel_steps() -> int:
	return _repel_steps


func set_repel_steps(steps: int) -> void:
	var next_steps: int = maxi(0, steps)
	if next_steps == _repel_steps:
		return
	_repel_steps = next_steps
	changed.emit()


## The item SELECT uses, or zero for none. `RegisterItem` writes the number and
## `CheckRegisteredItem` clears it again the moment the pack no longer holds it,
## which is why the ownership test lives with the reader rather than here.
func registered_item() -> int:
	return _registered_item


func set_registered_item(item: int) -> void:
	var next_item: int = item if item > 0 else 0
	if next_item == _registered_item:
		return
	_registered_item = next_item
	changed.emit()


func kurt_apricorn_quantity() -> int:
	return _kurt_apricorn_quantity


func set_kurt_apricorn_quantity(quantity: int) -> void:
	var next_quantity: int = clampi(quantity, 0, 0xFF)
	if next_quantity == _kurt_apricorn_quantity:
		return
	_kurt_apricorn_quantity = next_quantity
	changed.emit()


func fruit_tree_picked(tree_id: int) -> bool:
	return bool(_picked_fruit_trees.get(tree_id, false))


func picked_fruit_trees() -> Dictionary:
	return _picked_fruit_trees.duplicate()


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


func has_caught_species(species: int) -> bool:
	return species > 0 and bool(_caught_species.get(species, false))


func caught_species() -> Dictionary:
	return _caught_species.duplicate()


## `CountSetBits` over wPokedexCaught, which is the number the trainer card
## prints and `_GetVarAction`'s dex-count variables read.
func caught_count() -> int:
	return _caught_species.size()


func seen_count() -> int:
	return _seen_species.size()


## `SetSeenAndCaughtMon` sets the caught flag and then falls through into
## `SetSeenMon`, so catching also marks seen and no caller does both.
func set_species_caught(species: int, caught: bool = true) -> void:
	if species <= 0:
		return
	if caught:
		_caught_species[species] = true
		set_species_seen(species, true)
	else:
		_caught_species.erase(species)


## `UpdateUnownDex`: appends the form unless it is already listed. The walk stops
## at the first empty slot, so a form only ever reaches the end of the list, and
## a full twenty-six returns without writing anything.
##
## Its caller is what limits this, not the routine: `GeneratePartyMonStats` runs
## it only for a PARTYMON, so an Unown that goes straight to the PC is caught
## without entering the dex.
func update_unown_dex(form: int) -> void:
	if form < 1 or form > RomLayout.UNOWN_FORMS:
		return
	if form in _unown_dex or _unown_dex.size() >= RomLayout.UNOWN_FORMS:
		return
	_unown_dex.append(form)


## The forms caught, in catching order. `Pokedex_DrawUnownModeBG` walks exactly
## this and stops at the first empty slot.
func unown_dex() -> Array[int]:
	return _unown_dex.duplicate()


## `_GetVarAction.UnownCaught`, which is `VAR_UNOWNCOUNT`.
func unown_caught_count() -> int:
	return _unown_dex.size()


func has_seen_species(species: int) -> bool:
	return species > 0 and bool(_seen_species.get(species, false))


func seen_species() -> Dictionary:
	return _seen_species.duplicate()


## Clearing drops the entry rather than storing false, so the dictionary holds
## only what has been seen and round-trips through a snapshot unchanged.
func set_species_seen(species: int, seen: bool = true) -> void:
	if species <= 0:
		return
	if seen:
		_seen_species[species] = true
	else:
		_seen_species.erase(species)


## Advances each active roaming Pokémon using the source's connected-map
## selection. A zero in the source's five-bit mask performs a random jump to a
## roaming map; otherwise the low two bits select one of the current row's
## connections and retry when that index is absent.
func advance_roaming(map_rows: Array, random: RandomNumberGenerator = null) -> Array:
	if _roaming_mons.is_empty() or map_rows.is_empty():
		return []
	## A schedule tick is stateful even when no mon moves: every failed attempt
	## consumes draws. Refuse the operation without a caller-owned stream rather
	## than introducing an unrepeatable random source inside persistent state.
	if random == null:
		return []
	var generator: RandomNumberGenerator = random
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


## Every entry point for a roaming record funnels through here: the constructor,
## ensure_roaming_mons(), restore() and roaming_mons(). The importer writes these
## four fields as integers, but a cache or snapshot round-trips through JSON,
## where they come back as floats, so they are normalized once on the way in
## rather than at each read.
func _copy_roaming_mons(source: Array) -> Array:
	var out: Array = []
	for raw: Variant in source:
		if raw is Dictionary:
			var mon: Dictionary = (raw as Dictionary).duplicate(true)
			for field: String in ["species", "level", "map_group", "map_number"]:
				if mon.has(field):
					mon[field] = int(mon[field])
			out.append(mon)
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
	var pc_item_changes: Dictionary = runtime_changes.get("pc_items", {})
	if not pc_item_changes is Dictionary:
		return {"ok": false, "reason": &"invalid_pc_items"}
	for raw_item: Variant in pc_item_changes:
		if int(raw_item) <= 0 or int(pc_item_changes[raw_item]) < 0:
			return {"ok": false, "reason": &"invalid_pc_item_quantity"}
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
	var next_kurt_apricorns: int = int(
		runtime_changes.get("kurt_apricorn_quantity", _kurt_apricorn_quantity)
	)
	if next_kurt_apricorns < 0 or next_kurt_apricorns > 0xFF:
		return {"ok": false, "reason": &"invalid_kurt_apricorn_quantity"}
	var fruit_tree_changes: Dictionary = runtime_changes.get("fruit_trees", {})
	if not fruit_tree_changes is Dictionary:
		return {"ok": false, "reason": &"invalid_fruit_trees"}
	for raw_tree: Variant in fruit_tree_changes:
		if int(raw_tree) < 1 or int(raw_tree) > RomLayout.FRUIT_TREE_COUNT:
			return {"ok": false, "reason": &"invalid_fruit_trees"}
	var seen_changes: Dictionary = runtime_changes.get("seen_species", {})
	if not seen_changes is Dictionary:
		return {"ok": false, "reason": &"invalid_seen_species"}
	for raw_species: Variant in seen_changes:
		if int(raw_species) <= 0:
			return {"ok": false, "reason": &"invalid_seen_species"}
	var caught_changes: Dictionary = runtime_changes.get("caught_species", {})
	if not caught_changes is Dictionary:
		return {"ok": false, "reason": &"invalid_caught_species"}
	for raw_species: Variant in caught_changes:
		if int(raw_species) <= 0:
			return {"ok": false, "reason": &"invalid_caught_species"}
	var memory_changes: Dictionary = runtime_changes.get("script_memory", {})
	if not memory_changes is Dictionary:
		return {"ok": false, "reason": &"invalid_script_memory"}
	for raw_address: Variant in memory_changes:
		var change_value: int = int(memory_changes[raw_address])
		if int(raw_address) <= 0 or change_value < 0 or change_value > 0xFF:
			return {"ok": false, "reason": &"invalid_script_memory"}

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
	var next_pc_items: Dictionary = _pc_items.duplicate()
	for raw_item: Variant in pc_item_changes:
		var pc_item: int = int(raw_item)
		var pc_quantity: int = int(pc_item_changes[raw_item])
		if pc_quantity == 0:
			next_pc_items.erase(pc_item)
		else:
			next_pc_items[pc_item] = pc_quantity
	if next_pc_items.size() > Gen2WorldPack.MAX_PC_ITEMS:
		return {"ok": false, "reason": &"pc_item_capacity"}
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
	var next_caught_species: Dictionary = _caught_species.duplicate()
	for raw_species: Variant in caught_changes:
		var caught_species_number: int = int(raw_species)
		if bool(caught_changes[raw_species]):
			next_caught_species[caught_species_number] = true
			next_seen_species[caught_species_number] = true
		else:
			next_caught_species.erase(caught_species_number)
	var next_contacts: Dictionary = _phone_contacts.duplicate()
	for raw_contact: Variant in phone_changes:
		var contact: int = int(raw_contact)
		if bool(phone_changes[raw_contact]):
			next_contacts[contact] = true
		else:
			next_contacts.erase(contact)
	if next_contacts.size() > PHONE_CONTACT_CAPACITY:
		return {"ok": false, "reason": &"phone_contact_capacity"}
	var next_script_memory: Dictionary = _script_memory.duplicate()
	for raw_address: Variant in memory_changes:
		var address: int = int(raw_address)
		var value: int = int(memory_changes[raw_address])
		if value == 0:
			next_script_memory.erase(address)
		else:
			next_script_memory[address] = value
	if next_script_memory.size() > SCRIPT_MEMORY_CAPACITY:
		return {"ok": false, "reason": &"script_memory_capacity"}
	var next_fruit_trees: Dictionary = _picked_fruit_trees.duplicate()
	for raw_tree: Variant in fruit_tree_changes:
		var tree: int = int(raw_tree)
		if bool(fruit_tree_changes[raw_tree]):
			next_fruit_trees[tree] = true
		else:
			next_fruit_trees.erase(tree)
	var next_just_battled: bool = bool(
		runtime_changes.get("just_battled", _just_battled)
	)

	var did_change: bool = next_flags != _event_flags or next_engine_flags != _engine_flags \
		or next_scenes != _map_scenes \
		or next_items != _items or next_pc_items != _pc_items \
		or next_money != _money or next_coins != _coins \
		or next_contacts != _phone_contacts or next_just_battled != _just_battled \
		or next_seen_species != _seen_species \
		or next_caught_species != _caught_species \
		or next_repel_steps != _repel_steps or next_swarm_map != _swarm_map \
		or next_fishing_swarm_species != _fishing_swarm_species \
		or next_receive_cycle != _phone_receive_cycle \
		or next_receive_minutes != _phone_receive_minutes \
		or next_special_phone_call != _pending_special_phone_call \
		or next_script_memory != _script_memory \
		or next_kurt_apricorns != _kurt_apricorn_quantity \
		or next_fruit_trees != _picked_fruit_trees
	_event_flags = next_flags
	_engine_flags = next_engine_flags
	_map_scenes = next_scenes
	_items = next_items
	_pc_items = next_pc_items
	_money = next_money
	_seen_species = next_seen_species
	_caught_species = next_caught_species
	_coins = next_coins
	_phone_contacts = next_contacts
	_just_battled = next_just_battled
	_repel_steps = next_repel_steps
	_swarm_map = next_swarm_map
	_fishing_swarm_species = next_fishing_swarm_species
	_phone_receive_cycle = next_receive_cycle
	_phone_receive_minutes = next_receive_minutes
	_pending_special_phone_call = next_special_phone_call
	_script_memory = next_script_memory
	_kurt_apricorn_quantity = next_kurt_apricorns
	_picked_fruit_trees = next_fruit_trees
	if did_change:
		changed.emit()
	return {"ok": true, "changed": did_change}
