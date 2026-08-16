extends GutTest

## The Pokegear radio card's tuning table and the music a station commits.
##
## The load-bearing part is the Poke Flute channel: it is the only way anything
## other than a map's own track reaches `wMapMusic`, and `SnorlaxAwake` reads
## that byte. Everything else here exists so the three profile splits in
## RadioChannels stay honest, since Gold and Silver ship no Buena's Password
## channel and check the EXPN card on one Kanto station rather than three.

## Landmarks the rules turn on (constants/landmark_constants.asm), Crystal side.
const LANDMARK_NEW_BARK_TOWN: int = 1
const LANDMARK_RUINS_OF_ALPH: int = 9
const LANDMARK_LAKE_OF_RAGE: int = 38
const LANDMARK_VERMILION_CITY: int = 61
const LANDMARK_FAST_SHIP: int = 95

const KNOB_POKE_FLUTE: int = 78
const KNOB_BUENAS: int = 40
const KNOB_PLACES: int = 64
const KNOB_TALK: int = 16


func _kanto(overrides: Dictionary = {}) -> Dictionary:
	var context: Dictionary = {
		"landmark": LANDMARK_VERMILION_CITY, "crystal": true, "expn_card": true,
	}
	context.merge(overrides, true)
	return context


func _johto(overrides: Dictionary = {}) -> Dictionary:
	var context: Dictionary = {
		"landmark": LANDMARK_NEW_BARK_TOWN, "crystal": true, "expn_card": true,
	}
	context.merge(overrides, true)
	return context


func test_the_dial_is_the_sources_own_two_step_knob() -> void:
	var values: Array[int] = Gen2WorldRadio.knob_values()
	assert_eq(values.front(), 0, "the dial starts at zero")
	assert_eq(values.back(), Gen2WorldRadio.KNOB_MAX, "and is capped at 80")
	assert_eq(values.size(), 41, "two at a time")
	# The table's own comment: frequency value = 4 x ingame_frequency - 2.
	assert_almost_eq(Gen2WorldRadio.frequency_for(KNOB_POKE_FLUTE), 20.0, 0.001,
		"the Poke Flute channel is 20.0")
	assert_almost_eq(Gen2WorldRadio.frequency_for(KNOB_TALK), 4.5, 0.001,
		"and Oak's Talk 04.5")


func test_the_poke_flute_channel_needs_kanto_and_the_expn_card() -> void:
	var tuned: Dictionary = Gen2WorldRadio.station_for(KNOB_POKE_FLUTE, _kanto())
	assert_true(bool(tuned.get("ok", false)), "Kanto with the EXPN card answers")
	assert_eq(int(tuned.get("channel", -1)), Gen2WorldRadio.POKE_FLUTE_RADIO)
	assert_eq(int(tuned.get("music", -1)), Gen2WorldRadio.MUSIC_POKE_FLUTE_CHANNEL,
		"RadioChannelSongs puts MUSIC_POKE_FLUTE_CHANNEL on it")
	assert_eq(String(tuned.get("name", "")), "# FLUTE")

	assert_false(
		bool(Gen2WorldRadio.station_for(
			KNOB_POKE_FLUTE, _kanto({"expn_card": false})
		).get("ok", false)),
		"without the EXPN card it is dead air"
	)
	assert_false(
		bool(Gen2WorldRadio.station_for(KNOB_POKE_FLUTE, _johto()).get("ok", false)),
		"and .InJohto refuses it in Johto"
	)


func test_the_fast_ship_counts_as_johto() -> void:
	# .InJohto tests LANDMARK_FAST_SHIP before it compares against KANTO_LANDMARK,
	# and the ship's own landmark is the highest one there is. Both values are
	# profile split, since Crystal's LANDMARK_BATTLE_TOWER shifts the whole run.
	assert_eq(Gen2WorldRadio.fast_ship_landmark(true), LANDMARK_FAST_SHIP)
	assert_eq(Gen2WorldRadio.fast_ship_landmark(false), LANDMARK_FAST_SHIP - 1)
	assert_false(Gen2WorldRadio.is_kanto_landmark(LANDMARK_FAST_SHIP, true))
	assert_false(Gen2WorldRadio.is_kanto_landmark(LANDMARK_FAST_SHIP - 1, false))
	assert_true(Gen2WorldRadio.is_kanto_landmark(LANDMARK_VERMILION_CITY, true))
	assert_true(Gen2WorldRadio.is_kanto_landmark(LANDMARK_VERMILION_CITY - 1, false),
		"Vermilion is one lower there too")


func test_gold_and_silver_carry_no_buenas_password_channel() -> void:
	assert_true(
		bool(Gen2WorldRadio.station_for(KNOB_BUENAS, _johto()).get("ok", false)),
		"Crystal has the channel on 10.5"
	)
	assert_false(
		bool(Gen2WorldRadio.station_for(KNOB_BUENAS, _johto({"crystal": false})).get("ok", false)),
		"Gold and Silver ship no row for it at all"
	)
	assert_eq(Gen2WorldRadio.channel_count(true), 11)
	assert_eq(Gen2WorldRadio.channel_count(false), 10)
	# Their own ids sit one lower from PLACES_AND_PEOPLE on.
	assert_eq(Gen2WorldRadio.raw_channel(Gen2WorldRadio.LUCKY_CHANNEL, false), 3)
	assert_eq(Gen2WorldRadio.raw_channel(Gen2WorldRadio.BUENAS_PASSWORD, false), -1)
	assert_eq(Gen2WorldRadio.raw_channel(Gen2WorldRadio.POKE_FLUTE_RADIO, false), 7)
	assert_eq(Gen2WorldRadio.raw_channel(Gen2WorldRadio.POKE_FLUTE_RADIO, true), 8)


func test_only_crystal_gates_places_and_people_on_the_expn_card() -> void:
	assert_true(
		bool(Gen2WorldRadio.station_for(KNOB_PLACES, _kanto()).get("ok", false)),
		"Crystal with the card"
	)
	assert_false(
		bool(Gen2WorldRadio.station_for(
			KNOB_PLACES, _kanto({"expn_card": false})
		).get("ok", false)),
		"Crystal without it"
	)
	assert_true(
		bool(Gen2WorldRadio.station_for(
			KNOB_PLACES, _kanto({"crystal": false, "expn_card": false})
		).get("ok", false)),
		"Gold and Silver check the region only on this station"
	)


func test_the_morning_swaps_oaks_talk_for_the_pokedex_show() -> void:
	var morning: Dictionary = Gen2WorldRadio.station_for(
		KNOB_TALK, _johto({"time_of_day": Gen2WorldRadio.TIME_MORNING})
	)
	assert_eq(int(morning.get("channel", -1)), Gen2WorldRadio.POKEDEX_SHOW)
	var day: Dictionary = Gen2WorldRadio.station_for(KNOB_TALK, _johto({"time_of_day": 1}))
	assert_eq(int(day.get("channel", -1)), Gen2WorldRadio.OAKS_POKEMON_TALK)


func test_the_rocket_takeover_overrides_every_johto_station_below_the_flute() -> void:
	var seized: Dictionary = Gen2WorldRadio.station_for(
		KNOB_TALK, _johto({"rockets_in_radio_tower": true})
	)
	assert_eq(int(seized.get("channel", -1)), Gen2WorldRadio.ROCKET_RADIO,
		"PlayRadioShow rewrites wCurRadioLine before it jumps")
	assert_eq(String(seized.get("name", "")), "Let's All Sing!",
		"LoadStation_RocketRadio really does reuse that name")
	# Kanto is exempt, and so is anything at or above the Poke Flute channel.
	var kanto: Dictionary = Gen2WorldRadio.station_for(
		KNOB_POKE_FLUTE, _kanto({"rockets_in_radio_tower": true})
	)
	assert_eq(int(kanto.get("channel", -1)), Gen2WorldRadio.POKE_FLUTE_RADIO)


func test_the_two_landmark_stations_answer_only_where_they_air() -> void:
	var unown: Dictionary = Gen2WorldRadio.station_for(
		52, _johto({"landmark": LANDMARK_RUINS_OF_ALPH})
	)
	assert_eq(int(unown.get("channel", -1)), Gen2WorldRadio.UNOWN_RADIO)
	assert_false(bool(Gen2WorldRadio.station_for(52, _johto()).get("ok", false)))

	var evolution: Dictionary = Gen2WorldRadio.station_for(
		80, _johto({"landmark": LANDMARK_LAKE_OF_RAGE, "rocket_signal": true})
	)
	assert_eq(int(evolution.get("channel", -1)), Gen2WorldRadio.EVOLUTION_RADIO)
	assert_false(
		bool(Gen2WorldRadio.station_for(
			80, _johto({"landmark": LANDMARK_LAKE_OF_RAGE})
		).get("ok", false)),
		"without STATUSFLAGS_ROCKET_SIGNAL_F there is no signal"
	)


func test_a_knob_position_between_stations_is_dead_air() -> void:
	var quiet: Dictionary = Gen2WorldRadio.station_for(30, _johto())
	assert_false(bool(quiet.get("ok", false)))
	assert_eq(StringName(quiet.get("reason", &"")), &"no_signal")
	assert_eq(int(quiet.get("music", 0)), -1, "and it names no track")


func test_every_channel_song_is_a_real_music_index() -> void:
	assert_eq(Gen2WorldRadio.CHANNEL_SONGS.size(), Gen2WorldRadio.NUM_RADIO_CHANNELS)
	for song: int in Gen2WorldRadio.CHANNEL_SONGS:
		assert_gt(song, 0, "MUSIC_NONE is not a station")


func test_the_state_snaps_the_knob_to_the_dial_and_survives_a_round_trip() -> void:
	var state := Gen2WorldState.new()
	assert_eq(state.map_music(), Gen2WorldState.MUSIC_NONE, "wMapMusic starts silent")
	state.set_radio_knob(79)
	assert_eq(state.radio_knob(), KNOB_POKE_FLUTE, "an odd value snaps down to the dial")
	state.set_radio_knob(999)
	assert_eq(state.radio_knob(), Gen2WorldRadio.KNOB_MAX, "and the top is clamped")
	state.set_radio_knob(KNOB_POKE_FLUTE)
	state.set_radio_channel(Gen2WorldRadio.POKE_FLUTE_RADIO)
	state.set_map_music(Gen2WorldRadio.MUSIC_POKE_FLUTE_CHANNEL)

	var restored: Gen2WorldState = Gen2WorldState.from_dict(state.to_dict())
	assert_eq(restored.map_music(), Gen2WorldRadio.MUSIC_POKE_FLUTE_CHANNEL)
	assert_eq(restored.radio_knob(), KNOB_POKE_FLUTE)
	assert_eq(restored.radio_channel(), Gen2WorldRadio.POKE_FLUTE_RADIO)


func test_a_state_written_before_the_radio_existed_needs_no_migration() -> void:
	var old: Dictionary = Gen2WorldState.new().to_dict()
	old.erase("map_music")
	old.erase("radio_knob")
	old.erase("radio_channel")
	var restored: Gen2WorldState = Gen2WorldState.from_dict(old)
	assert_eq(restored.map_music(), Gen2WorldState.MUSIC_NONE)
	assert_eq(restored.radio_knob(), Gen2WorldRadio.KNOB_MIN)
	assert_eq(restored.radio_channel(), -1)


func test_play_map_music_reports_only_a_real_change() -> void:
	var state := Gen2WorldState.new()
	assert_true(state.play_map_music(12), "the first track is a change")
	assert_false(state.play_map_music(12), "the same track does not restart")
	assert_true(state.play_map_music(13))
	assert_eq(state.map_music(), 13)


## The programme layer. The corpus sweep lives in `tools/checks/radio.gd`, which
## drives every segment on a real cache; what is worth pinning here is the box's
## own two-line behaviour and the four branches whose input is not a roll.

func _show(channel: int, context: Dictionary = {}) -> Gen2RadioShow:
	var random := RandomNumberGenerator.new()
	random.seed = 1
	var facts: Dictionary = {"crystal": true, "weekday": 0, "hour": 20}
	facts.merge(context, true)
	return Gen2RadioShow.start(null, channel, facts, random)


## Runs frames until a segment actually prints, rather than until the box moves:
## `RadioScroll` clears the bottom row a frame before the next line lands on it.
func _next_line(show: Gen2RadioShow) -> PackedStringArray:
	for _frame: int in Gen2RadioShow.LINE_FRAMES + 3:
		var before: StringName = show.segment()
		show.advance_frame()
		if before != Gen2RadioShow.SCROLL:
			return show.lines()
	return show.lines()


func test_the_first_line_lands_on_the_top_row_and_the_rest_scroll_up() -> void:
	var show: Gen2RadioShow = _show(Gen2WorldRadio.ROCKET_RADIO)
	assert_eq(
		_next_line(show), PackedStringArray(["… …Ahem, we are", ""]),
		"the first line printed is the top row and nothing has scrolled"
	)
	assert_eq(_next_line(show), PackedStringArray(["… …Ahem, we are", "TEAM ROCKET!"]))
	assert_eq(_next_line(show), PackedStringArray(["TEAM ROCKET!", "After three years"]))


func test_a_line_is_up_for_a_hundred_frames() -> void:
	var show: Gen2RadioShow = _show(Gen2WorldRadio.ROCKET_RADIO)
	show.advance_frame()
	assert_eq(show.lines()[0], "… …Ahem, we are")
	for _frame: int in Gen2RadioShow.LINE_FRAMES:
		assert_false(show.advance_frame(), "the box moved before its delay ran out")
	# Frame 101 is `RadioScroll` taking wNextRadioLine, which prints nothing;
	# the segment it took runs on the frame after it.
	assert_false(show.advance_frame())
	assert_eq(show.segment(), StringName("RocketRadio2"))
	assert_true(show.advance_frame(), "the next segment did not run on frame 102")


func test_the_three_music_only_stations_print_nothing_and_stop() -> void:
	for channel: int in [
		Gen2WorldRadio.POKE_FLUTE_RADIO, Gen2WorldRadio.UNOWN_RADIO,
		Gen2WorldRadio.EVOLUTION_RADIO,
	]:
		var show: Gen2RadioShow = _show(channel)
		show.advance_frame()
		assert_true(show.finished(), "channel %d kept talking" % channel)
		assert_eq(show.lines(), PackedStringArray(["", ""]))
		assert_eq(
			show.pending_music, Gen2WorldRadio.CHANNEL_SONGS[channel],
			"StartRadioStation did not commit channel %d's track" % channel
		)


func test_the_music_channel_picks_its_track_off_the_weekday() -> void:
	for weekday: int in 7:
		var show: Gen2RadioShow = _show(
			Gen2WorldRadio.POKEMON_MUSIC, {"weekday": weekday}
		)
		show.advance_frame()
		assert_eq(
			show.pending_music,
			Gen2RadioShow.MUSIC_POKEMON_MARCH if weekday % 2 == 0 \
				else Gen2RadioShow.MUSIC_POKEMON_LULLABY,
			"weekday %d took the wrong half of StartPokemonMusicChannel" % weekday
		)


func test_the_music_channel_says_its_three_lines_once_and_stops() -> void:
	var show: Gen2RadioShow = _show(Gen2WorldRadio.POKEMON_MUSIC, {"weekday": 1})
	var said: Array[String] = []
	for _frame: int in Gen2RadioShow.LINE_FRAMES * 10:
		if show.finished():
			break
		if show.advance_frame():
			said.append(show.lines()[1] if not show.lines()[1].is_empty() else show.lines()[0])
	assert_true(show.finished(), "BenFernMusic7's bare ret did not end the show")
	assert_eq(said[said.size() - 1], "#MON Lullaby!")


## `BuenasPasswordCheckTime` is a live reading, so the hour moving under a show
## already talking is what reaches the ten shutdown lines.
func test_midnight_takes_buena_off_the_air_mid_show() -> void:
	var show: Gen2RadioShow = _show(Gen2WorldRadio.BUENAS_PASSWORD, {"hour": 20})
	assert_eq(_next_line(show), PackedStringArray(["BUENA: BUENA here!", ""]))
	show.set_hour(0)
	var said: Array[String] = []
	for _frame: int in Gen2RadioShow.LINE_FRAMES * 20:
		if show.advance_frame():
			said.append(show.lines()[1])
	assert_true(
		said.has("have to shut down!"),
		"the midnight arm never ran: %s" % ", ".join(said.slice(0, 6))
	)


func test_buenas_password_is_rolled_once_a_day_and_kept() -> void:
	var show: Gen2RadioShow = _show(Gen2WorldRadio.BUENAS_PASSWORD, {"hour": 20})
	for _frame: int in Gen2RadioShow.LINE_FRAMES * 6:
		show.advance_frame()
	assert_true(show.buenas_password_today, "the daily flag was not set")
	var first: int = show.buenas_password
	assert_true(first >= 0 and (first & 0xF) < 3, "the low nybble is not a word index")
	assert_true(
		(first >> 4) < Gen2RadioShow.BUENA_PASSWORDS.size(),
		"the high nybble is not a category"
	)
	for _frame: int in Gen2RadioShow.LINE_FRAMES * 20:
		show.advance_frame()
	assert_eq(show.buenas_password, first, "a second pass rolled a new password")


func test_a_password_category_names_a_word_of_its_own_kind() -> void:
	assert_eq(
		Gen2RadioShow.password_words(null, (6 << 4) | 1), "CHERRYGROVE CITY",
		"the literal categories are read straight out of the table"
	)


## `PeoplePlaces4`'s list is walked from a label, so progress shortens it.
func test_the_hidden_people_list_shrinks_with_progress() -> void:
	var early: Array[int] = Gen2RadioShow.hidden_people(false, 0)
	var beaten: Array[int] = Gen2RadioShow.hidden_people(true, 0)
	var all_badges: Array[int] = Gen2RadioShow.hidden_people(true, 0xFF)
	assert_eq(early.size(), 18)
	assert_eq(beaten.size(), 13)
	assert_eq(all_badges.size(), 5)
	for class_number: int in all_badges:
		assert_true(class_number in early, "class %d stopped being hidden" % class_number)
