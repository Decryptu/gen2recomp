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
		_:
			push_error("No such effect command: %s" % command)


static func _used_move_text(turn: Gen2Turn) -> void:
	turn.emit(Gen2Battle.USED_MOVE, {"move": turn.move_number})


## Struggle is what a Pokémon does when there is nothing left to spend, so it
## spends nothing, and it is the one move that arrives without a slot.
static func _do_turn(turn: Gen2Turn) -> void:
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


static func _check_hit(turn: Gen2Turn) -> void:
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


## Sleep, then freeze, then paralysis, which is the order the cartridge asks in.
## A frozen Pokémon is never asked whether it is also paralysed, because the byte
## cannot say both.
##
## Waking up does not cost the turn. The cartridge counts the sleep off, prints
## that the Pokémon woke, and carries on into the rest of its checks rather than
## ending the turn, so a Pokémon whose counter runs out attacks the same turn it
## opens its eyes. That is Generation 2's rule and not Generation 1's.
static func _check_status(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()

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
