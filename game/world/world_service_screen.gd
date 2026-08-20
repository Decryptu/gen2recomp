class_name Gen2WorldServiceScreen
extends Control

## Presentation host for imported overworld services. It owns only selection,
## labels and input. Script state and transactions stay in the scene-free world
## hosts and API.

signal completed(results: Array)

const PANEL: Color = Color("#14233a")
const BORDER: Color = Color("#4f6f9e")
const TEXT: Color = Color("#f4f7fb")
const MUTED: Color = Color("#9eacc0")
const ACCENT: Color = Color("#f3c969")
const SUCCESS: Color = Color("#7bd89a")
const ERROR: Color = Color("#ef8a8a")

enum MODE {
	MENU, MART, PHONE, AUDIO, POKEGEAR, TOWN_MAP, CARD,
	APRICORN, PC, PC_ITEMS, PC_ITEM_LIST, PC_TEXT,
}

## `PokemonCenterPC`'s own box storage, which is the one row that opens a screen
## rather than a list. It is added as a child the way the MAP card adds the
## region map, so the top menu is still there when the box screen closes.
const BOX_SCENE := preload("res://game/save/box_screen.tscn")

## `BuyMenu`'s own 160x144, which a window-resolution panel cannot host.
const HARDWARE_SCENE: PackedScene = preload("res://game/render/gen2_screen.tscn")

## engine/pokegear/pokegear.asm's card order. Each is behind its own
## wPokegearFlags bit, named here by the engine flag that carries it, since that
## is what the state holds. The clock card needs no flag.
const POKEGEAR_CARDS: Array[Dictionary] = [
	{"card": &"clock", "name": "CLOCK"},
	{"card": &"map", "name": "MAP", "flag": Gen2WorldState.ENGINE_MAP_CARD},
	{"card": &"phone", "name": "PHONE", "flag": Gen2WorldState.ENGINE_PHONE_CARD},
	{"card": &"radio", "name": "RADIO", "flag": Gen2WorldState.ENGINE_RADIO_CARD},
]

## `wPokegearRadioMusicPlaying`, which is what `ExitPokegearRadio_HandleMusic`
## branches on: zero while nothing in this overlay has touched the music, and
## one of the source's own two values once the radio card has.
const RADIO_MUSIC_SILENT: int = 0
const RADIO_MUSIC_RESTART_MAP: int = 0xFE
const RADIO_MUSIC_ENTER_MAP: int = 0xFF

const WorldMenu := preload("res://game/world/world_menu.gd")

## `BuyMenuLoop`'s four states: the list `ScrollingMenu` runs, the quantity
## `SelectQuantityToBuy` asks for, `MartConfirmPurchase`'s yes/no, and a box
## waiting on `JoyWaitAorB`.
const MART_LIST: StringName = &"list"
const MART_QUANTITY: StringName = &"quantity"
const MART_CONFIRM: StringName = &"confirm"
const MART_MESSAGE: StringName = &"message"
## Which of `GetMartDialogGroup.MartTextFunctionPointers`' groups a variant
## reads. The rooftop sale takes the standard group, which is why it has no
## prefix of its own; the bargain shop's `MARTTEXT_HOW_MANY` slot is
## `BuyMenuLoop` rather than a text, so it asks no quantity.
const MART_TEXT_PREFIX: Dictionary = {
	&"standard": "", &"bitter": "bitter_", &"bargain": "bargain_",
	&"pharmacy": "pharmacy_", &"rooftop_mart_1": "", &"rooftop_mart_2": "",
}
## `PlayTransactionSound`, once the money has been taken.
const SFX_TRANSACTION: int = 0x22
## `Textbox`'s interior, which is what a mart box's words are wrapped to.
const MART_TEXT_COLUMNS: int = 18
const MART_TEXT_ROWS: int = 2
## `hMoneyTemp` is HRAM and `wItemQuantityChange` is not, which is how a
## `text_decimal` marker says which of the two numbers it wants.
const HRAM_FIRST: int = 0xFF00

var _world: Gen2WorldAPI = null
var _data: GameData = null
var _save: Gen2SaveData = null
var _persist: bool = false
var _request: Dictionary = {}
var _resolved: Dictionary = {}
var _mode: int = -1
var _choices: Array = []
var _menu_input: Dictionary = {}
var _menu: Gen2WorldMenu = null
var _cursor: int = 0
var _mart: Dictionary = {}
var _mart_entries: Array = []
var _mart_quantity: int = 1
var _mart_purchased: bool = false
## `BuyMenu`'s screen, which owns all 160x144 the way the region map does: the
## scrolling list's own scroll and cursor, which of `BuyMenuLoop`'s four states
## it is in, and the boxes waiting on a press.
var _mart_hardware: Gen2Screen = null
var _mart_view: TextureRect = null
var _mart_page: Gen2MartPage = null
var _mart_menu_page: Gen2MenuPage = null
var _mart_stage: StringName = MART_LIST
var _mart_scroll: int = 0
var _mart_pages: Array = []
var _mart_after: StringName = MART_LIST
var _mart_confirm: int = 0
var _apricorns: Gen2WorldApricorn = null
var _pokegear_cards: Array = []
var _town_map: Gen2TownMapScreen = null
## The clock, phone or radio card while one is open, which is a hardware-
## resolution screen over this panel the way the region map is.
var _pokegear: Gen2PokegearScreen = null
## `wPokegearRadioMusicPlaying`. Only the radio card writes it, so an overlay
## that never opened one leaves the map's own music where it stands.
var _radio_music: int = RADIO_MUSIC_SILENT
## Whether the region map on screen is the fly map, which answers a spawn rather
## than closing back into the card list.
var _fly_map: bool = false
var _town_map_from_request: bool = false
## `PokemonCenterPC` and the item PC behind it: which rows are on offer, which
## of the three item lists is open, and the box screen when BILL'S PC is.
var _pc_rows: Array = []
var _pc_house: bool = false
var _pc_action: int = -1
var _pc_entries: Array = []
var _pc_quantity: int = 1
## The PC's own text boxes and what happens once the last is acknowledged:
## `PROF.OAK'S PC` returns to the top menu and `TURN OFF` shuts the machine down.
var _pc_pages: Array = []
var _pc_sfx: int = -1
var _pc_after: StringName = &"top"
var _pc_label: String = ""
var _boxes: Gen2BoxScreen = null

var _service_hardware: Gen2Screen = null
var _service_view: TextureRect = null
var _service_page: Gen2WorldServicePage = null
## `SetDayOfWeek`'s own dial, shared with the new game's `InitClock` screen.
var _clock_page: Gen2ClockSetPage = null

var _panel: PanelContainer = null
var _title: Label = null
var _summary: Label = null
var _options: VBoxContainer = null
var _status: Label = null
var _footer: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


## Opens the host for whatever pending input the world currently exposes.
func open_pending(
	world: Gen2WorldAPI,
	data: GameData,
	save: Gen2SaveData = null,
	persist: bool = false
) -> bool:
	_world = world
	_data = data
	_save = save
	_persist = persist
	if _world == null or _data == null:
		_show_error("Service host has no world or cartridge cache.")
		return false
	var input: Dictionary = _world.pending_script_input()
	var input_type: StringName = StringName(input.get("type", &""))
	if input_type in [&"choice", &"menu"]:
		_open_menu(input)
		return true
	var request: Dictionary = _world.pending_runtime_request()
	if request.is_empty():
		_show_error("No pending service request.")
		return false
	_request = request
	if StringName(request.get("kind", &"")) == &"town_map_requested":
		_open_town_map(true)
		return true
	var resolved: Dictionary = Gen2WorldHost.resolve_runtime_request(_world, request)
	if not bool(resolved.get("ok", false)):
		_show_error("Service unavailable: %s" % String(resolved.get("reason", "unknown")))
		return false
	_resolved = resolved
	match StringName(request.get("kind", &"")):
		&"mart_requested":
			_open_mart(resolved.get("data", {}).get("mart", {}))
			return true
		&"phone_call_requested", &"special_phone_call_requested":
			_open_phone(request, resolved.get("data", {}))
			return true
		&"audio_requested":
			_open_audio(request, resolved.get("data", {}).get("audio", {}))
			return true
		&"apricorn_selection_requested":
			_open_apricorns()
			return true
		&"pc_requested":
			_open_pc(StringName(resolved.get("data", {}).get("pc", {}).get("mode", &"")))
			return true
	_show_error("No scene host for %s." % String(request.get("kind", "request")))
	return false


func is_active() -> bool:
	return _mode >= 0


## Opens the Pokegear straight onto its PHONE card, which is what the overworld's
## own phone shortcut reaches.
func open_phone_list(
	world: Gen2WorldAPI,
	data: GameData,
	save: Gen2SaveData = null,
	persist: bool = false
) -> bool:
	if not _open_pokegear(world, data, save, persist, "Phone"):
		return false
	_open_card(Gen2PokegearScreen.CARD_PHONE)
	return true


## Opens the Pokegear on its card list. Only cards the player owns are
## selectable, in the source's own clock/map/phone/radio order.
func open_pokegear(
	world: Gen2WorldAPI,
	data: GameData,
	save: Gen2SaveData = null,
	persist: bool = false
) -> bool:
	if not _open_pokegear(world, data, save, persist, "Pokegear"):
		return false
	_open_pokegear_cards()
	return true


## `wPokegearFlags`: which cards the player owns, in the jumptable's own order.
func _open_pokegear(
	world: Gen2WorldAPI, data: GameData, save: Gen2SaveData, persist: bool, label: String
) -> bool:
	_world = world
	_data = data
	_save = save
	_persist = persist
	if _world == null or _data == null:
		_show_error("%s has no world or cartridge cache." % label)
		return false
	_pokegear_cards = []
	for card: Dictionary in POKEGEAR_CARDS:
		var owned: bool = not card.has("flag") \
			or _world.state.is_engine_flag_active(int(card["flag"]))
		if not owned:
			continue
		_pokegear_cards.append(card)
	return true


## Parent screens route buttons here so the service overlay owns input while open.
func handle_button(button: int) -> bool:
	if not is_active():
		return false
	if _mode == MODE.APRICORN:
		_press_apricorns(button)
		return true
	if _mode == MODE.MART:
		_press_mart(button)
		return true
	if _mode == MODE.CARD and _pokegear != null:
		return _pokegear.handle_button(button)
	## The panel is behind the box screen while BILL'S PC is open, the way it is
	## behind the region map, so the buttons are the box screen's.
	if _boxes != null:
		return _boxes.handle_button(button)
	if Gen2Button.is_direction(button):
		_move_direction(Gen2Button.vector(button))
		return true
	match button:
		Gen2Button.A:
			_confirm()
			return true
		Gen2Button.B:
			_cancel()
			return true
	return false


func selected_index() -> int:
	return _cursor


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(500, 300)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)
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

	_service_hardware = HARDWARE_SCENE.instantiate() as Gen2Screen
	_service_hardware.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_service_hardware.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_service_hardware.z_index = 4
	add_child(_service_hardware)
	_service_view = TextureRect.new()
	_service_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_service_view.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_service_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_service_hardware.display(_service_view)
	_panel.visible = false
	_service_hardware.visible = false


func _open_menu(input: Dictionary) -> void:
	_mode = MODE.MENU
	_menu_input = input.duplicate(true)
	_menu = WorldMenu.from_input(_menu_input)
	_choices = _menu.options.duplicate(true)
	_cursor = _menu.selected_index()
	_title.text = "MENU"
	## The question the box behind this menu is still showing. A command name is
	## an internal key, never something the cartridge prints, so it is not a
	## fallback: an unattached menu says nothing rather than saying "yesorno".
	_summary.text = String(input.get("text", ""))
	_status.text = ""
	_footer.text = "D-pad: move    A: choose    B: cancel"
	_render_options()


## `BuyMenu`, which is a screen of its own rather than a box over the map: the
## panel steps aside for it the way it does for the region map, and the shop's
## own intro box is the first thing it prints.
func _open_mart(mart: Dictionary) -> void:
	_mode = MODE.MART
	_mart = mart.duplicate(true)
	for row: Dictionary in Gen2ModHost.instance().mart_entries(_mart):
		(_mart["items"] as Array).append(row)
	_refresh_mart_entries()
	_mart_quantity = 1
	_mart_purchased = false
	_mart_scroll = 0
	_cursor = 0
	_panel.visible = false
	if _mart_hardware == null:
		_mart_hardware = HARDWARE_SCENE.instantiate() as Gen2Screen
		_mart_hardware.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_mart_hardware.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mart_hardware.z_index = 5
		add_child(_mart_hardware)
		_mart_view = TextureRect.new()
		_mart_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_mart_view.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
		_mart_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mart_hardware.display(_mart_view)
	_show_mart_text(_mart_text("intro"), MART_LIST)


## One of the shop's own boxes, by the slot name its group gives it.
func _mart_text(slot: String, filled: Dictionary = {}) -> String:
	var prefix: String = String(MART_TEXT_PREFIX.get(
		StringName(_mart_source().get("variant", &"standard")), ""
	))
	var slot_name: String = prefix + slot
	if slot == "intro" and prefix.is_empty():
		slot_name = "welcome"
	var text: String = _data.mart_text(slot_name)
	if text.is_empty():
		return ""
	return _fill_mart_markers(text, filled)


## `PartyMonItemName` and the two `text_decimal`s a mart box carries. The number
## markers are told apart by their address rather than by their order, since the
## bargain shop names the item first and the price second.
func _fill_mart_markers(text: String, filled: Dictionary) -> String:
	var out: String = Gen2TextStream.fill_marker(
		text, Gen2TextStream.RAM_MARKER, String(filled.get("name", ""))
	)
	while true:
		var at: int = out.find(Gen2TextStream.NUMBER_MARKER)
		if at < 0:
			break
		var end: int = out.find(">", at)
		if end < 0:
			break
		var address: int = out.substr(
			at + Gen2TextStream.NUMBER_MARKER.length(),
			end - at - Gen2TextStream.NUMBER_MARKER.length()
		).hex_to_int()
		out = out.substr(0, at) + String.num_int64(int(filled.get(
			"total" if address >= HRAM_FIRST else "quantity", 0
		))) + out.substr(end + 1)
	return out


## A box the shop is holding on, laid out into the pages `JoyWaitAorB` steps
## through. An empty text goes straight on, which is what a cache imported
## before the mart's own words leaves.
func _show_mart_text(text: String, after: StringName) -> void:
	_mart_after = after
	_mart_pages = [] if text.strip_edges().is_empty() \
		else Gen2TextLayout.lay_out(text, MART_TEXT_COLUMNS, MART_TEXT_ROWS)
	if _mart_pages.is_empty():
		_advance_mart_text()
		return
	_mart_stage = MART_MESSAGE
	_render_mart()


func _advance_mart_text() -> void:
	if not _mart_pages.is_empty():
		_mart_pages.remove_at(0)
	if not _mart_pages.is_empty():
		_render_mart()
		return
	if _mart_after == MART_LIST:
		_mart_stage = MART_LIST
		_render_mart()
		return
	_close_mart()
	_finish_runtime({"ok": true, "script_value": 1 if _mart_purchased else 0})


## `w2DMenuNumRows`: the CANCEL row is only on offer when the whole list fits,
## because `ScrollingMenu_InitFlags` adds it to the row count and `.d_down`
## stops scrolling at `size - height`.
func _mart_row_count() -> int:
	return _mart_entries.size() + 1 if _mart_entries.size() < Gen2MartPage.LIST_HEIGHT \
		else Gen2MartPage.LIST_HEIGHT


func _mart_rows() -> Array:
	var out: Array = []
	for row: int in _mart_row_count():
		var index: int = _mart_scroll + row
		out.append(
			{"cancel": true} if index >= _mart_entries.size() else _mart_entries[index]
		)
	return out


func _mart_selection() -> Dictionary:
	var index: int = _mart_scroll + _cursor
	return {} if index >= _mart_entries.size() else _mart_entries[index]


func _press_mart(button: int) -> void:
	match _mart_stage:
		MART_MESSAGE:
			if button in [Gen2Button.A, Gen2Button.B]:
				_advance_mart_text()
		MART_LIST:
			_press_mart_list(button)
		MART_QUANTITY:
			_press_mart_quantity(button)
		MART_CONFIRM:
			_press_mart_confirm(button)


func _press_mart_list(button: int) -> void:
	match button:
		Gen2Button.UP:
			_move_mart_cursor(-1)
		Gen2Button.DOWN:
			_move_mart_cursor(1)
		Gen2Button.B:
			_leave_mart()
		Gen2Button.A:
			var entry: Dictionary = _mart_selection()
			if entry.is_empty():
				_leave_mart()
				return
			if bool(entry.get("sold_out", false)):
				## `BargainShopAskPurchaseQuantity.SoldOut`, the one refusal that
				## comes before a price is ever named.
				_show_mart_text(_mart_text("sold_out", {"name": entry.get("name", "")}), MART_LIST)
				return
			_mart_quantity = 1
			if StringName(_mart_source().get("variant", &"")) == &"bargain":
				_ask_mart_confirm()
				return
			## `MARTTEXT_HOW_MANY` is printed before `SelectQuantityToBuy`, and
			## the box stays up under the dial rather than waiting on a press.
			_mart_pages = Gen2TextLayout.lay_out(
				_mart_text("how_many"), MART_TEXT_COLUMNS, MART_TEXT_ROWS
			)
			_mart_stage = MART_QUANTITY
			_render_mart()


func _move_mart_cursor(delta: int) -> void:
	var rows: int = _mart_row_count()
	var next: int = _cursor + delta
	if next < 0:
		if _mart_scroll > 0:
			_mart_scroll -= 1
	elif next >= rows:
		if _mart_entries.size() >= _mart_scroll + Gen2MartPage.LIST_HEIGHT:
			_mart_scroll += 1
	else:
		_cursor = next
	_render_mart()


## `BuySellToss_InterpretJoypad`: one on up and down, ten on left and right,
## against `wItemQuantity`, which `StandardMartAskPurchaseQuantity` sets to the
## whole stack rather than to what the money or the pack allows.
func _press_mart_quantity(button: int) -> void:
	var maximum: int = Gen2WorldMartHost.MAX_ITEM_STACK
	match button:
		Gen2Button.UP:
			_mart_quantity = 1 if _mart_quantity >= maximum else _mart_quantity + 1
		Gen2Button.DOWN:
			_mart_quantity = maximum if _mart_quantity <= 1 else _mart_quantity - 1
		Gen2Button.RIGHT:
			_mart_quantity = mini(_mart_quantity + 10, maximum)
		Gen2Button.LEFT:
			_mart_quantity = maxi(_mart_quantity - 10, 1)
		Gen2Button.B:
			_mart_stage = MART_LIST
		Gen2Button.A:
			_ask_mart_confirm()
			return
	_render_mart()


## `MartConfirmPurchase`: the price box and the yes/no over it.
func _ask_mart_confirm() -> void:
	var entry: Dictionary = _mart_selection()
	_mart_confirm = 0
	_mart_stage = MART_CONFIRM
	_mart_pages = Gen2TextLayout.lay_out(
		_mart_text("final_price", {
			"name": entry.get("name", ""),
			"quantity": _mart_quantity,
			"total": int(entry.get("price", 0)) * _mart_quantity,
		}),
		MART_TEXT_COLUMNS, MART_TEXT_ROWS
	)
	_render_mart()


func _press_mart_confirm(button: int) -> void:
	match button:
		Gen2Button.UP, Gen2Button.DOWN:
			_mart_confirm = 1 - _mart_confirm
		Gen2Button.B:
			_mart_stage = MART_LIST
		Gen2Button.A:
			if _mart_confirm == 0:
				_buy_mart_selection()
				return
			_mart_stage = MART_LIST
	_render_mart()


## The transaction itself, and whichever of `BuyMenuLoop`'s three answers it
## earns: too little money, no room in the pack, or the shop's own thanks.
func _buy_mart_selection() -> void:
	var entry: Dictionary = _mart_selection()
	var purchase: Dictionary = Gen2WorldMartHost.purchase(
		_world, _save, _mart_source(), int(entry.get("item", 0)), _mart_quantity, _persist
	)
	if not bool(purchase.get("ok", false)):
		var reason: StringName = StringName(purchase.get("reason", &""))
		var slot: String = {
			&"insufficient_money": "no_money", &"item_stack_full": "pack_full",
			&"bargain_item_sold_out": "sold_out",
		}.get(reason, "")
		if slot.is_empty():
			_status.text = "Purchase failed: %s" % String(reason)
			_status.add_theme_color_override("font_color", ERROR)
			_mart_stage = MART_LIST
			_render_mart()
			return
		_show_mart_text(_mart_text(slot, {"name": entry.get("name", "")}), MART_LIST)
		return
	_mart_purchased = true
	Gen2WorldAudioHost.play(_data.world_audio(&"sfx", SFX_TRANSACTION), &"sound")
	_refresh_mart_entries()
	_show_mart_text(_mart_text("thanks", {
		"name": purchase.get("name", ""), "quantity": _mart_quantity,
		"total": int(purchase.get("total", 0)),
	}), MART_LIST)


func _leave_mart() -> void:
	_show_mart_text(_mart_text("come_again"), &"exit")


func _close_mart() -> void:
	if _mart_hardware != null:
		_mart_hardware.queue_free()
		_mart_hardware = null
		_mart_view = null
	_panel.visible = true
	_service_hardware.visible = true


func _render_mart() -> void:
	if _mart_view == null or _data == null:
		return
	if _mart_page == null:
		_mart_page = Gen2MartPage.from_data(_data)
	if _mart_page == null:
		return
	var page: PackedStringArray = _mart_pages[0] if not _mart_pages.is_empty() \
		else PackedStringArray()
	var image: Image = _mart_page.render({
		"money": _world.state.money(Gen2WorldMartHost.MONEY_ACCOUNT),
		"rows": _mart_rows(),
		"cursor": _cursor if _mart_stage == MART_LIST else -1,
		"scrolled": _mart_scroll > 0,
		"text": "\n".join(page) if _mart_stage != MART_LIST else _mart_description(),
		## `StandardMartAskPurchaseQuantity` closes the dial with `ExitMenu`
		## before `MartConfirmPurchase` prints, so the box is the quantity
		## stage's alone.
		"quantity": _mart_quantity if _mart_stage == MART_QUANTITY else -1,
		"subtotal": int(_mart_selection().get("price", 0)) * _mart_quantity,
	})
	if image == null:
		return
	if _mart_stage == MART_CONFIRM:
		if _mart_menu_page == null:
			_mart_menu_page = Gen2MenuPage.from_data(_data)
		if _mart_menu_page != null:
			var box: Gen2MenuBox = _mart_yes_no_box()
			var menu: Image = _mart_menu_page.render(
				box, ["YES", "NO"], _mart_confirm
			)
			image.blend_rect(
				menu, Rect2i(Vector2i.ZERO, menu.get_size()),
				box.border_position() * Gen2Font.TILE
			)
	_mart_view.texture = ImageTexture.create_from_image(image)


## `YesNoBox`'s own `lb bc, SCREEN_WIDTH - 6, 7`, which `_YesNoBox` turns into
## the five-wide, four-tall box at (14,7).
func _mart_yes_no_box() -> Gen2MenuBox:
	return Gen2MenuBox.from_coords(
		14, 7, 19, 11,
		Gen2MenuBox.STATICMENU_CURSOR | Gen2MenuBox.STATICMENU_NO_TOP_SPACING
	)


## `UpdateItemDescription`, which prints nothing for the CANCEL row.
func _mart_description() -> String:
	var entry: Dictionary = _mart_selection()
	if entry.is_empty():
		return ""
	return String(_data.item(int(entry.get("item", 0))).get("description", ""))


## `SelectApricornForKurt`'s two boxes. The model owns both cursors and the loop
## between them, so this only draws whichever one it is on.
func _open_apricorns() -> void:
	_mode = MODE.APRICORN
	_apricorns = Gen2WorldApricorn.open(_world.data, _world.state)
	_title.text = "APRICORNS"
	if _apricorns.is_done():
		## FindApricornsInBag's own refusal. Kurt only asks with one in the bag,
		## so this is the guard rather than a branch a player reaches.
		_finish_apricorns()
		return
	_render_apricorns()


func _render_apricorns() -> void:
	if _apricorns.phase == Gen2WorldApricorn.SELECT_QUANTITY:
		_cursor = 0
		var chosen: Dictionary = _apricorns.selected_entry()
		_summary.text = "How many should I make?"
		## `PlaceApricornQuantity` draws the name and `×NN` under it; the
		## ceiling is this host's own, since nothing here draws a bag page.
		_status.text = "x%d    of %d" % [
			_apricorns.prompt.value, _apricorns.prompt.maximum,
		]
		_status.add_theme_color_override("font_color", TEXT)
		_footer.text = "Up/down: one    Left/right: ten    A: give    B: back"
		_render_options([String(chosen.get("name", ""))])
		return
	_summary.text = "Which APRICORN should I use?"
	_status.text = ""
	_footer.text = "D-pad: move    A: choose    B: leave"
	_render_options(_apricorn_rows())


## The four-row window the scrolling menu shows, CANCEL included when the list
## is short enough for it. `_cursor` is the row inside that window.
func _apricorn_rows() -> Array:
	var rows: Array = []
	for row: int in _apricorns.rows():
		var index: int = _apricorns.scroll + row
		if index >= _apricorns.entries.size():
			rows.append("CANCEL")
			break
		var entry: Dictionary = _apricorns.entries[index]
		rows.append("%-12s x%2d" % [String(entry.get("name", "")), int(entry.get("quantity", 0))])
	_cursor = _apricorns.cursor_y - 1
	return rows


func _press_apricorns(button: int) -> void:
	_apricorns.press(button)
	if _apricorns.is_done():
		_finish_apricorns()
		return
	_render_apricorns()


func _finish_apricorns() -> void:
	var answer: Dictionary = _apricorns.result()
	_apricorns = null
	_finish_runtime({"ok": true, "item": answer["item"], "quantity": answer["quantity"]})


## `PokemonCenterPC`'s top menu, or `_PlayersHousePC`'s item PC when the script
## asked for the bedroom's. `PC_CheckPartyForPokemon` is the one refusal either
## has before it opens.
func _open_pc(mode: StringName) -> void:
	_pc_house = mode == &"players_house"
	if not _pc_house and not Gen2WorldPC.can_open(_save):
		## `.PokecenterPCCantUseText`: the machine answers and shuts down again.
		_finish_runtime({"ok": true, "script_value": 0, "cancelled": true})
		return
	if _pc_house:
		_open_pc_items()
		return
	_mode = MODE.PC
	_cursor = 0
	_pc_rows = Gen2WorldPC.top_menu(
		_data, _world.state, _save.player_name if _save != null else ""
	)
	_title.text = "PC"
	_summary.text = _data.pokecenter_pc_text("whose")
	_status.text = ""
	_status.add_theme_color_override("font_color", MUTED)
	_footer.text = "D-pad: move    A: choose    B: turn off"
	_render_options()


## The item PC's own menu. The Pokemon Center's list ends in LOG OFF because the
## top menu is still open behind it; the bedroom's ends in TURN OFF.
func _open_pc_items() -> void:
	_mode = MODE.PC_ITEMS
	_cursor = 0
	_pc_action = -1
	_pc_rows = Gen2WorldPC.players_pc_menu(_data, _pc_house)
	_title.text = _data.pokecenter_pc_row("players_pc").replace(
		Gen2WorldPC.PLAYER_MARKER,
		_save.player_name if _save != null and not _save.player_name.is_empty()
		else "PLAYER"
	)
	_summary.text = _data.pokecenter_pc_text("ask_what_do")
	_refresh_pc_counts()
	_footer.text = "D-pad: move    A: choose    B: back"
	_render_options()


## Whichever of the bag and the PC the chosen action reads.
func _open_pc_item_list(action: int) -> void:
	_pc_action = action
	_cursor = 0
	_pc_quantity = 1
	_refresh_pc_entries()
	if _pc_entries.is_empty():
		## `.CheckItemsInBag`'s `.PlayersPCNoItemsText`, which the source prints
		## for a deposit. The other two open an empty scrolling menu there, which
		## can only be cancelled, so they are refused with the same box rather
		## than drawn empty.
		_status.text = _data.pokecenter_pc_text("no_items")
		_status.add_theme_color_override("font_color", ERROR)
		_render_options()
		return
	_mode = MODE.PC_ITEM_LIST
	## `SelectQuantityToToss` is asked before the move, so the box that names it
	## is the list's own prompt here.
	_summary.text = {
		Gen2WorldPC.PLAYERSPCITEM_WITHDRAW_ITEM: "how_many_withdraw",
		Gen2WorldPC.PLAYERSPCITEM_DEPOSIT_ITEM: "how_many_deposit",
	}.get(action, "")
	_summary.text = _data.pokecenter_pc_text(_summary.text) if not _summary.text.is_empty() \
		else _data.menu_text("toss_ask")
	_footer.text = "D-pad: move and quantity    A: choose    B: back"
	_render_options()


func _refresh_pc_entries() -> void:
	_pc_entries = Gen2WorldPC.bag_entries(_data, _world.state) \
		if _pc_action == Gen2WorldPC.PLAYERSPCITEM_DEPOSIT_ITEM \
		else Gen2WorldPC.pc_entries(_data, _world.state)
	_cursor = mini(_cursor, maxi(0, _pc_entries.size() - 1))
	_refresh_pc_counts()


func _refresh_pc_counts() -> void:
	_status.text = "PC %d/%d stacks" % [
		_world.state.pc_items().size(), Gen2WorldPack.MAX_PC_ITEMS,
	]
	_status.add_theme_color_override("font_color", MUTED)


func _confirm_pc_row() -> void:
	if _cursor < 0 or _cursor >= _pc_rows.size():
		return
	var row: int = int(_pc_rows[_cursor].get("row", -1))
	if _mode == MODE.PC:
		match row:
			Gen2WorldPC.PCPCITEM_BILLS_PC:
				_open_boxes()
			Gen2WorldPC.PCPCITEM_PLAYERS_PC:
				_open_pc_items()
			Gen2WorldPC.PCPCITEM_OAKS_PC:
				_open_pc_oak()
			Gen2WorldPC.PCPCITEM_TURN_OFF:
				## `TurnOffPC` prints before `.shutdown` runs.
				_open_pc_text(
					[_data.pokecenter_pc_text("closed")], &"close", "TURN OFF"
				)
		return
	match row:
		Gen2WorldPC.PLAYERSPCITEM_WITHDRAW_ITEM, \
		Gen2WorldPC.PLAYERSPCITEM_DEPOSIT_ITEM, \
		Gen2WorldPC.PLAYERSPCITEM_TOSS_ITEM:
			_open_pc_item_list(row)
		Gen2WorldPC.PLAYERSPCITEM_LOG_OFF:
			_open_pc(&"pokemon_center")
		Gen2WorldPC.PLAYERSPCITEM_TURN_OFF:
			_finish_runtime({"ok": true, "script_value": 0})


func _confirm_pc_item() -> void:
	if _cursor < 0 or _cursor >= _pc_entries.size():
		_open_pc_items()
		return
	var entry: Dictionary = _pc_entries[_cursor]
	var item: int = int(entry.get("item", 0))
	var applied: Dictionary = {}
	match _pc_action:
		Gen2WorldPC.PLAYERSPCITEM_WITHDRAW_ITEM:
			applied = Gen2WorldPC.withdraw(_world, _save, item, _pc_quantity, _persist)
		Gen2WorldPC.PLAYERSPCITEM_DEPOSIT_ITEM:
			applied = Gen2WorldPC.deposit(_world, _save, item, _pc_quantity, _persist)
		_:
			applied = Gen2WorldPC.toss(_world, _save, item, _pc_quantity, _persist)
	if not bool(applied.get("ok", false)):
		## `.PackFull` and `.NoRoomInPC` are the two the source has a box for;
		## everything else is a refusal it never reaches.
		var reason: StringName = StringName(applied.get("reason", &""))
		_status.text = {
			&"pc_full": "no_room_deposit", &"pack_full": "no_room_withdraw",
			&"item_stack_full": "no_room_withdraw",
		}.get(reason, "")
		_status.text = _data.pokecenter_pc_text(_status.text) if not _status.text.is_empty() \
			else "Refused: %s" % String(reason)
		_status.add_theme_color_override("font_color", ERROR)
		return
	_pc_quantity = 1
	_refresh_pc_entries()
	## `.PlayersPCWithdrewItemsText` and `.PlayersPCDepositItemsText`, whose two
	## markers `PartyMonItemName` and the quantity fill.
	_status.text = _filled(
		_data.pokecenter_pc_text(
			"withdrew" if _pc_action == Gen2WorldPC.PLAYERSPCITEM_WITHDRAW_ITEM
			else "deposited"
		),
		applied
	) if _pc_action != Gen2WorldPC.PLAYERSPCITEM_TOSS_ITEM else _filled(
		_data.menu_text("toss_threw"), applied
	)
	_status.add_theme_color_override("font_color", SUCCESS)
	_render_options()


## The item name and the quantity into whichever markers the box left for them.
func _filled(text: String, applied: Dictionary) -> String:
	var out: String = Gen2TextStream.fill_marker(
		text, Gen2TextStream.NUMBER_MARKER, String.num_int64(int(applied.get("quantity", 0)))
	)
	return Gen2TextStream.fill_marker(
		out, Gen2TextStream.RAM_MARKER, String(applied.get("name", ""))
	)


func _change_pc_quantity(step: int) -> void:
	if _cursor < 0 or _cursor >= _pc_entries.size():
		return
	var owned: int = int(_pc_entries[_cursor].get("quantity", 1))
	_pc_quantity = clampi(_pc_quantity + step, 1, maxi(1, owned))
	_render_options()


## `OaksPC`, which prints `ProfOaksPC`'s rating into the PC's own box and
## returns to the loop. A cache with no rating table has nothing to print, which
## is what an empty boot says.
func _open_pc_oak() -> void:
	var boot: Dictionary = Gen2ProfOaksPC.boot(_data, _world.state)
	if boot.is_empty():
		_status.text = "PROF.OAK'S PC needs a cache that carries its ratings."
		_status.add_theme_color_override("font_color", ERROR)
		return
	_pc_sfx = int(boot["sfx"])
	_open_pc_text(boot["pages"], &"top", "PROF.OAK'S PC")


## A run of the PC's own boxes, acknowledged one at a time.
func _open_pc_text(pages: Array, after: StringName, label: String) -> void:
	_mode = MODE.PC_TEXT
	_pc_pages = pages.duplicate()
	_pc_after = after
	_cursor = 0
	_pc_label = label
	_show_pc_page()


func _show_pc_page() -> void:
	_summary.text = String(_pc_pages[0]) if not _pc_pages.is_empty() else ""
	_status.text = ""
	_status.add_theme_color_override("font_color", MUTED)
	_footer.text = "A: continue"
	_render_options([_pc_label])


## `ProfOaksPCBoot` plays the sound `Rate` chose once the rating is printed, so
## the last page is where it lands.
func _advance_pc_text() -> void:
	if not _pc_pages.is_empty():
		_pc_pages.remove_at(0)
	if not _pc_pages.is_empty():
		_show_pc_page()
		return
	if _pc_sfx >= 0:
		Gen2WorldAudioHost.play(_data.world_audio(&"sfx", _pc_sfx), &"sound")
	_pc_sfx = -1
	if _pc_after == &"close":
		_finish_runtime({"ok": true, "script_value": 0})
		return
	_open_pc(&"pokemon_center")


## BILL'S PC. The panel steps aside for the box screen the way it does for the
## region map, so the top menu is still there when the boxes close.
func _open_boxes() -> void:
	var host: Gen2BoxScreen = BOX_SCENE.instantiate() as Gen2BoxScreen
	if host == null or _save == null:
		_status.text = "Box storage needs a validated save."
		_status.add_theme_color_override("font_color", ERROR)
		return
	_boxes = host
	_panel.visible = false
	_service_hardware.visible = false
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.z_index = 5
	add_child(host)
	host.set_context(_data, _save, _persist, true)
	host.closed.connect(_on_boxes_closed)


## `Gen2BoxScreen.closed` carries the result its own host would have resumed a
## script with; nothing is waiting here, because the PC's request is still open.
func _on_boxes_closed(_result: Dictionary) -> void:
	if _boxes != null:
		_boxes.queue_free()
		_boxes = null
	_panel.visible = true
	_service_hardware.visible = true
	_open_pc(&"pokemon_center")


func _open_phone(request: Dictionary, data: Dictionary) -> void:
	_mode = MODE.PHONE
	_cursor = 0
	_title.text = "PHONE"
	var summary: Dictionary = {}
	if StringName(request.get("kind", &"")) == &"phone_call_requested":
		summary = Gen2WorldPhoneHost.contact_summary(
			_data, data.get("contact", {})
		)
		_summary.text = _phone_text(summary)
	else:
		summary = Gen2WorldPhoneHost.special_call_summary(
			_data, data.get("special_call", {})
		)
		_summary.text = "Special call %d for contact %d." % [
			int(summary.get("index", -1)), int(summary.get("contact", -1)),
		]
	_status.text = "The imported call record is ready."
	if bool(data.get("out_of_area", false)):
		_status.text = "This call will use the cartridge out-of-area script."
	elif bool(data.get("phone", {}).get("same_map", false)):
		_status.text = "This call will use the cartridge same-map script."
	_footer.text = "A: continue    B: hang up"
	_render_options(["Continue"])


func _open_pokegear_cards() -> void:
	_mode = MODE.POKEGEAR
	_cursor = 0
	_title.text = "POKEGEAR"
	var clock: Dictionary = _world.world_clock()
	_summary.text = "%02d:%02d" % [int(clock.get("hour", 0)), int(clock.get("minute", 0))]
	_status.text = "Choose a card."
	_footer.text = "D-pad: move    A: open    B: close"
	_render_options()


## The clock, phone and radio cards, each on the hardware's own tile grid the way
## the MAP card is. The card list stays this panel's, so a card is opened over it
## and closing one comes back to the list.
func _open_card(card: StringName) -> void:
	_mode = MODE.CARD
	_cursor = 0
	_panel.visible = false
	_service_hardware.visible = false
	_pokegear = Gen2PokegearScreen.new()
	_pokegear.z_index = 5
	add_child(_pokegear)
	_pokegear.closed.connect(_on_card_closed)
	_pokegear.switched.connect(_on_card_switched)
	_pokegear.tuned.connect(_on_card_tuned)
	_pokegear.called.connect(_on_card_called)
	_pokegear.deleted.connect(_on_card_deleted)
	var owned: Array = []
	for entry: Dictionary in _pokegear_cards:
		owned.append(StringName(entry.get("card", &"")))
	var text: String = ""
	if card == Gen2PokegearScreen.CARD_CLOCK:
		text = _data.pokegear_text("press_button")
	elif card == Gen2PokegearScreen.CARD_PHONE:
		text = _data.pokegear_text("ask_who")
	if not _pokegear.open(
		_data, card, owned, text, _data.pokegear_text("ask_delete"),
		_world.map_time_of_day()
	):
		_on_card_closed()
		return
	_refresh_card()


## What the open card reads off the world, which is all of its display state.
func _refresh_card() -> void:
	if _pokegear == null:
		return
	match _pokegear.card():
		Gen2PokegearScreen.CARD_CLOCK:
			var clock: Dictionary = _world.world_clock()
			_pokegear.set_clock(
				int(clock.get("day", 0)), int(clock.get("hour", 0)),
				int(clock.get("minute", 0))
			)
		Gen2PokegearScreen.CARD_RADIO:
			var tuned: Dictionary = _world.radio_station()
			# `RadioMusicRestartDE` on a station and `NoRadioMusic` on dead air:
			# either way the card has taken the music off the map, which is what
			# makes the exit restart it.
			_radio_music = RADIO_MUSIC_RESTART_MAP if bool(tuned.get("ok", false)) \
				else RADIO_MUSIC_ENTER_MAP
			var radio_show: Gen2RadioShow = _world.radio_show()
			_pokegear.set_radio(
				_world.state.radio_knob(),
				String(tuned.get("name", "")) if bool(tuned.get("ok", false)) else "",
				radio_show.lines() if radio_show != null else PackedStringArray()
			)
		Gen2PokegearScreen.CARD_PHONE:
			_pokegear.set_contacts(
				_world.registered_phone_contacts(),
				Gen2WorldPhoneHost.map_has_phone_service(_world.current_map)
			)


## `Pokegear_SwitchPage`: the next or previous card the player owns, with no wrap
## at either end. The clock is always there and is where the Pokegear opens.
func _on_card_switched(direction: int) -> void:
	var order: Array = []
	for entry: Dictionary in _pokegear_cards:
		order.append(StringName(entry.get("card", &"")))
	var at: int = order.find(_pokegear.card()) + direction
	if at < 0 or at >= order.size():
		return
	var card: StringName = order[at]
	if card == &"map":
		# The MAP card is the region map's own screen, and closing it comes back
		# to the card list rather than to the card this left.
		_close_card()
		_open_town_map(false)
		return
	_close_card()
	_open_card(card)


## `wPokegearRadioMusicPlaying`, for the host that owns the driver:
## `ExitPokegearRadio_HandleMusic` restarts the map's music only when the radio
## card has played something over it, and every other service leaves it alone.
## The restart lands when this overlay closes rather than when the card does,
## since the card list is this panel rather than the Pokegear's own screen.
func radio_music_playing() -> int:
	return _radio_music


## One hardware frame of whichever card is open. Only the radio card spends any:
## `PlayRadioShow` is the one thing the Pokegear runs per frame.
func advance_frame() -> void:
	if _pokegear == null or _pokegear.card() != Gen2PokegearScreen.CARD_RADIO:
		return
	if _world.advance_radio_frame():
		_refresh_card()


func _on_card_tuned(knob: int) -> void:
	_world.tune_radio(knob)
	_refresh_card()


func _on_card_called(contact: int) -> void:
	var results: Array = _world.request_outgoing_phone_call(contact)
	_close_card()
	_panel.visible = true
	_service_hardware.visible = true
	_mode = -1
	completed.emit(results)


## `PokegearPhone_DeletePhoneNumber`, which clears the slot and closes the gap
## behind it. The list here is a set, so dropping the contact is the whole of it.
func _on_card_deleted(contact: int) -> void:
	var changed: Dictionary = _world.state.apply_changes({}, {}, {
		"phone_contacts": {contact: false},
	})
	if bool(changed.get("ok", false)):
		_refresh_card()


func _on_card_closed() -> void:
	if _pokegear != null and _pokegear.card() == Gen2PokegearScreen.CARD_RADIO:
		_world.close_radio()
	_close_card()
	_panel.visible = true
	_service_hardware.visible = true
	_open_pokegear_cards()


func _close_card() -> void:
	if _pokegear == null:
		return
	_pokegear.queue_free()
	_pokegear = null


## `_FlyMap` opened as an overlay of its own: the region map with the flypoint
## cursor, and nothing of the Pokegear around it.
##
## The chosen spawn is reported through [signal completed] as
## `{ "kind": &"fly_chosen", "spawn": index }`, and a cancel reports -1, which is
## the `ld a, -1` `.pressedB` leaves.
func open_fly_map(
	world: Gen2WorldAPI, data: GameData, save: Gen2SaveData, request: Dictionary
) -> bool:
	_world = world
	_data = data
	_save = save
	_persist = false
	if _world == null or _data == null:
		_show_error("The region map has no world or cartridge cache.")
		return false
	_mode = MODE.TOWN_MAP
	_town_map_from_request = false
	_fly_map = true
	_panel.visible = false
	_service_hardware.visible = false
	_town_map = Gen2TownMapScreen.new()
	_town_map.z_index = 5
	add_child(_town_map)
	_town_map.closed.connect(_on_town_map_closed)
	var visited: Array[int] = []
	for index: Variant in request.get("visited", []):
		visited.append(int(index))
	var opened: bool = _town_map.open_fly(
		_data,
		_world.landmark(),
		bool(request.get("in_kanto", false)),
		visited,
		_save != null and _save.gender == Gen2SaveData.GENDER_FEMALE,
		_world.map_time_of_day(),
	)
	if not opened:
		_on_town_map_closed()
		return false
	return true


func _open_town_map(from_request: bool) -> void:
	_mode = MODE.TOWN_MAP
	_town_map_from_request = from_request
	# The region map is the whole screen, so the card list's own panel goes with
	# its labels; the scrim behind it stays as the overlay's backdrop.
	_panel.visible = false
	_service_hardware.visible = false
	_town_map = Gen2TownMapScreen.new()
	_town_map.z_index = 5
	add_child(_town_map)
	_town_map.closed.connect(_on_town_map_closed)
	# The Pokegear's own MAP card when the Pokegear opened it, `_TownMap`'s
	# corner box when `OverworldTownMap` did.
	var owned: Array = []
	for card: Dictionary in _pokegear_cards:
		owned.append(StringName(card.get("card", &"")))
	var screen: StringName = Gen2TownMap.SCREEN_TOWN_MAP if from_request \
		else Gen2TownMap.SCREEN_POKEGEAR_CARD
	var opened: bool = _town_map.open(
		_data,
		_world.landmark(),
		_world.state.hall_of_fame(),
		screen,
		owned,
		_save != null and _save.gender == Gen2SaveData.GENDER_FEMALE,
		_world.map_time_of_day(),
	)
	if not opened:
		_on_town_map_closed()


func _on_town_map_closed() -> void:
	var chosen: int = _town_map.chosen_spawn() if _town_map != null else -1
	if _town_map != null:
		_town_map.queue_free()
		_town_map = null
	_panel.visible = true
	_service_hardware.visible = true
	if _fly_map:
		_fly_map = false
		_mode = -1
		completed.emit([{"kind": &"fly_chosen", "spawn": chosen}])
		return
	if _town_map_from_request:
		_town_map_from_request = false
		_finish_runtime({"ok": true, "script_value": 1})
		return
	_mode = -1
	completed.emit([])


func _open_audio(request: Dictionary, record: Dictionary) -> void:
	_mode = MODE.AUDIO
	_cursor = 0
	_title.text = "AUDIO HOST"
	var kind: StringName = StringName(request.get("values", {}).get("kind", &"audio"))
	var playback: Dictionary = Gen2WorldAudioHost.play(record, kind)
	_summary.text = "Resolved %s %s:%04X (%d bytes)." % [
		String(kind), int(record.get("bank", -1)), int(record.get("address", -1)),
		int(record.get("byte_count", 0)),
	]
	_status.text = "Audio resolved for shared runtime: %s" % String(
		playback.get("backend", "unavailable")
	)
	_footer.text = "A: continue    B: stop"
	_render_options(["Continue"])


func _move_cursor(delta: int) -> void:
	var count: int = _option_count()
	if count <= 0:
		return
	_cursor = wrapi(_cursor + delta, 0, count)
	if _mode == MODE.PC_ITEM_LIST:
		_pc_quantity = 1
	_render_options()


func _move_direction(direction: Vector2i) -> void:
	if _mode == MODE.TOWN_MAP and _town_map != null:
		_town_map.handle_button(Gen2Button.from_vector(direction))
		return
	if _mode == MODE.MENU and _menu != null:
		if _menu.move(direction):
			_cursor = _menu.selected_index()
			_render_options()
		return
	if _mode == MODE.PC_ITEM_LIST and direction.x != 0:
		_change_pc_quantity(direction.x)
		return
	if direction.x != 0:
		_move_cursor(direction.x)
	else:
		_move_cursor(direction.y)


func _confirm() -> void:
	if _mode in [MODE.PC, MODE.PC_ITEMS]:
		_confirm_pc_row()
		return
	if _mode == MODE.PC_ITEM_LIST:
		_confirm_pc_item()
		return
	if _mode == MODE.PC_TEXT:
		_advance_pc_text()
		return
	if _mode == MODE.MENU:
		if _choices.is_empty():
			_status.text = "The imported menu has no selectable options."
			_status.add_theme_color_override("font_color", ERROR)
			return
		_finish_input(_cursor)
		return
	if _mode == MODE.POKEGEAR:
		if _cursor >= _pokegear_cards.size():
			return
		var card: Dictionary = _pokegear_cards[_cursor]
		if bool(card.get("unavailable", false)):
			_status.text = "%s is not implemented." % String(card.get("name", ""))
			_status.add_theme_color_override("font_color", ERROR)
			return
		var chosen: StringName = StringName(card.get("card", &""))
		if chosen == &"map":
			_open_town_map(false)
		else:
			_open_card(chosen)
		return
	if _mode in [MODE.PHONE, MODE.AUDIO]:
		_finish_runtime({"ok": true, "script_value": 1})


func _cancel() -> void:
	if _mode == MODE.PC:
		## `.shutdown`: B off the top menu is the same shut-down TURN OFF is.
		_finish_runtime({"ok": true, "script_value": 0})
	elif _mode == MODE.PC_ITEMS:
		if _pc_house:
			_finish_runtime({"ok": true, "script_value": 0})
		else:
			_open_pc(&"pokemon_center")
	elif _mode == MODE.PC_ITEM_LIST:
		_open_pc_items()
	elif _mode == MODE.PC_TEXT:
		## Both `PromptButton` answers advance the box; neither leaves early.
		_advance_pc_text()
	elif _mode == MODE.MENU:
		_finish_input_cancelled()
	elif _mode == MODE.POKEGEAR:
		_mode = -1
		completed.emit([])
	elif _mode in [MODE.PHONE, MODE.AUDIO]:
		_finish_runtime({"ok": true, "script_value": 0, "cancelled": true})
	elif _mode == MODE.TOWN_MAP and _town_map != null:
		_town_map.close()


func _finish_input(choice: int) -> void:
	var results: Array = _world.choose_script_input(choice)
	_finish(results)


func _finish_input_cancelled() -> void:
	var results: Array = _world.cancel_script_input()
	_finish(results)


func _finish_runtime(result: Dictionary) -> void:
	var host_result: Dictionary = Gen2WorldHost.complete_runtime_request(
		_world, result, _save, _persist
	)
	if not bool(host_result.get("ok", false)):
		_status.text = "Request failed: %s" % String(host_result.get("reason", "unknown"))
		_status.add_theme_color_override("font_color", ERROR)
		return
	_finish(host_result.get("results", []))


func _finish(results: Array) -> void:
	_mode = -1
	_close_mart()
	completed.emit(results)


func _render_options(override: Array = []) -> void:
	if _options == null:
		return
	for child: Node in _options.get_children():
		child.queue_free()
	var parent: Container = _options
	if _mode == MODE.MENU and _menu != null and _menu.kind == &"2d":
		var grid := GridContainer.new()
		grid.columns = maxi(1, _menu.columns)
		grid.add_theme_constant_override("h_separation", 18)
		_options.add_child(grid)
		parent = grid
	if _is_dial() and override.is_empty():
		## One value at a time, the way the dial itself shows it.
		override = [_choices[clampi(_cursor, 0, _choices.size() - 1)]] if not _choices.is_empty() \
			else []
	var values: Array = override if not override.is_empty() else (
		_choices if _mode == MODE.MENU \
		else _pc_rows if _mode in [MODE.PC, MODE.PC_ITEMS] \
		else _pc_entries if _mode == MODE.PC_ITEM_LIST \
		else _pokegear_cards if _mode == MODE.POKEGEAR else ["Continue"]
	)
	for index: int in values.size():
		var value: Variant = values[index]
		var label := Label.new()
		var text: String = str(value)
		if value is Dictionary:
			var dictionary: Dictionary = value as Dictionary
			text = str(dictionary.get("name", ""))
			if text.is_empty():
				text = str(dictionary.get("caller_label", ""))
			if text.is_empty():
				text = str(dictionary.get("trainer_name", "UNKNOWN"))
			if text.is_empty() and dictionary.has("index"):
				text = "CONTACT %d" % int(dictionary.get("index", -1))
		if value is Dictionary and _mode == MODE.PC_ITEM_LIST:
			var stack: int = int((value as Dictionary).get("quantity", 0))
			text = "%s    x%d of %d" % [text, _pc_quantity, stack] if index == _cursor \
				else "%s    x%d" % [text, stack]
		label.text = ("> " if index == _cursor else "  ") + text
		label.add_theme_color_override("font_color", ACCENT if index == _cursor else TEXT)
		label.add_theme_font_size_override("font_size", 18)
		parent.add_child(label)
	_render_service_page(values)


## `PhoneCall`'s ringing box and `PC_DisplayText`'s plain `MenuTextbox` print
## neither one, so those two draw no rows at all here.
func _render_service_page(values: Array) -> void:
	if _service_view == null or _data == null:
		return
	if _service_page == null:
		_service_page = Gen2WorldServicePage.from_data(_data)
	if _service_page == null:
		return
	var page_rows: Array = [] if _mode in [MODE.PHONE, MODE.PC_TEXT, MODE.AUDIO] else values
	var labels: Array = []
	for value: Variant in page_rows:
		if value is Dictionary:
			var row: Dictionary = value
			var label: String = String(row.get("name", row.get("caller_label", "")))
			if _mode == MODE.PC_ITEM_LIST:
				label += " x%d" % int(row.get("quantity", 0))
			labels.append(label)
		else:
			labels.append(String(value))
	var image: Image = _dial_image() if _is_dial() else _service_page.render(
		_title.text, _summary.text, labels, _cursor, _status.text, _service_box()
	)
	if image != null:
		_service_view.texture = ImageTexture.create_from_image(image)
		_service_hardware.visible = true


func _is_dial() -> bool:
	return _mode == MODE.MENU and _menu != null and _menu.kind == &"spinner"


## `SetDayOfWeek`'s `.loop`: the box, the two arrows, the one weekday string at
## `hlcoord 10, 5` and `.OakTimeWhatDayIsItText` in the speech box below it.
func _dial_image() -> Image:
	if _clock_page == null:
		_clock_page = Gen2ClockSetPage.from_data(_data)
	if _clock_page == null:
		return null
	var day: int = clampi(_cursor, 0, Gen2ClockSetScreen.DAYS.size() - 1)
	var prompt: String = _summary.text if not _summary.text.is_empty() \
		else "What day is it?"
	return _clock_page.render(Gen2ClockSetScreen.DAYS[day], prompt, -1, true)


## The `menu_coords` box this mode's own list sits in. `null` draws no box,
## which is what MODE.MENU falls back to before a menu is loaded.
func _service_box() -> Gen2MenuBox:
	match _mode:
		MODE.MENU:
			if _menu == null or _menu.kind == &"spinner":
				return null
			return _menu.box()
		MODE.PC, MODE.PC_ITEMS:
			return _pc_top_box()
		MODE.PC_ITEM_LIST:
			return _pc_item_list_box()
		MODE.APRICORN:
			return _apricorn_quantity_box() if _apricorns != null \
				and _apricorns.phase == Gen2WorldApricorn.SELECT_QUANTITY \
				else _apricorn_select_box()
		MODE.POKEGEAR, MODE.AUDIO:
			return _dynamic_box(_option_count())
	return null


## `PokemonCenterPC.TopMenu` and `PlayersPCMenuData` share this `menu_coords`.
func _pc_top_box() -> Gen2MenuBox:
	return Gen2MenuBox.from_coords(
		0, 0, 15, 12, Gen2MenuBox.STATICMENU_CURSOR | Gen2MenuBox.STATICMENU_WRAP
	)


## `PCItemsMenuData`'s `menu_coords 4, 1, 18, 10`.
func _pc_item_list_box() -> Gen2MenuBox:
	return Gen2MenuBox.from_coords(4, 1, 18, 10, Gen2MenuBox.STATICMENU_CURSOR)


## `Kurt_SelectApricorn.MenuHeader`'s `menu_coords 1, 1, 13, 10`.
func _apricorn_select_box() -> Gen2MenuBox:
	return Gen2MenuBox.from_coords(1, 1, 13, 10, Gen2MenuBox.STATICMENU_CURSOR)


## `Kurt_SelectQuantity.MenuHeader`'s `menu_coords 6, 9, SCREEN_WIDTH - 1, 12`.
## `PlaceApricornQuantity` writes the name and quantity by hand rather than
## through a `STATICMENU_CURSOR` list, so this box draws no cursor.
func _apricorn_quantity_box() -> Gen2MenuBox:
	return Gen2MenuBox.from_coords(6, 9, 19, 12, 0)


## The list box every mode above still leaves to the panel: POKEGEAR's card
## list, which `HANDOFF.md` already records as staying a panel, and AUDIO,
## which is a debug host with no cartridge screen of its own.
func _dynamic_box(count: int) -> Gen2MenuBox:
	var bottom: int = mini(17, 1 + maxi(count, 1) * 2)
	return Gen2MenuBox.from_coords(
		9, 0, 19, bottom, Gen2MenuBox.STATICMENU_CURSOR | Gen2MenuBox.STATICMENU_WRAP
	)


func _option_count() -> int:
	if _mode == MODE.MENU:
		return _menu.options.size() if _menu != null else _choices.size()
	if _mode == MODE.POKEGEAR:
		return _pokegear_cards.size()
	if _mode in [MODE.PC, MODE.PC_ITEMS]:
		return _pc_rows.size()
	if _mode == MODE.PC_ITEM_LIST:
		return maxi(1, _pc_entries.size())
	return 1


func _mart_source() -> Dictionary:
	return _mart


## `FarReadMart`'s own list. CANCEL is not one of its rows: `ScrollingMenu`
## draws it past the terminator, which is what [method _mart_rows] does.
func _refresh_mart_entries() -> void:
	_mart_entries = Gen2WorldMartHost.entries(_data, _mart_source())


func _phone_text(summary: Dictionary) -> String:
	return "%s %d\nMap %d/%d\nCaller time %d, callee time %d" % [
		String(summary.get("trainer_name", "UNKNOWN")),
		int(summary.get("trainer_number", 0)),
		int(summary.get("map_group", -1)), int(summary.get("map_number", -1)),
		int(summary.get("caller_time", 0)), int(summary.get("callee_time", 0)),
	]


func _show_error(message: String) -> void:
	_mode = -1
	_menu = null
	if _title != null:
		_title.text = "SERVICE ERROR"
		_summary.text = message
		_status.text = ""
		_footer.text = ""
		_status.add_theme_color_override("font_color", ERROR)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
