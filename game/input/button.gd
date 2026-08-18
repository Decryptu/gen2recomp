class_name Gen2Button
extends RefCounted

## The eight buttons the hardware had, and the input actions that stand for them.
##
## Every screen that reads the cartridge's own controls speaks this vocabulary
## and nothing else, so a key, a pad button and an on-screen button are already
## the same thing by the time a screen sees one. What a device has to do to
## produce a button is [Gen2InputActions]' business, and which device the player
## is holding is [Gen2InputDevice]'s.

const NONE: int = 0
const UP: int = 1
const DOWN: int = 2
const LEFT: int = 3
const RIGHT: int = 4
const A: int = 5
const B: int = 6
const START: int = 7
const SELECT: int = 8

## Source order: the d-pad, then the face buttons, then START and SELECT. Remap
## UI and touch layouts both list buttons in this order.
const ALL: Array[int] = [UP, DOWN, LEFT, RIGHT, A, B, START, SELECT]
const DIRECTIONS: Array[int] = [UP, DOWN, LEFT, RIGHT]

const ACTIONS: Dictionary = {
	UP: &"gen2_up",
	DOWN: &"gen2_down",
	LEFT: &"gen2_left",
	RIGHT: &"gen2_right",
	A: &"gen2_a",
	B: &"gen2_b",
	START: &"gen2_start",
	SELECT: &"gen2_select",
}

const LABELS: Dictionary = {
	UP: "Up",
	DOWN: "Down",
	LEFT: "Left",
	RIGHT: "Right",
	A: "A",
	B: "B",
	START: "START",
	SELECT: "SELECT",
}

const VECTORS: Dictionary = {
	UP: Vector2i.UP,
	DOWN: Vector2i.DOWN,
	LEFT: Vector2i.LEFT,
	RIGHT: Vector2i.RIGHT,
}


static func action(button: int) -> StringName:
	return ACTIONS.get(button, &"")


static func from_action(name: StringName) -> int:
	for button: int in ALL:
		if ACTIONS[button] == name:
			return button
	return NONE


static func label(button: int) -> String:
	return LABELS.get(button, "")


static func is_direction(button: int) -> bool:
	return DIRECTIONS.has(button)


static func vector(button: int) -> Vector2i:
	return VECTORS.get(button, Vector2i.ZERO)


static func from_vector(direction: Vector2i) -> int:
	for button: int in DIRECTIONS:
		if VECTORS[button] == direction:
			return button
	return NONE


## The button an event has just pressed, or [constant NONE]. Echo is refused:
## a held key repeats at the operating system's rate, which is not the rate the
## hardware walked at. Continuous input is read with [method held] instead.
static func pressed_in(event: InputEvent) -> int:
	for button: int in ALL:
		if event.is_action_pressed(ACTIONS[button]):
			return button
	return NONE


static func released_in(event: InputEvent) -> int:
	for button: int in ALL:
		if event.is_action_released(ACTIONS[button]):
			return button
	return NONE


static func held(button: int) -> bool:
	return Input.is_action_pressed(ACTIONS.get(button, &""))


## Whether a printing text should run at one letter a frame. `PrintLetterDelay`
## reads `hJoyDown` and answers a HELD A or B with a single `DelayFrame`
## (`home/print_text.asm`), so this is the whole of what a button does to text
## that is still appearing, and it is a hold rather than a press.
static func text_accelerating() -> bool:
	return held(A) or held(B)
