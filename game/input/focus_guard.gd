class_name Gen2FocusGuard
extends Node

## Gives a controller somewhere to start.
##
## Godot moves focus between [Control]s on `ui_up` and the rest of that family,
## but only once something already has focus, and nothing does when a screen
## opens. That is the whole reason a pad did nothing in the launcher: every
## button was focusable and reachable, and none of them was the first.
##
## A mouse or a finger needs no focus ring, so one is only put up while the
## player is on a keyboard or a pad. It is never taken away again, because a
## click that dropped focus would empty the field the click had just filled.
##
## Add one to a screen with [method attach] and call [method refresh] whenever
## what is on that screen changes.

## Where focus should land when there is somewhere better than the first control
## in tree order. A screen whose first control is a corner toggle would otherwise
## start a pad there rather than on what the screen is about.
var preferred: Control = null

var _root: Control = null


func _process(_delta: float) -> void:
	# Lists and detail panes are rebuilt after button presses. If the focused
	# button was part of that rebuild, restore a visible target on the next frame.
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	var direction := Vector2.ZERO
	if event.is_action_pressed("ui_up", true):
		direction = Vector2.UP
	elif event.is_action_pressed("ui_down", true):
		direction = Vector2.DOWN
	elif event.is_action_pressed("ui_left", true):
		direction = Vector2.LEFT
	elif event.is_action_pressed("ui_right", true):
		direction = Vector2.RIGHT
	else:
		return
	if move_focus(direction):
		_root.get_viewport().set_input_as_handled()


## Attaches a guard to [param root] and returns it. The guard is a child of the
## screen it watches, so it goes away with it.
static func attach(root: Control) -> Gen2FocusGuard:
	var guard := Gen2FocusGuard.new()
	guard.name = "FocusGuard"
	guard._root = root
	root.add_child(guard)
	return guard


func _ready() -> void:
	Gen2InputRuntime.instance().device_changed.connect(_on_device_changed)
	# One frame late: a screen built in code has nothing to focus while its own
	# _ready is still running.
	refresh.call_deferred()


## Puts focus on the first control that can take it, if the player is using a
## device that wants one and nothing has it already.
func refresh() -> void:
	if _root == null or not _root.is_inside_tree():
		return
	if Gen2InputDevice.is_pointer(Gen2InputRuntime.instance().device()):
		return
	var viewport: Viewport = _root.get_viewport()
	if viewport == null or viewport.gui_get_focus_owner() != null:
		return
	var target: Control = _wanted()
	if target != null:
		target.grab_focus()


func _wanted() -> Control:
	if (
		preferred != null
		and is_instance_valid(preferred)
		and preferred.is_visible_in_tree()
		and preferred.focus_mode == Control.FOCUS_ALL
		and not _is_disabled(preferred)
	):
		return preferred
	return first_focusable(_root)


func _on_device_changed(_kind: StringName) -> void:
	refresh()


## Directional fallback for layouts Godot cannot join geometrically, notably
## the page host and the floating dock. It only receives an unhandled action,
## so native traversal inside rows, sliders, text fields and scroll panes keeps
## precedence.
func move_focus(direction: Vector2) -> bool:
	if _root == null or not _root.is_inside_tree() or direction == Vector2.ZERO:
		return false
	var viewport: Viewport = _root.get_viewport()
	var current: Control = viewport.gui_get_focus_owner()
	if current == null or not _root.is_ancestor_of(current):
		refresh()
		return viewport.gui_get_focus_owner() != null
	var origin: Vector2 = current.get_global_rect().get_center()
	var best: Control = null
	var best_score: float = INF
	for candidate: Control in focusable_controls(_root):
		if candidate == current:
			continue
		var delta: Vector2 = candidate.get_global_rect().get_center() - origin
		var forward: float = delta.dot(direction)
		if forward <= 1.0:
			continue
		var sideways: float = absf(delta.cross(direction))
		# Prefer the intended axis strongly, while still allowing the dock's
		# offset buttons to be reached from controls near either page edge.
		var score: float = forward + sideways * 2.5
		if score < best_score:
			best_score = score
			best = candidate
	if best == null:
		return false
	best.grab_focus()
	return true


## The first control under [param root] that would accept focus, depth first in
## tree order, which for a screen built top to bottom is the first one a reader
## would point at.
static func first_focusable(root: Node) -> Control:
	for child: Node in root.get_children():
		var control := child as Control
		if control != null:
			if not control.visible:
				continue
			if control.focus_mode == Control.FOCUS_ALL and not _is_disabled(control):
				return control
		var found: Control = first_focusable(child)
		if found != null:
			return found
	return null


static func focusable_controls(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	_collect_focusable(root, out)
	return out


static func _collect_focusable(root: Node, out: Array[Control]) -> void:
	for child: Node in root.get_children():
		var control := child as Control
		if control != null:
			if not control.is_visible_in_tree():
				continue
			if control.focus_mode == Control.FOCUS_ALL and not _is_disabled(control):
				out.append(control)
		_collect_focusable(child, out)


static func _is_disabled(control: Control) -> bool:
	var button := control as BaseButton
	return button != null and button.disabled
