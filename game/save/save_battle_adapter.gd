class_name Gen2SaveBattleAdapter
extends RefCounted

## The seam between persistent data and the scene-free battle engine. The save
## model does not own battle rules, while the battle engine does not open save
## files or know about slots.

static func from_battle_mon(mon: Gen2BattleMon) -> Gen2SaveMon:
	if mon == null:
		return null
	var out := Gen2SaveMon.new()
	out.species = mon.species
	out.item = mon.item
	out.level = mon.level
	out.exp = mon.exp
	out.dvs = mon.dvs
	out.stat_exp = {}
	for key: String in Gen2SaveMon.STAT_EXP_KEYS:
		out.stat_exp[key] = int(mon.stat_exp.get(key, 0))
	out.hp = mon.hp
	out.status = mon.status
	for slot: int in Gen2SaveMon.MAX_MOVES:
		if slot < mon.moves.size():
			out.moves[slot] = int(mon.moves[slot])
			out.pp[slot] = mon.pp_left(slot)
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
	out.pp = saved_pp
	out.hp = clampi(saved.hp, 0, out.max_hp())
	return out


static func from_battle_party(
	game_id: StringName, rom_sha1: String, slot: int, party: Gen2Party, player_name: String = "",
	source_save: Gen2SaveData = null
) -> Gen2SaveData:
	if party == null or party.mons.is_empty() or party.mons.size() > Gen2Party.MAX_SIZE:
		return null
	var out := Gen2SaveData.new()
	out.game_id = game_id
	out.rom_sha1 = rom_sha1
	out.slot = slot
	out.player_name = source_save.player_name if source_save != null else player_name
	if source_save != null:
		out.boxes.clear()
		for raw_box: Variant in source_save.boxes:
			var box: Gen2SaveBox = raw_box if raw_box is Gen2SaveBox else null
			if box == null:
				out.boxes.append(Gen2SaveBox.new())
				continue
			var copied_box: Gen2SaveBox = Gen2SaveBox.from_dict(box.to_dict())
			copied_box.shape_valid = box.shape_valid
			out.boxes.append(copied_box)
		while out.boxes.size() < Gen2SaveData.BOX_COUNT:
			out.boxes.append(Gen2SaveBox.new())
		if source_save.world != null:
			out.world = Gen2WorldSnapshot.from_dict(source_save.world.to_dict())
	for index: int in party.mons.size():
		var saved_mon: Gen2SaveMon = from_battle_mon(party.mons[index])
		if source_save != null and index < source_save.party.size():
			var previous: Gen2SaveMon = source_save.party[index]
			saved_mon.ot_id = previous.ot_id
			saved_mon.happiness = previous.happiness
			saved_mon.pokerus = previous.pokerus
			saved_mon.caught_time = previous.caught_time
			saved_mon.caught_gender = previous.caught_gender
			saved_mon.caught_level = previous.caught_level
			saved_mon.caught_location = previous.caught_location
			saved_mon.nickname = previous.nickname
			saved_mon.original_trainer = previous.original_trainer
		out.party.append(saved_mon)
	return out


static func to_battle_party(data: GameData, save: Gen2SaveData) -> Gen2Party:
	if data == null or save == null:
		return null
	var members: Array = []
	for saved: Gen2SaveMon in save.party:
		var mon: Gen2BattleMon = to_battle_mon(data, saved)
		if mon == null:
			return null
		members.append(mon)
	return Gen2Party.create(members)
