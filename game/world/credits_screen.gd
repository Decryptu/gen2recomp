class_name Gen2CreditsScreen
extends Control

## The credits, embedded in the overworld the way the Hall of Fame is.
##
## [Gen2Credits] owns `Credits`' whole loop and [Gen2CreditsPage] draws it; this
## spends the frames and reads the two buttons `.execution_loop` reads. Both are
## held states rather than presses (`hJoypadDown`), so the host has to say when
## each is let go: A only leaves once the script has run out, and B burns a tick
## of the current wait per frame and only on a replay.
##
## The two `PlayMusic` calls are the overworld's rather than this screen's, the
## same way the Hall of Fame's rating sound is.

signal closed()
signal music_requested(music: int)
## `.end`'s `wMusicFade`, which fades whatever is playing into MUSIC_POST_CREDITS
## over its own frame count.
signal music_fade_requested(music: int, frames: int)

var _data: GameData = null
var _credits: Gen2Credits = null
var _page: Gen2CreditsPage = null
var _view: TextureRect = null
var _held: Array = []
## Leftover of a hardware frame this screen has not counted yet.
var _elapsed: float = 0.0


## [param skippable] is `STATUSFLAGS_HALL_OF_FAME_F`. False leaves the credits
## unskippable, which is what the first run through them is.
##
## Answers false when the cache has no credits, so a caller that has already
## added the node is left with nothing rather than an empty rectangle.
func set_context(data: GameData, skippable: bool = false) -> bool:
	_data = data
	_page = Gen2CreditsPage.from_data(data)
	_credits = Gen2Credits.create(data, skippable)
	if _page == null or not _page.ready() or _credits == null:
		_page = null
		_credits = null
		visible = false
		return false
	return true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	if _credits == null:
		closed.emit()
		return
	_view = TextureRect.new()
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	add_child(_view)
	_refresh()


func credits() -> Gen2Credits:
	return _credits


## A press is also a hold, so A is answered where it lands as well as on the
## frame after it: the script may run out while the button is already down.
func handle_button(button: int) -> bool:
	if _credits == null:
		return false
	if not button in _held:
		_held.append(button)
	if _credits.may_finish(_held):
		close()
	return true


## The other half of `hJoypadDown`, which a press-only host cannot say.
func release_button(button: int) -> void:
	_held.erase(button)


func advance_frame() -> void:
	if _credits == null:
		return
	for event: Dictionary in _credits.advance_frame(_held):
		if StringName(event.get("type", &"")) == &"music_requested":
			music_requested.emit(int(event["music"]))
		else:
			music_fade_requested.emit(int(event["music"]), int(event["frames"]))
	if _credits.may_finish(_held):
		close()
		return
	_refresh()


func advance_frames(count: int) -> void:
	for _step: int in count:
		if _credits == null:
			return
		advance_frame()


func close() -> void:
	if _credits == null:
		return
	_credits = null
	closed.emit()


## The whole 160x144 screen, for a preview or a test that wants pixels rather
## than a viewport.
func render() -> Image:
	if _page == null or _credits == null:
		return Image.create(Gen2Screen.WIDTH, Gen2Screen.HEIGHT, false, Image.FORMAT_RGBA8)
	return _page.image(_data, _credits.frame_state())


func _process(delta: float) -> void:
	if _credits == null:
		return
	_elapsed += delta
	while _elapsed >= Gen2WorldAnimation.FRAME_SECONDS:
		_elapsed -= Gen2WorldAnimation.FRAME_SECONDS
		advance_frame()


func _refresh() -> void:
	if _view == null:
		return
	_view.texture = ImageTexture.create_from_image(render())
