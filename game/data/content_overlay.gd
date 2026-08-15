class_name Gen2ContentOverlay
extends RefCounted

## Content a mod adds or changes, consulted ahead of the cartridge's own tables.
##
## [GameData] funnels every species, move, item and trainer read through one
## place, so this is the one place that has to answer to add a Pokémon or
## rebalance a move. Nothing downstream knows a mod exists: a defined species has
## a learnset, evolutions and TM flags because those live on the species row, and
## the engine reads them the way it reads Pikachu's.
##
## Two operations, deliberately distinct:
##
## - [method define] adds content at a number the cartridge does not use.
## - [method patch] changes fields of a row the cartridge does use.
##
## Definitions are normalized on the way in, against [constant DEFAULTS], because
## readers index these rows directly: [method GameData.palette] reads
## [code]palette.normal[/code] and [method GameData.species_pic] reads
## [code]front_tiles[/code], and a definition that omitted either would crash the
## reader rather than draw wrong. A mod supplies what it cares about.

## The content kinds a mod may reach. Types are not one of them: the matchup
## lookup keys on [constant RomLayout.TYPE_COUNT], so a twenty-ninth type would
## renumber every pair already in the chart.
const KIND_SPECIES: StringName = &"species"
const KIND_MOVE: StringName = &"move"
const KIND_ITEM: StringName = &"item"
const KIND_TRAINER: StringName = &"trainer"
## One map's wild encounter record, the row [method GameData.world_encounter]
## answers, numbered with [method encounter_number].
const KIND_ENCOUNTER: StringName = &"encounter"
## One fishing group, the row [method GameData.world_fishing_group] answers,
## numbered with the group number a map header carries.
const KIND_FISHING: StringName = &"fishing"
const KINDS: Array[StringName] = [
	KIND_SPECIES, KIND_MOVE, KIND_ITEM, KIND_TRAINER, KIND_ENCOUNTER, KIND_FISHING,
]

## The kinds that are a cartridge table rather than numbered content, and are
## therefore [method patch]-only: a mod cannot add a map or a map header, so
## there is no row for a [method define] to sit at. Their numbers are table
## coordinates and do not obey [constant FIRST_MOD_NUMBER].
const TABLE_KINDS: Array[StringName] = [KIND_ENCOUNTER, KIND_FISHING]

## The methods [method encounter_number] can name, in the order it encodes them.
## `surf` is the runtime's name for the cartridge's water table, which is what
## [method GameData.world_encounter] takes.
const ENCOUNTER_METHODS: Array[StringName] = [
	&"grass", &"surf", &"swarm_grass", &"swarm_water",
]

## The first number a mod may define. Every cartridge content number is one byte,
## in all three games, so a number that does not fit in one is unambiguously not
## the cartridge's. That is what makes a mod's own numbers mean the same thing on
## Gold, Silver and Crystal, which a boundary derived from a per-game count
## (251 species, 66 or 67 trainer classes) would not.
##
## The cost is that a mod number does not fit the cartridge's byte-wide storage:
## [Gen2SramAdapter] exports party species to a real `.sav` and cannot carry one.
## The project save is JSON and carries them fine.
const FIRST_MOD_NUMBER: int = 256

## What a definition that omits a field gets instead, per kind. The field lists
## are the importer's own rows (`_import_species`, `_import_moves`,
## `_import_items`, `_import_trainers`), so a definition is a cartridge row with
## the parts a mod did not care about filled in.
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


## The overlay [GameData] consults. Shared rather than per-cache because mods
## load before any cache is opened and their content applies to whichever game
## the player then picks.
static func shared() -> Gen2ContentOverlay:
	if _shared == null:
		_shared = Gen2ContentOverlay.new()
	return _shared


## Discards every registration. [method Gen2ModHost.reset] calls this, so
## reloading the mod list does not leave the last load's content behind.
static func reset() -> void:
	_shared = null


## Whether anything is registered at all. Every content read asks this first, so
## a game with no mods pays one dictionary check per species lookup.
func is_empty() -> bool:
	return _defined.is_empty() and _patched.is_empty()


## Adds content at a number the cartridge does not use.
##
## [param row] is a partial row: whatever it does not carry comes from
## [constant DEFAULTS], so a species defined with a name, stats and a learnset is
## a complete species. Refused if the number is a cartridge number, if the kind
## is not one of [constant KINDS], or if another mod already claimed it.
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


## Replaces named fields of a cartridge row: a move's power, a species' types, an
## item's price.
##
## Only the fields given change, and a Dictionary field merges rather than
## replacing, so patching [code]{"stats": {"speed": 120}}[/code] leaves the other
## five stats alone. An Array field replaces whole, which is what a randomizer
## rewriting an encounter row's [code]slots[/code] wants. Refused for a number a
## mod would have to [method define].
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


## The row a reader gets for [param number], given the cartridge's own
## [param base]. A definition answers on its own; a patch is folded onto the
## base; anything else is the base untouched.
##
## A patch of a number this cartridge does not carry answers empty rather than
## conjuring a row out of the patch alone: Crystal's MYSTICALMAN is not a trainer
## class Gold has, and a mod patching it must not invent one there.
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


## Every number defined for [param kind], in ascending order. What a menu or a
## dex listing walks to show mod content beside the cartridge's, since
## [method GameData.species_count] stays the cartridge's own count.
func defined_numbers(kind: StringName) -> Array[int]:
	var out: Array[int] = []
	for number: int in (_defined.get(kind, {}) as Dictionary).keys():
		out.append(number)
	out.sort()
	return out


## The [constant KIND_ENCOUNTER] number for one map's table under one method, or
## -1 for a method or a map coordinate that cannot exist. A map group and number
## are each one byte, so the three parts pack without colliding and a mod's
## patch means the same thing on all three cartridges.
static func encounter_number(method: StringName, group: int, number: int) -> int:
	var at: int = ENCOUNTER_METHODS.find(method)
	if at < 0 or group < 0 or group > 0xFF or number < 0 or number > 0xFF:
		return -1
	return at * 0x10000 + group * 0x100 + number


## Which mod claimed [param number], or an empty name. For a launcher listing
## what changed the game it is about to start.
func owner_of(kind: StringName, number: int) -> StringName:
	return StringName((_owners.get(kind, {}) as Dictionary).get(number, &""))


## One number, one mod. Two mods reaching for the same species is exactly the
## conflict a player wants named rather than resolved by load order.
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
## partial [code]stats[/code] keeps the stats it did not name. Arrays replace
## whole: a two-element [code]types[/code] merged element-wise would make
## [code][15][/code] mean "Ice and whatever was there", which is not what writing
## it says.
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
