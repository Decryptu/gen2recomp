class_name Gen2PokegearScreen
extends Control

## The Pokegear's clock, phone and radio cards, embedded the way the MAP card is.
##
## [Gen2TownMapPage] draws all four; this composes one of the three over a
## [Gen2Screen] and puts the two objects `InitPokegearTilemap` spawns on top: the
## mode indicator arrow under the card icons, and the radio card's tuning knob.
## The MAP card is [Gen2TownMapScreen], which owns the region map's own cursor,
## player icon and landmark walk and is also the dex area and the fly map.
##
## Nothing here decides anything: the world owns the clock, the dial and the
## contact list, so a press is reported and the host reopens the card with what
## the world then says.

signal closed()
## Left or right, which is `Pokegear_SwitchPage` and is the host's to resolve:
## the card offered depends on which cards the player owns.
signal switched(direction: int)
## A press on the radio card's dial, as the knob value `.TuningKnob` would leave.
signal tuned(knob: int)
## The phone submenu's CALL row: the contact under the cursor, as its own index.
signal called(contact: int)
## Its DELETE row, once the yes/no box has been answered.
signal deleted(contact: int)

const SCREEN_SCENE: PackedScene = preload("res://game/render/gen2_screen.tscn")

const CARD_CLOCK: StringName = &"clock"
const CARD_PHONE: StringName = &"phone"
const CARD_RADIO: StringName = &"radio"

## `InitPokegearModeIndicatorArrow`'s `depixel 4, 2, 4, 0`, less the hardware's
## own OAM offsets and `.OAMData_RedWalk`'s `dbsprite -1, -1`, plus the card's
## own entry in `AnimatePokegearModeIndicatorArrow.XCoords`. The clock's is zero,
## which puts the arrow under the Pokegear's own icon rather than a card's.
const ARROW_TILE: int = 0x00
const ARROW_AT: Vector2i = Vector2i(0, 12)
const ARROW_CARD_STRIDE: int = 0x10
const ARROW_CARDS: Array[StringName] = [CARD_CLOCK, &"map", CARD_PHONE, CARD_RADIO]

## `PokegearRadio_Init`'s `depixel 4, 10, 4, 4` with `SPRITEANIMSTRUCT_TILE_ID`
## $08, read the same way: three tiles stacked, sliding right with
## `wRadioTuningKnob`, so the middle one rides the dial's own scale row.
const KNOB_TILE: int = 0x08
const KNOB_AT: Vector2i = Vector2i(72, 8)
const KNOB_TILES: int = 3

## `wPhoneList`, which the display list scrolls a row at a time.
const PHONE_LIST_SIZE: int = 10
const PHONE_DISPLAY_HEIGHT: int = Gen2TownMapPage.PHONE_DISPLAY_HEIGHT

## `PokegearPhoneContactSubmenu`'s two lists, and the contacts
## `CheckCanDeletePhoneNumber` refuses to offer the second of: the two
## non-trainers whose numbers the story needs.
const SUBMENU_CALL: String = "CALL"
const SUBMENU_DELETE: String = "DELETE"
const SUBMENU_CANCEL: String = "CANCEL"
const UNDELETABLE_CONTACTS: Array[int] = [1, 4]

var _data: GameData = null
var _page: Gen2TownMapPage = null
var _card: StringName = CARD_CLOCK
var _owned: Array = []
var _time_of_day: int = Gen2WorldPalette.TIME_MORNING
var _open: bool = false

## The clock card's reading, the radio card's dial and the box text, all as the
## host last gave them.
var _weekday: int = 0
var _hour: int = 0
var _minute: int = 0
var _knob: int = 0
var _station: String = ""
var _show_lines: PackedStringArray = PackedStringArray()
var _text: String = ""
## `PokegearAskDeleteText`, which replaces the card's question while the yes/no
## box is up.
var _delete_text: String = ""
## The phone card's own list: every contact, the window's first row and the
## cursor inside that window.
var _contacts: Array = []
var _scroll: int = 0
var _cursor: int = 0
var _service: bool = true
## `PokegearPhoneContactSubmenu` while it is up, and the yes/no box DELETE opens
## over it. Both are drawn on the card rather than on a layer of their own, the
## way `Textbox` writes into the same tilemap.
var _submenu: Array = []
var _submenu_cursor: int = 0
var _asking_delete: bool = false
var _yes_no_cursor: int = 0

var _field: Control = null
var _background: TextureRect = null
var _arrow: TextureRect = null
var _knob_icon: TextureRect = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if _page != null:
		_refresh()


## Opens one of the three cards. [param owned] is `wPokegearFlags` as the card
## names `Pokegear_FinishTilemap` tests, [param text] whichever of the Pokegear's
## own texts the card prints: the question it opens with and, on the phone card,
## `PokegearAskDeleteText`.
##
## Optional the way the region map is: a cache with no card tilemaps answers
## false and the caller keeps its own screen open.
func open(
	data: GameData,
	card_id: StringName,
	owned: Array,
	text: String = "",
	delete_text: String = "",
	time_of_day: int = Gen2WorldPalette.TIME_MORNING,
) -> bool:
	_data = data
	_page = Gen2TownMapPage.from_data(_data) if _data != null else null
	if _page == null or not _page.ready() or not _page.cards_ready():
		visible = false
		return false
	_card = card_id
	_owned = owned.duplicate()
	_text = text
	_delete_text = delete_text
	_time_of_day = time_of_day
	## `PokegearPhone_Init`'s three zeroes.
	_scroll = 0
	_cursor = 0
	_close_submenu()
	_open = true
	visible = true
	if is_inside_tree() and _background != null:
		_refresh()
	return true


## `Pokegear_UpdateClock`'s three readings, which the card_id redraws every frame.
func set_clock(weekday: int, hour: int, minute: int) -> void:
	_weekday = weekday
	_hour = hour
	_minute = minute
	_refresh()


## `wRadioTuningKnob`, whatever `UpdateRadioStation` last placed for it, and the
## two rows [Gen2RadioShow] has printed into the card's text box.
func set_radio(
	knob: int, station: String, lines: PackedStringArray = PackedStringArray()
) -> void:
	_knob = knob
	_station = station
	_show_lines = lines
	_refresh()


## The whole contact list and `GetMapPhoneService`'s answer. Only the first ten
## are kept, which is `wPhoneList`; the window and the cursor are left where they
## are, since `PokegearPhone_Init` is the one place that zeroes them and a delete
## redraws the list under the cursor it was chosen from.
func set_contacts(contacts: Array, service: bool) -> void:
	_contacts = contacts.slice(0, PHONE_LIST_SIZE)
	_service = service
	_refresh()


func card() -> StringName:
	return _card


## Which contact the cursor is on, or -1 on an empty slot, which is what
## `.a`'s own `and a / ret z` refuses.
func selected_contact() -> int:
	var index: int = _scroll + _cursor
	if index < 0 or index >= _contacts.size():
		return -1
	return int((_contacts[index] as Dictionary).get("index", -1))


## The three joypad handlers: B leaves every card, left and right are
## `Pokegear_SwitchPage`, and up and down are the dial on the radio card and the
## contact list on the phone card. The clock card reads neither.
func handle_button(button: int) -> bool:
	if not _open:
		return false
	if _asking_delete:
		_press_yes_no(button)
		return true
	if not _submenu.is_empty():
		_press_submenu(button)
		return true
	match button:
		Gen2Button.B:
			close()
			return true
		Gen2Button.LEFT, Gen2Button.RIGHT:
			switched.emit(-1 if button == Gen2Button.LEFT else 1)
			return true
	if _card == CARD_RADIO and button in [Gen2Button.UP, Gen2Button.DOWN]:
		var step: int = Gen2WorldRadio.KNOB_STEP * (1 if button == Gen2Button.UP else -1)
		var next: int = clampi(_knob + step, Gen2WorldRadio.KNOB_MIN, Gen2WorldRadio.KNOB_MAX)
		if next != _knob:
			tuned.emit(next)
		return true
	if _card != CARD_PHONE:
		# `PokegearClock_Joypad` quits on `PAD_BUTTONS`, so its up and down do
		# nothing at all; A on the radio card is swallowed, the dial being that
		# card's whole input.
		if _card == CARD_CLOCK and not Gen2Button.is_direction(button):
			close()
		return true
	match button:
		Gen2Button.UP:
			_move_phone(-1)
		Gen2Button.DOWN:
			_move_phone(1)
		Gen2Button.A:
			## `.a` refuses an empty slot before it opens the submenu.
			if selected_contact() >= 0:
				_open_submenu()
	return true


## `PokegearPhoneContactSubmenu`: CALL and CANCEL always, DELETE between them
## for a contact `CheckCanDeletePhoneNumber` allows.
func _open_submenu() -> void:
	_submenu = [SUBMENU_CALL, SUBMENU_CANCEL] if not _can_delete_selected() \
		else [SUBMENU_CALL, SUBMENU_DELETE, SUBMENU_CANCEL]
	_submenu_cursor = 0
	_refresh()


## `CheckCanDeletePhoneNumber`: every trainer, and every other caller but the two
## whose numbers it names.
func _can_delete_selected() -> bool:
	var index: int = _scroll + _cursor
	if index < 0 or index >= _contacts.size():
		return false
	var contact: Dictionary = _contacts[index]
	if int(contact.get("trainer_class", 0)) != 0:
		return true
	return not int(contact.get("non_trainer_id", -1)) in UNDELETABLE_CONTACTS


## `.loop`'s own joypad read: the cursor stops at both ends rather than wrapping,
## and B is CANCEL wherever it is.
func _press_submenu(button: int) -> void:
	match button:
		Gen2Button.UP:
			_submenu_cursor = maxi(_submenu_cursor - 1, 0)
		Gen2Button.DOWN:
			_submenu_cursor = mini(_submenu_cursor + 1, _submenu.size() - 1)
		Gen2Button.B:
			_close_submenu()
			return
		Gen2Button.A:
			match String(_submenu[_submenu_cursor]):
				SUBMENU_CALL:
					var contact: int = selected_contact()
					_close_submenu()
					called.emit(contact)
					return
				SUBMENU_DELETE:
					_asking_delete = true
					## `YesNoMenuHeader`'s own `db 1`, which is YES.
					_yes_no_cursor = 0
				_:
					_close_submenu()
					return
	_refresh()


## `YesNoBox`, whose B is the same answer NO is.
func _press_yes_no(button: int) -> void:
	match button:
		Gen2Button.UP:
			_yes_no_cursor = 0
		Gen2Button.DOWN:
			_yes_no_cursor = 1
		Gen2Button.B:
			## `InterpretTwoOptionMenu` answers a B the way NO answers.
			_close_submenu()
			return
		Gen2Button.A:
			var contact: int = selected_contact()
			var yes: bool = _yes_no_cursor == 0
			_close_submenu()
			if yes:
				deleted.emit(contact)
			return
	_refresh()


func _close_submenu() -> void:
	_submenu = []
	_asking_delete = false
	_refresh()


## `PokegearPhone_GetDPad`: the cursor walks the four rows on screen and the
## window scrolls only once it is against an end, and neither wraps.
func _move_phone(step: int) -> void:
	if step < 0:
		if _cursor > 0:
			_cursor -= 1
		elif _scroll > 0:
			_scroll -= 1
		else:
			return
	else:
		if _cursor < PHONE_DISPLAY_HEIGHT - 1:
			_cursor += 1
		elif _scroll < PHONE_LIST_SIZE - PHONE_DISPLAY_HEIGHT:
			_scroll += 1
		else:
			return
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


## The whole card as one 160x144 image, objects included, for a preview or a test
## that wants pixels rather than a viewport.
func render() -> Image:
	var out: Image = _background_image()
	out.blend_rect(
		_arrow_image(), Rect2i(Vector2i.ZERO, Vector2i(16, 16)), _arrow_position()
	)
	if _card == CARD_RADIO:
		out.blend_rect(
			_knob_image(),
			Rect2i(Vector2i.ZERO, Vector2i(Gen2TownMapPage.TILE, KNOB_TILES * Gen2TownMapPage.TILE)),
			_knob_position()
		)
	return out


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
	# The knob is spawned after the arrow and so takes the higher shadow-OAM
	# index; the two never overlap, but the order is the source's.
	_arrow = _sprite()
	_knob_icon = _sprite()


func _sprite() -> TextureRect:
	var node := TextureRect.new()
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(node)
	return node


func _refresh() -> void:
	if not _open or _background == null or _page == null:
		return
	_background.texture = ImageTexture.create_from_image(_background_image())
	_background.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_arrow.position = Vector2(_arrow_position())
	_arrow.texture = ImageTexture.create_from_image(_arrow_image())
	_knob_icon.visible = _card == CARD_RADIO
	if _knob_icon.visible:
		_knob_icon.position = Vector2(_knob_position())
		_knob_icon.texture = ImageTexture.create_from_image(_knob_image())


func _background_image() -> Image:
	if _page == null or _data == null:
		return Image.create(Gen2Screen.WIDTH, Gen2Screen.HEIGHT, false, Image.FORMAT_RGBA8)
	return _page.image(_data, _tilemap())


func _tilemap() -> PackedInt32Array:
	if _card == CARD_RADIO:
		return _page.radio_tilemap(_owned, _station, _show_lines)
	if _card != CARD_PHONE:
		return _page.clock_tilemap(_owned, _weekday, _hour, _minute, _text)
	var map: PackedInt32Array = _page.phone_tilemap(
		_owned, _phone_rows(), _cursor, _service,
		_delete_text if _asking_delete else _text
	)
	if not _submenu.is_empty():
		# The yes/no box is a window over the submenu rather than a replacement,
		# so the row it was chosen from keeps its arrow.
		_page.draw_phone_submenu(map, _submenu, _submenu_cursor)
	if _asking_delete:
		_page.draw_yes_no(map, _yes_no_cursor)
	return map


## The four rows on screen, as `GetCallerClassAndName` writes them: a trainer's
## own name over their class, and one line for everyone else. An empty slot is an
## empty row, which is what `wPhoneList`'s zeroes print.
func _phone_rows() -> Array:
	var rows: Array = []
	for row: int in PHONE_DISPLAY_HEIGHT:
		var index: int = _scroll + row
		if index >= _contacts.size():
			rows.append({})
			continue
		var contact: Dictionary = _contacts[index]
		var trainer_class: int = int(contact.get("trainer_class", 0))
		if trainer_class <= 0:
			rows.append({"name": String(contact.get("caller_label", ""))})
			continue
		rows.append({
			"name": String(_data.trainer_party(
				trainer_class, int(contact.get("trainer_number", 1)) - 1
			).get("name", "")),
			"class": _data.trainer_name(trainer_class),
		})
	return rows


func _arrow_position() -> Vector2i:
	return ARROW_AT + Vector2i(ARROW_CARD_STRIDE * maxi(ARROW_CARDS.find(_card), 0), 0)


func _knob_position() -> Vector2i:
	return KNOB_AT + Vector2i(_knob, 0)


## `.OAMData_RedWalk` over `PokegearSpritesGFX`'s first four tiles, which is the
## arrow rather than the region map's cursor.
func _arrow_image() -> Image:
	return _icon(ARROW_TILE, 2, 2)


## `.OAMData_RadioTuningKnob`, which is the same tile three times over.
func _knob_image() -> Image:
	return _icon(KNOB_TILE, 1, KNOB_TILES, true)


## A block of object tiles out of the Pokegear's own sprite sheet, coloured
## through the overworld's first palette the way every icon on these screens is.
## Colour zero is transparent, which is what lets one sit over the card.
func _icon(first: int, columns: int, rows: int, repeat: bool = false) -> Image:
	var pixels := Vector2i(columns, rows) * Gen2TownMapPage.TILE
	var out := Image.create(pixels.x, pixels.y, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var tiles: PackedByteArray = _data.tile_indices("pokegear_sprites") if _data != null \
		else PackedByteArray()
	var palette: PackedColorArray = _data.overworld_sprite_palette(0, _time_of_day) \
		if _data != null else PackedColorArray()
	if tiles.is_empty() or palette.is_empty():
		return out
	var width: int = tiles.size() / Gen2TownMapPage.TILE
	for row: int in rows:
		for column: int in columns:
			var tile: int = first if repeat else first + row * columns + column
			for y: int in Gen2TownMapPage.TILE:
				for x: int in Gen2TownMapPage.TILE:
					var index: int = tiles[
						y * width + tile * Gen2TownMapPage.TILE + x
					]
					if index == 0:
						continue
					out.set_pixel(
						column * Gen2TownMapPage.TILE + x,
						row * Gen2TownMapPage.TILE + y,
						palette[clampi(index, 0, palette.size() - 1)]
					)
	return out
