class_name Gen2Apu
extends RefCounted

## DMG audio processing unit: the four hardware channels behind $ff10-$ff3f.
##
## The sound engine only ever writes registers; everything audible is decided
## here. Ported from MiniGBS by way of minigb_apu, which is what suiCune renders
## pokecrystal's engine through, so a register trace taken from either lands on
## the same samples.
##
## One [method render_frame] call is one LCD frame: registers are sampled once
## and held for the whole block, exactly as a per-VBlank driver observes them.

const SAMPLE_RATE: int = 32768
## AUDIO_SAMPLE_RATE / (DMG clock / 70,224 clocks per frame), truncated.
const SAMPLES_PER_FRAME: int = 548
const DMG_CLOCK: int = 4194304

const FIRST_REGISTER: int = 0xFF10
const LAST_REGISTER: int = 0xFF3F
const REGISTER_COUNT: int = LAST_REGISTER - FIRST_REGISTER + 1

## Timebase for every counter below: one unit is 1/16 of an output sample.
const FREQ_INC_REF: int = SAMPLE_RATE * 16
const MAX_CHAN_VOLUME: int = 15
## A single channel at full envelope, leaving room for four of them plus the
## master level under the 16-bit ceiling.
const VOL_STEP: int = 273
const WAVE_STEP: int = 511

const DUTY_PATTERNS: Array = [0x10, 0x30, 0x3C, 0xCF]
const NOISE_DIVISORS: Array = [8, 16, 32, 48, 64, 80, 96, 112]
const READ_MASKS: Array = [
	0x80, 0x3F, 0x00, 0xFF, 0xBF,
	0xFF, 0x3F, 0x00, 0xFF, 0xBF,
	0x7F, 0xFF, 0x9F, 0xFF, 0xBF,
	0xFF, 0xFF, 0x00, 0x00, 0xBF,
	0x00, 0x00, 0x70,
	0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
]
const POWER_ON_REGISTERS: Array = [
	0x80, 0xBF, 0xF3, 0xFF, 0x3F,
	0xFF, 0x3F, 0x00, 0xFF, 0x3F,
	0x7F, 0xFF, 0x9F, 0xFF, 0x3F,
	0xFF, 0xFF, 0x00, 0x00, 0x3F,
	0x77, 0xF3, 0xF1,
]

## Per-channel state, indexed 0-3. Flat arrays rather than objects: the mixer
## touches these once per output sample.
var _enabled: PackedByteArray = PackedByteArray()
var _powered: PackedByteArray = PackedByteArray()
var _on_left: PackedByteArray = PackedByteArray()
var _on_right: PackedByteArray = PackedByteArray()
var _volume: PackedInt32Array = PackedInt32Array()
var _volume_init: PackedInt32Array = PackedInt32Array()
var _freq: PackedInt32Array = PackedInt32Array()
var _freq_counter: PackedInt32Array = PackedInt32Array()
var _freq_inc: PackedInt32Array = PackedInt32Array()
var _value: PackedInt32Array = PackedInt32Array()
var _len_load: PackedInt32Array = PackedInt32Array()
var _len_enabled: PackedByteArray = PackedByteArray()
var _len_counter: PackedInt32Array = PackedInt32Array()
var _len_inc: PackedInt32Array = PackedInt32Array()
var _env_step: PackedInt32Array = PackedInt32Array()
var _env_up: PackedByteArray = PackedByteArray()
var _env_counter: PackedInt32Array = PackedInt32Array()
var _env_inc: PackedInt32Array = PackedInt32Array()
var _sweep_freq: int = 0
var _sweep_rate: int = 0
var _sweep_shift: int = 0
var _sweep_up: bool = false
var _sweep_counter: int = 0
var _sweep_inc: int = 0
var _duty: PackedInt32Array = PackedInt32Array()
var _duty_counter: PackedInt32Array = PackedInt32Array()
var _lfsr: int = 0
var _lfsr_wide: bool = false
var _lfsr_div: int = 0
var _wave_position: int = 0
var _capacitor: PackedFloat32Array = PackedFloat32Array()

var _registers: PackedByteArray = PackedByteArray()
var _master_left: int = 0
var _master_right: int = 0
var _mix: PackedInt32Array = PackedInt32Array()

## Register-write log, off unless a parity tool turns it on.
var tracing: bool = false
var trace_frame: int = 0
var trace_lines: PackedStringArray = PackedStringArray()


func _init() -> void:
	_enabled.resize(4)
	_powered.resize(4)
	_on_left.resize(4)
	_on_right.resize(4)
	_volume.resize(4)
	_volume_init.resize(4)
	_freq.resize(4)
	_freq_counter.resize(4)
	_freq_inc.resize(4)
	_value.resize(4)
	_len_load.resize(4)
	_len_enabled.resize(4)
	_len_counter.resize(4)
	_len_inc.resize(4)
	_env_step.resize(4)
	_env_up.resize(4)
	_env_counter.resize(4)
	_env_inc.resize(4)
	_duty.resize(4)
	_duty_counter.resize(4)
	_capacitor.resize(4)
	_registers.resize(REGISTER_COUNT)
	_mix.resize(SAMPLES_PER_FRAME * 2)
	reset()


## Power-on state, matching what the boot ROM leaves behind.
func reset() -> void:
	for channel: int in 4:
		_enabled[channel] = 0
		_powered[channel] = 0
		_on_left[channel] = 0
		_on_right[channel] = 0
		_volume[channel] = 0
		_volume_init[channel] = 0
		_freq[channel] = 0
		_freq_counter[channel] = 0
		_freq_inc[channel] = 0
		_value[channel] = 0
		_len_load[channel] = 0
		_len_enabled[channel] = 0
		_len_counter[channel] = 0
		_len_inc[channel] = 0
		_env_step[channel] = 0
		_env_up[channel] = 0
		_env_counter[channel] = 0
		_env_inc[channel] = 0
		_duty[channel] = 0
		_duty_counter[channel] = 0
		_capacitor[channel] = 0.0
	_value[0] = -1
	_value[1] = -1
	_sweep_freq = 0
	_sweep_rate = 0
	_sweep_shift = 0
	_sweep_up = false
	_sweep_counter = 0
	_sweep_inc = 0
	_lfsr = 0
	_lfsr_wide = false
	_lfsr_div = 0
	_wave_position = 0
	_master_left = 0
	_master_right = 0
	for index: int in REGISTER_COUNT:
		_registers[index] = 0
	for index: int in POWER_ON_REGISTERS.size():
		write(FIRST_REGISTER + index, POWER_ON_REGISTERS[index])


func read(address: int) -> int:
	var index: int = address - FIRST_REGISTER
	if index < 0 or index >= REGISTER_COUNT:
		return 0xFF
	return _registers[index] | READ_MASKS[index]


func write(address: int, value: int) -> void:
	var index: int = address - FIRST_REGISTER
	if index < 0 or index >= REGISTER_COUNT:
		return
	value &= 0xFF
	if tracing:
		trace_lines.append("%d %04X %02X" % [trace_frame, address, value])
	if address == 0xFF26:
		_registers[index] = value & 0x80
		if (value & 0x80) == 0:
			for cleared: int in 0xFF26 - FIRST_REGISTER:
				_registers[cleared] = 0
			for channel: int in 4:
				_enabled[channel] = 0
		return
	# Every register except NR52 is inert while the APU is powered down.
	if _registers[0xFF26 - FIRST_REGISTER] == 0:
		return
	_registers[index] = value
	var channel: int = index / 5
	match address:
		0xFF12, 0xFF17, 0xFF21:
			_volume_init[channel] = value >> 4
			_powered[channel] = 1 if (value >> 3) != 0 else 0
			# Zombie mode: rewriting the envelope of a live channel nudges its
			# volume instead of reloading it.
			if _powered[channel] != 0 and _enabled[channel] != 0:
				if _env_step[channel] == 0 and _env_inc[channel] != 0:
					_volume[channel] += 1 if (value & 0x08) != 0 else 2
				else:
					_volume[channel] = 16 - _volume[channel]
				_volume[channel] &= 0x0F
				_env_step[channel] = value & 0x07
		0xFF1C:
			_volume[2] = (value >> 5) & 0x03
			_volume_init[2] = _volume[2]
		0xFF11, 0xFF16, 0xFF20:
			_len_load[channel] = value & 0x3F
			_duty[channel] = DUTY_PATTERNS[value >> 6]
		0xFF1B:
			_len_load[2] = value
		0xFF13, 0xFF18, 0xFF1D:
			_freq[channel] = (_freq[channel] & 0xFF00) | value
		0xFF1A:
			_powered[2] = 1 if (value & 0x80) != 0 else 0
			_set_enabled(2, (value & 0x80) != 0)
		0xFF14, 0xFF19, 0xFF1E:
			_freq[channel] = (_freq[channel] & 0x00FF) | ((value & 0x07) << 8)
			_len_enabled[channel] = 1 if (value & 0x40) != 0 else 0
			if (value & 0x80) != 0:
				_trigger(channel)
		0xFF23:
			_len_enabled[3] = 1 if (value & 0x40) != 0 else 0
			if (value & 0x80) != 0:
				_trigger(3)
		0xFF22:
			_freq[3] = value >> 4
			_lfsr_wide = (value & 0x08) == 0
			_lfsr_div = value & 0x07
		0xFF24:
			_master_left = (value >> 4) & 0x07
			_master_right = value & 0x07
		0xFF25:
			for output: int in 4:
				_on_left[output] = (value >> (4 + output)) & 1
				_on_right[output] = (value >> output) & 1


## Renders one LCD frame. The returned buffer is reused, so a caller that keeps
## it past the next call must copy it.
func render_frame(out: PackedVector2Array) -> void:
	var mix: PackedInt32Array = _mix
	for index: int in SAMPLES_PER_FRAME * 2:
		mix[index] = 0
	_render_square(mix, 0)
	_render_square(mix, 1)
	_render_wave(mix)
	_render_noise(mix)
	if out.size() != SAMPLES_PER_FRAME:
		out.resize(SAMPLES_PER_FRAME)
	for index: int in SAMPLES_PER_FRAME:
		out[index] = Vector2(
			clampf(float(mix[index * 2]) / 32768.0, -1.0, 1.0),
			clampf(float(mix[index * 2 + 1]) / 32768.0, -1.0, 1.0),
		)


## Same block of samples as [method render_frame], as interleaved 16-bit values.
## Only the offline render and trace tools use this.
func render_frame_pcm() -> PackedInt32Array:
	var mix: PackedInt32Array = _mix
	for index: int in SAMPLES_PER_FRAME * 2:
		mix[index] = 0
	_render_square(mix, 0)
	_render_square(mix, 1)
	_render_wave(mix)
	_render_noise(mix)
	return mix


func _set_enabled(channel: int, enable: bool) -> void:
	_enabled[channel] = 1 if enable else 0
	var index: int = 0xFF26 - FIRST_REGISTER
	_registers[index] = (_registers[index] & 0x80) \
		| (_enabled[3] << 3) | (_enabled[2] << 2) | (_enabled[1] << 1) | _enabled[0]


func _trigger(channel: int) -> void:
	_set_enabled(channel, true)
	_volume[channel] = _volume_init[channel]
	var envelope: int = _registers[0xFF12 + channel * 5 - FIRST_REGISTER]
	_env_step[channel] = envelope & 0x07
	_env_up[channel] = 1 if (envelope & 0x08) != 0 else 0
	if _env_step[channel] != 0:
		_env_inc[channel] = (FREQ_INC_REF * 64) / (_env_step[channel] * SAMPLE_RATE)
	else:
		_env_inc[channel] = (8 * FREQ_INC_REF) / SAMPLE_RATE
	_env_counter[channel] = 0
	if channel == 0:
		var sweep: int = _registers[0]
		_sweep_freq = _freq[0]
		_sweep_rate = (sweep >> 4) & 0x07
		_sweep_up = (sweep & 0x08) == 0
		_sweep_shift = sweep & 0x07
		_sweep_inc = (128 * FREQ_INC_REF) / (_sweep_rate * SAMPLE_RATE) if _sweep_rate != 0 else 0
		_sweep_counter = FREQ_INC_REF
	var length_max: int = 64
	if channel == 2:
		length_max = 256
		_wave_position = 0
	elif channel == 3:
		_lfsr = 0xFFFF
		_value[3] = -VOL_STEP
	_len_inc[channel] = (256 * FREQ_INC_REF) / (SAMPLE_RATE * maxi(1, length_max - _len_load[channel]))
	_len_counter[channel] = 0


func _render_square(mix: PackedInt32Array, channel: int) -> void:
	if _powered[channel] == 0 or _enabled[channel] == 0 or _freq[channel] >= 2048:
		return
	var frequency: int = DMG_CLOCK / ((2048 - _freq[channel]) << 5)
	var freq_inc: int = frequency * 16 * 8
	_freq_inc[channel] = freq_inc
	var freq_counter: int = _freq_counter[channel]
	var duty: int = _duty[channel]
	var duty_counter: int = _duty_counter[channel]
	var value: int = _value[channel]
	var volume: int = _volume[channel]
	var env_counter: int = _env_counter[channel]
	var env_inc: int = _env_inc[channel]
	var env_step: int = _env_step[channel]
	var env_up: bool = _env_up[channel] != 0
	var len_counter: int = _len_counter[channel]
	var len_inc: int = _len_inc[channel]
	var len_enabled: bool = _len_enabled[channel] != 0
	var capacitor: float = _capacitor[channel]
	var enabled: bool = true
	var left: int = _on_left[channel] * _master_left
	var right: int = _on_right[channel] * _master_right
	for index: int in SAMPLES_PER_FRAME:
		if len_enabled:
			len_counter += len_inc
			if len_counter > FREQ_INC_REF:
				enabled = false
				_set_enabled(channel, false)
				len_counter = 0
		if not enabled:
			continue
		env_counter += env_inc
		while env_counter > FREQ_INC_REF:
			if env_step != 0:
				volume += 1 if env_up else -1
				if volume == 0 or volume == MAX_CHAN_VOLUME:
					env_inc = 0
				volume = clampi(volume, 0, MAX_CHAN_VOLUME)
			env_counter -= FREQ_INC_REF
		if channel == 0 and _sweep_inc != 0:
			_sweep_counter += _sweep_inc
			while _sweep_counter > FREQ_INC_REF:
				if _sweep_shift != 0:
					var step: int = _sweep_freq >> _sweep_shift
					_freq[0] = (_freq[0] + (step if _sweep_up else -step)) & 0xFFFF
					if _freq[0] > 2047:
						enabled = false
						_enabled[0] = 0
					else:
						freq_inc = (DMG_CLOCK / ((2048 - _freq[0]) << 5)) * 16 * 8
				elif _sweep_rate != 0:
					enabled = false
					_enabled[0] = 0
				_sweep_counter -= FREQ_INC_REF
		var position: int = 0
		var previous: int = 0
		var sample: int = 0
		while true:
			var increment: int = freq_inc - position
			freq_counter += increment
			if freq_counter <= FREQ_INC_REF:
				position = freq_inc
				break
			position = freq_inc - (freq_counter - FREQ_INC_REF)
			freq_counter = 0
			duty_counter = (duty_counter + 1) & 7
			sample += ((position - previous) / freq_inc) * value
			value = VOL_STEP if (duty & (1 << duty_counter)) != 0 else -VOL_STEP
			previous = position
		sample += value
		sample = (sample * volume) / 4
		var raw: float = float(sample) / 32768.0
		var filtered: float = raw - capacitor
		capacitor = raw - filtered * 0.996
		sample = int(filtered * 32768.0)
		var at: int = index * 2
		mix[at] += sample * left
		mix[at + 1] += sample * right
	_freq_counter[channel] = freq_counter
	_duty_counter[channel] = duty_counter
	_value[channel] = value
	_volume[channel] = volume
	_env_counter[channel] = env_counter
	_env_inc[channel] = env_inc
	_env_step[channel] = env_step
	_len_counter[channel] = len_counter
	_capacitor[channel] = capacitor
	_freq_inc[channel] = freq_inc


func _render_wave(mix: PackedInt32Array) -> void:
	if _powered[2] == 0 or _enabled[2] == 0 or _freq[2] >= 2048:
		return
	var frequency: int = (DMG_CLOCK / 64) / (2048 - _freq[2])
	var freq_inc: int = frequency * 16 * 32
	var freq_counter: int = _freq_counter[2]
	var position: int = _wave_position
	var volume: int = _volume[2]
	var len_counter: int = _len_counter[2]
	var len_inc: int = _len_inc[2]
	var len_enabled: bool = _len_enabled[2] != 0
	var capacitor: float = _capacitor[2]
	var enabled: bool = true
	var left: int = _on_left[2] * _master_left
	var right: int = _on_right[2] * _master_right
	var shift: int = maxi(0, volume - 1)
	# The sixteen packed sample bytes, hoisted out of the per-sample read.
	var wave: PackedByteArray = _registers.slice(
		0xFF30 - FIRST_REGISTER, 0xFF40 - FIRST_REGISTER
	)
	if volume == 0:
		wave.fill(0x80)
	for index: int in SAMPLES_PER_FRAME:
		if len_enabled:
			len_counter += len_inc
			if len_counter > FREQ_INC_REF:
				enabled = false
				_set_enabled(2, false)
				len_counter = 0
		if not enabled:
			continue
		var packed: int = wave[position >> 1]
		var nibble: int = ((packed & 0x0F) if (position & 1) != 0 else (packed >> 4)) >> shift
		var cursor: int = 0
		var previous: int = 0
		var sample: int = 0
		while true:
			var increment: int = freq_inc - cursor
			freq_counter += increment
			if freq_counter <= FREQ_INC_REF:
				cursor = freq_inc
				break
			cursor = freq_inc - (freq_counter - FREQ_INC_REF)
			freq_counter = 0
			position = (position + 1) & 31
			sample += ((cursor - previous) / freq_inc) * (nibble - 8) * WAVE_STEP
			packed = wave[position >> 1]
			nibble = ((packed & 0x0F) if (position & 1) != 0 else (packed >> 4)) >> shift
			previous = cursor
		sample += (nibble - 8) * WAVE_STEP
		if volume == 0:
			continue
		sample = sample / 4
		var raw: float = float(sample) / 32768.0
		var filtered: float = raw - capacitor
		capacitor = raw - filtered * 0.996
		sample = int(filtered * 32768.0)
		var at: int = index * 2
		mix[at] += sample * left
		mix[at + 1] += sample * right
	_freq_counter[2] = freq_counter
	_wave_position = position
	_len_counter[2] = len_counter
	_capacitor[2] = capacitor
	_freq_inc[2] = freq_inc


func _render_noise(mix: PackedInt32Array) -> void:
	if _powered[3] == 0:
		return
	var freq_inc: int = (DMG_CLOCK / (NOISE_DIVISORS[_lfsr_div] << _freq[3])) * 16
	if _freq[3] >= 14:
		_enabled[3] = 0
	if _enabled[3] == 0:
		_freq_inc[3] = freq_inc
		return
	var freq_counter: int = _freq_counter[3]
	var value: int = _value[3]
	var lfsr: int = _lfsr
	var wide: bool = _lfsr_wide
	var volume: int = _volume[3]
	var env_counter: int = _env_counter[3]
	var env_inc: int = _env_inc[3]
	var env_step: int = _env_step[3]
	var env_up: bool = _env_up[3] != 0
	var len_counter: int = _len_counter[3]
	var len_inc: int = _len_inc[3]
	var len_enabled: bool = _len_enabled[3] != 0
	var capacitor: float = _capacitor[3]
	var enabled: bool = true
	var left: int = _on_left[3] * _master_left
	var right: int = _on_right[3] * _master_right
	for index: int in SAMPLES_PER_FRAME:
		if len_enabled:
			len_counter += len_inc
			if len_counter > FREQ_INC_REF:
				enabled = false
				_set_enabled(3, false)
				len_counter = 0
		if not enabled:
			continue
		env_counter += env_inc
		while env_counter > FREQ_INC_REF:
			if env_step != 0:
				volume += 1 if env_up else -1
				if volume == 0 or volume == MAX_CHAN_VOLUME:
					env_inc = 0
				volume = clampi(volume, 0, MAX_CHAN_VOLUME)
			env_counter -= FREQ_INC_REF
		var position: int = 0
		var previous: int = 0
		var sample: int = 0
		while true:
			var increment: int = freq_inc - position
			freq_counter += increment
			if freq_counter <= FREQ_INC_REF:
				position = freq_inc
				break
			position = freq_inc - (freq_counter - FREQ_INC_REF)
			freq_counter = 0
			lfsr = ((lfsr << 1) | (1 if value >= VOL_STEP else 0)) & 0xFFFF
			var tap_high: int = 14 if wide else 6
			var tap_low: int = 13 if wide else 5
			var feedback: int = ((lfsr >> tap_high) & 1) ^ ((lfsr >> tap_low) & 1)
			value = -VOL_STEP if feedback != 0 else VOL_STEP
			sample += ((position - previous) / freq_inc) * value
			previous = position
		sample += value
		sample = (sample * volume) / 4
		var raw: float = float(sample) / 32768.0
		var filtered: float = raw - capacitor
		capacitor = raw - filtered * 0.996
		sample = int(filtered * 32768.0)
		var at: int = index * 2
		mix[at] += sample * left
		mix[at + 1] += sample * right
	_freq_counter[3] = freq_counter
	_value[3] = value
	_lfsr = lfsr
	_volume[3] = volume
	_env_counter[3] = env_counter
	_env_inc[3] = env_inc
	_env_step[3] = env_step
	_len_counter[3] = len_counter
	_capacitor[3] = capacitor
	_freq_inc[3] = freq_inc
