class_name Gen2OakSpeechScreen
extends Control

## `OakSpeech` drawn: a pic above the standard text box, advanced with A, with
## the naming screen embedded where `NamePlayer` sits.
##
## The pics are the ones the cartridge already gives this project: Oak is
## trainer class POKEMON_PROF out of the same table every class pic comes from,
## and Wooper is a species front pic. `DrawIntroPlayerPic`'s ChrisPic and
## KrisPic are not imported, so the two beats either side of the naming screen
## draw their text and no picture; the Hall of Fame's player panel has the same
## gap for the same reason.
##
## Boundaries kept out on purpose, all presentation: the three palette
## rotations, `Intro_WipeInFrontpic`, `MovePlayerPicRight`/`Left`, Wooper's cry
## on `_OakText2`, and `ShowPlayerNamingChoices`' preset-name menu, which is a
## cartridge table this project does not import.

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
		_show_beat()


## Which beat is showing, zero-based, for a driver that wants to step to one.
func beat_index() -> int:
	return _index


func beat_count() -> int:
	return _beats.size()


## True while the naming screen is up, which is the one point in the speech that
## does not answer A by advancing.
func naming() -> bool:
	return _naming != null


## The name the intro has settled on so far, empty until the naming screen
## closes.
func player_name() -> String:
	return _player_name


## A advances, the way every `PrintText` in the routine waits for one. While the
## naming screen is up it owns every button instead.
func handle_button(button: int) -> bool:
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
	if _naming != null or _index >= _beats.size():
		return
	# Every beat here is one `PrintText`, which waits at each page and again at
	# the end, so the beat only moves on once the box has nothing left.
	if _text_box != null and _text_box.advance():
		return
	var key: String = String(_beats[_index].get("key", ""))
	if key == Gen2OakSpeech.NAME_AFTER:
		_open_naming()
		return
	_index += 1
	if _index >= _beats.size():
		finished.emit(_player_name)
		return
	_show_beat()


func _open_naming() -> void:
	_naming = Gen2NamingScreenScreen.new()
	if not _naming.open(_data, Gen2OakSpeech.NAME_PROMPT):
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


func _show_beat() -> void:
	if _text_box == null or _index >= _beats.size():
		return
	var beat: Dictionary = _beats[_index]
	_text_box.show_text(Gen2OakSpeech.with_player_name(
		String(beat["text"]), _player_name
	))
	_show_pic(int(beat["pic"]))


## `Intro_PrepTrainerPic` and `PrepMonFrontpic` both centre a seven-tile cell on
## (6,4); a pic smaller than the cell sits at its bottom, the way
## `_PrepMonFrontpic` places one.
func _show_pic(kind: int) -> void:
	if _pic == null:
		return
	_pic.texture = null
	if _data == null:
		return
	var image: Image = null
	match kind:
		Gen2OakSpeech.Pic.OAK:
			image = _trainer_image(Gen2OakSpeech.POKEMON_PROF)
		Gen2OakSpeech.Pic.WOOPER:
			image = _species_image(Gen2OakSpeech.WOOPER)
	if image == null:
		return
	_pic.texture = ImageTexture.create_from_image(image)
	_pic.size = Vector2(image.get_size())
	var cell: int = PIC_TILES * TILE
	_pic.position = Vector2(
		PIC_AT.x * TILE + (cell - image.get_width()) / 2.0,
		PIC_AT.y * TILE + cell - image.get_height()
	)


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
