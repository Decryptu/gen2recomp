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
		# The SVG text is what is rasterised, so the source has to be exported
		# verbatim: Godot's SVG importer would ship the `.ctex` alone and every
		# glyph would draw nothing outside the editor.
		var import_path: String = "%s.import" % Gen2LauncherIcon.source_path(glyph)
		assert_true(FileAccess.file_exists(import_path), import_path)
		assert_string_contains(
			FileAccess.get_file_as_string(import_path), 'importer="keep"', String(glyph)
		)
	assert_false(Gen2LauncherIcon.has_glyph(&"nonesuch"))
	assert_eq(Gen2LauncherIcon.source_path(&"nonesuch"), "")


## The built-in browser lists paths `FileAccess.open()` then refuses on every
## sandboxed platform, so a dialog that does not ask for the system picker is a
## picker the player cannot import with. `FileDialog` makes the feature test
## itself, so asking is always right and gating is what breaks iOS.
func test_every_file_picker_asks_for_the_systems_own() -> void:
	var dialog: FileDialog = Gen2LauncherUI.file_picker(
		_light, "Choose", FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*.gbc; Dump"])
	)
	autofree(dialog)
	assert_true(dialog.use_native_dialog)
	assert_eq(dialog.access, FileDialog.ACCESS_FILESYSTEM)
	assert_eq(dialog.file_mode, FileDialog.FILE_MODE_OPEN_FILE)
	assert_eq(dialog.title, "Choose")
	# One helper, so a screen added later cannot reintroduce its own gate.
	for path: String in _scripts_under("res://game"):
		var source: String = FileAccess.get_file_as_string(path)
		if path.ends_with("launcher/launcher_ui.gd"):
			continue
		assert_false(source.contains("FileDialog.new()"), path)
		assert_false(source.contains("FEATURE_NATIVE_DIALOG_FILE"), path)


func _scripts_under(root: String) -> Array[String]:
	var found: Array[String] = []
	var queue: Array[String] = [root]
	while not queue.is_empty():
		var directory: String = queue.pop_front()
		for name: String in DirAccess.get_directories_at(directory):
			queue.append("%s/%s" % [directory, name])
		for name: String in DirAccess.get_files_at(directory):
			if name.ends_with(".gd"):
				found.append("%s/%s" % [directory, name])
	return found


## A launcher page scrolls vertically only, so nothing inside one may measure
## wider than the window it is given: a portrait phone is the ordinary case.
func test_a_settings_row_stacks_rather_than_running_off_a_narrow_page() -> void:
	var choices: Array = ["Windowed", "Fullscreen", "Borderless"]
	var control: Control = Gen2LauncherUI.segmented(_light, choices, 0, func(_i: int) -> void: pass)
	var row: Container = Gen2LauncherUI.field(_light, "Window", control)
	var host := Control.new()
	add_child_autofree(host)
	host.add_child(row)
	var label: Control = row.get_child(0)

	# The row never asks for more than the control itself, so no page is widened
	# by one and then measured as fitting.
	var wanted: float = Gen2LauncherUI.preferred_width(control)
	assert_lt(row.get_combined_minimum_size().x, wanted)

	row.size = Vector2(wanted + label.get_combined_minimum_size().x + 100.0, 0.0)
	await wait_process_frames(2)
	assert_gt(control.position.x, label.size.x, "side by side while both fit")

	row.size = Vector2(wanted + 10.0, 0.0)
	await wait_process_frames(2)
	assert_eq(control.position.x, 0.0, "stacked once they do not")
	assert_gt(control.position.y, label.size.y, "the control under the label")
	assert_eq(control.size.x, row.size.x, "the control takes the whole width once stacked")


func test_every_glyph_the_launcher_asks_for_is_one_the_set_draws() -> void:
	var used: Array[StringName] = [
		&"shelf", &"mods", &"settings", &"about", &"play", &"plus", &"back",
		&"folder", &"trash", &"refresh", &"download", &"check", &"warning",
		&"save", &"dots", &"close", &"power", &"refresh_square",
		&"bug", &"github", &"discord",
	]
	for glyph: StringName in used:
		assert_true(Gen2LauncherIcon.has_glyph(glyph), String(glyph))


func test_mod_update_controls_stay_icon_sized_for_mobile() -> void:
	var page: Gen2ModsPage = Gen2ModsPage.create(_light)
	add_child_autofree(page)
	page.size = Vector2(360, 640)
	await get_tree().process_frame
	var check: Gen2LauncherButton = page.get("_check_updates_button")
	assert_not_null(check)
	assert_eq(check.text, "", "the page-wide check does not widen the mobile header")
	assert_eq(check.get("_glyph"), &"refresh_square")
	var actions: Array[Control] = page._action_buttons({
		"name": "Example", "installed": true,
		"update": Gen2ModIndex.UPDATE_AVAILABLE,
	})
	var update: Gen2LauncherButton = actions[0] as Gen2LauncherButton
	assert_eq(update.text, "", "an available update is the requested download-only button")
	assert_eq(update.get("_glyph"), &"download")
	assert_lte(page.get_combined_minimum_size().x, 360.0, "the Mods page fits a narrow phone")
	for action: Control in actions:
		action.free()


func test_a_mod_icon_keeps_its_square_whether_or_not_the_mod_has_a_picture() -> void:
	var image: Image = Image.create_empty(
		Gen2ModArt.ICON_SIDE, Gen2ModArt.ICON_SIDE, false, Image.FORMAT_RGBA8
	)
	image.fill(Color.REBECCA_PURPLE)
	var texture: ImageTexture = ImageTexture.create_from_image(image)

	var blank: Control = Gen2LauncherUI.mod_icon(_light, null)
	var drawn: Control = Gen2LauncherUI.mod_icon(_light, texture)
	var side: float = Gen2LauncherUI.MOD_ICON_SIDE
	for square: Control in [blank, drawn]:
		assert_eq(
			square.custom_minimum_size, Vector2(side, side),
			"a name starts at the same place with or without an icon"
		)
	assert_eq(
		(drawn as TextureRect).stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
		"an icon that is not square for its box is never stretched to fit"
	)
	assert_eq(
		(drawn as TextureRect).texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
		"32x32 cartridge art is not smoothed on the way up"
	)
	assert_true(Gen2LauncherUI.set_mod_icon(drawn, texture), "a drawn square takes a later picture")
	assert_false(
		Gen2LauncherUI.set_mod_icon(blank, texture),
		"and the fallback glyph is replaced by its owner rather than filled"
	)
	blank.free()
	drawn.free()


func test_launcher_buttons_always_draw_a_coloured_focus_ring() -> void:
	for variant: Gen2LauncherButton.Variant in Gen2LauncherButton.Variant.values():
		var button: Gen2LauncherButton = Gen2LauncherButton.create(_light, "Focus", variant)
		var ring: StyleBoxFlat = button.get_theme_stylebox("focus") as StyleBoxFlat
		assert_not_null(ring)
		assert_eq(ring.border_color, _light.accent)
		assert_gte(ring.border_width_left, 3)
		button.free()


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


func test_dragging_the_row_settles_on_whatever_it_was_left_nearest() -> void:
	var page: Gen2ShelfPage = Gen2ShelfPage.create(_light, false)
	add_child_autofree(page)
	page.size = Vector2(1000, 640)
	await get_tree().process_frame
	var stage: Gen2CartridgeStage = page.stage()
	var stride: float = stage.cartridge(RomRegistry.ORDER[0]).size.x

	# Dragging left carries the row left, which brings the next cartridge in.
	_drag(stage, -stride * 1.2)
	await wait_seconds(0.5)
	assert_eq(stage.selected, 1, "a full slot of travel moves on by one")

	# A drag that does not reach halfway falls back to where it started.
	_drag(stage, -stride * 0.2)
	await wait_seconds(0.5)
	assert_eq(stage.selected, 1, "and a short one settles back")

	# A press that goes nowhere is a click, which on a neighbour selects it.
	var neighbour: Gen2Cartridge = stage.cartridge(RomRegistry.ORDER[0])
	_press(stage, Rect2(neighbour.position, neighbour.size).get_center())
	assert_eq(stage.selected, 0, "clicking the one beside it chooses it")


## The pointer path itself, pushed through a viewport rather than handed to the
## stage. Every other test here calls `_gui_input` directly and is blind to what
## the mouse actually reaches: a card that stopped the pointer left the row
## selectable only by the gaps between the cards, on a mouse and on a
## touchscreen alike.
func test_a_press_on_a_cartridge_reaches_the_row_behind_it() -> void:
	var stage: Gen2CartridgeStage = await _pointed_stage()
	var neighbour: Gen2Cartridge = stage.cartridge(RomRegistry.ORDER[1])
	assert_eq(neighbour.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the card is not a wall")
	_point(stage, neighbour.get_global_rect().get_center())
	await get_tree().process_frame
	assert_eq(stage.selected, 1, "pressing a cartridge chooses it")

	# And a drag begun on a card carries the row, which is the touch gesture.
	# After the slide, so the card being grabbed is the size it has at rest.
	await wait_seconds(0.4)
	var card: Gen2Cartridge = stage.selected_cartridge()
	var from: Vector2 = card.get_global_rect().get_center()
	var by := Vector2(-card.size.x * 1.2, 0.0)
	_pointer(stage, _button(from, true))
	_pointer(stage, _motion(from + by, by))
	_pointer(stage, _button(from + by, false))
	await wait_seconds(0.5)
	assert_eq(stage.selected, 2, "dragging from a cartridge moves the row")


## A shelf in a viewport of its own, so pushed input is routed the way the
## running launcher routes it. The test runner's own interface is over the
## window and would take every press pushed at that one.
func _pointed_stage() -> Gen2CartridgeStage:
	var holder := SubViewport.new()
	holder.size = Vector2i(1000, 640)
	holder.handle_input_locally = true
	add_child_autofree(holder)
	var page: Gen2ShelfPage = Gen2ShelfPage.create(_light, false)
	holder.add_child(page)
	page.size = Vector2(1000, 640)
	await get_tree().process_frame
	return page.stage()


func _point(stage: Gen2CartridgeStage, at: Vector2) -> void:
	_pointer(stage, _button(at, true))
	_pointer(stage, _button(at, false))


func _pointer(stage: Gen2CartridgeStage, event: InputEvent) -> void:
	(stage.get_viewport() as SubViewport).push_input(event, true)


func test_a_scroll_pane_only_stops_a_pad_when_there_is_more_to_see() -> void:
	var pane: Gen2LauncherScroll = Gen2LauncherScroll.create()
	pane.size = Vector2(200, 120)
	var column: VBoxContainer = Gen2LauncherUI.column()
	pane.add_child(column)
	add_child_autofree(pane)
	var filler: Label = Gen2LauncherUI.body(_light, "x")
	filler.custom_minimum_size = Vector2(0, 40)
	column.add_child(filler)
	await wait_seconds(0.2)
	assert_eq(pane.focus_mode, Control.FOCUS_NONE, "a pane that fits is not a stop")
	assert_true(pane.follow_focus, "and it carries a pad's focus with it either way")

	var tall: Label = Gen2LauncherUI.body(_light, "y")
	tall.custom_minimum_size = Vector2(0, 600)
	column.add_child(tall)
	await wait_seconds(0.2)
	assert_eq(pane.focus_mode, Control.FOCUS_ALL, "one with more to see takes focus")


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
	# The toast is a chip, so its status colours are the ones that can be read on
	# one rather than the raw palette entries.
	assert_eq(icon.tint, _light.on_chip(_light.error))
	await wait_seconds(0.4)
	assert_almost_eq(toast.modulate.a, 1.0, 0.01, "a refusal stays up")

	toast.show_message(&"success", "Import complete.", "")
	assert_eq(icon.glyph, &"check")
	assert_eq(icon.tint, _light.on_chip(_light.success))


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


## A press, a move and a release over the stage, which is the whole of a drag as
## far as the carousel is concerned.
func _drag(stage: Gen2CartridgeStage, by: float) -> void:
	var from := Vector2(stage.size.x * 0.5, stage.size.y * 0.5)
	stage._gui_input(_button(from, true))
	stage._gui_input(_motion(from + Vector2(by, 0.0), Vector2(by, 0.0)))
	stage._gui_input(_button(from + Vector2(by, 0.0), false))


func _press(stage: Gen2CartridgeStage, at: Vector2) -> void:
	stage._gui_input(_button(at, true))
	stage._gui_input(_button(at, false))


func _button(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	return event


func _motion(at: Vector2, by: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.relative = by
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	return event


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


func test_the_about_page_offers_both_ways_to_report_a_bug() -> void:
	# The two destinations are what the page exists to hand over, so they are
	# asserted by the URL a press would open rather than by button order.
	var page: Gen2AboutPage = Gen2AboutPage.create(_light)
	add_child_autofree(page)
	page.open_report_sheet()
	await get_tree().process_frame
	var opened: Array[String] = []
	for button: Gen2LauncherButton in _buttons_under(page):
		if not button.tooltip_text.is_empty():
			opened.append(button.tooltip_text)
	assert_has(opened, Gen2AppVersion.ISSUES, "the tracker, for anyone who uses one")
	assert_has(opened, Gen2AppVersion.DISCORD, "the chat, for everyone else")
	assert_has(opened, Gen2AppVersion.REPOSITORY, "and the project itself on the page")


## Every button in [param root]'s subtree, which is how a page built in code is
## inspected without naming the containers it happens to nest them in.
func _buttons_under(root: Node) -> Array[Gen2LauncherButton]:
	var found: Array[Gen2LauncherButton] = []
	if root is Gen2LauncherButton:
		found.append(root)
	for child: Node in root.get_children():
		found.append_array(_buttons_under(child))
	return found
