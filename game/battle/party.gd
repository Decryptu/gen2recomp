class_name Gen2Party
extends RefCounted

## The Pokémon one side of a battle has, and which of them is out.
##
## An ordered list and a cursor into it, not a set: the order is what a switch
## menu shows and what a replacement is chosen from, and the first entry leads. A
## wild battle is a party of one, so it needs no special case.
##
## Fainted Pokémon stay in the list, still counting against the six. A battle is
## lost when all of them are down, not when the list runs out.

## What a trainer can carry. Six is a rule of these games rather than of this
## class, but a party that is longer is a bug somewhere upstream and is worth
## refusing at the door.
const MAX_SIZE: int = 6

var mons: Array = []
var active: int = 0


## A party from the Pokémon in it, in order. Returns null for an empty list or
## for one longer than a trainer can carry.
static func create(members: Array) -> Gen2Party:
	if members.is_empty() or members.size() > MAX_SIZE:
		return null
	for member: Variant in members:
		if member == null:
			return null

	var out := Gen2Party.new()
	out.mons = members.duplicate()
	out.active = 0
	return out


## A party of one, which is what a wild encounter is.
static func of(mon: Gen2BattleMon) -> Gen2Party:
	return create([mon])


func size() -> int:
	return mons.size()


## One member by its position, or null if there is no such position.
func at(index: int) -> Gen2BattleMon:
	if index < 0 or index >= mons.size():
		return null
	return mons[index]


func active_mon() -> Gen2BattleMon:
	return at(active)


## Whether the whole party is down, which is what loses a battle. Not whether the
## one that is out has fainted: that is a Pokémon to replace, not a defeat.
func is_wiped() -> bool:
	for mon: Gen2BattleMon in mons:
		if not mon.is_fainted():
			return false
	return true


func healthy_count() -> int:
	var out: int = 0
	for mon: Gen2BattleMon in mons:
		if not mon.is_fainted():
			out += 1
	return out


## Whether [param index] is somebody this party could send out: a member that is
## still standing and is not already the one out.
func can_send_out(index: int) -> bool:
	var mon: Gen2BattleMon = at(index)
	return mon != null and index != active and not mon.is_fainted()


## The first member still standing, or -1 for a party that is wiped. What a
## caller with no opinion sends out, and what leads a battle.
func first_healthy() -> int:
	for index: int in mons.size():
		if not mons[index].is_fainted():
			return index
	return -1


## Puts [param index] out, and answers whether it went.
##
## The Pokémon leaving keeps its health and PP and loses its stat stages and
## everything [Gen2Substatus] holds. A stage is a lens on a stat, and neither it
## nor confusion, a charge or a recharge survives the walk back to the ball.
func send_out(index: int) -> bool:
	if not can_send_out(index):
		return false

	var leaving: Gen2BattleMon = active_mon()
	if leaving != null:
		leaving.reset_stages()
		leaving.reset_volatile()
	active = index
	return true
