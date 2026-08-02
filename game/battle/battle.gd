class_name Gen2Battle
extends RefCounted

## A battle: two Pokémon, a turn at a time.
##
## [RefCounted] and scene-free, with its randomness injected, so a whole battle
## can be fought inside a test with no display. It knows nothing about how a
## battle is drawn.
##
## A turn answers with a list of events rather than with a new state or a string.
## An event says what happened and carries the numbers behind it; turning that
## into a sentence, an animation or a bar that drains is the screen's job, and
## keeping the two apart is what lets a battle be asserted on rather than read.
##
## One Pokémon a side, and no switching. A party, and the choice of what to send
## out next, is the next thing this wants and is deliberately not here yet.

## The two sides, as plain numbers rather than an enum: they are dictionary keys
## and event payloads throughout, and an enum buys nothing where everything that
## reads one is comparing it against these two constants.
const PLAYER: int = 0
const ENEMY: int = 1

## What a turn can report. Every event carries [code]side[/code], which is
## whoever acted, and the rest depends on the type.
const USED_MOVE: StringName = &"used_move"
const MISSED: StringName = &"missed"
const NO_EFFECT: StringName = &"no_effect"
const HIT: StringName = &"hit"
const RECOIL: StringName = &"recoil"
const FAINTED: StringName = &"fainted"
const OVER: StringName = &"over"

## Priority runs from 0 to 3 and most moves are 1, so a move can go below the
## ordinary as well as above it. The values are keyed by the move's effect byte,
## which the cache already carries.
const BASE_PRIORITY: int = 1
const EFFECT_PRIORITIES: Dictionary = {
	0x6F: 3,  # Protect
	0x74: 3,  # Endure
	0x67: 2,  # Quick Attack, Extreme Speed, Mach Punch
	0x1C: 0,  # Whirlwind and Roar
	0x59: 0,  # Counter
	0x90: 0,  # Mirror Coat
}

## Vital Throw is slower than everything and says so in the move itself rather
## than through its effect, so it is the one move the table cannot answer for.
const VITAL_THROW: int = 0xE9

## Recoil is a quarter of the damage dealt, never less than one. It is the only
## move effect this understands, and it is here because Struggle needs it: a
## Pokémon out of PP has to be able to hurt itself, or a battle between two
## empty Pokémon never ends.
const EFFECT_RECOIL_HIT: int = 48
const RECOIL_DIVISOR: int = 4

var data: GameData = null
var rng: RandomNumberGenerator = null

var player: Gen2BattleMon = null
var enemy: Gen2BattleMon = null


static func create(
	game_data: GameData,
	player_mon: Gen2BattleMon,
	enemy_mon: Gen2BattleMon,
	generator: RandomNumberGenerator
) -> Gen2Battle:
	if game_data == null or player_mon == null or enemy_mon == null:
		return null

	var out := Gen2Battle.new()
	out.data = game_data
	out.player = player_mon
	out.enemy = enemy_mon
	out.rng = generator if generator != null else RandomNumberGenerator.new()
	return out


func mon(side: int) -> Gen2BattleMon:
	return player if side == PLAYER else enemy


func opponent_of(side: int) -> int:
	return ENEMY if side == PLAYER else PLAYER


func is_over() -> bool:
	return player.is_fainted() or enemy.is_fainted()


## Whoever is still standing, or null if the battle is not over. Both sides can
## faint in one turn, through recoil; the cartridge gives it to whoever is left
## and there is nobody, so this answers null for that too.
func winner() -> Variant:
	if not is_over():
		return null
	if player.is_fainted() and enemy.is_fainted():
		return null
	return ENEMY if player.is_fainted() else PLAYER


## Both sides pick a move slot, and the turn plays out. Returns the events in the
## order they happened.
func take_turn(player_slot: int, enemy_slot: int) -> Array:
	var events: Array = []
	if is_over():
		return events

	var chosen: Dictionary = {
		PLAYER: move_for(PLAYER, player_slot),
		ENEMY: move_for(ENEMY, enemy_slot),
	}
	var slots: Dictionary = {PLAYER: player_slot, ENEMY: enemy_slot}

	for side: int in order(chosen):
		if is_over():
			break
		_act(side, slots[side], chosen[side], events)

	if is_over():
		events.append({"type": OVER, "winner": winner()})
	return events


## Which move a side will actually use.
##
## A slot with nothing usable in it answers Struggle, which is the cartridge's
## answer for a Pokémon with no PP anywhere. Here it is also the answer for a
## slot that is empty or spent while others are not, because a caller that points
## at one has asked for something that cannot happen, and Struggle is the only
## move that is always available.
func move_for(side: int, slot: int) -> int:
	var attacker: Gen2BattleMon = mon(side)
	return int(attacker.moves[slot]) if attacker.can_use(slot) else Gen2Damage.STRUGGLE


## Who goes first, as the two sides in the order they act.
##
## Priority decides it; equal priority goes to the faster Pokémon, by its speed
## with stages applied; and a genuine tie is a coin flip. The cartridge weighs a
## held Quick Claw between the priority and the speed, which nothing here carries
## yet.
func order(chosen: Dictionary) -> Array:
	var player_priority: int = priority_of(data.move(int(chosen[PLAYER])))
	var enemy_priority: int = priority_of(data.move(int(chosen[ENEMY])))
	if player_priority != enemy_priority:
		return _sides(player_priority > enemy_priority)

	var player_speed: int = player.stat("speed")
	var enemy_speed: int = enemy.stat("speed")
	if player_speed != enemy_speed:
		return _sides(player_speed > enemy_speed)

	return _sides(rng.randi_range(0, 255) < 128)


func _sides(player_first: bool) -> Array:
	return [PLAYER, ENEMY] if player_first else [ENEMY, PLAYER]


## A move's priority, from its effect byte.
static func priority_of(move: Dictionary) -> int:
	if int(move.get("number", 0)) == VITAL_THROW:
		return 0
	return int(EFFECT_PRIORITIES.get(int(move.get("effect", -1)), BASE_PRIORITY))


## One side's move, from the announcement to the faint.
##
## The order is the cartridge's: the damage is worked out before the hit is
## rolled, and an immunity is settled before either. That matters less for the
## answer than for the shape, but it is also free.
func _act(side: int, slot: int, move_number: int, events: Array) -> void:
	var attacker: Gen2BattleMon = mon(side)
	var target: int = opponent_of(side)
	var defender: Gen2BattleMon = mon(target)
	var move: Dictionary = data.move(move_number)
	if move.is_empty():
		return

	# Struggle is what happens when there is nothing to spend, so it spends
	# nothing.
	if move_number != Gen2Damage.STRUGGLE:
		attacker.spend_pp(slot)
	events.append({"type": USED_MOVE, "side": side, "move": move_number})

	var result: Dictionary = Gen2Damage.calculate(attacker, defender, move, rng)
	if bool(result["immune"]):
		events.append({"type": NO_EFFECT, "side": side, "target": target})
		return

	if not Gen2Accuracy.rolls_hit(rng, _hit_chance(attacker, defender, move)):
		events.append({"type": MISSED, "side": side, "target": target})
		return

	var dealt: int = defender.take_damage(int(result["damage"]))
	events.append({
		"type": HIT,
		"side": side,
		"target": target,
		"amount": dealt,
		"critical": bool(result["critical"]),
		"effectiveness": int(result["effectiveness"]),
		"hp": defender.hp,
		"max_hp": defender.max_hp(),
	})

	if int(move.get("effect", -1)) == EFFECT_RECOIL_HIT and dealt > 0:
		@warning_ignore("integer_division")
		var recoil: int = maxi(dealt / RECOIL_DIVISOR, 1)
		var taken: int = attacker.take_damage(recoil)
		events.append({
			"type": RECOIL, "side": side, "amount": taken,
			"hp": attacker.hp, "max_hp": attacker.max_hp(),
		})

	# Both can be down at this point: recoil can take the attacker with it.
	for fainted: int in [target, side]:
		if mon(fainted).is_fainted():
			events.append({"type": FAINTED, "side": fainted})


func _hit_chance(
	attacker: Gen2BattleMon, defender: Gen2BattleMon, move: Dictionary
) -> int:
	return Gen2Accuracy.chance(
		int(move.get("accuracy", Gen2Accuracy.ALWAYS_HITS)),
		attacker.stage("accuracy"), defender.stage("evasion")
	)
