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
	fill_moves(learnset, out, level)
	return out


## `FillMoves` itself, which is what [method moves_at_level] is one call of.
##
## [param known] is filled in place and may already hold moves: a slot is taken
## when one is empty, and the four are shifted down when none is. [param above]
## is `wPrevPartyLevel`, and passing anything above zero is the
## `wSkipMovesBeforeLevelUp` branch, which offers only the levels *between* the
## two. `known` grows to at most [constant MOVE_SLOTS] entries and is padded with
## zeroes only if it arrived that way, so a party row's four-slot array stays
## four slots.
static func fill_moves(
	learnset: Array, known: Array, level: int, above: int = 0
) -> void:
	var padded: bool = known.size() == MOVE_SLOTS
	for entry: Dictionary in learnset:
		var at: int = int(entry["level"])
		if at > level:
			break
		if above > 0 and at <= above:
			continue
		var move: int = int(entry["move"])
		if known.has(move):
			continue
		var slot: int = known.find(0) if padded else -1
		if slot >= 0:
			known[slot] = move
			continue
		if known.size() == MOVE_SLOTS:
			for index: int in MOVE_SLOTS - 1:
				known[index] = known[index + 1]
			known[MOVE_SLOTS - 1] = move
			continue
		known.append(move)


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
