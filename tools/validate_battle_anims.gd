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

## `NUM_BATTLE_BG_EFFECTS` in each pin, and the id the two lists part company on.
## pokegold ships no `BATTLE_BG_EFFECT_BODY_SLAM`, so from here its own list runs
## one lower and `..._ROLLOUT` sits at $2d rather than $2e.
const BG_EFFECTS_CRYSTAL: int = 54
const BG_EFFECTS_GOLD: int = 53
const BODY_SLAM_EFFECT: int = 0x25
const ROLLOUT_EFFECT_CRYSTAL: int = 0x2E
const ROLLOUT_EFFECT_GOLD: int = 0x2D

## Well past the longest shipped animation, which is 365 frames.
const MAX_FRAMES: int = 4096

## The `BattleAnimSineWave` entry that pins the table as imported: a quarter turn
## is sin(pi/2), which `sine_table 32` evaluates to a full $0100. Any eight-bit
## re-derivation answers $00ff here and is wrong by one everywhere it is used.
const SINE_QUARTER: int = 16
const SINE_ONE: int = 0x0100

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_regions(game_id, data)
		_verify_sine(game_id, data)
		_verify_pound(game_id, data)
		_verify_profile_split(game_id, data)
		_verify_objects(game_id, data)
		_verify_palettes(game_id, data)
		_verify_gfx(game_id, data)
		_run_every_animation(game_id, data)
		_play_every_animation(game_id, data)
	_finish()


## Every animation played through [Gen2BattleAnimPlayer], which is the script
## plus the object pool, the tile window and the shadow OAM.
##
## Nothing here asserts what an animation looks like; what it pins is that all
## 278 spawn, step and retire their objects inside the cartridge's own limits,
## and it prints the inventory of what is still to build.
func _play_every_animation(game_id: StringName, data: GameData) -> void:
	var anims: Gen2BattleAnimData = Gen2BattleAnimData.from_game_data(data)
	if not _check(anims != null, "%s: no battle animation data in the cache." % game_id):
		return
	var objects: int = 0
	var sprites: int = 0
	var leaked: int = 0
	var functions: Dictionary = {}
	var effects: Dictionary = {}
	var live: int = 0
	var reached: int = 0
	var windows: int = 0
	var remaps: int = 0
	var edits: int = 0
	for index: int in anims.count(&"scripts"):
		for enemy_turn: bool in [false, true]:
			var player: Gen2BattleAnimPlayer = Gen2BattleAnimPlayer.create(
				anims, index, enemy_turn
			)
			if not _check(
				player != null, "%s: animation %d would not start." % [game_id, index]
			):
				continue
			var blank: PackedByteArray = player.background().bg_map.duplicate()
			var opened: bool = false
			var remapped: bool = false
			var frames: int = 0
			while player.advance_frame() and frames < MAX_FRAMES:
				frames += 1
				objects = maxi(objects, player.objects().size())
				sprites = maxi(sprites, player.sprites().size())
				live = maxi(live, player.bg_effects().size())
				reached += player.bg_effects().size()
				opened = opened \
					or player.background().lcdc_pointer != 0 \
					or player.background().scx != 0 \
					or player.background().scy != 0
				remapped = remapped or player.background().palettes_dirty
			windows += 1 if opened else 0
			remaps += 1 if remapped else 0
			edits += 1 if player.background().bg_map != blank else 0
			_check(
				not player.failed(),
				"%s: animation %d ran off its region." % [game_id, index]
			)
			# How many objects are still standing at the top-level `anim_ret`.
			# Not expected to be zero: `PlayBattleAnim` returns with the structs
			# as they are and the next animation's `ClearBattleAnims` zeroes
			# them, so an object nothing retired outlives its own script.
			leaked = maxi(leaked, player.objects().size())
			var missing: Dictionary = player.unimplemented()
			for id: int in missing["functions"]:
				functions[id] = int(functions.get(id, 0)) + 1
			for id: int in missing["bg_effects"]:
				effects[id] = int(effects.get(id, 0)) + 1
	_check(
		objects <= Gen2BattleAnimPlayer.MAX_OBJECTS,
		"%s: %d objects at once, past the %d slots." % [
			game_id, objects, Gen2BattleAnimPlayer.MAX_OBJECTS,
		]
	)
	_check(
		sprites <= Gen2BattleAnimPlayer.MAX_SPRITES,
		"%s: %d sprites at once, past the hardware's %d." % [
			game_id, sprites, Gen2BattleAnimPlayer.MAX_SPRITES,
		]
	)
	_check(
		functions.is_empty(),
		"%s: %d motion callbacks are still unbuilt: %s." % [
			game_id, functions.size(), functions.keys(),
		]
	)
	_check(
		effects.is_empty(),
		"%s: %d bg effects are still unbuilt: %s." % [
			game_id, effects.size(), effects.keys(),
		]
	)
	_check(
		reached > 0 and windows > 0 and remaps > 0 and edits > 0,
		"%s: the bg effects ran but produced nothing: %d queued, %d scanline windows, %d palette remaps, %d tilemap edits." % [
			game_id, reached, windows, remaps, edits,
		]
	)
	print("%s: %d bg effect slots used at once; %d animations opened a scanline window, %d remapped a palette, %d edited the tilemap." % [
		game_id, live, windows, remaps, edits,
	])
	print("%s: played %d animations both ways; at most %d objects and %d sprites at once." % [
		game_id, anims.count(&"scripts"), objects, sprites,
	])
	print("%s: still to build, %d motion callbacks and %d bg effects; at most %d objects still live at the end." % [
		game_id, functions.size(), effects.size(), leaked,
	])


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


## `BattleAnimSineWave` as it was imported, and the one entry that says it was
## imported rather than derived: sin(pi/2) is a full $0100 and not $00ff.
func _verify_sine(game_id: StringName, data: GameData) -> void:
	var table: PackedByteArray = data.battle_anim_sine()
	if not _check(
		table.size() == RomLayout.BATTLE_ANIM_SINE_BYTES,
		"%s: sine table holds %d bytes, not %d." % [
			game_id, table.size(), RomLayout.BATTLE_ANIM_SINE_BYTES,
		]
	):
		return
	for index: int in table.size():
		if not _check(
			table[index] == int(RomLayout.BATTLE_ANIM_SINE_WAVE[index]),
			"%s: sine byte %d is $%02X, not the pinned $%02X." % [
				game_id, index, table[index], int(RomLayout.BATTLE_ANIM_SINE_WAVE[index]),
			]
		):
			return
	var anims: Gen2BattleAnimData = Gen2BattleAnimData.create({}, [], table)
	_check(
		anims.sine_word(SINE_QUARTER) == SINE_ONE,
		"%s: sine quarter turn is $%04X, not the $%04X only the cartridge's own table gives." % [
			game_id, anims.sine_word(SINE_QUARTER), SINE_ONE,
		]
	)
	print("%s: %d-sample sine table, quarter turn $%04X." % [
		game_id, RomLayout.BATTLE_ANIM_SINE_SAMPLES, anims.sine_word(SINE_QUARTER),
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
	_verify_bg_effect_table(game_id)


## The other half of that split: the same id names a different effect in the two
## games from $25 on, so the two `BattleBGEffects` tables are kept whole and
## nothing is normalised between them.
func _verify_bg_effect_table(game_id: StringName) -> void:
	var names: Array[StringName] = Gen2BattleAnimBgEffects.names_for(game_id)
	var crystal: bool = game_id == &"crystal"
	_check(
		names.size() == (BG_EFFECTS_CRYSTAL if crystal else BG_EFFECTS_GOLD),
		"%s: the bg effect table is %d long." % [game_id, names.size()]
	)
	_check(
		names[BODY_SLAM_EFFECT] == (&"body_slam" if crystal else &"wobble_mon"),
		"%s: bg effect $%02X is %s." % [game_id, BODY_SLAM_EFFECT, names[BODY_SLAM_EFFECT]]
	)
	_check(
		names[ROLLOUT_EFFECT_CRYSTAL if crystal else ROLLOUT_EFFECT_GOLD] == &"rollout",
		"%s: BATTLE_BG_EFFECT_ROLLOUT is not where the constants put it." % game_id
	)
	for id: int in BODY_SLAM_EFFECT:
		_check(
			names[id] == Gen2BattleAnimBgEffects.EFFECTS_CRYSTAL[id],
			"%s: bg effect $%02X differs below the split." % [game_id, id]
		)
	print("%s: %d bg effects, $%02X is %s." % [
		game_id, names.size(), BODY_SLAM_EFFECT, names[BODY_SLAM_EFFECT],
	])


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
