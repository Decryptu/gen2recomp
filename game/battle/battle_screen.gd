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
## It draws what it is given and decides nothing. A [Gen2Battle] behind it works
## out the turn and answers with a list of events; this shows them one at a time,
## taking every number it draws out of the event rather than asking the engine
## again. That is why the setters still take plain values: the engine is one
## caller of them and not the only possible one.
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

## What both Pokémon know, until there are learnsets to ask. Tackle because
## every early Pokémon has it and because a Normal move against anything gives a
## plain hit to look at. This is scaffolding: a party's moves come from the
## learnset and trainer party tables, and neither is decoded yet.
const PLACEHOLDER_MOVES: Array = [33]

const TILE: int = Gen2Font.TILE

## The white the hardware fills the battle background with.
const BACKGROUND: Color = Color.WHITE

var _data: GameData = null
var _hud: Gen2BattleHud = null

## The battle behind the screen, and the two Pokémon in it. The display state
## below is what is currently drawn, which is not always where the battle has
## got to: a turn resolves at once and is then shown an event at a time.
var _battle: Gen2Battle = null
var _pending: Array = []
var _rng := RandomNumberGenerator.new()

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


## Puts two Pokémon on the screen at a level each, both at full health, and
## starts a battle between them.
func show_matchup(enemy: int, player: int, enemy_level: int = 5, player_level: int = 5) -> void:
	_enemy = _wrap_species(enemy)
	_player = _wrap_species(player)
	_enemy_level = enemy_level
	_player_level = player_level

	_pending = []
	_battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, _player, _player_level, PLACEHOLDER_MOVES),
		Gen2BattleMon.create(_data, _enemy, _enemy_level, PLACEHOLDER_MOVES),
		_rng
	)
	if _battle == null:
		return

	set_hp(
		_battle.enemy.hp, _battle.enemy.max_hp(),
		_battle.player.hp, _battle.player.max_hp()
	)


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
## that a bar and its numbers agree. It goes through the Pokémon rather than
## through the display, so the battle and the screen do not drift apart.
func hurt_enemy() -> void:
	_hurt(_battle.enemy if _battle != null else null)


func hurt_player() -> void:
	_hurt(_battle.player if _battle != null else null)


func _hurt(mon: Gen2BattleMon) -> void:
	if mon == null:
		return
	@warning_ignore("integer_division")
	mon.take_damage(maxi(mon.max_hp() / 4, 1))
	_read_hp()


## Plays one turn out: both sides use their first move, and the events come back
## to be shown one at a time.
func take_turn() -> void:
	if _battle == null or _battle.is_over() or not _pending.is_empty():
		return
	_pending = _battle.take_turn(0, 0)
	_show_next_event()


## What a button press does. Finishes the current message if it is still
## revealing, then moves on to the next event, and starts a turn when there is
## nothing left to say.
func advance() -> void:
	if _box == null:
		return
	if _box.advance():
		return
	if _pending.is_empty():
		take_turn()
		return
	_show_next_event()


## The next event, with whatever it changes applied first.
##
## Every number drawn comes out of the event rather than out of the Pokémon,
## because the turn has already finished resolving by the time the first event is
## shown. Reading the Pokémon here would draw the end of the turn during the
## middle of it.
func _show_next_event() -> void:
	while not _pending.is_empty():
		var event: Dictionary = _pending.pop_front()
		_apply_event(event)
		var text: String = _describe(event)
		if not text.is_empty():
			show_message(text)
			return


func _apply_event(event: Dictionary) -> void:
	match event["type"]:
		Gen2Battle.HIT, Gen2Battle.RECOIL:
			var target: int = int(event.get("target", event["side"]))
			if target == Gen2Battle.ENEMY:
				set_hp(int(event["hp"]), int(event["max_hp"]), _player_hp, _player_max_hp)
			else:
				set_hp(_enemy_hp, _enemy_max_hp, int(event["hp"]), int(event["max_hp"]))


## An event as a sentence, or an empty string for one there is nothing to say
## about. A neutral hit has no line of its own in these games: the bar moving is
## the whole of the message.
func _describe(event: Dictionary) -> String:
	var side: int = int(event["side"])
	match event["type"]:
		Gen2Battle.USED_MOVE:
			return "%s used %s!" % [
				_battler_name(side), String(_data.move(int(event["move"])).get("name", "")),
			]
		Gen2Battle.MISSED:
			return "%s's attack missed!" % _battler_name(side)
		Gen2Battle.NO_EFFECT:
			return "It doesn't affect %s!" % _battler_name(int(event["target"]))
		Gen2Battle.HIT:
			if bool(event["critical"]):
				return "A critical hit!"
			if int(event["effectiveness"]) > RomLayout.MATCHUP_EFFECTIVE:
				return "It's super effective!"
			if int(event["effectiveness"]) < RomLayout.MATCHUP_EFFECTIVE:
				return "It's not very effective..."
		Gen2Battle.RECOIL:
			return "%s is hit with recoil!" % _battler_name(side)
		Gen2Battle.FAINTED:
			return "%s fainted!" % _battler_name(side)
		Gen2Battle.OVER:
			return "%s won!" % ("The enemy" if event["winner"] == Gen2Battle.ENEMY else "Player")
	return ""


## How a battle refers to one of the two, which is by side and not by species:
## the enemy's name is prefixed and the player's is not.
func _battler_name(side: int) -> String:
	if side == Gen2Battle.ENEMY:
		return "Enemy %s" % _name_of(_enemy)
	return _name_of(_player)


## Re-reads both Pokémon. For the paths that change health outside a turn, where
## there is no event to read it out of.
func _read_hp() -> void:
	if _battle == null:
		return
	set_hp(
		_battle.enemy.hp, _battle.enemy.max_hp(),
		_battle.player.hp, _battle.player.max_hp()
	)


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
		KEY_A:
			take_turn()
		KEY_SPACE, KEY_ENTER:
			advance()
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
