class_name Gen2IntroPresentation
extends RefCounted

## The intro's own per-frame animation: `home/fade.asm`'s palette fades,
## `Intro_RotatePalettesLeftFrontpic`, `Intro_WipeInFrontpic` and
## `MovePlayerPic`, queued as steps a screen advances one VBlank at a time.
##
## A palette step is a DMG palette byte, not a rotation: `CopyPals` reads it two
## bits at a time and writes the loaded colour each pair names, so a fade is an
## index remap of the palette already loaded ([method apply_bgp]). Every count is
## a `DelayFrames` operand, so a screen stepping this at [constant FRAME_RATE]
## spends the frames the cartridge spends.

const FRAME_RATE: float = 59.7275

## A step that writes no palette byte, or that does not move the pic.
const KEEP: int = -1

## `%11100100`: the identity remap, which is what an unfaded screen shows.
const BGP_NORMAL: int = 0xE4

## `home/fade.asm`'s IncGradGBPalTable_00 to _07, the half the rotate routines
## take when hCGB is set. A row is bgp, obp0 and obp1, all three equal here, so
## one byte stands for the row and one fade covers the sprites too.
const INC_GRAD: Array[int] = [0xFF, 0xFE, 0xF9, 0xE4, 0xE4, 0x90, 0x40, 0x00]
## Both rotate routines' own `ld c, 8`.
const FADE_STEP_FRAMES: int = 8

## `WaitBGMap`'s own `ld c, 4` (`home/tilemap.asm`), which is what makes a
## `MovePlayerPic` iteration five frames rather than one.
const WAIT_BG_MAP_FRAMES: int = 4

## `IntroFadePalettes`, ten frames a step: the pic resolves out of the white
## `RotateThreePalettesRight` left behind.
const FRONTPIC_FADE: Array[int] = [0x54, 0xA8, 0xFC, 0xF8, 0xF4, 0xE4]
const FRONTPIC_FADE_STEP_FRAMES: int = 10

## `Intro_WipeInFrontpic` walks hWX from $77 down in eights until it would pass
## zero. hWY sits at $90 for the whole of `OakSpeech` (`StartTitleScreen`), so
## the window is off the bottom and the walk is a delay; the pic appears when the
## routine writes the identity palette on its second frame.
const WIPE_START: int = 0x77
const WIPE_STEP: int = 8

## `MovePlayerPic`'s `ld c, $8`, and the five VBlanks one iteration costs:
## `WaitBGMap`'s `ld c, 4` plus the `DelayFrame` after it.
const MOVE_STEPS: int = 8
const MOVE_STEP_FRAMES: int = WAIT_BG_MAP_FRAMES + 1
## `MovePlayerPicRight` starts at `hlcoord 6, 4`, `MovePlayerPicLeft` at
## `hlcoord 13, 4`, and each ends where the other starts.
const PIC_LEFT_COLUMN: int = 6
const PIC_RIGHT_COLUMN: int = 13

## Each entry is [bgp, column, frames]; [constant KEEP] leaves that value alone.
var _steps: Array[Array] = []
var _step: int = 0
var _step_frame: int = 0
var _bgp: int = BGP_NORMAL
var _column: int = PIC_LEFT_COLUMN


## Empties the queue. The palette byte and pic column are hardware state and
## survive it, which is how `MovePlayerPicRight` hands the naming menu a pic
## already at column 13.
func clear() -> void:
	_steps.clear()
	_step = 0
	_step_frame = 0


func push(palette_byte: int, pic_column: int, frames: int) -> void:
	if frames > 0:
		_steps.append([palette_byte, pic_column, frames])


func push_delay(frames: int) -> void:
	push(KEEP, KEEP, frames)


## `RotateFourPalettesLeft`: tables 03 down to 00, ending on black.
func push_rotate_four_left() -> void:
	_push_fade([3, 2, 1, 0])


## `RotateFourPalettesRight`: tables 00 up to 03, ending on the identity.
func push_rotate_four_right() -> void:
	_push_fade([0, 1, 2, 3])


## `RotateThreePalettesRight`: tables 05 up to 07, ending on white.
func push_rotate_three_right() -> void:
	_push_fade([5, 6, 7])


## `RotateThreePalettesLeft`: tables 06 down to 04, ending on the identity.
func push_rotate_three_left() -> void:
	_push_fade([6, 5, 4])


func push_rotate_left_frontpic() -> void:
	for palette_byte: int in FRONTPIC_FADE:
		push(palette_byte, KEEP, FRONTPIC_FADE_STEP_FRAMES)


func push_wipe_in_frontpic() -> void:
	push(KEEP, KEEP, 1)
	push(BGP_NORMAL, KEEP, wipe_frames() - 1)


## `MovePlayerPic`: eight iterations, one tile each, holding every column for
## [constant MOVE_STEP_FRAMES]. The last column is not cleared, so the pic stays
## where the run ends.
func push_move_player_pic(right: bool) -> void:
	var from: int = PIC_LEFT_COLUMN if right else PIC_RIGHT_COLUMN
	var step: int = 1 if right else -1
	for index: int in MOVE_STEPS:
		push(KEEP, from + index * step, MOVE_STEP_FRAMES)


## Applies the queued step's own palette byte and pic column without spending a
## frame. A routine writes its first palette before the `DelayFrames` that holds
## it, so a screen drawn between the push and the first VBlank is already in the
## state the step names rather than one frame behind it.
func sync() -> void:
	if finished() or _step_frame != 0:
		return
	var step: Array = _steps[_step]
	if int(step[0]) != KEEP:
		_bgp = int(step[0])
	if int(step[1]) != KEEP:
		_column = int(step[1])


## Advances one source frame. False once the queue has run out, which is what
## tells a screen the routine it is standing in has returned.
func advance_frame() -> bool:
	if finished():
		return false
	var step: Array = _steps[_step]
	if _step_frame == 0:
		if int(step[0]) != KEEP:
			_bgp = int(step[0])
		if int(step[1]) != KEEP:
			_column = int(step[1])
	_step_frame += 1
	if _step_frame >= int(step[2]):
		_step += 1
		_step_frame = 0
	return true


func finished() -> bool:
	return _step >= _steps.size()


## The palette byte in force, which every drawn palette is remapped through.
func bgp() -> int:
	return _bgp


## Where the player pic sits, in tiles.
func column() -> int:
	return _column


func remaining_frames() -> int:
	var out: int = 0
	for index: int in range(_step, _steps.size()):
		out += int(_steps[index][2])
	return out - _step_frame


## `CopyPals`: displayed colour `i` is the loaded colour the byte's `i`th pair
## names, low pair first. Anything that is not a four-colour row is handed back,
## since there is no palette for the byte to index.
static func apply_bgp(row: PackedColorArray, palette_byte: int) -> PackedColorArray:
	if row.size() != 4:
		return row
	var out := PackedColorArray()
	out.resize(4)
	for index: int in 4:
		out[index] = row[(palette_byte >> (2 * index)) & 3]
	return out


## How many frames `Intro_WipeInFrontpic` costs: one before the loop, then one
## per eight of hWX until the subtraction would pass zero.
static func wipe_frames() -> int:
	@warning_ignore("integer_division")
	return 1 + (WIPE_START + 1) / WIPE_STEP


## hWX on a given frame of the wipe, for a renderer that wants to draw the
## window the source moves even though nothing is behind it.
static func wipe_window_x(frame: int) -> int:
	return maxi(0, WIPE_START - maxi(frame, 0) * WIPE_STEP)


func _push_fade(tables: Array[int]) -> void:
	for table: int in tables:
		push(INC_GRAD[table], KEEP, FADE_STEP_FRAMES)
