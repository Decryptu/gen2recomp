extends GutTest

## The host clock uses the same one-second units as the cartridge RTC, but it
## is deterministic so a test can cross a boundary without waiting in real time.


func test_clock_publishes_one_schedule_tick_per_completed_minute() -> void:
	var clock := Gen2WorldClock.new(9, 59, 2)
	assert_eq(clock.advance(59.9, null).size(), 0)
	var ticks: Array = clock.advance(0.1, null)
	assert_eq(ticks.size(), 1)
	assert_eq(ticks[0]["day"], 2)
	assert_eq(ticks[0]["hour"], 10)
	assert_eq(ticks[0]["minute"], 0)
	assert_eq(ticks[0]["time_of_day"], Gen2WorldPalette.TIME_DAY)


func test_clock_uses_source_time_of_day_boundaries_and_wraps_the_week() -> void:
	var clock := Gen2WorldClock.new(17, 59, 6)
	assert_eq(clock.time_of_day(), Gen2WorldPalette.TIME_DAY)
	clock.advance(60.0, null)
	assert_eq(clock.time_of_day(), Gen2WorldPalette.TIME_NIGHT)
	assert_eq(clock.day, 6)
	clock.advance(6.0 * 60.0 * 60.0, null)
	assert_eq(clock.hour, 0)
	assert_eq(clock.day, 0)
