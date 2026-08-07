class_name Gen2MoveForget
extends RefCounted

## Giving up one of four moves to make room for a fifth
## (engine/pokemon/learn.asm's LearnMove and ForgetMove).
##
## `LearnMove` reaches `ForgetMove` from both of its callers: `TeachTMHM` for a
## TM or HM out of the pack, and a level-up in battle. So the tables and the
## wording live here rather than beside either one, and neither
## [Gen2WorldPartyHost] nor [Gen2Battle] owns the other's copy.
##
## Everything here is byte identical between the pins. learn.asm differs by one
## line, `bit B_PAD_B` against `bit B_BUTTON_F`, which is the same bit under two
## names; home/hm_moves.asm and the seven move numbers are identical.
##
## The order the source asks in, which both screens follow:
##
## 1. `AskForgetMoveText` and its yes/no. No returns carry, which is
##    `LearnMove.cancel`.
## 2. `MoveAskForgetText` and the move list. B is also `LearnMove.cancel`; an HM
##    row prints `MoveCantForgetHMText` and redisplays the list (`jr .loop`),
##    which is not a cancel.
## 3. `LearnMove.cancel` is `StopLearningMoveText` and its yes/no. Yes ends with
##    `DidNotLearnMoveText`; no returns to step 1.

## How many moves a Pokémon can know at once, NUM_MOVES.
const MOVE_SLOTS: int = 4

## home/hm_moves.asm's `IsHMMove.HMMoves`, in source order, from
## constants/move_constants.asm's hex comment column. Seven moves, which is a
## longer list than the four [constant Gen2WorldFieldMove.FIELD_MOVES] this
## project acts on in the overworld: forgetting is gated on every HM the
## cartridge has, not on the ones with a field effect here.
const HM_MOVES: Array[int] = [
	0x0F,  # CUT
	0x13,  # FLY
	0x39,  # SURF
	0x46,  # STRENGTH
	0x94,  # FLASH
	0x7F,  # WATERFALL
	0xFA,  # WHIRLPOOL
]


## `IsHMMove`: whether [param move] is one an HM teaches, and so one
## `ForgetMove` refuses to give up.
static func is_hm_move(move: int) -> bool:
	return HM_MOVES.has(move)


## The rows `ListMoves` draws, one per move the Pokémon actually knows.
##
## `ListMoves` stops at the first zero, so a padded slot is not listed; in
## practice `ForgetMove` is only reached with all four taken. `forgettable` is
## the `IsHMMove` test the menu makes on confirm, resolved up front so a screen
## can mark the row rather than only refuse it.
static func options(data: GameData, moves: Array) -> Array:
	var out: Array = []
	if data == null:
		return out
	for slot: int in mini(moves.size(), MOVE_SLOTS):
		var move: int = int(moves[slot])
		if move == 0:
			break
		out.append({
			"slot": slot,
			"move": move,
			"name": String(data.move(move).get("name", "MOVE")),
			"forgettable": not is_hm_move(move),
		})
	return out


## `AskForgetMoveText`. The source prints it as one box of three paragraphs.
static func ask_text(mon_name: String, move_name: String) -> String:
	return "%s is trying to learn %s. But %s can't learn more than four moves. Delete an older move to make room for %s?" % [
		mon_name, move_name, mon_name, move_name,
	]


## `MoveAskForgetText`, the heading over the move list.
static func which_text() -> String:
	return "Which move should be forgotten?"


## `StopLearningMoveText`, `LearnMove.cancel`'s own yes/no.
static func stop_text(move_name: String) -> String:
	return "Stop learning %s?" % move_name


## `DidNotLearnMoveText`, the end of a cancelled offer.
static func did_not_learn_text(mon_name: String, move_name: String) -> String:
	return "%s did not learn %s." % [mon_name, move_name]


## `Text_1_2_and_Poof` then `_MoveForgotText`, as the one line this project
## shows where the source shows two boxes and a pause. The SFX_SWITCH_POKEMON
## between them is a boundary: neither screen that reaches this has an SFX
## route.
static func forgot_text(mon_name: String, old_move_name: String) -> String:
	return "1, 2 and… Poof! %s forgot %s. And…" % [mon_name, old_move_name]


## `LearnedMoveText`, which `LearnMove.learned` prints on either path into it.
static func learned_text(mon_name: String, move_name: String) -> String:
	return "%s learned %s!" % [mon_name, move_name]


## `MoveCantForgetHMText`. The list stays open behind it, since the source's
## `.hmmove` branch is `jr .loop`.
static func cant_forget_hm_text() -> String:
	return "HM moves can't be forgotten now."
