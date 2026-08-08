class_name Gen2BattleAI
extends RefCounted

## Scores an enemy trainer's move choice the way the cartridge's own AI does.
##
## Every slot starts at 20, or 80 with no PP. Each bit set in the trainer class's
## [constant RomLayout.ATTR_AI_MOVE_WEIGHTS] word runs one scoring layer over the
## four slots in the cartridge's bit order ([constant RomLayout.AI_BASIC] through
## [constant RomLayout.AI_RISKY]), nudging scores up (discourage) or down
## (encourage). Lowest score wins, ties broken at random.
##
## [RefCounted], scene-free, randomness injected, so a whole decision can be
## asserted on in a test.
##
## `engine/battle/ai/scoring.asm` finds that minimum by decrementing every slot's
## counter per pass until one reaches zero, then walking backward to give tied
## slots the same outcome. That is an argmin without a MIN instruction, not a
## rule of its own, so [method choose_slot] takes the minimum directly.
##
## Percent chances use the cartridge's `X * 255 / 100` macro rather than the odd
## byte a few call sites adjust by one; the difference is one part in 256.
##
## Not every AI flag or per-move handler exists yet.

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

## The weather each of the three weather moves would set, which is the whole of
## `AI_Redundant`'s `.RainDance`, `.SunnyDay` and `.Sandstorm`: a move that would
## set the weather already up is a wasted turn.
const WEATHER_FOR_EFFECT: Dictionary = {
	Gen2MoveEffect.RAIN_DANCE: Gen2Weather.RAIN,
	Gen2MoveEffect.SUNNY_DAY: Gen2Weather.SUN,
	Gen2MoveEffect.SANDSTORM: Gen2Weather.SANDSTORM,
}

## `RainDanceMoves` and `SunnyDayMoves`: what makes each of the two worth
## setting, by move number. Neither list is what a player would write, and the
## Sunny Day one is missing Solarbeam, Flame Wheel and Moonlight outright, which
## `docs/bugs_and_glitches.md` records as a bug rather than a choice.
const RAIN_DANCE_MOVE_NUMBERS: Array = [55, 56, 57, 61, 87, 127, 128, 145, 152, 190, 250]
const SUNNY_DAY_MOVE_NUMBERS: Array = [7, 52, 53, 83, 126, 221, 234, 235]

## `.SandstormImmuneTypes`, which is the same three types the damage itself
## exempts.
const SANDSTORM_IMMUNE_TYPES: Array = Gen2Weather.SANDSTORM_EXEMPT_TYPES

## [constant RomLayout.AI_CAUTIOUS] discourages these once it is no longer the
## first turn, because a move whose value is a residual effect (Leech Seed,
## Toxic-family status, a screen) has usually already paid for itself or not
## at all by then: `data/battle/ai/residual_moves.asm` in pokecrystal.
const RESIDUAL_MOVE_NUMBERS: Array = [54, 73, 77, 78, 86, 116, 117, 139, 144, 160, 164, 191]


## Picks a move slot for [param attacker] to use against [param defender], the
## way [param ai_move_weights] (a trainer class's own
## [constant RomLayout.ATTR_AI_MOVE_WEIGHTS]) says to score it.
##
## [param attacker_turns_taken] and [param defender_turns_taken] are
## `wEnemyTurnsTaken` and `wPlayerTurnsTaken`, each side's own
## [member Gen2BattleMon.turns_taken] read before the turn is spent, which is
## when the cartridge's AI reads them too. Every handler that wants them wants
## the same thing: whether this is the Pokémon's first turn out.
##
## [param weather] is [member Gen2Battle.weather].
##
## Always returns a slot in range: [method Gen2Battle.move_for] turns an
## unusable slot into Struggle, so no empty-moveset case is needed here.
static func choose_slot(
	attacker: Gen2BattleMon,
	defender: Gen2BattleMon,
	data: GameData,
	ai_move_weights: int,
	rng: RandomNumberGenerator,
	attacker_turns_taken: int = 0,
	defender_turns_taken: int = 0,
	weather: int = Gen2Weather.NONE
) -> int:
	var scores: Array = []
	for slot: int in Gen2BattleMon.MAX_MOVES:
		scores.append(DEFAULT_SCORE if attacker.can_use(slot) else UNUSABLE_SCORE)

	if ai_move_weights & RomLayout.AI_BASIC:
		_apply_basic(
			scores, attacker, defender, data, rng,
			attacker_turns_taken, defender_turns_taken, weather
		)
	if ai_move_weights & RomLayout.AI_SETUP:
		_apply_setup(
			scores, attacker, defender, data, rng,
			attacker_turns_taken, defender_turns_taken, weather
		)
	if ai_move_weights & RomLayout.AI_TYPES:
		_apply_types(
			scores, attacker, defender, data, rng,
			attacker_turns_taken, defender_turns_taken, weather
		)
	if ai_move_weights & RomLayout.AI_OFFENSIVE:
		_apply_offensive(
			scores, attacker, defender, data, rng,
			attacker_turns_taken, defender_turns_taken, weather
		)
	if ai_move_weights & RomLayout.AI_SMART:
		_apply_smart(
			scores, attacker, defender, data, rng,
			attacker_turns_taken, defender_turns_taken, weather
		)
	if ai_move_weights & RomLayout.AI_OPPORTUNIST:
		_apply_opportunist(
			scores, attacker, defender, data, rng,
			attacker_turns_taken, defender_turns_taken, weather
		)
	if ai_move_weights & RomLayout.AI_AGGRESSIVE:
		_apply_aggressive(
			scores, attacker, defender, data, rng,
			attacker_turns_taken, defender_turns_taken, weather
		)
	if ai_move_weights & RomLayout.AI_CAUTIOUS:
		_apply_cautious(
			scores, attacker, defender, data, rng,
			attacker_turns_taken, defender_turns_taken, weather
		)
	if ai_move_weights & RomLayout.AI_STATUS:
		_apply_status(
			scores, attacker, defender, data, rng,
			attacker_turns_taken, defender_turns_taken, weather
		)
	if ai_move_weights & RomLayout.AI_RISKY:
		_apply_risky(
			scores, attacker, defender, data, rng,
			attacker_turns_taken, defender_turns_taken, weather
		)

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


## [constant RomLayout.AI_BASIC]: nothing redundant. A status move against an
## already-statused target, confusion against a confused one, Disable or Encore
## against a locked one, Attract against a target already in love or of the same
## or unknown gender, and a second Mist or Focus Energy, which is why those two
## read the attacker rather than the defender. `AI_Redundant`'s remaining rows
## (Light Screen already up, a standing Substitute) read state this engine does
## not carry, so they never fire and read as "not redundant".
static func _apply_basic(
	scores: Array, attacker: Gen2BattleMon, defender: Gen2BattleMon, data: GameData,
	_rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int, weather: int
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
		elif effect == Gen2MoveEffect.MEAN_LOOK:
			# `.MeanLook` reads the user's own flag, the side the trap sits on.
			redundant = Gen2Substatus.has(attacker.substatus, Gen2Substatus.CANT_RUN)
		elif WEATHER_FOR_EFFECT.has(effect):
			redundant = weather == int(WEATHER_FOR_EFFECT[effect])
		if redundant:
			_discourage(scores, slot)


## [constant RomLayout.AI_SETUP]: use a stat move on the first turn. Raising is
## encouraged only on the attacker's first turn and lowering only on the
## defender's; past that both are heavily discouraged.
static func _apply_setup(
	scores: Array, attacker: Gen2BattleMon, defender: Gen2BattleMon, data: GameData,
	rng: RandomNumberGenerator, atk_turns: int, def_turns: int, weather: int
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
	_rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int, weather: int
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
	_rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int, weather: int
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
	rng: RandomNumberGenerator, atk_turns: int, def_turns: int, weather: int
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
			Gen2MoveEffect.SOLARBEAM:
				_smart_solarbeam(scores, slot, weather, rng)
			Gen2MoveEffect.THUNDER:
				_smart_thunder(scores, slot, weather, rng)
			Gen2MoveEffect.SANDSTORM:
				_smart_sandstorm(scores, slot, defender, rng)
			Gen2MoveEffect.RAIN_DANCE:
				_smart_weather_move(
					scores, slot, attacker, defender, rng, atk_turns, def_turns,
					RomLayout.TYPE_WATER, RomLayout.TYPE_FIRE, RAIN_DANCE_MOVE_NUMBERS
				)
			Gen2MoveEffect.SUNNY_DAY:
				_smart_weather_move(
					scores, slot, attacker, defender, rng, atk_turns, def_turns,
					RomLayout.TYPE_FIRE, RomLayout.TYPE_WATER, SUNNY_DAY_MOVE_NUMBERS
				)
			Gen2MoveEffect.TRAP_TARGET:
				_smart_trap_target(scores, slot, attacker, defender, def_turns, rng)
			Gen2MoveEffect.HEAL, Gen2MoveEffect.MORNING_SUN, Gen2MoveEffect.SYNTHESIS, \
			Gen2MoveEffect.MOONLIGHT:
				_smart_heal(scores, slot, attacker, rng)


## `AI_Smart_Solarbeam`: 80% to encourage it greatly in sun, where it needs no
## charge turn, and 90% to discourage it greatly in rain, where it also loses
## half its damage.
static func _smart_solarbeam(
	scores: Array, slot: int, weather: int, rng: RandomNumberGenerator
) -> void:
	if weather == Gen2Weather.SUN:
		if not _skip_80_20(rng):
			_encourage(scores, slot, 2)
		return
	if weather == Gen2Weather.RAIN and not _roll(rng, 10):
		_discourage(scores, slot, 2)


## `AI_Smart_Thunder`: 90% to discourage it in sun, where its accuracy halves.
## Rain is not mentioned, because the accuracy step and `CheckHit` have already
## made it certain.
static func _smart_thunder(
	scores: Array, slot: int, weather: int, rng: RandomNumberGenerator
) -> void:
	if weather == Gen2Weather.SUN and not _roll(rng, 10):
		_discourage(scores, slot, 1)


## `AI_Smart_Sandstorm`: worthless against a target the sand cannot touch, poor
## against one already low, and a 50% encouragement otherwise.
static func _smart_sandstorm(
	scores: Array, slot: int, defender: Gen2BattleMon, rng: RandomNumberGenerator
) -> void:
	for defending_type: int in defender.types():
		if SANDSTORM_IMMUNE_TYPES.has(int(defending_type)):
			_discourage(scores, slot, 2)
			return

	if not _above_half(defender):
		_discourage(scores, slot, 1)
		return
	if not _skip_50_50(rng):
		_encourage(scores, slot, 1)


## `AI_Smart_RainDance` and `AI_Smart_SunnyDay`, which are one routine with two
## type pairs: the weather is a bad idea if it would suit the target and a good
## one if it would hurt it, and otherwise worth setting only with a move that
## wants it.
##
## [param favours_target] is the type the weather helps and
## [param disfavours_target] the one it hurts, in the order the cartridge tests
## them: the target's first type answers before its second, so a Water/Fire
## target under Rain Dance is a Water target.
static func _smart_weather_move(
	scores: Array, slot: int, attacker: Gen2BattleMon, defender: Gen2BattleMon,
	rng: RandomNumberGenerator, atk_turns: int, def_turns: int,
	favours_target: int, disfavours_target: int, wanted_moves: Array
) -> void:
	for defending_type: int in defender.types():
		if int(defending_type) == favours_target:
			_discourage(scores, slot, 3)
			return
		if int(defending_type) == disfavours_target:
			_good_weather_type(scores, slot, defender, atk_turns, def_turns)
			return

	# `AIHasMoveInArray` walks the four slots by move number alone: no PP check
	# and no usability check, so a wanted move with nothing left in it still
	# counts as a reason to set the weather.
	var has_wanted: bool = false
	for known: Variant in attacker.moves:
		if wanted_moves.has(int(known)):
			has_wanted = true
			break

	if not has_wanted or not _above_half(defender):
		_discourage(scores, slot, 3)
		return
	if not _skip_50_50(rng):
		_encourage(scores, slot, 1)


## `AIGoodWeatherType`: worth two only while the target is still healthy and one
## of the two Pokémon has just come out.
static func _good_weather_type(
	scores: Array, slot: int, defender: Gen2BattleMon, atk_turns: int, def_turns: int
) -> void:
	if not _above_half(defender):
		return
	if def_turns == 0 or atk_turns == 0:
		_encourage(scores, slot, 2)


## `AI_Smart_TrapTarget`: pointless against a target already bound, and worth two
## against one that is losing health anyway or has only just come out, provided
## the user has enough left to hold it there.
##
## Two of the five states the cartridge encourages on are missing, because
## neither exists here yet: `SUBSTATUS_IDENTIFIED` (Foresight) and
## `SUBSTATUS_NIGHTMARE`. The other three are Toxic, Attract and Rollout.
static func _smart_trap_target(
	scores: Array, slot: int, attacker: Gen2BattleMon, defender: Gen2BattleMon,
	def_turns: int, rng: RandomNumberGenerator
) -> void:
	var worth_it: bool = defender.trapped_turns <= 0 and (
		defender.toxic_counter > 0
		or Gen2Substatus.has(
			defender.substatus, Gen2Substatus.ATTRACTED | Gen2Substatus.ROLLOUT
		)
		or def_turns == 0
	)

	if not worth_it:
		if not _skip_50_50(rng):
			_discourage(scores, slot, 1)
		return

	if not _above_quarter(attacker):
		return
	if not _skip_50_50(rng):
		_encourage(scores, slot, 2)


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


## `AI_Smart_Heal`, which `AI_Smart_MorningSun`, `AI_Smart_Synthesis` and
## `AI_Smart_Moonlight` are all labels on: 90% to encourage it greatly below a
## quarter health, discourage it above half, and nothing in between. The AI reads
## its own health here, never the player's.
static func _smart_heal(
	scores: Array, slot: int, attacker: Gen2BattleMon, rng: RandomNumberGenerator
) -> void:
	if not _above_quarter(attacker):
		if not _roll(rng, 10):
			_encourage(scores, slot, 2)
		return
	if _above_half(attacker):
		_discourage(scores, slot, 1)


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
	rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int, weather: int
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
## The estimate is [constant Gen2Damage.MAX_VARIATION] with no critical, the top
## of a hit's real range. `AIDamageCalc` special-cases fixed-damage effects this
## engine does not implement, so those use the ordinary formula: that shifts how
## hard they rank, not which move is strongest.
static func _apply_aggressive(
	scores: Array, attacker: Gen2BattleMon, defender: Gen2BattleMon, data: GameData,
	_rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int, weather: int
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
## Diverges from a documented source bug (`docs/bugs_and_glitches.md`,
## "'Cautious' AI may fail to discourage residual moves"): a missed roll there
## abandons the remaining slots instead of moving on. This implements pret's own
## fix, the same call [code]Gen2EffectCommands._belly_drum[/code] makes.
static func _apply_cautious(
	scores: Array, attacker: Gen2BattleMon, _defender: Gen2BattleMon, data: GameData,
	rng: RandomNumberGenerator, atk_turns: int, _def_turns: int, weather: int
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
## shrugs off. Toxic and Poison need no poison-type shortcut, since a Poison-type
## defender against a Poison-type move already reads
## [constant RomLayout.MATCHUP_NO_EFFECT] out of the real chart.
static func _apply_status(
	scores: Array, attacker: Gen2BattleMon, defender: Gen2BattleMon, data: GameData,
	_rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int, weather: int
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
	rng: RandomNumberGenerator, _atk_turns: int, _def_turns: int, weather: int
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
