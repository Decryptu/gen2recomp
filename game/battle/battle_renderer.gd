class_name Gen2BattleRenderer
extends Control

## Draws the battle field: two pics, two status panels, two HP bars, the exp bar
## and whatever a battle animation is putting over them. It does not own the
## battle; call [method set_battle_data] once, then [method set_view] whenever
## the screen has new display values to show.
##
## The pics are drawn through `wTilemap` rather than placed at a corner, because
## that map is what a battle animation edits: `BattleBGEffect_HideMon` blanks a
## battler's box, `..._RemoveMon` shifts it a column at a time and the pic-resize
## script stamps smaller arrangements of the same tiles over it. The screen owns
## the map and hands it in; a tile id is the hardware's, `$00` up for the enemy's
## front pic and `$31` up for the player's back pic.
##
## Panels compose into one screen-sized index buffer drawn over the pics with
## index 0 transparent: a panel is a shape on a white field, drawn into the
## background layer on hardware, so the pics show through everything that is not
## ink.
##
## Every background layer is part of one plane, so a scroll applies to all of
## them alike: the view hands over a per-scanline offset and each layer is
## scrolled through [Gen2Raster] by the same one. The animation's own objects are
## not part of that plane and do not scroll, the way OAM does not.

const TILE: int = Gen2Font.TILE

## Where each picture sits and which tile ids are its own: see
## [Gen2BattleScreenMap], which the screen builds the map with.
const COLUMNS: int = Gen2BattleScreenMap.COLUMNS
const ROWS: int = Gen2BattleScreenMap.ROWS

## The background map is 256 pixels each way against the screen's 160 by 144, so
## a scroll wraps and blank is what comes in.
const MAP_WIDTH: int = 256
const MAP_HEIGHT: int = 256

## `%11100100`, the DMG palette byte that maps every colour to itself.
const PALETTE_IDENTITY: int = 0xE4

## OAM attribute bits, as [Gen2BattleAnimObject] writes them.
const OAM_YFLIP: int = 1 << 6
const OAM_XFLIP: int = 1 << 5
const OAM_PALETTE: int = 0x07

## The white the hardware fills the battle background with.
const BACKGROUND: Color = Color.WHITE

var _data: GameData = null
var _hud: Gen2BattleHud = null
var _view: Dictionary = {}

var _enemy_pic: TextureRect = null
var _player_pic: TextureRect = null
var _panels: TextureRect = null
var _enemy_bar: TextureRect = null
var _player_bar: TextureRect = null
var _exp_bar: TextureRect = null
var _sprites: TextureRect = null

## One 56x56 and one 48x48 index buffer, the two pics padded out to their own
## boxes, rebuilt only when the species drawn changes.
var _enemy_pixels: PackedByteArray = PackedByteArray()
var _player_pixels: PackedByteArray = PackedByteArray()
var _enemy_pixels_species: int = -1
var _player_pixels_species: int = -1

## Everything a pic layer is built out of. A draining bar moves the panels while
## the map, the species, the palette and the scroll all stand still, so the same
## two pictures were being rebuilt into a screen-sized buffer and a fresh
## texture on every frame of it. The layer is kept until one of its own inputs
## changes.
var _enemy_pic_key: Array = []
var _player_pic_key: Array = []
## The same for the four layers above them, by name.
var _layer_keys: Dictionary = {}


## Whether [param id] has to be rebuilt, recording [param key] as what it will
## then be holding.
func _layer_changed(id: StringName, key: Array) -> bool:
	if _layer_keys.get(id, null) == key:
		return false
	_layer_keys[id] = key
	return true


## The per-scanline offsets every background layer is scrolled by, which belong
## to each of them as much as their own contents do.
func _raster_key() -> Array:
	return [
		PackedInt32Array(_view.get("raster_scy", [])),
		PackedInt32Array(_view.get("raster_scx", [])),
	]


## Reads what it draws with out of the cache and builds its layers. Answers
## false if the cache is missing something the HUD needs, mirroring
## [method Gen2BattleHud.from_data].
func set_battle_data(data: GameData) -> bool:
	_data = data
	_hud = Gen2BattleHud.from_data(data)
	if _hud == null:
		return false

	var field := ColorRect.new()
	field.color = BACKGROUND
	field.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	add_child(field)

	_enemy_pic = _new_layer()
	_player_pic = _new_layer()
	_panels = _new_layer()
	_enemy_bar = _new_layer()
	_player_bar = _new_layer()
	_exp_bar = _new_layer()
	_sprites = _new_layer()
	return true


## The display values a battle screen has settled on right now. Plain values,
## not the battle engine: what is drawn deliberately lags what has resolved,
## since a turn resolves at once and is then shown an event at a time.
func set_view(view: Dictionary) -> void:
	_view = view
	refresh()


func refresh() -> void:
	if _hud == null:
		return

	_draw_pics()
	_draw_panels()
	_draw_sprites()


## Both pics, each read out of the tilemap so an animation that blanked, shifted
## or resized one is what shows.
func _draw_pics() -> void:
	var map: PackedByteArray = _bg_map()
	_ensure_pixels()
	var raster: Array = _raster_key()

	var enemy: int = int(_view.get("enemy_species", 0))
	var enemy_palette: PackedColorArray = _battler_palette(
		enemy, Gen2BattleAnimBackground.PAL_BG_ENEMY
	)
	var enemy_key: Array = [map, enemy, enemy_palette, raster]
	if enemy_key != _enemy_pic_key:
		_enemy_pic_key = enemy_key
		_show_layer(
			_enemy_pic,
			_pic_layer(map, Gen2BattleScreenMap.ENEMY_BASE_TILE, Gen2BattleScreenMap.ENEMY_SIDE, _enemy_pixels),
			enemy_palette
		)
	# `InitBattleDisplay` places the player's back pic with `PlaceGraphic` only
	# after `BattleIntroSlidingPics` has returned, so it is not on the map to be
	# scrolled and is simply not there yet.
	if bool(_view.get("player_pic_visible", true)):
		var player: int = int(_view.get("player_species", 0))
		var player_palette: PackedColorArray = _battler_palette(
			player, Gen2BattleAnimBackground.PAL_BG_PLAYER
		)
		var player_key: Array = [map, player, player_palette, raster]
		if player_key != _player_pic_key:
			_player_pic_key = player_key
			_show_layer(
				_player_pic,
				_pic_layer(map, Gen2BattleScreenMap.PLAYER_BASE_TILE, Gen2BattleScreenMap.PLAYER_SIDE, _player_pixels),
				player_palette
			)
	else:
		_player_pic.texture = null
		_player_pic_key = []


## The tilemap the animation edits, or the plain one both pics sit in when the
## view carries none.
func _bg_map() -> PackedByteArray:
	var supplied: Variant = _view.get("bg_map", null)
	if supplied is PackedByteArray \
			and (supplied as PackedByteArray).size() == COLUMNS * ROWS:
		return supplied
	return Gen2BattleScreenMap.seeded()


## One screen-sized index buffer holding every cell of [param map] whose tile id
## falls inside this pic's own run, drawn from the pic's padded box. A tile is
## `base + column * side + row`, which is the column-major order `PlaceGraphic`
## walks and `.BGSquares` indexes.
func _pic_layer(
	map: PackedByteArray, base: int, side: int, pixels: PackedByteArray
) -> PackedByteArray:
	var out: PackedByteArray = _new_buffer()
	var box: int = side * TILE
	if pixels.size() < box * box:
		return out
	for row: int in ROWS:
		for column: int in COLUMNS:
			var tile: int = int(map[row * COLUMNS + column]) - base
			if tile < 0 or tile >= side * side:
				continue
			@warning_ignore("integer_division")
			var source_x: int = (tile / side) * TILE
			var source_y: int = (tile % side) * TILE
			for line: int in TILE:
				var from: int = (source_y + line) * box + source_x
				var to: int = (row * TILE + line) * Gen2Screen.WIDTH + column * TILE
				for x: int in TILE:
					out[to + x] = pixels[from + x]
	return out


## The two pics as index buffers padded out to their own boxes, so a tile id
## indexes a fixed grid whatever size the species' own pic is.
func _ensure_pixels() -> void:
	var enemy: int = int(_view.get("enemy_species", 0))
	if enemy != _enemy_pixels_species:
		_enemy_pixels = _padded_pic(_data.species_pic(enemy), Gen2BattleScreenMap.ENEMY_SIDE)
		_enemy_pixels_species = enemy
	var player: int = int(_view.get("player_species", 0))
	if player != _player_pixels_species:
		_player_pixels = _padded_pic(_data.species_pic(player, true), Gen2BattleScreenMap.PLAYER_SIDE)
		_player_pixels_species = player


func _padded_pic(pic: Dictionary, side: int) -> PackedByteArray:
	var box: int = side * TILE
	var out: PackedByteArray = PackedByteArray()
	out.resize(box * box)
	if pic.is_empty():
		return out

	var atlas: Dictionary = _data.atlas(String(pic["atlas"]))
	var indices: PackedByteArray = _data.atlas_indices(String(pic["atlas"]))
	var cell: int = int(atlas.get("cell", 0))
	var columns: int = int(atlas.get("columns", 0))
	var atlas_width: int = int(atlas.get("width", 0))
	var slot: int = int(pic.get("slot", -1))
	if cell <= 0 or columns <= 0 or atlas_width <= 0 or slot < 0:
		return out

	var width: int = mini(int(pic.get("width", cell)), mini(cell, box))
	var height: int = mini(int(pic.get("height", cell)), mini(cell, box))
	var left: int = (slot % columns) * cell
	@warning_ignore("integer_division")
	var top: int = (slot / columns) * cell
	for y: int in height:
		var from: int = (top + y) * atlas_width + left
		if from + width > indices.size():
			break
		for x: int in width:
			out[y * box + x] = indices[from + x]
	return out


## A battler pic's own palette, permuted by whatever DMG byte the animation's
## last `BattleAnimRequestPals` left on that palette slot.
func _battler_palette(species: int, slot: int) -> PackedColorArray:
	return _remap(_data.palette(species), _palette_map("bg_palette_maps", slot))


## `CopyPals`: colour [param index] of the result is colour
## [code](byte >> index * 2) & 3[/code] of the pristine palette, which is why a
## remap never compounds.
static func _remap(palette: PackedColorArray, dmg: int) -> PackedColorArray:
	if palette.size() < Gen2Palette.COLORS_PER_PIC or dmg == PALETTE_IDENTITY:
		return palette
	var out := PackedColorArray()
	for index: int in Gen2Palette.COLORS_PER_PIC:
		out.append(palette[(dmg >> (index * 2)) & 3])
	return out


func _palette_map(key: String, slot: int) -> int:
	var maps: Variant = _view.get(key, null)
	if not maps is PackedByteArray or slot < 0 or slot >= (maps as PackedByteArray).size():
		return PALETTE_IDENTITY
	return int((maps as PackedByteArray)[slot])


## The panels, and then each bar over them in its own colour.
##
## The hardware gives every background tile its own palette, so a green HP bar
## sits in a panel of black text without either being separate. Here that is one
## buffer per palette, which is why the bars are drawn apart from the panels.
##
## `BattleAnimClearHud` takes all four off the map for the length of a move
## animation and `BattleAnimRestoreHuds` puts them back, which is what
## `hud_visible` is.
func _draw_panels() -> void:
	if not bool(_view.get("hud_visible", true)):
		_panels.texture = null
		_enemy_bar.texture = null
		_player_bar.texture = null
		_exp_bar.texture = null
		_layer_keys.clear()
		return

	var raster: Array = _raster_key()
	var enemy_hp: int = int(_view.get("enemy_hp", 0))
	var enemy_max_hp: int = int(_view.get("enemy_max_hp", 0))
	var player_hp: int = int(_view.get("player_hp", 0))
	var player_max_hp: int = int(_view.get("player_max_hp", 0))
	var enemy_name: String = String(_view.get("enemy_name", ""))
	var enemy_level: int = int(_view.get("enemy_level", 0))
	var player_name: String = String(_view.get("player_name", ""))
	var player_level: int = int(_view.get("player_level", 0))
	var exp_pixels: int = int(_view.get("exp_pixels", 0))

	# The player's panel prints its own HP numbers, so it moves with the bar; the
	# enemy's does not, which is why both sit in one layer keyed on all of it.
	if _layer_changed(&"panels", [
		enemy_name, enemy_level, player_name, player_level, player_hp, player_max_hp, raster,
	]):
		var panels: PackedByteArray = _new_buffer()
		_hud.draw_enemy(panels, Gen2Screen.WIDTH, enemy_name, enemy_level)
		_hud.draw_player(
			panels, Gen2Screen.WIDTH, player_name, player_level, player_hp, player_max_hp
		)
		_show_layer(
			_panels, panels,
			Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
		)

	if _layer_changed(&"enemy_bar", [enemy_hp, enemy_max_hp, raster]):
		var enemy: PackedByteArray = _new_buffer()
		_hud.draw_hp_bar(enemy, Gen2Screen.WIDTH, Gen2BattleHud.ENEMY_BAR, enemy_hp, enemy_max_hp)
		_show_layer(_enemy_bar, enemy, _hp_palette(enemy_hp, enemy_max_hp))

	if _layer_changed(&"player_bar", [player_hp, player_max_hp, raster]):
		var player: PackedByteArray = _new_buffer()
		_hud.draw_hp_bar(
			player, Gen2Screen.WIDTH, Gen2BattleHud.PLAYER_BAR, player_hp, player_max_hp
		)
		_show_layer(_player_bar, player, _hp_palette(player_hp, player_max_hp))

	if _layer_changed(&"exp_bar", [exp_pixels, raster]):
		var gained: PackedByteArray = _new_buffer()
		_hud.draw_exp_bar(gained, Gen2Screen.WIDTH, exp_pixels)
		_show_layer(_exp_bar, gained, _data.bar_palette("exp"))


## `wShadowOAM` as the animation left it: up to forty sprites, each eight by
## eight, in the order they were written, so a later one draws over an earlier.
##
## Objects are not part of the background plane and take no scroll. Index 0 is
## transparent, which is what OAM's own colour 0 is.
func _draw_sprites() -> void:
	var sprites: Array = _view.get("anim_sprites", [])
	if sprites.is_empty():
		_sprites.texture = null
		return

	var image: Image = Image.create_empty(
		Gen2Screen.WIDTH, Gen2Screen.HEIGHT, false, Image.FORMAT_RGBA8
	)
	for entry: Variant in sprites:
		if entry is Dictionary:
			_blit_sprite(image, entry as Dictionary)
	_sprites.texture = ImageTexture.create_from_image(image)
	_sprites.size = image.get_size()
	_sprites.position = Vector2.ZERO


## One OAM entry. The stored y and x are the hardware's, which subtracts sixteen
## and eight, so a zero in either is off screen rather than at the corner.
func _blit_sprite(into: Image, sprite: Dictionary) -> void:
	var pixels: PackedByteArray = _sprite_tile(int(sprite.get("tile", 0)))
	if pixels.is_empty():
		return
	var attributes: int = int(sprite.get("attributes", 0))
	var palette: PackedColorArray = _remap(
		_object_palette(attributes & OAM_PALETTE),
		_palette_map("ob_palette_maps", attributes & OAM_PALETTE)
	)
	var lookup: Image = Gen2PicImage.from_indices(pixels, TILE, TILE, palette, true)
	if (attributes & OAM_XFLIP) != 0:
		lookup.flip_x()
	if (attributes & OAM_YFLIP) != 0:
		lookup.flip_y()

	var left: int = int(sprite.get("x", 0)) - 8
	var top: int = int(sprite.get("y", 0)) - 16
	var clip: Rect2i = Rect2i(0, 0, TILE, TILE)
	if left < 0:
		clip.position.x = -left
		clip.size.x += left
		left = 0
	if top < 0:
		clip.position.y = -top
		clip.size.y += top
		top = 0
	clip.size.x = mini(clip.size.x, Gen2Screen.WIDTH - left)
	clip.size.y = mini(clip.size.y, Gen2Screen.HEIGHT - top)
	if clip.size.x <= 0 or clip.size.y <= 0:
		return
	into.blend_rect(lookup, clip, Vector2i(left, top))


## The eight pixels by eight of one animation tile, found through the window
## [method Gen2BattleAnimPlayer.tiles] describes, counted from
## `BATTLEANIM_BASE_TILE`.
##
## A window tile is either an imported sheet's or one of the battle's own two
## pictures, which is what `anim_battlergfx_1row` and `..._2row` put there so an
## effect can move a battler as objects.
func _sprite_tile(tile: int) -> PackedByteArray:
	var window: Array = _view.get("anim_tiles", [])
	var at: int = tile - Gen2BattleAnimObject.BASE_TILE
	if at < 0 or at >= window.size() or not window[at] is Dictionary:
		return PackedByteArray()
	var entry: Dictionary = window[at]
	if entry.has("battler_tile"):
		return _battler_tile(int(entry["battler_tile"]))
	var strip: PackedByteArray = _data.battle_anim_gfx_indices(int(entry["gfx"]))
	var index: int = int(entry["tile"])
	var width: int = strip.size() / TILE if strip.size() > 0 else 0
	if width <= 0 or (index + 1) * TILE > width:
		return PackedByteArray()

	var out: PackedByteArray = PackedByteArray()
	out.resize(TILE * TILE)
	for row: int in TILE:
		var from: int = row * width + index * TILE
		for column: int in TILE:
			out[row * TILE + column] = strip[from + column]
	return out


## One tile of `vTiles2`, out of the same padded boxes the tilemap is drawn
## from, so a battler moved as objects is the picture that was on the field.
func _battler_tile(vram: int) -> PackedByteArray:
	var enemy: bool = vram < Gen2BattleScreenMap.PLAYER_BASE_TILE
	var side: int = Gen2BattleScreenMap.ENEMY_SIDE if enemy \
		else Gen2BattleScreenMap.PLAYER_SIDE
	var base: int = Gen2BattleScreenMap.ENEMY_BASE_TILE if enemy \
		else Gen2BattleScreenMap.PLAYER_BASE_TILE
	var pixels: PackedByteArray = _enemy_pixels if enemy else _player_pixels
	var index: int = vram - base
	var box: int = side * TILE
	if index < 0 or index >= side * side or pixels.size() < box * box:
		return PackedByteArray()

	@warning_ignore("integer_division")
	var left: int = (index / side) * TILE
	var top: int = (index % side) * TILE
	var out: PackedByteArray = PackedByteArray()
	out.resize(TILE * TILE)
	for row: int in TILE:
		var from: int = (top + row) * box + left
		for column: int in TILE:
			out[row * TILE + column] = pixels[from + column]
	return out


## `PAL_BATTLE_OB_*`. Slots 0 and 1 are the two battlers' own rather than
## `BattleObjectPals` rows, which is what `_CGB_BattleScreenLayout` fills them
## with.
func _object_palette(slot: int) -> PackedColorArray:
	return _data.battle_object_palette(
		slot,
		_battler_pair(int(_view.get("enemy_species", 0))),
		_battler_pair(int(_view.get("player_species", 0)))
	)


func _battler_pair(species: int) -> Array:
	var entry: Dictionary = _data.species(species)
	if entry.is_empty():
		return []
	var stored: Variant = (entry.get("palette", {}) as Dictionary).get("normal", [])
	return stored if stored is Array else []


func _new_layer() -> TextureRect:
	var out := TextureRect.new()
	# Nearest, or the integer-scaled viewport is undone on the last hop.
	out.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(out)
	return out


func _new_buffer() -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	return out


## Every layer above the pics is drawn with index 0 transparent: a panel is a
## shape on the background, not a rectangle over it.
func _show_layer(
	into: TextureRect, indices: PackedByteArray, palette: PackedColorArray
) -> void:
	_show_image(into, Gen2PicImage.from_indices(
		indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT, palette, true
	))


## One background layer, scrolled by whatever the view is asking for. An empty
## or absent offset list is a background sitting still, which is every frame
## outside the intro and outside an animation that opened a scanline window.
func _show_image(into: TextureRect, image: Image) -> void:
	var rows: PackedInt32Array = PackedInt32Array(_view.get("raster_scy", []))
	if not rows.is_empty():
		image = Gen2Raster.scroll_rows(image, rows, MAP_HEIGHT)
	var offsets: PackedInt32Array = PackedInt32Array(_view.get("raster_scx", []))
	if not offsets.is_empty():
		image = Gen2Raster.scroll(image, offsets, MAP_WIDTH)
	into.texture = ImageTexture.create_from_image(image)
	into.size = image.get_size()
	into.position = Vector2.ZERO


## An HP bar is green, yellow or red by how much of it is lit rather than by the
## hit points behind it, which is the rule the games use.
func _hp_palette(hp: int, max_hp: int) -> PackedColorArray:
	var lit: int = Gen2BattleHud.bar_pixels(
		hp, max_hp, Gen2BattleHud.HP_BAR_TILES * Gen2BattleHud.TILE
	)
	return _data.bar_palette(GameData.hp_bar_palette_name(lit))
