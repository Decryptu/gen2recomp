class_name Gen2WorldCatalog
extends RefCounted

## Every stable gameplay SITE the cartridge hands something out at, decoded once
## and addressed by an id that does not move: a starter, a gift, a static battle,
## a trade, a Game Corner prize, an item on the ground, a badge and a shop.
##
## Why this exists rather than a mod holding a list of script addresses: a
## randomizer that shuffled starters by patching `ElmsLab` at $58F3 would be a
## private copy of cartridge semantics, wrong on Gold the moment an address
## shifts, and silently broken by any change here. The host owns the decoding;
## the mod owns the placement.
##
## Nothing is imported for this. Every row is derived from data the cache already
## holds: the decoded scripts, the map events, the mart lists and the trade
## records. That is why there is no cache-format bump behind it and why a fresh
## cartridge needs no re-import.
##
## A patch changes a FIELD of a row. It never replaces a script, a completion
## flag, a dialogue, an inventory transaction or a battle flow: the site still
## runs the cartridge's own code, and only the number it hands over is the mod's.
## See [method Gen2ModHost.patch_check].

const KIND_STARTER: StringName = &"starter"
const KIND_GIFT: StringName = &"gift"
const KIND_STATIC: StringName = &"static"
const KIND_TRADE: StringName = &"trade"
const KIND_PRIZE: StringName = &"prize"
const KIND_ITEM: StringName = &"item"
const KIND_BADGE: StringName = &"badge"
const KIND_SHOP: StringName = &"shop"
## Also the id's own kind nibble, so the order is part of the id and adding a
## kind at the end cannot renumber the ones before it.
const KINDS: Array[StringName] = [
	KIND_STARTER, KIND_GIFT, KIND_STATIC, KIND_TRADE, KIND_PRIZE, KIND_ITEM,
	KIND_BADGE, KIND_SHOP,
]

## `id = kind << 40 | bank << 24 | absolute address`. The address is ABSOLUTE, the
## script's own base plus the command's offset inside it, and that is what makes
## the id stable: the cache stores one blob per entry point and two entry points
## into one routine overlap, so a site addressed by (blob, offset) would be
## counted once per blob that reaches it. Addressed by the byte it lives at, it
## is one site however many ways in there are, and a runtime reader computes the
## same number from its own frame.
##
## A site that is a map EVENT rather than a script has no address: it uses the
## map's group as the bank and [constant ID_EVENT_BIT] over the map number and
## the event index, so the two spaces cannot collide.
const ID_KIND_SHIFT: int = 40
const ID_BANK_SHIFT: int = 24
const ID_ADDRESS_MASK: int = 0xFFFFFF
const ID_EVENT_BIT: int = 0x800000

## `ObjectEventTypeArray.itemball`, and `BGEVENT_ITEM` for one under a tile.
const OBJECT_TYPE_ITEMBALL: int = Gen2WorldObject.OBJECTTYPE_ITEMBALL
const BGEVENT_ITEM: int = Gen2WorldAPI.BGEVENT_ITEM

## How far back a site looks for the conditions guarding it. The whole script, in
## practice; this is the guard against a decode that runs away.
const MAX_SCRIPT_COMMANDS: int = 4096

var _data: GameData = null
## id to row.
var _rows: Dictionary = {}
## kind to the ids under it, in decode order.
var _by_kind: Dictionary = {}


## Builds the catalog for [param data]. Walks every imported script once and
## every map's events once, which is why a caller holds the result rather than
## asking twice; [method GameData.catalog] does that holding.
static func build(data: GameData) -> Gen2WorldCatalog:
	var out := Gen2WorldCatalog.new()
	out._data = data
	if data == null:
		return out
	out._scan_scripts()
	out._scan_map_events()
	return out


## [param address] is the command's absolute address: the script's base plus the
## command's own offset inside it.
static func pack_id(kind: StringName, bank: int, address: int) -> int:
	var index: int = KINDS.find(kind)
	if index < 0:
		return -1
	return index << ID_KIND_SHIFT | (bank & 0xFF) << ID_BANK_SHIFT \
		| (address & ID_ADDRESS_MASK)


## The id of a map EVENT site: an item ball or an item under a tile.
static func pack_event_id(kind: StringName, group: int, number: int, index: int) -> int:
	return pack_id(kind, group, ID_EVENT_BIT | (number & 0xFF) << 8 | (index & 0xFF))


## The row at [param id] with any mod patch already folded in, or empty for an id
## this cartridge has no site for. This is what a runtime reader asks.
func check(id: int) -> Dictionary:
	var row: Variant = _rows.get(id, null)
	if not row is Dictionary:
		return {}
	if _data == null:
		return (row as Dictionary).duplicate(true)
	return _data.overlaid_check(id, (row as Dictionary).duplicate(true))


## Every id of [param kind], in the order the corpus was walked, which is stable
## for one cache. Pass nothing for every id of every kind.
func ids(kind: StringName = &"") -> Array:
	if String(kind).is_empty():
		var all: Array = []
		for name: StringName in KINDS:
			all.append_array(_by_kind.get(name, []))
		return all
	return (_by_kind.get(kind, []) as Array).duplicate()


func size() -> int:
	return _rows.size()


## Every row, patched, for a mod planning a placement in one pass.
func rows(kind: StringName = &"") -> Array:
	var out: Array = []
	for id: int in ids(kind):
		out.append(check(id))
	return out


## The three species Elm's own balls offer, which is what a mod proving a seed
## traversable starts from. Empty on a cache whose scripts did not decode.
func possible_starters() -> Array[int]:
	var out: Array[int] = []
	for row: Dictionary in rows(KIND_STARTER):
		var species: int = int(row.get("species", 0))
		if species > 0 and not out.has(species):
			out.append(species)
	return out


## The HM items whose move is a field move, which are the rewards a placement
## must keep reachable. Read off the cartridge's own TM/HM move table rather
## than written down, so Gold and Crystal each answer for themselves.
func field_hm_items() -> Array[int]:
	var out: Array[int] = []
	if _data == null:
		return out
	var count: int = _data.tmhm_moves().size()
	for number: int in count:
		var item: int = RomLayout.item_for_tmhm_number(number + 1, count)
		if not Gen2WorldTMHM.is_hm(item):
			continue
		if Gen2WorldFieldMove.is_field_move(_data.tmhm_move(number + 1)):
			out.append(item)
	return out


## Whether a row's reward is one a later check may be gated behind: a badge, or a
## field HM. A placement that moves one of these has to prove the seed still
## finishes; a placement that moves a Potion does not.
func is_progression(row: Dictionary) -> bool:
	if StringName(row.get("kind", &"")) == KIND_BADGE:
		return true
	return field_hm_items().has(int(row.get("item", 0)))


## Walks every imported script, decoding linearly from its first byte. A command
## the decoder does not know ends that script's walk rather than guessing an
## operand width, which is the same rule `scan_references` follows: a site found
## past an unknown command would be at an invented offset.
func _scan_scripts() -> void:
	var crystal: bool = Gen2WorldState.is_crystal_profile(_data)
	for key: Variant in _data.world_script_keys():
		var parts: PackedStringArray = String(key).split(":")
		if parts.size() != 2:
			continue
		## `Gen2WorldScript.pointer_key` is a DECIMAL bank and a hex address.
		var bank: int = String(parts[0]).to_int()
		var address: int = String(parts[1]).hex_to_int()
		_scan_one_script(bank, address, _data.world_script(bank, address), crystal)


func _scan_one_script(
	bank: int, address: int, body: PackedByteArray, crystal: bool
) -> void:
	if body.is_empty():
		return
	var commands: Array = []
	var offset: int = 0
	## The walk does NOT stop at the first `end` or `sjump`. A bounded blob holds
	## a routine and the branch bodies behind it, and the Game Corner's three
	## prizes are exactly that: one `.loop` and three labels after its jump.
	##
	## It DOES stop at the first byte no command owns. Everything decoded before
	## that came from a real entry point at a real offset; everything after would
	## be text or a data table read as code. Two more guards sit behind this one:
	## a site's numbers have to be ones the cartridge can hold ([method
	## _plausible]), and a static has to be followed by the `startbattle` that
	## makes it one.
	for _step: int in MAX_SCRIPT_COMMANDS:
		if offset >= body.size():
			break
		var command: Dictionary = Gen2WorldScript.command_at(body, offset, crystal)
		if not bool(command.get("ok", false)):
			break
		commands.append(command)
		offset += int(command["width"])
	## Two facts about the WHOLE script decide what its give sites mean: a
	## `takecoins` makes them purchases, and a `pokepic` of the species a
	## `givepoke` later hands over is the only shape Elm's three balls take and
	## the only shape anything else in either game does not.
	## The price is per SITE, not per script: a prize vendor's three branches sit
	## in one script and each spends its own `takecoins`.
	var pictured: Dictionary = {}
	for command: Dictionary in commands:
		if StringName(command["name"]) == &"pokepic":
			pictured[int(command.get("pokemon", 0))] = true
	for command: Dictionary in commands:
		_record_script_site(
			bank, address, command, commands, _coin_price(commands, int(command["offset"])),
			pictured, crystal
		)


## `takecoins`' own operand, which is the purchase price and is what makes a
## `givepoke` beside it a PRIZE rather than a gift. The source order is give then
## take, so the answer is the nearest one AFTER [param at]; a script that takes
## before it gives falls back to the nearest before. Zero when the script spends
## no coins at all.
func _coin_price(commands: Array, at: int) -> int:
	var before: int = 0
	for command: Dictionary in commands:
		if StringName(command["name"]) != &"takecoins":
			continue
		if int(command["offset"]) > at:
			return int(command.get("value", 0))
		before = int(command.get("value", 0))
	return before


func _record_script_site(
	bank: int, address: int, command: Dictionary, commands: Array, coins: int,
	pictured: Dictionary, crystal: bool
) -> void:
	var offset: int = int(command["offset"])
	## Each command's own decoded keys, not a positional operand list:
	## `Gen2WorldScript.command_at` names what it read.
	match StringName(command["name"]):
		&"givepoke", &"giveegg":
			var species: int = int(command.get("pokemon", command.get("value", 0)))
			var level: int = int(command.get("level", command.get("value_2", 0)))
			if species <= 0:
				return
			var kind: StringName = KIND_GIFT
			if coins > 0:
				kind = KIND_PRIZE
			elif pictured.has(species):
				kind = KIND_STARTER
			_add(kind, bank, address, offset, {
				"species": species, "level": level,
				"item": int(command.get("item", 0)), "price": coins,
			}, commands, offset, crystal)
		&"loadwildmon":
			## `loadwildmon` then `startbattle` is what a static encounter IS;
			## two bytes that merely decode as one are not.
			if not _followed_by(commands, offset, &"startbattle"):
				return
			_add(KIND_STATIC, bank, address, offset, {
				"species": int(command.get("pokemon", 0)),
				"level": int(command.get("level", 0)),
			}, commands, offset, crystal)
		&"trade":
			var index: int = int(command.get("value", 0))
			var record: Dictionary = _data.world_trade(index)
			_add(KIND_TRADE, bank, address, offset, {
				"trade": index,
				"species": int(record.get("offered_species", 0)),
				"requested_species": int(record.get("requested_species", 0)),
			}, commands, offset, crystal)
		&"pokemart":
			## `db dialog_id / dw mart_id`, so the dialog is the byte and the
			## mart index the word behind it.
			_add(KIND_SHOP, bank, address, offset, {
				"mart": int(command.get("address", 0)),
				"dialog": int(command.get("value", 0)),
			}, commands, offset, crystal)
		&"giveitem", &"verbosegiveitem":
			var item: int = int(command.get("item", command.get("value", 0)))
			if item <= 0:
				return
			_add(KIND_ITEM, bank, address, offset, {
				"item": item,
				"quantity": maxi(1, int(command.get("quantity", command.get("value_2", 1)))),
				"price": coins, "hidden": false,
			}, commands, offset, crystal)
		&"setflag":
			var badge: int = _badge_for_flag(int(command.get("flag", -1)))
			if badge < 0:
				return
			_add(KIND_BADGE, bank, address, offset, {
				"badge": badge, "engine_flag": int(command.get("flag", 0)),
			}, commands, offset, crystal)


## Whether [param name] is the next few commands after [param at]. The cartridge
## puts `startbattle` immediately behind its `loadwildmon`, with at most a text
## or a flag between them.
static func _followed_by(commands: Array, at: int, name: StringName, within: int = 6) -> bool:
	var seen: int = 0
	for command: Dictionary in commands:
		if int(command["offset"]) <= at:
			continue
		if StringName(command["name"]) == name:
			return true
		seen += 1
		if seen >= within:
			return false
	return false


## Which badge an engine flag grants, or -1. The two profiles number the badge
## block one apart, so the answer is the cartridge's own list rather than a
## constant.
func _badge_for_flag(flag: int) -> int:
	var flags: Array[int] = Gen2WorldState.BADGE_ENGINE_FLAGS \
		if Gen2WorldState.is_crystal_profile(_data) \
		else Gen2WorldState.BADGE_ENGINE_FLAGS_GOLD_SILVER
	return flags.find(flag)


## The item balls and the items under a tile, which are map EVENTS and carry no
## script of their own: `itemball`'s two bytes are the object's script pointer
## read as data, and `hiddenitem` is a `bg_event` of type
## [constant BGEVENT_ITEM].
func _scan_map_events() -> void:
	for map: Gen2WorldMap in _data.world_maps():
		var bank: int = int(map.events.get("bank", 0))
		var objects: Array = map.events.get("objects", [])
		for index: int in objects.size():
			var object: Variant = objects[index]
			if not object is Dictionary:
				continue
			if int((object as Dictionary).get("object_type", 0)) != OBJECT_TYPE_ITEMBALL:
				continue
			## `db item, quantity` behind the object's script pointer, read as
			## data. `Gen2WorldAPI._item_ball_request_for_event` decodes the same
			## two bytes at runtime and asks this catalog for them.
			var raw: PackedByteArray = _data.world_script(
				bank, int((object as Dictionary).get("script", 0))
			)
			if raw.size() < 2 or int(raw[0]) <= 0:
				continue
			_add_event(KIND_ITEM, map, index, {
				"item": int(raw[0]), "quantity": maxi(1, int(raw[1])), "hidden": false,
			})
		var bg_events: Array = map.events.get("bg_events", [])
		for index: int in bg_events.size():
			var event: Variant = bg_events[index]
			if not event is Dictionary:
				continue
			if int((event as Dictionary).get("type", 0)) != BGEVENT_ITEM:
				continue
			## `dwb event, item`: the flag first as a word, the item last.
			var raw: PackedByteArray = _data.world_script(
				bank, int((event as Dictionary).get("script", 0))
			)
			if raw.size() < 3 or int(raw[2]) <= 0:
				continue
			_add_event(KIND_ITEM, map, objects.size() + index, {
				"item": int(raw[2]), "quantity": 1, "hidden": true,
				"event_flag": int(raw[0]) | (int(raw[1]) << 8),
			})


func _add(
	kind: StringName, bank: int, address: int, offset: int, fields: Dictionary,
	commands: Array, at: int, crystal: bool
) -> void:
	var row: Dictionary = fields.duplicate()
	row["id"] = pack_id(kind, bank, address + offset)
	row["kind"] = kind
	row["bank"] = bank
	row["address"] = address + offset
	row["requires"] = _requirements(commands, at, crystal)
	_store(row)


func _add_event(
	kind: StringName, map: Gen2WorldMap, index: int, fields: Dictionary
) -> void:
	var row: Dictionary = fields.duplicate()
	row["id"] = pack_event_id(kind, map.group, map.number, index)
	row["kind"] = kind
	row["map"] = Vector2i(map.group, map.number)
	row["event_index"] = index
	row["requires"] = []
	_store(row)


## A linear walk over bounded blobs finds real sites and, occasionally, three
## bytes of text that read as a command. A row whose numbers are outside what the
## cartridge can hold is one of those, and is dropped rather than offered to a
## mod as somewhere to put a Pokemon.
func _plausible(row: Dictionary) -> bool:
	var species: int = int(row.get("species", 0))
	if row.has("species") and (species < 1 or species > RomLayout.SPECIES_COUNT):
		return false
	var level: int = int(row.get("level", 0))
	if row.has("level") and (level < 1 or level > RomLayout.MAX_LEVEL):
		return false
	var item: int = int(row.get("item", 0))
	if row.has("item") and item != 0 and _data != null and _data.item(item).is_empty():
		return false
	if row.has("trade") and _data != null and _data.world_trade(int(row["trade"])).is_empty():
		return false
	return true


func _store(row: Dictionary) -> void:
	var id: int = int(row["id"])
	if id < 0 or _rows.has(id) or not _plausible(row):
		return
	_rows[id] = row
	var kind: StringName = StringName(row["kind"])
	var list: Array = _by_kind.get(kind, [])
	list.append(id)
	_by_kind[kind] = list


## What the script tested BEFORE reaching this site: the event and engine flags
## it checked and the items it asked for. The decoded graph fact a placement
## needs, and no more than a fact: it does not say the site is unreachable
## without them, only that the cartridge looked.
##
## Read in source order up to the site rather than over the whole script, since a
## `checkevent` after a `givepoke` guards something else.
func _requirements(commands: Array, at: int, _crystal: bool) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for command: Dictionary in commands:
		if int(command["offset"]) >= at:
			break
		match StringName(command["name"]):
			&"checkevent":
				_append_once(out, seen, {"event": int(command.get("flag", 0))})
			&"checkflag":
				_append_once(out, seen, {"engine_flag": int(command.get("flag", 0))})
			&"checkitem":
				_append_once(out, seen, {"item": int(command.get("value", 0))})
	return out


## One entry per distinct condition. Two entry points into one routine overlap in
## the cache, so the same `checkevent` is walked once per blob that reaches it.
static func _append_once(out: Array, seen: Dictionary, entry: Dictionary) -> void:
	var key: String = str(entry)
	if seen.has(key):
		return
	seen[key] = true
	out.append(entry)
