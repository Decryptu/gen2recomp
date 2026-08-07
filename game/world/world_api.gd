class_name Gen2WorldAPI
extends RefCounted

## Scene-free runtime access to one imported Generation 2 map.
##
## The API works in walk cells: every cell is a 2x2 group of 8x8 graphics
## tiles. It owns player position, camera framing and live object state, while
## event flags are supplied through a separate scene-free world state.

const VIEW_CELLS: Vector2i = Vector2i(10, 9)
const VIEW_TILES: Vector2i = VIEW_CELLS * RomLayout.MAP_BLOCK_CELL_WIDTH
const CELL_PIXELS: int = Gen2Tiles.TILE_WIDTH * RomLayout.MAP_BLOCK_CELL_WIDTH
const MOVEMENT_WALK: StringName = &"walk"
const MOVEMENT_SURF: StringName = &"surf"
const TRAINER_SHOCK_EMOTE: int = 0
const TRAINER_SHOCK_FRAMES: int = 30
const TRAINER_SLOW_STEP_FRAMES: int = 16
## StepVectors' normal-speed row: 2 pixels per frame for 8 frames, the source
## duration for ordinary player walking (engine/overworld/map_objects.asm).
const STEP_FRAMES_WALK: int = 8
## A ledge hop is two chained STEP_WALK-duration cells back to back
## (engine/overworld/map_objects.asm's StepFunction_PlayerJump: .initjump/
## .stepjump then .initland/.stepland, each timed by the same InitStep call
## the ordinary walk uses). The source also overlays a visual jump arc via
## OBJECT_JUMP_HEIGHT/UpdateJumpPosition, which this project does not render;
## no vertical bob exists anywhere else in this renderer either.
const STEP_FRAMES_HOP: int = STEP_FRAMES_WALK * 2
## StepVectors' slow row: 1 pixel per frame for 16 frames. _RandomWalkContinue
## calls InitStep with a direction of 0 to 3, which indexes that first row, so
## a wandering object steps at half the player's walking speed.
const STEP_FRAMES_NPC_WALK: int = 16
## MovementFunction_Strength calls InitStep with `direction | 0`, so a pushed
## boulder indexes that same slow row and slides at a wandering NPC's speed.
const STEP_FRAMES_BOULDER_PUSH: int = STEP_FRAMES_NPC_WALK
## RandomStepDuration_Slow and _Fast mask the source random byte before storing
## it as the wait preceding the next movement decision.
const IDLE_MASK_SLOW: int = 0x7F
const IDLE_MASK_FAST: int = 0x1F

## Crystal background event types from script_constants.asm. READ and the four
## facing variants point directly at a script. IFSET and IFNOTSET point at a
## four-byte conditional record containing an event flag and script pointer.
const BGEVENT_READ: int = 0
const BGEVENT_UP: int = 1
const BGEVENT_DOWN: int = 2
const BGEVENT_RIGHT: int = 3
const BGEVENT_LEFT: int = 4
const BGEVENT_IFSET: int = 5
const BGEVENT_IFNOTSET: int = 6
const BGEVENT_ITEM: int = 7
const BGEVENT_COPY: int = 8

var data: GameData = null
var state: Gen2WorldState = null
var inventory: Gen2WorldInventory = null
var current_map: Gen2WorldMap = null
var current_tileset: Gen2WorldTileset = null
var player_cell: Vector2i = Vector2i.ZERO
var player_facing: int = Gen2WorldSprite.FACING_DOWN
var objects: Array = []
var object_hour: int = 6
var object_time_of_day: int = Gen2WorldPalette.TIME_MORNING
var world_day: int = 0
var world_hour: int = 6
var world_minute: int = 0
var dst_enabled: bool = false
var movement_mode: StringName = MOVEMENT_WALK
## wPlayerState resolved through ChrisStateSprites, which is the only part of
## that state a renderer reads. movement_mode carries the rest; the two surfing
## states differ from each other here and nowhere else.
var player_sprite_number: int = Gen2WorldSprite.SPRITE_PLAYER
var _script_queue: Array = []
var _active_script: Gen2WorldScriptRunner = null
var _map_entry_scene_pending: bool = false
var _object_visibility_overrides: Dictionary = {}
## Live cells and facings written by moveobject, turnobject, followers and the
## trainer approach. The cartridge keeps the same values in wMapObjects, which
## a map load rebuilds from ROM, so these do not outlive the loaded map; see
## _apply_map(). Visibility is not one of them, because disappear/appear write
## event flags, which the cartridge does persist.
var _object_position_overrides: Dictionary = {}
var _object_facing_overrides: Dictionary = {}
var _object_followers: Dictionary = {}
var _variable_sprites: Dictionary = {}
var _block_overrides: Dictionary = {}
## A resolved but uncommitted Cut, held between cut_request() and complete_cut()
## the way Script_Cut holds wCutWhirlpool* across its writetext. Cleared with the
## block overrides, since the block it names belongs to the loaded map.
var _pending_cut: Dictionary = {}
## The same for Surf, held between surf_request() and complete_surf() while
## UsedSurfScript shows its text. The cell it names belongs to the loaded map,
## so it is cleared beside the Cut request.
var _pending_surf: Dictionary = {}
## The same for Whirlpool, which shares the source's wCutWhirlpool* slots with
## Cut and is cleared beside it for the same reason.
var _pending_whirlpool: Dictionary = {}
## The same for Strength, held while Script_UsedStrength shows its text. It names
## no cell or block, but it is cleared with the others anyway: the source queues
## Script_StrengthFromMenu and runs it at once, so a request cannot outlive the
## map it was made on.
var _pending_strength: Dictionary = {}
var _command_queues: Dictionary = {}
var _next_command_queue_id: int = 0
var _fishing: Gen2WorldFishing = Gen2WorldFishing.new()
## Supplies the roaming jumps performed during map setup. A caller that needs a
## reproducible route sets its own generator; otherwise map setup randomizes.
var schedule_random: RandomNumberGenerator = null
## Supplies the source RANDOM command and the phone routines that roll. Kept
## apart from schedule_random so seeding one route does not shift the other.
## A null generator leaves each invocation to randomize its own.
var script_random: RandomNumberGenerator = null
## Supplies the wandering and spinning movement templates. Kept apart from the
## other two so seeding NPC motion cannot shift an encounter, a phone roll or a
## script's RANDOM result.
var object_random: RandomNumberGenerator = null
var _last_schedule: Dictionary = {}
var _phone_ring: Gen2WorldPhoneRing = null
var _phone_ring_request: Dictionary = {}
## Transient presentation offset for the player's own walk step. player_cell
## already holds the committed destination; this only paces how far behind it
## a renderer draws the sprite. Never read by collision, events or the
## snapshot.
var _player_step_direction: Vector2i = Vector2i.ZERO
var _player_step_frames_total: int = 0
var _player_step_frames_remaining: int = 0
var _player_step_accumulator: float = 0.0
## Real time banked toward the next hardware frame of object movement, held
## beside the player's own accumulator so the two stay in phase after a stall.
var _object_step_accumulator: float = 0.0
## Read-only mirror of the selected save's party, refreshed by the screen
## whenever the save or party changes. Gen2WorldAPI does not own a save, so
## this stays optional; a script that reads it while empty fails rather than
## reporting an invented zero. Never written by the script runner.
var _party_summary: Dictionary = {}

const PHONE_ENTRANCE_COLLISIONS: Array[int] = [0x71, 0x79, 0x7A, 0x7B]


## Opens one map through the public cartridge-content API.
## Returns null when the cache does not contain the requested map or tileset.
static func open(
	game_data: GameData,
	group: int,
	number: int,
	start_cell: Vector2i,
	world_state: Gen2WorldState = null,
) -> Gen2WorldAPI:
	if game_data == null:
		return null
	var map: Gen2WorldMap = game_data.world_map(group, number)
	if map == null:
		return null
	var tileset: Gen2WorldTileset = game_data.world_tileset(map.tileset)
	if tileset == null:
		return null
	return Gen2WorldAPI.new(game_data, map, tileset, start_cell, world_state)


## Opens a validated map/player snapshot without silently clamping its cell.
static func open_snapshot(game_data: GameData, world_snapshot: Gen2WorldSnapshot) -> Gen2WorldAPI:
	if game_data == null or world_snapshot == null:
		return null
	var map: Gen2WorldMap = game_data.world_map(world_snapshot.map_id.x, world_snapshot.map_id.y)
	if map == null or world_snapshot.world_state == null:
		return null
	if world_snapshot.player_cell.x < 0 or world_snapshot.player_cell.y < 0 \
		or world_snapshot.player_cell.x >= map.collision_width \
		or world_snapshot.player_cell.y >= map.collision_height:
		return null
	if world_snapshot.player_facing < Gen2WorldSprite.FACING_DOWN \
		or world_snapshot.player_facing > Gen2WorldSprite.FACING_RIGHT:
		return null
	if world_snapshot.movement_mode not in [MOVEMENT_WALK, MOVEMENT_SURF]:
		return null
	if world_snapshot.world_day < 0 or world_snapshot.world_day >= Gen2WorldClock.DAYS_PER_WEEK \
		or world_snapshot.world_hour < 0 or world_snapshot.world_hour >= Gen2WorldClock.HOURS_PER_DAY \
		or world_snapshot.world_minute < 0 \
		or world_snapshot.world_minute >= Gen2WorldClock.MINUTES_PER_HOUR:
		return null
	var tileset: Gen2WorldTileset = game_data.world_tileset(map.tileset)
	if tileset == null:
		return null
	var out := Gen2WorldAPI.new(
		game_data, map, tileset, world_snapshot.player_cell, world_snapshot.world_state
	)
	out.player_facing = world_snapshot.player_facing
	out.movement_mode = world_snapshot.movement_mode
	out.player_sprite_number = world_snapshot.player_sprite_number
	out.world_day = world_snapshot.world_day
	out.world_hour = world_snapshot.world_hour
	out.world_minute = world_snapshot.world_minute
	out.dst_enabled = world_snapshot.dst_enabled
	return out


func _init(
	game_data: GameData,
	map: Gen2WorldMap,
	tileset: Gen2WorldTileset,
	start_cell: Vector2i = Vector2i.ZERO,
	world_state: Gen2WorldState = null,
) -> void:
	data = game_data
	state = world_state if world_state != null else Gen2WorldState.new()
	state.changed.connect(_on_world_state_changed)
	inventory = Gen2WorldInventory.new(data, state)
	state.ensure_roaming_mons(data.world_roaming_mons())
	current_map = map
	current_tileset = tileset
	player_cell = _clamp_cell(start_cell)
	_load_objects()


func map_id() -> Vector2i:
	return Vector2i(current_map.group, current_map.number) if current_map != null else Vector2i(-1, -1)


func snapshot() -> Gen2WorldSnapshot:
	return Gen2WorldSnapshot.from_world(self)


func map_size_cells() -> Vector2i:
	if current_map == null:
		return Vector2i.ZERO
	return Vector2i(current_map.collision_width, current_map.collision_height)


func map_size_pixels() -> Vector2i:
	return map_size_cells() * CELL_PIXELS


func visible_origin_cell() -> Vector2i:
	if current_map == null:
		return Vector2i.ZERO
	var size: Vector2i = map_size_cells()
	var max_x: int = maxi(0, size.x - VIEW_CELLS.x)
	var max_y: int = maxi(0, size.y - VIEW_CELLS.y)
	return Vector2i(
		clampi(player_cell.x - floori(float(VIEW_CELLS.x) / 2.0), 0, max_x),
		clampi(player_cell.y - floori(float(VIEW_CELLS.y) / 2.0), 0, max_y)
	)


func player_view_cell() -> Vector2i:
	return player_cell - visible_origin_cell()


## The player's presentation position in walk cells: the committed cell plus any
## in-flight step. A renderer that frames its own view reads this instead of
## composing player_cell and player_step_offset_cells() itself. player_cell
## stays the authoritative logical cell.
func player_position_cells() -> Vector2:
	return Vector2(player_cell) + player_step_offset_cells()


## The framed view's top-left in fractional walk cells.
##
## visible_origin_cell() is the hardware page origin: it follows the committed
## cell, so it moves a whole cell the instant a step starts. A camera that is not
## drawing a tile page would pan a step early on that, so this frames the
## interpolated position with the same centring and map clamp. With no step in
## flight the two agree.
func visible_origin_cells() -> Vector2:
	if current_map == null:
		return Vector2.ZERO
	var size: Vector2i = map_size_cells()
	var position: Vector2 = player_position_cells()
	return Vector2(
		clampf(position.x - floorf(float(VIEW_CELLS.x) / 2.0), 0.0, float(maxi(0, size.x - VIEW_CELLS.x))),
		clampf(position.y - floorf(float(VIEW_CELLS.y) / 2.0), 0.0, float(maxi(0, size.y - VIEW_CELLS.y)))
	)


## The committed cell in pixels, offset by any in-flight walk step so a
## renderer can draw the approach to it. player_cell itself never carries
## this offset; collision, events and the snapshot never see it.
func player_pixel_position() -> Vector2i:
	return player_view_cell() * CELL_PIXELS + Vector2i(
		player_step_offset_cells() * float(CELL_PIXELS)
	)


func player_step_in_progress() -> bool:
	return _player_step_frames_remaining > 0


## The in-flight walk step's presentation offset in fractional walk cells,
## from 1.0 cell behind player_cell down to zero, so a renderer that does not
## think in hardware pixels (a 3D or free-roam mod) can still smooth against
## it without reverse-engineering CELL_PIXELS.
func player_step_offset_cells() -> Vector2:
	if _player_step_frames_remaining <= 0 or _player_step_frames_total <= 0:
		return Vector2.ZERO
	var fraction: float = float(_player_step_frames_remaining) / float(_player_step_frames_total)
	return Vector2(-_player_step_direction.x, -_player_step_direction.y) * fraction


func _start_player_step(direction: Vector2i, frames: int) -> void:
	_player_step_direction = direction
	_player_step_frames_total = maxi(0, frames)
	_player_step_frames_remaining = _player_step_frames_total


func _clear_player_step() -> void:
	_player_step_direction = Vector2i.ZERO
	_player_step_frames_total = 0
	_player_step_frames_remaining = 0
	_player_step_accumulator = 0.0


## Advances the player's walk-step offset by real elapsed time, at
## Gen2WorldAnimation's hardware-frame rate and stall catch-up cap, so both stay
## in phase after a pause. This only shrinks a presentation offset that starts
## and ends at player_cell; it never changes player_cell, collision or event
## results, and a caller that never starts a step sees no difference.
func advance_player_step(delta: float) -> bool:
	if _player_step_frames_remaining <= 0 or delta <= 0.0:
		return false
	_player_step_accumulator = minf(
		_player_step_accumulator + delta,
		Gen2WorldAnimation.FRAME_SECONDS * float(Gen2WorldAnimation.MAX_CATCHUP_FRAMES)
	)
	var changed: bool = false
	while _player_step_accumulator >= Gen2WorldAnimation.FRAME_SECONDS \
		and _player_step_frames_remaining > 0:
		_player_step_accumulator -= Gen2WorldAnimation.FRAME_SECONDS
		_player_step_frames_remaining -= 1
		changed = true
	return changed


## GetPlayerSprite: the sprite for the player's current state, not a fixed one.
func player_sprite() -> Gen2WorldSprite:
	return data.overworld_sprite(player_sprite_number) if data != null else null


func set_movement_mode(mode: StringName) -> Dictionary:
	if mode not in [MOVEMENT_WALK, MOVEMENT_SURF]:
		return {"ok": false, "reason": &"invalid_movement_mode", "mode": mode}
	movement_mode = mode
	return {"ok": true, "mode": movement_mode}


## Sets the read-only party mirror a queued script's VAR_PARTYCOUNT read, its
## CheckPokerus special and its checkpoke consult. count must be non-negative;
## has_pokerus is the source's own low-nibble-nonzero check across the whole
## party, computed by the caller because Gen2WorldAPI does not read Gen2SaveMon
## fields directly. [param species] mirrors `wPartySpecies` for `checkpoke`.
## [param moves] is one move list per slot, mirroring the party's move slots for
## `CheckPartyMove`, and [param names] one display name per slot for
## `GetPartyNickname`; TryStrengthOW asks the first and Script_UsedStrength the
## second. Only an absent summary fails a script-visible read; a summary whose
## list is empty answers "not in the party", which is what the story preview's
## own callers rely on.
func set_party_summary(
	count: int, has_pokerus: bool, species: Array[int] = [] as Array[int],
	moves: Array = [], names: Array = []
) -> Dictionary:
	if count < 0:
		return {"ok": false, "reason": &"invalid_party_summary", "count": count}
	_party_summary = {
		"count": count, "pokerus": has_pokerus, "species": species.duplicate(),
		"moves": moves.duplicate(true), "names": names.duplicate(),
	}
	return {"ok": true}


## Clears the mirror so a stale count cannot answer a later read after the
## caller stops refreshing it (for example, closing the injected preview save).
func clear_party_summary() -> void:
	_party_summary = {}


## Empty when no caller has set a summary yet; a script-visible read must fail
## rather than invent a count in that case.
func party_summary() -> Dictionary:
	return _party_summary.duplicate()


func available_fishing_rods() -> Array[StringName]:
	return inventory.owned_rods() if inventory != null else []


func fishing_state() -> StringName:
	return _fishing.state()


func fishing_busy() -> bool:
	return _fishing.is_busy()


func facing_cell() -> Vector2i:
	return player_cell + _direction_for_facing(player_facing)


func fishing_request(
	rod: StringName,
	random: RandomNumberGenerator = null,
	force_encounter: bool = false,
) -> Dictionary:
	if current_map == null or data == null:
		return _fishing_failure(&"missing_map")
	if inventory == null or not inventory.owns_rod(rod):
		return _fishing_failure(&"rod_not_owned")
	var context: Dictionary = _fishing_context(rod)
	if not bool(context.get("ok", false)):
		return _fishing_failure(StringName(context.get("reason", &"cannot_fish")))
	return _fishing.begin(
		rod,
		context["record"],
		int(context["fish_group"]),
		int(context["selected_fish_group"]),
		object_time_of_day,
		data.world_fishing_time_groups(),
		map_id(),
		player_cell,
		player_facing,
		context["facing_cell"],
		movement_mode,
		random,
		force_encounter,
	)


func advance_fishing() -> Dictionary:
	return _fishing.advance()


func cancel_fishing() -> Dictionary:
	return _fishing.cancel()


## engine/events/overworld.asm's CutFunction, staged rather than applied.
##
## The source order is load bearing: .CheckAble tests ENGINE_HIVEBADGE before it
## ever looks at the tile, so a player without the badge is told about the badge
## even while facing a cuttable tree. A match records the block, replacement and
## animation the way CheckMapForSomethingToCut fills wCutWhirlpool*; nothing is
## written until complete_cut(), because Script_Cut shows its text first and only
## then calls CutDownTreeOrGrass.
func cut_request() -> Dictionary:
	if current_map == null or current_tileset == null:
		return _cut_failure(&"missing_map")
	if not _pending_cut.is_empty():
		return _cut_failure(&"cut_in_progress")
	var crystal: bool = Gen2WorldState.is_crystal_profile(data)
	if not state.is_engine_flag_active(
		Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_HIVE, crystal)
	):
		return _cut_failure(&"badge_required")
	var target: Vector2i = facing_cell()
	if not Gen2WorldFieldMove.cuttable(collision_code_at(target)):
		return _cut_failure(&"nothing_to_cut")
	var block_cell: Vector2i = _script_block_cell(target)
	var replacement: Dictionary = Gen2WorldFieldMove.cut_replacement(
		current_map.tileset, block_at(block_cell.x, block_cell.y), crystal
	)
	if not bool(replacement.get("ok", false)):
		return _cut_failure(&"nothing_to_cut")
	_pending_cut = {
		"ok": true,
		"kind": &"cut_requested",
		"move": Gen2WorldFieldMove.MOVE_CUT,
		"cell": target,
		"block_cell": block_cell,
		"block": int(replacement["block"]),
		"animation": int(replacement["animation"]),
	}
	return _pending_cut.duplicate(true)


## Empty until cut_request() succeeds. A host shows its text while this is set.
func pending_cut() -> Dictionary:
	return _pending_cut.duplicate(true)


## CutDownTreeOrGrass: writes the replacement into the loaded map's block grid.
## change_block() already re-resolves collision through the tileset and drops the
## override on a map change or reload, which is the cartridge's own behavior,
## since the routine writes wOverworldMapBlocks and a map load re-reads the
## block data from ROM. The tree regrows on the next visit.
func complete_cut() -> Dictionary:
	if _pending_cut.is_empty():
		return _cut_failure(&"no_pending_cut")
	var request: Dictionary = _pending_cut
	_pending_cut = {}
	var block_cell: Vector2i = request["block_cell"]
	var changed: Dictionary = change_block(block_cell.x, block_cell.y, int(request["block"]))
	if not bool(changed.get("ok", false)):
		return changed
	return {
		"ok": true,
		"kind": &"cut_applied",
		"move": int(request["move"]),
		"cell": request["cell"],
		"block_cell": block_cell,
		"block": int(request["block"]),
		"animation": int(request["animation"]),
	}


static func _cut_failure(reason: StringName) -> Dictionary:
	return {"ok": false, "kind": &"cut_failed", "reason": reason}


## engine/events/overworld.asm's SurfFunction .TrySurf, staged rather than
## applied, for the same reason Cut is: UsedSurfScript changes nothing until its
## text is acknowledged.
##
## The refusal order is the source's. The badge is tested before the player's own
## state and before the tile, so a player without the Fog Badge is told about the
## badge whether or not the water in front of them is surfable. CheckBadge itself
## is what pushes that text, which is why this reports the same badge_required
## Cut does. [param species] is the chosen party member's, for GetSurfType.
##
## The source's wBikeFlags branch has no counterpart here, since no bike exists.
func surf_request(species: int = 0) -> Dictionary:
	if current_map == null or current_tileset == null:
		return _surf_failure(&"missing_map")
	if not _pending_surf.is_empty():
		return _surf_failure(&"surf_in_progress")
	var crystal: bool = Gen2WorldState.is_crystal_profile(data)
	if not state.is_engine_flag_active(
		Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_FOG, crystal)
	):
		return _surf_failure(&"badge_required")
	if movement_mode == MOVEMENT_SURF:
		return _surf_failure(&"already_surfing")
	var target: Vector2i = facing_cell()
	if collision_permission_at(target) != Gen2WorldCollision.WATER_TILE:
		return _surf_failure(&"cannot_surf")
	var direction: Vector2i = _direction_for_facing(player_facing)
	# CheckDirection: the standing cell's own permissions must not wall off the
	# way the player faces.
	var face: int = Gen2WorldCollision.face_mask_for_direction(direction)
	if face != 0 and (tile_permissions_at(player_cell) & face) != 0:
		return _surf_failure(&"cannot_surf")
	# CheckFacingObject is Crystal only. pokegold's .TrySurf omits it and carries
	# the "You can Surf on top of NPCs" bug comment.
	if crystal and object_at(target) != null:
		return _surf_failure(&"cannot_surf")
	_pending_surf = {
		"ok": true,
		"kind": &"surf_requested",
		"move": Gen2WorldFieldMove.MOVE_SURF,
		"cell": target,
		"direction": direction,
		"sprite": Gen2WorldFieldMove.surf_sprite(species),
	}
	return _pending_surf.duplicate(true)


## Empty until surf_request() succeeds. A host shows its text while this is set.
func pending_surf() -> Dictionary:
	return _pending_surf.duplicate(true)


## The rest of UsedSurfScript after its waitbutton: writevar VAR_MOVEMENT,
## UpdatePlayerSprite, then SurfStartStep's single slow_step into the water.
##
## That step is an applymovement, not player input, so it neither consumes a
## repel step nor rolls an encounter, and it is not re-validated: .TrySurf
## already checked the cell, and the movement engine does not check again.
func complete_surf() -> Dictionary:
	if _pending_surf.is_empty():
		return _surf_failure(&"no_pending_surf")
	var request: Dictionary = _pending_surf
	_pending_surf = {}
	movement_mode = MOVEMENT_SURF
	player_sprite_number = int(request["sprite"])
	player_cell = request["cell"]
	_start_player_step(request["direction"], STEP_FRAMES_NPC_WALK)
	return {
		"ok": true,
		"kind": &"surf_applied",
		"move": int(request["move"]),
		"cell": player_cell,
		"sprite": player_sprite_number,
	}


static func _surf_failure(reason: StringName) -> Dictionary:
	return {"ok": false, "kind": &"surf_failed", "reason": reason}


## engine/events/overworld.asm's WhirlpoolFunction .TryWhirlpool, staged the way
## Cut is: TryWhirlpoolMenu fills the same wCutWhirlpool* slots, and
## Script_UsedWhirlpool reaches DisappearWhirlpool only after UseWhirlpoolText.
##
## .TryWhirlpool checks ENGINE_GLACIERBADGE before the tile, the same order
## .CheckAble has. It checks no player state at all: the source neither requires
## nor refuses surfing, so a player facing a whirlpool from land resolves too.
func whirlpool_request() -> Dictionary:
	if current_map == null or current_tileset == null:
		return _whirlpool_failure(&"missing_map")
	if not _pending_whirlpool.is_empty():
		return _whirlpool_failure(&"whirlpool_in_progress")
	if not state.is_engine_flag_active(Gen2WorldState.badge_flag(
		Gen2WorldFieldMove.BADGE_GLACIER, Gen2WorldState.is_crystal_profile(data)
	)):
		return _whirlpool_failure(&"badge_required")
	var target: Vector2i = facing_cell()
	if not Gen2WorldFieldMove.whirlpool_tile(collision_code_at(target)):
		return _whirlpool_failure(&"nothing_to_whirlpool")
	var block_cell: Vector2i = _script_block_cell(target)
	var replacement: Dictionary = Gen2WorldFieldMove.whirlpool_replacement(
		current_map.tileset, block_at(block_cell.x, block_cell.y)
	)
	if not bool(replacement.get("ok", false)):
		return _whirlpool_failure(&"nothing_to_whirlpool")
	_pending_whirlpool = {
		"ok": true,
		"kind": &"whirlpool_requested",
		"move": Gen2WorldFieldMove.MOVE_WHIRLPOOL,
		"cell": target,
		"block_cell": block_cell,
		"block": int(replacement["block"]),
		"animation": int(replacement["animation"]),
	}
	return _pending_whirlpool.duplicate(true)


## Empty until whirlpool_request() succeeds. A host shows its text while this is set.
func pending_whirlpool() -> Dictionary:
	return _pending_whirlpool.duplicate(true)


## DisappearWhirlpool, which writes the replacement block and re-runs
## GetMovementPermissions exactly as CutDownTreeOrGrass does, so the override
## dies with the loaded map and the whirlpool returns on the next visit.
func complete_whirlpool() -> Dictionary:
	if _pending_whirlpool.is_empty():
		return _whirlpool_failure(&"no_pending_whirlpool")
	var request: Dictionary = _pending_whirlpool
	_pending_whirlpool = {}
	var block_cell: Vector2i = request["block_cell"]
	var changed: Dictionary = change_block(block_cell.x, block_cell.y, int(request["block"]))
	if not bool(changed.get("ok", false)):
		return changed
	return {
		"ok": true,
		"kind": &"whirlpool_applied",
		"move": int(request["move"]),
		"cell": request["cell"],
		"block_cell": block_cell,
		"block": int(request["block"]),
		"animation": int(request["animation"]),
	}


static func _whirlpool_failure(reason: StringName) -> Dictionary:
	return {"ok": false, "kind": &"whirlpool_failed", "reason": reason}


## engine/events/overworld.asm's StrengthFunction .TryStrength, staged the way
## the other three are because Script_UsedStrength sets nothing until after its
## text either.
##
## Unlike them, .TryStrength is a badge check and nothing else: no faced tile, no
## block table, no player state, and no check that a boulder is even in front.
## Its .AlreadyUsingStrength branch is annotated unreferenced in both pins, so an
## already-active flag is not a refusal here. [param species] is the chosen party
## member's, for SetStrengthFlag's wStrengthSpecies.
func strength_request(species: int = 0) -> Dictionary:
	if current_map == null or current_tileset == null:
		return _strength_failure(&"missing_map")
	if not _pending_strength.is_empty():
		return _strength_failure(&"strength_in_progress")
	if not state.is_engine_flag_active(Gen2WorldState.badge_flag(
		Gen2WorldFieldMove.BADGE_PLAIN, Gen2WorldState.is_crystal_profile(data)
	)):
		return _strength_failure(&"badge_required")
	_pending_strength = {
		"ok": true,
		"kind": &"strength_requested",
		"move": Gen2WorldFieldMove.MOVE_STRENGTH,
		"species": species,
	}
	return _pending_strength.duplicate(true)


## Empty until strength_request() succeeds. A host shows its text while this is set.
func pending_strength() -> Dictionary:
	return _pending_strength.duplicate(true)


## SetStrengthFlag: the engine flag plus wStrengthSpecies, which is only read
## back by Script_UsedStrength's own cry. Nothing in the pinned sources ever
## clears the flag, so this is the one write and it persists for the save.
func complete_strength() -> Dictionary:
	if _pending_strength.is_empty():
		return _strength_failure(&"no_pending_strength")
	var request: Dictionary = _pending_strength
	_pending_strength = {}
	state.set_engine_flag(
		Gen2WorldState.strength_active_flag(Gen2WorldState.is_crystal_profile(data)), true
	)
	return {
		"ok": true,
		"kind": &"strength_applied",
		"move": int(request["move"]),
		"species": int(request["species"]),
	}


## Whether BIKEFLAGS_STRENGTH_ACTIVE_F is set, the single condition
## DoPlayerMovement.CheckStrengthBoulder and TryStrengthOW both read.
func strength_active() -> bool:
	return state.is_engine_flag_active(
		Gen2WorldState.strength_active_flag(Gen2WorldState.is_crystal_profile(data))
	)


static func _strength_failure(reason: StringName) -> Dictionary:
	return {"ok": false, "kind": &"strength_failed", "reason": reason}


## Rolls an encounter from the current map. Auto mode preserves the existing
## terrain behavior; an explicit rod method uses the map header's fishing
## group. The caller supplies the generator so tests can reproduce a result.
func encounter_request(
	random: RandomNumberGenerator = null, force_encounter: bool = false,
	method: StringName = &"auto", lead_level: int = -1
) -> Dictionary:
	if current_map == null or data == null:
		return {}
	if method in [
		Gen2WorldEncounter.METHOD_OLD_ROD,
		Gen2WorldEncounter.METHOD_GOOD_ROD,
		Gen2WorldEncounter.METHOD_SUPER_ROD,
	]:
		if inventory == null or not inventory.owns_rod(method):
			return {}
		var context: Dictionary = _fishing_context(method)
		if not bool(context.get("ok", false)):
			return {}
		var fish_group: int = int(context["fish_group"])
		var selected_group: int = int(context["selected_fish_group"])
		var fishing_record: Dictionary = context["record"]
		var fishing: Dictionary = Gen2WorldEncounter.resolve_fishing(
			fishing_record, method, object_time_of_day, data.world_fishing_time_groups(),
			random, force_encounter
		)
		if fishing.is_empty():
			return {}
		fishing["map"] = map_id()
		fishing["cell"] = player_cell
		fishing["fish_group"] = fish_group
		fishing["selected_fish_group"] = selected_group
		fishing["movement"] = movement_mode
		fishing["facing"] = player_facing
		fishing["facing_cell"] = context["facing_cell"]
		return fishing
	if method != &"auto" and method not in [
		Gen2WorldEncounter.METHOD_GRASS, Gen2WorldEncounter.METHOD_SURF,
	]:
		return {}
	var permission: int = collision_permission_at(player_cell)
	var terrain_method: StringName = method
	if terrain_method == &"auto" and permission == Gen2WorldCollision.WATER_TILE:
		terrain_method = Gen2WorldEncounter.METHOD_SURF
	elif terrain_method == &"auto" and permission == Gen2WorldCollision.LAND_TILE:
		terrain_method = Gen2WorldEncounter.METHOD_GRASS
	if terrain_method not in [Gen2WorldEncounter.METHOD_GRASS, Gen2WorldEncounter.METHOD_SURF]:
		return {}
	var source: StringName = Gen2WorldEncounter.SOURCE_NORMAL
	var record: Dictionary = data.world_encounter(terrain_method, current_map.group, current_map.number)
	if state.swarm_active_on(current_map.group, current_map.number):
		var swarm_method: StringName = &"swarm_grass" if terrain_method == Gen2WorldEncounter.METHOD_GRASS else &"swarm_water"
		var swarm_record: Dictionary = data.world_encounter(
			swarm_method, current_map.group, current_map.number
		)
		if not swarm_record.is_empty():
			record = swarm_record
			source = Gen2WorldEncounter.SOURCE_SWARM
	var resolved: Dictionary = Gen2WorldEncounter.resolve(
		record, terrain_method, object_time_of_day, random, force_encounter, {
			"source": source,
			"roaming_mons": state.roaming_mons(),
			"map_group": current_map.group,
			"map_number": current_map.number,
			"repel_steps": state.repel_steps(),
			"lead_level": lead_level,
		}
	)
	if resolved.is_empty():
		return {}
	resolved["map"] = map_id()
	resolved["cell"] = player_cell
	resolved["fish_group"] = current_map.fish_group
	resolved["movement"] = movement_mode
	return resolved


func set_repel_steps(steps: int) -> void:
	state.set_repel_steps(steps)


func repel_steps() -> int:
	return state.repel_steps()


func set_swarm_map(map_key: Vector2i, active: bool = true, fishing_species: int = 0) -> void:
	state.set_swarm_map(map_key, active, fishing_species)


func roaming_mons() -> Array:
	return state.roaming_mons()


func advance_roaming(random: RandomNumberGenerator = null) -> Array:
	return state.advance_roaming(data.world_roaming_maps(), random)


## Applies one host schedule tick to the imported roaming graph. Swarm state is
## returned alongside it so a clock, radio event or save host can publish one
## coherent update without reaching into Gen2WorldState.
func advance_schedule(random: RandomNumberGenerator = null) -> Dictionary:
	var moved: Array = advance_roaming(random)
	return {
		"ok": true,
		"kind": &"world_schedule_updated",
		"roaming": moved,
		"swarm_map": state.swarm_map(),
		"fishing_swarm_species": state.fishing_swarm_species(),
	}


func set_world_clock(day: int, hour: int, minute: int) -> void:
	var next_day: int = posmod(day, Gen2WorldClock.DAYS_PER_WEEK)
	if next_day != world_day and state != null:
		state.reset_daily_flags(Gen2WorldState.is_crystal_profile(data))
	world_day = next_day
	world_hour = posmod(hour, Gen2WorldClock.HOURS_PER_DAY)
	world_minute = posmod(minute, Gen2WorldClock.MINUTES_PER_HOUR)


func world_clock() -> Dictionary:
	return {"day": world_day, "hour": world_hour, "minute": world_minute}


func daylight_saving_time_enabled() -> bool:
	return dst_enabled


func set_daylight_saving_time_enabled(enabled: bool) -> void:
	dst_enabled = enabled


func phone_ring_active() -> bool:
	return _phone_ring != null and not _phone_ring.is_finished()


func pending_phone_ring() -> Dictionary:
	if _phone_ring == null:
		return {}
	var ring: Dictionary = _phone_ring.snapshot()
	ring["kind"] = _phone_ring_request.get("kind", &"phone_incoming")
	ring["phone"] = (_phone_ring_request.get("phone", {}) as Dictionary).duplicate(true)
	ring["contact"] = (_phone_ring_request.get("contact", {}) as Dictionary).duplicate(true)
	return ring


## Advances the source ring timing and starts the imported phone script when
## both rings have completed. A phone ring is transient runtime state and is
## intentionally absent from world snapshots.
func advance_phone_ring(delta: float) -> Array:
	if _phone_ring == null:
		return []
	var progress: Dictionary = _phone_ring.advance(delta)
	if not bool(progress.get("finished", false)):
		return []
	var request: Dictionary = _phone_ring_request.duplicate(true)
	_phone_ring = null
	_phone_ring_request = {}
	_enqueue_script(request)
	return run_event_queue(false)


## Queues a source-style incoming call after checking the entrance, receive
## timer, random roll, service map, registration, time and same-map rules.
func request_incoming_phone_call(
	standing_on_entrance: bool = true,
	timer_ready: bool = true,
	random_byte: int = 0,
	force: bool = false,
	selection_byte: int = 0,
) -> Array:
	if phone_ring_active():
		return [{"ok": true, "status": &"phone_ring", "event": pending_phone_ring()}]
	var resolved: Dictionary = Gen2WorldPhoneHost.resolve_incoming(
		data, state, current_map, world_hour, standing_on_entrance, timer_ready,
		random_byte, force, selection_byte
	)
	if not bool(resolved.get("ok", false)):
		return [{"ok": false, "status": &"phone_unavailable", "reason": resolved.get("reason", &"phone_unavailable")}]
	var contact: Dictionary = resolved["contact"]
	var request: Dictionary = {
		"kind": &"phone_incoming",
		"map_group": current_map.group,
		"map_number": current_map.number,
		"bank": int(resolved["script"]["bank"]),
		"script": int(resolved["script"]["address"]),
		"phone": resolved["phone"],
		"contact": contact,
		"reset_receive_timer": true,
	}
	return _start_phone_ring(request)


## Queues a source-style special call. The pending call remains in world state
## until the imported phone script clears VAR_SPECIALPHONECALL.
func request_special_phone_call(call_id: int) -> Array:
	if phone_ring_active():
		return [{"ok": true, "status": &"phone_ring", "event": pending_phone_ring()}]
	var resolved: Dictionary = Gen2WorldPhoneHost.resolve_special(
		data, current_map, call_id, world_hour
	)
	if not bool(resolved.get("ok", false)):
		return [{
			"ok": false, "status": &"special_phone_unavailable",
			"reason": resolved.get("reason", &"special_phone_unavailable"),
		}]
	var request: Dictionary = {
		"kind": &"phone_special",
		"map_group": current_map.group,
		"map_number": current_map.number,
		"bank": int(resolved["script"]["bank"]),
		"script": int(resolved["script"]["address"]),
		"phone": resolved["phone"],
		"contact": resolved["contact"],
		"special_call_id": call_id,
		"reset_receive_timer": true,
	}
	return _start_phone_ring(request, 30)


## Checks the pending special call before ordinary step effects, matching the
## source CountStep path. A failed condition leaves the pending call queued.
func try_special_phone_call() -> Dictionary:
	if state == null:
		return {"ok": false, "reason": &"missing_world_state", "attempted": false}
	var call_id: int = state.pending_special_phone_call()
	if call_id <= 0:
		return {"ok": true, "attempted": false, "results": []}
	var resolved: Dictionary = Gen2WorldPhoneHost.resolve_special(
		data, current_map, call_id, world_hour
	)
	if not bool(resolved.get("ok", false)):
		return {
			"ok": true,
			"attempted": false,
			"call_id": call_id,
			"reason": resolved.get("reason", &"special_phone_unavailable"),
			"results": [],
		}
	return {
		"ok": true,
		"attempted": true,
		"call_id": call_id,
		"results": request_special_phone_call(call_id),
	}


## Advances the receive timer by completed game minutes. The source checks the
## entrance before it checks the timer, so a due call waits until the player is
## standing on a door, staircase or cave tile.
func advance_phone_schedule(
	minutes: int = 1,
	random: RandomNumberGenerator = null,
	selection_byte: int = -1,
	force: bool = false
) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": &"missing_world_state", "timer_ready": false}
	if phone_ring_active():
		return {
			"ok": true,
			"timer_ready": state.phone_receive_ready(),
			"ringing": true,
			"results": [{"ok": true, "status": &"phone_ring", "event": pending_phone_ring()}],
		}
	var crossed: bool = state.advance_phone_receive_timer(minutes)
	var attempt: Dictionary = {
		"ok": true,
		"timer_ready": state.phone_receive_ready(),
		"timer_crossed": crossed,
		"results": [],
	}
	if not state.phone_receive_ready() or not standing_on_phone_entrance():
		return attempt
	var random_byte: int = random.randi_range(0, 255) if random != null else 0
	var chosen: int = selection_byte
	if chosen < 0:
		chosen = random.randi_range(0, 255) if random != null else 0
	state.consume_phone_receive_timer()
	attempt["attempted"] = true
	attempt["results"] = request_incoming_phone_call(
		true, true, random_byte, force, chosen
	)
	return attempt


## Checks a due receive timer after movement or map setup. This covers the
## source path where elapsed time made the timer ready away from an entrance.
func try_receive_phone_call(
	random: RandomNumberGenerator = null, selection_byte: int = -1, force: bool = false
) -> Dictionary:
	return advance_phone_schedule(0, random, selection_byte, force)


func standing_on_phone_entrance(cell: Vector2i = player_cell) -> bool:
	return PHONE_ENTRANCE_COLLISIONS.has(collision_code_at(cell))


func registered_phone_contacts() -> Array:
	return Gen2WorldPhoneHost.registered_contact_summaries(data, state)


## Queues the selected outgoing caller script. Pokegear presentation can use
## this boundary without duplicating phone eligibility rules in a scene.
func request_outgoing_phone_call(contact_id: int) -> Array:
	if phone_ring_active():
		return [{"ok": true, "status": &"phone_ring", "event": pending_phone_ring()}]
	var resolved: Dictionary = Gen2WorldPhoneHost.resolve_outgoing(
		data, state, current_map, contact_id, world_hour
	)
	if not bool(resolved.get("ok", false)):
		return [{"ok": false, "status": &"phone_unavailable", "reason": resolved.get("reason", &"phone_unavailable")}]
	var request: Dictionary = {
		"kind": &"phone_outgoing",
		"map_group": current_map.group,
		"map_number": current_map.number,
		"bank": int(resolved["script"]["bank"]),
		"script": int(resolved["script"]["address"]),
		"phone": resolved["phone"],
		"contact": resolved["contact"],
	}
	return _start_phone_ring(request)


func _start_phone_ring(request: Dictionary, lead_frames: int = 0) -> Array:
	if _phone_ring != null:
		return [{"ok": false, "status": &"phone_unavailable", "reason": &"phone_ring_active"}]
	_phone_ring_request = request.duplicate(true)
	_phone_ring = Gen2WorldPhoneRing.new(lead_frames)
	return [{
		"ok": true,
		"status": &"phone_ring",
		"event": pending_phone_ring(),
		"request": request.duplicate(true),
	}]


func _fishing_group_for_state(group: int) -> int:
	var fishing_swarm: int = state.fishing_swarm_species()
	if fishing_swarm == 0:
		return group
	if group == 11 and fishing_swarm == 0xD3:
		return 6
	if group == 12 and fishing_swarm == 0xDF:
		return 7
	return group


func _fishing_context(rod: StringName) -> Dictionary:
	if not Gen2WorldFishing.is_rod(rod):
		return {"ok": false, "reason": &"invalid_rod"}
	if inventory == null or not inventory.owns_rod(rod):
		return {"ok": false, "reason": &"rod_not_owned"}
	if movement_mode == MOVEMENT_SURF:
		return {"ok": false, "reason": &"cannot_fish_while_surfing"}
	var target: Vector2i = facing_cell()
	if collision_permission_at(target) != Gen2WorldCollision.WATER_TILE:
		return {"ok": false, "reason": &"not_facing_water"}
	var fish_group: int = current_map.fish_group
	var selected_group: int = _fishing_group_for_state(fish_group)
	var record: Dictionary = data.world_fishing_group(selected_group)
	if fish_group <= 0 or selected_group <= 0 or record.is_empty():
		return {"ok": false, "reason": &"no_fishing_group"}
	return {
		"ok": true,
		"fish_group": fish_group,
		"selected_fish_group": selected_group,
		"record": record,
		"facing_cell": target,
	}


func tick() -> bool:
	var changed: bool = false
	for object: Gen2WorldObject in objects:
		changed = object.tick_emote() or changed
	return changed


## Builds the source trainer approach path. The cartridge's
## ComputePathToWalkToPlayer routine emits the longer axis first, with the
## final movement removed by TrainerWalkToPlayer so the trainer stops before
## the player. This helper keeps that path rule deterministic and scene-free.
static func trainer_approach_path(start_cell: Vector2i, target_cell: Vector2i) -> Array:
	var path: Array = []
	var x_delta: int = target_cell.x - start_cell.x
	var y_delta: int = target_cell.y - start_cell.y
	var x_direction: Vector2i = Vector2i.RIGHT if x_delta > 0 else Vector2i.LEFT
	var y_direction: Vector2i = Vector2i.DOWN if y_delta > 0 else Vector2i.UP
	var x_steps: int = abs(x_delta)
	var y_steps: int = abs(y_delta)
	if x_steps >= y_steps:
		for _step: int in x_steps:
			path.append(x_direction)
		for _step: int in y_steps:
			path.append(y_direction)
	else:
		for _step: int in y_steps:
			path.append(y_direction)
		for _step: int in x_steps:
			path.append(x_direction)
	return path


## Starts the scene-free portion of SeenByTrainerScript that follows the
## encounter-music request. The screen owns pacing; the API owns validation,
## emote state and the logical object position.
func start_trainer_approach(
	object_index: int, direction: Vector2i, distance: int
) -> Dictionary:
	var plan: Dictionary = trainer_approach_plan(object_index, direction, distance)
	if not bool(plan.get("ok", false)):
		return plan
	var object: Gen2WorldObject = objects[object_index]
	object.set_emote(TRAINER_SHOCK_EMOTE, true, TRAINER_SHOCK_FRAMES)
	plan["emote_id"] = TRAINER_SHOCK_EMOTE
	plan["emote_frames"] = TRAINER_SHOCK_FRAMES
	plan["step_frames"] = TRAINER_SLOW_STEP_FRAMES
	return plan


## Returns the source trainer approach target and movement directions without
## mutating the world. A sight distance of one produces the source's empty
## movement buffer and leaves the trainer in place.
func trainer_approach_plan(
	object_index: int, direction: Vector2i, distance: int
) -> Dictionary:
	if current_map == null or object_index < 0 or object_index >= objects.size():
		return {"ok": false, "reason": &"invalid_trainer_object"}
	if direction not in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		return {"ok": false, "reason": &"invalid_trainer_direction"}
	var object: Gen2WorldObject = objects[object_index]
	if object.object_type != Gen2WorldObject.OBJECTTYPE_TRAINER:
		return {"ok": false, "reason": &"not_a_trainer"}
	var target_cell: Vector2i = object.cell
	if distance > 1:
		target_cell = player_cell - direction
	var path: Array = trainer_approach_path(object.cell, target_cell)
	return {
		"ok": true,
		"object_index": object_index,
		"start_cell": object.cell,
		"target_cell": target_cell,
		"path": path,
		"distance": distance,
		"direction": direction,
	}


## Applies one source slow-step from an already validated approach plan and
## starts that object's presentation offset for the pacing caller to consume;
## the object's cell is already the destination when this returns.
func advance_trainer_approach_step(object_index: int, direction: Vector2i) -> Dictionary:
	if current_map == null or object_index < 0 or object_index >= objects.size():
		return {"ok": false, "reason": &"invalid_trainer_object"}
	var object: Gen2WorldObject = objects[object_index]
	var destination: Vector2i = object.cell + direction
	object.apply_direction(direction)
	if not can_object_walk_to(destination, object, direction):
		return {
			"ok": false, "reason": &"movement_blocked",
			"object_index": object_index, "cell": destination,
		}
	object.cell = destination
	object.start_step(direction, TRAINER_SLOW_STEP_FRAMES)
	var key: String = _object_key(current_map.group, current_map.number, object_index)
	_object_position_overrides[key] = object.cell
	_object_facing_overrides[key] = object.facing
	return {
		"ok": true, "type": &"trainer_approach_step",
		"object_index": object_index, "cell": object.cell,
		"direction": direction,
	}


## Completes the source writeobjectxy and faceobject portion of the trainer
## intro after the final movement step.
func finish_trainer_approach(object_index: int) -> Dictionary:
	if current_map == null or object_index < 0 or object_index >= objects.size():
		return {"ok": false, "reason": &"invalid_trainer_object"}
	var object: Gen2WorldObject = objects[object_index]
	object.set_emote(TRAINER_SHOCK_EMOTE, false)
	object.facing = _facing_toward(object.cell, player_cell)
	var key: String = _object_key(current_map.group, current_map.number, object_index)
	_object_position_overrides[key] = object.cell
	_object_facing_overrides[key] = object.facing
	player_facing = _facing_toward(player_cell, object.cell)
	return {
		"ok": true, "type": &"trainer_approach_finished",
		"object_index": object_index, "cell": object.cell,
		"facing": object.facing, "player_facing": player_facing,
	}


func set_object_time(hour: int, time_of_day: int) -> void:
	object_hour = clampi(hour, 0, 23)
	object_time_of_day = clampi(time_of_day, 0, 3)
	for object: Gen2WorldObject in objects:
		object.active = object.visible_with_state(object_hour, object_time_of_day, state)
		var key: String = _object_key(current_map.group, current_map.number, object.index)
		if _object_visibility_overrides.has(key):
			object.active = bool(_object_visibility_overrides[key])
		if object.deleted:
			object.active = false


func set_event_flag(flag: int, active: bool = true) -> void:
	state.set_event_flag(flag, active)


func clear_event_flag(flag: int) -> void:
	state.clear_event_flag(flag)


func event_flag_active(flag: int) -> bool:
	return state.is_event_flag_active(flag)


func visible_objects() -> Array:
	var out: Array = []
	for object: Gen2WorldObject in objects:
		if object.active and not object.deleted and object.sprite != null:
			out.append(object)
	return out


func object_at(cell: Vector2i, visible_only: bool = true) -> Gen2WorldObject:
	for object: Gen2WorldObject in objects:
		if object.cell != cell or object.deleted or (visible_only and not object.active):
			continue
		if object.sprite != null:
			return object
	return null


func block_at(block_x: int, block_y: int) -> int:
	if current_map == null:
		return 0
	# Every drawn tile asks this, so the key is only built when a changeblock has
	# actually put an override on the loaded map.
	if not _block_overrides.is_empty():
		var key: String = _block_key(current_map, block_x, block_y)
		if _block_overrides.has(key):
			return int(_block_overrides[key])
	return current_map.block_at(block_x, block_y)


func change_block(block_x: int, block_y: int, block: int) -> Dictionary:
	if current_map == null or current_tileset == null:
		return {"ok": false, "reason": &"missing_map"}
	if block_x < 0 or block_y < 0 or block_x >= current_map.width_blocks \
		or block_y >= current_map.height_blocks:
		return {
			"ok": false, "reason": &"invalid_block_cell",
			"cell": Vector2i(block_x, block_y),
		}
	if block < 0 or block >= current_tileset.block_count:
		return {"ok": false, "reason": &"invalid_block", "block": block}
	var key: String = _block_key(current_map, block_x, block_y)
	if block == current_map.block_at(block_x, block_y):
		_block_overrides.erase(key)
	else:
		_block_overrides[key] = block
	return {
		"ok": true,
		"kind": &"block_change",
		"cell": Vector2i(block_x, block_y),
		"block": block,
	}


func command_queues() -> Array:
	var out: Array = []
	for key: Variant in _command_queues:
		out.append((_command_queues[key] as Dictionary).duplicate(true))
	return out


func apply_command_queue_write(bank: int, address: int) -> Dictionary:
	var key: String = "%d:%04X" % [bank, address]
	var queue_id: int = _next_command_queue_id
	_next_command_queue_id += 1
	var queue: Dictionary = {"id": queue_id, "bank": bank, "address": address}
	# The imported payload, so a written queue carries what it does and not only
	# where it came from. A queue the cartridge has no entry for stays pointer
	# only, which is what every type but CMDQUEUE_STONETABLE is.
	if data != null:
		var record: Dictionary = data.world_command_queue(bank, address)
		if not record.is_empty():
			queue["type"] = int(record.get("type", 0))
			queue["rows"] = record.get("rows", [])
	_command_queues[key] = queue
	return {"ok": true, "kind": &"command_queue_written", "queue": _command_queues[key]}


## The one-based warp index `HandleStoneQueue.check_on_warp` counts, or 0 when
## the cell carries no warp event. One-based because the source's
## `.found_warp` answers `count - remaining + 1`.
func warp_index_at(cell: Vector2i) -> int:
	if current_map == null:
		return 0
	var warps: Array = current_map.events.get("warps", [])
	for index: int in warps.size():
		var event: Dictionary = warps[index]
		if int(event.get("x", -1)) == cell.x and int(event.get("y", -1)) == cell.y:
			return index + 1
	return 0


## engine/overworld/cmd_queue.asm's CmdQueue_StoneTable and home/stone_queue.asm's
## HandleStoneQueue, as one question: which script does this boulder's cell fire?
##
## The source's own order, all five tests. The object must be a Strength boulder,
## standing on a pit tile (`CheckPitTile`, COLL_PIT or COLL_PIT_68), not mid-step,
## on a warp event, and named by a written CMDQUEUE_STONETABLE row for that
## warp. Answers an empty Dictionary when any of them refuses.
##
## The row's object id is an `object_const_def` constant, which starts at 2, so
## it is compared against the object's own index plus two. That is the same
## mapping `applymovement` uses, and the source makes it by comparing against
## OBJECT_MAP_OBJECT_INDEX + 1 over a table whose index zero is the player.
func stone_queue_script(boulder: Gen2WorldObject) -> Dictionary:
	if boulder == null or not boulder.is_strength_boulder() or boulder.is_stepping():
		return {}
	if not Gen2WorldCollision.is_pit_tile(collision_code_at(boulder.cell)):
		return {}
	var warp: int = warp_index_at(boulder.cell)
	if warp <= 0:
		return {}
	var object_id: int = boulder.index + 2
	for key: Variant in _command_queues:
		var queue: Dictionary = _command_queues[key]
		if int(queue.get("type", 0)) != Gen2WorldScript.CMDQUEUE_STONETABLE:
			continue
		for row: Dictionary in queue.get("rows", []):
			if int(row.get("warp", -1)) != warp or int(row.get("object", -1)) != object_id:
				continue
			# The row scripts were collected under the queue's own bank, which is
			# the map script bank the writecmdqueue ran in.
			return {"bank": int(queue.get("bank", 0)), "script": int(row.get("script", 0))}
	return {}


func apply_command_queue_delete(queue_id: int) -> Dictionary:
	for key: Variant in _command_queues:
		var queue: Dictionary = _command_queues[key]
		if int(queue.get("id", -1)) != queue_id:
			continue
		_command_queues.erase(key)
		return {"ok": true, "kind": &"command_queue_deleted", "queue_id": queue_id}
	return {"ok": true, "kind": &"command_queue_deleted", "queue_id": queue_id, "removed": false}


## The expanded graphics tile at a map-space tile coordinate, or -1 outside
## the map. A map block contains sixteen tiles in row-major order.
func tile_index_at(tile_x: int, tile_y: int) -> int:
	if current_map == null or current_tileset == null:
		return -1
	var map_tile_width: int = current_map.width_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH

	if tile_x < 0 or tile_y < 0 or tile_x >= map_tile_width \
		or tile_y >= current_map.height_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH:
		return -1

	var block: int = block_at(
		floori(float(tile_x) / float(RomLayout.MAP_BLOCK_TILE_WIDTH)),
		floori(float(tile_y) / float(RomLayout.MAP_BLOCK_TILE_WIDTH)),
	)
	var local_tile: int = (tile_y & 3) * RomLayout.MAP_BLOCK_TILE_WIDTH + (tile_x & 3)
	return current_tileset.tile_index(block, local_tile)


## Returns the visible 20x18 graphics-tile page in row-major order. -1 marks
## the padding around maps smaller than the hardware viewport.
##
## This is [method tile_index_at] for 360 tiles, written out rather than called
## 360 times: it is on the draw path, and the per-tile call did the same block
## division and bounds check for every tile of the same block row.
func visible_tile_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(VIEW_TILES.x * VIEW_TILES.y)
	out.fill(-1)
	if current_map == null or current_tileset == null:
		return out

	# visible_origin_cell() is clamped to the map, so both coordinates below are
	# non-negative and the block divisions are plain integer divisions.
	var origin: Vector2i = visible_origin_cell() * RomLayout.MAP_BLOCK_CELL_WIDTH
	var tile_width: int = RomLayout.MAP_BLOCK_TILE_WIDTH
	var map_tile_width: int = current_map.width_blocks * tile_width
	var map_tile_height: int = current_map.height_blocks * tile_width
	for y: int in VIEW_TILES.y:
		var tile_y: int = origin.y + y
		if tile_y >= map_tile_height:
			break
		var row: int = y * VIEW_TILES.x
		@warning_ignore("integer_division")
		var block_y: int = tile_y / tile_width
		var local_row: int = (tile_y % tile_width) * tile_width
		for x: int in VIEW_TILES.x:
			var tile_x: int = origin.x + x
			if tile_x >= map_tile_width:
				break
			@warning_ignore("integer_division")
			var block: int = block_at(tile_x / tile_width, block_y)
			out[row + x] = current_tileset.tile_index(block, local_row + tile_x % tile_width)
	return out


## The raw cartridge permission byte at a walk cell.
##
## The imported grid already holds the code the tileset gave each cell, so it is
## the answer unless a changeblock has replaced the block this cell belongs to.
## An overridden block has to be looked up in the tileset instead, because the
## imported grid still describes the block the cartridge shipped.
func collision_code_at(cell: Vector2i) -> int:
	if current_map == null or current_tileset == null:
		return -1
	if _block_overrides.is_empty():
		return current_map.collision_at(cell.x, cell.y)
	var block_x: int = floori(float(cell.x) / float(RomLayout.MAP_BLOCK_CELL_WIDTH))
	var block_y: int = floori(float(cell.y) / float(RomLayout.MAP_BLOCK_CELL_WIDTH))
	var block: int = block_at(block_x, block_y)
	if block == current_map.block_at(block_x, block_y):
		return current_map.collision_at(cell.x, cell.y)
	return current_tileset.collision_index(
		block,
		cell.x & (RomLayout.MAP_BLOCK_CELL_WIDTH - 1),
		cell.y & (RomLayout.MAP_BLOCK_CELL_WIDTH - 1),
	)


func collision_permission_at(cell: Vector2i) -> int:
	return Gen2WorldCollision.permission_for(collision_code_at(cell))


## home/map.asm's GetMovementPermissions for a player standing at [param cell]:
## the standing code's own walled edges plus each neighbour's wall facing back,
## profile-split per Gen2WorldCollision.tile_permissions(). A neighbour outside
## the map answers -1, which side_wall_face_mask() treats as no wall; the
## cartridge would read a border block there, but callers already refuse an
## out-of-map destination before this matters.
func tile_permissions_at(cell: Vector2i) -> int:
	return Gen2WorldCollision.tile_permissions(
		collision_code_at(cell),
		collision_code_at(cell + Vector2i.UP),
		collision_code_at(cell + Vector2i.DOWN),
		collision_code_at(cell + Vector2i.LEFT),
		collision_code_at(cell + Vector2i.RIGHT),
		Gen2WorldState.is_crystal_profile(data),
	)


## Returns the raw warp record at a cell, or an empty Dictionary when the
## player is not standing on one. Warp destinations are one-based in the
## cartridge data, matching the map macro that writes them.
func warp_at(cell: Vector2i = player_cell) -> Dictionary:
	if current_map == null:
		return {}
	for event: Dictionary in current_map.events.get("warps", []):
		if int(event.get("x", -1)) == cell.x and int(event.get("y", -1)) == cell.y:
			return event.duplicate(true)
	return {}


## Returns all decoded event records at a cell in cartridge checking order.
## Script pointers remain data; this method does not interpret them.
func events_at(cell: Vector2i = player_cell) -> Array:
	if current_map == null:
		return []
	var out: Array = []
	for source: String in ["warps", "coord_events", "bg_events", "objects"]:
		var rows: Array = current_map.events.get(source, [])
		for index: int in rows.size():
			var raw: Dictionary = rows[index]
			if int(raw.get("x", -1)) != cell.x or int(raw.get("y", -1)) != cell.y:
				continue
			var event: Dictionary = raw.duplicate(true)
			event["kind"] = StringName(source)
			if source == "objects":
				event["object_index"] = index
			out.append(event)
	return out


## Public event boundary for the screen and future systems. By default it
## reports active decoded records without interpreting cartridge scripts. The
## optional execution flag keeps the old raw-data call stable while exposing
## the queued interpreter to callers that are ready for it.
func dispatch_events(cell: Vector2i = player_cell, execute_scripts: bool = false) -> Array:
	var events: Array = _active_events_at(cell)
	if execute_scripts:
		if _active_script == null and _script_queue.is_empty():
			_enqueue_script_events(events)
		return run_event_queue(false)
	return events


## Queues the active scripted records at a cell in cartridge source order and
## advances until the queue reaches text/button input or is empty.
func dispatch_script_events(cell: Vector2i = player_cell) -> Array:
	if _active_script == null and _script_queue.is_empty():
		_enqueue_script_events(_active_events_at(cell))
	return run_event_queue(false)


## Queues the first visible trainer who can see the player, matching the
## cartridge's trainer scan order. A trainer sees only along its facing axis,
## and a nonzero event flag prevents the encounter from being queued.
func dispatch_sight_events() -> Array:
	if _active_script != null or not _script_queue.is_empty():
		return run_event_queue(false)
	var request: Dictionary = _find_sight_request()
	if request.is_empty():
		return []
	_enqueue_script(request)
	return run_event_queue(false)


func script_input_waiting() -> bool:
	return _active_script != null and _active_script.is_waiting()


## True while a script holds the world, either running or still queued. A host
## that drives ambient motion checks this so a script keeps sole ownership of
## the objects it may be moving.
func script_busy() -> bool:
	return _active_script != null or not _script_queue.is_empty()


func pending_runtime_request() -> Dictionary:
	return _active_script.pending_runtime_request() if _active_script != null else {}


func pending_script_input() -> Dictionary:
	return _active_script.pending_input() if _active_script != null else {}


## Starts one callback type from the current map's callback table. A type of -1
## runs all callbacks in their stored order.
func dispatch_callbacks(callback_type: int = -1) -> Array:
	if current_map == null:
		return []
	if _active_script == null and _script_queue.is_empty():
		_queue_map_callbacks(callback_type)
	return run_event_queue(false)


## Runs the callbacks that belong to entering the current map. The scene calls
## this once after opening a new or validated snapshot; map transitions already
## queue the same callback set from _apply_map().
func dispatch_map_entry() -> Array:
	if current_map == null:
		return []
	if _active_script == null and _script_queue.is_empty():
		_queue_map_callbacks(-1)
		_map_entry_scene_pending = true
	return run_event_queue(false)


## Starts the first active scripted object in the cell the player is facing.
## This is the explicit interaction boundary for NPCs, signs and item-like
## objects. It never executes a hidden object or invents a fallback action.
func interact() -> Array:
	if _active_script != null or not _script_queue.is_empty():
		return run_event_queue(false)
	var target: Vector2i = facing_cell()
	var events: Array = []
	## TryObjectEvent runs before TryBGEvent in the cartridge event loop. Keep
	## that order even though events_at() exposes the cache's source order.
	for event: Dictionary in _active_events_at(target):
		if event.get("kind", &"") == &"objects" and event.has("script"):
			events.append(event)
	for event: Dictionary in _active_events_at(target):
		if event.get("kind", &"") != &"bg_events":
			continue
		if _bg_event_interacts(event) and _script_address_for_event(event) > 0:
			events.append(event)
	if not events.is_empty():
		_enqueue_script_events(events)
		return run_event_queue(false)
	## TryTileCollisionEvent runs last, only when neither an object nor a
	## background event answered (engine/overworld/events.asm PlayerEvents).
	var tile_request: Dictionary = _tile_collision_script_request(target)
	if tile_request.is_empty():
		return []
	_enqueue_script(tile_request)
	return run_event_queue(false)


## engine/events/std_collision.asm's CheckFacingTileForStdScript. Keyed by the
## faced cell's collision code, not its tile ID despite the source's own
## comment: GetFacingTileCoord returns wTileUp/Down/Left/Right, which
## GetMovementPermissions fills from GetCoordTileCollision. Returns an empty
## Dictionary when the code has no entry in TileCollisionStdScripts.
func _tile_collision_script_request(cell: Vector2i) -> Dictionary:
	if current_map == null or data == null:
		return {}
	var collision: int = collision_code_at(cell)
	var index: int = Gen2WorldCollision.tile_collision_std_index(
		collision, Gen2WorldState.is_crystal_profile(data)
	)
	if index < 0:
		return {}
	var entry: Dictionary = data.world_standard_script(index)
	if entry.is_empty():
		return {}
	return {
		"kind": &"tile_collision",
		"map_group": current_map.group,
		"map_number": current_map.number,
		"cell": cell,
		"bank": int(entry.get("bank", -1)),
		"script": int(entry.get("address", -1)),
	}


## Acknowledge the current text/button pause and continue the first queued
## script. Completed results retain the source event so a screen can react to
## them without reaching into the runner.
func run_event_queue(acknowledge: bool = false, choice: int = -1) -> Array:
	var results: Array = []
	var accept: bool = acknowledge
	var selected_choice: int = choice
	while true:
		if _active_script == null:
			if _script_queue.is_empty():
				if _map_entry_scene_pending:
					_map_entry_scene_pending = false
					_queue_map_scene()
					if not _script_queue.is_empty():
						continue
				break
			var request: Dictionary = _script_queue.pop_front()
			_active_script = Gen2WorldScriptRunner.begin(
				data, state, request, Callable(self, "_validate_script_warp"),
				script_random
			)
		var result: Dictionary = _active_script.advance(accept, selected_choice)
		accept = false
		selected_choice = -1
		if StringName(result.get("status", &"")) == &"waiting":
			results.append(result)
			break
		results.append(_finish_script_result(result))
		_active_script = null
	return results


## Completes an explicit menu or yes/no host input without allowing a default
## selection to leak into cartridge script state.
func choose_script_input(choice: int) -> Array:
	return run_event_queue(true, choice)


## Cancels the current menu or choice and resumes the queued script with a
## false result. This is distinct from choosing an imported option.
func cancel_script_input() -> Array:
	if _active_script == null:
		return []
	var results: Array = []
	var advanced: Dictionary = _active_script.cancel_input()
	if StringName(advanced.get("status", &"")) == &"waiting":
		results.append(advanced)
		return results
	results.append_array(_resume_after(advanced))
	return results


## Completes the currently pending host-owned request and resumes the same
## scene-free script invocation. The world API owns the runner lifecycle, so a
## screen never needs to reach into the runner or replace its state.
func complete_runtime_request(result: Dictionary) -> Array:
	if _active_script == null:
		return []
	var results: Array = []
	var advanced: Dictionary = _active_script.complete_runtime_request(result)
	if StringName(advanced.get("status", &"")) == &"waiting":
		results.append(advanced)
		return results
	if StringName(advanced.get("status", &"")) == &"recovered":
		results.append(advanced)
		_active_script = null
		_script_queue.clear()
		return results
	results.append_array(_resume_after(advanced))
	return results


## Closes out a resumed invocation and runs whatever was queued behind it. Both
## resume boundaries, a cancelled input and a completed host request, end the
## same way, and the terminal result must not be finished twice.
func _resume_after(advanced: Dictionary) -> Array:
	var results: Array = []
	results.append(
		_finish_script_result(advanced) if bool(advanced.get("ok", false)) else advanced
	)
	_active_script = null
	results.append_array(_drain_script_queue())
	return results


## Starts each queued script in turn and stops at the first one that waits for
## the host.
func _drain_script_queue() -> Array:
	var results: Array = []
	while _active_script == null and not _script_queue.is_empty():
		var request: Dictionary = _script_queue.pop_front()
		_active_script = Gen2WorldScriptRunner.begin(
			data, state, request, Callable(self, "_validate_script_warp"),
			script_random
		)
		var next: Dictionary = _active_script.advance()
		if StringName(next.get("status", &"")) == &"waiting":
			results.append(next)
			break
		results.append(_finish_script_result(next) if bool(next.get("ok", false)) else next)
		_active_script = null
	return results


func _active_events_at(cell: Vector2i) -> Array:
	var out: Array = []
	for event: Dictionary in events_at(cell):
		# Object records below are matched against their live cells. A source
		# movement or trainer approach can move one away from its cached cell.
		if event.get("kind", &"") == &"objects":
			continue
		if event.get("kind", &"") == &"bg_events" \
			and not _bg_event_condition_active(event):
			continue
		elif event.get("kind", &"") == &"coord_events" \
			and not _coord_event_condition_active(event):
			continue
		out.append(event)
	if current_map == null:
		return out
	var rows: Array = current_map.events.get("objects", [])
	for object: Gen2WorldObject in objects:
		if not object.active or object.cell != cell \
			or object.index < 0 or object.index >= rows.size() \
			or not rows[object.index] is Dictionary:
			continue
		var event: Dictionary = (rows[object.index] as Dictionary).duplicate(true)
		event["x"] = object.cell.x
		event["y"] = object.cell.y
		event["kind"] = &"objects"
		event["object_index"] = object.index
		out.append(event)
	return out


func _enqueue_script_events(events: Array) -> void:
	var bank: int = int(current_map.events.get("bank", 0)) if current_map != null else 0
	for event: Dictionary in events:
		if event.get("kind", &"") == &"warps" or not event.has("script"):
			continue
		var script_address: int = _script_address_for_event(event)
		if script_address <= 0:
			continue
		var request: Dictionary = {
			"kind": event.get("kind", &""),
			"map_group": current_map.group,
			"map_number": current_map.number,
			"cell": Vector2i(int(event.get("x", 0)), int(event.get("y", 0))),
			"bank": bank,
			"script": script_address,
			"event": event.duplicate(true),
		}
		var trainer_request: Dictionary = _trainer_request_for_event(event)
		if not trainer_request.is_empty():
			request = trainer_request
		_enqueue_script(request)


func _trainer_request_for_event(event: Dictionary) -> Dictionary:
	if event.get("kind", &"") != &"objects" or current_map == null:
		return {}
	var object_index: int = int(event.get("object_index", -1))
	if object_index < 0 or object_index >= objects.size():
		return {}
	var object: Gen2WorldObject = objects[object_index]
	if object.object_type != Gen2WorldObject.OBJECTTYPE_TRAINER \
		or object.trainer_data.is_empty():
		return {}
	var trainer: Dictionary = object.trainer_data.duplicate(true)
	var beaten: bool = object.trainer_flag_active(state)
	var script_address: int = int(trainer.get("after_script", 0)) if beaten \
		else int(event.get("script", object.event_script))
	if script_address <= 0:
		return {}
	var request: Dictionary = {
		"kind": &"trainer",
		"map_group": current_map.group,
		"map_number": current_map.number,
		"cell": object.cell,
		"bank": int(current_map.events.get("bank", 0)),
		"script": script_address,
		"object_index": object.index,
		"event": event.duplicate(true),
		"trainer": trainer,
		"trainer_phase": &"after" if beaten else &"initial",
	}
	request["event"]["trainer"] = trainer.duplicate(true)
	return request


func _bg_event_interacts(event: Dictionary) -> bool:
	var event_type: int = int(event.get("type", -1))
	match event_type:
		BGEVENT_READ, BGEVENT_IFSET, BGEVENT_IFNOTSET:
			return true
		BGEVENT_UP:
			return player_facing == Gen2WorldSprite.FACING_UP
		BGEVENT_DOWN:
			return player_facing == Gen2WorldSprite.FACING_DOWN
		BGEVENT_LEFT:
			return player_facing == Gen2WorldSprite.FACING_LEFT
		BGEVENT_RIGHT:
			return player_facing == Gen2WorldSprite.FACING_RIGHT
	return false


func _bg_event_condition_active(event: Dictionary) -> bool:
	var event_type: int = int(event.get("type", -1))
	if event_type not in [BGEVENT_IFSET, BGEVENT_IFNOTSET]:
		return true
	var conditional: Dictionary = _bg_event_condition(event)
	if not bool(conditional.get("ok", false)):
		return false
	var active: bool = event_flag_active(int(conditional["flag"]))
	return active if event_type == BGEVENT_IFSET else not active


func _bg_event_condition(event: Dictionary) -> Dictionary:
	if data == null or current_map == null:
		return {"ok": false, "reason": &"missing_bg_event_context"}
	var pointer: int = int(event.get("script", 0))
	var raw: PackedByteArray = data.world_script(
		int(current_map.events.get("bank", 0)), pointer
	)
	if raw.size() < 4:
		return {"ok": false, "reason": &"invalid_bg_event_condition", "pointer": pointer}
	return {
		"ok": true,
		"flag": int(raw[0]) | (int(raw[1]) << 8),
		"script": int(raw[2]) | (int(raw[3]) << 8),
	}


func _script_address_for_event(event: Dictionary) -> int:
	if event.get("kind", &"") != &"bg_events":
		return int(event.get("script", 0))
	var event_type: int = int(event.get("type", -1))
	if event_type in [BGEVENT_IFSET, BGEVENT_IFNOTSET]:
		if not _bg_event_condition_active(event):
			return -1
		return int(_bg_event_condition(event).get("script", -1))
	if event_type in [BGEVENT_READ, BGEVENT_UP, BGEVENT_DOWN, BGEVENT_RIGHT, BGEVENT_LEFT]:
		return int(event.get("script", 0))
	return -1


func _enqueue_script(request: Dictionary) -> void:
	if int(request.get("script", 0)) <= 0:
		return
	if not request.has("collision"):
		var cell_value: Variant = request.get("cell", player_cell)
		var cell: Vector2i = cell_value if cell_value is Vector2i else player_cell
		request["collision"] = collision_code_at(cell)
	if not request.has("clock"):
		request["clock"] = world_clock()
	if current_map != null and not request.has("environment"):
		request["environment"] = current_map.environment
	if not request.has("facing"):
		request["facing"] = player_facing
	if not request.has("party") and not _party_summary.is_empty():
		request["party"] = _party_summary.duplicate()
	if not request.has("object_event_flags"):
		## `disappear` and `appear` write an object's event flag where the source
		## does, inside the script, so a later `checkevent` on the same flag sees
		## it. The runner holds no object table, so it is handed the flag per
		## object index the way it is handed collision and the clock.
		var object_flags: Array[int] = []
		for object: Gen2WorldObject in objects:
			object_flags.append(object.event_flag)
		request["object_event_flags"] = object_flags
	_script_queue.append(request)


func _queue_map_callbacks(callback_type: int) -> void:
	if current_map == null:
		return
	var bank: int = int(current_map.scripts.get("bank", 0))
	for callback: Dictionary in current_map.scripts.get("callbacks", []):
		if callback_type >= 0 and int(callback.get("type", -1)) != callback_type:
			continue
		_enqueue_script({
			"kind": &"callback",
			"callback_type": int(callback.get("type", -1)),
			"map_group": current_map.group,
			"map_number": current_map.number,
			"bank": bank,
			"script": int(callback.get("script", 0)),
		})


func _queue_map_scene() -> void:
	if current_map == null:
		return
	var scenes: Array = current_map.scripts.get("scenes", [])
	if scenes.is_empty():
		return
	var current_scene: int = state.map_scene(current_map.group, current_map.number)
	for scene: Dictionary in scenes:
		if int(scene.get("id", -1)) != current_scene:
			continue
		_enqueue_script({
			"kind": &"scene",
			"map_group": current_map.group,
			"map_number": current_map.number,
			"scene": current_scene,
			"bank": int(current_map.scripts.get("bank", 0)),
			"script": int(scene.get("script", 0)),
		})
		break


func _coord_event_condition_active(event: Dictionary) -> bool:
	var scenes: Array = current_map.scripts.get("scenes", []) if current_map != null else []
	if scenes.is_empty():
		return true
	return int(event.get("scene", -1)) == state.map_scene(current_map.group, current_map.number)


func _apply_script_object_events(raw_events: Variant) -> Array:
	var generated: Array = []
	if not raw_events is Array:
		return generated
	var reload_objects: bool = false
	for raw_event: Variant in raw_events as Array:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event as Dictionary
		var event_type: StringName = StringName(event.get("type", &""))
		if event_type == &"warp_check_requested":
			## Script_warpcheck asks whether the player is standing on a warp
			## and takes it if so, which is how the Burned Tower rival scene
			## drops the player through the hole it just opened. A cell with no
			## warp answers nothing, exactly as WarpCheck's carry does.
			var checked: Dictionary = try_warp()
			generated.append({
				"type": &"warp_check",
				"taken": bool(checked.get("ok", false)),
				"transition": checked.duplicate(true),
			})
			continue
		if event_type == &"player_movement_requested":
			generated.append_array(_apply_player_movement(event))
			continue
		if event_type == &"object_movement_requested":
			generated.append_array(_apply_object_movement(event))
			continue
		if event_type == &"object_write_position":
			var write_map_group: int = int(event.get("map_group", -1))
			var write_map_number: int = int(event.get("map_number", -1))
			var write_index: int = int(event.get("object_index", -1))
			if current_map == null or write_map_group != current_map.group \
				or write_map_number != current_map.number \
				or write_index < 0 or write_index >= objects.size():
				generated.append({"type": &"object_change_failed", "reason": &"invalid_object"})
				continue
			var write_object: Gen2WorldObject = objects[write_index]
			var write_key: String = _object_key(
				write_map_group, write_map_number, write_index
			)
			_object_position_overrides[write_key] = write_object.cell
			generated.append({
				"type": &"object_position_written",
				"object_index": write_index, "cell": write_object.cell,
			})
			continue
		if event_type == &"map_block_changed":
			if current_map == null or int(event.get("map_group", -1)) != current_map.group \
				or int(event.get("map_number", -1)) != current_map.number:
				generated.append({"type": &"map_change_failed", "reason": &"invalid_map"})
				continue
			var source_cell := Vector2i(
				int(event.get("x", -1)), int(event.get("y", -1))
			)
			var block_cell: Vector2i = _script_block_cell(source_cell)
			var changed_block: Dictionary = change_block(
				block_cell.x, block_cell.y, int(event.get("block", -1))
			)
			if bool(changed_block.get("ok", false)):
				changed_block["source_cell"] = source_cell
				generated.append({"type": &"map_block_changed", "change": changed_block})
			else:
				generated.append({
					"type": &"map_change_failed",
					"reason": changed_block.get("reason", &"invalid_block"),
					"source_cell": source_cell,
					"block_cell": block_cell,
				})
			continue
		if event_type == &"map_reload_requested":
			generated.append(reload_current_map())
			continue
		if event_type == &"variable_sprite_changed":
			var variable_sprite: int = int(event.get("variable_sprite", -1))
			var sprite: int = int(event.get("sprite", 0))
			if variable_sprite < Gen2WorldScriptRunner.VARIABLE_SPRITE_BASE \
				or sprite <= 0:
				generated.append({"type": &"variable_sprite_change_failed"})
				continue
			_variable_sprites[variable_sprite] = sprite
			reload_objects = true
			generated.append({
				"type": &"variable_sprite_changed",
				"variable_sprite": variable_sprite,
				"sprite": sprite,
			})
			continue
		if event_type == &"map_refresh_requested":
			generated.append({"type": &"map_refreshed", "map": map_id()})
			continue
		if event_type == &"command_queue_written":
			generated.append(apply_command_queue_write(
				int(event.get("bank", 0)), int(event.get("address", 0))
			))
			continue
		if event_type == &"command_queue_deleted":
			generated.append(apply_command_queue_delete(int(event.get("queue_id", -1))))
			continue
		if event_type == &"earthquake_requested":
			generated.append({
				"type": &"screen_shake_requested",
				"strength": int(event.get("strength", 0)),
			})
			continue
		if event_type == &"object_follow":
			var follow_key: String = _object_key(
				int(event.get("map_group", -1)), int(event.get("map_number", -1)),
				int(event.get("object_index", -1))
			)
			_object_followers[follow_key] = {
				"target_index": int(event.get("target_index", -1)),
				"exact": bool(event.get("exact", true)),
			}
			continue
		if event_type == &"object_stop_follow":
			_object_followers.clear()
			continue
		if event_type in [&"object_deleted", &"object_emote", &"object_event_flag"]:
			var local_map_group: int = int(event.get("map_group", -1))
			var local_map_number: int = int(event.get("map_number", -1))
			var local_index: int = int(event.get("object_index", -1))
			if current_map == null or local_map_group != current_map.group \
				or local_map_number != current_map.number \
				or local_index < 0 or local_index >= objects.size():
				generated.append({"type": &"object_change_failed", "reason": &"invalid_object"})
				continue
			var local_object: Gen2WorldObject = objects[local_index]
			var local_key: String = _object_key(local_map_group, local_map_number, local_index)
			match event_type:
				&"object_deleted":
					local_object.deleted = true
					local_object.active = false
					_object_followers.erase(local_key)
					generated.append({"type": &"object_deleted", "object_index": local_index})
				&"object_emote":
					local_object.set_emote(
						int(event.get("emote_id", -1)), bool(event.get("visible", false)),
						int(event.get("duration", 0))
					)
				&"object_event_flag":
					var flag: int = local_object.event_flag
					if flag > 0:
						state.set_event_flag(flag, bool(event.get("active", false)))
			continue
		if event_type == &"player_face_object":
			var player_target_index: int = int(event.get("target_index", -1))
			if current_map != null and int(event.get("map_group", -1)) == current_map.group \
				and int(event.get("map_number", -1)) == current_map.number \
				and player_target_index >= 0 and player_target_index < objects.size():
				player_facing = _facing_toward(
					player_cell, (objects[player_target_index] as Gen2WorldObject).cell
				)
			continue
		if event_type not in [
			&"object_visibility", &"object_position", &"object_facing",
			&"object_face_player", &"object_face_object",
		]:
			continue
		var map_group: int = int(event.get("map_group", -1))
		var map_number: int = int(event.get("map_number", -1))
		var object_index: int = int(event.get("object_index", -1))
		if object_index < 0:
			continue
		var key: String = _object_key(map_group, map_number, object_index)
		match event_type:
			&"object_visibility":
				_object_visibility_overrides[key] = bool(event.get("active", false))
				reload_objects = true
			&"object_position":
				var cell: Variant = event.get("cell", Vector2i.ZERO)
				if cell is Vector2i:
					_object_position_overrides[key] = cell
					reload_objects = true
			&"object_facing":
				_object_facing_overrides[key] = clampi(
					int(event.get("facing", Gen2WorldSprite.FACING_DOWN)),
					Gen2WorldSprite.FACING_DOWN, Gen2WorldSprite.FACING_RIGHT
				)
				reload_objects = true
			&"object_face_player":
				if map_group == current_map.group and map_number == current_map.number \
					and object_index < objects.size():
					var object: Gen2WorldObject = objects[object_index]
					var facing: int = _facing_toward(object.cell, player_cell)
					_object_facing_overrides[key] = facing
			&"object_face_object":
				var target_index: int = int(event.get("target_index", -1))
				if map_group == current_map.group and map_number == current_map.number \
					and object_index < objects.size() and target_index >= 0 \
					and target_index < objects.size():
					_object_facing_overrides[key] = _facing_toward(
						(objects[object_index] as Gen2WorldObject).cell,
						(objects[target_index] as Gen2WorldObject).cell
					)
				reload_objects = true
	if reload_objects and current_map != null:
		_load_objects()
	return generated


func _apply_object_movement(event: Dictionary) -> Array:
	var generated: Array = []
	var map_group: int = int(event.get("map_group", -1))
	var map_number: int = int(event.get("map_number", -1))
	var object_index: int = int(event.get("object_index", -1))
	if current_map == null or map_group != current_map.group or map_number != current_map.number \
		or object_index < 0 or object_index >= objects.size():
		generated.append({"type": &"movement_failed", "reason": &"invalid_object"})
		return generated
	var raw: PackedByteArray = data.world_movement(
		int(event.get("bank", 0)), int(event.get("address", 0))
	)
	var decoded: Dictionary = Gen2WorldMovement.decode(raw)
	if not bool(decoded.get("ok", false)):
		generated.append({
			"type": &"movement_failed", "reason": decoded.get("reason", &"invalid_movement"),
			"object_index": object_index,
		})
		return generated
	var object: Gen2WorldObject = objects[object_index]
	for command: Dictionary in decoded.get("commands", []):
		var kind: StringName = StringName(command.get("kind", &""))
		if kind in [&"turn_head", &"turn_in", &"turn_waterfall"]:
			object.apply_direction(_movement_direction(int(command.get("direction", 0))))
			continue
		if kind == &"turn_away":
			object.apply_direction(-_movement_direction(int(command.get("direction", 0))))
			continue
		if kind in [
			&"turn_step", &"slow_step", &"step", &"big_step", &"slow_slide_step",
			&"slide_step", &"fast_slide_step", &"slow_jump_step", &"jump_step",
			&"fast_jump_step",
		]:
			var direction: Vector2i = _movement_direction(int(command.get("direction", 0)))
			object.apply_direction(direction)
			var destination: Vector2i = object.cell + direction
			if can_object_walk_to(destination, object, direction):
				object.cell = destination
			else:
				generated.append({
					"type": &"movement_blocked", "object_index": object_index,
					"cell": destination,
				})
			continue
		match kind:
			&"show_object":
				object.deleted = false
				object.active = true
				_object_visibility_overrides[_object_key(map_group, map_number, object_index)] = true
			&"hide_object":
				object.active = false
				_object_visibility_overrides[_object_key(map_group, map_number, object_index)] = false
			&"remove_object":
				object.deleted = true
				object.active = false
				_object_followers.erase(_object_key(map_group, map_number, object_index))
				generated.append({"type": &"object_deleted", "object_index": object_index})
				break
			&"show_emote":
				object.set_emote(object.emote_id, true)
			&"hide_emote":
				object.set_emote(object.emote_id, false)
			&"step_stop":
				break
			&"step_sleep", &"set_sliding", &"remove_sliding", &"fix_facing", &"remove_fixed_facing":
				pass
			_:
				generated.append({
					"type": &"movement_command_requested", "object_index": object_index,
					"command": command.duplicate(true),
				})
	var key: String = _object_key(map_group, map_number, object_index)
	_object_position_overrides[key] = object.cell
	_object_facing_overrides[key] = object.facing
	return generated


func _apply_player_movement(event: Dictionary) -> Array:
	var generated: Array = []
	var map_group: int = int(event.get("map_group", -1))
	var map_number: int = int(event.get("map_number", -1))
	if current_map == null or map_group != current_map.group or map_number != current_map.number:
		return [{"type": &"movement_failed", "reason": &"invalid_map"}]
	var raw: PackedByteArray = data.world_movement(
		int(event.get("bank", 0)), int(event.get("address", 0))
	)
	var decoded: Dictionary = Gen2WorldMovement.decode(raw)
	if not bool(decoded.get("ok", false)):
		return [{
			"type": &"movement_failed", "reason": decoded.get("reason", &"invalid_movement"),
			"player": true,
		}]
	for command: Dictionary in decoded.get("commands", []):
		var kind: StringName = StringName(command.get("kind", &""))
		if kind in [&"turn_head", &"turn_in", &"turn_waterfall"]:
			player_facing = _facing_for_direction(
				_movement_direction(int(command.get("direction", 0)))
			)
			continue
		if kind == &"turn_away":
			var away: Vector2i = -_movement_direction(int(command.get("direction", 0)))
			player_facing = _facing_for_direction(away)
			continue
		if kind in [
			&"turn_step", &"slow_step", &"step", &"big_step", &"slow_slide_step",
			&"slide_step", &"fast_slide_step", &"slow_jump_step", &"jump_step",
			&"fast_jump_step",
		]:
			var direction: Vector2i = _movement_direction(int(command.get("direction", 0)))
			player_facing = _facing_for_direction(direction)
			var destination: Vector2i = player_cell + direction
			if can_walk_to(destination, direction):
				player_cell = destination
			else:
				generated.append({
					"type": &"movement_blocked", "player": true, "cell": destination,
				})
			continue
		if kind in [&"step_end", &"step_stop"]:
			break
		if kind in [
			&"step_sleep", &"step_wait_end", &"set_sliding", &"remove_sliding",
			&"fix_facing", &"remove_fixed_facing",
		]:
			continue
		generated.append({
			"type": &"movement_command_requested", "player": true,
			"command": command.duplicate(true),
		})
	return generated


func _movement_direction(direction: int) -> Vector2i:
	match direction & 3:
		0:
			return Vector2i.DOWN
		1:
			return Vector2i.UP
		2:
			return Vector2i.LEFT
		3:
			return Vector2i.RIGHT
	return Vector2i.ZERO


func _object_key(map_group: int, map_number: int, object_index: int) -> String:
	return "%d:%d:%d" % [map_group, map_number, object_index]


func _block_key(map: Gen2WorldMap, block_x: int, block_y: int) -> String:
	return "%d:%d:%d:%d" % [map.group, map.number, block_x, block_y]


func _facing_toward(from: Vector2i, to: Vector2i) -> int:
	var delta: Vector2i = to - from
	if abs(delta.x) > abs(delta.y):
		return Gen2WorldSprite.FACING_RIGHT if delta.x > 0 else Gen2WorldSprite.FACING_LEFT
	if delta.y != 0:
		return Gen2WorldSprite.FACING_DOWN if delta.y > 0 else Gen2WorldSprite.FACING_UP
	return Gen2WorldSprite.FACING_DOWN


func _validate_script_warp(map_group: int, map_number: int, cell: Vector2i) -> Dictionary:
	var target_map: Gen2WorldMap = data.world_map(map_group, map_number) if data != null else null
	if target_map == null:
		return {"ok": false, "reason": &"missing_map"}
	var target_tileset: Gen2WorldTileset = data.world_tileset(target_map.tileset) if data != null else null
	if target_tileset == null:
		return {"ok": false, "reason": &"missing_tileset"}
	if cell.x < 0 or cell.y < 0 or cell.x >= target_map.collision_width \
		or cell.y >= target_map.collision_height:
		return {"ok": false, "reason": &"invalid_target_cell"}
	return {"ok": true}


func _finish_script_result(result: Dictionary) -> Dictionary:
	if not bool(result.get("ok", false)):
		return result
	if result.has("clock"):
		var clock: Dictionary = result.get("clock", {})
		set_world_clock(
			int(clock.get("day", world_day)),
			int(clock.get("hour", world_hour)),
			int(clock.get("minute", world_minute))
		)
	if result.has("dst_enabled"):
		set_daylight_saving_time_enabled(bool(result.get("dst_enabled", false)))
	var generated_events: Array = _apply_script_object_events(result.get("events", []))
	for generated: Dictionary in generated_events:
		result["events"].append(generated)
	var warp: Variant = result.get("warp", {})
	if warp is Dictionary and not (warp as Dictionary).is_empty():
		var transition: Dictionary = _apply_script_warp(warp as Dictionary)
		if not bool(transition.get("ok", false)):
			result["ok"] = false
			result["status"] = &"failed"
			result["reason"] = transition.get("reason", &"warp_failed")
			return result
		result["events"].append({"type": &"warp", "transition": transition})
	return result


func _apply_script_warp(request: Dictionary) -> Dictionary:
	var map_group: int = int(request.get("map_group", -1))
	var map_number: int = int(request.get("map_number", -1))
	var cell := Vector2i(int(request.get("x", -1)), int(request.get("y", -1)))
	var validation: Dictionary = _validate_script_warp(map_group, map_number, cell)
	if not bool(validation.get("ok", false)):
		return validation
	var target_map: Gen2WorldMap = data.world_map(map_group, map_number)
	var target_tileset: Gen2WorldTileset = data.world_tileset(target_map.tileset)
	var from_map: Vector2i = map_id()
	var from_cell: Vector2i = player_cell
	_apply_map(target_map, target_tileset, cell)
	return {
		"ok": true,
		"kind": &"warp",
		"from_map": from_map,
		"from_cell": from_cell,
		"to_map": map_id(),
		"to_cell": player_cell,
		"destination": request.duplicate(true),
	}


## Resolves and applies an ordinary warp at the current cell. The destination
## field selects a one-based warp in the destination map, as in the original
## map macro. An invalid target leaves this API unchanged and returns an error
## record instead of silently placing the player on another map.
func try_warp(cell: Vector2i = player_cell) -> Dictionary:
	var source_warp: Dictionary = warp_at(cell)
	if source_warp.is_empty():
		return {}
	## CheckWarpCollision gates every warp on the tile's own code, so a
	## warp_event sitting on ordinary floor never fires. Burned Tower B1F's
	## (10,8) is one, and the walk to the beasts crosses it.
	if not Gen2WorldCollision.is_warp_tile(collision_code_at(cell)):
		return {}
	var target_group: int = int(source_warp.get("map_group", -1))
	var target_number: int = int(source_warp.get("map_number", -1))
	var target_map: Gen2WorldMap = data.world_map(target_group, target_number) if data != null else null
	if target_map == null:
		return {
			"ok": false,
			"kind": &"warp",
			"reason": &"missing_map",
			"from_map": map_id(),
			"from_cell": cell,
		}

	var destination_index: int = int(source_warp.get("destination", 0)) - 1
	var target_warps: Array = target_map.events.get("warps", [])
	if destination_index < 0 or destination_index >= target_warps.size():
		return {
			"ok": false,
			"kind": &"warp",
			"reason": &"missing_destination",
			"from_map": map_id(),
			"from_cell": cell,
		}

	var target_tileset: Gen2WorldTileset = data.world_tileset(target_map.tileset) if data != null else null
	if target_tileset == null:
		return {
			"ok": false,
			"kind": &"warp",
			"reason": &"missing_tileset",
			"from_map": map_id(),
			"from_cell": cell,
		}

	var target_warp: Dictionary = (target_warps[destination_index] as Dictionary).duplicate(true)
	var from_map: Vector2i = map_id()
	var from_cell: Vector2i = cell
	_apply_map(target_map, target_tileset, Vector2i(int(target_warp["x"]), int(target_warp["y"])))
	return {
		"ok": true,
		"kind": &"warp",
		"from_map": from_map,
		"from_cell": from_cell,
		"to_map": map_id(),
		"to_cell": player_cell,
		"source": source_warp,
		"destination": target_warp,
	}


## Resolves the source connection for a cardinal step beyond the current map.
## The stored offsets are the signed cell offsets generated by the cartridge's
## connection macro. No map mutation occurs when the target is invalid.
func try_connection(direction: Vector2i) -> Dictionary:
	var direction_name: String = _direction_name(direction)
	if direction_name.is_empty() or current_map == null or data == null:
		return {}
	if not _at_connection_edge(direction_name):
		return {
			"ok": false,
			"kind": &"connection",
			"reason": &"not_at_edge",
			"from_map": map_id(),
			"from_cell": player_cell,
			"direction": direction_name,
		}
	var source_connection: Dictionary = {}
	for connection: Dictionary in current_map.connections:
		if String(connection.get("direction", "")) == direction_name:
			source_connection = connection.duplicate(true)
			break
	if source_connection.is_empty():
		return {}

	var target_group: int = int(source_connection.get("map_group", -1))
	var target_number: int = int(source_connection.get("map_number", -1))
	var target_map: Gen2WorldMap = data.world_map(target_group, target_number)
	if target_map == null:
		return {
			"ok": false,
			"kind": &"connection",
			"reason": &"missing_map",
			"from_map": map_id(),
			"from_cell": player_cell,
			"direction": direction_name,
		}
	var target_tileset: Gen2WorldTileset = data.world_tileset(target_map.tileset)
	if target_tileset == null:
		return {
			"ok": false,
			"kind": &"connection",
			"reason": &"missing_tileset",
			"from_map": map_id(),
			"from_cell": player_cell,
			"direction": direction_name,
		}

	var target_cell: Vector2i
	match direction_name:
		"north":
			target_cell = Vector2i(
				player_cell.x + int(source_connection.get("x_offset", 0)),
				target_map.collision_height - 1,
			)
		"south":
			target_cell = Vector2i(
				player_cell.x + int(source_connection.get("x_offset", 0)),
				0,
			)
		"west":
			target_cell = Vector2i(
				target_map.collision_width - 1,
				player_cell.y + int(source_connection.get("y_offset", 0)),
			)
		"east":
			target_cell = Vector2i(
				0,
				player_cell.y + int(source_connection.get("y_offset", 0)),
			)
		_:
			return {}
	if target_cell.x < 0 or target_cell.y < 0 \
		or target_cell.x >= target_map.collision_width \
		or target_cell.y >= target_map.collision_height:
		return {
			"ok": false,
			"kind": &"connection",
			"reason": &"invalid_target_cell",
			"from_map": map_id(),
			"from_cell": player_cell,
			"direction": direction_name,
		}

	var from_map: Vector2i = map_id()
	var from_cell: Vector2i = player_cell
	_apply_map(target_map, target_tileset, target_cell)
	return {
		"ok": true,
		"kind": &"connection",
		"direction": direction_name,
		"from_map": from_map,
		"from_cell": from_cell,
		"to_map": map_id(),
		"to_cell": player_cell,
		"source": source_connection,
	}


## [param direction] is the attempted movement direction, matching
## .CheckLandPerms/.CheckSurfPerms ANDing wFacingDirection against
## wTilePermissions computed at the player's current cell. Vector2i.ZERO skips
## that test for callers that only want the destination's plain permission.
func can_walk_to(cell: Vector2i, direction: Vector2i = Vector2i.ZERO) -> bool:
	if not _step_permission_allows(cell, direction):
		return false
	return object_at(cell) == null


## .CheckLandPerms/.CheckSurfPerms alone, without .CheckNPC. Split out because
## the source runs the two in that order and only reaches the NPC test when the
## permission passed, which is what makes a boulder on a wall unpushable.
func _step_permission_allows(cell: Vector2i, direction: Vector2i) -> bool:
	if current_map == null or cell.x < 0 or cell.y < 0 \
		or cell.x >= current_map.collision_width or cell.y >= current_map.collision_height:
		return false
	if direction != Vector2i.ZERO:
		var face: int = Gen2WorldCollision.face_mask_for_direction(direction)
		if face != 0 and (tile_permissions_at(player_cell) & face) != 0:
			return false
	var permission: int = collision_permission_at(cell)
	if movement_mode == MOVEMENT_SURF:
		var current_permission: int = collision_permission_at(player_cell)
		if current_permission == Gen2WorldCollision.WATER_TILE:
			return permission in [Gen2WorldCollision.LAND_TILE, Gen2WorldCollision.WATER_TILE]
		return permission == Gen2WorldCollision.WATER_TILE
	return permission == Gen2WorldCollision.LAND_TILE


## [param direction] matches CanObjectMoveInDirection's CanObjectLeaveTile
## (moving's own cell) and WillObjectBumpIntoTile (the destination) side-wall
## checks; Vector2i.ZERO skips them for callers that only want the destination
## permission and occupancy.
func can_object_walk_to(
	cell: Vector2i, moving: Gen2WorldObject, direction: Vector2i = Vector2i.ZERO
) -> bool:
	if current_map == null or cell.x < 0 or cell.y < 0 \
		or cell.x >= current_map.collision_width or cell.y >= current_map.collision_height:
		return false
	if Gen2WorldCollision.permission_for(collision_code_at(cell)) != Gen2WorldCollision.LAND_TILE:
		return false
	if direction != Vector2i.ZERO and Gen2WorldCollision.side_wall_step_blocked(
		collision_code_at(moving.cell), collision_code_at(cell), direction
	):
		return false
	for object: Gen2WorldObject in objects:
		if object != moving and object.active and not object.deleted \
			and object.sprite != null and object.cell == cell:
			return false
	return cell != player_cell


## Advances the movement templates whose source behavior is data-driven in this
## slice. Scripted movement is executed by the script runner, while followers
## advance after each successful player step.
##
## One movement decision per eligible object per call. A caller wanting the
## source's pacing uses advance_object_steps(), which spends the step and idle
## durations this records.
func advance_objects(random: RandomNumberGenerator) -> int:
	var moved: int = 0
	for object: Gen2WorldObject in objects:
		if not object.active or not object.movement_supported():
			continue
		if _decide_object_movement(object, random):
			moved += 1
	return moved


## One object's turn at StepFunction_FromMovement: the movement template picks
## a facing or a direction, then records how long the resulting step or wait
## lasts. Returns true when the object committed to a new cell.
func _decide_object_movement(object: Gen2WorldObject, random: RandomNumberGenerator) -> bool:
	if object.movement in [
		Gen2WorldObject.MOVEMENT_SPINRANDOM_SLOW, Gen2WorldObject.MOVEMENT_SPINRANDOM_FAST
	]:
		# MovementFunction_RandomSpinSlow and _Fast set a facing and go straight
		# to their own wait; neither ever starts a step.
		object.facing = random.randi_range(
			Gen2WorldSprite.FACING_DOWN, Gen2WorldSprite.FACING_RIGHT
		)
		var spin_mask: int = IDLE_MASK_SLOW \
			if object.movement == Gen2WorldObject.MOVEMENT_SPINRANDOM_SLOW else IDLE_MASK_FAST
		object.start_idle(random.randi() & spin_mask)
		return false
	var direction: Vector2i = object.next_direction(random)
	if direction == Vector2i.ZERO:
		return false
	var destination: Vector2i = object.cell + direction
	if not object.can_leave_to(destination) \
		or not can_object_walk_to(destination, object, direction):
		# _RandomWalkContinue's .new_duration branch: a blocked object keeps its
		# cell and waits again before trying another direction.
		object.start_idle(random.randi() & IDLE_MASK_SLOW)
		return false
	object.cell = destination
	object.apply_direction(direction)
	object.start_step(direction, STEP_FRAMES_NPC_WALK)
	return true


## Paces the data-driven movement templates by real elapsed time, at the same
## hardware-frame rate and stall catch-up cap the player's own walk step and
## Gen2WorldAnimation use.
##
## Per frame an object spends one frame of an in-flight step, one frame of its
## wait, or takes a new decision: the source's STEP_TYPE_CONTINUE_WALK,
## STEP_TYPE_SLEEP and STEP_TYPE_FROM_MOVEMENT cycle. The cell commits when the
## step starts, matching InitStep and the player path, and only the presentation
## offset trails. Returns true when something a renderer draws changed.
func advance_object_steps(delta: float, random: RandomNumberGenerator) -> bool:
	if delta <= 0.0 or random == null or objects.is_empty():
		return false
	_object_step_accumulator = minf(
		_object_step_accumulator + delta,
		Gen2WorldAnimation.FRAME_SECONDS * float(Gen2WorldAnimation.MAX_CATCHUP_FRAMES)
	)
	var changed: bool = false
	while _object_step_accumulator >= Gen2WorldAnimation.FRAME_SECONDS:
		_object_step_accumulator -= Gen2WorldAnimation.FRAME_SECONDS
		for object: Gen2WorldObject in objects:
			if not object.active or object.deleted or object.sprite == null:
				continue
			# A step in flight is drained whatever put it there, so a pushed
			# boulder slides even though its template never decides anything.
			# StepFunction_StrengthBoulder ends by standing the boulder back up
			# without rolling a wait, which is why only a template that decides
			# reaches start_idle below.
			if object.is_stepping():
				if object.tick_step():
					changed = true
					if not object.is_stepping() and object.movement_advances():
						# StepFunction_ContinueWalk rolls a new wait the moment
						# the step duration reaches zero, so a wandering object
						# pauses between steps instead of walking without
						# stopping.
						object.start_idle(random.randi() & IDLE_MASK_SLOW)
				continue
			if not object.movement_advances():
				continue
			if object.tick_idle():
				continue
			var facing_before: int = object.facing
			if _decide_object_movement(object, random):
				_remember_object_position(object)
				changed = true
			elif object.facing != facing_before:
				_remember_object_position(object)
				changed = true
	return changed


## Keeps a moved or turned object's live cell and facing across the map reloads
## that rebuild object records, the same way the trainer approach does.
func _remember_object_position(object: Gen2WorldObject) -> void:
	if current_map == null:
		return
	var key: String = _object_key(current_map.group, current_map.number, object.index)
	_object_position_overrides[key] = object.cell
	_object_facing_overrides[key] = object.facing


func _advance_followers(previous_player_cell: Vector2i, previous_cells: Dictionary) -> void:
	var relations: Array = []
	for key: String in _object_followers:
		var separator: PackedStringArray = key.split(":")
		if separator.size() != 3 or int(separator[0]) != current_map.group \
			or int(separator[1]) != current_map.number:
			continue
		relations.append({
			"key": key,
			"index": int(separator[2]),
			"relation": (_object_followers[key] as Dictionary).duplicate(true),
		})
	relations.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return int(first["index"]) < int(second["index"])
	)
	for entry: Dictionary in relations:
		var follower_index: int = int(entry["index"])
		if follower_index < 0 or follower_index >= objects.size():
			continue
		var follower: Gen2WorldObject = objects[follower_index]
		if not follower.active or follower.deleted:
			continue
		var relation: Dictionary = entry["relation"]
		var target_index: int = int(relation.get("target_index", -1))
		var exact: bool = bool(relation.get("exact", true))
		var target_cell: Vector2i = previous_player_cell
		if target_index >= 0 and previous_cells.has(target_index):
			target_cell = previous_cells[target_index]
		elif target_index >= 0 and target_index < objects.size():
			target_cell = (objects[target_index] as Gen2WorldObject).cell
		var delta: Vector2i = target_cell - follower.cell
		if abs(delta.x) + abs(delta.y) <= 1:
			continue
		var direction: Vector2i
		if exact and abs(delta.x) != 0 and abs(delta.y) != 0:
			# Exact followers preserve the leader's cardinal path instead of
			# cutting a diagonal corner.
			direction = Vector2i(signi(delta.x), 0) if abs(delta.x) >= abs(delta.y) \
				else Vector2i(0, signi(delta.y))
		elif abs(delta.x) >= abs(delta.y):
			direction = Vector2i(signi(delta.x), 0)
		else:
			direction = Vector2i(0, signi(delta.y))
		var destination: Vector2i = follower.cell + direction
		if can_object_walk_to(destination, follower, direction):
			follower.cell = destination
			follower.apply_direction(direction)
			# A follower keeps pace with the player, so it takes the player's
			# own walk duration rather than the slower wandering one.
			follower.start_step(direction, STEP_FRAMES_WALK)
			var override_key: String = _object_key(
				current_map.group, current_map.number, follower_index
			)
			_object_position_overrides[override_key] = follower.cell
			_object_facing_overrides[override_key] = follower.facing


## Moves one cell or enters a neighboring map when the step leaves a connected
## map edge. The legacy boolean move() wrapper remains available to callers.
func move_result(direction: Vector2i) -> Dictionary:
	if phone_ring_active():
		return {"ok": false, "kind": &"move", "reason": &"phone_ring_active"}
	if abs(direction.x) + abs(direction.y) != 1:
		return {"ok": false, "kind": &"move", "reason": &"invalid_direction"}
	if current_map == null:
		return {"ok": false, "kind": &"move", "reason": &"missing_map"}
	## .CheckTile runs before .CheckTurning and .TryStep/.TrySurf and overwrites
	## wWalkingDirection, so the standing tile wins over the pressed direction.
	var forced: Dictionary = forced_movement()
	var forced_walk: bool = false
	match StringName(forced.get("kind", &"none")):
		&"force_turn":
			return _forced_turn()
		&"walk":
			direction = forced["direction"]
			forced_walk = true
	var destination: Vector2i = player_cell + direction
	if destination.x < 0 or destination.y < 0 \
		or destination.x >= current_map.collision_width \
		or destination.y >= current_map.collision_height:
		var transition: Dictionary = try_connection(direction)
		if not transition.is_empty():
			if bool(transition.get("ok", false)):
				player_facing = _facing_for_direction(direction)
				state.consume_repel_step()
			return transition
		return {"ok": false, "kind": &"move", "reason": &"map_edge"}
	if forced_walk:
		return _forced_step(direction, destination)
	if not can_walk_to(destination, direction):
		## .CheckNPC runs after .CheckLandPerms and before .TryJump, and its own
		## comment says a movable boulder is treated the same as any NPC in front:
		## both .bump. So a push starts the boulder and still refuses the player,
		## and .bump returns without carry, so the ledge hop is tried afterwards
		## exactly as it would have been.
		var pushed: Dictionary = _try_push_boulder(direction, destination)
		var hop: Dictionary = _try_ledge_hop(direction)
		if not hop.is_empty():
			return hop
		if not pushed.is_empty():
			return pushed
		return {"ok": false, "kind": &"move", "reason": &"blocked"}
	var from_map: Vector2i = map_id()
	var from_cell: Vector2i = player_cell
	var previous_cells: Dictionary = {}
	for index: int in objects.size():
		previous_cells[index] = (objects[index] as Gen2WorldObject).cell
	## .TrySurf's .ExitWater: .GetOutOfWater restores PLAYER_NORMAL and the walking
	## sprite before .DoStep runs, so the state is already back to walking while
	## the step onto land is still being taken.
	var exiting_water: bool = movement_mode == MOVEMENT_SURF \
		and collision_permission_at(destination) == Gen2WorldCollision.LAND_TILE
	var kind: StringName = &"move"
	if exiting_water:
		movement_mode = MOVEMENT_WALK
		player_sprite_number = Gen2WorldSprite.SPRITE_PLAYER
		kind = &"exit_water"
	elif movement_mode == MOVEMENT_SURF:
		kind = &"water_move"
	player_cell = destination
	player_facing = _facing_for_direction(direction)
	state.consume_repel_step()
	_advance_followers(from_cell, previous_cells)
	_start_player_step(direction, STEP_FRAMES_WALK)
	return {
		"ok": true,
		"kind": kind,
		"from_map": from_map,
		"from_cell": from_cell,
		"to_map": from_map,
		"to_cell": player_cell,
	}


## .CheckTile for the cell the player stands on: whether the tile overrides input,
## and with what. [code]none[/code] leaves ordinary movement alone.
func forced_movement() -> Dictionary:
	if current_map == null:
		return {"kind": &"none"}
	return Gen2WorldCollision.forced_action(collision_code_at(player_cell))


## Applies whatever the standing tile forces, with no input at all, because the
## source polls .CheckTile every frame rather than only on a press. Empty when
## the tile forces nothing.
func advance_forced_movement() -> Dictionary:
	var forced: Dictionary = forced_movement()
	match StringName(forced.get("kind", &"none")):
		&"force_turn":
			return _forced_turn()
		&"walk":
			return move_result(forced["direction"])
	return {}


## PLAYERMOVEMENT_FORCE_TURN, which queues Script_ForcedMovement: it reads
## VAR_FACING, the committed facing rather than the pressed direction, and applies
## a stream of step_dig, turn_in and turn_head. None of those opcodes moves a cell,
## so the whole effect is that the player is spun to face the way they came. A
## player who surfs onto a whirlpool therefore cannot walk off it, which is the
## cartridge's own behavior and not a gap here.
func _forced_turn() -> Dictionary:
	player_facing = _facing_for_direction(-_direction_for_facing(player_facing))
	return {
		"ok": true,
		"kind": &"forced_turn",
		"cell": player_cell,
		"facing": player_facing,
	}


## .continue_walk: STEP_WALK through .DoStep, which never consults permissions, so
## a forced step commits into a cell an ordinary step would refuse. It reaches
## .CheckTile before .TrySurf, so it also never runs .ExitWater: a forced step from
## water onto land keeps the surfing state. No shipped map places a forced tile
## where either matters; both are kept because the source has no guard for them.
func _forced_step(direction: Vector2i, destination: Vector2i) -> Dictionary:
	var from_map: Vector2i = map_id()
	var from_cell: Vector2i = player_cell
	var previous_cells: Dictionary = {}
	for index: int in objects.size():
		previous_cells[index] = (objects[index] as Gen2WorldObject).cell
	player_cell = destination
	player_facing = _facing_for_direction(direction)
	state.consume_repel_step()
	_advance_followers(from_cell, previous_cells)
	_start_player_step(direction, STEP_FRAMES_WALK)
	return {
		"ok": true,
		"kind": &"forced_move",
		"from_map": from_map,
		"from_cell": from_cell,
		"to_map": from_map,
		"to_cell": player_cell,
	}


## .CheckStrengthBoulder, then the boulder's own MovementFunction_Strength.
##
## The source splits these across two frames: the player's step flags the boulder
## and bumps, and the boulder starts moving on its next movement tick. Nothing
## observable sits between the two, because the boulder is not asked to decide
## anything in between and the flag it carries is cleared unread by nobody, so
## both are resolved here in one call. The player is not moved either way; the
## caller still reports a blocked step.
##
## Refusals, in the source's own order: BIKEFLAGS_STRENGTH_ACTIVE_F, then a
## boulder that is standing (OBJECT_WALKING == STANDING, so a boulder already
## mid-push is not pushed again), then the destination the boulder would take.
## The boulder's own cell being a pit stops it permanently
## (MovementFunction_Strength .on_pit), which is Blackthorn Gym 2F's puzzle and
## the only thing that reads it.
##
## [param destination] is the boulder's cell, already known to have refused the
## player. Its permission is checked here because .CheckLandPerms runs before
## .CheckNPC, so a boulder standing somewhere the player could not walk anyway is
## never even considered.
func _try_push_boulder(direction: Vector2i, destination: Vector2i) -> Dictionary:
	if not strength_active():
		return {}
	if not _step_permission_allows(destination, direction):
		return {}
	var boulder: Gen2WorldObject = object_at(destination)
	if boulder == null or not boulder.is_strength_boulder() or boulder.is_stepping():
		return {}
	if Gen2WorldCollision.is_pit_tile(collision_code_at(boulder.cell)):
		return {}
	var landing: Vector2i = boulder.cell + direction
	# CanObjectMoveInDirection with the boulder's own flags: WONT_DELETE,
	# FIXED_FACING, SLIDING and MOVE_ANYWHERE, palette bit STRENGTH_BOULDER and
	# no NOCLIP or SWIMMING. That leaves the destination's land permission, both
	# side-wall rules, and IsNPCAtCoord over the object structs, which start at
	# the player's own. can_object_walk_to() is those four tests.
	if not can_object_walk_to(landing, boulder, direction):
		return {}
	boulder.cell = landing
	# The stone queue is asked here, on the call that commits the cell, for the
	# same reason the push itself is resolved here: the source waits for the
	# boulder to reach STANDING, and nothing between those frames asks the
	# boulder anything or moves it again.
	var fall: Dictionary = stone_queue_script(boulder)
	# FIXED_FACING is set on the boulder's movement data, so InitStep skips the
	# OBJECT_DIRECTION write and the sprite keeps facing down while it slides.
	boulder.start_step(direction, STEP_FRAMES_BOULDER_PUSH)
	_remember_object_position(boulder)
	var pushed: Dictionary = {
		"index": boulder.index,
		"from_cell": landing - direction,
		"to_cell": landing,
		"direction": direction,
	}
	if not fall.is_empty():
		pushed["fall_script"] = int(fall["script"])
		_enqueue_script({
			"kind": &"stone_table",
			"map_group": current_map.group,
			"map_number": current_map.number,
			"cell": landing,
			"bank": int(fall["bank"]),
			"script": int(fall["script"]),
			"object_index": boulder.index,
		})
	return {
		"ok": false,
		"kind": &"move",
		"reason": &"blocked",
		"boulder_pushed": pushed,
	}


## engine/overworld/player_movement.asm's .TryJump, reached only after an ordinary
## step into [param direction] is blocked. Reads the collision code of the cell
## the player already stands on, not the faced cell; on a match the player covers
## two cells in one bounded action, bypassing collision on both the intervening
## and landing cells as the source does. An empty Dictionary means no hop, so the
## caller falls through to an ordinary blocked result. Surfing refuses outright,
## since .Surf calls .TrySurf then jumps straight to .NotMoving; a landing cell
## outside the map is refused too, as out-of-range cells always block here.
func _try_ledge_hop(direction: Vector2i) -> Dictionary:
	if movement_mode == MOVEMENT_SURF:
		return {}
	if not Gen2WorldCollision.allows_hop(collision_code_at(player_cell), direction):
		return {}
	var landing: Vector2i = player_cell + direction * 2
	if landing.x < 0 or landing.y < 0 \
		or landing.x >= current_map.collision_width \
		or landing.y >= current_map.collision_height:
		return {}
	var from_map: Vector2i = map_id()
	var from_cell: Vector2i = player_cell
	var previous_cells: Dictionary = {}
	for index: int in objects.size():
		previous_cells[index] = (objects[index] as Gen2WorldObject).cell
	player_cell = landing
	player_facing = _facing_for_direction(direction)
	state.consume_repel_step()
	_advance_followers(from_cell, previous_cells)
	_start_player_step(direction * 2, STEP_FRAMES_HOP)
	return {
		"ok": true,
		"kind": &"ledge_hop",
		"from_map": from_map,
		"from_cell": from_cell,
		"to_map": from_map,
		"to_cell": player_cell,
	}


## Moves exactly one walk cell in a cardinal direction, or two when a ledge
## hop applies. Diagonal, zero and out-of-bounds moves are rejected without
## changing the player position.
func move(direction: Vector2i) -> bool:
	return bool(move_result(direction).get("ok", false))


func _clamp_cell(cell: Vector2i) -> Vector2i:
	var size: Vector2i = map_size_cells()
	return Vector2i(
		clampi(cell.x, 0, maxi(0, size.x - 1)),
		clampi(cell.y, 0, maxi(0, size.y - 1)),
	)


func _direction_name(direction: Vector2i) -> String:
	match direction:
		Vector2i.UP:
			return "north"
		Vector2i.DOWN:
			return "south"
		Vector2i.LEFT:
			return "west"
		Vector2i.RIGHT:
			return "east"
	return ""


func _direction_for_facing(facing: int) -> Vector2i:
	match facing:
		Gen2WorldSprite.FACING_UP:
			return Vector2i.UP
		Gen2WorldSprite.FACING_LEFT:
			return Vector2i.LEFT
		Gen2WorldSprite.FACING_RIGHT:
			return Vector2i.RIGHT
	return Vector2i.DOWN


func _facing_for_direction(direction: Vector2i) -> int:
	match direction:
		Vector2i.UP:
			return Gen2WorldSprite.FACING_UP
		Vector2i.DOWN:
			return Gen2WorldSprite.FACING_DOWN
		Vector2i.LEFT:
			return Gen2WorldSprite.FACING_LEFT
		Vector2i.RIGHT:
			return Gen2WorldSprite.FACING_RIGHT
	return player_facing


func _fishing_failure(reason: StringName) -> Dictionary:
	return {
		"ok": false,
		"kind": &"fishing_failed",
		"reason": reason,
		"state": Gen2WorldFishing.STATE_IDLE,
	}


func _at_connection_edge(direction_name: String) -> bool:
	if current_map == null:
		return false
	match direction_name:
		"north":
			return player_cell.y == 0
		"south":
			return player_cell.y == current_map.collision_height - 1
		"west":
			return player_cell.x == 0
		"east":
			return player_cell.x == current_map.collision_width - 1
	return false


## engine/overworld/map_setup.asm's CheckUpdatePlayerSprite, which every warp and
## connection reaches through warp_connection.asm. The cartridge re-derives the
## player state from the cell it lands on rather than carrying it over:
## .CheckSurfing starts surfing on water and keeps an existing surf state,
## .ResetSurfingOrBikingState restores PLAYER_NORMAL anywhere else. Without it a
## warp taken from a water tile lands on dry land still surfing, where nothing
## but water is a legal step. .CheckForcedBiking has no counterpart here.
func _apply_map_setup_player_state() -> void:
	if collision_permission_at(player_cell) == Gen2WorldCollision.WATER_TILE:
		if movement_mode != MOVEMENT_SURF:
			movement_mode = MOVEMENT_SURF
			player_sprite_number = Gen2WorldSprite.SPRITE_SURF
		return
	if movement_mode == MOVEMENT_SURF:
		movement_mode = MOVEMENT_WALK
		player_sprite_number = Gen2WorldSprite.SPRITE_PLAYER


func _apply_map(
	target_map: Gen2WorldMap, target_tileset: Gen2WorldTileset, target_cell: Vector2i
) -> void:
	_block_overrides.clear()
	_pending_cut.clear()
	_pending_surf.clear()
	_pending_whirlpool.clear()
	_pending_strength.clear()
	# home/map.asm's map load calls ReadObjectEvents, which calls
	# ClearObjectStructs and re-reads every object event from ROM. moveobject
	# writes MAPOBJECT_X_COORD/Y_COORD in that same rebuilt table, so a scripted
	# position never survives a map load; a MAPCALLBACK_OBJECTS callback
	# re-applies it while its condition holds. Keeping these overrides across a
	# map change left objects where an earlier visit had put them:
	# ElmsLabMoveElmCallback moves Elm to (3, 4) during SCENE_ELMSLAB_MEET_ELM,
	# and the story then found nothing at his authored (5, 2) on returning.
	_object_position_overrides.clear()
	_object_facing_overrides.clear()
	state.reset_map_reload_flags()
	current_map = target_map
	current_tileset = target_tileset
	player_cell = _clamp_cell(target_cell)
	_apply_map_setup_player_state()
	_clear_player_step()
	# _load_objects() rebuilds every record, so in-flight object steps end with
	# the objects that owned them; only the shared frame accumulator survives.
	_object_step_accumulator = 0.0
	_load_objects()
	# The cartridge moves roaming Pokémon in map setup, not on a timer, so a
	# player who stands still does not watch them cross Johto.
	_last_schedule = advance_schedule(schedule_random)
	_queue_map_callbacks(-1)
	_map_entry_scene_pending = true


## The schedule update produced by the most recent map change, for a host that
## wants to report where the roamers went.
func last_schedule() -> Dictionary:
	return _last_schedule.duplicate(true)


## Reloads the current map's live object records without changing the player
## cell or queuing a second map transition. This is the host effect of
## [code]reloadmapafterbattle[/code] when the suspended script resumes.
func reload_current_map() -> Dictionary:
	if current_map == null or current_tileset == null:
		return {"ok": false, "reason": &"missing_map"}
	_block_overrides.clear()
	_pending_cut.clear()
	_pending_surf.clear()
	_pending_whirlpool.clear()
	_pending_strength.clear()
	state.reset_map_reload_flags()
	_load_objects()
	return {"ok": true, "kind": &"reload_map", "map": map_id(), "cell": player_cell}


func _on_world_state_changed() -> void:
	set_object_time(object_hour, object_time_of_day)


func _load_objects() -> void:
	objects = []
	if current_map == null or data == null:
		return
	var rows: Array = current_map.events.get("objects", [])
	for index: int in rows.size():
		var value: Dictionary = rows[index]
		var source_sprite_number: int = int(value.get("sprite", 0))
		var sprite_number: int = int(_variable_sprites.get(
			source_sprite_number, source_sprite_number
		))
		var sprite: Gen2WorldSprite = data.overworld_sprite(sprite_number)
		var object_event: Dictionary = value.duplicate(true)
		object_event["sprite"] = sprite_number
		var object: Gen2WorldObject = Gen2WorldObject.from_event(index, object_event, sprite)
		var key: String = _object_key(current_map.group, current_map.number, index)
		if _object_position_overrides.has(key):
			object.cell = _object_position_overrides[key]
		if _object_facing_overrides.has(key):
			object.facing = int(_object_facing_overrides[key])
		objects.append(object)
	set_object_time(object_hour, object_time_of_day)


## The source changeblock macro receives walk-cell coordinates. The cartridge
## adds four tile coordinates before resolving the padded block buffer. Since
## one block contains two walk cells and the live map exposes only its interior,
## the resulting local block is floor((source + 4) / 2) - 2.
func _script_block_cell(source_cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(source_cell.x + 4) / 2.0) - 2,
		floori(float(source_cell.y + 4) / 2.0) - 2,
	)


func _find_sight_request() -> Dictionary:
	if current_map == null:
		return {}
	var bank: int = int(current_map.events.get("bank", 0))
	var rows: Array = current_map.events.get("objects", [])
	for object: Gen2WorldObject in objects:
		if not object.active or object.sprite == null \
			or object.object_type != Gen2WorldObject.OBJECTTYPE_TRAINER \
			or object.sight_range <= 0 or object.event_script <= 0:
			continue
		if object.event_flag_active(state) or object.trainer_flag_active(state):
			continue
		var sight: Dictionary = _sight_distance(object)
		if sight.is_empty() or int(sight["distance"]) > object.sight_range:
			continue
		if object.index < 0 or object.index >= rows.size() or not rows[object.index] is Dictionary:
			continue
		var event: Dictionary = (rows[object.index] as Dictionary).duplicate(true)
		event["kind"] = &"objects"
		event["object_index"] = object.index
		event["trigger"] = &"sight"
		var request: Dictionary = _trainer_request_for_event(event)
		if request.is_empty():
			request = {
				"kind": &"sight",
				"map_group": current_map.group,
				"map_number": current_map.number,
				"cell": object.cell,
				"bank": bank,
				"script": object.event_script,
				"object_index": object.index,
				"event": event,
			}
		request["kind"] = &"sight"
		request["distance"] = int(sight["distance"])
		request["direction"] = sight["direction"]
		return request
	return {}


func _sight_distance(object: Gen2WorldObject) -> Dictionary:
	var delta: Vector2i = player_cell - object.cell
	var direction: Vector2i = Vector2i.ZERO
	match object.facing:
		Gen2WorldSprite.FACING_DOWN:
			if delta.x == 0 and delta.y > 0:
				direction = Vector2i.DOWN
		Gen2WorldSprite.FACING_UP:
			if delta.x == 0 and delta.y < 0:
				direction = Vector2i.UP
		Gen2WorldSprite.FACING_LEFT:
			if delta.y == 0 and delta.x < 0:
				direction = Vector2i.LEFT
		Gen2WorldSprite.FACING_RIGHT:
			if delta.y == 0 and delta.x > 0:
				direction = Vector2i.RIGHT
	if direction == Vector2i.ZERO:
		return {}
	return {"distance": absi(delta.x) + absi(delta.y), "direction": direction}
