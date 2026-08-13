class_name Gen2BattleSwitchMenu
extends RefCounted

## Choosing who comes in next, from inside a battle
## (`PickSwitchMonInBattle` and `ForcePickSwitchMonInBattle`,
## `engine/battle/core.asm`).
##
## Three callers, one list. `OfferSwitch`'s YES reaches the first, which the
## player can back out of; Baton Pass reaches the second through
## `ForcePickPartyMonInBattle`, which cannot be backed out of and answers a
## refusal with `SFX_WRONG` and the list again. `ForcePlayerMonChoice`, the
## replacement after a faint, is that same forced list one wrapper lower: it
## stops at `ForcePickPartyMonInBattle` and so makes no `SwitchMonAlreadyOut`
## check, which costs nothing because the slot it would refuse holds the Pokémon
## that just fainted and `CheckIfCurPartyMonIsFitToFight` refuses it first.
##
## Both wrap `PickPartyMonInBattle`, so both make the same two checks on the row
## that was chosen and print the same two lines:
##
## - `CheckIfCurPartyMonIsFitToFight`: a fainted Pokémon prints
##   `BattleText_TheresNoWillToBattle`;
## - `SwitchMonAlreadyOut`: the Pokémon already standing prints
##   `BattleText_MonIsAlreadyOut`.
##
## Scene-free: the rows and the cursor rules live here, [Gen2PartyMenuPage] draws
## them and the battle screen owns the presses. `SetUpBattlePartyMenu` always
## goes through `InitPartyMenuWithCancel`, so CANCEL is a row in both variants;
## in the forced one choosing it is refused rather than absent.

## `PartyMenu2DMenuData`'s `_2DMENU_WRAP_UP_DOWN`, which is the only movement
## flag the party menu sets: the list wraps and there is one column.
const WRAPS: bool = true

## `InitPartyMenuWithCancel` writes `wMenuCursorY` 1, which is the first member.
const DEFAULT_CURSOR: int = 0

## `SFX_WRONG`, which `ForcePickPartyMonInBattle` plays when the pick it cannot
## refuse is refused anyway, and `SFX_READ_TEXT_2`, which `PartyMenuSelect` plays
## on both of its own ways out (`constants/sfx_constants.asm`).
const SFX_WRONG: int = 0x19
const SFX_READ_TEXT_2: int = 0x08

## What [method confirm] and [method cancel] answer with.
const CHOSEN: StringName = &"chosen"
const CANCELLED: StringName = &"cancelled"
const ALREADY_OUT: StringName = &"already_out"
const NO_ENERGY: StringName = &"no_energy"
const CANNOT_CANCEL: StringName = &"cannot_cancel"

## One row per party member, in party order:
## `{index, name, level, hp, max_hp, status, fainted}`. [Gen2PartyMenuPage] draws
## exactly these fields and nothing reads the battle behind them.
var rows: Array = []

## `ForcePickSwitchMonInBattle` rather than `PickSwitchMonInBattle`.
var forced: bool = false

## The party slot already on the field, which `SwitchMonAlreadyOut` compares
## against.
var active: int = -1

## Zero-based over [method item_count], the CANCEL row last.
var cursor: int = DEFAULT_CURSOR


static func for_party(party: Gen2Party, is_forced: bool = false) -> Gen2BattleSwitchMenu:
	var menu := Gen2BattleSwitchMenu.new()
	menu.forced = is_forced
	if party == null:
		return menu
	menu.active = party.active
	for index: int in party.size():
		var mon: Gen2BattleMon = party.at(index)
		if mon == null:
			continue
		menu.rows.append({
			"index": index,
			"name": mon.name_text(),
			"level": mon.level,
			"hp": mon.hp,
			"max_hp": mon.max_hp(),
			"status": mon.status,
			"fainted": mon.is_fainted(),
		})
	return menu


## `w2DMenuNumRows`: the party plus CANCEL.
func item_count() -> int:
	return rows.size() + 1


func is_cancel(index: int) -> bool:
	return index == rows.size()


## `_2DMENU_WRAP_UP_DOWN` over one column. Answers whether the cursor moved,
## which it always does on a list of more than one row.
func move(delta: int) -> bool:
	if delta == 0 or item_count() <= 1:
		return false
	cursor = wrapi(cursor + delta, 0, item_count())
	return true


## A is `PartyMenuSelect` returning the row, then `PickPartyMonInBattle`'s and
## `PickSwitchMonInBattle`'s two checks over it. A refusal leaves the list
## standing, which is what both `jr z, .loop` and `jr c, .pick` do.
func confirm() -> Dictionary:
	if is_cancel(cursor):
		return cancel()
	if cursor < 0 or cursor >= rows.size():
		return {"result": CANNOT_CANCEL, "sfx": SFX_WRONG}
	var row: Dictionary = rows[cursor]
	# The source also refuses an EGG (`BattleText_AnEGGCantBattle`). A battle
	# party here is built from Pokémon that fight, so that branch has no way to
	# be reached and is not modelled.
	if bool(row.get("fainted", false)):
		return {"result": NO_ENERGY, "text": no_energy_text()}
	if int(row.get("index", -1)) == active:
		return {"result": ALREADY_OUT, "text": already_out_text(String(row.get("name", "")))}
	return {"result": CHOSEN, "index": int(row.get("index", -1))}


## B, and the CANCEL row, which `PartyMenuSelect` sets carry for alike.
## `ForcePickPartyMonInBattle` swallows that carry, so the forced list refuses.
func cancel() -> Dictionary:
	if forced:
		return {"result": CANNOT_CANCEL, "sfx": SFX_WRONG}
	return {"result": CANCELLED}


## `PartyMenuStrings`' `WhichPKMNString`, which `PARTYMENUACTION_SWITCH` picks
## and `PlacePartyMenuText` prints in the box along the bottom.
static func prompt_text() -> String:
	return "Which PKMN?"


## `PlacePartyNicknames`' own `.CancelString`, printed two columns left of the
## nicknames on the row below the last one.
static func cancel_label() -> String:
	return "CANCEL"


## `BattleText_TheresNoWillToBattle`.
static func no_energy_text() -> String:
	return "There's no will to battle!"


## `BattleText_MonIsAlreadyOut`.
static func already_out_text(name: String) -> String:
	return "%s is already out." % name


## `BattleText_UseNextMon`, the question `AskUseNextPokemon` puts up over the
## same yes/no box `OfferSwitch` uses. Wild battles only: a trainer battle
## returns from the routine before it prints.
static func use_next_text() -> String:
	return "Use next PKMN?"


## `BattleText_EnemyIsAboutToUseWillPlayerChangeMon`, the question `OfferSwitch`
## puts up before the trainer's Pokémon is on the field. [param trainer] is
## `Battle_GetTrainerName`'s answer and [param mon] the one about to come in.
static func offer_text(trainer: String, mon: String, player: String) -> String:
	return "%s is about to use %s. Will %s change PKMN?" % [trainer, mon, player]
