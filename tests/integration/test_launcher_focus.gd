extends GutTest

## Whether a controller has anywhere to start in the launcher.
##
## Godot moves focus between controls on `ui_up` and the rest of that family, but
## only once something already has it, and nothing did. Traversal itself is the
## engine's; what is checked here is that a screen hands over a first control and
## that a modal takes it and gives it back.

var _launcher: Control = null


func before_each() -> void:
	Gen2InputRuntime.instance().apply_options(Gen2Options.new())
	_launcher = load("res://game/main/main.tscn").instantiate() as Control
	add_child_autofree(_launcher)
	await get_tree().process_frame


func after_each() -> void:
	Gen2OptionsStore.use_test_path()


func _use(event: InputEvent) -> void:
	Gen2InputRuntime.instance()._input(event)


func _focus_owner() -> Control:
	return _launcher.get_viewport().gui_get_focus_owner()


func test_a_pad_lands_on_something_it_can_press() -> void:
	_use(InputEventJoypadButton.new())
	await get_tree().process_frame
	await get_tree().process_frame

	var focused: Control = _focus_owner()
	assert_not_null(focused, "a controller needs a first control")
	assert_true(_launcher.is_ancestor_of(focused))
	assert_eq(focused.focus_mode, Control.FOCUS_ALL)


func test_switching_pages_hands_the_ring_to_the_new_one() -> void:
	_use(InputEventJoypadButton.new())
	await get_tree().process_frame
	await get_tree().process_frame

	_launcher.select_page(&"settings")
	await get_tree().process_frame
	await get_tree().process_frame

	var focused: Control = _focus_owner()
	assert_not_null(focused)
	assert_true(focused.is_visible_in_tree(), "focus never lands on a hidden page")


## A mouse needs no ring, and putting one up would move it away from whatever
## the player is pointing at.
func test_a_mouse_is_left_alone() -> void:
	_use(InputEventMouseButton.new())
	var guard: Gen2FocusGuard = _launcher.find_child("FocusGuard", true, false)
	assert_not_null(guard, "the shell carries a guard")

	_launcher.get_viewport().gui_release_focus()
	guard.refresh()
	await get_tree().process_frame
	assert_null(_focus_owner())


func test_the_first_focusable_skips_what_cannot_take_focus() -> void:
	var root := Control.new()
	add_child_autofree(root)
	root.add_child(Label.new())
	var hidden := Button.new()
	hidden.visible = false
	root.add_child(hidden)
	var off := Button.new()
	off.disabled = true
	root.add_child(off)
	var wanted := Button.new()
	root.add_child(wanted)

	assert_same(Gen2FocusGuard.first_focusable(root), wanted)


func test_nothing_focusable_is_not_an_error() -> void:
	var root := Control.new()
	add_child_autofree(root)
	root.add_child(Label.new())
	assert_null(Gen2FocusGuard.first_focusable(root))


## A modal is where a pad has to be, and where it was has to come back, or
## closing a sheet would strand the player with nothing selected.
func test_a_sheet_takes_the_ring_and_gives_it_back() -> void:
	_use(InputEventJoypadButton.new())
	await get_tree().process_frame
	await get_tree().process_frame
	var before: Control = _focus_owner()
	assert_not_null(before)

	var sheet: Gen2LauncherSheet = Gen2LauncherSheet.create(
		Gen2LauncherTheme.active(), "Replace mod"
	)
	sheet.add_action(Gen2LauncherButton.create(
		Gen2LauncherTheme.active(), "Replace", Gen2LauncherButton.Variant.PRIMARY
	))
	sheet.open(_launcher)
	await get_tree().process_frame
	await get_tree().process_frame

	var inside: Control = _focus_owner()
	assert_not_null(inside)
	assert_true(sheet.is_ancestor_of(inside), "the ring moved into the sheet")

	sheet.close()
	await get_tree().process_frame
	assert_same(_focus_owner(), before)


## The cancel used to be read in _gui_input, which only ever reaches the focused
## control, and the sheet itself never holds focus.
func test_cancel_closes_a_sheet_from_a_button_inside_it() -> void:
	var sheet: Gen2LauncherSheet = Gen2LauncherSheet.create(Gen2LauncherTheme.active(), "Sheet")
	sheet.open(_launcher)
	await get_tree().process_frame
	await get_tree().process_frame

	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	sheet._unhandled_input(cancel)
	await get_tree().process_frame

	assert_false(is_instance_valid(sheet) and sheet.is_inside_tree())
