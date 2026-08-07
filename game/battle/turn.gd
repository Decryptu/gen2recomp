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

## What the damage step worked out, for the steps after it.
var damage: int = 0
var critical: bool = false
var effectiveness: int = RomLayout.MATCHUP_EFFECTIVE
var immune: bool = false
var missed: bool = false

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
	return int(move.get("effect", -1))


## Writes an event down. [param extra] is merged over the side, which every event
## carries.
func emit(type: StringName, extra: Dictionary = {}) -> void:
	var event: Dictionary = {"type": type, "side": side}
	event.merge(extra, true)
	events.append(event)


## Stops the move where it stands. The commands after this one are not run.
func end() -> void:
	ended = true
