class_name Gen2WorldStartMenu
extends RefCounted

## Scene-free model of the cartridge start menu (engine/menus/start_menu.asm).
##
## `StartMenu.SetUpMenuItems` appends items in a fixed source order, skipping only
## what its own gate refuses: Pokedex behind wStatusFlags/STATUSFLAGS_POKEDEX_F,
## Pokemon behind a non-zero wPartyCount, Pokegear behind
## wPokegearFlags/POKEGEAR_OBTAINED_F.
##
## QUIT never appears because its Bug Contest and link-mode gate is never true
## here.
##
## Entries registered on `Gen2ModHost` are spliced in ahead of EXIT, so a mod can
## add a screen without reordering or removing anything the cartridge shipped.
##
## `STATICMENU_WRAP` is source flag data on `.MenuData`, so the cursor wraps at
## both ends like a cached cartridge menu.

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
## Not the cartridge's. Appears only when an installed mod registered a setting,
## so a player with no mods, or none that configure anything, sees the source
## menu exactly. It sits after OPTION and before the entries mods registered
## themselves, which keeps both additions in one block ahead of EXIT.
const ITEM_MODS: StringName = &"mods"

## What `SetUpMenuItems` gates each source entry on. An empty gate is always
## appended, matching the entries the source adds unconditionally.
const GATE_POKEDEX: StringName = &"pokedex"
const GATE_PARTY: StringName = &"party"
const GATE_POKEGEAR: StringName = &"pokegear"

## `SetUpMenuItems` in source order, as data rather than a run of appends, so the
## host's registered entries can be spliced in without the order becoming a
## question. EXIT stays last: it is what closes the menu, and the source never
## puts anything after it.
## The labels are `.PokedexString` and its siblings verbatim, which is what the
## box over the map prints. `#` is the charmap's own $54 and expands to "POKe";
## `<PLAYER>`, which the source's own `.StatusString` is, is filled in by
## [method build] because `PlaceString` reads `wPlayerName` for it.
const SOURCE_ENTRIES: Array[Dictionary] = [
	{"kind": ITEM_POKEDEX, "label": "#DEX", "available": true, "gate": GATE_POKEDEX},
	{"kind": ITEM_POKEMON, "label": "#MON", "available": true, "gate": GATE_PARTY},
	{"kind": ITEM_PACK, "label": "PACK", "available": true, "gate": &""},
	{"kind": ITEM_POKEGEAR, "label": "<POKE>GEAR", "available": true, "gate": GATE_POKEGEAR},
	{"kind": ITEM_PLAYER, "label": "<PLAYER>", "available": true, "gate": &""},
	{"kind": ITEM_SAVE, "label": "SAVE", "available": true, "gate": &""},
	{"kind": ITEM_OPTION, "label": "OPTION", "available": true, "gate": &""},
	{"kind": ITEM_EXIT, "label": "EXIT", "available": true, "gate": &""},
]

## `.Items`' third column, the one MENU ACCOUNT draws under the list
## (`.MenuDesc`), as imported. A mod's entry has none, which is what the empty
## answer means, and so does a cache imported before the run was.
var _descriptions: Dictionary = {}

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
	player_name: String = "",
) -> Gen2WorldStartMenu:
	var menu := Gen2WorldStartMenu.new()
	var passes: Dictionary = {
		GATE_POKEDEX: pokedex_obtained,
		GATE_PARTY: party_count > 0,
		GATE_POKEGEAR: pokegear_obtained,
	}
	var items: Array = []
	for entry: Dictionary in SOURCE_ENTRIES:
		var gate: StringName = StringName(entry.get("gate", &""))
		if not String(gate).is_empty() and not bool(passes.get(gate, false)):
			continue
		if entry["kind"] == ITEM_EXIT:
			if not Gen2ModHost.instance().option_mod_ids().is_empty():
				items.append(_entry(ITEM_MODS, "Mods", true))
			items.append_array(Gen2ModHost.instance().menu_entries(Gen2ModHost.MENU_START))
		var label: String = String(entry["label"])
		## `PlaceString` reads `wPlayerName` for `<PLAYER>`, so the STATUS row
		## says the player's own name and never those eight characters.
		## A world with no save selected has no name to read, which is a
		## screenshot tool or a test rather than a game: the row says PLAYER
		## rather than printing the marker's own characters.
		if entry["kind"] == ITEM_PLAYER:
			label = player_name if not player_name.is_empty() else "PLAYER"
		items.append(_entry(
			StringName(entry["kind"]), label, bool(entry["available"])
		))
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
	var menu: Gen2WorldStartMenu = Gen2WorldStartMenu.build(
		party_count,
		world.state.is_engine_flag_active(ENGINE_POKEDEX),
		world.state.is_engine_flag_active(ENGINE_POKEGEAR),
		previous_cursor,
		world.player_name(),
	)
	menu.load_descriptions(world.data)
	return menu


## `.MenuDesc`'s own strings, read out of the cache. Called by
## [method from_world]; a menu built by hand has none and answers empty, which is
## what a cache imported before the run does too.
func load_descriptions(data: GameData) -> void:
	_descriptions = {}
	if data == null:
		return
	for entry: Dictionary in _items:
		var kind: StringName = StringName(entry.get("kind", &""))
		var text: String = data.menu_description(kind)
		if not text.is_empty():
			## Kept as the two rows `.MenuDesc`'s own `next` places, since the
			## account block is ten tiles wide and no line of it fits on one.
			_descriptions[kind] = text


static func _entry(kind: StringName, label: String, available: bool) -> Dictionary:
	return {"kind": kind, "label": label, "available": available}


func items() -> Array:
	return _items.duplicate(true)


## `.MenuDesc`'s line for one entry, empty for an entry the cartridge has none
## for. The caller decides whether to draw it: MENU ACCOUNT is what
## `.IsMenuAccountOn` reads, and it is an option rather than a rule.
func description(kind: StringName) -> String:
	return String(_descriptions.get(kind, ""))


func selected_description() -> String:
	return description(selected_kind())


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
