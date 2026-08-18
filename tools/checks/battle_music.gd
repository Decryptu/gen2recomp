extends RefCounted

var _r: RefCounted = null

## Verifies `PlayBattleMusic` (engine/battle/start_battle.asm) against freshly
## imported real caches, on all three cartridges.
##
## The routine is a walk down a list of compares, so the failure it can have is
## not an arithmetic one: it is a row that stops being reachable, or a track it
## names that the audio importer does not hold. Both are swept here over the
## whole corpus rather than sampled, which is two sweeps:
##
## - every map in the cache, through `RegionCheck`, so the wild rows are asked
##   at every landmark the cartridge has rather than at one;
## - every trainer class the cartridge ships and every individual trainer inside
##   it, so the RIVAL2 id split and both leader lists are reached by real data.
##
## Every track either sweep names is then looked up in the imported audio index,
## which is what says the piece can actually be played. Gold and Silver have no
## `MUSIC_SUICUNE_BATTLE` and never write the two battle types that reach it, so
## that row is asked of Crystal alone.
##
##   Godot --headless --path . -s res://tools/validate.gd -- battle_music

## The two hours the wild rows split on. Only Johto has a night track.
const HOURS: Array[int] = [Gen2WorldPalette.TIME_DAY, Gen2WorldPalette.TIME_NIGHT]


func run(r: RefCounted) -> void:
	_r = r
	_r.each_game(func() -> void:
		_verify_wild_over_every_map()
		_verify_every_trainer_class()
		_verify_the_crystal_only_row()
	)


## `RegionCheck` over the whole map list, which is the only input a wild battle's
## track has beyond the hour.
func _verify_wild_over_every_map() -> void:
	var tracks: Dictionary = {}
	var kanto_maps: int = 0
	for map: Gen2WorldMap in _r.data.world_maps():
		if Gen2Battle.region_is_kanto(map.location, _r.crystal):
			kanto_maps += 1
		for hour: int in HOURS:
			var track: int = Gen2Battle.battle_music(
				Gen2Battle.BATTLETYPE_NORMAL, 0, 0, map.location, hour, _r.crystal
			)
			tracks[track] = int(tracks.get(track, 0)) + 1
			_verify_track_exists(track, "map %d/%d at hour %d" % [
				map.group, map.number, hour,
			])
	var wanted: Array = [
		Gen2Battle.MUSIC_JOHTO_WILD_BATTLE,
		Gen2Battle.MUSIC_JOHTO_WILD_BATTLE_NIGHT,
		Gen2Battle.MUSIC_KANTO_WILD_BATTLE,
	]
	var found: Array = tracks.keys()
	found.sort()
	wanted.sort()
	_r.note("wild: %d maps, %d in Kanto, tracks %s." % [
		_r.data.world_maps().size(), kanto_maps, str(found),
	])
	_r.check(
		found == wanted,
		"the corpus reaches wild tracks %s, not all three of %s." % [
			str(found), str(wanted),
		]
	)
	## A cartridge with no Kanto map would pass the row above by accident.
	_r.check(kanto_maps > 0, "no map in the corpus is in Kanto.")


## Every class the cartridge ships, and every individual trainer inside it, so
## the RIVAL2 id split is asked with the ids that exist rather than invented.
func _verify_every_trainer_class() -> void:
	var tracks: Dictionary = {}
	var classes: int = 0
	for trainer_class: int in range(1, _r.data.trainer_count() + 1):
		var count: int = _r.data.trainer_party_count(trainer_class)
		if count == 0:
			continue
		classes += 1
		for index: int in count:
			## `wOtherTrainerID` is one-based, which is what `trainerclass`
			## restarts its own count at.
			var track: int = Gen2Battle.battle_music(
				Gen2Battle.BATTLETYPE_NORMAL, trainer_class, index + 1,
				Gen2WorldRadio.LANDMARK_SPECIAL, Gen2WorldPalette.TIME_DAY, _r.crystal
			)
			tracks[track] = int(tracks.get(track, 0)) + 1
			_verify_track_exists(track, "trainer class %d id %d" % [
				trainer_class, index + 1,
			])
	var found: Array = tracks.keys()
	found.sort()
	_r.note("trainers: %d classes, tracks %s." % [classes, str(found)])
	## Every row of `.trainermusic` but the Kanto ones, which need a Kanto
	## landmark rather than a class and are swept above.
	for track: int in [
		Gen2Battle.MUSIC_CHAMPION_BATTLE, Gen2Battle.MUSIC_ROCKET_BATTLE,
		Gen2Battle.MUSIC_KANTO_GYM_LEADER_BATTLE,
		Gen2Battle.MUSIC_JOHTO_GYM_LEADER_BATTLE, Gen2Battle.MUSIC_RIVAL_BATTLE,
		Gen2Battle.MUSIC_JOHTO_TRAINER_BATTLE,
	]:
		_r.check(
			tracks.has(track),
			"no trainer class in the corpus reaches track %d." % track
		)
	## The same classes on a Kanto landmark, which is the only way the ordinary
	## trainer row changes its answer.
	var kanto: int = Gen2Battle.battle_music(
		Gen2Battle.BATTLETYPE_NORMAL, 0x16, 1,
		Gen2WorldRadio.kanto_landmark(_r.crystal), Gen2WorldPalette.TIME_DAY, _r.crystal
	)
	_r.check(
		kanto == Gen2Battle.MUSIC_KANTO_TRAINER_BATTLE,
		"a Kanto trainer takes track %d rather than the Kanto trainer battle." % kanto
	)
	_verify_track_exists(Gen2Battle.MUSIC_KANTO_TRAINER_BATTLE, "a Kanto trainer")


## `MUSIC_SUICUNE_BATTLE` is Crystal's own constant; the two battle types that
## reach it are written by no Gold or Silver script.
func _verify_the_crystal_only_row() -> void:
	for battle_type: int in [Gen2Battle.BATTLETYPE_SUICUNE, Gen2Battle.BATTLETYPE_ROAMING]:
		var track: int = Gen2Battle.battle_music(
			battle_type, Gen2Battle.TRAINER_CLASS_CHAMPION, 1,
			Gen2WorldRadio.kanto_landmark(_r.crystal),
			Gen2WorldPalette.TIME_NIGHT, _r.crystal
		)
		_r.check(
			track == Gen2Battle.MUSIC_SUICUNE_BATTLE,
			"battle type %d takes track %d rather than Suicune's." % [battle_type, track]
		)
	if _r.crystal:
		_verify_track_exists(Gen2Battle.MUSIC_SUICUNE_BATTLE, "a Suicune battle")


func _verify_track_exists(track: int, where: String) -> void:
	if _r.data.world_audio(&"music", track).is_empty():
		_r.fail("%s asks for track %d, which the audio index does not hold." % [
			where, track,
		])
