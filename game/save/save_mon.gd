class_name Gen2SaveMon
extends RefCounted

## Persistent Pokémon data kept by a save slot.
##
## The fields mirror the stable part of Generation 2's box and party records:
## identity, moves, experience, training, DVs, PP, current HP and status. A
## battle reconstructs derived stats from the identity and training fields, so
## cached stats and volatile battle state are deliberately not stored here.

const MAX_MOVES: int = Gen2BattleMon.MAX_MOVES
const MAX_EXP: int = Gen2Experience.MAX_EXP
const STAT_EXP_KEYS: Array = ["hp", "attack", "defense", "speed", "special"]

var species: int = 0
var item: int = 0
var moves: Array = [0, 0, 0, 0]
var pp: Array = [0, 0, 0, 0]
var ot_id: int = 0
var exp: int = 0
var stat_exp: Dictionary = {
	"hp": 0,
	"attack": 0,
	"defense": 0,
	"speed": 0,
	"special": 0,
}
var dvs: int = Gen2BattleMon.PERFECT_DVS
var happiness: int = 0
var pokerus: int = 0
var caught_time: int = 0
var caught_gender: int = 0
var caught_level: int = 0
var caught_location: int = 0
var level: int = 1
var hp: int = 0
var status: int = Gen2Status.NONE
var nickname: String = ""
var original_trainer: String = ""


func to_dict() -> Dictionary:
	var saved_stat_exp: Dictionary = {}
	for key: String in STAT_EXP_KEYS:
		saved_stat_exp[key] = int(stat_exp.get(key, 0))
	return {
		"species": species,
		"item": item,
		"moves": moves.duplicate(),
		"pp": pp.duplicate(),
		"ot_id": ot_id,
		"exp": exp,
		"stat_exp": saved_stat_exp,
		"dvs": dvs,
		"happiness": happiness,
		"pokerus": pokerus,
		"caught_time": caught_time,
		"caught_gender": caught_gender,
		"caught_level": caught_level,
		"caught_location": caught_location,
		"level": level,
		"hp": hp,
		"status": status,
		"nickname": nickname,
		"original_trainer": original_trainer,
	}


## Parses shape only. Range and cartridge-content checks belong to
## [Gen2SaveValidator], where the selected [GameData] is available.
static func from_dict(raw: Variant) -> Gen2SaveMon:
	if not raw is Dictionary:
		return null
	var source: Dictionary = raw
	var out := Gen2SaveMon.new()
	out.species = int(source.get("species", 0))
	out.item = int(source.get("item", 0))
	out.moves = _fixed_int_array(source.get("moves", []), MAX_MOVES)
	out.pp = _fixed_int_array(source.get("pp", []), MAX_MOVES)
	out.ot_id = int(source.get("ot_id", 0))
	out.exp = int(source.get("exp", 0))
	var raw_stat_exp: Variant = source.get("stat_exp", {})
	if raw_stat_exp is Dictionary:
		for key: String in STAT_EXP_KEYS:
			out.stat_exp[key] = int((raw_stat_exp as Dictionary).get(key, 0))
	out.dvs = int(source.get("dvs", Gen2BattleMon.PERFECT_DVS))
	out.happiness = int(source.get("happiness", 0))
	out.pokerus = int(source.get("pokerus", 0))
	out.caught_time = int(source.get("caught_time", 0))
	out.caught_gender = int(source.get("caught_gender", 0))
	out.caught_level = int(source.get("caught_level", 0))
	out.caught_location = int(source.get("caught_location", 0))
	out.level = int(source.get("level", 1))
	out.hp = int(source.get("hp", 0))
	out.status = int(source.get("status", Gen2Status.NONE))
	out.nickname = String(source.get("nickname", ""))
	out.original_trainer = String(source.get("original_trainer", ""))
	return out


static func _fixed_int_array(value: Variant, size: int) -> Array:
	var out: Array = []
	var source: Array = value if value is Array else []
	for index: int in size:
		out.append(int(source[index]) if index < source.size() else 0)
	return out
