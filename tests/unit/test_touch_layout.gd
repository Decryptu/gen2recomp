extends GutTest

## Where the on-screen controller's clusters land, and what a point presses.

const PORTRAIT := Rect2(Vector2.ZERO, Vector2(480, 700))
const LANDSCAPE := Rect2(Vector2.ZERO, Vector2(960, 480))


func _layout() -> Gen2TouchLayout:
	return Gen2TouchLayout.new()


func test_orientation_follows_the_area() -> void:
	assert_eq(
		Gen2TouchLayout.orientation_of(Vector2(480, 700)),
		Gen2TouchLayout.ORIENTATION_PORTRAIT,
	)
	assert_eq(
		Gen2TouchLayout.orientation_of(Vector2(960, 480)),
		Gen2TouchLayout.ORIENTATION_LANDSCAPE,
	)
	assert_eq(
		Gen2TouchLayout.orientation_of(Vector2(500, 500)),
		Gen2TouchLayout.ORIENTATION_LANDSCAPE,
		"a square area is not portrait",
	)


func test_every_group_is_inside_the_area_in_both_orientations() -> void:
	var layout: Gen2TouchLayout = _layout()
	for area: Rect2 in [PORTRAIT, LANDSCAPE]:
		for group: StringName in Gen2TouchLayout.GROUPS:
			var rect: Rect2 = layout.group_rect(group, area)
			assert_true(
				area.encloses(rect),
				"%s fits %s" % [group, area.size],
			)


## Landscape centres the hardware screen and leaves the margins, so nothing may
## sit across the middle where the game is.
func test_landscape_keeps_the_clusters_off_the_centre() -> void:
	var layout: Gen2TouchLayout = _layout()
	var middle: float = LANDSCAPE.size.x * 0.5
	for group: StringName in Gen2TouchLayout.GROUPS:
		var rect: Rect2 = layout.group_rect(group, LANDSCAPE)
		assert_false(
			rect.position.x < middle and rect.end.x > middle,
			"%s clears the screen" % group,
		)


func test_the_dpad_reads_by_dominant_axis() -> void:
	var layout: Gen2TouchLayout = _layout()
	var rect: Rect2 = layout.group_rect(Gen2TouchLayout.GROUP_PAD, PORTRAIT)
	var centre: Vector2 = rect.get_center()
	var reach: float = rect.size.x * 0.45

	assert_eq(layout.direction_at(centre + Vector2(0, -reach), PORTRAIT), Gen2Button.UP)
	assert_eq(layout.direction_at(centre + Vector2(0, reach), PORTRAIT), Gen2Button.DOWN)
	assert_eq(layout.direction_at(centre + Vector2(-reach, 0), PORTRAIT), Gen2Button.LEFT)
	assert_eq(layout.direction_at(centre + Vector2(reach, 0), PORTRAIT), Gen2Button.RIGHT)


## A corner gives one direction, not two: nothing in either game moves
## diagonally, and a press that walked twice would be wrong in a menu as well.
func test_a_corner_of_the_dpad_gives_one_direction() -> void:
	var layout: Gen2TouchLayout = _layout()
	var rect: Rect2 = layout.group_rect(Gen2TouchLayout.GROUP_PAD, PORTRAIT)
	var corner: Vector2 = rect.get_center() + rect.size * 0.35
	assert_eq(layout.direction_at(corner, PORTRAIT), Gen2Button.RIGHT)


func test_a_thumb_resting_dead_centre_presses_nothing() -> void:
	var layout: Gen2TouchLayout = _layout()
	var rect: Rect2 = layout.group_rect(Gen2TouchLayout.GROUP_PAD, PORTRAIT)
	assert_eq(layout.direction_at(rect.get_center(), PORTRAIT), Gen2Button.NONE)
	assert_eq(layout.button_at(rect.get_center(), PORTRAIT), Gen2Button.NONE)


func test_a_point_outside_the_dpad_is_not_a_direction() -> void:
	var layout: Gen2TouchLayout = _layout()
	assert_eq(layout.direction_at(Vector2(-40, -40), PORTRAIT), Gen2Button.NONE)


func test_each_face_and_menu_button_is_pressable_at_its_own_centre() -> void:
	var layout: Gen2TouchLayout = _layout()
	var rects: Dictionary = layout.button_rects(PORTRAIT)
	for button: int in [Gen2Button.A, Gen2Button.B, Gen2Button.START, Gen2Button.SELECT]:
		assert_true(rects.has(button), Gen2Button.label(button))
		assert_eq(
			layout.button_at((rects[button] as Rect2).get_center(), PORTRAIT),
			button,
			Gen2Button.label(button),
		)


func test_a_is_below_and_left_of_b() -> void:
	var rects: Dictionary = _layout().button_rects(PORTRAIT)
	var a: Rect2 = rects[Gen2Button.A]
	var b: Rect2 = rects[Gen2Button.B]
	assert_lt(a.get_center().x, b.get_center().x)
	assert_gt(a.get_center().y, b.get_center().y)


func test_scale_grows_every_group() -> void:
	var layout: Gen2TouchLayout = _layout()
	var before: Vector2 = layout.group_size(Gen2TouchLayout.GROUP_PAD)
	layout.scale = Gen2TouchLayout.MAX_SCALE
	assert_gt(layout.group_size(Gen2TouchLayout.GROUP_PAD).x, before.x)


## The one way an options screen could hand back a layout nobody can press.
func test_a_group_cannot_be_dragged_off_the_area() -> void:
	var layout: Gen2TouchLayout = _layout()
	layout.set_anchor(
		Gen2TouchLayout.ORIENTATION_PORTRAIT,
		Gen2TouchLayout.GROUP_PAD,
		Vector2(-3.0, 5.0),
		PORTRAIT.size,
	)
	assert_true(PORTRAIT.encloses(layout.group_rect(Gen2TouchLayout.GROUP_PAD, PORTRAIT)))


func test_an_unknown_group_or_orientation_moves_nothing() -> void:
	var layout: Gen2TouchLayout = _layout()
	var before: Vector2 = layout.anchor(
		Gen2TouchLayout.ORIENTATION_PORTRAIT, Gen2TouchLayout.GROUP_PAD
	)
	layout.set_anchor(&"sideways", Gen2TouchLayout.GROUP_PAD, Vector2(0.9, 0.9), PORTRAIT.size)
	layout.set_anchor(
		Gen2TouchLayout.ORIENTATION_PORTRAIT, &"shoulder", Vector2(0.9, 0.9), PORTRAIT.size
	)
	layout.set_anchor(
		Gen2TouchLayout.ORIENTATION_PORTRAIT, Gen2TouchLayout.GROUP_PAD, Vector2(0.9, 0.9),
		Vector2.ZERO,
	)
	assert_eq(layout.anchor(Gen2TouchLayout.ORIENTATION_PORTRAIT, Gen2TouchLayout.GROUP_PAD), before)


func test_the_two_orientations_are_kept_apart() -> void:
	var layout: Gen2TouchLayout = _layout()
	var landscape_before: Vector2 = layout.anchor(
		Gen2TouchLayout.ORIENTATION_LANDSCAPE, Gen2TouchLayout.GROUP_PAD
	)
	layout.set_anchor(
		Gen2TouchLayout.ORIENTATION_PORTRAIT, Gen2TouchLayout.GROUP_PAD,
		Vector2(0.5, 0.5), PORTRAIT.size,
	)
	assert_eq(
		layout.anchor(Gen2TouchLayout.ORIENTATION_LANDSCAPE, Gen2TouchLayout.GROUP_PAD),
		landscape_before,
	)


func test_a_layout_survives_the_options_file() -> void:
	var layout: Gen2TouchLayout = _layout()
	layout.scale = 1.4
	layout.opacity = 0.5
	layout.set_anchor(
		Gen2TouchLayout.ORIENTATION_LANDSCAPE, Gen2TouchLayout.GROUP_FACE,
		Vector2(0.7, 0.3), LANDSCAPE.size,
	)
	var restored: Gen2TouchLayout = Gen2TouchLayout.parse(
		JSON.parse_string(JSON.stringify(layout.to_dict()))
	)
	assert_eq(restored.to_dict(), layout.to_dict())
	assert_false(restored.is_default())


func test_an_unreadable_layout_clamps_to_the_defaults() -> void:
	for raw: Variant in [null, "layout", 3]:
		assert_true(Gen2TouchLayout.parse(raw).is_default())
	var partial: Gen2TouchLayout = Gen2TouchLayout.parse({
		"scale": 99.0,
		"opacity": -4.0,
		"portrait": {"pad": "over there", "face": [2.0, -1.0]},
	})
	assert_eq(partial.scale, Gen2TouchLayout.MAX_SCALE)
	assert_eq(partial.opacity, Gen2TouchLayout.MIN_OPACITY)
	assert_eq(
		partial.anchor(Gen2TouchLayout.ORIENTATION_PORTRAIT, Gen2TouchLayout.GROUP_PAD),
		Gen2TouchLayout.DEFAULT_ANCHORS[Gen2TouchLayout.ORIENTATION_PORTRAIT][Gen2TouchLayout.GROUP_PAD],
	)
	assert_eq(
		partial.anchor(Gen2TouchLayout.ORIENTATION_PORTRAIT, Gen2TouchLayout.GROUP_FACE),
		Vector2(1.0, 0.0),
	)


func test_a_duplicate_is_independent_of_the_original() -> void:
	var layout: Gen2TouchLayout = _layout()
	var copy: Gen2TouchLayout = layout.duplicate_layout()
	copy.scale = 1.5
	copy.set_anchor(
		Gen2TouchLayout.ORIENTATION_PORTRAIT, Gen2TouchLayout.GROUP_PAD,
		Vector2(0.6, 0.6), PORTRAIT.size,
	)
	assert_true(layout.is_default())


## A mod's own controls have to reach a phone player, and must not cover the
## screen of one who never asked for them.
func test_mod_buttons_are_off_until_the_player_switches_them_on() -> void:
	var layout: Gen2TouchLayout = _layout()
	layout.mod_buttons = [
		{"action": &"mod_voxel_pitch_up", "label": "Camera up"},
		{"action": &"mod_voxel_pitch_down", "label": "Camera down"},
	]
	assert_true(layout.mod_groups().is_empty(), "off by default")
	assert_true(layout.mod_button_rects(PORTRAIT).is_empty())

	layout.mod_buttons_shown = true
	assert_eq(layout.mod_groups().size(), 2)
	assert_eq(layout.mod_label(&"mod_voxel_pitch_up"), "Camera up")
	var rects: Dictionary = layout.mod_button_rects(PORTRAIT)
	assert_eq(rects.size(), 2)
	# Each is pressable at its own centre and stacked clear of the one above.
	for action: StringName in rects:
		assert_eq(layout.mod_action_at((rects[action] as Rect2).get_center(), PORTRAIT), action)
	assert_false(
		(rects[&"mod_voxel_pitch_up"] as Rect2).intersects(rects[&"mod_voxel_pitch_down"])
	)


func test_a_mod_button_is_placed_and_survives_the_options_file() -> void:
	var layout: Gen2TouchLayout = _layout()
	layout.mod_buttons = [{"action": &"mod_voxel_pitch_up", "label": "Camera up"}]
	layout.mod_buttons_shown = true
	layout.set_anchor(
		Gen2TouchLayout.ORIENTATION_PORTRAIT, &"mod_voxel_pitch_up",
		Vector2(0.3, 0.7), PORTRAIT.size,
	)
	var stored: Gen2TouchLayout = Gen2TouchLayout.parse(layout.to_dict())
	assert_true(stored.mod_buttons_shown)
	# The placement is read back without knowing which mods are installed, so an
	# uninstalled mod's position waits rather than being thrown away.
	assert_eq(
		stored.anchor(Gen2TouchLayout.ORIENTATION_PORTRAIT, &"mod_voxel_pitch_up"),
		Vector2(0.3, 0.7),
	)
	assert_false(layout.is_default())
