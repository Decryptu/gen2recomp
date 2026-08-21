class_name Gen2MoveDeleter
extends RefCounted

## `MoveDeletion` (`engine/events/move_deleter.asm`), the rules half.
##
## Same shape as [Gen2NameRater], one house further on: an introduction and a
## `YesNoBox`, the party list `SelectMonFromParty` opens, two endings that need
## no move, `ChooseMoveToDelete`'s own list, a second `YesNoBox` and
## `.DeleteMove`. [Gen2MoveDeleterScreen] is the routine; this holds nothing.

## The endings `PrintText` closes on, by the stub each branch loads into hl.
const ENDING_EGG: StringName = &"egg"
const ENDING_ONLY_ONE_MOVE: StringName = &"knows_one"
const ENDING_DECLINED: StringName = &"come_again"
const ENDING_FORGOT: StringName = &"forgot"

## `constants/sfx_constants.asm`'s SFX_MOVE_DELETED, played between two
## `WaitSFX`es once the slot has been cleared.
const SFX_MOVE_DELETED: int = 0x97


## Which ending [param mon] reaches once it has been chosen, or `&""` for the
## one member the routine carries on with.
##
## `.onlyonemove` reads `wPartyMon1Moves + 1`, which is the *second* slot rather
## than a move count, so a member whose second slot is empty is refused whatever
## stands behind it.
static func ending_for(mon: Gen2SaveMon) -> StringName:
	if mon == null:
		return ENDING_DECLINED
	if mon.is_egg:
		return ENDING_EGG
	if mon.moves.size() < 2 or int(mon.moves[1]) == 0:
		return ENDING_ONLY_ONE_MOVE
	return &""


## `.DeleteMove`: the slots above the deleted one come down and the last is
## zeroed, moves and PP in the same shape. Answers whether anything was written.
static func delete_move(mon: Gen2SaveMon, slot: int) -> bool:
	if mon == null or slot < 0 or slot >= mon.moves.size():
		return false
	if int(mon.moves[slot]) == 0:
		return false
	_shift(mon.moves, slot)
	_shift(mon.pp, slot)
	return true


static func _shift(slots: Array, slot: int) -> void:
	if slot >= slots.size():
		return
	for index: int in range(slot, slots.size() - 1):
		slots[index] = slots[index + 1]
	slots[slots.size() - 1] = 0
