class_name Gen2TrainerParty
extends RefCounted

## Turns one of a trainer class's individual trainers into a battle-ready party.
##
## Lives beside the rest of [code]game/battle/[/code] rather than next to
## [Gen2Learnset], because what it produces is [Gen2BattleMon]s and
## [Gen2Party]s, and the data layer holds no battle types. [RefCounted] and
## static throughout, the same as [Gen2Learnset]: nothing here needs a scene,
## only [GameData] and the trainer number to ask it about.
##
## A NORMAL or ITEM trainer's Pokémon knows what its level says it knows, out of
## the learnset, the same as a wild one. A MOVES or ITEM_MOVES trainer's Pokémon
## knows exactly the moves stored with it instead, which is why the two are read
## through [method GameData.moves_at_level] and the stored list respectively
## rather than through one shared path.
##
## Trainer Pokémon carry the cartridge's own per-trainer-class DVs
## ([method GameData.trainer_dvs]), not [constant Gen2BattleMon.PERFECT_DVS]: a
## trainer's whole team shares one fixed set of DVs on the real cartridge,
## which is why the word is asked for once per class rather than once per
## Pokémon.


## The party a trainer class's [param index]th trainer brings, or null if
## [param data] has no such trainer or none of its Pokémon could be built.
static func build(data: GameData, trainer_class: int, index: int) -> Gen2Party:
	if data == null:
		return null

	var trainer: Dictionary = data.trainer_party(trainer_class, index)
	if trainer.is_empty():
		return null

	var mon_type: int = int(trainer["type"])
	var dvs: int = data.trainer_dvs(trainer_class)
	var members: Array = []
	for mon: Dictionary in (trainer["party"] as Array):
		var species: int = int(mon["species"])
		var level: int = int(mon["level"])
		var moves: Array = _moves_for(data, mon_type, species, level, mon["moves"])
		members.append(
			Gen2BattleMon.create(data, species, level, moves, dvs, {}, int(mon["item"]))
		)

	return Gen2Party.create(members)


## What one of this trainer's Pokémon knows: its own stored moves if the
## trainer's type says it carries them, or the ordinary learnset fill
## otherwise. Zero is not a move; it is an empty slot in the stored list, and
## is dropped rather than passed to [Gen2BattleMon] as one.
static func _moves_for(
	data: GameData, mon_type: int, species: int, level: int, stored: Array
) -> Array:
	if mon_type == RomLayout.TRAINER_MON_MOVES or mon_type == RomLayout.TRAINER_MON_ITEM_MOVES:
		var out: Array = []
		for move: Variant in stored:
			if int(move) != 0:
				out.append(int(move))
		return out

	return data.moves_at_level(species, level)
