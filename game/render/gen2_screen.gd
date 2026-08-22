class_name Gen2Screen
extends Control

## A Game Boy Color screen: 160x144 pixels, scaled by a whole number to fit.
##
## What the game draws goes into a hardware-sized [SubViewport] blown up by an
## integer factor, since any other scale resamples an 8x8 tile into something
## that crawls when it moves. Surrounding chrome is ordinary Godot UI at window
## resolution, which is why this is a [Control] and not a stretch setting.
##
## [method display_native] is a second layer behind it, covering the same
## rectangle at window resolution, for a view that cannot be drawn into a 160x144
## buffer and magnified but still has to line up with the boxes above it.
##
## [member expanded] widens the buffer instead of framing it. The window is not
## 10:9 and never was; the black bars are the shape of a screen this project can
## draw past, so a view that asks for it is given a surface the size of the whole
## control and fills it with more world. Interface is unmoved: [method display]
## puts a screen inside a 160x144 rectangle centred in that surface, so every
## box, menu and cursor is laid out exactly where the cartridge laid it out and
## only the surround grows. [member zoom_step] is how many whole pixels a
## hardware pixel is drawn as, counted from the largest that fits.

const WIDTH: int = 160
const HEIGHT: int = 144
## Below one screen pixel per hardware pixel the picture is halved rather than
## stepped, which is what puts a whole region in a window.
const MIN_SCALE: float = 0.25
## An expanded buffer grows by whole map blocks, so half the difference from the
## hardware screen is always a whole tile and the interface rectangle inside it
## lands on the grid every screen is laid out against.
const BUFFER_STEP: int = 32
## How far past the fitting scale a player may zoom out. Three steps reaches
## MIN_SCALE from a 1x window, and the same three from any other.
const ZOOM_OUT_STEPS: int = 3

## After a resize changes the factor. Nothing in the game should care.
signal scale_changed(factor: int)
## After the native layer's rectangle changes; a view drawn there sizes to this.
signal native_size_changed(size: Vector2i)
## After the drawn buffer changes size, in hardware pixels. A view that fills it
## reads this rather than assuming 160x144.
signal view_size_changed(size: Vector2i)
## After [member expanded] is switched, so the frame around the screen can hand
## it a different rectangle.
signal expanded_changed(expanded: bool)

var scale_factor: int = 1
## Whether the buffer grows to the control instead of being framed inside it.
var expanded: bool = false:
	set(value):
		if expanded == value:
			return
		expanded = value
		clip_contents = value
		expanded_changed.emit(value)
		_fit()
## Whole steps away from the fitting scale, positive towards the player.
var zoom_step: int = 0:
	get:
		return _zoom_step
	set(value):
		var stepped: int = clampi(value, _min_zoom_step(), _max_zoom_step())
		if _zoom_step == stepped:
			return
		_zoom_step = stepped
		_fit()

var _zoom_step: int = 0

## Whether everything outside the 160x144 rectangle is blacked out.
##
## A screen that owns the whole picture -- a battle, the pack, the PC -- is laid
## out in 160x144 and has nothing to fill a wider buffer with. The surround
## becomes the letterbox a framed screen has, rather than the map that screen is
## standing in front of.
var interface_masked: bool = false:
	set(value):
		if interface_masked == value:
			return
		interface_masked = value
		if _mask != null:
			_mask.visible = value

## What [member interface_masked] paints with. The screen does not know what is
## behind it, and a mask in a different colour from the bars a framed screen
## leaves would read as a border rather than as the same letterbox; the scene
## that owns the screen says which colour its own background is.
var letterbox_color: Color = Color.BLACK:
	set(value):
		letterbox_color = value
		if _mask != null:
			_mask.queue_redraw()

var _view_size: Vector2i = Vector2i(WIDTH, HEIGHT)
var _draw_scale: float = 1.0

@onready var _container: SubViewportContainer = %Container
@onready var _viewport: SubViewport = %Viewport
@onready var _native: Control = %Native
## The 160x144 rectangle interface is laid out in, moved to the middle of a
## wider buffer rather than the buffer's corner.
var _interface: Control = null
## Drawn between the content and the interface: see [member interface_masked].
var _mask: Control = null


func _ready() -> void:
	# The viewport's size is the container's divided by the shrink factor, and
	# writing it directly is refused at runtime.
	resized.connect(_fit)
	_mask = Control.new()
	_mask.name = "Mask"
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask.visible = interface_masked
	_mask.draw.connect(_draw_mask)
	_viewport.add_child(_mask)
	_interface = Control.new()
	_interface.name = "Interface"
	_interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interface.size = Vector2(WIDTH, HEIGHT)
	# The viewport used to be exactly the Game Boy screen and clipped anything
	# drawn past it, which is a slide-in's own edge. An expanded buffer no longer
	# does, so the rectangle it was clipped against does it instead.
	_interface.clip_contents = true
	_viewport.add_child(_interface)
	_fit()


## Inside the screen, in hardware pixels: position it in the 160x144 space.
##
## Everything placed this way is interface, and sits above whatever
## [method display_content] put there, in the order it was placed.
func display(node: Node) -> void:
	_interface.add_child(node)


## Renderer content, in hardware pixels, kept below every node [method display]
## placed. A renderer rebuilt mid-screen would otherwise be appended after a live
## text box and paint over it.
##
## Its origin is the buffer's own, not the interface rectangle's, so a view that
## fills an expanded screen draws over all of it.
func display_content(node: Node) -> void:
	_viewport.add_child(node)
	_viewport.move_child(node, 0)


## On the layer behind, in [method native_size] window pixels; the hardware
## viewport is composited over it.
func display_native(node: Node) -> void:
	_native.add_child(node)


## The native layer's rectangle in window pixels.
func native_size() -> Vector2i:
	return Vector2i((Vector2(_view_size) * _draw_scale).round())


## The drawn buffer in hardware pixels: 160x144 unless [member expanded].
func view_size() -> Vector2i:
	return _view_size


## The cartridge's own 160x144 screen, in the native layer's own pixels.
##
## A view on that layer is handed a rectangle and told nothing else, and every
## hardware-pixel number it is given -- the text box's, first -- has to land
## somewhere inside it. Framed, that mapping was the layer itself, since the
## rectangle was a whole multiple of 160x144. Expanded it is not, so the screen
## says where.
func screen_rect() -> Rect2i:
	var drawn: Vector2 = Vector2(WIDTH, HEIGHT) * _draw_scale
	var at: Vector2 = (_interface.position if _interface != null else Vector2.ZERO) \
		* _draw_scale
	return Rect2i(Vector2i(at.round()), Vector2i(drawn.round()))


## The largest whole number of window pixels per hardware pixel that fits.
## Public because [Gen2GameFrame] sizes the on-screen controller off it.
static func fit_factor(area: Vector2) -> int:
	return maxi(1, mini(int(area.x) / WIDTH, int(area.y) / HEIGHT))


## Screen pixels per hardware pixel at [param step] away from a fitting scale of
## [param fit]. Whole numbers on the way in; on the way out the last three steps
## halve instead, since one screen pixel per hardware pixel is as far as whole
## numbers go and a survey of a region needs to be further out than that.
static func scale_at(fit: int, step: int) -> float:
	var raw: int = maxi(fit, 1) + step
	if raw >= 1:
		return float(raw)
	return maxf(pow(0.5, float(1 - raw)), MIN_SCALE)


## One step of zoom, reported as the scale it settled on. Refused unless the
## screen is expanded: framed at 160x144 there is no more world to show and a
## step would only shrink the picture.
func step_zoom(delta: int) -> float:
	if not expanded:
		return _draw_scale
	zoom_step = zoom_step + delta
	return _draw_scale


func reset_zoom() -> void:
	zoom_step = 0


## Frees everything on screen, on both layers.
func clear() -> void:
	for parent: Node in [_interface, _native]:
		for child: Node in parent.get_children():
			drop(child)
	for child: Node in _viewport.get_children():
		if child != _interface:
			drop(child)


## Takes a node off the screen now and frees it at the end of the frame.
##
## `queue_free` on its own only does the second half: the node stays in the tree,
## and drawn, until the frame it was dropped on is served. A replacement added on
## the same frame is then composited over its predecessor rather than instead of
## it, which is a stale panel showing under the live one for exactly the frame a
## screenshot catches; inside a [Container] the two are laid out side by side.
##
## Static, and the one way a screen drops a child it is replacing.
static func drop(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()


## The same for every child of [param parent], which is what a row list being
## rebuilt in place wants.
static func drop_children(parent: Node) -> void:
	if parent == null:
		return
	for child: Node in parent.get_children():
		drop(child)


## The viewport itself, for a caller that needs to read the drawn frame.
func viewport() -> SubViewport:
	return _viewport


## The layer [method display] puts a screen on: the 160x144 rectangle, centred
## in the buffer. For a caller that has to know where in the viewport the
## interface sits, which is above whatever [method display_content] drew.
func interface_layer() -> Control:
	return _interface


## The letterbox, drawn rather than left empty: four rectangles around the
## 160x144 the interface is laid out in. Not a filled surface, because the
## middle is not always the interface's -- a battle transition is the renderer's
## own screen and has to stay visible inside it.
func _draw_mask() -> void:
	var inside := Rect2(_interface.position, Vector2(WIDTH, HEIGHT))
	var whole := Vector2(_view_size)
	for band: Rect2 in [
		Rect2(Vector2.ZERO, Vector2(whole.x, inside.position.y)),
		Rect2(Vector2(0.0, inside.end.y), Vector2(whole.x, whole.y - inside.end.y)),
		Rect2(Vector2(0.0, inside.position.y), Vector2(inside.position.x, inside.size.y)),
		Rect2(
			Vector2(inside.end.x, inside.position.y),
			Vector2(whole.x - inside.end.x, inside.size.y),
		),
	]:
		if band.size.x > 0.0 and band.size.y > 0.0:
			_mask.draw_rect(band, letterbox_color, true)


func _min_zoom_step() -> int:
	return 1 - fit_factor(size) - ZOOM_OUT_STEPS


func _max_zoom_step() -> int:
	return fit_factor(size)


## The buffer a scale of [param scale] needs to cover [param area], rounded up
## to a whole block on each axis past the hardware's own screen so the 160x144
## interface rectangle lands on a whole tile.
static func buffer_for(area: Vector2, scale: float) -> Vector2i:
	var wanted := Vector2i(
		maxi(ceili(area.x / maxf(scale, MIN_SCALE)), WIDTH),
		maxi(ceili(area.y / maxf(scale, MIN_SCALE)), HEIGHT),
	)
	return Vector2i(
		WIDTH + ceili(float(wanted.x - WIDTH) / float(BUFFER_STEP)) * BUFFER_STEP,
		HEIGHT + ceili(float(wanted.y - HEIGHT) / float(BUFFER_STEP)) * BUFFER_STEP,
	)


func _fit() -> void:
	var factor: int = fit_factor(size)
	# A resize moves the fitting scale, so a step chosen against the old one can
	# fall outside the ladder. Clamped on the field rather than through the
	# property, which would come straight back into this.
	_zoom_step = clampi(_zoom_step, _min_zoom_step(), _max_zoom_step())
	var scale_now: float = scale_at(factor, _zoom_step) if expanded else float(factor)
	var view: Vector2i = buffer_for(size, scale_now) if expanded \
		else Vector2i(WIDTH, HEIGHT)
	var drawn: Vector2 = Vector2(view) * scale_now

	# A whole-number scale keeps the proven shrink path, where the container is
	# the drawn size and the viewport is that divided by the factor. Below one
	# the shrink cannot express the ratio, so the container is the buffer and the
	# texture is scaled down instead.
	if scale_now >= 1.0 and is_equal_approx(scale_now, roundf(scale_now)):
		_container.stretch_shrink = int(roundf(scale_now))
		_container.scale = Vector2.ONE
		_container.size = drawn
	else:
		_container.stretch_shrink = 1
		_container.size = Vector2(view)
		_container.scale = Vector2(scale_now, scale_now)
	# Nearest is what keeps a hardware pixel a square block of screen pixels, and
	# it is the wrong answer in the one place the picture is made smaller rather
	# than larger: dropping three pixels in four turns a tree wall into moire.
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if scale_now >= 1.0 \
		else CanvasItem.TEXTURE_FILTER_LINEAR
	# Centred rather than anchored: an uneven margin is visible.
	_container.position = ((size - drawn) * 0.5).floor()
	_native.size = drawn
	_native.position = _container.position
	if _mask != null:
		_mask.size = Vector2(view)
		_mask.queue_redraw()
	if _interface != null:
		_interface.position = ((Vector2(view - Vector2i(WIDTH, HEIGHT)) * 0.5)
			/ float(Gen2Tiles.TILE_WIDTH)).floor() * float(Gen2Tiles.TILE_WIDTH)
		_interface.size = Vector2(WIDTH, HEIGHT)

	_draw_scale = scale_now
	if view != _view_size:
		_view_size = view
		view_size_changed.emit(view)
	if factor != scale_factor:
		scale_factor = factor
		scale_changed.emit(factor)
	native_size_changed.emit(Vector2i(drawn))
