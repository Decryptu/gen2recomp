class_name Gen2UnownPuzzleScreen
extends Control

## `_UnownPuzzle`'s own loop, on the overworld's pump.
##
## [Gen2UnownPuzzle] owns the rules and [Gen2UnownPuzzlePage] the picture; this
## is `.loop`: one pass a frame, `JoyTextDelay`'s repeat carried by the board,
## and the exit `JUMPTABLE_EXIT_F` sets.
##
## Two things the loop states that a screen would otherwise get wrong:
##
## - **A press is answered where it lands as well as on the frame.** The host is
##   press-only, so a tap between two frames would be lost; the pass runs on the
##   press and the frame's own pass is skipped, which keeps one pass a frame.
## - **`UnownPuzzle_A` ends on `WaitSFX` and nothing is read until it returns.**
##   The wait is the driver's, not a frame count, so the screen holds while the
##   player it was handed reports an effect. A screen with no player waits
##   nothing, which is what a headless driver and every test see.

signal closed(solved: bool)
signal sfx_requested(index: int, waited: bool)

var _board: Gen2UnownPuzzle = null
var _page: Gen2UnownPuzzlePage = null
var _view: TextureRect = null
var _audio: Gen2AudioPlayer = null
## `hVBlankCounter`, which the empty cursor blinks off.
var _frame: int = 0
## Whether this frame's pass has already run, which a press does.
var _acted: bool = false
## Whether `WaitSFX` is still holding.
var _waiting: bool = false
## `hJoyDown`, which the host can only say by pairing presses with releases. A
## direction walks the board while it is held, so this is what the repeat reads.
var _held: Array[int] = []
var _open: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)


## [param puzzle] is the `UNOWNPUZZLE_*` index the map's own `setval` left in
## wScriptVar, [param rng] the generator the scatter is drawn from.
##
## Answers false on a cache with no puzzle art, which is what a caller refuses
## the special on rather than opening an empty board.
func open(data: GameData, puzzle: int, rng: RandomNumberGenerator) -> bool:
	_page = Gen2UnownPuzzlePage.from_data(data, puzzle)
	if _page == null or not _page.ready():
		visible = false
		return false
	_board = Gen2UnownPuzzle.create(rng)
	_open = true
	visible = true
	_refresh()
	return true


func set_audio_player(player: Gen2AudioPlayer) -> void:
	_audio = player


func board() -> Gen2UnownPuzzle:
	return _board


func page() -> Gen2UnownPuzzlePage:
	return _page


func frame_number() -> int:
	return _frame


## Whether `WaitSFX` is holding the loop this frame.
func waiting_for_sfx() -> bool:
	return _waiting


func handle_button(button: int) -> bool:
	if not _open or _board == null:
		return false
	if not _held.has(button):
		_held.append(button)
	if _waiting:
		return true
	_pass([button], _held)
	_acted = true
	_refresh()
	return true


## The other half of `hJoyDown`. A direction released stops walking; a press the
## host never releases would otherwise repeat for ever.
func release_button(button: int) -> void:
	_held.erase(button)


func advance_frame() -> void:
	if not _open or _board == null:
		return
	_frame += 1
	if _waiting:
		## `WaitSFX`. Held by the driver rather than by a count, so a screen with
		## no audio player is never held and a test drives straight through.
		if _audio != null and _audio.effect_playing():
			_refresh()
			return
		_waiting = false
	if not _acted:
		_pass([], _held)
	_acted = false
	_refresh()


## One pass of `.loop`, and the exit it may reach.
func _pass(pressed: Array, held: Array) -> void:
	var result: Dictionary = _board.advance(pressed, held)
	for index: int in result.get("sounds", []) as Array:
		sfx_requested.emit(index, false)
	if bool(result.get("wait_sfx", false)):
		_waiting = true
	if _board.finished():
		close()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit(_board != null and _board.solved())


func _refresh() -> void:
	if _page == null or _board == null:
		return
	if _view == null:
		_view = TextureRect.new()
		_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_view)
	_view.texture = ImageTexture.create_from_image(_page.render(_board, _frame))
