class_name Gen2MoveForget
extends RefCounted

## engine/pokemon/learn.asm's `LearnMove` and `ForgetMove`. Shared here because
## `LearnMove` is reached from both `TeachTMHM` and a level-up in battle, so
## neither [Gen2WorldPartyHost] nor [Gen2Battle] owns it. Identical in both pins.
##
## The order the source asks in: `AskForgetMoveText`'s yes/no, then
## `MoveAskForgetText` and the move list, where an HM row prints
## `MoveCantForgetHMText` and loops rather than cancelling. B or a no reaches
## `LearnMove.cancel`, ending in `DidNotLearnMoveText` or asking again.

## How many moves a Pokémon can know at once, NUM_MOVES.
const MOVE_SLOTS: int = 4

## home/hm_moves.asm's `IsHMMove.HMMoves`, in source order. Seven, against the
## four [constant Gen2WorldFieldMove.FIELD_MOVES] the overworld acts on:
## forgetting is gated on every HM, not on the ones with a field effect here.
const HM_MOVES: Array[int] = [
	0x0F,  # CUT
	0x13,  # FLY
	0x39,  # SURF
	0x46,  # STRENGTH
	0x94,  # FLASH
	0x7F,  # WATERFALL
	0xFA,  # WHIRLPOOL
]


## `IsHMMove`: an HM's move, which `ForgetMove` refuses to give up.
static func is_hm_move(move: int) -> bool:
	return HM_MOVES.has(move)


## `ListMoves`' rows: it stops at the first zero, so a padded slot is not listed.
## `forgettable` is the `IsHMMove` test the menu makes on confirm, resolved up
## front so a screen can mark the row rather than only refuse it.
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


## `Text_1_2_and_Poof` then `_MoveForgotText`, as one line where the source
## shows two: the SFX_SWITCH_POKEMON between them has no route on either screen.
static func forgot_text(mon_name: String, old_move_name: String) -> String:
	return "1, 2 and… Poof! %s forgot %s. And…" % [mon_name, old_move_name]


## `LearnedMoveText`, which `LearnMove.learned` prints on either path into it.
static func learned_text(mon_name: String, move_name: String) -> String:
	return "%s learned %s!" % [mon_name, move_name]


## `MoveCantForgetHMText`. The list stays open, since `.hmmove` is `jr .loop`.
static func cant_forget_hm_text() -> String:
	return "HM moves can't be forgotten now."
