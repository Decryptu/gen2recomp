class_name Gen2BattleWorldContext
extends RefCounted

## Where a battle is being fought, as the world was when it started.
##
## [Gen2BattleScreen] hands a battle renderer display values and nothing else,
## which is all the cartridge's own battle needs. A renderer staging the fight on
## the map instead of on a white field needs the place as well, so this carries
## it: the map and its tileset, the player's cell and facing, and the time of day
## the world was drawn with.
##
## It is a copy taken at battle start, not a handle on the world: a renderer
## cannot reach live world state through it and the two screens stay
## independent. The map and tileset are named by number, which is what
## [method GameData.world_map] and [method GameData.world_tileset] take, so a
## renderer resolves the records it wants through the [GameData] it was already
## given.

## Group and number, the pair every map is addressed by, as
## [member Gen2WorldSnapshot.map_id] holds it.
var map_id: Vector2i = Vector2i(-1, -1)
var tileset: int = -1
var player_cell: Vector2i = Vector2i.ZERO
var player_facing: int = Gen2WorldSprite.FACING_DOWN
## The row the world was drawn with rather than the hour: a dark cave is night
## until Flash is used. See [method Gen2WorldPalette.map_time_of_day].
var time_of_day: int = Gen2WorldPalette.TIME_DAY
## `GetWorldMapLocation`'s answer for this map, which is what `RegionCheck`
## reads and so what `PlayBattleMusic` picks a wild track off.
var landmark: int = Gen2WorldRadio.LANDMARK_SPECIAL


## The world's own values, read once. [param drawn_time_of_day] is the caller's,
## because the palette row a screen draws with is the screen's answer and not
## the world's; passing -1 takes the world's map row.
static func capture(
	world: Gen2WorldAPI, drawn_time_of_day: int = -1
) -> Gen2BattleWorldContext:
	if world == null or world.current_map == null:
		return null
	var out := Gen2BattleWorldContext.new()
	out.map_id = Vector2i(world.current_map.group, world.current_map.number)
	out.tileset = world.current_map.tileset
	out.player_cell = world.player_cell
	out.player_facing = world.player_facing
	out.landmark = world.landmark()
	out.time_of_day = clampi(
		drawn_time_of_day if drawn_time_of_day >= 0 else world.map_time_of_day(), 0, 3
	)
	return out


func map_group() -> int:
	return map_id.x


func map_number() -> int:
	return map_id.y


func to_dictionary() -> Dictionary:
	return {
		"map_id": map_id,
		"tileset": tileset,
		"player_cell": player_cell,
		"player_facing": player_facing,
		"time_of_day": time_of_day,
		"landmark": landmark,
	}
