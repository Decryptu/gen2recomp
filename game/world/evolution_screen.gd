class_name Gen2EvolutionScreen
extends Control

## `EvolveAfterBattle`'s `.proceed` and the `EvolutionAnimation` it farcalls,
## for one plan at a time out of [method Gen2Evolution.after_battle].
##
## Presentation only: nothing here writes a party row. Each plan is announced
## with [signal resolved] at the point `.proceed` writes the new species, so the
## caller applies it in the source's own order and the next plan starts after it.
##
## Two pieces of `.PlayEvolvedSFX` are not drawn: the thirty-two balls of light
## are sprite-anim objects and this project has no sprite-anim layer outside the
## intro, so their frames are spent and the screen holds the new picture through
## them. Everything else, including both cries, the flash loop's own rising and
## falling counters and `AnimateFrontpic ANIM_MON_EVOLVE`, is the routine's.

signal resolved(plan: Dictionary, canceled: bool)
signal closed()
## `PlayMonCry`, `PlaySFX` and `PlayMusic`, all through the overworld's own
## driver the way the Hall of Fame's and the Pokedex's are.
signal cry_requested(species: int)
signal sfx_requested(index: int)
signal music_requested(index: int)

## constants/music_constants.asm.
const MUSIC_NONE: int = 0
const MUSIC_EVOLUTION: int = 0x22
## constants/sfx_constants.asm.
const SFX_EVOLVED: int = 0x4F
const SFX_CAUGHT_MON: int = 0x2F

const TILE: int = Gen2Font.TILE
## `hlcoord 7, 2`, the 7x7 block both pics are placed in.
const PIC_AT: Vector2i = Vector2i(7, 2)
const BOX: int = Gen2PicImage.FRONTPIC_TILES

## `.proceed`'s own `ld c, 50` after `EvolvingText`, and the `ld c, 40` after
## `SFX_CAUGHT_MON` at the end of it.
const EVOLVING_FRAMES: int = 50
const CAUGHT_FRAMES: int = 40
## `EvolutionAnimation`'s `ld c, 80` between `MUSIC_EVOLUTION` and the sequence.
const MUSIC_FRAMES: int = 80
## `.AnimationSequence`'s `lb bc, 1, 2 * 7`: b flashes rising by one and c frames
## falling by two, so seven passes of 14, 12 ... 2 frames.
const FLASH_START_WAIT: int = 2 * 7
## Each `.ReplaceFrontpic` ends in `WaitBGMap`, so one half of a flash is one
## frame and a flash is two.
const REPLACE_FRAMES: int = 1
## `.balls_of_light` spends a frame per jumptable step over its own 32, and
## `.done` spends 32 more.
const BALLS_FRAMES: int = 64

enum Phase {
	EVOLVING,
	HOLD,
	FLASH,
	REPLACE,
	BALLS,
	ANIMATE,
	CONGRATULATIONS,
	CANCELED,
	DONE,
}

var _data: GameData = null
var _plans: Array = []
var _index: int = 0
var _phase: int = Phase.DONE
var _frames: int = 0
var _canceled: bool = false
## Whether B arrived since the last frame; see [method advance_frame].
var _b_held: bool = false
var _showing_new: bool = false
## The flash loop's own `b` and `c`, and how much of the current pass is left.
var _flash_b: int = 1
var _flash_c: int = FLASH_START_WAIT
var _flash_left: int = 0
var _flashes_left: int = 0
var _animation: Gen2PicAnimation = null
var _animation_pixels: PackedByteArray = PackedByteArray()

var _backdrop: ColorRect = null
var _pic: TextureRect = null
var _text_box: Gen2TextBox = null


## [param plans] is [method Gen2Evolution.after_battle]'s list. An empty one
## closes on the frame it is opened, the way the Hall of Fame's does.
func set_context(data: GameData, plans: Array) -> void:
	_data = data
	_plans = plans.duplicate()
	_index = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	if _data == null or _plans.is_empty():
		closed.emit()
		return
	_build()
	_begin_plan()


func remaining() -> int:
	return maxi(_plans.size() - _index, 0)


func current_plan() -> Dictionary:
	if _index < 0 or _index >= _plans.size():
		return {}
	return _plans[_index]


func phase() -> int:
	return _phase


## Whether the sequence is standing on a press: a page with another behind it,
## which is `Paragraph`'s own `PromptButton`, or `StoppedEvolvingText`'s `prompt`.
## Every other wait in the routine is a `DelayFrames` count.
func awaiting_press() -> bool:
	if _text_box == null or not _text_box.visible:
		return false
	return _text_box.has_pages_left() or _phase == Phase.CANCELED


## Every line the box is holding, its pages in order. What the sequence says is
## read through this rather than through the plan it was built from.
func text_lines() -> PackedStringArray:
	if _text_box == null or not _text_box.visible:
		return PackedStringArray()
	return _text_box.text_lines()


## `.WaitFrames_CheckPressedB` reads `hJoyDown`, which is the button being HELD
## rather than a fresh press, and only inside the flash loop.
func handle_button(button: int) -> bool:
	if button == Gen2Button.B:
		_b_held = true
		return true
	if button == Gen2Button.A and _text_box != null and _text_box.visible \
		and (_text_box.is_revealing() or _text_box.has_pages_left()):
		_text_box.advance()
		return true
	if button == Gen2Button.A and _phase == Phase.CANCELED:
		_finish_plan()
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

	_text_box = Gen2TextBox.new()
	## The overworld owns the frame here too, so the reveal is spent from
	## [method advance_frame] rather than from real time.
	_text_box.driven = true
	_text_box.font = Gen2Font.from_data(_data)
	## The OPTION menu's own TEXT SPEED and frame, the way every other box in the
	## overworld is drawn: this one is `PrintText` like the rest.
	var options: Gen2Options = Gen2OptionsStore.current()
	_text_box.set_frame_style(options.textbox_frame)
	_text_box.reveal_speed = options.text_reveal_speed()
	_text_box.place_at_bottom()
	_text_box.visible = false
	add_child(_text_box)


## `.proceed` up to its `ld c, 50`: the name is read before the species is
## replaced, so the box is built from the plan rather than from the party.
func _begin_plan() -> void:
	var plan: Dictionary = current_plan()
	if plan.is_empty():
		_phase = Phase.DONE
		closed.emit()
		return
	_canceled = false
	_b_held = false
	_showing_new = false
	## `EvolvingText` is printed over the map, before the `ClearBox` that takes
	## it down, so this phase draws no backdrop of its own.
	_backdrop.visible = false
	_pic.visible = false
	_show_text(Gen2Evolution.evolving_text(String(plan.get("evolving_name", ""))))
	_enter(Phase.EVOLVING, EVOLVING_FRAMES)


func _enter(next: int, frames: int) -> void:
	_phase = next
	_frames = frames


func _show_text(text: String) -> void:
	if _text_box == null:
		return
	_text_box.visible = true
	## Neither `EvolvingText` nor `EvolvedIntoText` ends in `prompt`, and
	## `StoppedEvolvingText` does: the arrow follows the terminator, not the wait.
	_text_box.show_text(text, _phase == Phase.CANCELED)


## One hardware frame. Every wait in the routine is a `DelayFrames` count, so
## the whole sequence is spent from the overworld's own pump.
func advance_frame() -> void:
	if _phase == Phase.DONE or _data == null:
		return
	if _text_box != null:
		_text_box.advance_frame()
		## A page still printing, or one with another behind it, is what the
		## routine's own `PrintText` is waiting on before its `DelayFrames`.
		if _text_box.visible and (_text_box.is_revealing() or _text_box.has_pages_left()):
			return
	## `hJoyDown` is the pad as it stands rather than a latch, and it is read on
	## the wait frames alone, so a press is offered to this frame and dropped.
	var pressed_b: bool = _b_held
	_b_held = false
	match _phase:
		Phase.EVOLVING:
			if _spend():
				_open_animation()
		Phase.HOLD:
			if _spend():
				_begin_flash()
		Phase.FLASH:
			_advance_flash(pressed_b)
		Phase.REPLACE:
			if _spend():
				_begin_balls()
		Phase.BALLS:
			if _spend():
				_open_frontpic_animation()
		Phase.ANIMATE:
			_advance_frontpic_animation()
		Phase.CONGRATULATIONS:
			if _spend():
				_finish_plan()
		Phase.CANCELED:
			## `StoppedEvolvingText` ends in `prompt`, so this one waits on a
			## press rather than on a count.
			pass


## True on the frame the countdown runs out.
func _spend() -> bool:
	_frames -= 1
	return _frames <= 0


## `EvolutionAnimation` up to its `ld c, 80`: the map is cleared, the OLD pic is
## placed, the cry plays unless the Pokemon is statused, and the evolution track
## takes over from whatever was playing.
func _open_animation() -> void:
	var plan: Dictionary = current_plan()
	_text_box.visible = false
	_backdrop.visible = true
	_pic.visible = true
	_draw_species(int(plan.get("old_species", 0)))
	music_requested.emit(MUSIC_NONE)
	if not bool(plan.get("statused", false)):
		cry_requested.emit(int(plan.get("old_species", 0)))
	music_requested.emit(MUSIC_EVOLUTION)
	_enter(Phase.HOLD, MUSIC_FRAMES)


func _begin_flash() -> void:
	_flash_b = 1
	_flash_c = FLASH_START_WAIT
	_flash_left = _flash_c
	_flashes_left = _flash_b * 2
	_phase = Phase.FLASH


## `.loop`: `c` frames of `.WaitFrames_CheckPressedB`, then `.Flash` b times,
## then `inc b` and two `dec c`, until c reaches zero. B is read during the wait
## alone, which is why a press landing inside a flash cancels nothing on the
## cartridge either.
func _advance_flash(pressed_b: bool) -> void:
	if _flash_left > 0:
		if pressed_b and bool(current_plan().get("can_cancel", true)):
			_cancel()
			return
		_flash_left -= 1
		return
	if _flashes_left > 0:
		## One `.ReplaceFrontpic` is one `WaitBGMap`, so a flash is two frames:
		## the new stage on the first and the old one back on the second.
		_flashes_left -= 1
		_show_stage(not _showing_new)
		if _flashes_left > 0:
			return
	_flash_c -= 2
	if _flash_c <= 0:
		_settle()
		return
	_flash_b += 1
	_flash_left = _flash_c
	_flashes_left = _flash_b * 2


## The `ld a, -7 * 7 / .ReplaceFrontpic` after the sequence: the new stage is
## left standing, `SFX_EVOLVED` plays and the balls of light run over it.
func _settle() -> void:
	_show_stage(true)
	_enter(Phase.REPLACE, REPLACE_FRAMES)


func _begin_balls() -> void:
	sfx_requested.emit(SFX_EVOLVED)
	_enter(Phase.BALLS, BALLS_FRAMES)


## `.cancel_evo`: the old stage stays, `.PlayEvolvedSFX` returns without a sound
## because `wEvolutionCanceled` is set, and a Pokemon that is not statused cries.
func _cancel() -> void:
	_canceled = true
	_show_stage(false)
	var plan: Dictionary = current_plan()
	if not bool(plan.get("statused", false)):
		cry_requested.emit(int(plan.get("old_species", 0)))
	_phase = Phase.CANCELED
	_backdrop.visible = true
	_show_text(Gen2Evolution.stopped_evolving_text(
		String(plan.get("evolving_name", ""))
	))


## `AnimateFrontpic ANIM_MON_EVOLVE`, skipped for a statused Pokemon along with
## the cry, and absent from Gold and Silver, which have no pic animation at all.
func _open_frontpic_animation() -> void:
	var plan: Dictionary = current_plan()
	var species: int = int(plan.get("new_species", 0))
	var record: Dictionary = _data.pic_animation(species)
	if bool(plan.get("statused", false)) or record.is_empty():
		_open_congratulations()
		return
	_animation = Gen2PicAnimation.new(record, Gen2PicAnimation.ANIM_MON_EVOLVE)
	_animation_pixels = Gen2BattleRenderer.padded_pic(
		_data, _data.species_pic(species), BOX, true,
		_data.species_pic_animation(species)
	)
	_phase = Phase.ANIMATE
	_advance_frontpic_animation()


func _advance_frontpic_animation() -> void:
	if _animation == null:
		_open_congratulations()
		return
	var cry: StringName = _animation.advance()
	if cry != &"":
		cry_requested.emit(int(current_plan().get("new_species", 0)))
	_draw_animation_box()
	if _animation.finished():
		_animation = null
		_animation_pixels = PackedByteArray()
		_open_congratulations()


## `CongratulationsYourPokemonText` and `EvolvedIntoText`, then `MUSIC_NONE`,
## `SFX_CAUGHT_MON`, `WaitSFX` and `ld c, 40`.
func _open_congratulations() -> void:
	var plan: Dictionary = current_plan()
	_show_stage(true)
	_phase = Phase.CONGRATULATIONS
	_show_text(Gen2Evolution.evolved_text(
		String(plan.get("evolving_name", "")),
		String(_data.species(int(plan.get("new_species", 0))).get("name", ""))
	))
	music_requested.emit(MUSIC_NONE)
	sfx_requested.emit(SFX_CAUGHT_MON)
	_frames = CAUGHT_FRAMES


## `.proceed`'s write, or `CancelEvolution`'s `jp EvolveAfterBattle_MasterLoop`.
func _finish_plan() -> void:
	var plan: Dictionary = current_plan()
	if not plan.is_empty():
		resolved.emit(plan.duplicate(true), _canceled)
	_index += 1
	if _text_box != null:
		_text_box.visible = false
	if _index >= _plans.size():
		_phase = Phase.DONE
		closed.emit()
		return
	_begin_plan()


func _show_stage(new_stage: bool) -> void:
	_showing_new = new_stage
	var plan: Dictionary = current_plan()
	_draw_species(int(plan.get(
		"new_species" if new_stage else "old_species", 0
	)))


func _draw_species(species: int) -> void:
	if _pic == null or _data == null:
		return
	var pic: Dictionary = _data.species_pic(species)
	if pic.is_empty():
		_pic.texture = null
		return
	var image: Image = Gen2PicImage.from_atlas(
		_data.atlas_indices(pic["atlas"]), _data.atlas(pic["atlas"]), pic,
		_data.palette(species)
	)
	_pic.texture = ImageTexture.create_from_image(image)
	_pic.size = Vector2(image.get_size())
	## `PadFrontpic` bottom-aligns a pic shorter than the block one column in,
	## which is where `PlaceGraphic`'s tile numbers put it.
	@warning_ignore("integer_division")
	var columns: int = image.get_width() / TILE
	@warning_ignore("integer_division")
	var rows: int = image.get_height() / TILE
	_pic.position = Vector2(
		(PIC_AT.x + Gen2PicImage.frontpic_pad_columns(columns)) * TILE,
		(PIC_AT.y + Gen2PicImage.frontpic_pad_rows(rows)) * TILE
	)


## The animation's own 7x7 box, drawn out of the same padded strip the battle
## renderer reads: a cell is `column * 7 + row` into the box and its value is a
## tile number down the strip's columns.
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
		indices, side, side,
		_data.palette(int(current_plan().get("new_species", 0)))
	)
	_pic.texture = ImageTexture.create_from_image(image)
	_pic.size = Vector2(image.get_size())
	_pic.position = Vector2(PIC_AT.x * TILE, PIC_AT.y * TILE)
