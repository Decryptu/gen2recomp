extends RefCounted

var _r: RefCounted = null

## Verifies the profile map ids `tools/preview_world_story.gd` resolves by name
## against freshly imported real caches, for both command profiles.
##
## A map number counts from its group's first entry, so a map pokegold does not
## ship shifts every later number in that group: group 3 runs eight lower from
## UNION_CAVE_1F on, because pokecrystal inserts eight Ruins of Alph word and
## item rooms (constants/map_constants.asm). The route walker names only the
## maps it reaches by id rather than by cell, and only Ilex Forest is on a
## walked leg today; the other three are read by the Mahogany and Rocket Base
## legs, which no Gold walk reaches yet, so a wrong number there would be
## silent. That is what this file is for.
##
## Each row carries the map's own block dimensions from its `map_const`, which
## is what makes a wrong number loud: every number in this table resolves to a
## differently sized map on the other profile.
##
##   Godot --headless --path . -s res://tools/validate.gd -- story_map_ids


## name: [crystal id, gold id, block width, block height]. The dimensions are
## the same on both profiles; only the number moves.
const MAP_IDS: Dictionary = {
	&"ILEX_FOREST": [Vector2i(3, 52), Vector2i(3, 44), 15, 27],
	&"MAHOGANY_MART_1F": [Vector2i(3, 48), Vector2i(3, 40), 4, 4],
	&"TEAM_ROCKET_BASE_B2F": [Vector2i(3, 50), Vector2i(3, 42), 15, 9],
	&"TEAM_ROCKET_BASE_B3F": [Vector2i(3, 51), Vector2i(3, 43), 15, 9],
}

## What the wrong profile's number resolves to on this cartridge, pinned so the
## split is proved rather than assumed: a wrong number is a wrong map, not a
## missing one, and would otherwise read a scene off whatever sits there.
## name: [dimensions on a Gold or Silver cache, dimensions on a Crystal cache].
const WRONG_PROFILE_MAPS: Dictionary = {
	# MOUNT_MORTAR_B1F on Gold and Silver, OLIVINE_LIGHTHOUSE_3F on Crystal
	&"ILEX_FOREST": [Vector2i(20, 18), Vector2i(10, 9)],
	# GOLDENROD_UNDERGROUND_WAREHOUSE, SLOWPOKE_WELL_B1F
	&"MAHOGANY_MART_1F": [Vector2i(10, 9), Vector2i(10, 9)],
	# MOUNT_MORTAR_1F_INSIDE, OLIVINE_LIGHTHOUSE_1F
	&"TEAM_ROCKET_BASE_B2F": [Vector2i(20, 27), Vector2i(10, 9)],
	# MOUNT_MORTAR_2F_INSIDE, OLIVINE_LIGHTHOUSE_2F
	&"TEAM_ROCKET_BASE_B3F": [Vector2i(20, 18), Vector2i(10, 9)],
}


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		var crystal: bool = Gen2WorldState.is_crystal_profile(data)
		for name: StringName in MAP_IDS:
			_verify_row(game_id, data, crystal, name)


func _verify_row(
	game_id: StringName, data: GameData, crystal: bool, name: StringName
) -> void:
	var row: Array = MAP_IDS[name]
	var id: Vector2i = row[0] if crystal else row[1]
	var other: Vector2i = row[1] if crystal else row[0]
	var map: Gen2WorldMap = data.world_map(id.x, id.y)
	if not _r.check(
		map != null, "%s: %s is missing at %d/%d." % [game_id, name, id.x, id.y]
	):
		return
	_r.check(
		map.width_blocks == int(row[2]) and map.height_blocks == int(row[3]),
		"%s: %s at %d/%d is %dx%d blocks, not the pinned %dx%d." % [
			game_id, name, id.x, id.y,
			map.width_blocks, map.height_blocks, int(row[2]), int(row[3]),
		]
	)
	## The other profile's number has to resolve to the pinned other map, which
	## is what proves the split rather than merely asserting one exists.
	var wrong: Gen2WorldMap = data.world_map(other.x, other.y)
	var expected: Vector2i = WRONG_PROFILE_MAPS[name][1 if crystal else 0]
	if not _r.check(
		wrong != null,
		"%s: %d/%d, which is %s on the other profile, is missing." % [
			game_id, other.x, other.y, name,
		]
	):
		return
	_r.check(
		Vector2i(wrong.width_blocks, wrong.height_blocks) == expected,
		"%s: %d/%d is %dx%d blocks, not the %dx%d the other profile's %s number holds." % [
			game_id, other.x, other.y,
			wrong.width_blocks, wrong.height_blocks, expected.x, expected.y, name,
		]
	)
