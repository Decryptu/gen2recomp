class_name Gen2ContentOverlay
extends RefCounted

## Content a mod adds or changes, consulted ahead of the cartridge's own tables.
##
## [GameData] funnels every species, move, item and trainer read through one
## place, so this is the one place that has to answer. Nothing downstream knows a
## mod exists: a defined species has a learnset, evolutions and TM flags because
## those live on the species row.
##
## [method define] adds content at a number the cartridge does not use;
## [method patch] changes fields of a row it does. Definitions are normalized
## against [constant DEFAULTS] on the way in, because readers index these rows
## directly ([method GameData.palette] reads [code]palette.normal[/code],
## [method GameData.species_pic] reads [code]front_tiles[/code]) and an omitted
## field would crash the reader rather than draw wrong.

## The kinds a mod may reach. Types are not one: the matchup lookup keys on
## [constant RomLayout.TYPE_COUNT], so a new type renumbers the whole chart.
const KIND_SPECIES: StringName = &"species"
const KIND_MOVE: StringName = &"move"
const KIND_ITEM: StringName = &"item"
const KIND_TRAINER: StringName = &"trainer"
## [method GameData.world_encounter]'s row, numbered by [method encounter_number].
const KIND_ENCOUNTER: StringName = &"encounter"
## [method GameData.world_fishing_group]'s row, numbered as a map header does.
const KIND_FISHING: StringName = &"fishing"
## The four wild sources beside the map tables, each numbered by its own index
## in the cartridge's table: [method GameData.treemon_set]'s set, one
## `ContestMons` row, one roaming mon, and one day/night fishing substitution.
##
## A row is PATCHED, never replaced: `percent` is the contest's own roll and its
## scoring weight, a rod entry's `threshold` is the bite, and a roaming mon's map
## is live state. Naming only `species` and `level` leaves every one of them.
const KIND_TREEMON: StringName = &"treemon"
const KIND_BUG_CONTEST: StringName = &"bug_contest"
const KIND_ROAMING: StringName = &"roaming"
const KIND_FISHING_TIME: StringName = &"fishing_time"
const KINDS: Array[StringName] = [
	KIND_SPECIES, KIND_MOVE, KIND_ITEM, KIND_TRAINER, KIND_ENCOUNTER, KIND_FISHING,
	KIND_TREEMON, KIND_BUG_CONTEST, KIND_ROAMING, KIND_FISHING_TIME,
]

## A cartridge table rather than numbered content, so [method patch]-only: a mod
## cannot add a map for a definition to sit at. Their numbers are table
## coordinates and do not obey [constant FIRST_MOD_NUMBER].
const TABLE_KINDS: Array[StringName] = [
	KIND_ENCOUNTER, KIND_FISHING, KIND_TREEMON, KIND_BUG_CONTEST, KIND_ROAMING,
	KIND_FISHING_TIME,
]

## [method encounter_number]'s methods in the order it encodes them. `surf` is
## the runtime's name for the water table, which is what the reader takes.
const ENCOUNTER_METHODS: Array[StringName] = [
	&"grass", &"surf", &"swarm_grass", &"swarm_water",
]

## Every cartridge content number is one byte in all three games, so anything
## past a byte is unambiguously not the cartridge's, and a mod's numbers mean the
## same thing on each. A boundary taken from a per-game count (251 species, 66 or
## 67 trainer classes) would not. The cost: [Gen2SramAdapter] exports party
## species to a real `.sav` and cannot carry one. The project save is JSON.
const FIRST_MOD_NUMBER: int = 256

## What an omitted field gets, per kind. The field lists are the importer's own
## rows (`_import_species`, `_import_moves`, `_import_items`, `_import_trainers`).
const DEFAULTS: Dictionary = {
	KIND_SPECIES: {
		"name": "?",
		"stats": {
			"hp": 1, "attack": 1, "defense": 1,
			"speed": 1, "sp_attack": 1, "sp_defense": 1,
		},
		"types": [0, 0],
		"catch_rate": 255,
		"base_exp": 0,
		"held_items": [0, 0],
		# 127 is the cartridge's own even split; 255 would be genderless.
		"gender_ratio": 127,
		"hatch_cycles": 20,
		"growth_rate": 0,
		# 15 is EGG_NONE, so a defined species does not breed until it says so.
		"egg_groups": [15, 15],
		"tmhm": [0, 0, 0, 0, 0, 0, 0, 0],
		"evolutions": [],
		"learnset": [],
		"front_tiles": [7, 7],
		# White and black, which draws something legible and obviously not
		# coloured, the same answer bar_palette() gives an unknown name.
		"palette": {"normal": [0x7FFF, 0x0000], "shiny": [0x7FFF, 0x0000]},
	},
	KIND_MOVE: {
		"name": "?",
		"effect": 0,
		"power": 0,
		"type": 0,
		# $FF skips the accuracy roll, so an unspecified move always connects
		# rather than never doing.
		"accuracy": 255,
		"pp": 5,
		"effect_chance": 0,
	},
	KIND_ITEM: {
		"name": "?",
		"price": 0,
		"effect": 0,
		"parameter": -1,
		"permissions": 0,
		"pocket": 1,
		"field_menu": 0,
		"battle_menu": 0,
	},
	KIND_TRAINER: {
		"name": "?",
		"palette": [0x7FFF, 0x0000],
		"trainers": [],
		"attributes": {
			"item1": 0, "item2": 0, "base_reward": 0,
			"ai_move_weights": 0, "ai_item_switch": 0,
		},
		"dvs": Gen2BattleMon.PERFECT_DVS,
	},
}

static var _shared: Gen2ContentOverlay = null

## kind to number to the whole normalized row.
var _defined: Dictionary = {}
## kind to number to the fields that replace the cartridge's.
var _patched: Dictionary = {}
## kind to number to the mod id that claimed it, so a conflict can name both.
var _owners: Dictionary = {}


## Shared rather than per-cache: mods load before any cache is opened and apply
## to whichever game the player then picks.
static func shared() -> Gen2ContentOverlay:
	if _shared == null:
		_shared = Gen2ContentOverlay.new()
	return _shared


## [method Gen2ModHost.reset]'s, so a reload leaves no earlier content behind.
static func reset() -> void:
	_shared = null


## Asked first by every content read, so an unmodded game pays one check.
func is_empty() -> bool:
	return _defined.is_empty() and _patched.is_empty()


## Adds content at a number the cartridge does not use. [param row] is partial
## and the rest comes from [constant DEFAULTS]. Refused for a cartridge number,
## a kind outside [constant KINDS], or a number another mod claimed.
func define(kind: StringName, id: StringName, number: int, row: Dictionary) -> Dictionary:
	if not KINDS.has(kind):
		return {"ok": false, "reason": &"unknown_content_kind", "detail": String(kind)}
	if TABLE_KINDS.has(kind):
		return {"ok": false, "reason": &"content_kind_is_patch_only", "detail": String(kind)}
	if number < FIRST_MOD_NUMBER:
		return {
			"ok": false, "reason": &"reserved_content_number",
			"detail": "%s %d" % [kind, number],
		}
	var conflict: Dictionary = _claim(kind, id, number)
	if not bool(conflict.get("ok", false)):
		return conflict
	var defined: Dictionary = _defined.get(kind, {})
	defined[number] = _normalized(kind, number, row)
	_defined[kind] = defined
	return {"ok": true, "kind": kind, "number": number}


## Replaces named fields of a cartridge row. A Dictionary field merges, so
## [code]{"stats": {"speed": 120}}[/code] leaves the other five alone; an Array
## replaces whole, which is what a randomizer rewriting an encounter row's
## [code]slots[/code] wants. Refused for a number [method define] would take.
func patch(kind: StringName, id: StringName, number: int, fields: Dictionary) -> Dictionary:
	if not KINDS.has(kind):
		return {"ok": false, "reason": &"unknown_content_kind", "detail": String(kind)}
	if TABLE_KINDS.has(kind):
		if number < 0:
			return {
				"ok": false, "reason": &"not_a_table_row",
				"detail": "%s %d" % [kind, number],
			}
	elif number < 1 or number >= FIRST_MOD_NUMBER:
		return {
			"ok": false, "reason": &"not_a_cartridge_number",
			"detail": "%s %d" % [kind, number],
		}
	if fields.is_empty():
		return {"ok": false, "reason": &"empty_content_patch", "detail": String(kind)}
	var conflict: Dictionary = _claim(kind, id, number)
	if not bool(conflict.get("ok", false)):
		return conflict
	var patched: Dictionary = _patched.get(kind, {})
	patched[number] = fields.duplicate(true)
	_patched[kind] = patched
	return {"ok": true, "kind": kind, "number": number}


## The row a reader gets: a definition answers alone, a patch is folded onto
## [param base], anything else is the base untouched. A patch of a number this
## cartridge does not carry answers empty rather than conjuring a row, since
## Crystal's MYSTICALMAN is not a trainer class Gold has.
func resolve(kind: StringName, number: int, base: Dictionary) -> Dictionary:
	var defined: Dictionary = _defined.get(kind, {})
	if defined.has(number):
		return defined[number]
	if base.is_empty():
		return base
	var patched: Dictionary = _patched.get(kind, {})
	if not patched.has(number):
		return base
	return _merged(base, patched[number])


## Ascending, for a menu or dex listing showing mod content beside the
## cartridge's, since [method GameData.species_count] stays the cartridge's.
func defined_numbers(kind: StringName) -> Array[int]:
	var out: Array[int] = []
	for number: int in (_defined.get(kind, {}) as Dictionary).keys():
		out.append(number)
	out.sort()
	return out


## One map's table under one method, or -1 for a coordinate that cannot exist.
## Group and number are a byte each, so the three parts pack without colliding.
static func encounter_number(method: StringName, group: int, number: int) -> int:
	var at: int = ENCOUNTER_METHODS.find(method)
	if at < 0 or group < 0 or group > 0xFF or number < 0 or number > 0xFF:
		return -1
	return at * 0x10000 + group * 0x100 + number


## Which mod claimed [param number], for a launcher listing what it will change.
func owner_of(kind: StringName, number: int) -> StringName:
	return StringName((_owners.get(kind, {}) as Dictionary).get(number, &""))


## Drops everything [param id] claimed, definitions and patches both, and
## releases the numbers so it or another mod may claim them again.
##
## What a save switch needs: a run's patches belong to the save that created
## them, and the next save has to start from the cartridge rather than from the
## last one's shuffle. See [method Gen2ModHost.activate_save].
func clear_owner(id: StringName) -> void:
	for kind: Variant in _owners:
		var owners: Dictionary = _owners[kind]
		for number: Variant in owners.keys():
			if StringName(owners[number]) != id:
				continue
			owners.erase(number)
			(_defined.get(kind, {}) as Dictionary).erase(number)
			(_patched.get(kind, {}) as Dictionary).erase(number)


## One number, one mod: a collision is named rather than settled by load order.
func _claim(kind: StringName, id: StringName, number: int) -> Dictionary:
	var owners: Dictionary = _owners.get(kind, {})
	var owner: StringName = StringName(owners.get(number, &""))
	if owner != &"" and owner != id:
		return {
			"ok": false, "reason": &"duplicate_content",
			"detail": "%s %d: %s and %s" % [kind, number, owner, id],
		}
	owners[number] = id
	_owners[kind] = owners
	return {"ok": true}


## A partial definition filled out against [constant DEFAULTS]. The number is
## written last so a row cannot disagree with the key it is stored under.
func _normalized(kind: StringName, number: int, row: Dictionary) -> Dictionary:
	var out: Dictionary = _merged(DEFAULTS[kind], row)
	out["number"] = number
	return out


## [param over] laid on [param base], recursing into Dictionary values so a
## partial [code]stats[/code] keeps what it did not name. Arrays replace whole: a
## merged [code]types[/code] would read [code][15][/code] as "Ice and whatever
## was there".
func _merged(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for key: Variant in over:
		var value: Variant = over[key]
		if value is Dictionary and out.get(key, null) is Dictionary:
			out[key] = _merged(out[key], value)
		elif value is Dictionary or value is Array:
			out[key] = value.duplicate(true)
		else:
			out[key] = value
	return out
