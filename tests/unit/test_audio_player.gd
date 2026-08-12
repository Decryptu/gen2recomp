extends GutTest

## The player's own decisions, separate from decoding and rendering: which
## requests restart music, and how many rendered tracks it is willing to keep.

const Player := preload("res://game/audio/gen2_audio_player.gd")

var _player: Gen2AudioPlayer = null


func before_each() -> void:
	_player = Player.new()
	add_child_autofree(_player)


## One short playable track. The bytes are the decoder's own fixture grammar:
## one channel header, a note, and a terminator. Only the bank varies between
## records, because the header's pointer is resolved against the address.
func _record(bank: int, address: int = 0x4000) -> Dictionary:
	return {
		"bank": bank,
		"address": address,
		"bytes": [
			0x00, 0x03, 0x40,
			0xD4, 0xD8, 0x02, 0xF1, 0x12, 0x20, 0xFF,
		],
	}


func _loop_record(bank: int) -> Dictionary:
	return {
		"bank": bank,
		"address": 0x4000,
		"bytes": [
			0x00, 0x03, 0x40,
			0xD8, 0x01, 0xF1, 0x11,
			0xFC, 0x03, 0x40,
		],
	}


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
	var other: Dictionary = _player.play_record(_record(3), &"map_music")
	assert_true(other["played"])


func test_the_source_restart_special_starts_the_same_track_again() -> void:
	assert_true(_player.play_record(_record(2), &"map_music")["played"])
	# RestartMapMusic exists to override the rule above, so it has to.
	var restarted: Dictionary = _player.play_record(
		_record(2), &"map_music", {}, true
	)
	assert_true(restarted["played"])


func test_kept_music_streams_are_bounded_and_never_drop_what_is_playing() -> void:
	for index: int in Player.MUSIC_CACHE_LIMIT + 3:
		assert_true(_player.play_record(_record(index), &"map_music")["ok"])
	assert_lt(_player.cached_music_count(), Player.MUSIC_CACHE_LIMIT + 1)

	# The track still playing is the one a further request must not have to
	# render again, so it has to have survived the evictions.
	var current: Dictionary = _player.play_record(
		_record(Player.MUSIC_CACHE_LIMIT + 2), &"map_music"
	)
	assert_true(current["continued"])


func test_generator_refill_pushes_audio_within_its_output_capacity() -> void:
	var result: Dictionary = _player.play_record(_loop_record(99), &"map_music")
	assert_true(result["ok"])
	_player._service_timeline()
	var available: int = _player._music_playback.get_frames_available()
	var capacity: int = ceili(float(_player._music_generator.mix_rate) * _player._music_generator.buffer_length)
	assert_gt(available, 0)
	assert_lt(available, capacity)
