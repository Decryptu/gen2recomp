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
const WIN_TEXT: int = 0x7000
const LOSS_TEXT: int = 0x7010
const TRAINER_FLAG: int = 7
const TRAINER_SPECIES: int = 16
const TRAINER_SPRITE: int = 1


static func directory() -> String:
	return RomCache.directory_for(GAME_ID, SHA1)


static func build() -> GameData:
	var directory: String = directory()
	var base: GameData = BattleFixture.build(directory)
	assert(base != null)

	var manifest: Dictionary = RomCache.read_manifest(directory)
	_write_trainers(directory)
	_write_world(directory)
	_write_overworld_graphics(directory)
	_write_battle_graphics(directory, manifest)
	manifest["game_id"] = String(GAME_ID)
	manifest["sha1"] = SHA1
	manifest["complete"] = true
	RomCache.write_json(RomCache.manifest_path(directory), manifest)
	return GameData.open_directory(directory)


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


static func _write_world(directory: String) -> void:
	var blocks: Array = []
	blocks.resize(MAP_WIDTH_BLOCKS * MAP_HEIGHT_BLOCKS)
	blocks.fill(0)
	var collision: Array = []
	collision.resize(MAP_WIDTH_CELLS * MAP_HEIGHT_CELLS)
	collision.fill(0)

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
	}]
	var map: Dictionary = {
		"group": MAP_GROUP,
		"number": MAP_NUMBER,
		"tileset": 0,
		"environment": 0,
		"width_blocks": MAP_WIDTH_BLOCKS,
		"height_blocks": MAP_HEIGHT_BLOCKS,
		"blocks": blocks,
		"collision": collision,
		"collision_width": MAP_WIDTH_CELLS,
		"collision_height": MAP_HEIGHT_CELLS,
		"scripts": {"bank": BANK, "callbacks": []},
		"events": {"bank": BANK, "objects": objects},
	}
	RomCache.write_json(RomCache.world_maps_path(directory), [map])

	var script: Array = [
		0x5E, 1, 0,
		0x64, WIN_TEXT & 0xFF, WIN_TEXT >> 8, LOSS_TEXT & 0xFF, LOSS_TEXT >> 8,
		0x5F,
		0x33, TRAINER_FLAG & 0xFF, TRAINER_FLAG >> 8,
		0x60,
		0x91,
	]
	RomCache.write_json(RomCache.world_scripts_path(directory), {
		Gen2WorldScript.pointer_key(BANK, TRAINER_SCRIPT): script,
	})
	RomCache.write_json(RomCache.world_text_path(directory), {
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
			"first_code": RomLayout.FONT_FIRST_CODE if name == "font" else 0,
			"bits": 1,
		}
	manifest["tiles"] = sheets
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
	out.append(Gen2Text.TERMINATOR)
	return out
