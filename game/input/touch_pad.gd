class_name Gen2TouchPad
extends Control

## The on-screen controller: a d-pad, A and B, START and SELECT.
##
## Godot ships no such thing for a [Control] interface, so this is ours. It
## draws what [Gen2TouchLayout] places and turns a finger into the same button a
## key or a pad produces, by way of [Gen2InputRuntime], so no screen has to know a
## touchscreen exists.
##
## Touches are read in [method _input] rather than [method _gui_input] because
## more than one finger is normal here: a thumb walking while the other presses
## A is two live touches, and the GUI layer only ever tracks one pointer.
##
## In edit mode nothing is pressed and a drag moves a cluster instead. The
## layout handed to [method set_layout] is edited in place, which is how the
## settings page arranges the live one and has nothing to copy back.

const FILL: Color = Color(1.0, 1.0, 1.0, 0.14)
const FILL_PRESSED: Color = Color(1.0, 1.0, 1.0, 0.42)
const BORDER: Color = Color(1.0, 1.0, 1.0, 0.55)
const GLYPH: Color = Color(1.0, 1.0, 1.0, 0.85)
const EDIT_TINT: Color = Color(0.36, 0.72, 1.0, 0.55)
const BORDER_WIDTH: float = 2.0
## Of the d-pad's own width, for each arm of the cross.
const CROSS_ARM: float = 0.36
## No touchscreen reports an index this low, so the mouse can share the touch
## bookkeeping in edit mode without ever colliding with a finger.
const MOUSE_TOUCH_INDEX: int = -1

var _layout: Gen2TouchLayout = Gen2TouchLayout.new()
## Whether a caller handed one over. The settings preview edits the live layout
## object, so entering the tree must not swap it for the stored one.
var _layout_given: bool = false
var _edit_mode: bool = false
## Touch index to the [InputMap] action it is on, which is one of the eight or a
## mod's own. A finger sliding off one button onto another swaps which, so the
## d-pad can be rolled around without lifting.
var _touches: Dictionary = {}
## Action to how many touches are on it, so two thumbs on A do not release it
## when the first lifts.
var _held: Dictionary = {}
## In edit mode: the group being dragged, which pointer has it, and where in it
## the drag started.
var _dragging: StringName = &""
var _drag_index: int = 0
var _drag_offset: Vector2 = Vector2.ZERO


func _enter_tree() -> void:
	Gen2InputRuntime.instance().claim_touch_pad(self)


func _ready() -> void:
	# The pad is drawn over the game and must never take a click away from it.
	# Touches arrive through _input, which does not go through this filter.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _layout_given:
		_layout = Gen2InputRuntime.instance().touch_layout()
	Gen2InputRuntime.instance().touch_controls_changed.connect(_on_touch_controls_changed)
	_on_touch_controls_changed(Gen2InputRuntime.instance().touch_controls_shown())


func _exit_tree() -> void:
	# A button left held by a screen change would walk the player into a wall
	# for as long as the next screen is up.
	release_all()
	Gen2InputRuntime.instance().release_touch_pad(self)


func set_layout(new_layout: Gen2TouchLayout) -> void:
	_layout = new_layout if new_layout != null else Gen2TouchLayout.new()
	_layout_given = true
	queue_redraw()


func layout() -> Gen2TouchLayout:
	return _layout


## Turns pressing off and dragging on, for the settings page's live preview.
func set_edit_mode(editing: bool) -> void:
	if _edit_mode == editing:
		return
	_edit_mode = editing
	release_all()
	_dragging = &""
	_on_touch_controls_changed(Gen2InputRuntime.instance().touch_controls_shown())
	queue_redraw()


func is_editing() -> bool:
	return _edit_mode


func area() -> Rect2:
	return Rect2(Vector2.ZERO, size)


## Which button a point in the pad's own coordinates would press. Public so a
## test can ask without a touchscreen.
func button_at(point: Vector2) -> int:
	return _layout.button_at(point, area())


## The action a point presses: one of the eight, or a mod's own button, or an
## empty name. The eight are asked first, so a mod's button laid over the d-pad
## costs the mod its press rather than costing the player a step.
func action_at(point: Vector2) -> StringName:
	var button: int = button_at(point)
	if button != Gen2Button.NONE:
		return Gen2Button.action(button)
	return _layout.mod_action_at(point, area())


## Whether this is the controller in front. A battle opened over the map has one
## of its own, and the map's must neither draw behind it nor answer a finger
## meant for it.
func is_active() -> bool:
	return Gen2InputRuntime.instance().active_touch_pad() == self


func _on_touch_controls_changed(shown: bool) -> void:
	# Edit mode is a preview and shows whatever the player is arranging, even
	# when the setting would hide it everywhere else.
	visible = (shown or _edit_mode) and is_active()
	if not visible:
		release_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or not is_active():
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = make_input_local(event)
		_pointer(touch.index, touch.position, touch.pressed)
		return
	if event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = make_input_local(event)
		_pointer_moved(drag.index, drag.position)
		return
	# The mouse drives the layout editor, which is arranged on a desktop as
	# often as on the device it is for. It never presses a button: outside edit
	# mode a mouse means the player is not using the touchscreen at all.
	if not _edit_mode:
		return
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = make_input_local(event)
		if click.button_index == MOUSE_BUTTON_LEFT:
			_pointer(MOUSE_TOUCH_INDEX, click.position, click.pressed)
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = make_input_local(event)
		_pointer_moved(MOUSE_TOUCH_INDEX, motion.position)


func _pointer(index: int, point: Vector2, pressed: bool) -> void:
	if _edit_mode:
		_edit_pointer(index, point, pressed)
		return
	if pressed:
		var action: StringName = action_at(point)
		if String(action).is_empty():
			return
		_touches[index] = action
		_apply_held()
		get_viewport().set_input_as_handled()
		return
	if not _touches.has(index):
		return
	_touches.erase(index)
	_apply_held()


func _pointer_moved(index: int, point: Vector2) -> void:
	if _edit_mode:
		_edit_moved(index, point)
		return
	if not _touches.has(index):
		return
	var action: StringName = action_at(point)
	# Sliding off the controller entirely keeps the last button held: a thumb
	# that drifts a few pixels past the d-pad mid-step should not stop the walk.
	if String(action).is_empty() or action == StringName(_touches[index]):
		return
	_touches[index] = action
	_apply_held()


## Sends the difference between what is held and what was, so a button already
## down is not pressed twice and one under two fingers stays down until both
## lift.
func _apply_held() -> void:
	var wanted: Dictionary = {}
	for index: int in _touches:
		var action: StringName = _touches[index]
		wanted[action] = int(wanted.get(action, 0)) + 1
	for action: StringName in _held:
		if not wanted.has(action):
			Gen2InputRuntime.instance().send_action(action, false)
	for action: StringName in wanted:
		if not _held.has(action):
			Gen2InputRuntime.instance().send_action(action, true)
	_held = wanted
	queue_redraw()


## Lets go of everything. Called when the pad is hidden, edited or removed,
## since a button held across any of those has nothing left to release it.
func release_all() -> void:
	_touches.clear()
	_apply_held()


func _edit_pointer(index: int, point: Vector2, pressed: bool) -> void:
	if not pressed:
		if _dragging != &"" and index == _drag_index:
			_dragging = &""
		return
	if _dragging != &"":
		return
	for group: StringName in _placeable_groups():
		var rect: Rect2 = _layout.group_rect(group, area())
		if rect.has_point(point):
			_dragging = group
			_drag_index = index
			_drag_offset = point - rect.get_center()
			return


func _edit_moved(index: int, point: Vector2) -> void:
	if _dragging == &"" or index != _drag_index or size.x <= 0.0 or size.y <= 0.0:
		return
	_layout.set_anchor(
		Gen2TouchLayout.orientation_of(size), _dragging, (point - _drag_offset) / size, size
	)
	queue_redraw()


func _draw() -> void:
	var rect: Rect2 = area()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var alpha: float = _layout.opacity
	_draw_cross(_layout.group_rect(Gen2TouchLayout.GROUP_PAD, rect), alpha)
	var rects: Dictionary = _layout.button_rects(rect)
	for button: int in [Gen2Button.A, Gen2Button.B]:
		_draw_round(rects[button], Gen2Button.label(button), alpha, _is_held(button))
	for button: int in [Gen2Button.SELECT, Gen2Button.START]:
		_draw_pill(rects[button], Gen2Button.label(button), alpha, _is_held(button))
	var mod_rects: Dictionary = _layout.mod_button_rects(rect)
	for action: StringName in mod_rects:
		_draw_pill(
			mod_rects[action], _layout.mod_label(action), alpha, _held.has(action)
		)
	if _edit_mode:
		for group: StringName in _placeable_groups():
			draw_rect(_layout.group_rect(group, rect), EDIT_TINT, false, BORDER_WIDTH)


## The cross, as one horizontal and one vertical bar. The held arm is filled
## over the top rather than drawn instead, so the shape never changes size when
## it is pressed.
func _draw_cross(rect: Rect2, alpha: float) -> void:
	var arm: Vector2 = rect.size * CROSS_ARM
	var horizontal := Rect2(
		Vector2(rect.position.x, rect.get_center().y - arm.y * 0.5),
		Vector2(rect.size.x, arm.y),
	)
	var vertical := Rect2(
		Vector2(rect.get_center().x - arm.x * 0.5, rect.position.y),
		Vector2(arm.x, rect.size.y),
	)
	for bar: Rect2 in [horizontal, vertical]:
		_draw_rounded_box(bar, _tint(FILL, alpha), _tint(BORDER, alpha))
	for button: int in Gen2Button.DIRECTIONS:
		if not _is_held(button):
			continue
		var step: Vector2 = Vector2(Gen2Button.vector(button))
		var span: Vector2 = Vector2(
			arm.x if step.x == 0.0 else (rect.size.x - arm.x) * 0.5,
			arm.y if step.y == 0.0 else (rect.size.y - arm.y) * 0.5,
		)
		var centre: Vector2 = rect.get_center() + step * (rect.size - span) * 0.5
		_draw_rounded_box(Rect2(centre - span * 0.5, span), _tint(FILL_PRESSED, alpha))


func _draw_rounded_box(rect: Rect2, fill: Color, border: Color = Color.TRANSPARENT) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	if border.a > 0.0:
		box.set_border_width_all(int(BORDER_WIDTH))
	box.set_corner_radius_all(int(minf(rect.size.x, rect.size.y) * 0.16))
	draw_style_box(box, rect)


func _draw_round(rect: Rect2, text: String, alpha: float, pressed: bool) -> void:
	var radius: float = rect.size.x * 0.5
	draw_circle(rect.get_center(), radius, _tint(FILL_PRESSED if pressed else FILL, alpha))
	draw_circle(rect.get_center(), radius, _tint(BORDER, alpha), false, BORDER_WIDTH)
	_draw_label(rect, text, alpha, radius * 0.9)


func _draw_pill(rect: Rect2, text: String, alpha: float, pressed: bool) -> void:
	var radius: float = rect.size.y * 0.5
	var box := StyleBoxFlat.new()
	box.bg_color = _tint(FILL_PRESSED if pressed else FILL, alpha)
	box.border_color = _tint(BORDER, alpha)
	box.set_border_width_all(int(BORDER_WIDTH))
	box.set_corner_radius_all(int(radius))
	draw_style_box(box, rect)
	_draw_label(rect, text, alpha, rect.size.y * 0.52)


func _draw_label(rect: Rect2, text: String, alpha: float, size_pixels: float) -> void:
	var font: Font = get_theme_default_font()
	if font == null or text.is_empty():
		return
	var height: int = maxi(8, int(size_pixels))
	var measured: Vector2 = font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, height
	)
	# draw_string takes a baseline, so the centre has to be walked back by half
	# the string and up by half the difference between ascent and descent.
	var baseline: Vector2 = rect.get_center() + Vector2(
		-measured.x * 0.5, (font.get_ascent(height) - font.get_descent(height)) * 0.5
	)
	draw_string(
		font,
		baseline,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		height,
		_tint(GLYPH, alpha),
	)


func _is_held(button: int) -> bool:
	return _held.has(Gen2Button.action(button))


## Every cluster a drag may move: the stock four, then a mod's own buttons while
## the player has them switched on.
func _placeable_groups() -> Array[StringName]:
	var groups: Array[StringName] = Gen2TouchLayout.GROUPS.duplicate()
	groups.append_array(_layout.mod_groups())
	return groups


static func _tint(colour: Color, alpha: float) -> Color:
	return Color(colour.r, colour.g, colour.b, colour.a * alpha)
