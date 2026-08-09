extends GutTest

## Seeing and changing the controls from the launcher.

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
	Gen2OptionsStore.forget_cached()
	DirAccess.remove_absolute(Gen2OptionsStore.PATH)
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


func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


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
	sheet._unhandled_input(_key(KEY_F7))

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
	sheet._unhandled_input(_key(KEY_Z))

	assert_eq(_options.controls[Gen2Button.A], before)


## One key on two buttons is the player's call. The sheet says so and allows it.
func test_a_binding_already_on_another_button_is_reported_not_refused() -> void:
	var sheet: Gen2BindingSheet = await _open(Gen2Button.B)
	sheet._start_capture()
	sheet._unhandled_input(_key(KEY_SPACE))

	assert_true((_options.controls[Gen2Button.B] as Array).has(
		{"kind": Gen2InputActions.KIND_KEY, "code": KEY_SPACE}
	))
	assert_string_contains(sheet.get("_prompt").text, Gen2Button.label(Gen2Button.A))


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
