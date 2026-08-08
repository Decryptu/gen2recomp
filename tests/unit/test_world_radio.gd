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
