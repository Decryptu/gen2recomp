class_name Gen2BattleScreen
extends Control

## The battle screen: two Pokémon, two status panels and a text box, at the
## positions the hardware puts them.
##
## This is the first screen that is not a development view. Everything on it
## already existed a layer down (a pic from an atlas, a panel from the HUD
## sheets, a box from the font and a border), and what this adds is where each
## of them goes: the enemy's pic in the top right, the player's back pic below
## and to the left of it, a panel each, and the standard box along the bottom.
##
## It draws what it is given and decides nothing. There is no battle here: no
## turn order, no damage, no faint. When there is an engine, it will hand this
## the same numbers a caller hands it now, which is why the setters take plain
## values rather than a battle state object.
##
## The panels are composed into one screen-sized index buffer and drawn over the
## pics with index 0 transparent, because a panel is a shape on a white field
## rather than a rectangle: the games draw them into the background layer, where
## nothing overlaps, and the pics have to show through everything that is not ink.

## Where the two pics sit, in tiles.
const ENEMY_PIC: Vector2i = Vector2i(12, 0)
const PLAYER_PIC: Vector2i = Vector2i(2, 6)

## What is on screen before a caller says otherwise: the first battle a player
## of Gold or Silver is likely to have.
const DEFAULT_ENEMY: int = 16
const DEFAULT_PLAYER: int = 155
const DEFAULT_LEVEL: int = 5

const TILE: int = Gen2Font.TILE

## The white the hardware fills the battle background with.
const BACKGROUND: Color = Color.WHITE

var _data: GameData = null
var _hud: Gen2BattleHud = null

var _enemy: int = 1
var _player: int = 1
var _enemy_level: int = 5
var _player_level: int = 5
var _enemy_hp: int = 0
var _enemy_max_hp: int = 0
var _player_hp: int = 0
var _player_max_hp: int = 0
var _exp: float = 0.0

var _enemy_pic: TextureRect = null
var _player_pic: TextureRect = null
var _panels: TextureRect = null
var _enemy_bar: TextureRect = null
var _player_bar: TextureRect = null
var _exp_bar: TextureRect = null
var _box: Gen2TextBox = null

@onready var _screen: Gen2Screen = %Screen


func _ready() -> void:
	_data = GameData.open_any()
	_hud = Gen2BattleHud.from_data(_data)
	if _hud == null:
		return

	var field := ColorRect.new()
	field.color = BACKGROUND
	field.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_screen.display(field)

	_enemy_pic = _new_layer()
	_player_pic = _new_layer()
	_panels = _new_layer()
	_enemy_bar = _new_layer()
	_player_bar = _new_layer()
	_exp_bar = _new_layer()

	_box = Gen2TextBox.new()
	_box.font = _hud.font
	_screen.display(_box)
	_box.place_at_bottom()

	show_matchup(DEFAULT_ENEMY, DEFAULT_PLAYER, DEFAULT_LEVEL, DEFAULT_LEVEL)
	set_exp(0.5)
	_announce()


## True once the cache had everything the screen draws with.
func is_ready() -> bool:
	return _hud != null


## Puts two Pokémon on the screen at a level each, both at full health.
func show_matchup(enemy: int, player: int, enemy_level: int = 5, player_level: int = 5) -> void:
	_enemy = _wrap_species(enemy)
	_player = _wrap_species(player)
	_enemy_level = enemy_level
	_player_level = player_level
	_enemy_max_hp = _hp_at_level(_enemy, _enemy_level)
	_player_max_hp = _hp_at_level(_player, _player_level)
	_enemy_hp = _enemy_max_hp
	_player_hp = _player_max_hp
	_refresh()


## Both HP totals, for a caller that has its own numbers.
func set_hp(enemy: int, enemy_max: int, player: int, player_max: int) -> void:
	_enemy_hp = enemy
	_enemy_max_hp = enemy_max
	_player_hp = player
	_player_max_hp = player_max
	_refresh()


## How full the exp bar is, from nothing to a level's worth.
func set_exp(fraction: float) -> void:
	_exp = clampf(fraction, 0.0, 1.0)
	_refresh()


func show_message(text: String) -> void:
	if _box != null:
		_box.show_text(text)


## Reveals the rest of the message at once, so a photograph of the screen does
## not depend on how long the capture took to arrive.
func finish() -> void:
	if _box != null:
		_box.finish()


func next_enemy() -> void:
	show_matchup(_enemy + 1, _player, _enemy_level, _player_level)
	_announce()


func next_player() -> void:
	show_matchup(_enemy, _player + 1, _enemy_level, _player_level)
	_announce()


## Takes a quarter of the enemy's health off, which is the fastest way to see
## that a bar and its numbers agree.
func hurt_enemy() -> void:
	_enemy_hp = maxi(_enemy_hp - maxi(_enemy_max_hp / 4, 1), 0)
	_refresh()


func hurt_player() -> void:
	_player_hp = maxi(_player_hp - maxi(_player_max_hp / 4, 1), 0)
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if _hud == null or not event.is_pressed():
		return

	var key: InputEventKey = event as InputEventKey
	if key == null:
		return

	match key.keycode:
		KEY_RIGHT:
			next_enemy()
		KEY_LEFT:
			next_player()
		KEY_D:
			hurt_enemy()
		KEY_S:
			hurt_player()
		KEY_SPACE, KEY_ENTER:
			_box.advance()
		_:
			return
	accept_event()


func _new_layer() -> TextureRect:
	var out := TextureRect.new()
	# Nearest, or the integer-scaled viewport is undone on the last hop.
	out.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_screen.display(out)
	return out


func _wrap_species(number: int) -> int:
	var count: int = _data.species_count() if _data != null else 0
	return wrapi(number, 1, maxi(count, 1) + 1) if count > 0 else 1


## A rough HP total, so the bar and the numbers have something to show. The real
## formula belongs to the engine that does not exist yet, along with the IVs and
## the effort values it also reads.
func _hp_at_level(species: int, level: int) -> int:
	var entry: Dictionary = _data.species(species)
	if entry.is_empty():
		return 1
	var base: int = int(entry["stats"]["hp"])
	@warning_ignore("integer_division")
	return (base * 2 * level) / 100 + level + 10


func _refresh() -> void:
	if _hud == null:
		return

	_draw_pic(_enemy_pic, _data.species_pic(_enemy), _data.palette(_enemy), ENEMY_PIC)
	_draw_pic(_player_pic, _data.species_pic(_player, true), _data.palette(_player), PLAYER_PIC)
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
## The hardware gives every tile of the background its own palette, so a green
## HP bar sits in a panel of black text without either being a separate thing.
## Layering is how that is done here, one buffer per palette, which is why the
## bars are drawn apart from the panels that hold them.
func _draw_panels() -> void:
	var panels: PackedByteArray = _new_buffer()
	_hud.draw_enemy(panels, Gen2Screen.WIDTH, _name_of(_enemy), _enemy_level)
	_hud.draw_player(
		panels, Gen2Screen.WIDTH, _name_of(_player), _player_level, _player_hp, _player_max_hp
	)
	_show_layer(
		_panels, panels,
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	)

	var enemy: PackedByteArray = _new_buffer()
	_hud.draw_hp_bar(
		enemy, Gen2Screen.WIDTH, Gen2BattleHud.ENEMY_BAR, _enemy_hp, _enemy_max_hp
	)
	_show_layer(_enemy_bar, enemy, _hp_palette(_enemy_hp, _enemy_max_hp))

	var player: PackedByteArray = _new_buffer()
	_hud.draw_hp_bar(
		player, Gen2Screen.WIDTH, Gen2BattleHud.PLAYER_BAR, _player_hp, _player_max_hp
	)
	_show_layer(_player_bar, player, _hp_palette(_player_hp, _player_max_hp))

	var gained: PackedByteArray = _new_buffer()
	_hud.draw_exp_bar(gained, Gen2Screen.WIDTH, _exp)
	_show_layer(_exp_bar, gained, _data.bar_palette("exp"))


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


func _name_of(species: int) -> String:
	return String(_data.species(species).get("name", ""))


func _announce() -> void:
	show_message("Wild %s appeared!" % _name_of(_enemy))
