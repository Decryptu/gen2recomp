extends SubViewportContainer

## A world renderer that draws geometry instead of hardware tiles.
##
## The point is that nothing about the world requires the view to be 2D. It reads
## exactly what the built-in renderer reads (each walk cell's collision
## permission, the block grid, the tileset's palettes, the player's cell) and
## extrudes a solid per cell with a camera on the player.
##
## It answers [code]uses_hardware_viewport[/code] false, so it gets the Game Boy
## screen's rectangle at window resolution rather than a 160x144 buffer. Text
## boxes and menus stay hardware pixels over the top.
##
## It reads the world and never writes it, so the two renderers can be swapped
## mid-step and neither can tell the other what changed.

## What mod.json declares, which is how the renderer names itself to the host
## when it reads its own settings back.
const MOD_ID: StringName = &"voxel_preview"
const OPTION_PITCH: StringName = &"pitch"
const OPTION_RECENTRE: StringName = &"recentre"
const ACTION_PITCH_UP: StringName = &"pitch_up"
const ACTION_PITCH_DOWN: StringName = &"pitch_down"

const CELL_SIZE: float = 1.0
const WALL_HEIGHT: float = 1.0
const WATER_DEPTH: float = -0.25
## How far from the player the camera sits, and the angle above the horizon it
## starts at: together the (0, 9, 7.5) offset this view used before the pitch
## was steerable. Roughly what the overworld reads at while still showing the
## extrusion.
const CAMERA_DISTANCE: float = 11.715
const CAMERA_PITCH_DEGREES: float = 50.19
## Q and E walk the pitch between a near-flat and a near-overhead camera. The
## screen does not read either key, which is the only reason this view is
## allowed to.
const CAMERA_PITCH_STEP: float = 5.0
const CAMERA_PITCH_LIMITS := Vector2(10.0, 88.0)
## Light colour per time of day, in the order Gen2WorldPalette names them.
const DAY_LIGHT: Array[Color] = [
	Color(1.0, 0.94, 0.86), Color(1.0, 1.0, 0.98),
	Color(0.72, 0.76, 1.0), Color(0.45, 0.5, 0.7),
]

var _world: Gen2WorldAPI = null
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _light: DirectionalLight3D = null
var _terrain: MeshInstance3D = null
var _player: MeshInstance3D = null
var _objects: Node3D = null
var _time_of_day: int = 0
var _camera_pitch: float = CAMERA_PITCH_DEGREES
var _text_box_rect := Rect2i()


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	# Its own 3D world, so this never shares a scene with whatever else the
	# screen has open.
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#101a2c")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#6a7ba0")
	settings.ambient_light_energy = 0.6
	environment.environment = settings
	_viewport.add_child(environment)

	_light = DirectionalLight3D.new()
	_light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	_viewport.add_child(_light)

	_camera = Camera3D.new()
	_camera.fov = 45.0
	_viewport.add_child(_camera)

	_terrain = MeshInstance3D.new()
	_viewport.add_child(_terrain)

	_objects = Node3D.new()
	_viewport.add_child(_objects)

	_player = MeshInstance3D.new()
	var player_mesh := BoxMesh.new()
	player_mesh.size = Vector3(0.6, 1.2, 0.6)
	_player.mesh = player_mesh
	_player.material_override = _material(Color("#d34a5a"))
	_viewport.add_child(_player)

	# The setting mod.gd registered, read once here and again whenever it
	# changes, so a value picked in the start menu or the launcher reaches the
	# camera without this view polling for it. Null means the entry script did
	# not run, which is what a renderer loaded on its own gets.
	var host: Gen2ModHost = Gen2ModHost.instance()
	var pitch: Variant = host.option(MOD_ID, OPTION_PITCH)
	if pitch != null:
		_camera_pitch = float(pitch)
	host.option_changed.connect(_on_option_changed)
	host.action_changed.connect(_on_action_changed)


## This renderer is not made of hardware pixels, so it asks for the layer that is
## not either. See Gen2ModHost.RENDERER_SURFACE_METHOD.
func uses_hardware_viewport() -> bool:
	return false


## The cartridge draws its text box on its own white background; over this view
## that box is a slab across the map, so the field is asked for translucent. The
## frame and the glyphs stay opaque whatever this answers. See
## Gen2ModHost.RENDERER_INTERFACE_OPACITY_METHOD.
func interface_opacity() -> float:
	return 0.75


## Where that box is, in hardware pixels, and empty when none is on screen. This
## view composes nothing around it and only records it; a renderer staging a
## scene below the box reads it instead of assuming the standard six rows. See
## Gen2ModHost.RENDERER_TEXT_BOX_METHOD.
func set_text_box_rect(rect: Rect2i) -> void:
	_text_box_rect = rect


func text_box_rect() -> Rect2i:
	return _text_box_rect


func _on_option_changed(id: StringName, key: StringName, value: Variant) -> void:
	if id != MOD_ID:
		return
	if key == OPTION_PITCH:
		_set_camera_pitch(float(value))
	elif key == OPTION_RECENTRE:
		_set_camera_pitch(CAMERA_PITCH_DEGREES)


## The mod's own controls, arriving as ids rather than as an InputEvent, so the
## same handler serves a key, a pad button and a finger on the on-screen pad.
func _on_action_changed(id: StringName, key: StringName, pressed: bool) -> void:
	if id != MOD_ID or not pressed:
		return
	match key:
		ACTION_PITCH_DOWN:
			_set_camera_pitch(_camera_pitch - CAMERA_PITCH_STEP)
		ACTION_PITCH_UP:
			_set_camera_pitch(_camera_pitch + CAMERA_PITCH_STEP)


## The container's own size is all that is set here: a stretching
## SubViewportContainer owns its viewport's size and refuses a manual one.
func set_native_size(size_pixels: Vector2i) -> void:
	size = Vector2(size_pixels)


func set_world(world: Gen2WorldAPI, _animation: Gen2WorldAnimation = null) -> void:
	_world = world
	_rebuild_terrain()
	refresh()


func set_time_of_day(time_of_day: int) -> void:
	_time_of_day = clampi(time_of_day, 0, DAY_LIGHT.size() - 1)
	if _light != null:
		_light.light_color = DAY_LIGHT[_time_of_day]
		_light.light_energy = 0.6 if _time_of_day >= 2 else 1.1
	_rebuild_terrain()


## Tileset animation replaces atlas slots, which this view samples once per
## rebuild rather than per frame. A renderer that textured its geometry with the
## live strip would rebuild its material here instead.
func refresh_animation() -> void:
	pass


## The raw leftovers, for what a declared action cannot express: pointer and
## stick motion a free camera wants. Named controls go through
## _on_action_changed instead, since those are bindable and reach a touchscreen.
## See Gen2ModHost.RENDERER_INPUT_METHOD: a movement or interaction key never
## arrives here, because the screen claims those first.
func handle_world_input(_event: InputEvent) -> bool:
	return false


func camera_pitch() -> float:
	return _camera_pitch


func _set_camera_pitch(degrees: float) -> void:
	_camera_pitch = clampf(degrees, CAMERA_PITCH_LIMITS.x, CAMERA_PITCH_LIMITS.y)
	refresh()


func refresh() -> void:
	if _world == null or _camera == null:
		return
	var here: Vector3 = _player_position()
	# The hop is the card's alone: arcing the camera with it shakes the view.
	_player.position = here + Vector3(0.0, 0.6 + _player_height(), 0.0)
	_camera.position = here + _camera_offset()
	_camera.look_at(here, Vector3.UP)
	_rebuild_objects()


func _camera_offset() -> Vector3:
	var pitch: float = deg_to_rad(_camera_pitch)
	return Vector3(0.0, sin(pitch), cos(pitch)) * CAMERA_DISTANCE


func _cell_center(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) * CELL_SIZE, 0.0, float(cell.y) * CELL_SIZE)


## The committed cell plus its in-flight step, so the box and camera ease into a
## new cell instead of snapping. Gen2WorldAPI composes the two.
func _player_position() -> Vector3:
	var cell_position: Vector2 = _world.player_position_cells()
	return Vector3(cell_position.x * CELL_SIZE, 0.0, cell_position.y * CELL_SIZE)


## The ledge hop's own arc, in cells: the host gives it in world pixels, and a
## walk cell is Gen2WorldAPI.CELL_PIXELS of them.
func _player_height() -> float:
	return _world.player_height_offset_pixels() \
		/ float(Gen2WorldAPI.CELL_PIXELS) * CELL_SIZE


## One solid per walk cell, extruded by what the cell's collision permission
## says it is. Built as a single mesh: a map is a few thousand cells and a node
## for each of them would cost more than the geometry does.
func _rebuild_terrain() -> void:
	if _world == null or _world.current_map == null or _terrain == null:
		return
	var map_size: Vector2i = _world.map_size_cells()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for y: int in map_size.y:
		for x: int in map_size.x:
			var cell := Vector2i(x, y)
			var permission: int = _world.collision_permission_at(cell)
			var height: float = WALL_HEIGHT if permission == Gen2WorldCollision.WALL_TILE \
				else (WATER_DEPTH if permission == Gen2WorldCollision.WATER_TILE else 0.0)
			_add_cell(surface, cell, height, _cell_color(cell, permission))
	surface.generate_normals()
	_terrain.mesh = surface.commit()
	var ground := StandardMaterial3D.new()
	ground.vertex_color_use_as_albedo = true
	ground.roughness = 0.9
	_terrain.material_override = ground


## The colour the 2D view would draw this cell's top-left tile in. Sampling the
## same palettes is what keeps a Johto route looking like a Johto route without
## this mod shipping any art of its own.
func _cell_color(cell: Vector2i, permission: int) -> Color:
	if permission == Gen2WorldCollision.WATER_TILE:
		return Color("#2f6ad6")
	var palettes: Array = Gen2WorldPalette.tile_palettes(
		_world.data, _world.current_map, _world.current_tileset, _time_of_day
	)
	var block: int = _world.block_at(cell.x >> 1, cell.y >> 1)
	var tile: int = _world.current_tileset.tile_index(
		block, (cell.y & 1) * 2 * RomLayout.MAP_BLOCK_TILE_WIDTH + (cell.x & 1) * 2
	)
	if tile < 0 or tile >= palettes.size():
		return Color("#6f9c4a")
	var palette: PackedColorArray = palettes[tile]
	if palette.is_empty():
		return Color("#6f9c4a")
	# The tile's four colours averaged. A single index picks either the highlight
	# or the outline and reads as white or near-black; the average is close to
	# what the tile looks like from a distance, which is what a solid is.
	var average := Color(0.0, 0.0, 0.0)
	for entry: Color in palette:
		average += entry
	return average / float(palette.size())


func _add_cell(surface: SurfaceTool, cell: Vector2i, height: float, color: Color) -> void:
	var center: Vector3 = _cell_center(cell)
	var half: float = CELL_SIZE * 0.5
	var top: float = height
	var corners: Array[Vector3] = [
		center + Vector3(-half, top, -half), center + Vector3(half, top, -half),
		center + Vector3(half, top, half), center + Vector3(-half, top, half),
	]
	surface.set_color(color)
	_add_quad(surface, corners[0], corners[1], corners[2], corners[3])
	if is_zero_approx(height):
		return
	# Skirt down to the ground plane so a wall reads as a solid rather than a
	# floating lid.
	var shade: Color = color.darkened(0.35)
	surface.set_color(shade)
	for edge: int in 4:
		var first: Vector3 = corners[edge]
		var second: Vector3 = corners[(edge + 1) % 4]
		_add_quad(
			surface, first, second,
			Vector3(second.x, 0.0, second.z), Vector3(first.x, 0.0, first.z)
		)


func _add_quad(
	surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3
) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(d)


## The map's live objects, rebuilt on each refresh because an object can be
## hidden, moved or deleted by a script between one step and the next.
func _rebuild_objects() -> void:
	if _objects == null:
		return
	for child: Node in _objects.get_children():
		child.queue_free()
	for object: Gen2WorldObject in _world.visible_objects():
		var marker := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.6, 1.0, 0.6)
		marker.mesh = mesh
		marker.material_override = _material(Color("#f3c969"))
		# The same fractional offset the player box reads, from the object's
		# own in-flight step, so a wandering NPC eases between cells here
		# without this renderer knowing anything about hardware pixels.
		var offset: Vector2 = object.step_offset_cells()
		marker.position = _cell_center(object.cell) \
			+ Vector3(offset.x, 0.0, offset.y) * CELL_SIZE \
			+ Vector3(0.0, 0.5, 0.0)
		_objects.add_child(marker)


func _material(color: Color) -> StandardMaterial3D:
	var made := StandardMaterial3D.new()
	made.albedo_color = color
	made.roughness = 0.8
	return made
