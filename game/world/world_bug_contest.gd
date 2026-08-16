class_name Gen2WorldBugContest
extends RefCounted

## The Bug Catching Contest: its own encounter roll, its score, and its judging
## (`engine/events/bug_contest/`, `engine/overworld/events.asm`'s
## `TryWildEncounter_BugContest` and `ChooseWildEncounter_BugContest`).
##
## Scene-free and stateless, like [Gen2WorldTreemon]: the tables are the cache's
## (`GameData.bug_contest_mons`, `GameData.bug_contestants`), the live counters
## are [Gen2WorldState]'s, and every roll takes the caller's generator so a
## contest is reproducible.

## constants/script_constants.asm.
const BALLS: int = 20
const MINUTES: int = 20
const SECONDS: int = 0
const PLAYER_ID: int = 1
const NUM_CONTESTANTS: int = 10
## `ContestMons`' own eleven rows, the last of which is the `db -1` sentinel.
const NUM_CONTEST_MONS: int = 11
## `SelectRandomBugContestContestants` sets five of the ten flags, and a set
## flag is a contestant who is *not* in this contest: `ComputeAIContestantScores`
## skips the ones whose flag answers nz.
const CONTESTANTS_WITHDRAWN: int = 5

## `macros/data.asm`'s `percent`, which is `* $ff / 100`, so these are the two
## `TryWildEncounter_BugContest` loads rather than 40 and 20.
const RATE_LONG_GRASS: int = 40 * 0xFF / 100
const RATE_ELSEWHERE: int = 20 * 0xFF / 100

## `ChooseWildEncounter_BugContest`'s own `cp 100 << 1`: the roll is taken over
## 0-199 and halved, so the walk down the percentages is uniform over 0-99.
const CHOICE_LIMIT: int = 200


## `TryWildEncounter_BugContest` then `ChooseWildEncounter_BugContest`: the rate
## is the standing tile's, the two rate modifiers are the ordinary ones, and the
## table is walked by percentage. Answers the same shape
## [method Gen2WorldEncounter.resolve] does, or an empty Dictionary.
static func resolve(
	mons: Array,
	long_grass: bool,
	random: RandomNumberGenerator,
	force_encounter: bool = false,
	options: Dictionary = {},
) -> Dictionary:
	if mons.is_empty() or random == null:
		return {}
	var rate: int = RATE_LONG_GRASS if long_grass else RATE_ELSEWHERE
	rate = Gen2WorldEncounter.apply_music_effect(rate, int(options.get("map_music", 0)))
	if bool(options.get("cleanse_tag", false)):
		rate >>= 1
	var encounter_roll: int = -1
	if not force_encounter:
		encounter_roll = random.randi_range(0, 255)
		if encounter_roll >= rate:
			return {}

	var choice_roll: int = -1
	for _attempt: int in 128:
		var roll: int = random.randi_range(0, 255)
		if roll < CHOICE_LIMIT:
			choice_roll = roll >> 1
			break
	if choice_roll < 0:
		return {}

	var remaining: int = choice_roll
	var chosen: Dictionary = {}
	for row: Dictionary in mons:
		remaining -= int(row.get("percent", 0))
		if remaining < 0:
			chosen = row
			break
	if chosen.is_empty():
		return {}

	var level: int = _level(chosen, random)
	if int(options.get("repel_steps", 0)) > 0 and int(options.get("lead_level", -1)) > 0 \
		and level < int(options["lead_level"]):
		return {}
	return {
		"kind": &"wild_encounter_requested",
		"method": Gen2WorldEncounter.METHOD_GRASS,
		"source": SOURCE_CONTEST,
		"slot": -1,
		"pokemon": int(chosen.get("species", 0)),
		"level": level,
		"rate": rate,
		"encounter_roll": encounter_roll,
		"choice_roll": choice_roll,
		"forced": force_encounter,
		"battle_type": BATTLE_TYPE,
		"values": {
			"kind": &"wild", "pokemon": int(chosen.get("species", 0)), "level": level,
			## `loadvar VAR_BATTLETYPE, BATTLETYPE_CONTEST`, which
			## `BugCatchingContestBattleScript` sets before `startbattle`.
			"battle_type": BATTLE_TYPE,
		},
	}


## The encounter's own source name, beside [Gen2WorldEncounter]'s five. The
## battle type is the engine's own constant rather than a second copy of it.
const SOURCE_CONTEST: StringName = &"bug_contest"
const BATTLE_TYPE: int = Gen2Battle.BATTLETYPE_CONTEST


## `.RandomLevel`: a level between the row's own two, taken as
## `ContestMons` in the shape [method Gen2WorldEncounter.active_slots] answers
## in, which is how a caller reads the table the contest replaces the map's with.
## The percentages are the roll's and are not part of what a slot offers.
static func active_slots(mons: Array) -> Array:
	var out: Array = []
	for row: Variant in mons:
		if not row is Dictionary:
			continue
		var low: int = int((row as Dictionary).get("min_level", 1))
		out.append({
			"species": int((row as Dictionary).get("species", 0)),
			"min_level": low,
			"max_level": maxi(low, int((row as Dictionary).get("max_level", low))),
		})
	return out


## `Random % (max - min + 1) + min`, which `SimpleDivide`'s remainder is. Equal
## bounds skip the roll entirely, so a Venomoth costs no draw.
static func _level(row: Dictionary, random: RandomNumberGenerator) -> int:
	var low: int = int(row.get("min_level", 1))
	var high: int = int(row.get("max_level", low))
	if high <= low:
		return low
	return low + random.randi_range(0, 255) % (high - low + 1)


## `ContestScore`: the tally the player's caught Pokemon is judged on. Every
## term is the *low* byte of a big-endian word, which is the stat itself for
## anything a contest Pokemon can reach, and the whole runs 16 bit with carry.
##
## [param mon] is the caught Pokemon as [Gen2WorldState] keeps it:
## `max_hp`, `hp`, `attack`, `defense`, `speed`, `special_attack`,
## `special_defense`, `dvs` and `item`.
static func score(mon: Dictionary) -> int:
	if int(mon.get("species", 0)) <= 0:
		return 0
	var total: int = 0
	for _copy: int in 4:
		total += int(mon.get("max_hp", 0)) & 0xFF
	for stat: String in [
		"attack", "defense", "speed", "special_attack", "special_defense",
	]:
		total += int(mon.get(stat, 0)) & 0xFF
	total += _dv_score(int(mon.get("dvs", 0)))
	total += (int(mon.get("hp", 0)) & 0xFF) >> 3
	if int(mon.get("item", 0)) > 0:
		total += 1
	return total & 0xFFFF


## The DV term, bit for bit. Only bit 1 of each of the four DVs is read, which
## is the same bit `CheckShininess` reads, and each is weighted differently:
## attack twice, defense four times, speed a half and special twice, the whole
## then doubled twice by the two `add d`s.
static func _dv_score(dvs: int) -> int:
	var attack: int = (dvs >> 12) & 0x0F
	var defense: int = (dvs >> 8) & 0x0F
	var speed: int = (dvs >> 4) & 0x0F
	var special: int = dvs & 0x0F
	var first: int = ((attack & 0x02) << 1) + ((defense & 0x02) << 2)
	var second: int = ((speed & 0x02) >> 1) + ((special & 0x02) << 1)
	return (second + first * 2) & 0xFF


## `BugContest_JudgeContestants`: the AI contestants are scored first and the
## player is inserted last, which is why the player takes a place on a tie.
##
## [param withdrawn] is the set of contestant indices whose event flag is set,
## which `SelectRandomBugContestContestants` chose and who therefore do not
## compete. Answers `{"placings": [...], "player_place": 0..3}` with the placings
## first to third, each `{"id", "species", "score"}` and an id of
## [constant PLAYER_ID] for the player.
static func judge(
	player_species: int,
	player_score: int,
	contestants: Array,
	withdrawn: Dictionary,
	random: RandomNumberGenerator,
) -> Dictionary:
	var placings: Array = []
	for index: int in mini(NUM_CONTESTANTS, contestants.size()):
		if bool(withdrawn.get(index, false)):
			continue
		var entry: Dictionary = contestants[index]
		var rows: Array = entry.get("placings", [])
		if rows.is_empty():
			continue
		var pick: int = -1
		for _attempt: int in 128:
			var roll: int = random.randi_range(0, 255) & 0x03
			if roll != 3:
				pick = roll
				break
		if pick < 0 or pick >= rows.size():
			continue
		var row: Dictionary = rows[pick]
		_insert(placings, {
			## `ld a, e / inc a / inc a`: the player is 1, so contestant zero is 2.
			"id": index + 2,
			"species": int(row.get("species", 0)),
			## The score is perturbed upward by `Random and %111`, never down.
			"score": (int(row.get("score", 0)) + (random.randi_range(0, 255) & 0x07)) & 0xFFFF,
		})
	_insert(placings, {
		"id": PLAYER_ID, "species": player_species, "score": player_score,
	})
	var player_place: int = 0
	for index: int in placings.size():
		if int(placings[index].get("id", 0)) == PLAYER_ID:
			player_place = index + 1
			break
	return {"placings": placings, "player_place": player_place}


## `DetermineContestWinners`: three slots, each entry compared against first,
## then second, then third, and the ones below it pushed down. `CompareBytes`
## answers carry only when the newcomer is *lower*, so an equal score takes the
## place.
static func _insert(placings: Array, entry: Dictionary) -> void:
	for index: int in 3:
		if index >= placings.size():
			placings.append(entry)
			return
		if int(entry["score"]) >= int(placings[index].get("score", 0)):
			placings.insert(index, entry)
			if placings.size() > 3:
				placings.resize(3)
			return


## `CheckBugContestTimer`, in the minutes the world clock keeps: the contest
## runs [constant MINUTES] from the minute it started and the counter is what
## `VAR_BUGCONTEST_MINS_REMAINING` reads. The source also counts the seconds
## down inside the minute; nothing here has seconds, and no script reads them.
static func minutes_remaining(started: Dictionary, now: Dictionary) -> int:
	if started.is_empty():
		return 0
	var elapsed: int = _minute_of_week(now) - _minute_of_week(started)
	if elapsed < 0:
		elapsed += Gen2WorldClock.DAYS_PER_WEEK \
			* Gen2WorldClock.HOURS_PER_DAY * Gen2WorldClock.MINUTES_PER_HOUR
	return maxi(0, MINUTES - elapsed)


static func _minute_of_week(clock: Dictionary) -> int:
	return ((int(clock.get("day", 0)) * Gen2WorldClock.HOURS_PER_DAY
		+ int(clock.get("hour", 0))) * Gen2WorldClock.MINUTES_PER_HOUR
		+ int(clock.get("minute", 0)))


## `SelectRandomBugContestContestants`: five of the ten flags set, chosen by a
## rejection roll that refuses a flag it has already set. Answers the set of
## indices, which is what `ComputeAIContestantScores` skips.
static func select_withdrawn(random: RandomNumberGenerator) -> Dictionary:
	var out: Dictionary = {}
	if random == null:
		return out
	while out.size() < CONTESTANTS_WITHDRAWN:
		## `cp $ff / NUM_BUG_CONTESTANTS * NUM_BUG_CONTESTANTS` is 250, and the
		## divisor is 25, so the roll is uniform over the ten.
		var roll: int = random.randi_range(0, 255)
		if roll >= 250:
			continue
		out[roll / 25] = true
	return out
