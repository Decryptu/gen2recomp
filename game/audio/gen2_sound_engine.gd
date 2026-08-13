class_name Gen2SoundEngine
extends RefCounted

## The cartridge sound driver, ported from `audio/engine.asm`.
##
## [method update_sound] is one `_UpdateSound`, which the cartridge runs once
## per LCD frame. It parses each of the eight channel streams and writes the
## hardware registers; [Gen2Apu] turns those writes into samples. Nothing here
## decides what a note sounds like, exactly as on the cartridge.
##
## Every audible behaviour that used to be approximated - vibrato, pitch slides,
## the rotating duty pattern, envelopes, the noise channel, sfx stealing music
## channels - is now the driver's own state machine running at its own rate.

const NUM_MUSIC_CHANNELS: int = 4
const NUM_CHANNELS: int = 8
const CHAN4: int = 3
const CHAN5: int = 4
const CHAN8: int = 7
## Bit set in wCurChannel for CHAN5-CHAN8.
const NOISE_CHAN_BIT: int = 2

const FIRST_MUSIC_COMMAND: int = 0xD0
const SOUND_RETURN: int = 0xFF
const MAX_VOLUME: int = 0x77
const VOLUME_LEVEL_MASK: int = 0x07
const MUSIC_FADE_IN_BIT: int = 7
const DANGER_ON_BIT: int = 7
const MAX_PARSE_STEPS: int = 4096

const RAUD_BASE: Array = [0xFF10, 0xFF15, 0xFF1A, 0xFF1F]
const RNR50: int = 0xFF24
const RNR51: int = 0xFF25
const RNR52: int = 0xFF26
const RWAVE: int = 0xFF30

## `audio/notes.asm`. Register values the cartridge shifts down per octave, not
## a derived scale: entry 16 is $0100 rather than $00ff.
const FREQUENCY_TABLE: Array = [
	0x0000,
	0xF82C, 0xF89D, 0xF907, 0xF96B, 0xF9CA, 0xFA23,
	0xFA77, 0xFAC7, 0xFB12, 0xFB58, 0xFB9B, 0xFBDA,
	0xFC16, 0xFC4E, 0xFC83, 0xFCB5, 0xFCE5, 0xFD11,
	0xFD3B, 0xFD63, 0xFD89, 0xFDAC, 0xFDCD, 0xFDED,
]

## One `channel_struct`. Field names follow the CHANNEL_* members so a reader
## can hold the disassembly beside this.
class Channel:
	extends RefCounted

	var music_id: int = 0
	var music_bank: int = 0
	var music_address: int = 0
	var last_music_address: int = 0

	var channel_on: bool = false
	var subroutine: bool = false
	var looping: bool = false
	var sfx: bool = false
	var noise: bool = false
	var cry: bool = false

	var vibrato: bool = false
	var pitch_slide: bool = false
	var duty_loop: bool = false
	var pitch_offset_enabled: bool = false

	var vibrato_dir: bool = false
	var pitch_slide_dir: bool = false

	var duty_override: bool = false
	var freq_override: bool = false
	var pitch_sweep: bool = false
	var noise_sampling: bool = false
	var rest: bool = false
	var vibrato_override: bool = false

	var condition: int = 0
	var duty_cycle: int = 0
	var volume_envelope: int = 0
	var frequency: int = 0
	var pitch: int = 0
	var octave: int = 0
	var transposition: int = 0
	var note_duration: int = 0
	var note_duration_modifier: int = 0
	var loop_count: int = 0
	var tempo: int = 0x100
	var tracks: int = 0
	var duty_cycle_pattern: int = 0
	var vibrato_delay_count: int = 0
	var vibrato_delay: int = 0
	var vibrato_extent: int = 0
	var vibrato_rate: int = 0
	var pitch_slide_target: int = 0
	var pitch_slide_amount: int = 0
	var pitch_slide_amount_fraction: int = 0
	var field25: int = 0
	var pitch_offset: int = 0
	var note_length: int = 0

	## `ChannelInit`: clear the struct, then restore the two defaults it sets.
	func init() -> void:
		music_id = 0
		music_bank = 0
		music_address = 0
		last_music_address = 0
		channel_on = false
		subroutine = false
		looping = false
		sfx = false
		noise = false
		cry = false
		vibrato = false
		pitch_slide = false
		duty_loop = false
		pitch_offset_enabled = false
		vibrato_dir = false
		pitch_slide_dir = false
		clear_note_flags()
		condition = 0
		duty_cycle = 0
		volume_envelope = 0
		frequency = 0
		pitch = 0
		octave = 0
		transposition = 0
		note_duration = 0
		note_duration_modifier = 0
		loop_count = 0
		tracks = 0
		duty_cycle_pattern = 0
		vibrato_delay_count = 0
		vibrato_delay = 0
		vibrato_extent = 0
		vibrato_rate = 0
		pitch_slide_target = 0
		pitch_slide_amount = 0
		pitch_slide_amount_fraction = 0
		field25 = 0
		pitch_offset = 0
		tempo = 0x100
		note_length = 1

	func clear_note_flags() -> void:
		duty_override = false
		freq_override = false
		pitch_sweep = false
		noise_sampling = false
		rest = false
		vibrato_override = false


var apu: Gen2Apu = null

var channels: Array[Channel] = []
var music_playing: bool = false
var stereo: bool = false

var volume: int = 0
var last_volume: int = 0
var sound_output: int = 0
var sfx_priority: int = 0
var pitch_sweep_value: int = 0
var low_health_alarm: int = 0

var music_fade: int = 0
var music_fade_count: int = 0
var music_fade_record: Dictionary = {}

var cry_pitch: int = 0
var cry_length: int = 0
var cry_tracks: int = 0
var stereo_panning_mask: int = 0

var _cur_channel: int = 0
var _cur_track_duty: int = 0
var _cur_track_volume_envelope: int = 0
var _cur_track_frequency: int = 0
var _cur_music_byte: int = 0
var _cur_note_duration: int = 0
var _music_id: int = 0
var _music_bank: int = 0
var _noise_sample_address: int = 0
var _noise_sample_delay: int = 0
var _music_noise_sample_set: int = 0
var _sfx_noise_sample_set: int = 0
var _channel_jump_condition: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])

var _banks: Dictionary = {}
var _wave_samples: PackedByteArray = PackedByteArray()
var _drumkits: PackedByteArray = PackedByteArray()
var _drumkits_address: int = 0


func _init(shared_apu: Gen2Apu = null) -> void:
	apu = shared_apu if shared_apu != null else Gen2Apu.new()
	channels.resize(NUM_CHANNELS)
	for index: int in NUM_CHANNELS:
		channels[index] = Channel.new()


## Wave samples and drum kits, as read out of the cartridge by the importer.
func set_assets(assets: Dictionary) -> void:
	var wave: Dictionary = assets.get("wave_samples", {})
	_wave_samples = _to_bytes(wave.get("bytes", []))
	var drums: Dictionary = assets.get("drumkits", {})
	_drumkits = _to_bytes(drums.get("bytes", []))
	_drumkits_address = int(drums.get("address", 0))


## An imported record carries the whole ROM bank its stream lives in, so one
## registration serves every song, effect and cry in that bank.
func register_record(record: Dictionary) -> bool:
	var bank: int = int(record.get("bank", -1))
	if bank < 0:
		return false
	if _banks.has(bank):
		return true
	var bytes: PackedByteArray = _to_bytes(record.get("bytes", []))
	if bytes.is_empty():
		return false
	_banks[bank] = {
		"bytes": bytes,
		"origin": int(record.get("data_address", 0x4000)),
	}
	return true


func registered_bank_count() -> int:
	return _banks.size()


# ---------------------------------------------------------------- entry points


## `_InitSound`.
func init_sound() -> void:
	music_off()
	apu.write(0xFF24, 0)
	apu.write(0xFF25, 0)
	apu.write(0xFF26, 0x80)
	for index: int in NUM_MUSIC_CHANNELS:
		_clear_channel(RAUD_BASE[index])
	# `_InitSound` zero-fills wAudio rather than calling `ChannelInit`, so the
	# tempo and note-length defaults a loaded channel gets are not set here.
	for channel: Channel in channels:
		channel.init()
		channel.tempo = 0
		channel.note_length = 0
	last_volume = 0
	sound_output = 0
	sfx_priority = 0
	pitch_sweep_value = 0
	low_health_alarm = 0
	music_fade = 0
	music_fade_count = 0
	music_fade_record = {}
	cry_pitch = 0
	cry_length = 0
	cry_tracks = 0
	stereo_panning_mask = 0
	_cur_track_duty = 0
	_cur_track_volume_envelope = 0
	_cur_track_frequency = 0
	_cur_music_byte = 0
	_cur_note_duration = 0
	_noise_sample_address = 0
	_noise_sample_delay = 0
	_music_noise_sample_set = 0
	_sfx_noise_sample_set = 0
	_channel_jump_condition = PackedInt32Array([0, 0, 0, 0])
	volume = MAX_VOLUME
	music_on()


func music_on() -> void:
	music_playing = true


func music_off() -> void:
	music_playing = false


## `_PlayMusic`.
func play_music(record: Dictionary) -> bool:
	if not register_record(record):
		return false
	music_off()
	_music_id = int(record.get("index", 0))
	_music_bank = int(record.get("bank", 0))
	var address: int = int(record.get("address", 0))
	var count: int = ((_music_byte(_music_bank, address) >> 6) & 0x03) + 1
	for _channel: int in count:
		address = _load_channel(address)
		_start_channel()
	_channel_jump_condition = PackedInt32Array([0, 0, 0, 0])
	_noise_sample_address = 0
	_noise_sample_delay = 0
	_music_noise_sample_set = 0
	music_on()
	return true


## `_PlaySFX`, including the hardware clear each active sfx channel gets first.
func play_sfx(record: Dictionary) -> bool:
	if not register_record(record):
		return false
	music_off()
	if channels[CHAN5].channel_on:
		channels[CHAN5].channel_on = false
		apu.write(0xFF11, 0)
		apu.write(0xFF12, 0x08)
		apu.write(0xFF13, 0)
		apu.write(0xFF14, 0x80)
		pitch_sweep_value = 0
		apu.write(0xFF10, 0)
	if channels[CHAN5 + 1].channel_on:
		channels[CHAN5 + 1].channel_on = false
		apu.write(0xFF16, 0)
		apu.write(0xFF17, 0x08)
		apu.write(0xFF18, 0)
		apu.write(0xFF19, 0x80)
	if channels[CHAN5 + 2].channel_on:
		channels[CHAN5 + 2].channel_on = false
		apu.write(0xFF1A, 0)
		apu.write(0xFF1B, 0)
		apu.write(0xFF1C, 0x08)
		apu.write(0xFF1D, 0)
		apu.write(0xFF1E, 0x80)
	if channels[CHAN8].channel_on:
		channels[CHAN8].channel_on = false
		apu.write(0xFF20, 0)
		apu.write(0xFF21, 0x08)
		apu.write(0xFF22, 0)
		apu.write(0xFF23, 0x80)
		_noise_sample_address = 0
	_music_id = int(record.get("index", 0))
	_music_bank = int(record.get("bank", 0))
	var address: int = int(record.get("address", 0))
	var count: int = ((_music_byte(_music_bank, address) >> 6) & 0x03) + 1
	for _channel: int in count:
		address = _load_channel(address)
		channels[_cur_channel].sfx = true
		_start_channel()
	music_on()
	sfx_priority = 0
	return true


## `_PlayCry`. The record supplies the two `PokemonCries` parameters.
func play_cry(record: Dictionary) -> bool:
	if not register_record(record):
		return false
	music_off()
	_music_id = int(record.get("index", 0))
	_music_bank = int(record.get("bank", 0))
	cry_pitch = int(record.get("cry_pitch", cry_pitch))
	cry_length = int(record.get("cry_length", cry_length))
	var address: int = int(record.get("address", 0))
	var count: int = ((_music_byte(_music_bank, address) >> 6) & 0x03) + 1
	for _channel: int in count:
		address = _load_channel(address)
		var channel: Channel = channels[_cur_channel]
		channel.cry = true
		channel.pitch_offset_enabled = true
		channel.pitch_offset = cry_pitch & 0xFFFF
		if (_cur_channel & 0x03) < CHAN4:
			channel.tempo = cry_length & 0xFFFF
		_start_channel()
		if stereo_panning_mask != 0 and stereo:
			channel.tracks &= cry_tracks
	if last_volume == 0:
		last_volume = volume
		volume = MAX_VOLUME
	sfx_priority = 1
	music_on()
	return true


## `FadeMusic`'s entry conditions: a frame count per volume step, and the record
## to fade in once the fade out reaches zero.
func start_fade(frames: int, fade_in_record: Dictionary = {}) -> void:
	music_fade = frames & 0x3F
	music_fade_count = 0
	music_fade_record = fade_in_record


func music_channels_active() -> bool:
	for index: int in NUM_MUSIC_CHANNELS:
		if channels[index].channel_on:
			return true
	return false


## `_CheckSFX`.
func sfx_active() -> bool:
	for index: int in range(NUM_MUSIC_CHANNELS, NUM_CHANNELS):
		if channels[index].channel_on:
			return true
	return false


func any_channel_active() -> bool:
	return music_channels_active() or sfx_active()


# ------------------------------------------------------------------ per frame


## `_UpdateSound`.
func update_sound() -> void:
	if not music_playing:
		return
	sound_output = 0
	for index: int in NUM_CHANNELS:
		_cur_channel = index
		var channel: Channel = channels[index]
		if not channel.channel_on:
			continue
		if channel.note_duration < 2:
			channel.vibrato_delay_count = channel.vibrato_delay
			channel.pitch_slide = false
			_parse_music()
		else:
			channel.note_duration -= 1
		_apply_pitch_slide()
		_cur_track_duty = channel.duty_cycle
		_cur_track_volume_envelope = channel.volume_envelope
		_cur_track_frequency = channel.frequency
		_handle_track_vibrato()
		_handle_noise()
		if sfx_priority != 0 and index < NUM_MUSIC_CHANNELS and sfx_active():
			channel.rest = true
		if index >= NUM_MUSIC_CHANNELS or not channels[index + NUM_MUSIC_CHANNELS].channel_on:
			_update_channels()
			sound_output |= channel.tracks
		channel.clear_note_flags()
	_play_danger()
	_fade_music()
	apu.write(RNR50, volume)
	apu.write(RNR51, sound_output)


func _update_channels() -> void:
	match _cur_channel & 0x03:
		0:
			if _cur_channel == 0 and (low_health_alarm & (1 << DANGER_ON_BIT)) != 0:
				return
			_update_channel1()
		1:
			_update_channel2()
		2:
			_update_channel3()
		_:
			_update_channel4()


func _update_channel1() -> void:
	var channel: Channel = channels[_cur_channel]
	if channel.pitch_sweep:
		apu.write(0xFF10, pitch_sweep_value)
	if channel.rest:
		apu.write(RNR52, apu.read(RNR52) & 0b10001110)
		_clear_channel(0xFF10)
	elif channel.noise_sampling:
		apu.write(0xFF11, 0x3F | _cur_track_duty)
		apu.write(0xFF12, _cur_track_volume_envelope)
		apu.write(0xFF13, _cur_track_frequency & 0xFF)
		apu.write(0xFF14, ((_cur_track_frequency >> 8) & 0xFF) | 0x80)
	elif channel.freq_override:
		apu.write(0xFF13, _cur_track_frequency & 0xFF)
		apu.write(0xFF14, (_cur_track_frequency >> 8) & 0xFF)
		if channel.duty_override:
			apu.write(0xFF11, (apu.read(0xFF11) & 0x3F) | _cur_track_duty)
	elif channel.vibrato_override:
		apu.write(0xFF11, (apu.read(0xFF11) & 0x3F) | _cur_track_duty)
		apu.write(0xFF13, _cur_track_frequency & 0xFF)
	elif channel.duty_override:
		apu.write(0xFF11, (apu.read(0xFF11) & 0x3F) | _cur_track_duty)


func _update_channel2() -> void:
	var channel: Channel = channels[_cur_channel]
	if channel.rest:
		apu.write(RNR52, apu.read(RNR52) & 0b10001101)
		_clear_channel(0xFF15)
	elif channel.noise_sampling:
		apu.write(0xFF16, 0x3F | _cur_track_duty)
		apu.write(0xFF17, _cur_track_volume_envelope)
		apu.write(0xFF18, _cur_track_frequency & 0xFF)
		apu.write(0xFF19, ((_cur_track_frequency >> 8) & 0xFF) | 0x80)
	elif channel.vibrato_override:
		apu.write(0xFF16, (apu.read(0xFF16) & 0x3F) | _cur_track_duty)
		apu.write(0xFF18, _cur_track_frequency & 0xFF)
	elif channel.duty_override:
		apu.write(0xFF16, (apu.read(0xFF16) & 0x3F) | _cur_track_duty)


func _update_channel3() -> void:
	var channel: Channel = channels[_cur_channel]
	if channel.rest:
		apu.write(RNR52, apu.read(RNR52) & 0b10001011)
		_clear_channel(0xFF1A)
	elif channel.noise_sampling:
		apu.write(0xFF1B, 0x3F)
		apu.write(0xFF1A, 0)
		_load_wave_pattern()
		apu.write(0xFF1A, 0x80)
		apu.write(0xFF1D, _cur_track_frequency & 0xFF)
		apu.write(0xFF1E, ((_cur_track_frequency >> 8) & 0xFF) | 0x80)
	elif channel.vibrato_override:
		apu.write(0xFF1D, _cur_track_frequency & 0xFF)


func _update_channel4() -> void:
	var channel: Channel = channels[_cur_channel]
	if channel.rest:
		apu.write(RNR52, apu.read(RNR52) & 0b10000111)
		_clear_channel(0xFF1F)
	elif channel.noise_sampling:
		apu.write(0xFF20, 0x3F)
		apu.write(0xFF21, _cur_track_volume_envelope)
		apu.write(0xFF22, _cur_track_frequency & 0xFF)
		apu.write(0xFF23, 0x80)


## `.load_wave_pattern`: the envelope's low nibble picks the sample, its high
## nibble becomes the output level. Channel 3 has no volume envelope.
func _load_wave_pattern() -> void:
	var sample: int = (_cur_track_volume_envelope & 0x0F) << 4
	for index: int in 16:
		var at: int = sample + index
		apu.write(RWAVE + index, _wave_samples[at] if at < _wave_samples.size() else 0)
	apu.write(0xFF1C, (_cur_track_volume_envelope & 0xF0) << 1)


## `ClearChannel`: 00 00 08 00 80 over one channel's five registers.
func _clear_channel(base: int) -> void:
	apu.write(base, 0)
	apu.write(base + 1, 0)
	apu.write(base + 2, 0x08)
	apu.write(base + 3, 0)
	apu.write(base + 4, 0x80)


func _play_danger() -> void:
	if (low_health_alarm & (1 << DANGER_ON_BIT)) == 0:
		return
	var timer: int = low_health_alarm & ~(1 << DANGER_ON_BIT)
	if not sfx_active():
		var pitch: int = -1
		if timer == 0:
			pitch = 0x750
		elif timer == 16:
			pitch = 0x6EE
		if pitch >= 0:
			apu.write(0xFF10, 0)
			apu.write(0xFF11, 0x80)
			apu.write(0xFF12, 0xE2)
			apu.write(0xFF13, pitch & 0xFF)
			apu.write(0xFF14, ((pitch >> 8) & 0xFF) | 0x80)
	timer += 1
	if timer >= 30:
		timer = 0
	low_health_alarm = timer | (1 << DANGER_ON_BIT)
	if (sound_output & 0x11) == 0:
		sound_output |= 0x11


func _fade_music() -> void:
	if music_fade == 0:
		return
	if music_fade_count != 0:
		music_fade_count -= 1
		return
	music_fade_count = music_fade & 0x3F
	var level: int = volume & VOLUME_LEVEL_MASK
	if (music_fade & (1 << MUSIC_FADE_IN_BIT)) != 0:
		if level >= (MAX_VOLUME & 0x0F):
			music_fade = 0
			return
		level += 1
	else:
		if level == 0:
			volume = 0
			# `MusicFadeRestart` is `_InitSound` with the queued song carried
			# across the clear, which is the only reason it exists.
			var record: Dictionary = music_fade_record
			init_sound()
			if not record.is_empty():
				play_music(record)
			return
		level -= 1
	volume = (level << 4) | level


# ------------------------------------------------------------- note machinery


func _load_note() -> void:
	var channel: Channel = channels[_cur_channel]
	if not channel.pitch_slide:
		return
	var duration: int = channel.note_duration - _cur_note_duration
	if duration < 0:
		duration = 1
	_cur_note_duration = duration
	var difference: int = 0
	if channel.frequency >= channel.pitch_slide_target:
		channel.pitch_slide_dir = false
		difference = channel.frequency - channel.pitch_slide_target
	else:
		channel.pitch_slide_dir = true
		difference = channel.pitch_slide_target - channel.frequency
	# `.resume`'s repeated-subtraction loop counts the borrowing pass too, so
	# the stored amount is the quotient plus one and a slide arrives early.
	var quotient: int = 0
	var high: int = (difference >> 8) & 0xFF
	var low: int = difference & 0xFF
	var divisor: int = _cur_note_duration & 0xFF
	if divisor == 0:
		# The cartridge subtracts forever here and locks the console up, so no
		# shipped stream reaches it. Leaving the slide flat is the safe read.
		channel.pitch_slide_amount = 0
		channel.pitch_slide_amount_fraction = 0
		channel.field25 = 0
		return
	while true:
		quotient += 1
		low -= divisor
		if low >= 0:
			continue
		if high == 0:
			break
		high -= 1
		low &= 0xFF
	channel.pitch_slide_amount = quotient & 0xFF
	channel.pitch_slide_amount_fraction = (low + divisor) & 0xFF
	channel.field25 = 0


func _handle_track_vibrato() -> void:
	var channel: Channel = channels[_cur_channel]
	if channel.duty_loop:
		channel.duty_cycle_pattern = ((channel.duty_cycle_pattern << 2)
			| (channel.duty_cycle_pattern >> 6)) & 0xFF
		_cur_track_duty = channel.duty_cycle_pattern & 0xC0
		channel.duty_override = true
	if channel.pitch_offset_enabled:
		_cur_track_frequency = (_cur_track_frequency + channel.pitch_offset) & 0xFFFF
	if not channel.vibrato:
		return
	if channel.vibrato_delay_count != 0:
		channel.vibrato_delay_count -= 1
		return
	if channel.vibrato_extent == 0:
		return
	if (channel.vibrato_rate & 0x0F) != 0:
		channel.vibrato_rate -= 1
		return
	channel.vibrato_rate |= channel.vibrato_rate >> 4
	var low: int = _cur_track_frequency & 0xFF
	channel.vibrato_dir = not channel.vibrato_dir
	if channel.vibrato_dir:
		var above: int = (channel.vibrato_extent & 0xF0) >> 4
		low = 0xFF if low + above > 0xFF else low + above
	else:
		var below: int = channel.vibrato_extent & 0x0F
		low = 0 if below > low else low - below
	_cur_track_frequency = (_cur_track_frequency & 0xFF00) | low
	channel.vibrato_override = true


func _apply_pitch_slide() -> void:
	var channel: Channel = channels[_cur_channel]
	if not channel.pitch_slide:
		return
	var frequency: int = channel.frequency
	if channel.pitch_slide_dir:
		frequency += channel.pitch_slide_amount
		if channel.field25 + channel.pitch_slide_amount_fraction >= 0x100:
			frequency += 1
		channel.field25 = (channel.field25 + channel.pitch_slide_amount_fraction) & 0xFF
		frequency &= 0xFFFF
		if frequency > channel.pitch_slide_target:
			channel.pitch_slide = false
			channel.pitch_slide_dir = false
			return
	else:
		frequency -= channel.pitch_slide_amount
		if channel.field25 + channel.field25 >= 0x100:
			frequency -= 1
		channel.field25 = (channel.field25 + channel.field25) & 0xFF
		frequency &= 0xFFFF
		if frequency < channel.pitch_slide_target:
			channel.pitch_slide = false
			channel.pitch_slide_dir = false
			return
	channel.frequency = frequency
	channel.freq_override = true
	channel.duty_override = true


func _handle_noise() -> void:
	var channel: Channel = channels[_cur_channel]
	if not channel.noise:
		return
	if (_cur_channel & (1 << NOISE_CHAN_BIT)) == 0:
		if channels[CHAN8].channel_on and channels[CHAN8].noise:
			return
	if _noise_sample_delay != 0:
		_noise_sample_delay -= 1
		return
	_read_noise_sample()


func _read_noise_sample() -> void:
	if _noise_sample_address == 0:
		return
	var length: int = _drum_byte(_noise_sample_address)
	if length == SOUND_RETURN:
		return
	_noise_sample_delay = (length & 0x0F) + 1
	_cur_track_volume_envelope = _drum_byte(_noise_sample_address + 1)
	_cur_track_frequency = _drum_byte(_noise_sample_address + 2)
	_noise_sample_address = (_noise_sample_address + 3) & 0xFFFF
	channels[_cur_channel].noise_sampling = true


func _parse_music() -> void:
	var channel: Channel = channels[_cur_channel]
	# A stream that jumps without ever reaching a note hangs the cartridge.
	# Bounding it turns that into a silent channel instead of a frozen game.
	var steps: int = 0
	while true:
		steps += 1
		if steps > MAX_PARSE_STEPS:
			channel.channel_on = false
			channel.rest = true
			push_warning("Gen2SoundEngine: channel %d parsed %d commands without a note."
				% [_cur_channel, MAX_PARSE_STEPS])
			return
		var command: int = _get_music_byte()
		if command == SOUND_RETURN and not channel.subroutine:
			if _cur_channel >= NUM_MUSIC_CHANNELS \
				or not channels[_cur_channel + NUM_MUSIC_CHANNELS].channel_on:
				if channel.cry:
					_restore_volume()
				if _cur_channel == CHAN5:
					apu.write(0xFF10, 0)
			channel.channel_on = false
			channel.rest = true
			channel.music_id = 0
			channel.music_bank = 0
			return
		if command < FIRST_MUSIC_COMMAND:
			if channel.sfx or channel.cry:
				_parse_sfx_or_cry()
			elif channel.noise:
				_get_noise_sample()
			else:
				_set_note_duration(_cur_music_byte & 0x0F)
				var note: int = _cur_music_byte >> 4
				if note != 0:
					channel.pitch = note
					channel.frequency = _get_frequency(note, channel.octave)
					channel.noise_sampling = true
					_load_note()
				else:
					channel.rest = true
			return
		_parse_music_command(command)


func _restore_volume() -> void:
	if _cur_channel != CHAN5:
		return
	channels[CHAN5 + 1].pitch_offset = 0
	channels[CHAN8].pitch_offset = 0
	volume = last_volume
	last_volume = 0
	sfx_priority = 0


func _parse_sfx_or_cry() -> void:
	var channel: Channel = channels[_cur_channel]
	channel.noise_sampling = true
	_set_note_duration(_cur_music_byte)
	channel.volume_envelope = _get_music_byte()
	var frequency: int = _get_music_byte()
	if (_cur_channel & 0x03) != CHAN4:
		frequency |= _get_music_byte() << 8
	channel.frequency = frequency


func _get_noise_sample() -> void:
	if (_cur_channel & 0x03) != CHAN4:
		return
	_set_note_duration(_cur_music_byte & 0x0F)
	var kit: int = 0
	if (_cur_channel & (1 << NOISE_CHAN_BIT)) != 0:
		kit = _sfx_noise_sample_set
	else:
		if channels[CHAN8].channel_on:
			return
		kit = _music_noise_sample_set
	var note: int = _cur_music_byte >> 4
	if note == 0:
		return
	_noise_sample_address = _drum_sample_address(kit, note)
	_noise_sample_delay = 0


func _parse_music_command(command: int) -> void:
	var channel: Channel = channels[_cur_channel]
	match command:
		0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7:
			channel.octave = _cur_music_byte & 0x07
		0xD8:
			channel.note_length = _get_music_byte()
			if (_cur_channel & 0x03) != CHAN4:
				channel.volume_envelope = _get_music_byte()
		0xD9:
			channel.transposition = _get_music_byte()
		0xDA:
			# `bigdw`: the high byte is written first.
			var tempo: int = _get_music_byte() << 8
			tempo |= _get_music_byte()
			_set_global_tempo(tempo)
		0xDB:
			channel.duty_cycle = (_get_music_byte() << 6) & 0xFF
		0xDC:
			channel.volume_envelope = _get_music_byte()
		0xDD:
			pitch_sweep_value = _get_music_byte()
			channel.pitch_sweep = true
		0xDE:
			channel.duty_loop = true
			var pattern: int = _get_music_byte()
			channel.duty_cycle_pattern = ((pattern >> 2) | (pattern << 6)) & 0xFF
			channel.duty_cycle = channel.duty_cycle_pattern & 0xC0
		0xDF:
			channel.sfx = not channel.sfx
		0xE0:
			_cur_note_duration = _get_music_byte()
			var note: int = _get_music_byte()
			channel.pitch_slide_target = _get_frequency(note & 0x0F, note >> 4)
			channel.pitch_slide = true
		0xE1:
			channel.vibrato = true
			channel.vibrato_dir = false
			channel.vibrato_delay = _get_music_byte()
			channel.vibrato_delay_count = channel.vibrato_delay
			var shape: int = _get_music_byte()
			var extent: int = (shape & 0xF0) >> 4
			# The two halves are stored apart so the up swing rounds away from
			# zero and the down swing rounds toward it.
			channel.vibrato_extent = (((extent >> 1) + (extent & 1)) << 4) | (extent >> 1)
			var rate: int = shape & 0x0F
			channel.vibrato_rate = (rate << 4) | rate
		0xE2:
			var _unused_e2: int = _get_music_byte()
		0xE3:
			channel.noise = not channel.noise
			if channel.noise:
				_music_noise_sample_set = _get_music_byte()
		0xE4:
			_set_lr_tracks()
			channel.tracks &= _get_music_byte()
		0xE5:
			var level: int = _get_music_byte()
			if music_fade == 0:
				volume = level
		0xE6:
			# `bigdw`, like tempo.
			var offset: int = _get_music_byte() << 8
			offset |= _get_music_byte()
			channel.pitch_offset_enabled = true
			channel.pitch_offset = offset
		0xE7:
			var _unused_e7: int = _get_music_byte()
		0xE8:
			var _unused_e8: int = _get_music_byte()
		0xE9:
			var relative: int = _get_music_byte()
			if relative >= 0x80:
				relative -= 0x100
			_set_global_tempo((channel.tempo + relative) & 0xFFFF)
		0xEA:
			var header: int = _get_music_byte()
			header |= _get_music_byte() << 8
			_music_id = channel.music_id
			_music_bank = channel.music_bank
			var entry: int = _music_byte(_music_bank, header)
			entry |= _music_byte(_music_bank, header + 1) << 8
			var saved: int = _cur_channel
			_load_channel(entry)
			_start_channel()
			_cur_channel = saved
		0xEB:
			# `Music_NewSong` names a song id, and no cartridge stream uses it.
			# Reaching it would need a song table this driver does not own.
			var _song_low: int = _get_music_byte()
			var _song_high: int = _get_music_byte()
		0xEC:
			sfx_priority = 1
		0xED:
			sfx_priority = 0
		0xEE:
			var slot: int = _cur_channel & 0x03
			if _channel_jump_condition[slot] != 0:
				_channel_jump_condition[slot] = 0
				var target: int = _get_music_byte()
				channel.music_address = (target | (_get_music_byte() << 8)) & 0xFFFF
			else:
				channel.music_address = (channel.music_address + 2) & 0xFFFF
		0xEF:
			if stereo:
				_set_lr_tracks()
				channel.tracks &= _get_music_byte()
			else:
				var _skipped: int = _get_music_byte()
		0xF0:
			channel.noise = not channel.noise
			if channel.noise:
				_sfx_noise_sample_set = _get_music_byte()
		0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9:
			pass
		0xFA:
			channel.condition = _get_music_byte()
		0xFB:
			if _get_music_byte() == channel.condition:
				var target: int = _get_music_byte()
				channel.music_address = (target | (_get_music_byte() << 8)) & 0xFFFF
			else:
				channel.music_address = (channel.music_address + 2) & 0xFFFF
		0xFC:
			var target: int = _get_music_byte()
			channel.music_address = (target | (_get_music_byte() << 8)) & 0xFFFF
		0xFD:
			var count: int = _get_music_byte()
			if not channel.looping:
				if count == 0:
					var target: int = _get_music_byte()
					channel.music_address = (target | (_get_music_byte() << 8)) & 0xFFFF
					return
				channel.looping = true
				channel.loop_count = (count - 1) & 0xFF
			if channel.loop_count == 0:
				channel.looping = false
				channel.music_address = (channel.music_address + 2) & 0xFFFF
			else:
				channel.loop_count -= 1
				var target: int = _get_music_byte()
				channel.music_address = (target | (_get_music_byte() << 8)) & 0xFFFF
		0xFE:
			var target: int = _get_music_byte()
			target |= _get_music_byte() << 8
			channel.last_music_address = channel.music_address
			channel.music_address = target & 0xFFFF
			channel.subroutine = true
		SOUND_RETURN:
			channel.subroutine = false
			channel.music_address = channel.last_music_address


func _set_note_duration(duration: int) -> void:
	var channel: Channel = channels[_cur_channel]
	var units: int = (duration + 1) & 0xFF
	var low: int = (channel.note_length * units) & 0xFF
	var total: int = (low * channel.tempo + channel.note_duration_modifier) & 0xFFFF
	channel.note_duration_modifier = total & 0xFF
	channel.note_duration = total >> 8


func _set_global_tempo(tempo: int) -> void:
	var base: int = 0 if _cur_channel < NUM_MUSIC_CHANNELS else NUM_MUSIC_CHANNELS
	for index: int in NUM_MUSIC_CHANNELS:
		var channel: Channel = channels[base + index]
		channel.tempo = tempo & 0xFFFF
		channel.note_duration_modifier = 0


func _start_channel() -> void:
	_set_lr_tracks()
	channels[_cur_channel].channel_on = true


func _set_lr_tracks() -> void:
	channels[_cur_channel].tracks = _default_tracks(_cur_channel)


## `MonoTracks` and `StereoTracks` hold the same four values, so a channel's
## default is its own bit in both output nibbles.
func _default_tracks(index: int) -> int:
	var bit: int = 1 << (index & 0x03)
	return bit | (bit << 4)


## `LoadChannel`. Returns the address just past the three-byte channel header.
func _load_channel(address: int) -> int:
	_cur_channel = _music_byte(_music_bank, address) & 0x07
	address += 1
	var channel: Channel = channels[_cur_channel]
	channel.channel_on = false
	channel.init()
	channel.music_address = _music_byte(_music_bank, address)
	address += 1
	channel.music_address |= _music_byte(_music_bank, address) << 8
	address += 1
	channel.music_id = _music_id
	channel.music_bank = _music_bank
	return address


func _get_music_byte() -> int:
	var channel: Channel = channels[_cur_channel]
	_cur_music_byte = _music_byte(channel.music_bank, channel.music_address)
	channel.music_address = (channel.music_address + 1) & 0xFFFF
	return _cur_music_byte


## `GetFrequency`. The table is shifted right arithmetically once per octave
## below seven; every entry has bit 15 set, so a logical shift is an octave out.
func _get_frequency(note: int, octave: int) -> int:
	var channel: Channel = channels[_cur_channel]
	var index: int = note + (channel.transposition & 0x0F)
	if index < 0 or index >= FREQUENCY_TABLE.size():
		return 0
	var value: int = FREQUENCY_TABLE[index]
	if (value & 0x8000) != 0:
		value -= 0x10000
	var shift: int = 7 - mini(7, octave + ((channel.transposition >> 4) & 0x0F))
	while shift > 0:
		value >>= 1
		shift -= 1
	return value & 0x07FF


func _music_byte(bank: int, address: int) -> int:
	var entry: Variant = _banks.get(bank, null)
	if entry == null:
		return 0xFF
	var bytes: PackedByteArray = (entry as Dictionary)["bytes"]
	var at: int = address - int((entry as Dictionary)["origin"])
	if at < 0 or at >= bytes.size():
		return 0xFF
	return bytes[at]


func _drum_byte(address: int) -> int:
	var at: int = address - _drumkits_address
	if at < 0 or at >= _drumkits.size():
		return SOUND_RETURN
	return _drumkits[at]


func _drum_sample_address(kit: int, note: int) -> int:
	var table: int = _drumkits_address + kit * 2
	var base: int = _drum_byte(table) | (_drum_byte(table + 1) << 8)
	var entry: int = base + note * 2
	return _drum_byte(entry) | (_drum_byte(entry + 1) << 8)


static func _to_bytes(value: Variant) -> PackedByteArray:
	if value is PackedByteArray:
		return value
	if not value is Array:
		return PackedByteArray()
	var raw: Array = value as Array
	var out := PackedByteArray()
	out.resize(raw.size())
	for index: int in out.size():
		out[index] = int(raw[index]) & 0xFF
	return out
