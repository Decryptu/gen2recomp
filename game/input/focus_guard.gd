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

var _root: Control = null


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
	var target: Control = first_focusable(_root)
	if target != null:
		target.grab_focus()


func _on_device_changed(_kind: StringName) -> void:
	refresh()


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


static func _is_disabled(control: Control) -> bool:
	var button := control as BaseButton
	return button != null and button.disabled
