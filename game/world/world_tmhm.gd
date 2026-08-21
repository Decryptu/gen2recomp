class_name Gen2WorldTMHM
extends RefCounted

## Scene-free tables and gates for teaching a TM or HM
## (engine/items/tmhm.asm, engine/items/tmhm2.asm).
##
## The TM/HM pocket does not reach `UseItem`'s jumptable at all: its own USE
## entry runs AskTeachTMHM, then ChooseMonToLearnTMHM, then TeachTMHM
## (engine/items/pack.asm's .UseItem). This class owns the first and the checks
## the third makes; Gen2WorldPartyHost.teach_tm_hm() owns the transaction.
##
## Everything here is byte identical between the pins. pokegold's TeachTMHM
## differs by one line, a stubbed trainer-ranking call that does nothing.

## constants/item_constants.asm. The run from TM01 to HM07 is not contiguous:
## ITEM_C3 and ITEM_DC sit inside it as dummies, which is why the number a TM
## carries comes from RomLayout.tmhm_number_for_item() rather than subtraction.
const ITEM_TM01: int = RomLayout.ITEM_TM01
const ITEM_HM01: int = RomLayout.ITEM_HM01
## `cp TM01` needs no ceiling on hardware because an item number is a byte. A
## defined item is not one: Gen2ContentOverlay.FIRST_MOD_NUMBER is 256, so
## without this every mod item read as a TM, and as an HM.
const ITEM_BYTE_MAX: int = RomLayout.ITEM_BYTE_MAX

## Eight bytes of learnable flags on each species, one bit per TMNUM, indexed by
## the entry's own zero-based place in TMHMMoves.
const TMHM_FLAG_BYTES: int = RomLayout.TMHM_BYTES


## AskTeachTMHM's first test, `cp TM01` before anything else: an item below TM01
## is not a TM or HM and the prompt never appears.
static func is_tm_hm(item: int) -> bool:
	return item >= ITEM_TM01 and item <= ITEM_BYTE_MAX


## IsHM, which TeachTMHM asks before ConsumeTM: an HM is never used up.
static func is_hm(item: int) -> bool:
	return item >= ITEM_HM01 and item <= ITEM_BYTE_MAX


## GetTMHMItemMove: the move [param item] teaches, or 0 when it is not a TM/HM
## this cartridge carries.
static func move_for_item(data: GameData, item: int) -> int:
	if data == null or not is_tm_hm(item):
		return 0
	var number: int = RomLayout.tmhm_number_for_item(item, data.tmhm_moves().size())
	return data.tmhm_move(number)


## CanLearnTMHMMove: the species' own flag bit for the TM/HM that teaches
## [param move]. A move no TM/HM teaches answers false, matching the source's
## `.end` branch, which returns c = 0 after walking off the end of TMHMMoves.
static func can_learn(data: GameData, species: int, move: int) -> bool:
	if data == null:
		return false
	var number: int = data.tmhm_number_for_move(move)
	if number < 1:
		return false
	var flags: Array = data.species(species).get("tmhm", [])
	if flags.size() < TMHM_FLAG_BYTES:
		return false
	# SmallFarFlagAction with d = 0: byte index >> 3, then bit index & 7 counted
	# from the *low* bit, since it shifts 1 left that many times.
	var index: int = number - 1
	var byte: int = int(flags[index >> 3])
	return (byte & (1 << (index & 7))) != 0


## KnowsMove (engine/pokemon/knows_move.asm), which TeachTMHM asks after
## compatibility and before LearnMove: all four slots, zeros included, though a
## zero can never match a real move.
static func knows_move(moves: Array, move: int) -> bool:
	return moves.has(move)


## LearnMove's own first step: the first empty move slot, or -1 when all four are
## taken and the source would open ForgetMove instead.
static func first_empty_slot(moves: Array) -> int:
	for slot: int in moves.size():
		if int(moves[slot]) == 0:
			return slot
	return -1


## AskTeachTMHM's two texts, BootedTMText/BootedHMText then ContainedMoveText,
## as the one prompt this project shows before its yes/no. The source prints them
## as two boxes; the wording is verbatim.
static func teach_prompt(data: GameData, item: int) -> Dictionary:
	var move: int = move_for_item(data, item)
	if move <= 0:
		return {"ok": false, "reason": &"not_a_tm_hm", "item": item}
	var move_name: String = String(data.move(move).get("name", "MOVE"))
	var booted: String = "Booted up an HM." if is_hm(item) else "Booted up a TM."
	return {
		"ok": true,
		"item": item,
		"move": move,
		"move_name": move_name,
		"hm": is_hm(item),
		"text": "%s It contained %s. Teach %s to a #MON?" % [booted, move_name, move_name],
	}
