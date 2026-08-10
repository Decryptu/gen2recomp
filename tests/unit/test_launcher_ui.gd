extends GutTest

## The launcher's own presentation layer: palettes, icons, the cartridge stage
## and the animations. Nothing here imports a cartridge or writes the player's
## options file.

var _light: Gen2LauncherTheme = null
var _dark: Gen2LauncherTheme = null


func before_each() -> void:
	_light = Gen2LauncherTheme.for_mode(Gen2LauncherTheme.LIGHT)
	_dark = Gen2LauncherTheme.for_mode(Gen2LauncherTheme.DARK)


func test_both_palettes_exist_and_an_unknown_name_falls_back_to_light() -> void:
	assert_eq(_light.mode, Gen2LauncherTheme.LIGHT)
	assert_eq(_dark.mode, Gen2LauncherTheme.DARK)
	assert_eq(Gen2LauncherTheme.for_mode(&"sepia").mode, Gen2LauncherTheme.LIGHT)
	assert_eq(_light.other_mode(), Gen2LauncherTheme.DARK)
	assert_eq(_dark.other_mode(), Gen2LauncherTheme.LIGHT)
	assert_lt(_dark.backdrop_top.get_luminance(), _light.backdrop_top.get_luminance())
	assert_gt(_dark.text.get_luminance(), _light.text.get_luminance())


func test_every_cartridge_is_lit_in_its_own_colour() -> void:
	var seen: Array[Color] = []
	for game_id: StringName in RomRegistry.ORDER:
		var tint: Color = _light.tint_for(game_id)
		assert_false(seen.has(tint), "%s reuses another cartridge's colour" % game_id)
		seen.append(tint)
	# Anything the registry does not name falls back to the app accent rather
	# than to an unset colour.
	assert_eq(_light.tint_for(&"emerald"), _light.accent)


func test_the_appearance_choice_survives_the_options_file() -> void:
	var options := Gen2Options.new()
	options.ui_theme = Gen2LauncherTheme.DARK
	var reloaded: Gen2Options = Gen2Options.parse(options.to_dict())
	assert_eq(reloaded.ui_theme, Gen2LauncherTheme.DARK)
	# Unlike a save, a damaged options file clamps rather than being refused.
	assert_eq(Gen2Options.parse({"ui_theme": "chartreuse"}).ui_theme, Gen2LauncherTheme.LIGHT)


func test_every_sound_the_launcher_plays_is_present_and_bounded() -> void:
	for clip: StringName in Gen2LauncherAudio.CLIPS:
		var stream: AudioStream = Gen2LauncherAudio.CLIPS[clip]
		assert_not_null(stream, String(clip))
		assert_gt(stream.get_length(), 0.0, String(clip))
		# A launcher sound is feedback, not music: anything longer is a mistake.
		assert_lt(stream.get_length(), 1.5, String(clip))


func test_a_muted_sound_setting_silences_the_launcher() -> void:
	var options: Gen2Options = Gen2OptionsStore.current()
	var previous: int = options.sfx_volume
	var audio := Gen2LauncherAudio.new()
	add_child_autofree(audio)
	await get_tree().process_frame

	options.sfx_volume = 0
	audio.play_clip(&"click")
	assert_false(_any_playing(audio), "volume 0 must reach no player")

	options.sfx_volume = Gen2Options.MAX_VOLUME
	audio.muted = true
	audio.play_clip(&"click")
	assert_false(_any_playing(audio), "a muted launcher must stay silent")

	options.sfx_volume = previous


func _any_playing(audio: Gen2LauncherAudio) -> bool:
	for child: Node in audio.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing:
			return true
	return false


func test_every_named_icon_rasterises_rather_than_drawing_nothing() -> void:
	# The glyphs are looked up by name, so a typo would silently draw an empty
	# texture rather than fail.
	for glyph: StringName in Gen2LauncherIcon.PATHS:
		var raster: Texture2D = Gen2LauncherIcon.raster(glyph, 24.0, _light.text)
		assert_not_null(raster, String(glyph))
		assert_gt(raster.get_width(), 0, String(glyph))
	assert_false(Gen2LauncherIcon.has_glyph(&"nonesuch"))


func test_every_glyph_the_launcher_asks_for_is_one_the_set_draws() -> void:
	var used: Array[StringName] = [
		&"shelf", &"mods", &"settings", &"about", &"play", &"plus", &"back",
		&"sun", &"moon", &"folder", &"trash", &"refresh", &"download", &"check",
		&"warning", &"save", &"dots", &"close", &"left", &"right", &"power",
	]
	for glyph: StringName in used:
		assert_true(Gen2LauncherIcon.has_glyph(glyph), String(glyph))


func test_a_card_pads_its_child_and_carries_no_shadow_unless_it_floats() -> void:
	var card: Gen2LauncherCard = Gen2LauncherCard.create(_light, Gen2LauncherTheme.RADIUS_MD, 20)
	var label: Label = Gen2LauncherUI.body(_light, "x")
	label.custom_minimum_size = Vector2(100, 30)
	card.add_child(label)
	add_child_autofree(card)
	await get_tree().process_frame

	assert_eq(card.get_combined_minimum_size(), Vector2(140, 70))
	assert_eq(label.position, Vector2(20, 20))
	# A printed card has no shadow to be cut off by whatever scrolls it. Only the
	# few surfaces that genuinely float do.
	var printed: StyleBoxFlat = card.get_theme_stylebox("panel")
	assert_eq(printed.shadow_size, 0)
	var floating: Gen2LauncherCard = Gen2LauncherCard.floating(_light)
	assert_gt((floating.get_theme_stylebox("panel") as StyleBoxFlat).shadow_size, 0)
	floating.free()


func test_a_segmented_control_moves_its_choice_and_reports_the_index() -> void:
	var chosen: Array[int] = []
	var control: Control = Gen2LauncherUI.segmented(
		_light, ["One", "Two", "Three"], 0, func(index: int) -> void: chosen.append(index)
	)
	add_child_autofree(control)
	await get_tree().process_frame

	var buttons: Array[Gen2LauncherButton] = []
	for child: Node in control.get_child(0).get_children():
		buttons.append(child)
	assert_true(buttons[0].is_active())
	buttons[2].pressed.emit()
	assert_eq(chosen, [2] as Array[int])
	assert_true(buttons[2].is_active())
	assert_false(buttons[0].is_active(), "only one segment can be chosen")


func test_the_stage_holds_one_cartridge_per_supported_game() -> void:
	var page: Gen2ShelfPage = Gen2ShelfPage.create(_light, false)
	add_child_autofree(page)
	await get_tree().process_frame

	for game_id: StringName in RomRegistry.ORDER:
		var card: Gen2Cartridge = page.cartridge(game_id)
		assert_not_null(card, String(game_id))
		assert_false(card.imported, "a bay starts empty")
		assert_not_null(Gen2Cartridge.ART[game_id], "every cartridge has art")


func test_the_selected_cartridge_stands_biggest_and_the_row_stays_centred() -> void:
	var page: Gen2ShelfPage = Gen2ShelfPage.create(_light, false)
	add_child_autofree(page)
	page.size = Vector2(1000, 640)
	await get_tree().process_frame
	var stage: Gen2CartridgeStage = page.stage()
	await get_tree().process_frame

	for index: int in RomRegistry.ORDER.size():
		stage.select(index, false)
		await get_tree().process_frame
		var hero: Gen2Cartridge = stage.selected_cartridge()
		for other: Gen2Cartridge in _cartridges_of(stage):
			if other == hero:
				continue
			assert_lt(other.size.x, hero.size.x, "only the selection is at full size")
		# Whichever end of the row is chosen, the cartridge being looked at stays
		# on the stage rather than being pushed off to balance the rest.
		assert_gte(hero.position.x, 0.0, "the hero starts on the stage")
		assert_lte(hero.position.x + hero.size.x, stage.size.x, "and ends on it")


func test_every_cartridge_beside_the_selection_is_the_same_size_and_centred_on_it() -> void:
	var page: Gen2ShelfPage = Gen2ShelfPage.create(_light, false)
	add_child_autofree(page)
	page.size = Vector2(1000, 640)
	await get_tree().process_frame
	var stage: Gen2CartridgeStage = page.stage()

	for index: int in RomRegistry.ORDER.size():
		stage.select(index, false)
		await get_tree().process_frame
		var hero: Gen2Cartridge = stage.selected_cartridge()
		assert_almost_eq(
			hero.position.x + hero.size.x * 0.5, stage.size.x * 0.5, 0.5,
			"the selection is always in the middle",
		)
		var side: float = -1.0
		for other: Gen2Cartridge in _cartridges_of(stage):
			if other == hero:
				continue
			if side < 0.0:
				side = other.size.x
			assert_almost_eq(other.size.x, side, 0.5, "one size for everything beside it")
			assert_lt(other.size.x, hero.size.x, "and smaller than the selection")


func test_the_carousel_turns_the_short_way_round_the_ring() -> void:
	var page: Gen2ShelfPage = Gen2ShelfPage.create(_light, false)
	add_child_autofree(page)
	page.size = Vector2(1000, 640)
	await get_tree().process_frame
	var stage: Gen2CartridgeStage = page.stage()
	var last: int = RomRegistry.ORDER.size() - 1

	# Stepping back off the first cartridge lands on the last one beside it,
	# rather than travelling the whole row to reach it.
	stage.select(0, false)
	stage.step(-1)
	assert_eq(stage.selected, last)
	var behind: Gen2Cartridge = stage.cartridge(RomRegistry.ORDER[0])
	await wait_seconds(0.5)
	assert_gt(behind.position.x, stage.size.x * 0.5, "the one stepped off sits to the right")


func test_arrow_keys_move_the_selection_and_wrap() -> void:
	var page: Gen2ShelfPage = Gen2ShelfPage.create(_light, false)
	add_child_autofree(page)
	page.size = Vector2(1000, 640)
	await get_tree().process_frame
	var stage: Gen2CartridgeStage = page.stage()

	stage.step(1)
	assert_eq(stage.selected, 1)
	stage.step(-1)
	assert_eq(stage.selected, 0)
	stage.step(-1)
	assert_eq(stage.selected, RomRegistry.ORDER.size() - 1, "the row wraps")


func test_a_seated_cartridge_ends_its_animation_back_at_rest() -> void:
	var page: Gen2ShelfPage = Gen2ShelfPage.create(_light, false)
	add_child_autofree(page)
	page.size = Vector2(900, 600)
	await get_tree().process_frame
	var card: Gen2Cartridge = page.cartridge(RomRegistry.CRYSTAL)
	var rest: float = card.rest_y()

	card.play_insert()
	assert_true(card.imported, "the cartridge is there as soon as it drops")
	assert_lt(card.position.y, rest, "and starts above its bay")
	await wait_seconds(1.0)
	assert_almost_eq(card.position.y, rest, 0.5, "then settles into it")
	assert_almost_eq(card.scale.x, 1.0, 0.02)

	await card.play_start()
	assert_almost_eq(card.position.y, rest, 0.5, "pressing it home leaves it seated")
	assert_almost_eq(card.scale.x, 1.0, 0.02)


func test_ejecting_a_cartridge_empties_its_bay() -> void:
	var page: Gen2ShelfPage = Gen2ShelfPage.create(_light, false)
	add_child_autofree(page)
	page.size = Vector2(900, 600)
	await get_tree().process_frame
	var card: Gen2Cartridge = page.cartridge(RomRegistry.GOLD)
	page.set_slot_state(RomRegistry.GOLD, true, "Ready")
	assert_true(card.imported)

	await card.play_eject()
	assert_false(card.imported, "the bay is empty again")
	assert_almost_eq(card.position.y, card.rest_y(), 0.5, "and back where it stood")


func test_the_toast_says_which_kind_of_message_it_is_showing() -> void:
	var toast: Gen2LauncherToast = Gen2LauncherToast.create(_light)
	add_child_autofree(toast)
	await get_tree().process_frame

	toast.show_message(&"error", "Import stopped.", "That file is not a cartridge.")
	var icon: Gen2LauncherIcon = _icon_of(toast)
	assert_eq(icon.glyph, &"warning")
	assert_eq(icon.tint, _light.error)
	await wait_seconds(0.4)
	assert_almost_eq(toast.modulate.a, 1.0, 0.01, "a refusal stays up")

	toast.show_message(&"success", "Import complete.", "")
	assert_eq(icon.glyph, &"check")
	assert_eq(icon.tint, _light.success)


func test_the_toast_hides_itself_when_there_is_nothing_to_report() -> void:
	var toast: Gen2LauncherToast = Gen2LauncherToast.create(_light)
	add_child_autofree(toast)
	await get_tree().process_frame

	toast.show_message(&"info", "Verifying...", "")
	await wait_seconds(0.4)
	assert_almost_eq(toast.modulate.a, 1.0, 0.01)
	toast.hide_message()
	await wait_seconds(0.4)
	assert_almost_eq(toast.modulate.a, 0.0, 0.01, "a quiet launcher shows nothing")


func _cartridges_of(stage: Gen2CartridgeStage) -> Array[Gen2Cartridge]:
	var found: Array[Gen2Cartridge] = []
	for child: Node in stage.get_children():
		if child is Gen2Cartridge:
			found.append(child)
	return found


func _icon_of(from: Node) -> Gen2LauncherIcon:
	var queue: Array[Node] = [from]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node is Gen2LauncherIcon:
			return node
		for child: Node in node.get_children():
			queue.append(child)
	return null
