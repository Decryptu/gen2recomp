extends RefCounted

var _r: RefCounted = null

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
##   Godot --headless --path . -s res://tools/validate.gd -- battle_anims


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


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_regions(game_id, data)
		_verify_sine(game_id, data)
		_verify_pound(game_id, data)
		_verify_profile_split(game_id, data)
		_verify_objects(game_id, data)
		_verify_palettes(game_id, data)
		_verify_gfx(game_id, data)
		_verify_substitute_pic(game_id, data)
		_run_every_animation(game_id, data)
		_play_every_animation(game_id, data)
		_verify_the_entrance(game_id, data)
		_verify_the_transition(game_id, data)


## The two bodies `BattleAnim_SendOutMon`'s parameter picks between, by the bg
## effects each runs: `.Normal` is `BATTLE_BG_EFFECT_ENTER_MON` alone and
## `.Shiny` is the inverted flash and the palette cycle. The beta body the fan
## falls through to runs `BATTLE_BG_EFFECT_BETA_SEND_OUT_MON2` ($2b), which is
## how a parameter that never reached the interpreter shows up here.
const SEND_OUT_EFFECTS: Dictionary = {0: [0x0B], 1: [0x01, 0x06]}
## And how long each takes: the two `anim_wait`s of `.Normal` and the ten of
## `.Shiny`, plus the frame each batch of commands between them spends.
const SEND_OUT_FRAMES: Dictionary = {0: 39, 1: 69}


## `ANIM_SEND_OUT_MON`, which every entrance plays and which nothing else in the
## corpus reaches with a parameter: `BattleAnim_SendOutMon` is an
## `anim_if_param_equal` fan, so the sweep above walks its `$0` body alone and
## the shiny branch is never decoded. Both are run here, on both sides, and the
## `SFX_SHINE` `BattleStartMessage` plays in front of a trainer's line is looked
## up in the audio index the way a track is.
func _verify_the_entrance(game_id: StringName, data: GameData) -> void:
	var anims: Gen2BattleAnimData = Gen2BattleAnimData.from_game_data(data)
	if not _r.check(anims != null, "%s: no battle animation data in the cache." % game_id):
		return
	for param: int in [Gen2Battle.SEND_OUT_ANIM_NORMAL, Gen2Battle.SEND_OUT_ANIM_SHINY]:
		for enemy_turn: bool in [false, true]:
			var player: Gen2BattleAnimPlayer = Gen2BattleAnimPlayer.create(
				anims, Gen2Battle.ANIM_SEND_OUT_MON, enemy_turn, param
			)
			if not _r.check(
				player != null,
				"%s: the send-out animation would not start at param %d." % [game_id, param]
			):
				continue
			var frames: int = 0
			var sprites: int = 0
			var effects: Array = []
			while player.advance_frame() and frames < MAX_FRAMES:
				frames += 1
				sprites = maxi(sprites, player.sprites().size())
				for effect: Gen2BattleAnimBgEffect in player.bg_effects():
					if not effects.has(effect.id):
						effects.append(effect.id)
			_r.check(
				not player.failed(),
				"%s: the send-out animation ran off its region at param %d." % [
					game_id, param,
				]
			)
			## Which body ran, not just that one did. `BattleAnim_SendOutMon` is
			## a fan of `anim_if_param_equal`, and a parameter that does not
			## reach the interpreter falls through to the beta branch, which is
			## four times as long and deforms the other battler.
			_r.check(
				effects == SEND_OUT_EFFECTS[param],
				"%s: param %d ran bg effects %s, not the pinned %s." % [
					game_id, param, effects, SEND_OUT_EFFECTS[param],
				]
			)
			_r.check(
				frames == SEND_OUT_FRAMES[param],
				"%s: param %d ran %d frames, not the pinned %d." % [
					game_id, param, frames, SEND_OUT_FRAMES[param],
				]
			)
			_r.check(
				sprites > 0,
				"%s: the send-out animation drew nothing at param %d on the %s side." % [
					game_id, param, "enemy" if enemy_turn else "player",
				]
			)
	_r.check(
		not data.world_audio(&"sfx", Gen2BattleScreen.SFX_SHINE).is_empty(),
		"%s: SFX_SHINE is not in the audio index, so a trainer battle opens silently." % game_id
	)
	print("%s: the entrance runs both send-out branches on both sides." % game_id)


## `DoBattleTransition` on a real cache: the two tiles it wipes with, the palette
## it floods the map with, and all four animations run to the end.
##
## The tiles are content whose value is known independently, which is what checks
## the address: one of them is solid colour 3 and the other is the chequered
## square, and no other pair of tiles in the dump is that.
func _verify_the_transition(game_id: StringName, data: GameData) -> void:
	var sheet: Dictionary = data.tile_sheet("battle_transition")
	var indices: PackedByteArray = data.tile_indices("battle_transition")
	if not _r.check(
		int(sheet.get("tiles", 0)) == RomLayout.BATTLE_TRANSITION_TILES
			and indices.size() == RomLayout.BATTLE_TRANSITION_TILES * Gen2Tiles.TILE_PIXELS,
		"%s: the transition sheet is %d tiles, %d pixels." % [
			game_id, int(sheet.get("tiles", 0)), indices.size(),
		]
	):
		return
	var width: int = int(sheet["width"])
	var square: Array[int] = []
	var black: Array[int] = []
	for y: int in Gen2Tiles.TILE_HEIGHT:
		for x: int in Gen2Tiles.TILE_WIDTH:
			square.append(int(indices[y * width + x]))
			black.append(int(indices[y * width + Gen2Tiles.TILE_WIDTH + x]))
	_r.check(
		black.count(3) == black.size(),
		"%s: BATTLETRANSITION_BLACK is not solid colour 3." % game_id
	)
	_r.check(
		square.count(3) < square.size() and square.count(3) > 0,
		"%s: BATTLETRANSITION_SQUARE has no pattern in it." % game_id
	)
	for dark: bool in [false, true]:
		var palette: PackedColorArray = data.battle_transition_palette(dark)
		_r.check(
			palette.size() == RomLayout.TRANSITION_PALETTE_COLORS,
			"%s: the %s transition palette has %d colours." % [
				game_id, "dark" if dark else "day", palette.size(),
			]
		)
	## Every animation, to the frame the screen is black on. Nothing here says
	## what one looks like; what it pins is that all four reach their own end
	## rather than running off a table, and how long each takes.
	var lengths: Array[int] = []
	for stronger: bool in [false, true]:
		for cave: bool in [false, true]:
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			var transition: Gen2BattleTransition = Gen2BattleTransition.create(
				stronger, cave, true, false, rng, data.battle_anim_sine()
			)
			var frames: int = 0
			while transition.advance_frame() and frames < MAX_FRAMES:
				frames += 1
			lengths.append(frames)
			var cells: PackedByteArray = transition.cells()
			var black_cells: int = 0
			for cell: int in cells:
				black_cells += 1 if cell == Gen2BattleTransition.CELL_BLACK else 0
			_r.check(
				transition.finished() and black_cells == cells.size(),
				"%s: the %s transition left %d of %d cells unwiped." % [
					game_id, "cave" if cave else "route", black_cells, cells.size(),
				]
			)
	print("%s: the four transitions run %s frames." % [game_id, lengths])


## `GetSubstitutePic`, on both sides and all three cartridges: the doll is four
## tiles of `MonsterSpriteGFX` in an otherwise empty box, at the one place the
## routine copies them to. Nothing else in the box may carry ink, since the
## routine zeroes it first and the battler's own picture is gone while it is up.
func _verify_substitute_pic(game_id: StringName, data: GameData) -> void:
	var strip: PackedByteArray = data.overworld_sprite_indices(
		Gen2BattleRenderer.SUBSTITUTE_SPRITE
	)
	if not _r.check(
		not strip.is_empty(),
		"%s: no monster overworld sprite in the cache, so no doll." % game_id
	):
		return
	for player_side: bool in [false, true]:
		var side: int = Gen2BattleScreenMap.PLAYER_SIDE if player_side \
			else Gen2BattleScreenMap.ENEMY_SIDE
		var box: int = side * Gen2Font.TILE
		var pixels: PackedByteArray = Gen2BattleRenderer.substitute_pixels(strip, player_side)
		if not _r.check(
			pixels.size() == box * box,
			"%s: the doll's box is %d pixels, not %d." % [game_id, pixels.size(), box * box]
		):
			continue
		var at: Vector2i = Gen2BattleRenderer.SUBSTITUTE_AT[player_side]
		var doll := Rect2i(at * Gen2Font.TILE, Vector2i(16, 16))
		var inside: int = 0
		var outside: int = 0
		for y: int in box:
			for x: int in box:
				if pixels[y * box + x] == 0:
					continue
				if doll.has_point(Vector2i(x, y)):
					inside += 1
				else:
					outside += 1
		_r.check(inside > 0, "%s: the doll drew nothing." % game_id)
		_r.check(
			outside == 0,
			"%s: %d lit pixels outside the doll's own 16 by 16." % [game_id, outside]
		)
		print("%s: the %s doll is %d lit pixels at %s of a %dx%d box." % [
			game_id, "player's" if player_side else "enemy's", inside, at, side, side,
		])


## Every animation played through [Gen2BattleAnimPlayer], which is the script
## plus the object pool, the tile window and the shadow OAM.
##
## Nothing here asserts what an animation looks like; what it pins is that all
## 278 spawn, step and retire their objects inside the cartridge's own limits,
## and it prints the inventory of what is still to build.
func _play_every_animation(game_id: StringName, data: GameData) -> void:
	var anims: Gen2BattleAnimData = Gen2BattleAnimData.from_game_data(data)
	if not _r.check(anims != null, "%s: no battle animation data in the cache." % game_id):
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
			if not _r.check(
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
			_r.check(
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
	_r.check(
		objects <= Gen2BattleAnimPlayer.MAX_OBJECTS,
		"%s: %d objects at once, past the %d slots." % [
			game_id, objects, Gen2BattleAnimPlayer.MAX_OBJECTS,
		]
	)
	_r.check(
		sprites <= Gen2BattleAnimPlayer.MAX_SPRITES,
		"%s: %d sprites at once, past the hardware's %d." % [
			game_id, sprites, Gen2BattleAnimPlayer.MAX_SPRITES,
		]
	)
	_r.check(
		functions.is_empty(),
		"%s: %d motion callbacks are still unbuilt: %s." % [
			game_id, functions.size(), functions.keys(),
		]
	)
	_r.check(
		effects.is_empty(),
		"%s: %d bg effects are still unbuilt: %s." % [
			game_id, effects.size(), effects.keys(),
		]
	)
	_r.check(
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
		if not _r.check(not region.is_empty(), "%s: no %s region in the cache." % [game_id, name]):
			continue
		_r.check(
			int(region["count"]) == int(EXPECTED_COUNTS[name]),
			"%s: %s holds %d entries, not the pinned %d." % [
				game_id, name, int(region["count"]), int(EXPECTED_COUNTS[name]),
			]
		)
		_r.check(
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
	if not _r.check(
		table.size() == RomLayout.BATTLE_ANIM_SINE_BYTES,
		"%s: sine table holds %d bytes, not %d." % [
			game_id, table.size(), RomLayout.BATTLE_ANIM_SINE_BYTES,
		]
	):
		return
	for index: int in table.size():
		if not _r.check(
			table[index] == int(RomLayout.BATTLE_ANIM_SINE_WAVE[index]),
			"%s: sine byte %d is $%02X, not the pinned $%02X." % [
				game_id, index, table[index], int(RomLayout.BATTLE_ANIM_SINE_WAVE[index]),
			]
		):
			return
	var anims: Gen2BattleAnimData = Gen2BattleAnimData.create({}, [], table)
	_r.check(
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
	if not _r.check(
		ran.size() == EXPECTED_POUND.size(),
		"%s: POUND ran %d commands, not the pinned %d." % [
			game_id, ran.size(), EXPECTED_POUND.size(),
		]
	):
		return
	for index: int in ran.size():
		var got: Dictionary = ran[index]
		var want: Array = EXPECTED_POUND[index]
		_r.check(
			got["name"] == want[0] and Array(got["operands"]) == Array(want[1]),
			"%s: POUND command %d is %s %s, not %s %s." % [
				game_id, index, got["name"], got["operands"], want[0], want[1],
			]
		)

	var dummy: Array = _run(data, DUMMY_INDEX)
	_r.check(
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
	_r.check(
		names.size() == (BG_EFFECTS_CRYSTAL if crystal else BG_EFFECTS_GOLD),
		"%s: the bg effect table is %d long." % [game_id, names.size()]
	)
	_r.check(
		names[BODY_SLAM_EFFECT] == (&"body_slam" if crystal else &"wobble_mon"),
		"%s: bg effect $%02X is %s." % [game_id, BODY_SLAM_EFFECT, names[BODY_SLAM_EFFECT]]
	)
	_r.check(
		names[ROLLOUT_EFFECT_CRYSTAL if crystal else ROLLOUT_EFFECT_GOLD] == &"rollout",
		"%s: BATTLE_BG_EFFECT_ROLLOUT is not where the constants put it." % game_id
	)
	for id: int in BODY_SLAM_EFFECT:
		_r.check(
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
	_r.check(
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
		if not _r.check(not row.is_empty(), "%s: object %d is missing." % [game_id, index]):
			return
		_r.check(
			int(row["frameset"]) < framesets,
			"%s: object %d names frameset %d of %d." % [
				game_id, index, int(row["frameset"]), framesets,
			]
		)
		_r.check(
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
	_r.check(
		data.battle_object_palette(0, enemy, player)[1]
			== Gen2Palette.from_packed(enemy[0]),
		"%s: PAL_BATTLE_OB_ENEMY did not come from the battler's own pair." % game_id
	)
	_r.check(
		data.battle_object_palette(1, enemy, player)[1]
			== Gen2Palette.from_packed(player[0]),
		"%s: PAL_BATTLE_OB_PLAYER did not come from the battler's own pair." % game_id
	)
	for index: int in RomLayout.BATTLE_OBJECT_PALETTES_STORED:
		var slot: int = index + RomLayout.BATTLE_OBJECT_PALETTE_FIRST_STORED
		var colors: PackedColorArray = data.battle_object_palette(slot)
		var wanted: Array = RomLayout.BATTLE_OBJECT_PALETTES[index]
		if not _r.check(
			colors.size() == RomLayout.BATTLE_OBJECT_PALETTE_COLORS,
			"%s: object palette %d has %d colours." % [game_id, slot, colors.size()]
		):
			continue
		for colour: int in wanted.size():
			_r.check(
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
		_r.check(
			indices.size() == int(row["tiles"]) * Gen2Tiles.TILE_PIXELS,
			"%s: graphics %d decoded %d pixels for %d tiles." % [
				game_id, index, indices.size(), int(row["tiles"]),
			]
		)
	_r.check(
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
		if not _r.check(script != null, "%s: animation %d has no address." % [game_id, index]):
			continue
		var frames: int = 0
		while not script.finished() and frames < MAX_FRAMES:
			frames += 1
			for command: Dictionary in script.advance_frame():
				commands += 1
				if command["name"] == Gen2BattleAnimScript.SOUND:
					sounds += 1
		_r.check(
			not script.failed(),
			"%s: animation %d ran off its region." % [game_id, index]
		)
		_r.check(
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
