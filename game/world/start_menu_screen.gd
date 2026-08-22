class_name Gen2StartMenuScreen
extends Control

## The overworld pause menu (engine/menus/start_menu.asm). The list, `_Option`,
## `SaveMenu` and every box the pack opens are the cartridge's own screens
## through [Gen2StartMenuPage] and [Gen2PackPage], drawn into whichever
## [Gen2Screen] the host hands over. A caller that hands over none keeps the
## window-resolution panel below, which is what a launcher preview gets.
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
## `.Field`'s PACKSTATE_QUITRUNSCRIPT: an ITEMMENU_CLOSE item whose effect
## succeeded, so the pack quits and the overworld runs what the effect queued.
## The payload is the resolved effect, because the screen hosting the world is
## the one that can cast a rod or draw a warp.
signal field_item_used(request: Dictionary)

## `EvoStoneEffect`'s own `EvolvePokemon`: the pack has already written the party
## row, and the animation belongs to the screen the overworld hosts. [param after]
## is this menu's own continuation, run when that screen closes.
signal evolution_animation_requested(plan: Dictionary, after: Callable)
## `PlaySFX`, which this screen has no driver of its own for: the world that
## hosts it owns the player. `SFX_SAVE` is the only one it asks for.
signal sfx_requested(sfx: int, waited: bool)

enum Mode {
	LIST, PACK, PACK_ITEM, PACK_TEACH, PACK_TARGET,
	PACK_FORGET_ASK, PACK_FORGET, PACK_STOP_LEARNING,
	PACK_TOSS_QUANTITY, PACK_TOSS_CONFIRM, PACK_GIVE_SWAP,
	PACK_RESULT, SAVE_ASK, SAVE_OVERWRITE, SAVE_SAVING, SAVE_SAVED,
	SAVE_FAILED, OPTIONS, MODS, MOD_OPTIONS,
}

## `SaveMenu`'s four texts, out of `data/text/common_3.asm` on Crystal and
## `common_2.asm` on Gold and Silver, which no importer reads and which this
## project authors beside its other engine text. Verbatim, one entry a line, so
## the box scrolls where `_ContText` scrolls.
const SAVE_ASK_LINES: Array[String] = [
	"Would you like to", "save the game?",
]
## `AlreadyASaveFileText`. `AnotherSaveFileText` is its sibling for a save file
## belonging to another player, and `CompareLoadedAndSavedPlayerID` cannot
## reach it here: a world is always played from the slot it was started in.
const SAVE_OVERWRITE_LINES: Array[String] = [
	"There is already a", "save file. Is it", "OK to overwrite?",
]
const SAVE_SAVING_LINES: Array[String] = [
	"SAVING… DON'T TURN", "OFF THE POWER.",
]
## `_SavedTheGameText`, whose `<PLAYER>` is filled from the save.
const SAVE_SAVED_LINES: Array[String] = [
	"%s saved", "the game.",
]

## `SavingDontTurnOffThePower`'s own `ld c, 16`, then `SavedTheGame`'s 32 before
## the words and 30 after them.
const SAVE_SAVING_FRAMES: int = 16
const SAVE_WRITE_FRAMES: int = 32
const SAVE_DONE_FRAMES: int = 30
## `ld de, SFX_SAVE` (constants/sfx_constants.asm; the comment column there is
## hex).
const SFX_SAVE: int = 0x25

## The pack's five imported texts, by the key `GameData.menu_text` holds each
## under. `UseItem`'s two refusals and `TossMenu`'s three; "(S)" is three literal
## characters in the charmap rather than a plural rule, so the cartridge really
## does say "POTION(S)".
const TEXT_OAK: String = "oak_no_time"
const TEXT_NO_MON: String = "no_mon"
const TEXT_TOSS_ASK: String = "toss_ask"
const TEXT_TOSS_ASK_QUANTITY: String = "toss_ask_quantity"
const TEXT_TOSS_THREW: String = "toss_threw"

## What each reads on a cache imported before the texts were, which is the only
## way any of these is ever seen. Verbatim from data/text/common_2.asm.
const TEXT_FALLBACKS: Dictionary = {
	TEXT_OAK: "OAK: <PLAYER>!\nThis isn't the\ntime to use that!",
	TEXT_NO_MON: "You don't have a\nPOKéMON!",
	TEXT_TOSS_ASK: "Throw away how\nmany?",
	TEXT_TOSS_ASK_QUANTITY: "Throw away <NUM_>\n<RAM_>(S)?",
	TEXT_TOSS_THREW: "Threw away\n<RAM_>(S).",
}


## The pack's submenus, all `MENU_BACKUP_TILES` boxes over the pack's own screen.
##
## `MenuHeader_UsableKeyItem` and its five siblings differ only in where the box
## starts: `menu_coords 13, y, SCREEN_WIDTH - 1, TEXTBOX_Y - 1` with y chosen so
## the rows end on the text box, which is `TEXTBOX_Y - 1 - 2 * items`.
const ITEM_MENU_LEFT: int = 13
const ITEM_MENU_RIGHT: int = 19
const ITEM_MENU_BOTTOM: int = 11
## `YesNoBox`'s own `lb bc, SCREEN_WIDTH - 6, 7`, which `_YesNoBox` turns into
## left 14, right 19, top 7, bottom 11.
const YES_NO_AT: Vector2i = Vector2i(14, 7)
const YES_NO_SPAN: Vector2i = Vector2i(5, 4)
## `TossItem_MenuHeader`: `menu_coords 15, 9, SCREEN_WIDTH - 1, TEXTBOX_Y - 1`.
const TOSS_QUANTITY_AT: Vector2i = Vector2i(15, 9)
const TOSS_QUANTITY_TO: Vector2i = Vector2i(19, 11)
## `STATICMENU_CURSOR | STATICMENU_NO_TOP_SPACING`, which every one of them sets.
const SUBMENU_FLAGS: int = (
	Gen2MenuBox.STATICMENU_CURSOR | Gen2MenuBox.STATICMENU_NO_TOP_SPACING
)
## `YesNoMenuHeader.MenuData`'s own two strings.
const YES_NO_OPTIONS: Array[String] = ["YES", "NO"]

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
## `wItemsPocketScrollPosition` and its three siblings: which entry the visible
## five start at. Held per pocket, the way the source holds one variable each.
var _pack_scroll: Array[int] = [0, 0, 0, 0]
var _pack_cursors: Array[int] = [0, 0, 0, 0]
var _pack_page: Gen2PackPage = null
var _pack_result_ok: bool = false
## `PrintText` waits per page, so a result longer than the box's two rows is
## pressed through rather than cut off at the frame.
var _pack_result_pages: Array = []
var _pack_result_page: int = 0
## What runs when the last page of the box is pressed past, instead of the pack
## coming back: the next move an evolution has to offer.
var _pack_result_next: Callable = Callable()
## AskTeachTMHM's resolved prompt, held while its yes/no is on screen, and
## whether the party list that follows is ChooseMonToLearnTMHM's rather than
## `.Party`'s.
var _teach_prompt: Dictionary = {}
var _teach_cursor: int = 0
var _teaching: bool = false
## `SelectQuantityToToss`'s dial and `YesNoBox`'s cursor, held while TOSS runs.
var _toss_prompt: Gen2WorldQuantityPrompt = null
var _toss_confirm_cursor: int = 0

## GIVE's two directions. `_giving` is the pack's own: the item is chosen and the
## party list picks who holds it. `_give_target` is `GiveTakePartyMonItem`'s,
## where the Pokemon is already chosen and the pack list is `DepositSellPack`,
## which acts on the item rather than opening a submenu over it.
var _giving: bool = false
var _give_target: int = -1
## `PokemonAskSwapItemText`'s yes/no, who it is about and the question itself,
## which stands in the pack's own text box while the box is up.
var _swap_cursor: int = 0
var _swap_target: int = -1
var _swap_question: String = ""
## Whether the USE running is `UseRegisteredItem`'s rather than the pack's own,
## which is the one thing the two jumptables disagree about: their refusals.
var _using_registered: bool = false
## An entry point asked for before the panel was built, run once it is.
var _pending_entry: Callable = Callable()

## ForgetMove's list and the two yes/no boxes around it. The party index is held
## because the second teach_tm_hm() call has to name the same Pokémon the first
## one refused.
var _forget_moves: Array = []
## `MoveCantForgetHMText` while the list it was refused on is still open.
var _forget_refusal: String = ""
var _forget_cursor: int = 0
var _forget_party_index: int = -1
var _forget_confirm_cursor: int = 0
## What is being learned, whichever opened the flow: a TM/HM's move or one an
## evolution offered. `_learning_move` is 0 while a TM owns the flow, so the
## confirm knows which of the two host calls to make.
var _forget_move_name: String = ""
var _learning_move: int = 0
## The moves a field evolution offered that would not fit, offered one at a time
## the way `EvolveAfterBattle` calls `LearnMove` over the new learnset.
var _evolution_offers: Array[int] = []

## `SaveMenu`'s own state: the text standing in the speech box, which of its
## lines is on the top row, `wMenuCursorY` for the yes/no, and the frames the
## two timed modes have spent.
var _save_lines: Array = []
var _save_line: int = 0
var _save_cursor: int = -1
var _save_frames: int = 0
var _save_elapsed: float = 0.0
var _save_result: Dictionary = {}

var _options_menu: Gen2WorldOptionsMenu = null

## The MODS entry: which mod is being configured and where each cursor sits.
## The rows themselves are the host's registrations, read fresh on every render
## so a value changed from the launcher is never shown stale.
var _mod_ids: Array[StringName] = []
var _mod_cursor: int = 0
var _mod_id: StringName = &""
var _mod_option_cursor: int = 0

## The cartridge's own screens, drawn into whichever [Gen2Screen] the host
## handed over. `StartMenu`'s box sits over the map, so it goes into the world's
## own screen rather than one of this node's; without one, the panel below
## stands in, which is what a test or the launcher gets.
var _screen: Gen2Screen = null
var _view: TextureRect = null
var _page: Gen2StartMenuPage = null
## `LoadPartyMenuGFX`: the target list is the party menu, so it is drawn by the
## page that draws the party menu everywhere else.
var _target_page: Gen2PartyMenuPage = null
## Leftover of a hardware frame the target list's icons have not counted yet.
var _target_elapsed: float = 0.0
## The panel's own two roots, hidden whenever a cartridge screen is up.



func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _menu != null:
		_open_list_mode()
	if _pending_entry.is_valid():
		var entry: Callable = _pending_entry
		_pending_entry = Callable()
		entry.call()


## `save_action` is called with no arguments and must return a Dictionary
## shaped like Gen2WorldScreen.persist_world_snapshot()'s result (an "ok" key,
## with "reason" on failure). Kept as a Callable so this screen does not need
## to know how a snapshot is written or where saves live.
##
## Mirrors Gen2BoxScreen.set_context(): open() may be called before or after this
## node enters the tree, so opening the list defers to _ready() until it is in
## one, and runs immediately here otherwise.
func open(world: Gen2WorldAPI, data: GameData, save_action: Callable, previous_cursor: int = 0) -> bool:
	_world = world
	_data = data
	_save_action = save_action
	if _world == null or _data == null:
		return false
	_menu = Gen2WorldStartMenu.from_world(_world, previous_cursor)
	if is_inside_tree():
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


## `GiveTakePartyMonItem`'s GIVE, which opens the pack over a Pokemon the player
## has already chosen. [method open] and [method set_party_context] come first,
## the same way the start menu's own pack does.
func open_give(party_index: int) -> void:
	_give_target = party_index
	if _defer_entry(open_give.bind(party_index)):
		return
	_open_pack_mode()


## `SelectMenu`. `CheckRegisteredItem` answers first, and its `.NotRegistered`
## carry is `MayRegisterItemText` rather than a pack at all; otherwise
## `UseRegisteredItem` runs `CheckItemMenu`'s jumptable over the registered item,
## which is the same one the pack's own USE reads.
func open_registered_item() -> void:
	if _defer_entry(open_registered_item):
		return
	var item: int = Gen2WorldBagHost.registered_item(_world)
	_open_pack_mode()
	_using_registered = true
	if item <= 0:
		_show_pack_result(Gen2WorldPack.may_register_text(), false)
		return
	if not _select_pack_item(item):
		_show_pack_result(Gen2WorldPack.may_register_text(), false)
		return
	_confirm_use()


## Holds an entry point until this screen is in the tree, the way [method open]
## holds the list. A caller that opens this screen before adding it to the tree
## is a preview or a test; the overworld adds it first.
func _defer_entry(entry: Callable) -> bool:
	if is_inside_tree():
		return false
	_pending_entry = entry
	return true


## Puts the pack cursor on one item, which is what `CheckRegisteredItem` finding
## the entry in its pocket amounts to here.
func _select_pack_item(item: int) -> bool:
	for pocket_index: int in _pack_pockets.size():
		var items: Array = (_pack_pockets[pocket_index] as Dictionary).get("items", [])
		for index: int in items.size():
			if int((items[index] as Dictionary).get("item", 0)) != item:
				continue
			_pack_pocket_index = pocket_index
			_pack_cursor = index
			_render_pack()
			return true
	return false


func handle_button(button: int) -> bool:
	## `BuySellToss_InterpretJoypad` reads the joypad itself and answers with a
	## carry, so the dial takes the whole button rather than a direction and an
	## A/B split, the way [Gen2WorldApricorn] feeds it.
	if _mode == Mode.PACK_TOSS_QUANTITY:
		var pressed: bool = _press_toss_quantity(button)
		_render_hardware()
		return pressed
	if Gen2Button.is_direction(button):
		_move(Gen2Button.vector(button))
		_render_hardware()
		return true
	match button:
		Gen2Button.A:
			_confirm()
			_render_hardware()
			return true
		Gen2Button.B:
			_cancel()
			_render_hardware()
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
				_forget_refusal = ""
				_render_forget_list()
		Mode.PACK_STOP_LEARNING:
			if direction.y != 0 or direction.x != 0:
				_forget_confirm_cursor = 1 - _forget_confirm_cursor
				_render_stop_learning()
		Mode.PACK_TOSS_CONFIRM:
			if direction.y != 0 or direction.x != 0:
				_toss_confirm_cursor = 1 - _toss_confirm_cursor
				_render_toss_confirm()
		Mode.PACK_GIVE_SWAP:
			if direction.y != 0 or direction.x != 0:
				_swap_cursor = 1 - _swap_cursor
				_render_give_swap()
		Mode.PACK_TARGET:
			## `InitPartyMenuWithCancel`: CANCEL is the row after the last member
			## and the cursor wraps around it, which is `w2DMenuNumRows` being the
			## party count plus one.
			if direction.y != 0 and not _party_targets().is_empty():
				_target_cursor = wrapi(
					_target_cursor + signi(direction.y), 0, _party_targets().size() + 1
				)
				_render_targets()
		## `VerticalMenu` over `YesNoMenuHeader`, which is only up while a
		## question is; the two timed modes read no joypad at all.
		Mode.SAVE_ASK, Mode.SAVE_OVERWRITE:
			if _save_cursor >= 0 and (direction.x != 0 or direction.y != 0):
				_save_cursor = 1 - _save_cursor
				_render_save()
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
			## `ScrollingMenuJoyAction`'s `.a_button` answers `-1` on the CANCEL
			## row and falls into `.b_button`, so choosing it leaves the pack.
			if _pack_cursor_on_cancel():
				_cancel()
				return
			## `DepositSellPack` acts on the item it is given rather than
			## opening a submenu over it, which is the pack `.GiveItem` opens.
			if _give_target >= 0:
				_give_selected_item(_give_target)
			else:
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
		Mode.PACK_TOSS_CONFIRM:
			_confirm_toss()
		Mode.PACK_GIVE_SWAP:
			_confirm_give_swap()
		Mode.PACK_TARGET:
			## `PartyMenuSelect` returns carry on CANCEL, which the caller answers
			## the same way it answers B.
			if _target_cursor >= _party_targets().size():
				_open_item_mode()
			elif _teaching:
				_teach_selected_item(_target_cursor)
			elif _giving:
				_give_selected_item(_target_cursor)
			else:
				_use_selected_item(_target_cursor)
		## A pack opened over one Pokemon has no menu behind it to go back to:
		## the party screen closed when it asked for this one.
		Mode.PACK_RESULT:
			if _pack_result_advanced():
				return
			if _pack_result_continued():
				return
			if _give_target >= 0:
				closed.emit()
			else:
				_open_pack_mode(false)
		Mode.SAVE_ASK, Mode.SAVE_OVERWRITE, Mode.SAVE_SAVING, Mode.SAVE_SAVED, \
		Mode.SAVE_FAILED:
			_confirm_save()
		## Options_Cancel is the only handler that reads A.
		Mode.OPTIONS:
			if _options_menu.is_cancel():
				_open_list_mode()
		Mode.MODS:
			if _mod_cursor >= 0 and _mod_cursor < _mod_ids.size():
				_open_mod_options_mode(_mod_ids[_mod_cursor])
		## A ladder row is read with left and right, so A does nothing on one, the
		## way it does on the cartridge's own value rows. A button row is the
		## exception: pressing it is the whole setting.
		Mode.MOD_OPTIONS:
			_press_mod_option()


func _cancel() -> void:
	match _mode:
		Mode.LIST:
			closed.emit()
		Mode.PACK:
			if _give_target >= 0:
				closed.emit()
			else:
				_open_list_mode()
		Mode.PACK_ITEM, Mode.PACK_TEACH:
			_open_pack_mode(false)
		Mode.PACK_RESULT:
			if _pack_result_advanced():
				return
			if _pack_result_continued():
				return
			if _give_target >= 0:
				closed.emit()
			else:
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
		## B at the yes/no is `YesNoBox`'s no, which is the carry `TossMenu`
		## returns on. The submenu is already closed by then, so it lands back on
		## the pocket list rather than on the item's own menu.
		Mode.PACK_TOSS_CONFIRM, Mode.PACK_GIVE_SWAP:
			_open_pack_mode(false)
		Mode.SAVE_ASK, Mode.SAVE_OVERWRITE, Mode.SAVE_SAVING, Mode.SAVE_SAVED, \
		Mode.SAVE_FAILED:
			_cancel_save()
		## `_Option.joypad_loop` exits on PAD_START | PAD_B from any row.
		Mode.OPTIONS, Mode.MODS:
			_open_list_mode()
		Mode.MOD_OPTIONS:
			_open_mods_mode()


func _confirm_list() -> void:
	if _menu == null or _menu.size() == 0:
		return
	if not _menu.selected_available():
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
	_render_list()


func _render_list() -> void:
	if _menu == null:
		return
	_render_hardware()


## `StartMenu_Option`'s `farcall Option`. The model edits the shared
## [Gen2OptionsStore] object, so the launcher's settings card and this menu can
## never disagree about a value, which is the same reason the cartridge block
## exists at all.
func _open_options_mode() -> void:
	_mode = Mode.OPTIONS
	_options_menu = Gen2WorldOptionsMenu.build(Gen2OptionsStore.current())
	_render_options_menu()


## Written on every change, matching the launcher card and the cartridge, which
## commits each press to `wOptions` rather than on the way out.
func _persist_options() -> void:
	if Gen2OptionsStore.save(_options_menu.options()):
		return


func _render_options_menu() -> void:
	_render_hardware()


## The MODS entry: the mods that registered a setting, one row each. Only
## reachable when there is at least one, which is what puts the entry in the list
## at all.
func _open_mods_mode() -> void:
	_mode = Mode.MODS
	_mod_ids = Gen2ModHost.instance().option_mod_ids()
	_mod_cursor = clampi(_mod_cursor, 0, maxi(_mod_ids.size() - 1, 0))
	_render_mods()


func _render_mods() -> void:
	_render_hardware()


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
	_render_mod_options()


## Read from the host on every render rather than held, so a value the launcher
## changed is never shown stale.
func _mod_options() -> Array:
	return Gen2ModHost.instance().options(_mod_id)


func _render_mod_options() -> void:
	_render_hardware()


## A button row acts on the press and stores nothing. A ladder row ignores A.
func _press_mod_option() -> void:
	var rows: Array = _mod_options()
	if rows.is_empty():
		return
	var row: Dictionary = rows[_mod_option_cursor]
	if StringName(row.get("kind", Gen2ModHost.OPTION_LADDER)) != Gen2ModHost.OPTION_BUTTON:
		return
	## Both of `press_option`'s refusals are ruled out by the two checks above,
	## and this screen has no cartridge box to print one in either way.
	Gen2ModHost.instance().press_option(_mod_id, StringName(row.get("key", &"")))


## One step either way: a rung, wrapping the way the cartridge's own value rows
## do, or one of a number's own steps. Written through the host, so the file is
## committed on the press and whatever registered the setting hears about it at
## once.
func _adjust_mod_option(rows: Array, delta: int) -> void:
	var row: Dictionary = rows[_mod_option_cursor]
	if StringName(row.get("kind", Gen2ModHost.OPTION_LADDER)) == Gen2ModHost.OPTION_BUTTON:
		return
	var result: Dictionary = Gen2ModHost.instance().adjust_option(
		_mod_id, StringName(row.get("key", &"")), delta
	)
	if not bool(result.get("ok", false)):
		return
	_render_mod_options()


## [param reset] false keeps the pocket and cursor, which is what returning from
## an item submenu does; the source restores each pocket's own saved cursor the
## same way. The item list is always rebuilt, since a USE changed a quantity.
func _open_pack_mode(reset: bool = true) -> void:
	_mode = Mode.PACK
	_giving = false
	_teaching = false
	_using_registered = false
	_evolution_offers.clear()
	_learning_move = 0
	_forget_move_name = ""
	_pack_pockets = Gen2WorldPack.build(_data, _world.state) if _world != null else []
	if reset:
		_pack_pocket_index = 0
		_pack_cursor = 0
		_pack_cursors.fill(0)
		_pack_scroll.fill(0)
	_pack_pocket_index = clampi(_pack_pocket_index, 0, maxi(_pack_pockets.size() - 1, 0))
	## The CANCEL row is always there, so an emptied pocket puts the cursor on it
	## rather than on an item that is gone.
	_pack_cursor = clampi(_pack_cursor, 0, _current_pocket_items().size())
	_render_pack()


func _current_pocket() -> Dictionary:
	if _pack_pockets.is_empty():
		return {}
	return _pack_pockets[_pack_pocket_index]


func _current_pocket_items() -> Array:
	return _current_pocket().get("items", [])


## `.ItemsPocketMenu` and its three siblings, each of which stores its own
## `w*PocketCursor` and `w*PocketScrollPosition` on the way out and loads them
## again on the way in, so a pocket is where the player left it.
func _cycle_pocket(delta: int) -> void:
	if _pack_pockets.is_empty():
		return
	_pack_cursors[_pack_pocket_index] = _pack_cursor
	_pack_pocket_index = wrapi(_pack_pocket_index + signi(delta), 0, _pack_pockets.size())
	_pack_cursor = clampi(
		_pack_cursors[_pack_pocket_index], 0, _current_pocket_items().size()
	)
	_render_pack()


## `ScrollingMenuJoyAction`'s `.d_up` and `.d_down`, which move the cursor
## inside the visible five and scroll only at their edges. The CANCEL row is one
## past the last item, which is what makes the walk wrap over `size + 1`.
func _move_pack_cursor(delta: int) -> void:
	var rows: int = _current_pocket_items().size() + 1
	_pack_cursor = wrapi(_pack_cursor + signi(delta), 0, rows)
	_pack_scroll[_pack_pocket_index] = clampi(
		clampi(
			_pack_scroll[_pack_pocket_index],
			_pack_cursor - (Gen2PackPage.LIST_HEIGHT - 1), _pack_cursor
		),
		0, maxi(rows - Gen2PackPage.LIST_HEIGHT, 0)
	)
	_render_pack()


## Whether the cursor is on `ScrollingMenu_UpdateDisplay`'s CANCEL row, which is
## what a pocket with nothing in it is entirely made of.
func _pack_cursor_on_cancel() -> bool:
	return _pack_cursor >= _current_pocket_items().size()


func _render_pack() -> void:
	_render_hardware()


## The five rows `ScrollingMenu_UpdateDisplay` writes, out of the pocket's own
## items and the CANCEL row after them. The TM/HM pocket is
## `TMHM_DisplayPocketItems`, which prints the TM number and the move it teaches
## rather than the item's name.
func _pack_rows() -> Array:
	var items: Array = _current_pocket_items()
	var tmhm: bool = int(_current_pocket().get("pocket", 0)) == Gen2WorldPack.TYPE_TM_HM
	var scroll: int = _pack_scroll[_pack_pocket_index]
	var out: Array = []
	for offset: int in Gen2PackPage.LIST_HEIGHT:
		var index: int = scroll + offset
		if index > items.size():
			break
		if index == items.size():
			out.append({"kind": Gen2PackPage.ROW_CANCEL})
			break
		var entry: Dictionary = items[index]
		var item: int = int(entry.get("item", 0))
		## `PlaceMenuItemQuantity` asks `_CheckTossableItem`, so a key item and
		## an HM carry no count on this screen.
		var row: Dictionary = {
			"kind": Gen2PackPage.ROW_ITEM,
			"name": String(entry.get("name", "")),
			"quantity": int(entry.get("quantity", 0)),
			"show_quantity": Gen2WorldPack.can_toss(_data, item),
		}
		if tmhm:
			var number: int = RomLayout.tmhm_number_for_item(
				item, _data.tmhm_moves().size() if _data != null else 0
			)
			var hm: bool = Gen2WorldTMHM.is_hm(item)
			row["kind"] = Gen2PackPage.ROW_TM
			row["hm"] = hm
			row["number"] = number - RomLayout.TMHM_TM_COUNT if hm else number
			row["name"] = _data.move(
				Gen2WorldTMHM.move_for_item(_data, item)
			).get("name", "") if _data != null else ""
		out.append(row)
	return out


## The pack as the cartridge draws it. `UpdateItemDescription` prints the item's
## own description, and the TM/HM pocket the move's; a cursor on CANCEL leaves
## the box empty, which is what `TMHM_CheckHoveringOverCancel` does.
func _pack_image() -> Image:
	if _pack_page == null:
		_pack_page = Gen2PackPage.from_data(_data)
	if _pack_page == null:
		return null
	return _pack_page.image(
		_data, _pack_map(_pack_description()), _pack_pocket_index, _player_is_female()
	)


## The pocket listing's own tilemap with [param text] in its description box,
## which is where every one of the pack's prints lands: `Pack_PrintTextNoScroll`
## and `MenuTextbox` both write the same six rows at the foot of the screen.
func _pack_map(text: String) -> PackedInt32Array:
	var pocket: int = _pack_pocket_index
	return _pack_page.pocket_map(
		pocket, _pack_rows(), _pack_cursor - _pack_scroll[pocket], text,
		_data.pack_pocket_name(pocket) if _data != null else PackedByteArray()
	)


## The pack's screen with one of its `MENU_BACKUP_TILES` boxes over it.
## [param draw] writes tiles into the map the pack just built, so the box wears
## the attrmap `_CGB_PackPals` left rather than being a layer of its own.
func _pack_overlay(text: String, draw_page: Callable) -> Image:
	if _pack_page == null:
		_pack_page = Gen2PackPage.from_data(_data)
	if _pack_page == null:
		return null
	var map: PackedInt32Array = _pack_map(text)
	if draw_page.is_valid():
		draw_page.call(map)
	return _pack_page.image(_data, map, _pack_pocket_index, _player_is_female())


## `YesNoBox` over one of the pack's printed questions, which is what every one
## of its confirmations is.
func _pack_yes_no(text: String, cursor_index: int) -> Image:
	return _pack_overlay(_last_page(text), func(map: PackedInt32Array) -> void:
		_pack_page.draw_menu(
			map,
			Gen2MenuBox.from_coords(
				YES_NO_AT.x, YES_NO_AT.y,
				YES_NO_AT.x + YES_NO_SPAN.x, YES_NO_AT.y + YES_NO_SPAN.y,
				SUBMENU_FLAGS
			),
			YES_NO_OPTIONS, cursor_index
		)
	)


## `MenuHeader_UsableKeyItem` and its five siblings, which are one box whose top
## is chosen so [param count] rows end on the text box.
func _item_menu_box(count: int) -> Gen2MenuBox:
	return Gen2MenuBox.from_coords(
		ITEM_MENU_LEFT, ITEM_MENU_BOTTOM - 2 * maxi(count, 0),
		ITEM_MENU_RIGHT, ITEM_MENU_BOTTOM, SUBMENU_FLAGS
	)


## What a box is left holding after the prints in front of a question: `YesNoBox`
## opens over the last page of the last `PrintText`, so a question preceded by
## more words than two rows hold shows its tail rather than its head.
## `AskTeachTMHM`'s pair of texts is the one that reaches past a page.
func _last_page(text: String) -> String:
	var pages: Array = Gen2TextLayout.lay_out(
		text, Gen2PackPage.TEXTBOX_COLUMNS - 2, Gen2PackPage.TEXTBOX_ROWS_OF_TEXT
	)
	if pages.is_empty():
		return ""
	return "\n".join(pages[pages.size() - 1] as PackedStringArray)


## Which page of the result text the box is holding.
func _pack_result_text() -> String:
	if _pack_result_pages.is_empty():
		return ""
	var page: PackedStringArray = _pack_result_pages[
		clampi(_pack_result_page, 0, _pack_result_pages.size() - 1)
	]
	return "\n".join(page)


func _pack_description() -> String:
	if _pack_cursor_on_cancel() or _data == null:
		return ""
	var item: int = int(_selected_item().get("item", 0))
	if Gen2WorldTMHM.is_tm_hm(item):
		return String(_data.move(
			Gen2WorldTMHM.move_for_item(_data, item)
		).get("description", ""))
	return String(_data.item(item).get("description", ""))


## `wPlayerGender`, which picks Kris's pack and her own palettes.
func _player_is_female() -> bool:
	return _world != null and _world.player_female()


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
	## Both are answers the party list ahead is still waiting to give. Leaving
	## either set here is what let a TM's cancelled ChooseMonToLearnTMHM teach
	## itself from the next item's own `.Party` list.
	_teaching = false
	_giving = false
	_item_actions = Gen2WorldPack.item_submenu(_data, int(item.get("item", 0)))
	_item_cursor = 0
	_render_item_menu()


func _render_item_menu() -> void:
	_render_hardware()


func _confirm_item_action() -> void:
	if _item_cursor < 0 or _item_cursor >= _item_actions.size():
		return
	var action: StringName = StringName(
		(_item_actions[_item_cursor] as Dictionary).get("action", &"")
	)
	match action:
		Gen2WorldPack.ACTION_QUIT:
			_open_pack_mode(false)
		Gen2WorldPack.ACTION_TOSS:
			_open_toss_quantity()
		Gen2WorldPack.ACTION_GIVE:
			_open_give_target()
		Gen2WorldPack.ACTION_SELECT:
			_register_selected_item()
		_:
			_confirm_use()


## `GiveItem`'s own party list, which `.NoPokemon` answers when there is none.
func _open_give_target() -> void:
	if _party_targets().is_empty():
		_show_pack_result(_pack_text(TEXT_NO_MON), false)
		return
	_giving = true
	_open_target_mode()


## `RegisterItem`. `CheckSelectableItem` has already decided whether SEL is in
## the submenu at all, so the refusal here is only reachable from a caller that
## is not that submenu.
func _register_selected_item() -> void:
	var item: Dictionary = _selected_item()
	if item.is_empty():
		return
	if _world == null:
		_show_pack_result("No world is loaded.", false)
		return
	var result: Dictionary = Gen2WorldBagHost.register(
		_world, _pack_save, int(item.get("item", 0)), _pack_persist
	)
	if not bool(result.get("ok", false)):
		if StringName(result.get("reason", &"")) == &"item_cannot_be_registered":
			_show_pack_result(Gen2WorldPack.cant_register_text(), false)
			return
		_show_pack_result(
			"Could not register that (%s)." % String(result.get("reason", "")), false
		)
		return
	_show_pack_result(Gen2WorldPack.registered_text(String(result.get("name", ""))), true)


## `TryGiveItemToPartymon`, from either direction: the pack's GIVE names the
## Pokemon last and `GiveTakePartyMonItem`'s GIVE names the item last. A hand
## that is already full stops at `PokemonAskSwapItemText` with nothing written.
func _give_selected_item(party_index: int, swap: bool = false) -> void:
	var item: Dictionary = _selected_item()
	if item.is_empty():
		return
	if _pack_save == null or _world == null:
		_show_pack_result("No save is loaded.", false)
		return
	var number: int = int(item.get("item", 0))
	if not Gen2WorldPack.can_hold(_data, number):
		_show_pack_result(Gen2WorldPack.cant_hold_text(), false)
		return
	var result: Dictionary = Gen2WorldBagHost.give_to_party(
		_world, _pack_save, number, party_index, swap, _pack_persist
	)
	if bool(result.get("ok", false)):
		var target_name: String = _target_name(party_index)
		var held_name: String = String(result.get("held_name", ""))
		_show_pack_result(
			Gen2WorldPack.swap_text(target_name, held_name, String(result.get("name", ""))) \
				if int(result.get("held", 0)) > 0 \
				else Gen2WorldPack.hold_text(target_name, String(result.get("name", ""))),
			true
		)
		return
	var reason: StringName = StringName(result.get("reason", &""))
	if reason == &"already_holding":
		_open_give_swap(party_index, String(
			(result.get("details", {}) as Dictionary).get("held_name", "")
		))
		return
	_show_pack_result(_give_refusal(reason, party_index), false)


func _give_refusal(reason: StringName, party_index: int) -> String:
	match reason:
		&"cannot_hold_egg":
			return Gen2WorldPack.egg_cant_hold_text()
		&"item_cannot_be_held":
			return Gen2WorldPack.cant_hold_text()
		&"bag_full":
			return Gen2WorldPack.storage_full_text()
		&"insufficient_item_quantity":
			return "You have none of those."
	return "%s could not be given that (%s)." % [_target_name(party_index), String(reason)]


func _open_give_swap(party_index: int, held_name: String) -> void:
	_mode = Mode.PACK_GIVE_SWAP
	_swap_cursor = 0
	_swap_target = party_index
	_swap_question = Gen2WorldPack.ask_swap_text(_target_name(party_index), held_name)
	_render_give_swap()


func _render_give_swap() -> void:
	_render_hardware()


## The answer to `PokemonAskSwapItemText`. Its no is `.abort`, which leaves both
## items where they were.
func _confirm_give_swap() -> void:
	if _swap_cursor != 0:
		_open_pack_mode(false)
		return
	_give_selected_item(_swap_target, true)


## `UseItem`'s jumptable: `.Oak` refuses, `.Current` and `.Field` apply straight
## away, and `.Party` asks which Pokemon first. `.Field` runs the effect here and
## quits the pack only when it succeeded, which is `wItemEffectSucceeded`; a CLOSE
## item this project has no effect for leaves the byte clear and lands on `.Oak`
## with every other refusal.
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
				_show_pack_result(_pack_text(TEXT_NO_MON), false)
				return
			_open_target_mode()
		Gen2WorldPack.ITEMMENU_CURRENT:
			## `CoinCaseEffect` is `MenuTextboxWaitButton` over
			## `_CoinCaseCountText` and nothing else: the count is shown where the
			## pack already prints, and the pack stays open behind it.
			if number == Gen2WorldPack.ITEM_COIN_CASE:
				_show_pack_result(_coin_case_text(), true)
				return
			_use_selected_item(-1)
		Gen2WorldPack.ITEMMENU_CLOSE:
			_use_field_item(number)
		_:
			_show_pack_result(_pack_text(TEXT_OAK), false)


## `.Field`: `DoItemEffect` and then `wItemEffectSucceeded`. The effects that run
## in the overworld are resolved here and reported to the host, which is what
## `QueueScript` is on the cartridge; the pack itself only decides whether to
## quit.
func _use_field_item(item: int) -> void:
	var request: Dictionary = _resolve_field_item(item) if _world != null else {}
	if not bool(request.get("ok", false)):
		## `.Field` says `.Oak` and `UseRegisteredItem`'s `.Overworld`
		## `CantUseItem`, which is the one thing the two jumptables disagree on.
		_show_pack_result(_use_refusal(&"item_effect_failed", item), false)
		return
	field_item_used.emit(request)


## One `ItemEffects` entry each, in the order `Gen2WorldPack.FIELD_EFFECTS` names
## them. A failure is `.Oak`, whatever the effect's own reason was: the source
## reads one byte and cannot tell them apart either.
func _resolve_field_item(item: int) -> Dictionary:
	var effect: StringName = Gen2WorldPack.field_effect(_data, item)
	var request: Dictionary = {"ok": true, "effect": effect, "item": item}
	match effect:
		Gen2WorldPack.FIELD_EFFECT_BICYCLE:
			var ridden: Dictionary = _world.bike_request()
			if not bool(ridden.get("ok", false)):
				return {"ok": false}
			request["bike"] = ridden
		Gen2WorldPack.FIELD_EFFECT_ESCAPE_ROPE:
			var escaped: Dictionary = _world.escape_rope_request()
			if not bool(escaped.get("ok", false)):
				return {"ok": false}
			## `UseDisposableItem`, which only the succeeding half reaches. The
			## row was chosen out of the pack, so the pocket holds at least one.
			if _world.inventory != null:
				_world.inventory.change_item_quantity(item, -1)
			request["warp"] = escaped
		Gen2WorldPack.FIELD_EFFECT_ROD:
			var rod: StringName = Gen2WorldInventory.rod_for_item(item)
			if not bool(_world.fishing_check(rod).get("ok", false)):
				return {"ok": false}
			request["rod"] = rod
		Gen2WorldPack.FIELD_EFFECT_ITEMFINDER:
			request["found"] = _world.hidden_item_nearby()
		Gen2WorldPack.FIELD_EFFECT_CARD_KEY:
			var slot: Dictionary = _world.card_key_request()
			if not bool(slot.get("ok", false)):
				return {"ok": false}
			request.merge(slot, true)
		Gen2WorldPack.FIELD_EFFECT_BASEMENT_KEY:
			var door: Dictionary = _world.basement_key_request()
			if not bool(door.get("ok", false)):
				return {"ok": false}
			request.merge(door, true)
		## The one effect that cannot fail: `_Squirtbottle` writes
		## `wItemEffectSucceeded` before the script it queues decides anything,
		## so the pack closes whether or not a Sudowoodo is in front.
		Gen2WorldPack.FIELD_EFFECT_SQUIRTBOTTLE:
			request.merge(_world.squirtbottle_request(), true)
		Gen2WorldPack.FIELD_EFFECT_SACRED_ASH:
			if _pack_save == null:
				return {"ok": false}
			var used: Dictionary = Gen2WorldPartyHost.use_item(
				_world, _pack_save, item, -1, _pack_persist
			)
			if not bool(used.get("ok", false)):
				return {"ok": false}
			request["healed"] = int(used.get("healed", 0))
		_:
			return {"ok": false}
	return request


## `.Party`'s party list. Reads the same save the USE will be applied to, so a
## screen without one offers no targets and answers `.NoPokemon`. The rows are
## `WritePartyMenuTilemap`'s, in the shape [Gen2PartyMenuPage] draws and
## [Gen2PartyScreen] builds, since the list this opens is that same menu.
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
			"index": targets.size(),
			"species": mon.species,
			"item": mon.item,
			"name": mon.nickname if not mon.nickname.is_empty() \
				else String(_data.species(mon.species).get("name", "UNKNOWN")),
			"level": mon.level,
			"hp": mon.hp,
			"max_hp": 0 if mon.is_egg else (battle_mon.max_hp() if battle_mon != null else 0),
			"status": mon.status,
			"fainted": not mon.is_egg and mon.hp <= 0,
			"egg": mon.is_egg,
		})
	return targets


## `PartyMenuStrings`, picked by the `wPartyMenuActionText` each of the three
## entrances writes: `TeachTMHM`'s PARTYMENUACTION_TEACH_TMHM, `GiveItem`'s
## PARTYMENUACTION_GIVE_ITEM, and the PARTYMENUACTION_HEALING_ITEM every
## `.Party` item effect writes.
func _target_prompt() -> String:
	if _teaching:
		return Gen2PartyScreen.PROMPT_TEACH_WHICH
	return Gen2PartyScreen.PROMPT_TO_WHICH if _giving \
		else Gen2PartyScreen.PROMPT_USE_ON_WHICH


## `LoadPartyMenuGFX`, built the first time the list is opened and kept, the way
## [member _page] is.
func _party_menu_page() -> Gen2PartyMenuPage:
	if _target_page == null and _data != null:
		_target_page = Gen2PartyMenuPage.from_data(_data)
	return _target_page


## One pass of the target list's icons, which animate on the hardware clock the
## rest of the party menu's do. Public the way [method advance_save_frame] is, so
## a test or a screenshot driver can step them without waiting on real time.
func advance_target_icons() -> void:
	if _target_page == null or _mode != Mode.PACK_TARGET:
		return
	_target_page.advance(_party_targets(), _target_cursor)
	_render_hardware()


## AskTeachTMHM: the booted-up text and its yes/no. A TM/HM the cartridge does
## not carry has no move, which is the source's `.NotTMHM` fall-through, so no
## prompt appears and USE reports nothing happened.
func _open_teach_mode(item: int) -> void:
	_teach_prompt = Gen2WorldTMHM.teach_prompt(_data, item)
	if not bool(_teach_prompt.get("ok", false)):
		_show_pack_result(_pack_text(TEXT_OAK), false)
		return
	_teaching = false
	_teach_cursor = 0
	_mode = Mode.PACK_TEACH
	_render_teach()


func _render_teach() -> void:
	_render_hardware()


## The yes/no answer. Yes reaches ChooseMonToLearnTMHM, which is the same party
## list `.Party` uses; no closes the way the source's carry return does.
func _confirm_teach() -> void:
	if _teach_cursor != 0:
		_open_pack_mode(false)
		return
	if _party_targets().is_empty():
		_show_pack_result(_pack_text(TEXT_NO_MON), false)
		return
	_teaching = true
	_open_target_mode()


func _teach_selected_item(party_index: int) -> void:
	if _pack_save == null or _world == null:
		_show_pack_result("No save is loaded.", false)
		return
	var item: int = int(_teach_prompt.get("item", 0))
	_learning_move = 0
	_forget_move_name = String(_teach_prompt.get("move_name", ""))
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
	_render_forget_ask()


func _render_forget_ask() -> void:
	_render_hardware()


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
	_forget_refusal = ""
	_forget_cursor = 0
	_render_forget_list()


## The list's own box carries `MoveCantForgetHMText` while it stands, since
## `.hmmove` prints it and is `jr .loop` rather than a cancel. Any move of the
## cursor puts `ListMoves`' own question back.
func _render_forget_list() -> void:
	_render_hardware()


## The answer TeachTMHM is called a second time with. An HM keeps the list open
## behind MoveCantForgetHMText, since .hmmove is `jr .loop` and not a cancel.
func _confirm_forget() -> void:
	if _forget_cursor < 0 or _forget_cursor >= _forget_moves.size():
		return
	var entry: Dictionary = _forget_moves[_forget_cursor]
	if not bool(entry.get("forgettable", false)):
		_forget_refusal = Gen2MoveForget.cant_forget_hm_text()
		_render_forget_list()
		return
	var slot: int = int(entry.get("slot", -1))
	var result: Dictionary = Gen2WorldPartyHost.learn_move(
		_world, _pack_save, _forget_party_index, _learning_move, slot, _pack_persist
	) if _learning_move > 0 else Gen2WorldPartyHost.teach_tm_hm(
		_world, _pack_save, int(_teach_prompt.get("item", 0)), _forget_party_index,
		slot, _pack_persist
	)
	if not bool(result.get("ok", false)):
		_show_pack_result(
			_teach_refusal(StringName(result.get("reason", &"")), _forget_party_index), false,
			_offer_next_evolution_move if _learning_move > 0 else Callable()
		)
		return
	var target_name: String = _target_name(_forget_party_index)
	_show_pack_result("%s %s" % [
		Gen2MoveForget.forgot_text(target_name, String(entry.get("name", ""))),
		Gen2MoveForget.learned_text(target_name, _forget_move_name),
	], true, _offer_next_evolution_move if _learning_move > 0 else Callable())


## LearnMove.cancel, reached from the ask's no and from B in the list alike.
func _open_stop_learning() -> void:
	_mode = Mode.PACK_STOP_LEARNING
	_forget_confirm_cursor = 0
	_render_stop_learning()


func _render_stop_learning() -> void:
	_render_hardware()


## Yes ends the offer with DidNotLearnMoveText; no is `jp .loop`, which reaches
## ForgetMove's ask again.
func _confirm_stop_learning() -> void:
	if _forget_confirm_cursor != 0:
		_open_forget_ask()
		return
	_show_pack_result(Gen2MoveForget.did_not_learn_text(
		_target_name(_forget_party_index), _forget_move_name
	), false, _offer_next_evolution_move if _learning_move > 0 else Callable())


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
	var move_name: String = _forget_move_name if not _forget_move_name.is_empty() \
		else String(_teach_prompt.get("move_name", "that move"))
	var target_name: String = _target_name(party_index)
	match reason:
		&"not_compatible":
			return Gen2WorldTMHM.not_compatible_text(target_name, move_name)
		&"already_knows_move":
			return Gen2WorldTMHM.knows_move_text(target_name, move_name)
		&"cannot_forget_hm":
			return Gen2MoveForget.cant_forget_hm_text()
		&"invalid_forget_slot":
			return "%s can't forget that move." % target_name
		&"cannot_teach_egg":
			return "An EGG can't learn anything."
	return "Can't teach that: %s" % String(reason)


func _open_target_mode() -> void:
	_mode = Mode.PACK_TARGET
	_target_cursor = clampi(_target_cursor, 0, _party_targets().size())
	## `InitPartyMenuGFX` respawns one icon struct per member every time the list
	## is opened, which is what puts the icons on the page at all.
	if _party_menu_page() != null:
		_target_page.reset(_party_targets())
	_target_elapsed = 0.0
	_render_targets()
	## `InitPartyMenuGFX` opens every struct on frame -1, so the icons are blank
	## until `DoNextFrameForAllSprites` has run once; the list is drawn after
	## that first pass rather than before it.
	advance_target_icons()


func _render_targets() -> void:
	## The panel fallback carries the same CANCEL row the hardware page draws, so
	## the cursor means one thing whichever of the two is up.
	var rows: Array = _party_targets()
	rows.append({"cancel": true})
	_render_hardware()


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
		_show_pack_result(_use_refusal(StringName(result.get("reason", &"")), number), false)
		return
	if StringName(result.get("effect", &"")) == &"evolution":
		_forget_party_index = party_index
		_evolution_offers.assign(result.get("move_offers", []))
		## `EvoStoneEffect` reaches `EvolvePokemon` with `wForceEvolution` set, so
		## the same `EvolutionAnimation` runs and its B does nothing: the whole
		## presentation is the screen the after-battle pass uses, and this path
		## prints no box of its own.
		evolution_animation_requested.emit({
			"index": party_index,
			"old_species": int(result.get("old_species", 0)),
			"new_species": int(result.get("new_species", 0)),
			"evolving_name": String(result.get("evolving_name", "")),
			"statused": Gen2Evolution.is_statused(_pack_save.party[party_index]),
			"can_cancel": false,
		}, _offer_next_evolution_move)
		return
	_show_pack_result(_use_summary(item, result), true)


## `EvolveAfterBattle`'s tail: `LearnMove` over what the new species knows at its
## own level, one move at a time, each able to open `ForgetMove` in turn.
func _offer_next_evolution_move() -> void:
	if _evolution_offers.is_empty():
		_learning_move = 0
		_forget_move_name = ""
		_open_pack_mode(false)
		return
	var move: int = _evolution_offers.pop_front()
	_learning_move = move
	_forget_move_name = String(_data.move(move).get("name", "")) if _data != null else ""
	var result: Dictionary = Gen2WorldPartyHost.learn_move(
		_world, _pack_save, _forget_party_index, move, -1, _pack_persist
	)
	if bool(result.get("ok", false)):
		_show_pack_result(Gen2MoveForget.learned_text(
			_target_name(_forget_party_index), _forget_move_name
		), true, _offer_next_evolution_move)
		return
	if StringName(result.get("reason", &"")) == &"moveset_full":
		var details: Dictionary = result.get("details", {})
		_forget_moves = Gen2MoveForget.options(_data, details.get("moves", []))
		if not _forget_moves.is_empty():
			_open_forget_ask()
			return
	_offer_next_evolution_move()


## The source has no single "it worked" line: the effect routine prints its own.
## These name what changed, from the values Gen2WorldPartyHost already returns.
func _use_summary(item: Dictionary, result: Dictionary) -> String:
	var item_name: String = String(item.get("name", "ITEM"))
	if int(result.get("repel_steps", -1)) >= 0:
		return "%s will repel weak Pokemon for %d steps." % [
			item_name, int(result.get("repel_steps", 0)),
		]
	var healed: int = int(result.get("healed", 0))
	if healed > 0:
		return "%s restored %d HP." % [item_name, healed]
	if int(result.get("status_cleared", 0)) != 0:
		return "%s cured the status." % item_name
	return "%s was used." % item_name


## `UseItem` and `UseRegisteredItem` refuse the same item in two words: the
## pack's `.Field` falls through to `.Oak` when the effect did nothing, and
## SELECT's `.Overworld` reaches `CantUseItem` instead.
func _use_refusal(reason: StringName, item: int) -> String:
	if _using_registered:
		return Gen2WorldPack.cant_use_text()
	## `.Field` reads one byte and says `.Oak` for every way an effect can fail,
	## so a CLOSE item is answered before the reasons `.Party`'s own effects give.
	if Gen2WorldPack.field_use_kind(_data, item) == Gen2WorldPack.ITEMMENU_CLOSE:
		return _pack_text(TEXT_OAK)
	match reason:
		&"item_has_no_effect":
			return "It won't have any effect."
		&"insufficient_item_quantity":
			return "You have none of those."
	return "Can't use that here: %s" % String(reason)


## `TossMenu`: the ask, then `SelectQuantityToToss`, which is the same dial the
## mart and Kurt read their joypad through. The ceiling is the stack itself.
func _open_toss_quantity() -> void:
	var item: Dictionary = _selected_item()
	if item.is_empty():
		return
	_mode = Mode.PACK_TOSS_QUANTITY
	_toss_prompt = Gen2WorldQuantityPrompt.open(int(item.get("quantity", 1)))
	_render_toss_quantity()


func _render_toss_quantity() -> void:
	_render_hardware()


## `AskQuantityThrowAwayText` and the `YesNoBox` behind it.
func _open_toss_confirm() -> void:
	if _toss_prompt == null or _selected_item().is_empty():
		return
	_mode = Mode.PACK_TOSS_CONFIRM
	_toss_confirm_cursor = 0
	_render_toss_confirm()


func _render_toss_confirm() -> void:
	_render_hardware()


## `TossItem` and `ThrewAwayText`. The bag host owns the transaction; a refusal
## is reported rather than swallowed, since nothing else here can explain it.
func _confirm_toss() -> void:
	if _toss_confirm_cursor != 0:
		_open_pack_mode(false)
		return
	var item: Dictionary = _selected_item()
	if _world == null or item.is_empty() or _toss_prompt == null:
		_show_pack_result("No world is loaded.", false)
		return
	var result: Dictionary = Gen2WorldBagHost.toss(
		_world, _pack_save, int(item.get("item", 0)), _toss_prompt.value, _pack_persist
	)
	if not bool(result.get("ok", false)):
		_show_pack_result(
			"Could not throw that away (%s)." % String(result.get("reason", "")), false
		)
		return
	## The result box keeps whatever summary the mode before it left, and the
	## question is not it: `ThrewAwayText` is printed under the item's own name.
	_show_pack_result(
		_fill_item_text(_pack_text(TEXT_TOSS_THREW), String(result.get("name", ""))), true
	)


## The dial's own joypad read. Its cancel is `cp -1 / scf`, the same carry
## `TossMenu` treats as "finish", so B goes back to the pocket list.
func _press_toss_quantity(button: int) -> bool:
	if _toss_prompt == null:
		_open_pack_mode(false)
		return true
	match _toss_prompt.press(button):
		Gen2WorldQuantityPrompt.CONFIRMED:
			_open_toss_confirm()
		Gen2WorldQuantityPrompt.CANCELLED:
			_toss_prompt = null
			_open_pack_mode(false)
		_:
			_render_toss_quantity()
	return true


## `_CoinCaseCountText`, whose `text_decimal wCoins, 2, 4` comes back as a
## number marker the count fills. Gold and Silver carry no usable text: theirs
## ends with `done` rather than `text_end`, so `DoTextUntilTerminator` runs off
## `TextCommands` and the cartridge executes whatever follows, which is
## `docs/bugs_and_glitches.md`'s own Coin Case entry. Those two keep the wording.
func _coin_case_text() -> String:
	var text: String = _data.menu_text("coin_case") if _data != null else ""
	if text.is_empty():
		return "Coins:\n%4d" % _coins()
	return Gen2TextStream.fill_marker(
		text, Gen2TextStream.NUMBER_MARKER, "%4d" % _coins()
	)


## `wCoins`, which only the Coin Case reads here.
func _coins() -> int:
	return _world.state.coins() if _world != null and _world.state != null else 0


## One of the pack's own texts, imported when the cache carries it. The source's
## own line breaks are kept: these boxes are the hardware's now, and a break is
## where the cartridge ended the row.
func _pack_text(key: String) -> String:
	var text: String = _data.menu_text(key) if _data != null else ""
	if text.is_empty():
		text = String(TEXT_FALLBACKS.get(key, ""))
	return text


## `Pack_GetItemName` fills wStringBuffer2 and the dial owns wItemQuantityChange,
## so a text's one name slot and one number slot are these two. Filled by
## position: the address inside a marker is the profile's own WRAM.
func _fill_item_text(text: String, item_name: String, quantity: int = -1) -> String:
	var out: String = text
	if quantity >= 0:
		out = Gen2TextStream.fill_marker(
			out, Gen2TextStream.NUMBER_MARKER, str(quantity)
		)
	return Gen2TextStream.fill_marker(out, Gen2TextStream.RAM_MARKER, item_name)


func _show_pack_result(message: String, ok: bool, next: Callable = Callable()) -> void:
	_mode = Mode.PACK_RESULT
	_pack_result_next = next
	_pack_result = message
	_pack_result_ok = ok
	_pack_result_pages = Gen2TextLayout.lay_out(
		message, Gen2PackPage.TEXTBOX_COLUMNS - 2, Gen2PackPage.TEXTBOX_ROWS_OF_TEXT
	)
	_pack_result_page = 0
	_render_pack_result()


## The box's last page handing back to whatever queued work is left, which is
## how an evolution's move offers follow its own two lines.
func _pack_result_continued() -> bool:
	if not _pack_result_next.is_valid():
		return false
	var next: Callable = _pack_result_next
	_pack_result_next = Callable()
	next.call()
	return true


## `PrintText`'s own wait: a result that runs past the box's two rows is pressed
## through page by page before the pack comes back.
func _pack_result_advanced() -> bool:
	if _pack_result_page + 1 >= _pack_result_pages.size():
		return false
	_pack_result_page += 1
	_render_pack_result()
	return true


func _render_pack_result() -> void:
	_render_hardware()


## `SaveMenu`'s first question. `LoadStandardMenuHeader` and
## `DisplaySaveInfoOnSave` put the info box up before it, and both stay up for
## every mode below.
func _open_save_confirm_mode() -> void:
	_enter_save_mode(Mode.SAVE_ASK, SAVE_ASK_LINES, 0)


## The yes/no's own cursor, `YesNoMenuHeader`'s `db 1` default, and the words
## the box holds. [param cursor] below zero is a mode with no box at all.
func _enter_save_mode(mode: Mode, lines: Array, cursor_index: int) -> void:
	_mode = mode
	_save_lines = lines.duplicate()
	_save_line = 0
	_save_cursor = cursor_index
	_save_frames = 0
	_render_save()


func _confirm_save() -> void:
	match _mode:
		## `.refused` on NO, which is the carry `StartMenu_Save` answers with 0:
		## back to the list rather than out of the menu.
		Mode.SAVE_ASK:
			if _save_cursor == 1:
				_open_list_mode()
			else:
				_enter_save_mode(Mode.SAVE_OVERWRITE, SAVE_OVERWRITE_LINES, -1)
		Mode.SAVE_OVERWRITE:
			## `_ContText`'s own `PromptButton` before the third line, which
			## `AlreadyASaveFileText` is the only one of these texts to carry.
			if _save_cursor < 0:
				_save_line = 1
				_save_cursor = 0
				_render_save()
			elif _save_cursor == 1:
				_open_list_mode()
			else:
				_enter_save_mode(Mode.SAVE_SAVING, SAVE_SAVING_LINES, -1)
		## The two timed modes read no button, since `SavingDontTurnOffThePower`
		## zeroes the joypad bytes before it prints.
		Mode.SAVE_SAVING, Mode.SAVE_SAVED:
			pass
		Mode.SAVE_FAILED:
			_open_list_mode()


## B is `YesNoBox`'s no wherever a question is up, and `PromptButton`'s other
## button while the text still has a line to come. The two timed modes read no
## joypad at all.
func _cancel_save() -> void:
	if _save_cursor < 0 and _mode == Mode.SAVE_OVERWRITE:
		_confirm_save()
	elif _save_cursor >= 0:
		_open_list_mode()


## One hardware frame of the two timed modes. Public so a test or a preview owns
## its own frames rather than sampling a screen mid-flight.
func advance_save_frame() -> void:
	if _mode != Mode.SAVE_SAVING and _mode != Mode.SAVE_SAVED:
		return
	_save_frames += 1
	match _mode:
		Mode.SAVE_SAVING:
			if _save_frames == SAVE_SAVING_FRAMES:
				_write_save()
			elif _save_frames == SAVE_SAVING_FRAMES + SAVE_WRITE_FRAMES:
				_show_save_result()
		## Exactly, not past: the host is freed a frame later and this would
		## otherwise emit again on every frame in between.
		Mode.SAVE_SAVED:
			if _save_frames == SAVE_DONE_FRAMES:
				## `StartMenu_Save`'s `ld a, 1`, which is `StartMenu`'s exit
				## rather than its `.Reopen`.
				closed.emit()


func advance_save_frames(count: int) -> void:
	for _step: int in count:
		advance_save_frame()


func _process(delta: float) -> void:
	if _mode == Mode.PACK_TARGET:
		## Capped the way every other hardware-frame pump here caps it: a stall
		## drops icon passes rather than running a second of them at once.
		_target_elapsed = minf(
			_target_elapsed + delta,
			Gen2WorldAnimation.FRAME_SECONDS * float(Gen2WorldAnimation.MAX_CATCHUP_FRAMES),
		)
		while _target_elapsed >= Gen2WorldAnimation.FRAME_SECONDS:
			_target_elapsed -= Gen2WorldAnimation.FRAME_SECONDS
			advance_target_icons()
		return
	_target_elapsed = 0.0
	if _mode != Mode.SAVE_SAVING and _mode != Mode.SAVE_SAVED:
		return
	_save_elapsed += delta
	while _save_elapsed >= Gen2WorldAnimation.FRAME_SECONDS:
		_save_elapsed -= Gen2WorldAnimation.FRAME_SECONDS
		advance_save_frame()


func _write_save() -> void:
	_save_result = _save_action.call() if _save_action.is_valid() \
		else {"ok": false, "reason": &"no_save_action"}


## `SavedTheGame`'s words and `SFX_SAVE` behind them. A refused write is this
## project's own line: the cartridge has no failure path, because its write is
## to SRAM it has already checked.
func _show_save_result() -> void:
	if not bool(_save_result.get("ok", false)):
		_enter_save_mode(Mode.SAVE_FAILED, [
			"Save failed:", String(_save_result.get("reason", "unknown")),
		], 0)
		return
	var player_name: String = _pack_save.player_name if _pack_save != null else ""
	_enter_save_mode(Mode.SAVE_SAVED, [
		SAVE_SAVED_LINES[0] % player_name, SAVE_SAVED_LINES[1],
	], -1)
	## `WaitSFX` after it is not spent, for the reason the intro cry's is not.
	## `SavedTheGame` reaches SFX_SAVE through `WaitPlaySFX`.
	sfx_requested.emit(SFX_SAVE, true)


## `DisplaySaveInfoOnSave`'s four rows: the same fields [Gen2TrainerCard]'s
## first page reads, with `Continue_DisplayBadgeCount`'s popcount over both
## badge bytes beside them.
func _save_state() -> Dictionary:
	var state: Gen2WorldState = _world.state if _world != null else null
	var time: Gen2GameTime = _pack_save.game_time \
		if _pack_save != null and _pack_save.game_time != null else Gen2GameTime.new()
	var crystal: bool = Gen2WorldState.is_crystal_profile(_data)
	return {
		"player_name": _pack_save.player_name if _pack_save != null else "",
		"badges": state.badge_count(crystal) if state != null else 0,
		"pokedex": state != null and state.is_engine_flag_active(
			Gen2WorldStartMenu.ENGINE_POKEDEX
		),
		"caught": state.caught_count() if state != null else 0,
		"hours": time.hours,
		"minutes": time.minutes,
		"lines": _save_lines,
		"line": _save_line,
		"cursor": _save_cursor,
	}


func _render_save() -> void:
	_render_hardware()


## The screen `StartMenu`'s own box is drawn into. The world hands over the one
## the map is already in, so the box stands over it the way the map name sign
## does.
func set_screen(screen: Gen2Screen) -> void:
	_screen = screen
	if _screen == null or _view != null:
		return
	_view = TextureRect.new()
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.display(_view)
	_render_hardware()


## Frees the overlay, since it lives in a screen this node does not own.
func _exit_tree() -> void:
	if _view != null:
		Gen2Screen.drop(_view)
		_view = null


## Whichever of the cartridge's screens this mode is. `_hardware_image()` answers
## every one of them, so there is no window-resolution fallback behind it.
func _render_hardware() -> void:
	if _view == null:
		return
	var image: Image = _hardware_image()
	_view.visible = image != null
	if image == null:
		return
	_view.texture = ImageTexture.create_from_image(image)


## The words this mode's own box prints, which is what [method _hardware_image]
## hands the page. One reading, so a caller can have the box without the pixels.
func box_text() -> String:
	match _mode:
		Mode.PACK_ITEM:
			return _pack_description()
		Mode.PACK_TEACH:
			return String(_teach_prompt.get("text", ""))
		Mode.PACK_FORGET_ASK:
			return Gen2MoveForget.ask_text(
				_target_name(_forget_party_index), _forget_move_name
			)
		Mode.PACK_STOP_LEARNING:
			return Gen2MoveForget.stop_text(_forget_move_name)
		Mode.PACK_TOSS_CONFIRM:
			return _fill_item_text(
				_pack_text(TEXT_TOSS_ASK_QUANTITY),
				String(_selected_item().get("name", "")),
				_toss_prompt.value if _toss_prompt != null else 1
			)
		Mode.PACK_GIVE_SWAP:
			return _swap_question
		Mode.PACK_TOSS_QUANTITY:
			return _pack_text(TEXT_TOSS_ASK)
		Mode.PACK_FORGET:
			return _forget_refusal if not _forget_refusal.is_empty() \
				else Gen2MoveForget.which_text()
		Mode.PACK_RESULT:
			return _pack_result_text()
	return ""


func _hardware_image() -> Image:
	if _data == null:
		return null
	if _page == null:
		_page = Gen2StartMenuPage.from_data(_data)
	if _page == null:
		return null
	match _mode:
		Mode.LIST:
			if _menu == null:
				return null
			var labels: Array = []
			for entry: Variant in _menu.items():
				labels.append(String((entry as Dictionary).get("label", "")))
			## `.PrintMenuAccount` reads the option on every cursor move, so
			## turning MENU ACCOUNT off takes the block away at once.
			var description: String = _menu.selected_description() \
				if Gen2OptionsStore.current().menu_account else ""
			return _page.render_list(
				labels, _menu.cursor, description,
				_world != null and _world.bug_contest_active()
			)
		Mode.SAVE_ASK, Mode.SAVE_OVERWRITE, Mode.SAVE_SAVING, Mode.SAVE_SAVED, \
		Mode.SAVE_FAILED:
			return _page.render_save(_save_state())
		Mode.OPTIONS:
			if _options_menu == null:
				return null
			return _page.render_options(_options_menu.rows(), _options_menu.cursor)
		Mode.PACK:
			return _pack_image()
		Mode.PACK_ITEM:
			var labels: Array = []
			for entry: Dictionary in _item_actions:
				labels.append(String(entry.get("label", "")))
			return _pack_overlay(box_text(), func(map: PackedInt32Array) -> void:
				_pack_page.draw_menu(map, _item_menu_box(labels.size()), labels, _item_cursor)
			)
		Mode.PACK_TEACH:
			return _pack_yes_no(box_text(), _teach_cursor)
		Mode.PACK_FORGET_ASK:
			return _pack_yes_no(box_text(), _forget_confirm_cursor)
		Mode.PACK_STOP_LEARNING:
			return _pack_yes_no(box_text(), _forget_confirm_cursor)
		Mode.PACK_TOSS_CONFIRM:
			return _pack_yes_no(box_text(), _toss_confirm_cursor)
		Mode.PACK_GIVE_SWAP:
			return _pack_yes_no(box_text(), _swap_cursor)
		Mode.PACK_TOSS_QUANTITY:
			return _pack_overlay(box_text(), func(map: PackedInt32Array) -> void:
				_pack_page.draw_quantity(
					map,
					Gen2MenuBox.from_coords(
						TOSS_QUANTITY_AT.x, TOSS_QUANTITY_AT.y,
						TOSS_QUANTITY_TO.x, TOSS_QUANTITY_TO.y, 0
					),
					_toss_prompt.value if _toss_prompt != null else 1
				)
			)
		Mode.PACK_FORGET:
			var moves: Array = []
			for entry: Dictionary in _forget_moves:
				moves.append(String(entry.get("name", "")))
			return _pack_overlay(
				box_text(), func(map: PackedInt32Array) -> void:
					_pack_page.draw_move_list(map, moves, _forget_cursor)
			)
		Mode.PACK_RESULT:
			return _pack_overlay(box_text(), Callable())
		Mode.PACK_TARGET:
			if _party_menu_page() == null:
				return null
			return _target_page.render(
				_party_targets(), _target_cursor, _target_prompt()
			)
		Mode.MODS:
			var rows: Array = []
			for id: StringName in _mod_ids:
				rows.append({"label": _mod_name(id), "value": ""})
			var window: Dictionary = _option_window(rows, _mod_cursor)
			return _page.render_options(window["rows"], window["cursor"])
		Mode.MOD_OPTIONS:
			var rows: Array = []
			for raw: Dictionary in _mod_options():
				var value: String = ""
				match StringName(raw.get("kind", Gen2ModHost.OPTION_LADDER)):
					Gen2ModHost.OPTION_BUTTON:
						value = String(raw.get("press_label", "Go"))
					Gen2ModHost.OPTION_NUMBER:
						value = str(int(raw.get("value", 0)))
					_:
						var labels: Array = raw.get("labels", []) as Array
						var index: int = int(raw.get("index", 0))
						if index >= 0 and index < labels.size():
							value = String(labels[index])
				rows.append({"label": String(raw.get("label", "")), "value": value})
			var window: Dictionary = _option_window(
				rows, _mod_option_cursor, Gen2StartMenuPage.OPTIONS_VISIBLE_VALUE_ROWS
			)
			return _page.render_options(window["rows"], window["cursor"])
	return null


## Keeps the active global row on the hardware page. Input and mutations retain
## the global cursor; only the rows handed to the page move.
func _option_window(
	rows: Array, cursor_index: int,
	visible_rows: int = Gen2StartMenuPage.OPTIONS_VISIBLE_ROWS
) -> Dictionary:
	var first: int = clampi(
		cursor_index - visible_rows + 1,
		0, maxi(rows.size() - visible_rows, 0)
	)
	var last: int = mini(first + visible_rows, rows.size())
	return {
		"rows": rows.slice(first, last),
		"cursor": cursor_index - first if cursor_index >= 0 else -1,
	}
