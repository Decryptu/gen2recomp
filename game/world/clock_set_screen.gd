class_name Gen2ClockSetScreen
extends Control

## `InitClock`, before Oak's first speech beat. Hour and minutes only: the
## routine ends on `OakText_ResponseToSetTime` after `.MinutesAreSet` and never
## calls `SetDayOfWeek`, which is Mom's own errand in `PlayersHouse1F.asm`. The
## weekday the save starts on is whatever the RTC holds, SUNDAY on a fresh one.
##
## Every line here is a `PrintText`, so the box is a [Gen2TextBox] and reveals at
## the cartridge's own rate, and every wait is a `DelayFrames` operand spent
## through a [Gen2IntroPresentation]. `RotateFourPalettesLeft` is the caller's,
## over the screen `InitGender` left standing; see [Gen2IntroScreen].

signal finished(day: int, hour: int, minute: int)

enum Phase { WOKE_UP, HOUR, HOUR_CONFIRM, MINUTE, MINUTE_CONFIRM, RESPONSE, DONE }

const TILE: int = Gen2Font.TILE

## `SetDayOfWeek`'s own `.WeekdayStrings`, padded the way the source pads them so
## the name is centred in its nine-wide box. Drawn by Mom's errand rather than
## here; this is where the strings live because the dial page is shared.
const DAYS: Array[String] = [
	" SUNDAY", " MONDAY", " TUESDAY", "WEDNESDAY", "THURSDAY", " FRIDAY", "SATURDAY",
]

## `_OakTimeWokeUpText`. `<……>` is `SixDotsCharText`, which is two ellipsis
## tiles, so each of the first two lines is twelve.
const WOKE_UP_TEXT: String = "%s\n%s%sZzz… Hm? Wha…?\nYou woke me up!%sWill you check the\nclock for me?"

## `constants/misc_constants.asm`. `GetTimeOfDayString` tests MORN_HOUR, DAY_HOUR
## and NITE_HOUR in that order and falls through to NITE, so 18 and up is NITE
## again; `OakText_ResponseToSetTime` tests `DAY_HOUR + 1` instead, which is why
## its three answers do not split the day where the MORN/DAY/NITE word does.
const MORN_HOUR: int = 4
const DAY_HOUR: int = 10
const NITE_HOUR: int = 18
const NOON_HOUR: int = 12

## `.loop` and `.HourIsSet` both end on `ld c, 10 / call DelayFrames` before
## their input loop, and `InterpretTwoOptionMenu` holds `ld c, $f` after an
## answer, so neither a dial nor a YES/NO reads a button on the frame it is
## drawn.
const DIAL_DELAY_FRAMES: int = 10
const YES_NO_DELAY_FRAMES: int = 15

var _page: Gen2ClockSetPage = null
var _view: TextureRect = null
var _text_box: Gen2TextBox = null
var _presentation := Gen2IntroPresentation.new()
var _after: Callable = Callable()
var _accumulator: float = 0.0
var _phase: int = Phase.WOKE_UP
var _hour: int = 10
var _minute: int = 0
## `InitTimeOfDay` leaves the RTC's own weekday alone, so a new save starts on
## SUNDAY and Mom's `SetDayOfWeek` is what changes it.
var _day: int = 0
var _confirm_cursor: int = 0
## True while a queued `DelayFrames` run is being spent, which reads no button.
var _waiting: bool = false
## Whether the box was still printing when the screen behind it was last drawn.
var _revealing: bool = false


func open(data: GameData) -> bool:
	_page = Gen2ClockSetPage.from_data(data)
	if _page == null:
		return false
	_text_box = Gen2TextBox.new()
	_text_box.driven = true
	_text_box.font = _page.font
	_text_box.frame_style = Gen2OptionsStore.current().textbox_frame
	_text_box.position = Vector2(0, Gen2TextBox.STANDARD_TOP * TILE)
	return true


func _ready() -> void:
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_view = TextureRect.new()
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.size = size
	add_child(_view)
	if _text_box != null:
		add_child(_text_box)
		# `RotateFourPalettesRight` comes back on a screen `ClearTilemap` and
		# `.ClearScreen` left empty; the first `PrintText` is what puts a box on it.
		_text_box.visible = false
	_begin()


func _process(delta: float) -> void:
	if _text_box != null:
		_text_box.accelerated = Gen2Button.text_accelerating()
	_accumulator += delta * Gen2IntroPresentation.FRAME_RATE
	var frames: int = int(_accumulator)
	_accumulator -= float(frames)
	advance_frames(frames)


## Runs [param count] source frames of whatever the screen is standing in.
## Public so a test or a preview tool can spend the cartridge's own
## `DelayFrames` without a clock; [method _process] is the only other caller.
func advance_frames(count: int) -> void:
	for _frame: int in count:
		if _text_box != null:
			_text_box.advance_frame()
		if not _waiting:
			# The YES/NO box is `YesNoBox`, which runs after its question has
			# finished printing, so the screen behind the box is redrawn on the
			# frame the reveal ends.
			if _text_box != null and _revealing != _text_box.is_revealing():
				_render()
			continue
		_presentation.advance_frame()
		_render()
		# The last VBlank of a `DelayFrames` run is the frame the routine
		# returns on, so no frame is spent at a call boundary.
		if _presentation.finished():
			_finish_queue()


## How many source frames the screen owes before it will read a button: the
## queued `DelayFrames`, or the rest of a text that is still printing.
func animation_frames_left() -> int:
	if _waiting:
		return _presentation.remaining_frames()
	return _text_box.frames_left() if _text_box != null else 0


func handle_button(button: int) -> bool:
	if _phase == Phase.DONE:
		return true
	if _waiting:
		return true
	if _text_box != null and _text_box.is_revealing():
		return true
	match _phase:
		Phase.WOKE_UP:
			if button != Gen2Button.A and button != Gen2Button.B:
				return false
			if _text_box.advance():
				return true
			_begin_hour()
			return true
		Phase.RESPONSE:
			# `WaitPressAorB_BlinkCursor` takes either.
			if button != Gen2Button.A and button != Gen2Button.B:
				return false
			_phase = Phase.DONE
			finished.emit(_day, _hour, _minute)
			return true
	if _phase == Phase.HOUR_CONFIRM or _phase == Phase.MINUTE_CONFIRM:
		return _handle_confirm(button)
	if button in [Gen2Button.UP, Gen2Button.DOWN]:
		var step: int = 1 if button == Gen2Button.UP else -1
		if _phase == Phase.HOUR:
			_hour = wrapi(_hour + step, 0, 24)
		else:
			_minute = wrapi(_minute + step, 0, 60)
		_render()
		return true
	if button != Gen2Button.A:
		return false
	_begin_confirm()
	return true


func value() -> Dictionary:
	return {"day": _day, "hour": _hour, "minute": _minute}


## `VerticalMenu` under `YesNoBox`: up and down move, A answers the row and B is
## NO. `InterpretTwoOptionMenu` spends `ld c, $f` on either before the box is
## closed, so the answer is not acted on until those frames have gone.
func _handle_confirm(button: int) -> bool:
	if button in [Gen2Button.UP, Gen2Button.DOWN]:
		_confirm_cursor = 1 - _confirm_cursor
		_render()
		return true
	if button != Gen2Button.A and button != Gen2Button.B:
		return false
	var yes: bool = button == Gen2Button.A and _confirm_cursor == 0
	_presentation.clear()
	_presentation.push_delay(YES_NO_DELAY_FRAMES)
	_queue(_accept_confirm.bind(yes))
	return true


func _accept_confirm(yes: bool) -> void:
	var hour_phase: bool = _phase == Phase.HOUR_CONFIRM
	if not yes:
		# `jr nc` failing takes the hour back to `.loop` and the minutes back to
		# `.HourIsSet`, which is each dial's own entry.
		if hour_phase:
			_begin_hour()
		else:
			_begin_minute()
		return
	if hour_phase:
		_begin_minute()
		return
	_begin_response()


## `OakSpeech`'s `farcall InitClock` opens on `RotateFourPalettesRight`: the
## caller faded to black over the gender screen, this screen is built behind it
## and comes back in. `PrintText OakTimeWokeUpText` is what follows.
func _begin() -> void:
	_presentation.clear()
	_presentation.push_rotate_four_right()
	_queue(_show_woke_up)


func _show_woke_up() -> void:
	_phase = Phase.WOKE_UP
	var dots: String = "…".repeat(12)
	_text_box.visible = true
	# Ends in `prompt`, which is the one text here that loads the arrow.
	_text_box.show_text(WOKE_UP_TEXT % [
		dots, dots, Gen2TextStream.PAGE_BREAK, Gen2TextStream.PAGE_BREAK
	], true)
	_render()


## `.loop`: the question, the dial and its arrows, then `ld c, 10`.
func _begin_hour() -> void:
	_phase = Phase.HOUR
	_show_line("What time is it?")
	_hold(DIAL_DELAY_FRAMES)


## `.HourIsSet`, which is the minutes' own entry and what a refused minute
## returns to.
func _begin_minute() -> void:
	_phase = Phase.MINUTE
	_show_line("How many minutes?")
	_hold(DIAL_DELAY_FRAMES)


## `.ClearScreen` takes the dial off before either question, so a YES/NO box
## stands on an otherwise empty screen.
func _begin_confirm() -> void:
	_phase = Phase.HOUR_CONFIRM if _phase == Phase.HOUR else Phase.MINUTE_CONFIRM
	_confirm_cursor = 0
	_show_line("What?" if _phase == Phase.HOUR_CONFIRM else "Whoa!")


## `.MinutesAreSet`: `OakText_ResponseToSetTime` prints the time it was given and
## then one of three lines, all of which end in `done`, so `WaitPressAorB_
## BlinkCursor` waits with no arrow shown.
func _begin_response() -> void:
	_phase = Phase.RESPONSE
	_show_line("%s:%02d%s" % [_hour_text(), _minute, _response_line()], false)


func _response_line() -> String:
	if _hour < MORN_HOUR or _hour >= NITE_HOUR:
		return "!\nNo wonder it's so%sdark!" % Gen2TextStream.SCROLL_BREAK
	if _hour <= DAY_HOUR:
		return "!\nI overslept!"
	return "!\nYikes! I over-%sslept!" % Gen2TextStream.SCROLL_BREAK


func _show_line(text: String, blink_cursor: bool = false) -> void:
	_text_box.visible = true
	_text_box.show_text(text, blink_cursor)
	_render()


func _hold(frames: int) -> void:
	_presentation.clear()
	_presentation.push_delay(frames)
	_queue(Callable())


func _queue(after: Callable) -> void:
	_after = after
	_waiting = true
	_accumulator = 0.0
	# The routine writes its first palette before the `DelayFrames` that holds
	# it, so the frame this is queued on is already in that state.
	_presentation.sync()
	_render()


func _finish_queue() -> void:
	_presentation.clear()
	_waiting = false
	var next: Callable = _after
	_after = Callable()
	if next.is_valid():
		next.call()


func _render() -> void:
	if _view == null or _page == null or _phase == Phase.DONE:
		return
	var confirm: bool = (_phase == Phase.HOUR_CONFIRM or _phase == Phase.MINUTE_CONFIRM) \
		and _text_box != null and not _text_box.is_revealing()
	var kind: StringName = &""
	var value_text: String = ""
	if _phase == Phase.HOUR:
		kind = &"hour"
		value_text = "%s o'clock" % _hour_text()
	elif _phase == Phase.MINUTE:
		kind = &"minutes"
		value_text = "%d min." % _minute
	# Every BG palette on screen goes through the frame's own byte, which is what
	# a hardware fade does to a screen carrying more than one palette.
	var colors: PackedColorArray = Gen2IntroPresentation.apply_bgp(
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK])),
		_presentation.bgp()
	)
	_view.texture = ImageTexture.create_from_image(_page.render(
		value_text, "", _confirm_cursor if confirm else -1, kind, colors
	))
	if _text_box != null:
		_text_box.palette = colors
		_revealing = _text_box.is_revealing()


## `PrintHour` prints `GetTimeOfDayString`'s own MORN/DAY/NITE ahead of the
## hour, not AM/PM, and `AdjustHourForAMorPM` turns midnight into twelve.
func _hour_text() -> String:
	var shown: int = _hour % NOON_HOUR
	if shown == 0:
		shown = NOON_HOUR
	var word: String = "NITE"
	if _hour >= MORN_HOUR and _hour < DAY_HOUR:
		word = "MORN"
	elif _hour >= DAY_HOUR and _hour < NITE_HOUR:
		word = "DAY"
	return "%s %d" % [word, shown]
