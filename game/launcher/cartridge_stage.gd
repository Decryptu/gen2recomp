class_name Gen2CartridgeStage
extends Control

## The shelf itself: every cartridge stood on one baseline, the selected one at
## full size in the middle and the rest smaller and further back.
##
## Children are placed by hand rather than by a container. A container would
## either clip the contact shadows or fight the animations for the same
## [member Control.position], and neither is worth the layout it saves.

signal selection_changed(game_id: StringName)
signal insert_requested(game_id: StringName)
signal play_requested(game_id: StringName)

## How much smaller a cartridge gets for each step away from the selection.
const FALLOFF: float = 0.30
const DIM: float = 0.55
## Room kept under the baseline for the contact shadows.
const FLOOR: float = 26.0
const MAX_HEIGHT: float = 360.0
const MIN_HEIGHT: float = 130.0
## How many steps either side of the selection must stay fully on the stage.
const NEAR: int = 1

var selected: int = 0

var _theme: Gen2LauncherTheme = null
var _cartridges: Array[Gen2Cartridge] = []
var _order: Array[StringName] = []
var _tween: Tween = null


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
	custom_minimum_size = Vector2(0, MIN_HEIGHT + FLOOR)
	resized.connect(_lay_out.bind(false))
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


func select(index: int, animated: bool = true) -> void:
	var wanted: int = clampi(index, 0, _cartridges.size() - 1)
	if wanted == selected:
		return
	selected = wanted
	Gen2LauncherAudio.play(&"hover")
	_lay_out(animated)
	selection_changed.emit(selected_id())


func step(direction: int) -> void:
	select(posmod(selected + direction, _cartridges.size()))


func set_imported(game_id: StringName, state: bool) -> void:
	var target: Gen2Cartridge = cartridge(game_id)
	if target != null and target.imported != state:
		target.set_imported(state)


func _on_pressed(index: int) -> void:
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


## Every cartridge is bottom-aligned on one baseline, so a smaller one reads as
## standing further back rather than as floating.
func _lay_out(animated: bool = true) -> void:
	if _cartridges.is_empty() or size.x <= 0.0:
		return
	var hero_height: float = clampf(size.y - FLOOR, MIN_HEIGHT, MAX_HEIGHT)
	var hero_width: float = hero_height * Gen2Cartridge.ASPECT
	var gap: float = hero_width * 0.10

	# Only the selected cartridge and the two beside it have to fit. Anything
	# further out may run past the edge, because half a cartridge showing says
	# there is more to the side, which is what the row means. Fitting the whole
	# row instead would shrink the one being looked at to make room for the one
	# that is not.
	var span: float = _span(hero_width, gap, NEAR)
	if span > size.x:
		hero_height *= size.x / span
		hero_width = hero_height * Gen2Cartridge.ASPECT
		gap = hero_width * 0.10

	# The spare height is split evenly, so a tall window does not strand the row
	# at the top or glue it to the caption underneath.
	var slack: float = maxf(0.0, size.y - FLOOR - hero_height)
	var baseline: float = size.y - FLOOR - slack * 0.45
	# The row is centred as a whole rather than on the selected cartridge, so
	# choosing the first or the last one does not leave the stage lopsided.
	var centre: float = size.x * 0.5 - _drift(hero_width, gap)
	if animated and is_inside_tree():
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.set_parallel(true)
		_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	for index: int in _cartridges.size():
		var card: Gen2Cartridge = _cartridges[index]
		var distance: int = index - selected
		var factor: float = _factor(index)
		var width: float = hero_width * factor
		var height: float = hero_height * factor
		var x: float = centre - width * 0.5 + _offset(index, hero_width, gap)
		var y: float = baseline - height
		var fade: float = 1.0 if distance == 0 else DIM

		card.size = Vector2(width, height)
		card.set_depth(absi(distance))
		card.z_index = 10 - absi(distance)
		if _tween != null and _tween.is_valid() and animated:
			_tween.tween_property(card, "position:x", x, 0.26)
			_tween.tween_method(card.set_rest_y, card.rest_y(), y, 0.26)
			_tween.tween_property(card, "modulate:a", fade, 0.20)
		else:
			card.position.x = x
			card.set_rest_y(y)
			card.modulate.a = fade


## Where the row begins and ends, measured from the middle of the selected
## cartridge, counting only what is within [param reach] steps of it.
func _extent(hero_width: float, gap: float, reach: int) -> Vector2:
	var low: float = 0.0
	var high: float = 0.0
	for index: int in _cartridges.size():
		if absi(index - selected) > reach:
			continue
		var half: float = hero_width * _factor(index) * 0.5
		var middle: float = _offset(index, hero_width, gap)
		low = minf(low, middle - half)
		high = maxf(high, middle + half)
	return Vector2(low, high)


func _span(hero_width: float, gap: float, reach: int) -> float:
	var edges: Vector2 = _extent(hero_width, gap, reach)
	return edges.y - edges.x


## How far the middle of the row sits from the middle of the selected cartridge.
## Measured over the same near group as the fit, so the selected cartridge is
## never pushed off the stage to balance one that is overhanging anyway.
func _drift(hero_width: float, gap: float) -> float:
	var edges: Vector2 = _extent(hero_width, gap, NEAR)
	return (edges.x + edges.y) * 0.5


## The width of a cartridge [param steps] away from the selection, as a fraction
## of the selected one.
func _scale_at(steps: int) -> float:
	return maxf(0.34, 1.0 - FALLOFF * float(steps))


func _factor(index: int) -> float:
	return _scale_at(absi(index - selected))


## How far the centre of cartridge [param index] sits from the middle of the
## stage: half the hero, then every cartridge and gap standing between them.
func _offset(index: int, hero_width: float, gap: float) -> float:
	var steps: int = absi(index - selected)
	if steps == 0:
		return 0.0
	var travel: float = hero_width * 0.5
	for step_index: int in range(1, steps + 1):
		travel += gap + hero_width * _scale_at(step_index)
	travel -= hero_width * _scale_at(steps) * 0.5
	return travel * float(signi(index - selected))
