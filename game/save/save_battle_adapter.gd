class_name Gen2SaveBattleAdapter
extends RefCounted

## The seam between persistent data and the scene-free battle engine. The save
## model does not own battle rules, while the battle engine does not open save
## files or know about slots.

static func from_battle_mon(mon: Gen2BattleMon) -> Gen2SaveMon:
	if mon == null:
		return null
	var out := Gen2SaveMon.new()
	out.species = mon.persistent_species()
	out.item = mon.item
	out.level = mon.level
	out.exp = mon.exp
	out.dvs = mon.persistent_dvs()
	out.stat_exp = {}
	for key: String in Gen2SaveMon.STAT_EXP_KEYS:
		out.stat_exp[key] = int(mon.stat_exp.get(key, 0))
	out.hp = mon.hp
	out.status = mon.status
	out.happiness = mon.happiness
	out.caught_location = mon.caught_location
	for slot: int in Gen2SaveMon.MAX_MOVES:
		# Mimic and Transform edit only the battle move struct. Sketch edits the
		# party move too, so it needs no exception here.
		out.moves[slot] = mon.persistent_move(slot)
		out.pp[slot] = mon.persistent_pp(slot)
	return out


static func to_battle_mon(data: GameData, saved: Gen2SaveMon) -> Gen2BattleMon:
	if data == null or saved == null or saved.is_egg:
		return null
	var known_moves: Array = []
	var saved_pp: Array = []
	for slot: int in Gen2SaveMon.MAX_MOVES:
		var move_number: int = int(saved.moves[slot])
		if move_number == 0:
			continue
		known_moves.append(move_number)
		saved_pp.append(int(saved.pp[slot]))
	var out: Gen2BattleMon = Gen2BattleMon.create(
		data, saved.species, saved.level, known_moves, saved.dvs, saved.stat_exp, saved.item
	)
	if out == null:
		return null
	out.exp = saved.exp
	out.status = saved.status
	out.happiness = saved.happiness
	out.caught_location = saved.caught_location & Gen2BattleMon.CAUGHT_LOCATION_MASK
	out.pp = saved_pp
	out.hp = clampi(saved.hp, 0, out.max_hp())
	return out


## Writes a fought party back over [param source_save]. Eggs never entered the
## battle party, so they keep their own slots and the battle Pokémon fill the
## rest in order; the write fails rather than dropping an egg or shifting a
## slot when the two no longer line up.
##
## The candidate starts as a complete clone of [param source_save], so fields
## the battle model does not carry cannot disappear as the save schema grows.
## Happiness is not restored from that clone: Return and Frustration read it,
## so [Gen2BattleMon] holds it and it round-trips with the fought party.
static func from_battle_party(
	game_id: StringName, rom_sha1: String, slot: int, party: Gen2Party, player_name: String = "",
	source_save: Gen2SaveData = null
) -> Gen2SaveData:
	if party == null or party.mons.is_empty() or party.mons.size() > Gen2Party.MAX_SIZE:
		return null
	var egg_count: int = 0
	if source_save != null:
		for member: Gen2SaveMon in source_save.party:
			if member != null and member.is_egg:
				egg_count += 1
		if egg_count > 0 and source_save.party.size() - egg_count != party.mons.size():
			return null
		if source_save.party.size() > Gen2Party.MAX_SIZE:
			return null
	var out: Gen2SaveData = (
		Gen2SaveData.from_dict(source_save.to_dict())
		if source_save != null else Gen2SaveData.new()
	)
	if out == null:
		return null
	out.game_id = game_id
	out.rom_sha1 = rom_sha1
	out.slot = slot
	out.player_name = source_save.player_name if source_save != null else player_name
	out.party.clear()
	var fought: int = 0
	var slot_count: int = source_save.party.size() if egg_count > 0 else party.mons.size()
	for index: int in slot_count:
		var previous: Gen2SaveMon = (
			source_save.party[index]
			if source_save != null and index < source_save.party.size() else null
		)
		if previous != null and previous.is_egg:
			out.party.append(Gen2SaveMon.from_dict(previous.to_dict()))
			continue
		var saved_mon: Gen2SaveMon = from_battle_mon(party.mons[fought])
		fought += 1
		if previous != null:
			saved_mon.ot_id = previous.ot_id
			saved_mon.pokerus = previous.pokerus
			saved_mon.caught_time = previous.caught_time
			saved_mon.caught_gender = previous.caught_gender
			saved_mon.caught_level = previous.caught_level
			saved_mon.caught_location = previous.caught_location
			# `UpdateSpeciesNameIfNotNicknamed`: a party member that evolved
			# during the battle takes the new species' name unless it was
			# nicknamed, which is the one thing the old row does not decide.
			saved_mon.nickname = Gen2Evolution.nickname_after_evolution(
				party.mons[fought - 1].data, previous.nickname,
				previous.species, saved_mon.species
			)
			saved_mon.original_trainer = previous.original_trainer
		out.party.append(saved_mon)
	return out


## The fighting half of a saved party. An egg keeps its party slot on the
## cartridge and is only refused as a combatant (`CheckIfCurPartyMonIsFitToFight`
## answers `BattleText_AnEGGCantBattle`), so it is skipped here rather than
## failing the party; a party of nothing but eggs has no fit mon and answers
## null the way `CheckPlayerPartyForFitMon` does.
static func to_battle_party(data: GameData, save: Gen2SaveData) -> Gen2Party:
	if data == null or save == null:
		return null
	var members: Array = []
	for saved: Gen2SaveMon in save.party:
		if saved != null and saved.is_egg:
			continue
		var mon: Gen2BattleMon = to_battle_mon(data, saved)
		if mon == null:
			return null
		members.append(mon)
	return Gen2Party.create(members)


## Where battle-party slot [param battle_index] sits in [param save]'s party.
## `CheckIfCurPartyMonIsFitToFight` refuses an EGG as a combatant but leaves it
## in its party slot, so [method to_battle_party] skips it and the two lists
## stop lining up the moment a party carries one. -1 when there is no such slot.
static func save_party_index(save: Gen2SaveData, battle_index: int) -> int:
	if save == null or battle_index < 0:
		return -1
	var seen: int = 0
	for index: int in save.party.size():
		var mon: Gen2SaveMon = save.party[index]
		if mon != null and mon.is_egg:
			continue
		if seen == battle_index:
			return index
		seen += 1
	return -1
