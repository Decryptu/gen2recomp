extends RefCounted

var _r: RefCounted = null

## Verifies Bill's PC's own graphics and its screen against freshly imported real
## caches, over every species rather than a sampled one.
##
## Expected values come from `engine/pokemon/bills_pc.asm`: `BillsPC_InitGFX`'s
## two runs, `_CGB_BillsPC`'s palettes, `BillsPC_RefreshTextboxes`' listing and
## `PCMonInfo`'s left column. The sweep is over species because that column is
## the one thing on the screen whose width is not fixed: a pic wider than its
## seven-tile cell, or a name wider than the two boxes `ClearBox` leaves for it,
## would overrun the listing, and no one-species screenshot says so.
##
##   Godot --headless --path . -s res://tools/validate.gd -- pc

## `BillsPCOrangePalette`, `gfx/pc/orange.pal`, which is the same four colours in
## all three dumps.
const ORANGE: Array[int] = [0x01FF, 0x0197, 0x00EF, 0x0000]
const SPECIES_COUNT: int = 251
## What `PCMonInfo` clears for the pic, the name and the level: eight columns
## (`hlcoord 0, 0 / lb bc, 15, 8`) plus the three past them on the name's own row
## (`hlcoord 8, 14 / lb bc, 1, 3`). The second clear is there for exactly one
## reason: the longest species name is ten tiles printed from column 1.
const INFO_COLUMNS: int = 8
const NAME_OVERHANG: Vector2i = Vector2i(8, 14)
const NAME_OVERHANG_COLUMNS: int = 3


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_graphics(game_id, data)
		_verify_cursor(game_id, Gen2PCBoxPage.from_data(data))
		_verify_info_column(game_id, data)


## `BillsPC_InitGFX`'s two sheets and the palette `_CGB_BillsPC` loads over the
## pic box for a row with no Pokemon on it.
func _verify_graphics(game_id: StringName, data: GameData) -> void:
	for run_row: Array in [
		["pc_select", RomLayout.PC_SELECT_TILES], ["pc_mail", RomLayout.PC_MAIL_TILES],
	]:
		var strip: PackedByteArray = data.tile_indices(String(run_row[0]))
		var want: int = int(run_row[1]) * Gen2Tiles.TILE_WIDTH * Gen2Tiles.TILE_HEIGHT
		_r.check(
			strip.size() == want,
			"%s: %s is %d pixels, not the %d its %d tiles need." % [
				game_id, String(run_row[0]), strip.size(), want, int(run_row[1]),
			]
		)
	var palette: PackedColorArray = data.pc_palette()
	if not _r.check(
		palette.size() == RomLayout.PC_PALETTE_COLORS,
		"%s: the PC palette holds %d colours, not %d." % [
			game_id, palette.size(), RomLayout.PC_PALETTE_COLORS,
		]
	):
		return
	for index: int in ORANGE.size():
		_r.check(
			palette[index].is_equal_approx(Gen2Palette.from_packed(ORANGE[index])),
			"%s: PC colour %d is %s, not the pinned $%04X." % [
				game_id, index, palette[index], ORANGE[index],
			]
		)


## `BillsPC_UpdateSelectionCursor`'s OAM for each of the five rows it can stand
## on: every object inside the listing box and stepping sixteen pixels a row,
## which is what says the shadow-OAM bias was taken off once rather than twice.
func _verify_cursor(game_id: StringName, page: Gen2PCBoxPage) -> void:
	if not _r.check(page != null, "%s: the PC page needs a font." % game_id):
		return
	var box: Rect2i = Gen2PCBoxPage.LIST_BOX
	var left: int = box.position.x * Gen2Font.TILE
	var right: int = (box.position.x + box.size.x) * Gen2Font.TILE
	var first: Array = page.cursor_sprites(0, 1)
	for cursor: int in Gen2PCBoxPage.LIST_HEIGHT:
		var sprites: Array = page.cursor_sprites(cursor, 1)
		if not _r.check(
			sprites.size() == page.cursor_set().size(),
			"%s: cursor %d draws %d objects, not %d." % [
				game_id, cursor, sprites.size(), page.cursor_set().size(),
			]
		):
			return
		for index: int in sprites.size():
			var at: Vector2i = sprites[index]["position"]
			var step: int = at.y - Vector2i(first[index]["position"]).y
			_r.check(
				step == cursor * Gen2PCBoxPage.CURSOR_STEP,
				"%s: cursor %d object %d sits %d pixels down, not %d." % [
					game_id, cursor, index, step,
					cursor * Gen2PCBoxPage.CURSOR_STEP,
				]
			)
			_r.check(
				at.x >= left - Gen2Font.TILE and at.x < right \
					and at.y >= 0 and at.y < Gen2Screen.HEIGHT,
				"%s: cursor %d object %d is at %s, outside the listing." % [
					game_id, cursor, index, at,
				]
			)
	_r.check(
		page.cursor_sprites(0, 0).is_empty(),
		"%s: a list with nothing in it still draws a cursor." % game_id
	)


## `PCMonInfo`'s column over the whole species run: the pic fits the seven-tile
## cell and the name fits the eleven columns its two clears cover.
func _verify_info_column(game_id: StringName, data: GameData) -> void:
	var cell: int = Gen2PCBoxPage.pic_size()
	var widest: int = 0
	var widest_name: String = ""
	for species: int in range(1, SPECIES_COUNT + 1):
		var pic: Dictionary = data.species_pic(species)
		if not _r.check(not pic.is_empty(), "%s: species %d has no pic." % [game_id, species]):
			continue
		_r.check(
			int(pic.get("width", 0)) <= cell and int(pic.get("height", 0)) <= cell,
			"%s: species %d is %dx%d, past the %dx%d cell." % [
				game_id, species, int(pic["width"]), int(pic["height"]), cell, cell,
			]
		)
		var name: String = String(data.species(species).get("name", ""))
		var columns: int = Gen2Text.encoded_length(name, Gen2Text.FONT_BATTLE_EXTRA)
		if columns > widest:
			widest = columns
			widest_name = name
	_r.check(
		Gen2PCBoxPage.SPECIES_AT.x + widest <= INFO_COLUMNS + NAME_OVERHANG_COLUMNS,
		"%s: %s is %d columns and runs past the %d PCMonInfo clears." % [
			game_id, widest_name, widest, INFO_COLUMNS + NAME_OVERHANG_COLUMNS,
		]
	)
	_r.check(
		Gen2PCBoxPage.SPECIES_AT.y == NAME_OVERHANG.y \
			and Gen2PCBoxPage.SPECIES_AT.x + widest <= NAME_OVERHANG.x + NAME_OVERHANG_COLUMNS,
		"%s: the name row is not the one the second ClearBox covers." % game_id
	)
