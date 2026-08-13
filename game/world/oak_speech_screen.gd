class_name Gen2OakSpeechScreen
extends Control

## `OakSpeech` drawn: a pic above the standard text box, advanced with A, with
## `NamePlayer`'s menu and keyboard where the source puts them.
##
## The routine is a run of `PrintText` calls separated by palette fades and
## `ClearTilemap`, so this screen is a run of beats separated by
## [Gen2IntroPresentation] queues. Nothing here waits a number of frames it
## chose: every count is a `DelayFrames` operand, and a fade is the source's own
## palette-byte remap applied to each palette on screen.
##
## Oak and the speech species use the ordinary imported pic tables. Gold and
## Silver use CAL's trainer pic for the player; Crystal uses the imported raw
## ChrisPic or KrisPic.

## Carries the name the intro settled on, already through `InitName`'s default.
signal finished(player_name: String)

## `Intro_PrepTrainerPic` and `PrepMonFrontpic` both place at `hlcoord 6, 4`.
const PIC_AT: Vector2i = Vector2i(6, 4)
const PIC_TILES: int = 7
const TILE: int = Gen2Font.TILE

## Where the screen is standing, which is the routine it is inside.
enum Phase {
	## Inside a queued run of `DelayFrames`: no button does anything.
	ANIMATING,
	## At a `PrintText`, which is the only place A advances.
	TEXT,
	## `ShowPlayerNamingChoices`, then `NamingScreen` on its NEW NAME row.
	NAME_MENU,
	NAMING,
	DONE,
}

var _data: GameData = null
var _beats: Array = []
var _index: int = 0
var _gender: int = Gen2SaveData.GENDER_MALE
var _player_name: String = ""
var _phase: int = Phase.ANIMATING

var _background: ColorRect = null
var _pic: TextureRect = null
var _pic_palette: PackedColorArray = PackedColorArray()
## `Palette_TextBG7`, the palette a `TextboxPalette` region is drawn through, so
## a fade over a text box passes through its two middle colours. Gold and Silver
## ship none and fall back to the black-on-white every 1bpp page here uses.
var _text_palette: PackedColorArray = PackedColorArray()
## The picture as indices and size, kept so a fade recolours rather than redraws.
var _pic_cell: Dictionary = {}
var _pic_pad_columns: int = 0
var _text_box: Gen2TextBox = null
var _naming: Gen2NamingScreenScreen = null
var _name_menu: Gen2PlayerNameMenuScreen = null
var _audio: Gen2AudioPlayer = null
var _audio_started: bool = false
var _cry_played: bool = false
var _presentation := Gen2IntroPresentation.new()
var _accumulator: float = 0.0
## What to run when the queue empties, which is where the routine resumes.
var _after: Callable = Callable()


## Answers false when the cache carries no intro text, which the caller reports
## rather than running a speech with nothing in it.
func open(data: GameData, gender: int) -> bool:
	_data = data
	_gender = gender
	_beats = Gen2OakSpeech.beats(data)
	_index = 0
	if _beats.is_empty():
		return false
	_text_palette = data.text_bg_palette()
	if _text_palette.size() != 4:
		_text_palette = Gen2Palette.pic_palette(
			PackedColorArray([Color.WHITE, Color.BLACK])
		)
	if is_inside_tree():
		_begin()
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
	# `ClearTilemap` runs before the first pic is even loaded, so the speech
	# opens on a blank screen and not on an empty box.
	_text_box.visible = false
	add_child(_text_box)

	if not _beats.is_empty():
		_begin()


func _process(delta: float) -> void:
	_accumulator += delta * Gen2IntroPresentation.FRAME_RATE
	var frames: int = int(_accumulator)
	_accumulator -= float(frames)
	advance_frames(frames)


## Runs [param count] source frames of whatever the screen is standing in.
## Public so a test or a preview tool can spend the cartridge's own
## `DelayFrames` without a clock; [method _process] is the only other caller.
func advance_frames(count: int) -> void:
	for _frame: int in count:
		if _phase != Phase.ANIMATING:
			# The cry sits inside `OakText2`'s own `text_asm`, so it fires when
			# the words have finished appearing rather than when A is pressed.
			_play_cry_if_due()
			return
		_presentation.advance_frame()
		_apply_frame()
		# The last VBlank of a `DelayFrames` run is the frame the routine
		# returns on, so no frame is spent at a call boundary.
		if _presentation.finished():
			_finish_queue()


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


## How many source frames the queued animation still owes, zero at a `PrintText`.
func animation_frames_left() -> int:
	return _presentation.remaining_frames() if _phase == Phase.ANIMATING else 0


## The name the intro has settled on so far, empty until the naming screen
## closes.
func player_name() -> String:
	return _player_name


## A advances, the way every `PrintText` in the routine waits for one. A button
## pressed inside a `DelayFrames` run is swallowed, which is what the hardware
## does with a joypad nobody is reading.
func handle_button(button: int) -> bool:
	if _phase == Phase.ANIMATING:
		return true
	if _name_menu != null:
		return _name_menu.handle_button(button)
	if _naming != null:
		return _naming.handle_button(button)
	if button != Gen2Button.A:
		return false
	advance()
	return true


## One page forward, then one beat forward once the text has run out. A plain
## method as well as a key handler, so the speech can be photographed partway.
func advance() -> void:
	if _phase != Phase.TEXT or _index >= _beats.size():
		return
	# Every beat here is one `PrintText`, which waits at each page and again at
	# the end, so the beat only moves on once the box has nothing left.
	if _text_box != null and _text_box.advance():
		return
	if String(_beats[_index].get("key", "")) == Gen2OakSpeech.NAME_AFTER:
		_open_name_menu()
		return
	# `RotateThreePalettesRight` then `ClearTilemap` after the beats that load a
	# new picture; the beats that keep the one before them run straight on.
	if bool(_beats[_index].get("clears_after", false)):
		_presentation.push_rotate_three_right()
		_queue(_enter_next_beat)
		return
	_enter_next_beat()


## The whole opening of `OakSpeech`: out to black, the music, back in, and out
## to white before the first picture is loaded.
func _begin() -> void:
	_presentation.clear()
	_presentation.push_rotate_four_left()
	_queue(_after_first_fade)


func _after_first_fade() -> void:
	_start_audio()
	_presentation.push_rotate_four_right()
	_presentation.push_rotate_three_right()
	_queue(_show_beat)


func _queue(after: Callable) -> void:
	_after = after
	_phase = Phase.ANIMATING
	_accumulator = 0.0
	_apply_frame()


func _finish_queue() -> void:
	_presentation.clear()
	_phase = Phase.TEXT
	var next: Callable = _after
	_after = Callable()
	if next.is_valid():
		next.call()


## Writes the frame's palette byte and pic column onto what is drawn. Every BG
## palette on screen goes through the same byte, which is what a hardware fade
## does to a screen carrying more than one palette.
func _apply_frame() -> void:
	var bgp: int = _presentation.bgp()
	var text_colors: PackedColorArray = Gen2IntroPresentation.apply_bgp(_text_palette, bgp)
	if _background != null:
		_background.color = text_colors[0]
	if _text_box != null:
		_text_box.palette = text_colors
	if _name_menu != null:
		_name_menu.palette = text_colors
	if _naming != null:
		_naming.palette = text_colors
	if _pic != null and _pic.texture != null and _pic_palette.size() == 4:
		_redraw_pic(Gen2IntroPresentation.apply_bgp(_pic_palette, bgp))
	if _pic != null:
		_pic.position.x = float(
			(_presentation.column() + _pic_pad_columns) * TILE
		)


func _enter_next_beat() -> void:
	_index += 1
	if _index >= _beats.size():
		_phase = Phase.DONE
		finished.emit(_player_name)
		return
	_show_beat()


## Loads the beat's picture, then runs whichever transition brings it in before
## the text is printed over it.
func _show_beat() -> void:
	if _text_box == null or _index >= _beats.size():
		return
	var beat: Dictionary = _beats[_index]
	_cry_played = false
	_show_pic(int(beat["pic"]))
	match int(beat.get("enter", Gen2OakSpeech.Enter.NONE)):
		Gen2OakSpeech.Enter.FRONTPIC:
			_presentation.push_rotate_left_frontpic()
		Gen2OakSpeech.Enter.WIPE:
			_presentation.push_wipe_in_frontpic()
	if _presentation.finished():
		_print_text()
		return
	# `ClearTilemap` left the screen blank, so there is no box until `PrintText`
	# draws one after the transition.
	_text_box.visible = false
	_queue(_print_text)


func _print_text() -> void:
	if _text_box == null or _index >= _beats.size():
		return
	_text_box.visible = true
	_text_box.show_text(Gen2OakSpeech.with_player_name(
		String(_beats[_index]["text"]), _player_name
	))
	_phase = Phase.TEXT
	_apply_frame()


## `OakText2`'s `text_asm` plays the cry once the words are up. The source's
## `WaitSFX` after it is not modelled; see `HANDOFF.md`.
func _play_cry_if_due() -> void:
	if _cry_played or _index >= _beats.size() or _text_box == null:
		return
	if String(_beats[_index].get("key", "")) != "oak_2" or _text_box.is_revealing():
		return
	_cry_played = true
	_play_intro_cry()


## `NamePlayer`: the pic slides to the right, then the preset menu opens over
## where it was.
func _open_name_menu() -> void:
	_presentation.push_move_player_pic(true)
	_queue(_show_name_choices)


func _show_name_choices() -> void:
	_name_menu = Gen2PlayerNameMenuScreen.new()
	if not _name_menu.open(_data, _gender):
		_name_menu.free()
		_name_menu = null
		_open_naming()
		return
	_name_menu.closed.connect(_on_name_choice)
	add_child(_name_menu)
	if _text_box != null:
		_text_box.visible = false
	_phase = Phase.NAME_MENU


func _on_name_choice(chosen: String) -> void:
	_name_menu.queue_free()
	_name_menu = null
	if chosen == "":
		_open_naming()
		return
	_player_name = chosen
	if _text_box != null:
		_text_box.visible = true
	# `StorePlayerName`, `ApplyMonOrTrainerPals`, then the pic walks back.
	_presentation.push_move_player_pic(false)
	_queue(_enter_next_beat)


func _open_naming() -> void:
	_naming = Gen2NamingScreenScreen.new()
	if not _naming.open(_data, Gen2OakSpeech.NAME_PROMPT):
		# Never parented, so it is freed outright rather than queued.
		_naming.free()
		_naming = null
		_enter_next_beat()
		return
	_naming.closed.connect(_on_named)
	add_child(_naming)
	_hide_speech(true)
	_phase = Phase.NAMING


## `.NewName`'s tail: out to white, the screen cleared, the player pic drawn
## again at (6,4), `WaitBGMap`'s four frames, and back in from white.
func _on_named(entered: String) -> void:
	_player_name = Gen2OakSpeech.resolve_name(entered, _gender)
	_presentation.push_rotate_three_right()
	_queue(_after_naming_fade)


func _after_naming_fade() -> void:
	_naming.queue_free()
	_naming = null
	_hide_speech(false)
	if _text_box != null:
		_text_box.visible = false
	_show_pic(Gen2OakSpeech.Pic.PLAYER)
	_presentation.push_delay(Gen2IntroPresentation.WAIT_BG_MAP_FRAMES)
	_presentation.push_rotate_three_left()
	_queue(_resume_after_name)


func _resume_after_name() -> void:
	if _text_box != null:
		_text_box.visible = true
	_enter_next_beat()


func _hide_speech(hidden: bool) -> void:
	for node: CanvasItem in [_background, _pic, _text_box]:
		if node != null:
			node.visible = not hidden


## `Intro_PrepTrainerPic` and `PrepMonFrontpic` both fill a seven-tile box at
## (6,4). A pic smaller than the box is padded by `PadFrontpic`
## (`engine/gfx/load_pics.asm`), not centred: it lays one blank tile column
## before the pic, blank rows above it, and for a 5x5 one blank column after, so
## the pic ends up bottom-aligned one column in.
func _show_pic(kind: int) -> void:
	if _pic == null:
		return
	_pic.texture = null
	_pic_palette = PackedColorArray()
	_pic_cell = {}
	if _data == null:
		return
	var cell: Dictionary = {}
	var palette: PackedColorArray = PackedColorArray()
	var mirrored: bool = false
	match kind:
		Gen2OakSpeech.Pic.OAK:
			palette = _data.trainer_palette(Gen2OakSpeech.POKEMON_PROF)
			cell = _trainer_cell(Gen2OakSpeech.POKEMON_PROF)
		Gen2OakSpeech.Pic.MON:
			# `PrepMonFrontpic` sets wBoxAlignment before `PlaceGraphic`, and
			# `Intro_PrepTrainerPic` does not, so only this beat is mirrored.
			mirrored = true
			var species: int = Gen2OakSpeech.intro_species(_data)
			palette = _data.palette(species)
			cell = _species_cell(species)
			if not cell.is_empty():
				cell["indices"] = Gen2PicImage.x_flipped_indices(
					cell["indices"], int(cell["width"])
				)
		Gen2OakSpeech.Pic.PLAYER:
			palette = _player_palette()
			cell = _player_cell()
	if cell.is_empty():
		return
	_pic_cell = cell
	_pic_palette = palette
	_pic_pad_columns = _pad_columns(int(cell["width"]) / TILE, mirrored)
	_pic.size = Vector2(float(cell["width"]), float(cell["height"]))
	_pic.position = Vector2(
		float((PIC_AT.x + _pic_pad_columns) * TILE),
		float(PIC_AT.y * TILE + PIC_TILES * TILE - int(cell["height"]))
	)
	_redraw_pic(Gen2IntroPresentation.apply_bgp(palette, _presentation.bgp()))


## Redraws the picture through [param colors]. The indices are kept, so a fade
## step costs a palette swap rather than another crop of the atlas.
func _redraw_pic(colors: PackedColorArray) -> void:
	if _pic_cell.is_empty():
		return
	_pic.texture = ImageTexture.create_from_image(Gen2PicImage.from_indices(
		_pic_cell["indices"], int(_pic_cell["width"]), int(_pic_cell["height"]), colors
	))


## Blank tile columns `PadFrontpic` leaves to the left of a pic in the 7x7 box.
##
## A full-width pic is padded on neither side. A narrower one takes one blank
## column at the left, so `.right`'s column reversal leaves `PIC_TILES - 1 -
## width` of the trailing blank on that side instead.
static func _pad_columns(width: int, mirrored: bool) -> int:
	if width >= PIC_TILES or width <= 0:
		return 0
	return PIC_TILES - 1 - width if mirrored else 1


func _trainer_cell(trainer_class: int) -> Dictionary:
	var pic: Dictionary = _data.trainer_pic(trainer_class)
	if pic.is_empty():
		return {}
	return Gen2PicImage.atlas_cell(
		_data.atlas_indices(pic["atlas"]), _data.atlas(pic["atlas"]), pic
	)


func _species_cell(species: int) -> Dictionary:
	var pic: Dictionary = _data.species_pic(species)
	if pic.is_empty():
		return {}
	return Gen2PicImage.atlas_cell(
		_data.atlas_indices(pic["atlas"]), _data.atlas(pic["atlas"]), pic
	)


func _player_palette() -> PackedColorArray:
	if not Gen2WorldState.is_crystal_profile(_data):
		return _data.trainer_palette(Gen2OakSpeech.CAL)
	return _data.card_palette(1 if _gender == Gen2SaveData.GENDER_FEMALE else 0)


func _player_cell() -> Dictionary:
	if not Gen2WorldState.is_crystal_profile(_data):
		# pokegold NamePlayer and ShrinkPlayer use trainer class CAL.
		return _trainer_cell(Gen2OakSpeech.CAL)
	var sheet: String = (
		"intro_player_female"
		if _gender == Gen2SaveData.GENDER_FEMALE else "intro_player_male"
	)
	var strip: PackedByteArray = _data.tile_indices(sheet)
	var tiles: int = RomLayout.INTRO_PLAYER_PIC_TILES
	var tile: int = Gen2Font.TILE
	if strip.size() < tiles * tile * tile:
		return {}
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
	return {"indices": indices, "width": width, "height": width}


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
