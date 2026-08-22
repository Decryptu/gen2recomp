class_name Gen2MoveTutor
extends RefCounted

## `MoveTutor` and `CheckCanLearnMoveTutorMove` (`engine/events/move_tutor.asm`),
## the rules half. [Gen2MoveTutorScreen] is the routine and
## [method Gen2WorldPartyHost.teach_tutor_move] owns the transaction.
##
## Crystal only: `TMHMMoves` ends at HM07 on both Gold and Silver, so
## [method move_for_value] answers 0 there and no map script reaches the special
## anyway.

## constants/script_constants.asm's MOVETUTOR_* run, which the map's own
## `verticalmenu` leaves in wScriptVar. Its fourth row is CANCEL, which the
## script branches away from before the special.
const VALUE_FLAMETHROWER: int = 1
const VALUE_THUNDERBOLT: int = 2
const VALUE_ICE_BEAM: int = 3

## `.quit`'s own `xor a` and `.cancel`'s `ld a, -1`, as the byte wScriptVar
## holds. The map script reads only `ifequal FALSE`, so a cancelled list and an
## incompatible party both reach `.Incompatible`.
const SCRIPT_VALUE_LEARNED: int = 0
const SCRIPT_VALUE_CANCELLED: int = 0xFF

## `constants/sfx_constants.asm`'s SFX_WRONG, which `.can_learn`'s else branch
## plays in front of `TMHMNotCompatibleText`.
const SFX_WRONG: int = 0x2E


## `.GetMoveTutorMove`. MT01_MOVE through MT03_MOVE are TMHMMoves entries
## `NUM_TMS + NUM_HMS + 1` and up, so the move comes off the imported table
## rather than from a pinned move number, and a cartridge without the three rows
## answers 0.
static func move_for_value(data: GameData, value: int) -> int:
	if data == null:
		return 0
	## `cp MOVETUTOR_FLAMETHROWER` and `cp MOVETUTOR_THUNDERBOLT`, and anything
	## else falls through to ICE_BEAM.
	var tutor: int = clampi(value, VALUE_FLAMETHROWER, VALUE_ICE_BEAM) \
		if value in [VALUE_FLAMETHROWER, VALUE_THUNDERBOLT] else VALUE_ICE_BEAM
	return data.tmhm_move(RomLayout.TMHM_TM_COUNT + RomLayout.TMHM_HM_COUNT + tutor)
