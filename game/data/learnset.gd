class_name Gen2Learnset
extends RefCounted

## What a Pokémon knows, worked out from its level-up moves.
##
## The cartridge asks two different questions and gets two different answers, so
## both are here and neither is the other's shortcut:
##
## [method moves_at_level] furnishes a newly created Pokémon, wild, trainer-owned
## or a starter. It walks from the beginning and stops at the first move above
## the level being filled for.
##
## [method moves_learned_at] offers a just-levelled Pokémon something new. It
## reads the whole list and takes entries at exactly the level reached.
##
## One species' list is not ascending (see
## [constant RomLayout.UNSORTED_LEARNSET_SPECIES]), so the first stops early and
## misses moves the second finds: a wild Muk really is short three moves a raised
## Muk has.
##
## [RefCounted] and static: a learnset is an Array of { level, move } from
## [GameData], and nothing here needs a cache, scene or Pokémon.

## How many moves a Pokémon can know at once.
const MOVE_SLOTS: int = 4


## The moves a Pokémon of [param level] is created knowing, in the order it knows
## them.
##
## Walked from the start, skipping already-known moves, stopping at the first
## entry above [param level] rather than filtering the whole list. A full four
## slots pushes the oldest out, so the answer is the last four learnable moves.
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
