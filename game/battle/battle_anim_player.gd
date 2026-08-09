class_name Gen2BattleAnimPlayer
extends RefCounted

## One battle animation playing: `RunBattleAnimScript`'s own frame loop
## (engine/battle_anims/anim_commands.asm).
##
## [Gen2BattleAnimScript] is the interpreter and knows only bytes;
## [Gen2BattleAnimObject] is one object and knows only itself. This is what the
## cartridge does with both once a frame: run the script until it yields, step
## every live object, and collect what they would put in `wShadowOAM`.
##
## Scene-free like the rest of the battle layer. Nothing here draws: a frame
## answers with sprites, a tile window and the palette each sprite wants, and
## whoever is drawing decides what that looks like.
##
## One of `.playframe`'s five steps is not here yet and is named rather than
## quietly skipped: `_ExecuteBGEffects`. [method unimplemented] reports what an
## animation asked for and did not get, so a caller can tell one that ran whole
## from one that ran without its background.

## `NUM_BATTLE_ANIM_STRUCTS`: ten slots, and an eleventh object is simply not
## spawned.
const MAX_OBJECTS: int = 10

## `BATTLEANIMSTRUCT_LENGTH`, which only matters because `BattleAnimCmd_ClearObjs`
## counts in bytes rather than objects.
const OBJECT_STRUCT_BYTES: int = 24

## `BattleAnimCmd_ClearObjs` clears `$a0` bytes where the ten structs are `$f0`,
## so it reaches into the seventh object and stops. Zeroing a struct's first byte
## is what frees it, so seven slots are freed and the last three survive a
## command that reads as if it cleared everything.
## This is the cartridge's own bug (docs/bugs_and_glitches.md) and is reproduced.
const CLEAR_OBJS_BYTES: int = 0xA0

## `OAM_COUNT`: the hardware's forty sprites. An object whose sprites would run
## past the end aborts the whole update, which is why a busy frame can lose the
## objects queued after it rather than truncating one.
const MAX_SPRITES: int = 40

## `NUM_BATTLEANIMTILEDICT_ENTRIES`: the five graphics sheets one animation may
## have loaded at once, as `anim_1gfx` through `anim_5gfx` fill them.
const TILE_DICT_ENTRIES: int = 5

## The tile window an animation's graphics are loaded into, from
## `BATTLEANIM_BASE_TILE` up to `vTiles1`. `BattleAnimCmd_*GFX` stops loading
## once the running tile id reaches this, which is why a five-sheet animation
## can silently load fewer than five.
const MAX_TILES: int = 128 - Gen2BattleAnimObject.BASE_TILE

## `wBattleAnimFlags` bits (constants/ram_constants.asm).
const FLAG_KEEP_SPRITES: int = 1 << 3

## `ROLLOUT`, whose animation runs without waiting a frame while its own bg
## effect is active.
const ROLLOUT: int = 0xCD

var _data: Gen2BattleAnimData = null
var _script: Gen2BattleAnimScript = null
var _anim_index: int = 0
var _enemy_turn: bool = false

var _objects: Array[Gen2BattleAnimObject] = []
var _last_object_index: int = 0
## `wBattleAnimTileDict`: five (graphics id, tile offset) pairs.
var _tile_dict: Array = []
## Which sheet occupies each tile of the window, as
## [code]{ gfx, tile }[/code] per loaded tile, so a renderer knows where an
## OAM tile id's pixels come from.
var _tiles: Array = []
var _keep_sprites: bool = false
var _sprites: Array = []
var _unimplemented: Dictionary = {}

## `wCurItem`, which `GetBallAnimPal` reads to colour a thrown ball. Nothing but
## a ball animation asks, and an item that is not a ball falls out of
## `BallColors` on its own terminator.
var cur_item: int = 0

## `wOBP0`, the DMG object palette `BattleAnimFunc_SkyAttack` flashes. Kept
## because the write is the whole of that state; the Color hardware draws
## objects from `wOBPals1` instead, so nothing shows.
var obp0: int = 0

## `hLCDCPointer`, `hLYOverrideStart` and `hLYOverrideEnd`: the scanline window
## `BattleAnimFunc_Surf` opens over `rSCY` and hands back when the wave has
## crossed the screen. It is the only callback that reaches the raster.
var lcdc_pointer: int = 0
var ly_override_start: int = 0
var ly_override_end: int = 0


## Starts [param index] of `BattleAnimations`. Answers null when the cache has no
## such animation, which is what an unimported layer looks like.
##
## [param param] is `wBattleAnimParam`, and [param enemy_turn] is `hBattleTurn`:
## the two inputs the battle engine sets before `PlayBattleAnim`.
static func create(
	data: Gen2BattleAnimData, index: int, enemy_turn: bool = false, param: int = 0
) -> Gen2BattleAnimPlayer:
	if data == null:
		return null
	var region: Dictionary = data.region(&"scripts")
	var address: int = data.pointer(&"scripts", index)
	if region.is_empty() or address < 0:
		return null

	var player := Gen2BattleAnimPlayer.new()
	player._data = data
	player._anim_index = index
	player._enemy_turn = enemy_turn
	# `ClearBattleAnims` zeroes the whole animation block before the script's
	# pointer is loaded, so every object slot, the tile dict and the flags start
	# empty on each animation rather than carrying over from the last one.
	player._objects.resize(MAX_OBJECTS)
	player._tile_dict.resize(TILE_DICT_ENTRIES)
	player._script = Gen2BattleAnimScript.create(
		region["data"], int(region["address"]), address, param
	)
	return player


## `hBattleTurn`, which two callbacks and the enemy-side coordinate fix read.
func enemy_turn() -> bool:
	return _enemy_turn


## The imported tables the callbacks resolve their sine and framesets through.
func data() -> Gen2BattleAnimData:
	return _data


func finished() -> bool:
	return _script.finished()


func failed() -> bool:
	return _script.failed()


## The sprites the last frame put in `wShadowOAM`, each
## [code]{ y, x, tile, attributes }[/code] with the cartridge's own byte values.
##
## A y or x of zero is off screen, the way it is on hardware: OAM subtracts 16
## and 8 from what is written.
func sprites() -> Array:
	return _sprites


## Which graphics sheet each tile of the animation window currently holds, as
## [code]{ gfx, tile }[/code] indexed from [constant Gen2BattleAnimObject.BASE_TILE].
## An OAM tile id below that base is not an animation tile at all.
func tiles() -> Array:
	return _tiles


## The live objects, for a caller that wants more than their sprites.
func objects() -> Array:
	var out: Array = []
	for object: Gen2BattleAnimObject in _objects:
		if object != null and object.active():
			out.append(object)
	return out


## What this animation asked for and did not get, as
## [code]{ "bg_effects": [id, ...], "functions": [id, ...] }[/code], each id
## once. Empty when the animation ran whole.
func unimplemented() -> Dictionary:
	var out: Dictionary = {"bg_effects": [], "functions": []}
	for key: String in _unimplemented:
		var parts: PackedStringArray = key.split(":")
		(out[parts[0]] as Array).append(int(parts[1]))
	(out["bg_effects"] as Array).sort()
	(out["functions"] as Array).sort()
	return out


## One hardware frame of `.playframe`: the script, then the bg effects, then
## every object. Answers whether the animation is still running.
func advance_frame() -> bool:
	if finished():
		_finish()
		return false

	# `.playframe` runs its body again without waiting a frame while Rollout's
	# own bg effect is up, which is what makes that animation twice as quick.
	for _repeat: int in 2:
		_run_commands()
		_execute_bg_effects()
		_update_oam()
		if not _rollout_running():
			break
	if finished():
		_finish()
	return true


## `RunBattleAnimCommand`, plus the commands that reach past the interpreter into
## the objects and the tile window.
func _run_commands() -> void:
	for command: Dictionary in _script.advance_frame():
		match command["name"]:
			Gen2BattleAnimScript.OBJ:
				_queue_object(command["operands"])
			&"gfx_1", &"gfx_2", &"gfx_3", &"gfx_4", &"gfx_5":
				_load_graphics(command["operands"])
			&"inc_obj":
				var target: Gen2BattleAnimObject = _object_with_index(
					int((command["operands"] as Array)[0])
				)
				if target != null:
					target.jumptable_index = (target.jumptable_index + 1) & 0xFF
			&"set_obj":
				var operands: Array = command["operands"]
				var found: Gen2BattleAnimObject = _object_with_index(int(operands[0]))
				if found != null:
					found.jumptable_index = int(operands[1])
			&"clear_objs":
				_clear_objects()
			&"keep_sprites":
				_keep_sprites = true
			&"bg_effect":
				_note(&"bg_effects", int((command["operands"] as Array)[0]))
			&"inc_bg_effect":
				_note(&"bg_effects", int((command["operands"] as Array)[0]))


## `QueueBattleAnimation`: the first free slot, or nothing at all. The index
## counter is bumped before the object is built and is never reset, so it wraps
## through a byte over a long animation.
func _queue_object(operands: Array) -> void:
	for slot: int in MAX_OBJECTS:
		var existing: Gen2BattleAnimObject = _objects[slot]
		if existing != null and existing.active():
			continue
		_last_object_index = (_last_object_index + 1) & 0xFF
		var row: Dictionary = _data.object_row(int(operands[0]))
		if row.is_empty():
			return
		_objects[slot] = Gen2BattleAnimObject.create(
			_last_object_index, row, _tile_offset(int(row[&"gfx"])),
			int(operands[1]), int(operands[2]), int(operands[3])
		)
		return


## `BattleAnimCmd_*GFX`: each named sheet is loaded into the window in turn and
## recorded in the tile dict, until the window is full.
func _load_graphics(operands: Array) -> void:
	var next_tile: int = 0
	var entry: int = 0
	for gfx: Variant in operands:
		if next_tile >= MAX_TILES:
			return
		if entry >= TILE_DICT_ENTRIES:
			return
		_tile_dict[entry] = {"gfx": int(gfx), "tile": next_tile}
		entry += 1
		var row: Dictionary = _data.gfx(int(gfx))
		var count: int = int(row.get("tiles", 0)) if not row.is_empty() else 0
		for tile: int in count:
			if next_tile + tile >= MAX_TILES:
				break
			_tiles.resize(maxi(_tiles.size(), next_tile + tile + 1))
			_tiles[next_tile + tile] = {"gfx": int(gfx), "tile": tile}
		next_tile += count


## `GetBattleAnimTileOffset`: where in the window a graphics id was loaded, or
## zero when it was not loaded at all, which draws the window's first tiles
## rather than nothing.
func _tile_offset(gfx: int) -> int:
	for entry: Variant in _tile_dict:
		if entry is Dictionary and int((entry as Dictionary)["gfx"]) == gfx:
			return int((entry as Dictionary)["tile"])
	return 0


func _object_with_index(index: int) -> Gen2BattleAnimObject:
	for object: Gen2BattleAnimObject in _objects:
		if object != null and object.index == index:
			return object
	return null


## `BattleAnimCmd_ClearObjs` and its own byte count; see
## [constant CLEAR_OBJS_BYTES].
func _clear_objects() -> void:
	@warning_ignore("integer_division")
	var freed: int = (CLEAR_OBJS_BYTES + OBJECT_STRUCT_BYTES - 1) / OBJECT_STRUCT_BYTES
	for slot: int in mini(freed, MAX_OBJECTS):
		if _objects[slot] != null:
			_objects[slot].deinit()


## `_ExecuteBGEffects`. The effects themselves are not built; the ids the script
## asked for are recorded by [method _run_commands] as it reads them.
func _execute_bg_effects() -> void:
	pass


## `.playframe`'s Rollout check: the frame delay is skipped while
## `BATTLE_BG_EFFECT_ROLLOUT` is one of the five live effects. No effect is live
## until they are built, so this answers false the way it does for every other
## animation.
func _rollout_running() -> bool:
	return false


## `BattleAnim_UpdateOAM_All`: every live object stepped and drawn, in slot
## order, stopping at the first one whose sprites would not fit.
func _update_oam() -> void:
	_sprites = []
	for object: Gen2BattleAnimObject in _objects:
		if object == null or not object.active():
			continue
		_do_battle_anim_frame(object)
		if not object.active():
			continue
		var update: Dictionary = object.oam_update(_data, _enemy_turn, _anim_index)
		var sprites: Array = update["sprites"]
		if _sprites.size() + sprites.size() > MAX_SPRITES:
			# `BattleAnimOAMUpdate` returns carry once the pointer reaches the end
			# of the shadow buffer, and the caller stops there.
			for sprite: Variant in sprites:
				if _sprites.size() >= MAX_SPRITES:
					break
				_sprites.append(sprite)
			return
		_sprites.append_array(sprites)


## `DoBattleAnimFrame`: the object's own motion callback, in
## [Gen2BattleAnimFunctions]. A callback outside the jumptable is reported rather
## than run, which the importer's own range check makes unreachable from a
## cartridge and a hand-built object can still ask for.
func _do_battle_anim_frame(object: Gen2BattleAnimObject) -> void:
	if not Gen2BattleAnimFunctions.run(self, object):
		_note(&"functions", object.function)


## `BattleAnim_ClearOAM`. Keeping the sprites does not keep their colours: every
## one is moved onto `PAL_BATTLE_OB_ENEMY`, which the source asserts is zero.
func _finish() -> void:
	if not _keep_sprites:
		_sprites = []
		return
	var kept: Array = []
	for sprite: Variant in _sprites:
		var entry: Dictionary = (sprite as Dictionary).duplicate()
		entry["attributes"] = int(entry["attributes"]) & ~(
			Gen2BattleAnimObject.OAM_PALETTE | Gen2BattleAnimObject.OAM_BANK1
		) & 0xFF
		kept.append(entry)
	_sprites = kept


func _note(kind: StringName, id: int) -> void:
	_unimplemented["%s:%d" % [kind, id]] = true
