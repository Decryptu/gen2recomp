class_name Gen2WorldPartyHost
extends RefCounted

## Scene-free transactions for party-owned overworld operations.
##
## A script can stage world changes and then pause for a gift, egg or NPC trade.
## The host builds a candidate save first, resumes the script, and only writes
## the candidate after both sides have succeeded. The six-party limit is
## deliberate until the save model has a real PC-box owner.

const ITEM_POTION: int = 0x12
const ITEM_REVIVE: int = 0x27
const ITEM_MAX_REVIVE: int = 0x28
const ITEM_REPEL: int = 0x14
const ITEM_SUPER_REPEL: int = 0x2A
const ITEM_MAX_REPEL: int = 0x2B
const ITEM_MASTER_BALL: int = 0x01
const ITEM_ULTRA_BALL: int = 0x02
const ITEM_GREAT_BALL: int = 0x04
const ITEM_POKE_BALL: int = 0x05
## The Bug Contest's own ball. It is never in the bag: `wParkBallsRemaining` is
## what holds it and `BattleMenu_Pack`'s contest branch loads it by name.
const ITEM_PARK_BALL: int = 0xB1

## HAPPINESS_THRESHOLD_1 and HAPPINESS_THRESHOLD_2
## (constants/pokemon_data_constants.asm), which pick a HappinessChanges column.
const HAPPINESS_THRESHOLD_1: int = 100
const HAPPINESS_THRESHOLD_2: int = 200

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
	var opened: Dictionary = Gen2WorldTransaction.begin(world, save)
	if not bool(opened.get("ok", false)):
		return _failure(StringName(opened["reason"]), {
			"details": opened.get("details", {}), "request": request,
		})

	var candidate: Gen2SaveData = opened["candidate"]
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
	## After the snapshot, so a refused transaction rolls the dex flag back with
	## everything else the request wrote.
	_register_caught(world, int(transaction.get("register_caught", 0)))
	_register_unown(world, int(transaction.get("register_unown", 0)))
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

	var committed: Dictionary = Gen2WorldTransaction.commit(
		world, save, candidate, before, persist
	)
	if not bool(committed.get("ok", false)):
		return _failure(StringName(committed["reason"]), {
			"details": committed.get("details", {}), "results": resumed,
		})
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
	var opened: Dictionary = Gen2WorldTransaction.begin(world, save)
	if not bool(opened.get("ok", false)):
		return _failure(StringName(opened["reason"]), opened.get("details", {}))
	var candidate: Gen2SaveData = opened["candidate"]
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
	var committed: Dictionary = Gen2WorldTransaction.commit(
		world, save, candidate, before, persist
	)
	if not bool(committed.get("ok", false)):
		return _failure(StringName(committed["reason"]), committed.get("details", {}))
	return {
		"ok": true,
		"handled": true,
		"healed_members": healed,
		"results": resumed,
	}


## `Softboiled_MilkDrinkFunction`: a fifth of the user's own maximum health moved
## from the user to another party member, as one candidate transaction.
##
## Both halves are the *user's* fifth. `GetOneFifthMaxHP` is called twice with
## `wCurPartyMon` still holding the user, and only then is the recipient written
## into it, so a big Pokemon heals a small one by a big number.
##
## The refusals are `.SelectMilkDrinkRecipient`'s own, in its order: the user
## itself, a fainted recipient and one already at full health. The caller checks
## the user's own health first, which is the `.CheckMonHasEnoughHP` this shares
## with the party menu's line.
static func transfer_health(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	from_index: int,
	to_index: int,
	persist: bool = true,
) -> Dictionary:
	if world == null or save == null or world.data == null:
		return _failure(&"missing_save", {})
	if from_index == to_index:
		return _failure(&"same_member", {"party_index": to_index})
	var opened: Dictionary = Gen2WorldTransaction.begin(world, save)
	if not bool(opened.get("ok", false)):
		return _failure(StringName(opened["reason"]), opened.get("details", {}))
	var candidate: Gen2SaveData = opened["candidate"]
	var user: Gen2SaveMon = _party_member(candidate, from_index)
	var target: Gen2SaveMon = _party_member(candidate, to_index)
	if user == null or target == null:
		return _failure(&"unknown_party_member", {"party_index": to_index})
	var amount: int = one_fifth_max_hp(world.data, user)
	if amount <= 0 or user.hp <= amount:
		return _failure(&"not_enough_health", {"party_index": from_index})
	if target.is_egg or target.hp <= 0:
		return _failure(&"fainted_member", {"party_index": to_index})
	var target_max: int = _max_hp(world.data, target)
	if target.hp >= target_max:
		return _failure(&"already_full", {"party_index": to_index})

	user.hp -= amount
	var restored: int = mini(amount, target_max - target.hp)
	target.hp += restored
	var before: Gen2WorldSnapshot = world.snapshot()
	var committed: Dictionary = Gen2WorldTransaction.commit(
		world, save, candidate, before, persist
	)
	if not bool(committed.get("ok", false)):
		return _failure(StringName(committed["reason"]), committed.get("details", {}))
	return {
		"ok": true,
		"amount": amount,
		"restored": restored,
		"from": from_index,
		"to": to_index,
	}


## `GetOneFifthMaxHP`, and so also `.CheckMonHasEnoughHP`'s own divisor: a
## Pokemon may use Softboiled or Milk Drink only while it has more than this.
static func one_fifth_max_hp(data: GameData, mon: Gen2SaveMon) -> int:
	if data == null or mon == null or mon.is_egg:
		return 0
	@warning_ignore("integer_division")
	return _max_hp(data, mon) / 5


## A party member by index, or null when the slot is empty.
static func _party_member(save: Gen2SaveData, index: int) -> Gen2SaveMon:
	if save == null or index < 0 or index >= save.party.size():
		return null
	return save.party[index]


## Applies a field item to a save and the live world as one candidate transaction.
## The current slice covers source party item effects, including EvoStoneEffect's
## candidate evolution and the HP delta applied by EvolvePokemon.
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
	var opened: Dictionary = Gen2WorldTransaction.begin(world, save)
	if not bool(opened.get("ok", false)):
		return _failure(StringName(opened["reason"]), opened.get("details", {}))
	var candidate: Gen2SaveData = opened["candidate"]
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
	var committed: Dictionary = Gen2WorldTransaction.commit(
		world, save, candidate, before, persist
	)
	if not bool(committed.get("ok", false)):
		return _failure(StringName(committed["reason"]), committed.get("details", {}))
	return {
		"ok": true,
		"item": item,
		"party_index": party_index,
		"effect": effect.get("effect", &""),
		"healed": int(effect.get("healed", 0)),
		"status_cleared": int(effect.get("status_cleared", 0)),
		"repel_steps": int(effect.get("repel_steps", -1)),
		"old_species": int(effect.get("old_species", 0)),
		"new_species": int(effect.get("new_species", 0)),
		"move_offers": effect.get("move_offers", []).duplicate(),
	}


## engine/items/tmhm.asm's TeachTMHM, as one candidate transaction beside
## use_item(). The pack's own USE reaches this, not `UseItem`'s jumptable: the
## TM/HM pocket runs AskTeachTMHM, ChooseMonToLearnTMHM and TeachTMHM instead
## (engine/items/pack.asm's .UseItem).
##
## The refusal order is the source's. CanLearnTMHMMove comes first, then
## KnowsMove, then LearnMove's own search for an empty slot; each answers before
## anything is written.
##
## A full moveset is where LearnMove reaches ForgetMove, which is a menu, so this
## is called twice: once with [param forget_slot] left at -1, which is what runs
## the two compatibility checks and answers `moveset_full` having written
## nothing, and again with the slot the player gave up. An empty slot always
## wins over a passed [param forget_slot], because LearnMove.loop only reaches
## ForgetMove when its own scan finds no zero.
##
## An HM is not consumed: TeachTMHM returns straight after IsHM, so it skips both
## ConsumeTM and the happiness change. The happiness change a TM does make is a
## boundary, since no ChangeHappiness table is imported.
static func teach_tm_hm(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	item: int,
	party_index: int,
	forget_slot: int = -1,
	persist: bool = true
) -> Dictionary:
	if world == null or save == null or world.data == null:
		return _failure(&"missing_save", {})
	if world.state == null or world.state.item_quantity(item) <= 0:
		return _failure(&"insufficient_item_quantity", {"item": item})
	var move: int = Gen2WorldTMHM.move_for_item(world.data, item)
	if move <= 0:
		return _failure(&"not_a_tm_hm", {"item": item})
	if party_index < 0 or party_index >= save.party.size():
		return _failure(&"invalid_party_index", {"party_index": party_index})
	var mon: Gen2SaveMon = save.party[party_index] as Gen2SaveMon
	if mon == null:
		return _failure(&"invalid_party_index", {"party_index": party_index})
	# ChooseMonToLearnTMHM refuses an egg with SFX_WRONG and reopens the list, so
	# an egg never reaches TeachTMHM at all.
	if mon.is_egg:
		return _failure(&"cannot_teach_egg", {"party_index": party_index})
	if not Gen2WorldTMHM.can_learn(world.data, mon.species, move):
		return _failure(&"not_compatible", {"species": mon.species, "move": move})
	if Gen2WorldTMHM.knows_move(mon.moves, move):
		return _failure(&"already_knows_move", {"move": move})
	var slot: int = Gen2WorldTMHM.first_empty_slot(mon.moves)
	var forgot: int = 0
	if slot < 0:
		# ForgetMove's own refusals, answering before the candidate save is built
		# the way every refusal above them does.
		if forget_slot < 0:
			return _failure(&"moveset_full", {
				"party_index": party_index, "move": move, "moves": mon.moves.duplicate(),
			})
		if forget_slot >= mon.moves.size():
			return _failure(&"invalid_forget_slot", {"forget_slot": forget_slot})
		forgot = int(mon.moves[forget_slot])
		if Gen2MoveForget.is_hm_move(forgot):
			return _failure(&"cannot_forget_hm", {"forget_slot": forget_slot, "forgot": forgot})
		slot = forget_slot

	var opened: Dictionary = Gen2WorldTransaction.begin(world, save)
	if not bool(opened.get("ok", false)):
		return _failure(StringName(opened["reason"]), opened.get("details", {}))
	var candidate: Gen2SaveData = opened["candidate"]
	var learner: Gen2SaveMon = candidate.party[party_index] as Gen2SaveMon
	learner.moves[slot] = move
	# LearnMove writes the move, then its PP from Moves + MOVE_PP: a freshly
	# learned move always arrives at full PP.
	learner.pp[slot] = int(world.data.move(move).get("pp", 0))

	var before: Gen2WorldSnapshot = world.snapshot()
	## `IsHM` returns before both the happiness change and `ConsumeTM`, so an HM
	## costs nothing and moves nothing; a TM does both, in that order.
	var consumed: bool = not Gen2WorldTMHM.is_hm(item)
	var happiness: int = learner.happiness
	if consumed:
		learner.happiness = change_happiness(
			world.data, learner.happiness, RomLayout.HAPPINESS_LEARNMOVE
		)
	var applied: Dictionary = {"ok": true}
	if consumed:
		applied = world.state.apply_changes({}, {}, {
			"items": {item: world.state.item_quantity(item) - 1},
		})
	if not bool(applied.get("ok", false)):
		return _failure(&"item_state_failed", applied)
	var committed: Dictionary = Gen2WorldTransaction.commit(
		world, save, candidate, before, persist
	)
	if not bool(committed.get("ok", false)):
		return _failure(StringName(committed["reason"]), committed.get("details", {}))
	return {
		"ok": true,
		"item": item,
		"party_index": party_index,
		"move": move,
		"slot": slot,
		"forgot": forgot,
		"pp": learner.pp[slot],
		"consumed": consumed,
		"happiness": learner.happiness,
		"happiness_change": learner.happiness - happiness,
	}


## `ChangeHappiness` over the imported table, without the egg and battle-mon
## halves: an egg cannot reach a caller here, and no caller runs inside a battle.
##
## The three rows are picked by HAPPINESS_THRESHOLD_1 and _2, and the sign of a
## change is `cp $64`: a byte from 100 up is the subtracting branch, which is why
## the table is read signed. Each branch answers the carry rather than clamping,
## so a rise saturates at 255 and a fall at 0.
static func change_happiness(data: GameData, happiness: int, kind: int) -> int:
	var changes: Array[int] = []
	if data != null:
		changes = data.happiness_changes(kind)
	if changes.size() < RomLayout.HAPPINESS_CHANGE_WIDTH:
		return happiness
	var row: int = 0 if happiness < HAPPINESS_THRESHOLD_1 \
		else (1 if happiness < HAPPINESS_THRESHOLD_2 else 2)
	return clampi(happiness + changes[row], 0, 255)



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
	var opened: Dictionary = Gen2WorldTransaction.begin(world, save)
	if not bool(opened.get("ok", false)):
		return _failure(StringName(opened["reason"]), opened.get("details", {}))
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
	var candidate: Gen2SaveData = opened["candidate"]
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
	## After the snapshot the rollback below restores, so a refused candidate
	## save takes the dex flag back with the ball.
	if bool(outcome.get("caught", false)):
		_register_caught(world, wild.species)
		_register_unown(world, _unown_form(
			wild.species, wild.persistent_dvs(), destination
		))
	var next_quantity: int = world.state.item_quantity(ball) - 1
	var item_result: Dictionary = world.state.apply_changes({}, {}, {"items": {ball: next_quantity}})
	if not bool(item_result.get("ok", false)):
		return _failure(&"ball_state_failed", item_result)
	var committed: Dictionary = Gen2WorldTransaction.commit(
		world, save, candidate, before, persist
	)
	if not bool(committed.get("ok", false)):
		return _failure(StringName(committed["reason"]), committed.get("details", {}))
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
			"register_caught": received.species,
			## A trade lands in the party slot the given Pokemon left, which is
			## the PARTYMON `GeneratePartyMonStats` registers.
			"register_unown": _unown_form(
				received.species, received.dvs, {"destination": &"party"}
			),
			"summary": {
				"kind": &"trade", "accepted": true, "trade_id": trade_id,
				"given_species": requested.species,
				"received_species": received.species,
			},
		}
	return {"ok": false, "reason": &"unsupported_party_request"}


## `AddPartyMon`'s `.registerpokedex`, which an egg never reaches: the source
## checks `cp EGG` first and jumps past `SetSeenAndCaughtMon`, so a Pokemon is
## unknown to the dex until it hatches.
static func _append_mon(
	candidate: Gen2SaveData, mon: Gen2SaveMon,
	script_value: int, summary: Dictionary
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
		"register_caught": 0 if StringName(summary.get("kind", &"")) == &"egg" else mon.species,
		"register_unown": 0 if mon.is_egg else _unown_form(mon.species, mon.dvs, destination),
		"summary": summary.merged({
			"accepted": true, "destination": destination.duplicate(true),
		}),
	}


## `SetSeenAndCaughtMon`. Written straight onto the live state rather than
## staged, the way the ball count is, and always after the caller has taken its
## rollback snapshot so a refused save takes the flag back too.
static func _register_caught(world: Gen2WorldAPI, species: int) -> void:
	if world == null or world.state == null or species <= 0:
		return
	world.state.set_species_caught(species)


## `GeneratePartyMonStats`' `.registerunowndex`. The form is read off the DVs
## rather than stored, and only a Pokemon that reached the party registers: the
## routine runs under `wMonType` PARTYMON alone, so an Unown caught with a full
## party is caught without entering the Unown dex.
static func _unown_form(species: int, dvs: int, destination: Dictionary) -> int:
	if species != RomLayout.UNOWN_SPECIES:
		return 0
	if StringName(destination.get("destination", &"")) != &"party":
		return 0
	return Gen2Stats.unown_letter(dvs)


## Written straight onto the live state beside [method _register_caught], and
## for the same reason: the caller has already taken the snapshot a refused save
## rolls back to.
static func _register_unown(world: Gen2WorldAPI, form: int) -> void:
	if world == null or world.state == null or form <= 0:
		return
	world.state.update_unown_dex(form)


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
	if item == Gen2WorldPack.ITEM_SACRED_ASH:
		return _apply_sacred_ash(data, save)
	if party_index < 0 or party_index >= save.party.size():
		return {"ok": false, "reason": &"party_member_required"}
	var mon: Gen2SaveMon = save.party[party_index]
	if mon == null or mon.is_egg:
		return {"ok": false, "reason": &"invalid_party_member"}
	var evolution: Dictionary = _apply_item_evolution(data, mon, item)
	if not evolution.is_empty():
		return evolution
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


## `_SacredAsh`: `CheckAnyFaintedMon` first, which skips eggs and stops at the
## first zero, and then `SacredAshScript`'s `special HealParty` over the whole
## party rather than over the fainted members alone.
static func _apply_sacred_ash(data: GameData, save: Gen2SaveData) -> Dictionary:
	var fainted: bool = false
	for mon: Gen2SaveMon in save.party:
		if mon != null and not mon.is_egg and mon.hp <= 0:
			fainted = true
			break
	if not fainted:
		return {"ok": false, "reason": &"item_has_no_effect"}
	var healed: int = 0
	for mon: Gen2SaveMon in save.party:
		if mon == null or mon.is_egg:
			continue
		var max_hp: int = _max_hp(data, mon)
		if max_hp <= 0:
			return {"ok": false, "reason": &"invalid_party_member"}
		healed += max_hp - mon.hp
		mon.hp = max_hp
		mon.status = Gen2Status.NONE
		for slot: int in Gen2SaveMon.MAX_MOVES:
			var move_number: int = int(mon.moves[slot])
			mon.pp[slot] = int(data.move(move_number).get("pp", 0)) if move_number > 0 else 0
	return {"ok": true, "effect": &"sacred_ash", "healed": healed}


static func _apply_item_evolution(data: GameData, mon: Gen2SaveMon, item: int) -> Dictionary:
	if item not in Gen2Evolution.STONE_ITEMS:
		return {}
	var battle_mon: Gen2BattleMon = Gen2SaveBattleAdapter.to_battle_mon(data, mon)
	if battle_mon == null:
		return {}
	var row: Dictionary = Gen2Evolution.item_evolution(data, battle_mon, item)
	if row.is_empty():
		return {}
	var result: Dictionary = Gen2Evolution.evolve(battle_mon, int(row.get("target", 0)))
	if result.is_empty():
		return {}
	var move_offers: Array[int] = []
	for move: int in data.moves_learned_at(battle_mon.species, battle_mon.level):
		if battle_mon.moves.has(move):
			continue
		if not battle_mon.learn_move(move):
			move_offers.append(move)
	mon.species = battle_mon.species
	mon.moves = [0, 0, 0, 0]
	mon.pp = [0, 0, 0, 0]
	for slot: int in mini(battle_mon.moves.size(), Gen2SaveMon.MAX_MOVES):
		mon.moves[slot] = int(battle_mon.moves[slot])
		mon.pp[slot] = int(battle_mon.pp[slot])
	mon.exp = battle_mon.exp
	mon.hp = battle_mon.hp
	mon.status = battle_mon.status
	mon.happiness = battle_mon.happiness
	return {
		"ok": true,
		"effect": &"evolution",
		"old_species": int(result["old_species"]),
		"new_species": int(result["new_species"]),
		"move_offers": move_offers,
	}


## A Park Ball thrown inside the Bug Catching Contest, which is a different
## transaction from [method capture_wild]: the ball comes out of
## `wParkBallsRemaining` rather than the bag, and what is caught goes to
## `wContestMon` rather than to the party or a box, so no save is touched and
## nothing can be refused for a full party.
##
## `BugContest_SetCaughtContestMon` asks before replacing a Pokemon already
## caught, so a hit while one is held answers `replace_offer` and leaves the
## state alone until the caller comes back with [method set_contest_mon].
static func capture_contest(
	world: Gen2WorldAPI, wild: Gen2BattleMon, random: RandomNumberGenerator = null
) -> Dictionary:
	if world == null or world.data == null or world.state == null or wild == null:
		return _failure(&"missing_capture_context", {})
	if world.state.park_balls() <= 0:
		return _failure(&"no_park_balls", {"ball": ITEM_PARK_BALL})
	var generator: RandomNumberGenerator = random if random != null else RandomNumberGenerator.new()
	if random == null:
		generator.randomize()
	world.state.set_park_balls(world.state.park_balls() - 1)
	var outcome: Dictionary = _capture_outcome(world.data, wild, ITEM_PARK_BALL, generator)
	var result: Dictionary = {
		"ok": true,
		"ball": ITEM_PARK_BALL,
		"quantity": world.state.park_balls(),
		"caught": bool(outcome["caught"]),
		"catch_rate": int(outcome["catch_rate"]),
		"wobbles": int(outcome["wobbles"]),
		"contest": true,
	}
	if not bool(outcome["caught"]):
		return result
	result["mon"] = contest_mon_from(wild)
	result["replace_offer"] = not world.state.contest_mon().is_empty()
	if not bool(result["replace_offer"]):
		world.state.set_contest_mon(result["mon"])
	return result


## `.generatestats`: the caught Pokemon as `ContestScore` reads it. The stats
## and DVs are the ones the wild was standing there with, which is what
## `GeneratePartyMonStats` builds for a `WILDMON`.
static func contest_mon_from(wild: Gen2BattleMon) -> Dictionary:
	return {
		"species": wild.species,
		"level": wild.level,
		"hp": wild.hp,
		"max_hp": wild.max_hp(),
		"attack": int(wild.stats.get("attack", 0)),
		"defense": int(wild.stats.get("defense", 0)),
		"speed": int(wild.stats.get("speed", 0)),
		"special_attack": int(wild.stats.get("sp_attack", 0)),
		"special_defense": int(wild.stats.get("sp_defense", 0)),
		"dvs": wild.dvs,
		"item": wild.item,
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
		## `GreatBallMultiplier` and `ParkBallMultiplier` are the same routine
		## written twice: catch rate times one and a half.
		ITEM_GREAT_BALL, ITEM_PARK_BALL:
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


static func _failure(reason: StringName, details: Dictionary) -> Dictionary:
	return {"ok": false, "handled": false, "reason": reason, "details": details.duplicate(true)}
