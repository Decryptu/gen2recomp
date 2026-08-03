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

## Recoil, which is the only effect with a list of its own so far. It is here
## because Struggle needs it: a Pokémon with nothing left to spend has to be able
## to hurt itself, or two empty Pokémon never finish their battle.
const RECOIL_HIT: int = 48

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

## Effect bytes that do something other than [constant NORMAL_HIT]. An effect
## that is not in here is an ordinary attack, which is what most of the table is
## and what an effect nobody has written yet falls back to.
const SEQUENCES: Dictionary = {
	RECOIL_HIT: RECOIL_HIT_SEQUENCE,
}


## The commands a move with this effect byte is made of.
static func sequence_for(effect: int) -> Array:
	return SEQUENCES.get(effect, NORMAL_HIT)


## Whether an effect has a list of its own yet, which is what separates a move
## that is fully implemented from one that is standing in as an ordinary attack.
static func is_written(effect: int) -> bool:
	return SEQUENCES.has(effect)
