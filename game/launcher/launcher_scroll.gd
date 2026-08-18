class_name Gen2LauncherScroll
extends ScrollContainer

## A vertical scroll pane that can be read without a pointer.
##
## Two things are needed and Godot gives neither by default. A pad walking the
## controls inside a pane has to bring the pane with it, which is
## [member ScrollContainer.follow_focus]. And a pane whose content is mostly text
## has stretches with nothing focusable in them, so the pane itself takes focus
## and reads `ui_up` and `ui_down` as scrolling, which is the only way past a
## wall of prose on a keyboard.
##
## The pane only takes focus when it actually has somewhere to go, so a short
## page does not put a stop on the way down to the dock.

## How far one press moves the pane, as a fraction of what it shows.
const PAGE: float = 0.42


static func create() -> Gen2LauncherScroll:
	var scroll := Gen2LauncherScroll.new()
	# Never `SCROLL_MODE_DISABLED`: that adds the child's whole minimum width to
	# the pane, so one row wider than the window widens the launcher itself
	# rather than being held inside the pane. Hidden instead, and the rows stack
	# or wrap ([FieldRow], `controls_section.gd`) so nothing needs the axis.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	return scroll


func _ready() -> void:
	get_v_scroll_bar().changed.connect(_refresh_focus_mode)
	resized.connect(_refresh_focus_mode)
	_refresh_focus_mode()


func _gui_input(event: InputEvent) -> void:
	if not _scrollable():
		return
	var step: float = maxf(size.y * PAGE, 40.0)
	if event.is_action_pressed("ui_down", true):
		accept_event()
		scroll_vertical = int(float(scroll_vertical) + step)
	elif event.is_action_pressed("ui_up", true):
		accept_event()
		scroll_vertical = int(float(scroll_vertical) - step)


## Whether there is more here than fits, which is the only case where the pane is
## worth stopping on.
func _scrollable() -> bool:
	var bar: VScrollBar = get_v_scroll_bar()
	return bar != null and bar.max_value > bar.page


func _refresh_focus_mode() -> void:
	focus_mode = Control.FOCUS_ALL if _scrollable() else Control.FOCUS_NONE
