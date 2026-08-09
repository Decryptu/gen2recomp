class_name Gen2TouchLayout
extends RefCounted

## Where the on-screen controller's three clusters sit, how big they are and how
## much of the screen they hide.
##
## Geometry only: [Gen2TouchPad] draws and reads touches, and this answers where
## everything is. Keeping them apart is what lets the settings page show a live
## preview and lets a test check placement without a viewport.
##
## Positions are stored as a fraction of the area the controller was given, not
## as pixels, so a layout arranged on a phone still means the same thing on a
## tablet, in the other orientation, or after the window is resized. Portrait and
## landscape keep separate positions, because a cluster reachable by the thumb in
## one is in the middle of the screen in the other.

const GROUP_PAD: StringName = &"pad"
const GROUP_FACE: StringName = &"face"
const GROUP_MENU: StringName = &"menu"
const GROUPS: Array[StringName] = [GROUP_PAD, GROUP_FACE, GROUP_MENU]

const GROUP_LABELS: Dictionary = {
	GROUP_PAD: "D-pad",
	GROUP_FACE: "A and B",
	GROUP_MENU: "START and SELECT",
}

const ORIENTATION_PORTRAIT: StringName = &"portrait"
const ORIENTATION_LANDSCAPE: StringName = &"landscape"
const ORIENTATIONS: Array[StringName] = [ORIENTATION_PORTRAIT, ORIENTATION_LANDSCAPE]

## Unscaled sizes, in window pixels. A finger covers about 9mm, which is roughly
## 45 pixels on a phone at its native density, so nothing here is smaller than
## that once the minimum scale is applied.
const PAD_SIZE: float = 168.0
const FACE_DIAMETER: float = 84.0
## Centre-to-centre along the diagonal A and B sit on, so they never touch.
const FACE_SPACING: float = 104.0
const MENU_SIZE: Vector2 = Vector2(96.0, 38.0)
const MENU_SPACING: float = 108.0

## Inside this fraction of the d-pad's half-width nothing is pressed, so a thumb
## resting dead centre does not pick an arbitrary direction.
const PAD_CENTRE_DEAD: float = 0.22

const MIN_SCALE: float = 0.6
const MAX_SCALE: float = 1.8
const MIN_OPACITY: float = 0.2
const MAX_OPACITY: float = 1.0

## Thumb-reachable corners in each orientation. Landscape puts the clusters hard
## against the edges, since the hardware screen sits centred between them.
const DEFAULT_ANCHORS: Dictionary = {
	ORIENTATION_PORTRAIT: {
		GROUP_PAD: Vector2(0.24, 0.52),
		GROUP_FACE: Vector2(0.76, 0.52),
		GROUP_MENU: Vector2(0.50, 0.88),
	},
	ORIENTATION_LANDSCAPE: {
		GROUP_PAD: Vector2(0.12, 0.62),
		GROUP_FACE: Vector2(0.88, 0.62),
		GROUP_MENU: Vector2(0.50, 0.92),
	},
}

const DEFAULT_SCALE: float = 1.0
const DEFAULT_OPACITY: float = 0.65

var scale: float = DEFAULT_SCALE
var opacity: float = DEFAULT_OPACITY
## Orientation name, then group name, to a normalised centre.
var anchors: Dictionary = {}


func _init() -> void:
	anchors = _default_anchors()


static func _default_anchors() -> Dictionary:
	var copy: Dictionary = {}
	for orientation: StringName in ORIENTATIONS:
		var groups: Dictionary = {}
		for group: StringName in GROUPS:
			groups[group] = DEFAULT_ANCHORS[orientation][group] as Vector2
		copy[orientation] = groups
	return copy


static func orientation_of(area: Vector2) -> StringName:
	return ORIENTATION_LANDSCAPE if area.x >= area.y else ORIENTATION_PORTRAIT


func anchor(orientation: StringName, group: StringName) -> Vector2:
	var groups: Dictionary = anchors.get(orientation, {})
	return groups.get(group, DEFAULT_ANCHORS[orientation][group])


## Moves a cluster. The centre is clamped so no part of it can be dragged off
## the area, which is the only way an options screen can hand back a layout the
## player cannot press.
func set_anchor(orientation: StringName, group: StringName, centre: Vector2, area: Vector2) -> void:
	if not ORIENTATIONS.has(orientation) or not GROUPS.has(group) or area.x <= 0.0 or area.y <= 0.0:
		return
	var half: Vector2 = group_size(group) * 0.5
	var margin: Vector2 = Vector2(half.x / area.x, half.y / area.y)
	if not anchors.has(orientation):
		anchors[orientation] = {}
	(anchors[orientation] as Dictionary)[group] = Vector2(
		clampf(centre.x, margin.x, 1.0 - margin.x),
		clampf(centre.y, margin.y, 1.0 - margin.y),
	)


## The box a cluster occupies at the current scale, used for both dragging and
## hit testing.
func group_size(group: StringName) -> Vector2:
	match group:
		GROUP_PAD:
			return Vector2(PAD_SIZE, PAD_SIZE) * scale
		GROUP_FACE:
			return Vector2(FACE_SPACING + FACE_DIAMETER, FACE_SPACING + FACE_DIAMETER) * scale
		GROUP_MENU:
			return Vector2(MENU_SPACING + MENU_SIZE.x, MENU_SIZE.y) * scale
	return Vector2.ZERO


func group_rect(group: StringName, area: Rect2) -> Rect2:
	var orientation: StringName = orientation_of(area.size)
	var size: Vector2 = group_size(group)
	var centre: Vector2 = area.position + anchor(orientation, group) * area.size
	return Rect2(centre - size * 0.5, size)


## Every pressable rectangle, keyed by [Gen2Button]. The d-pad is not in here:
## it is one control with four answers, which [method direction_at] resolves.
func button_rects(area: Rect2) -> Dictionary:
	var rects: Dictionary = {}
	var face: Rect2 = group_rect(GROUP_FACE, area)
	var diameter: float = FACE_DIAMETER * scale
	# A below and left of B, the diagonal the hardware used.
	rects[Gen2Button.B] = Rect2(
		Vector2(face.position.x + face.size.x - diameter, face.position.y), Vector2(diameter, diameter)
	)
	rects[Gen2Button.A] = Rect2(
		Vector2(face.position.x, face.position.y + face.size.y - diameter), Vector2(diameter, diameter)
	)
	var menu: Rect2 = group_rect(GROUP_MENU, area)
	var pill: Vector2 = MENU_SIZE * scale
	rects[Gen2Button.SELECT] = Rect2(menu.position, pill)
	rects[Gen2Button.START] = Rect2(
		Vector2(menu.position.x + menu.size.x - pill.x, menu.position.y), pill
	)
	return rects


## The button a point presses, or [constant Gen2Button.NONE]. The d-pad is asked
## first, so a finger sliding off it onto an overlapping face button keeps
## walking rather than swapping to A halfway through a step.
func button_at(point: Vector2, area: Rect2) -> int:
	var direction: int = direction_at(point, area)
	if direction != Gen2Button.NONE:
		return direction
	var rects: Dictionary = button_rects(area)
	for button: int in rects:
		if (rects[button] as Rect2).has_point(point):
			return button
	return Gen2Button.NONE


## Which way the d-pad reads at a point, by dominant axis from its centre. One
## direction at a time: the hardware reported diagonals, but nothing in either
## game moves diagonally, and a corner press that walked twice would be wrong in
## a menu as well as on the map.
func direction_at(point: Vector2, area: Rect2) -> int:
	var rect: Rect2 = group_rect(GROUP_PAD, area)
	if not rect.has_point(point):
		return Gen2Button.NONE
	var local: Vector2 = (point - rect.get_center()) / (rect.size * 0.5)
	if local.length() < PAD_CENTRE_DEAD:
		return Gen2Button.NONE
	if absf(local.x) >= absf(local.y):
		return Gen2Button.RIGHT if local.x > 0.0 else Gen2Button.LEFT
	return Gen2Button.DOWN if local.y > 0.0 else Gen2Button.UP


func to_dict() -> Dictionary:
	var stored: Dictionary = {"scale": scale, "opacity": opacity}
	for orientation: StringName in ORIENTATIONS:
		var groups: Dictionary = {}
		for group: StringName in GROUPS:
			var centre: Vector2 = anchor(orientation, group)
			groups[String(group)] = [centre.x, centre.y]
		stored[String(orientation)] = groups
	return stored


## Clamped like the rest of the options file: an unreadable position costs that
## cluster its place, not the whole layout.
static func parse(raw: Variant) -> Gen2TouchLayout:
	var layout := Gen2TouchLayout.new()
	if raw is not Dictionary:
		return layout
	var stored: Dictionary = raw
	layout.scale = clampf(float(stored.get("scale", DEFAULT_SCALE)), MIN_SCALE, MAX_SCALE)
	layout.opacity = clampf(float(stored.get("opacity", DEFAULT_OPACITY)), MIN_OPACITY, MAX_OPACITY)
	for orientation: StringName in ORIENTATIONS:
		var groups: Variant = stored.get(String(orientation))
		if groups is not Dictionary:
			continue
		for group: StringName in GROUPS:
			var centre: Variant = (groups as Dictionary).get(String(group))
			if centre is not Array or (centre as Array).size() != 2:
				continue
			(layout.anchors[orientation] as Dictionary)[group] = Vector2(
				clampf(float((centre as Array)[0]), 0.0, 1.0),
				clampf(float((centre as Array)[1]), 0.0, 1.0),
			)
	return layout


func duplicate_layout() -> Gen2TouchLayout:
	return Gen2TouchLayout.parse(to_dict())


func is_default() -> bool:
	return to_dict() == Gen2TouchLayout.new().to_dict()
