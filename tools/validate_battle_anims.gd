extends SceneTree

## Runs every battle animation out of a freshly imported real cache, on all
## three cartridges, and checks the four tables behind them.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## data/moves/animations.asm's BattleAnimations, data/battle_anims/objects.asm,
## framesets.asm, oam.asm and object_gfx.asm, and
## engine/battle_anims/anim_commands.asm's own interpreter.
##
## The real-cartridge counterpart to tests/unit/test_battle_anim_script.gd. What
## pins it is running all 278 to completion rather than spot checking: an
## operand width that is wrong by one byte still decodes, and only walking every
## body past every branch makes it fall over.
##
##   Godot --headless --path . -s res://tools/validate_battle_anims.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## `assert_table_length` in each pinned data file. All five are shared by the
## two pins: the only thing data/battle_anims differs on is nothing, and
## animations.asm differs only inside eight bodies.
const EXPECTED_COUNTS: Dictionary = {
	&"scripts": RomLayout.BATTLE_ANIM_SCRIPT_COUNT,
	&"objects": RomLayout.BATTLE_ANIM_OBJECT_COUNT,
	&"framesets": RomLayout.BATTLE_ANIM_FRAMESET_COUNT,
	&"oam_sets": RomLayout.BATTLE_ANIM_OAM_SET_COUNT,
}

## `BattleAnim_Pound`, decoded. The seven commands `anim_1gfx`, `anim_sound`,
## `anim_obj`, `anim_wait 6`, `anim_obj`, `anim_wait 16`, `anim_ret`, as
## [code][name, operands][/code].
const EXPECTED_POUND: Array = [
	[&"gfx_1", [0x01]],
	[&"sound", [0x01, 0x31]],
	[&"obj", [0x08, 136, 56, 0x00]],
	[&"wait", [6]],
	[&"obj", [0x01, 136, 56, 0x00]],
	[&"wait", [16]],
	[&"ret", []],
]

## `BattleAnim_Dummy`, which entry 0 and three of the four padding entries share.
const DUMMY_INDEX: int = 0
const POUND_INDEX: int = 1

## Both shapes the profile split in data/moves/animations.asm takes, as the
## whole `anim_bgeffect` sequence of the animation that shows each. Neither is
## reachable without following the animation properly: every one of these
## sequences opens and closes inside a subroutine.
##
## TACKLE shows the split in which routine is called: Crystal calls
## `BattleAnim_TargetObj_2Row` and Gold and Silver `..._1Row`, and the two
## differ only in the effect they run, `BATTLE_BG_EFFECT_BATTLEROBJ_2ROW` ($12)
## against `..._1ROW` ($11). Its own `BATTLE_BG_EFFECT_TACKLE` ($24) and the
## closing `BattleAnim_ShowMon_0`'s `..._SHOW_MON` ($0a) are shared.
const TACKLE_INDEX: int = 0x21
const TACKLE_BG_EFFECTS: Dictionary = {
	&"gold": [0x11, 0x24, 0x0A],
	&"silver": [0x11, 0x24, 0x0A],
	&"crystal": [0x12, 0x24, 0x0A],
}

## BODY SLAM shows the other shape, the same call on both profiles running a
## different constant: `BATTLE_BG_EFFECT_BODY_SLAM` ($25) is Crystal's and
## pokegold does not have that constant at all, so it runs
## `BATTLE_BG_EFFECT_TACKLE` ($24). That is where
## constants/battle_anim_constants.asm starts to diverge, and it is why a bg
## effect id is profile-local and is never normalised across the two.
const BODY_SLAM_INDEX: int = 0x22
const BODY_SLAM_BG_EFFECTS: Dictionary = {
	&"gold": [0x12, 0x22, 0x24, 0x0A],
	&"silver": [0x12, 0x22, 0x24, 0x0A],
	&"crystal": [0x12, 0x22, 0x25, 0x0A],
}

## What `_decode_sheets` decompressed: `AnimObjGFX` rows 1 to 39, whose tile
## counts sum to this in every dump. Rows 0, 40 and 41 have no sheet.
const EXPECTED_GFX_SHEETS: int = 39
const EXPECTED_GFX_TILES: int = 659

## Well past the longest shipped animation, which is 365 frames.
const MAX_FRAMES: int = 4096

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_regions(game_id, data)
		_verify_pound(game_id, data)
		_verify_profile_split(game_id, data)
		_verify_objects(game_id, data)
		_verify_palettes(game_id, data)
		_verify_gfx(game_id, data)
		_run_every_animation(game_id, data)
	_finish()


func _verify_regions(game_id: StringName, data: GameData) -> void:
	for name: StringName in EXPECTED_COUNTS:
		var region: Dictionary = data.battle_anim_region(name)
		if not _check(not region.is_empty(), "%s: no %s region in the cache." % [game_id, name]):
			continue
		_check(
			int(region["count"]) == int(EXPECTED_COUNTS[name]),
			"%s: %s holds %d entries, not the pinned %d." % [
				game_id, name, int(region["count"]), int(EXPECTED_COUNTS[name]),
			]
		)
		_check(
			(region["data"] as PackedByteArray).size() > 0,
			"%s: %s region is empty." % [game_id, name]
		)
	print("%s: four regions, %d scripts over %d bytes." % [
		game_id,
		int(data.battle_anim_region(&"scripts")["count"]),
		(data.battle_anim_region(&"scripts")["data"] as PackedByteArray).size(),
	])


## Entry 1 command by command, and entry 0 as the bare `anim_ret` the table pads
## itself with.
func _verify_pound(game_id: StringName, data: GameData) -> void:
	var ran: Array = _run(data, POUND_INDEX)
	if not _check(
		ran.size() == EXPECTED_POUND.size(),
		"%s: POUND ran %d commands, not the pinned %d." % [
			game_id, ran.size(), EXPECTED_POUND.size(),
		]
	):
		return
	for index: int in ran.size():
		var got: Dictionary = ran[index]
		var want: Array = EXPECTED_POUND[index]
		_check(
			got["name"] == want[0] and Array(got["operands"]) == Array(want[1]),
			"%s: POUND command %d is %s %s, not %s %s." % [
				game_id, index, got["name"], got["operands"], want[0], want[1],
			]
		)

	var dummy: Array = _run(data, DUMMY_INDEX)
	_check(
		dummy.size() == 1 and dummy[0]["name"] == Gen2BattleAnimScript.RET,
		"%s: animation %d is not a bare anim_ret." % [game_id, DUMMY_INDEX]
	)
	print("%s: POUND decodes to its seven commands." % game_id)


func _verify_profile_split(game_id: StringName, data: GameData) -> void:
	_verify_bg_effects(game_id, data, "TACKLE", TACKLE_INDEX, TACKLE_BG_EFFECTS[game_id])
	_verify_bg_effects(
		game_id, data, "BODY SLAM", BODY_SLAM_INDEX, BODY_SLAM_BG_EFFECTS[game_id]
	)


func _verify_bg_effects(
	game_id: StringName, data: GameData, name: String, index: int, expected: Array
) -> void:
	var found: Array = []
	for command: Dictionary in _run(data, index):
		if command["name"] == &"bg_effect":
			found.append(int((command["operands"] as Array)[0]))
	_check(
		found == expected,
		"%s: %s runs bg effects %s, not the pinned %s." % [game_id, name, found, expected]
	)
	print("%s: %s runs %d bg effects, %s." % [
		game_id, name, found.size(), ", ".join(found.map(func(v: int) -> String: return "$%02X" % v)),
	])


## Every object row's four table indexes, which is what a wrong stride would
## break first.
func _verify_objects(game_id: StringName, data: GameData) -> void:
	var count: int = int(data.battle_anim_region(&"objects")["count"])
	var framesets: int = int(data.battle_anim_region(&"framesets")["count"])
	var used_gfx: Dictionary = {}
	for index: int in count:
		var row: Dictionary = data.battle_anim_object(index)
		if not _check(not row.is_empty(), "%s: object %d is missing." % [game_id, index]):
			return
		_check(
			int(row["frameset"]) < framesets,
			"%s: object %d names frameset %d of %d." % [
				game_id, index, int(row["frameset"]), framesets,
			]
		)
		_check(
			int(row["palette"]) < Gen2BattleAnimImporter.PALETTE_COUNT,
			"%s: object %d names palette %d." % [game_id, index, int(row["palette"])]
		)
		used_gfx[int(row["gfx"])] = true
	print("%s: %d objects reference %d of the %d graphics rows." % [
		game_id, count, used_gfx.size(), data.battle_anim_gfx_count(),
	])


## The eight palettes an object row can name. Only six are table rows; slots 0
## and 1 are whoever is on the field, so they are asked for with a pair and must
## answer with it rather than with the table.
func _verify_palettes(game_id: StringName, data: GameData) -> void:
	var enemy: Array = [0x1234, 0x5678]
	var player: Array = [0x0C63, 0x1084]
	_check(
		data.battle_object_palette(0, enemy, player)[1]
			== Gen2Palette.from_packed(enemy[0]),
		"%s: PAL_BATTLE_OB_ENEMY did not come from the battler's own pair." % game_id
	)
	_check(
		data.battle_object_palette(1, enemy, player)[1]
			== Gen2Palette.from_packed(player[0]),
		"%s: PAL_BATTLE_OB_PLAYER did not come from the battler's own pair." % game_id
	)
	for index: int in RomLayout.BATTLE_OBJECT_PALETTES_STORED:
		var slot: int = index + RomLayout.BATTLE_OBJECT_PALETTE_FIRST_STORED
		var colors: PackedColorArray = data.battle_object_palette(slot)
		var wanted: Array = RomLayout.BATTLE_OBJECT_PALETTES[index]
		if not _check(
			colors.size() == RomLayout.BATTLE_OBJECT_PALETTE_COLORS,
			"%s: object palette %d has %d colours." % [game_id, slot, colors.size()]
		):
			continue
		for colour: int in wanted.size():
			_check(
				colors[colour] == Gen2Palette.from_packed(int(wanted[colour])),
				"%s: object palette %d colour %d is not the pinned $%04X." % [
					game_id, slot, colour, int(wanted[colour]),
				]
			)
	print("%s: %d object palettes, plus the two the battlers supply." % [
		game_id, RomLayout.BATTLE_OBJECT_PALETTES_STORED,
	])


func _verify_gfx(game_id: StringName, data: GameData) -> void:
	var sheets: int = 0
	var tiles: int = 0
	for index: int in data.battle_anim_gfx_count():
		var row: Dictionary = data.battle_anim_gfx(index)
		if not bool(row["sheet"]):
			continue
		sheets += 1
		tiles += int(row["tiles"])
		var indices: PackedByteArray = data.battle_anim_gfx_indices(index)
		_check(
			indices.size() == int(row["tiles"]) * Gen2Tiles.TILE_PIXELS,
			"%s: graphics %d decoded %d pixels for %d tiles." % [
				game_id, index, indices.size(), int(row["tiles"]),
			]
		)
	_check(
		sheets == EXPECTED_GFX_SHEETS and tiles == EXPECTED_GFX_TILES,
		"%s: %d graphics sheets over %d tiles, not the pinned %d over %d." % [
			game_id, sheets, tiles, EXPECTED_GFX_SHEETS, EXPECTED_GFX_TILES,
		]
	)
	print("%s: %d graphics sheets, %d tiles." % [game_id, sheets, tiles])


## All 278, run to a top-level `anim_ret`. Nothing may fail, and nothing may
## reach [constant MAX_FRAMES].
func _run_every_animation(game_id: StringName, data: GameData) -> void:
	var region: Dictionary = data.battle_anim_region(&"scripts")
	var count: int = int(region["count"])
	var commands: int = 0
	var longest: int = 0
	var longest_index: int = -1
	var sounds: int = 0
	for index: int in count:
		var script: Gen2BattleAnimScript = _script(data, index)
		if not _check(script != null, "%s: animation %d has no address." % [game_id, index]):
			continue
		var frames: int = 0
		while not script.finished() and frames < MAX_FRAMES:
			frames += 1
			for command: Dictionary in script.advance_frame():
				commands += 1
				if command["name"] == Gen2BattleAnimScript.SOUND:
					sounds += 1
		_check(
			not script.failed(),
			"%s: animation %d ran off its region." % [game_id, index]
		)
		_check(
			script.finished(),
			"%s: animation %d never reached anim_ret in %d frames." % [
				game_id, index, MAX_FRAMES,
			]
		)
		if frames > longest:
			longest = frames
			longest_index = index
	print("%s: %d animations ran %d commands, %d of them anim_sound; longest %d frames (%d)." % [
		game_id, count, commands, sounds, longest, longest_index,
	])


func _run(data: GameData, index: int) -> Array:
	var script: Gen2BattleAnimScript = _script(data, index)
	if script == null:
		return []
	var out: Array = []
	var frames: int = 0
	while not script.finished() and frames < MAX_FRAMES:
		frames += 1
		out.append_array(script.advance_frame())
	return out


func _script(data: GameData, index: int) -> Gen2BattleAnimScript:
	var region: Dictionary = data.battle_anim_region(&"scripts")
	var address: int = data.battle_anim_address(index)
	if region.is_empty() or address < 0:
		return null
	return Gen2BattleAnimScript.create(region["data"], int(region["address"]), address)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS battle anims: every animation ran, four tables and the graphics verified.")
		quit(0)
		return
	for message: String in _failures:
		print("FAIL %s" % message)
	quit(1)
