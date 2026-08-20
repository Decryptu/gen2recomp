extends GutTest

## Seeing and changing settings from the launcher: the controls, and the rules
## the game is played under.

var _theme: Gen2LauncherTheme = null
var _options: Gen2Options = null
var _host: Control = null
var _section: Gen2ControlsSection = null


func before_each() -> void:
	_theme = Gen2LauncherTheme.for_mode(Gen2LauncherTheme.DARK)
	_options = Gen2Options.new()
	_host = Control.new()
	_host.size = Vector2(900, 700)
	add_child_autofree(_host)
	_section = Gen2ControlsSection.create(_theme, _options, _host)
	_host.add_child(_section)


## The sheets rebuild their rows by freeing them, so the frames that run the
## deletion queue are part of tearing one down.
func after_each() -> void:
	var open_sheet: Gen2BindingSheet = _sheet()
	if open_sheet != null:
		open_sheet.close()
	await get_tree().process_frame
	await get_tree().process_frame
	Gen2OptionsStore.use_test_path()
	DirAccess.remove_absolute(Gen2OptionsStore.path())
	Gen2InputRuntime.instance().apply_options(Gen2Options.new())


func _sheet() -> Gen2BindingSheet:
	for child: Node in _host.get_children():
		if child is Gen2BindingSheet:
			return child
	return null


func _open(button: int) -> Gen2BindingSheet:
	_section._open_editor(button)
	await get_tree().process_frame
	return _sheet()


func _key(code: int, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	return event


## A capture reads the press and binds on the release, so a tap is both.
func _tap(sheet: Gen2BindingSheet, code: int) -> void:
	sheet._unhandled_input(_key(code))
	sheet._unhandled_input(_key(code, false))


func test_a_binding_reads_as_keys_then_pad() -> void:
	var text: String = Gen2ControlsSection.describe(_options.controls[Gen2Button.START])
	assert_string_contains(text, "Pad: Start")
	assert_lt(text.find("Pad:"), text.length())
	assert_gt(text.find("Pad:"), 0, "the keys come first")


func test_a_button_with_nothing_bound_says_so() -> void:
	assert_eq(Gen2ControlsSection.describe([]), "Unbound")


func test_the_editor_opens_on_the_launcher_rather_than_inside_the_card() -> void:
	assert_not_null(await _open(Gen2Button.A), "a sheet has to cover the dock as well")


## The whole point of the card: press something, and that is what the button is.
func test_capturing_a_key_adds_it_to_the_button() -> void:
	var before: int = (_options.controls[Gen2Button.B] as Array).size()
	var sheet: Gen2BindingSheet = await _open(Gen2Button.B)
	sheet._start_capture()
	_tap(sheet, KEY_F7)

	var bindings: Array = _options.controls[Gen2Button.B]
	assert_eq(bindings.size(), before + 1)
	assert_eq(bindings.back(), {"kind": Gen2InputActions.KIND_KEY, "code": KEY_F7})


func test_a_capture_ignores_a_pointer_and_a_synthesised_action() -> void:
	var sheet: Gen2BindingSheet = await _open(Gen2Button.A)
	var before: int = (_options.controls[Gen2Button.A] as Array).size()

	sheet._start_capture()
	for event: InputEvent in [
		InputEventMouseButton.new(), InputEventScreenTouch.new(), InputEventAction.new(),
	]:
		event.set("pressed", true)
		sheet._unhandled_input(event)

	assert_eq((_options.controls[Gen2Button.A] as Array).size(), before)


func test_binding_the_same_thing_twice_changes_nothing() -> void:
	var sheet: Gen2BindingSheet = await _open(Gen2Button.A)
	var before: Array = (_options.controls[Gen2Button.A] as Array).duplicate(true)

	sheet._start_capture()
	_tap(sheet, KEY_Z)

	assert_eq(_options.controls[Gen2Button.A], before)


## One key on two buttons is the player's call. The sheet says so and allows it.
func test_a_binding_already_on_another_button_is_reported_not_refused() -> void:
	var sheet: Gen2BindingSheet = await _open(Gen2Button.B)
	sheet._start_capture()
	_tap(sheet, KEY_SPACE)

	assert_true((_options.controls[Gen2Button.B] as Array).has(
		{"kind": Gen2InputActions.KIND_KEY, "code": KEY_SPACE}
	))
	assert_string_contains(sheet.get("_prompt").text, Gen2Button.label(Gen2Button.A))


## A player on a pad alone used to have no way out of a capture: every button
## they pressed became the binding, and only a mouse or a finger could close the
## sheet. Holding one past the threshold closes it and binds nothing.
func test_holding_a_button_cancels_the_capture_instead_of_binding_it() -> void:
	var sheet: Gen2BindingSheet = await _open(Gen2Button.B)
	var before: Array = (_options.controls[Gen2Button.B] as Array).duplicate(true)
	sheet._start_capture()
	sheet._unhandled_input(_key(KEY_F8))
	assert_false(sheet.get("_pending").is_empty(), "the press is held, not bound")

	sheet.set("_pending_since", Time.get_ticks_msec() - Gen2BindingSheet.HOLD_CANCEL_MSEC)
	sheet._process(0.0)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(_options.controls[Gen2Button.B], before, "nothing was bound")
	assert_null(_sheet(), "and the sheet closed")


## A release that is not the held one is not the end of the capture: letting go
## of a modifier still leaves the key it was pressed with waiting.
func test_a_release_of_something_else_does_not_finish_the_capture() -> void:
	var sheet: Gen2BindingSheet = await _open(Gen2Button.B)
	var before: int = (_options.controls[Gen2Button.B] as Array).size()
	sheet._start_capture()
	sheet._unhandled_input(_key(KEY_F9))
	sheet._unhandled_input(_key(KEY_F10, false))
	assert_eq((_options.controls[Gen2Button.B] as Array).size(), before)

	sheet._unhandled_input(_key(KEY_F9, false))
	assert_eq((_options.controls[Gen2Button.B] as Array).size(), before + 1)


## A stick has no release event: it falls back inside the same deadzone that
## stopped it being read as a binding on the way out.
func test_a_stick_binds_when_it_returns_to_centre() -> void:
	var sheet: Gen2BindingSheet = await _open(Gen2Button.LEFT)
	var before: int = (_options.controls[Gen2Button.LEFT] as Array).size()
	sheet._start_capture()
	## The right stick, since the left one is already on this button by default
	## and a binding the button already has is reported rather than added twice.
	sheet._unhandled_input(_motion(JOY_AXIS_RIGHT_X, -1.0))
	assert_eq((_options.controls[Gen2Button.LEFT] as Array).size(), before)

	sheet._unhandled_input(_motion(JOY_AXIS_RIGHT_X, 0.0))
	var bindings: Array = _options.controls[Gen2Button.LEFT]
	assert_eq(bindings.size(), before + 1)
	assert_eq(bindings.back(), {
		"kind": Gen2InputActions.KIND_PAD_AXIS,
		"code": int(JOY_AXIS_RIGHT_X), "sign": -1,
	})


func _motion(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func test_a_binding_can_be_removed_but_never_the_last_one() -> void:
	var sheet: Gen2BindingSheet = await _open(Gen2Button.START)
	var bindings: Array = _options.controls[Gen2Button.START]

	while bindings.size() > 1:
		sheet._remove(0)
	assert_eq(bindings.size(), 1)

	sheet._remove(0)
	assert_eq(bindings.size(), 1, "a button with nothing bound cannot be pressed")


func test_reset_puts_the_defaults_and_the_stock_layout_back() -> void:
	_options.controls[Gen2Button.A] = [{"kind": Gen2InputActions.KIND_KEY, "code": KEY_F7}]
	_options.touch_layout.scale = Gen2TouchLayout.MAX_SCALE
	_section._reset()

	assert_true(Gen2InputActions.is_default(_options.controls))
	assert_true(_options.touch_layout.is_default())


func test_the_layout_editor_previews_the_controller_it_is_arranging() -> void:
	var sheet: Gen2TouchLayoutSheet = Gen2TouchLayoutSheet.create(_theme, _options)
	sheet.open(_host)
	await get_tree().process_frame

	var pad: Gen2TouchPad = null
	for child: Node in sheet.get_children():
		if child is Gen2TouchPad:
			pad = child
	assert_not_null(pad)
	assert_true(pad.is_editing())
	# Shown even though a desktop is not a touchscreen: this is the preview.
	assert_true(pad.visible)
	assert_same(pad.layout(), _options.touch_layout, "it edits the live layout")

	sheet.close()
	await get_tree().process_frame


## The Gameplay card names three modes and nothing else said what was in them,
## while the per-flag overrides the model has always carried were reachable from
## no screen at all. Both halves are read off one snapshot, so the line under the
## row and the sheet's own list cannot disagree.
func test_the_bug_rules_are_named_and_each_one_can_be_moved_by_hand() -> void:
	var page: Gen2SettingsPage = Gen2SettingsPage.create(_theme, _host)
	_host.add_child(page)
	var opened: Dictionary = page.rules_snapshot()
	assert_eq(StringName(opened["mode"]), Gen2Rules.MODE_CURRENT)
	assert_string_contains(
		String(opened["summary"]), "of %d bugs" % Gen2Rules.FLAGS.size()
	)
	# Wording is what a player has instead of the source, so a flag added without
	# it fails here rather than showing as a bare symbol.
	assert_eq((opened["flags"] as Array).size(), Gen2Rules.FLAGS.size())
	for row: Dictionary in opened["flags"] as Array:
		assert_false(String(row["title"]).is_empty(), String(row["flag"]))
		assert_false(String(row["detail"]).is_empty(), String(row["flag"]))

	page._open_rules_sheet()
	await get_tree().process_frame
	var sheet: Gen2LauncherSheet = null
	for child: Node in _host.get_children():
		if child is Gen2LauncherSheet:
			sheet = child
	assert_not_null(sheet)
	var switches: Array[Gen2LauncherToggle] = []
	for entry: Node in sheet.body().get_children():
		for control: Node in entry.get_children():
			for half: Node in control.get_children():
				if half is Gen2LauncherToggle:
					switches.append(half)
	assert_eq(switches.size(), Gen2Rules.FLAGS.size(), "one switch per bug")

	var first: Dictionary = (opened["flags"] as Array)[0]
	switches[0].button_pressed = not bool(first["on"])
	var moved: Dictionary = page.rules_snapshot()
	assert_eq(StringName(moved["mode"]), Gen2Rules.MODE_CUSTOM)
	assert_ne(bool((moved["flags"] as Array)[0]["on"]), bool(first["on"]))

	# And the sheet's own way back, which is the mode the player last picked
	# rather than a reset to the shipped one.
	page._options.rules.clear_flags()
	assert_eq(StringName(page.rules_snapshot()["mode"]), Gen2Rules.MODE_CURRENT)
	sheet.close()
	await get_tree().process_frame


## A sheet is a modal, and everything under it is still in the tree and still
## focusable: without the guard treating it as the only screen, one press down
## walked out of the sheet and scrolled the page behind it.
func test_arrows_stay_inside_an_open_sheet() -> void:
	var behind: Gen2SettingsPage = Gen2SettingsPage.create(_theme, _host)
	_host.add_child(behind)
	var guard: Gen2FocusGuard = Gen2FocusGuard.attach(_host)
	await get_tree().process_frame
	behind._open_rules_sheet()
	await get_tree().process_frame
	var sheet: Gen2LauncherSheet = _launcher_sheet()
	assert_not_null(sheet)

	var inside: Array[Control] = Gen2FocusGuard.focusable_controls(sheet)
	assert_true(inside.size() > 1, "the sheet has somewhere to move")
	inside[0].grab_focus()
	for step: int in 12:
		guard.move_focus(Vector2.DOWN)
		var owner: Control = _host.get_viewport().gui_get_focus_owner()
		assert_true(
			owner == sheet or sheet.is_ancestor_of(owner),
			"down %d stayed in the sheet" % step
		)
	for step: int in 12:
		guard.move_focus(Vector2.UP)
		var owner: Control = _host.get_viewport().gui_get_focus_owner()
		assert_true(
			owner == sheet or sheet.is_ancestor_of(owner), "up %d" % step
		)
	sheet.close()
	await get_tree().process_frame


## A [CenterContainer] grants a card whatever minimum size it asks for, so a
## sheet with more rows than the window is tall used to hang its actions off the
## bottom edge with no way to reach them. The rows are what gives now.
func test_a_sheet_taller_than_the_window_keeps_its_actions_on_screen() -> void:
	_host.size = Vector2(900, 420)
	var page: Gen2SettingsPage = Gen2SettingsPage.create(_theme, _host)
	_host.add_child(page)
	page._open_rules_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	var sheet: Gen2LauncherSheet = _launcher_sheet()
	assert_not_null(sheet)
	var window := Rect2(Vector2.ZERO, _host.size)
	assert_true(window.encloses(sheet._card.get_global_rect()), "the card fits")
	# The rows are what scrolls; the title, the close button and the actions are
	# the parts that must never leave, since one of them is the way out.
	for control: Control in Gen2FocusGuard.focusable_controls(sheet._actions):
		assert_true(
			window.encloses(control.get_global_rect()), "an action is on screen"
		)
	assert_true(
		window.encloses(Gen2FocusGuard.first_focusable(sheet._card).get_global_rect()),
		"and the close button"
	)
	assert_true(sheet._scroll.get_v_scroll_bar().max_value > sheet._scroll.size.y)
	sheet.close()
	await get_tree().process_frame


func _launcher_sheet() -> Gen2LauncherSheet:
	for child: Node in _host.get_children():
		if child is Gen2LauncherSheet:
			return child
	return null
