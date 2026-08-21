extends RefCounted

## Sweeps every cached map script on all three cartridges for the `special`
## command and asserts that each index it reaches is one this project answers,
## or one of the named routines it deliberately does not.
##
## The class this exists to stop is a dispatch gap rather than a wrong reading:
## `Gen2WorldScriptRunner._execute_special` fails an index it does not name, and
## `_run_command`'s own `_fail` then stops the script where it stands, so one
## missing entry is a wall in front of every NPC that reaches it. Nothing else
## in the suite sees that, because a test reaches the specials it was written
## for and a story walk reaches the maps it was written for.
##
## `data/events/special_pointers.asm` is the corpus and the runner's own match
## is the claim, so the difference is derived rather than kept by hand:
## `EXPECTED_DEFERRED` names what is left, and a routine leaving that list is a
## line deleted here rather than a number edited.
##
##   Godot --headless --path . -s res://tools/validate.gd -- specials

## Every index the corpus reaches that this project answers with nothing, and
## the feature each belongs to. `Gen2WorldScriptRunner` is checked against this
## in both directions: an index here that the runner now handles fails, so the
## row is deleted with the work rather than left behind.
const EXPECTED_DEFERRED: Dictionary = {
	## HANDOFF's "Deliberately deferred": link play, the Mobile Adapter GB,
	## Mystery Gift and the Battle Tower. None of the four has a path to a
	## modern platform or a save section this project reads.
	1: "SetBitsForLinkTradeRequest", 2: "WaitForLinkedFriend",
	3: "CheckLinkTimeout_Receptionist", 4: "TryQuickSave",
	5: "CheckBothSelectedSameRoom", 6: "FailedLinkToPast", 7: "CloseLink",
	8: "WaitForOtherPlayerToExit", 9: "SetBitsForBattleRequest",
	10: "SetBitsForTimeCapsuleRequest", 11: "CheckTimeCapsuleCompatibility",
	12: "EnterTimeCapsule", 13: "TradeCenter", 14: "Colosseum", 15: "TimeCapsule",
	16: "CableClubCheckWhichChris", 17: "CheckMysteryGift",
	18: "GetMysteryGiftItem", 19: "UnlockMysteryGift", 88: "DisplayLinkRecord",
	116: "BattleTowerRoomMenu", 119: "BattleTowerBattle",
	122: "LoadOpponentTrainerAndPokemonWithOTSprite",
	124: "CheckForBattleTowerRules", 125: "GiveOddEgg",
	127: "Function1011f1", 128: "Function101220", 129: "Function101225",
	130: "Function101231", 134: "BattleTowerAction",
	136: "Menu_ChallengeExplanationCancel", 139: "BattleTowerMobileError",
	140: "AskMobileOrCable", 154: "Mobile_SelectThreeMons",
	155: "Function1037eb", 156: "Function10383c", 159: "Function1037c2",
	160: "CheckMobileAdapterStatusSpecial", 161: "Function103780",
	162: "Function10387b", 163: "AskRememberPassword",

	## Screens and facilities with no routine here yet. Each is its own piece of
	## work, not a dispatch entry: it opens a screen, spends a transaction, or
	## reads a save field nothing writes.
	25: "CheckMagikarpLength", 26: "MagikarpHouseSign",
	34: "BankOfMom", 39: "UnownPrinter", 40: "MapRadio", 41: "UnownPuzzle",
	42: "SlotMachine", 43: "CardFlip", 57: "GameCornerPrizeMonCheckDex",
	75: "GiveShuckle", 76: "ReturnShuckie",
	82: "CheckForLuckyNumberWinners",
	83: "CheckLuckyNumberShowFlag", 84: "ResetLuckyNumberShowFlag",
	85: "PrintTodaysLuckyNumber", 103: "TrainerHouse",
	104: "PhotoStudio", 107: "Diploma", 108: "PrintDiploma",
	126: "Reset", 131: "MoveTutor", 132: "OmanyteChamber",
	141: "HoOhChamber", 143: "CelebiShrineEvent", 144: "CheckCaughtCelebi",
	145: "PokeSeer", 146: "BuenasPassword", 147: "BuenaPrize",
	148: "GiveDratini", 149: "SampleKenjiBreakCountdown",

	## Reached by one script row each and by nothing the player can talk to.
	## `FindPartyMonAboveLevel` is marked `; unused` in the pin's own table.
	0: "WarpToSpawnPoint", 64: "FindPartyMonAboveLevel",
}

## Decoded `special` operands that name no `SpecialsPointers` entry. Pinned
## rather than filtered, so a walker that starts overrunning a script again is
## caught here: every one of these comes from a cached script pointer, and a
## pointer only exists because some walk collected it.
##
## Crystal's one is the cartridge's own. BattleTowerElevator.asm's receptionist
## is an `OBJECTTYPE_SCRIPT` object whose script word is
## `MovementData_BattleTowerElevatorReceptionistWalksIn`, so the bytes behind it
## are movement rather than commands; the object stands in a room the scene
## script drives and is never talked to.
const EXPECTED_OUT_OF_TABLE: Dictionary = {&"crystal": 1, &"gold": 0, &"silver": 0}

## The five fades and what each of them costs, from `ConvertTimePals*HL`'s own
## `ld c` and `BattleTowerFade`'s. A fade that spends no frame is what this
## number is here to stop.
const EXPECTED_FADE_FRAMES: Dictionary = {46: 8, 47: 28, 48: 8, 49: 8, 50: 8}

## `data/events/special_pointers.asm`'s own length, the same in both pins.
const SPECIALS_POINTERS_SIZE: int = 169

var _r: RefCounted = null
## Which indices the runner answers, derived from the runner rather than kept
## beside it: a second copy of the match would go stale the first time one is
## built, which is the whole failure this topic exists to catch.
var _handled: Dictionary = {}


func run(r: RefCounted) -> void:
	_r = r
	_probe_handled()
	_verify_fade_table()
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_r.game_id = game_id
		_verify_corpus(data, game_id == &"crystal")
		_verify_slow_cry(data)
	_r.game_id = &""
	_verify_deferred_list_is_current()


## `_execute_special` asked about every index in `SpecialsPointers`. An index it
## answers with `unsupported_phone_special` is one no script can reach; every
## other reason (a missing party mirror, an absent record) is a handler that ran.
func _probe_handled() -> void:
	for special: int in SPECIALS_POINTERS_SIZE:
		var runner := Gen2WorldScriptRunner.new()
		var result: Variant = runner.call(&"_execute_special", special)
		if result is Dictionary and StringName((result as Dictionary).get(
			"reason", &""
		)) == &"unsupported_phone_special":
			continue
		_handled[special] = true
	_r.check(
		not _handled.is_empty(), "the runner answers no special at all"
	)


## Each fade's four rows and the frames it holds each of them for, against the
## runner's own tables rather than against a repeated literal.
func _verify_fade_table() -> void:
	for raw_special: Variant in EXPECTED_FADE_FRAMES:
		var special: int = int(raw_special)
		var orders: Array = Gen2WorldScriptRunner.FADE_ORDERS_OF.get(special, [])
		_r.check(
			orders.size() == 4,
			"special %d walks %d fade rows, not 4" % [special, orders.size()]
		)
		var step_frames: int = Gen2WorldPalette.BATTLE_TOWER_FADE_STEP_FRAMES \
			if special == Gen2WorldScriptRunner.SPECIAL_BATTLE_TOWER_FADE \
			else Gen2WorldPalette.FADE_STEP_FRAMES
		_r.check(
			orders.size() * step_frames == int(EXPECTED_FADE_FRAMES[special]),
			"special %d spends %d frames, not %d" % [
				special, orders.size() * step_frames, EXPECTED_FADE_FRAMES[special],
			]
		)
		## Both ends of the walk are rows of `.cgbfade`, and the one it starts or
		## ends on is the identity, which is what says the direction is right.
		_r.check(
			Gen2WorldPalette.FADE_IDENTITY in [int(orders[0]), int(orders[3])],
			"special %d's fade touches neither end of the identity row" % special
		)
		for order: Variant in orders:
			_r.check(
				Gen2WorldPalette.FADE_ORDERS.has(int(order)),
				"special %d walks row %d, which is not one of .cgbfade's" % [
					special, int(order),
				]
			)


## `PlaySlowCry` edits the record `LoadCry` just loaded rather than playing a
## second one: `wCryPitch` less `$140` and `wCryLength` plus `$60`, both sixteen
## bit. Swept over every species rather than one, since a record whose pitch is
## already below `$140` is where the wrap shows.
func _verify_slow_cry(data: GameData) -> void:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(0, 0))
	if world == null:
		_r.fail("the first map is unavailable")
		return
	var checked: int = 0
	for species: int in range(1, 252):
		var plain: Dictionary = Gen2WorldHost.audio_for_request(world, {
			"values": {"kind": &"cry", "species": species},
		})
		if plain.is_empty():
			continue
		var slow: Dictionary = Gen2WorldHost.audio_for_request(world, {
			"values": {"kind": &"cry", "species": species, "slow": true},
		})
		checked += 1
		if int(slow.get("cry_pitch", 0)) != (int(plain["cry_pitch"]) - 0x140) & 0xFFFF \
			or int(slow.get("cry_length", 0)) != (int(plain["cry_length"]) + 0x60) & 0xFFFF:
			_r.fail("species %d's slow cry is not the record moved" % species)
			return
		## The plain request has to be left alone, or `Script_cry` plays the
		## slow one after a `PlaySlowCry` has run once.
		if int(Gen2WorldHost.audio_for_request(world, {
			"values": {"kind": &"cry", "species": species},
		}).get("cry_pitch", -1)) != int(plain["cry_pitch"]):
			_r.fail("species %d's own record was edited in place" % species)
			return
	_r.check(checked >= 250, "%d species cries read, not 251" % checked)


## Every cached script on one cartridge, walked for `special` and tallied.
func _verify_corpus(data: GameData, crystal_commands: bool) -> void:
	var scripts: Array = data.world_script_keys()
	if scripts.is_empty():
		_r.fail("the script table is missing")
		return
	var reached: Dictionary = {}
	for raw_key: Variant in scripts:
		var parts: PackedStringArray = String(raw_key).split(":")
		if parts.size() != 2:
			continue
		var bytes: PackedByteArray = data.world_script(
			int(parts[0]), ("0x%s" % parts[1]).hex_to_int()
		)
		for special: int in _specials_in(bytes, crystal_commands):
			reached[special] = int(reached.get(special, 0)) + 1
	var unnamed: PackedStringArray = PackedStringArray()
	var sites: int = 0
	var out_of_table: int = 0
	for raw_special: Variant in reached:
		var special: int = int(raw_special)
		if special < 0 or special >= SPECIALS_POINTERS_SIZE:
			out_of_table += int(reached[raw_special])
			continue
		if _handled.has(special) or EXPECTED_DEFERRED.has(special):
			continue
		unnamed.append("%d (%d sites)" % [special, int(reached[raw_special])])
		sites += int(reached[raw_special])
	_r.check(
		out_of_table == int(EXPECTED_OUT_OF_TABLE.get(data.id, -1)),
		"%d decoded specials fall outside SpecialsPointers, not %d" % [
			out_of_table, EXPECTED_OUT_OF_TABLE.get(data.id, -1),
		]
	)
	_r.check(
		unnamed.is_empty(),
		"%d script sites reach a special this project neither answers nor names: %s" % [
			sites, ", ".join(unnamed),
		]
	)
	## The census the exit code cannot carry: how much of the corpus is still
	## waiting on a named routine, which is what says whether the list is
	## shrinking between sessions.
	var deferred_sites: int = 0
	var deferred_indices: int = 0
	for raw_special: Variant in reached:
		if not EXPECTED_DEFERRED.has(int(raw_special)):
			continue
		deferred_indices += 1
		deferred_sites += int(reached[raw_special])
	_r.note(
		"%d script sites reach %d named-but-unbuilt specials." % [
			deferred_sites, deferred_indices,
		]
	)
	## The other direction: a routine that is built has to leave the list, or
	## the list stops describing what is missing.
	for raw_special: Variant in EXPECTED_DEFERRED:
		_r.check(
			not _handled.has(int(raw_special)),
			"special %d (%s) is built and still listed as deferred" % [
				int(raw_special), EXPECTED_DEFERRED[raw_special],
			]
		)


## Every special index one script's bytes reach, stopping where control leaves
## the script rather than at its last byte.
func _specials_in(bytes: PackedByteArray, crystal_commands: bool) -> Array[int]:
	var out: Array[int] = []
	var offset: int = 0
	var steps: int = 0
	while offset < bytes.size() and steps < Gen2WorldScript.MAX_COMMANDS:
		var command: Dictionary = Gen2WorldScript.command_at(bytes, offset, crystal_commands)
		if not bool(command.get("ok", false)):
			break
		var name: String = String(command.get("name", ""))
		if name == "special":
			out.append(Gen2WorldScript.special_index(
				int(command.get("value", -1)), crystal_commands
			))
		steps += 1
		offset += int(command["width"])
		if not Gen2WorldScript.continues_after(int(command["opcode"]), crystal_commands):
			break
	return out


## The list names routines, so a typo in one is a row that can never be deleted.
## `SpecialsPointers` is `SPECIALS_POINTERS_SIZE` entries long in both pins.
func _verify_deferred_list_is_current() -> void:
	for raw_special: Variant in EXPECTED_DEFERRED:
		var special: int = int(raw_special)
		_r.check(
			special >= 0 and special < SPECIALS_POINTERS_SIZE,
			"deferred special %d is outside SpecialsPointers" % special
		)
		_r.check(
			not String(EXPECTED_DEFERRED[raw_special]).is_empty(),
			"deferred special %d is unnamed" % special
		)
