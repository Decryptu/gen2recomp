extends SceneTree

## Checks that every button a launcher screen shows can actually be pressed.
##
##   Godot --path . -s res://tools/preview_clickable.gd
##
## Not headless, and not a `tools/checks/` topic: it reads `root` and
## `gui_get_hovered_control()`, so it needs a real window the way
## `tools/screenshot.gd` does. Run with `--headless` it reports every button as
## unreachable, which is the absent window rather than the screen.
##
## A button that is wired correctly and drawn in the right place is still dead
## if something transparent is sitting on top of it, and nothing in the scene
## tree says so: the overlay is visible, the button is visible, and only the
## viewport's own hit test knows which one a click reaches. So this asks the
## viewport, one button at a time, through the same path a mouse takes.
##
## Not a GUT test. These screens lay themselves out against the window, and the
## test harness gives them neither its size nor a real hit test, so under GUT
## every rect falls outside the viewport and the walk finds nothing to check.
## `test_launcher.gd` keeps the half that is checkable headlessly, which is that
## a toast contains nothing a click can land on.

## The size the launcher is designed against. A window this size puts every
## screen's own actions on screen without scrolling.
const WINDOW := Vector2i(1280, 800)

const SCREENS: Array[String] = [
	"res://game/main/main.tscn",
	"res://game/save/save_screen.tscn",
]

var _screen: Node = null
var _step: int = 0
var _settle: int = 0
var _pending: Array = []
var _checking: Gen2LauncherButton = null
## Frames to let a motion event reach the viewport's hover state before it is
## read back. One is not always enough.
var _aimed: int = 0
var _problems: int = 0
var _checked: int = 0


func _initialize() -> void:
	DisplayServer.window_set_size(WINDOW)
	root.set_content_scale_size(WINDOW)
	root.size = WINDOW
	# The save screen needs a cartridge and a slot to have anything to draw.
	var runtime: Node = root.get_node_or_null(NodePath("GameRuntime"))
	for game_id: StringName in RomRegistry.ORDER:
		var data: GameData = GameData.open(game_id)
		if data == null:
			continue
		runtime.call("select_game", game_id)
		var slots: Array = Gen2SaveStore.slots_for(data.id, data.sha1, data)
		if not slots.is_empty():
			runtime.call("select_save_slot", game_id, int(slots[0]["slot"]))
		break


func _process(_delta: float) -> bool:
	if _checking != null:
		_aimed += 1
		if _aimed < 3:
			return false
		_aimed = 0
		_report(_checking)
		_checking = null
		if _pending.is_empty():
			_screen.free()
			_screen = null
		return false

	if not _pending.is_empty():
		_checking = _pending.pop_front()
		_aim_at(_checking)
		return false

	if _screen != null:
		_settle += 1
		if _settle < 20:
			return false
		_settle = 0
		_collect(_screen, _pending)
		if _pending.is_empty():
			print("  no visible buttons")
			_screen.free()
			_screen = null
		return false

	_settle += 1
	if _settle < 20:
		return false
	_settle = 0
	if _step < SCREENS.size():
		print(SCREENS[_step])
		_screen = load(SCREENS[_step]).instantiate()
		root.add_child(_screen)
		_step += 1
		return false

	print("%d buttons checked, %d unreachable" % [_checked, _problems])
	quit(1 if _problems > 0 else 0)
	return true


func _report(button: Gen2LauncherButton) -> void:
	_checked += 1
	var hovered: Control = root.gui_get_hovered_control()
	var label: String = button.text if not button.text.is_empty() \
		else "<icon at %s>" % button.get_global_rect().position
	if hovered != button:
		_problems += 1
		print("  UNREACHABLE  %-24s a click lands on %s instead" % [
			label, hovered.get_class() if hovered != null else "nothing",
		])
		return
	# One connection is [Gen2LauncherButton]'s own press sound, so a button
	# carrying only that one reaches nothing when it is pressed.
	if button.pressed.get_connections().size() <= 1:
		_problems += 1
		print("  DEAD         %-24s nothing is connected to pressed" % label)


func _aim_at(button: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	motion.global_position = motion.position
	Input.parse_input_event(motion)


## Every button a player can see: on screen, and inside every clipping ancestor.
## One scrolled below a fold is out of view rather than broken, so it is left
## out; the point of the check is the buttons that look pressable.
func _collect(node: Node, out: Array) -> void:
	if node is Gen2LauncherButton and node.is_visible_in_tree() and _on_screen(node):
		out.append(node)
	for child: Node in node.get_children():
		_collect(child, out)


func _on_screen(button: Control) -> bool:
	var rect: Rect2 = button.get_global_rect()
	var parent: Node = button.get_parent()
	while parent is Control:
		var ancestor: Control = parent
		if ancestor.clip_contents and not ancestor.get_global_rect().encloses(rect):
			return false
		parent = ancestor.get_parent()
	return Rect2(Vector2.ZERO, Vector2(WINDOW)).encloses(rect)
