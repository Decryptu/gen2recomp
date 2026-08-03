class_name Gen2BattleMon
extends RefCounted

## One Pokémon as a battle sees it: its stats, what it knows, how much of it is
## left, and how far its stats have been pushed around.
##
## [RefCounted] and scene-free, like everything below the renderer, so a whole
## battle can be fought inside a test with no display. It reads cartridge content
## through [GameData] and never touches a ROM.
##
## The stats are worked out once, when the Pokémon is built, because that is when
## the cartridge works them out: a level up recalculates them, and nothing else
## in a battle does. Stages are applied on the way out instead, to the unmodified
## stat every time, which is why they are stored separately rather than folded in.

## What a Pokémon can carry into a battle, which is the same four slots
## [Gen2Learnset] fills.
const MAX_MOVES: int = Gen2Learnset.MOVE_SLOTS

## The stats a stage can be applied to, in the order the cartridge keeps them.
const STAGED_STATS: Array = ["attack", "defense", "speed", "sp_attack", "sp_defense"]

## Accuracy and evasion are staged like a stat and are not stats: they have their
## own multiplier table, and there is no number behind them for a stage to
## multiply. They are kept in the same place because a battle raises and lowers
## all seven the same way. See [Gen2Accuracy].
const STAGED_ODDS: Array = ["accuracy", "evasion"]

## Every DV at its maximum. A caller that has not said otherwise gets a Pokémon
## that is as good as its species allows, which is the useful default for a test
## and for a screen with nothing behind it yet. A wild encounter rolls its own;
## see [method random_dvs].
const PERFECT_DVS: int = 0xFFFF

var data: GameData = null

var species: int = 0
var level: int = 1
var dvs: int = PERFECT_DVS
var stat_exp: Dictionary = {}

## Move numbers and the PP left in each, one to one.
var moves: Array = []
var pp: Array = []

var hp: int = 0
var stats: Dictionary = {}
var stages: Dictionary = {}


## Builds a Pokémon at a level, at full health, knowing [param moves].
##
## Returns null for a species the cache does not have, because a battle with a
## Pokémon that has no base stats is not something to paper over.
static func create(
	game_data: GameData,
	species_number: int,
	at_level: int,
	known_moves: Array = [],
	dv_word: int = PERFECT_DVS,
	trained: Dictionary = {}
) -> Gen2BattleMon:
	if game_data == null:
		return null
	if game_data.species(species_number).is_empty():
		return null

	var out := Gen2BattleMon.new()
	out.data = game_data
	out.species = species_number
	out.level = maxi(at_level, 1)
	out.dvs = dv_word
	out.stat_exp = trained
	out.moves = known_moves.slice(0, MAX_MOVES)
	out.reset_stages()
	out.recalculate()
	out.hp = out.max_hp()
	out.restore_pp()
	return out


## Four DVs rolled the way a wild encounter rolls them.
static func random_dvs(rng: RandomNumberGenerator) -> int:
	return Gen2Stats.pack_dvs(
		rng.randi_range(0, Gen2Stats.MAX_DV), rng.randi_range(0, Gen2Stats.MAX_DV),
		rng.randi_range(0, Gen2Stats.MAX_DV), rng.randi_range(0, Gen2Stats.MAX_DV)
	)


## Works the six stats out from the base stats, the DVs and the stat experience.
## Called when the Pokémon is built and after a level up, and at no other time:
## a stage is not a change to a stat, it is a lens on one.
func recalculate() -> void:
	var base: Dictionary = data.species(species).get("stats", {})
	stats = {
		"hp": _stat(base, "hp", Gen2Stats.hp_dv(dvs), "hp", true),
		"attack": _stat(base, "attack", Gen2Stats.attack_dv(dvs), "attack"),
		"defense": _stat(base, "defense", Gen2Stats.defense_dv(dvs), "defense"),
		"speed": _stat(base, "speed", Gen2Stats.speed_dv(dvs), "speed"),
		# Special Attack and Special Defense have base stats of their own but
		# share a DV and a stat experience total, which is the half of the
		# special split that Generation 2 did not finish.
		"sp_attack": _stat(base, "sp_attack", Gen2Stats.special_dv(dvs), "special"),
		"sp_defense": _stat(base, "sp_defense", Gen2Stats.special_dv(dvs), "special"),
	}
	hp = mini(hp, max_hp())


func _stat(
	base: Dictionary, key: String, dv: int, exp_key: String, is_hp: bool = false
) -> int:
	return Gen2Stats.calculate(
		int(base.get(key, 0)), dv, int(stat_exp.get(exp_key, 0)), level, is_hp
	)


## A stat as the damage formula sees it, with its stage applied.
func stat(key: String) -> int:
	var value: int = int(stats.get(key, 0))
	if not STAGED_STATS.has(key):
		return value
	return Gen2Stats.apply_stage(value, int(stages.get(key, 0)))


## A stat with no stage applied, which is what a critical hit uses when the
## stages would work against the attacker.
func unmodified_stat(key: String) -> int:
	return int(stats.get(key, 0))


func stage(key: String) -> int:
	return int(stages.get(key, 0))


## Moves a stage, and answers whether it actually moved: at the top or the bottom
## the cartridge says so rather than silently doing nothing.
func change_stage(key: String, by: int) -> bool:
	if not STAGED_STATS.has(key) and not STAGED_ODDS.has(key):
		return false
	var before: int = int(stages.get(key, 0))
	var after: int = clampi(before + by, Gen2Stats.MIN_STAGE, Gen2Stats.MAX_STAGE)
	stages[key] = after
	return after != before


func reset_stages() -> void:
	stages = {}
	for key: String in STAGED_STATS + STAGED_ODDS:
		stages[key] = 0


## The two type numbers, which are the same number twice for a single-type
## Pokémon: the cartridge fills both slots either way.
func types() -> Array:
	var entry: Array = data.species(species).get("types", [])
	return [int(entry[0]), int(entry[1])] if entry.size() >= 2 else []


func name_text() -> String:
	return String(data.species(species).get("name", ""))


func max_hp() -> int:
	return int(stats.get("hp", 1))


func is_fainted() -> bool:
	return hp <= 0


## Takes damage off, and answers how much actually landed. A Pokémon cannot be
## taken below zero, so the answer is not always the amount asked for, and a
## caller that wants to report the hit wants what landed.
func take_damage(amount: int) -> int:
	var dealt: int = clampi(amount, 0, hp)
	hp -= dealt
	return dealt


func heal(amount: int) -> int:
	var healed: int = clampi(amount, 0, max_hp() - hp)
	hp += healed
	return healed


## PP for a move slot, or zero for a slot that holds nothing.
func pp_left(slot: int) -> int:
	return int(pp[slot]) if slot >= 0 and slot < pp.size() else 0


func spend_pp(slot: int) -> void:
	if slot >= 0 and slot < pp.size():
		pp[slot] = maxi(int(pp[slot]) - 1, 0)


## Whether there is anything left to do with a move slot.
func can_use(slot: int) -> bool:
	return slot >= 0 and slot < moves.size() and pp_left(slot) > 0


## True when every slot is empty. The cartridge answers Struggle here; this
## answers the question and leaves that decision to the battle.
func is_out_of_pp() -> bool:
	for slot: int in moves.size():
		if can_use(slot):
			return false
	return true


func restore_pp() -> void:
	pp = []
	for move: int in moves:
		pp.append(int(data.move(int(move)).get("pp", 0)))
