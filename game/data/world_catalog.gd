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
## The scan is not cheap: it decodes every command of every imported script,
## about thirteen seconds for Crystal, and it answered 547 rows for that. So it
## is written beside the cache as a sidecar and read back ([method to_dict]).
## The sidecar is derived, not imported: an absent, stale or unreadable one is
## rebuilt and written, so no cache format covers it and a cache from an older
## build needs no re-import.
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

## The cache stores every script as a fixed 512-byte window rather than as its
## own length, so a walk that ran the whole window would spend most of it
## decoding whatever the ROM put after the script. A blob holds one routine and
## the branch labels behind it: the Game Corner's vendor, the busiest shape
## either game has, is a loop and three prizes, which is five. Sixteen is well
## past anything real and is what keeps this a second rather than eight.
const MAX_ROUTINES: int = 16

## The sidecar's own shape. Bumped when a row, a link or a kind changes meaning,
## which rebuilds every cache's sidecar without touching the cache format.
const FORMAT_VERSION: int = 1

## The row and link fields whose value is a StringName rather than a String:
## `kind` on every row, and `role` on a link. See [method _restore_value].
const STRING_NAME_FIELDS: Array[String] = ["kind", "role"]
## The one field whose value is a Vector2i, the map a site stands on. JSON has
## no vector, so it goes out as a two-element array.
const VECTOR_FIELDS: Array[String] = ["map"]

var _data: GameData = null
## id to row.
var _rows: Dictionary = {}
## kind to the ids under it, in decode order.
var _by_kind: Dictionary = {}
## The commands a site's fields also have to reach, keyed by the byte they sit
## at: `bank << 24 | address` to `{id, role}`. A starter's species is its ball's
## PICTURE as well as its `givepoke`, and a prize's price is both the
## `checkcoins` that decides affordability and the `takecoins` that charges. See
## [method link_at].
var _links: Dictionary = {}
## Built on first ask. See [method item_sources].
var _item_sources: Dictionary = {}
## Built on first ask. See [method field_hm_items].
var _field_hms: Array[int] = []


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
	out._attribute_maps()
	return out


## The scan's result, for the sidecar. Ids are dictionary keys, so they go out
## as decimal strings and come back as ints; every one is well under the 2^53
## a JSON number carries exactly.
##
## The lazy answers ([member _item_sources], [member _field_hms]) are not here:
## both are derived from these rows in a millisecond and would only be a second
## copy to keep in step.
func to_dict() -> Dictionary:
	var stored_rows: Dictionary = {}
	for id: int in _rows:
		stored_rows[str(id)] = _stored_value(_rows[id])
	var links: Dictionary = {}
	for at: int in _links:
		links[str(at)] = _stored_value(_links[at])
	var kinds: Dictionary = {}
	for kind: StringName in _by_kind:
		kinds[String(kind)] = (_by_kind[kind] as Array).duplicate()
	return {"version": FORMAT_VERSION, "rows": stored_rows, "links": links, "kinds": kinds}


## The counterpart, bound to [param data] so [method check] can still fold a mod
## patch in. Answers null for anything that is not this version's own shape, so
## a stale or truncated sidecar is rebuilt rather than half read.
static func from_dict(data: GameData, source: Variant) -> Gen2WorldCatalog:
	if not source is Dictionary:
		return null
	var raw: Dictionary = source as Dictionary
	if int(raw.get("version", -1)) != FORMAT_VERSION:
		return null
	for key: String in ["rows", "links", "kinds"]:
		if not raw.get(key, null) is Dictionary:
			return null
	var out := Gen2WorldCatalog.new()
	out._data = data
	for id: String in raw["rows"] as Dictionary:
		var row: Variant = (raw["rows"] as Dictionary)[id]
		if not row is Dictionary:
			return null
		out._rows[id.to_int()] = _restore_value(row)
	for at: String in raw["links"] as Dictionary:
		var link: Variant = (raw["links"] as Dictionary)[at]
		if not link is Dictionary:
			return null
		out._links[at.to_int()] = _restore_value(link)
	for kind: String in raw["kinds"] as Dictionary:
		var kind_ids: Variant = (raw["kinds"] as Dictionary)[kind]
		if not kind_ids is Array:
			return null
		var packed: Array = []
		for id: Variant in kind_ids as Array:
			packed.append(int(id))
		out._by_kind[StringName(kind)] = packed
	return out


## JSON has one number type and no StringName, so a row that went out as ints
## and a `kind` comes back as floats and a String. A reader compares these with
## `==` against typed literals, so the shapes have to be restored rather than
## coerced at every site.
##
## Whole floats become ints: every number a row carries is an id, a bank, an
## address, an item, a quantity or a price, and none of them is fractional. The
## two String fields that are StringNames name themselves.
static func _stored_value(value: Variant) -> Variant:
	if value is Array:
		var list: Array = []
		for entry: Variant in value as Array:
			list.append(_stored_value(entry))
		return list
	if not value is Dictionary:
		return value
	var out: Dictionary = {}
	for key: Variant in value as Dictionary:
		var stored: Variant = (value as Dictionary)[key]
		if String(key) in VECTOR_FIELDS and stored is Vector2i:
			out[key] = [(stored as Vector2i).x, (stored as Vector2i).y]
			continue
		out[key] = _stored_value(stored)
	return out


static func _restore_value(value: Variant) -> Variant:
	if value is float:
		var number: float = value as float
		if is_equal_approx(number, floor(number)):
			return int(number)
		return number
	if value is Array:
		var list: Array = []
		for entry: Variant in value as Array:
			list.append(_restore_value(entry))
		return list
	if not value is Dictionary:
		return value
	var out: Dictionary = {}
	for key: Variant in value as Dictionary:
		var restored: Variant = _restore_value((value as Dictionary)[key])
		if String(key) in STRING_NAME_FIELDS and restored is String:
			restored = StringName(restored as String)
		elif String(key) in VECTOR_FIELDS and restored is Array \
			and (restored as Array).size() == 2:
			restored = Vector2i(int((restored as Array)[0]), int((restored as Array)[1]))
		out[key] = restored
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


## The site a command at [param bank]:[param address] belongs to but is not
## itself, as `{id, role}`, or empty. `role` is `picture` for a starter's
## `pokepic` and `price` for a prize's `checkcoins` or `takecoins`.
##
## This is what makes a patched field effective at the whole TRANSACTION rather
## than at one command of it: the ball that shows a Bellsprout hands over a
## Bellsprout, and a prize the mod priced at 500 is refused at 499 coins and
## charges 500.
func link_at(bank: int, address: int) -> Dictionary:
	var value: Variant = _links.get((bank & 0xFF) << ID_BANK_SHIFT | (address & ID_ADDRESS_MASK), null)
	return value if value is Dictionary else {}


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
	if not _field_hms.is_empty():
		return _field_hms
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
	_field_hms = out
	return out


## Which badge an engine flag grants, or -1. Public because a requirement names
## the FLAG and a placement reasons about the badge.
func badge_for_engine_flag(flag: int) -> int:
	return _badge_for_flag(flag)


## The badge [param item]'s own move needs before the overworld will run it, or
## -1 for an item that is not a field HM. `GetTMHMItemMove` and the field
## functions' own `CheckBadge` arguments, neither of them written down here.
func badge_for_hm_item(item: int) -> int:
	return Gen2WorldFieldMove.badge_for_move(move_for_hm_item(item))


## The field move [param item] teaches, or 0 for anything that is not a field HM.
func move_for_hm_item(item: int) -> int:
	if _data == null or not Gen2WorldTMHM.is_hm(item):
		return 0
	var move: int = Gen2WorldTMHM.move_for_item(_data, item)
	return move if Gen2WorldFieldMove.is_field_move(move) else 0


## Every item some check in this catalog hands over, as a set. An item outside it
## is bought, found in a mart or given by a story script, so asking for it gates
## no placement.
func item_sources() -> Dictionary:
	if not _item_sources.is_empty():
		return _item_sources
	for row: Dictionary in rows(KIND_ITEM):
		_item_sources[int(row["item"])] = true
	for kind: StringName in [KIND_STARTER, KIND_GIFT, KIND_PRIZE]:
		for row: Dictionary in rows(kind):
			if int(row.get("item", 0)) > 0:
				_item_sources[int(row["item"])] = true
	return _item_sources


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
	## The bound counts `end`s, not every command that never returns: a `sjump`
	## into a label below it is one routine, not two.
	##
	## It DOES stop at the first byte no command owns. Everything decoded before
	## that came from a real entry point at a real offset; everything after would
	## be text or a data table read as code. Two more guards sit behind this one:
	## a site's numbers have to be ones the cartridge can hold ([method
	## _plausible]), and a static has to be followed by the `startbattle` that
	## makes it one.
	var terminators: int = 0
	for _step: int in MAX_SCRIPT_COMMANDS:
		if offset >= body.size():
			break
		var command: Dictionary = Gen2WorldScript.command_at(body, offset, crystal)
		if not bool(command.get("ok", false)):
			break
		commands.append(command)
		offset += int(command["width"])
		if Gen2WorldScript.is_terminal(int(command["opcode"]), crystal):
			terminators += 1
			if terminators >= MAX_ROUTINES:
				break
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
			bank, address, command, commands,
			_coin_price(commands, int(command["offset"]), crystal), pictured, crystal
		)


## `takecoins`' own operand, which is the purchase price and is what makes a
## `givepoke` beside it a PRIZE rather than a gift. Read from the give's own
## branch, so a vendor's three prizes get three prices. Zero when the branch
## spends no coins at all, which is what makes a give a gift.
func _coin_price(commands: Array, at: int, crystal: bool) -> int:
	var take: int = _nearest_coin_command(commands, at, &"takecoins", crystal)
	if take < 0:
		return 0
	for command: Dictionary in commands:
		if int(command["offset"]) == take:
			return int(command.get("value", 0))
	return 0


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
			var row: Dictionary = {
				"species": species, "level": level,
				"item": int(command.get("item", 0)), "price": coins,
			}
			## The ball's own picture, and the two coin commands of the branch
			## this give sits in. Absolute addresses, so the runner finds them
			## from its own frame.
			if kind == KIND_STARTER:
				var picture: int = _address_of(commands, &"pokepic", species)
				if picture >= 0:
					row["picture_address"] = address + picture
			if kind == KIND_PRIZE:
				var check_at: int = _nearest_coin_command(commands, offset, &"checkcoins", crystal)
				var take: int = _nearest_coin_command(commands, offset, &"takecoins", crystal)
				if check_at >= 0:
					row["check_address"] = address + check_at
				if take >= 0:
					row["take_address"] = address + take
			_add(kind, bank, address, offset, row, commands, offset, crystal)
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
			var mart: int = int(command.get("address", 0))
			_add(KIND_SHOP, bank, address, offset, {
				"mart": mart,
				"dialog": int(command.get("value", 0)),
				## The inventory this site sells, resolved to `{item, price}` so
				## a mod can move one row of one shop without inventing a mart.
				## Prices are the items' own until a patch names another.
				"items": _mart_items(mart),
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


## Where a command naming [param species] sits inside the blob, or -1. Used for
## the `pokepic` a starter's `givepoke` answers.
static func _address_of(commands: Array, name: StringName, species: int) -> int:
	for command: Dictionary in commands:
		if StringName(command["name"]) == name and int(command.get("pokemon", -1)) == species:
			return int(command["offset"])
	return -1


## The coin command of the BRANCH [param at] sits in, or -1. A branch is what
## lies between two terminators, which is how the Game Corner's vendor keeps
## three prices in one script: one `.loop` and a label per prize. Bounded that
## way, one coin command belongs to one give site and no two sites claim it.
static func _nearest_coin_command(
	commands: Array, at: int, name: StringName, crystal: bool
) -> int:
	var bounds: Array = _branch_bounds(commands, at, crystal)
	for command: Dictionary in commands:
		if StringName(command["name"]) != name:
			continue
		var offset: int = int(command["offset"])
		if offset >= int(bounds[0]) and offset < int(bounds[1]):
			return offset
	return -1


## The offsets bounding the branch [param at] sits in: just past the terminator
## before it, up to and including the terminator after it.
static func _branch_bounds(commands: Array, at: int, crystal: bool) -> Array:
	var start: int = 0
	var end: int = 0x10000
	for command: Dictionary in commands:
		var offset: int = int(command["offset"])
		if Gen2WorldScript.continues_after(int(command["opcode"]), crystal):
			continue
		if offset < at:
			start = offset + int(command["width"])
		else:
			end = offset + int(command["width"])
			break
	return [start, end]


## The mart list at [param index] as `{item, price}` rows, which is the shape
## [method Gen2WorldMartHost.entries] already reads.
func _mart_items(index: int) -> Array:
	var out: Array = []
	if _data == null:
		return out
	var mart: Dictionary = _data.world_mart(index)
	for raw: Variant in mart.get("items", []):
		var item: int = int(raw) if not raw is Dictionary else int((raw as Dictionary).get("item", 0))
		if item <= 0:
			continue
		out.append({"item": item, "price": int(_data.item(item).get("price", 0))})
	return out


## Stamps every script site with the MAP whose events reach it, which is the one
## thing a script address does not carry and a placement cannot do without: a
## badge is only completable if its gym can be walked to.
##
## Each map's own event scripts are followed through `scall`, `sjump`, `farscall`
## and the branch commands, which is the same closure the importer walks. A
## script two maps both reach is stamped with the first in map order, so the
## answer is stable; a script no map reaches keeps no map at all rather than a
## guessed one.
func _attribute_maps() -> void:
	var crystal: bool = Gen2WorldState.is_crystal_profile(_data)
	var owner: Dictionary = {}
	## One scan per script for the whole corpus, not one per map that reaches it:
	## the busiest scripts are reached from dozens of maps.
	var references: Dictionary = {}
	for map: Gen2WorldMap in _data.world_maps():
		var bank: int = int(map.events.get("bank", 0))
		var pending: Array = []
		for source: String in ["objects", "bg_events", "coord_events"]:
			for raw: Variant in map.events.get(source, []):
				if raw is Dictionary and int((raw as Dictionary).get("script", 0)) > 0:
					pending.append([bank, int((raw as Dictionary)["script"])])
		var scripts: Dictionary = map.scripts
		if int(scripts.get("address", 0)) > 0:
			pending.append([int(scripts.get("bank", bank)), int(scripts["address"])])
		for raw: Variant in scripts.get("callbacks", []):
			if raw is Dictionary and int((raw as Dictionary).get("script", 0)) > 0:
				pending.append([int(scripts.get("bank", bank)), int((raw as Dictionary)["script"])])
		var seen: Dictionary = {}
		for _step: int in MAX_SCRIPT_COMMANDS:
			if pending.is_empty():
				break
			var entry: Array = pending.pop_back()
			var key: int = (int(entry[0]) & 0xFF) << ID_BANK_SHIFT \
				| (int(entry[1]) & ID_ADDRESS_MASK)
			if seen.has(key):
				continue
			seen[key] = true
			if not owner.has(key):
				owner[key] = Vector2i(map.group, map.number)
			if not references.has(key):
				var body: PackedByteArray = _data.world_script(int(entry[0]), int(entry[1]))
				references[key] = Gen2WorldScript.scan_references(
					body, int(entry[0]), int(entry[1]), crystal
				).get("scripts", []) if not body.is_empty() else []
			for referenced: Variant in references[key]:
				if referenced is Dictionary:
					pending.append([
						int((referenced as Dictionary)["bank"]),
						int((referenced as Dictionary)["address"]),
					])
	for id: Variant in _rows:
		var row: Dictionary = _rows[id]
		if row.has("map") or not row.has("address"):
			continue
		## The site's own byte first, then the entry point its blob starts at:
		## a site inside a routine is reached through the routine, not at it.
		for address: int in [int(row["address"]), int(row.get("script_base", row["address"]))]:
			var key: int = (int(row["bank"]) & 0xFF) << ID_BANK_SHIFT | (address & ID_ADDRESS_MASK)
			if owner.has(key):
				row["map"] = owner[key]
				break


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
	## The blob this site was decoded from, which is the address a map's own
	## event points at. See [method _attribute_maps].
	row["script_base"] = address
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
	for key: String in ["picture_address", "check_address", "take_address"]:
		if not row.has(key):
			continue
		_links[(int(row["bank"]) & 0xFF) << ID_BANK_SHIFT | (int(row[key]) & ID_ADDRESS_MASK)] = {
			"id": id, "role": &"picture" if key == "picture_address" else &"price",
		}
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
func _requirements(commands: Array, at: int, crystal: bool) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for command: Dictionary in commands:
		if int(command["offset"]) >= at:
			break
		## A blob holds several routines back to back, and a condition before the
		## last `end` or `sjump` guards one of the earlier ones. Reading the whole
		## blob put thirteen conditions on a starter, two of them badges the
		## cartridge plainly does not ask a starter for.
		if not Gen2WorldScript.continues_after(int(command["opcode"]), crystal):
			out.clear()
			seen.clear()
			continue
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
