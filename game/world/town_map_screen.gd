class_name Gen2TownMapScreen
extends Control

## Full-screen host for engine/pokegear/pokegear.asm's _TownMap routine.
## Landmark order and coordinates mirror data/maps/landmarks.asm. The source
## stores a tile image, but the interaction is driven by this same landmark
## table, so the map remains complete even when a cartridge tile art pack is not
## present in the runtime cache.

signal closed

const BACKGROUND: Color = Color("#08111f")
const MAP_BACKGROUND: Color = Color("#142b3d")
const MAP_GRID: Color = Color(0.30, 0.55, 0.62, 0.22)
const PATH: Color = Color("#5f9a96")
const LANDMARK: Color = Color("#b8d8c8")
const SELECTED: Color = Color("#f3c969")
const PLAYER: Color = Color("#7bd89a")
const TEXT: Color = Color("#f4f7fb")
const MUTED: Color = Color("#9eacc0")

const JOHTO_START: int = 1
const JOHTO_END: int = 46
const KANTO_START: int = 47
const KANTO_END: int = 94
const FAST_SHIP: int = 95

## Raw x,y values from the landmark macro in data/maps/landmarks.asm.
const LANDMARKS: Array[Dictionary] = [
	{"name": "SPECIAL", "point": Vector2(0, 0)},
	{"name": "NEW BARK TOWN", "point": Vector2(140, 100)},
	{"name": "ROUTE 29", "point": Vector2(128, 100)},
	{"name": "CHERRYGROVE CITY", "point": Vector2(100, 100)},
	{"name": "ROUTE 30", "point": Vector2(100, 80)},
	{"name": "ROUTE 31", "point": Vector2(96, 60)},
	{"name": "VIOLET CITY", "point": Vector2(84, 60)},
	{"name": "SPROUT TOWER", "point": Vector2(85, 58)},
	{"name": "ROUTE 32", "point": Vector2(84, 92)},
	{"name": "RUINS OF ALPH", "point": Vector2(76, 76)},
	{"name": "UNION CAVE", "point": Vector2(84, 124)},
	{"name": "ROUTE 33", "point": Vector2(82, 124)},
	{"name": "AZALEA TOWN", "point": Vector2(68, 124)},
	{"name": "SLOWPOKE WELL", "point": Vector2(70, 122)},
	{"name": "ILEX FOREST", "point": Vector2(52, 120)},
	{"name": "ROUTE 34", "point": Vector2(52, 112)},
	{"name": "GOLDENROD CITY", "point": Vector2(52, 92)},
	{"name": "RADIO TOWER", "point": Vector2(50, 92)},
	{"name": "ROUTE 35", "point": Vector2(52, 76)},
	{"name": "NATIONAL PARK", "point": Vector2(52, 60)},
	{"name": "ROUTE 36", "point": Vector2(64, 60)},
	{"name": "ROUTE 37", "point": Vector2(68, 52)},
	{"name": "ECRUTEAK CITY", "point": Vector2(68, 44)},
	{"name": "TIN TOWER", "point": Vector2(70, 42)},
	{"name": "BURNED TOWER", "point": Vector2(66, 42)},
	{"name": "ROUTE 38", "point": Vector2(52, 44)},
	{"name": "ROUTE 39", "point": Vector2(36, 48)},
	{"name": "OLIVINE CITY", "point": Vector2(36, 60)},
	{"name": "LIGHTHOUSE", "point": Vector2(38, 62)},
	{"name": "BATTLE TOWER", "point": Vector2(28, 56)},
	{"name": "ROUTE 40", "point": Vector2(28, 64)},
	{"name": "WHIRL ISLANDS", "point": Vector2(28, 92)},
	{"name": "ROUTE 41", "point": Vector2(28, 100)},
	{"name": "CIANWOOD CITY", "point": Vector2(20, 100)},
	{"name": "ROUTE 42", "point": Vector2(92, 44)},
	{"name": "MT. MORTAR", "point": Vector2(84, 44)},
	{"name": "MAHOGANY TOWN", "point": Vector2(108, 44)},
	{"name": "ROUTE 43", "point": Vector2(108, 36)},
	{"name": "LAKE OF RAGE", "point": Vector2(108, 28)},
	{"name": "ROUTE 44", "point": Vector2(120, 44)},
	{"name": "ICE PATH", "point": Vector2(130, 38)},
	{"name": "BLACKTHORN CITY", "point": Vector2(132, 44)},
	{"name": "DRAGON'S DEN", "point": Vector2(132, 36)},
	{"name": "ROUTE 45", "point": Vector2(132, 64)},
	{"name": "DARK CAVE", "point": Vector2(112, 72)},
	{"name": "ROUTE 46", "point": Vector2(124, 88)},
	{"name": "SILVER CAVE", "point": Vector2(148, 68)},
	{"name": "PALLET TOWN", "point": Vector2(52, 108)},
	{"name": "ROUTE 1", "point": Vector2(52, 92)},
	{"name": "VIRIDIAN CITY", "point": Vector2(52, 76)},
	{"name": "ROUTE 2", "point": Vector2(52, 64)},
	{"name": "PEWTER CITY", "point": Vector2(52, 52)},
	{"name": "ROUTE 3", "point": Vector2(64, 52)},
	{"name": "MT. MOON", "point": Vector2(76, 52)},
	{"name": "ROUTE 4", "point": Vector2(88, 52)},
	{"name": "CERULEAN CITY", "point": Vector2(100, 52)},
	{"name": "ROUTE 24", "point": Vector2(100, 44)},
	{"name": "ROUTE 25", "point": Vector2(108, 36)},
	{"name": "ROUTE 5", "point": Vector2(100, 60)},
	{"name": "UNDERGROUND PATH", "point": Vector2(108, 76)},
	{"name": "ROUTE 6", "point": Vector2(100, 76)},
	{"name": "VERMILION CITY", "point": Vector2(100, 84)},
	{"name": "DIGLETT'S CAVE", "point": Vector2(88, 60)},
	{"name": "ROUTE 7", "point": Vector2(88, 68)},
	{"name": "ROUTE 8", "point": Vector2(116, 68)},
	{"name": "ROUTE 9", "point": Vector2(116, 52)},
	{"name": "ROCK TUNNEL", "point": Vector2(132, 52)},
	{"name": "ROUTE 10", "point": Vector2(132, 56)},
	{"name": "POWER PLANT", "point": Vector2(132, 60)},
	{"name": "LAVENDER TOWN", "point": Vector2(132, 68)},
	{"name": "LAVENDER RADIO TOWER", "point": Vector2(140, 68)},
	{"name": "CELADON CITY", "point": Vector2(76, 68)},
	{"name": "SAFFRON CITY", "point": Vector2(100, 68)},
	{"name": "ROUTE 11", "point": Vector2(116, 84)},
	{"name": "ROUTE 12", "point": Vector2(132, 80)},
	{"name": "ROUTE 13", "point": Vector2(124, 100)},
	{"name": "ROUTE 14", "point": Vector2(116, 112)},
	{"name": "ROUTE 15", "point": Vector2(104, 116)},
	{"name": "ROUTE 16", "point": Vector2(68, 68)},
	{"name": "ROUTE 17", "point": Vector2(68, 92)},
	{"name": "ROUTE 18", "point": Vector2(80, 116)},
	{"name": "FUCHSIA CITY", "point": Vector2(92, 116)},
	{"name": "ROUTE 19", "point": Vector2(92, 128)},
	{"name": "ROUTE 20", "point": Vector2(76, 132)},
	{"name": "SEAFOAM ISLANDS", "point": Vector2(68, 132)},
	{"name": "CINNABAR ISLAND", "point": Vector2(52, 132)},
	{"name": "ROUTE 21", "point": Vector2(52, 120)},
	{"name": "ROUTE 22", "point": Vector2(36, 68)},
	{"name": "VICTORY ROAD", "point": Vector2(28, 52)},
	{"name": "ROUTE 23", "point": Vector2(28, 44)},
	{"name": "INDIGO PLATEAU", "point": Vector2(28, 36)},
	{"name": "ROUTE 26", "point": Vector2(28, 92)},
	{"name": "ROUTE 27", "point": Vector2(20, 100)},
	{"name": "TOHJO FALLS", "point": Vector2(12, 100)},
	{"name": "ROUTE 28", "point": Vector2(20, 68)},
	{"name": "FAST SHIP", "point": Vector2(140, 116)},
]

var _current_landmark: int = JOHTO_START
var _cursor_landmark: int = JOHTO_START
var _region_start: int = JOHTO_START
var _region_end: int = JOHTO_END
var _open: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func open(current_landmark: int, _crystal_profile: bool = true) -> void:
	_current_landmark = current_landmark
	if current_landmark >= KANTO_START and current_landmark <= KANTO_END:
		_region_start = KANTO_START
		_region_end = KANTO_END
	else:
		_region_start = JOHTO_START
		_region_end = JOHTO_END
	_cursor_landmark = clampi(current_landmark, _region_start, _region_end)
	if current_landmark == Gen2WorldRadio.LANDMARK_SPECIAL or current_landmark == FAST_SHIP:
		_cursor_landmark = _region_start
	_open = true
	visible = true
	queue_redraw()


func handle_button(button: int) -> bool:
	if not _open:
		return false
	if button == Gen2Button.B:
		close()
		return true
	if button == Gen2Button.UP:
		_cursor_landmark = mini(_cursor_landmark + 1, _region_end)
		queue_redraw()
		return true
	if button == Gen2Button.DOWN:
		_cursor_landmark = maxi(_cursor_landmark - 1, _region_start)
		queue_redraw()
		return true
	return true


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


func cursor_landmark() -> int:
	return _cursor_landmark


func cursor_name() -> String:
	return String(LANDMARKS[_cursor_landmark].get("name", ""))


func _draw() -> void:
	if not _open:
		return
	var font: Font = ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	draw_string(font, Vector2(34, 42), "TOWN MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, TEXT)
	draw_string(
		font, Vector2(size.x - 210, 40),
		"JOHTO" if _region_start == JOHTO_START else "KANTO",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, SELECTED
	)
	var map_rect := Rect2(32, 64, size.x - 64, size.y - 158)
	draw_rect(map_rect, MAP_BACKGROUND)
	for grid_x: int in range(0, 9):
		var x: float = map_rect.position.x + map_rect.size.x * float(grid_x) / 8.0
		draw_line(Vector2(x, map_rect.position.y), Vector2(x, map_rect.end.y), MAP_GRID, 1.0)
	for grid_y: int in range(0, 7):
		var y: float = map_rect.position.y + map_rect.size.y * float(grid_y) / 6.0
		draw_line(Vector2(map_rect.position.x, y), Vector2(map_rect.end.x, y), MAP_GRID, 1.0)
	for index: int in range(_region_start, _region_end + 1):
		if index > _region_start:
			var previous := _map_point(index - 1, map_rect)
			var current := _map_point(index, map_rect)
			if previous.distance_to(current) < map_rect.size.x * 0.34:
				draw_line(previous, current, PATH, 3.0)
	for index: int in range(_region_start, _region_end + 1):
		var point := _map_point(index, map_rect)
		var color: Color = SELECTED if index == _cursor_landmark else LANDMARK
		draw_circle(point, 5.0 if index == _cursor_landmark else 3.0, color)
		if index == _current_landmark:
			draw_arc(point, 10.0, 0.0, TAU, 24, PLAYER, 2.0)
	var selected := Rect2(32, size.y - 78, size.x - 64, 42)
	draw_rect(selected, Color("#0d1a2a"))
	draw_string(font, Vector2(48, size.y - 50), cursor_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, TEXT)
	draw_string(font, Vector2(size.x - 250, size.y - 50), "UP/DOWN: browse   B: close", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MUTED)


func _map_point(index: int, map_rect: Rect2) -> Vector2:
	var source_point: Vector2 = LANDMARKS[index].get("point", Vector2.ZERO)
	return map_rect.position + Vector2(source_point.x / 160.0, source_point.y / 144.0) * map_rect.size
