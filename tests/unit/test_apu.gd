extends GutTest

## The hardware behind the registers: what a given write actually sounds like.


func _apu() -> Gen2Apu:
	var apu := Gen2Apu.new()
	apu.write(0xFF26, 0x80)
	apu.write(0xFF24, 0x77)
	apu.write(0xFF25, 0xFF)
	return apu


## One frame is too short to measure a low note against, so every reading below
## takes a stretch of them. The first frames are dropped because the analog
## stage starts discharged and its settling swamps a peak reading.
func _render(apu: Gen2Apu, frames: int, warmup: int = 8) -> PackedInt32Array:
	for _frame: int in warmup:
		apu.render_frame_pcm()
	var out := PackedInt32Array()
	for _frame: int in frames:
		out.append_array(apu.render_frame_pcm())
	return out


func _peak(pcm: PackedInt32Array) -> int:
	var peak: int = 0
	for value: int in pcm:
		peak = maxi(peak, absi(value))
	return peak


## Peak to peak on the left output. The analog stage removes the offset a wave
## sample carries, so this is the amplitude and the peak alone is not.
func _range(pcm: PackedInt32Array) -> int:
	var high: int = -0x8000
	var low: int = 0x7FFF
	for index: int in pcm.size() / 2:
		high = maxi(high, pcm[index * 2])
		low = mini(low, pcm[index * 2])
	return high - low


## Rising zero crossings a second on the left output, which is the cheapest
## frequency read.
func _hertz(pcm: PackedInt32Array) -> float:
	var count: int = 0
	var previous: int = 0
	for index: int in pcm.size() / 2:
		var value: int = pcm[index * 2]
		if previous <= 0 and value > 0:
			count += 1
		previous = value
	return float(count) * Gen2Apu.SAMPLE_RATE / float(pcm.size() / 2)


## Sample-to-sample changes, which counts how busy a noise waveform is.
func _transitions(pcm: PackedInt32Array) -> int:
	var count: int = 0
	var previous: int = 0
	for index: int in pcm.size() / 2:
		var value: int = pcm[index * 2]
		if absi(value - previous) > 200:
			count += 1
		previous = value
	return count


func test_duty_patterns_are_bit_masks_rather_than_thresholds() -> void:
	# $10, $30, $3c, $cf hold one, two, four and six set bits: 12.5, 25, 50, 75
	# percent. A threshold comparison would make the first and last identical.
	var widths: Array = []
	for duty: int in Gen2Apu.DUTY_PATTERNS:
		var bits: int = 0
		for index: int in 8:
			bits += 1 if (int(duty) & (1 << index)) != 0 else 0
		widths.append(bits)
	assert_eq(widths, [1, 2, 4, 6])


func test_square_frequency_follows_the_register_divider() -> void:
	var apu: Gen2Apu = _apu()
	# $700 is 131072 / (2048 - 1792) = 512 Hz.
	apu.write(0xFF11, 0x80)
	apu.write(0xFF12, 0xF0)
	apu.write(0xFF13, 0x00)
	apu.write(0xFF14, 0x87)
	assert_almost_eq(_hertz(_render(apu, 30)), 512.0, 8.0)


func test_the_wave_channel_runs_an_octave_below_the_pulse_channels() -> void:
	var apu: Gen2Apu = _apu()
	for index: int in 16:
		# A square wave in the sample table: eight high nibbles then eight low.
		apu.write(0xFF30 + index, 0xFF if index < 8 else 0x00)
	apu.write(0xFF1A, 0x80)
	apu.write(0xFF1B, 0x3F)
	apu.write(0xFF1C, 0x20)
	apu.write(0xFF1D, 0x00)
	apu.write(0xFF1E, 0x87)
	# 65536 / (2048 - 1792) = 256 Hz, half what the same register gives a pulse.
	assert_almost_eq(_hertz(_render(apu, 30)), 256.0, 8.0)


func test_the_wave_output_level_halves_rather_than_muting() -> void:
	var levels: Array = []
	for level: int in [0x00, 0x20, 0x40, 0x60]:
		var apu: Gen2Apu = _apu()
		for index: int in 16:
			apu.write(0xFF30 + index, 0xF0)
		apu.write(0xFF1A, 0x80)
		apu.write(0xFF1B, 0x3F)
		apu.write(0xFF1C, level)
		apu.write(0xFF1D, 0x00)
		apu.write(0xFF1E, 0x84)
		levels.append(_range(_render(apu, 4)))
	assert_eq(levels[0], 0, "level 0 is mute")
	assert_gt(levels[1], levels[2], "100 percent is louder than 50")
	assert_gt(levels[2], levels[3], "50 percent is louder than 25")
	# The sample is shifted once per level, so each step is roughly half. An
	# implementation that also divided by the level, as minigb_apu does, would
	# quarter it and bury the channel.
	assert_almost_eq(float(levels[2]) / float(levels[1]), 0.5, 0.1)


func test_the_volume_envelope_decays_at_sixty_four_steps_a_second() -> void:
	var apu: Gen2Apu = _apu()
	apu.write(0xFF11, 0x80)
	# Volume 15, decreasing, one step per 1/64 second: silent after 15/64 s.
	apu.write(0xFF12, 0xF1)
	apu.write(0xFF13, 0x00)
	apu.write(0xFF14, 0x86)
	var loud: int = _peak(apu.render_frame_pcm())
	assert_gt(loud, 0)
	for _frame: int in 14:
		apu.render_frame_pcm()
	assert_eq(_peak(apu.render_frame_pcm()), 0, "the envelope reached zero")


func _noise(poly: int) -> PackedInt32Array:
	var apu: Gen2Apu = _apu()
	apu.write(0xFF20, 0x3F)
	apu.write(0xFF21, 0xF0)
	apu.write(0xFF22, poly)
	apu.write(0xFF23, 0x80)
	return _render(apu, 8, 2)


func test_the_noise_clock_follows_the_polynomial_divider() -> void:
	# $5 and $a in the high nibble are 16 kHz and 512 Hz off the same divisor.
	var fast: PackedInt32Array = _noise(0x50)
	var slow: PackedInt32Array = _noise(0xA0)
	assert_gt(_peak(fast), 0)
	assert_gt(_peak(slow), 0)
	assert_gt(_transitions(fast), _transitions(slow) * 4)


func test_the_narrow_shift_register_is_a_different_sound() -> void:
	var wide: PackedInt32Array = _noise(0x50)
	# Bit 3 shortens the register to seven stages, which repeats every 127 steps
	# and reads as a tone rather than as noise.
	var narrow: PackedInt32Array = _noise(0x58)
	assert_gt(_peak(narrow), 0)
	var same: int = 0
	for index: int in mini(wide.size(), narrow.size()):
		same += 1 if wide[index] == narrow[index] else 0
	assert_lt(same, wide.size() / 2, "the two registers produce different waveforms")


func test_powering_the_apu_down_clears_every_register_but_the_wave_table() -> void:
	var apu: Gen2Apu = _apu()
	apu.write(0xFF30, 0xAB)
	apu.write(0xFF12, 0xF0)
	apu.write(0xFF26, 0x00)
	assert_eq(apu.read(0xFF12) & 0xF0, 0x00, "the envelope was cleared")
	assert_eq(apu.read(0xFF30), 0xAB, "wave RAM survives")
	# Writes are ignored until the APU is powered back on.
	apu.write(0xFF12, 0xF0)
	assert_eq(apu.read(0xFF12) & 0xF0, 0x00)


func test_the_master_level_scales_each_output_independently() -> void:
	var apu: Gen2Apu = _apu()
	apu.write(0xFF24, 0x70)
	apu.write(0xFF11, 0x80)
	apu.write(0xFF12, 0xF0)
	apu.write(0xFF13, 0x00)
	apu.write(0xFF14, 0x86)
	var pcm: PackedInt32Array = apu.render_frame_pcm()
	var left: int = 0
	var right: int = 0
	for index: int in Gen2Apu.SAMPLES_PER_FRAME:
		left = maxi(left, absi(pcm[index * 2]))
		right = maxi(right, absi(pcm[index * 2 + 1]))
	assert_gt(left, 0)
	assert_eq(right, 0, "the right level is zero")


func test_a_frame_is_the_vblank_rate_not_sixty_hertz() -> void:
	# 32,768 / (4,194,304 / 70,224) is 548.6 samples per frame, truncated to a
	# whole sample. Frequencies are exact; only the frame clock runs 0.11
	# percent fast, which is under two cents of tempo.
	assert_eq(Gen2Apu.SAMPLES_PER_FRAME, 548)
	var implied: float = float(Gen2Apu.SAMPLE_RATE) / Gen2Apu.SAMPLES_PER_FRAME
	assert_almost_eq(implied, 59.7275, 0.08)
	assert_lt(absf(implied - 59.7275) / 59.7275, 0.002)
