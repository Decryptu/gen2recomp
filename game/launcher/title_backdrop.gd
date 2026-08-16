class_name Gen2LauncherTitleBackdrop
extends Node

## A muted, non-interactive title-screen loop for the launcher backdrop.
##
## This deliberately hosts only [Gen2TitleScene] and [Gen2TitlePage]. The boot
## cinema that advances into the intro and menu is never created, and neither is
## an audio player. When the title timer expires, this node creates a fresh title
## scene and starts the same title animation again.

const FRAME_TIME: float = 1.0 / 60.0
const MAX_STEPS_PER_TICK: int = 4

var _data: GameData = null
var _page: Gen2TitlePage = null
var _scene: Gen2TitleScene = null
var _sine: Gen2BattleAnimData = null
var _texture: ImageTexture = null
var _elapsed: float = 0.0


func _ready() -> void:
	set_process(false)


## Starts or resumes [param data]'s title. Answers the live texture the shell
## should display, or null when this cache does not carry title-screen art.
func show_game(data: GameData) -> Texture2D:
	if data == null:
		hide_backdrop()
		return null
	if _data != data:
		_data = data
		_page = Gen2TitlePage.from_data(data)
		_sine = Gen2BattleAnimData.from_game_data(data)
		# A game change gets a new resource so the shell can crossfade to it. A
		# loop restart keeps the existing resource because the shell holds it.
		_texture = null
		_restart()
	if _page == null or _scene == null:
		set_process(false)
		return null
	set_process(true)
	return _texture


func hide_backdrop() -> void:
	set_process(false)
	_elapsed = 0.0


func _process(delta: float) -> void:
	if _page == null or _scene == null or _texture == null:
		return
	_elapsed += delta
	var steps: int = mini(int(_elapsed / FRAME_TIME), MAX_STEPS_PER_TICK)
	if steps <= 0:
		return
	_elapsed -= float(steps) * FRAME_TIME
	for _step: int in steps:
		_scene.advance_frame()
		if _scene.finished():
			_restart()
	var frame: Image = _clean_frame(_page.draw(_scene))
	if frame != null:
		_texture.update(frame)


func _restart() -> void:
	_elapsed = 0.0
	if _data == null or _page == null:
		_scene = null
		_texture = null
		return
	_scene = Gen2TitleScene.create(_data.id, _sine)
	var frame: Image = _clean_frame(_page.draw(_scene))
	if frame == null:
		_texture = null
	elif _texture == null:
		_texture = ImageTexture.create_from_image(frame)
	else:
		_texture.update(frame)


## Removes only the title lettering from the launcher copy. The real title page
## and every gameplay caller still receive the cartridge-accurate frame.
func _clean_frame(frame: Image) -> Image:
	if frame == null:
		return null
	# Gold and Silver keep the logo in the first seven tile rows; Crystal starts
	# its logo three rows down and ends on row ten. Their animated Pokémon begin
	# below these bands, so none of the live subject is erased.
	var lettering_bottom: int = 80 if _data.id == RomRegistry.CRYSTAL else 60
	frame.fill_rect(
		Rect2i(0, 0, frame.get_width(), lettering_bottom),
		frame.get_pixel(0, 0),
	)
	# The copyright is the final tile row. Preserve each profile's lower-band
	# colour instead of imposing a colour of the launcher's own.
	for y: int in range(136, frame.get_height()):
		frame.fill_rect(Rect2i(0, y, frame.get_width(), 1), frame.get_pixel(0, y))
	return frame
