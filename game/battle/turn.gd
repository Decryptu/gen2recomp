class_name Gen2Turn
extends RefCounted

## One move being used, while it is being used.
##
## The commands in [Gen2EffectCommands] are steps in a sequence and have to hand
## each other their working: the damage step writes down what it worked out and
## the step that applies it reads that back, rather than either of them doing the
## other's job. This is where that working lives, and it lasts exactly as long as
## the move does.
##
## It is not a copy of the battle. Everything about the two Pokémon is read
## through the battle every time, so a command that changes one is seen by the
## commands after it.

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

## What was actually taken off, which is not the same as [member damage]: a
## Pokémon with three hit points left takes three from a hit worth forty.
var dealt: int = 0

## Set by a command that has decided the move is finished, whether because it
## missed, because it did nothing, or because it reached its end.
var ended: bool = false


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
