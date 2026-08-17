class_name Gen2ClockSetScreen
extends Control

## `InitClock` followed by `SetDayOfWeek`, before Oak's first speech beat.

signal finished(day: int, hour: int, minute: int)

enum Phase { HOUR, HOUR_CONFIRM, MINUTE, MINUTE_CONFIRM, DAY, DAY_CONFIRM, DONE }

const DAYS: Array[String] = [
	" SUNDAY", " MONDAY", " TUESDAY", "WEDNESDAY", "THURSDAY", " FRIDAY", "SATURDAY",
]

var _page: Gen2ClockSetPage = null
var _view: TextureRect = null
var _phase: int = Phase.HOUR
var _hour: int = 10
var _minute: int = 0
var _day: int = 0
var _confirm_cursor: int = 0


func open(data: GameData) -> bool:
	_page = Gen2ClockSetPage.from_data(data)
	return _page != null


func _ready() -> void:
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_view = TextureRect.new()
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.size = size
	add_child(_view)
	_render()


func handle_button(button: int) -> bool:
	if _phase == Phase.DONE:
		return true
	if button in [Gen2Button.UP, Gen2Button.DOWN]:
		if _phase in [Phase.HOUR_CONFIRM, Phase.MINUTE_CONFIRM, Phase.DAY_CONFIRM]:
			_confirm_cursor = 1 - _confirm_cursor
			_render()
			return true
		var step: int = 1 if button == Gen2Button.UP else -1
		match _phase:
			Phase.HOUR: _hour = wrapi(_hour + step, 0, 24)
			Phase.MINUTE: _minute = wrapi(_minute + step, 0, 60)
			Phase.DAY: _day = wrapi(_day + step, 0, 7)
		_render()
		return true
	if button == Gen2Button.B and _phase in [Phase.HOUR_CONFIRM, Phase.MINUTE_CONFIRM, Phase.DAY_CONFIRM]:
		_phase -= 1
		_confirm_cursor = 0
		_render()
		return true
	if button != Gen2Button.A:
		return false
	if _phase in [Phase.HOUR_CONFIRM, Phase.MINUTE_CONFIRM, Phase.DAY_CONFIRM] \
			and _confirm_cursor == 1:
		_phase -= 1
		_confirm_cursor = 0
		_render()
		return true
	match _phase:
		Phase.HOUR:
			_phase = Phase.HOUR_CONFIRM
			_confirm_cursor = 0
		Phase.HOUR_CONFIRM: _phase = Phase.MINUTE
		Phase.MINUTE:
			_phase = Phase.MINUTE_CONFIRM
			_confirm_cursor = 0
		Phase.MINUTE_CONFIRM: _phase = Phase.DAY
		Phase.DAY:
			_phase = Phase.DAY_CONFIRM
			_confirm_cursor = 0
		Phase.DAY_CONFIRM:
			_phase = Phase.DONE
			finished.emit(_day, _hour, _minute)
	_render()
	return true


func value() -> Dictionary:
	return {"day": _day, "hour": _hour, "minute": _minute}


func _render() -> void:
	if _view == null or _page == null or _phase == Phase.DONE:
		return
	var day: bool = _phase in [Phase.DAY, Phase.DAY_CONFIRM]
	var confirm: bool = _phase in [Phase.HOUR_CONFIRM, Phase.MINUTE_CONFIRM, Phase.DAY_CONFIRM]
	var value_text: String
	var prompt: String
	if day:
		value_text = DAYS[_day]
		prompt = "%s, is it?" % DAYS[_day].strip_edges() if confirm else "What day is it?"
	elif _phase in [Phase.MINUTE, Phase.MINUTE_CONFIRM]:
		value_text = "%d min." % _minute
		prompt = "Whoa! %d min.?" % _minute if confirm else "How many minutes?"
	else:
		value_text = "%s o'clock" % _hour_text()
		prompt = "What? %s?" % value_text if confirm else "What time is it?"
	_view.texture = ImageTexture.create_from_image(_page.render(
		value_text, prompt, _confirm_cursor if confirm else -1, day
	))


func _hour_text() -> String:
	var shown: int = _hour % 12
	if shown == 0:
		shown = 12
	return "%d %s" % [shown, "AM" if _hour < 12 else "PM"]
