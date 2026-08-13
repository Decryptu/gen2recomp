extends GutTest

## The cartridge driver's own decisions, watched through the registers it writes.
##
## Every fixture is a real channel stream: a three-byte header per channel, then
## commands from `macros/scripts/audio.asm`. Assertions are on hardware writes
## because that is the only thing the driver produces.

const NR11: int = 0xFF11
const NR12: int = 0xFF12
const NR13: int = 0xFF13
const NR14: int = 0xFF14
const NR21: int = 0xFF16
const NR23: int = 0xFF18
const NR32: int = 0xFF1C
const NR42: int = 0xFF21
const NR43: int = 0xFF22
const NR50: int = 0xFF24
const NR51: int = 0xFF25


## One record whose header sits at $4000 and whose channel streams follow it.
func _record(streams: Array, bank: int = 0x3B) -> Dictionary:
	var bytes: Array = []
	var header_size: int = streams.size() * 3
	var at: int = 0x4000 + header_size
	for index: int in streams.size():
		var channel_id: int = int((streams[index] as Array)[0])
		bytes.append(((streams.size() - 1) << 6) | channel_id if index == 0 else channel_id)
		bytes.append(at & 0xFF)
		bytes.append((at >> 8) & 0xFF)
		at += ((streams[index] as Array)[1] as Array).size()
	for stream: Array in streams:
		bytes.append_array(stream[1] as Array)
	return {
		"index": 1,
		"bank": bank,
		"address": 0x4000,
		"data_address": 0x4000,
		"bytes": bytes,
	}


func _engine(assets: Dictionary = {}) -> Gen2SoundEngine:
	var engine := Gen2SoundEngine.new()
	engine.set_assets(assets)
	engine.init_sound()
	engine.apu.tracing = true
	return engine


## Register writes as `[frame, address, value]`, ignoring the power-on and
## `_InitSound` traffic that precedes the first update.
func _writes(engine: Gen2SoundEngine, frames: int) -> Array:
	engine.apu.trace_lines = PackedStringArray()
	var out: Array = []
	for frame: int in frames:
		engine.apu.trace_frame = frame
		engine.update_sound()
	for line: String in engine.apu.trace_lines:
		var parts: PackedStringArray = line.split(" ")
		out.append([int(parts[0]), parts[1].hex_to_int(), parts[2].hex_to_int()])
	return out


func _values(writes: Array, address: int) -> Array:
	var out: Array = []
	for write: Array in writes:
		if int(write[1]) == address:
			out.append(int(write[2]))
	return out


func _frames_of(writes: Array, address: int) -> Array:
	var out: Array = []
	for write: Array in writes:
		if int(write[1]) == address:
			out.append(int(write[0]))
	return out


func test_note_duration_is_note_length_times_units_times_tempo() -> void:
	# note_type 8, 11, 1 / tempo $100 / note C_, 4 -> 8 * 4 * $100 >> 8 = 32.
	var engine: Gen2SoundEngine = _engine()
	assert_true(engine.play_music(_record([[0, [
		0xDA, 0x01, 0x00,
		0xD8, 0x08, 0xB1,
		0xD4,
		0x13,
		0xFF,
	]]])))
	var writes: Array = _writes(engine, 40)
	# One retrigger at frame 0 and nothing again until the note is over.
	assert_eq(_frames_of(writes, NR14), [0, 32], "one note of 32 frames, then the stream ends")


func test_tempo_reaches_every_channel_in_the_group() -> void:
	var engine: Gen2SoundEngine = _engine()
	assert_true(engine.play_music(_record([
		[0, [0xDA, 0x00, 0x80, 0xD8, 0x08, 0xB1, 0xD4, 0x13, 0xFF]],
		[1, [0xD8, 0x08, 0xB1, 0xD4, 0x13, 0xFF]],
	])))
	engine.update_sound()
	# `SetGlobalTempo` writes all four music channels, so the second channel's
	# note is half as long even though it never saw the command.
	assert_eq(engine.channels[0].tempo, 0x0080)
	assert_eq(engine.channels[1].tempo, 0x0080)
	assert_eq(engine.channels[2].tempo, 0x0080)
	assert_eq(engine.channels[3].tempo, 0x0080)


func test_counted_loop_runs_the_body_the_source_number_of_times() -> void:
	var engine: Gen2SoundEngine = _engine()
	# sound_loop 3, body: the body plays three notes in total.
	assert_true(engine.play_music(_record([[0, [
		0xD8, 0x01, 0xB1,
		0xD4,
		0x10,
		0xFD, 0x03, 0x03, 0x40,
		0xFF,
	]]])))
	var writes: Array = _writes(engine, 30)
	# `sound_loop 3` stores two and jumps while the count is non-zero, so the
	# body runs its first pass plus three more.
	assert_eq(_values(writes, NR14).size(), 4, "four passes, then the stream ends")


func test_duty_cycle_pattern_rotates_once_per_frame() -> void:
	var engine: Gen2SoundEngine = _engine()
	# duty_cycle_pattern 0, 1, 2, 3 held under one long note.
	assert_true(engine.play_music(_record([[0, [
		0xD8, 0x08, 0xB1,
		0xDE, 0x1B,
		0xD4,
		0x1F,
		0xFF,
	]]])))
	var writes: Array = _writes(engine, 6)
	var duties: Array = []
	for value: int in _values(writes, NR11):
		duties.append((value >> 6) & 0x03)
	# `HandleTrackVibrato` rotates the pattern on every `_UpdateSound`, not once
	# per note, so four frames walk the whole sequence and the fifth repeats it.
	assert_eq(duties.slice(0, 5), [0, 1, 2, 3, 0])


func test_vibrato_swings_up_by_the_rounded_half_and_down_by_the_floor() -> void:
	var engine: Gen2SoundEngine = _engine()
	# vibrato 0, 5, 1: extent 5 splits into 3 above and 2 below.
	assert_true(engine.play_music(_record([[0, [
		0xD8, 0x08, 0xB1,
		0xE1, 0x00, 0x51,
		0xD4,
		0x1F,
		0xFF,
	]]])))
	var writes: Array = _writes(engine, 6)
	assert_eq(engine.channels[0].vibrato_extent, 0x32, "high nibble up, low nibble down")
	var base: int = engine.channels[0].frequency & 0xFF
	var lows: Array = _values(writes, NR13)
	assert_eq(lows[0], base, "the note itself")
	assert_eq(lows[1], (base + 3) & 0xFF, "the first swing is up by the rounded half")
	assert_eq(lows[2], (base - 2) & 0xFF, "and the next is down by the floor")


func test_pitch_slide_step_is_the_quotient_the_cartridge_stores() -> void:
	var engine: Gen2SoundEngine = _engine()
	# One 128-frame note at octave 5 sliding down to octave 4 over 128 - 8.
	assert_true(engine.play_music(_record([[0, [
		0xD8, 0x08, 0xB1,
		0xD3,
		0xE0, 0x08, 0x41,
		0x1F,
		0xFF,
	]]])))
	engine.update_sound()
	var channel: Gen2SoundEngine.Channel = engine.channels[0]
	assert_true(channel.pitch_slide, "the slide is running")
	assert_eq(channel.pitch_slide_target, 0x705)
	assert_false(channel.pitch_slide_dir, "it slides down")
	# $782 to $705 is 125 over 120 frames. `.resume`'s repeated subtraction
	# counts its own borrowing pass, so the stored step is the quotient plus one
	# and the slide lands before the note ends.
	assert_eq(channel.pitch_slide_amount, 2)
	assert_eq(channel.pitch_slide_amount_fraction, 5)


func test_frequency_shifts_arithmetically_so_low_octaves_stay_low() -> void:
	var engine: Gen2SoundEngine = _engine()
	assert_true(engine.play_music(_record([[0, [
		0xD8, 0x10, 0xB1,
		0xD7,
		0x1F,
		0xFF,
	]]])))
	engine.update_sound()
	# `octave 1` is $d7, so CHANNEL_OCTAVE is 7 and `GetFrequency` shifts nothing.
	# A logical shift of $f82c would leave $02c and put the note an octave out.
	assert_eq(engine.channels[0].frequency, 0xF82C & 0x07FF)


func test_a_cry_adds_its_pitch_offset_once_per_frame_and_the_register_wraps()  -> void:
	var engine: Gen2SoundEngine = _engine()
	var record: Dictionary = _record([[4, [0x0F, 0xB1, 0x00, 0x07, 0xFF]]])
	record["cry_pitch"] = 0x80
	record["cry_length"] = 0x100
	assert_true(engine.play_cry(record))
	var writes: Array = _writes(engine, 2)
	# $700 + $80 is $780, still inside eleven bits.
	assert_eq(_values(writes, NR13)[0], 0x80)
	assert_eq(_values(writes, NR14)[0] & 0x07, 0x07)

	var over: Gen2SoundEngine = _engine()
	var wrapping: Dictionary = _record([[4, [0x0F, 0xB1, 0x00, 0x07, 0xFF]]], 0x3C)
	wrapping["cry_pitch"] = 0x180
	assert_true(over.play_cry(wrapping))
	var over_writes: Array = _writes(over, 2)
	# `rAUDxHIGH` keeps three frequency bits, so $880 reaches the register as
	# $080 and the note comes out low rather than clipped.
	assert_eq(_values(over_writes, NR14)[0] & 0x07, 0x00)


func test_an_effect_takes_the_music_channel_and_gives_it_back() -> void:
	var engine: Gen2SoundEngine = _engine()
	assert_true(engine.play_music(_record([[0, [
		0xD8, 0x10, 0xB1, 0xD4, 0x1F, 0xFC, 0x03, 0x40,
	]]], 0x3B)))
	engine.update_sound()
	assert_true(engine.channels[0].channel_on)

	# One short effect on CHAN5, which is the same hardware channel as CHAN1.
	assert_true(engine.play_sfx(_record([[4, [
		0xDF, 0xD8, 0x01, 0xB1, 0xD4, 0x10, 0xFF,
	]]], 0x3C)))
	var stolen: Array = _writes(engine, 1)
	assert_true(engine.channels[4].channel_on, "the effect owns channel 5")
	assert_gt(_values(stolen, NR12).size(), 0, "and it is the one writing channel 1")

	# The music channel stayed on underneath and takes the hardware back.
	assert_true(engine.channels[0].channel_on)
	var _drain: Array = _writes(engine, 6)
	assert_false(engine.channels[4].channel_on, "the effect ended")
	assert_true(engine.music_channels_active(), "the music never stopped")


func test_sfx_priority_rests_the_music_channels_while_an_effect_runs() -> void:
	var engine: Gen2SoundEngine = _engine()
	assert_true(engine.play_music(_record([[1, [
		0xD8, 0x10, 0xB1, 0xD4, 0x1F, 0xFC, 0x03, 0x40,
	]]], 0x3B)))
	engine.update_sound()
	# `sfx_priority_on` inside an effect mutes every music channel, which is what
	# a cry does through `_PlayCry`.
	assert_true(engine.play_sfx(_record([[4, [
		0xDF, 0xEC, 0xD8, 0x08, 0xB1, 0xD4, 0x10, 0xFF,
	]]], 0x3C)))
	var writes: Array = _writes(engine, 2)
	# A rested channel is cleared rather than left ringing, and `ClearChannel`
	# is the only thing that writes $08 to an envelope register.
	assert_true(_values(writes, 0xFF17).has(0x08), "channel 2 was cleared")
	assert_true(engine.music_channels_active(), "without turning the stream off")


func test_a_drum_note_on_an_effect_channel_uses_the_effect_noise_kit() -> void:
	# Two kits, each one pointer table of thirteen entries, then two samples.
	var drum_base: int = 0x4E52
	var bytes: Array = []
	bytes.resize(0x60)
	bytes.fill(0xFF)
	var kit0: int = drum_base + 0x10
	var kit1: int = drum_base + 0x30
	var sample0: int = drum_base + 0x50
	var sample1: int = drum_base + 0x56
	for entry: Array in [[0, kit0], [2, kit1]]:
		bytes[int(entry[0])] = int(entry[1]) & 0xFF
		bytes[int(entry[0]) + 1] = (int(entry[1]) >> 8) & 0xFF
	for entry: Array in [[kit0 - drum_base + 2, sample0], [kit1 - drum_base + 2, sample1]]:
		bytes[int(entry[0])] = int(entry[1]) & 0xFF
		bytes[int(entry[0]) + 1] = (int(entry[1]) >> 8) & 0xFF
	# noise_note 1, 12, 1, $33 and noise_note 1, 1, 1, $11.
	for entry: Array in [[sample0 - drum_base, [0x00, 0xC1, 0x33, 0xFF]],
			[sample1 - drum_base, [0x00, 0x11, 0x11, 0xFF]]]:
		var at: int = int(entry[0])
		for value: int in entry[1] as Array:
			bytes[at] = value
			at += 1
	var assets := {"drumkits": {"address": drum_base, "bytes": bytes}}

	var engine := Gen2SoundEngine.new()
	engine.set_assets(assets)
	engine.init_sound()
	engine.apu.tracing = true
	# `sfx_toggle_noise 1` on CHAN8 picks kit 1; `toggle_noise` would pick the
	# music kit, which is the register pair this distinguishes.
	assert_true(engine.play_sfx(_record([[7, [
		0xDF, 0xF0, 0x01, 0xD8, 0x0C, 0x1B, 0xFF,
	]]], 0x3C)))
	var writes: Array = _writes(engine, 2)
	assert_eq(_values(writes, NR42)[0], 0x11, "kit 1's sample, not kit 0's")
	assert_eq(_values(writes, NR43)[0], 0x11)


func test_volume_and_output_reach_the_mixer_registers_every_frame() -> void:
	var engine: Gen2SoundEngine = _engine()
	assert_true(engine.play_music(_record([[0, [
		0xE5, 0x77, 0xD8, 0x10, 0xB1, 0xD4, 0x1F, 0xFF,
	]]])))
	var writes: Array = _writes(engine, 3)
	assert_eq(_values(writes, NR50), [0x77, 0x77, 0x77], "wVolume lands on NR50")
	assert_eq(_values(writes, NR51)[0], 0x11, "channel 1 is on both outputs")


func test_stereo_panning_is_ignored_when_the_sound_option_is_mono() -> void:
	var mono: Gen2SoundEngine = _engine()
	mono.stereo = false
	var stream: Array = [[0, [0xEF, 0x10, 0xD8, 0x10, 0xB1, 0xD4, 0x1F, 0xFF]]]
	assert_true(mono.play_music(_record(stream)))
	assert_eq(_values(_writes(mono, 1), NR51)[0], 0x11, "both outputs stay on")

	var stereo: Gen2SoundEngine = _engine()
	stereo.stereo = true
	assert_true(stereo.play_music(_record(stream, 0x3C)))
	assert_eq(_values(_writes(stereo, 1), NR51)[0], 0x10, "left only")


func test_a_record_with_no_bytes_is_refused() -> void:
	var engine: Gen2SoundEngine = _engine()
	assert_false(engine.play_music({"index": 1, "bank": 0x3B, "address": 0x4000, "bytes": []}))
	assert_false(engine.play_music({}))


func test_a_fade_steps_the_master_volume_and_then_restarts_the_driver() -> void:
	var engine: Gen2SoundEngine = _engine()
	var playing: Dictionary = _record([[0, [0xD8, 0x08, 0xB1, 0xD4, 0x1F, 0xFC, 0x03, 0x40]]])
	assert_true(engine.play_music(playing))
	# Two frames per volume level, from $77 down to nothing.
	engine.start_fade(2)
	var writes: Array = _writes(engine, 40)
	var levels: Array = []
	for value: int in _values(writes, NR50):
		if levels.is_empty() or int(levels[levels.size() - 1]) != value:
			levels.append(value)
	# `FadeMusic` runs before the NR50 write and its count starts at zero, so the
	# first frame of a fade is already a level down.
	assert_eq(levels.slice(0, 4), [0x66, 0x55, 0x44, 0x33], "one level every other frame")
	# The fade ends in `_InitSound`, which stops the song and restores volume.
	assert_false(engine.music_channels_active())
	assert_eq(engine.volume, Gen2SoundEngine.MAX_VOLUME)
	assert_eq(engine.music_fade, 0)


func test_a_fade_can_hand_over_to_the_song_queued_behind_it() -> void:
	var engine: Gen2SoundEngine = _engine()
	assert_true(engine.play_music(_record([[0, [0xD8, 0x08, 0xB1, 0xD4, 0x1F, 0xFC, 0x03, 0x40]]])))
	var queued: Dictionary = _record([[1, [0xD8, 0x08, 0xB1, 0xD4, 0x1F, 0xFC, 0x03, 0x40]]], 0x3C)
	engine.start_fade(1, queued)
	for _frame: int in 40:
		engine.update_sound()
	# `wMusicFadeID` survives the restart, so the new song is playing and it is
	# the one the fade named, on its own channel.
	assert_true(engine.music_channels_active())
	assert_false(engine.channels[0].channel_on)
	assert_true(engine.channels[1].channel_on)
	assert_eq(engine.music_fade, 0)
