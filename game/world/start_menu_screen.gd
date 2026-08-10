class_name Gen2StartMenuScreen
extends Control

## The overworld pause menu (engine/menus/start_menu.asm), presented as a
## window-resolution Control panel consistent with the mart, phone and PC
## storage overlays rather than the hardware `menu_coords` box.
##
## Pokedex, Pokemon and Pokegear are screens the world already owns
## (Gen2PokedexScreen, Gen2PartyScreen, the phone list on
## Gen2WorldServiceScreen), so this only reports the choice through
## [signal action_chosen]. Pack and Save live here as internal modes, the way
## Gen2WorldServiceScreen owns a mart mode beside its menu mode.

## Emitted for an available entry this screen does not own itself
## (Pokedex, Pokemon, Pokegear, Player); the caller opens the matching screen.
signal action_chosen(kind: StringName)
## Emitted on Exit or cancel from the top-level list.
signal closed

enum Mode {
	LIST, PACK, PACK_ITEM, PACK_TEACH, PACK_TARGET,
	PACK_FORGET_ASK, PACK_FORGET, PACK_STOP_LEARNING,
	PACK_RESULT, SAVE_CONFIRM, OPTIONS, MODS, MOD_OPTIONS,
}

## engine/items/pack.asm's own refusal texts, verbatim from data/text/common_2.asm.
const OAK_TEXT: String = "OAK: This isn't the time to use that!"
const NO_MON_TEXT: String = "You don't have a #MON!"

const PANEL: Color = Color("#14233a")
const BORDER: Color = Color("#4f6f9e")
const SCRIM: Color = Color(0.02, 0.04, 0.08, 0.78)
const TEXT: Color = Color("#f4f7fb")
const MUTED: Color = Color("#9eacc0")
const ACCENT: Color = Color("#f3c969")
const SUCCESS: Color = Color("#7bd89a")
const ERROR: Color = Color("#ef8a8a")

var _world: Gen2WorldAPI = null
var _data: GameData = null
var _save_action: Callable = Callable()
var _mode: Mode = Mode.LIST
var _menu: Gen2WorldStartMenu = null

var _pack_pockets: Array = []
var _pack_pocket_index: int = 0
var _pack_cursor: int = 0
var _pack_save: Gen2SaveData = null
var _pack_persist: bool = true
var _item_actions: Array = []
var _item_cursor: int = 0
var _target_cursor: int = 0
var _pack_result: String = ""
var _pack_result_ok: bool = false
## AskTeachTMHM's resolved prompt, held while its yes/no is on screen, and
## whether the party list that follows is ChooseMonToLearnTMHM's rather than
## `.Party`'s.
var _teach_prompt: Dictionary = {}
var _teach_cursor: int = 0
var _teaching: bool = false

## ForgetMove's list and the two yes/no boxes around it. The party index is held
## because the second teach_tm_hm() call has to name the same Pokémon the first
## one refused.
var _forget_moves: Array = []
var _forget_cursor: int = 0
var _forget_party_index: int = -1
var _forget_confirm_cursor: int = 0

var _save_cursor: int = 0
var _save_result_shown: bool = false

var _options_menu: Gen2WorldOptionsMenu = null

## The MODS entry: which mod is being configured and where each cursor sits.
## The rows themselves are the host's registrations, read fresh on every render
## so a value changed from the launcher is never shown stale.
var _mod_ids: Array[StringName] = []
var _mod_cursor: int = 0
var _mod_id: StringName = &""
var _mod_option_cursor: int = 0

var _title: Label = null
var _summary: Label = null
var _options: VBoxContainer = null
var _status: Label = null
var _footer: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if _menu != null:
		_open_list_mode()


## `save_action` is called with no arguments and must return a Dictionary
## shaped like Gen2WorldScreen.persist_world_snapshot()'s result (an "ok" key,
## with "reason" on failure). Kept as a Callable so this screen does not need
## to know how a snapshot is written or where saves live.
##
## Mirrors Gen2BoxScreen.set_context(): open() may be called before or after this
## node enters the tree, so building the option list defers to _ready() until
## _title/_options exist, and runs immediately here otherwise.
func open(world: Gen2WorldAPI, data: GameData, save_action: Callable, previous_cursor: int = 0) -> bool:
	_world = world
	_data = data
	_save_action = save_action
	if _world == null or _data == null:
		return false
	_menu = Gen2WorldStartMenu.from_world(_world, previous_cursor)
	if is_inside_tree() and _options != null:
		_open_list_mode()
	return true


## The save the pack's USE applies to, and whether that write reaches disk.
## Optional: without it the pack still lists items and refuses to use one, which
## is what a screenshot tool driving an injected world gets.
##
## Passed rather than wrapped in a Callable the way `save_action` is, because
## using an item is a Gen2WorldPartyHost transaction over this same save, not a
## world-snapshot write only the world screen knows how to do.
func set_party_context(save: Gen2SaveData, persist: bool = true) -> void:
	_pack_save = save
	_pack_persist = persist


## The list model's cursor, so a caller can carry it into the next open() the
## way the source's wBattleMenuCursorPosition survives a reopen.
func cursor() -> int:
	return _menu.cursor if _menu != null else 0


func handle_button(button: int) -> bool:
	if Gen2Button.is_direction(button):
		_move(Gen2Button.vector(button))
		return true
	match button:
		Gen2Button.A:
			_confirm()
			return true
		Gen2Button.B:
			_cancel()
			return true
	return false


func _move(direction: Vector2i) -> void:
	match _mode:
		Mode.LIST:
			## The source's .MenuData omits STATICMENU_ENABLE_LEFT_RIGHT, so
			## only vertical input moves the top-level list.
			if direction.x == 0 and _menu != null and _menu.move(direction.y):
				_render_list()
		Mode.PACK:
			if direction.x != 0:
				_cycle_pocket(direction.x)
			elif direction.y != 0:
				_move_pack_cursor(direction.y)
		Mode.PACK_ITEM:
			if direction.y != 0 and not _item_actions.is_empty():
				_item_cursor = wrapi(_item_cursor + signi(direction.y), 0, _item_actions.size())
				_render_item_menu()
		Mode.PACK_TEACH:
			if direction.y != 0 or direction.x != 0:
				_teach_cursor = 1 - _teach_cursor
				_render_teach()
		Mode.PACK_FORGET_ASK:
			if direction.y != 0 or direction.x != 0:
				_forget_confirm_cursor = 1 - _forget_confirm_cursor
				_render_forget_ask()
		Mode.PACK_FORGET:
			## w2DMenuNumCols is 1, so only vertical input moves the move list.
			if direction.y != 0 and not _forget_moves.is_empty():
				_forget_cursor = wrapi(
					_forget_cursor + signi(direction.y), 0, _forget_moves.size()
				)
				_render_forget_list()
		Mode.PACK_STOP_LEARNING:
			if direction.y != 0 or direction.x != 0:
				_forget_confirm_cursor = 1 - _forget_confirm_cursor
				_render_stop_learning()
		Mode.PACK_TARGET:
			if direction.y != 0 and not _party_targets().is_empty():
				_target_cursor = wrapi(
					_target_cursor + signi(direction.y), 0, _party_targets().size()
				)
				_render_targets()
		Mode.SAVE_CONFIRM:
			if not _save_result_shown and (direction.x != 0 or direction.y != 0):
				_save_cursor = 1 - _save_cursor
				_render_save_confirm()
		Mode.OPTIONS:
			if direction.y != 0:
				_options_menu.move(direction.y)
				_render_options_menu()
			elif direction.x != 0 and _options_menu.adjust(direction.x):
				_persist_options()
				_render_options_menu()
		Mode.MODS:
			if direction.y != 0 and not _mod_ids.is_empty():
				_mod_cursor = wrapi(_mod_cursor + signi(direction.y), 0, _mod_ids.size())
				_render_mods()
		Mode.MOD_OPTIONS:
			var rows: Array = _mod_options()
			if rows.is_empty():
				return
			if direction.y != 0:
				_mod_option_cursor = wrapi(
					_mod_option_cursor + signi(direction.y), 0, rows.size()
				)
				_render_mod_options()
			elif direction.x != 0:
				_adjust_mod_option(rows, direction.x)


func _confirm() -> void:
	match _mode:
		Mode.LIST:
			_confirm_list()
		Mode.PACK:
			if not _current_pocket_items().is_empty():
				_open_item_mode()
		Mode.PACK_ITEM:
			_confirm_item_action()
		Mode.PACK_TEACH:
			_confirm_teach()
		Mode.PACK_FORGET_ASK:
			_confirm_forget_ask()
		Mode.PACK_FORGET:
			_confirm_forget()
		Mode.PACK_STOP_LEARNING:
			_confirm_stop_learning()
		Mode.PACK_TARGET:
			if _teaching:
				_teach_selected_item(_target_cursor)
			else:
				_use_selected_item(_target_cursor)
		Mode.PACK_RESULT:
			_open_pack_mode(false)
		Mode.SAVE_CONFIRM:
			_confirm_save()
		## Options_Cancel is the only handler that reads A.
		Mode.OPTIONS:
			if _options_menu.is_cancel():
				_open_list_mode()
		Mode.MODS:
			if _mod_cursor >= 0 and _mod_cursor < _mod_ids.size():
				_open_mod_options_mode(_mod_ids[_mod_cursor])
		## Every row is a ladder read with left and right, so A does nothing,
		## the way it does on the cartridge's own value rows.
		Mode.MOD_OPTIONS:
			pass


func _cancel() -> void:
	match _mode:
		Mode.LIST:
			closed.emit()
		Mode.PACK:
			_open_list_mode()
		Mode.PACK_ITEM, Mode.PACK_RESULT, Mode.PACK_TEACH:
			_open_pack_mode(false)
		## B at ForgetMove's ask is YesNoBox's no, and B in the move list is its
		## own .cancel's scf. Both are the carry LearnMove.cancel tests.
		Mode.PACK_FORGET_ASK, Mode.PACK_FORGET:
			_open_stop_learning()
		## No to "Stop learning?" is `jp .loop`, back to ForgetMove's ask.
		Mode.PACK_STOP_LEARNING:
			_open_forget_ask()
		Mode.PACK_TARGET:
			_open_item_mode()
		Mode.SAVE_CONFIRM:
			_open_list_mode()
		## `_Option.joypad_loop` exits on PAD_START | PAD_B from any row.
		Mode.OPTIONS, Mode.MODS:
			_open_list_mode()
		Mode.MOD_OPTIONS:
			_open_mods_mode()


func _confirm_list() -> void:
	if _menu == null or _menu.size() == 0:
		return
	if not _menu.selected_available():
		_status.text = "%s is not available yet." % String(_menu.selected_item().get("label", ""))
		_status.add_theme_color_override("font_color", MUTED)
		return
	match _menu.selected_kind():
		Gen2WorldStartMenu.ITEM_PACK:
			_open_pack_mode()
		Gen2WorldStartMenu.ITEM_SAVE:
			_open_save_confirm_mode()
		Gen2WorldStartMenu.ITEM_OPTION:
			_open_options_mode()
		Gen2WorldStartMenu.ITEM_MODS:
			_open_mods_mode()
		Gen2WorldStartMenu.ITEM_EXIT:
			closed.emit()
		Gen2WorldStartMenu.ITEM_POKEDEX, Gen2WorldStartMenu.ITEM_POKEMON, \
		Gen2WorldStartMenu.ITEM_POKEGEAR, Gen2WorldStartMenu.ITEM_PLAYER:
			action_chosen.emit(_menu.selected_kind())
		_:
			# A Gen2ModHost-registered entry. Its handler is what made it
			# available at all, so this cannot reach an entry without one.
			var handler: Variant = _menu.selected_item().get("handler", null)
			if handler is Callable:
				(handler as Callable).call()


func _open_list_mode() -> void:
	_mode = Mode.LIST
	_title.text = "MENU"
	_summary.text = ""
	_status.text = ""
	_footer.text = "D-pad: move    A: choose    B: close"
	_render_list()


func _render_list() -> void:
	if _menu == null:
		return
	_render_options(_menu.items(), _menu.cursor, func(entry: Dictionary) -> String:
		var label: String = String(entry.get("label", ""))
		return label if bool(entry.get("available", false)) else "%s (unavailable)" % label
	)


## `StartMenu_Option`'s `farcall Option`. The model edits the shared
## [Gen2OptionsStore] object, so the launcher's settings card and this menu can
## never disagree about a value, which is the same reason the cartridge block
## exists at all.
func _open_options_mode() -> void:
	_mode = Mode.OPTIONS
	_options_menu = Gen2WorldOptionsMenu.build(Gen2OptionsStore.current())
	_title.text = "OPTION"
	_summary.text = ""
	_status.text = ""
	_footer.text = "Up and down: move    Left and right: change    B: back"
	_render_options_menu()


## Written on every change, matching the launcher card and the cartridge, which
## commits each press to `wOptions` rather than on the way out.
func _persist_options() -> void:
	if Gen2OptionsStore.save(_options_menu.options()):
		return
	_status.text = "The options file could not be written."
	_status.add_theme_color_override("font_color", ERROR)


func _render_options_menu() -> void:
	_render_options(_options_menu.rows(), _options_menu.cursor, func(row: Dictionary) -> String:
		var value: String = String(row.get("value", ""))
		var label: String = String(row.get("label", ""))
		return label if value.is_empty() else "%s    %s" % [label, value]
	)


## The MODS entry: the mods that registered a setting, one row each. Only
## reachable when there is at least one, which is what puts the entry in the list
## at all.
func _open_mods_mode() -> void:
	_mode = Mode.MODS
	_mod_ids = Gen2ModHost.instance().option_mod_ids()
	_mod_cursor = clampi(_mod_cursor, 0, maxi(_mod_ids.size() - 1, 0))
	_title.text = "MODS"
	_summary.text = ""
	_status.text = ""
	_footer.text = "Up and down: move    A: choose    B: back"
	_render_mods()


func _render_mods() -> void:
	_render_options(_mod_ids, _mod_cursor, func(id: StringName) -> String:
		return _mod_name(id)
	)


## The name the player installed, falling back to the id for a mod registered
## without a manifest, which is what a test or the built-in host does.
func _mod_name(id: StringName) -> String:
	for manifest: Gen2ModManifest in Gen2ModHost.instance().manifests():
		if manifest.id == id:
			return manifest.name
	return String(id)


func _open_mod_options_mode(id: StringName) -> void:
	_mode = Mode.MOD_OPTIONS
	_mod_id = id
	_mod_option_cursor = 0
	_title.text = _mod_name(id).to_upper()
	_summary.text = ""
	_status.text = ""
	_footer.text = "Up and down: move    Left and right: change    B: back"
	_render_mod_options()


## Read from the host on every render rather than held, so a value the launcher
## changed is never shown stale.
func _mod_options() -> Array:
	return Gen2ModHost.instance().options(_mod_id)


func _render_mod_options() -> void:
	_render_options(_mod_options(), _mod_option_cursor, func(row: Dictionary) -> String:
		return "%s    %s" % [
			String(row.get("label", "")),
			String((row.get("labels", []) as Array)[int(row.get("index", 0))]),
		]
	)


## One rung either way, wrapping the way the cartridge's own value rows do.
## Written through the host, so the file is committed on the press and whatever
## registered the setting hears about it at once.
func _adjust_mod_option(rows: Array, delta: int) -> void:
	var row: Dictionary = rows[_mod_option_cursor]
	var values: Array = row.get("values", []) as Array
	var next: int = wrapi(int(row.get("index", 0)) + signi(delta), 0, maxi(values.size(), 1))
	var result: Dictionary = Gen2ModHost.instance().set_option_index(
		_mod_id, StringName(row.get("key", &"")), next
	)
	if not bool(result.get("ok", false)):
		_status.text = Gen2ModRefusal.text(result)
		_status.add_theme_color_override("font_color", ERROR)
		return
	_status.text = ""
	_render_mod_options()


## [param reset] false keeps the pocket and cursor, which is what returning from
## an item submenu does; the source restores each pocket's own saved cursor the
## same way. The item list is always rebuilt, since a USE changed a quantity.
func _open_pack_mode(reset: bool = true) -> void:
	_mode = Mode.PACK
	_pack_pockets = Gen2WorldPack.build(_data, _world.state) if _world != null else []
	if reset:
		_pack_pocket_index = 0
		_pack_cursor = 0
	_pack_pocket_index = clampi(_pack_pocket_index, 0, maxi(_pack_pockets.size() - 1, 0))
	_pack_cursor = clampi(_pack_cursor, 0, maxi(_current_pocket_items().size() - 1, 0))
	_status.text = ""
	_footer.text = "Left and right: pocket    Up and down: move    A: choose    B: back"
	_render_pack()


func _current_pocket() -> Dictionary:
	if _pack_pockets.is_empty():
		return {}
	return _pack_pockets[_pack_pocket_index]


func _current_pocket_items() -> Array:
	return _current_pocket().get("items", [])


func _cycle_pocket(delta: int) -> void:
	if _pack_pockets.is_empty():
		return
	_pack_pocket_index = wrapi(_pack_pocket_index + signi(delta), 0, _pack_pockets.size())
	_pack_cursor = 0
	_render_pack()


func _move_pack_cursor(delta: int) -> void:
	var items: Array = _current_pocket_items()
	if items.is_empty():
		return
	_pack_cursor = wrapi(_pack_cursor + signi(delta), 0, items.size())
	_render_pack()


func _render_pack() -> void:
	var pocket: Dictionary = _current_pocket()
	_title.text = "PACK"
	_summary.text = String(pocket.get("name", ""))
	var items: Array = pocket.get("items", [])
	if items.is_empty():
		_status.text = "No items in this pocket."
		_status.add_theme_color_override("font_color", MUTED)
	_render_options(items, _pack_cursor, func(entry: Dictionary) -> String:
		return "%s    x%d" % [entry.get("name", "UNKNOWN"), int(entry.get("quantity", 0))]
	)


func _selected_item() -> Dictionary:
	var items: Array = _current_pocket_items()
	if _pack_cursor < 0 or _pack_cursor >= items.size():
		return {}
	return items[_pack_cursor]


## `.ItemBallsKey_LoadSubmenu` and `.TMHMPocketMenu` both open a submenu on the
## selected item rather than acting on it directly.
func _open_item_mode() -> void:
	var item: Dictionary = _selected_item()
	if item.is_empty():
		return
	_mode = Mode.PACK_ITEM
	_item_actions = Gen2WorldPack.item_submenu(_data, int(item.get("item", 0)))
	_item_cursor = 0
	_status.text = ""
	_summary.text = String(item.get("name", ""))
	_footer.text = "Up and down: move    A: choose    B: back"
	_render_item_menu()


func _render_item_menu() -> void:
	_title.text = "PACK"
	_render_options(_item_actions, _item_cursor, func(entry: Dictionary) -> String:
		var label: String = String(entry.get("label", ""))
		return label if bool(entry.get("available", false)) else "%s (unavailable)" % label
	)


func _confirm_item_action() -> void:
	if _item_cursor < 0 or _item_cursor >= _item_actions.size():
		return
	var entry: Dictionary = _item_actions[_item_cursor]
	var action: StringName = StringName(entry.get("action", &""))
	if action == Gen2WorldPack.ACTION_QUIT:
		_open_pack_mode(false)
		return
	if not bool(entry.get("available", false)):
		_status.text = "%s is not available yet." % String(entry.get("label", ""))
		_status.add_theme_color_override("font_color", MUTED)
		return
	_confirm_use()


## `UseItem`'s jumptable: `.Oak` refuses, `.Current` and `.Field` apply straight
## away, and `.Party` asks which Pokemon first. `.Field`'s extra
## `PACKSTATE_QUITRUNSCRIPT` on success has no counterpart yet, because no
## `ITEMMENU_CLOSE` item has an effect here: Escape Rope and Dig need the spawn
## warp, so every one of them reaches `.Oak`'s refusal instead.
func _confirm_use() -> void:
	var item: Dictionary = _selected_item()
	if item.is_empty():
		return
	var number: int = int(item.get("item", 0))
	## The TM/HM pocket never reaches `UseItem`'s jumptable: engine/items/pack.asm
	## gives it its own USE, which runs AskTeachTMHM first.
	if Gen2WorldPack.pocket_for(_data, number) == Gen2WorldPack.TYPE_TM_HM:
		_open_teach_mode(number)
		return
	match Gen2WorldPack.field_use_kind(_data, number):
		Gen2WorldPack.ITEMMENU_PARTY:
			if _party_targets().is_empty():
				_show_pack_result(NO_MON_TEXT, false)
				return
			_open_target_mode()
		Gen2WorldPack.ITEMMENU_CURRENT, Gen2WorldPack.ITEMMENU_CLOSE:
			_use_selected_item(-1)
		_:
			_show_pack_result(OAK_TEXT, false)


## `.Party`'s party list. Reads the same save the USE will be applied to, so a
## screen without one offers no targets and answers `.NoPokemon`.
func _party_targets() -> Array:
	if _pack_save == null:
		return []
	var targets: Array = []
	for member: Variant in _pack_save.party:
		var mon: Gen2SaveMon = member as Gen2SaveMon
		if mon == null:
			continue
		# Max HP is derived, not stored, the same way Gen2PartyScreen derives it.
		var battle_mon: Gen2BattleMon = Gen2SaveBattleAdapter.to_battle_mon(_data, mon)
		targets.append({
			"name": mon.nickname if not mon.nickname.is_empty() \
				else String(_data.species(mon.species).get("name", "UNKNOWN")),
			"hp": mon.hp,
			"max_hp": battle_mon.max_hp() if battle_mon != null else 0,
			"egg": mon.is_egg,
		})
	return targets


## AskTeachTMHM: the booted-up text and its yes/no. A TM/HM the cartridge does
## not carry has no move, which is the source's `.NotTMHM` fall-through, so no
## prompt appears and USE reports nothing happened.
func _open_teach_mode(item: int) -> void:
	_teach_prompt = Gen2WorldTMHM.teach_prompt(_data, item)
	if not bool(_teach_prompt.get("ok", false)):
		_show_pack_result(OAK_TEXT, false)
		return
	_teaching = false
	_teach_cursor = 0
	_mode = Mode.PACK_TEACH
	_status.text = ""
	_footer.text = "Up and down: move    A: choose    B: back"
	_render_teach()


func _render_teach() -> void:
	_title.text = "TEACH"
	_summary.text = String(_teach_prompt.get("text", ""))
	_render_options([{"label": "YES"}, {"label": "NO"}], _teach_cursor,
		func(entry: Dictionary) -> String: return String(entry.get("label", ""))
	)


## The yes/no answer. Yes reaches ChooseMonToLearnTMHM, which is the same party
## list `.Party` uses; no closes the way the source's carry return does.
func _confirm_teach() -> void:
	if _teach_cursor != 0:
		_open_pack_mode(false)
		return
	if _party_targets().is_empty():
		_show_pack_result(NO_MON_TEXT, false)
		return
	_teaching = true
	_open_target_mode()


func _teach_selected_item(party_index: int) -> void:
	if _pack_save == null or _world == null:
		_show_pack_result("No save is loaded.", false)
		return
	var item: int = int(_teach_prompt.get("item", 0))
	var result: Dictionary = Gen2WorldPartyHost.teach_tm_hm(
		_world, _pack_save, item, party_index, -1, _pack_persist
	)
	_teaching = false
	if not bool(result.get("ok", false)):
		var reason: StringName = StringName(result.get("reason", &""))
		# LearnMove runs after CanLearnTMHMMove and KnowsMove, so this is the one
		# refusal that opens a menu instead of ending the USE.
		if reason == &"moveset_full":
			var details: Dictionary = result.get("details", {})
			_forget_party_index = party_index
			_forget_moves = Gen2MoveForget.options(_data, details.get("moves", []))
			if not _forget_moves.is_empty():
				_open_forget_ask()
				return
		_show_pack_result(_teach_refusal(reason, party_index), false)
		return
	_show_pack_result(Gen2MoveForget.learned_text(
		_target_name(party_index), String(_teach_prompt.get("move_name", ""))
	), true)


## ForgetMove's own AskForgetMoveText yes/no, which it prints before the list.
func _open_forget_ask() -> void:
	_mode = Mode.PACK_FORGET_ASK
	_forget_confirm_cursor = 0
	_status.text = ""
	_footer.text = "Up and down: move    A: choose    B: back"
	_render_forget_ask()


func _render_forget_ask() -> void:
	_title.text = "TEACH"
	_summary.text = Gen2MoveForget.ask_text(
		_target_name(_forget_party_index), String(_teach_prompt.get("move_name", ""))
	)
	_render_options([{"label": "YES"}, {"label": "NO"}], _forget_confirm_cursor,
		func(entry: Dictionary) -> String: return String(entry.get("label", ""))
	)


func _confirm_forget_ask() -> void:
	if _forget_confirm_cursor != 0:
		_open_stop_learning()
		return
	_open_forget_list()


## ForgetMove's .loop: MoveAskForgetText over the moves ListMoves drew. The
## cartridge's list is plain move names, so an HM is not marked here; it answers
## on confirm, the way .hmmove does.
func _open_forget_list() -> void:
	_mode = Mode.PACK_FORGET
	_forget_cursor = 0
	_status.text = ""
	_footer.text = "Up and down: move    A: forget    B: back"
	_render_forget_list()


func _render_forget_list() -> void:
	_title.text = "FORGET"
	_summary.text = Gen2MoveForget.which_text()
	_render_options(_forget_moves, _forget_cursor,
		func(entry: Dictionary) -> String: return String(entry.get("name", ""))
	)


## The answer TeachTMHM is called a second time with. An HM keeps the list open
## behind MoveCantForgetHMText, since .hmmove is `jr .loop` and not a cancel.
func _confirm_forget() -> void:
	if _forget_cursor < 0 or _forget_cursor >= _forget_moves.size():
		return
	var entry: Dictionary = _forget_moves[_forget_cursor]
	if not bool(entry.get("forgettable", false)):
		_status.text = Gen2MoveForget.cant_forget_hm_text()
		_status.add_theme_color_override("font_color", ERROR)
		return
	var result: Dictionary = Gen2WorldPartyHost.teach_tm_hm(
		_world, _pack_save, int(_teach_prompt.get("item", 0)), _forget_party_index,
		int(entry.get("slot", -1)), _pack_persist
	)
	if not bool(result.get("ok", false)):
		_show_pack_result(
			_teach_refusal(StringName(result.get("reason", &"")), _forget_party_index), false
		)
		return
	var name: String = _target_name(_forget_party_index)
	_show_pack_result("%s %s" % [
		Gen2MoveForget.forgot_text(name, String(entry.get("name", ""))),
		Gen2MoveForget.learned_text(name, String(_teach_prompt.get("move_name", ""))),
	], true)


## LearnMove.cancel, reached from the ask's no and from B in the list alike.
func _open_stop_learning() -> void:
	_mode = Mode.PACK_STOP_LEARNING
	_forget_confirm_cursor = 0
	_status.text = ""
	_footer.text = "Up and down: move    A: choose    B: back"
	_render_stop_learning()


func _render_stop_learning() -> void:
	_title.text = "TEACH"
	_summary.text = Gen2MoveForget.stop_text(String(_teach_prompt.get("move_name", "")))
	_render_options([{"label": "YES"}, {"label": "NO"}], _forget_confirm_cursor,
		func(entry: Dictionary) -> String: return String(entry.get("label", ""))
	)


## Yes ends the offer with DidNotLearnMoveText; no is `jp .loop`, which reaches
## ForgetMove's ask again.
func _confirm_stop_learning() -> void:
	if _forget_confirm_cursor != 0:
		_open_forget_ask()
		return
	_show_pack_result(Gen2MoveForget.did_not_learn_text(
		_target_name(_forget_party_index), String(_teach_prompt.get("move_name", ""))
	), false)


func _target_name(party_index: int) -> String:
	var targets: Array = _party_targets()
	if party_index < 0 or party_index >= targets.size():
		return "#MON"
	return String((targets[party_index] as Dictionary).get("name", "#MON"))


## TeachTMHM's own refusals, verbatim from data/text/common_2.asm and
## common_3.asm. A full moveset is not among them: it opens ForgetMove's menu
## instead, so the only way to reach the two forget-slot reasons here is a
## revalidation failing between the two teach_tm_hm() calls.
func _teach_refusal(reason: StringName, party_index: int) -> String:
	var move_name: String = String(_teach_prompt.get("move_name", "that move"))
	var name: String = _target_name(party_index)
	match reason:
		&"not_compatible":
			return "%s is not compatible with %s. It can't learn %s." % [
				move_name, name, move_name,
			]
		&"already_knows_move":
			return "%s knows %s." % [name, move_name]
		&"cannot_forget_hm":
			return Gen2MoveForget.cant_forget_hm_text()
		&"invalid_forget_slot":
			return "%s can't forget that move." % name
		&"cannot_teach_egg":
			return "An EGG can't learn anything."
	return "Can't teach that: %s" % String(reason)


func _open_target_mode() -> void:
	_mode = Mode.PACK_TARGET
	_target_cursor = clampi(_target_cursor, 0, maxi(_party_targets().size() - 1, 0))
	_status.text = ""
	_footer.text = "Up and down: move    A: use    B: back"
	_render_targets()


func _render_targets() -> void:
	_title.text = "USE ON"
	_summary.text = String(_selected_item().get("name", ""))
	_render_options(_party_targets(), 0 if _party_targets().is_empty() else _target_cursor,
		func(entry: Dictionary) -> String:
			if bool(entry.get("egg", false)):
				return "%s    EGG" % String(entry.get("name", ""))
			return "%s    %d/%d HP" % [
				String(entry.get("name", "")), int(entry.get("hp", 0)),
				int(entry.get("max_hp", 0)),
			]
	)


func _use_selected_item(party_index: int) -> void:
	var item: Dictionary = _selected_item()
	if item.is_empty():
		return
	if _pack_save == null or _world == null:
		_show_pack_result("No save is loaded.", false)
		return
	var number: int = int(item.get("item", 0))
	var result: Dictionary = Gen2WorldPartyHost.use_item(
		_world, _pack_save, number, party_index, _pack_persist
	)
	if not bool(result.get("ok", false)):
		_show_pack_result(_use_refusal(StringName(result.get("reason", &""))), false)
		return
	_show_pack_result(_use_summary(item, result), true)


## The source has no single "it worked" line: the effect routine prints its own.
## These name what changed, from the values Gen2WorldPartyHost already returns.
func _use_summary(item: Dictionary, result: Dictionary) -> String:
	var name: String = String(item.get("name", "ITEM"))
	if int(result.get("repel_steps", -1)) >= 0:
		return "%s will repel weak Pokemon for %d steps." % [
			name, int(result.get("repel_steps", 0)),
		]
	var healed: int = int(result.get("healed", 0))
	if healed > 0:
		return "%s restored %d HP." % [name, healed]
	if int(result.get("status_cleared", 0)) != 0:
		return "%s cured the status." % name
	return "%s was used." % name


func _use_refusal(reason: StringName) -> String:
	match reason:
		&"item_has_no_effect":
			return "It won't have any effect."
		&"insufficient_item_quantity":
			return "You have none of those."
	return "Can't use that here: %s" % String(reason)


func _show_pack_result(message: String, ok: bool) -> void:
	_mode = Mode.PACK_RESULT
	_pack_result = message
	_pack_result_ok = ok
	_footer.text = "A: continue"
	_render_pack_result()


func _render_pack_result() -> void:
	_title.text = "PACK"
	_status.text = _pack_result
	_status.add_theme_color_override("font_color", SUCCESS if _pack_result_ok else MUTED)
	_render_options(["Continue"], 0, func(entry: Variant) -> String: return str(entry))


func _open_save_confirm_mode() -> void:
	_mode = Mode.SAVE_CONFIRM
	_save_cursor = 0
	_save_result_shown = false
	_title.text = "SAVE"
	_summary.text = "Save your progress?"
	_status.text = ""
	_footer.text = "D-pad: choose    A: confirm    B: cancel"
	_render_save_confirm()


func _confirm_save() -> void:
	if _save_result_shown:
		_open_list_mode()
		return
	if _save_cursor == 1:
		_open_list_mode()
		return
	var result: Dictionary = _save_action.call() if _save_action.is_valid() else {"ok": false, "reason": &"no_save_action"}
	_save_result_shown = true
	if bool(result.get("ok", false)):
		_status.text = "World saved."
		_status.add_theme_color_override("font_color", SUCCESS)
	else:
		_status.text = "Save failed: %s" % String(result.get("reason", "unknown"))
		_status.add_theme_color_override("font_color", ERROR)
	_render_options(["Continue"], 0, func(entry: Variant) -> String: return str(entry))


func _render_save_confirm() -> void:
	_render_options(["Yes", "No"], _save_cursor, func(entry: Variant) -> String: return str(entry))


func _build_ui() -> void:
	var scrim := ColorRect.new()
	scrim.color = SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 320)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	_title = Label.new()
	_title.add_theme_color_override("font_color", TEXT)
	_title.add_theme_font_size_override("font_size", 24)
	content.add_child(_title)
	_summary = Label.new()
	_summary.add_theme_color_override("font_color", MUTED)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_summary)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 4)
	_options.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_options)
	_status = Label.new()
	_status.add_theme_color_override("font_color", MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	_footer = Label.new()
	_footer.add_theme_color_override("font_color", ACCENT)
	content.add_child(_footer)


func _render_options(values: Array, cursor: int, label_for: Callable) -> void:
	if _options == null:
		return
	for child: Node in _options.get_children():
		child.queue_free()
	for index: int in values.size():
		var label := Label.new()
		var name: String = label_for.call(values[index])
		label.text = ("> " if index == cursor else "  ") + name
		label.add_theme_color_override("font_color", ACCENT if index == cursor else TEXT)
		label.add_theme_font_size_override("font_size", 18)
		_options.add_child(label)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
