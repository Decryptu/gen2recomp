class_name Gen2GameFrame
extends Control

## Places the hardware screen and the on-screen controller, in either
## orientation and at any window size.
##
## Portrait sends the screen to the top and gives the controller the room under
## it, which is the shape a phone held upright has and the only arrangement
## where a thumb is not over the map. Landscape centres the screen and leaves
## the margins either side, which is where the thumbs already are on a phone
## held sideways.
##
## With no controller on screen both cases are the same: the screen centres in
## the whole frame, so a desktop window looks exactly as it did.
##
## The frame also owns the way back from hidden controls. The gesture is watched
## here rather than in [Gen2TouchPad] because a hidden pad is exactly when it is
## needed, and it has to be reachable from anywhere on the game screen.

## How much of a portrait screen the controller may take. The hardware screen is
## 10:9, so even a tall phone has this much left over once the map has its share.
const PORTRAIT_CONTROL_SHARE: float = 0.44

var _screen: Gen2Screen = null
var _pad: Gen2TouchPad = null
var _gesture := Gen2TapGesture.new()


func _ready() -> void:
	# Found by type rather than by name: both scenes that use a frame build the
	# same two children, and neither should have to agree on a path as well.
	for child: Node in get_children():
		if child is Gen2Screen:
			_screen = child
		elif child is Gen2TouchPad:
			_pad = child
	resized.connect(_relayout)
	Gen2InputRuntime.instance().touch_controls_changed.connect(_on_touch_controls_changed)
	if _screen != null:
		# An expanded screen takes the whole portrait share rather than the 10:9
		# rectangle in it, so the split has to be redone when it is switched on.
		_screen.expanded_changed.connect(_on_screen_expanded_changed)
	_relayout()


## The rectangle the hardware screen occupies, and the one left for the
## controller. Split out so a test can check both without a viewport.
##
## [param expanded] is a screen that fills whatever it is given
## ([member Gen2Screen.expanded]): it is handed the whole share rather than the
## 10:9 rectangle inside it, since the leftover would be void it could have
## drawn map into.
static func split(area: Vector2, controls_shown: bool, expanded: bool = false) -> Dictionary:
	var landscape: bool = area.x >= area.y
	if landscape or not controls_shown:
		return {"screen": Rect2(Vector2.ZERO, area), "controls": Rect2(Vector2.ZERO, area)}
	var offered := Vector2(area.x, floorf(area.y * (1.0 - PORTRAIT_CONTROL_SHARE)))
	if expanded:
		return {
			"screen": Rect2(Vector2.ZERO, offered),
			"controls": Rect2(Vector2(0.0, offered.y), Vector2(area.x, area.y - offered.y)),
		}
	var drawn: Vector2 = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT) \
		* float(Gen2Screen.fit_factor(offered))
	return {
		# Top aligned, and centred across the width. The screen centres itself
		# inside whatever it is given, so it is given exactly its own size.
		"screen": Rect2(Vector2((area.x - drawn.x) * 0.5, 0.0), drawn),
		"controls": Rect2(Vector2(0.0, drawn.y), Vector2(area.x, area.y - drawn.y)),
	}


func _relayout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var rects: Dictionary = split(
		size,
		Gen2InputRuntime.instance().touch_controls_shown(),
		_screen != null and _screen.expanded,
	)
	if _screen != null:
		var screen_rect: Rect2 = rects["screen"]
		_screen.position = screen_rect.position
		_screen.size = screen_rect.size
	if _pad != null:
		var control_rect: Rect2 = rects["controls"]
		_pad.position = control_rect.position
		_pad.size = control_rect.size


func _on_touch_controls_changed(_shown: bool) -> void:
	_relayout()


func _on_screen_expanded_changed(_expanded: bool) -> void:
	_relayout()


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or not touch.pressed:
		return
	if _gesture.tap(touch.position, Time.get_ticks_msec() / 1000.0):
		Gen2InputRuntime.instance().reveal_touch_controls()
