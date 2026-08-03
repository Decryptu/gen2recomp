class_name Gen2MoveEffect
extends RefCounted

## What each move's effect byte makes it do, as a list of commands.
##
## This is the table the cartridge keeps in [code]data/moves/effects.asm[/code],
## and the sequences below are meant to be read against it. Every move in these
## games is one of these lists; a move number picks an effect byte and an effect
## byte picks a list.
##
## Almost every list is [constant NORMAL_HIT] with something inserted. That is
## the whole reason for keeping the shape: burn, paralysis, the stat changes,
## the multi-hit moves and the rest arrive as commands added to a list rather
## than as branches added to the turn loop, and none of them reaches
## [Gen2Battle], which knows only how to run a list.
##
## The effect bytes themselves are the cartridge's own, out of the move table.

## The effect bytes with a list of their own. The numbers are the cartridge's,
## out of the move table.
##
## Recoil is here because Struggle needs it: a Pokémon with nothing left to spend
## has to be able to hurt itself, or two empty Pokémon never finish their battle.
## The rest are the status conditions, in the two shapes they come in: a move
## whose whole purpose is the status, and a move that does damage and leaves
## something behind on a roll.
const SLEEP: int = 1
const POISON_HIT: int = 2
const BURN_HIT: int = 4
const FREEZE_HIT: int = 5
const PARALYZE_HIT: int = 6
const TOXIC: int = 33
const RECOIL_HIT: int = 48
const POISON: int = 66
const PARALYZE: int = 67

## An ordinary attack: say it, spend it, work it out, roll it, apply it, and see
## who is standing. Everything else is this with steps moved.
const NORMAL_HIT: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.END_MOVE,
]

## The same list with the recoil taken between the hit and the faint, so that an
## attacker that goes down to its own recoil is reported alongside the defender
## rather than after it.
const RECOIL_HIT_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.RECOIL,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.END_MOVE,
]

## A move that is nothing but a status: no damage, and the status is the whole of
## what it does. Sleep is the odd one of the three, because nothing is immune to
## it: there is no matchup step in its list, where the other two have one.
const SLEEP_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.SLEEP_TARGET,
	Gen2EffectCommands.END_MOVE,
]

const POISON_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.POISON_TARGET,
	Gen2EffectCommands.END_MOVE,
]

## The matchup before the roll rather than after it, which is the order the
## cartridge lists them in and the reason Thunder Wave against a Ground type says
## it had no effect rather than that it missed.
const PARALYZE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.PARALYZE_TARGET,
	Gen2EffectCommands.END_MOVE,
]


## An attack that leaves something behind if its roll comes up. The damage is
## done either way: the roll sits between the hit and the status, so a failed one
## costs [param trailing] and nothing else. Most callers leave one command
## behind; a stat change leaves two, the change and its message, because a
## secondary effect never carries the fail-text step a status move's own
## sequence has.
static func _secondary(trailing: Array) -> Array:
	return [
		Gen2EffectCommands.USED_MOVE_TEXT,
		Gen2EffectCommands.DO_TURN,
		Gen2EffectCommands.DAMAGE_CALC,
		Gen2EffectCommands.CHECK_IMMUNE,
		Gen2EffectCommands.CHECK_HIT,
		Gen2EffectCommands.EFFECT_CHANCE,
		Gen2EffectCommands.APPLY_DAMAGE,
		Gen2EffectCommands.CHECK_FAINT,
	] + trailing + [Gen2EffectCommands.END_MOVE]


## Where each run of seven starts, in the cartridge's own numbering. The seven
## across a run are [constant Gen2BattleMon.STAGED_STATS] followed by
## [constant Gen2BattleMon.STAGED_ODDS], which is also the order
## [Gen2EffectCommands] keeps its per-stat command lists in, so a run and an
## index into those lists are the same number.
const STAT_UP_BASE: int = 10
const STAT_DOWN_BASE: int = 18
const STAT_UP_2_BASE: int = 50
const STAT_DOWN_2_BASE: int = 58
const STAT_DOWN_HIT_BASE: int = 68
const STAT_RUN_LENGTH: int = 7

## The two effect bytes a run does not reach. Metal Claw raises the user's
## Attack on a roll and Ancientpower raises all five of them, and neither sits
## in a run of its own: 139 falls where an eighth "down by one, on a hit" stat
## would if there were one, and 140 is the byte after it.
const ATTACK_UP_HIT: int = 139
const ALL_STATS_UP_HIT: int = 140

const STAT_UP_COMMANDS: Array = [
	Gen2EffectCommands.ATTACK_UP, Gen2EffectCommands.DEFENSE_UP,
	Gen2EffectCommands.SPEED_UP, Gen2EffectCommands.SP_ATTACK_UP,
	Gen2EffectCommands.SP_DEFENSE_UP, Gen2EffectCommands.ACCURACY_UP,
	Gen2EffectCommands.EVASION_UP,
]
const STAT_UP_2_COMMANDS: Array = [
	Gen2EffectCommands.ATTACK_UP_2, Gen2EffectCommands.DEFENSE_UP_2,
	Gen2EffectCommands.SPEED_UP_2, Gen2EffectCommands.SP_ATTACK_UP_2,
	Gen2EffectCommands.SP_DEFENSE_UP_2, Gen2EffectCommands.ACCURACY_UP_2,
	Gen2EffectCommands.EVASION_UP_2,
]
const STAT_DOWN_COMMANDS: Array = [
	Gen2EffectCommands.ATTACK_DOWN, Gen2EffectCommands.DEFENSE_DOWN,
	Gen2EffectCommands.SPEED_DOWN, Gen2EffectCommands.SP_ATTACK_DOWN,
	Gen2EffectCommands.SP_DEFENSE_DOWN, Gen2EffectCommands.ACCURACY_DOWN,
	Gen2EffectCommands.EVASION_DOWN,
]
const STAT_DOWN_2_COMMANDS: Array = [
	Gen2EffectCommands.ATTACK_DOWN_2, Gen2EffectCommands.DEFENSE_DOWN_2,
	Gen2EffectCommands.SPEED_DOWN_2, Gen2EffectCommands.SP_ATTACK_DOWN_2,
	Gen2EffectCommands.SP_DEFENSE_DOWN_2, Gen2EffectCommands.ACCURACY_DOWN_2,
	Gen2EffectCommands.EVASION_DOWN_2,
]

## A status move that only raises a stat: it cannot miss, so there is no roll in
## its list, only the change, its message, and the text for when it was already
## at the top.
static func _stat_up_sequence(command: StringName) -> Array:
	return [
		Gen2EffectCommands.USED_MOVE_TEXT,
		Gen2EffectCommands.DO_TURN,
		command,
		Gen2EffectCommands.STAT_UP_MESSAGE,
		Gen2EffectCommands.STAT_UP_FAIL_TEXT,
		Gen2EffectCommands.END_MOVE,
	]


## A status move that lowers the foe's stat: it can miss, which is the one
## difference from the list above and the reason Screech has a roll where Swords
## Dance does not.
static func _stat_down_sequence(command: StringName) -> Array:
	return [
		Gen2EffectCommands.USED_MOVE_TEXT,
		Gen2EffectCommands.DO_TURN,
		Gen2EffectCommands.CHECK_HIT,
		command,
		Gen2EffectCommands.STAT_DOWN_MESSAGE,
		Gen2EffectCommands.STAT_DOWN_FAIL_TEXT,
		Gen2EffectCommands.END_MOVE,
	]


## The seven-wide runs, walked once into a dictionary rather than written out by
## hand. A wrong entry here would be a wrong number in a table that self-checks
## nothing, which is why [code]tools/dump_tables.gd[/code] and the published
## effect list are what settled the five bases in the first place, not this
## function.
static func _stat_sequences() -> Dictionary:
	var out: Dictionary = {}
	for offset: int in STAT_RUN_LENGTH:
		out[STAT_UP_BASE + offset] = _stat_up_sequence(STAT_UP_COMMANDS[offset])
		out[STAT_UP_2_BASE + offset] = _stat_up_sequence(STAT_UP_2_COMMANDS[offset])
		out[STAT_DOWN_BASE + offset] = _stat_down_sequence(STAT_DOWN_COMMANDS[offset])
		out[STAT_DOWN_2_BASE + offset] = _stat_down_sequence(STAT_DOWN_2_COMMANDS[offset])
		out[STAT_DOWN_HIT_BASE + offset] = _secondary([
			STAT_DOWN_COMMANDS[offset], Gen2EffectCommands.STAT_DOWN_MESSAGE,
		])
	out[ATTACK_UP_HIT] = _secondary([
		STAT_UP_COMMANDS[0], Gen2EffectCommands.STAT_UP_MESSAGE,
	])
	out[ALL_STATS_UP_HIT] = _secondary([Gen2EffectCommands.ALL_STATS_UP])
	return out


## Effect bytes that do something other than [constant NORMAL_HIT]. An effect
## that is not in here is an ordinary attack, which is what most of the table is
## and what an effect nobody has written yet falls back to.
##
## Toxic shares the ordinary poison list. On the cartridge it is a poison that
## doubles every turn, counted on a substatus that nothing here carries yet, so
## it is currently the weaker thing it is closest to rather than nothing at all.
static func _sequences() -> Dictionary:
	var out: Dictionary = {
		SLEEP: SLEEP_SEQUENCE,
		POISON: POISON_SEQUENCE,
		TOXIC: POISON_SEQUENCE,
		PARALYZE: PARALYZE_SEQUENCE,
		POISON_HIT: _secondary([Gen2EffectCommands.POISON_TARGET]),
		BURN_HIT: _secondary([Gen2EffectCommands.BURN_TARGET]),
		FREEZE_HIT: _secondary([Gen2EffectCommands.FREEZE_TARGET]),
		PARALYZE_HIT: _secondary([Gen2EffectCommands.PARALYZE_TARGET]),
		RECOIL_HIT: RECOIL_HIT_SEQUENCE,
	}
	out.merge(_stat_sequences())
	return out


## The commands a move with this effect byte is made of.
static func sequence_for(effect: int) -> Array:
	return _sequences().get(effect, NORMAL_HIT)


## Whether an effect has a list of its own yet, which is what separates a move
## that is fully implemented from one that is standing in as an ordinary attack.
static func is_written(effect: int) -> bool:
	return _sequences().has(effect)
