extends Control

## Development view: one species on a real 160x144 screen.
##
## Scaffolding, and deliberately so. It exists to prove the whole path from a
## cartridge to a lit pixel (cache to indices to palette to viewport to an
## integer-scaled window) and to make a wrong decode visible without a dev tool
## writing a PNG. The battle screen will do this properly, with the pic where
## the hardware puts it and a tile-based font around it.
##
## Left/right change species, S toggles shiny, B swaps front for back, and T
## switches to the trainer classes, which have one palette each and no back pic.
## Each is also a plain method so `tools/screenshot.gd` can drive it.

## The white the hardware fills a pic window with. Index 0 of every pic is this
## colour, so a sprite on it looks exactly as it does in the game.
const BACKGROUND: Color = Color.WHITE

var _data: GameData = null
var _number: int = 1
var _shiny: bool = false
var _back: bool = false
var _trainers: bool = false

var _pic: TextureRect = null

@onready var _screen: Gen2Screen = %Screen
@onready var _caption: Label = %Caption
@onready var _hint: Label = %Hint


func _ready() -> void:
	_data = GameData.open_any()
	if _data == null:
		_caption.text = "No cache found"
		_hint.text = "Run tools/import_rom.gd first."
		return

	var field := ColorRect.new()
	field.color = BACKGROUND
	field.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_screen.display(field)

	_pic = TextureRect.new()
	# Nearest, or the whole point of the integer-scaled viewport is lost on the
	# last hop.
	_pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_screen.display(_pic)

	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if _data == null or not event.is_pressed():
		return

	var key: InputEventKey = event as InputEventKey
	if key == null:
		return

	match key.keycode:
		KEY_RIGHT:
			next_species()
		KEY_LEFT:
			previous_species()
		KEY_S:
			toggle_shiny()
		KEY_B:
			toggle_back()
		KEY_T:
			toggle_trainers()
		_:
			return
	accept_event()


func next_species() -> void:
	show_species(_number + 1)


func previous_species() -> void:
	show_species(_number - 1)


## Wraps at both ends, so holding an arrow down never lands on a blank screen.
## In trainer mode the number is a class rather than a species; the two count
## differently and the wrap follows whichever is on screen.
func show_species(number: int) -> void:
	if _data == null:
		return
	var count: int = _data.trainer_count() if _trainers else _data.species_count()
	if count <= 0:
		return
	_number = wrapi(number, 1, count + 1)
	_refresh()


## The trainer classes use the same viewer because they are the same path: a
## slot in an atlas and a palette applied at draw time.
func show_trainer(number: int) -> void:
	_trainers = true
	show_species(number)


func toggle_shiny() -> void:
	_shiny = not _shiny
	_refresh()


func toggle_back() -> void:
	_back = not _back
	_refresh()


func toggle_trainers() -> void:
	_trainers = not _trainers
	# Class 67 is a species and species 251 is not a class, so the number cannot
	# survive the switch.
	show_species(1)


func _refresh() -> void:
	if _data == null or _pic == null:
		return

	if _trainers:
		_refresh_trainer()
		return

	var entry: Dictionary = _data.species(_number)
	var pic: Dictionary = _data.species_pic(_number, _back)
	if entry.is_empty() or pic.is_empty():
		return

	var atlas: Dictionary = _data.atlas(pic["atlas"])
	var image: Image = Gen2PicImage.from_atlas(
		_data.atlas_indices(pic["atlas"]), atlas, pic, _data.palette(_number, _shiny)
	)

	_show(image)
	_caption.text = "%s   #%03d %s   %s   %s" % [
		_data.title(), _number, entry["name"],
		"back" if _back else "front",
		"shiny" if _shiny else "normal",
	]
	_hint.text = "left/right species    S shiny    B front/back    T trainers"


func _refresh_trainer() -> void:
	var pic: Dictionary = _data.trainer_pic(_number)
	if pic.is_empty():
		return

	_show(Gen2PicImage.from_atlas(
		_data.atlas_indices(pic["atlas"]), _data.atlas(pic["atlas"]), pic,
		_data.trainer_palette(_number)
	))
	_caption.text = "%s   class %02d %s" % [
		_data.title(), _number, _data.trainer_name(_number),
	]
	_hint.text = "left/right class    T back to species"


func _show(image: Image) -> void:
	_pic.texture = ImageTexture.create_from_image(image)
	_pic.size = image.get_size()
	_pic.position = (
		Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT) - Vector2(image.get_size())
	).floor() * 0.5
