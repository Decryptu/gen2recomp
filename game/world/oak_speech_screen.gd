class_name Gen2OakSpeechScreen
extends Control

## `OakSpeech` drawn: a pic above the standard text box, advanced with A, with
## the naming screen embedded where `NamePlayer` sits.
##
## Oak and the speech species use the ordinary imported pic tables. Gold and
## Silver use CAL's trainer pic for the player; Crystal uses the imported raw
## ChrisPic or KrisPic. The source preset-name menu is embedded before the
## keyboard, and this screen owns OakSpeech's music and cry.

## Carries the name the intro settled on, already through `InitName`'s default.
signal finished(player_name: String)

## `Intro_PrepTrainerPic` and `PrepMonFrontpic` both place at `hlcoord 6, 4`.
const PIC_AT: Vector2i = Vector2i(6, 4)
const PIC_TILES: int = 7
const TILE: int = Gen2Font.TILE

var _data: GameData = null
var _beats: Array = []
var _index: int = 0
var _gender: int = Gen2SaveData.GENDER_MALE
var _player_name: String = ""

var _background: ColorRect = null
var _pic: TextureRect = null
var _text_box: Gen2TextBox = null
var _naming: Gen2NamingScreenScreen = null
var _name_menu: Gen2PlayerNameMenuScreen = null
var _audio: Gen2AudioPlayer = null
var _audio_started: bool = false
var _presentation := Gen2IntroPresentation.new()
var _presentation_accumulator: float = 0.0


## Answers false when the cache carries no intro text, which the caller reports
## rather than running a speech with nothing in it.
func open(data: GameData, gender: int) -> bool:
	_data = data
	_gender = gender
	_beats = Gen2OakSpeech.beats(data)
	_index = 0
	if _beats.is_empty():
		return false
	if is_inside_tree():
		_start_audio()
		_show_beat()
	return true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	# `ClearTilemap` leaves the whole screen blank, which is white here the way
	# every other 1bpp page in this project is.
	_background = ColorRect.new()
	_background.color = Color.WHITE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	add_child(_background)

	_audio = Gen2AudioPlayer.new()
	add_child(_audio)

	_pic = TextureRect.new()
	_pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pic)

	_text_box = Gen2TextBox.new()
	_text_box.font = Gen2Font.from_data(_data)
	_text_box.frame_style = Gen2OptionsStore.current().textbox_frame
	_text_box.position = Vector2(0, Gen2TextBox.STANDARD_TOP * TILE)
	add_child(_text_box)

	if not _beats.is_empty():
		_start_audio()
	if _name_menu != null:
		_show_name_choices()
	elif not _beats.is_empty():
		_show_beat()


func _process(delta: float) -> void:
	if _name_menu == null or _pic == null or _presentation.finished():
		return
	_presentation_accumulator += delta * Gen2IntroPresentation.FRAME_RATE
	while _presentation_accumulator >= 1.0 and not _presentation.finished():
		_presentation_accumulator -= 1.0
		_presentation.advance_frame()
		_pic.position.x = _presentation.position()


## Which beat is showing, zero-based, for a driver that wants to step to one.
func beat_index() -> int:
	return _index


func beat_count() -> int:
	return _beats.size()


## True while the naming screen is up, which is the one point in the speech that
## does not answer A by advancing.
func naming() -> bool:
	return _naming != null


func choosing_name() -> bool:
	return _name_menu != null


func name_choice_image() -> Image:
	return _name_menu.image() if _name_menu != null else null


## The name the intro has settled on so far, empty until the naming screen
## closes.
func player_name() -> String:
	return _player_name


## A advances, the way every `PrintText` in the routine waits for one. While the
## naming screen is up it owns every button instead.
func handle_button(button: int) -> bool:
	if _name_menu != null:
		return _name_menu.handle_button(button)
	if _naming != null:
		return _naming.handle_button(button)
	if button != Gen2Button.A:
		return false
	advance()
	return true


## One page forward, then one beat forward once the text has run out, then into
## the naming screen where `NamePlayer` sits, or out. A plain method as well as
## a key handler, so the speech can be photographed partway through.
func advance() -> void:
	if _naming != null or _name_menu != null or _index >= _beats.size():
		return
	# Every beat here is one `PrintText`, which waits at each page and again at
	# the end, so the beat only moves on once the box has nothing left.
	if _text_box != null and _text_box.advance():
		return
	var key: String = String(_beats[_index].get("key", ""))
	if key == "oak_2":
		_play_intro_cry()
	if key == Gen2OakSpeech.NAME_AFTER:
		_open_name_menu()
		return
	_index += 1
	if _index >= _beats.size():
		finished.emit(_player_name)
		return
	_show_beat()


func _open_name_menu() -> void:
	_name_menu = Gen2PlayerNameMenuScreen.new()
	if not _name_menu.open(_data, _gender):
		_name_menu.free()
		_name_menu = null
		_open_naming()
		return
	_name_menu.closed.connect(_on_name_choice)
	add_child(_name_menu)
	# MovePlayerPicRight runs eight frames and leaves the 7x7 pic at (13,4)
	# while MENU_BACKUP_TILES draws the name menu over the left side.
	_show_name_choices()


func _on_name_choice(name: String) -> void:
	_name_menu.queue_free()
	_name_menu = null
	if name == "":
		_hide_speech(true)
		_open_naming()
		return
	_player_name = name
	_resume_after_name()


func _open_naming() -> void:
	_naming = Gen2NamingScreenScreen.new()
	if not _naming.open(_data, Gen2OakSpeech.NAME_PROMPT):
		# Never parented, so it is freed outright rather than queued.
		_naming.free()
		_naming = null
		_index += 1
		_show_beat()
		return
	_naming.closed.connect(_on_named)
	add_child(_naming)
	_hide_speech(true)


func _on_named(entered: String) -> void:
	_player_name = Gen2OakSpeech.resolve_name(entered, _gender)
	_naming.queue_free()
	_naming = null
	_resume_after_name()


func _resume_after_name() -> void:
	if _pic != null:
		_pic.position.x = PIC_AT.x * TILE
	_hide_speech(false)
	_index += 1
	if _index >= _beats.size():
		finished.emit(_player_name)
		return
	_show_beat()


func _hide_speech(hidden: bool) -> void:
	for node: CanvasItem in [_background, _pic, _text_box]:
		if node != null:
			node.visible = not hidden


func _show_name_choices() -> void:
	if _pic != null:
		if _pic.texture == null:
			_show_pic(Gen2OakSpeech.Pic.PLAYER)
		_presentation.start_slide(PIC_AT.x * TILE, 13 * TILE)
		_presentation_accumulator = 0.0
		_pic.position.x = _presentation.position()
		_pic.visible = true
	if _background != null:
		_background.visible = true
	if _text_box != null:
		_text_box.visible = false


func _show_beat() -> void:
	if _text_box == null or _index >= _beats.size():
		return
	var beat: Dictionary = _beats[_index]
	_text_box.show_text(Gen2OakSpeech.with_player_name(
		String(beat["text"]), _player_name
	))
	_show_pic(int(beat["pic"]))


## `Intro_PrepTrainerPic` and `PrepMonFrontpic` both fill a seven-tile box at
## (6,4). A pic smaller than the box is padded by `PadFrontpic`
## (`engine/gfx/load_pics.asm`), not centred: it lays one blank tile column
## before the pic, blank rows above it, and for a 5x5 one blank column after, so
## the pic ends up bottom-aligned one column in.
func _show_pic(kind: int) -> void:
	if _pic == null:
		return
	_pic.texture = null
	if _data == null:
		return
	var image: Image = null
	var mirrored: bool = false
	match kind:
		Gen2OakSpeech.Pic.OAK:
			image = _trainer_image(Gen2OakSpeech.POKEMON_PROF)
		Gen2OakSpeech.Pic.MON:
			# `PrepMonFrontpic` sets wBoxAlignment before `PlaceGraphic`, and
			# `Intro_PrepTrainerPic` does not, so only this beat is mirrored.
			mirrored = true
			image = Gen2PicImage.x_flipped(
				_species_image(Gen2OakSpeech.intro_species(_data))
			)
		Gen2OakSpeech.Pic.PLAYER:
			image = _player_image()
	if image == null:
		return
	_pic.texture = ImageTexture.create_from_image(image)
	_pic.size = Vector2(image.get_size())
	_pic.position = Vector2(PIC_AT * TILE) + Vector2(
		_pad_columns(image.get_width() / TILE, mirrored) * TILE,
		PIC_TILES * TILE - image.get_height()
	)


## Blank tile columns `PadFrontpic` leaves to the left of a pic in the 7x7 box.
##
## A full-width pic is padded on neither side. A narrower one takes one blank
## column at the left, so `.right`'s column reversal leaves `PIC_TILES - 1 -
## width` of the trailing blank on that side instead.
static func _pad_columns(width: int, mirrored: bool) -> int:
	if width >= PIC_TILES or width <= 0:
		return 0
	return PIC_TILES - 1 - width if mirrored else 1


func _trainer_image(trainer_class: int) -> Image:
	var pic: Dictionary = _data.trainer_pic(trainer_class)
	if pic.is_empty():
		return null
	return Gen2PicImage.from_atlas(
		_data.atlas_indices(pic["atlas"]), _data.atlas(pic["atlas"]), pic,
		_data.trainer_palette(trainer_class)
	)


func _species_image(species: int) -> Image:
	var pic: Dictionary = _data.species_pic(species)
	if pic.is_empty():
		return null
	return Gen2PicImage.from_atlas(
		_data.atlas_indices(pic["atlas"]), _data.atlas(pic["atlas"]), pic,
		_data.palette(species)
	)


func _player_image() -> Image:
	if not Gen2WorldState.is_crystal_profile(_data):
		# pokegold NamePlayer and ShrinkPlayer use trainer class CAL.
		return _trainer_image(0x0C)
	var sheet: String = (
		"intro_player_female"
		if _gender == Gen2SaveData.GENDER_FEMALE else "intro_player_male"
	)
	var strip: PackedByteArray = _data.tile_indices(sheet)
	var tiles: int = RomLayout.INTRO_PLAYER_PIC_TILES
	var tile: int = Gen2Font.TILE
	if strip.size() < tiles * tile * tile:
		return null
	var width: int = RomLayout.INTRO_PLAYER_PIC_COLUMNS * tile
	var indices := PackedByteArray()
	indices.resize(width * RomLayout.INTRO_PLAYER_PIC_ROWS * tile)
	var strip_width: int = tiles * tile
	for row: int in RomLayout.INTRO_PLAYER_PIC_ROWS:
		for column: int in RomLayout.INTRO_PLAYER_PIC_COLUMNS:
			var source_tile: int = row * RomLayout.INTRO_PLAYER_PIC_COLUMNS + column
			for y: int in tile:
				for x: int in tile:
					indices[(row * tile + y) * width + column * tile + x] = \
						strip[y * strip_width + source_tile * tile + x]
	return Gen2PicImage.from_indices(indices, width, width, _data.card_palette(
		1 if _gender == Gen2SaveData.GENDER_FEMALE else 0
	))


func _start_audio() -> void:
	if _audio_started or _audio == null or _data == null:
		return
	_audio_started = true
	_audio.play_record(
		_data.world_audio(&"music", Gen2OakSpeech.MUSIC_ROUTE_30), &"music",
		_audio_assets()
	)


func _play_intro_cry() -> void:
	if _audio == null or _data == null:
		return
	_audio.play_record(
		_data.species_cry(Gen2OakSpeech.intro_species(_data)), &"cry", _audio_assets()
	)


func _audio_assets() -> Dictionary:
	return {
		"wave_samples": _data.world_audio_asset(&"wave_samples"),
		"drumkits": _data.world_audio_asset(&"drumkits"),
	}
