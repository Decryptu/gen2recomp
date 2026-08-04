class_name Gen2BattleAI
extends RefCounted

## Scores an enemy trainer's move choice the way the cartridge's own AI does.
##
## Every slot starts at 20; a slot with no PP starts at 80. Each bit set in the
## trainer class's own [constant RomLayout.ATTR_AI_MOVE_WEIGHTS] word runs one
## scoring layer over the four slots, in the cartridge's own bit order (see
## [constant RomLayout.AI_BASIC] through [constant RomLayout.AI_RISKY]), each
## nudging a score up (discourage) or down (encourage). The move with the
## lowest score wins; a tie is broken at random.
##
## [RefCounted], scene-free and its randomness passed in, the same discipline
## [Gen2Battle] holds to, so a whole AI decision can be asserted on inside a
## test.
##
## The real routine (`engine/battle/ai/scoring.asm` in pokecrystal) picks the
## lowest score by decrementing every slot's counter once per pass until one
## reaches zero, then walking backward to give every tied slot the same
## outcome before choosing among them at random. That is provably the same
## thing as finding the minimum and breaking ties at random directly, which is
## what [method choose_slot] does: the byte-level race is how eight-bit
## hardware computes an argmin without a MIN instruction, not a rule of its
## own to reproduce.
##
## Every percent chance below uses the cartridge's own "X percent" macro
## (`X * 255 / 100`, truncated) rather than the odd byte a handful of call
## sites add or subtract one from for a marginally different threshold; the
## difference is at most one part in 256 and not worth the loss of a single
## readable helper.
##
## What is here does not cover every trainer AI flag or every move's own
## scoring handler; see [code]HANDOFF.md[/code] for what is and is not.

## A move nobody can use, whatever the layers think of it.
const DEFAULT_SCORE: int = 20
const UNUSABLE_SCORE: int = 80

## What [code]AIDiscourageMove[/code] adds: a move that is actively a bad idea
## right now, short of being unusable outright.
const DISCOURAGE_MOVE: int = 10

## The status conditions [constant RomLayout.AI_BASIC] will not stack a second
## of onto a target that already carries one, because the cartridge's own
## status byte refuses a second status the same way [Gen2Status] does.
const STATUS_ONLY_EFFECTS: Array = [
	Gen2MoveEffect.SLEEP, Gen2MoveEffect.TOXIC, Gen2MoveEffect.POISON, Gen2MoveEffect.PARALYZE,
]

## [constant RomLayout.AI_AGGRESSIVE] does not punish a move for dealing less
## damage than the hardest hitter if losing the mon over it is the point.
## Effect bytes, not moves: Selfdestruct and Explosion share one, and so do
## every double and multi-hit move.
const RECKLESS_EFFECTS: Array = [7, 27, 29, 44] # SELFDESTRUCT, RAMPAGE, MULTI_HIT, DOUBLE_HIT

## [constant RomLayout.AI_RISKY] treats these two as a special case: a move
## that faints the user (Selfdestruct, Explosion) or skips the damage formula
## for a guaranteed kill (Horn Drill, Fissure, Guillotine, Sheer Cold) is worth
## holding back on unless already hurt.
const RISKY_EFFECTS: Array = [7, 38] # SELFDESTRUCT, OHKO

## [constant RomLayout.AI_OPPORTUNIST] discourages these particular moves, by
## number, once its own HP is low: `data/battle/ai/stall_moves.asm` in
## pokecrystal. Every one of them either does nothing to the opponent's HP or
## buys time, which is a poor trade when the trade might not come.
const STALL_MOVE_NUMBERS: Array = [
	14, 39, 43, 45, 50, 54, 68, 73, 74, 81, 96, 97, 99, 102, 103, 106, 110, 111, 112, 113, 114,
	115, 116, 117, 133, 144, 150, 151, 159, 160, 164, 172,
]

## [constant RomLayout.AI_CAUTIOUS] discourages these once it is no longer the
## first turn, because a move whose value is a residual effect (Leech Seed,
## Toxic-family status, a screen) has usually already paid for itself or not
## at all by then: `data/battle/ai/residual_moves.asm` in pokecrystal.
const RESIDUAL_MOVE_NUMBERS: Array = [54, 73, 77, 78, 86, 116, 117, 139, 144, 160, 164, 191]

## The effect bytes with a scoring handler of their own, out of
## `AI_Smart_EffectHandlers` in pokecrystal, restricted to the effects this
## engine actually implements: an effect nobody has written a battle sequence
## for yet cannot be tested against a real cartridge's choice, so it is left
## to the generic layers rather than guessed at. See "What to do next" in
## [code]HANDOFF.md[/code] for what pret's own table covers beyond this.
##
## Razor Wind, Solar Beam and Fly's own handlers are deliberately absent: all
## three read either the weather or a semi-invulnerability substatus this
## engine does not track yet, and a handler that always reads "not weather"
## or "not invulnerable" is not a simplification, it is a handler that never
## fires.


## Picks a move slot for [param attacker] to use against [param defender], the
## way [param ai_move_weights] (a trainer class's own
## [constant RomLayout.ATTR_AI_MOVE_WEIGHTS]) says to score it.
##
## [param attacker_turns_taken] and [param defender_turns_taken] are how many
## turns each side has already acted this battle, which only
## [constant RomLayout.AI_SETUP] and [constant RomLayout.AI_CAUTIOUS] read, and
## only to ask whether this is the very first one. Nothing in [Gen2Battle] counts
## these yet, so a caller with no count of its own can leave both at zero, which
## is the state that actually holds for the first turn of every battle.
##
## Returns a slot in range even when nothing is usable: [method Gen2Battle.move_for]
## already turns an unusable slot into Struggle, whichever one is named, so the
## AI does not need a case of its own for a Pokémon with nothing left to spend.
static func choose_slot(
	attacker: Gen2BattleMon,
	defender: Gen2BattleMon,
	data: GameData,
	ai_move_weights: int,
	rng: RandomNumberGenerator,
	attacker_turns_taken: int = 0,
	defender_turns_taken: int = 0
) -> int:
	var scores: Array = []
	for slot: int in Gen2BattleMon.MAX_MOVES:
		scores.append(DEFAULT_SCORE if attacker.can_use(slot) else UNUSABLE_SCORE)

	if ai_move_weights & RomLayout.AI_BASIC:
		_apply_basic(scores, attacker, defender, data, rng, attacker_turns_taken, defender_turns_taken)
	if ai_move_weights & RomLayout.AI_SETUP:
		_apply_setup(scores, attacker, defender, data, rng, attacker_turns_taken, defender_turns_taken)
	if ai_move_weights & RomLayout.AI_TYPES:
		_apply_types(scores, attacker, defender, data, rng, attacker_turns_taken, defender_turns_taken)
	if ai_move_weights & RomLayout.AI_OFFENSIVE:
		_apply_offensive(scores, attacker, defender, data, rng, attacker_turns_taken, defender_turns_taken)
	if ai_move_weights & RomLayout.AI_SMART:
		_apply_smart(scores, attacker, defender, data, rng, attacker_turns_taken, defender_turns_taken)
	if ai_move_weights & RomLayout.AI_OPPORTUNIST:
		_apply_opportunist(scores, attacker, defender, data, rng, attacker_turns_taken, defender_turns_taken)
	if ai_move_weights & RomLayout.AI_AGGRESSIVE:
		_apply_aggressive(scores, attacker, defender, data, rng, attacker_turns_taken, defender_turns_taken)
	if ai_move_weights & RomLayout.AI_CAUTIOUS:
		_apply_cautious(scores, attacker, defender, data, rng, attacker_turns_taken, defender_turns_taken)
	if ai_move_weights & RomLayout.AI_STATUS:
		_apply_status(scores, attacker, defender, data, rng, attacker_turns_taken, defender_turns_taken)
	if ai_move_weights & RomLayout.AI_RISKY:
		_apply_risky(scores, attacker, defender, data, rng, attacker_turns_taken, defender_turns_taken)

	return _pick_lowest(scores, attacker, rng)


static func _pick_lowest(scores: Array, attacker: Gen2BattleMon, rng: RandomNumberGenerator) -> int:
	var best: int = UNUSABLE_SCORE + 1
	for slot: int in scores.size():
		if attacker.can_use(slot) and int(scores[slot]) < best:
			best = int(scores[slot])

	var candidates: Array = []
	for slot: int in scores.size():
		if attacker.can_use(slot) and int(scores[slot]) == best:
			candidates.append(slot)

	if candidates.is_empty():
		return 0
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## The move a slot names, or an empty Dictionary for a slot with nothing in it.
static func _move_at(mon: Gen2BattleMon, data: GameData, slot: int) -> Dictionary:
	if slot < 0 or slot >= mon.moves.size():
		return {}
	return data.move(int(mon.moves[slot]))


static func _effect(move: Dictionary) -> int:
	return int(move.get("effect", 0))


static func _power(move: Dictionary) -> int:
	return int(move.get("power", 0))


static func _discourage(scores: Array, slot: int, by: int = DISCOURAGE_MOVE) -> void:
	scores[slot] = int(scores[slot]) + by


static func _encourage(scores: Array, slot: int, by: int = 1) -> void:
	scores[slot] = int(scores[slot]) - by


static func _above_half(mon: Gen2BattleMon) -> bool:
	return mon.hp * 2 > mon.max_hp()


static func _above_quarter(mon: Gen2BattleMon) -> bool:
	return mon.hp * 4 > mon.max_hp()


static func _at_max_hp(mon: Gen2BattleMon) -> bool:
	return mon.hp >= mon.max_hp()


## Whether [param a] is faster than [param b] with stages and status applied,
## the same stat a turn's own speed order reads.
static func _faster(a: Gen2BattleMon, b: Gen2BattleMon) -> bool:
	return a.stat("speed") > b.stat("speed")


## True with roughly [param percent] chance, the cartridge's own "X percent"
## macro: a threshold out of 255, truncated.
static func _roll(rng: RandomNumberGenerator, percent: int) -> bool:
	return rng.randi_range(0, 255) < percent * 255 / 100


## [code]AI_50_50[/code] and [code]AI_80_20[/code]: named for the "do nothing"
## half of the roll, because every call site in pret's own source is a skip.
static func _skip_50_50(rng: RandomNumberGenerator) -> bool:
	return rng.randi_range(0, 255) < 128


static func _skip_80_20(rng: RandomNumberGenerator) -> bool:
	return rng.randi_range(0, 255) < 50


## [constant RomLayout.AI_BASIC]: don't do anything redundant. A status move
## whose target already carries a status does nothing on the cartridge, and so
## do Confuse Ray or Supersonic against an already-confused target, Disable or
## Encore against an already-locked target, Attract against a target already
## in love or of the same or an unknown gender, and Mist or Focus Energy used
## a second time by the attacker itself, which is why those two read the
## attacker's own state rather than the defender's. The rest of
## `AI_Redundant`'s own table (Light Screen while it is already up, a
## Substitute already standing, and so on) reads state this engine does not
## carry yet and so never fires, which reads as "not redundant" rather than as
## a wrong answer.
static func _apply_basic(
	scores: Array, attacker: Gen2BattleMon, defender: Gen2BattleMon, data: GameData,
	_rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int
) -> void:
	for slot: int in Gen2BattleMon.MAX_MOVES:
		if not attacker.can_use(slot):
			continue
		var effect: int = _effect(_move_at(attacker, data, slot))
		var redundant: bool = false
		if effect == Gen2MoveEffect.CONFUSE:
			redundant = Gen2Substatus.has(defender.substatus, Gen2Substatus.CONFUSED)
		elif STATUS_ONLY_EFFECTS.has(effect):
			redundant = Gen2Status.is_afflicted(defender.status)
		elif effect == Gen2MoveEffect.DISABLE:
			redundant = defender.disabled_slot >= 0
		elif effect == Gen2MoveEffect.ENCORE:
			redundant = defender.encored_slot >= 0
		elif effect == Gen2MoveEffect.ATTRACT:
			var same_gender: bool = attacker.gender() == defender.gender()
			var unknown_gender: bool = attacker.gender() == Gen2BattleMon.GENDER_NONE \
				or defender.gender() == Gen2BattleMon.GENDER_NONE
			redundant = same_gender or unknown_gender \
				or Gen2Substatus.has(defender.substatus, Gen2Substatus.ATTRACTED)
		elif effect == Gen2MoveEffect.MIST:
			redundant = Gen2Substatus.has(attacker.substatus, Gen2Substatus.MIST)
		elif effect == Gen2MoveEffect.FOCUS_ENERGY:
			redundant = Gen2Substatus.has(attacker.substatus, Gen2Substatus.FOCUS_ENERGY)
		if redundant:
			_discourage(scores, slot)


## [constant RomLayout.AI_SETUP]: use a stat move on the very first turn.
## Raising a stat is encouraged only on the attacker's own first turn and
## lowering one only on the defender's; past that, both are heavily
## discouraged, because a stat move that has missed its opening is mostly
## wasted tempo.
static func _apply_setup(
	scores: Array, attacker: Gen2BattleMon, defender: Gen2BattleMon, data: GameData,
	rng: RandomNumberGenerator, atk_turns: int, def_turns: int
) -> void:
	for slot: int in Gen2BattleMon.MAX_MOVES:
		if not attacker.can_use(slot):
			continue
		var effect: int = _effect(_move_at(attacker, data, slot))
		var is_up: bool = _in_run(effect, Gen2MoveEffect.STAT_UP_BASE) \
			or _in_run(effect, Gen2MoveEffect.STAT_UP_2_BASE)
		var is_down: bool = _in_run(effect, Gen2MoveEffect.STAT_DOWN_BASE) \
			or _in_run(effect, Gen2MoveEffect.STAT_DOWN_2_BASE)

		if is_up:
			if atk_turns == 0:
				if not _skip_50_50(rng):
					_encourage(scores, slot, 2)
			elif not _roll(rng, 12):
				_discourage(scores, slot, 2)
		elif is_down:
			if def_turns == 0:
				if not _skip_50_50(rng):
					_encourage(scores, slot, 2)
			elif not _roll(rng, 12):
				_discourage(scores, slot, 2)


static func _in_run(effect: int, base: int) -> bool:
	return effect >= base and effect < base + Gen2MoveEffect.STAT_RUN_LENGTH


## [constant RomLayout.AI_TYPES]: dismiss a move the defender is immune to,
## encourage a super-effective one, and discourage a not-very-effective one
## unless it is the only type of damage on offer.
static func _apply_types(
	scores: Array, attacker: Gen2BattleMon, defender: Gen2BattleMon, data: GameData,
	_rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int
) -> void:
	for slot: int in Gen2BattleMon.MAX_MOVES:
		if not attacker.can_use(slot):
			continue
		var move: Dictionary = _move_at(attacker, data, slot)
		var move_type: int = int(move.get("type", RomLayout.TYPE_NORMAL))
		var effectiveness: int = data.type_effectiveness(move_type, defender.types())

		if effectiveness == RomLayout.MATCHUP_NO_EFFECT:
			_discourage(scores, slot)
		elif effectiveness == RomLayout.MATCHUP_EFFECTIVE:
			continue
		elif effectiveness > RomLayout.MATCHUP_EFFECTIVE:
			if _power(move) > 0:
				_encourage(scores, slot)
		else:
			# Not very effective. Discourage it only if some other move in the
			# same four deals damage of a different type: a mon that only knows
			# one type of attack should still use it.
			for other: int in Gen2BattleMon.MAX_MOVES:
				var other_move: Dictionary = _move_at(attacker, data, other)
				if other_move.is_empty():
					continue
				if int(other_move.get("type", -1)) == move_type:
					continue
				if _power(other_move) > 0:
					_discourage(scores, slot, 1)
					break


## [constant RomLayout.AI_OFFENSIVE]: heavily discourage a move with no power,
## for a class whose whole strategy is to attack.
static func _apply_offensive(
	scores: Array, attacker: Gen2BattleMon, _defender: Gen2BattleMon, data: GameData,
	_rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int
) -> void:
	for slot: int in Gen2BattleMon.MAX_MOVES:
		if not attacker.can_use(slot):
			continue
		if _power(_move_at(attacker, data, slot)) <= 0:
			_discourage(scores, slot, 2)


## [constant RomLayout.AI_SMART]: context-specific scoring, per move effect.
## See the constant above this function for which effects have a handler.
static func _apply_smart(
	scores: Array, attacker: Gen2BattleMon, defender: Gen2BattleMon, data: GameData,
	rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int
) -> void:
	for slot: int in Gen2BattleMon.MAX_MOVES:
		if not attacker.can_use(slot):
			continue
		match _effect(_move_at(attacker, data, slot)):
			Gen2MoveEffect.SLEEP:
				if not _skip_50_50(rng):
					_encourage(scores, slot, 2)
			Gen2MoveEffect.HAZE: # AI_Smart_ResetStats
				_smart_reset_stats(scores, slot, attacker, defender, rng)
			Gen2MoveEffect.TOXIC:
				if not _above_half(defender):
					_discourage(scores, slot, 1)
			Gen2MoveEffect.CONFUSE:
				_smart_confuse(scores, slot, defender, rng)
			Gen2MoveEffect.PARALYZE:
				_smart_paralyze(scores, slot, attacker, defender, rng)
			Gen2MoveEffect.RECHARGE_HIT: # Hyper Beam
				_smart_hyper_beam(scores, slot, attacker, rng)
			Gen2MoveEffect.SKULL_BASH:
				if _above_quarter(attacker):
					_discourage(scores, slot, 1)
			Gen2MoveEffect.BELLY_DRUM:
				_smart_belly_drum(scores, slot, attacker)
			Gen2MoveEffect.PSYCH_UP:
				_smart_psych_up(scores, slot, attacker, defender, rng)


static func _smart_reset_stats(
	scores: Array, slot: int, attacker: Gen2BattleMon, defender: Gen2BattleMon,
	rng: RandomNumberGenerator
) -> void:
	var encourage: bool = false
	for key: String in Gen2BattleMon.STAGED_STATS + Gen2BattleMon.STAGED_ODDS:
		if attacker.stage(key) < -2:
			encourage = true
			break
	if not encourage:
		for key: String in Gen2BattleMon.STAGED_STATS + Gen2BattleMon.STAGED_ODDS:
			if defender.stage(key) > 2:
				encourage = true
				break

	if not encourage:
		_discourage(scores, slot, 1)
		return
	if not _roll(rng, 16):
		_encourage(scores, slot, 1)


static func _smart_confuse(
	scores: Array, slot: int, defender: Gen2BattleMon, rng: RandomNumberGenerator
) -> void:
	if _above_half(defender):
		return
	if _roll(rng, 90):
		_discourage(scores, slot, 1)
	if not _above_quarter(defender):
		_discourage(scores, slot, 1)


static func _smart_paralyze(
	scores: Array, slot: int, attacker: Gen2BattleMon, defender: Gen2BattleMon,
	rng: RandomNumberGenerator
) -> void:
	if not _above_quarter(defender):
		if not _skip_50_50(rng):
			_discourage(scores, slot, 1)
		return
	if _faster(attacker, defender):
		return
	if not _above_quarter(attacker):
		return
	if not _skip_80_20(rng):
		_encourage(scores, slot, 2)


static func _smart_hyper_beam(
	scores: Array, slot: int, attacker: Gen2BattleMon, rng: RandomNumberGenerator
) -> void:
	if _above_half(attacker):
		if not _roll(rng, 16):
			return
		_discourage(scores, slot, 1)
		if _skip_50_50(rng):
			return
		_discourage(scores, slot, 1)
		return

	if _above_quarter(attacker):
		return
	if _skip_50_50(rng):
		return
	_encourage(scores, slot, 1)


static func _smart_belly_drum(scores: Array, slot: int, attacker: Gen2BattleMon) -> void:
	if attacker.stage("attack") >= 3:
		_discourage(scores, slot, 5)
		return
	if _at_max_hp(attacker):
		return
	_discourage(scores, slot, 1)
	if not _above_half(attacker):
		_discourage(scores, slot, 5)


static func _smart_psych_up(
	scores: Array, slot: int, attacker: Gen2BattleMon, defender: Gen2BattleMon,
	rng: RandomNumberGenerator
) -> void:
	var enemy_sum: int = 0
	var player_sum: int = 0
	for key: String in Gen2BattleMon.STAGED_STATS + Gen2BattleMon.STAGED_ODDS:
		enemy_sum += attacker.stage(key)
		player_sum += defender.stage(key)

	if enemy_sum >= player_sum:
		_discourage(scores, slot, 2)
		return
	if defender.stage("accuracy") < -1:
		return
	if attacker.stage("evasion") > 0:
		return
	if _skip_80_20(rng):
		return
	_encourage(scores, slot, 1)


## [constant RomLayout.AI_OPPORTUNIST]: discourage [constant STALL_MOVE_NUMBERS]
## once its own HP is low, more insistently the lower it is.
static func _apply_opportunist(
	scores: Array, attacker: Gen2BattleMon, _defender: Gen2BattleMon, data: GameData,
	rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int
) -> void:
	if _above_half(attacker):
		return
	if _above_quarter(attacker) and _skip_50_50(rng):
		return

	for slot: int in Gen2BattleMon.MAX_MOVES:
		if not attacker.can_use(slot):
			continue
		var move: Dictionary = _move_at(attacker, data, slot)
		if STALL_MOVE_NUMBERS.has(int(move.get("number", 0))):
			_discourage(scores, slot, 1)


## [constant RomLayout.AI_AGGRESSIVE]: discourage every damaging move but
## whichever deals the most, unless it would cost the mon itself
## ([constant RECKLESS_EFFECTS]) or does one point of damage that is really a
## fixed-damage move ([code]power < 2[/code]).
##
## The estimate is [constant Gen2Damage.MAX_VARIATION] and never a critical,
## the top of a hit's real range: the cartridge's own `AIDamageCalc` special-
## cases a handful of fixed-damage effects this engine does not implement yet,
## so those are estimated by the ordinary formula instead of exactly, which
## only matters for how hard they are ranked against the rest, not whether
## they are chosen as the strongest.
static func _apply_aggressive(
	scores: Array, attacker: Gen2BattleMon, defender: Gen2BattleMon, data: GameData,
	_rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int
) -> void:
	var best_slot: int = -1
	var best_damage: int = -1
	for slot: int in Gen2BattleMon.MAX_MOVES:
		if not attacker.can_use(slot):
			continue
		var move: Dictionary = _move_at(attacker, data, slot)
		if _power(move) <= 0:
			continue
		var damage: int = _estimate_damage(attacker, defender, move)
		if damage >= best_damage:
			best_damage = damage
			best_slot = slot

	if best_slot == -1 or best_damage <= 0:
		return

	for slot: int in Gen2BattleMon.MAX_MOVES:
		if slot == best_slot or not attacker.can_use(slot):
			continue
		var move: Dictionary = _move_at(attacker, data, slot)
		if _power(move) < 2:
			continue
		if RECKLESS_EFFECTS.has(_effect(move)):
			continue
		_discourage(scores, slot, 1)


static func _estimate_damage(attacker: Gen2BattleMon, defender: Gen2BattleMon, move: Dictionary) -> int:
	return int(Gen2Damage.calculate_with(
		attacker, defender, move, false, Gen2Damage.MAX_VARIATION
	)["damage"])


## [constant RomLayout.AI_CAUTIOUS]: discourage [constant RESIDUAL_MOVE_NUMBERS]
## once it is no longer the attacker's first turn.
##
## pret's own routine has a documented bug here (see
## `docs/bugs_and_glitches.md`'s "'Cautious' AI may fail to discourage
## residual moves"): a missed roll on one residual move stops it from
## checking any of the rest of that mon's moves at all, rather than moving on
## to the next slot. This implements the fix pret's own docs give rather than
## the bug, the same call [code]Gen2EffectCommands._belly_drum[/code] makes
## for Belly Drum's HP threshold; see [code]HANDOFF.md[/code] if bug-for-bug
## fidelity turns out to matter here after all.
static func _apply_cautious(
	scores: Array, attacker: Gen2BattleMon, _defender: Gen2BattleMon, data: GameData,
	rng: RandomNumberGenerator, atk_turns: int, _def_turns: int
) -> void:
	if atk_turns == 0:
		return
	for slot: int in Gen2BattleMon.MAX_MOVES:
		if not attacker.can_use(slot):
			continue
		var move: Dictionary = _move_at(attacker, data, slot)
		if RESIDUAL_MOVE_NUMBERS.has(int(move.get("number", 0))) and _roll(rng, 90):
			_discourage(scores, slot, 1)


## [constant RomLayout.AI_STATUS]: dismiss a status move the defender's typing
## already shrugs off. Toxic and Poison fold into the general type check
## rather than needing their own poison-type shortcut, because a Poison-type
## defender against a Poison-type move already reads
## [constant RomLayout.MATCHUP_NO_EFFECT] out of the real matchup chart.
static func _apply_status(
	scores: Array, attacker: Gen2BattleMon, defender: Gen2BattleMon, data: GameData,
	_rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int
) -> void:
	for slot: int in Gen2BattleMon.MAX_MOVES:
		if not attacker.can_use(slot):
			continue
		var move: Dictionary = _move_at(attacker, data, slot)
		var effect: int = _effect(move)
		if not STATUS_ONLY_EFFECTS.has(effect) and _power(move) > 0:
			continue

		var move_type: int = int(move.get("type", RomLayout.TYPE_NORMAL))
		if data.type_effectiveness(move_type, defender.types()) == RomLayout.MATCHUP_NO_EFFECT:
			_discourage(scores, slot)


## [constant RomLayout.AI_RISKY]: greatly encourage anything that would
## faint the defender outright. [constant RISKY_EFFECTS] (a move that costs
## the user its own faint, or skips the formula for a guaranteed hit) is held
## back on unless the attacker is already hurt.
static func _apply_risky(
	scores: Array, attacker: Gen2BattleMon, defender: Gen2BattleMon, data: GameData,
	rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int
) -> void:
	for slot: int in Gen2BattleMon.MAX_MOVES:
		if not attacker.can_use(slot):
			continue
		var move: Dictionary = _move_at(attacker, data, slot)
		if _power(move) <= 0:
			continue

		if RISKY_EFFECTS.has(_effect(move)):
			if _at_max_hp(attacker):
				continue
			if _roll(rng, 79):
				continue

		if _estimate_damage(attacker, defender, move) >= defender.hp:
			_encourage(scores, slot, 5)
