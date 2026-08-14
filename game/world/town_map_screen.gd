class_name Gen2TownMapScreen
extends Control

## The region map, embedded in the overworld the way the trainer card and the
## Hall of Fame are.
##
## [Gen2TownMap] owns the cursor walk and the region choice, [Gen2TownMapPage]
## the tile screen; this composes the two and draws the objects over them: the
## cursor `PokegearMap_InitCursor` spawns and the player icon
## `PokegearMap_InitPlayerIcon` does.
##
## Landmark coordinates are shadow-OAM values with the hardware's own offsets
## already in them (`data/maps/landmarks.asm`'s `db x + 8, y + 16`), which the
## importer takes back off, so a landmark's stored point is the centre of its
## 16x16 icon.

signal closed()

## The region map is drawn in hardware pixels, and the Pokegear's card list it is
## opened from is ordinary UI at window resolution, so the screen carries a
## [Gen2Screen] of its own rather than trusting whatever it was added to.
const SCREEN_SCENE: PackedScene = preload("res://game/render/gen2_screen.tscn")

const CURSOR_TILE: int = 0x04
const ICON_SIZE: int = 16
## `.OAMData_RedWalk`'s `dbsprite -1, -1`: the four objects sit a tile up and
## left of the struct's own coordinate.
const ICON_ORIGIN: int = 8

## `.Frameset_RedWalk`, whose four entries are `oamframe X, 8` and so last nine
## frames each: standing, walking, standing, walking mirrored.
const WALK_FRAME_LENGTH: int = 9
const WALK_FRAMES: Array[int] = [0, 1, 2, 3]

## `PAL_OW_RED`, which is what `.OAMData_RedWalk` gives every object it draws.
## `_CGB_PokegearPals` writes background palettes only, so the objects keep the
## overworld's own.
const OBJECT_PALETTE: int = 0

var _data: GameData = null
var _map: Gen2TownMap = null
var _page: Gen2TownMapPage = null
var _cards: Array = []
var _female: bool = false
var _time_of_day: int = Gen2WorldPalette.TIME_MORNING
var _frames: int = 0
var _open: bool = false
## The 160x144 field inside the hardware screen, which everything is drawn into.
var _field: Control = null
var _background: TextureRect = null
var _cursor_icon: TextureRect = null
var _player_icon: TextureRect = null
## Leftover of a hardware frame this screen has not counted yet.
var _elapsed: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if _page != null:
		_refresh()


## [param landmark] is `TownMap_GetCurrentLandmark`'s answer, [param hall_of_fame]
## `STATUSFLAGS_HALL_OF_FAME_F`, and [param screen] which frame is drawn over the
## region map: `_TownMap`'s own corner box or the Pokegear card's icon row.
## [param cards] is the owned `wPokegearFlags` cards, which only the card frame
## reads.
##
## Optional the way the other overlays are: a cache with no region map answers
## false and the caller keeps its menu open.
func open(
	data: GameData,
	landmark: int,
	hall_of_fame: bool = false,
	screen: StringName = Gen2TownMap.SCREEN_TOWN_MAP,
	cards: Array = [],
	female: bool = false,
	time_of_day: int = Gen2WorldPalette.TIME_MORNING,
) -> bool:
	_data = data
	_page = Gen2TownMapPage.from_data(_data) if _data != null else null
	if _data == null or _data.landmark_count() == 0 or _page == null or not _page.ready():
		# A caller that added the node before opening would otherwise be left
		# with an empty rectangle over its own menu.
		visible = false
		return false
	_map = Gen2TownMap.create(
		landmark, Gen2WorldState.is_crystal_profile(_data), hall_of_fame, screen
	)
	_cards = cards.duplicate()
	_female = female
	_time_of_day = time_of_day
	_frames = 0
	_open = true
	visible = true
	if is_inside_tree() and _background != null:
		_refresh()
	return true


func map() -> Gen2TownMap:
	return _map


func cursor_landmark() -> int:
	return _map.cursor if _map != null else 0


func cursor_name() -> String:
	return _data.landmark_name(cursor_landmark()) if _data != null else ""


## `.loop`'s own joypad read: B leaves and the d-pad walks the window. Every
## other button is swallowed, which is what the loop does with them.
func handle_button(button: int) -> bool:
	if not _open or _map == null:
		return false
	if button == Gen2Button.B:
		close()
		return true
	if _map.press(button):
		_refresh()
	return true


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


## One hardware frame. Only the player icon moves: the cursor's own
## `SPRITEANIMSTRUCT_ANIM_SEQ_ID` is overwritten with `SPRITE_ANIM_FUNC_NULL`, so
## it holds `.Frameset_StillCursor`'s single entry forever.
func advance_frame() -> void:
	_frames += 1
	if _frames % WALK_FRAME_LENGTH == 0:
		_refresh_player_icon()


## The whole screen as one 160x144 image, objects included, for a preview or a
## test that wants pixels rather than a viewport.
func render() -> Image:
	var out: Image = _background_image()
	if _map == null:
		return out
	for object: Array in [
		[_cursor_image(), _map.cursor], [_player_image(), _map.player_landmark],
	]:
		if not _has_landmark(int(object[1])):
			continue
		out.blend_rect(
			object[0], Rect2i(Vector2i.ZERO, Vector2i(ICON_SIZE, ICON_SIZE)),
			_icon_position(int(object[1]))
		)
	return out


func _process(delta: float) -> void:
	if not _open:
		return
	_elapsed += delta
	while _elapsed >= Gen2WorldAnimation.FRAME_SECONDS:
		_elapsed -= Gen2WorldAnimation.FRAME_SECONDS
		advance_frame()


## The cursor is built before the player icon so the player draws over it:
## `_TownMap` spawns the player's struct first, which takes the lower shadow-OAM
## indices, and a lower index is the one that shows.
func _build() -> void:
	var screen: Gen2Screen = SCREEN_SCENE.instantiate() as Gen2Screen
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	_field = Control.new()
	_field.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.display(_field)
	_background = _sprite()
	_cursor_icon = _sprite()
	_player_icon = _sprite()


func _sprite() -> TextureRect:
	var node := TextureRect.new()
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(node)
	return node


func _refresh() -> void:
	if _background != null:
		_background.texture = ImageTexture.create_from_image(_background_image())
		_background.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_refresh_player_icon()
	_refresh_cursor()


func _background_image() -> Image:
	if _page == null or _map == null or _data == null:
		return Image.create(Gen2Screen.WIDTH, Gen2Screen.HEIGHT, false, Image.FORMAT_RGBA8)
	var region: String = "kanto" if _map.region() == Gen2TownMap.REGION_KANTO else "johto"
	var landmark: Dictionary = _data.landmark(_map.cursor)
	return _page.image(_data, _page.tilemap(
		_data.town_map_region(region), landmark.get("codes", PackedByteArray()), _map.screen, _cards
	), _female)


## `PokegearMap_InitCursor`: `.Frameset_StillCursor` over `PokegearSpritesGFX`'s
## tile $04, placed on the cursor landmark.
func _refresh_cursor() -> void:
	if _cursor_icon == null or _map == null:
		return
	_place(_cursor_icon, _map.cursor)
	_cursor_icon.texture = ImageTexture.create_from_image(_cursor_image())


func _cursor_image() -> Image:
	var tiles: PackedByteArray = _data.tile_indices("pokegear_sprites") if _data != null \
		else PackedByteArray()
	var palette: PackedColorArray = _object_palette()
	var out := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	if tiles.is_empty() or palette.is_empty():
		return out
	var width: int = tiles.size() / Gen2TownMapPage.TILE
	for quadrant: int in 4:
		var source_x: int = (CURSOR_TILE + quadrant) * Gen2TownMapPage.TILE
		var to_x: int = (quadrant & 1) * Gen2TownMapPage.TILE
		var to_y: int = (quadrant >> 1) * Gen2TownMapPage.TILE
		for y: int in Gen2TownMapPage.TILE:
			for x: int in Gen2TownMapPage.TILE:
				var index: int = tiles[y * width + source_x + x]
				# Object colour zero is transparent under the hardware's own
				# rules, which is what lets the cursor sit over the map.
				if index == 0:
					continue
				out.set_pixel(
					to_x + x, to_y + y, palette[clampi(index, 0, palette.size() - 1)]
				)
	return out


## `PokegearMap_InitPlayerIcon`: `GetPlayerIcon`'s standing and walking frames,
## which are the player's own overworld sprite facing down.
func _refresh_player_icon() -> void:
	if _player_icon == null or _map == null:
		return
	_place(_player_icon, _map.player_landmark)
	_player_icon.texture = ImageTexture.create_from_image(_player_image())


func _player_image() -> Image:
	var blank := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0, 0, 0, 0))
	if _data == null:
		return blank
	var number: int = Gen2WorldSprite.player_normal_sprite(_female)
	var sprite: Gen2WorldSprite = _data.overworld_sprite(number)
	if sprite == null:
		return blank
	@warning_ignore("integer_division")
	var step: int = (_frames / WALK_FRAME_LENGTH) % WALK_FRAMES.size()
	return Gen2WorldSprite.image_for(
		sprite,
		_data.overworld_sprite_indices(number),
		_object_palette(),
		Gen2WorldSprite.FACING_DOWN,
		WALK_FRAMES[step],
	)


func _object_palette() -> PackedColorArray:
	if _data == null:
		return PackedColorArray()
	return _data.overworld_sprite_palette(OBJECT_PALETTE, _time_of_day)


func _place(node: TextureRect, landmark: int) -> void:
	node.visible = _has_landmark(landmark)
	if node.visible:
		node.position = Vector2(_icon_position(landmark))


func _has_landmark(landmark: int) -> bool:
	return _data != null and not _data.landmark(landmark).is_empty()


func _icon_position(landmark: int) -> Vector2i:
	var entry: Dictionary = _data.landmark(landmark)
	return Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))) \
		- Vector2i(ICON_ORIGIN, ICON_ORIGIN)
