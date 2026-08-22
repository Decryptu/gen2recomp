class_name Gen2LauncherTitleBackdrop
extends Node

## A non-interactive title-screen loop, picture and music, for the launcher
## backdrop.
##
## This deliberately hosts only [Gen2TitleScene] and [Gen2TitlePage]. The boot
## cinema that advances into the intro and menu is never created. What it does
## create is the cartridge sound driver, so the screen is heard as well as seen:
## the same `MUSIC_TITLE` the title screen itself plays, at [constant
## VOLUME_SCALE] of the player's settings, looping for as long as the backdrop
## is up.

const FRAME_TIME: float = 1.0 / 60.0
const MAX_STEPS_PER_TICK: int = 4
## The backdrop plays under an interface rather than as the game, so it takes
## half of whatever the app block's music volume is.
const VOLUME_SCALE: float = 0.5
## How often the loop is checked. The title piece loops on the driver's own
## `loopchannel`, so this only has to catch a cache whose piece ends.
const LOOP_CHECK_FRAMES: int = 60

var _data: GameData = null
var _page: Gen2TitlePage = null
var _scene: Gen2TitleScene = null
var _sine: Gen2BattleAnimData = null
var _texture: ImageTexture = null
var _elapsed: float = 0.0
var _audio: Gen2AudioPlayer = null
var _loop_countdown: int = LOOP_CHECK_FRAMES


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
		_stop_music()
		return null
	set_process(true)
	_start_music()
	return _texture


func hide_backdrop() -> void:
	set_process(false)
	_elapsed = 0.0
	_stop_music()


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
	_hold_music()


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


## `PlayMusic MUSIC_TITLE`, which is what the title screen's own entrance ends
## on. The player is built on the first backdrop rather than in `_ready` so a
## headless launcher run, a test or a screenshot tool never wakes the driver.
func _start_music() -> void:
	if _data == null:
		return
	var record: Dictionary = _data.world_audio(&"music", Gen2BootCinema.MUSIC_TITLE)
	if record.is_empty():
		return
	if _audio == null:
		_audio = Gen2AudioPlayer.new()
		_audio.volume_scale = VOLUME_SCALE
		add_child(_audio)
	_loop_countdown = LOOP_CHECK_FRAMES
	# A second request for the piece already playing is continued rather than
	# restarted, so returning to the shelf does not start the tune over.
	_audio.play_record(record, &"music", _audio_assets())


func _stop_music() -> void:
	if _audio == null:
		return
	_audio.stop_all()


## The loop. The piece carries its own `loopchannel 0`, so the driver repeats it
## without help; this only covers the case of it running out, which is what a
## cache holding a piece with no loop would do.
func _hold_music() -> void:
	if _audio == null:
		return
	_loop_countdown -= 1
	if _loop_countdown > 0:
		return
	_loop_countdown = LOOP_CHECK_FRAMES
	if not bool(_audio.audio_status().get("music_active", false)):
		_start_music()


## The two blobs [Gen2SoundEngine] reads outside a record, the same pair the
## opening's own screen passes.
func _audio_assets() -> Dictionary:
	return {
		"wave_samples": _data.world_audio_asset(&"wave_samples"),
		"drumkits": _data.world_audio_asset(&"drumkits"),
	}


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
