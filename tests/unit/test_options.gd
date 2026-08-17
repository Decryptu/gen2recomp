extends GutTest

## The cartridge block is checked against `data/default_options.asm` and the
## `options_menu.asm` handlers, which are byte identical between the two pins.

const DEFAULT_OPTIONS_BYTES: Array[int] = [0x03, 0x00, 0x00, 0x01, 0x40, 0x01, 0x00, 0x00]


func after_each() -> void:
	Gen2OptionsStore.use_test_path()
	DirAccess.remove_absolute(Gen2OptionsStore.path())


func test_defaults_match_the_source_default_options_table() -> void:
	var options := Gen2Options.new()
	var bytes: PackedByteArray = options.to_source_bytes()

	assert_eq(bytes.size(), Gen2Options.SOURCE_BLOCK_SIZE)
	for index: int in DEFAULT_OPTIONS_BYTES.size():
		assert_eq(
			bytes[index],
			DEFAULT_OPTIONS_BYTES[index],
			"DefaultOptions byte %d" % index,
		)


func test_battle_scene_bit_is_set_when_the_scene_is_off() -> void:
	var options := Gen2Options.new()
	options.battle_scene = true
	assert_eq(options.to_source_bytes()[0] & (1 << Gen2Options.BIT_BATTLE_SCENE), 0)

	options.battle_scene = false
	assert_ne(options.to_source_bytes()[0] & (1 << Gen2Options.BIT_BATTLE_SCENE), 0)


func test_battle_shift_bit_is_set_for_set_not_for_shift() -> void:
	var options := Gen2Options.new()
	options.battle_style_set = false
	assert_eq(options.to_source_bytes()[0] & (1 << Gen2Options.BIT_BATTLE_SHIFT), 0)

	options.battle_style_set = true
	assert_ne(options.to_source_bytes()[0] & (1 << Gen2Options.BIT_BATTLE_SHIFT), 0)


func test_text_speed_round_trips_through_the_source_delays() -> void:
	for index: int in Gen2Options.TEXT_DELAYS.size():
		var options := Gen2Options.new()
		options.text_speed = index
		var bytes: PackedByteArray = options.to_source_bytes()
		assert_eq(bytes[0] & Gen2Options.TEXT_DELAY_MASK, Gen2Options.TEXT_DELAYS[index])

		var restored := Gen2Options.new()
		assert_true(restored.apply_source_bytes(bytes))
		assert_eq(restored.text_speed, index)


## `PrintLetterDelay` waits the low three bits of wOptions between two
## characters, so the row is one, three or five frames a character and a box
## driven by elapsed time wants that as a rate.
func test_text_speed_is_a_per_character_frame_count() -> void:
	var options := Gen2Options.new()
	for index: int in Gen2Options.TEXT_DELAYS.size():
		options.text_speed = index
		assert_eq(options.text_delay_frames(), Gen2Options.TEXT_DELAYS[index])
		assert_almost_eq(
			options.text_reveal_speed(),
			1.0 / (Gen2Options.FRAME_SECONDS * float(Gen2Options.TEXT_DELAYS[index])),
			0.001
		)
	options.text_speed = 2
	assert_almost_eq(options.text_reveal_speed(), 12.0, 0.001, "slow is five frames")


## `.fast`: the branch taken when wTextboxFlags' FAST_TEXT_DELAY bit is clear
## overrides the row with TEXT_DELAY_FAST.
func test_a_cleared_fast_text_delay_bit_overrides_the_speed_row() -> void:
	var options := Gen2Options.new()
	options.text_speed = 2
	options.fast_text_delay = false
	assert_eq(options.text_delay_frames(), Gen2Options.TEXT_DELAY_FAST)


func test_an_unlisted_text_delay_reads_as_medium() -> void:
	var bytes: PackedByteArray = Gen2Options.new().to_source_bytes()
	bytes[0] = (bytes[0] & ~Gen2Options.TEXT_DELAY_MASK) | 0b111

	var options := Gen2Options.new()
	assert_true(options.apply_source_bytes(bytes))
	assert_eq(options.text_speed, 1, "GetTextSpeed falls through to medium")


func test_an_unlisted_printer_brightness_reads_as_normal() -> void:
	var bytes: PackedByteArray = Gen2Options.new().to_source_bytes()
	bytes[Gen2Options.OFFSET_PRINTER] = 0x11

	var options := Gen2Options.new()
	assert_true(options.apply_source_bytes(bytes))
	assert_eq(options.printer_brightness, Gen2Options.PRINTER_NORMAL_INDEX)


func test_a_short_source_block_is_refused() -> void:
	var options := Gen2Options.new()
	assert_false(options.apply_source_bytes(PackedByteArray([0x03, 0x00])))


func test_every_cartridge_field_survives_a_byte_round_trip() -> void:
	var options := Gen2Options.new()
	options.text_speed = 2
	options.battle_scene = false
	options.battle_style_set = true
	options.stereo = true
	options.printer_brightness = 4
	options.menu_account = false
	options.textbox_frame = 6
	options.fast_text_delay = false

	var restored := Gen2Options.new()
	assert_true(restored.apply_source_bytes(options.to_source_bytes()))
	assert_eq(restored.text_speed, 2)
	assert_false(restored.battle_scene)
	assert_true(restored.battle_style_set)
	assert_true(restored.stereo)
	assert_eq(restored.printer_brightness, 4)
	assert_false(restored.menu_account)
	assert_eq(restored.textbox_frame, 6)
	assert_false(restored.fast_text_delay)


func test_out_of_range_values_are_clamped_rather_than_refused() -> void:
	var options: Gen2Options = Gen2Options.parse({
		"text_speed": 99,
		"music_volume": -4,
		"sfx_volume": 900,
		"textbox_frame": 12,
		"video_mode": "hologram",
		"game_speed": "",
		"max_fps": 7,
	})

	assert_eq(options.text_speed, 2)
	assert_eq(options.music_volume, 0)
	assert_eq(options.sfx_volume, Gen2Options.MAX_VOLUME)
	assert_eq(options.textbox_frame, Gen2Options.FRAME_COUNT - 1)
	assert_eq(options.video_mode, &"windowed")
	assert_eq(options.game_speed, &"normal")
	assert_eq(options.max_fps, 60, "an unlisted frame cap falls back to 60")


## The gameplay rules live in the options file but are their own block: the
## settings screen edits them there, and a new run takes a copy.
func test_the_rules_block_travels_with_the_options_file() -> void:
	var options := Gen2Options.new()
	assert_eq(options.rules.mode, Gen2Rules.MODE_CURRENT)
	options.rules.set_mode(Gen2Rules.MODE_VANILLA)
	options.rules.difficulty = Gen2Rules.DIFFICULTY_EASY

	var restored: Gen2Options = Gen2Options.parse(options.to_dict())
	assert_true(restored.rules.matches(options.rules))
	assert_eq(restored.rules.mode, Gen2Rules.MODE_VANILLA)
	assert_eq(restored.rules.difficulty, Gen2Rules.DIFFICULTY_EASY)
	assert_eq(
		Gen2Options.parse({}).rules.mode, Gen2Rules.MODE_CURRENT,
		"a file written before the block existed plays what shipped"
	)


func test_a_non_dictionary_parses_as_defaults() -> void:
	var options: Gen2Options = Gen2Options.parse("not options")
	assert_eq(options.to_source_bytes(), Gen2Options.new().to_source_bytes())


func test_saving_then_loading_keeps_both_blocks() -> void:
	var options := Gen2Options.new()
	options.battle_scene = false
	options.textbox_frame = 3
	options.music_volume = 2
	options.video_mode = &"fullscreen"
	options.max_fps = 120
	assert_true(Gen2OptionsStore.save(options))

	Gen2OptionsStore.use_test_path()
	var loaded: Gen2Options = Gen2OptionsStore.load_options()
	assert_false(loaded.battle_scene)
	assert_eq(loaded.textbox_frame, 3)
	assert_eq(loaded.music_volume, 2)
	assert_eq(loaded.video_mode, &"fullscreen")
	assert_eq(loaded.max_fps, 120)


func test_a_missing_file_loads_defaults() -> void:
	DirAccess.remove_absolute(Gen2OptionsStore.path())
	Gen2OptionsStore.use_test_path()

	var loaded: Gen2Options = Gen2OptionsStore.load_options()
	assert_eq(loaded.to_source_bytes(), Gen2Options.new().to_source_bytes())


func test_a_damaged_file_loads_defaults_rather_than_failing() -> void:
	var file: FileAccess = FileAccess.open(Gen2OptionsStore.path(), FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	Gen2OptionsStore.use_test_path()

	var loaded: Gen2Options = Gen2OptionsStore.load_options()
	assert_eq(loaded.to_source_bytes(), Gen2Options.new().to_source_bytes())


func test_current_shares_one_object_until_forgotten() -> void:
	var first: Gen2Options = Gen2OptionsStore.current()
	first.music_volume = 1
	assert_eq(Gen2OptionsStore.current().music_volume, 1)

	Gen2OptionsStore.use_test_path()
	assert_eq(Gen2OptionsStore.current().music_volume, 7)
