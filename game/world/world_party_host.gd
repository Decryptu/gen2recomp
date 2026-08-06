class_name Gen2WorldPartyHost
extends RefCounted

## Scene-free transactions for party-owned overworld operations.
##
## A script can stage world changes and then pause for a gift, egg or NPC trade.
## The host builds a candidate save first, resumes the script, and only writes
## the candidate after both sides have succeeded. The six-party limit is
## deliberate until the save model has a real PC-box owner.

const ITEM_REVIVE: int = 0x27
const ITEM_MAX_REVIVE: int = 0x28
const ITEM_REPEL: int = 0x14
const ITEM_SUPER_REPEL: int = 0x2A
const ITEM_MAX_REPEL: int = 0x2B
const ITEM_MASTER_BALL: int = 0x01
const ITEM_ULTRA_BALL: int = 0x02
const ITEM_GREAT_BALL: int = 0x04
const ITEM_POKE_BALL: int = 0x05

const CAPTURE_BALLS: Array[int] = [
	ITEM_POKE_BALL, ITEM_GREAT_BALL, ITEM_ULTRA_BALL, ITEM_MASTER_BALL,
]

const WOBBLE_PROBABILITIES: Array = [
	[1, 63], [2, 75], [3, 84], [4, 90], [5, 95], [7, 103], [10, 113],
	[15, 126], [20, 134], [30, 149], [40, 160], [50, 169], [60, 177],
	[80, 191], [100, 201], [120, 211], [140, 220], [160, 227], [180, 234],
	[200, 240], [220, 246], [240, 251], [254, 253], [255, 255],
]


## Returns the ball items whose capture effects are implemented by this host.
## The order follows the ordinary ball pocket order used by the source menu.
static func capture_ball_items() -> Array[int]:
	return CAPTURE_BALLS.duplicate()


## Returns owned supported balls without making the battle scene aware of world
## state. Item definitions still validate the pocket when a throw is resolved.
static func owned_capture_balls(world: Gen2WorldAPI) -> Array[int]:
	var out: Array[int] = []
	if world == null or world.state == null:
		return out
	for ball: int in CAPTURE_BALLS:
		if world.state.item_quantity(ball) > 0:
			out.append(ball)
	return out


static func complete_runtime_request(
	world: Gen2WorldAPI,
	result: Dictionary,
	save: Gen2SaveData = null,
	persist: bool = true,
	random: RandomNumberGenerator = null
) -> Dictionary:
	if world == null:
		return _failure(&"missing_world", {})
	var request: Dictionary = world.pending_runtime_request()
	if request.is_empty():
		return _failure(&"runtime_request_not_pending", {})
	var kind: StringName = StringName(request.get("kind", &""))
	if kind not in [&"pokemon_requested", &"trade_requested"]:
		return _failure(&"party_request_not_pending", request)
	if save == null or world.data == null:
		return _failure(&"missing_save", request)
	var validation: Dictionary = Gen2SaveValidator.validate(save, world.data)
	if not bool(validation.get("ok", false)):
		return _failure(&"invalid_save", {
			"message": validation.get("message", ""), "request": request,
		})

	var candidate: Gen2SaveData = Gen2SaveData.from_dict(save.to_dict())
	var generator: RandomNumberGenerator = random if random != null else RandomNumberGenerator.new()
	if random == null:
		generator.randomize()
	var transaction: Dictionary = _apply_party_request(
		world, candidate, request, result, generator
	)
	if not bool(transaction.get("ok", false)):
		return _failure(
			StringName(transaction.get("reason", &"party_request_failed")),
			{"request": request, "details": transaction}
		)

	var before: Gen2WorldSnapshot = world.snapshot()
	var completion_result: Dictionary = {
		"ok": true,
		"script_value": int(transaction.get("script_value", 0)),
		"accepted": bool(transaction.get("accepted", false)),
		"reason": transaction.get("reason", &""),
		"transaction": transaction.get("summary", {}).duplicate(true),
	}
	var resumed: Array = world.complete_runtime_request(completion_result)
	if resumed.is_empty() or not bool(resumed[0].get("ok", false)):
		return _failure(&"runtime_request_failed", {
			"request": request, "results": resumed,
		})

	candidate.world = world.snapshot()
	var candidate_validation: Dictionary = Gen2SaveValidator.validate(candidate, world.data)
	if not bool(candidate_validation.get("ok", false)):
		world.state.restore_from_dict(before.world_state.to_dict())
		return _failure(&"candidate_save_invalid", {
			"message": candidate_validation.get("message", ""), "results": resumed,
		})
	var write_result: Dictionary = {"ok": true}
	if persist:
		write_result = Gen2SaveStore.save(candidate, world.data)
	if not bool(write_result.get("ok", false)):
		world.state.restore_from_dict(before.world_state.to_dict())
		return _failure(&"save_failed", {
			"message": write_result.get("message", ""), "results": resumed,
		})
	_copy_save(save, candidate)
	return {
		"ok": true,
		"handled": true,
		"request": request,
		"transaction": transaction.get("summary", {}).duplicate(true),
		"results": resumed,
	}


## Restores HP, status and PP for every non-egg party member, matching the
## source HealParty routine. The candidate save is validated before writeback,
## and the live world only resumes after the candidate is ready.
static func heal_party(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	persist: bool = true,
) -> Dictionary:
	if world == null or save == null or world.data == null:
		return _failure(&"missing_save", {})
	var validation: Dictionary = Gen2SaveValidator.validate(save, world.data)
	if not bool(validation.get("ok", false)):
		return _failure(&"invalid_save", {"message": validation.get("message", "")})
	var candidate: Gen2SaveData = Gen2SaveData.from_dict(save.to_dict())
	var healed: int = 0
	for mon: Gen2SaveMon in candidate.party:
		if mon == null or mon.is_egg:
			continue
		var battle_mon: Gen2BattleMon = Gen2SaveBattleAdapter.to_battle_mon(world.data, mon)
		if battle_mon == null:
			return _failure(&"invalid_party_member", {"species": mon.species})
		var max_hp: int = battle_mon.max_hp()
		if mon.hp != max_hp or mon.status != Gen2Status.NONE:
			healed += 1
		mon.hp = max_hp
		mon.status = Gen2Status.NONE
		for slot: int in Gen2SaveMon.MAX_MOVES:
			var move_number: int = int(mon.moves[slot])
			mon.pp[slot] = int(world.data.move(move_number).get("pp", 0)) if move_number > 0 else 0

	var before: Gen2WorldSnapshot = world.snapshot()
	var resumed: Array = world.complete_runtime_request({
		"ok": true,
		"script_value": 1,
		"healed_members": healed,
	})
	if resumed.is_empty() or not bool(resumed[0].get("ok", false)):
		return _failure(&"runtime_request_failed", {"results": resumed})
	candidate.world = world.snapshot()
	var candidate_validation: Dictionary = Gen2SaveValidator.validate(candidate, world.data)
	if not bool(candidate_validation.get("ok", false)):
		world.state.restore_from_dict(before.world_state.to_dict())
		return _failure(&"candidate_save_invalid", candidate_validation)
	var write_result: Dictionary = {"ok": true}
	if persist:
		write_result = Gen2SaveStore.save(candidate, world.data)
	if not bool(write_result.get("ok", false)):
		world.state.restore_from_dict(before.world_state.to_dict())
		return _failure(&"save_failed", write_result)
	_copy_save(save, candidate)
	return {
		"ok": true,
		"handled": true,
		"healed_members": healed,
		"results": resumed,
	}


## Applies a field item to a save and the live world as one candidate transaction.
## The current slice covers the source's HP/status/revival and repel effects.
static func use_item(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	item: int,
	party_index: int = -1,
	persist: bool = true
) -> Dictionary:
	if world == null or save == null or world.data == null:
		return _failure(&"missing_save", {})
	if world.state == null or world.state.item_quantity(item) <= 0:
		return _failure(&"insufficient_item_quantity", {"item": item})
	var validation: Dictionary = Gen2SaveValidator.validate(save, world.data)
	if not bool(validation.get("ok", false)):
		return _failure(&"invalid_save", {"message": validation.get("message", "")})
	var candidate: Gen2SaveData = Gen2SaveData.from_dict(save.to_dict())
	var effect: Dictionary = _apply_item_effect(world.data, candidate, item, party_index)
	if not bool(effect.get("ok", false)):
		return _failure(StringName(effect.get("reason", &"item_has_no_effect")), effect)
	var before: Gen2WorldSnapshot = world.snapshot()
	var next_quantity: int = world.state.item_quantity(item) - 1
	var changes: Dictionary = {"items": {item: next_quantity}}
	if effect.has("repel_steps"):
		changes["repel_steps"] = int(effect["repel_steps"])
	var applied: Dictionary = world.state.apply_changes({}, {}, changes)
	if not bool(applied.get("ok", false)):
		return _failure(&"item_state_failed", applied)
	candidate.world = world.snapshot()
	var candidate_validation: Dictionary = Gen2SaveValidator.validate(candidate, world.data)
	if not bool(candidate_validation.get("ok", false)):
		world.state.restore_from_dict(before.world_state.to_dict())
		return _failure(&"candidate_save_invalid", candidate_validation)
	var write_result: Dictionary = {"ok": true}
	if persist:
		write_result = Gen2SaveStore.save(candidate, world.data)
	if not bool(write_result.get("ok", false)):
		world.state.restore_from_dict(before.world_state.to_dict())
		return _failure(&"save_failed", write_result)
	_copy_save(save, candidate)
	return {
		"ok": true,
		"item": item,
		"party_index": party_index,
		"effect": effect.get("effect", &""),
		"healed": int(effect.get("healed", 0)),
		"status_cleared": int(effect.get("status_cleared", 0)),
		"repel_steps": int(effect.get("repel_steps", -1)),
	}


## Attempts to catch one wild battle mon and consumes the ball on either result.
## The battle screen owns the animation; this host owns the cartridge outcome and
## the save/world writeback. A caught mon enters the party when there is room and
## otherwise uses the first free PC-box slot.
static func capture_wild(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	wild: Gen2BattleMon,
	ball: int,
	random: RandomNumberGenerator = null,
	caught_location: int = 0,
	persist: bool = true
) -> Dictionary:
	if world == null or save == null or world.data == null or wild == null:
		return _failure(&"missing_capture_context", {})
	var validation: Dictionary = Gen2SaveValidator.validate(save, world.data)
	if not bool(validation.get("ok", false)):
		return _failure(&"invalid_save", {"message": validation.get("message", "")})
	if save.party.size() >= Gen2SaveData.MAX_PARTY:
		var storage: Dictionary = save.first_empty_box_slot()
		if not bool(storage.get("ok", false)):
			return _failure(&"storage_full", {"ball": ball})
	var definition: Dictionary = world.data.item(ball)
	if definition.is_empty():
		return _failure(&"unknown_ball", {"ball": ball})
	if int(definition.get("pocket", 0)) != RomLayout.ITEM_POCKET_BALL:
		return _failure(&"item_is_not_a_ball", {"ball": ball})
	if ball not in [ITEM_MASTER_BALL, ITEM_ULTRA_BALL, ITEM_GREAT_BALL, ITEM_POKE_BALL]:
		return _failure(&"unsupported_ball_effect", {"ball": ball})
	if world.state == null or world.state.item_quantity(ball) <= 0:
		return _failure(&"insufficient_ball_quantity", {"ball": ball})
	var generator: RandomNumberGenerator = random if random != null else RandomNumberGenerator.new()
	if random == null:
		generator.randomize()
	var outcome: Dictionary = _capture_outcome(world.data, wild, ball, generator)
	var candidate: Gen2SaveData = Gen2SaveData.from_dict(save.to_dict())
	var destination: Dictionary = {}
	if bool(outcome.get("caught", false)):
		var captured: Gen2SaveMon = _captured_mon(
			world.data, save, wild, generator, caught_location
		)
		if captured == null:
			return _failure(&"could_not_create_captured_pokemon", outcome)
		destination = candidate.add_party_or_box(captured)
		if not bool(destination.get("ok", false)):
			return _failure(StringName(destination.get("reason", &"storage_full")), {
				"ball": ball, "outcome": outcome,
			})
	var before: Gen2WorldSnapshot = world.snapshot()
	var next_quantity: int = world.state.item_quantity(ball) - 1
	var item_result: Dictionary = world.state.apply_changes({}, {}, {"items": {ball: next_quantity}})
	if not bool(item_result.get("ok", false)):
		return _failure(&"ball_state_failed", item_result)
	candidate.world = world.snapshot()
	var candidate_validation: Dictionary = Gen2SaveValidator.validate(candidate, world.data)
	if not bool(candidate_validation.get("ok", false)):
		world.state.restore_from_dict(before.world_state.to_dict())
		return _failure(&"candidate_save_invalid", candidate_validation)
	var write_result: Dictionary = {"ok": true}
	if persist:
		write_result = Gen2SaveStore.save(candidate, world.data)
	if not bool(write_result.get("ok", false)):
		world.state.restore_from_dict(before.world_state.to_dict())
		return _failure(&"save_failed", write_result)
	_copy_save(save, candidate)
	return {
		"ok": true,
		"handled": true,
		"caught": bool(outcome.get("caught", false)),
		"ball": ball,
		"quantity": next_quantity,
		"catch_rate": int(outcome.get("catch_rate", 0)),
		"wobbles": int(outcome.get("wobbles", 0)),
		"species": wild.species,
		"destination": destination.duplicate(true),
	}


static func _apply_party_request(
	world: Gen2WorldAPI,
	candidate: Gen2SaveData,
	request: Dictionary,
	result: Dictionary,
	random: RandomNumberGenerator
) -> Dictionary:
	var kind: StringName = StringName(request.get("kind", &""))
	if kind == &"pokemon_requested":
		var values: Dictionary = request.get("values", {})
		var is_egg: bool = not values.has("pokemon")
		var species: int = int(values.get("pokemon", values.get("value", 0)))
		var level: int = int(values.get("level", values.get("value_2", 0)))
		var held_item: int = int(values.get("item", 0))
		if species <= 0 or world.data.species(species).is_empty():
			return {"ok": false, "reason": &"unknown_species", "species": species}
		if level < 1 or level > Gen2Experience.MAX_LEVEL:
			return {"ok": false, "reason": &"invalid_level", "level": level}
		if held_item < 0 or (held_item > 0 and world.data.item(held_item).is_empty()):
			return {"ok": false, "reason": &"unknown_item", "item": held_item}
		var mon: Gen2SaveMon = _new_mon(
			world.data, candidate, species, level, held_item, random, is_egg
		)
		if mon == null:
			return {"ok": false, "reason": &"could_not_create_pokemon"}
		if not is_egg:
			var source: Dictionary = request.get("source", {})
			var bank: int = int(source.get("bank", -1))
			var nickname: String = _world_name(
				world.data, bank, int(values.get("nickname_address", -1))
			)
			var ot_name: String = _world_name(
				world.data, bank, int(values.get("ot_name_address", -1))
			)
			if not nickname.is_empty():
				mon.nickname = nickname
			if not ot_name.is_empty():
				mon.original_trainer = ot_name
		return _append_mon(candidate, mon, 2 if is_egg else 1, {
			"kind": &"egg" if is_egg else &"gift",
			"species": species, "level": level, "item": held_item,
		})

	if kind == &"trade_requested":
		var values: Dictionary = request.get("values", {})
		var trade_id: int = int(values.get("trade_id", -1))
		var trade: Dictionary = world.data.world_trade(trade_id)
		if trade.is_empty():
			return {"ok": false, "reason": &"unknown_trade", "trade_id": trade_id}
		var requested_index: int = int(result.get("party_index", -1))
		if requested_index < 0 or requested_index >= candidate.party.size():
			requested_index = _find_trade_candidate(world.data, candidate, trade)
		if requested_index < 0:
			return {
				"ok": true, "accepted": false, "script_value": 0,
				"reason": &"requested_pokemon_missing",
				"summary": {"kind": &"trade", "accepted": false, "trade_id": trade_id},
			}
		var requested: Gen2SaveMon = candidate.party[requested_index]
		if requested.species != int(trade["requested_species"]):
			return {"ok": false, "reason": &"trade_candidate_mismatch"}
		if not _trade_gender_matches(
			world.data, requested, int(trade.get("gender", RomLayout.TRADE_GENDER_EITHER))
		):
			return {"ok": false, "reason": &"trade_candidate_gender_mismatch"}
		var received: Gen2SaveMon = _new_mon(
			world.data, candidate, int(trade["offered_species"]), requested.level,
			int(trade["item"]), random, false, int(trade["dvs"])
		)
		if received == null:
			return {"ok": false, "reason": &"could_not_create_trade_pokemon"}
		received.nickname = String(trade.get("nickname", ""))
		received.original_trainer = String(trade.get("ot_name", ""))
		received.ot_id = int(trade.get("ot_id", 0))
		candidate.party[requested_index] = received
		return {
			"ok": true, "accepted": true, "script_value": 1,
			"summary": {
				"kind": &"trade", "accepted": true, "trade_id": trade_id,
				"given_species": requested.species,
				"received_species": received.species,
			},
		}
	return {"ok": false, "reason": &"unsupported_party_request"}


static func _append_mon(
	candidate: Gen2SaveData, mon: Gen2SaveMon, script_value: int, summary: Dictionary
) -> Dictionary:
	var destination: Dictionary = candidate.add_party_or_box(mon)
	if not bool(destination.get("ok", false)):
		return {
			"ok": false,
			"reason": destination.get("reason", &"storage_full"),
			"destination": destination,
		}
	return {
		"ok": true, "accepted": true, "script_value": script_value,
		"summary": summary.merged({
			"accepted": true, "destination": destination.duplicate(true),
		}),
	}


static func _new_mon(
	data: GameData,
	save: Gen2SaveData,
	species: int,
	level: int,
	held_item: int,
	random: RandomNumberGenerator,
	is_egg: bool,
	dvs: int = -1
) -> Gen2SaveMon:
	var known_moves: Array = data.moves_at_level(species, level)
	var dv_word: int = Gen2BattleMon.random_dvs(random) if dvs < 0 else dvs
	var battle_mon: Gen2BattleMon = Gen2BattleMon.create(
		data, species, level, known_moves, dv_word, {}, held_item
	)
	if battle_mon == null:
		return null
	var out: Gen2SaveMon = Gen2SaveBattleAdapter.from_battle_mon(battle_mon)
	out.nickname = String(data.species(species).get("name", ""))
	out.original_trainer = save.player_name
	out.is_egg = is_egg
	if is_egg:
		out.nickname = "EGG"
		out.hp = 0
	return out


static func _find_trade_candidate(data: GameData, save: Gen2SaveData, trade: Dictionary) -> int:
	var requested_species: int = int(trade.get("requested_species", 0))
	var required_gender: int = int(trade.get("gender", RomLayout.TRADE_GENDER_EITHER))
	for index: int in save.party.size():
		var mon: Gen2SaveMon = save.party[index]
		if mon == null or mon.is_egg or mon.species != requested_species:
			continue
		if _trade_gender_matches(data, mon, required_gender):
			return index
	return -1


static func _trade_gender_matches(
	data: GameData, mon: Gen2SaveMon, required_gender: int
) -> bool:
	if required_gender == RomLayout.TRADE_GENDER_EITHER:
		return true
	var battle_mon: Gen2BattleMon = Gen2SaveBattleAdapter.to_battle_mon(data, mon)
	if battle_mon == null:
		return false
	if required_gender == RomLayout.TRADE_GENDER_MALE:
		return battle_mon.gender() == Gen2BattleMon.GENDER_MALE
	if required_gender == RomLayout.TRADE_GENDER_FEMALE:
		return battle_mon.gender() == Gen2BattleMon.GENDER_FEMALE
	return false


static func _apply_item_effect(
	data: GameData, save: Gen2SaveData, item: int, party_index: int
) -> Dictionary:
	var definition: Dictionary = data.item(item)
	if definition.is_empty():
		return {"ok": false, "reason": &"unknown_item", "item": item}
	if item in [ITEM_REPEL, ITEM_SUPER_REPEL, ITEM_MAX_REPEL]:
		return {
			"ok": true, "effect": &"repel",
			"repel_steps": 100 if item == ITEM_REPEL else (200 if item == ITEM_SUPER_REPEL else 250),
		}
	if party_index < 0 or party_index >= save.party.size():
		return {"ok": false, "reason": &"party_member_required"}
	var mon: Gen2SaveMon = save.party[party_index]
	if mon == null or mon.is_egg:
		return {"ok": false, "reason": &"invalid_party_member"}
	var max_hp: int = _max_hp(data, mon)
	if item in [ITEM_REVIVE, ITEM_MAX_REVIVE]:
		if mon.hp > 0:
			return {"ok": false, "reason": &"item_has_no_effect"}
		mon.hp = max_hp if item == ITEM_MAX_REVIVE else maxi(max_hp / 2, 1)
		return {"ok": true, "effect": &"revive", "healed": mon.hp}

	var status_mask: int = int(definition.get("status_mask", 0))
	var heal_amount: int = int(definition.get("heal_amount", 0))
	var cleared: int = mon.status & status_mask
	var healed: int = 0
	if heal_amount > 0 and mon.hp > 0:
		var target_hp: int = max_hp if heal_amount >= Gen2Stats.MAX_STAT_VALUE else mini(
			max_hp, mon.hp + heal_amount
		)
		healed = target_hp - mon.hp
		mon.hp = target_hp
	if cleared != 0:
		mon.status &= ~status_mask
	if healed <= 0 and cleared == 0:
		return {"ok": false, "reason": &"item_has_no_effect"}
	return {
		"ok": true, "effect": &"party_item", "healed": healed,
		"status_cleared": cleared,
	}


static func _capture_outcome(
	data: GameData, wild: Gen2BattleMon, ball: int, random: RandomNumberGenerator
) -> Dictionary:
	if ball == ITEM_MASTER_BALL:
		return {"caught": true, "catch_rate": 255, "wobbles": 3}
	var species: Dictionary = data.species(wild.species)
	var catch_rate: int = clampi(int(species.get("catch_rate", 0)), 1, 255)
	match ball:
		ITEM_ULTRA_BALL:
			catch_rate = mini(catch_rate * 2, 255)
		ITEM_GREAT_BALL:
			catch_rate = mini(catch_rate + int(catch_rate / 2.0), 255)
		ITEM_POKE_BALL:
			pass
	var max_hp: int = maxi(wild.max_hp(), 1)
	var current_hp: int = clampi(wild.hp, 1, max_hp)
	var final_rate: int = _source_hp_catch_rate(max_hp, current_hp, catch_rate)
	# This is the actual Gen 2 behavior: sleep and freeze add 10, while the
	# intended +5 for burn, poison and paralysis is skipped by the source bug.
	if Gen2Status.has(wild.status, Gen2Status.FREEZE) or Gen2Status.is_asleep(wild.status):
		final_rate = mini(final_rate + 10, 255)
	var caught: bool = random.randi_range(0, 255) <= final_rate
	return {
		"caught": caught,
		"catch_rate": final_rate,
		"wobbles": 3 if caught else _failed_wobbles(final_rate, random),
	}


static func _source_hp_catch_rate(max_hp: int, current_hp: int, catch_rate: int) -> int:
	# The cartridge shifts both operands by two only when 3 * max HP does not
	# fit in one byte. It then keeps the low byte, including the documented
	# high-HP overflow behavior, instead of using a wider modern formula.
	var three_max: int = 3 * max_hp
	var two_current: int = 2 * current_hp
	if (three_max >> 8) != 0:
		three_max >>= 2
		two_current >>= 2
	var divisor: int = maxi(three_max & 0xFF, 1)
	var current_part: int = maxi(two_current & 0xFF, 1)
	var remaining: int = maxi((three_max & 0xFF) - current_part, 0)
	return clampi(maxi(1, int(remaining * catch_rate / float(divisor))), 1, 255)


static func _failed_wobbles(catch_rate: int, random: RandomNumberGenerator) -> int:
	var chance: int = 63
	for row: Array in WOBBLE_PROBABILITIES:
		if catch_rate <= int(row[0]):
			chance = int(row[1])
			break
	for wobble: int in 3:
		if random.randi_range(0, 255) >= chance:
			return wobble + 1
	return 3


static func _captured_mon(
	data: GameData,
	save: Gen2SaveData,
	wild: Gen2BattleMon,
	random: RandomNumberGenerator,
	caught_location: int
) -> Gen2SaveMon:
	var out: Gen2SaveMon = Gen2SaveBattleAdapter.from_battle_mon(wild)
	if out == null:
		return null
	out.hp = wild.max_hp()
	out.status = Gen2Status.NONE
	out.nickname = String(data.species(wild.species).get("name", ""))
	out.original_trainer = save.player_name
	out.ot_id = random.randi_range(0, 0xFFFF)
	out.happiness = 70
	out.caught_level = wild.level
	out.caught_gender = 1 if wild.gender() == Gen2BattleMon.GENDER_FEMALE else 0
	out.caught_location = clampi(caught_location, 0, 127)
	out.is_egg = false
	return out


static func _max_hp(data: GameData, mon: Gen2SaveMon) -> int:
	var species: Dictionary = data.species(mon.species)
	var base: Dictionary = species.get("stats", {})
	return Gen2Stats.calculate(
		int(base.get("hp", 0)), Gen2Stats.hp_dv(mon.dvs), int(mon.stat_exp.get("hp", 0)),
		mon.level, true
	)


static func _world_name(data: GameData, bank: int, address: int) -> String:
	if bank < 0 or address < 0:
		return ""
	var bytes: PackedByteArray = data.world_text(bank, address)
	return Gen2Text.decode_fixed(bytes, 0, RomLayout.TRADE_NAME_LENGTH) if not bytes.is_empty() else ""


static func _copy_save(target: Gen2SaveData, source: Gen2SaveData) -> void:
	target.format_version = source.format_version
	target.game_id = source.game_id
	target.rom_sha1 = source.rom_sha1
	target.slot = source.slot
	target.player_name = source.player_name
	target.party = source.party
	target.boxes = source.boxes
	target.world = source.world


static func _failure(reason: StringName, details: Dictionary) -> Dictionary:
	return {"ok": false, "handled": false, "reason": reason, "details": details.duplicate(true)}
