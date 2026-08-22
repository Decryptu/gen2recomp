class_name Gen2CardFlipScreen
extends Control

## `_CardFlip`'s own loop, on the overworld's pump.
##
## [Gen2CardFlip] owns the rules and [Gen2CardFlipPage] the picture; this is
## `.MasterLoop`: one pass a frame, the boxes the game asks for answered where
## the cartridge's own blocking calls would have stood, and the exit
## `JUMPTABLE_EXIT_F` sets.
##
## Two things the loop states that a screen would otherwise get wrong:
##
## - **`YesNoBox` spends frames inside a state.** `VerticalMenu` does not return
##   until the player answers, so nothing deals, nothing toggles and no coin is
##   paid while either box is up. `.ChooseACard`'s toggle and `.PlaceYourBet`'s
##   cursor are the opposite: both read the joypad on frames the loop is still
##   spending, so a press there is answered where it lands as well as on the
##   frame.
## - **`WaitSFX` is the driver's, not a frame count.** The screen holds while the
##   player it was handed reports an effect; a screen with no player waits
##   nothing, which is what a headless driver and every test see.

signal closed(coins: int)
signal sfx_requested(index: int, waited: bool)
signal music_requested(index: int)

var _game: Gen2CardFlip = null
var _page: Gen2CardFlipPage = null
var _view: TextureRect = null
var _audio: Gen2AudioPlayer = null
var _data: GameData = null
## The box under the table, which is `PrintTextboxText`'s own.
var _text: String = ""
## `wMenuCursorY` for whichever `YesNoBox` is up.
var _yes_no_cursor: int = 1
## Whether this frame's pass has already run, which a press does.
var _acted: bool = false
var _open: bool = false
## `hVBlankCounter`, which `_BlinkCursor` counts the arrow's own phase off.
var _frames: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)


## [param coins] is `wCoins` and [param object_palette] the `wOBPals1` palette 0
## the map screen left standing, which every object here is drawn through.
##
## Answers false on a cache with no card flip art, which is what a caller
## refuses the special on rather than opening an empty table.
func open(
	data: GameData, coins: int, object_palette: PackedColorArray,
	rng: RandomNumberGenerator
) -> bool:
	_page = Gen2CardFlipPage.from_data(data)
	if _page == null or not _page.ready():
		visible = false
		return false
	_data = data
	_page.set_object_palette(object_palette)
	_game = Gen2CardFlip.create(_page.board(), coins, rng)
	_open = true
	visible = true
	_drain()
	_refresh()
	return true


func set_audio_player(player: Gen2AudioPlayer) -> void:
	_audio = player


func game() -> Gen2CardFlip:
	return _game


func page() -> Gen2CardFlipPage:
	return _page


func text() -> String:
	return _text


func prompt() -> int:
	return _game.prompt() if _game != null else Gen2CardFlip.Prompt.NONE


## One pass of `.MasterLoop`, plus the `WaitSFX` the driver may be holding it on.
func advance_frame() -> void:
	if not _open or _game == null:
		return
	if _game.waiting_for_sfx():
		if _audio != null and _audio.effect_playing():
			_refresh()
			return
		_game.sfx_finished()
	_frames += 1
	if not _acted:
		_pass()
	_acted = false
	_refresh()


## A press. `.ChooseACard` and `.PlaceYourBet` read A, the bet loop reads the
## pad, and the two `YesNoBox` calls read the pad and B.
func handle_button(button: int) -> bool:
	if not _open or _game == null:
		return false
	match _game.prompt():
		Gen2CardFlip.Prompt.YES_NO:
			_handle_yes_no_button(button)
		Gen2CardFlip.Prompt.PRESS:
			if button == Gen2Button.A or button == Gen2Button.B:
				_game.dismiss_text()
				_drain()
		Gen2CardFlip.Prompt.BET:
			if button == Gen2Button.A:
				_game.press_a()
			else:
				_game.move_cursor(button)
			_drain()
		Gen2CardFlip.Prompt.CHOOSE:
			if button == Gen2Button.A:
				_game.press_a()
			_drain()
		_:
			pass
	_refresh()
	return true


## `PlaceYesNoBox`, which opens on YES and takes B as NO.
func _handle_yes_no_button(button: int) -> void:
	match button:
		Gen2Button.UP:
			_yes_no_cursor = 1
		Gen2Button.DOWN:
			_yes_no_cursor = 2
		Gen2Button.A:
			_text = ""
			var yes: bool = _yes_no_cursor == 1
			_yes_no_cursor = 1
			_game.answer_yes_no(yes)
			_drain()
		Gen2Button.B:
			_text = ""
			_yes_no_cursor = 1
			_game.answer_yes_no(false)
			_drain()
		_:
			pass


## One pass of the loop and whatever it emitted.
func _pass() -> void:
	if not _game.advance() and not _game.waiting_for_sfx():
		_drain()
		close()
		return
	_drain()


## The sounds, boxes and music the pass asked for.
func _drain() -> void:
	for event: Variant in _game.take_events():
		var row: Dictionary = event
		match row.get("kind", &""):
			&"sound":
				sfx_requested.emit(int(row["index"]), false)
			&"music":
				music_requested.emit(int(row["index"]))
			&"text":
				_text = _data.card_flip_text(String(row["name"])) if _data != null else ""
			_:
				pass


## The state the page draws over the table.
func overlay_state() -> Dictionary:
	if _game == null:
		return {}
	var waiting: bool = _game.prompt() == Gen2CardFlip.Prompt.PRESS \
		and _game.blinking_cursor()
	return {
		"text": _text,
		"blink": _frames if waiting else -1,
		"yes_no": _yes_no_cursor \
			if _game.prompt() == Gen2CardFlip.Prompt.YES_NO else 0,
	}


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit(_game.coins() if _game != null else 0)


func _refresh() -> void:
	if _page == null or _game == null:
		return
	if _view == null:
		_view = TextureRect.new()
		_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_view)
	_view.texture = ImageTexture.create_from_image(
		_page.render(_game, overlay_state())
	)
