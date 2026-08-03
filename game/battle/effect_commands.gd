class_name Gen2EffectCommands
extends RefCounted

## The steps a move is made of.
##
## A move in these games is not a special case in a switch statement, it is a
## short program: the cartridge keeps a list of commands per effect and runs them
## in order, and an ordinary attack is the list that announces the move, spends
## the PP, works the damage out, rolls the hit, applies it and checks for a
## faint. Every other move is that list with steps added, removed or replaced.
##
## Reproducing the shape rather than the outcome is what makes the rest of
## Generation 2 additive. A burn is a command appended to a list; a move that
## cannot miss is a list with the roll left out; a two-turn move is a list that
## ends early the first time. None of that reaches [Gen2Battle], which knows only
## how to run a list.
##
## The names are the cartridge's own, so a sequence here can be read against
## [code]data/moves/effects.asm[/code] in the pret disassembly line for line. See
## [Gen2MoveEffect] for the lists themselves.

## Announces the move. First, because a move that fails still says it was used.
const USED_MOVE_TEXT: StringName = &"usedmovetext"

## Spends the PP.
const DO_TURN: StringName = &"doturn"

## Works out what the move would do: the critical, the type matchup, the STAB and
## the random spread. Nothing is applied here, and nothing has been rolled for
## whether it connects.
const DAMAGE_CALC: StringName = &"damagecalc"

## Ends the move if the defender cannot be touched by it at all. Separate from
## the roll, because an immunity is not a miss and does not read as one.
const CHECK_IMMUNE: StringName = &"checkimmune"

## Rolls whether the move connects, and ends it if it does not.
const CHECK_HIT: StringName = &"checkhit"

## Takes the damage off, and reports what was actually taken.
const APPLY_DAMAGE: StringName = &"applydamage"

## Takes a quarter of what was dealt off the attacker.
const RECOIL: StringName = &"recoil"

## Reports whoever is down. Both can be, since recoil can take the attacker with
## the defender.
const CHECK_FAINT: StringName = &"checkfaint"

## The end of the list. It does nothing except be the end, which is worth having
## as a step so a sequence reads the way the cartridge's does.
const END_MOVE: StringName = &"endmove"

## Whether the move happens at all. Sleep, freeze and paralysis are checked here,
## in that order, and any of them can cost the turn.
##
## Not part of any sequence: the cartridge runs this before it looks the effect
## up, so every move goes through it and no list has to remember to. [Gen2Battle]
## runs it ahead of the list for that reason.
const CHECK_STATUS: StringName = &"checkstatus"

## Whether a secondary effect happens, out of the move's own chance. A move whose
## sequence has this in it does its damage either way; what is behind it is what
## the roll decides.
const EFFECT_CHANCE: StringName = &"effectchance"

## The five things a move can leave on a Pokémon. Each refuses a target that
## already has something, which is the rule the status byte encodes: one at a
## time, and a second is a failure rather than an addition.
const SLEEP_TARGET: StringName = &"sleeptarget"
const POISON_TARGET: StringName = &"poisontarget"
const BURN_TARGET: StringName = &"burntarget"
const FREEZE_TARGET: StringName = &"freezetarget"
const PARALYZE_TARGET: StringName = &"paralyzetarget"

## What Toxic leaves behind: the same poison flag [constant POISON_TARGET]
## leaves, plus the ramping counter that makes it Toxic rather than an ordinary
## poison. Its own command rather than [constant POISON_TARGET] with an extra
## step after it, because the counter has to start before the first residual
## turn sees it, and nothing else needs a command that touches both.
const TOXIC_TARGET: StringName = &"toxictarget"

## The two things a move can leave on [Gen2Substatus] rather than the status
## byte. Flinch is only ever a secondary effect, so it obeys
## [member Gen2Turn.failed_chance] the same way the five above do; confusion
## comes both ways, as a status move of its own (Confuse Ray, Supersonic) and
## as a secondary effect (Confusion, Psybeam), which is why [Gen2MoveEffect]
## reaches for this command from both shapes of sequence.
const FLINCH_TARGET: StringName = &"flinchtarget"
const CONFUSE_TARGET: StringName = &"confusetarget"

## Heals the attacker for half of what the hit calculated, the same command for
## Absorb-family drain and, gated by [constant Gen2MoveEffect.DREAM_EATER]'s own
## rule inside [constant CHECK_HIT], for Dream Eater.
const DRAIN_TARGET: StringName = &"draintarget"

## Two to five hits for [constant Gen2MoveEffect.MULTI_HIT], or exactly two for
## [constant Gen2MoveEffect.DOUBLE_HIT] and [constant Gen2MoveEffect.TWINEEDLE]:
## one command that repeats the roll and the hit itself rather than a sequence
## repeated by the runner, the same way [constant ALL_STATS_UP] repeats a stage
## change five times without five commands.
const MULTI_HIT: StringName = &"multihit"

## Overwrites what [constant DAMAGE_CALC] worked out with the number
## [constant Gen2MoveEffect.SUPER_FANG], [constant Gen2MoveEffect.STATIC_DAMAGE],
## [constant Gen2MoveEffect.LEVEL_DAMAGE] and [constant Gen2MoveEffect.PSYWAVE]
## actually deal. [constant DAMAGE_CALC]'s own roll still ran first, and its
## immunity answer is the one thing about it this keeps.
const FIXED_DAMAGE: StringName = &"fixeddamage"

## Guillotine, Horn Drill and Fissure's own accuracy rule and their own damage:
## nothing here is [constant CHECK_HIT] or [constant APPLY_DAMAGE].
const OHKO: StringName = &"ohko"

## Recharge: locks the user out of its next turn, the tail of Hyper Beam's own
## list rather than anything a target-facing command touches.
const RECHARGE: StringName = &"recharge"

## A two-turn move's charge. The first time it is run it locks the user in,
## announces the charge and ends the move there; the second time, it is the
## release turn, so it clears the lock and lets the rest of the list run as an
## ordinary attack. [Gen2Battle._act] is what makes sure the second call is the
## user's only option: see [method Gen2Battle.move_for].
const CHARGE_MOVE: StringName = &"chargemove"

## Clears every stage on both sides. Only the stages: nothing here touches
## either Pokémon's status byte or [Gen2Substatus].
const HAZE: StringName = &"haze"

## Costs half the user's maximum HP to raise its own Attack straight to the top
## of its range. Fails without costing anything if the user does not have more
## than half its health, or if Attack is already there.
const BELLY_DRUM: StringName = &"bellydrum"

## Copies the target's stages onto the user, all seven at once. Fails if the
## target has nothing raised or lowered to copy.
const PSYCH_UP: StringName = &"psychup"

## Raises and lowers a stat by one stage or two, named the way the cartridge
## names them and in the order [constant Gen2BattleMon.STAGED_STATS] plus
## [constant Gen2BattleMon.STAGED_ODDS] already keeps the seven in, because that
## is also the order the cartridge's own effect bytes run in: seven in a row for
## "up by one", seven more for "down by one", and so on. [Gen2MoveEffect] is what
## turns that run into a table; this only names the seven stops along it.
const ATTACK_UP: StringName = &"attackup"
const DEFENSE_UP: StringName = &"defenseup"
const SPEED_UP: StringName = &"speedup"
const SP_ATTACK_UP: StringName = &"specialattackup"
const SP_DEFENSE_UP: StringName = &"specialdefenseup"
const ACCURACY_UP: StringName = &"accuracyup"
const EVASION_UP: StringName = &"evasionup"

const ATTACK_UP_2: StringName = &"attackup2"
const DEFENSE_UP_2: StringName = &"defenseup2"
const SPEED_UP_2: StringName = &"speedup2"
const SP_ATTACK_UP_2: StringName = &"specialattackup2"
const SP_DEFENSE_UP_2: StringName = &"specialdefenseup2"
const ACCURACY_UP_2: StringName = &"accuracyup2"
const EVASION_UP_2: StringName = &"evasionup2"

const ATTACK_DOWN: StringName = &"attackdown"
const DEFENSE_DOWN: StringName = &"defensedown"
const SPEED_DOWN: StringName = &"speeddown"
const SP_ATTACK_DOWN: StringName = &"specialattackdown"
const SP_DEFENSE_DOWN: StringName = &"specialdefensedown"
const ACCURACY_DOWN: StringName = &"accuracydown"
const EVASION_DOWN: StringName = &"evasiondown"

const ATTACK_DOWN_2: StringName = &"attackdown2"
const DEFENSE_DOWN_2: StringName = &"defensedown2"
const SPEED_DOWN_2: StringName = &"speeddown2"
const SP_ATTACK_DOWN_2: StringName = &"specialattackdown2"
const SP_DEFENSE_DOWN_2: StringName = &"specialdefensedown2"
const ACCURACY_DOWN_2: StringName = &"accuracydown2"
const EVASION_DOWN_2: StringName = &"evasiondown2"

## Raises the user's five real stats at once, which is what Ancientpower leaves
## behind on a roll. Accuracy and evasion are not among them: the cartridge's own
## command is a loop over the five stats a stage multiplies a real number for,
## and the two odds are not that.
const ALL_STATS_UP: StringName = &"allstatsup"

## The stat commands in the run order the cartridge's effect bytes use, indexed
## by [Gen2MoveEffect] rather than named one at a time there. Each entry is
## [param stat_key, param amount, param targets_user]: the key
## [method Gen2BattleMon.change_stage] takes, how many stages it moves by, and
## whether the move points it at whoever used it rather than the other side.
const STAT_COMMANDS: Dictionary = {
	ATTACK_UP: ["attack", 1, true], DEFENSE_UP: ["defense", 1, true],
	SPEED_UP: ["speed", 1, true], SP_ATTACK_UP: ["sp_attack", 1, true],
	SP_DEFENSE_UP: ["sp_defense", 1, true], ACCURACY_UP: ["accuracy", 1, true],
	EVASION_UP: ["evasion", 1, true],

	ATTACK_UP_2: ["attack", 2, true], DEFENSE_UP_2: ["defense", 2, true],
	SPEED_UP_2: ["speed", 2, true], SP_ATTACK_UP_2: ["sp_attack", 2, true],
	SP_DEFENSE_UP_2: ["sp_defense", 2, true], ACCURACY_UP_2: ["accuracy", 2, true],
	EVASION_UP_2: ["evasion", 2, true],

	ATTACK_DOWN: ["attack", -1, false], DEFENSE_DOWN: ["defense", -1, false],
	SPEED_DOWN: ["speed", -1, false], SP_ATTACK_DOWN: ["sp_attack", -1, false],
	SP_DEFENSE_DOWN: ["sp_defense", -1, false], ACCURACY_DOWN: ["accuracy", -1, false],
	EVASION_DOWN: ["evasion", -1, false],

	ATTACK_DOWN_2: ["attack", -2, false], DEFENSE_DOWN_2: ["defense", -2, false],
	SPEED_DOWN_2: ["speed", -2, false], SP_ATTACK_DOWN_2: ["sp_attack", -2, false],
	SP_DEFENSE_DOWN_2: ["sp_defense", -2, false], ACCURACY_DOWN_2: ["accuracy", -2, false],
	EVASION_DOWN_2: ["evasion", -2, false],
}

## The five real stats [constant ALL_STATS_UP] raises, in the cartridge's order.
const ALL_STATS_KEYS: Array = ["attack", "defense", "speed", "sp_attack", "sp_defense"]

## Reports a stat change, or says nothing for one that is folded into a hit and
## has no message step of its own. Separate from the change itself because a
## status move that fails to move a stat says so and a secondary effect that
## fails to says nothing, which is two different steps rather than one asking
## both questions.
const STAT_UP_MESSAGE: StringName = &"statupmessage"
const STAT_DOWN_MESSAGE: StringName = &"statdownmessage"

## Reports that a stat could not go any higher or lower. Only on a status move's
## own sequence: a secondary effect's sequence has no step here at all, so its
## failure is silent, the way a failed [constant EFFECT_CHANCE] already is.
const STAT_UP_FAIL_TEXT: StringName = &"statupfailtext"
const STAT_DOWN_FAIL_TEXT: StringName = &"statdownfailtext"

## Recoil is a quarter of the damage dealt, never less than one, and it is the
## same quarter for every move that has it rather than a figure per move.
const RECOIL_DIVISOR: int = 4

## The two moves a frozen Pokémon can use, which thaw it in the using. Flame
## Wheel and Sacred Fire, by move number.
const THAWING_MOVES: Array = [172, 221]


## Runs one command against [param turn].
##
## An unknown command is an error rather than a no-op: a sequence that names a
## step nobody wrote would otherwise play out as a move that quietly does less
## than it says.
static func run(command: StringName, turn: Gen2Turn) -> void:
	match command:
		USED_MOVE_TEXT:
			_used_move_text(turn)
		DO_TURN:
			_do_turn(turn)
		DAMAGE_CALC:
			_damage_calc(turn)
		CHECK_IMMUNE:
			_check_immune(turn)
		CHECK_HIT:
			_check_hit(turn)
		APPLY_DAMAGE:
			_apply_damage(turn)
		RECOIL:
			_recoil(turn)
		CHECK_FAINT:
			_check_faint(turn)
		END_MOVE:
			turn.end()
		CHECK_STATUS:
			_check_status(turn)
		EFFECT_CHANCE:
			_effect_chance(turn)
		SLEEP_TARGET:
			_status_target(turn, Gen2Status.SLEEP_MASK)
		POISON_TARGET:
			_status_target(turn, Gen2Status.POISON)
		BURN_TARGET:
			_status_target(turn, Gen2Status.BURN)
		FREEZE_TARGET:
			_status_target(turn, Gen2Status.FREEZE)
		PARALYZE_TARGET:
			_status_target(turn, Gen2Status.PARALYSIS)
		TOXIC_TARGET:
			_toxic_target(turn)
		FLINCH_TARGET:
			_flinch_target(turn)
		CONFUSE_TARGET:
			_confuse_target(turn)
		DRAIN_TARGET:
			_drain_target(turn)
		MULTI_HIT:
			_multi_hit(turn)
		FIXED_DAMAGE:
			_fixed_damage(turn)
		OHKO:
			_ohko(turn)
		RECHARGE:
			_recharge(turn)
		CHARGE_MOVE:
			_charge_move(turn)
		HAZE:
			_haze(turn)
		BELLY_DRUM:
			_belly_drum(turn)
		PSYCH_UP:
			_psych_up(turn)
		ALL_STATS_UP:
			_all_stats_up(turn)
		STAT_UP_MESSAGE, STAT_DOWN_MESSAGE:
			_stat_message(turn)
		STAT_UP_FAIL_TEXT, STAT_DOWN_FAIL_TEXT:
			_stat_fail_text(turn)
		_:
			if STAT_COMMANDS.has(command):
				_stat_change(command, turn)
			else:
				push_error("No such effect command: %s" % command)


static func _used_move_text(turn: Gen2Turn) -> void:
	turn.emit(Gen2Battle.USED_MOVE, {"move": turn.move_number})


## Struggle is what a Pokémon does when there is nothing left to spend, so it
## spends nothing, and it is the one move that arrives without a slot. Neither
## does the release turn of a two-turn move: the PP for it went on the charge
## turn, which is what [member Gen2Turn.locked] means here.
static func _do_turn(turn: Gen2Turn) -> void:
	if turn.locked:
		return
	if turn.slot >= 0 and turn.move_number != Gen2Damage.STRUGGLE:
		turn.attacker().spend_pp(turn.slot)


static func _damage_calc(turn: Gen2Turn) -> void:
	var result: Dictionary = Gen2Damage.calculate(
		turn.attacker(), turn.defender(), turn.move, turn.rng()
	)
	turn.damage = int(result["damage"])
	turn.critical = bool(result["critical"])
	turn.effectiveness = int(result["effectiveness"])
	turn.immune = bool(result["immune"])


static func _check_immune(turn: Gen2Turn) -> void:
	if not turn.immune:
		return
	turn.emit(Gen2Battle.NO_EFFECT, {"target": turn.target})
	turn.end()


## Dream Eater's own rule ("a Pokémon that isn't asleep cannot be eaten from")
## is not a step of its own: the real cartridge folds it into this same shared
## check, reading as a miss on a target that is not asleep rather than as a
## distinct failure.
static func _check_hit(turn: Gen2Turn) -> void:
	if turn.effect() == Gen2MoveEffect.DREAM_EATER \
		and not Gen2Status.is_asleep(turn.defender().status):
		turn.emit(Gen2Battle.MISSED, {"target": turn.target})
		turn.end()
		return

	var chance: int = Gen2Accuracy.chance(
		int(turn.move.get("accuracy", Gen2Accuracy.ALWAYS_HITS)),
		turn.attacker().stage("accuracy"), turn.defender().stage("evasion")
	)
	if Gen2Accuracy.rolls_hit(turn.rng(), chance):
		return
	turn.emit(Gen2Battle.MISSED, {"target": turn.target})
	turn.end()


static func _apply_damage(turn: Gen2Turn) -> void:
	var defender: Gen2BattleMon = turn.defender()
	turn.dealt = defender.take_damage(turn.damage)
	turn.emit(Gen2Battle.HIT, {
		"target": turn.target,
		"amount": turn.dealt,
		"critical": turn.critical,
		"effectiveness": turn.effectiveness,
		"hp": defender.hp,
		"max_hp": defender.max_hp(),
	})


static func _recoil(turn: Gen2Turn) -> void:
	if turn.dealt <= 0:
		return

	var attacker: Gen2BattleMon = turn.attacker()
	@warning_ignore("integer_division")
	var taken: int = attacker.take_damage(maxi(turn.dealt / RECOIL_DIVISOR, 1))
	turn.emit(Gen2Battle.RECOIL, {
		"amount": taken, "hp": attacker.hp, "max_hp": attacker.max_hp(),
	})


## The defender first, then the attacker, which is the order they can go down in.
static func _check_faint(turn: Gen2Turn) -> void:
	for side: int in [turn.target, turn.side]:
		if turn.battle.mon(side).is_fainted():
			turn.events.append({"type": Gen2Battle.FAINTED, "side": side})


## Recharge, then sleep, then freeze, then flinch, then confusion, then
## paralysis, which is the cartridge's own order in [code]CheckPlayerTurn[/code].
## Disable and Attract sit between flinch and confusion on the cartridge and are
## not written yet; nothing here skips a slot for them because neither writes
## [Gen2Substatus] yet either.
##
## A frozen Pokémon is never asked whether it is also paralysed, because the
## status byte cannot say both; a confused Pokémon that hits itself is never
## asked about paralysis either, because it has already spent its turn.
##
## Waking up does not cost the turn. The cartridge counts the sleep off, prints
## that the Pokémon woke, and carries on into the rest of its checks rather than
## ending the turn, so a Pokémon whose counter runs out attacks the same turn it
## opens its eyes. That is Generation 2's rule and not Generation 1's. Snapping
## out of confusion works the same way: the counter reaching zero clears the
## flag and lets the move through the same turn.
static func _check_status(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()

	if Gen2Substatus.has(mon.substatus, Gen2Substatus.RECHARGING):
		mon.substatus &= ~Gen2Substatus.RECHARGING
		turn.emit(Gen2Battle.CANNOT_MOVE, {"reason": &"recharge"})
		turn.end()
		return

	if Gen2Status.is_asleep(mon.status):
		mon.status = Gen2Status.tick_sleep(mon.status)
		if Gen2Status.is_asleep(mon.status):
			turn.emit(Gen2Battle.CANNOT_MOVE, {"reason": &"sleep"})
			turn.end()
			return
		turn.emit(Gen2Battle.WOKE_UP)

	if Gen2Status.has(mon.status, Gen2Status.FREEZE):
		# Flame Wheel and Sacred Fire are used through a freeze, and thaw the
		# Pokémon using them; nothing else in the game does.
		if not THAWING_MOVES.has(turn.move_number):
			turn.emit(Gen2Battle.CANNOT_MOVE, {"reason": &"freeze"})
			turn.end()
			return
		mon.status &= ~Gen2Status.FREEZE
		turn.emit(Gen2Battle.THAWED)

	if Gen2Substatus.has(mon.substatus, Gen2Substatus.FLINCHED):
		mon.substatus &= ~Gen2Substatus.FLINCHED
		turn.emit(Gen2Battle.CANNOT_MOVE, {"reason": &"flinch"})
		turn.end()
		return

	if Gen2Substatus.has(mon.substatus, Gen2Substatus.CONFUSED):
		mon.confusion_turns -= 1
		if mon.confusion_turns <= 0:
			mon.substatus &= ~Gen2Substatus.CONFUSED
			turn.emit(Gen2Battle.SNAPPED_OUT)
		else:
			turn.emit(Gen2Battle.CONFUSED)
			if Gen2Substatus.rolls_confusion_hit(turn.rng()):
				var dealt: int = mon.take_damage(Gen2Damage.confusion_damage(mon, turn.rng()))
				turn.emit(Gen2Battle.HURT_ITSELF, {
					"amount": dealt, "hp": mon.hp, "max_hp": mon.max_hp(),
				})
				turn.end()
				return

	if Gen2Status.has(mon.status, Gen2Status.PARALYSIS) \
		and Gen2Status.rolls_full_paralysis(turn.rng()):
		turn.emit(Gen2Battle.CANNOT_MOVE, {"reason": &"paralysis"})
		turn.end()


## A secondary effect's roll. The chance is a byte out of 256 in the move's own
## table, like accuracy, and what it gates is only what comes after it: the
## damage in front of it has already been done.
##
## A chance of zero never comes up, which is what the cartridge's comparison
## does with it too. That is worth leaving alone rather than reading as "no
## chance was given, so always": a move that says zero is a move that says never.
static func _effect_chance(turn: Gen2Turn) -> void:
	var chance: int = int(turn.move.get("effect_chance", 0))
	if turn.rng().randi_range(0, Gen2Status.CHANCE_RANGE - 1) >= chance:
		turn.failed_chance = true


## Puts a status on the defender, or fails.
##
## One status at a time: a Pokémon that already has something on its byte is
## refused rather than added to, and so is one whose type makes it immune. A
## sleep is rolled for how long it lasts; the rest are a flag.
static func _status_target(turn: Gen2Turn, flag: int) -> void:
	if turn.failed_chance:
		return

	var defender: Gen2BattleMon = turn.defender()
	if defender.is_fainted() or Gen2Status.is_afflicted(defender.status):
		return

	if flag == Gen2Status.SLEEP_MASK:
		defender.status = Gen2Status.roll_sleep(turn.rng())
	else:
		defender.status |= flag

	turn.emit(Gen2Battle.STATUS_INFLICTED, {
		"target": turn.target,
		"status": defender.status,
		"name": Gen2Status.name_of(defender.status),
	})


## Poisons the target the way [constant POISON_TARGET] does, and starts the
## counter that makes it Toxic rather than an ordinary poison: see
## [method Gen2Status.toxic_damage], which reads it back at the end of every
## turn from here on.
static func _toxic_target(turn: Gen2Turn) -> void:
	if turn.failed_chance:
		return

	var defender: Gen2BattleMon = turn.defender()
	if defender.is_fainted() or Gen2Status.is_afflicted(defender.status):
		return

	defender.status |= Gen2Status.POISON
	defender.toxic_counter = 1
	turn.emit(Gen2Battle.STATUS_INFLICTED, {
		"target": turn.target, "status": defender.status, "name": &"toxic",
	})


## Sets the target flinching, for [constant CHECK_STATUS] to catch on its turn.
## Only ever a secondary effect, so it obeys [member Gen2Turn.failed_chance] the
## same way a status target does; a fainted target cannot be made to flinch on
## a turn it will not take.
static func _flinch_target(turn: Gen2Turn) -> void:
	if turn.failed_chance:
		return

	var defender: Gen2BattleMon = turn.defender()
	if defender.is_fainted():
		return

	defender.substatus |= Gen2Substatus.FLINCHED


## Sets the target confused and rolls how long for, or fails. A Pokémon already
## confused is refused rather than having its counter restarted, which is the
## rule [Gen2Substatus.CONFUSED] enforces the same way the status byte enforces
## it for sleep, poison, burn, freeze and paralysis, except that confusion sits
## alongside a status rather than instead of one: a poisoned Pokémon can still
## be confused.
static func _confuse_target(turn: Gen2Turn) -> void:
	if turn.failed_chance:
		return

	var defender: Gen2BattleMon = turn.defender()
	if defender.is_fainted() or Gen2Substatus.has(defender.substatus, Gen2Substatus.CONFUSED):
		return

	defender.substatus |= Gen2Substatus.CONFUSED
	defender.confusion_turns = Gen2Substatus.roll_confusion(turn.rng())

	# Not [constant Gen2Battle.STATUS_INFLICTED]: that event's [code]status[/code]
	# field is the status byte, and confusion never touches it.
	turn.emit(Gen2Battle.CONFUSE_INFLICTED, {"target": turn.target})


## Heals the attacker for half of what the hit calculated, at least one.
##
## Half of [member Gen2Turn.damage], the number the formula worked out, not
## half of [member Gen2Turn.dealt], the number that actually came off a target
## who had less than that left. The real cartridge's own drain reads the same
## uncapped figure [constant APPLY_DAMAGE] read before clamping it to what the
## defender had, so a move that calculates fifty against a target with three
## hit points left heals twenty-five, not one.
static func _drain_target(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	@warning_ignore("integer_division")
	var healed: int = attacker.heal(maxi(turn.damage / 2, 1))
	turn.emit(Gen2Battle.DRAINED, {
		# "from" rather than "target": the healing lands on the attacker, whose
		# hp and max_hp these are, but the message names who it was sucked from.
		"from": turn.target, "amount": healed, "hp": attacker.hp, "max_hp": attacker.max_hp(),
	})


## Two to five hits for [constant Gen2MoveEffect.MULTI_HIT], or exactly two for
## [constant Gen2MoveEffect.DOUBLE_HIT] and [constant Gen2MoveEffect.TWINEEDLE].
##
## [constant CHECK_HIT] has already rolled the one accuracy check the whole
## move gets, the way the cartridge's own script checks it before the loop
## that repeats the hit even starts; everything from here on is this command's
## own job. The first hit reuses what [constant DAMAGE_CALC] already worked
## out; every hit after it rerolls the critical and the spread fresh, the way
## the cartridge's own loop does by jumping back to reroll rather than reusing
## the first hit's numbers. A faint ends the move where it stands, which is
## also why the "hit N times" summary is only sent when every planned hit
## actually landed: the cartridge's own loop jumps straight past that line the
## moment a hit brings the target down.
static func _multi_hit(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	var defender: Gen2BattleMon = turn.defender()
	var hits: int = 2 if FIXED_TWO_HIT_EFFECTS.has(turn.effect()) else _roll_multi_hit_count(turn.rng())

	for hit: int in hits:
		if hit > 0:
			var result: Dictionary = Gen2Damage.calculate(attacker, defender, turn.move, turn.rng())
			turn.damage = int(result["damage"])
			turn.critical = bool(result["critical"])
			turn.effectiveness = int(result["effectiveness"])

		turn.dealt = defender.take_damage(turn.damage)
		turn.emit(Gen2Battle.HIT, {
			"target": turn.target, "amount": turn.dealt, "critical": turn.critical,
			"effectiveness": turn.effectiveness, "hp": defender.hp, "max_hp": defender.max_hp(),
		})

		if defender.is_fainted():
			_check_faint(turn)
			turn.end()
			return

	turn.emit(Gen2Battle.HIT_TIMES, {"target": turn.target, "times": hits})


const FIXED_TWO_HIT_EFFECTS: Array = [Gen2MoveEffect.DOUBLE_HIT, Gen2MoveEffect.TWINEEDLE]


## How many times a generic multi-hit move connects, following the cartridge's
## own two-roll algorithm: a first roll out of four keeps 0 or 1 outright, or
## triggers a second roll out of four for 2 or 3, so 2 and 3 hits come up three
## times as often as 4 and 5 do (37.5%, 37.5%, 12.5%, 12.5%).
static func _roll_multi_hit_count(rng: RandomNumberGenerator) -> int:
	var first: int = rng.randi_range(0, 3)
	if first < 2:
		return first + 2
	return rng.randi_range(0, 3) + 2


## Overwrites what [constant DAMAGE_CALC] worked out with the number these four
## effects actually deal, none of which come out of the ordinary formula:
## [constant Gen2MoveEffect.LEVEL_DAMAGE] is the user's own level,
## [constant Gen2MoveEffect.PSYWAVE] a roll of it, [constant Gen2MoveEffect.SUPER_FANG]
## half the target's current HP, and [constant Gen2MoveEffect.STATIC_DAMAGE] the
## move's own power field, taken directly rather than as an input to a formula.
## None of the four criticals or gets announced as super or not very effective,
## since the number was never actually multiplied by either; [constant DAMAGE_CALC]'s
## own roll, already spent, is only kept for the one thing worth keeping from
## it, whether the hit is immune at all, which [constant CHECK_IMMUNE] has
## already acted on by the time this runs.
static func _fixed_damage(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	var defender: Gen2BattleMon = turn.defender()

	match turn.effect():
		Gen2MoveEffect.LEVEL_DAMAGE:
			turn.damage = attacker.level
		Gen2MoveEffect.PSYWAVE:
			turn.damage = Gen2Damage.psywave_damage(attacker.level, turn.rng())
		Gen2MoveEffect.SUPER_FANG:
			@warning_ignore("integer_division")
			turn.damage = maxi(defender.hp / 2, 1)
		_: # STATIC_DAMAGE: Sonicboom and Dragon Rage deal exactly their own power.
			turn.damage = int(turn.move.get("power", 0))

	turn.critical = false
	turn.effectiveness = RomLayout.MATCHUP_EFFECTIVE


## How much an attacker's own level adds to an OHKO move's accuracy, doubled
## and added to the move's stored 30%-ish base once the defender's level is
## subtracted off.
const OHKO_LEVEL_BONUS: int = 2

## Guillotine, Horn Drill and Fissure: an instant faint with its own accuracy
## rule rather than the move's stored one read plainly.
##
## A defender with a higher level than the attacker is immune outright, no
## roll at all. Otherwise the move's own stored accuracy (a shade under 30%)
## is raised by two for every level the attacker has over the defender, capped
## the way any accuracy is, and rolled through the ordinary stage machinery
## before it decides anything: an attacker that has lowered the target's
## evasion or raised its own accuracy makes a one-hit KO likelier to land, the
## same as it would any other move.
static func _ohko(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	var defender: Gen2BattleMon = turn.defender()

	if attacker.level < defender.level:
		turn.emit(Gen2Battle.NO_EFFECT, {"target": turn.target})
		turn.end()
		return

	var accuracy: int = clampi(
		int(turn.move.get("accuracy", 0)) + (attacker.level - defender.level) * OHKO_LEVEL_BONUS,
		0, Gen2Accuracy.ALWAYS_HITS
	)
	var chance: int = Gen2Accuracy.chance(
		accuracy, attacker.stage("accuracy"), defender.stage("evasion")
	)
	if not Gen2Accuracy.rolls_hit(turn.rng(), chance):
		turn.emit(Gen2Battle.MISSED, {"target": turn.target})
		turn.end()
		return

	var dealt: int = defender.take_damage(defender.hp)
	turn.emit(Gen2Battle.OHKO, {
		"target": turn.target, "amount": dealt, "hp": defender.hp, "max_hp": defender.max_hp(),
	})
	_check_faint(turn)


## Locks the user out of its next turn. The tail of Hyper Beam's own list,
## always reached: there is no roll behind it and nothing it can fail against.
static func _recharge(turn: Gen2Turn) -> void:
	turn.attacker().substatus |= Gen2Substatus.RECHARGING


## A two-turn move's charge, in the shape [code]docs/CONTRIBUTING.md[/code]
## already describes: a list that ends early the first time.
##
## Not charging yet: locks the user in, announces it and ends the move before
## the damage is even worked out. Already charging, which is the release turn:
## clears the lock and falls through into the rest of the list, which is an
## ordinary attack from here. [method Gen2Battle.move_for] is what guarantees
## the release turn's move is the one that was charged, whatever slot the
## caller asks for.
static func _charge_move(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()
	if Gen2Substatus.has(mon.substatus, Gen2Substatus.CHARGING):
		mon.substatus &= ~Gen2Substatus.CHARGING
		mon.charged_move = 0
		return

	mon.substatus |= Gen2Substatus.CHARGING
	mon.charged_move = turn.move_number
	turn.emit(Gen2Battle.CHARGING_UP)
	turn.end()


## Haze: every stage on both sides, back to nothing. Not [Gen2Substatus] and not
## the status byte, either side's: only what [method Gen2BattleMon.reset_stages]
## already resets on a switch is reset here on demand.
static func _haze(turn: Gen2Turn) -> void:
	turn.battle.mon(Gen2Battle.PLAYER).reset_stages()
	turn.battle.mon(Gen2Battle.ENEMY).reset_stages()
	turn.emit(Gen2Battle.STAGES_CLEARED)


## Belly Drum. Fails, and costs nothing, unless the user has more than half its
## maximum HP and Attack has somewhere left to go; otherwise it takes half the
## maximum off and sends Attack straight to the top, however far short of it
## the stage already was.
static func _belly_drum(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()
	var has_enough_hp: bool = mon.hp * 2 > mon.max_hp()
	var stage: int = mon.stage("attack")
	if not has_enough_hp or stage >= Gen2Stats.MAX_STAGE:
		turn.emit(Gen2Battle.STAT_CHANGE_FAILED, {"target": turn.side, "stat": "attack", "by": 6})
		return

	@warning_ignore("integer_division")
	mon.take_damage(mon.max_hp() / 2)
	mon.change_stage("attack", Gen2Stats.MAX_STAGE - stage)
	turn.emit(Gen2Battle.STAT_CHANGED, {"target": turn.side, "stat": "attack", "by": 6})


## Psych Up: the target's seven stages, copied onto the user in one go, or a
## failure if the target has nothing raised or lowered for there to be anything
## to copy.
static func _psych_up(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	var defender: Gen2BattleMon = turn.defender()
	var keys: Array = Gen2BattleMon.STAGED_STATS + Gen2BattleMon.STAGED_ODDS

	var defender_changed: bool = false
	for key: String in keys:
		if int(defender.stages.get(key, 0)) != 0:
			defender_changed = true
			break
	if not defender_changed:
		return

	for key: String in keys:
		attacker.stages[key] = int(defender.stages.get(key, 0))
	turn.emit(Gen2Battle.STAGES_COPIED)


## Moves one stat by one command's worth, and writes down who it happened to and
## whether it actually moved, for the message step behind it to read.
##
## A secondary effect's failed roll skips this the same way it skips a status:
## the damage in front of it has already landed, and what was behind the roll is
## the only thing the roll can still cost.
static func _stat_change(command: StringName, turn: Gen2Turn) -> void:
	var entry: Array = STAT_COMMANDS[command]
	var stat_key: String = String(entry[0])
	var amount: int = int(entry[1])
	var side: int = turn.side if bool(entry[2]) else turn.target

	turn.stat_key = stat_key
	turn.stat_by = amount
	turn.stat_target = side

	if turn.failed_chance:
		turn.stat_moved = false
		return

	turn.stat_moved = turn.battle.mon(side).change_stage(stat_key, amount)


## Ancientpower's roll: the user's five real stats, all at once, reported as one
## event rather than five. Accuracy and evasion are not among them, because the
## cartridge's own command loops over the five a stage multiplies a real number
## for and not the two that only have a table of their own.
static func _all_stats_up(turn: Gen2Turn) -> void:
	if turn.failed_chance:
		return

	var mon: Gen2BattleMon = turn.attacker()
	var moved: bool = false
	for key: String in ALL_STATS_KEYS:
		if mon.change_stage(key, 1):
			moved = true

	if moved:
		turn.emit(Gen2Battle.STAT_CHANGED, {"target": turn.side, "stat": "all", "by": 1})


## Says a stat moved, or says nothing. A move whose sequence has no fail-text
## step behind this, which is every secondary effect, is silent either way when
## the stage was already at its limit.
static func _stat_message(turn: Gen2Turn) -> void:
	if not turn.stat_moved:
		return
	turn.emit(Gen2Battle.STAT_CHANGED, {
		"target": turn.stat_target, "stat": turn.stat_key, "by": turn.stat_by,
	})


## Says a stat could not move. Only reached from a status move's own sequence,
## which is the only place the cartridge follows a message step with this one.
static func _stat_fail_text(turn: Gen2Turn) -> void:
	if turn.stat_moved:
		return
	turn.emit(Gen2Battle.STAT_CHANGE_FAILED, {
		"target": turn.stat_target, "stat": turn.stat_key, "by": turn.stat_by,
	})
