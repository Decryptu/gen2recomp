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

## Total experience, on this species' own growth curve. Seeded at
## [method create] to exactly what [param at_level] starts with, not zero: a
## level 7 Pidgey is created already carrying level 7's own threshold, the same
## way the cartridge's box and party screens always agree with a Pokémon's
## level rather than a fresh one reading level 1 until its first battle.
var exp: int = 0

## Move numbers and the PP left in each, one to one.
var moves: Array = []
var pp: Array = []

var hp: int = 0
var stats: Dictionary = {}
var stages: Dictionary = {}

## The status byte, as the cartridge packs it: see [Gen2Status]. It survives a
## switch and a battle, unlike a stage, which is why it sits with the health
## rather than with them.
var status: int = Gen2Status.NONE

## The second byte: see [Gen2Substatus]. Unlike [member status] this one clears
## on a switch, along with the counters below it, which is what makes it
## volatile rather than a status.
var substatus: int = Gen2Substatus.NONE

## How many turns of confusion are left, meaningful only while
## [constant Gen2Substatus.CONFUSED] is set.
var confusion_turns: int = 0

## The move a two-turn move locked this Pokémon into, meaningful only while
## [constant Gen2Substatus.CHARGING] is set. Zero means nothing is charged.
var charged_move: int = 0

## How many turns a badly poisoned Pokémon has been poisoned, which is what
## Toxic's damage ramps on. Zero unless actually toxic.
var toxic_counter: int = 0

## The item this Pokémon is holding, by item number, or zero for none. Carried
## through from a trainer's party or a save; nothing in the engine reads it yet.
var item: int = 0


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
	trained: Dictionary = {},
	held_item: int = 0
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
	out.item = held_item
	out.reset_stages()
	out.recalculate()
	out.hp = out.max_hp()
	out.restore_pp()
	out.exp = Gen2Experience.total_exp_at(out.growth_rate(), out.level)
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


## A stat as the damage formula sees it, with its stage and then its status
## applied.
##
## The order is the cartridge's: it copies the stat, applies the stage, and then
## halves the Attack of a burned Pokémon and quarters the Speed of a paralysed
## one. Both land on the same copy the stages did, which is what decides that a
## critical hit reading [method unmodified_stat] is free of the burn as well as of
## the stages.
func stat(key: String) -> int:
	var value: int = int(stats.get(key, 0))
	if not STAGED_STATS.has(key):
		return value

	var out: int = Gen2Stats.apply_stage(value, int(stages.get(key, 0)))
	if key == "attack" and Gen2Status.has(status, Gen2Status.BURN):
		out = Gen2Status.apply_burn(out)
	elif key == "speed" and Gen2Status.has(status, Gen2Status.PARALYSIS):
		out = Gen2Status.apply_paralysis(out)
	return out


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


## Clears everything [Gen2Substatus] holds, and the counters that go with it.
## Called on a switch, alongside but separately from [method reset_stages]:
## Haze resets the stages on both sides without touching either one's
## volatiles, so the two have to stay two calls rather than become one.
func reset_volatile() -> void:
	substatus = Gen2Substatus.NONE
	confusion_turns = 0
	charged_move = 0
	toxic_counter = 0


## The two type numbers, which are the same number twice for a single-type
## Pokémon: the cartridge fills both slots either way.
func types() -> Array:
	var entry: Array = data.species(species).get("types", [])
	return [int(entry[0]), int(entry[1])] if entry.size() >= 2 else []


func name_text() -> String:
	return String(data.species(species).get("name", ""))


## The curve [Gen2Experience] should read this species on, or medium fast for
## a species the cache does not have: the same fallback [method recalculate]
## already makes for a missing base stats entry.
func growth_rate() -> int:
	return int(data.species(species).get("growth_rate", Gen2Experience.GROWTH_MEDIUM_FAST))


func base_exp() -> int:
	return int(data.species(species).get("base_exp", 0))


## The five base stats [Gen2Experience.stat_exp_gain] wants when this Pokémon
## is the one fainting, keyed the way [member stat_exp] already is. Special
## Attack's base value fills the shared [code]"special"[/code] slot, never
## Special Defense's: see [constant Gen2Experience.STAT_EXP_KEYS] for why the
## cartridge reads it that way.
func base_stat_exp_shape() -> Dictionary:
	var base: Dictionary = data.species(species).get("stats", {})
	return {
		"hp": int(base.get("hp", 0)),
		"attack": int(base.get("attack", 0)),
		"defense": int(base.get("defense", 0)),
		"speed": int(base.get("speed", 0)),
		"special": int(base.get("sp_attack", 0)),
	}


## Adds experience, capped the way the cartridge's own three-byte total is.
func gain_exp(amount: int) -> void:
	exp = clampi(exp + amount, 0, Gen2Experience.MAX_EXP)


## Adds a level's worth of stat experience, one entry per key in [param gains],
## each capped the way a stat's own training already is in [method recalculate].
func gain_stat_exp(gains: Dictionary) -> void:
	for key: String in gains:
		var total: int = int(stat_exp.get(key, 0)) + int(gains[key])
		stat_exp[key] = clampi(total, 0, Gen2Stats.MAX_STAT_EXP)


## The level [member exp] has actually reached on this species' curve, which is
## not necessarily [member level]: a caller awards experience first and asks
## this after, one level at a time, so that a move learned partway up a
## multi-level jump is offered at the level that actually teaches it.
func level_for_exp() -> int:
	return Gen2Experience.level_for_exp(growth_rate(), exp)


## Raises the level by exactly one and recalculates every stat from it, the
## same call [method create] makes and the only other time this is meant to
## happen. Current HP gains the *difference* the new max makes, rather than
## being refilled or left where it was: the cartridge adds the two maximums'
## delta onto whatever HP was sitting at, so a Pokémon one hit from fainting
## before the level up is still one hit from fainting after it, just against a
## bigger hit.
func level_up() -> void:
	if level >= Gen2Experience.MAX_LEVEL:
		return
	var before_max: int = max_hp()
	level += 1
	recalculate()
	hp += max_hp() - before_max


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


## Learns a move into an empty slot, with its own full PP. Refuses if every
## slot is already taken: [method Gen2Battle.learn_move] is what overwrites one
## instead, because which one to give up is not this class's decision.
func learn_move(move: int) -> bool:
	if moves.size() >= MAX_MOVES:
		return false
	moves.append(move)
	pp.append(int(data.move(move).get("pp", 0)))
	return true


## Overwrites [param slot] with [param move], full PP, whatever was there.
func replace_move(slot: int, move: int) -> bool:
	if slot < 0 or slot >= moves.size():
		return false
	moves[slot] = move
	pp[slot] = int(data.move(move).get("pp", 0))
	return true


func restore_pp() -> void:
	pp = []
	for move: int in moves:
		pp.append(int(data.move(int(move)).get("pp", 0)))
