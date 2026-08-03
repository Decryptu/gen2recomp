class_name Gen2Learnset
extends RefCounted

## What a Pokémon knows, worked out from its level-up moves.
##
## The cartridge asks this in two different ways and gets two different answers,
## so both are here and neither is the other's shortcut:
##
## [method moves_at_level] is how a Pokémon that has just been brought into
## existence is furnished, whether it is wild, in a trainer's party or a starter.
## It walks the list from the beginning and stops at the first move whose level is
## above the one being filled for.
##
## [method moves_learned_at] is how a Pokémon that has just levelled up is
## offered something new. It reads the whole list and takes the entries whose
## level is exactly the one just reached.
##
## The difference is not academic. One species' list is not in ascending order
## (see [constant RomLayout.UNSORTED_LEARNSET_SPECIES]), so the first stops early
## and misses moves the second finds. That is the cartridge's behaviour, not a
## rounding of it: a Muk caught in the wild really is missing three moves that a
## Muk raised to the same level has.
##
## [RefCounted] and static throughout: a learnset is an Array of
## { level, move } out of [GameData], and nothing here needs a cache, a scene or
## a Pokémon to answer.

## How many moves a Pokémon can know at once.
const MOVE_SLOTS: int = 4


## The moves a Pokémon of [param level] is created knowing, in the order it knows
## them.
##
## The list is walked from the start, skipping moves that are already known, and
## the walk stops at the first entry above [param level] rather than filtering the
## whole list. When all four slots are full the oldest is pushed out, which is why
## the answer is the last four learnable moves and not the first four.
static func moves_at_level(learnset: Array, level: int) -> Array:
	var out: Array = []

	for entry: Dictionary in learnset:
		if int(entry["level"]) > level:
			break

		var move: int = int(entry["move"])
		if out.has(move):
			continue
		if out.size() == MOVE_SLOTS:
			out.remove_at(0)
		out.append(move)

	return out


## The moves offered on reaching exactly [param level], in the order the list
## carries them. Empty for a level at which nothing is learned.
static func moves_learned_at(learnset: Array, level: int) -> Array:
	var out: Array = []

	for entry: Dictionary in learnset:
		if int(entry["level"]) != level:
			continue
		var move: int = int(entry["move"])
		if not out.has(move):
			out.append(move)

	return out
