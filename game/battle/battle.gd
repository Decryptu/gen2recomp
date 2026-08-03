class_name Gen2Battle
extends RefCounted

## A battle: two parties, a turn at a time.
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
## A side is a party, and a wild encounter is a party of one. Two things are the
## caller's to decide rather than this class's, because the cartridge asks a
## person or an AI for both and neither exists yet: which action a side takes,
## and who replaces a Pokémon that has fainted. A turn that ends with somebody
## down stops there and says so through [method must_replace]; nothing is sent
## out until [method send_out] is called.

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
## A status stopped a Pokémon moving. [code]reason[/code] says which one, since
## the three read differently and only one of them is a surprise.
const CANNOT_MOVE: StringName = &"cannot_move"
const WOKE_UP: StringName = &"woke_up"
const THAWED: StringName = &"thawed"
## A status put on a Pokémon, and a slice taken off by one it already had.
const STATUS_INFLICTED: StringName = &"status_inflicted"
const HURT_BY_STATUS: StringName = &"hurt_by_status"
## A stat moved a stage, or tried to and could not. [code]stat[/code] is the key
## [Gen2BattleMon] keeps it under, or [code]"all"[/code] for the five Ancientpower
## moves at once; [code]by[/code] is how many stages, signed.
const STAT_CHANGED: StringName = &"stat_changed"
const STAT_CHANGE_FAILED: StringName = &"stat_change_failed"
## A Pokémon called back, and a Pokémon put out. They are two events rather than
## one because a replacement after a faint is only the second half: there is
## nobody to call back, and the screen has one sentence to say rather than two.
const WITHDREW: StringName = &"withdrew"
const SENT_OUT: StringName = &"sent_out"
const OVER: StringName = &"over"

## What a side does with its turn. Switching is not a move with a very high
## priority: it is settled before priority is looked at, which is why it is an
## action rather than a move number.
const ACTION_MOVE: StringName = &"move"
const ACTION_SWITCH: StringName = &"switch"

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


var data: GameData = null
var rng: RandomNumberGenerator = null

## The two sides, keyed by [constant PLAYER] and [constant ENEMY].
var parties: Dictionary = {}

## Whoever is out on each side. Read through the party every time rather than
## kept in step with it: a switch changes who this is, and a copy that had to be
## updated is a copy that will one day not be.
var player: Gen2BattleMon:
	get:
		return party(PLAYER).active_mon()
var enemy: Gen2BattleMon:
	get:
		return party(ENEMY).active_mon()


## Two parties, each led by whoever is first in it.
static func create_parties(
	game_data: GameData,
	player_party: Gen2Party,
	enemy_party: Gen2Party,
	generator: RandomNumberGenerator
) -> Gen2Battle:
	if game_data == null or player_party == null or enemy_party == null:
		return null
	if player_party.is_wiped() or enemy_party.is_wiped():
		return null

	var out := Gen2Battle.new()
	out.data = game_data
	out.parties = {PLAYER: player_party, ENEMY: enemy_party}
	out.rng = generator if generator != null else RandomNumberGenerator.new()
	return out


## One Pokémon a side, which is what a wild encounter is.
static func create(
	game_data: GameData,
	player_mon: Gen2BattleMon,
	enemy_mon: Gen2BattleMon,
	generator: RandomNumberGenerator
) -> Gen2Battle:
	if player_mon == null or enemy_mon == null:
		return null
	return create_parties(
		game_data, Gen2Party.of(player_mon), Gen2Party.of(enemy_mon), generator
	)


## What a side asks for with its turn.
static func use_move(slot: int) -> Dictionary:
	return {"type": ACTION_MOVE, "slot": slot}


static func switch_to(index: int) -> Dictionary:
	return {"type": ACTION_SWITCH, "index": index}


func party(side: int) -> Gen2Party:
	return parties[side]


func mon(side: int) -> Gen2BattleMon:
	return party(side).active_mon()


func opponent_of(side: int) -> int:
	return ENEMY if side == PLAYER else PLAYER


## A battle is lost when a whole party is down, not when the Pokémon that is out
## has fainted. One of those is a defeat and the other is a Pokémon to replace.
func is_over() -> bool:
	return party(PLAYER).is_wiped() or party(ENEMY).is_wiped()


## Whoever is still standing, or null if the battle is not over. Both sides can
## go down in one turn, through recoil; the cartridge gives it to whoever is left
## and there is nobody, so this answers null for that too.
func winner() -> Variant:
	if not is_over():
		return null
	if party(PLAYER).is_wiped() and party(ENEMY).is_wiped():
		return null
	return ENEMY if party(PLAYER).is_wiped() else PLAYER


## Whether a side is waiting for somebody to be sent out: the Pokémon that was
## out has fainted and there is still a party behind it. Nothing else can happen
## on either side until it is answered, which is the cartridge's order too.
func must_replace(side: int) -> bool:
	var current: Gen2Party = party(side)
	return current.active_mon().is_fainted() and not current.is_wiped()


func awaiting_replacement() -> bool:
	return must_replace(PLAYER) or must_replace(ENEMY)


## Sends a side's [param index] out, whether as a replacement or between turns.
## Returns the events, which is one event or none: a switch that cannot be made
## is refused rather than approximated.
func send_out(side: int, index: int) -> Array:
	var events: Array = []
	if is_over():
		return events

	var current: Gen2Party = party(side)
	var leaving: int = current.active
	var leaving_species: int = current.active_mon().species
	var withdrawing: bool = not current.active_mon().is_fainted()
	if not current.send_out(index):
		return events

	# Nothing is called back after a faint, so the first half of the pair is only
	# there when there was somebody to call back.
	if withdrawing:
		events.append({
			"type": WITHDREW, "side": side, "index": leaving, "species": leaving_species,
		})
	events.append({
		"type": SENT_OUT, "side": side, "index": index,
		"species": current.active_mon().species,
		"hp": current.active_mon().hp, "max_hp": current.active_mon().max_hp(),
	})
	return events


## Both sides act, and the turn plays out. Returns the events in the order they
## happened.
##
## An action is [method use_move] or [method switch_to]. Nothing happens while
## either side owes a replacement, and a faint ends the turn where it is: a
## Pokémon that is knocked out before it has moved does not get to move, which is
## most of what speed is for.
func take_actions(player_action: Dictionary, enemy_action: Dictionary) -> Array:
	var events: Array = []
	if is_over() or awaiting_replacement():
		return events

	var actions: Dictionary = {PLAYER: player_action, ENEMY: enemy_action}
	var chosen: Dictionary = {
		PLAYER: _move_for_action(PLAYER, player_action),
		ENEMY: _move_for_action(ENEMY, enemy_action),
	}

	var acting: Array = order(chosen, actions)
	for side: int in acting:
		if _is_switch(actions[side]):
			events.append_array(send_out(side, int(actions[side].get("index", -1))))
			continue
		if mon(side).is_fainted() or mon(opponent_of(side)).is_fainted():
			break
		_act(side, int(actions[side].get("slot", 0)), chosen[side], events)

	_residual_damage(acting, events)

	if is_over():
		events.append({"type": OVER, "winner": winner()})
	return events


## Both sides use a move slot, which is the common case and the whole of a battle
## that has one Pokémon a side.
func take_turn(player_slot: int, enemy_slot: int) -> Array:
	return take_actions(use_move(player_slot), use_move(enemy_slot))


## What a burn or a poison takes at the end of the turn, from each side in the
## order it acted.
##
## After both moves rather than after each, and skipping whoever is already down:
## a Pokémon that has fainted this turn is not burned any further, and one that
## goes down to its burn faints here rather than in the middle of somebody's move.
func _residual_damage(acting: Array, events: Array) -> void:
	for side: int in acting:
		var current: Gen2BattleMon = mon(side)
		if current.is_fainted():
			continue
		if not Gen2Status.has(current.status, Gen2Status.BURN | Gen2Status.POISON):
			continue

		var taken: int = current.take_damage(Gen2Status.residual_damage(current.max_hp()))
		events.append({
			"type": HURT_BY_STATUS,
			"side": side,
			"status": current.status,
			"name": Gen2Status.name_of(current.status),
			"amount": taken,
			"hp": current.hp,
			"max_hp": current.max_hp(),
		})
		if current.is_fainted():
			events.append({"type": FAINTED, "side": side})


static func _is_switch(action: Dictionary) -> bool:
	return StringName(action.get("type", ACTION_MOVE)) == ACTION_SWITCH


## The move an action commits a side to, which is nothing at all for a switch.
## Struggle stands in there so that the order can be worked out without a special
## case; a switching side never reaches the point of using it.
func _move_for_action(side: int, action: Dictionary) -> int:
	if _is_switch(action):
		return Gen2Damage.STRUGGLE
	return move_for(side, int(action.get("slot", 0)))


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
## A switch is settled before any of this: the cartridge sends the incoming
## Pokémon out and then lets the other side's move hit it, so a side that is
## switching acts first however fast the other one is and whatever priority its
## move has. Two switches in the same turn go to the player, which is what the
## cartridge does outside a link battle.
##
## Failing that, priority decides it; equal priority goes to the faster Pokémon,
## by its speed with stages applied; and a genuine tie is a coin flip. The
## cartridge weighs a held Quick Claw between the priority and the speed, which
## nothing here carries yet.
func order(chosen: Dictionary, actions: Dictionary = {}) -> Array:
	var player_switching: bool = _is_switch(actions.get(PLAYER, {}))
	var enemy_switching: bool = _is_switch(actions.get(ENEMY, {}))
	if player_switching or enemy_switching:
		return _sides(player_switching)

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


## One side's move, run as the list of commands its effect is made of.
##
## Nothing about what a particular move does lives here. The effect byte picks a
## sequence out of [Gen2MoveEffect], the commands in it are run in order against
## a [Gen2Turn] until one of them says the move is finished, and every rule about
## announcing, spending, rolling, applying and fainting is one of those commands.
## That is the cartridge's own arrangement, and it is what lets the rest of
## Generation 2 be written as commands rather than as branches in here.
func _act(side: int, slot: int, move_number: int, events: Array) -> void:
	var move: Dictionary = data.move(move_number)
	if move.is_empty():
		return

	var turn: Gen2Turn = Gen2Turn.create(self, side, slot, move_number, move, events)

	# Whether the Pokémon can move at all is asked before the effect is looked up,
	# which is the cartridge's arrangement: every move goes through it, so no
	# sequence has to remember to include it.
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_STATUS, turn)

	for command: StringName in Gen2MoveEffect.sequence_for(turn.effect()):
		if turn.ended:
			return
		Gen2EffectCommands.run(command, turn)
