class_name Gen2WorldServiceScreen
extends Control

## Presentation host for imported overworld services. It owns only selection,
## labels and input. Script state and transactions stay in the scene-free world
## hosts and API.

signal completed(results: Array)

const PANEL: Color = Color("#14233a")
const BORDER: Color = Color("#4f6f9e")
const SCRIM: Color = Color(0.02, 0.04, 0.08, 0.78)
const TEXT: Color = Color("#f4f7fb")
const MUTED: Color = Color("#9eacc0")
const ACCENT: Color = Color("#f3c969")
const SUCCESS: Color = Color("#7bd89a")
const ERROR: Color = Color("#ef8a8a")

enum MODE {
	MENU, MART, PHONE, PHONE_LIST, AUDIO, POKEGEAR, RADIO, TOWN_MAP, CLOCK,
	APRICORN, PC, PC_ITEMS, PC_ITEM_LIST, PC_TEXT,
}

## `PokemonCenterPC`'s own box storage, which is the one row that opens a screen
## rather than a list. It is added as a child the way the MAP card adds the
## region map, so the top menu is still there when the box screen closes.
const BOX_SCENE := preload("res://game/save/box_screen.tscn")

## engine/pokegear/pokegear.asm's card order. Each is behind its own
## wPokegearFlags bit, named here by the engine flag that carries it, since that
## is what the state holds. The clock card needs no flag.
const POKEGEAR_CARDS: Array[Dictionary] = [
	{"card": &"clock", "name": "CLOCK"},
	{"card": &"map", "name": "MAP", "flag": Gen2WorldState.ENGINE_MAP_CARD},
	{"card": &"phone", "name": "PHONE", "flag": Gen2WorldState.ENGINE_PHONE_CARD},
	{"card": &"radio", "name": "RADIO", "flag": Gen2WorldState.ENGINE_RADIO_CARD},
]

const WorldMenu := preload("res://game/world/world_menu.gd")

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
var _mart_entries: Array = []
var _mart_quantity: int = 1
var _mart_purchased: bool = false
var _apricorns: Gen2WorldApricorn = null
var _phone_entries: Array = []
var _pokegear_cards: Array = []
var _town_map: Gen2TownMapScreen = null
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


## Opens the Pokegear phone list. Contact order follows the cartridge table,
## and only registered numbers are selectable.
func open_phone_list(
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
		_show_error("Phone has no world or cartridge cache.")
		return false
	_phone_entries = _world.registered_phone_contacts()
	_open_phone_list()
	return true


## Opens the Pokegear on its card list. Only cards the player owns are
## selectable, in the source's own clock/map/phone/radio order.
func open_pokegear(
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
		_show_error("Pokegear has no world or cartridge cache.")
		return false
	_pokegear_cards = []
	for card: Dictionary in POKEGEAR_CARDS:
		var owned: bool = not card.has("flag") \
			or _world.state.is_engine_flag_active(int(card["flag"]))
		if not owned:
			continue
		_pokegear_cards.append(card)
	_open_pokegear_cards()
	return true


## Parent screens route buttons here so the service overlay owns input while open.
func handle_button(button: int) -> bool:
	if not is_active():
		return false
	if _mode == MODE.APRICORN:
		_press_apricorns(button)
		return true
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
	var scrim := ColorRect.new()
	scrim.color = SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

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


func _open_menu(input: Dictionary) -> void:
	_mode = MODE.MENU
	_menu_input = input.duplicate(true)
	_menu = WorldMenu.from_input(_menu_input)
	_choices = _menu.options.duplicate(true)
	_cursor = _menu.selected_index()
	_title.text = "MENU"
	_summary.text = String(input.get("command", input.get("menu_kind", "Choose an option")))
	_status.text = ""
	_footer.text = "D-pad: move    A: choose    B: cancel"
	_render_options()


func _open_mart(mart: Dictionary) -> void:
	_mode = MODE.MART
	_refresh_mart_entries()
	_mart_quantity = 1
	_mart_purchased = false
	_cursor = 0
	_title.text = String(mart.get("label", "MART"))
	_summary.text = "Money: %d" % _world.state.money(Gen2WorldMartHost.MONEY_ACCOUNT)
	_status.text = "One of each item per visit." if StringName(mart.get("variant", &"")) == &"bargain" \
		else "Select an item. Left and right change the quantity."
	_footer.text = "D-pad: move and quantity    A: buy    B: leave"
	_render_options()


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


func _open_phone_list() -> void:
	_mode = MODE.PHONE_LIST
	_cursor = 0
	_title.text = "PHONE"
	_summary.text = "Registered numbers"
	_status.text = "Choose a contact to call." if not _phone_entries.is_empty() else "No registered numbers."
	_footer.text = "D-pad: move    A: call    B: close"
	_render_options()


func _open_pokegear_cards() -> void:
	_mode = MODE.POKEGEAR
	_cursor = 0
	_title.text = "POKEGEAR"
	var clock: Dictionary = _world.world_clock()
	_summary.text = "%02d:%02d" % [int(clock.get("hour", 0)), int(clock.get("minute", 0))]
	_status.text = "Choose a card."
	_footer.text = "D-pad: move    A: open    B: close"
	_render_options()


## The source clock card clears its inner box, prints the weekday and renders a
## 12-hour clock with the AM/PM label. The host keeps the card list as its
## navigation shell, then presents the card as its own read-only page.
func _open_clock_card() -> void:
	_mode = MODE.CLOCK
	_cursor = 0
	_title.text = "CLOCK"
	var clock: Dictionary = _world.world_clock()
	var hour24: int = int(clock.get("hour", 0))
	var hour12: int = hour24 % 12
	if hour12 == 0:
		hour12 = 12
	var period: String = "AM" if hour24 < 12 else "PM"
	var weekday: String = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"][
		posmod(int(clock.get("day", 0)), 7)
	]
	_summary.text = "%s\n\n%02d:%02d %s" % [
		weekday, hour12, int(clock.get("minute", 0)), period,
	]
	_status.text = "Time of day: %s" % _time_of_day_label(hour24)
	_status.add_theme_color_override("font_color", TEXT)
	_footer.text = "B: back to cards"
	_render_options(["CLOCK CARD"])


func _time_of_day_label(hour24: int) -> String:
	if hour24 < Gen2WorldClock.MORN_START or hour24 >= Gen2WorldClock.NITE_START:
		return "NIGHT"
	if hour24 < Gen2WorldClock.DAY_START:
		return "MORNING"
	return "DAY"


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


## The radio card. Left and right are the tuning knob, which is the whole of the
## card's input: the source has no confirm on a station.
func _open_radio() -> void:
	_mode = MODE.RADIO
	_cursor = 0
	_title.text = "RADIO"
	_refresh_radio()
	_footer.text = "Left and right: tune    B: close"


func _refresh_radio() -> void:
	var tuned: Dictionary = _world.radio_station()
	_summary.text = "%.1f MHz" % float(tuned.get("frequency", 0.0))
	if bool(tuned.get("ok", false)):
		_status.text = String(tuned.get("name", ""))
		_status.add_theme_color_override("font_color", SUCCESS)
	else:
		# NoRadioName blanks the label rather than saying anything.
		_status.text = ""
		_status.add_theme_color_override("font_color", MUTED)
	_render_options([_radio_dial()])


## The dial as the knob positions it can stop on, so a player can see where the
## stations sit without a drawn tuner.
func _radio_dial() -> String:
	var dial: String = ""
	for knob: int in Gen2WorldRadio.knob_values():
		dial += "|" if knob == _world.state.radio_knob() else "."
	return dial


func _tune_radio(step: int) -> void:
	_world.tune_radio(_world.state.radio_knob() + step * Gen2WorldRadio.KNOB_STEP)
	_refresh_radio()


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
	if _mode == MODE.MART:
		_mart_quantity = 1
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
	if _mode == MODE.MART and direction.x != 0:
		_change_mart_quantity(direction.x)
		return
	if _mode == MODE.RADIO:
		if direction.x != 0:
			_tune_radio(direction.x)
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
	if _mode == MODE.MART:
		if _cursor >= _mart_entries.size():
			_cancel()
			return
		var entry: Dictionary = _mart_entries[_cursor]
		if bool(entry.get("leave", false)):
			_finish_runtime({"ok": true, "script_value": 1 if _mart_purchased else 0})
			return
		if bool(entry.get("sold_out", false)):
			_status.text = "This item is sold out for this visit."
			_status.add_theme_color_override("font_color", ERROR)
			return
		var purchase: Dictionary = Gen2WorldMartHost.purchase(
			_world, _save, _mart_source(), int(entry.get("item", 0)), _mart_quantity, _persist
		)
		if not bool(purchase.get("ok", false)):
			_status.text = "Purchase failed: %s" % String(purchase.get("reason", "unknown"))
			_status.add_theme_color_override("font_color", ERROR)
			return
		_mart_purchased = true
		_summary.text = "Money: %d" % _world.state.money(Gen2WorldMartHost.MONEY_ACCOUNT)
		_status.text = "Bought %s. Owned: %d" % [
			String(purchase.get("name", "UNKNOWN")), int(purchase.get("owned", 0)),
		]
		_status.add_theme_color_override("font_color", SUCCESS)
		_mart_quantity = 1
		_refresh_mart_entries()
		_render_options()
		return
	if _mode == MODE.POKEGEAR:
		if _cursor >= _pokegear_cards.size():
			return
		var card: Dictionary = _pokegear_cards[_cursor]
		if bool(card.get("unavailable", false)):
			_status.text = "%s is not implemented." % String(card.get("name", ""))
			_status.add_theme_color_override("font_color", ERROR)
			return
		match StringName(card.get("card", &"")):
			&"map":
				_open_town_map(false)
			&"radio":
				_open_radio()
			&"phone":
				_phone_entries = _world.registered_phone_contacts()
				_open_phone_list()
			&"clock":
				_open_clock_card()
		return
	if _mode == MODE.CLOCK:
		return
	if _mode == MODE.RADIO:
		return
	if _mode == MODE.PHONE_LIST:
		if _phone_entries.is_empty():
			_status.text = "No registered numbers."
			return
		var contact: Dictionary = _phone_entries[_cursor]
		var results: Array = _world.request_outgoing_phone_call(int(contact.get("index", -1)))
		_mode = -1
		completed.emit(results)
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
	elif _mode == MODE.MART:
		_finish_runtime({"ok": true, "script_value": 1 if _mart_purchased else 0, "cancelled": true})
	elif _mode == MODE.RADIO:
		_world.close_radio()
		_open_pokegear_cards()
	elif _mode == MODE.CLOCK:
		_open_pokegear_cards()
	elif _mode == MODE.POKEGEAR:
		_mode = -1
		completed.emit([])
	elif _mode == MODE.PHONE_LIST:
		if _pokegear_cards.is_empty():
			_mode = -1
			completed.emit([])
		else:
			_open_pokegear_cards()
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
	var values: Array = override if not override.is_empty() else (
		_choices if _mode == MODE.MENU else _mart_entries if _mode == MODE.MART \
		else _phone_entries if _mode == MODE.PHONE_LIST \
		else _pc_rows if _mode in [MODE.PC, MODE.PC_ITEMS] \
		else _pc_entries if _mode == MODE.PC_ITEM_LIST \
		else _pokegear_cards if _mode == MODE.POKEGEAR else ["Continue"]
	)
	for index: int in values.size():
		var value: Variant = values[index]
		var label := Label.new()
		var name: String = str(value)
		if value is Dictionary:
			var dictionary: Dictionary = value as Dictionary
			name = str(dictionary.get("name", ""))
			if name.is_empty():
				name = str(dictionary.get("caller_label", ""))
			if name.is_empty():
				name = str(dictionary.get("trainer_name", "UNKNOWN"))
			if name.is_empty() and dictionary.has("index"):
				name = "CONTACT %d" % int(dictionary.get("index", -1))
		if value is Dictionary and _mode == MODE.MART \
			and not bool((value as Dictionary).get("leave", false)):
			if bool((value as Dictionary).get("sold_out", false)):
				name = "%s    SOLD OUT" % name
				label.text = ("> " if index == _cursor else "  ") + name
				label.add_theme_color_override("font_color", ERROR if index == _cursor else MUTED)
				label.add_theme_font_size_override("font_size", 18)
				parent.add_child(label)
				continue
			var price: int = int((value as Dictionary).get("price", 0))
			if index == _cursor:
				name = "%s    %d x %d = %d" % [
					name, price, _mart_quantity, price * _mart_quantity,
				]
			else:
				name = "%s    %d" % [name, price]
		if value is Dictionary and _mode == MODE.PC_ITEM_LIST:
			var stack: int = int((value as Dictionary).get("quantity", 0))
			name = "%s    x%d of %d" % [name, _pc_quantity, stack] if index == _cursor \
				else "%s    x%d" % [name, stack]
		if value is Dictionary and _mode == MODE.PHONE_LIST:
			if int((value as Dictionary).get("trainer_class", 0)) > 0:
				name = "%s %d" % [name, int((value as Dictionary).get("trainer_number", 0))]
		label.text = ("> " if index == _cursor else "  ") + name
		label.add_theme_color_override("font_color", ACCENT if index == _cursor else TEXT)
		label.add_theme_font_size_override("font_size", 18)
		parent.add_child(label)
	if _mode == MODE.MART:
		_update_mart_status()


func _option_count() -> int:
	if _mode == MODE.MENU:
		return _menu.options.size() if _menu != null else _choices.size()
	if _mode == MODE.MART:
		return _mart_entries.size()
	if _mode == MODE.PHONE_LIST:
		return _phone_entries.size()
	if _mode == MODE.POKEGEAR:
		return _pokegear_cards.size()
	if _mode in [MODE.PC, MODE.PC_ITEMS]:
		return _pc_rows.size()
	if _mode == MODE.PC_ITEM_LIST:
		return maxi(1, _pc_entries.size())
	return 1


func _mart_source() -> Dictionary:
	return _resolved.get("data", {}).get("mart", {})


func _refresh_mart_entries() -> void:
	_mart_entries = Gen2WorldMartHost.entries(_data, _mart_source())
	_mart_entries.append({"leave": true, "name": "LEAVE"})


func _change_mart_quantity(delta: int) -> void:
	if _cursor < 0 or _cursor >= _mart_entries.size():
		return
	var entry: Dictionary = _mart_entries[_cursor]
	if bool(entry.get("leave", false)) or bool(entry.get("sold_out", false)):
		return
	if StringName(_mart_source().get("variant", &"")) == &"bargain":
		return
	var owned: int = _world.state.item_quantity(int(entry.get("item", 0)))
	var maximum: int = Gen2WorldMartHost.MAX_ITEM_STACK - owned
	if maximum <= 0:
		_mart_quantity = 0
	else:
		_mart_quantity = clampi(_mart_quantity + delta, 1, maximum)
	_render_options()


func _update_mart_status() -> void:
	if _mode != MODE.MART or _cursor < 0 or _cursor >= _mart_entries.size():
		return
	var entry: Dictionary = _mart_entries[_cursor]
	if bool(entry.get("leave", false)):
		_status.text = "Leave this shop."
		return
	if bool(entry.get("sold_out", false)):
		_status.text = "Sold out for this visit."
		return
	var item: int = int(entry.get("item", 0))
	var owned: int = _world.state.item_quantity(item)
	var maximum: int = Gen2WorldMartHost.MAX_ITEM_STACK - owned
	if maximum <= 0:
		_status.text = "This item stack is full."
		return
	_status.text = "Owned: %d    Quantity: %d    Total: %d" % [
		owned, _mart_quantity, int(entry.get("price", 0)) * _mart_quantity,
	]


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
