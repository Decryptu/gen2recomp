class_name Gen2CartridgeStage
extends Control

## The shelf itself: a carousel that wraps, with the selected cartridge always in
## the middle at full size and every other one the same step smaller beside it.
##
## Placement runs off one continuous [member _scroll] rather than off the integer
## selection, so a step animates as a slide and the cartridge that has to cross
## the row does it off the edge instead of through the middle. Children are placed
## by hand because a container would fight the animations for the same
## [member Control.position].

signal selection_changed(game_id: StringName)
signal insert_requested(game_id: StringName)
signal play_requested(game_id: StringName)

## How big a cartridge beside the selection is, as a fraction of it.
const SIDE: float = 0.56
const DIM: float = 0.72
## The space between two cartridges, as a fraction of the selected one's width.
const GAP: float = 0.11
## The narrowest the selected cartridge gets, as a fraction of the stage, once
## the whole row no longer fits.
const NARROW_SHARE: float = 0.62
## The width a selected cartridge has to keep for the row to be worth fitting.
const COMFORT: float = 200.0
const MAX_HEIGHT: float = 460.0
const MIN_HEIGHT: float = 130.0
## Slots past the first that a cartridge is pushed out by, so the one wrapping
## round is well off the visible group before it crosses.
const EXILE: float = 2.6
## Where a cartridge has faded out completely, in slots.
const VANISH: float = 1.34
## How far across the stage a finger travels to turn it by one cartridge.
const SWIPE: float = 0.12

var selected: int = 0

var _theme: Gen2LauncherTheme = null
var _cartridges: Array[Gen2Cartridge] = []
var _order: Array[StringName] = []
var _tween: Tween = null
## Distance a finger has travelled since the last cartridge it turned.
var _swipe: float = 0.0
## The carousel position in slots. Equal to [member selected] at rest and driven
## between the two while a step animates.
var _scroll: float = 0.0:
	set(value):
		_scroll = value
		_place_all()


static func create(theme: Gen2LauncherTheme, order: Array[StringName]) -> Gen2CartridgeStage:
	var stage := Gen2CartridgeStage.new()
	stage._theme = theme
	stage._order = order
	stage._build()
	return stage


func _build() -> void:
	clip_contents = false
	focus_mode = Control.FOCUS_ALL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, MIN_HEIGHT)
	resized.connect(_place_all)
	focus_entered.connect(_place_all)
	focus_exited.connect(_place_all)
	for index: int in _order.size():
		var id: StringName = _order[index]
		var cartridge: Gen2Cartridge = Gen2Cartridge.create(_theme, id)
		cartridge.insert_requested.connect(func() -> void: insert_requested.emit(id))
		cartridge.play_requested.connect(func() -> void: _on_pressed(index))
		add_child(cartridge)
		_cartridges.append(cartridge)


func cartridge(game_id: StringName) -> Gen2Cartridge:
	var index: int = _order.find(game_id)
	return _cartridges[index] if index >= 0 else null


func selected_id() -> StringName:
	return _order[selected] if selected < _order.size() else &""


func selected_cartridge() -> Gen2Cartridge:
	return _cartridges[selected] if selected < _cartridges.size() else null


## Moves the carousel onto [param index], wrapping rather than clamping: the row
## has no first or last cartridge.
func select(index: int, animated: bool = true) -> void:
	if _cartridges.is_empty():
		return
	var wanted: int = posmod(index, _cartridges.size())
	if wanted == selected:
		return
	# Measured from where the carousel actually is, so a step taken mid-slide
	# carries on in the same direction rather than snapping back.
	var travel: float = _shortest(float(wanted) - _scroll)
	selected = wanted
	Gen2LauncherAudio.play(&"hover")
	_slide(_scroll + travel, animated)
	selection_changed.emit(selected_id())


func step(direction: int) -> void:
	select(selected + direction)


func set_imported(game_id: StringName, state: bool) -> void:
	var target: Gen2Cartridge = cartridge(game_id)
	if target != null and target.imported != state:
		target.set_imported(state)


func _on_pressed(index: int) -> void:
	# Reaching a cartridge with a pointer leaves the carousel where the arrow keys
	# expect to find it, so a mouse and a keyboard can be used in either order.
	if focus_mode == Control.FOCUS_ALL:
		grab_focus()
	# One click selects, a second plays. On the cartridge already chosen the two
	# collapse into one, which is what a pointer expects.
	if index != selected:
		select(index)
		return
	if _cartridges[index].imported:
		play_requested.emit(_order[index])
	else:
		insert_requested.emit(_order[index])


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		accept_event()
		step(-1)
	elif event.is_action_pressed("ui_right"):
		accept_event()
		step(1)
	elif event.is_action_pressed("ui_accept"):
		accept_event()
		_on_pressed(selected)
	elif event is InputEventScreenDrag:
		# A swipe turns the carousel one cartridge per [constant SWIPE], measured
		# against the stage rather than in pixels so it feels the same on a phone
		# as on a tablet.
		var drag: InputEventScreenDrag = event
		_swipe += drag.relative.x
		var threshold: float = maxf(size.x * SWIPE, 24.0)
		if absf(_swipe) >= threshold:
			accept_event()
			step(-signi(int(_swipe)))
			_swipe = 0.0
	elif event is InputEventScreenTouch:
		_swipe = 0.0
	elif event is InputEventMouseButton:
		# A wheel over the stage turns the carousel, which is what a pointer
		# expects of a row that scrolls sideways.
		var wheel: InputEventMouseButton = event
		if not wheel.pressed:
			return
		match wheel.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
				accept_event()
				step(-1)
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
				accept_event()
				step(1)


func _slide(target: float, animated: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not animated or not is_inside_tree():
		_scroll = target
		return
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "_scroll", target, 0.30)


## How wide the whole visible row is, in selected-cartridge widths: the hero, a
## gap and a neighbour either side of it.
func _span_ratio() -> float:
	return 1.0 + 2.0 * (GAP + SIDE)


## The signed distance to a slot, taking whichever way round the ring is shorter.
func _shortest(delta: float) -> float:
	var ring: float = float(_cartridges.size())
	if ring <= 0.0:
		return 0.0
	return fposmod(delta + ring * 0.5, ring) - ring * 0.5


func _place_all() -> void:
	if _cartridges.is_empty() or size.x <= 0.0:
		return
	var hero_height: float = clampf(size.y * 0.94, MIN_HEIGHT, MAX_HEIGHT)
	var hero_width: float = hero_height * Gen2Cartridge.ASPECT
	# The whole row fits whenever fitting it leaves a cartridge worth looking at.
	# Below that the hero holds [constant NARROW_SHARE] of the stage and the two
	# beside it run off the edge: on a phone, three cartridges that all fit are
	# three thumbnails.
	var fitted: float = size.x / _span_ratio()
	if fitted < COMFORT:
		fitted = maxf(fitted, size.x * NARROW_SHARE)
	hero_width = minf(hero_width, fitted)
	hero_height = hero_width / Gen2Cartridge.ASPECT
	var stride: float = hero_width * (0.5 + GAP + SIDE * 0.5)
	var middle: Vector2 = Vector2(size.x * 0.5, size.y * 0.5)

	# Furthest from the middle first, so the selected cartridge is drawn last and
	# nothing beside it overlaps the one being looked at. Draw order is child
	# order rather than [member CanvasItem.z_index], which would also lift the
	# cartridges over the controls under the stage.
	var by_distance: Array[int] = []
	for index: int in _cartridges.size():
		by_distance.append(index)
	by_distance.sort_custom(
		func(a: int, b: int) -> bool: return absf(_slot(a)) > absf(_slot(b))
	)
	for order: int in by_distance.size():
		move_child(_cartridges[by_distance[order]], order)

	for index: int in _cartridges.size():
		var card: Gen2Cartridge = _cartridges[index]
		var slot: float = _slot(index)
		var reach: float = absf(slot)
		var factor: float = lerpf(1.0, SIDE, minf(reach, 1.0))
		var width: float = hero_width * factor
		var height: float = hero_height * factor
		# Past the first slot a cartridge is pushed out fast, so the one crossing
		# the ring is off the stage by the time it changes sides.
		var out: float = reach if reach <= 1.0 else 1.0 + (reach - 1.0) * EXILE
		card.size = Vector2(width, height)
		card.set_depth(0 if reach < 0.5 else 1)
		card.position.x = middle.x + signf(slot) * out * stride - width * 0.5
		card.set_rest_y(middle.y - height * 0.5)
		card.modulate.a = clampf(
			lerpf(1.0, DIM, minf(reach, 1.0)) * clampf((VANISH - reach) / 0.34, 0.0, 1.0), 0.0, 1.0
		)
		card.visible = card.modulate.a > 0.0
		card.set_highlighted(reach < 0.5 and has_focus())


## Where cartridge [param index] sits relative to the middle, in slots.
func _slot(index: int) -> float:
	return _shortest(float(index) - _scroll)
