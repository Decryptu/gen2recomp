class_name Gen2SaveValidator
extends RefCounted

## Validation for user-owned save data. A save is not accepted because it is
## valid JSON: every number that indexes cartridge content is checked against
## the selected [GameData], and every derived battle constraint is checked from
## the same formulas the battle engine uses.

static func validate(save: Gen2SaveData, data: GameData) -> Dictionary:
	if save == null:
		return _failure("the save is missing")
	if data == null:
		return _failure("the selected cartridge cache is missing")
	if save.format_version != Gen2SaveData.FORMAT_VERSION:
		return _failure("unsupported save format %d" % save.format_version)
	if save.game_id != data.id:
		return _failure("the save belongs to %s, not %s" % [save.game_id, data.id])
	if save.rom_sha1 != data.sha1:
		return _failure("the save belongs to a different cartridge revision")
	if save.slot < 0 or save.slot >= Gen2SaveStore.SLOT_COUNT:
		return _failure("save slot %d is out of range" % save.slot)
	if save.player_name.is_empty():
		return _failure("the player name is empty")
	if Gen2Text.encoded_length(save.player_name) > Gen2SaveData.MAX_PLAYER_NAME:
		return _failure("the player name is too long")
	if save.party.is_empty() or save.party.size() > Gen2SaveData.MAX_PARTY:
		return _failure("the party must contain between one and six Pokémon")
	if not save.boxes_shape_valid or save.boxes.size() != Gen2SaveData.BOX_COUNT:
		return _failure("the save does not contain exactly %d PC boxes" % Gen2SaveData.BOX_COUNT)
	var world_result: Dictionary = _validate_world(save.world, data)
	if not world_result["ok"]:
		return world_result

	for index: int in save.party.size():
		var mon: Gen2SaveMon = save.party[index]
		var result: Dictionary = _validate_mon(mon, data, index)
		if not result["ok"]:
			return result
	for box_index: int in Gen2SaveData.BOX_COUNT:
		var box: Gen2SaveBox = save.boxes[box_index]
		if box == null or not box.shape_valid or box.slots.size() != Gen2SaveBox.CAPACITY:
			return _failure("PC box %d has an invalid slot shape" % (box_index + 1))
		for slot_index: int in Gen2SaveBox.CAPACITY:
			var boxed: Gen2SaveMon = box.slots[slot_index]
			if boxed == null:
				continue
			var box_result: Dictionary = _validate_mon(
				boxed, data, slot_index, "PC box %d slot" % (box_index + 1)
			)
			if not box_result["ok"]:
				return box_result
	return {"ok": true, "message": ""}


static func _validate_world(world: Gen2WorldSnapshot, data: GameData) -> Dictionary:
	if world == null:
		return {"ok": true, "message": ""}
	if world.format_version != Gen2WorldSnapshot.FORMAT_VERSION:
		return _failure("unsupported world snapshot format %d" % world.format_version)
	var map: Gen2WorldMap = data.world_map(world.map_id.x, world.map_id.y)
	if map == null:
		return _failure("the saved world map %d/%d is not in the cartridge cache" % [
			world.map_id.x, world.map_id.y,
		])
	if world.player_cell.x < 0 or world.player_cell.y < 0 \
		or world.player_cell.x >= map.collision_width \
		or world.player_cell.y >= map.collision_height:
		return _failure("the saved player cell is outside map %d/%d" % [
			world.map_id.x, world.map_id.y,
		])
	if world.player_facing < Gen2WorldSprite.FACING_DOWN \
		or world.player_facing > Gen2WorldSprite.FACING_RIGHT:
		return _failure("the saved player facing is invalid")
	if world.movement_mode not in [Gen2WorldAPI.MOVEMENT_WALK, Gen2WorldAPI.MOVEMENT_SURF]:
		return _failure("the saved movement mode is invalid")
	if world.world_day < 0 or world.world_day >= Gen2WorldClock.DAYS_PER_WEEK \
		or world.world_hour < 0 or world.world_hour >= Gen2WorldClock.HOURS_PER_DAY \
		or world.world_minute < 0 \
		or world.world_minute >= Gen2WorldClock.MINUTES_PER_HOUR:
		return _failure("the saved world clock is invalid")
	if world.world_state == null:
		return _failure("the saved world state is missing")
	for raw_flag: Variant in world.world_state.engine_flags():
		if int(raw_flag) < 0:
			return _failure("the saved world engine flag is invalid")
	for raw_item: Variant in world.world_state.items():
		if data.item(int(raw_item)).is_empty():
			return _failure("the saved world contains unknown item %d" % int(raw_item))
	for raw_account: Variant in world.world_state.money_balances():
		var balance: int = int(world.world_state.money_balances()[raw_account])
		if balance < 0 or balance > Gen2WorldInventory.MAX_MONEY:
			return _failure("the saved world money balance is invalid")
	if world.world_state.coins() < 0 or world.world_state.coins() > Gen2WorldInventory.MAX_COINS:
		return _failure("the saved world coin balance is invalid")
	return {"ok": true, "message": ""}


static func _validate_mon(
	mon: Gen2SaveMon, data: GameData, index: int, label: String = "party member"
) -> Dictionary:
	var subject: String = "%s %d" % [label, index + 1]
	if mon == null:
		return _failure("%s is missing" % subject)
	if mon.species <= 0 or data.species(mon.species).is_empty():
		return _failure("%s has unknown species %d" % [subject, mon.species])
	if mon.level < 1 or mon.level > Gen2Experience.MAX_LEVEL:
		return _failure("%s has invalid level %d" % [subject, mon.level])
	if mon.exp < 0 or mon.exp > Gen2Experience.MAX_EXP:
		return _failure("%s has invalid experience" % subject)
	var expected_level: int = Gen2Experience.level_for_exp(
		int(data.species(mon.species).get("growth_rate", Gen2Experience.GROWTH_MEDIUM_FAST)),
		mon.exp
	)
	if expected_level != mon.level:
		return _failure("%s level and experience disagree" % subject)
	if mon.dvs < 0 or mon.dvs > 0xFFFF:
		return _failure("%s has invalid DVs" % subject)
	for key: String in Gen2SaveMon.STAT_EXP_KEYS:
		var value: int = int(mon.stat_exp.get(key, -1))
		if value < 0 or value > Gen2Stats.MAX_STAT_EXP:
			return _failure("%s has invalid %s stat experience" % [subject, key])

	var base: Dictionary = data.species(mon.species).get("stats", {})
	var max_hp: int = Gen2Stats.calculate(
		int(base.get("hp", 0)), Gen2Stats.hp_dv(mon.dvs), int(mon.stat_exp.get("hp", 0)),
		mon.level, true
	)
	if mon.hp < 0 or mon.hp > max_hp:
		return _failure("%s has invalid HP" % subject)
	if not _valid_status(mon.status):
		return _failure("%s has invalid status" % subject)

	if mon.moves.size() != Gen2SaveMon.MAX_MOVES or mon.pp.size() != Gen2SaveMon.MAX_MOVES:
		return _failure("%s does not have four move slots" % subject)
	var empty_seen: bool = false
	for move_slot: int in Gen2SaveMon.MAX_MOVES:
		var move_number: int = int(mon.moves[move_slot])
		var pp: int = int(mon.pp[move_slot])
		if move_number == 0:
			empty_seen = true
			if pp != 0:
				return _failure("%s has PP for an empty move" % subject)
			continue
		if empty_seen:
			return _failure("%s has a move after an empty slot" % subject)
		var move: Dictionary = data.move(move_number)
		if move.is_empty():
			return _failure("%s has unknown move %d" % [subject, move_number])
		var max_pp: int = int(move.get("pp", 0))
		if pp < 0 or pp > max_pp:
			return _failure("%s has invalid PP for move %d" % [subject, move_number])

	if mon.item < 0:
		return _failure("%s has an invalid item" % subject)
	if mon.item > 0 and data.item(mon.item).is_empty():
		return _failure("%s has unknown item %d" % [subject, mon.item])
	return {"ok": true, "message": ""}


static func _valid_status(status: int) -> bool:
	if status < 0 or (status & ~Gen2Status.ANY) != 0:
		return false
	var flags: int = status & (Gen2Status.POISON | Gen2Status.BURN | Gen2Status.FREEZE | Gen2Status.PARALYSIS)
	if Gen2Status.is_asleep(status) and flags != 0:
		return false
	return flags == 0 or flags == Gen2Status.POISON or flags == Gen2Status.BURN \
		or flags == Gen2Status.FREEZE or flags == Gen2Status.PARALYSIS


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
