class_name Gen2NameRater
extends RefCounted

## `engine/events/name_rater.asm`, the rules half.
##
## `_NameRater` is a straight line of text, question, party selection, text and
## naming screen; what needs a reading rather than a screen is which of its five
## endings a chosen party member reaches, and the three routines beside it that
## decide the last one. [Gen2NameRaterScreen] is the routine itself, on the
## overworld's own pump; this holds nothing and answers questions.
##
## Every string is the cartridge's, read through [method GameData.name_rater_text]
## off the ten `text_far` stubs `RomLayout.NAME_RATER_TEXT_ORDER` pins.

## `MON_NAME_LENGTH - 1`: how many characters a nickname holds before its `@`.
const NICKNAME_LENGTH: int = 10

## The five endings `.done` prints, by the stub each one loads into hl.
const ENDING_EGG: StringName = &"egg"
const ENDING_TRADED: StringName = &"perfect_name"
const ENDING_CANCEL: StringName = &"come_again"
const ENDING_FINISHED: StringName = &"finished"
const ENDING_SAME_NAME: StringName = &"same_name"


## `CheckIfMonIsYourOT`, which returns carry when the member was *not* caught by
## this trainer. Both halves are compared: the OT name and the two bytes of the
## trainer ID, so a traded member carrying the player's own name is still refused
## on its ID.
static func is_your_ot(mon: Gen2SaveMon, player_name: String, player_id: int) -> bool:
	if mon == null:
		return false
	return mon.original_trainer == player_name and mon.ot_id == player_id


## `IsNewNameEmpty`: an entry of nothing but spaces, or one that begins with the
## terminator, is treated as unchanged. The walk stops after
## [constant NICKNAME_LENGTH] characters, which is what the naming screen holds.
static func is_new_name_empty(entered: String) -> bool:
	for index: int in mini(entered.length(), NICKNAME_LENGTH):
		if entered[index] != " ":
			return false
	return true


## `CompareNewToOld`, which returns carry when the two names are the same.
## `GetNicknamenameLength` stops at [constant NICKNAME_LENGTH], so two names that
## differ only past that length compare equal here as they do on the cartridge.
static func is_same_name(entered: String, current: String) -> bool:
	return entered.substr(0, NICKNAME_LENGTH) == current.substr(0, NICKNAME_LENGTH)


## Which of `_NameRater`'s endings [param mon] reaches once it has been chosen,
## and whether the routine carries on to the naming screen. `&""` is the answer
## for a member that does, which is the only branch with anything left to do.
static func ending_for(mon: Gen2SaveMon, player_name: String, player_id: int) -> StringName:
	if mon == null:
		return ENDING_CANCEL
	if mon.is_egg:
		return ENDING_EGG
	if not is_your_ot(mon, player_name, player_id):
		return ENDING_TRADED
	return &""


## The ending a settled naming screen reaches, and the nickname to write with it.
## `.samename` covers both refusals and keeps the row's own name.
static func ending_for_entry(entered: String, current: String) -> Dictionary:
	var trimmed: String = entered.substr(0, NICKNAME_LENGTH)
	if is_new_name_empty(trimmed) or is_same_name(trimmed, current):
		return {"ending": ENDING_SAME_NAME, "nickname": current}
	return {"ending": ENDING_FINISHED, "nickname": trimmed}
