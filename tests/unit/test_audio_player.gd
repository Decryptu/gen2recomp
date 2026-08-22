extends GutTest

## The player's own decisions, separate from the driver: which requests restart
## music, which stop it, and that the generator keeps being fed.

const Player := preload("res://game/audio/gen2_audio_player.gd")

var _player: Gen2AudioPlayer = null


func before_each() -> void:
	_player = Player.new()
	add_child_autofree(_player)


## One looping channel stream, so a started track stays started.
func _record(bank: int, index: int = 1) -> Dictionary:
	return {
		"index": index,
		"bank": bank,
		"address": 0x4000,
		"data_address": 0x4000,
		"bytes": [
			0x00, 0x03, 0x40,
			0xD8, 0x10, 0xB1, 0xD4, 0x1F, 0xFC, 0x03, 0x40,
		],
	}


## The app block's two volumes are the game's, not only the launcher's: they are
## pushed to the driver's mix, where music and effects can still be told apart,
## and a host's own scale multiplies them.
func test_the_app_volumes_and_a_host_scale_reach_the_drivers_mix() -> void:
	var options: Gen2Options = Gen2OptionsStore.current()
	var music: int = options.music_volume
	var sfx: int = options.sfx_volume
	options.music_volume = Gen2Options.MAX_VOLUME
	options.sfx_volume = 0
	# Edited in place while the player runs, which is what the settings slider
	# does, so the level has to be read rather than taken once at startup.
	_player._apply_volume()
	var status: Dictionary = _player.audio_status()
	assert_almost_eq(float(status["music_gain"]), 1.0, 0.001)
	assert_almost_eq(float(status["sfx_gain"]), 0.0, 0.001)

	_player.volume_scale = 0.5
	assert_almost_eq(float(_player.audio_status()["music_gain"]), 0.5, 0.001)

	options.music_volume = music
	options.sfx_volume = sfx


func test_music_already_playing_is_continued_rather_than_started_again() -> void:
	var first: Dictionary = _player.play_record(_record(2), &"map_music")
	assert_true(first["ok"])
	assert_true(first["played"])

	# Two connected maps with the same header music are one continuous track on
	# the cartridge. Restarting it at each map edge is audible.
	var again: Dictionary = _player.play_record(_record(2), &"map_music")
	assert_true(again["ok"])
	assert_false(again["played"])
	assert_true(again["continued"])

	# A different track still replaces it.
	assert_true(_player.play_record(_record(3), &"map_music")["played"])


func test_the_source_restart_special_starts_the_same_track_again() -> void:
	assert_true(_player.play_record(_record(2), &"map_music")["played"])
	# RestartMapMusic exists to override the rule above, so it has to.
	assert_true(_player.play_record(_record(2), &"map_music", {}, true)["played"])


func test_music_none_stops_everything_the_way_init_sound_does() -> void:
	assert_true(_player.play_record(_record(2), &"map_music")["played"])
	assert_true(_player.audio_status()["music_active"])
	# `PlayMusic MUSIC_NONE` is `_InitSound`, not a stream.
	var stopped: Dictionary = _player.play_record(_record(2, 0), &"map_music")
	assert_true(stopped["stopped"])
	assert_false(_player.audio_status()["music_active"])


func test_an_effect_is_playing_until_its_stream_ends() -> void:
	var effect: Dictionary = {
		"index": 3,
		"bank": 9,
		"address": 0x4000,
		"data_address": 0x4000,
		"bytes": [0x40, 0x03, 0x40, 0xDF, 0xD8, 0x01, 0xB1, 0xD4, 0x10, 0xFF],
	}
	assert_true(_player.play_record(effect, &"sound")["played"])
	assert_true(_player.effect_playing())
	for _frame: int in 8:
		_player._engine.update_sound()
	assert_false(_player.effect_playing())


func test_generator_refill_pushes_audio_within_its_output_capacity() -> void:
	assert_true(_player.play_record(_record(99), &"map_music")["ok"])
	_player._service_timeline()
	var available: int = _player._playback.get_frames_available()
	var capacity: int = ceili(float(_player._generator.mix_rate) * _player._generator.buffer_length)
	assert_gt(available, 0)
	assert_lt(available, capacity)
	assert_lt(available, Gen2Apu.SAMPLES_PER_FRAME, "the buffer is filled a frame at a time")


func test_a_fade_walks_the_master_volume_down_and_then_stops() -> void:
	assert_true(_player.play_record(_record(2), &"map_music")["played"])
	assert_true(_player.fade_out(1))
	for _frame: int in 32:
		_player._engine.update_sound()
	assert_eq(_player.audio_status()["volume"], Gen2SoundEngine.MAX_VOLUME,
		"the fade ends in `_InitSound`, which restores full volume")
	assert_false(_player.audio_status()["music_active"])


## `PlayStereoCry` writes wCryTracks and puts 1 in wStereoPanningMask;
## `PlayMonCry2` zeroes both. Written per request, so one battler's side does not
## leak into the next cry.
func test_a_cry_takes_its_tracks_for_that_request_only() -> void:
	var cry: Dictionary = _record(2)
	cry["cry_pitch"] = 0
	cry["cry_length"] = 0
	_player.play_record(cry, &"cry", {}, false, 0xF0)
	assert_eq(_player._engine.cry_tracks, 0xF0)
	assert_eq(_player._engine.stereo_panning_mask, 1)

	_player.play_record(cry, &"cry")
	assert_eq(_player._engine.cry_tracks, 0, "the next cry is PlayMonCry2's")
	assert_eq(_player._engine.stereo_panning_mask, 0)


## `wLowHealthAlarm`'s DANGER_ON bit is what `PlayDanger` runs off; clearing it
## zeroes the byte whole, the way `StopDangerSound` does.
func test_the_low_health_alarm_is_the_danger_bit_and_its_timer() -> void:
	assert_false(_player.low_health_alarm())
	_player.set_low_health_alarm(true)
	assert_true(_player.low_health_alarm())
	assert_eq(_player._engine.low_health_alarm, 1 << Gen2SoundEngine.DANGER_ON_BIT)

	_player._engine.low_health_alarm |= 12
	_player.set_low_health_alarm(false)
	assert_eq(_player._engine.low_health_alarm, 0, "the timer went with it")
