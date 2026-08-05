class_name Gen2WorldClock
extends RefCounted

## Deterministic host clock for the real-time Generation 2 day cycle.
## One elapsed host second is one cartridge clock second. A tick is published at
## each completed game minute, while time-of-day changes use the cartridge's
## 04:00, 10:00 and 18:00 boundaries.
##
## The clock does not move roaming Pokémon. The cartridge advances those during
## map setup, so [method Gen2WorldAPI.advance_schedule] is driven by a map
## change rather than by elapsed time.

const SECONDS_PER_MINUTE: float = 60.0
const MINUTES_PER_HOUR: int = 60
const HOURS_PER_DAY: int = 24
const DAYS_PER_WEEK: int = 7
const MORN_START: int = 4
const DAY_START: int = 10
const NITE_START: int = 18

var day: int = 0
var hour: int = 0
var minute: int = 0
var _elapsed_seconds: float = 0.0


func _init(start_hour: int = 0, start_minute: int = 0, start_day: int = 0) -> void:
	day = posmod(start_day, DAYS_PER_WEEK)
	hour = posmod(start_hour, HOURS_PER_DAY)
	minute = posmod(start_minute, MINUTES_PER_HOUR)


func time_of_day() -> int:
	if hour < MORN_START:
		return Gen2WorldPalette.TIME_NIGHT
	if hour < DAY_START:
		return Gen2WorldPalette.TIME_MORNING
	if hour < NITE_START:
		return Gen2WorldPalette.TIME_DAY
	return Gen2WorldPalette.TIME_NIGHT


func advance(seconds: float, world: Gen2WorldAPI = null) -> Array:
	if seconds <= 0.0:
		return []
	_elapsed_seconds += seconds
	var ticks: Array = []
	while _elapsed_seconds >= SECONDS_PER_MINUTE:
		_elapsed_seconds -= SECONDS_PER_MINUTE
		_advance_minute()
		if world != null:
			world.set_world_clock(day, hour, minute)
		ticks.append({
			"kind": &"world_clock_minute",
			"day": day,
			"hour": hour,
			"minute": minute,
			"time_of_day": time_of_day(),
		})
	return ticks


func snapshot() -> Dictionary:
	return {
		"day": day,
		"hour": hour,
		"minute": minute,
		"elapsed_seconds": _elapsed_seconds,
		"time_of_day": time_of_day(),
	}


func _advance_minute() -> void:
	minute += 1
	if minute < MINUTES_PER_HOUR:
		return
	minute = 0
	hour += 1
	if hour < HOURS_PER_DAY:
		return
	hour = 0
	day = (day + 1) % DAYS_PER_WEEK
