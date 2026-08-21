class_name Gen2DayCareScreen
extends Control

## `DayCareMan`, `DayCareLady`, `DayCareManOutside`, `DayCareMon1` and
## `DayCareMon2` on the overworld's own pump.
##
## All five are straight lines of boxes, questions, a party list and two sounds,
## so they are one screen with a queue rather than five: [Gen2WorldDayCare]
## answers every question that needs a source reading and this owns the presses.
##
## Which of the five is running decides how it ends. The two counters and the man
## outside are called from a script that follows them with `waitbutton`, so their
## last box is handed to the caller through [signal finished] and stands in the
## world's speech box for that one press; the two signs are called with no
## `waitbutton` at all, because `DayCareMonCursor` and the compatibility text's
## own `prompt` are the press.

## [param script_value] is -1 for the four routines that write no wScriptVar.
signal finished(script_value: int, ending_text: String)
signal closed()
signal cry_requested(species: int)
signal sfx_requested(sfx: int)

const TILE: int = Gen2Font.TILE

const PARTY_SCENE: PackedScene = preload("res://game/save/party_screen.tscn")

## `SFX_GET_EGG`, the one sound `DayCareManOutside` plays, and the 120 frames of
## `ld c, 120 / call DelayFrames` behind it.
const SFX_GET_EGG: int = 0xAC
const EGG_SOUND_FRAMES: int = 120

## Every box the five routines print that ends in `prompt` rather than `done`,
## which is the whole of the difference between a box that waits for a press and
## one the next thing draws over.
const PROMPT_TEXTS: Array[String] = [
	Gen2WorldDayCare.TEXT_WHICH_ONE, Gen2WorldDayCare.TEXT_LAST_MON,
	Gen2WorldDayCare.TEXT_CANT_BREED_EGG, Gen2WorldDayCare.TEXT_REMOVE_MAIL,
	Gen2WorldDayCare.TEXT_LAST_ALIVE_MON, Gen2WorldDayCare.TEXT_DEPOSIT,
	Gen2WorldDayCare.TEXT_WITHDRAW, Gen2WorldDayCare.TEXT_GOT_BACK,
	Gen2WorldDayCare.TEXT_PARTY_FULL, Gen2WorldDayCare.TEXT_NOT_ENOUGH_MONEY,
	Gen2WorldDayCare.TEXT_OH_FINE,
	Gen2WorldDayCare.COMPATIBILITY_BRIMMING, Gen2WorldDayCare.COMPATIBILITY_NONE,
	Gen2WorldDayCare.COMPATIBILITY_CARES, Gen2WorldDayCare.COMPATIBILITY_FRIENDLY,
	Gen2WorldDayCare.COMPATIBILITY_INTEREST,
]

## `constants/script_constants.asm`'s YOUR_MONEY.
const ACCOUNT_YOUR_MONEY: int = 0

enum Phase { TEXT, ASK, PARTY, WAIT, DONE }

var _data: GameData = null
var _save: Gen2SaveData = null
var _state: Gen2WorldState = null
var _role: StringName = &"man"
var _player_name: String = ""
var _player_id: int = 0
var _random: RandomNumberGenerator = null
## Every stub `RomLayout.DAY_CARE_TEXT_RUNS` names, by that name.
var _texts: Dictionary = {}

var _phase: int = Phase.DONE
var _queue: Array = []
var _yes: bool = true
var _question: StringName = &""
var _wait_frames: int = 0
## Whether the box now up is one the routine waits on, and the text it is
## holding. `Gen2TextBox` keeps neither: whether a box blinks is not whether it
## waits, and the two are decided here off the source's own terminators.
var _text_waits: bool = false
var _text_source: String = ""
var _script_value: int = -1
var _ending_text: String = ""
## Which slot the running routine acts on, and what it costs to get it back.
var _slot: int = Gen2WorldDayCare.SLOT_MAN
var _price: int = 0
var _growth: int = 0

var _text_box: Gen2TextBox = null
var _menu_page: Gen2MenuPage = null
var _menu: TextureRect = null
var _party: Gen2PartyScreen = null


func set_context(
	data: GameData,
	save: Gen2SaveData,
	state: Gen2WorldState,
	role: StringName,
	texts: Dictionary,
	player_name: String,
	player_id: int,
	random: RandomNumberGenerator
) -> void:
	_data = data
	_save = save
	_state = state
	_role = role
	_texts = texts.duplicate(true)
	_player_name = player_name
	_player_id = player_id
	_random = random


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	if _data == null or _save == null or _state == null \
		or _text(Gen2WorldDayCare.TEXT_MAN_INTRO).is_empty():
		_finish()
		return
	_build()
	match _role:
		&"lady":
			_slot = Gen2WorldDayCare.SLOT_LADY
			_open_counter()
		&"outside":
			_open_outside()
		&"mon1":
			_open_sign(Gen2WorldDayCare.SLOT_MAN)
		&"mon2":
			_open_sign(Gen2WorldDayCare.SLOT_LADY)
		_:
			_open_counter()
	_step()


func phase() -> int:
	return _phase


## The YES/NO cursor, so a driver can read it without a redraw. -1 when no box is
## up.
func question_cursor() -> int:
	return (0 if _yes else 1) if _phase == Phase.ASK else -1


func text_lines() -> PackedStringArray:
	if _text_box == null or not _text_box.visible:
		return PackedStringArray()
	return _text_box.text_lines()


func party_screen() -> Gen2PartyScreen:
	return _party


func handle_button(button: int) -> bool:
	if _phase == Phase.PARTY and _party != null:
		return _party.handle_button(button)
	if _phase == Phase.ASK:
		match button:
			Gen2Button.UP, Gen2Button.DOWN:
				_yes = not _yes
				_draw_yes_no()
				return true
			Gen2Button.A:
				_answer(_yes)
				return true
			Gen2Button.B:
				## `YesNoBox` answers B with the carry each caller takes as NO.
				_answer(false)
				return true
		return false
	if _phase != Phase.TEXT or button != Gen2Button.A \
		or _text_box == null or not _text_box.visible:
		return false
	if _text_box.is_revealing() or _text_box.has_pages_left():
		_text_box.advance()
		return true
	_step()
	return true


func advance_frame() -> void:
	if _phase == Phase.WAIT:
		_wait_frames -= 1
		if _wait_frames <= 0:
			_step()
		return
	if _text_box == null or not _text_box.visible:
		return
	_text_box.advance_frame()
	if _text_box.is_revealing() or _text_box.has_pages_left():
		return
	## `PrintText` on a text ending in `done` returns without a press, so the
	## queue carries on the frame the last character lands.
	if _phase == Phase.TEXT and not _text_waits:
		_step()


## `DayCareMan` and `DayCareLady`, which differ only in the slot and in which
## intro the first visit prints.
func _open_counter() -> void:
	if _state.day_care_has_mon(_slot):
		_queue_withdraw()
		return
	_queue.append({"text": _intro_key()})
	_queue.append({"ask": &"deposit"})


## `DayCareManIntroText` sets the man's ACTIVE bit and always prints his short
## line; `DayCareLadyIntroText` prints the *egg* variant on the visit that sets
## hers, which is why only the lady ever explains what an egg is.
func _intro_key() -> String:
	if _slot == Gen2WorldDayCare.SLOT_MAN:
		_state.set_day_care_man_flags(
			_state.day_care_man_flags() | Gen2WorldDayCare.MAN_ACTIVE
		)
		return Gen2WorldDayCare.TEXT_MAN_INTRO
	if _state.day_care_lady_flags() & Gen2WorldDayCare.LADY_ACTIVE != 0:
		return Gen2WorldDayCare.TEXT_LADY_INTRO
	_state.set_day_care_lady_flags(
		_state.day_care_lady_flags() | Gen2WorldDayCare.LADY_ACTIVE
	)
	return Gen2WorldDayCare.TEXT_LADY_INTRO_EGG


## `.AskWithdrawMon`: the level growth and the price are read before the first
## box, since both of them are printed inside it.
func _queue_withdraw() -> void:
	var mon: Gen2SaveMon = _state.day_care_mon(_slot)
	_growth = Gen2WorldDayCare.level_growth(_data, mon)
	_price = Gen2WorldDayCare.price_to_retrieve(_growth)
	if _growth == 0:
		_queue.append({"text": Gen2WorldDayCare.TEXT_TOO_SOON})
		_queue.append({"ask": &"withdraw_soon"})
		return
	_queue.append({"text": Gen2WorldDayCare.TEXT_GENIUSES})
	_queue.append({"ask": &"withdraw_see"})


## `DayCareManOutside`.
func _open_outside() -> void:
	if _state.day_care_man_flags() & Gen2WorldDayCare.MAN_HAS_EGG == 0:
		## `.NotYetText` returns without writing wScriptVar at all.
		_queue.append({"text": "not_yet"})
		return
	_queue.append({"text": "found_an_egg"})
	_queue.append({"ask": &"take_egg"})


## `DayCareMon1` and `DayCareMon2`.
func _open_sign(slot: int) -> void:
	var mine: Gen2SaveMon = _state.day_care_mon(slot)
	var other_slot: int = 1 - slot
	var key: String = "left_with_man" if slot == Gen2WorldDayCare.SLOT_MAN \
		else "left_with_lady"
	_queue.append({"text": key, "ram": _nickname(mine)})
	_queue.append({"cry": 0 if mine == null else mine.species})
	if not _state.day_care_has_mon(other_slot):
		## `DayCareMonCursor` is `WaitPressAorB_BlinkCursor`, which is the box
		## already standing plus a press.
		_queue.append({"press": true})
		return
	## `PromptButton`, and then the compatibility line, which names the *other*
	## slot in `wStringBuffer1`.
	_queue.append({"press": true})
	var other: Gen2SaveMon = _state.day_care_mon(other_slot)
	var value: int = Gen2WorldDayCare.compatibility(_data, mine, other)
	_queue.append({
		"text": Gen2WorldDayCare.compatibility_text_key(value),
		"ram": _nickname(other),
	})


func _answer(yes: bool) -> void:
	if _menu != null:
		_menu.visible = false
	var question: StringName = _question
	_question = &""
	match question:
		&"deposit":
			if not yes:
				_queue_cancel()
			else:
				_queue_deposit_selection()
		&"withdraw_soon":
			if not yes:
				_queue_refusal(Gen2WorldDayCare.TEXT_OH_FINE)
			else:
				_queue_pay()
		&"withdraw_see":
			if not yes:
				_queue_refusal(Gen2WorldDayCare.TEXT_OH_FINE)
			else:
				_queue.append({"text": Gen2WorldDayCare.TEXT_ASK_WITHDRAW})
				_queue.append({"ask": &"withdraw_take"})
		&"withdraw_take":
			if not yes:
				_queue_refusal(Gen2WorldDayCare.TEXT_OH_FINE)
			else:
				_queue_pay()
		&"take_egg":
			if not yes:
				_script_value = 0
				_queue.append({"text": "ill_keep_it"})
			elif _save.party.size() >= Gen2SaveData.MAX_PARTY:
				_script_value = 1
				_queue.append({"text": "no_room_for_egg"})
			else:
				_give_egg()
	_step()


## `DayCareAskDepositPokemon`'s own first test, which is the party count and not
## the selection: one Pokemon never reaches the list at all.
func _queue_deposit_selection() -> void:
	if _save.party.size() < 2:
		_queue_refusal(Gen2WorldDayCare.TEXT_LAST_MON)
		return
	_queue.append({"text": Gen2WorldDayCare.TEXT_WHICH_ONE})
	_queue.append({"party": true})


## `.print_text` then `.cancel`: a refusal prints its own box and then
## `ComeAgainText`.
func _queue_refusal(key: String) -> void:
	_queue.append({"text": key})
	_queue_cancel()


func _queue_cancel() -> void:
	_queue.append({"text": Gen2WorldDayCare.TEXT_COME_AGAIN})


## `.check_money` and `DayCare_GetBackMonForMoney`.
func _queue_pay() -> void:
	if _state.money(ACCOUNT_YOUR_MONEY) < _price:
		_queue_refusal(Gen2WorldDayCare.TEXT_NOT_ENOUGH_MONEY)
		return
	if _save.party.size() >= Gen2SaveData.MAX_PARTY:
		_queue_refusal(Gen2WorldDayCare.TEXT_PARTY_FULL)
		return
	var mon: Gen2SaveMon = _state.day_care_mon(_slot)
	var nickname: String = _nickname(mon)
	var retrieved: Dictionary = Gen2WorldDayCare.retrieve(_state, _save, _data, _slot)
	if retrieved.is_empty():
		_queue_cancel()
		return
	_state.apply_changes({}, {}, {
		"money": {ACCOUNT_YOUR_MONEY: _state.money(ACCOUNT_YOUR_MONEY) - _price},
	})
	## Withdrawing from either slot clears the man's compatibility bit, since it
	## is the *pair* that is no longer breeding.
	_state.set_day_care_man_flags(
		_state.day_care_man_flags() & ~Gen2WorldDayCare.MAN_MONS_COMPATIBLE
	)
	_queue.append({"text": Gen2WorldDayCare.TEXT_WITHDRAW})
	_queue.append({"cry": int(retrieved.get("species", 0))})
	_queue.append({"text": Gen2WorldDayCare.TEXT_GOT_BACK, "ram": nickname})
	_queue_cancel()


## `DayCare_GiveEgg`, `DayCare_InitBreeding` behind it and the three boxes.
func _give_egg() -> void:
	var given: Dictionary = Gen2WorldDayCare.give_egg(_state, _save)
	if given.is_empty():
		_script_value = 1
		_queue.append({"text": "no_room_for_egg"})
		return
	Gen2WorldDayCare.init_breeding(
		_state, _data, _player_name, _player_id, _random
	)
	_script_value = 0
	_queue.append({"text": "received_egg"})
	_queue.append({"sfx": SFX_GET_EGG, "frames": EGG_SOUND_FRAMES})
	_queue.append({"text": "take_good_care"})


func _step() -> void:
	if _queue.is_empty():
		_finish()
		return
	var action: Dictionary = _queue.pop_front()
	if action.has("text"):
		_phase = Phase.TEXT
		_show_text(action)
		return
	if action.has("ask"):
		_phase = Phase.ASK
		_question = StringName(action["ask"])
		_yes = true
		_draw_yes_no()
		return
	if action.has("party"):
		_open_party()
		return
	if action.has("cry"):
		if int(action["cry"]) > 0:
			cry_requested.emit(int(action["cry"]))
		_step()
		return
	if action.has("sfx"):
		sfx_requested.emit(int(action["sfx"]))
		_phase = Phase.WAIT
		_wait_frames = int(action.get("frames", 0))
		if _wait_frames <= 0:
			_step()
		return
	if action.has("press"):
		## A box already standing plus the press `PromptButton` and
		## `DayCareMonCursor` wait for, arrow included.
		_phase = Phase.TEXT
		_text_waits = true
		if _text_box != null:
			_text_box.set_blink_cursor(true)
		return
	_step()





func _show_text(action: Dictionary) -> void:
	var key: String = String(action["text"])
	var text: String = _text(key)
	if action.has("ram"):
		text = Gen2TextStream.fill_all_markers(
			text, Gen2TextStream.RAM_MARKER, String(action["ram"])
		)
	if key == Gen2WorldDayCare.TEXT_ASK_WITHDRAW:
		## `_YourMonHasGrownText`'s two `text_decimal`s, in the order it prints
		## them: the levels gained and then the price.
		text = Gen2TextStream.fill_marker(
			text, Gen2TextStream.NUMBER_MARKER, "%3d" % _growth
		)
		text = Gen2TextStream.fill_marker(
			text, Gen2TextStream.NUMBER_MARKER, "%4d" % _price
		)
	text = Gen2TextStream.fill_all_markers(text, "<PLAYER", _player_name)
	if _menu != null:
		_menu.visible = false
	if _text_box == null:
		return
	_text_waits = key in PROMPT_TEXTS
	_text_source = text
	_text_box.visible = true
	_text_box.show_text(text, _text_waits)


## `SelectTradeOrDayCareMon`, which is the party list under
## PARTYMENUACTION_GIVE_MON.
func _open_party() -> void:
	var host: Gen2PartyScreen = PARTY_SCENE.instantiate() as Gen2PartyScreen
	if host == null:
		_queue_refusal(Gen2WorldDayCare.TEXT_OH_FINE)
		_step()
		return
	host.set_context(_data, _save, true)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	host.selection_made.connect(_on_selected)
	add_child(host)
	host.open_selection()
	_party = host
	_text_box.visible = false
	_phase = Phase.PARTY


func _on_selected(party_index: int) -> void:
	Gen2Screen.drop(_party)
	_party = null
	if party_index < 0 or party_index >= _save.party.size():
		## `.Declined`, which is the same `OhFineThenText` a refused question
		## prints.
		_queue_refusal(Gen2WorldDayCare.TEXT_OH_FINE)
		_step()
		return
	var refusal: String = Gen2WorldDayCare.deposit_refusal(_save, party_index)
	if not refusal.is_empty():
		_queue_refusal(refusal)
		_step()
		return
	var mon: Gen2SaveMon = _save.party[party_index] as Gen2SaveMon
	var nickname: String = _nickname(mon)
	var species: int = mon.species
	Gen2WorldDayCare.deposit(_state, _save, _slot, party_index)
	Gen2WorldDayCare.init_breeding(_state, _data, _player_name, _player_id, _random)
	## `DayCare_DepositPokemonText`, and then the `ret` that leaves
	## `ComeAgainText` unprinted: a deposit is the one path that does not end on
	## it.
	_queue.append({"text": Gen2WorldDayCare.TEXT_DEPOSIT, "ram": nickname})
	_queue.append({"cry": species})
	_queue.append({"text": Gen2WorldDayCare.TEXT_COME_BACK_LATER})
	_step()


func _finish() -> void:
	_phase = Phase.DONE
	if _menu != null:
		_menu.visible = false
	## The two signs press their own last box; the three routines a script
	## follows with `waitbutton` hand theirs over instead.
	if _role not in [&"mon1", &"mon2"] and _text_box != null and _text_box.visible:
		_ending_text = _text_source
	if _text_box != null:
		_text_box.visible = false
	finished.emit(_script_value, _ending_text)
	closed.emit()


func _text(key: String) -> String:
	return String(_texts.get(key, ""))


func _nickname(mon: Gen2SaveMon) -> String:
	if mon == null:
		return ""
	if not mon.nickname.is_empty():
		return mon.nickname
	return String(_data.species(mon.species).get("name", ""))


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
