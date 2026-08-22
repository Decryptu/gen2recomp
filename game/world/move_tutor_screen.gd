class_name Gen2MoveTutorScreen
extends Control

## `MoveTutor` (`engine/events/move_tutor.asm`) on the overworld's own pump.
##
## The same shape as [Gen2MoveDeleterScreen]: the routine owns the party list
## `ChooseMonToLearnTMHM` opens, its refusals and the `ForgetMove` menu behind
## `LearnMove`, and the map script's own `waitbutton` presses the box it leaves
## standing.
##
## The `.loop` is the whole of it. `.didnt_learn` returns carry clear and the
## routine reopens the list, so every refusal comes back to the party list and
## only a learned move or a backed-out list ends the special.

signal finished(script_value: int, party_index: int, ending_text: String)
signal closed()
signal sfx_requested(index: int, waited: bool)

const TILE: int = Gen2Font.TILE

const PARTY_SCENE: PackedScene = preload("res://game/save/party_screen.tscn")

## `ForgetMove`'s own `hlcoord 5, 2 / ld b, NUM_MOVES * 2 / ld c, MOVE_NAME_LENGTH`
## and the `w2DMenuCursorOffsets` of `$20` under it, which is [Gen2MenuBox]'s
## default two-row step.
const FORGET_BOX: Array[int] = [5, 2, 19, 11]

enum Phase {
	SELECT_MON,
	REFUSAL,
	FORGET_ASK,
	FORGET_LIST,
	STOP_ASK,
	DONE,
}

var _data: GameData = null
var _world: Gen2WorldAPI = null
var _save: Gen2SaveData = null
var _persist: bool = true
var _move: int = 0
var _move_name: String = ""

var _phase: int = Phase.DONE
var _yes: bool = true
var _party_index: int = -1
var _forget_moves: Array = []
var _forget_cursor: int = 0
var _forget_refusal: String = ""
## The line the current `Phase.REFUSAL` box is standing on.
var _refusal_text: String = ""

var _text_box: Gen2TextBox = null
var _menu_page: Gen2MenuPage = null
var _menu: TextureRect = null
var _party: Gen2PartyScreen = null


func set_context(
	data: GameData, world: Gen2WorldAPI, save: Gen2SaveData, move: int,
	persist: bool = true
) -> void:
	_data = data
	_world = world
	_save = save
	_move = move
	_persist = persist
	_move_name = String(data.move(move).get("name", "MOVE")) if data != null else ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	if _data == null or _world == null or _save == null or _move <= 0:
		_end(Gen2MoveTutor.SCRIPT_VALUE_CANCELLED, "")
		return
	_build()
	_open_party()


func phase() -> int:
	return _phase


func question_cursor() -> int:
	return (0 if _yes else 1) if _phase in [Phase.FORGET_ASK, Phase.STOP_ASK] else -1


func forget_cursor() -> int:
	return _forget_cursor if _phase == Phase.FORGET_LIST else -1


func forget_options() -> Array:
	return _forget_moves.duplicate(true)


func text_lines() -> PackedStringArray:
	if _text_box == null or not _text_box.visible:
		return PackedStringArray()
	return _text_box.text_lines()


func party_screen() -> Gen2PartyScreen:
	return _party


## The words this phase's own box prints, so a headless caller can read the
## routine without the pixels.
func box_text() -> String:
	match _phase:
		Phase.REFUSAL:
			return _refusal_text
		Phase.FORGET_ASK:
			return Gen2MoveForget.ask_text(_mon_name(), _move_name)
		Phase.STOP_ASK:
			return Gen2MoveForget.stop_text(_move_name)
		Phase.FORGET_LIST:
			return _forget_refusal if not _forget_refusal.is_empty() \
				else Gen2MoveForget.which_text()
	return ""


func handle_button(button: int) -> bool:
	if _phase == Phase.SELECT_MON and _party != null:
		return _party.handle_button(button)
	if _phase == Phase.FORGET_LIST:
		return _handle_forget_list(button)
	if _phase in [Phase.FORGET_ASK, Phase.STOP_ASK]:
		match button:
			Gen2Button.UP, Gen2Button.DOWN:
				_yes = not _yes
				_draw_yes_no()
				return true
			Gen2Button.A:
				_answer(_yes)
				return true
			Gen2Button.B:
				_answer(false)
				return true
		return false
	if _phase != Phase.REFUSAL or button != Gen2Button.A or _text_box == null:
		return false
	if _text_box.is_revealing() or _text_box.has_pages_left():
		_text_box.advance()
		return true
	## `.didnt_learn` is `and a / ret`, which `.loop` reads as "go round again".
	_open_party()
	return true


func advance_frame() -> void:
	if _text_box != null and _text_box.visible:
		_text_box.advance_frame()


func _handle_forget_list(button: int) -> bool:
	match button:
		Gen2Button.UP, Gen2Button.DOWN:
			if _forget_moves.is_empty():
				return true
			## No `STATICMENU_WRAP`: `w2DMenuFlags1` is `$20` and the list stops
			## at either end.
			_forget_cursor = clampi(
				_forget_cursor + (1 if button == Gen2Button.DOWN else -1),
				0, _forget_moves.size() - 1
			)
			_forget_refusal = ""
			_draw_forget_list()
			return true
		Gen2Button.A:
			_confirm_forget()
			return true
		Gen2Button.B:
			## `.cancel` sets carry, which `LearnMove` reads as `.cancel`.
			_open_stop_ask()
			return true
	return false


func _build() -> void:
	_menu = TextureRect.new()
	_menu.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.visible = false
	add_child(_menu)

	_text_box = Gen2TextBox.new()
	_text_box.driven = true
	_text_box.font = Gen2Font.from_data(_data)
	var options: Gen2Options = Gen2OptionsStore.current()
	_text_box.set_frame_style(options.textbox_frame)
	_text_box.reveal_speed = options.text_reveal_speed()
	_text_box.place_at_bottom()
	_text_box.visible = false
	add_child(_text_box)


## `ChooseMonToLearnTMHM`, whose `PARTYMENUACTION_TEACH_TMHM` is the prompt the
## list stands under.
func _open_party() -> void:
	if _party != null:
		return
	var host: Gen2PartyScreen = PARTY_SCENE.instantiate() as Gen2PartyScreen
	if host == null:
		_end(Gen2MoveTutor.SCRIPT_VALUE_CANCELLED, "")
		return
	host.set_context(_data, _save, true)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	host.selection_made.connect(_on_member_selected)
	add_child(host)
	host.open_selection(Gen2PartyScreen.PROMPT_TEACH_WHICH)
	_party = host
	if _text_box != null:
		_text_box.visible = false
	if _menu != null:
		_menu.visible = false
	_phase = Phase.SELECT_MON


func _on_member_selected(party_index: int) -> void:
	Gen2Screen.drop(_party)
	_party = null
	## `jr c, .cancel`: B on the list is the one way out that is not a learned
	## move.
	if party_index < 0 or party_index >= _save.party.size():
		_end(Gen2MoveTutor.SCRIPT_VALUE_CANCELLED, "")
		return
	_party_index = party_index
	_teach(-1)


## `CheckCanLearnMoveTutorMove`'s own order, run through the host so the write
## and the happiness row land in one transaction.
func _teach(forget_slot: int) -> void:
	var result: Dictionary = Gen2WorldPartyHost.teach_tutor_move(
		_world, _save, _party_index, _move, forget_slot, _persist
	)
	if bool(result.get("ok", false)):
		var learned: String = Gen2MoveForget.learned_text(_mon_name(), _move_name)
		if forget_slot >= 0:
			learned = "%s %s" % [
				Gen2MoveForget.forgot_text(_mon_name(), _forgotten_name(forget_slot)),
				learned,
			]
		_end(Gen2MoveTutor.SCRIPT_VALUE_LEARNED, learned)
		return
	var reason: StringName = StringName(result.get("reason", &""))
	## `LearnMove` is the last of the three, so a full moveset is the one
	## refusal that opens a menu instead of printing a line.
	if reason == &"moveset_full":
		_forget_moves = Gen2MoveForget.options(
			_data, (result.get("details", {}) as Dictionary).get("moves", [])
		)
		if not _forget_moves.is_empty():
			_open_forget_ask()
			return
	_show_refusal(reason)


## The two lines `CheckCanLearnMoveTutorMove` prints itself, and the SFX_WRONG
## that stands in front of only the first.
func _show_refusal(reason: StringName) -> void:
	match reason:
		&"not_compatible":
			sfx_requested.emit(Gen2MoveTutor.SFX_WRONG, false)
			_refusal_text = Gen2WorldTMHM.not_compatible_text(_mon_name(), _move_name)
		&"already_knows_move":
			_refusal_text = Gen2WorldTMHM.knows_move_text(_mon_name(), _move_name)
		&"invalid_party_index":
			## `ChooseMonToLearnTMHM` refuses an egg with SFX_WRONG and reopens
			## the list without a box, which is what an empty text is here.
			sfx_requested.emit(Gen2MoveTutor.SFX_WRONG, false)
			_open_party()
			return
		_:
			_refusal_text = Gen2MoveForget.did_not_learn_text(_mon_name(), _move_name)
	_phase = Phase.REFUSAL
	_show_text(_refusal_text)


func _open_forget_ask() -> void:
	_phase = Phase.FORGET_ASK
	_yes = true
	_show_text(box_text())
	_draw_yes_no()


func _answer(yes: bool) -> void:
	if _phase == Phase.FORGET_ASK:
		if yes:
			_open_forget_list()
		else:
			_open_stop_ask()
		return
	## `.cancel`'s own `jp c, .loop`: no goes back to `ForgetMove`'s ask.
	if yes:
		_end_did_not_learn()
	else:
		_open_forget_ask()


func _open_forget_list() -> void:
	_phase = Phase.FORGET_LIST
	_forget_cursor = 0
	_forget_refusal = ""
	_show_text(box_text())
	_draw_forget_list()


func _confirm_forget() -> void:
	if _forget_cursor < 0 or _forget_cursor >= _forget_moves.size():
		return
	var entry: Dictionary = _forget_moves[_forget_cursor]
	## `.hmmove` is `jr .loop`, not a cancel: the list stays open behind the box.
	if not bool(entry.get("forgettable", false)):
		_forget_refusal = Gen2MoveForget.cant_forget_hm_text()
		_show_text(box_text())
		_draw_forget_list()
		return
	_teach(int(entry.get("slot", -1)))


func _open_stop_ask() -> void:
	_phase = Phase.STOP_ASK
	_yes = true
	_show_text(box_text())
	_draw_yes_no()


## `LearnMove` returns `b = 0`, which `CheckCanLearnMoveTutorMove` reads as
## `.didnt_learn`, so the routine loops back to the party list rather than
## ending.
func _end_did_not_learn() -> void:
	_refusal_text = Gen2MoveForget.did_not_learn_text(_mon_name(), _move_name)
	_phase = Phase.REFUSAL
	_show_text(_refusal_text)


func _forgotten_name(slot: int) -> String:
	for entry: Dictionary in _forget_moves:
		if int(entry.get("slot", -1)) == slot:
			return String(entry.get("name", ""))
	return ""


func _mon_name() -> String:
	if _save == null or _party_index < 0 or _party_index >= _save.party.size():
		return "#MON"
	var mon: Gen2SaveMon = _save.party[_party_index] as Gen2SaveMon
	if mon == null:
		return "#MON"
	var nickname: String = String(mon.nickname)
	if not nickname.is_empty():
		return nickname
	return String(_data.species(mon.species).get("name", "#MON")) if _data != null \
		else "#MON"


func _show_text(text: String, prompt: bool = false) -> void:
	if _text_box == null:
		return
	if _menu != null:
		_menu.visible = false
	_text_box.visible = true
	_text_box.show_text(text, prompt)


func _end(script_value: int, ending_text: String) -> void:
	_phase = Phase.DONE
	if _party != null:
		Gen2Screen.drop(_party)
		_party = null
	if _text_box != null:
		_text_box.visible = false
	if _menu != null:
		_menu.visible = false
	finished.emit(script_value, _party_index, ending_text)
	closed.emit()


func _page() -> Gen2MenuPage:
	if _menu_page == null:
		_menu_page = Gen2MenuPage.from_data(_data)
	return _menu_page


func _draw_yes_no() -> void:
	if _page() == null or _menu == null:
		return
	var box: Gen2MenuBox = Gen2MenuBox.yes_no()
	var image: Image = _page().render(box, ["YES", "NO"], 0 if _yes else 1)
	_menu.texture = ImageTexture.create_from_image(image)
	_menu.position = Vector2(box.border_position() * TILE)
	_menu.visible = true


func _draw_forget_list() -> void:
	if _page() == null or _menu == null:
		return
	var box: Gen2MenuBox = Gen2MenuBox.from_coords(
		FORGET_BOX[0], FORGET_BOX[1], FORGET_BOX[2], FORGET_BOX[3],
		Gen2MenuBox.STATICMENU_CURSOR
	)
	var names: Array = []
	for entry: Dictionary in _forget_moves:
		names.append(String(entry.get("name", "")))
	var image: Image = _page().render(box, names, _forget_cursor)
	_menu.texture = ImageTexture.create_from_image(image)
	_menu.position = Vector2(box.border_position() * TILE)
	_menu.visible = true
