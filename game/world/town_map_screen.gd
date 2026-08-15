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
## `Pokedex_GetArea`'s AREA screen is the same two pieces with a third object
## set: no cursor, one blinking nest icon per landmark the species is found at,
## and the player icon in their place while SELECT is held.
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
## `PAL_OW_BLUE`, which `.ShowPlayerLoop` gives Kris. The Pokegear's own icon
## takes `PAL_OW_RED` whoever the player is; only the dex area asks.
const OBJECT_PALETTE_FEMALE: int = 1

## `InitPokegearModeIndicatorArrow`, which the Pokegear spawns on every card
## including this one. Its position is [Gen2PokegearScreen]'s, at the MAP card's
## own entry in `AnimatePokegearModeIndicatorArrow.XCoords`.
const ARROW_TILE: int = 0x00
const ARROW_CARD: StringName = &"map"

## `PokedexNestIconGFX`, one 8x8 object tile whose OAM position is the landmark's
## own coordinates less four, which centres it on the point.
const NEST_TILE: int = 0
const NEST_ICON_SIZE: int = 8
const NEST_ORIGIN: int = 4
## `.BlinkNestIcons` reads `hVBlankCounter`: the set is redrawn or cleared every
## sixteenth frame and left alone in between.
const NEST_BLINK_FRAMES: int = 0x10
## `.String_SNest`, printed straight after `GetPokemonName`'s answer.
const NEST_HEADER_SUFFIX: String = "'S NEST"

## What the shadow OAM currently holds, which is a state rather than a redraw:
## the blink only writes it every sixteenth frame, so releasing SELECT leaves the
## player icon standing until the next one.
const OAM_NESTS: StringName = &"nests"
const OAM_PLAYER: StringName = &"player"
const OAM_CLEARED: StringName = &"cleared"

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
## The Pokegear's mode arrow, which is up on the card and on no other screen.
var _arrow: TextureRect = null
## `.pressedA`'s own answer, which `_FlyMap` returns in `e`: the chosen spawn, or
## -1 for the `ld a, -1` a B press leaves.
var _chosen_spawn: int = -1
var _player_icon: TextureRect = null
## The dex area's own state: the species its header names, one landmark list per
## region and what the shadow OAM holds this frame.
var _species: int = 0
var _nests: Array = []
var _oam: StringName = OAM_NESTS
var _select_held: bool = false
var _nest_icons: Array[TextureRect] = []
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
	if screen != Gen2TownMap.SCREEN_DEX_AREA:
		_species = 0
		_nests = []
		for icon: TextureRect in _nest_icons:
			icon.visible = false
	_cards = cards.duplicate()
	_female = female
	_time_of_day = time_of_day
	_frames = 0
	# `.GetAndPlaceNest` runs before `.loop`, so the icons are up on frame zero.
	_oam = OAM_NESTS
	_select_held = false
	_open = true
	visible = true
	if is_inside_tree() and _background != null:
		_refresh()
	return true


## `Pokedex_GetArea`. [param nests] is one landmark list per region, in
## [Gen2TownMap]'s own order, which is what [method Gen2WorldEncounter.nests]
## answers; [param landmark] is `wDexCurLocation`, where the player is standing.
func open_dex_area(
	data: GameData,
	species: int,
	nests: Array,
	landmark: int,
	hall_of_fame: bool = false,
	female: bool = false,
	time_of_day: int = Gen2WorldPalette.TIME_MORNING,
) -> bool:
	_species = species
	_nests = nests.duplicate(true)
	return open(
		data, landmark, hall_of_fame, Gen2TownMap.SCREEN_DEX_AREA, [], female, time_of_day
	)


## `_FlyMap`: the region map with the cursor walking the flypoints the player has
## visited. [param in_kanto] is which map `FlyMap` opens, which is the region the
## player is standing in, and [param visited] which `FLY_*` indexes
## `CheckIfVisitedFlypoint` answers for.
##
## The answer is taken with [method chosen_spawn] once this closes: -1 for a
## cancel, and the flypoint's own spawn for a choice, which is exactly the byte
## `.pressedA` leaves in `e`.
func open_fly(
	data: GameData,
	landmark: int,
	in_kanto: bool,
	visited: Array[int],
	female: bool = false,
	time_of_day: int = Gen2WorldPalette.TIME_MORNING,
) -> bool:
	_chosen_spawn = -1
	if not open(
		data, landmark, false, Gen2TownMap.SCREEN_FLY, [], female, time_of_day
	):
		return false
	_map = Gen2TownMap.fly(
		landmark, in_kanto, visited, Gen2WorldState.is_crystal_profile(_data)
	)
	if is_inside_tree() and _background != null:
		_refresh()
	return true


## Which spawn the fly map was left on: -1 until one is chosen, and -1 for good
## when B closed it.
func chosen_spawn() -> int:
	return _chosen_spawn


func map() -> Gen2TownMap:
	return _map


## Where the cursor is drawn. The fly map's own cursor is a flypoint rather than
## a landmark, and `Flypoints` is what turns one into the other.
func cursor_landmark() -> int:
	if _map == null:
		return 0
	if _map.screen != Gen2TownMap.SCREEN_FLY:
		return _map.cursor
	var row: Dictionary = _data.flypoint(_map.cursor) if _data != null else {}
	return int(row.get("landmark", 0))


func cursor_name() -> String:
	return _data.landmark_name(cursor_landmark()) if _data != null else ""


## `.loop`'s own joypad read: B leaves and the d-pad walks the window. Every
## other button is swallowed, which is what the loop does with them.
##
## The dex area's loop leaves on A as well as B, walks regions rather than
## landmarks, and reads SELECT as a held state; see [method release_button].
func handle_button(button: int) -> bool:
	if not _open or _map == null:
		return false
	if button == Gen2Button.A and _map.screen == Gen2TownMap.SCREEN_FLY:
		# `.pressedA` reads the flypoint's own spawn out of `Flypoints + 1`.
		var row: Dictionary = _data.flypoint(_map.cursor) if _data != null else {}
		_chosen_spawn = int(row.get("spawn", -1)) if not row.is_empty() else -1
		close()
		return true
	if button == Gen2Button.B \
		or (button == Gen2Button.A and _map.screen == Gen2TownMap.SCREEN_DEX_AREA):
		close()
		return true
	if button == Gen2Button.SELECT and _map.screen == Gen2TownMap.SCREEN_DEX_AREA:
		_select_held = true
		_apply_select()
		return true
	if _map.press(button):
		# `.left` and `.right` write the new region's icons at once rather than
		# waiting for the blink.
		_oam = OAM_NESTS
		_refresh()
	return true


## The other half of `hJoypadDown`, which a press-only host cannot say. Only the
## dex area's SELECT reads it.
func release_button(button: int) -> void:
	if button == Gen2Button.SELECT:
		_select_held = false


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


## One hardware frame. Only the player icon moves: the cursor's own
## `SPRITEANIMSTRUCT_ANIM_SEQ_ID` is overwritten with `SPRITE_ANIM_FUNC_NULL`, so
## it holds `.Frameset_StillCursor`'s single entry forever.
##
## The dex area animates nothing. Its own frame is `.BlinkNestIcons`, which
## shows the icons for sixteen frames and hides them for sixteen; the player
## icon it draws instead is `GetPlayerIcon`'s standing frame, not a walk.
func advance_frame() -> void:
	_frames += 1
	if _map != null and _map.screen == Gen2TownMap.SCREEN_DEX_AREA:
		_advance_dex_area()
		return
	if _frames % WALK_FRAME_LENGTH == 0:
		_refresh_player_icon()


func _advance_dex_area() -> void:
	if _select_held:
		_apply_select()
		return
	if _frames % NEST_BLINK_FRAMES != 0:
		return
	_oam = OAM_NESTS if (_frames & NEST_BLINK_FRAMES) != 0 else OAM_CLEARED
	_refresh_objects()


## `.HideNestsShowPlayer`, whose `.CheckPlayerLocation` empties the whole of
## shadow OAM when the player is in the region that is not on screen.
func _apply_select() -> void:
	_oam = OAM_PLAYER if _map != null and _map.player_in_region() else OAM_CLEARED
	_refresh_objects()


## The whole screen as one 160x144 image, objects included, for a preview or a
## test that wants pixels rather than a viewport.
func render() -> Image:
	var out: Image = _background_image()
	if _map == null:
		return out
	if _map.screen == Gen2TownMap.SCREEN_DEX_AREA:
		return _render_dex_area(out)
	if _map.screen == Gen2TownMap.SCREEN_POKEGEAR_CARD:
		out.blend_rect(
			_icon_from("pokegear_sprites", ARROW_TILE),
			Rect2i(Vector2i.ZERO, Vector2i(ICON_SIZE, ICON_SIZE)),
			Gen2PokegearScreen.ARROW_AT + Vector2i(
				Gen2PokegearScreen.ARROW_CARD_STRIDE
				* Gen2PokegearScreen.ARROW_CARDS.find(ARROW_CARD),
				0
			)
		)
	for object: Array in [
		[_cursor_image(), cursor_landmark()], [_player_image(), _map.player_landmark],
	]:
		if not _has_landmark(int(object[1])):
			continue
		out.blend_rect(
			object[0], Rect2i(Vector2i.ZERO, Vector2i(ICON_SIZE, ICON_SIZE)),
			_icon_position(int(object[1]))
		)
	return out


func _render_dex_area(out: Image) -> Image:
	if _oam == OAM_PLAYER:
		out.blend_rect(
			_player_image(), Rect2i(Vector2i.ZERO, Vector2i(ICON_SIZE, ICON_SIZE)),
			_icon_position(_map.player_landmark)
		)
		return out
	if _oam != OAM_NESTS:
		return out
	var icon: Image = _nest_image()
	for landmark: int in current_nests():
		if not _has_landmark(landmark):
			continue
		out.blend_rect(
			icon, Rect2i(Vector2i.ZERO, Vector2i(NEST_ICON_SIZE, NEST_ICON_SIZE)),
			_nest_position(landmark)
		)
	return out


## Which of the three things the dex area's shadow OAM is holding: the nest set,
## the player icon, or nothing.
func shadow_oam() -> StringName:
	return _oam


## The landmarks the region on screen holds the species at, which is the list
## `.GetAndPlaceNest` last loaded.
func current_nests() -> Array:
	if _map == null or _map.region() >= _nests.size():
		return []
	var list: Variant = _nests[_map.region()]
	return list if list is Array else []


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
	_arrow = _sprite()
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
	_refresh_arrow()
	if _map != null and _map.screen == Gen2TownMap.SCREEN_DEX_AREA:
		_refresh_objects()
		return
	_refresh_player_icon()
	_refresh_cursor()


## The dex area's shadow OAM, which holds one of three things whole rather than
## a per-object position.
func _refresh_objects() -> void:
	if _cursor_icon == null or _player_icon == null:
		return
	_cursor_icon.visible = false
	_player_icon.visible = _oam == OAM_PLAYER and _map != null \
		and _has_landmark(_map.player_landmark)
	if _player_icon.visible:
		_player_icon.position = Vector2(_icon_position(_map.player_landmark))
		_player_icon.texture = ImageTexture.create_from_image(_player_image())
	var landmarks: Array = current_nests() if _oam == OAM_NESTS else []
	while _nest_icons.size() < landmarks.size():
		_nest_icons.append(_sprite())
	var icon: Image = _nest_image() if not landmarks.is_empty() else null
	for index: int in _nest_icons.size():
		var node: TextureRect = _nest_icons[index]
		var landmark: int = int(landmarks[index]) if index < landmarks.size() else -1
		node.visible = landmark >= 0 and _has_landmark(landmark)
		if not node.visible:
			continue
		node.position = Vector2(_nest_position(landmark))
		node.texture = ImageTexture.create_from_image(icon)


## Up only on the Pokegear's own card: `OverworldTownMap`, the fly map and the
## dex area each open the region map without a Pokegear around it.
func _refresh_arrow() -> void:
	if _arrow == null:
		return
	_arrow.visible = _map != null and _map.screen == Gen2TownMap.SCREEN_POKEGEAR_CARD
	if not _arrow.visible:
		return
	_arrow.position = Vector2(
		Gen2PokegearScreen.ARROW_AT + Vector2i(
			Gen2PokegearScreen.ARROW_CARD_STRIDE
			* Gen2PokegearScreen.ARROW_CARDS.find(ARROW_CARD),
			0
		)
	)
	_arrow.texture = ImageTexture.create_from_image(_icon_from("pokegear_sprites", ARROW_TILE))


func _background_image() -> Image:
	if _page == null or _map == null or _data == null:
		return Image.create(Gen2Screen.WIDTH, Gen2Screen.HEIGHT, false, Image.FORMAT_RGBA8)
	var codes: PackedByteArray = _header_codes()
	return _page.image(_data, _page.tilemap(
		_data.town_map_region(Gen2TownMap.region_name(_map.region())),
		codes, _map.screen, _cards
	), _female)


## The landmark name each map screen puts in its own box, or `GetPokemonName`
## and `.String_SNest` for the dex area.
func _header_codes() -> PackedByteArray:
	if _map.screen != Gen2TownMap.SCREEN_DEX_AREA:
		return _data.landmark(cursor_landmark()).get("codes", PackedByteArray())
	var name: String = String(_data.species(_species).get("name", ""))
	var out: PackedByteArray = Gen2Text.encode(name)
	out.append_array(Gen2Text.encode(NEST_HEADER_SUFFIX))
	return out


## `PokegearMap_InitCursor`: `.Frameset_StillCursor` over `PokegearSpritesGFX`'s
## tile $04, placed on the cursor landmark.
func _refresh_cursor() -> void:
	if _cursor_icon == null or _map == null:
		return
	_place(_cursor_icon, cursor_landmark())
	_cursor_icon.texture = ImageTexture.create_from_image(_cursor_image())


func _cursor_image() -> Image:
	return _icon_from("pokegear_sprites", CURSOR_TILE)


## One 16x16 object out of a tile strip, as the four tiles from [param first].
## [param flip] is `B_OAM_XFLIP`, which the hardware applies to each tile where
## it stands rather than mirroring the square, so the quadrants keep their
## corners.
func _icon_from(sheet: String, first: int, flip: bool = false) -> Image:
	var tiles: PackedByteArray = _data.tile_indices(sheet) if _data != null \
		else PackedByteArray()
	var palette: PackedColorArray = _object_palette()
	var out := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	if tiles.is_empty() or palette.is_empty():
		return out
	var width: int = tiles.size() / Gen2TownMapPage.TILE
	for quadrant: int in 4:
		var source_x: int = (first + quadrant) * Gen2TownMapPage.TILE
		var to_x: int = (quadrant & 1) * Gen2TownMapPage.TILE
		var to_y: int = (quadrant >> 1) * Gen2TownMapPage.TILE
		for y: int in Gen2TownMapPage.TILE:
			for x: int in Gen2TownMapPage.TILE:
				var index: int = tiles[
					y * width + source_x + (Gen2TownMapPage.TILE - 1 - x if flip else x)
				]
				# Object colour zero is transparent under the hardware's own
				# rules, which is what lets an icon sit over the map.
				if index == 0:
					continue
				out.set_pixel(
					to_x + x, to_y + y, palette[clampi(index, 0, palette.size() - 1)]
				)
	return out


## `PokegearMap_InitPlayerIcon`: `GetPlayerIcon`'s standing and walking frames,
## which are the player's own overworld sprite facing down. `Pokegear_LoadGFX`
## copies `FastShipGFX` over those same tiles while the player is on the S.S.
## Aqua, so the icon there is the ship walking through the same four frames.
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
	@warning_ignore("integer_division")
	var step: int = (_frames / WALK_FRAME_LENGTH) % WALK_FRAMES.size()
	if _map != null and _map.screen == Gen2TownMap.SCREEN_DEX_AREA:
		# `.ShowPlayerLoop` writes four fixed tile offsets rather than starting a
		# sprite anim, so the dex area's icon never walks.
		step = 0
	if _map != null and _map.player_landmark == Gen2WorldRadio.fast_ship_landmark(_map.crystal):
		return _fast_ship_image(step)
	var number: int = Gen2WorldSprite.player_normal_sprite(_female)
	var sprite: Gen2WorldSprite = _data.overworld_sprite(number)
	if sprite == null:
		return blank
	return Gen2WorldSprite.image_for(
		sprite,
		_data.overworld_sprite_indices(number),
		_player_palette(),
		Gen2WorldSprite.FACING_DOWN,
		WALK_FRAMES[step],
	)


## `FastShipGFX`, eight tiles copied over `vTiles0 tile $10`: the standing four
## and the walking four the frameset alternates between, with no facing to pick.
func _fast_ship_image(step: int) -> Image:
	var frame: int = WALK_FRAMES[step]
	return _icon_from(
		"fast_ship", 4 if Gen2WorldSprite.is_walking_frame(frame) else 0, frame == 3
	)


## `PokedexNestIconGFX`, drawn with the same object palette every other icon on
## these screens takes.
func _nest_image() -> Image:
	var tiles: PackedByteArray = _data.tile_indices("dex_nest_icon") if _data != null \
		else PackedByteArray()
	var palette: PackedColorArray = _object_palette()
	var out := Image.create(NEST_ICON_SIZE, NEST_ICON_SIZE, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	if tiles.size() < Gen2TownMapPage.TILE * Gen2TownMapPage.TILE or palette.is_empty():
		return out
	var width: int = tiles.size() / Gen2TownMapPage.TILE
	for y: int in Gen2TownMapPage.TILE:
		for x: int in Gen2TownMapPage.TILE:
			var index: int = tiles[y * width + NEST_TILE * Gen2TownMapPage.TILE + x]
			if index == 0:
				continue
			out.set_pixel(x, y, palette[clampi(index, 0, palette.size() - 1)])
	return out


## `.nestloop`'s `sub 4` on both coordinates, which centres one tile on the
## landmark's own point rather than on the 16x16 icon's corner.
func _nest_position(landmark: int) -> Vector2i:
	var entry: Dictionary = _data.landmark(landmark)
	return Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))) \
		- Vector2i(NEST_ORIGIN, NEST_ORIGIN)


func _object_palette(slot: int = OBJECT_PALETTE) -> PackedColorArray:
	if _data == null:
		return PackedColorArray()
	return _data.overworld_sprite_palette(slot, _time_of_day)


## `PAL_OW_RED` everywhere but the dex area's player icon, which is the one
## object on these screens that asks `wPlayerGender`.
func _player_palette() -> PackedColorArray:
	if _female and _map != null and _map.screen == Gen2TownMap.SCREEN_DEX_AREA:
		return _object_palette(OBJECT_PALETTE_FEMALE)
	return _object_palette()


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
