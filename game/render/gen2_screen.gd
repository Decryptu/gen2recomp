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

const WIDTH: int = 160
const HEIGHT: int = 144

## After a resize changes the factor. Nothing in the game should care.
signal scale_changed(factor: int)
## After the native layer's rectangle changes; a view drawn there sizes to this.
signal native_size_changed(size: Vector2i)

var scale_factor: int = 1

@onready var _container: SubViewportContainer = %Container
@onready var _viewport: SubViewport = %Viewport
@onready var _native: Control = %Native


func _ready() -> void:
	# The viewport's size is the container's divided by the shrink factor, and
	# writing it directly is refused at runtime.
	resized.connect(_fit)
	_fit()


## Inside the screen, in hardware pixels: position it in the 160x144 space.
##
## Everything placed this way is interface, and sits above whatever
## [method display_content] put there, in the order it was placed.
func display(node: Node) -> void:
	_viewport.add_child(node)


## Renderer content, in hardware pixels, kept below every node [method display]
## placed. A renderer rebuilt mid-screen would otherwise be appended after a live
## text box and paint over it.
func display_content(node: Node) -> void:
	_viewport.add_child(node)
	_viewport.move_child(node, 0)


## On the layer behind, in [method native_size] window pixels; the hardware
## viewport is composited over it.
func display_native(node: Node) -> void:
	_native.add_child(node)


## The native layer's rectangle in window pixels.
func native_size() -> Vector2i:
	return Vector2i(WIDTH * scale_factor, HEIGHT * scale_factor)


## Frees everything on screen, on both layers.
func clear() -> void:
	for parent: Node in [_viewport, _native]:
		for child: Node in parent.get_children():
			parent.remove_child(child)
			child.queue_free()


## The viewport itself, for a caller that needs to read the drawn frame.
func viewport() -> SubViewport:
	return _viewport


## The largest whole number of window pixels per hardware pixel that fits.
## Public because [Gen2GameFrame] sizes the on-screen controller off it.
static func fit_factor(area: Vector2) -> int:
	return maxi(1, mini(int(area.x) / WIDTH, int(area.y) / HEIGHT))


func _fit() -> void:
	var factor: int = fit_factor(size)
	var drawn := Vector2(WIDTH * factor, HEIGHT * factor)

	_container.stretch_shrink = factor
	_container.size = drawn
	# Centred rather than anchored: an uneven margin is visible.
	_container.position = ((size - drawn) * 0.5).floor()
	_native.size = drawn
	_native.position = _container.position

	if factor != scale_factor:
		scale_factor = factor
		scale_changed.emit(factor)
	native_size_changed.emit(Vector2i(drawn))
