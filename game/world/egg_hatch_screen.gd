class_name Gen2EggHatchScreen
extends Control

## `HatchEggs` and the `EggHatch_AnimationSequence` its `.Text_HatchEgg` runs,
## for one party egg at a time.
##
## Presentation only: [method Gen2WorldPartyHost.hatch_egg] has already written
## the party row, which is the source's own order, so the picture the sequence
## ends on is the Pokemon the row now holds. What this screen owns after that is
## the nickname: [signal named] carries the answer and the caller writes it.
##
## `Hatch_InitShellFragments`' ten shell pieces are sprite-anim objects and this
## project has no sprite-anim layer outside the intro, the same reason
## `.PlayEvolvedSFX`'s balls of light are absent from [Gen2EvolutionScreen].
## Their 130 frames are spent with the hatchling standing.

## The nickname the player settled on for the hatched party slot.
signal named(party_index: int, nickname: String)
signal closed()
signal cry_requested(species: int)
signal sfx_requested(index: int)
signal music_requested(index: int)

## constants/music_constants.asm.
const MUSIC_NONE: int = 0
const MUSIC_EVOLUTION: int = 0x22
## constants/sfx_constants.asm.
const SFX_CAUGHT_MON: int = 0x02
const SFX_EGG_CRACK: int = 0x9E
const SFX_EGG_HATCH: int = 0xA6

const TILE: int = Gen2Font.TILE
const BOX: int = Gen2PicImage.FRONTPIC_TILES
## `hlcoord 7, 4` for the egg and `hlcoord 6, 3` for the hatchling. The egg is
## five tiles square and sits in the middle of the block the hatchling fills.
const EGG_AT: Vector2i = Vector2i(7, 4)
const HATCHLING_AT: Vector2i = Vector2i(6, 3)

## `ld c, 80` between `MUSIC_EVOLUTION` and the wobble.
const OPENING_FRAMES: int = 80
## `.outerloop` runs while the counter before the `inc` is under 8, so its
## passes are e = 1 to 8.
const WOBBLE_PASSES: int = 8
## Each half of a wobble is `EggHatch_DoAnimFrame`'s own `DelayFrame` plus
## `ld c, 2`, and a wobble is both halves.
const WOBBLE_HALF_FRAMES: int = 3
## `ld c, 16` at the end of every pass.
const PASS_TAIL_FRAMES: int = 16
## `hSCX` is written 2 and then -2, which scrolls the background the other way.
const WOBBLE_SHIFT: int = 2
## `Hatch_InitShellFragments`' own closing `EggHatch_DoAnimFrame` and
## `Hatch_ShellFragmentLoop`'s `ld c, 129`.
const FRAGMENT_FRAMES: int = 1 + 129

enum Phase {
	HUH,
	OPENING,
	WOBBLE,
	FRAGMENTS,
	ANIMATE,
	HATCHED,
	ASK_NICKNAME,
	NAMING,
	DONE,
}

var _data: GameData = null
## [method Gen2WorldPartyHost.hatch_egg]'s summaries, in party order.
var _hatches: Array = []
var _index: int = 0
var _phase: int = Phase.DONE
var _frames: int = 0
## `wFrameCounter`, and where the current pass stands inside its own wobble.
var _counter: int = 0
var _halves_left: int = 0
var _half_frames: int = 0
var _shift: int = 0
## Which block the picture is standing in, so the wobble can move it without
## knowing whether it is drawing the egg or the hatchling.
var _pic_origin: Vector2i = EGG_AT
var _nickname_yes: bool = true
var _animation: Gen2PicAnimation = null
var _animation_pixels: PackedByteArray = PackedByteArray()

var _backdrop: ColorRect = null
var _pic: TextureRect = null
var _text_box: Gen2TextBox = null
var _menu_page: Gen2MenuPage = null
var _menu: TextureRect = null
var _naming: Gen2NamingScreenScreen = null


## [param hatches] is one [method Gen2WorldPartyHost.hatch_egg] summary per egg,
## in the order `HatchEggs` walks the party. An empty list closes at once.
func set_context(data: GameData, hatches: Array) -> void:
	_data = data
	_hatches = hatches.duplicate(true)
	_index = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	if _data == null or _hatches.is_empty():
		closed.emit()
		return
	_build()
	_begin_hatch()


func remaining() -> int:
	return maxi(_hatches.size() - _index, 0)


func current_hatch() -> Dictionary:
	if _index < 0 or _index >= _hatches.size():
		return {}
	return _hatches[_index]


func phase() -> int:
	return _phase


## Whether the sequence is standing on a press rather than on a count:
## `Text_BreedHuh`'s `para`, `_BreedEggHatchText`'s `text_promptbutton` and the
## `YesNoBox` after it.
func awaiting_press() -> bool:
	if _phase in [Phase.ASK_NICKNAME, Phase.NAMING]:
		return true
	if _text_box == null or not _text_box.visible:
		return false
	return _text_box.has_pages_left() or _phase == Phase.HATCHED


func text_lines() -> PackedStringArray:
	if _text_box == null or not _text_box.visible:
		return PackedStringArray()
	return _text_box.text_lines()


## The YES/NO cursor, so a driver can read it without a redraw. -1 when the box
## is not up.
func nickname_cursor() -> int:
	return (0 if _nickname_yes else 1) if _phase == Phase.ASK_NICKNAME else -1


func naming_screen() -> Gen2NamingScreenScreen:
	return _naming


func handle_button(button: int) -> bool:
	if _phase == Phase.NAMING and _naming != null:
		return _naming.handle_button(button)
	if _phase == Phase.ASK_NICKNAME:
		match button:
			Gen2Button.UP, Gen2Button.DOWN:
				_nickname_yes = not _nickname_yes
				_draw_yes_no()
				return true
			Gen2Button.A:
				_answer_nickname(_nickname_yes)
				return true
			Gen2Button.B:
				## `YesNoBox` answers B as NO, which is `.nonickname`.
				_answer_nickname(false)
				return true
		return false
	if button == Gen2Button.A and _text_box != null and _text_box.visible \
		and (_text_box.is_revealing() or _text_box.has_pages_left()):
		_text_box.advance()
		return true
	if button == Gen2Button.A and _phase == Phase.HATCHED:
		_open_nickname_question()
		return true
	return false


func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color.WHITE
	_backdrop.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.visible = false
	add_child(_backdrop)

	_pic = TextureRect.new()
	_pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pic.visible = false
	add_child(_pic)

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


## `Text_BreedHuh`, printed over the map before anything is cleared.
func _begin_hatch() -> void:
	if current_hatch().is_empty():
		_phase = Phase.DONE
		closed.emit()
		return
	_backdrop.visible = false
	_pic.visible = false
	_menu.visible = false
	_phase = Phase.HUH
	_show_text(Gen2WorldPartyHost.HUH_TEXT)


func _show_text(text: String, prompt: bool = false) -> void:
	if _text_box == null:
		return
	_text_box.visible = true
	_text_box.show_text(text, prompt)


func advance_frame() -> void:
	if _phase == Phase.DONE or _data == null:
		return
	if _phase == Phase.NAMING:
		return
	if _text_box != null and _text_box.visible:
		_text_box.advance_frame()
		if _text_box.is_revealing() or _text_box.has_pages_left():
			return
	match _phase:
		Phase.HUH:
			## Reached on the frame the empty `para` page has been pressed past,
			## since a page with another behind it is what `awaiting_press`
			## answers and the funnel presses it.
			_open_sequence()
		Phase.OPENING:
			if _spend():
				_begin_wobble()
		Phase.WOBBLE:
			_advance_wobble()
		Phase.FRAGMENTS:
			if _spend():
				_open_frontpic_animation()
		Phase.ANIMATE:
			_advance_frontpic_animation()


func _spend() -> bool:
	_frames -= 1
	return _frames <= 0


## `EggHatch_AnimationSequence` up to its `ld c, 80`: the music stops, the
## screen is blanked and the egg is placed, and the evolution track starts
## before the wait rather than after it.
func _open_sequence() -> void:
	_text_box.visible = false
	_backdrop.visible = true
	_pic.visible = true
	_shift = 0
	music_requested.emit(MUSIC_NONE)
	_draw_egg()
	music_requested.emit(MUSIC_EVOLUTION)
	_phase = Phase.OPENING
	_frames = OPENING_FRAMES


func _begin_wobble() -> void:
	_counter = 0
	_phase = Phase.WOBBLE
	_start_pass()


## `.outerloop`: the counter is read, incremented and compared against 8, and
## the pass wobbles as many times as the incremented value.
func _start_pass() -> void:
	if _counter >= WOBBLE_PASSES:
		_finish_wobble()
		return
	_counter += 1
	_halves_left = _counter * 2
	_half_frames = WOBBLE_HALF_FRAMES
	_shift = -WOBBLE_SHIFT
	_place_pic()


func _advance_wobble() -> void:
	if _halves_left > 0:
		_half_frames -= 1
		if _half_frames > 0:
			return
		_halves_left -= 1
		_half_frames = WOBBLE_HALF_FRAMES
		_shift = -_shift
		_place_pic()
		if _halves_left > 0:
			return
		## `ld c, 16` closes the pass with the scroll still where the last half
		## left it; `.done` is what puts it back.
		_frames = PASS_TAIL_FRAMES
		return
	if _spend():
		_crack_shell()
		_start_pass()


## `EggHatch_CrackShell`: the counter's own `dec a / and $7`, which returns
## without a sound on the eighth pass and on every even step of the other
## seven, so three of the eight passes crack.
func _crack_shell() -> void:
	var step: int = (_counter - 1) & 0x7
	if step == 0x7 or (step & 1) == 0:
		return
	sfx_requested.emit(SFX_EGG_CRACK)


## `.done`: the scroll is put back, the shell fragments are thrown and the
## hatchling takes the block the egg was standing in.
func _finish_wobble() -> void:
	_shift = 0
	sfx_requested.emit(SFX_EGG_HATCH)
	_draw_species(int(current_hatch().get("species", 0)))
	_phase = Phase.FRAGMENTS
	_frames = FRAGMENT_FRAMES


## `AnimateFrontpic ANIM_MON_HATCH`, which is Crystal's alone: Gold and Silver
## have no pic animation and the sequence ends on the standing picture.
func _open_frontpic_animation() -> void:
	var species: int = int(current_hatch().get("species", 0))
	var record: Dictionary = _data.pic_animation(species)
	if record.is_empty():
		_open_hatched_text()
		return
	_animation = Gen2PicAnimation.new(record, Gen2PicAnimation.ANIM_MON_HATCH)
	_animation_pixels = Gen2BattleRenderer.padded_pic(
		_data, _data.species_pic(species), BOX, true,
		_data.species_pic_animation(species)
	)
	_phase = Phase.ANIMATE
	_advance_frontpic_animation()


func _advance_frontpic_animation() -> void:
	if _animation == null:
		_open_hatched_text()
		return
	var cry: StringName = _animation.advance()
	if cry != &"":
		cry_requested.emit(int(current_hatch().get("species", 0)))
	_draw_animation_box()
	if _animation.finished():
		_animation = null
		_animation_pixels = PackedByteArray()
		_open_hatched_text()


## `.BreedClearboxText` and then `_BreedEggHatchText`, which carries
## `sound_caught_mon` and ends in `text_promptbutton`.
func _open_hatched_text() -> void:
	_draw_species(int(current_hatch().get("species", 0)))
	_phase = Phase.HATCHED
	_show_text(
		Gen2WorldPartyHost.hatch_text(String(current_hatch().get("nickname", ""))), true
	)
	sfx_requested.emit(SFX_CAUGHT_MON)


func _open_nickname_question() -> void:
	_phase = Phase.ASK_NICKNAME
	_nickname_yes = true
	_show_text(
		Gen2WorldPartyHost.nickname_question(String(current_hatch().get("nickname", "")))
	)
	_draw_yes_no()


## `.nonickname` keeps `wStringBuffer1`, which is the species name the row was
## already given; YES opens `NamingScreen` under NAME_MON.
func _answer_nickname(yes: bool) -> void:
	_menu.visible = false
	if not yes:
		_finish_hatch(String(current_hatch().get("nickname", "")))
		return
	_naming = Gen2NamingScreenScreen.new()
	if not _naming.open(
		_data, Gen2WorldPartyHost.nickname_prompt(
			String(current_hatch().get("nickname", ""))
		),
		Gen2NamingScreenScreen.KIND_MON
	):
		_naming = null
		_finish_hatch(String(current_hatch().get("nickname", "")))
		return
	_text_box.visible = false
	_backdrop.visible = false
	_pic.visible = false
	_naming.closed.connect(_on_named)
	add_child(_naming)
	_phase = Phase.NAMING


## `InitName`, which keeps the species name when the entry came back empty.
func _on_named(entered: String) -> void:
	var chosen: String = entered.strip_edges()
	Gen2Screen.drop(_naming)
	_naming = null
	_finish_hatch(
		chosen if not chosen.is_empty()
		else String(current_hatch().get("nickname", ""))
	)


func _finish_hatch(nickname: String) -> void:
	var hatch: Dictionary = current_hatch()
	if not hatch.is_empty():
		named.emit(int(hatch.get("party_index", -1)), nickname)
	_index += 1
	if _text_box != null:
		_text_box.visible = false
	if _index >= _hatches.size():
		_phase = Phase.DONE
		closed.emit()
		return
	_begin_hatch()


func _draw_yes_no() -> void:
	if _menu_page == null:
		_menu_page = Gen2MenuPage.from_data(_data)
	if _menu_page == null:
		return
	var box: Gen2MenuBox = Gen2MenuBox.yes_no()
	var image: Image = _menu_page.render(box, ["YES", "NO"], 0 if _nickname_yes else 1)
	_menu.texture = ImageTexture.create_from_image(image)
	_menu.position = Vector2(box.border_position() * TILE)
	_menu.visible = true


## `GetEggFrontpic`, which is the egg's own picture and its own palette entry
## rather than the species the row is carrying.
func _draw_egg() -> void:
	var pic: Dictionary = _data.egg_pic()
	if pic.is_empty():
		_pic.texture = null
		return
	_blit(pic, _data.egg_palette(), EGG_AT)


func _draw_species(species: int) -> void:
	var pic: Dictionary = _data.species_pic(species)
	if pic.is_empty():
		_pic.texture = null
		return
	_blit(pic, _data.palette(species), HATCHLING_AT)


func _blit(pic: Dictionary, colours: PackedColorArray, at: Vector2i) -> void:
	var image: Image = Gen2PicImage.from_atlas(
		_data.atlas_indices(pic["atlas"]), _data.atlas(pic["atlas"]), pic, colours
	)
	_pic.texture = ImageTexture.create_from_image(image)
	_pic.size = Vector2(image.get_size())
	_pic_origin = at
	_place_pic()


## `hSCX` scrolls the whole background, so the picture moves the other way.
func _place_pic() -> void:
	if _pic == null:
		return
	_pic.position = Vector2(_pic_origin.x * TILE - _shift, _pic_origin.y * TILE)


func _draw_animation_box() -> void:
	if _pic == null or _animation == null:
		return
	var square: int = BOX * BOX
	if _animation.box.size() != square or _animation_pixels.is_empty():
		return
	var side: int = BOX * TILE
	@warning_ignore("integer_division")
	var strip: int = _animation_pixels.size() / side
	var indices: PackedByteArray = PackedByteArray()
	indices.resize(side * side)
	for column: int in BOX:
		for row: int in BOX:
			var tile: int = int(_animation.box[column * BOX + row])
			@warning_ignore("integer_division")
			var source_x: int = (tile / BOX) * TILE
			var source_y: int = (tile % BOX) * TILE
			if source_x + TILE > strip:
				continue
			for line: int in TILE:
				var from: int = (source_y + line) * strip + source_x
				var to: int = (row * TILE + line) * side + column * TILE
				for x: int in TILE:
					indices[to + x] = _animation_pixels[from + x]
	var image: Image = Gen2PicImage.from_indices(
		indices, side, side, _data.palette(int(current_hatch().get("species", 0)))
	)
	_pic.texture = ImageTexture.create_from_image(image)
	_pic.size = Vector2(image.get_size())
	_pic_origin = HATCHLING_AT
	_place_pic()
