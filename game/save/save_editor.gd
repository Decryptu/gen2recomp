class_name Gen2SaveEditor
extends RefCounted

## Edits a save slot while keeping it loadable.
##
## Every setter here maintains the invariants [Gen2SaveValidator] enforces
## rather than letting the player write a value and discover at save time that
## the slot is dead: level and experience are kept in agreement through the
## species' own growth curve, HP is clamped to the recomputed maximum, PP
## follows the move it belongs to, and move slots stay contiguous. The
## validator is still the gate on [method commit], so a bug here costs a
## refused write, not a corrupted slot.
##
## Scene free on purpose. The editor screen owns presentation only.

## An empty move slot. The validator refuses any move after one of these, so
## removing a move compacts the list rather than leaving a hole.
const NO_MOVE: int = 0

var data: GameData = null
var save: Gen2SaveData = null

var _dirty: bool = false


static func open(source: Gen2SaveData, game_data: GameData) -> Gen2SaveEditor:
	if source == null or game_data == null:
		return null
	# A working copy, so abandoning the editor cannot leave a half-edited save
	# behind in the object GameRuntime is sharing.
	var copy: Gen2SaveData = Gen2SaveData.from_dict(source.to_dict())
	if copy == null:
		return null
	var editor := Gen2SaveEditor.new()
	editor.data = game_data
	editor.save = copy
	return editor


func is_dirty() -> bool:
	return _dirty


## What [method commit] would say, without writing anything. This is what the
## screen shows continuously so an illegal state is visible before saving.
func validate() -> Dictionary:
	return Gen2SaveValidator.validate(save, data)


func commit() -> Dictionary:
	var result: Dictionary = Gen2SaveStore.save(save, data)
	if bool(result.get("ok", false)):
		_dirty = false
	return result


# --- Player -----------------------------------------------------------------


func set_player_name(name: String) -> Dictionary:
	var trimmed: String = name.strip_edges()
	if trimmed.is_empty():
		return _refuse("the player name cannot be empty")
	if Gen2Text.encoded_length(trimmed) > Gen2SaveData.MAX_PLAYER_NAME:
		return _refuse("the player name is at most %d characters" % Gen2SaveData.MAX_PLAYER_NAME)
	save.player_name = trimmed
	return _changed()


func set_label(label: String) -> Dictionary:
	var trimmed: String = label.strip_edges()
	if trimmed.length() > Gen2SaveData.MAX_LABEL:
		return _refuse("the slot name is at most %d characters" % Gen2SaveData.MAX_LABEL)
	save.label = trimmed
	return _changed()


# --- Party ------------------------------------------------------------------


## Creates a member at [param level] of [param species], with the moves that
## species knows at that level, exactly as a caught Pokemon would arrive.
func add_party_member(species: int, level: int) -> Dictionary:
	if save.party.size() >= Gen2SaveData.MAX_PARTY:
		return _refuse("the party is full")
	var mon: Gen2SaveMon = _create_mon(species, level)
	if mon == null:
		return _refuse("species %d is not in this cartridge cache" % species)
	save.party.append(mon)
	return _changed()


## An empty party is legal, the way a new game has one before Elm's Lab, so
## removing the last member is allowed rather than guessed at.
func remove_party_member(index: int) -> Dictionary:
	if not _party_index_valid(index):
		return _refuse("there is no party member %d" % (index + 1))
	save.party.remove_at(index)
	return _changed()


func move_party_member(from_index: int, to_index: int) -> Dictionary:
	if not _party_index_valid(from_index) or not _party_index_valid(to_index):
		return _refuse("that party position does not exist")
	if from_index == to_index:
		return _changed()
	var mon: Gen2SaveMon = save.party[from_index]
	save.party.remove_at(from_index)
	save.party.insert(to_index, mon)
	return _changed()


# --- One Pokemon ------------------------------------------------------------


## Changing species re-runs experience against the new growth curve and
## re-clamps HP, since both are species derived.
func set_species(mon: Gen2SaveMon, species: int) -> Dictionary:
	if mon == null:
		return _refuse("no Pokemon is selected")
	if data.species(species).is_empty():
		return _refuse("species %d is not in this cartridge cache" % species)
	mon.species = species
	_resync_level(mon, mon.level)
	return _changed()


func set_level(mon: Gen2SaveMon, level: int) -> Dictionary:
	if mon == null:
		return _refuse("no Pokemon is selected")
	if level < 1 or level > Gen2Experience.MAX_LEVEL:
		return _refuse("level is 1 to %d" % Gen2Experience.MAX_LEVEL)
	_resync_level(mon, level)
	return _changed()


## Sets a move and gives it full PP, the way `LearnMove` does. Slot order is
## kept contiguous, so clearing a move pulls the later ones forward.
func set_move(mon: Gen2SaveMon, slot: int, move_number: int) -> Dictionary:
	if mon == null:
		return _refuse("no Pokemon is selected")
	if slot < 0 or slot >= Gen2SaveMon.MAX_MOVES:
		return _refuse("there is no move slot %d" % (slot + 1))
	if move_number == NO_MOVE:
		mon.moves[slot] = NO_MOVE
		mon.pp[slot] = 0
		_compact_moves(mon)
		return _changed()
	var move: Dictionary = data.move(move_number)
	if move.is_empty():
		return _refuse("move %d is not in this cartridge cache" % move_number)
	if slot > 0 and int(mon.moves[slot - 1]) == NO_MOVE:
		return _refuse("fill move slot %d first" % slot)
	mon.moves[slot] = move_number
	mon.pp[slot] = int(move.get("pp", 0))
	return _changed()


func set_pp(mon: Gen2SaveMon, slot: int, pp: int) -> Dictionary:
	if mon == null:
		return _refuse("no Pokemon is selected")
	if slot < 0 or slot >= Gen2SaveMon.MAX_MOVES:
		return _refuse("there is no move slot %d" % (slot + 1))
	if int(mon.moves[slot]) == NO_MOVE:
		return _refuse("that move slot is empty")
	var maximum: int = int(data.move(int(mon.moves[slot])).get("pp", 0))
	mon.pp[slot] = clampi(pp, 0, maximum)
	return _changed()


func set_hp(mon: Gen2SaveMon, hp: int) -> Dictionary:
	if mon == null:
		return _refuse("no Pokemon is selected")
	mon.hp = clampi(hp, 0, max_hp_for(mon))
	return _changed()


func set_status(mon: Gen2SaveMon, status: int) -> Dictionary:
	if mon == null:
		return _refuse("no Pokemon is selected")
	if not Gen2SaveValidator.is_valid_status(status):
		return _refuse("that status combination cannot exist")
	mon.status = status
	return _changed()


## DVs are five 4-bit values packed into one word, so each is clamped on its
## own rather than trusting a hand-typed number.
func set_dvs(mon: Gen2SaveMon, attack: int, defense: int, speed: int, special: int) -> Dictionary:
	if mon == null:
		return _refuse("no Pokemon is selected")
	mon.dvs = Gen2Stats.pack_dvs(
		clampi(attack, 0, Gen2Stats.MAX_DV),
		clampi(defense, 0, Gen2Stats.MAX_DV),
		clampi(speed, 0, Gen2Stats.MAX_DV),
		clampi(special, 0, Gen2Stats.MAX_DV),
	)
	# HP's DV is derived from the other four, so the HP ceiling just moved.
	mon.hp = mini(mon.hp, max_hp_for(mon))
	return _changed()


func set_stat_exp(mon: Gen2SaveMon, key: String, value: int) -> Dictionary:
	if mon == null:
		return _refuse("no Pokemon is selected")
	if not Gen2SaveMon.STAT_EXP_KEYS.has(key):
		return _refuse("there is no %s stat experience" % key)
	mon.stat_exp[key] = clampi(value, 0, Gen2Stats.MAX_STAT_EXP)
	if key == "hp":
		mon.hp = mini(mon.hp, max_hp_for(mon))
	return _changed()


func set_held_item(mon: Gen2SaveMon, item: int) -> Dictionary:
	if mon == null:
		return _refuse("no Pokemon is selected")
	if item != 0 and data.item(item).is_empty():
		return _refuse("item %d is not in this cartridge cache" % item)
	mon.item = maxi(item, 0)
	return _changed()


func set_nickname(mon: Gen2SaveMon, nickname: String) -> Dictionary:
	if mon == null:
		return _refuse("no Pokemon is selected")
	mon.nickname = nickname.strip_edges()
	return _changed()


func set_happiness(mon: Gen2SaveMon, happiness: int) -> Dictionary:
	if mon == null:
		return _refuse("no Pokemon is selected")
	mon.happiness = clampi(happiness, 0, 255)
	return _changed()


func set_is_egg(mon: Gen2SaveMon, is_egg: bool) -> Dictionary:
	if mon == null:
		return _refuse("no Pokemon is selected")
	mon.is_egg = is_egg
	return _changed()


## The HP ceiling this Pokemon's identity and training produce right now.
func max_hp_for(mon: Gen2SaveMon) -> int:
	if mon == null:
		return 0
	var base: Dictionary = data.species(mon.species).get("stats", {})
	return Gen2Stats.calculate(
		int(base.get("hp", 0)),
		Gen2Stats.hp_dv(mon.dvs),
		int(mon.stat_exp.get("hp", 0)),
		mon.level,
		true,
	)


# --- Boxes ------------------------------------------------------------------


func box(index: int) -> Gen2SaveBox:
	if index < 0 or index >= save.boxes.size():
		return null
	return save.boxes[index]


func add_box_member(box_index: int, species: int, level: int) -> Dictionary:
	var target: Gen2SaveBox = box(box_index)
	if target == null:
		return _refuse("there is no box %d" % (box_index + 1))
	var mon: Gen2SaveMon = _create_mon(species, level)
	if mon == null:
		return _refuse("species %d is not in this cartridge cache" % species)
	var placed: Dictionary = target.put(mon)
	if not bool(placed.get("ok", false)):
		return _refuse("box %d is full" % (box_index + 1))
	return _changed()


func remove_box_member(box_index: int, slot: int) -> Dictionary:
	var target: Gen2SaveBox = box(box_index)
	if target == null:
		return _refuse("there is no box %d" % (box_index + 1))
	if slot < 0 or slot >= target.slots.size() or target.slots[slot] == null:
		return _refuse("that box slot is empty")
	target.slots[slot] = null
	return _changed()


# --- World ------------------------------------------------------------------


## The bag, money, flags and dex all live in the world snapshot, so a save
## written before the overworld existed has none of them to edit.
func has_world() -> bool:
	return save.world != null and save.world.world_state != null


func inventory() -> Gen2WorldInventory:
	if not has_world():
		return null
	return Gen2WorldInventory.new(data, save.world.world_state)


func set_item_quantity(item: int, quantity: int) -> Dictionary:
	var bag: Gen2WorldInventory = inventory()
	if bag == null:
		return _refuse("this save has no world state to edit")
	if item != 0 and data.item(item).is_empty():
		return _refuse("item %d is not in this cartridge cache" % item)
	var result: Dictionary = bag.set_item_quantity(item, quantity)
	if not bool(result.get("ok", false)):
		return _refuse(String(result.get("reason", "that item quantity was refused")))
	return _changed()


func set_money(account: int, balance: int) -> Dictionary:
	var bag: Gen2WorldInventory = inventory()
	if bag == null:
		return _refuse("this save has no world state to edit")
	var result: Dictionary = bag.set_money(
		account, clampi(balance, 0, Gen2WorldInventory.MAX_MONEY)
	)
	if not bool(result.get("ok", false)):
		return _refuse(String(result.get("reason", "that balance was refused")))
	return _changed()


func set_coins(balance: int) -> Dictionary:
	var bag: Gen2WorldInventory = inventory()
	if bag == null:
		return _refuse("this save has no world state to edit")
	var result: Dictionary = bag.set_coins(clampi(balance, 0, Gen2WorldInventory.MAX_COINS))
	if not bool(result.get("ok", false)):
		return _refuse(String(result.get("reason", "that balance was refused")))
	return _changed()


func set_event_flag(flag: int, active: bool) -> Dictionary:
	if not has_world():
		return _refuse("this save has no world state to edit")
	if flag < 0:
		return _refuse("an event flag number is not negative")
	save.world.world_state.set_event_flag(flag, active)
	return _changed()


## Badges are engine flags, so this is how a badge is granted or taken away.
## The numbers differ between the profiles, which is why they are read from
## the state rather than hardcoded here.
func set_engine_flag(flag: int, active: bool) -> Dictionary:
	if not has_world():
		return _refuse("this save has no world state to edit")
	if flag < 0:
		return _refuse("an engine flag number is not negative")
	save.world.world_state.set_engine_flag(flag, active)
	return _changed()


func badge_flags() -> Array[int]:
	var out: Array[int] = []
	if not has_world():
		return out
	var gold_silver: bool = save.game_id != RomRegistry.CRYSTAL
	var flags: Array[int] = (
		Gen2WorldState.BADGE_ENGINE_FLAGS_GOLD_SILVER if gold_silver
		else Gen2WorldState.BADGE_ENGINE_FLAGS
	)
	out.assign(flags)
	return out


func set_seen_species(species: int, seen: bool) -> Dictionary:
	if not has_world():
		return _refuse("this save has no world state to edit")
	if data.species(species).is_empty():
		return _refuse("species %d is not in this cartridge cache" % species)
	save.world.world_state.set_species_seen(species, seen)
	return _changed()


## Moving the player is checked against the destination map's own collision
## grid, because the validator refuses a cell outside it and a save that will
## not load is exactly what this editor exists to prevent.
func set_player_position(map_id: Vector2i, cell: Vector2i) -> Dictionary:
	if not has_world():
		return _refuse("this save has no world state to edit")
	var map: Gen2WorldMap = data.world_map(map_id.x, map_id.y)
	if map == null:
		return _refuse("map %d/%d is not in this cartridge cache" % [map_id.x, map_id.y])
	if cell.x < 0 or cell.y < 0 or cell.x >= map.collision_width or cell.y >= map.collision_height:
		return _refuse("that cell is outside map %d/%d" % [map_id.x, map_id.y])
	save.world.map_id = map_id
	save.world.player_cell = cell
	return _changed()


func set_clock(day: int, hour: int, minute: int) -> Dictionary:
	if not has_world():
		return _refuse("this save has no world state to edit")
	save.world.world_day = clampi(day, 0, Gen2WorldClock.DAYS_PER_WEEK - 1)
	save.world.world_hour = clampi(hour, 0, Gen2WorldClock.HOURS_PER_DAY - 1)
	save.world.world_minute = clampi(minute, 0, Gen2WorldClock.MINUTES_PER_HOUR - 1)
	return _changed()


# --- Internals --------------------------------------------------------------


## Level and experience must agree, so setting either sets both: experience
## becomes the curve's own total for that level under this species' growth
## rate. HP then re-clamps, because the maximum moved with the level.
func _resync_level(mon: Gen2SaveMon, level: int) -> void:
	var growth: int = int(
		data.species(mon.species).get("growth_rate", Gen2Experience.GROWTH_MEDIUM_FAST)
	)
	mon.level = clampi(level, 1, Gen2Experience.MAX_LEVEL)
	mon.exp = Gen2Experience.total_exp_at(growth, mon.level)
	mon.hp = mini(mon.hp, max_hp_for(mon))


func _create_mon(species: int, level: int) -> Gen2SaveMon:
	if data.species(species).is_empty():
		return null
	var wanted: int = clampi(level, 1, Gen2Experience.MAX_LEVEL)
	var battle_mon: Gen2BattleMon = Gen2BattleMon.create(
		data, species, wanted, data.moves_at_level(species, wanted)
	)
	if battle_mon == null:
		return null
	return Gen2SaveBattleAdapter.from_battle_mon(battle_mon)


## Pulls later moves forward so no gap sits before a filled slot, which the
## validator refuses.
func _compact_moves(mon: Gen2SaveMon) -> void:
	var moves: Array = []
	var pp: Array = []
	for slot: int in Gen2SaveMon.MAX_MOVES:
		if int(mon.moves[slot]) != NO_MOVE:
			moves.append(mon.moves[slot])
			pp.append(mon.pp[slot])
	while moves.size() < Gen2SaveMon.MAX_MOVES:
		moves.append(NO_MOVE)
		pp.append(0)
	mon.moves = moves
	mon.pp = pp


func _party_index_valid(index: int) -> bool:
	return index >= 0 and index < save.party.size()


func _changed() -> Dictionary:
	_dirty = true
	return {"ok": true, "message": ""}


func _refuse(message: String) -> Dictionary:
	return {"ok": false, "message": message}
