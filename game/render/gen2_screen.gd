class_name Gen2Screen
extends Control

## A Game Boy Color screen: 160x144 pixels, scaled by a whole number to fit.
##
## The game does not run at the window's resolution and must not. A GBC pixel
## has to stay square and stay sharp, so everything the game draws goes into a
## [SubViewport] the size of the real hardware and that image is blown up by an
## integer factor. Any other scale resamples an 8x8 tile into something that
## crawls when it moves.
##
## The launcher chrome around it is ordinary Godot UI at the window's own
## resolution. Keeping the two apart is why this is a [Control] rather than a
## project-wide stretch setting: menus stay crisp at any window size, and the
## game stays a Game Boy.
##
## Add what the game draws with [method display]; it goes inside the viewport.
##
## There is a second layer behind it, [method display_native], covering the same
## rectangle at the window's own resolution. A view that is not made of hardware
## pixels goes there: a 3D or HD renderer cannot be drawn in a 160x144 buffer and
## then magnified, but it still has to line up with the text boxes and menus
## drawn above it, which are hardware pixels and stay that way.

const WIDTH: int = 160
const HEIGHT: int = 144

## Emitted after a resize changes the whole-number factor the screen is drawn
## at. Nothing in the game should care, but a debug overlay might.
signal scale_changed(factor: int)
## Emitted after the native layer's rectangle changes, in window pixels. A view
## drawn there sizes itself to this rather than to the window.
signal native_size_changed(size: Vector2i)

var scale_factor: int = 1

@onready var _container: SubViewportContainer = %Container
@onready var _viewport: SubViewport = %Viewport
@onready var _native: Control = %Native


func _ready() -> void:
	# The viewport's size is not set here: a stretching SubViewportContainer
	# owns it, and it falls out of the container's size divided by the shrink
	# factor. Writing it directly is refused at runtime.
	resized.connect(_fit)
	_fit()


## Puts a node inside the screen. Anything added this way is drawn in hardware
## pixels, so position it in the 160x144 space and nothing else.
func display(node: Node) -> void:
	_viewport.add_child(node)


## Puts a node on the layer behind the hardware screen, covering the same
## rectangle at the window's own resolution. Position it in [method native_size]
## pixels; what is drawn in the hardware viewport is composited over it.
func display_native(node: Node) -> void:
	_native.add_child(node)


## The native layer's rectangle in window pixels, which is the hardware screen's
## size times the whole-number factor it is drawn at.
func native_size() -> Vector2i:
	return Vector2i(WIDTH * scale_factor, HEIGHT * scale_factor)


## Removes and frees everything currently on screen, on both layers.
func clear() -> void:
	for parent: Node in [_viewport, _native]:
		for child: Node in parent.get_children():
			parent.remove_child(child)
			child.queue_free()


## The viewport itself, for a caller that needs to read the drawn frame.
func viewport() -> SubViewport:
	return _viewport


## The largest whole number of window pixels per hardware pixel that still fits.
func _fit() -> void:
	var factor: int = maxi(1, mini(int(size.x) / WIDTH, int(size.y) / HEIGHT))
	var drawn := Vector2(WIDTH * factor, HEIGHT * factor)

	_container.stretch_shrink = factor
	_container.size = drawn
	# Centred rather than anchored: a screen that does not divide evenly into
	# the window leaves a margin, and an uneven one is visible.
	_container.position = ((size - drawn) * 0.5).floor()
	_native.size = drawn
	_native.position = _container.position

	if factor != scale_factor:
		scale_factor = factor
		scale_changed.emit(factor)
	native_size_changed.emit(Vector2i(drawn))
