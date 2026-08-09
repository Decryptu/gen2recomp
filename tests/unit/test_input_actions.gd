extends GutTest

## The button vocabulary and the bindings behind it.
##
## The [InputMap] is global engine state, so every test that installs a scheme
## puts the defaults back afterwards rather than leaving the next one to guess.


func after_each() -> void:
	Gen2InputActions.install(Gen2InputActions.defaults())


func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func test_every_button_has_an_action_and_maps_back() -> void:
	assert_eq(Gen2Button.ALL.size(), 8)
	for button: int in Gen2Button.ALL:
		var action: StringName = Gen2Button.action(button)
		assert_false(action.is_empty(), "button %d has an action" % button)
		assert_eq(Gen2Button.from_action(action), button)
	assert_eq(Gen2Button.from_action(&"not_a_button"), Gen2Button.NONE)


func test_directions_carry_vectors_both_ways() -> void:
	assert_eq(Gen2Button.DIRECTIONS.size(), 4)
	for button: int in Gen2Button.DIRECTIONS:
		assert_true(Gen2Button.is_direction(button))
		assert_eq(Gen2Button.from_vector(Gen2Button.vector(button)), button)
	assert_false(Gen2Button.is_direction(Gen2Button.A))
	assert_eq(Gen2Button.vector(Gen2Button.A), Vector2i.ZERO)
	assert_eq(Gen2Button.from_vector(Vector2i(1, 1)), Gen2Button.NONE)


func test_defaults_bind_every_button_on_both_devices() -> void:
	var scheme: Dictionary = Gen2InputActions.defaults()
	for button: int in Gen2Button.ALL:
		var devices: Array[StringName] = []
		for binding: Dictionary in scheme[button]:
			var device: StringName = Gen2InputActions.device_of(binding)
			if not devices.has(device):
				devices.append(device)
		assert_true(
			devices.has(Gen2InputActions.DEVICE_KEYBOARD),
			"%s has a key" % Gen2Button.label(button),
		)
		assert_true(
			devices.has(Gen2InputActions.DEVICE_GAMEPAD),
			"%s has a pad binding" % Gen2Button.label(button),
		)


func test_defaults_are_a_copy_the_caller_may_edit() -> void:
	var scheme: Dictionary = Gen2InputActions.defaults()
	(scheme[Gen2Button.A] as Array).clear()
	assert_false((Gen2InputActions.defaults()[Gen2Button.A] as Array).is_empty())


## Rebuilt, not merged: a rebind that only added would leave the old key working
## and the settings page would be lying about what is bound.
func test_install_replaces_the_previous_scheme() -> void:
	Gen2InputActions.install(Gen2InputActions.defaults())
	assert_true(_key(KEY_Z).is_action_pressed(&"gen2_a"))

	var scheme: Dictionary = Gen2InputActions.defaults()
	scheme[Gen2Button.A] = [{"kind": Gen2InputActions.KIND_KEY, "code": KEY_M}]
	Gen2InputActions.install(scheme)

	assert_true(_key(KEY_M).is_action_pressed(&"gen2_a"))
	assert_false(_key(KEY_Z).is_action_pressed(&"gen2_a"))
	assert_eq(InputMap.action_get_events(&"gen2_a").size(), 1)


func test_install_sets_the_deadzone_a_stick_needs() -> void:
	Gen2InputActions.install(Gen2InputActions.defaults())
	assert_eq(InputMap.action_get_deadzone(&"gen2_up"), Gen2InputActions.DEADZONE)


func test_events_round_trip_through_bindings() -> void:
	var cases: Array[Dictionary] = [
		{"kind": Gen2InputActions.KIND_KEY, "code": KEY_Q},
		{"kind": Gen2InputActions.KIND_PAD_BUTTON, "code": JOY_BUTTON_X},
		{"kind": Gen2InputActions.KIND_PAD_AXIS, "code": JOY_AXIS_LEFT_Y, "sign": -1},
	]
	for binding: Dictionary in cases:
		var event: InputEvent = Gen2InputActions.to_event(binding)
		assert_not_null(event, String(binding["kind"]))
		assert_eq(Gen2InputActions.from_event(event), binding)


func test_a_key_binding_is_physical_only() -> void:
	var event: InputEventKey = Gen2InputActions.to_event(
		{"kind": Gen2InputActions.KIND_KEY, "code": KEY_W}
	)
	assert_eq(event.physical_keycode, KEY_W)
	assert_eq(event.keycode, KEY_NONE, "a second code would match twice on one layout")


func test_pad_bindings_match_every_device() -> void:
	for binding: Dictionary in [
		{"kind": Gen2InputActions.KIND_PAD_BUTTON, "code": JOY_BUTTON_A},
		{"kind": Gen2InputActions.KIND_PAD_AXIS, "code": JOY_AXIS_LEFT_X, "sign": 1},
	]:
		assert_eq(
			Gen2InputActions.to_event(binding).device,
			Gen2InputActions.ALL_DEVICES,
			"the other port is not a rebind",
		)


## A stick resting near centre reports motion constantly, and none of it is a
## binding the player meant to make.
func test_a_resting_stick_is_not_a_binding() -> void:
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 0.1
	assert_eq(Gen2InputActions.from_event(motion), {})

	motion.axis_value = -0.9
	assert_eq(int(Gen2InputActions.from_event(motion)["sign"]), -1)


func test_unusable_events_are_not_bindings() -> void:
	assert_eq(Gen2InputActions.from_event(InputEventMouseMotion.new()), {})
	assert_eq(Gen2InputActions.from_event(InputEventKey.new()), {})


func test_sanitize_returns_the_defaults_for_anything_unreadable() -> void:
	for raw: Variant in [null, 7, "controls", []]:
		assert_true(
			Gen2InputActions.is_default(Gen2InputActions.sanitize(raw)),
			"unreadable input falls back",
		)


func test_sanitize_reads_a_stored_scheme_back() -> void:
	var scheme: Dictionary = Gen2InputActions.defaults()
	scheme[Gen2Button.START] = [{"kind": Gen2InputActions.KIND_KEY, "code": KEY_F8}]
	var restored: Dictionary = Gen2InputActions.sanitize(Gen2InputActions.to_dict(scheme))
	assert_eq(restored[Gen2Button.START], scheme[Gen2Button.START])


## Clamped, not refused: one unreadable binding costs that binding, and a button
## left with none at all keeps its default rather than becoming unpressable.
func test_sanitize_drops_bad_rows_and_keeps_a_button_pressable() -> void:
	var stored: Dictionary = Gen2InputActions.to_dict(Gen2InputActions.defaults())
	stored["gen2_b"] = [
		{"kind": "sorcery", "code": 4},
		{"kind": Gen2InputActions.KIND_KEY, "code": 0},
		{"kind": Gen2InputActions.KIND_PAD_BUTTON, "code": -3},
		"not a row",
		{"kind": Gen2InputActions.KIND_KEY, "code": KEY_N},
	]
	stored["gen2_a"] = []
	var scheme: Dictionary = Gen2InputActions.sanitize(stored)

	assert_eq(scheme[Gen2Button.B], [{"kind": Gen2InputActions.KIND_KEY, "code": KEY_N}])
	assert_eq(scheme[Gen2Button.A], Gen2InputActions.defaults()[Gen2Button.A])


func test_sanitize_drops_duplicates_and_bounds_the_count() -> void:
	var stored: Dictionary = Gen2InputActions.to_dict(Gen2InputActions.defaults())
	var rows: Array = []
	for index: int in Gen2InputActions.MAX_BINDINGS + 4:
		rows.append({"kind": Gen2InputActions.KIND_KEY, "code": KEY_A + index})
	rows.append({"kind": Gen2InputActions.KIND_KEY, "code": KEY_A})
	stored["gen2_select"] = rows
	var bindings: Array = Gen2InputActions.sanitize(stored)[Gen2Button.SELECT]

	assert_eq(bindings.size(), Gen2InputActions.MAX_BINDINGS)
	assert_eq(bindings[0], {"kind": Gen2InputActions.KIND_KEY, "code": KEY_A})


func test_conflicts_names_the_other_buttons_holding_a_binding() -> void:
	var scheme: Dictionary = Gen2InputActions.defaults()
	var space: Dictionary = {"kind": Gen2InputActions.KIND_KEY, "code": KEY_SPACE}

	assert_eq(Gen2InputActions.conflicts(scheme, space, Gen2Button.A), [] as Array[int])
	assert_eq(Gen2InputActions.conflicts(scheme, space, Gen2Button.B), [Gen2Button.A] as Array[int])


func test_describe_names_each_kind() -> void:
	assert_eq(
		Gen2InputActions.describe({"kind": Gen2InputActions.KIND_PAD_BUTTON, "code": JOY_BUTTON_START}),
		"Start",
	)
	assert_eq(
		Gen2InputActions.describe({
			"kind": Gen2InputActions.KIND_PAD_AXIS, "code": JOY_AXIS_LEFT_Y, "sign": 1,
		}),
		"Left stick down",
	)
	assert_eq(Gen2InputActions.describe({}), "Unbound")
	assert_false(
		Gen2InputActions.describe({"kind": Gen2InputActions.KIND_KEY, "code": KEY_SPACE}).is_empty()
	)


func test_a_key_beyond_the_named_pad_buttons_still_reads() -> void:
	assert_string_contains(
		Gen2InputActions.describe({"kind": Gen2InputActions.KIND_PAD_BUTTON, "code": 99}), "99"
	)
