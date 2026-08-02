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

const WIDTH: int = 160
const HEIGHT: int = 144

## Emitted after a resize changes the whole-number factor the screen is drawn
## at. Nothing in the game should care, but a debug overlay might.
signal scale_changed(factor: int)

var scale_factor: int = 1

@onready var _container: SubViewportContainer = %Container
@onready var _viewport: SubViewport = %Viewport


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


## Removes and frees everything currently on screen.
func clear() -> void:
	for child: Node in _viewport.get_children():
		_viewport.remove_child(child)
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

	if factor != scale_factor:
		scale_factor = factor
		scale_changed.emit(factor)
