class_name Gen2MoveDeleterScreen
extends Control

## `MoveDeletion` (`engine/events/move_deleter.asm`) on the overworld's own pump.
##
## The same shape as [Gen2NameRaterScreen] and for the same reason: the routine
## owns its boxes, its two `YesNoBox`es and the two screens it opens, and the
## map script's own `waitbutton` is what dismisses the text `PrintText` left
## standing, so the ending is handed back rather than pressed here.
##
## `ChooseMoveToDelete` is `MoveScreenLoop`'s own screen with
## `DeleteMoveScreen2DMenuData` in front of it, so the list is [Gen2MoveScreen]
## in its deletion mode and the picture is [Gen2MoveScreenPage].

signal finished(party_index: int, move_index: int, ending_text: String)
signal closed()
signal sfx_requested(index: int, waited: bool)

const TILE: int = Gen2Font.TILE

const PARTY_SCENE: PackedScene = preload("res://game/save/party_screen.tscn")

enum Phase {
	INTRO,
	INTRO_ASK,
	WHICH_MON,
	SELECT_MON,
	WHICH_MOVE,
	SELECT_MOVE,
	DELETE_ASK,
	DONE,
}

var _data: GameData = null
var _save: Gen2SaveData = null
## Every stub `RomLayout.MOVE_DELETER_TEXT_ORDER` names, by that name.
var _texts: Dictionary = {}

var _phase: int = Phase.DONE
var _yes: bool = true
var _party_index: int = -1
var _move_index: int = -1
var _move_name: String = ""

var _text_box: Gen2TextBox = null
var _menu_page: Gen2MenuPage = null
var _menu: TextureRect = null
var _party: Gen2PartyScreen = null
var _move_view: TextureRect = null
var _move_model: Gen2MoveScreen = null
var _move_page: Gen2MoveScreenPage = null


func set_context(data: GameData, save: Gen2SaveData, texts: Dictionary) -> void:
	_data = data
	_save = save
	_texts = texts.duplicate(true)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	if _data == null or _save == null or _text("intro").is_empty():
		_phase = Phase.DONE
		finished.emit(-1, -1, "")
		closed.emit()
		return
	_build()
	_phase = Phase.INTRO
	_show_text(_text("intro"))


func phase() -> int:
	return _phase


func question_cursor() -> int:
	return (0 if _yes else 1) if _phase in [Phase.INTRO_ASK, Phase.DELETE_ASK] else -1


func text_lines() -> PackedStringArray:
	if _text_box == null or not _text_box.visible:
		return PackedStringArray()
	return _text_box.text_lines()


func party_screen() -> Gen2PartyScreen:
	return _party


func move_screen() -> Gen2MoveScreen:
	return _move_model


func handle_button(button: int) -> bool:
	if _phase == Phase.SELECT_MON and _party != null:
		return _party.handle_button(button)
	if _phase == Phase.SELECT_MOVE and _move_model != null:
		var used: bool = _move_model.handle_button(button)
		if _move_model != null:
			_draw_move_list()
		return used
	if _phase in [Phase.INTRO_ASK, Phase.DELETE_ASK]:
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
	if button != Gen2Button.A or _text_box == null or not _text_box.visible:
		return false
	if _text_box.is_revealing() or _text_box.has_pages_left():
		_text_box.advance()
		return true
	match _phase:
		Phase.WHICH_MON:
			_open_party()
		Phase.WHICH_MOVE:
			_open_move_list()
		_:
			return false
	return true


func advance_frame() -> void:
	## `_2DMENU_ENABLE_SPRITE_ANIMS_F` is set for the deleter's list too, so its
	## `LoadMenuMonIcon` icon steps on the same clock the move screen's does.
	if _phase == Phase.SELECT_MOVE:
		if _move_page != null:
			_move_page.advance()
			_draw_move_list()
		return
	if _text_box != null and _text_box.visible:
		_text_box.advance_frame()
		if _text_box.is_revealing() or _text_box.has_pages_left():
			return
	## Both questions are a `YesNoBox` over a text ending in `done`, which
	## `PrintText` returns from without a press.
	if _phase == Phase.INTRO:
		_open_question(Phase.INTRO_ASK)
	elif _phase == Phase.DELETE_ASK and (_menu == null or not _menu.visible):
		_draw_yes_no()


func _text(key: String) -> String:
	return String(_texts.get(key, ""))


func _build() -> void:
	_move_view = TextureRect.new()
	_move_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_move_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_move_view.visible = false
	add_child(_move_view)

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


func _show_text(text: String, prompt: bool = false) -> void:
	if _text_box == null:
		return
	_menu.visible = false
	_text_box.visible = true
	_text_box.show_text(text, prompt)


func _open_question(next_phase: int) -> void:
	_phase = next_phase
	_yes = true
	_draw_yes_no()


func _answer(yes: bool) -> void:
	_menu.visible = false
	if not yes:
		_end(Gen2MoveDeleter.ENDING_DECLINED)
		return
	if _phase == Phase.INTRO_ASK:
		_phase = Phase.WHICH_MON
		_show_text(_text("which_mon"), true)
		return
	_delete_move()


## `SelectMonFromParty`, the same list the Name Rater's own question opens.
func _open_party() -> void:
	var host: Gen2PartyScreen = PARTY_SCENE.instantiate() as Gen2PartyScreen
	if host == null:
		_end(Gen2MoveDeleter.ENDING_DECLINED)
		return
	host.set_context(_data, _save, true)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	host.selection_made.connect(_on_member_selected)
	add_child(host)
	host.open_selection()
	_party = host
	_text_box.visible = false
	_phase = Phase.SELECT_MON


func _on_member_selected(party_index: int) -> void:
	Gen2Screen.drop(_party)
	_party = null
	if party_index < 0 or party_index >= _save.party.size():
		_end(Gen2MoveDeleter.ENDING_DECLINED)
		return
	_party_index = party_index
	var ending: StringName = Gen2MoveDeleter.ending_for(
		_save.party[party_index] as Gen2SaveMon
	)
	if ending != &"":
		_end(ending)
		return
	_phase = Phase.WHICH_MOVE
	_show_text(_text("which_move"), true)


func _open_move_list() -> void:
	_move_model = Gen2MoveScreen.create(_data, _save.party, _party_index)
	## No `sfx_requested` connection: `.ChooseMoveToDelete` plays nothing, so the
	## list is silent and the only sound this routine owes is
	## `SFX_MOVE_DELETED`.
	_move_model.open_deletion()
	_move_model.selection_made.connect(_on_move_selected)
	_text_box.visible = false
	_phase = Phase.SELECT_MOVE
	_draw_move_list()


func _on_move_selected(move_index: int) -> void:
	var mon: Gen2SaveMon = _save.party[_party_index] as Gen2SaveMon
	_move_model = null
	if _move_view != null:
		_move_view.visible = false
	if move_index < 0 or mon == null or move_index >= mon.moves.size():
		_end(Gen2MoveDeleter.ENDING_DECLINED)
		return
	_move_index = move_index
	## `GetMoveName` off the row the cursor landed on, which is what the
	## question names.
	_move_name = String(_data.move(int(mon.moves[move_index])).get("name", ""))
	_phase = Phase.DELETE_ASK
	_yes = true
	_show_text(Gen2TextStream.fill_all_markers(
		_text("ask_delete"), Gen2TextStream.RAM_MARKER, _move_name
	))


## `.DeleteMove` and the `WaitSFX` on either side of `SFX_MOVE_DELETED`.
func _delete_move() -> void:
	var mon: Gen2SaveMon = _save.party[_party_index] as Gen2SaveMon
	if not Gen2MoveDeleter.delete_move(mon, _move_index):
		_end(Gen2MoveDeleter.ENDING_DECLINED)
		return
	sfx_requested.emit(Gen2MoveDeleter.SFX_MOVE_DELETED, true)
	_end(Gen2MoveDeleter.ENDING_FORGOT)


func _end(ending: StringName) -> void:
	## `.DeleteMove` is the one branch that wrote anything.
	if ending != Gen2MoveDeleter.ENDING_FORGOT:
		_party_index = -1
		_move_index = -1
	_phase = Phase.DONE
	if _text_box != null:
		_text_box.visible = false
	if _menu != null:
		_menu.visible = false
	if _move_view != null:
		_move_view.visible = false
	finished.emit(_party_index, _move_index, _text(String(ending)))
	closed.emit()


func _draw_move_list() -> void:
	if _move_model == null or _move_view == null:
		return
	if _move_page == null:
		_move_page = Gen2MoveScreenPage.from_data(_data)
	if _move_page == null:
		return
	var image: Image = _move_page.render(_move_model.snapshot(), _data)
	if image == null:
		return
	_move_view.texture = ImageTexture.create_from_image(image)
	_move_view.visible = true


func _draw_yes_no() -> void:
	if _menu_page == null:
		_menu_page = Gen2MenuPage.from_data(_data)
	if _menu_page == null:
		return
	var box: Gen2MenuBox = Gen2MenuBox.yes_no()
	var image: Image = _menu_page.render(box, ["YES", "NO"], 0 if _yes else 1)
	_menu.texture = ImageTexture.create_from_image(image)
	_menu.position = Vector2(box.border_position() * TILE)
	_menu.visible = true
