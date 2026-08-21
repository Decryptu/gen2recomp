class_name Gen2BattleAnimPlayer
extends RefCounted

## One battle animation playing: `RunBattleAnimScript`'s frame loop
## (engine/battle_anims/anim_commands.asm). [Gen2BattleAnimScript] is the
## interpreter and knows only bytes, [Gen2BattleAnimObject] is one object and
## knows only itself; this is what the cartridge does with both once a frame,
## running the script until it yields, stepping every live object and collecting
## what they would put in `wShadowOAM`.
##
## Scene-free: a frame answers with sprites, a tile window and the palette each
## sprite wants. All five of `.playframe`'s steps are here, and
## [method unimplemented] reports what an animation asked for and did not get,
## which cartridge data no longer produces and a hand-built region still can.

## `NUM_BATTLE_ANIM_STRUCTS`: an eleventh object is simply not spawned.
const MAX_OBJECTS: int = 10

## Matters only because `BattleAnimCmd_ClearObjs` counts bytes, not objects.
const OBJECT_STRUCT_BYTES: int = 24

## `BattleAnimCmd_ClearObjs` clears `$a0` bytes where the ten structs are `$f0`,
## stopping inside the seventh. Zeroing a struct's first byte frees it, so seven
## go and the last three survive a command that reads as clearing everything:
## the cartridge's own bug (docs/bugs_and_glitches.md), reproduced.
const CLEAR_OBJS_BYTES: int = 0xA0

## The hardware's forty sprites. An object whose sprites would overrun aborts the
## whole update, so a busy frame loses the objects after it rather than one.
const MAX_SPRITES: int = 40

## The five sheets `anim_1gfx` through `anim_5gfx` may have loaded at once.
const TILE_DICT_ENTRIES: int = 5

## The window graphics load into, `BATTLEANIM_BASE_TILE` up to `vTiles1`.
## `BattleAnimCmd_*GFX` stops once the running tile id reaches it, so a
## five-sheet animation can silently load fewer.
const MAX_TILES: int = 128 - Gen2BattleAnimObject.BASE_TILE

## `wBattleAnimFlags` bits (constants/ram_constants.asm).
const FLAG_KEEP_SPRITES: int = 1 << 3

## The two `AnimObjGFX` rows with no sheet: the battler graphics commands fill
## them from whichever picture is on the field.
const GFX_PLAYERHEAD: int = 0x28
const GFX_ENEMYFEET: int = 0x29

## `vTiles0`, whose top `BattleAnimCmd_BattlerGFX_*` counts back from.
const OBJECT_TILES: int = 0x80

## Five background effects at once; a sixth is not queued, as an eleventh object
## is not spawned.
const MAX_BG_EFFECTS: int = Gen2BattleAnimBgEffects.MAX_EFFECTS

## What `Rollout_FillLYOverridesBackup` and `.playframe` check `wFXAnimID` for.
const ROLLOUT: int = 0xCD

## `BATTLE_AFTERANIMS` and the four offsets from it written into
## `wBattleAfterAnim`; `BattleAnimRunScript` adds the base back.
const BATTLE_AFTERANIMS: int = 0x10E
const AFTER_ANIM_NONE: int = 0
const AFTER_ANIM_ENEMY_DAMAGE: int = 0x10F - BATTLE_AFTERANIMS
const AFTER_ANIM_ENEMY_STAT_DOWN: int = 0x110 - BATTLE_AFTERANIMS
const AFTER_ANIM_PLAYER_DAMAGE: int = 0x112 - BATTLE_AFTERANIMS
const AFTER_ANIM_WOBBLE: int = 0x113 - BATTLE_AFTERANIMS

## The status animations `PlayOpponentBattleAnim` plays on the target, past
## `wFXAnimID`'s low byte and so reached by `BattleAnimRunScript`'s `.not_move`.
## Only these five of the block are named, the rest having no caller: `ANIM_SLP`
## and `ANIM_SAP` sit among them and nothing in either pin asks for one.
const ANIM_CONFUSED: int = 0x103
const ANIM_BRN: int = 0x105
const ANIM_PSN: int = 0x106
const ANIM_FRZ: int = 0x108
const ANIM_PAR: int = 0x109

var _data: Gen2BattleAnimData = null
var _script: Gen2BattleAnimScript = null
var _anim_index: int = 0
var _enemy_turn: bool = false

var _objects: Array[Gen2BattleAnimObject] = []
var _last_object_index: int = 0
## `wBattleAnimTileDict`: five (graphics id, tile offset) pairs.
var _tile_dict: Array = []
## [code]{ gfx, tile }[/code] per loaded tile, so a renderer knows where an OAM
## tile id's pixels come from.
var _tiles: Array = []
var _keep_sprites: bool = false
var _sprites: Array = []
## What the last frame's `RunBattleAnimCommand` ran, for the caller that owns
## what the interpreter does not: `anim_sound` and `anim_cry` need an audio
## player, which this layer has none of.
var _frame_commands: Array = []
var _unimplemented: Dictionary = {}
## `wActiveBGEffects`: five `battle_bg_effect` slots.
var _bg_effects: Array[Gen2BattleAnimBgEffect] = []
## The video state the bg effects and `BattleAnimFunc_Surf` share.
var _background: Gen2BattleAnimBackground = null

## `wCurItem`, read by `GetBallAnimPal` to colour a thrown ball. Nothing else
## asks, and a non-ball falls out of `BallColors` on its own terminator.
var cur_item: int = 0

## The Fly and Dig bits three bg effects check before touching a battler.
var player_off_field: bool = false
var enemy_off_field: bool = false


## Starts [param index] of `BattleAnimations`, null when the cache has no such
## animation. [param param] is `wBattleAnimParam` and [param enemy_turn] is
## `hBattleTurn`, the two inputs set before `PlayBattleAnim`.
static func create(
	anim_data: Gen2BattleAnimData, index: int, on_enemy_turn: bool = false, param: int = 0
) -> Gen2BattleAnimPlayer:
	if anim_data == null:
		return null
	var region: Dictionary = anim_data.region(&"scripts")
	var address: int = anim_data.pointer(&"scripts", index)
	if region.is_empty() or address < 0:
		return null

	var player := Gen2BattleAnimPlayer.new()
	player._data = anim_data
	player._anim_index = index
	player._enemy_turn = on_enemy_turn
	# `ClearBattleAnims` zeroes the whole animation block before the script's
	# pointer is loaded, so every object slot, the tile dict and the flags start
	# empty on each animation rather than carrying over from the last one.
	player._objects.resize(MAX_OBJECTS)
	player._tile_dict.resize(TILE_DICT_ENTRIES)
	player._bg_effects.resize(MAX_BG_EFFECTS)
	for slot: int in MAX_BG_EFFECTS:
		player._bg_effects[slot] = Gen2BattleAnimBgEffect.new()
	player._background = Gen2BattleAnimBackground.new()
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


## Which cartridge this animation came from, which only the bg effect table asks.
func profile() -> StringName:
	return _data.profile()


## `wFXAnimID`, which two routines compare against `ROLLOUT`.
func anim_index() -> int:
	return _anim_index


## The video state the background effects write: scanline tables, screen scroll,
## palette remaps and the tilemap.
func background() -> Gen2BattleAnimBackground:
	return _background


## The live `wActiveBGEffects` slots, for a caller that wants more than the
## screen they produced.
func bg_effects() -> Array:
	var out: Array = []
	for effect: Gen2BattleAnimBgEffect in _bg_effects:
		if effect.active():
			out.append(effect)
	return out


## `BGEffect_CheckFlyDigStatus`: whether the battler is off the field mid-Fly or
## mid-Dig, which stops three effects touching a picture that is not there.
func fly_dig_status(player_side: bool) -> bool:
	return player_off_field if player_side else enemy_off_field


## `wLastAnimObjectIndex` stepped on without an object being built, which is what
## a battler-object effect does when the battler is off the field.
func bump_object_index() -> void:
	_last_object_index = (_last_object_index + 1) & 0xFF


## `_QueueBattleAnimation`, which a battler-object effect calls with the same
## four values `anim_obj` supplies.
func queue_object(row: int, x: int, y: int, param: int) -> void:
	_queue_object([row, x, y, param])


## `wAnimObject1YOffset`, which `BattleBGEffect_Rollout` writes straight into the
## first struct whether or not a live object is standing in it.
func set_first_object_y_offset(value: int) -> void:
	if _objects[0] == null:
		_objects[0] = Gen2BattleAnimObject.new()
	_objects[0].y_offset = value & 0xFF


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


## What each tile of the animation window currently holds, indexed from
## [constant Gen2BattleAnimObject.BASE_TILE]. An OAM tile id below that base is
## not an animation tile at all.
##
## Two shapes: [code]{ gfx, tile }[/code] is a tile of an imported sheet, and
## [code]{ battler_tile }[/code] a tile of `vTiles2`, which is where the battle's
## own two pictures live, in the numbering [Gen2BattleScreenMap] uses. Only
## `anim_battlergfx_1row` and `..._2row` produce the second.
func tiles() -> Array:
	return _tiles


## The commands the last [method advance_frame] ran, each
## [code]{ name, byte, operands }[/code] as [Gen2BattleAnimScript] reports them.
func frame_commands() -> Array:
	return _frame_commands


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


## One hardware frame of `.playframe`, in its order: the script, the bg effects,
## every object, the scanline table and the palettes. `.playframe` skips its own
## `BattleAnimDelayFrame` while Rollout's bg effect is live, because that effect
## waits a frame itself, but both paths spend exactly one frame, so a player
## stepped once per frame has nothing for the check to decide.
func advance_frame() -> bool:
	if finished():
		_finish()
		return false

	_run_commands()
	_execute_bg_effects()
	_update_oam()
	_background.push_ly_overrides()
	_background.request_pals()
	if finished():
		_finish()
	return true


## `RunBattleAnimCommand`, plus the commands that reach past the interpreter into
## the objects and the tile window.
func _run_commands() -> void:
	_frame_commands = _script.advance_frame()
	for command: Dictionary in _frame_commands:
		match command["name"]:
			Gen2BattleAnimScript.OBJ:
				_queue_object(command["operands"])
			&"gfx_1", &"gfx_2", &"gfx_3", &"gfx_4", &"gfx_5":
				_load_graphics(command["operands"])
			&"battler_gfx_1row":
				_load_battler_graphics(1)
			&"battler_gfx_2row":
				_load_battler_graphics(2)
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
				_queue_bg_effect(command["operands"])
			&"inc_bg_effect":
				var live: Gen2BattleAnimBgEffect = _bg_effect_with_id(
					int((command["operands"] as Array)[0])
				)
				if live != null:
					live.jumptable_index = (live.jumptable_index + 1) & 0xFF
			&"bgp":
				_background.bgp = int((command["operands"] as Array)[0])
			&"obp0":
				_background.obp0 = int((command["operands"] as Array)[0])
			&"obp1":
				_background.obp1 = int((command["operands"] as Array)[0])
			&"reset_obp0":
				# `hSGB`'s $f0 is the branch the Color hardware does not take.
				_background.obp0 = 0xE0


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


## `BattleAnimCmd_BattlerGFX_1Row` and `..._2Row`: one or two rows of each
## battler's picture copied into the top of the animation window, so an effect
## can lift a battler's feet or head off the tilemap and move them as objects,
## which three bg effects including `BattleBGEffect_Tackle` do.
##
## The two dict entries are crosswise with what is copied, `PLAYERHEAD` holding
## the enemy's rows and `ENEMYFEET` the player's, and the object rows are crossed
## the same way, `BATTLE_ANIM_OBJ_ENEMYFEET_*` naming
## `BATTLE_ANIM_GFX_PLAYERHEAD`, so the two cancel. Both crossings are the
## cartridge's and neither is tidied.
##
## The window tiles these fill name a tile of `vTiles2`, where the battle's own
## pictures live, in the numbering [Gen2BattleScreenMap] writes.
func _load_battler_graphics(rows: int) -> void:
	var slot: int = _free_tile_dict_slot()
	if slot < 0 or slot + 1 >= TILE_DICT_ENTRIES:
		return

	var enemy_tiles: int = Gen2BattleScreenMap.ENEMY_SIDE * rows
	var player_tiles: int = Gen2BattleScreenMap.PLAYER_SIDE * rows
	var first: int = (OBJECT_TILES - player_tiles - enemy_tiles) \
		- Gen2BattleAnimObject.BASE_TILE
	var second: int = (OBJECT_TILES - player_tiles) - Gen2BattleAnimObject.BASE_TILE
	_tile_dict[slot] = {"gfx": GFX_PLAYERHEAD, "tile": first}
	_tile_dict[slot + 1] = {"gfx": GFX_ENEMYFEET, "tile": second}

	# The enemy's bottom rows, then the player's top ones, each column of the
	# picture contributing `rows` tiles: `.LoadFeet` steps the source by the
	# picture's own height and the destination by what it just copied.
	_copy_battler_rows(
		first, rows, Gen2BattleScreenMap.ENEMY_SIDE,
		Gen2BattleScreenMap.ENEMY_BASE_TILE + Gen2BattleScreenMap.ENEMY_SIDE - rows
	)
	_copy_battler_rows(
		second, rows, Gen2BattleScreenMap.PLAYER_SIDE,
		Gen2BattleScreenMap.PLAYER_BASE_TILE
	)


## One picture's rows into the window. Both pictures are square, so the source
## stride is the same [param side] the column count is.
func _copy_battler_rows(at: int, rows: int, side: int, source: int) -> void:
	for column: int in side:
		for row: int in rows:
			var window: int = at + column * rows + row
			if window < 0 or window >= MAX_TILES:
				continue
			_tiles.resize(maxi(_tiles.size(), window + 1))
			_tiles[window] = {"battler_tile": source + column * side + row}


## The first tile dict slot nothing has claimed. `BattleAnimCmd_BattlerGFX_*`
## walks the dict for a zero graphics id rather than starting at the front, which
## is what lets it sit behind an `anim_1gfx`.
func _free_tile_dict_slot() -> int:
	for slot: int in TILE_DICT_ENTRIES:
		var entry: Variant = _tile_dict[slot]
		if not entry is Dictionary or int((entry as Dictionary).get("gfx", 0)) == 0:
			return slot
	return -1


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


## `QueueBGEffect`: the first free slot, or nothing at all. Unlike an object, a
## refused effect leaves no trace: there is no index counter to step on.
func _queue_bg_effect(operands: Array) -> void:
	for slot: int in MAX_BG_EFFECTS:
		if _bg_effects[slot].active():
			continue
		_bg_effects[slot] = Gen2BattleAnimBgEffect.create(
			int(operands[0]), int(operands[1]), int(operands[2]), int(operands[3])
		)
		return


func _bg_effect_with_id(id: int) -> Gen2BattleAnimBgEffect:
	for effect: Gen2BattleAnimBgEffect in _bg_effects:
		if effect.id == id:
			return effect
	return null


## `_ExecuteBGEffects`: every live slot in order. An id past this profile's own
## table is reported rather than run, which cartridge data never produces.
func _execute_bg_effects() -> void:
	for effect: Gen2BattleAnimBgEffect in _bg_effects:
		if not effect.active():
			continue
		if not Gen2BattleAnimBgEffects.run(self, effect):
			_note(&"bg_effects", effect.id)


## `BattleAnim_UpdateOAM_All`: every live object stepped and drawn, in slot
## order, stopping at the first one whose sprites would not fit.
##
## The slot's index byte is tested once, at the top of the loop, so an object
## whose own callback calls `DeinitBattleAnimation` still reaches
## `BattleAnimOAMUpdate` and is **drawn one last time where it stands**;
## `DeinitBattleAnimation` clears the index and nothing else, so the frameset
## steps normally on that pass. Measured against a real cartridge: TACKLE's
## `anim_incobj 1` frees the target's two rows on the frame it runs and OAM
## still holds their fourteen sprites for that frame.
func _update_oam() -> void:
	_sprites = []
	for object: Gen2BattleAnimObject in _objects:
		if object == null or not object.active():
			continue
		_do_battle_anim_frame(object)
		var update: Dictionary = object.oam_update(_data, _enemy_turn, _anim_index)
		var new_sprites: Array = update["sprites"]
		if _sprites.size() + new_sprites.size() > MAX_SPRITES:
			# `BattleAnimOAMUpdate` returns carry once the pointer reaches the end
			# of the shadow buffer, and the caller stops there.
			for sprite: Variant in new_sprites:
				if _sprites.size() >= MAX_SPRITES:
					break
				_sprites.append(sprite)
			return
		_sprites.append_array(new_sprites)


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
