class_name Gen2AISwitch
extends RefCounted

## Whether a trainer pulls its Pokémon out, and which one it sends instead.
##
## `CheckAbleToSwitch` and its five party scans in
## [code]engine/battle/ai/switch.asm[/code], plus the three frequency gates in
## [code]engine/battle/ai/items.asm[/code] that decide how often the answer is
## acted on.
##
## The cartridge works in six-bit masks over the enemy party and reuses one
## variable as both a score and a party index. Here the masks are arrays of party
## indices and the two uses are separate return values, which changes nothing:
## every scan keeps party order, and every place the cartridge converts a mask to
## an index it takes the lowest index set, which is what every scan here answers
## with too.

## `BASE_AI_SWITCH_SCORE`, where [method matchup_score] starts before anything
## nudges it.
const BASE_SCORE: int = 10

## The score at or above which `CheckAbleToSwitch` stops looking: things are
## going well enough that there is nothing to think about.
const COMFORTABLE_SCORE: int = 11

## The three tiers `wEnemySwitchMonParam`'s high nibble carries, in rising order
## of how much the AI wants out. The low nibble is the party index, which is why
## the cartridge adds them together.
const TIER_LOW: int = 1
const TIER_MID: int = 2
const TIER_HIGH: int = 3

## How often each frequency acts on each tier, out of 256. Read off
## `SwitchOften`, `SwitchRarely` and `SwitchSometimes`, whose `$30` branches are
## written inverted ("don't switch if the roll is under") and are stated here as
## the chance of switching, which is what they come to.
const CHANCES: Dictionary = {
	RomLayout.SWITCH_OFTEN: {TIER_LOW: 128, TIER_MID: 200, TIER_HIGH: 246},
	RomLayout.SWITCH_RARELY: {TIER_LOW: 20, TIER_MID: 30, TIER_HIGH: 56},
	RomLayout.SWITCH_SOMETIMES: {TIER_LOW: 50, TIER_MID: 128, TIER_HIGH: 206},
}

## `EFFECTIVE + 1`: the cartridge tests "super effective" as "more than neutral"
## against a tenths figure, so anything above ten counts.
const SUPER_EFFECTIVE: int = RomLayout.MATCHUP_EFFECTIVE + 1

## What `.CheckEnemyMoveMatchups` adds per enemy move, and the figure a single
## super-effective move jumps straight to.
const WEIGHT_NOT_VERY_EFFECTIVE: int = 1
const WEIGHT_NEUTRAL: int = 6
const WEIGHT_SUPER_EFFECTIVE: int = 100

## The bands that figure is read in: nothing that lands at all is worth two off,
## under five is worth one, and a super-effective move is worth one back.
const THREAT_LOW: int = 5


## Whether this trainer switches, and to which party index.
##
## Answers [code]{"switch": bool, "index": int}[/code]. [param flags] is the
## class's own [constant RomLayout.ATTR_AI_ITEM_SWITCH] word; a class with none
## of the three switch bits never switches, which is `AI_SwitchOrTryItem`'s own
## fallthrough to `DontSwitch`.
static func decide(battle: Gen2Battle, flags: int, rng: RandomNumberGenerator) -> Dictionary:
	var frequency: int = _frequency(flags)
	if frequency == 0:
		return {"switch": false, "index": -1}

	var choice: Dictionary = evaluate(battle)
	if int(choice["tier"]) == 0:
		return {"switch": false, "index": -1}
	if not _alive_enough_to_switch(battle):
		return {"switch": false, "index": -1}

	var chance: int = int((CHANCES[frequency] as Dictionary)[int(choice["tier"])])
	if rng.randi_range(0, 255) >= chance:
		return {"switch": false, "index": -1}
	return {"switch": true, "index": int(choice["index"])}


## `FindMonInOTPartyToSwitchIntoBattle`: who the AI would rather have in, with no
## opinion about whether it should switch at all.
##
## [method decide] is the ordinary route and answers both questions at once.
## Baton Pass is the one caller that has already settled the first, so it needs
## the pick on its own. Nobody standing answers -1; a shortlist that resists
## nothing falls back to the lowest index still up, which is `.not_2` walking the
## alive mask from the top.
static func pick_target(battle: Gen2Battle) -> int:
	var alive: Array = _alive_others(battle)
	if alive.is_empty():
		return -1
	var best: Dictionary = _best_answer(battle, alive)
	var index: int = int(best["index"])
	return index if index >= 0 else int(alive[0])


## `CheckAbleToSwitch`: how badly the AI wants out and who it would rather have
## in, as [code]{"tier": int, "index": int}[/code]. A tier of zero is "stay".
static func evaluate(battle: Gen2Battle) -> Dictionary:
	var alive: Array = _alive_others(battle)
	if alive.is_empty():
		return _stay()

	var perish: Dictionary = _perish_choice(battle, alive)
	if not perish.is_empty():
		return perish

	if matchup_score(battle) >= COMFORTABLE_SCORE:
		return _stay()

	var last_move: int = battle.mon(Gen2Battle.PLAYER).last_counter_move
	if last_move != 0:
		var immune: Array = _immune_to(battle, last_move)
		if not immune.is_empty():
			return _counter_choice(battle, immune)

	return _no_counter_choice(battle, alive)


## `CheckAbleToSwitch`'s opening branch: the turn before Perish Song finishes
## the Pokémon that is out, get somebody else in. Empty means the branch did not
## apply and the matchup half decides instead.
##
## Only a count of exactly one qualifies. Two is too early and zero has already
## killed, so a Pokémon that will survive the song is left to fight.
##
## The tier is [constant TIER_HIGH] either way, which is the whole point of the
## branch: what the shortlist changes is who comes in, not how much the AI wants
## the switch. With a super-effective answer standing it is that Pokémon; without
## one, `.not_2` walks the alive mask from the top and takes the first bit, which
## is the lowest party index still standing, shortlist or no shortlist.
static func _perish_choice(battle: Gen2Battle, alive: Array) -> Dictionary:
	var enemy: Gen2BattleMon = battle.mon(Gen2Battle.ENEMY)
	if not Gen2Substatus.has(enemy.substatus, Gen2Substatus.PERISH):
		return {}
	if enemy.perish_count != 1:
		return {}

	var shortlist: Array = _resisting(battle, _at_least_quarter_hp(battle, alive))
	var best: Dictionary = _best_answer(battle, shortlist)
	if int(best["quality"]) == 2:
		return {"tier": TIER_HIGH, "index": int(best["index"])}
	return {"tier": TIER_HIGH, "index": int(alive[0])}


## `.no_perish`'s tail, and `.no_last_counter_move`: the AI is losing the type
## war and wants somebody who is healthy, resists what is coming, and can hit
## back hard. Only a super-effective answer is worth acting on here.
static func _no_counter_choice(battle: Gen2Battle, alive: Array) -> Dictionary:
	if matchup_score(battle) >= BASE_SCORE:
		return _stay()

	var shortlist: Array = _resisting(
		battle, _at_least_quarter_hp(battle, alive)
	)
	var best: Dictionary = _best_answer(battle, shortlist)
	if int(best["quality"]) != 2:
		return _stay()
	return {"tier": TIER_LOW, "index": int(best["index"])}


## The branch behind `wLastPlayerCounterMove`: somebody on the bench is immune to
## what just hit, which is worth more than merely resisting it.
static func _counter_choice(battle: Gen2Battle, immune: Array) -> Dictionary:
	var best: Dictionary = _best_answer(battle, immune)
	if int(best["index"]) < 0:
		return _stay()

	if int(best["quality"]) == 2:
		# `.not_2_again`, which pret's label names for the branch it is not:
		# reached when the answer *is* super-effective, and the only question
		# left is how badly the current matchup is going.
		var tier: int = TIER_LOW if matchup_score(battle) >= BASE_SCORE else TIER_MID
		return {"tier": tier, "index": int(best["index"])}

	if matchup_score(battle) >= BASE_SCORE:
		return _stay()
	return {"tier": TIER_LOW, "index": int(best["index"])}


## `CheckPlayerMoveTypeMatchups`: how well the Pokémon that is out is doing,
## starting at [constant BASE_SCORE]. Higher is better for staying in.
##
## The first half reads what the player has actually thrown so far, falling back
## to the player's own types when it has thrown nothing. The second half reads
## what the enemy's own moves would do back.
static func matchup_score(battle: Gen2Battle) -> int:
	var score: int = BASE_SCORE
	var enemy: Gen2BattleMon = battle.mon(Gen2Battle.ENEMY)
	var player: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	var used: Array = battle.player_used_moves

	if used.is_empty():
		# `.unknown_moves`: assume the player will attack with its own types,
		# and count each of the two that is super effective against one off.
		var seen: Array = []
		for attacking: int in player.types():
			if seen.has(attacking):
				continue
			seen.append(attacking)
			if battle.data.type_effectiveness(
				attacking, enemy.types(),
				Gen2Substatus.has(enemy.substatus, Gen2Substatus.IDENTIFIED)
			) >= SUPER_EFFECTIVE:
				score -= 1
	else:
		score += _used_move_adjustment(battle, used, enemy)

	return score + _enemy_move_adjustment(battle, enemy, player)


## The `.loop`/`.exit` half: the best thing the player has actually used decides
## it. One super-effective move already thrown is worth a point off and ends the
## walk; otherwise a neutral best is worth nothing, a resisted best one point,
## and nothing that lands at all two.
static func _used_move_adjustment(battle: Gen2Battle, used: Array, enemy: Gen2BattleMon) -> int:
	var best: int = 0
	for move_number: int in used:
		var move: Dictionary = battle.data.move(int(move_number))
		if int(move.get("power", 0)) <= 0:
			continue
		var matchup: int = battle.data.type_effectiveness(
				int(move.get("type", 0)), enemy.types(),
				Gen2Substatus.has(enemy.substatus, Gen2Substatus.IDENTIFIED)
			)
		if matchup >= SUPER_EFFECTIVE:
			return -1
		if matchup == 0:
			continue
		if matchup >= RomLayout.MATCHUP_EFFECTIVE:
			best = 2
			continue
		best = maxi(best, 1)

	if best == 2:
		return 0
	return 1 if best == 1 else 2


## `.CheckEnemyMoveMatchups`: what the Pokémon that is out could do back, as one
## accumulated figure over its own moves.
static func _enemy_move_adjustment(
	battle: Gen2Battle, enemy: Gen2BattleMon, player: Gen2BattleMon
) -> int:
	var threat: int = 0
	for move_number: int in enemy.moves:
		var move: Dictionary = battle.data.move(int(move_number))
		if int(move.get("power", 0)) <= 0:
			continue
		var matchup: int = battle.data.type_effectiveness(
			int(move.get("type", 0)), player.types(),
			Gen2Substatus.has(player.substatus, Gen2Substatus.IDENTIFIED)
		)
		if matchup == 0:
			continue
		if matchup < RomLayout.MATCHUP_EFFECTIVE:
			threat += WEIGHT_NOT_VERY_EFFECTIVE
		elif matchup == RomLayout.MATCHUP_EFFECTIVE:
			threat += WEIGHT_NEUTRAL
		else:
			threat = WEIGHT_SUPER_EFFECTIVE
			break

	if threat == 0:
		return -2
	if threat < THREAT_LOW:
		return -1
	if threat < WEIGHT_SUPER_EFFECTIVE:
		return 0
	return 1


## `FindAliveEnemyMons`' carry flag, which is the only part of it three of the
## smart-scoring handlers want: whether the AI has anybody left to send in.
static func has_bench(battle: Gen2Battle) -> bool:
	return not _alive_others(battle).is_empty()


## `FindAliveEnemyMons`: every party index still standing except the one that is
## out. Empty means there is nothing to switch to and nothing to think about.
static func _alive_others(battle: Gen2Battle) -> Array:
	var party: Gen2Party = battle.party(Gen2Battle.ENEMY)
	var out: Array = []
	for index: int in party.size():
		if index == party.active:
			continue
		var member: Gen2BattleMon = party.at(index)
		if member != null and not member.is_fainted():
			out.append(index)
	return out


## `AI_TrySwitch`: the switch is only actually taken with two or more of the
## party standing, counting the one that is out.
static func _alive_enough_to_switch(battle: Gen2Battle) -> bool:
	var party: Gen2Party = battle.party(Gen2Battle.ENEMY)
	var standing: int = 0
	for index: int in party.size():
		var member: Gen2BattleMon = party.at(index)
		if member != null and not member.is_fainted():
			standing += 1
	return standing >= 2


## `FindEnemyMonsWithAtLeastQuarterMaxHP`, narrowing whoever was passed in.
static func _at_least_quarter_hp(battle: Gen2Battle, candidates: Array) -> Array:
	var party: Gen2Party = battle.party(Gen2Battle.ENEMY)
	var out: Array = []
	for index: int in candidates:
		var member: Gen2BattleMon = party.at(int(index))
		if member != null and member.hp * 4 >= member.max_hp():
			out.append(index)
	return out


## `FindEnemyMonsThatResistPlayer`: nobody who would be hit super effectively by
## the player's last damaging move, or, when there has not been one, by either of
## the player's own types.
static func _resisting(battle: Gen2Battle, candidates: Array) -> Array:
	var party: Gen2Party = battle.party(Gen2Battle.ENEMY)
	var player: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	var attacking: Array = []

	var last_move: int = player.last_counter_move
	if last_move != 0:
		var move: Dictionary = battle.data.move(last_move)
		if int(move.get("power", 0)) > 0:
			attacking = [int(move.get("type", 0))]
	if attacking.is_empty():
		attacking = player.types()

	var out: Array = []
	for index: int in candidates:
		var member: Gen2BattleMon = party.at(int(index))
		if member == null:
			continue
		var safe: bool = true
		for attacking_type: int in attacking:
			if battle.data.type_effectiveness(
				attacking_type, member.types(),
				Gen2Substatus.has(member.substatus, Gen2Substatus.IDENTIFIED)
			) >= SUPER_EFFECTIVE:
				safe = false
				break
		if safe:
			out.append(index)
	return out


## `FindEnemyMonsWithASuperEffectiveMove`, with `FindAliveEnemyMons` folded in
## the way `FindAliveEnemyMonsWithASuperEffectiveMove` folds it.
##
## Answers [code]{"index": int, "quality": int}[/code]: quality 2 for the first
## candidate holding a move that is super effective against whoever the player
## has out, 1 for the first that at least has a neutral one, and 0 for nobody.
## Both non-zero answers take the earliest such party index, which is what the
## cartridge's mask-to-index conversion comes to.
static func _best_answer(battle: Gen2Battle, candidates: Array) -> Dictionary:
	var party: Gen2Party = battle.party(Gen2Battle.ENEMY)
	var player: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	var neutral: int = -1

	for index: int in candidates:
		var member: Gen2BattleMon = party.at(int(index))
		if member == null or member.is_fainted():
			continue
		var quality: int = 0
		for move_number: int in member.moves:
			var move: Dictionary = battle.data.move(int(move_number))
			if int(move.get("power", 0)) <= 0:
				continue
			var matchup: int = battle.data.type_effectiveness(
				int(move.get("type", 0)), player.types(),
				Gen2Substatus.has(player.substatus, Gen2Substatus.IDENTIFIED)
			)
			if matchup < RomLayout.MATCHUP_EFFECTIVE:
				continue
			if matchup >= SUPER_EFFECTIVE:
				quality = 2
				break
			quality = 1
		if quality == 2:
			return {"index": int(index), "quality": 2}
		if quality == 1 and neutral < 0:
			neutral = int(index)

	if neutral >= 0:
		return {"index": neutral, "quality": 1}
	return {"index": -1, "quality": 0}


## `FindEnemyMonsImmuneToLastCounterMove`: whoever on the bench takes nothing at
## all from the move that just landed. Only damaging moves count.
static func _immune_to(battle: Gen2Battle, move_number: int) -> Array:
	var move: Dictionary = battle.data.move(move_number)
	if int(move.get("power", 0)) <= 0:
		return []

	var party: Gen2Party = battle.party(Gen2Battle.ENEMY)
	var attacking: int = int(move.get("type", 0))
	var out: Array = []
	for index: int in party.size():
		if index == party.active:
			continue
		var member: Gen2BattleMon = party.at(index)
		if member == null or member.is_fainted():
			continue
		if battle.data.type_effectiveness(
			attacking, member.types(),
			Gen2Substatus.has(member.substatus, Gen2Substatus.IDENTIFIED)
		) == 0:
			out.append(index)
	return out


## Which of the three frequency bits a class carries, or zero for none. The
## cartridge tests them in this order and takes the first, so a class carrying
## two behaves as the first of them.
static func _frequency(flags: int) -> int:
	for bit: int in [
		RomLayout.SWITCH_OFTEN, RomLayout.SWITCH_RARELY, RomLayout.SWITCH_SOMETIMES,
	]:
		if (flags & bit) != 0:
			return bit
	return 0


static func _stay() -> Dictionary:
	return {"tier": 0, "index": -1}
