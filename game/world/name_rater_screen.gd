class_name Gen2NameRaterScreen
extends Control

## `_NameRater` (`engine/events/name_rater.asm`) on the overworld's own pump.
##
## The routine is a straight line: an introduction and a `YesNoBox`, the party
## list `SelectMonFromParty` opens, three endings that need no new name, a second
## `YesNoBox`, `_NamingScreen`, and `.done`'s own text. [Gen2NameRater] answers
## which ending a member reaches; this owns the boxes, the presses and the two
## screens it opens over itself.
##
## The last text is deliberately not pressed here. `special NameRater` returns
## the moment `PrintText` has drawn it and the map script's own `waitbutton` is
## what dismisses it, so the ending text is handed to the caller through
## [signal finished] and stands in the world's speech box for that one press.

## The chosen nickname, if the routine wrote one, and the text `.done` ends on.
## [param party_index] is -1 for every ending that renames nothing.
signal finished(party_index: int, nickname: String, ending_text: String)
signal closed()

const TILE: int = Gen2Font.TILE

const PARTY_SCENE: PackedScene = preload("res://game/save/party_screen.tscn")

enum Phase {
	HELLO,
	HELLO_ASK,
	WHICH_MON,
	SELECT,
	BETTER_NAME,
	BETTER_ASK,
	WHAT_NAME,
	NAMING,
	NAMED,
	DONE,
}

var _data: GameData = null
var _save: Gen2SaveData = null
var _player_name: String = ""
var _player_id: int = 0
## Every stub `RomLayout.NAME_RATER_TEXT_ORDER` names, by that name.
var _texts: Dictionary = {}

var _phase: int = Phase.DONE
var _yes: bool = true
## Which member `PartyMenuSelect` answered with, and the nickname the routine
## settled on for it.
var _party_index: int = -1
var _nickname: String = ""
var _ending: StringName = Gen2NameRater.ENDING_CANCEL

var _text_box: Gen2TextBox = null
var _menu_page: Gen2MenuPage = null
var _menu: TextureRect = null
var _party: Gen2PartyScreen = null
var _naming: Gen2NamingScreenScreen = null


## [param texts] is `GameData.name_rater_text` for each of the ten stubs, which
## the host has already read; an empty one closes at once rather than inventing
## a line.
func set_context(
	data: GameData,
	save: Gen2SaveData,
	texts: Dictionary,
	player_name: String,
	player_id: int
) -> void:
	_data = data
	_save = save
	_texts = texts.duplicate(true)
	_player_name = player_name
	_player_id = player_id


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	if _data == null or _save == null or _text("hello").is_empty():
		_phase = Phase.DONE
		finished.emit(-1, "", "")
		closed.emit()
		return
	_build()
	_phase = Phase.HELLO
	_show_text(_text("hello"))


func phase() -> int:
	return _phase


## The YES/NO cursor, so a driver can read it without a redraw. -1 when no box
## is up.
func question_cursor() -> int:
	return (0 if _yes else 1) if _phase in [Phase.HELLO_ASK, Phase.BETTER_ASK] else -1


func text_lines() -> PackedStringArray:
	if _text_box == null or not _text_box.visible:
		return PackedStringArray()
	return _text_box.text_lines()


func party_screen() -> Gen2PartyScreen:
	return _party


func naming_screen() -> Gen2NamingScreenScreen:
	return _naming


func handle_button(button: int) -> bool:
	if _phase == Phase.SELECT and _party != null:
		return _party.handle_button(button)
	if _phase == Phase.NAMING and _naming != null:
		return _naming.handle_button(button)
	if _phase in [Phase.HELLO_ASK, Phase.BETTER_ASK]:
		match button:
			Gen2Button.UP, Gen2Button.DOWN:
				_yes = not _yes
				_draw_yes_no()
				return true
			Gen2Button.A:
				_answer(_yes)
				return true
			Gen2Button.B:
				## `YesNoBox` answers B with the carry `jp c, .cancel` takes.
				_answer(false)
				return true
		return false
	if button != Gen2Button.A or _text_box == null or not _text_box.visible:
		return false
	if _text_box.is_revealing() or _text_box.has_pages_left():
		_text_box.advance()
		return true
	## The press `prompt` waits for. `PrintText` returns on it and the routine
	## carries on to whatever follows the text.
	match _phase:
		Phase.WHICH_MON:
			_open_party()
		Phase.WHAT_NAME:
			_open_naming()
		Phase.NAMED:
			_end(_ending)
		_:
			return false
	return true


func advance_frame() -> void:
	if _text_box != null and _text_box.visible:
		_text_box.advance_frame()
		if _text_box.is_revealing() or _text_box.has_pages_left():
			return
	## `PrintText` on a text ending in `done` returns without a press, and both
	## of the routine's questions are a `YesNoBox` over one.
	if _phase == Phase.HELLO:
		_open_question(Phase.HELLO_ASK)
	elif _phase == Phase.BETTER_NAME:
		_open_question(Phase.BETTER_ASK)


func _text(key: String) -> String:
	return String(_texts.get(key, ""))


## Every one of the routine's texts that names `wStringBuffer1` is filled with
## `GetCurNickname`'s own answer, which is the chosen member's nickname before
## the copy and its new one after.
func _filled(key: String, nickname: String) -> String:
	return Gen2TextStream.fill_all_markers(
		_text(key), Gen2TextStream.RAM_MARKER, nickname
	)


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
		_end(Gen2NameRater.ENDING_CANCEL)
		return
	if _phase == Phase.HELLO_ASK:
		_phase = Phase.WHICH_MON
		_show_text(_text("which_mon"), true)
		return
	_phase = Phase.WHAT_NAME
	_show_text(_text("what_name"), true)


## `SelectMonFromParty`, which is `InitPartyMenuWithCancel` with
## PARTYMENUACTION_CHOOSE_POKEMON in `wPartyMenuActionText`.
func _open_party() -> void:
	var host: Gen2PartyScreen = PARTY_SCENE.instantiate() as Gen2PartyScreen
	if host == null:
		_end(Gen2NameRater.ENDING_CANCEL)
		return
	host.set_context(_data, _save, true)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	host.selection_made.connect(_on_selected)
	add_child(host)
	host.open_selection()
	_party = host
	_text_box.visible = false
	_phase = Phase.SELECT


func _on_selected(party_index: int) -> void:
	Gen2Screen.drop(_party)
	_party = null
	if party_index < 0 or party_index >= _save.party.size():
		_end(Gen2NameRater.ENDING_CANCEL)
		return
	_party_index = party_index
	var mon: Gen2SaveMon = _save.party[party_index] as Gen2SaveMon
	_nickname = _display_name(mon)
	var ending: StringName = Gen2NameRater.ending_for(mon, _player_name, _player_id)
	if ending != &"":
		_end(ending)
		return
	_phase = Phase.BETTER_NAME
	_show_text(_filled("better_name", _nickname))


## `_NamingScreen` under NAME_MON, whose header is the *species* name out of
## `wNamedObjectIndex` rather than the nickname the row is carrying.
func _open_naming() -> void:
	var mon: Gen2SaveMon = _save.party[_party_index] as Gen2SaveMon
	var species: String = String(_data.species(mon.species).get("name", ""))
	_naming = Gen2NamingScreenScreen.new()
	if not _naming.open(
		_data, Gen2WorldPartyHost.nickname_prompt(species),
		Gen2NamingScreenScreen.KIND_MON
	):
		## No keyboard is no new name, which is `IsNewNameEmpty`'s own answer.
		_naming = null
		_ending = Gen2NameRater.ENDING_SAME_NAME
		_end_named(_nickname)
		return
	_text_box.visible = false
	_naming.closed.connect(_on_named)
	add_child(_naming)
	_phase = Phase.NAMING


func _on_named(entered: String) -> void:
	Gen2Screen.drop(_naming)
	_naming = null
	var settled: Dictionary = Gen2NameRater.ending_for_entry(entered, _nickname)
	_ending = StringName(settled["ending"])
	_end_named(String(settled["nickname"]))


## `.samename`, which the copy falls through into: `GetCurNickname` is read again
## and `NameRaterNamedText` prints before whichever of the two endings loaded hl.
func _end_named(nickname: String) -> void:
	_nickname = nickname
	_phase = Phase.NAMED
	_show_text(_filled("named", nickname), true)


func _end(ending: StringName) -> void:
	## Only `NameRaterFinishedText` is reached past the `CopyBytes`; every other
	## ending leaves the row's nickname where it was.
	if ending != Gen2NameRater.ENDING_FINISHED:
		_party_index = -1
	_phase = Phase.DONE
	if _text_box != null:
		_text_box.visible = false
	if _menu != null:
		_menu.visible = false
	finished.emit(
		_party_index, _nickname, _filled(String(ending), _nickname)
	)
	closed.emit()


func _display_name(mon: Gen2SaveMon) -> String:
	if mon == null:
		return ""
	if not mon.nickname.is_empty():
		return mon.nickname
	return String(_data.species(mon.species).get("name", ""))


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
