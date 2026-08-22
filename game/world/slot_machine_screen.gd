class_name Gen2SlotMachineScreen
extends Control

## `_SlotMachine`'s own loop, on the overworld's pump.
##
## [Gen2SlotMachine] owns the rules and [Gen2SlotMachinePage] the picture; this
## is `SlotsLoop`: one pass a frame, the boxes the machine asks for answered
## where the cartridge's own blocking calls would have stood, and the exit
## `SLOTS_END_LOOP_F` sets.
##
## Three things the loop states that a screen would otherwise get wrong:
##
## - **`Slots_AskBet` and `Slots_AskPlayAgain` spend frames inside an action.**
##   `VerticalMenu` and `PlaceYesNoBox` do not return until the player answers,
##   so nothing spins, no reel moves and no sprite is pumped while either is up.
##   The machine answers `prompt()` for exactly that reason.
## - **A press is answered where it lands as well as on the frame.** The host is
##   press-only, and `hJoypadSum` is a sum rather than a sample: a tap between
##   two frames stops a reel on the cartridge and has to here.
## - **`WaitSFX` is the driver's, not a frame count.** The screen holds while
##   the player it was handed reports an effect; a screen with no player waits
##   nothing, which is what a headless driver and every test see.

signal closed(coins: int)
signal sfx_requested(index: int, waited: bool)
signal music_requested(index: int)

var _machine: Gen2SlotMachine = null
var _page: Gen2SlotMachinePage = null
var _view: TextureRect = null
var _audio: Gen2AudioPlayer = null
var _data: GameData = null
## The box standing under the machine, which is `PrintText`'s own.
var _text: String = ""
## `wMenuCursorY` for whichever of the two menus is up.
var _bet_cursor: int = 1
var _yes_no_cursor: int = 1
## Whether this frame's pass has already run, which a press does.
var _acted: bool = false
var _open: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)


## [param coins] is `wCoins` and [param lucky] the `wScriptVar` the map's own
## `setval` left in front of the special.
##
## Answers false on a cache with no slots art, which is what a caller refuses
## the special on rather than opening an empty machine.
func open(
	data: GameData, coins: int, lucky: bool, rng: RandomNumberGenerator
) -> bool:
	_page = Gen2SlotMachinePage.from_data(data)
	if _page == null or not _page.ready():
		visible = false
		return false
	_data = data
	var strips: Array[PackedByteArray] = []
	for reel: int in Gen2SlotMachine.REELS:
		strips.append(data.slots_reel(reel))
	_machine = Gen2SlotMachine.create(strips, coins, lucky, rng)
	_open = true
	visible = true
	_drain()
	_refresh()
	return true


func set_audio_player(player: Gen2AudioPlayer) -> void:
	_audio = player


func machine() -> Gen2SlotMachine:
	return _machine


func page() -> Gen2SlotMachinePage:
	return _page


func text() -> String:
	return _text


## What the machine is asking the player for, if anything.
func prompt() -> int:
	return _machine.prompt() if _machine != null else Gen2SlotMachine.Prompt.NONE


## One pass of `SlotsLoop`, plus the `WaitSFX` the driver may be holding it on.
func advance_frame() -> void:
	if not _open or _machine == null:
		return
	if _machine.waiting_for_sfx():
		if _audio != null and _audio.effect_playing():
			_refresh()
			return
		_machine.sfx_finished()
	if not _acted:
		_pass()
	_acted = false
	_refresh()


## A press. The three `SlotsAction_WaitReel*` read A alone; the two menus read
## the pad and B, and are the only place either matters.
func handle_button(button: int) -> bool:
	if not _open or _machine == null:
		return false
	match _machine.prompt():
		Gen2SlotMachine.Prompt.BET:
			_handle_bet_button(button)
		Gen2SlotMachine.Prompt.PLAY_AGAIN:
			_handle_yes_no_button(button)
		Gen2SlotMachine.Prompt.TEXT, Gen2SlotMachine.Prompt.PRESS:
			if button == Gen2Button.A or button == Gen2Button.B:
				_machine.dismiss_text()
				_drain()
		_:
			if button == Gen2Button.A:
				_machine.press_a()
			_pass()
			_acted = true
	_refresh()
	return true


## `VerticalMenu` over `Slots_AskBet.MenuData`: three items, no wrap, B cancels.
func _handle_bet_button(button: int) -> void:
	match button:
		Gen2Button.UP:
			_bet_cursor = maxi(1, _bet_cursor - 1)
		Gen2Button.DOWN:
			_bet_cursor = mini(Gen2SlotMachinePage.BET_MENU_ITEMS.size(), _bet_cursor + 1)
		Gen2Button.A:
			_text = ""
			_machine.answer_bet(_bet_cursor)
			_drain()
		Gen2Button.B:
			_text = ""
			_machine.answer_bet(-1)
			_drain()
		_:
			pass


## `PlaceYesNoBox`, which opens on YES and takes B as NO.
func _handle_yes_no_button(button: int) -> void:
	match button:
		Gen2Button.UP:
			_yes_no_cursor = 1
		Gen2Button.DOWN:
			_yes_no_cursor = 2
		Gen2Button.A:
			_text = ""
			_machine.answer_play_again(_yes_no_cursor == 1)
			_yes_no_cursor = 1
			_drain()
		Gen2Button.B:
			_text = ""
			_machine.answer_play_again(false)
			_yes_no_cursor = 1
			_drain()
		_:
			pass


## One pass of the loop and whatever it emitted.
func _pass() -> void:
	if not _machine.advance() and not _machine.waiting_for_sfx():
		_drain()
		close()
		return
	_drain()


## The sounds, boxes and music the pass asked for.
func _drain() -> void:
	for event: Variant in _machine.take_events():
		var row: Dictionary = event
		match row.get("kind", &""):
			&"sound":
				sfx_requested.emit(int(row["index"]), false)
			&"music":
				music_requested.emit(int(row["index"]))
			&"text":
				_text = _data.slots_text(String(row["name"])) if _data != null else ""
			_:
				pass


## The state the page draws over the machine.
func overlay_state() -> Dictionary:
	if _machine == null:
		return {}
	return {
		"text": _text,
		"menu": _bet_cursor if _machine.prompt() == Gen2SlotMachine.Prompt.BET else 0,
		"yes_no": _yes_no_cursor \
			if _machine.prompt() == Gen2SlotMachine.Prompt.PLAY_AGAIN else 0,
	}


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit(_machine.coins() if _machine != null else 0)


func _refresh() -> void:
	if _page == null or _machine == null:
		return
	if _view == null:
		_view = TextureRect.new()
		_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_view)
	_view.texture = ImageTexture.create_from_image(
		_page.render(_machine, overlay_state())
	)
