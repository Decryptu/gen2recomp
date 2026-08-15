class_name Gen2Turn
extends RefCounted

## `wPlayerMoveStruct` and the working [Gen2EffectCommands] hand between its
## commands, for exactly as long as one move lasts. Not a copy of the battle:
## both Pokémon are read through it, so a command that changes one is seen by the
## commands after it.

var battle: Gen2Battle = null

var side: int = Gen2Battle.PLAYER
var target: int = Gen2Battle.ENEMY

## The slot PP is spent from, -1 for a move that came from nowhere (Struggle).
var slot: int = -1
var move_number: int = 0
var move: Dictionary = {}

## The same Array [method Gen2Battle.take_actions] hands its caller back.
var events: Array = []

## What the damage steps worked out, for the steps after them.
var damage: int = 0
var critical: bool = false
var effectiveness: int = RomLayout.MATCHUP_EFFECTIVE
var immune: bool = false
var missed: bool = false

## The truncated pair `damagestats` leaves for `damagecalc`: two commands rather
## than one, so Present can set the power between them.
var attack_stat: int = 0
var defense_stat: int = 0

## The per-turn copy `happinesspower`, `getmagnitude`, `present` and
## `hiddenpower` write a byte into, -1 for the row's own. [member move] is the
## cache's row itself, so writing there would edit the move table.
var power_override: int = -1
var type_override: int = -1

## The level `damagecalc` multiplies, -1 for the attacker's own. No
## `wPlayerMoveStruct` counterpart: `BattleCommand_BeatUp` hands the formula a
## party member's level in `e`.
var level_override: int = -1

## `DoSubstituteDamage` stamps `EFFECT_NORMAL_HIT` over `wPlayerMoveStruct +
## MOVE_EFFECT` once a doll has broken, so the steps behind it read a plain hit.
var effect_override: int = -1

## What was taken off, not [member damage]: three hit points left takes three.
var dealt: int = 0

## A command has decided the move is finished, however it finished.
var ended: bool = false

## The release turn of a two-turn move, whose PP was spent on the charge turn:
## what [method Gen2EffectCommands._do_turn] reads.
var locked: bool = false

## `ResetTurn`'s temporary charging byte: a move entered through Metronome,
## Mirror Move or Sleep Talk spends no PP and adds no second turn. Not
## [member locked], which is a real continuation.
var called: bool = false

## A called-move command's request to restart at another move's first command,
## zero for none. [Gen2Battle] consumes it as soon as the command returns.
var called_move_number: int = 0

## `StoreEnergy`'s Bide release, which skips `UsedMoveText`.
var bide_release: bool = false

## The accuracy byte rolled against, -1 for the move's own. Only
## [method Gen2EffectCommands._thunder_accuracy] sets it.
var accuracy: int = -1

## Solarbeam in sun: [method Gen2EffectCommands._charge_move] locks nothing in.
var skip_charge: bool = false

## A secondary effect's roll came up short. Not [member ended]: the damage
## stands and only what was behind the roll is skipped.
var failed_chance: bool = false

## What a stat-changing command worked out, for the message command behind it.
## [member stat_target] is the user for a raise and the defender for most drops.
var stat_key: String = ""
var stat_by: int = 0
var stat_target: int = Gen2Battle.PLAYER
var stat_moved: bool = false

## `wSomeoneIsRampaging`, read by `BattleCommand_LowerSub` alone.
var someone_is_rampaging: bool = false

## A drop blocked by Mist, which the fail-text step says differently from an
## "already at the bottom" one.
var stat_mist_blocked: bool = false


static func create(
	in_battle: Gen2Battle, acting: int, from_slot: int, number: int, move_data: Dictionary,
	into: Array
) -> Gen2Turn:
	var out := Gen2Turn.new()
	out.battle = in_battle
	out.side = acting
	out.target = in_battle.opponent_of(acting)
	out.slot = from_slot
	out.move_number = number
	out.move = move_data
	out.events = into
	return out


func attacker() -> Gen2BattleMon:
	return battle.mon(side)


func defender() -> Gen2BattleMon:
	return battle.mon(target)


func data() -> GameData:
	return battle.data


func rng() -> RandomNumberGenerator:
	return battle.rng


func effect() -> int:
	if effect_override >= 0:
		return effect_override
	return int(move.get("effect", -1))


## The row with [member power_override] and [member type_override] over it,
## copied rather than written into: [member move] is the cache's own row.
func effective_move() -> Dictionary:
	if power_override < 0 and type_override < 0:
		return move
	var out: Dictionary = move.duplicate()
	if power_override >= 0:
		out["power"] = power_override
	if type_override >= 0:
		out["type"] = type_override
	return out


## [param extra] merged over the side every event carries.
func emit(type: StringName, extra: Dictionary = {}) -> void:
	var event: Dictionary = {"type": type, "side": side}
	event.merge(extra, true)
	events.append(event)


## Stops the move: the commands after this one are not run.
func end() -> void:
	ended = true
