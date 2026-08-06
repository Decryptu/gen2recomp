class_name Gen2WorldStartMenu
extends RefCounted

## Scene-free model of the cartridge start menu (engine/menus/start_menu.asm).
##
## `StartMenu.SetUpMenuItems` builds its list by appending items in a fixed
## source order, skipping only the ones its own gate says are not present yet
## (Pokedex behind wStatusFlags/STATUSFLAGS_POKEDEX_F, Pokemon behind a
## non-zero wPartyCount, Pokegear behind wPokegearFlags/POKEGEAR_OBTAINED_F).
## Everything else it always appends. This project does not yet have a dex
## screen, a trainer card or an options screen, so those three entries are
## still built in their source position, marked unavailable rather than
## omitted, so the list shape does not silently change out from under a
## future implementation of any of them. Bug Contest and link-mode branches
## (STARTMENUITEM_QUIT, the contest status box) do not apply because this
## project has neither system, which is why QUIT never appears here at all:
## the source's own gate for it is never true.
##
## `STATICMENU_WRAP` is source flag data on `.MenuData`, so the cursor wraps
## at both ends the same way a cached cartridge menu does.

## constants/engine_flags.asm: ENGINE_POKEGEAR = 4, ENGINE_POKEDEX = 11. Both
## indices are identical in pokecrystal and pokegold (unlike the badge and
## Goldenrod merchant flags further down that table, which pokecrystal's extra
## ENGINE_MOBILE_SYSTEM entry shifts by one), so no profile split is needed
## for this menu's gating.
const ENGINE_POKEGEAR: int = 4
const ENGINE_POKEDEX: int = 11

const ITEM_POKEDEX: StringName = &"pokedex"
const ITEM_POKEMON: StringName = &"pokemon"
const ITEM_PACK: StringName = &"pack"
const ITEM_POKEGEAR: StringName = &"pokegear"
const ITEM_PLAYER: StringName = &"player"
const ITEM_SAVE: StringName = &"save"
const ITEM_OPTION: StringName = &"option"
const ITEM_EXIT: StringName = &"exit"

var cursor: int = 0
var _items: Array = []


## `party_count`, `pokedex_obtained` and `pokegear_obtained` come from the
## live world (party summary and engine flags 11 and 4); this stays scene-free
## the same way Gen2WorldMenu does. `previous_cursor` mirrors the source's
## `wBattleMenuCursorPosition`, which survives a reopen after a submenu closes;
## it is clamped to the rebuilt list so a shrunk list cannot leave the cursor
## out of range.
static func build(
	party_count: int,
	pokedex_obtained: bool,
	pokegear_obtained: bool,
	previous_cursor: int = 0,
) -> Gen2WorldStartMenu:
	var menu := Gen2WorldStartMenu.new()
	var items: Array = []
	if pokedex_obtained:
		items.append(_entry(ITEM_POKEDEX, "Pokedex", false))
	if party_count > 0:
		items.append(_entry(ITEM_POKEMON, "Pokemon", true))
	items.append(_entry(ITEM_PACK, "Pack", true))
	if pokegear_obtained:
		items.append(_entry(ITEM_POKEGEAR, "Pokegear", true))
	items.append(_entry(ITEM_PLAYER, "Player", false))
	items.append(_entry(ITEM_SAVE, "Save", true))
	items.append(_entry(ITEM_OPTION, "Options", false))
	items.append(_entry(ITEM_EXIT, "Exit", true))
	menu._items = items
	menu.cursor = clampi(previous_cursor, 0, maxi(items.size() - 1, 0))
	return menu


## Convenience for a screen: reads party count from the live world's party
## summary (0 when no caller has set one yet, matching the source's empty
## party before Elm's lab) and both gating flags directly off Gen2WorldState.
static func from_world(world: Gen2WorldAPI, previous_cursor: int = 0) -> Gen2WorldStartMenu:
	if world == null or world.state == null:
		return Gen2WorldStartMenu.build(0, false, false, previous_cursor)
	var party_count: int = int(world.party_summary().get("count", 0))
	return Gen2WorldStartMenu.build(
		party_count,
		world.state.is_engine_flag_active(ENGINE_POKEDEX),
		world.state.is_engine_flag_active(ENGINE_POKEGEAR),
		previous_cursor,
	)


static func _entry(kind: StringName, label: String, available: bool) -> Dictionary:
	return {"kind": kind, "label": label, "available": available}


func items() -> Array:
	return _items.duplicate(true)


func size() -> int:
	return _items.size()


## Mirrors StartMenu's STATICMENU_WRAP: moving past either end lands on the
## opposite end rather than stopping.
func move(delta: int) -> bool:
	if _items.is_empty() or delta == 0:
		return false
	var next: int = cursor + signi(delta)
	if next < 0:
		next = _items.size() - 1
	elif next >= _items.size():
		next = 0
	cursor = next
	return true


func selected_item() -> Dictionary:
	if cursor < 0 or cursor >= _items.size():
		return {}
	return _items[cursor]


func selected_kind() -> StringName:
	return StringName(selected_item().get("kind", &""))


func selected_available() -> bool:
	return bool(selected_item().get("available", false))
