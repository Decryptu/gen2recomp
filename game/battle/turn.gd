class_name Gen2Turn
extends RefCounted

## One move being used, while it is being used.
##
## The commands in [Gen2EffectCommands] hand each other their working: the damage
## step writes down what it calculated and the applying step reads it back. This
## is where that lives, for exactly as long as the move does.
##
## Not a copy of the battle: both Pokémon are read through the battle every time,
## so a command that changes one is seen by the commands after it.

var battle: Gen2Battle = null

## Who is using the move, and who it is aimed at.
var side: int = Gen2Battle.PLAYER
var target: int = Gen2Battle.ENEMY

## The move, its number, and the slot it came out of. The slot is what PP is
## spent from and is -1 for a move that came from nowhere, like Struggle.
var slot: int = -1
var move_number: int = 0
var move: Dictionary = {}

## Where the story of the turn is written. The same Array the caller of
## [method Gen2Battle.take_actions] is handed back.
var events: Array = []

## What the damage steps worked out, for the steps after them.
var damage: int = 0
var critical: bool = false
var effectiveness: int = RomLayout.MATCHUP_EFFECTIVE
var immune: bool = false
var missed: bool = false

## The truncated pair `damagestats` leaves in `b` and `c` for `damagecalc` to
## divide with. Two commands rather than one, so Present can set the power
## between them.
var attack_stat: int = 0
var defense_stat: int = 0

## What a command has written over the move's own power and type, or -1 for the
## cartridge row's own.
##
## `wPlayerMoveStruct` is a per-turn copy the cartridge writes into freely, so
## `happinesspower`, `getmagnitude`, `present` and `hiddenpower` all just store a
## byte there. [member move] is not a copy: [method GameData.move] hands back the
## cached row itself, so writing to it would edit the move table for the rest of
## the process. These two are that per-turn copy, read through
## [method effective_move].
var power_override: int = -1
var type_override: int = -1

## The level `damagecalc` multiplies, or -1 for the attacker's own. The one field
## here with no `wPlayerMoveStruct` counterpart: `BattleCommand_BeatUp` hands the
## formula a party member's level in `e`, and the Pokémon on the field is only
## one of the six it walks.
var level_override: int = -1

## The same per-turn copy one field along, with one writer: `DoSubstituteDamage`
## stamps `EFFECT_NORMAL_HIT` over `wPlayerMoveStruct + MOVE_EFFECT` once a doll
## has broken, so the steps behind the break read an ordinary attack.
var effect_override: int = -1

## What was actually taken off, which is not the same as [member damage]: a
## Pokémon with three hit points left takes three from a hit worth forty.
var dealt: int = 0

## Set by a command that has decided the move is finished, whether because it
## missed, because it did nothing, or because it reached its end.
var ended: bool = false

## Whether this is the release turn of a two-turn move, set by [Gen2Battle]
## before anything runs. The PP for a two-turn move is spent once, on the
## charge turn, so [method Gen2EffectCommands._do_turn] reads this rather than
## spending again on the turn the attack actually lands.
var locked: bool = false

## A move entered through Metronome, Mirror Move or Sleep Talk. `ResetTurn`
## marks the cartridge's temporary charging byte before it re-enters `DoMove`:
## the called sequence still announces and executes, but `doturn` spends no PP
## and does not add a second turn. This flag is that temporary byte, separate
## from [member locked], which is a real multi-turn continuation.
var called: bool = false

## A called-move command asks the effect interpreter to replace this turn's
## move and restart at that move's first command. Zero means no restart is
## pending. [Gen2Battle] consumes it immediately after the command returns.
var called_move_number: int = 0

## StoreEnergy marks a Bide release so UsedMoveText is skipped, matching its
## jump directly to `unleashenergy` in the command stream.
var bide_release: bool = false

## The accuracy byte this move is rolled against, or -1 for the move's own.
## `wPlayerMoveStruct` is a per-turn copy the cartridge is free to write into;
## [member move] is the cached row, so what would be a write there is this
## instead. Only [method Gen2EffectCommands._thunder_accuracy] sets it.
var accuracy: int = -1

## Set by [method Gen2EffectCommands._skip_sun_charge] so
## [method Gen2EffectCommands._charge_move] locks nothing in: Solarbeam in sun is
## a one-turn move.
var skip_charge: bool = false

## Set when a secondary effect's roll came up short. It is not the same as
## [member ended]: the move has happened and its damage stands, and only what was
## behind the roll is skipped.
var failed_chance: bool = false

## What a stat-changing command worked out, for the message command behind it.
## [member stat_target] is who it happened to, which is the user for a raise and
## the defender for almost every drop.
var stat_key: String = ""
var stat_by: int = 0
var stat_target: int = Gen2Battle.PLAYER
var stat_moved: bool = false

## `wSomeoneIsRampaging`, which `DoMove` clears before every move and only a
## rampage or a Rollout being *started* sets. `BattleCommand_LowerSub` is the
## one reader: a continuation turn drops the doll where a charging turn would
## not have.
var someone_is_rampaging: bool = false

## Set instead of moving a stat when a drop was blocked by the target's own
## Mist, so the fail-text step behind it can tell that apart from the ordinary
## "already at the bottom" failure and say the right thing.
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


## The move as the damage steps read it: the cartridge row with whatever
## [member power_override] and [member type_override] have put over it.
##
## Never [member move] itself once either is set, and never a write into it: that
## Dictionary is the cache's own row.
func effective_move() -> Dictionary:
	if power_override < 0 and type_override < 0:
		return move
	var out: Dictionary = move.duplicate()
	if power_override >= 0:
		out["power"] = power_override
	if type_override >= 0:
		out["type"] = type_override
	return out


## Writes an event down. [param extra] is merged over the side, which every event
## carries.
func emit(type: StringName, extra: Dictionary = {}) -> void:
	var event: Dictionary = {"type": type, "side": side}
	event.merge(extra, true)
	events.append(event)


## Stops the move where it stands. The commands after this one are not run.
func end() -> void:
	ended = true
