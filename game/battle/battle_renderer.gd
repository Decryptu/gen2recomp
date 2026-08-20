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
## `BattleStart_TrainerHuds`' party balls, which are OAM rather than background
## and so take no scroll.
var _hud_balls: TextureRect = null
var _sprites: TextureRect = null

## `SPRITE_MONSTER` (constants/sprite_constants.asm), the same number in both
## pins. `GetSubstitutePic` builds the doll out of `MonsterSpriteGFX`, which is
## that overworld sprite's own strip, so the battle draws a walking sprite.
const SUBSTITUTE_SPRITE: int = 0x4C

## Where `GetSubstitutePic` copies the four tiles: the enemy takes the sprite's
## down-facing frame at columns 2 and 3, rows 5 and 6 of its 7x7 box, the player
## the up-facing one a row higher in a 6x6 box. A tile index into either box is
## `column * side + row`, which is what `sScratch + (2 * 7 + 5) tiles` says.
const SUBSTITUTE_AT: Dictionary = {false: Vector2i(2, 5), true: Vector2i(2, 4)}
const SUBSTITUTE_FIRST_TILE: Dictionary = {false: 0, true: 4}

## One 56x56 and one 48x48 index buffer, the two pics padded out to their own
## boxes, rebuilt only when the picture drawn changes.
var _enemy_pixels: PackedByteArray = PackedByteArray()
var _player_pixels: PackedByteArray = PackedByteArray()
var _enemy_pixels_key: Array = []
var _player_pixels_key: Array = []

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
	_hud_balls = _new_layer()
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
	# A packed array is passed by reference, so a key holding the screen's own
	# map is a key that changes with it: every animation that edits nothing but
	# the tilemap, which is most of them, would compare equal to what is on
	# screen and never be redrawn.
	var map_key: PackedByteArray = map.duplicate()

	var enemy: int = int(_view.get("enemy_species", 0))
	var enemy_palette: PackedColorArray = _battler_palette(
		enemy, Gen2BattleAnimBackground.PAL_BG_ENEMY
	)
	# `GetFrontpicPalettePointer` reads `wTrainerClass` rather than a species
	# when the square is holding a trainer, which it is until that trainer has
	# sent something out.
	var enemy_trainer: int = int(_view.get("enemy_trainer_pic", 0))
	if enemy_trainer > 0:
		enemy_palette = _remap(
			_data.trainer_palette(enemy_trainer),
			_palette_map("bg_palette_maps", Gen2BattleAnimBackground.PAL_BG_ENEMY)
		)
	var enemy_key: Array = [map_key, enemy, _enemy_pixels_key, enemy_palette, raster]
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
		# `GetPlayerOrMonPalettePointer`'s `and a / jp nz`: a zero species is the
		# player standing there, and the palette is the player's own.
		var backpic: String = String(_view.get("player_backpic", ""))
		if not backpic.is_empty():
			player_palette = _remap(
				_data.player_palette(String(_view.get("player_backpic_palette", "chris"))),
				_palette_map("bg_palette_maps", Gen2BattleAnimBackground.PAL_BG_PLAYER)
			)
		var player_key: Array = [map_key, player, _player_pixels_key, player_palette, raster]
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
## indexes a fixed grid whatever size the species' own pic is. A side whose doll
## is up is holding the substitute's picture instead, which is the same box with
## a different four tiles in it.
func _ensure_pixels() -> void:
	var enemy_key: Array = [
		int(_view.get("enemy_species", 0)), bool(_view.get("enemy_substitute", false)),
		int(_view.get("enemy_unown_form", 0)), int(_view.get("enemy_trainer_pic", 0)),
	]
	if enemy_key != _enemy_pixels_key:
		if int(enemy_key[3]) > 0:
			_enemy_pixels = padded_pic(_data,
				_data.trainer_pic(int(enemy_key[3])), Gen2BattleScreenMap.ENEMY_SIDE
			)
		elif bool(enemy_key[1]):
			_enemy_pixels = _substitute_pic(false)
		else:
			_enemy_pixels = padded_pic(_data,
				_battler_pic(int(enemy_key[0]), int(enemy_key[2]), false),
				Gen2BattleScreenMap.ENEMY_SIDE, true
			)
		_enemy_pixels_key = enemy_key
	var player_key: Array = [
		int(_view.get("player_species", 0)), bool(_view.get("player_substitute", false)),
		int(_view.get("player_unown_form", 0)), String(_view.get("player_backpic", "")),
	]
	if player_key != _player_pixels_key:
		if not String(player_key[3]).is_empty():
			_player_pixels = padded_pic(_data,
				_data.player_backpic(String(player_key[3])),
				Gen2BattleScreenMap.PLAYER_SIDE
			)
		elif bool(player_key[1]):
			_player_pixels = _substitute_pic(true)
		else:
			_player_pixels = padded_pic(_data,
				_battler_pic(int(player_key[0]), int(player_key[2]), true),
				Gen2BattleScreenMap.PLAYER_SIDE
			)
		_player_pixels_key = player_key


## `_GetFrontpic`'s own branch: Unown is drawn out of `UnownPicPointers` by
## letter, and everything else out of the species table. The atlas is indexed
## from zero and a letter counts from one, which is the subtraction here.
func _battler_pic(species: int, unown_form: int, back: bool) -> Dictionary:
	if species == RomLayout.UNOWN_SPECIES and unown_form > 0:
		return _data.unown_pic(unown_form - 1, back)
	return _data.species_pic(species, back)


func _substitute_pic(player_side: bool) -> PackedByteArray:
	return substitute_pixels(_data.overworld_sprite_indices(SUBSTITUTE_SPRITE), player_side)


## `GetSubstitutePic`: a blank box with four tiles of [param strip], the monster
## overworld sprite, copied into it. The doll wears whichever battler palette its
## box sits in, since nothing writes one for it.
##
## Static because it is the whole of the picture and takes no screen: a check
## sweeping three caches builds it the same way the renderer does.
static func substitute_pixels(strip: PackedByteArray, player_side: bool) -> PackedByteArray:
	var side: int = Gen2BattleScreenMap.PLAYER_SIDE if player_side \
		else Gen2BattleScreenMap.ENEMY_SIDE
	var box: int = side * TILE
	var out: PackedByteArray = PackedByteArray()
	out.resize(box * box)

	var first: int = int(SUBSTITUTE_FIRST_TILE[player_side])
	# The strip is one tile row high, so its length is its width in pixels.
	@warning_ignore("integer_division")
	var width: int = strip.size() / TILE
	if width < (first + 4) * TILE:
		return out

	var at: Vector2i = SUBSTITUTE_AT[player_side]
	for tile: int in 4:
		var left: int = (at.x + (tile & 1)) * TILE
		var top: int = (at.y + (tile >> 1)) * TILE
		var from_x: int = (first + tile) * TILE
		for row: int in TILE:
			var from: int = row * width + from_x
			var to: int = (top + row) * box + left
			for column: int in TILE:
				out[to + column] = strip[from + column]
	return out


## [param front] is whether `PadFrontpic` runs over this one: a back pic fills
## its own box and a trainer's is already the whole 7x7, so neither is padded.
## Static because the placement is the whole of the picture and takes no screen:
## a check sweeping three caches builds the box the way the renderer does.
static func padded_pic(
	data: GameData, pic: Dictionary, side: int, front: bool = false
) -> PackedByteArray:
	var box: int = side * TILE
	var out: PackedByteArray = PackedByteArray()
	out.resize(box * box)
	if pic.is_empty():
		return out

	var atlas_name: String = String(pic.get("atlas", ""))
	var cell: Dictionary = Gen2PicImage.atlas_cell(
		data.atlas_indices(atlas_name), data.atlas(atlas_name), pic
	)
	if cell.is_empty():
		return out

	var indices: PackedByteArray = cell["indices"]
	var width: int = mini(int(cell["width"]), box)
	var height: int = mini(int(cell["height"]), box)
	var stride: int = int(cell["width"])
	## `PadFrontpic` does not centre a pic smaller than the 7x7 block: it lays one
	## blank tile column in front of it and blank tiles above each column, so the
	## pic is bottom-aligned one column in. The tile numbers `PlaceGraphic` writes
	## count over the padded block, so a pic left at the corner here is drawn a
	## column left and a row or two high of where the cartridge draws it.
	var pad_x: int = 0
	var pad_y: int = 0
	if front:
		@warning_ignore("integer_division")
		pad_x = Gen2PicImage.frontpic_pad_columns(width / TILE) * TILE
		@warning_ignore("integer_division")
		pad_y = Gen2PicImage.frontpic_pad_rows(height / TILE) * TILE
	for y: int in mini(height, box - pad_y):
		for x: int in mini(width, box - pad_x):
			out[(y + pad_y) * box + x + pad_x] = indices[y * stride + x]
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
## `BattleAnimClearHud` takes one side off the map for the length of a move
## animation and `BattleAnimRestoreHuds` puts it back; a battle opening has
## neither of them up for several seconds. Both are the two per-side keys, and
## the view's own `hud_visible` is the summary of them.
func _draw_panels() -> void:
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
	# Each panel goes up when its own side has something on the field.
	# `InitBattleDisplay` clears the player's box, and its caller only reaches
	# `UpdateEnemyHUD` for a wild battle, so an opening battle spends several
	# seconds with neither of them drawn.
	var enemy_hud: bool = bool(_view.get("enemy_hud_visible", true))
	var player_hud: bool = bool(_view.get("player_hud_visible", true))
	var border: Array = _view.get("trainer_hud_border", []) as Array

	# The player's panel prints its own HP numbers, so it moves with the bar; the
	# enemy's does not, which is why both sit in one layer keyed on all of it.
	if _layer_changed(&"panels", [
		enemy_name, enemy_level, player_name, player_level, player_hp, player_max_hp,
		enemy_hud, player_hud, border, raster,
	]):
		var panels: PackedByteArray = _new_buffer()
		if enemy_hud:
			_hud.draw_enemy(panels, Gen2Screen.WIDTH, enemy_name, enemy_level)
		if player_hud:
			_hud.draw_player(
				panels, Gen2Screen.WIDTH, player_name, player_level, player_hp, player_max_hp
			)
		_draw_trainer_hud_border(panels, border)
		_show_layer(
			_panels, panels,
			Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
		)

	if _layer_changed(&"enemy_bar", [enemy_hp, enemy_max_hp, enemy_hud, raster]):
		var enemy: PackedByteArray = _new_buffer()
		if enemy_hud:
			_hud.draw_hp_bar(
				enemy, Gen2Screen.WIDTH, Gen2BattleHud.ENEMY_BAR, enemy_hp, enemy_max_hp
			)
		_show_layer(_enemy_bar, enemy, _hp_palette(enemy_hp, enemy_max_hp))

	if _layer_changed(&"player_bar", [player_hp, player_max_hp, player_hud, raster]):
		var player: PackedByteArray = _new_buffer()
		if player_hud:
			_hud.draw_hp_bar(
				player, Gen2Screen.WIDTH, Gen2BattleHud.PLAYER_BAR, player_hp, player_max_hp
			)
		_show_layer(_player_bar, player, _hp_palette(player_hp, player_max_hp))

	if _layer_changed(&"exp_bar", [exp_pixels, player_hud, raster]):
		var gained: PackedByteArray = _new_buffer()
		if player_hud:
			_hud.draw_exp_bar(gained, Gen2Screen.WIDTH, exp_pixels)
		_show_layer(_exp_bar, gained, _data.bar_palette("exp"))

	_draw_hud_balls()


## `DrawPlayerPartyIconHUDBorder` and `DrawEnemyHUDBorder`: the frame the party
## balls hang in, a side, two corners and eight of a bottom edge out of the
## battle's own tile page. Cells rather than pixels, the way the source writes
## them into `wTilemap`.
func _draw_trainer_hud_border(into: PackedByteArray, border: Array) -> void:
	for entry: Variant in border:
		if not entry is Dictionary:
			continue
		var cell: Dictionary = entry as Dictionary
		_hud.tiles.draw(
			int(cell.get("tile", 0)), into, Gen2Screen.WIDTH,
			int(cell.get("x", 0)) * TILE, int(cell.get("y", 0)) * TILE
		)


## `LoadTrainerHudOAM`: six sprites a side, one of `LoadBallIconGFX`'s four tiles
## each, all on `PAL_BATTLE_OB_YELLOW`. Objects, so they take no scroll, and they
## are what `ClearSprites` takes away when the opening line is pressed past.
func _draw_hud_balls() -> void:
	var balls: Array = _view.get("trainer_hud_balls", []) as Array
	if balls.is_empty():
		_hud_balls.texture = null
		_layer_keys.erase(&"hud_balls")
		return
	if not _layer_changed(&"hud_balls", [balls]):
		return
	var sheet: PackedByteArray = _data.tile_indices("ball_icons")
	var width: int = int(_data.tile_sheet("ball_icons").get("width", 0))
	var buffer: PackedByteArray = _new_buffer()
	for entry: Variant in balls:
		if not entry is Dictionary or width <= 0:
			continue
		var ball: Dictionary = entry as Dictionary
		var tile: int = int(ball.get("tile", 0))
		var left: int = int(ball.get("x", 0))
		var top: int = int(ball.get("y", 0))
		for row: int in TILE:
			if top + row < 0 or top + row >= Gen2Screen.HEIGHT:
				continue
			var from: int = row * width + tile * TILE
			var to: int = (top + row) * Gen2Screen.WIDTH + left
			for column: int in TILE:
				var x: int = left + column
				if x < 0 or x >= Gen2Screen.WIDTH or from + column >= sheet.size():
					continue
				buffer[to + column] = sheet[from + column]
	# Not through `_show_image`: an object is not part of the background plane
	# and does not take the scroll the background layers do.
	var image: Image = Gen2PicImage.from_indices(
		buffer, Gen2Screen.WIDTH, Gen2Screen.HEIGHT,
		_object_palette(Gen2BattleAnimBackground.PAL_OB_YELLOW), true
	)
	_hud_balls.texture = ImageTexture.create_from_image(image)
	_hud_balls.size = image.get_size()
	_hud_balls.position = Vector2.ZERO


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
