class_name Gen2BattleRenderer
extends Control

## Draws the battle field: two pics, two status panels, two HP bars and the exp
## bar, at the positions the hardware puts them. It does not own the battle;
## call [method set_battle_data] once, then [method set_view] whenever the
## screen has new display values to show.
##
## Panels compose into one screen-sized index buffer drawn over the pics with
## index 0 transparent: a panel is a shape on a white field, drawn into the
## background layer on hardware, so the pics show through everything that is not
## ink.

## Where the two pics sit, in tiles.
const ENEMY_PIC: Vector2i = Vector2i(12, 0)
const PLAYER_PIC: Vector2i = Vector2i(2, 6)

const TILE: int = Gen2Font.TILE

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

	_draw_pic(
		_enemy_pic, _data.species_pic(int(_view.get("enemy_species", 0))),
		_data.palette(int(_view.get("enemy_species", 0))), ENEMY_PIC
	)
	_draw_pic(
		_player_pic, _data.species_pic(int(_view.get("player_species", 0)), true),
		_data.palette(int(_view.get("player_species", 0))), PLAYER_PIC
	)
	_draw_panels()


func _draw_pic(
	into: TextureRect, pic: Dictionary, palette: PackedColorArray, at: Vector2i
) -> void:
	if into == null or pic.is_empty():
		return

	var image: Image = Gen2PicImage.from_atlas(
		_data.atlas_indices(pic["atlas"]), _data.atlas(pic["atlas"]), pic, palette
	)
	into.texture = ImageTexture.create_from_image(image)
	into.size = image.get_size()
	into.position = Vector2(at.x * TILE, at.y * TILE)


## The panels, and then each bar over them in its own colour.
##
## The hardware gives every background tile its own palette, so a green HP bar
## sits in a panel of black text without either being separate. Here that is one
## buffer per palette, which is why the bars are drawn apart from the panels.
func _draw_panels() -> void:
	var enemy_hp: int = int(_view.get("enemy_hp", 0))
	var enemy_max_hp: int = int(_view.get("enemy_max_hp", 0))
	var player_hp: int = int(_view.get("player_hp", 0))
	var player_max_hp: int = int(_view.get("player_max_hp", 0))

	var panels: PackedByteArray = _new_buffer()
	_hud.draw_enemy(
		panels, Gen2Screen.WIDTH, String(_view.get("enemy_name", "")),
		int(_view.get("enemy_level", 0))
	)
	_hud.draw_player(
		panels, Gen2Screen.WIDTH, String(_view.get("player_name", "")),
		int(_view.get("player_level", 0)), player_hp, player_max_hp
	)
	_show_layer(
		_panels, panels,
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	)

	var enemy: PackedByteArray = _new_buffer()
	_hud.draw_hp_bar(enemy, Gen2Screen.WIDTH, Gen2BattleHud.ENEMY_BAR, enemy_hp, enemy_max_hp)
	_show_layer(_enemy_bar, enemy, _hp_palette(enemy_hp, enemy_max_hp))

	var player: PackedByteArray = _new_buffer()
	_hud.draw_hp_bar(player, Gen2Screen.WIDTH, Gen2BattleHud.PLAYER_BAR, player_hp, player_max_hp)
	_show_layer(_player_bar, player, _hp_palette(player_hp, player_max_hp))

	var gained: PackedByteArray = _new_buffer()
	_hud.draw_exp_bar(gained, Gen2Screen.WIDTH, int(_view.get("exp_pixels", 0)))
	_show_layer(_exp_bar, gained, _data.bar_palette("exp"))


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
	var image: Image = Gen2PicImage.from_indices(
		indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT, palette, true
	)
	into.texture = ImageTexture.create_from_image(image)
	into.size = image.get_size()


## An HP bar is green, yellow or red by how much of it is lit rather than by the
## hit points behind it, which is the rule the games use.
func _hp_palette(hp: int, max_hp: int) -> PackedColorArray:
	var lit: int = Gen2BattleHud.bar_pixels(
		hp, max_hp, Gen2BattleHud.HP_BAR_TILES * Gen2BattleHud.TILE
	)
	return _data.bar_palette(GameData.hp_bar_palette_name(lit))
