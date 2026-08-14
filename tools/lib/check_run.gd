extends RefCounted

## The harness every `tools/validate.gd` topic shares: the three cartridges, the
## failure list, and the world helpers a map check needs.
##
## A topic is a script under `tools/checks/` with `func run(r) -> void`. It
## reports through [method check] and prints its own census lines with
## [method note]; the runner owns the exit code.

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## The party [code]CheckPartyMove[/code] gates every field move against. These
## checks are about the tables and the map rather than the party, so a world one
## opens carries a member that knows all five. The story route is where a real
## party earning them is proved.
const FIELD_MOVE_PARTY_SIZE: int = 1

var failures: PackedStringArray = []

## Set per game by [method each_game] so a topic can read them without threading
## them through every helper.
var game_id: StringName = &""
var data: GameData = null
var crystal: bool = false


## Records [param message] when [param condition] is false, and answers it so a
## caller can stop after a failed precondition.
func check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append("%s: %s" % [game_id, message] if game_id != &"" else message)
	return condition


func fail(message: String) -> void:
	check(false, message)


## A census or landmark line. Kept apart from [method fail] so a topic reads the
## same whether it is passing or not.
func note(message: String) -> void:
	print("%s: %s" % [game_id, message] if game_id != &"" else message)


## Runs [param body] once per cartridge with [member data], [member game_id] and
## [member crystal] set. A cache that will not open is one failure, not a crash.
func each_game(body: Callable) -> void:
	for id: StringName in GAME_IDS:
		var opened: GameData = GameData.open(id)
		if opened == null:
			game_id = &""
			fail("%s cache is unavailable. Import roms/%s.gbc first." % [id, id])
			continue
		game_id = id
		data = opened
		crystal = Gen2WorldState.is_crystal_profile(opened)
		body.call()
	game_id = &""
	data = null


## A world opened on [param cell], with [param state] or a fresh one. Answers
## null and records the failure when the map is not in the cache.
func open_world(
	group: int, number: int, cell: Vector2i, state: Gen2WorldState = null
) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, group, number, cell, state if state != null else Gen2WorldState.new()
	)
	if world == null:
		fail("map %d/%d is missing." % [group, number])
	return world


## Every cell reachable on foot from [param from], which is what says two parts
## of a map are joined or sealed off from each other.
func region(world: Gen2WorldAPI, from: Vector2i) -> Dictionary:
	var seen: Dictionary = {from: true}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + step
			if seen.has(next) or not world.can_walk_to(next):
				continue
			seen[next] = true
			frontier.append(next)
	return seen


## Gives [param world] the party every field-move check assumes.
func field_move_party(world: Gen2WorldAPI) -> void:
	world.set_party_summary(
		FIELD_MOVE_PARTY_SIZE, false, [1] as Array[int],
		[Gen2WorldFieldMove.FIELD_MOVES.duplicate()], ["MON"], [false]
	)
