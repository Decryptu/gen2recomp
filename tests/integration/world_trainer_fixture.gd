extends RefCounted

## A small cache assembled in the same files the importer writes. It keeps the
## scene integration test independent of a user cartridge while preserving the
## real GameData, world API, script runner and battle overlay boundaries.

const BattleFixture := preload("res://tests/unit/battle_fixture.gd")

const GAME_ID: StringName = &"worldtrainer"
const SHA1: String = "0123456789abcdef"
const BANK: int = 48
const MAP_GROUP: int = 1
const MAP_NUMBER: int = 1
const MAP_WIDTH_BLOCKS: int = 6
const MAP_HEIGHT_BLOCKS: int = 5
const MAP_WIDTH_CELLS: int = MAP_WIDTH_BLOCKS * 2
const MAP_HEIGHT_CELLS: int = MAP_HEIGHT_BLOCKS * 2
const TRAINER_SCRIPT: int = 0x6100
const TUTORIAL_SCRIPT: int = 0x6110
const SEEN_TEXT: int = 0x6FF0
const WIN_TEXT: int = 0x7000
const LOSS_TEXT: int = 0x7010
const TRAINER_FLAG: int = 8
## The fixture ships one trainer class, numbered 1, holding one trainer.
const TRAINER_CLASS: int = 1
const TRAINER_SPECIES: int = 16
const TRAINER_SPRITE: int = 1


## Every caller but the Gold/Silver profile tests uses the default id, so the
## existing Crystal-profile fixture directory and manifest are unchanged.
static func directory(game_id: StringName = GAME_ID) -> String:
	return RomCache.directory_for(game_id, SHA1)


static func build(game_id: StringName = GAME_ID) -> GameData:
	var directory: String = directory(game_id)
	var base: GameData = BattleFixture.build(directory)
	assert(base != null)

	var manifest: Dictionary = RomCache.read_manifest(directory)
	# GameData.id, and therefore Gen2WorldScriptRunner's command profile, comes
	# straight from this field, so the trainer script bytes below must match it.
	var crystal_commands: bool = game_id != &"gold" and game_id != &"silver"
	_write_trainers(directory)
	_write_world(directory, crystal_commands)
	_write_overworld_graphics(directory)
	_write_battle_graphics(directory, manifest)
	_write_name_input_chars(directory)
	_write_intro_text(directory, crystal_commands)
	manifest["game_id"] = String(game_id)
	manifest["sha1"] = SHA1
	manifest["complete"] = true
	RomCache.write_json(RomCache.manifest_path(directory), manifest)
	return GameData.open_directory(directory)


## The four naming keyboards with the real block's shape and command rows, the
## letters generated. What is under a letter key decides nothing in
## `naming_screen.asm`; the command row and the row counts decide everything.
static func _write_name_input_chars(directory: String) -> void:
	var tables: Array = []
	for table: int in RomLayout.NAME_INPUT_TABLE_ROWS.size():
		var first: int = RomLayout.NAME_INPUT_LOWER_A if table < 2 else RomLayout.NAME_INPUT_UPPER_A
		var rows: Array = []
		var count: int = RomLayout.NAME_INPUT_TABLE_ROWS[table]
		for row: int in count:
			if row == count - 1:
				rows.append(Array(
					RomLayout.NAME_INPUT_COMMAND_LOWER if table < 2
					else RomLayout.NAME_INPUT_COMMAND_UPPER
				))
				continue
			var codes: Array[int] = []
			for column: int in RomLayout.NAME_INPUT_COLUMNS:
				codes.append(first + row * RomLayout.NAME_INPUT_COLUMNS + column)
				if column < RomLayout.NAME_INPUT_COLUMNS - 1:
					codes.append(Gen2Text.SPACE)
			rows.append(codes)
		tables.append(rows)
	RomCache.write_json(RomCache.name_input_chars_path(directory), tables)


## The intro's own texts, synthetic. Every rule that reads them cares only that
## a text is there and how many pages it wraps to, so the words are stand-ins.
## The gender text is Crystal only, the way `init_gender.asm` is: a Gold or
## Silver fixture leaves the key out and the gender screen refuses to open.
static func _write_intro_text(directory: String, crystal: bool) -> void:
	var text: Dictionary = {
		"oak_1": "Oak one.\n\nOak one page two.",
		"oak_2": "Oak two.",
		"oak_4": "Oak four.",
		"oak_5": "Oak five.",
		"oak_6": "Oak six.",
		"oak_7": "<PLAYER>, oak seven.",
	}
	if crystal:
		text["gender"] = "Are you a boy?\nOr are you a girl?"
	RomCache.write_json(RomCache.intro_text_path(directory), text)


static func _write_trainers(directory: String) -> void:
	RomCache.write_json(RomCache.trainers_path(directory), [{
		"number": 1,
		"name": "LEADER",
		"palette": [0x1234, 0x5678],
		"dvs": Gen2BattleMon.PERFECT_DVS,
		"attributes": {
			"item1": 0,
			"item2": 0,
			"base_reward": 25,
			"ai_move_weights": 0,
			"ai_item_switch": 0,
		},
		"trainers": [{
			"name": "RIVAL",
			"type": RomLayout.TRAINER_MON_ITEM_MOVES,
			"party": [{
				"level": 5,
				"species": TRAINER_SPECIES,
				"item": 0,
				"moves": [BattleFixture.TACKLE, 0, 0, 0],
			}],
		}],
	}])


static func _write_world(directory: String, crystal_commands: bool = true) -> void:
	var blocks: Array = []
	blocks.resize(MAP_WIDTH_BLOCKS * MAP_HEIGHT_BLOCKS)
	blocks.fill(0)
	var collision: Array = []
	collision.resize(MAP_WIDTH_CELLS * MAP_HEIGHT_CELLS)
	collision.fill(0)
	collision[7 * MAP_WIDTH_CELLS + 8] = 0x20

	var objects: Array = [{
		"sprite": TRAINER_SPRITE,
		"x": 5,
		"y": 3,
		"movement": Gen2WorldObject.MOVEMENT_FIXED_DOWN,
		"x_radius": 0,
		"y_radius": 0,
		"hour_1": -1,
		"hour_2": -1,
		"palette": 0,
		"object_type": Gen2WorldObject.OBJECTTYPE_TRAINER,
		"sight_range": 3,
		"script": TRAINER_SCRIPT,
		"event_flag": TRAINER_FLAG,
		"trainer": {
			"event_flag": TRAINER_FLAG,
			"trainer_group": 1,
			"trainer_id": 1,
			"seen_text": {"bank": BANK, "address": SEEN_TEXT},
			"win_text": {"bank": BANK, "address": WIN_TEXT},
			"loss_text": {"bank": BANK, "address": LOSS_TEXT},
			"after_script": 0,
		},
	}]
	var map: Dictionary = {
		"group": MAP_GROUP,
		"number": MAP_NUMBER,
		"tileset": 0,
		"environment": 0,
		"fish_group": 1,
		"music": 0,
		"width_blocks": MAP_WIDTH_BLOCKS,
		"height_blocks": MAP_HEIGHT_BLOCKS,
		"blocks": blocks,
		"collision": collision,
		"collision_width": MAP_WIDTH_CELLS,
		"collision_height": MAP_HEIGHT_CELLS,
		"scripts": {"bank": BANK, "callbacks": []},
		"events": {
			"bank": BANK,
			"coord_events": [{"scene": 0, "x": 4, "y": 5, "script": TUTORIAL_SCRIPT}],
			"objects": objects,
		},
	}
	var home_map: Dictionary = map.duplicate(true)
	home_map["group"] = Gen2WorldSpawn.NEW_BARK_GROUP
	home_map["number"] = Gen2WorldSpawn.PLAYERS_HOUSE_2F
	home_map["fish_group"] = 0
	home_map["width_blocks"] = 4
	home_map["height_blocks"] = 3
	var home_blocks: Array = []
	home_blocks.resize(12)
	home_blocks.fill(0)
	home_map["blocks"] = home_blocks
	var home_collision: Array = []
	home_collision.resize(8 * 6)
	home_collision.fill(0)
	home_map["collision"] = home_collision
	home_map["collision_width"] = 8
	home_map["collision_height"] = 6
	home_map["events"] = {"bank": BANK, "objects": []}
	RomCache.write_json(RomCache.world_maps_path(directory), [map, home_map])
	var grass_slots: Array = []
	for _slot: int in RomLayout.WILD_GRASS_SLOT_COUNT:
		grass_slots.append({"level": 5, "species": TRAINER_SPECIES})
	var grass_times: Array = [grass_slots.duplicate(true), grass_slots.duplicate(true), grass_slots.duplicate(true)]
	RomCache.write_json(RomCache.world_encounters_path(directory), {
		"grass": {"1:1": {
			"map": "1:1", "rates": [255, 255, 255], "slots": grass_times,
		}},
		"water": {},
		"fishing": {
			"groups": [{
				"chance": 255,
				"rods": [[{"threshold": 255, "species": TRAINER_SPECIES, "level": 5}], [], []],
			}],
			"time_groups": [],
		},
		"probabilities": {
			"grass": RomLayout.WILD_GRASS_PROBABILITIES,
			"water": RomLayout.WILD_WATER_PROBABILITIES,
		},
	})

	# These two scripts are stored at the object's/coord event's own address,
	# separate from the synthesized SeenByTrainerScript sequence the runner
	# builds for the initial sight-triggered phase. Their raw bytes must still
	# match the requested profile.
	var raw: Callable = func(source_opcode: int) -> int:
		return Gen2WorldScript.raw_opcode(source_opcode, crystal_commands)
	var script: Array = [
		raw.call(0x5D), 1, 0, # loadtrainer
		raw.call(0x63), WIN_TEXT & 0xFF, WIN_TEXT >> 8, LOSS_TEXT & 0xFF, LOSS_TEXT >> 8, # winlosstext
		raw.call(0x5E), # startbattle
		Gen2WorldScript.SETEVENT, TRAINER_FLAG & 0xFF, TRAINER_FLAG >> 8,
		raw.call(0x5F), # reloadmapafterbattle
		raw.call(0x90), # end
	]
	var tutorial_script: Array = [
		raw.call(0x5C), TRAINER_SPECIES, 5, # loadwildmon
		raw.call(0x60), 3, # catchtutorial
		raw.call(0x90), # end
	]
	RomCache.write_json(RomCache.world_scripts_path(directory), {
		Gen2WorldScript.pointer_key(BANK, TRAINER_SCRIPT): script,
		Gen2WorldScript.pointer_key(BANK, TUTORIAL_SCRIPT): tutorial_script,
	})
	RomCache.write_json(RomCache.world_text_path(directory), {
		Gen2WorldScript.pointer_key(BANK, SEEN_TEXT): _text("RIVAL noticed you."),
		Gen2WorldScript.pointer_key(BANK, WIN_TEXT): _text("YOU WON."),
		Gen2WorldScript.pointer_key(BANK, LOSS_TEXT): _text("YOU LOST."),
	})
	RomCache.write_json(RomCache.world_standard_scripts_path(directory), {})
	RomCache.write_json(RomCache.world_movements_path(directory), {})

	var meta: Array = []
	for tile: int in RomLayout.MAP_BLOCK_TILE_WIDTH * RomLayout.MAP_BLOCK_TILE_WIDTH:
		meta.append(tile)
	var palette_map: Array = []
	palette_map.resize((RomLayout.TILESET_TILE_COUNT + 1) / 2)
	palette_map.fill(0)
	RomCache.write_json(RomCache.world_tilesets_path(directory), [{
		"number": 0,
		"block_count": 1,
		"tile_count": RomLayout.TILESET_TILE_COUNT,
		"meta": meta,
		"collision": [],
		"palette_map": palette_map,
		"animation_commands": [],
	}])
	var palettes: Array = []
	for _group: int in 42:
		palettes.append([0x7FFF, 0x421F, 0x2108, 0])
	RomCache.write_json(RomCache.world_palettes_path(directory), palettes)
	RomCache.write_json(RomCache.world_animation_assets_path(directory), {})


static func _write_overworld_graphics(directory: String) -> void:
	RomCache.write_json(RomCache.overworld_sprites_path(directory), [{
		"number": TRAINER_SPRITE,
		"address": 0x4000,
		"bank": BANK,
		"bytes": 64,
		"tiles": 4,
		"type": Gen2WorldSprite.TYPE_STILL,
		"palette": 0,
	}])
	var palettes: Array = []
	for _group: int in RomLayout.OVERWORLD_SPRITE_PALETTE_GROUP_COUNT:
		palettes.append([0x7FFF, 0x421F, 0x2108, 0])
	RomCache.write_json(RomCache.overworld_sprite_palettes_path(directory), palettes)

	var tiles: PackedByteArray = PackedByteArray()
	tiles.resize(RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_PIXELS)
	tiles.fill(1)
	RomCache.write_indices(RomCache.world_tile_path(directory, 0), tiles)

	var sprite: PackedByteArray = PackedByteArray()
	sprite.resize(4 * Gen2Tiles.TILE_PIXELS)
	sprite.fill(1)
	RomCache.write_indices(RomCache.overworld_sprite_path(directory, TRAINER_SPRITE), sprite)


static func _write_battle_graphics(directory: String, manifest: Dictionary) -> void:
	var sheets: Dictionary = {}
	var sheet_tiles: Dictionary = {
		"exp_bar": [RomLayout.EXP_BAR_TILES, 2],
		"battle_font": [RomLayout.BATTLE_FONT_TILES, 1],
		"enemy_hud": [RomLayout.ENEMY_HUD_TILES, 2],
		"player_hud": [RomLayout.PLAYER_HUD_TILES, 3],
		"font": [RomLayout.FONT_TILES, 3],
		"frames": [RomLayout.FRAME_COUNT * RomLayout.FRAME_TILES, 3],
		## The trainer card's own sheets. Flat fills like the rest of these: the
		## card's layout is what a test checks, and real artwork would say
		## nothing about it.
		"card_status": [RomLayout.CARD_STATUS_TILES, 1],
		"card_leaders": [RomLayout.CARD_LEADER_TILES, 2],
		"card_badges": [RomLayout.CARD_BADGE_TILES, 3],
		"card_frame": [RomLayout.CARD_FRAME_TILES, 1],
		"card_pic_male": [RomLayout.CARD_PIC_TILES, 2],
		"card_pic_female": [RomLayout.CARD_PIC_TILES, 3],
		"card_right_corner": [RomLayout.CARD_RIGHT_CORNER_TILES, 1],
		## LoadNamingScreenGFX's four. The cursor gets its own index so the
		## bracket can be told from the keyboard under it.
		"naming_border": [RomLayout.NAMING_BORDER_TILES, 1],
		"naming_cursor": [RomLayout.NAMING_CURSOR_TILES, 2],
		"naming_middle_line": [RomLayout.NAMING_MARKER_TILES, 1],
		"naming_under_line": [RomLayout.NAMING_MARKER_TILES, 1],
		## `LoadGenderScreenLightBlueTile`'s one tile, on the index the real one
		## carries, since the page reads the fill out of it rather than assuming.
		"gender_screen": [RomLayout.GENDER_SCREEN_TILES, RomLayout.GENDER_SCREEN_FILL_INDEX],
		## `ShrinkPlayer`'s two pictures, flat fills like the rest: what a test
		## checks is when each is drawn, not what is in it.
		"shrink_1": [RomLayout.SHRINK_PIC_TILES, 2],
		"shrink_2": [RomLayout.SHRINK_PIC_TILES, 1],
	}
	## The font and the frames are the two sheets addressed by character code
	## rather than by slot, so both need their real first code. A frames sheet
	## left on 0 draws nothing at all, since every box-drawing code is then past
	## the end of the strip.
	var first_codes: Dictionary = {
		"font": RomLayout.FONT_FIRST_CODE,
		"frames": RomLayout.FRAME_FIRST_CODE,
	}
	for name: String in sheet_tiles:
		var tile_count: int = int(sheet_tiles[name][0])
		var indices: PackedByteArray = PackedByteArray()
		indices.resize(tile_count * Gen2Tiles.TILE_PIXELS)
		indices.fill(int(sheet_tiles[name][1]))
		RomCache.write_indices(RomCache.tile_path(directory, name), indices)
		sheets[name] = {
			"width": tile_count * Gen2Tiles.TILE_WIDTH,
			"height": Gen2Tiles.TILE_HEIGHT,
			"tiles": tile_count,
			"first_code": int(first_codes.get(name, 0)),
			"bits": 1,
		}
	manifest["tiles"] = sheets
	manifest["card_palettes"] = {
		"background": [
			[0x7FFF, 0x0000], [0x001F, 0x0000], [0x03E0, 0x0000], [0x7C00, 0x0000],
			[0x7FE0, 0x0000], [0x03FF, 0x0000], [0x7C1F, 0x0000], [0x4210, 0x0000],
		],
		"badge": [0x7FFF, 0x5ABA, 0x49EF, 0x0000],
	}
	## `gfx/new_game/gender_screen.pal`'s own four colours.
	manifest["gender_screen_palette"] = [0x7FFF, 0x7FC9, 0x7D61, 0x0000]
	manifest["bar_palettes"] = {
		"hp_green": [0x02E0, 0x02E0],
		"hp_yellow": [0x02BF, 0x02BF],
		"hp_red": [0x001F, 0x001F],
		"exp": [0x7E24, 0x7E24],
	}

	var cell: int = 7 * Gen2Tiles.TILE_WIDTH
	var columns: int = 16
	var atlas_width: int = columns * cell
	var rows: int = int(ceil(float(BattleFixture.MAGCARGO) / float(columns)))
	var atlas_indices: PackedByteArray = PackedByteArray()
	atlas_indices.resize(atlas_width * rows * Gen2Tiles.TILE_PIXELS)
	atlas_indices.fill(1)
	var atlases: Dictionary = manifest.get("atlases", {})
	for name: String in ["front", "back"]:
		RomCache.write_indices(RomCache.pic_path(directory, name), atlas_indices)
		atlases[name] = {
			"width": atlas_width,
			"height": rows * cell,
			"cell": cell,
			"columns": columns,
			"rows": rows,
		}
	manifest["atlases"] = atlases


static func _text(text: String) -> Array:
	var out: Array = [Gen2WorldScript.TEXT_START]
	for byte: int in Gen2Text.encode(text):
		out.append(byte)
	out.append(Gen2WorldScript.TEXT_TERMINATOR)
	return out
