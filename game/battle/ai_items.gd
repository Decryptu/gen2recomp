class_name Gen2AIItems
extends RefCounted

## What a trainer reaches into its bag for, and what happens when it does.
##
## `AI_TryItem` and the `EnemyUsed*` routines in
## [code]engine/battle/ai/items.asm[/code]. A trainer class carries at most two
## item numbers ([code]TRNATTR_ITEM1[/code] and [code]TRNATTR_ITEM2[/code],
## already in the cache as [method GameData.trainer_attributes]), and the same
## class's [code]TRNATTR_AI_ITEM_SWITCH[/code] word decides how freely they are
## spent.
##
## Only the enemy has any of this: the player's own pack has no X items and no
## in-battle healing beyond what [Gen2HeldItem] does on its own.

## The thirteen items the AI knows, at their cartridge numbers.
const FULL_RESTORE: int = 0x0E
const MAX_POTION: int = 0x0F
const HYPER_POTION: int = 0x10
const SUPER_POTION: int = 0x11
const POTION: int = 0x12
const X_ACCURACY: int = 0x21
const FULL_HEAL: int = 0x26
const GUARD_SPEC: int = 0x29
const DIRE_HIT: int = 0x2C
const X_ATTACK: int = 0x31
const X_DEFEND: int = 0x33
const X_SPEED: int = 0x34
const X_SPECIAL: int = 0x35

## `AI_Items`, in its own order. The table decides which of a trainer's two items
## is considered first, not the order the trainer carries them in, and the first
## one whose own check says yes is the one spent.
const ORDER: Array[int] = [
	FULL_RESTORE, MAX_POTION, HYPER_POTION, SUPER_POTION, POTION,
	X_ACCURACY, FULL_HEAL, GUARD_SPEC, DIRE_HIT,
	X_ATTACK, X_DEFEND, X_SPEED, X_SPECIAL,
]

## What each potion puts back, and what the two that fill the bar are told apart
## by. Full Restore and Max Potion restore everything; the other three add a flat
## number, capped at the maximum.
const POTION_AMOUNTS: Dictionary = {
	HYPER_POTION: 200,
	SUPER_POTION: 50,
	POTION: 20,
}

## The four X items that raise a stage by one, and which stage each raises.
## X Special raises Special Attack alone: the cartridge passes `SP_ATTACK`, and
## nothing gives Special Defense back.
const X_STATS: Dictionary = {
	X_ATTACK: "attack",
	X_DEFEND: "defense",
	X_SPEED: "speed",
	X_SPECIAL: "sp_attack",
}

## The three X items that set a flag rather than a stage.
const X_SUBSTATUSES: Dictionary = {
	X_ACCURACY: Gen2Substatus.X_ACCURACY,
	GUARD_SPEC: Gen2Substatus.MIST,
	DIRE_HIT: Gen2Substatus.FOCUS_ENERGY,
}

## The raw thresholds out of 256 the source writes as adjusted percentages. Kept
## as the numbers rather than the percentages because the adjustments are the
## point: `20 percent - 1` is 50, not 51.
const CHANCE_20: int = 50
const CHANCE_50: int = 128

## How long a Toxic has to have been running before `.StatusCheckContext` will
## spend a cure on it at all.
const TOXIC_PATIENCE: int = 4


## The item this trainer spends this turn, or zero for none.
##
## [param items] is the class's two item numbers, already emptied of anything
## spent earlier in the battle. [param flags] is the class's
## [code]ai_item_switch[/code] word.
static func choose(
	user: Gen2BattleMon, items: Array, flags: int, turns_taken: int, rng: RandomNumberGenerator
) -> int:
	for item: int in ORDER:
		if not items.has(item):
			continue
		if _will_use(item, user, flags, turns_taken, rng):
			return item
	return 0


## Whether the active Pokémon is at least as high a level as anything else in
## its own party, which `.IsHighestLevel` requires before any item is considered.
## A trainer leading with its weakest does not open the bag for it.
static func is_highest_level(party: Gen2Party) -> bool:
	var active: Gen2BattleMon = party.active_mon()
	if active == null:
		return false
	for index: int in party.size():
		var member: Gen2BattleMon = party.at(index)
		if member != null and member.level > active.level:
			return false
	return true


## Spends [param item] on [param user], answering what changed so a screen can
## say it. The decision is already made by here: this is the `EnemyUsed*` half.
static func apply(user: Gen2BattleMon, item: int) -> Dictionary:
	if POTION_AMOUNTS.has(item):
		return {"healed": user.heal(int(POTION_AMOUNTS[item]))}

	if item == MAX_POTION:
		return {"healed": user.heal(user.max_hp())}

	if item == FULL_RESTORE:
		# `AI_HealStatus` and then the confusion, which is the one thing Full
		# Restore clears that Full Heal does not: `EnemyUsedFullHeal` never
		# touches `SUBSTATUS_CONFUSED`, which pret documents as a bug rather
		# than a rule.
		var cured: bool = _heal_status(user)
		var unconfused: bool = Gen2Substatus.has(user.substatus, Gen2Substatus.CONFUSED)
		user.substatus &= ~Gen2Substatus.CONFUSED
		user.confusion_turns = 0
		return {
			"healed": user.heal(user.max_hp()),
			"cured": cured, "unconfused": unconfused,
		}

	if item == FULL_HEAL:
		return {"cured": _heal_status(user)}

	if X_SUBSTATUSES.has(item):
		user.substatus |= int(X_SUBSTATUSES[item])
		return {"substatus": int(X_SUBSTATUSES[item])}

	if X_STATS.has(item):
		var stat: String = String(X_STATS[item])
		var raised: bool = user.stage(stat) < Gen2Stats.MAX_STAGE
		if raised:
			user.change_stage(stat, 1)
		return {"stat": stat, "raised": raised}

	return {}


## `AI_HealStatus`: the status byte and Toxic's ramp, and nothing else. Sleep,
## freeze, burn, poison and paralysis all go; Nightmare stays, and so does the
## Attack or Speed a burn or a paralysis was already costing, both of which pret
## documents as bugs.
static func _heal_status(user: Gen2BattleMon) -> bool:
	var had: bool = Gen2Status.is_afflicted(user.status)
	user.status = Gen2Status.NONE
	user.toxic_counter = 0
	return had


static func _will_use(
	item: int, user: Gen2BattleMon, flags: int, turns_taken: int, rng: RandomNumberGenerator
) -> bool:
	if item == FULL_RESTORE:
		# `.FullRestore` takes the HP gate first and, only for a class that reads
		# the context, will spend one on a status at full health instead.
		if _heal_gate(user, flags, rng):
			return true
		if not _has(flags, RomLayout.CONTEXT_USE):
			return false
		return _status_gate(user, flags, rng)

	if item == FULL_HEAL:
		return _status_gate(user, flags, rng)

	if POTION_AMOUNTS.has(item) or item == MAX_POTION:
		return _heal_gate(user, flags, rng)

	return _x_item_gate(flags, turns_taken, rng)


## `.Status`: nothing to cure means nothing to spend, and a class that reads the
## context spends only on the statuses worth curing.
static func _status_gate(user: Gen2BattleMon, flags: int, rng: RandomNumberGenerator) -> bool:
	if not Gen2Status.is_afflicted(user.status):
		return false

	if _has(flags, RomLayout.CONTEXT_USE):
		# A Toxic that has been ramping for four turns is worth curing on a coin
		# flip; otherwise only sleep and freeze, the two that cost whole turns.
		if user.toxic_counter >= TOXIC_PATIENCE and _roll(rng, CHANCE_50):
			return true
		return Gen2Status.is_asleep(user.status) \
			or Gen2Status.has(user.status, Gen2Status.FREEZE)

	if _has(flags, RomLayout.ALWAYS_USE):
		return true
	return _roll(rng, CHANCE_20)


## `.HealItem`, the gate every potion shares. Above half health nothing is ever
## spent; below a quarter it always is; in between it depends on the class.
static func _heal_gate(user: Gen2BattleMon, flags: int, rng: RandomNumberGenerator) -> bool:
	if _has(flags, RomLayout.CONTEXT_USE):
		# `.CheckHalfOrQuarterHP`
		if _above_half(user):
			return false
		if not _above_quarter(user):
			return true
		return _roll(rng, CHANCE_20)

	if _above_half(user):
		return false

	if _has(flags, RomLayout.UNKNOWN_USE):
		# `.CheckQuarterHP`: this branch alone refuses while still above a
		# quarter, so it is strictly stingier than the one below it.
		if _above_quarter(user):
			return false
		return not _roll(rng, CHANCE_20)

	if not _above_quarter(user):
		return true
	return _roll(rng, CHANCE_50)


## `.XItem`: an X item is worth using on the turn the Pokémon came out and
## almost never after it, since the point is to set up before trading hits.
static func _x_item_gate(flags: int, turns_taken: int, rng: RandomNumberGenerator) -> bool:
	if turns_taken > 0:
		if not _has(flags, RomLayout.ALWAYS_USE):
			return false
		return _roll(rng, CHANCE_20)

	if _has(flags, RomLayout.ALWAYS_USE):
		return true
	if _roll(rng, CHANCE_50):
		return false
	if _has(flags, RomLayout.CONTEXT_USE):
		return true
	return not _roll(rng, CHANCE_50)


static func _has(flags: int, flag: int) -> bool:
	return (flags & flag) != 0


## True [param threshold] times out of 256, which is what `cp` against a
## `Random` byte answers.
static func _roll(rng: RandomNumberGenerator, threshold: int) -> bool:
	return rng.randi_range(0, 255) < threshold


static func _above_half(mon: Gen2BattleMon) -> bool:
	return mon.hp * 2 > mon.max_hp()


static func _above_quarter(mon: Gen2BattleMon) -> bool:
	return mon.hp * 4 > mon.max_hp()
