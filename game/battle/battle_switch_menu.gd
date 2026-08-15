class_name Gen2BattleSwitchMenu
extends RefCounted

## `PickSwitchMonInBattle` and `ForcePickSwitchMonInBattle`
## (`engine/battle/core.asm`).
##
## Three callers, one list. `OfferSwitch`'s YES can be backed out of; Baton Pass
## reaches `ForcePickPartyMonInBattle`, which cannot and answers a refusal with
## `SFX_WRONG` and the list again; `ForcePlayerMonChoice` is that forced list one
## wrapper lower, so it makes no `SwitchMonAlreadyOut` check, which costs nothing
## because `CheckIfCurPartyMonIsFitToFight` refuses the fainted slot first. Both
## wrap `PickPartyMonInBattle` and its two refusals.
##
## Scene-free: [Gen2PartyMenuPage] draws the rows and the battle screen owns the
## presses. `SetUpBattlePartyMenu` goes through `InitPartyMenuWithCancel`, so
## CANCEL is a row in both variants and the forced one refuses rather than drops
## it.

## `PartyMenu2DMenuData`'s `_2DMENU_WRAP_UP_DOWN`, its only movement flag.
const WRAPS: bool = true

## `InitPartyMenuWithCancel`'s `wMenuCursorY` 1: the first member.
const DEFAULT_CURSOR: int = 0

## `ForcePickPartyMonInBattle`'s refusal and `PartyMenuSelect`'s exits.
const SFX_WRONG: int = 0x19
const SFX_READ_TEXT_2: int = 0x08

## What [method confirm] and [method cancel] answer with.
const CHOSEN: StringName = &"chosen"
const CANCELLED: StringName = &"cancelled"
const ALREADY_OUT: StringName = &"already_out"
const NO_ENERGY: StringName = &"no_energy"
const CANNOT_CANCEL: StringName = &"cannot_cancel"

## One row per party member, in party order:
## `{index, species, item, name, level, hp, max_hp, status, fainted}`, which is
## exactly what [Gen2PartyMenuPage] draws and its icon needs.
var rows: Array = []

## `ForcePickSwitchMonInBattle` rather than `PickSwitchMonInBattle`.
var forced: bool = false

## What `SwitchMonAlreadyOut` compares against.
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
			"species": mon.species,
			"item": mon.item,
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


## `_2DMENU_WRAP_UP_DOWN` over one column.
func move(delta: int) -> bool:
	if delta == 0 or item_count() <= 1:
		return false
	cursor = wrapi(cursor + delta, 0, item_count())
	return true


## `PartyMenuSelect` returning the row, then the two checks over it; a refusal
## leaves the list standing (`jr z, .loop`, `jr c, .pick`).
func confirm() -> Dictionary:
	if is_cancel(cursor):
		return cancel()
	if cursor < 0 or cursor >= rows.size():
		return {"result": CANNOT_CANCEL, "sfx": SFX_WRONG}
	var row: Dictionary = rows[cursor]
		# `BattleText_AnEGGCantBattle` is unreachable: a battle party here holds
		# only Pokémon that fight.
	if bool(row.get("fainted", false)):
		return {"result": NO_ENERGY, "text": no_energy_text()}
	if int(row.get("index", -1)) == active:
		return {"result": ALREADY_OUT, "text": already_out_text(String(row.get("name", "")))}
	return {"result": CHOSEN, "index": int(row.get("index", -1))}


## B and the CANCEL row both set carry, which `ForcePickPartyMonInBattle`
## swallows.
func cancel() -> Dictionary:
	if forced:
		return {"result": CANNOT_CANCEL, "sfx": SFX_WRONG}
	return {"result": CANCELLED}


## `PartyMenuStrings`' `WhichPKMNString`, which `PARTYMENUACTION_SWITCH` picks.
static func prompt_text() -> String:
	return "Which PKMN?"


## `PlacePartyNicknames`' `.CancelString`, two columns left of the nicknames.
static func cancel_label() -> String:
	return "CANCEL"


## `BattleText_TheresNoWillToBattle`.
static func no_energy_text() -> String:
	return "There's no will to battle!"


## `BattleText_MonIsAlreadyOut`.
static func already_out_text(name: String) -> String:
	return "%s is already out." % name


## `AskUseNextPokemon`'s question, wild battles only.
static func use_next_text() -> String:
	return "Use next PKMN?"


## `BattleText_EnemyIsAboutToUseWillPlayerChangeMon`, asked before the trainer's
## Pokémon is out. [param trainer] is `Battle_GetTrainerName`'s.
static func offer_text(trainer: String, mon: String, player: String) -> String:
	return "%s is about to use %s. Will %s change PKMN?" % [trainer, mon, player]
