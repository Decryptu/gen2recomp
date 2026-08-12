extends GutTest

const Decoder := preload("res://game/audio/gen2_audio_decoder.gd")
const Renderer := preload("res://game/audio/gen2_audio_renderer.gd")

## The decoder tests use the source stream grammar directly. They verify the
## details that are easy to lose when turning banked bytes into playback
## events: packed channel headers, note timing, loop pointers and cry notes.


func test_music_header_and_note_duration_follow_the_cartridge_math() -> void:
	var record := {
		"address": 0x4000,
		"bytes": [
			0x00, 0x03, 0x40,
			0xD4, 0xD8, 0x02, 0xF1, 0x12, 0x20, 0xFF,
		],
	}
	var decoded: Dictionary = Decoder.decode(record)
	assert_true(decoded["ok"])
	assert_eq(decoded["tracks"].size(), 1)
	var track: Dictionary = decoded["tracks"][0]
	assert_eq(track["channel"], 1)
	assert_eq(track["events"].size(), 2)
	assert_eq(track["events"][0]["start_frame"], 0)
	assert_eq(track["events"][0]["duration_frames"], 6)
	assert_eq(track["events"][1]["start_frame"], 6)
	assert_eq(track["events"][1]["duration_frames"], 2)
	assert_eq(track["end_frame"], 8)
	assert_gt(track["events"][0]["frequency"], 0)


func test_counted_loop_jumps_to_the_source_pointer_and_then_exits() -> void:
	var record := {
		"address": 0x4000,
		"bytes": [
			0x00, 0x03, 0x40,
			0xD8, 0x01, 0xF1, 0x10,
			0xFD, 0x02, 0x06, 0x40, 0x20, 0xFF,
		],
	}
	var decoded: Dictionary = Decoder.decode(record)
	assert_true(decoded["ok"])
	var events: Array = decoded["tracks"][0]["events"]
	assert_eq(events.size(), 4)
	assert_eq(events[0]["start_frame"], 0)
	assert_eq(events[1]["start_frame"], 1)
	assert_eq(events[2]["start_frame"], 2)
	assert_eq(events[3]["start_frame"], 3)
	assert_eq(decoded["duration_frames"], 4)
	assert_false(decoded["looped"])


func test_sfx_starts_in_fixed_mode_then_toggle_sfx_restores_music_notes() -> void:
	var record := {
		"address": 0x4000,
		"bytes": [
			0x00, 0x03, 0x40,
			0xDF, 0xD8, 0x01, 0xF1, 0x11, 0xFF,
		],
	}
	var decoded: Dictionary = Decoder.decode(record, &"sound")
	assert_true(decoded["ok"])
	assert_eq(decoded["tracks"][0]["events"].size(), 1)
	assert_eq(decoded["tracks"][0]["events"][0]["duration_frames"], 2)


func test_sfx_priority_commands_are_carried_on_source_events() -> void:
	var record := {
		"address": 0x4000,
		"bytes": [
			0x00, 0x03, 0x40,
			0xD4, 0xD8, 0x01, 0xF1, 0xEC, 0x11,
			0xED, 0x11, 0xFF,
		],
	}
	var decoded: Dictionary = Decoder.decode(record)
	assert_true(decoded["ok"])
	assert_true(decoded["tracks"][0]["events"][0]["sfx_priority"])
	assert_false(decoded["tracks"][0]["events"][1]["sfx_priority"])


func test_cry_header_runs_commands_before_square_and_noise_notes() -> void:
	var record := {
		"address": 0x7000,
		"bytes": [
			0x44, 0x06, 0x70, 0x07, 0x0D, 0x70,
			0xDE, 0x1B, 1, 0xF8, 0x20, 0x03, 0xFF,
			2, 0xA1, 0x6C, 0xFF,
		],
	}
	var decoded: Dictionary = Decoder.decode(record, &"cry")
	assert_true(decoded["ok"])
	assert_eq(decoded["tracks"].size(), 2)
	assert_eq(decoded["tracks"][0]["hardware_channel"], 1)
	assert_eq(decoded["tracks"][0]["events"][0]["frequency"], 0x0320)
	assert_eq(decoded["tracks"][0]["events"][0]["duration_frames"], 2)
	assert_eq(decoded["tracks"][1]["hardware_channel"], 4)
	assert_true(decoded["tracks"][1]["events"][0]["noise"])
	assert_eq(decoded["duration_frames"], 3)


## `_PlayCry`'s two parameters, which `PlayCry` reads out of `PokemonCries`
## before it: the pitch offset lands on the note frequency and the length is the
## channel tempo `SetNoteDuration` multiplies by.
func test_a_cry_takes_its_pitch_and_length_from_the_species_row() -> void:
	var record := {
		"address": 0x7000,
		"cry_pitch": 0x20,
		"cry_length": 0x200,
		"bytes": [
			0x44, 0x06, 0x70, 0x07, 0x0D, 0x70,
			0xDE, 0x1B, 1, 0xF8, 0x20, 0x03, 0xFF,
			2, 0xA1, 0x6C, 0xFF,
		],
	}
	var decoded: Dictionary = Decoder.decode(record, &"cry")
	assert_true(decoded["ok"])
	var note: Dictionary = decoded["tracks"][0]["events"][0]
	assert_eq(note["frequency"], 0x0320 + 0x20)
	# Twice the neutral $100 tempo is twice the length.
	assert_eq(note["duration_frames"], 4)
	# `_PlayCry` writes no tempo for CHAN4, so the noise track keeps its own.
	assert_eq(decoded["tracks"][1]["events"][0]["duration_frames"], 3)


## `rAUDxHIGH` keeps three frequency bits, so a sum past $7ff wraps rather than
## clipping. Bulbasaur's own 128 takes its first notes over.
func test_a_cry_pitch_past_eleven_bits_wraps_the_way_the_register_does() -> void:
	var record := {
		"address": 0x7000,
		"cry_pitch": 128,
		"bytes": [
			0x04, 0x03, 0x70,
			1, 0xF8, 0xC0, 0x07, 0xFF,
		],
	}
	var decoded: Dictionary = Decoder.decode(record, &"cry")
	assert_true(decoded["ok"])
	assert_eq(decoded["tracks"][0]["events"][0]["frequency"], (0x07C0 + 128) & 0x7FF)


func test_truncated_audio_is_refused_with_a_structured_reason() -> void:
	var decoded: Dictionary = Decoder.decode({"bytes": [0x00, 0x00]})
	assert_false(decoded["ok"])
	assert_eq(decoded["reason"], &"audio_record_truncated")


func test_renderer_builds_a_playable_stream_from_decoded_events() -> void:
	var decoded: Dictionary = {
		"ok": true,
		"duration_frames": 2,
		"looped": false,
		"tracks": [{
			"events": [{
				"start_frame": 0, "duration_frames": 2, "pitch": 1,
				"hardware_channel": 1, "frequency": 1000, "volume": 15, "duty": 2,
			}],
		}],
	}
	var rendered: Dictionary = Renderer.render(decoded)
	assert_true(rendered["ok"])
	assert_not_null(rendered["stream"])
	assert_eq(rendered["stream"].data.size(), 2 * Renderer.SAMPLE_RATE * 4 / 60)
	assert_ne(rendered["stream"].data[0], 0)
	assert_false(rendered["stream"].loop_mode == AudioStreamWAV.LOOP_FORWARD)


func test_renderer_resets_the_oscillator_phase_at_each_source_note() -> void:
	var decoded: Dictionary = {
		"ok": true,
		"duration_frames": 2,
		"looped": false,
		"tracks": [{
			"events": [
				{"start_frame": 0, "duration_frames": 1, "pitch": 1,
					"hardware_channel": 1, "frequency": 997, "envelope": 0xF0, "duty": 2},
				{"start_frame": 1, "duration_frames": 1, "pitch": 1,
					"hardware_channel": 1, "frequency": 997, "envelope": 0xF0, "duty": 2},
			],
		}],
	}
	var rendered: Dictionary = Renderer.render(decoded)
	assert_true(rendered["ok"])
	var data: PackedByteArray = rendered["stream"].data
	var first: int = _sample(data, 0)
	var second: int = _sample(data, Renderer.SAMPLE_RATE / 60)
	assert_eq(second, first, "a new note retriggers the channel phase")


func test_pitch_offset_vibrato_and_pitch_slide_are_carried_on_music_events() -> void:
	var record := {
		"address": 0x4000,
		"bytes": [
			0x00, 0x03, 0x40,
			0xE6, 0x00, 0x02, 0xE1, 0x01, 0x24,
			0xE0, 0x01, 0x34, 0xD4, 0xD8, 0x01, 0xF1, 0x11, 0xFF,
		],
	}
	var decoded: Dictionary = Decoder.decode(record)
	assert_true(decoded["ok"], JSON.stringify(decoded))
	var note: Dictionary = decoded["tracks"][0]["events"][0]
	assert_eq(note["pitch_offset"], 2)
	assert_eq(note["frequency"], (Decoder.FREQUENCY_TABLE[1] >> 3 & 0x7FF) + 2)
	assert_eq(note["vibrato"]["delay_frames"], 1)
	assert_eq(note["vibrato"]["extent"], 1)
	assert_eq(note["vibrato"]["rate"], 4)
	assert_true(note.has("pitch_slide_target"))
	assert_eq(note["pitch_slide_duration"], 2)


func test_renderer_exposes_bounded_chunk_buffers() -> void:
	var decoded: Dictionary = {
		"ok": true,
		"duration_frames": 120,
		"tracks": [{"events": [{
			"start_frame": 0, "duration_frames": 120, "pitch": 1,
			"hardware_channel": 1, "frequency": 1000, "envelope": 0xF0, "duty": 2,
		}]}],
	}
	var chunk: Dictionary = Renderer.render_chunk(decoded, 60, 4)
	assert_true(chunk["ok"])
	assert_eq(chunk["frame_count"], 4)
	assert_eq(chunk["buffer"].size(), 4 * Renderer.SAMPLE_RATE / 60)


func test_adjacent_music_chunks_keep_a_note_continuous() -> void:
	var decoded: Dictionary = {
		"ok": true,
		"duration_frames": 8,
		"tracks": [{"events": [{
			"start_frame": 0, "duration_frames": 8, "pitch": 1,
			"hardware_channel": 1, "frequency": 997, "envelope": 0xF0, "duty": 2,
		}]}],
	}
	var first: Dictionary = Renderer.render_chunk(decoded, 0, 4)
	var second: Dictionary = Renderer.render_chunk(decoded, 4, 4)
	assert_true(first["ok"])
	assert_true(second["ok"])
	var full: Dictionary = Renderer.render(decoded)
	var full_data: PackedByteArray = full["stream"].data
	var second_buffer: PackedVector2Array = second["buffer"]
	var second_first: int = int(roundf(second_buffer[0].x * 32768.0))
	assert_eq(second_first, _sample(full_data, 4 * Renderer.SAMPLE_RATE / 60))


func test_audio_exact_dmg_duty_patterns_are_not_thresholds() -> void:
	assert_eq(Renderer.duty_pattern(0), [0, 0, 0, 0, 0, 0, 0, 1])
	assert_eq(Renderer.duty_pattern(1), [1, 0, 0, 0, 0, 0, 0, 1])
	assert_eq(Renderer.duty_pattern(2), [1, 0, 0, 0, 0, 1, 1, 1])
	assert_eq(Renderer.duty_pattern(3), [0, 1, 1, 1, 1, 1, 1, 0])


func test_audio_register_conversion_uses_the_channel_three_divider() -> void:
	assert_almost_eq(Renderer.register_frequency(1000, 1), 125.0687022900763, 0.0000001)
	assert_almost_eq(Renderer.register_frequency(1000, 3), 62.53435114503815, 0.0000001)


func test_audio_wave_nibbles_are_unsigned_and_wave_level_can_mute() -> void:
	var decoded: Dictionary = {
		"ok": true, "duration_frames": 1, "tracks": [{"events": [{
			"start_frame": 0, "duration_frames": 1, "pitch": 1,
			"hardware_channel": 3, "frequency": 1000, "volume": 15,
			"wave_index": 0, "wave_level": 1,
		}]}],
	}
	var assets := {"wave_samples": {"bytes": [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
		0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]}}
	var audible: Dictionary = Renderer.render(decoded, assets)
	assert_gt(_sample(audible["stream"].data, 0), 0)
	(decoded["tracks"][0]["events"][0] as Dictionary)["wave_level"] = 0
	var muted: Dictionary = Renderer.render(decoded, assets)
	assert_eq(_sample(muted["stream"].data, 0), 0)


func test_audio_noise_lfsr_and_filter_state_match_across_chunks() -> void:
	var decoded: Dictionary = {
		"ok": true, "duration_frames": 8, "tracks": [{"events": [{
			"start_frame": 0, "duration_frames": 8, "pitch": 1,
			"hardware_channel": 4, "frequency": 0x13, "volume": 15,
			"fade": 0,
		}]}],
	}
	var full: Dictionary = Renderer.render(decoded)
	var second: Dictionary = Renderer.render_chunk(decoded, 4, 4)
	var full_data: PackedByteArray = full["stream"].data
	var second_data: PackedVector2Array = second["buffer"]
	for index: int in second_data.size():
		assert_eq(
			int(roundf(second_data[index].x * 32767.0)),
			_sample_signed(full_data, 4 * Renderer.SAMPLE_RATE / 60 + index),
			"noise chunk state at sample %d" % index,
		)


func _sample(data: PackedByteArray, index: int) -> int:
	var at: int = index * 4
	return data[at] | (data[at + 1] << 8)


func _sample_signed(data: PackedByteArray, index: int) -> int:
	var value: int = _sample(data, index)
	return value - 0x10000 if (value & 0x8000) != 0 else value
