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
## The fixture's copyright strip, shorter than either cartridge's so a page test
## can name every tile in it.
const COPYRIGHT_TILES: int = 4
const MAP_WIDTH_CELLS: int = MAP_WIDTH_BLOCKS * 2
const MAP_HEIGHT_CELLS: int = MAP_HEIGHT_BLOCKS * 2
const TRAINER_SCRIPT: int = 0x6100
const TUTORIAL_SCRIPT: int = 0x6110
const SEEN_TEXT: int = 0x6FF0
const WIN_TEXT: int = 0x7000
const LOSS_TEXT: int = 0x7010
const TRAINER_FLAG: int = 8
## The fixture's two region maps, each a flat fill of one `TownMapGFX` tile so a
## page test can tell which was drawn. Both are even, so `TownMapPals` gives
## them the earth palette.
const TOWN_MAP_JOHTO_TILE: int = 0x02
const TOWN_MAP_KANTO_TILE: int = 0x04
const TOWN_MAP_EARTH: int = 1
const TOWN_MAP_MOUNTAIN: int = 2
## `<BSP>`, which `TownMap_ConvertLineBreakCharacters` rewrites as `<LF>`.
const TOWN_MAP_BREAK_CODE: int = 0x1F
## The landmark each of the fixture's two maps reports, so `FindNest` has one map
## per region to walk. The second is a Kanto number on a Johto map, which no
## cartridge does and every region-split test needs.
const MAP_LANDMARK: int = 1
const HOME_MAP_LANDMARK: int = 47
## The middle of the nest icon landmark 1 takes, which is its own stored point
## less the four `.nestloop` subtracts from both coordinates.
const NEST_ICON_PIXEL: Vector2i = Vector2i(138, 98)
## `OakRatings`' own thresholds (data/events/pokedex_ratings.asm), and a first
## sfx id the rest count up from so a row's sound identifies it.
const OAK_THRESHOLDS: Array[int] = [
	9, 19, 34, 49, 64, 79, 94, 109, 124, 139, 154, 169, 184, 199, 214, 229,
	239, 248, 255,
]
const OAK_FIRST_SFX: int = 40
## The fixture's `CreditsStringsPointers`: two names, the copyright and the
## heading, which is the smallest table `ParseCredits`' two branches both need.
const CREDITS_NAME_A: int = 0
const CREDITS_NAME_B: int = 1
const CREDITS_COPYRIGHT: int = 2
const CREDITS_STAFF: int = 3
const CREDITS_STRING_COUNT: int = 4
## The banner strip is filled so a tile's index is the block it belongs to,
## modulo the four an index can hold, which is how a page test says which frame
## is on screen.
const CREDITS_BLOCK_INDEXES: int = 4
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
	_write_splash_graphics(directory, manifest, game_id == RomRegistry.CRYSTAL)
	_write_menu_text(manifest)
	_write_pokecenter_pc(manifest)
	_write_unown_words(manifest)
	_write_credits(directory, manifest, crystal_commands)
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
	collision[7 * MAP_WIDTH_CELLS + 8] = 0x29

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
		"location": MAP_LANDMARK,
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
	home_map["location"] = HOME_MAP_LANDMARK
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
	var home_key: String = "%d:%d" % [
		Gen2WorldSpawn.NEW_BARK_GROUP, Gen2WorldSpawn.PLAYERS_HOUSE_2F,
	]
	RomCache.write_json(RomCache.world_encounters_path(directory), {
		"grass": {"1:1": {
			"map": "1:1", "region": "johto", "rates": [255, 255, 255], "slots": grass_times,
		}},
		## One water row in the other region, which is what `FindNest`'s two
		## walks are told apart by. Its rate is zero, so nothing surfs into it.
		"water": {home_key: {
			"map": home_key, "region": "kanto", "rate": 0,
			"slots": [{"level": 5, "species": TRAINER_SPECIES}],
		}},
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


## The start menu's nine descriptions and the pack's five texts, as the cartridge
## words them. The two toss texts keep [Gen2TextStream]'s markers, since what
## fills them is only known while the box is up.
static func _write_menu_text(manifest: Dictionary) -> void:
	manifest["menu_text"] = {
		"descriptions": {
			"pokedex": "POKéMON\ndatabase",
			"pokemon": "Party PKMN\nstatus",
			"pack": "Contains\nitems",
			"pokegear": "Trainer's\nkey device",
			"player": "Your own\nstatus",
			"save": "Save your\nprogress",
			"option": "Change\nsettings",
			"exit": "Close this\nmenu",
			"quit": "Quit and\nbe judged.",
		},
		"oak_no_time": "OAK: <PLAYER>!\nThis isn't the\ntime to use that!",
		"no_mon": "You don't have a\nPOKéMON!",
		"toss_ask": "Throw away how\nmany?",
		"toss_ask_quantity": "Throw away <NUM_D009>\n<RAM_CF7E>(S)?",
		"toss_threw": "Threw away\n<RAM_CF7E>(S).",
	}


## `PokemonCenterPC`'s two row runs, its `.WhichPC` lists and the six texts the
## routine prints, as the cartridge words them.
## One word per Unown form, each opening on its own letter the way
## `UnownWords`' do, so a test can tell which form the dex is showing.
static func _write_unown_words(manifest: Dictionary) -> void:
	var words: Array = []
	for form: int in RomLayout.UNOWN_FORMS:
		words.append("%sWORD" % char("A".unicode_at(0) + form))
	manifest["unown_words"] = words


static func _write_pokecenter_pc(manifest: Dictionary) -> void:
	manifest["pokecenter_pc"] = {
		"rows": {
			"players_pc": "<PLAYER>'s PC", "bills_pc": "BILL's PC",
			"oaks_pc": "PROF.OAK's PC", "hall_of_fame": "HALL OF FAME",
			"turn_off": "TURN OFF",
		},
		"lists": [[1, 0, 4], [1, 0, 2, 4], [1, 0, 2, 3, 4]],
		"players_rows": {
			"withdraw_item": "WITHDRAW ITEM", "deposit_item": "DEPOSIT ITEM",
			"toss_item": "TOSS ITEM", "mail_box": "MAIL BOX",
			"decoration": "DECORATION", "turn_off": "TURN OFF",
			"log_off": "LOG OFF",
		},
		"players_lists": [[0, 1, 2, 3, 5], [0, 1, 2, 3, 4, 6]],
		"texts": {
			"ask_what_do": "What do you want\nto do?",
			"how_many_withdraw": "How many do you\nwant to withdraw?",
			"withdrew": "Withdrew <NUM_D10C>\n<RAM_D086>(S).",
			"no_room_withdraw": "There's no room\nfor more items.",
			"no_items": "No items here!",
			"how_many_deposit": "How many do you\nwant to deposit?",
			"deposited": "Deposited <NUM_D10C>\n<RAM_D086>(S).",
			"no_room_deposit": "There's no room to\nstore items.",
			"turn_on": "<PLAYER> turned on\nthe PC.",
			"whose": "Access whose PC?",
			"bills_pc": "BILL's PC\naccessed.",
			"players_pc": "Accessed own PC.",
			"oaks_pc": "PROF.OAK's PC\naccessed.",
			"closed": "…\nLink closed…",
		},
	}


## A short `CreditsScript` reaching every command, its four strings, the four
## scene palettes and `Credits_LoadBorderGFX.Frames`. The two profiles differ the
## way the cartridges do: Crystal gives a scene three palettes and sixteen banner
## blocks, Gold and Silver one palette and thirteen.
static func _write_credits(
	directory: String, manifest: Dictionary, crystal: bool
) -> void:
	var frames: Array = []
	if crystal:
		for block: int in RomLayout.CREDITS_SCENES * RomLayout.CREDITS_SCENE_FRAMES:
			frames.append(block)
	else:
		for scene: int in RomLayout.CREDITS_SCENES - 1:
			frames.append_array([scene * 3, scene * 3 + 1, scene * 3, scene * 3 + 2])
		frames.append_array([9, 10, 11, 12])
	## `GetCreditsPalette.UpdatePals` copies 24 bytes on Crystal and 8 twice on
	## the other two, which is three palettes against one.
	var scene_palettes: int = 3 if crystal else 1
	var palettes: Array = []
	for colour: int in RomLayout.CREDITS_SCENES * scene_palettes \
		* RomLayout.CREDITS_PALETTE_COLORS:
		palettes.append(0x0400 * (colour % 4) + colour)
	manifest["credits"] = {
		"script": [
			RomLayout.CREDITS_CLEAR,
			CREDITS_STAFF, 1,
			RomLayout.CREDITS_WAIT, 2,
			RomLayout.CREDITS_MUSIC,
			RomLayout.CREDITS_WAIT2, 1,
			RomLayout.CREDITS_WAIT, 1,
			RomLayout.CREDITS_SCENE, 1,
			CREDITS_NAME_A, 0,
			CREDITS_NAME_B, 2,
			RomLayout.CREDITS_WAIT, 2,
			CREDITS_COPYRIGHT, 1,
			RomLayout.CREDITS_WAIT, 1,
			RomLayout.CREDITS_THEEND,
			RomLayout.CREDITS_WAIT, 1,
			RomLayout.CREDITS_END,
		],
		"strings": [
			[0x80, 0x81, 0x82],
			[0x83, 0x84],
			## The copyright is the one string drawn out of `CopyrightGFX` and
			## the one printed from column 2.
			[
				RomLayout.COPYRIGHT_FIRST_CODE, RomLayout.COPYRIGHT_FIRST_CODE + 1,
				Gen2Credits.CODE_NEXT_LINE,
				RomLayout.COPYRIGHT_FIRST_CODE + 2,
			],
			## `#` and a `<NEXT>`, which are the two things `PlaceString` does
			## that placing a code does not.
			[Gen2Credits.CODE_POKE, 0x85, Gen2Credits.CODE_NEXT_LINE, 0x86],
		],
		"staff": CREDITS_STAFF,
		"copyright": CREDITS_COPYRIGHT,
		"scene_palettes": scene_palettes,
		"palettes": palettes,
		"frames": frames,
	}
	var sheets: Dictionary = manifest.get("tiles", {})
	var blocks: int = int(frames.max()) + 1
	for entry: Array in [
		["credits_border", RomLayout.CREDITS_BORDER_TILES, RomLayout.CREDITS_BORDER_FIRST_CODE],
		["credits_the_end", RomLayout.CREDITS_THE_END_TILES, RomLayout.CREDITS_THE_END_FIRST_CODE],
		["credits_mons", blocks * RomLayout.CREDITS_MON_FRAME_TILES, 0],
	]:
		var count: int = int(entry[1])
		var indices := PackedByteArray()
		indices.resize(count * Gen2Tiles.TILE_PIXELS)
		for tile: int in count:
			@warning_ignore("integer_division")
			var block: int = tile / RomLayout.CREDITS_MON_FRAME_TILES
			var index: int = block % CREDITS_BLOCK_INDEXES if entry[0] == "credits_mons" else 2
			for pixel: int in Gen2Tiles.TILE_PIXELS:
				## The strips are strips, so a tile's pixels are a column of the
				## row rather than a run of it.
				var y: int = pixel / Gen2Tiles.TILE_WIDTH
				indices[y * count * Gen2Tiles.TILE_WIDTH
					+ tile * Gen2Tiles.TILE_WIDTH + pixel % Gen2Tiles.TILE_WIDTH] = index
		RomCache.write_indices(RomCache.tile_path(directory, String(entry[0])), indices)
		sheets[String(entry[0])] = {
			"width": count * Gen2Tiles.TILE_WIDTH,
			"height": Gen2Tiles.TILE_HEIGHT,
			"tiles": count,
			"first_code": int(entry[2]),
			"bits": 2,
		}
	manifest["tiles"] = sheets


## `GameFreakLogoGFX` and whichever object sheet the profile carries, as flat
## fills: what a page test checks is which tile lands where, not what is in it.
## The words below name the strip's own first tiles, so the ink index matters and
## the picture does not.
static func _write_splash_graphics(
	directory: String, manifest: Dictionary, crystal: bool
) -> void:
	var sheets: Dictionary = manifest.get("tiles", {})
	## The 1bpp logo carries `Gen2Tiles.INK`, since that is the only index a 1bpp
	## graphic ever decodes to. The object sheets carry the Ditto fade's own
	## colour, which is the one both profiles' sprites are mostly drawn in and
	## the one `GameFreakLogo_Transform` moves.
	var counts: Dictionary = {
		"game_freak_logo": [RomLayout.PRESENTS_GFX_TILES, Gen2Tiles.INK],
	}
	if crystal:
		counts["game_freak_ditto"] = [
			RomLayout.PRESENTS_DITTO_TILES, RomLayout.PRESENTS_DITTO_FADE_COLOR,
		]
	else:
		counts["game_freak_stars"] = [
			RomLayout.PRESENTS_STARS_TILES, RomLayout.PRESENTS_DITTO_FADE_COLOR,
		]
	for name: String in counts:
		var tile_count: int = int(counts[name][0])
		var indices: PackedByteArray = PackedByteArray()
		indices.resize(tile_count * Gen2Tiles.TILE_PIXELS)
		indices.fill(int(counts[name][1]))
		RomCache.write_indices(RomCache.tile_path(directory, name), indices)
		sheets[name] = {
			"width": tile_count * Gen2Tiles.TILE_WIDTH,
			"height": Gen2Tiles.TILE_HEIGHT,
			"tiles": tile_count,
			"first_code": 0,
			"bits": 1 if name == "game_freak_logo" else 2,
		}
	manifest["tiles"] = sheets
	## PREDEFPAL_GAMEFREAK_LOGO_OB, and on Crystal `gfx/splash/ditto.pal` with the
	## sixteen-step fade, all as the cartridge stores them.
	var palettes: Dictionary = {"object": [0x7FFF, 0x7FFF, 0x03D9, 0x03D9]}
	if crystal:
		palettes["ditto"] = [0x7FFF, 0x016D, 0x7197, 0x0000]
		var fade: Array = []
		for step: int in RomLayout.PRESENTS_DITTO_FADE_COLORS:
			fade.append(0x7197 - step)
		palettes["ditto_fade"] = fade
	manifest["presents_palettes"] = palettes


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
		## `CopyrightGFX`, four tiles rather than the cartridge's twenty-nine:
		## the string below names those four, and what a test checks is where
		## each lands.
		"copyright": [COPYRIGHT_TILES, 3],
		## `Pokegear_LoadGFX`'s three sheets, at their real lengths so a page can
		## address every tile a region map or a card frame names.
		"town_map": [RomLayout.TOWN_MAP_TILES, 1],
		"pokegear": [RomLayout.POKEGEAR_TILES, 2],
		"pokegear_sprites": [RomLayout.POKEGEAR_SPRITE_TILES, 3],
		"dex_nest_icon": [RomLayout.DEX_NEST_ICON_TILES, 3],
	}
	## The font and the frames are the two sheets addressed by character code
	## rather than by slot, so both need their real first code. A frames sheet
	## left on 0 draws nothing at all, since every box-drawing code is then past
	## the end of the strip.
	var first_codes: Dictionary = {
		"font": RomLayout.FONT_FIRST_CODE,
		"frames": RomLayout.FRAME_FIRST_CODE,
		"copyright": RomLayout.COPYRIGHT_FIRST_CODE,
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
	## `CopyrightString`'s shape: three `next`-separated rows of the strip's own
	## codes, and PREDEFPAL_GAMEFREAK_LOGO_BG, whose first colour is black.
	var copyright_string: Array = []
	for row: int in RomLayout.COPYRIGHT_STRING_ROWS:
		if row > 0:
			copyright_string.append(RomLayout.COPYRIGHT_STRING_NEXT)
		for index: int in COPYRIGHT_TILES:
			copyright_string.append(RomLayout.COPYRIGHT_FIRST_CODE + index)
	manifest["copyright_string"] = copyright_string
	manifest["copyright_palette"] = [0x0000, 0x2D68, 0x56B5, 0x7FFF]
	manifest["bar_palettes"] = {
		"hp_green": [0x02E0, 0x02E0],
		"hp_yellow": [0x02BF, 0x02BF],
		"hp_red": [0x001F, 0x001F],
		"exp": [0x7E24, 0x7E24],
	}
	manifest["town_map"] = _town_map()
	manifest["oak_ratings"] = _oak_ratings()

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


## `OakRatings` and the four texts around it, at the real table's shape. The
## thresholds are the cartridge's own, since what a test checks is the band a
## caught count lands in; the texts are short stand-ins.
static func _oak_ratings() -> Dictionary:
	var rows: Array = []
	for index: int in RomLayout.OAK_RATING_COUNT:
		rows.append({
			"threshold": OAK_THRESHOLDS[index],
			"sfx": OAK_FIRST_SFX + index,
			"text": "RATING%02d" % (index + 1),
		})
	return {
		"ask": "RATE?",
		"level": "LEVEL:",
		"counts": "<RAM_D099> SEEN\n<RAM_D0AC> OWNED",
		"closed": "CLOSED.",
		"ratings": rows,
	}


## `JohtoMap`, `KantoMap`, `TownMapPals` and `Landmarks`, at their real shapes.
## The two region maps are flat fills of one tile each so a page test can tell
## which one was drawn, and each landmark is placed on its own cell so a cursor
## position is checkable; only the two named below carry real coordinates and a
## line break, which is what the name box is tested with.
static func _town_map() -> Dictionary:
	var johto: Array = []
	var kanto: Array = []
	for cell: int in RomLayout.TOWN_MAP_REGION_CELLS:
		johto.append(TOWN_MAP_JOHTO_TILE)
		kanto.append(TOWN_MAP_KANTO_TILE)
	var palette_map: Array = []
	for index: int in RomLayout.TOWN_MAP_PALETTE_MAP_BYTES:
		## Every even tile earth, every odd one mountain, so a tile's palette is
		## a function of its number and nothing else.
		palette_map.append((TOWN_MAP_MOUNTAIN << 4) | TOWN_MAP_EARTH)
	var palettes: Array = []
	var palettes_female: Array = []
	for slot: int in RomLayout.TOWN_MAP_PALETTES:
		for index: int in RomLayout.TOWN_MAP_PALETTE_COLORS:
			palettes.append(RomLayout.TOWN_MAP_PALETTE_FIRST_COLOR if index == 0 else slot)
			palettes_female.append(
				RomLayout.TOWN_MAP_PALETTE_FIRST_COLOR if index == 0 else slot + 0x100
			)
	var landmarks: Array = []
	for index: int in RomLayout.LANDMARK_COUNT:
		landmarks.append({"x": index, "y": index, "codes": _codes("SPECIAL")})
	landmarks[1] = {"x": 140, "y": 100, "codes": _codes("NEW BARK<BSP>TOWN")}
	landmarks[2] = {"x": 128, "y": 100, "codes": _codes("ROUTE 29")}
	## The three card tilemaps, each a flat fill of the Pokegear sheet's own
	## blank: a card test reads what the page draws over one, never the art.
	var cards: Dictionary = {}
	for card: String in RomLayout.POKEGEAR_CARD_ORDER:
		var cells: Array = []
		for cell: int in RomLayout.POKEGEAR_CARD_CELLS:
			cells.append(Gen2TownMapPage.CARD_BLANK_TILE)
		cards[card] = cells
	return {
		"johto": johto,
		"kanto": kanto,
		"palette_map": palette_map,
		"palettes": palettes,
		"palettes_female": palettes_female,
		"landmarks": landmarks,
		"cards": cards,
		"card_texts": {
			"ask_who": "WHOM TO CALL?", "press_button": "PRESS A BUTTON",
			"ask_delete": "DELETE THIS NUMBER?",
		},
	}


## A landmark name as `GetLandmarkName` copies it, with `<BSP>` written out.
static func _codes(name: String) -> Array:
	var out: Array = []
	for part: String in name.split("<BSP>"):
		if not out.is_empty():
			out.append(TOWN_MAP_BREAK_CODE)
		for code: int in Gen2Text.encode(part):
			out.append(code)
	return out


static func _text(text: String) -> Array:
	var out: Array = [Gen2WorldScript.TEXT_START]
	for byte: int in Gen2Text.encode(text):
		out.append(byte)
	out.append(Gen2WorldScript.TEXT_TERMINATOR)
	return out
