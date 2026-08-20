class_name Gen2TrainerCardScreen
extends Control

## The trainer card (`engine/menus/trainer_card.asm`), embedded in the overworld
## the way the Hall of Fame and the PC overlays are.
##
## Three pages: the card itself, then the Johto and Kanto badge pages. Page 3 is
## unreachable, exactly as it is on the cartridge: both `.KantoBadgeCheck`
## branches that would reach it are unreferenced in either pin. It is built all
## the same, so the day something references it there is nothing to add.
##
## The page's tiles come from [Gen2TrainerCardPage]; the badges are objects with
## their own palette drawn over it, and the play timer's colon blinks off the
## same frame counter the badges animate on.

signal closed()

## `hVBlankCounter and $1f`, so the colon flips every 32 frames, and
## `hVBlankCounter and %111` with an eight-step counter for the badges.
const SEPARATOR_FRAMES: int = 32
const BADGE_FRAMES: int = 8
const BADGE_CYCLE: int = 8

## `TrainerCard_JohtoBadgesOAM`. Each badge is four 8x8 objects in a 2x2 square
## at its own screen position, and the animation walks eight tile ids from the
## row's face tile. The positions are OAM coordinates, which carry the hardware's
## own 16 and 8 pixel offsets.
const OAM_Y_OFFSET: int = 16
const OAM_X_OFFSET: int = 8
const BADGE_TILE_SIZE: int = 8
## Each badge's y, x and its own eight frames, verbatim from the table: the two
## cycles are the same four tiles for every badge but the Risingbadge, whose
## second cycle shows its face x-flipped. Bit 7 of a tile id is `.PrepOAM`'s
## "draw this frame flipped", which is what turns a badge over rather than
## making it jump. The order is `wJohtoBadges`' bit order, which is also the
## badge order [constant Gen2WorldState.BADGE_ENGINE_FLAGS] uses, so Storm and
## Mineral sit where the table puts them rather than where the screen does.
const BADGE_FLIP: int = 0x80
const BADGE_OAM: Array[Dictionary] = [
	{"y": 0x68, "x": 0x18, "frames": [0x00, 0x20, 0x24, 0xA0, 0x00, 0x20, 0x24, 0xA0]},
	{"y": 0x68, "x": 0x38, "frames": [0x04, 0x20, 0x24, 0xA0, 0x04, 0x20, 0x24, 0xA0]},
	{"y": 0x68, "x": 0x58, "frames": [0x08, 0x20, 0x24, 0xA0, 0x08, 0x20, 0x24, 0xA0]},
	{"y": 0x68, "x": 0x78, "frames": [0x0C, 0x20, 0x24, 0xA0, 0x0C, 0x20, 0x24, 0xA0]},
	{"y": 0x80, "x": 0x38, "frames": [0x10, 0x20, 0x24, 0xA0, 0x10, 0x20, 0x24, 0xA0]},
	{"y": 0x80, "x": 0x18, "frames": [0x14, 0x20, 0x24, 0xA0, 0x14, 0x20, 0x24, 0xA0]},
	{"y": 0x80, "x": 0x58, "frames": [0x18, 0x20, 0x24, 0xA0, 0x18, 0x20, 0x24, 0xA0]},
	{"y": 0x80, "x": 0x78, "frames": [0x1C, 0x20, 0x24, 0xA0, 0x9C, 0x20, 0x24, 0xA0]},
]

var _data: GameData = null
var _page_renderer: Gen2TrainerCardPage = null
var _save: Gen2SaveData = null
var _world: Gen2WorldAPI = null
var _page: int = Gen2TrainerCard.PAGE_1
var _frames: int = 0
var _background: TextureRect = null
var _badges: Array = []
## Leftover of a hardware frame this screen has not counted yet.
var _elapsed: float = 0.0


## Optional the way the other overlays are: without a save there is no card, so
## this answers false and the caller keeps the start menu open.
func open(data: GameData, world: Gen2WorldAPI, save: Gen2SaveData) -> bool:
	_data = data
	_world = world
	_save = save
	if _data == null or _save == null:
		return false
	_page_renderer = Gen2TrainerCardPage.from_data(
		_data,
		save.gender == Gen2SaveData.GENDER_FEMALE,
		Gen2WorldState.is_crystal_profile(_data),
	)
	if _page_renderer == null or not _page_renderer.ready():
		return false
	if is_inside_tree() and _background != null:
		_show_page(Gen2TrainerCard.PAGE_1)
	return true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_build()
	if _page_renderer != null:
		_show_page(Gen2TrainerCard.PAGE_1)


func current_page() -> int:
	return _page


## `.loop`'s own joypad read. Every page answers B, and the rest is
## [method Gen2TrainerCard.next_page]'s table.
func handle_button(button: int) -> bool:
	var answer: Dictionary = Gen2TrainerCard.next_page(_page, button)
	if answer.is_empty():
		return false
	if bool(answer.get("exit", false)):
		closed.emit()
		return true
	_show_page(int(answer["page"]))
	return true


## One hardware frame: the badges turn every eight and the colon flips every
## thirty-two, both off the counter the source reads rather than off a timer.
func advance_frame() -> void:
	_frames += 1
	if _frames % BADGE_FRAMES == 0 and _page != Gen2TrainerCard.PAGE_1:
		_refresh_badges()
	if _frames % SEPARATOR_FRAMES == 0 and _page == Gen2TrainerCard.PAGE_1:
		_refresh_page()


func _process(delta: float) -> void:
	_elapsed += delta
	while _elapsed >= Gen2WorldAnimation.FRAME_SECONDS:
		_elapsed -= Gen2WorldAnimation.FRAME_SECONDS
		advance_frame()


func _build() -> void:
	_background = TextureRect.new()
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)


## Each page's own LoadGFX: the 86-tile window is reloaded, the page redrawn and
## the badge objects rebuilt from scratch, which is what `ClearSprites` does.
func _show_page(page: int) -> void:
	_page = page
	_frames = 0
	_page_renderer.load_page_tiles(_data, page)
	_refresh_page()
	_refresh_badges()


func _refresh_page() -> void:
	if _background == null or _page_renderer == null:
		return
	var separator: bool = int(_frames / SEPARATOR_FRAMES) % 2 == 0
	var page: Dictionary = Gen2TrainerCard.page(_save, _world, _page, separator)
	var indices: PackedByteArray = _page_renderer.draw(page)
	_background.texture = ImageTexture.create_from_image(
		_image_from(indices, _page_renderer.attributes())
	)
	_background.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)


## Colours each tile through the palette `_CGB_TrainerCard` gave it, which is
## why this cannot go through [method Gen2PicImage.from_indices] whole: the card
## is eight palettes at once.
func _image_from(indices: PackedByteArray, attributes: PackedInt32Array) -> Image:
	var image := Image.create(Gen2Screen.WIDTH, Gen2Screen.HEIGHT, false, Image.FORMAT_RGBA8)
	var tile: int = Gen2TrainerCardPage.TILE
	var palettes: Array = []
	for slot: int in RomLayout.CARD_PALETTE_CLASSES.size():
		palettes.append(_data.card_palette(slot))
	for row: int in Gen2TrainerCardPage.ROWS:
		for column: int in Gen2TrainerCardPage.COLUMNS:
			var slot: int = attributes[row * Gen2TrainerCardPage.COLUMNS + column]
			var palette: PackedColorArray = palettes[clampi(slot, 0, palettes.size() - 1)]
			for y: int in tile:
				for x: int in tile:
					var at_x: int = column * tile + x
					var at_y: int = row * tile + y
					var index: int = indices[at_y * Gen2Screen.WIDTH + at_x]
					image.set_pixel(
						at_x, at_y, palette[clampi(index, 0, palette.size() - 1)]
					)
	return image


## `TrainerCard_Page2_3_OAMUpdate`: one 2x2 object group per set badge, skipping
## the clear ones, each drawn at its own template position in the frame the
## shared counter is on.
func _refresh_badges() -> void:
	for node: Node in _badges:
		node.queue_free()
	_badges = []
	if _page == Gen2TrainerCard.PAGE_1 or _data == null:
		return
	var set_badges: Array = Gen2TrainerCard.badges(
		_world.state if _world != null else null,
		_page,
		Gen2WorldState.is_crystal_profile(_data),
	)
	var frame: int = int(_frames / BADGE_FRAMES) % BADGE_CYCLE
	for index: int in BADGE_OAM.size():
		if index >= set_badges.size() or not bool(set_badges[index]):
			continue
		var badge: Dictionary = BADGE_OAM[index]
		var sprite := TextureRect.new()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.texture = ImageTexture.create_from_image(
			_badge_image(int((badge["frames"] as Array)[frame]))
		)
		sprite.position = Vector2(
			int(badge["x"]) - OAM_X_OFFSET, int(badge["y"]) - OAM_Y_OFFSET
		)
		add_child(sprite)
		_badges.append(sprite)


## One frame of one badge: `.facing1`'s four objects, or `.facing2`'s when the
## tile id carries bit 7. `.facing2` mirrors the whole 2x2 square, swapping the
## two columns as well as flipping each tile, which is why this mirrors across
## the square rather than inside a tile.
func _badge_image(frame_tile: int) -> Image:
	var tiles: PackedByteArray = _data.tile_indices("card_badges")
	var palette: PackedColorArray = _data.card_badge_palette()
	var side: int = BADGE_TILE_SIZE * 2
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	if tiles.is_empty():
		return image
	var strip_width: int = tiles.size() / BADGE_TILE_SIZE
	var flip: bool = (frame_tile & BADGE_FLIP) != 0
	var first: int = frame_tile & ~BADGE_FLIP
	for quadrant: int in 4:
		var tile: int = first + quadrant
		var to_x: int = (quadrant % 2) * BADGE_TILE_SIZE
		var to_y: int = int(quadrant / 2) * BADGE_TILE_SIZE
		for y: int in BADGE_TILE_SIZE:
			for x: int in BADGE_TILE_SIZE:
				var from: int = y * strip_width + tile * BADGE_TILE_SIZE + x
				if from >= tiles.size():
					continue
				var index: int = tiles[from]
				## Object colour zero is transparent under the hardware's own
				## rules, which is what lets a badge sit over the card.
				if index == 0:
					continue
				var at_x: int = side - 1 - (to_x + x) if flip else to_x + x
				image.set_pixel(
					at_x, to_y + y, palette[clampi(index, 0, palette.size() - 1)]
				)
	return image
