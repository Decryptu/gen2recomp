class_name Gen2PartyScreen
extends Control

## The party menu, in the two places it is opened from.
##
## Embedded in the overworld it is `PartyMenu` itself: `StartMenu_Pokemon` runs
## `InitPartyMenuWithCancel`, `WritePartyMenuTilemap` and `PlacePartyMenuText`,
## and `PokemonActionSubmenu` opens `MonSubmenu`'s box over the bottom of it. So
## the embedded view is [Gen2PartyMenuPage] and [Gen2MenuPage] at hardware
## resolution, in a [Gen2Screen] of its own, and the model below is what
## `PartyMenuSelect` and `MonMenuLoop` answer.
##
## The launcher's own party view, which is not a cartridge screen, keeps the
## window-resolution panel: it is opened from the save slots with a mouse and
## carries the PC storage and development battle buttons that no cartridge has.

## Emitted only when embedded, mirroring Gen2BoxScreen.closed: the overworld
## start menu resumes on this rather than the screen navigating away with
## change_scene_to_file, which would tear down the running world.
signal closed(result: Dictionary)
## A chosen submenu entry this screen does not own, mirroring
## Gen2StartMenuScreen.action_chosen. Field moves need the live world, which
## belongs to the world screen, so the choice is reported rather than run here.
signal action_chosen(action: Dictionary)

const HARDWARE_SCENE: PackedScene = preload("res://game/render/gen2_screen.tscn")

const BACKGROUND: Color = Color("#09111f")
const PANEL: Color = Color("#14233a")
const BORDER: Color = Color("#2d4566")
const TEXT: Color = Color("#f4f7fb")
const MUTED: Color = Color("#9eacc0")

## The two `MonMenuOptions` rows that open a second party list rather than
## leaving the menu: `MonMenu_Softboiled_MilkDrink` serves both.
const HEAL_TRANSFER_MOVES: Array[int] = [
	Gen2WorldFieldMove.MOVE_SOFTBOILED, Gen2WorldFieldMove.MOVE_MILK_DRINK,
]
const ACCENT: Color = Color("#f3c969")
const SUCCESS: Color = Color("#7bd89a")
const ERROR: Color = Color("#ef8a8a")

## data/mon_menu.asm's MONMENUVALUE_* option strings, in that file's order.
const OPTION_STATS: StringName = &"stats"
const OPTION_SWITCH: StringName = &"switch"
const OPTION_ITEM: StringName = &"item"
const OPTION_CANCEL: StringName = &"cancel"
const OPTION_MOVE: StringName = &"move"
## `GiveTakeItemMenuData`'s own two rows, which ITEM opens rather than answers.
const OPTION_GIVE: StringName = &"give"
const OPTION_TAKE: StringName = &"take"
## engine/pokemon/mon_submenu.asm's NUM_MONMENU_ITEMS: a list already this long
## drops CANCEL rather than growing.
const MAX_SUBMENU_ITEMS: int = 8

## `PartyMenuStrings`' two rows this screen reaches: `ChooseAMonString` for
## `PARTYMENUACTION_CHOOSE_POKEMON`, which `StartMenu_Pokemon` writes, and
## `UseOnWhichPKMNString` for the `PARTYMENUACTION_HEALING_ITEM` that
## `.SelectMilkDrinkRecipient` sets. Engine text no importer reads, like the rest
## of `data/text/common_*.asm`.
const PROMPT_CHOOSE: String = "Choose a #MON."
const PROMPT_USE_ON_WHICH: String = "Use on which PKMN?"

## `_PokemonNotEnoughHPText` and `_ItemCantUseOnMonText`, the two refusals the
## heal transfer prints. Both are a `MenuTextbox` over the menu on the cartridge
## and stand in the menu's own bottom box here, which is the divergence
## `HANDOFF.md` records; the A or B they wait for is the same.
const MESSAGE_NOT_ENOUGH_HP: String = "Not enough HP…"
const MESSAGE_NO_EFFECT: String = "It won't have any effect."

## `MonSubmenu.MenuHeader`'s `menu_coords 6, 0, SCREEN_WIDTH - 1,
## SCREEN_HEIGHT - 1` with `.GetTopCoord`'s own top:
## `1 + bottom - 2 * (count + 1)`, so the box grows upward from the bottom row.
const SUBMENU_LEFT: int = 6
const SUBMENU_RIGHT: int = 19
const SUBMENU_BOTTOM: int = 17

## `GiveTakeItemMenuData`'s `menu_coords 12, 12, SCREEN_WIDTH - 1,
## SCREEN_HEIGHT - 1`, which is a fixed box rather than a grown one.
const ITEM_MENU_BOX: Rect2i = Rect2i(12, 12, 7, 5)

var _data: GameData = null
var _data_override: GameData = null
var _save: Gen2SaveData = null
var _save_override: Gen2SaveData = null
var _embedded: bool = false
var _cards: VBoxContainer = null
var _player_label: Label = null
var _status: Label = null
var _storage_button: Button = null
var _battle_button: Button = null
## The cursor and per-mon submenu. Reachable only through handle_button(),
## which only the world screen calls, so the standalone save-screen view keeps
## its mouse-driven behavior unchanged.
var _member_cursor: int = 0
var _submenu: VBoxContainer = null
var _submenu_items: Array = []
var _submenu_cursor: int = 0
var _submenu_open: bool = false
## Whether the rows on screen are ITEM's GIVE/TAKE box rather than the mon's own
## submenu, which is what B goes back to.
var _item_menu_open: bool = false
## `.SelectMilkDrinkRecipient`: which party member is giving its health away, and
## which of the two moves asked. -1 and 0 when no recipient list is open.
var _heal_user: int = -1
var _heal_move: int = 0

## The embedded view's own hardware screen and the two pages drawn into it.
var _hardware: Gen2Screen = null
var _view: TextureRect = null
var _page: Gen2PartyMenuPage = null
var _menu_page: Gen2MenuPage = null
## A refusal standing in the menu's own bottom box, which the next A or B
## clears. See [constant MESSAGE_NOT_ENOUGH_HP].
var _message: String = ""
var _elapsed: float = 0.0


func _ready() -> void:
	_data = _data_override if _data_override != null else _resolve_data()
	_save = _save_override if _save_override != null else _resolve_save()
	_build_ui()
	_refresh()
	## Only the hardware view has anything to spend a frame on.
	set_process(_embedded)
	# Not while embedded in the overworld: the world screen routes buttons here
	# itself, and a focus ring appearing over the map would be the map's.
	if not _embedded:
		Gen2FocusGuard.attach(self)


## Test seam for a synthetic cache and validated save. `embedded` is the
## overworld start menu's Pokemon entry: the save-screen navigation actions
## (development battle, PC storage by scene change) do not apply while a
## world is running, so they are hidden rather than left to tear it down.
func set_context(data: GameData, save: Gen2SaveData, embedded: bool = false) -> void:
	_data_override = data
	_save_override = save
	_embedded = embedded
	_data = data
	_save = save
	_member_cursor = 0
	_submenu_open = false
	_item_menu_open = false
	_submenu_items = []
	_submenu_cursor = 0
	if is_inside_tree() and _cards != null:
		_refresh()


func party_snapshot() -> Dictionary:
	var members: Array = []
	if _data != null and _save != null:
		for index: int in Gen2SaveData.MAX_PARTY:
			if index >= _save.party.size():
				members.append({"empty": true, "index": index})
				continue
			members.append(_member_snapshot(index, _save.party[index]))
	return {
		"player_name": _save.player_name if _save != null else "",
		"slot": _save.slot if _save != null else -1,
		"members": members,
	}


## engine/pokemon/mon_submenu.asm's GetMonSubmenuItems for one party member.
##
## An egg gets three entries and no moves. Otherwise the four move slots are
## walked in the mon's own slot order, appending every move that appears in
## MonMenuOptions' field-move rows, then the fixed options follow. Only entries
## this project acts on are marked available; the rest keep their source
## position rather than being omitted, the same way Gen2WorldStartMenu carries
## its unimplemented entries.
##
## The MAIL branch is not reproduced: ItemIsMail tests the held item against
## data/items/mail_items.asm, and this project has no mail, so ITEM is always
## the entry in that position.
## [param slot] is one-based and [param in_battle] is whether the list belongs to
## a turn: both only decide which mod rows are offered, and neither changes a
## cartridge row.
static func submenu_items_for(
	data: GameData, mon: Gen2SaveMon, slot: int = 0, in_battle: bool = false
) -> Array:
	var items: Array = []
	if mon == null:
		return items
	# The source compares wCurPartySpecies against EGG ($fd); this save model
	# carries the same fact as Gen2SaveMon.is_egg beside a real species.
	## An egg is three rows and no moves, and a mod gets none of them: there is
	## nothing to follow, teach or send out, and the source itself offers less.
	if mon.is_egg:
		items.append(_option_entry(OPTION_STATS, "STATS"))
		items.append(_option_entry(OPTION_SWITCH, "SWITCH"))
		items.append(_option_entry(OPTION_CANCEL, "CANCEL"))
		return items
	for move: int in mon.moves:
		if move == 0 or not Gen2WorldFieldMove.is_field_move(move):
			continue
		items.append({
			"kind": &"field_move",
			"move": move,
			"label": String(data.move(move).get("name", "MOVE")) if data != null else "MOVE",
			"available": true,
		})
	items.append(_option_entry(OPTION_STATS, "STATS"))
	items.append(_option_entry(OPTION_SWITCH, "SWITCH"))
	items.append(_option_entry(OPTION_MOVE, "MOVE"))
	items.append(_option_entry(OPTION_ITEM, "ITEM", true))
	## After every cartridge action and before CANCEL, which is the source's own
	## last row and the way out of the box. A mod cannot displace one: the list
	## still stops at `NUM_MONMENU_ITEMS`, so rows past it are simply not offered.
	for entry: Dictionary in Gen2ModHost.instance().party_member_entries(slot, in_battle):
		if items.size() >= MAX_SUBMENU_ITEMS:
			break
		items.append({
			"kind": &"mod_party_action", "mod": entry["kind"],
			"label": entry["label"], "handler": entry["handler"], "available": true,
		})
	if items.size() < MAX_SUBMENU_ITEMS:
		items.append(_option_entry(OPTION_CANCEL, "CANCEL"))
	return items


static func _option_entry(
	option: StringName, label: String, available: bool = false
) -> Dictionary:
	return {"kind": &"option", "option": option, "label": label, "available": available}


## `GiveTakeItemMenuData`, the two-row box ITEM opens. Both answers need the live
## world the overworld owns, so each is reported rather than run here, the way a
## field move is.
static func item_menu_items() -> Array:
	return [
		{"kind": &"mon_item", "option": OPTION_GIVE, "label": "GIVE", "available": true},
		{"kind": &"mon_item", "option": OPTION_TAKE, "label": "TAKE", "available": true},
	]


func _party_size() -> int:
	return _save.party.size() if _save != null else 0


## Button driver for the embedded overworld view, mirroring
## Gen2StartMenuScreen.handle_button. Returns whether the button was used.
func handle_button(button: int) -> bool:
	## `JoyWaitAorB` behind a refusal: the press that clears the box does nothing
	## else, and a direction is not one of the two it waits for.
	if not _message.is_empty():
		if button == Gen2Button.A or button == Gen2Button.B:
			_message = ""
			_refresh()
			return true
		return false
	if _party_size() == 0:
		if button == Gen2Button.B:
			close_embedded()
			return true
		return false
	match button:
		Gen2Button.UP:
			_move_cursor(-1)
			return true
		Gen2Button.DOWN:
			_move_cursor(1)
			return true
		Gen2Button.A:
			_confirm()
			return true
		Gen2Button.B:
			_cancel()
			return true
	return false


func _move_cursor(delta: int) -> void:
	if _submenu_open:
		if _submenu_items.is_empty():
			return
		_submenu_cursor = wrapi(_submenu_cursor + delta, 0, _submenu_items.size())
	else:
		_member_cursor = wrapi(_member_cursor + delta, 0, _row_count())
	_refresh()


## `InitPartyMenuWithCancel`, which every way into this menu goes through: the
## party plus the CANCEL row `PlacePartyNicknames.end` prints after it.
func _row_count() -> int:
	return _party_size() + 1


## Where the arrow is, which [Gen2PartyMenuPage] counts the same way.
func _cursor_row() -> int:
	return _member_cursor


func _on_cancel_row() -> bool:
	return _member_cursor >= _party_size()


func _confirm() -> void:
	## `PartyMenuSelect` answers CANCEL with the same carry a B press sets, so
	## the row and the button are one path.
	if _on_cancel_row() and not _submenu_open:
		_cancel()
		return
	if _heal_user >= 0:
		_choose_heal_target()
		return
	if not _submenu_open:
		_open_submenu()
		return
	if _submenu_cursor < 0 or _submenu_cursor >= _submenu_items.size():
		return
	var entry: Dictionary = _submenu_items[_submenu_cursor]
	if StringName(entry.get("option", &"")) == OPTION_CANCEL:
		_close_submenu()
		return
	if not bool(entry.get("available", false)):
		_say("%s is not available yet." % String(entry.get("label", "")))
		return
	match StringName(entry.get("kind", &"")):
		&"field_move":
			var move: int = int(entry.get("move", 0))
			if move in HEAL_TRANSFER_MOVES:
				_open_heal_target(move)
				return
			action_chosen.emit({
				"kind": &"field_move",
				"move": move,
				"slot": _member_cursor,
				"name": _display_name(_save.party[_member_cursor]),
			})
		&"mon_item":
			action_chosen.emit({
				"kind": &"mon_item",
				"option": StringName(entry.get("option", &"")),
				"slot": _member_cursor,
				"name": _display_name(_save.party[_member_cursor]),
			})
		&"mod_party_action":
			## The handler is the mod's, and the slot is the only thing it is
			## told: the menu closes behind it the way a field move's does.
			(entry["handler"] as Callable).call(_member_cursor + 1)
			_close_submenu()
			action_chosen.emit({
				"kind": &"mod_party_action",
				"mod": StringName(entry.get("mod", &"")),
				"slot": _member_cursor,
				"name": _display_name(_save.party[_member_cursor]),
			})
		&"option":
			if StringName(entry.get("option", &"")) == OPTION_ITEM:
				_open_item_menu()


func _cancel() -> void:
	## `.SelectMilkDrinkRecipient`'s own `.set_carry`: a B press over the
	## recipient list gives up on the move and leaves the party menu standing.
	if _heal_user >= 0:
		_heal_user = -1
		_heal_move = 0
		_open_submenu()
		return
	## `GiveTakePartyMonItem`'s own `VerticalMenu` carry is `.cancel`, which
	## returns to the submenu it opened over rather than closing the party menu.
	if _item_menu_open:
		_open_submenu()
		return
	if _submenu_open:
		_close_submenu()
		return
	close_embedded()


## `MonMenu_Softboiled_MilkDrink`'s own gate and then
## `.SelectMilkDrinkRecipient`: a user with a fifth of its health or less says so
## and stays on the submenu, and anything else opens the recipient list, which is
## the party list again with the submenu closed.
func _open_heal_target(move: int) -> void:
	var user: Gen2SaveMon = _save.party[_member_cursor]
	var fifth: int = Gen2WorldPartyHost.one_fifth_max_hp(_data, user)
	if fifth <= 0 or user.hp <= fifth:
		## `.NotEnoughHP` prints and then returns 3, which is `.menu`: the
		## submenu does not survive the refusal.
		_say(MESSAGE_NOT_ENOUGH_HP)
		_close_submenu()
		return
	_heal_user = _member_cursor
	_heal_move = move
	_submenu_open = false
	_item_menu_open = false
	_submenu_items = []
	_refresh()


## One press over the recipient list. The three refusals stay on the list the way
## `.cant_use` loops back to it; anything else is the caller's to apply, since
## the health it moves belongs to a save the world owns.
func _choose_heal_target() -> void:
	if _member_cursor == _heal_user:
		_say(MESSAGE_NO_EFFECT)
		return
	var target: Gen2SaveMon = _save.party[_member_cursor]
	var target_max: int = Gen2SaveBattleAdapter.to_battle_mon(_data, target).max_hp() \
		if not target.is_egg else 0
	if target.is_egg or target.hp <= 0 or target.hp >= target_max:
		_say(MESSAGE_NO_EFFECT)
		return
	var action: Dictionary = {
		"kind": &"heal_transfer",
		"move": _heal_move,
		"slot": _heal_user,
		"target_slot": _member_cursor,
		"name": _display_name(_save.party[_heal_user]),
		"target_name": _display_name(target),
	}
	_heal_user = -1
	_heal_move = 0
	action_chosen.emit(action)


func _open_item_menu() -> void:
	_submenu_items = item_menu_items()
	_submenu_cursor = 0
	_item_menu_open = true
	_refresh()


func _open_submenu() -> void:
	if _member_cursor < 0 or _member_cursor >= _party_size():
		return
	_submenu_items = submenu_items_for(_data, _save.party[_member_cursor], _member_cursor + 1)
	_submenu_cursor = 0
	_submenu_open = not _submenu_items.is_empty()
	_item_menu_open = false
	_refresh()


func _close_submenu() -> void:
	_submenu_open = false
	_item_menu_open = false
	_submenu_items = []
	_submenu_cursor = 0
	_refresh()


## Test and host seam: the submenu as the screen currently shows it.
func submenu_snapshot() -> Dictionary:
	return {
		"open": _submenu_open,
		"item_menu": _item_menu_open,
		"cursor": _submenu_cursor,
		"member": _member_cursor,
		"on_cancel": _on_cancel_row(),
		"message": _message,
		"items": _submenu_items.duplicate(true),
	}


func _render_submenu() -> void:
	if _submenu == null:
		return
	Gen2LauncherUI.clear(_submenu)
	_submenu.visible = _submenu_open
	if not _submenu_open:
		return
	for index: int in _submenu_items.size():
		var entry: Dictionary = _submenu_items[index]
		var label := Label.new()
		var text: String = String(entry.get("label", ""))
		if not bool(entry.get("available", false)) \
			and StringName(entry.get("option", &"")) != OPTION_CANCEL:
			text = "%s (unavailable)" % text
		label.text = ("> " if index == _submenu_cursor else "  ") + text
		label.add_theme_color_override("font_color", ACCENT if index == _submenu_cursor else TEXT)
		label.add_theme_font_size_override("font_size", 18)
		_submenu.add_child(label)


func _resolve_data() -> GameData:
	return Gen2GameRuntime.data_or_any()


func _resolve_save() -> Gen2SaveData:
	return Gen2GameRuntime.selected_save_or_null() if _data != null else null


## `StartMenu_Pokemon`'s screen: the party menu owns all 160x144 of it, so the
## view goes in a [Gen2Screen] of its own rather than into whatever window-
## resolution parent added this one.
func _build_hardware_ui() -> void:
	_hardware = HARDWARE_SCENE.instantiate() as Gen2Screen
	_hardware.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hardware.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hardware)
	_view = TextureRect.new()
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hardware.display(_view)


## One hardware frame of `PlaySpriteAnimations` over the icons. `FreezeMonIcons`
## is what `MonSubmenu` calls before it draws its box, so a menu that is up
## stops them where they stand.
func _process(delta: float) -> void:
	if _view == null or _page == null:
		return
	_elapsed += delta
	var frames: int = 0
	while _elapsed >= Gen2WorldAnimation.FRAME_SECONDS:
		_elapsed -= Gen2WorldAnimation.FRAME_SECONDS
		frames += 1
	if frames == 0 or _submenu_open or _item_menu_open:
		return
	var rows: Array = _rows()
	for _frame: int in frames:
		_page.advance(rows, _cursor_row())
	_render_hardware()


## `WritePartyMenuTilemap`'s rows, in [Gen2BattleSwitchMenu]'s own shape plus the
## `egg` [Gen2PartyMenuPage] needs, which a battle party never carries.
func _rows() -> Array:
	var out: Array = []
	if _save == null:
		return out
	for index: int in _save.party.size():
		var mon: Gen2SaveMon = _save.party[index]
		if mon == null:
			continue
		out.append({
			"index": index,
			"species": mon.species,
			"item": mon.item,
			"name": _display_name(mon),
			"level": mon.level,
			"hp": mon.hp,
			"max_hp": 0 if mon.is_egg else _max_hp(mon),
			"status": mon.status,
			"fainted": not mon.is_egg and mon.hp <= 0,
			"egg": mon.is_egg,
		})
	return out


## `PlacePartyMenuText`'s string: a refusal that is still standing, then the
## recipient list's own action text, then `StartMenu_Pokemon`'s.
func _prompt() -> String:
	if not _message.is_empty():
		return _message
	return PROMPT_USE_ON_WHICH if _heal_user >= 0 else PROMPT_CHOOSE


func _render_hardware() -> void:
	if _view == null or _data == null:
		return
	if _page == null:
		_page = Gen2PartyMenuPage.from_data(_data)
	if _menu_page == null:
		_menu_page = Gen2MenuPage.from_data(_data)
	if _page == null:
		return
	var rows: Array = _rows()
	var image: Image = _page.render(rows, _cursor_row(), _prompt())
	if image == null:
		return
	if _menu_page != null and (_submenu_open or _item_menu_open):
		var box: Gen2MenuBox = _submenu_box()
		var menu: Image = _menu_page.render(box, _submenu_labels(), _submenu_cursor)
		image.blend_rect(
			menu, Rect2i(Vector2i.ZERO, menu.get_size()),
			box.border_position() * Gen2Font.TILE
		)
	_view.texture = ImageTexture.create_from_image(image)


## `.GetTopCoord` for the mon's own submenu, and `GiveTakeItemMenuData`'s fixed
## box for the GIVE/TAKE it opens.
func _submenu_box() -> Gen2MenuBox:
	if _item_menu_open:
		return Gen2MenuBox.from_coords(
			ITEM_MENU_BOX.position.x, ITEM_MENU_BOX.position.y,
			ITEM_MENU_BOX.end.x, ITEM_MENU_BOX.end.y, Gen2MenuBox.STATICMENU_CURSOR
		)
	return Gen2MenuBox.from_coords(
		SUBMENU_LEFT, SUBMENU_BOTTOM + 1 - 2 * (_submenu_items.size() + 1),
		SUBMENU_RIGHT, SUBMENU_BOTTOM, Gen2MenuBox.STATICMENU_CURSOR
	)


## `PopulateMonMenu` places the option strings themselves. The "(unavailable)"
## the panel appends is the launcher's affordance and has no room in a box the
## cartridge sized for a name, so an option this project does not act on says so
## when it is chosen instead.
func _submenu_labels() -> Array:
	var out: Array = []
	for entry: Variant in _submenu_items:
		out.append(String((entry as Dictionary).get("label", "")))
	return out


func _build_ui() -> void:
	if _embedded:
		_build_hardware_ui()
		return
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_right", 64)
	margin.add_theme_constant_override("margin_bottom", 42)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	content.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 3)
	header.add_child(heading)
	var title := Label.new()
	title.text = "PARTY"
	title.add_theme_color_override("font_color", TEXT)
	title.add_theme_font_size_override("font_size", 32)
	heading.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Player party and persistent condition"
	subtitle.add_theme_color_override("font_color", MUTED)
	heading.add_child(subtitle)
	var back := _button("Close" if _embedded else "Back to save slots", TEXT)
	back.custom_minimum_size = Vector2(190, 44)
	back.pressed.connect(_back)
	_storage_button = _button("Open PC storage", ACCENT)
	_storage_button.custom_minimum_size = Vector2(170, 44)
	_storage_button.pressed.connect(_open_storage)
	_storage_button.visible = not _embedded
	header.add_child(_storage_button)
	header.add_child(back)

	_player_label = Label.new()
	_player_label.add_theme_color_override("font_color", ACCENT)
	_player_label.add_theme_font_size_override("font_size", 18)
	content.add_child(_player_label)

	var scroll: Gen2LauncherScroll = Gen2LauncherScroll.create()
	content.add_child(scroll)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 9)
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cards)

	_submenu = VBoxContainer.new()
	_submenu.add_theme_constant_override("separation", 4)
	_submenu.visible = false
	content.add_child(_submenu)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	content.add_child(footer)
	_battle_button = _button("Start development battle", ACCENT)
	_battle_button.pressed.connect(_start_battle)
	_battle_button.visible = not _embedded
	footer.add_child(_battle_button)
	_status = Label.new()
	_status.add_theme_color_override("font_color", MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_status)


## A refusal, in whichever box this view has: the menu's own bottom one when it
## is the cartridge's screen, and the panel's status line when it is not.
func _say(message: String) -> void:
	if _embedded:
		_message = message
		_render_hardware()
		return
	if _status == null:
		return
	_status.text = message
	_status.add_theme_color_override("font_color", MUTED)


func _refresh() -> void:
	if _embedded:
		_render_hardware()
		return
	if _cards == null:
		return
	Gen2LauncherUI.clear(_cards)
	if _player_label != null:
		_player_label.text = "Player: %s" % (_save.player_name if _save != null else "Unavailable")
	if _data == null or _save == null:
		_status.text = "No validated save selected."
		_status.add_theme_color_override("font_color", ERROR)
		return
	for index: int in Gen2SaveData.MAX_PARTY:
		_cards.add_child(_member_card(index))
	_render_submenu()
	_status.text = "Slot %d" % (_save.slot + 1)
	_status.add_theme_color_override("font_color", SUCCESS)


func _member_card(index: int) -> PanelContainer:
	var card := PanelContainer.new()
	var selected: bool = index == _member_cursor and index < _party_size()
	card.add_theme_stylebox_override(
		"panel", _panel_style(PANEL, ACCENT if selected else BORDER, 8)
	)
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	card.add_child(content)
	var number := Label.new()
	number.text = "%d" % (index + 1)
	number.custom_minimum_size = Vector2(28, 0)
	number.add_theme_color_override("font_color", ACCENT)
	number.add_theme_font_size_override("font_size", 20)
	content.add_child(number)
	if _save == null or index >= _save.party.size():
		var empty := Label.new()
		empty.text = "Empty"
		empty.add_theme_color_override("font_color", MUTED)
		content.add_child(empty)
		return card
	var mon: Gen2SaveMon = _save.party[index]
	var summary := VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_constant_override("separation", 3)
	content.add_child(summary)
	var name := Label.new()
	name.text = _display_name(mon)
	name.add_theme_color_override("font_color", TEXT)
	name.add_theme_font_size_override("font_size", 20)
	summary.add_child(name)
	var details := Label.new()
	details.text = "%s    Level %d    HP %d/%d" % [
		_species_name(mon.species), mon.level, mon.hp, _max_hp(mon)
	]
	details.add_theme_color_override("font_color", MUTED)
	summary.add_child(details)
	var condition := Label.new()
	condition.text = "Status: %s" % _status_name(mon.status)
	condition.add_theme_color_override("font_color", _status_color(mon.status))
	summary.add_child(condition)
	return card


func _member_snapshot(index: int, mon: Gen2SaveMon) -> Dictionary:
	return {
		"empty": false,
		"index": index,
		"name": _display_name(mon),
		"species": mon.species,
		"level": mon.level,
		"hp": mon.hp,
		"max_hp": _max_hp(mon),
		"status": _status_name(mon.status),
	}


func _max_hp(mon: Gen2SaveMon) -> int:
	var battle_mon: Gen2BattleMon = Gen2SaveBattleAdapter.to_battle_mon(_data, mon)
	return battle_mon.max_hp() if battle_mon != null else 0


func _display_name(mon: Gen2SaveMon) -> String:
	return mon.nickname if not mon.nickname.is_empty() else _species_name(mon.species)


func _species_name(species: int) -> String:
	return String(_data.species(species).get("name", "UNKNOWN")) if _data != null else "UNKNOWN"


func _status_name(status: int) -> String:
	var name: StringName = Gen2Status.name_of(status)
	return "OK" if name.is_empty() else String(name).to_upper()


func _status_color(status: int) -> Color:
	return SUCCESS if Gen2Status.name_of(status).is_empty() else ACCENT


func _start_battle() -> void:
	if _data == null or _save == null:
		return
	if not _select_slot():
		return
	get_tree().change_scene_to_file.call_deferred("res://game/battle/battle_screen.tscn")


func _back() -> void:
	if _embedded:
		close_embedded()
		return
	get_tree().change_scene_to_file.call_deferred("res://game/save/save_screen.tscn")


func close_embedded() -> void:
	if not _embedded:
		return
	closed.emit({"ok": true})


func _open_storage() -> void:
	if _data == null or _save == null:
		_status.text = "No validated save selected."
		_status.add_theme_color_override("font_color", ERROR)
		return
	if not _select_slot():
		return
	get_tree().change_scene_to_file.call_deferred("res://game/save/box_screen.tscn")


## Hands the slot to the runtime before changing scene, so the screen that opens
## next reads the same save this one is showing. False with the refusal already
## on screen when there is no runtime or the cartridge is not in the registry.
func _select_slot() -> bool:
	var runtime: Gen2GameRuntime = Gen2GameRuntime.instance()
	if runtime != null and runtime.select_save_slot(_data.id, _save.slot):
		return true
	_status.text = "The selected cartridge is not in the registry."
	_status.add_theme_color_override("font_color", ERROR)
	return false


func _button(text: String, colour: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_color_override("font_color", colour)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 14)
	return button


func _panel_style(fill: Color, line: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = line
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_top = 14
	style.content_margin_right = 18
	style.content_margin_bottom = 14
	return style
