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
## costs the status and nothing else.
static func _secondary(status_command: StringName) -> Array:
	return [
		Gen2EffectCommands.USED_MOVE_TEXT,
		Gen2EffectCommands.DO_TURN,
		Gen2EffectCommands.DAMAGE_CALC,
		Gen2EffectCommands.CHECK_IMMUNE,
		Gen2EffectCommands.CHECK_HIT,
		Gen2EffectCommands.EFFECT_CHANCE,
		Gen2EffectCommands.APPLY_DAMAGE,
		Gen2EffectCommands.CHECK_FAINT,
		status_command,
		Gen2EffectCommands.END_MOVE,
	]


## Effect bytes that do something other than [constant NORMAL_HIT]. An effect
## that is not in here is an ordinary attack, which is what most of the table is
## and what an effect nobody has written yet falls back to.
##
## Toxic shares the ordinary poison list. On the cartridge it is a poison that
## doubles every turn, counted on a substatus that nothing here carries yet, so
## it is currently the weaker thing it is closest to rather than nothing at all.
static func _sequences() -> Dictionary:
	return {
		SLEEP: SLEEP_SEQUENCE,
		POISON: POISON_SEQUENCE,
		TOXIC: POISON_SEQUENCE,
		PARALYZE: PARALYZE_SEQUENCE,
		POISON_HIT: _secondary(Gen2EffectCommands.POISON_TARGET),
		BURN_HIT: _secondary(Gen2EffectCommands.BURN_TARGET),
		FREEZE_HIT: _secondary(Gen2EffectCommands.FREEZE_TARGET),
		PARALYZE_HIT: _secondary(Gen2EffectCommands.PARALYZE_TARGET),
		RECOIL_HIT: RECOIL_HIT_SEQUENCE,
	}


## The commands a move with this effect byte is made of.
static func sequence_for(effect: int) -> Array:
	return _sequences().get(effect, NORMAL_HIT)


## Whether an effect has a list of its own yet, which is what separates a move
## that is fully implemented from one that is standing in as an ordinary attack.
static func is_written(effect: int) -> bool:
	return _sequences().has(effect)
