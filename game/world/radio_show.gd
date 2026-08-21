class_name Gen2RadioShow
extends RefCounted

## `engine/pokegear/radio.asm`: the words a tuned station prints into the radio
## card's text box, one line at a time.
##
## [Gen2WorldRadio] is the dial, its availability rules and the music a station
## commits. This is the layer above it: `RadioJumptable`, dispatched once a
## hardware frame the way `PlayRadioShow` is, with `PrintRadioLine`,
## `NextRadioLine` and `RadioScroll` as the whole of its output.
##
## Scene-free and injected with its own generator, like the rest of the world:
## a caller hands it the facts the source reads off WRAM and spends frames.
##
## Segments are named after the source's own labels rather than numbered,
## because the numbers are profile split: Gold and Silver ship no Buena's
## Password, so every segment past `$04` in their jumptable sits fifteen lower.

## `wCurRadioLine`'s own RADIO_SCROLL entry, which every printing segment leaves
## behind it.
const SCROLL: StringName = &"RadioScroll"
## `PrintRadioLine` and `PlaceRadioString` both wait 100 frames; only
## `OaksPKMNTalk14`'s restart uses a different one.
const LINE_FRAMES: int = 100
const RESTART_FRAMES: int = 10

## `RadioJumptable` in table order, which is the whole state space. The three
## music-only stations answer no segment past their first.
const SEGMENTS: Array[StringName] = [
	&"OaksPKMNTalk1", &"PokedexShow1", &"BenMonMusic1", &"LuckyNumberShow1",
	&"BuenasPassword1", &"PeoplePlaces1", &"FernMonMusic1", &"RocketRadio1",
	&"PokeFluteRadio", &"UnownRadio", &"EvolutionRadio",
	&"OaksPKMNTalk2", &"OaksPKMNTalk3", &"OaksPKMNTalk4", &"OaksPKMNTalk5",
	&"OaksPKMNTalk6", &"OaksPKMNTalk7", &"OaksPKMNTalk8", &"OaksPKMNTalk9",
	&"PokedexShow2", &"PokedexShow3", &"PokedexShow4", &"PokedexShow5",
	&"BenMonMusic2", &"BenMonMusic3", &"BenFernMusic4", &"BenFernMusic5",
	&"BenFernMusic6", &"BenFernMusic7", &"FernMonMusic2",
	&"LuckyNumberShow2", &"LuckyNumberShow3", &"LuckyNumberShow4",
	&"LuckyNumberShow5", &"LuckyNumberShow6", &"LuckyNumberShow7",
	&"LuckyNumberShow8", &"LuckyNumberShow9", &"LuckyNumberShow10",
	&"LuckyNumberShow11", &"LuckyNumberShow12", &"LuckyNumberShow13",
	&"LuckyNumberShow14", &"LuckyNumberShow15",
	&"PeoplePlaces2", &"PeoplePlaces3", &"PeoplePlaces4", &"PeoplePlaces5",
	&"PeoplePlaces6", &"PeoplePlaces7",
	&"RocketRadio2", &"RocketRadio3", &"RocketRadio4", &"RocketRadio5",
	&"RocketRadio6", &"RocketRadio7", &"RocketRadio8", &"RocketRadio9",
	&"RocketRadio10",
	&"OaksPKMNTalk10", &"OaksPKMNTalk11", &"OaksPKMNTalk12", &"OaksPKMNTalk13",
	&"OaksPKMNTalk14",
	&"BuenasPassword2", &"BuenasPassword3", &"BuenasPassword4",
	&"BuenasPassword5", &"BuenasPassword6", &"BuenasPassword7",
	&"BuenasPassword8", &"BuenasPassword9", &"BuenasPassword10",
	&"BuenasPassword11", &"BuenasPassword12", &"BuenasPassword13",
	&"BuenasPassword14", &"BuenasPassword15", &"BuenasPassword16",
	&"BuenasPassword17", &"BuenasPassword18", &"BuenasPassword19",
	&"BuenasPassword20", &"BuenasPassword21",
	SCROLL,
	&"PokedexShow6", &"PokedexShow7", &"PokedexShow8",
]

## The segment each channel's `LoadStation_` jumps to, by canonical channel id.
const CHANNEL_ENTRY: Dictionary = {
	Gen2WorldRadio.OAKS_POKEMON_TALK: &"OaksPKMNTalk1",
	Gen2WorldRadio.POKEDEX_SHOW: &"PokedexShow1",
	Gen2WorldRadio.POKEMON_MUSIC: &"BenMonMusic1",
	Gen2WorldRadio.LUCKY_CHANNEL: &"LuckyNumberShow1",
	Gen2WorldRadio.BUENAS_PASSWORD: &"BuenasPassword1",
	Gen2WorldRadio.PLACES_AND_PEOPLE: &"PeoplePlaces1",
	Gen2WorldRadio.LETS_ALL_SING: &"FernMonMusic1",
	Gen2WorldRadio.ROCKET_RADIO: &"RocketRadio1",
	Gen2WorldRadio.POKE_FLUTE_RADIO: &"PokeFluteRadio",
	Gen2WorldRadio.UNOWN_RADIO: &"UnownRadio",
	Gen2WorldRadio.EVOLUTION_RADIO: &"EvolutionRadio",
}

## `data/text/common_1.asm`, which no importer reads: every radio text is one
## `line` and nothing else, so a segment's output is exactly one box line.
## Braced names are the `text_ram` buffers the segment fills first.
const TEXTS: Dictionary = {
	&"OPT_IntroText1": "MARY: PROF.OAK'S",
	&"OPT_IntroText2": "#MON TALK!",
	&"OPT_IntroText3": "With me, MARY!",
	&"OPT_OakText1": "OAK: {mon}",
	&"OPT_OakText2": "may be seen around",
	&"OPT_OakText3": "{landmark}.",
	&"OPT_MaryText1": "MARY: {mon}'s",
	&"OPT_PokemonChannelText": "#MON",
	&"PokedexShowText": "{mon}",
	&"BenIntroText1": "BEN: #MON MUSIC",
	&"BenIntroText2": "CHANNEL!",
	&"BenIntroText3": "It's me, DJ BEN!",
	&"FernIntroText1": "FERN: #MUSIC!",
	&"FernIntroText2": "With DJ FERN!",
	&"BenFernText1": "Today's {today},",
	&"BenFernText2A": "so let us jam to",
	&"BenFernText2B": "so chill out to",
	&"BenFernText3A": "#MON March!",
	&"BenFernText3B": "#MON Lullaby!",
	&"LC_Text1": "REED: Yeehaw! How",
	&"LC_Text2": "y'all doin' now?",
	&"LC_Text3": "Whether you're up",
	&"LC_Text4": "or way down low,",
	&"LC_Text5": "don't you miss the",
	&"LC_Text6": "LUCKY NUMBER SHOW!",
	&"LC_Text7": "This week's Lucky",
	&"LC_Text8": "Number is {number}!",
	&"LC_Text9": "I'll repeat that!",
	&"LC_Text10": "Match it and go to",
	&"LC_Text11": "the RADIO TOWER!",
	&"LC_DragText1": "…Repeating myself",
	&"LC_DragText2": "gets to be a drag…",
	&"PnP_Text1": "PLACES AND PEOPLE!",
	&"PnP_Text2": "Brought to you by",
	&"PnP_Text3": "me, DJ LILY!",
	&"PnP_Text4": "{class} {trainer}",
	&"PnP_Text5": "{landmark}",
	&"RocketRadioText1": "… …Ahem, we are",
	&"RocketRadioText2": "TEAM ROCKET!",
	&"RocketRadioText3": "After three years",
	&"RocketRadioText4": "of preparation, we",
	&"RocketRadioText5": "have risen again",
	&"RocketRadioText6": "from the ashes!",
	&"RocketRadioText7": "GIOVANNI! Can you",
	&"RocketRadioText8": "hear? We did it!",
	&"RocketRadioText9": "Where is our boss?",
	&"RocketRadioText10": "Is he listening?",
	&"BuenaRadioText1": "BUENA: BUENA here!",
	&"BuenaRadioText2": "Today's password!",
	&"BuenaRadioText3": "Let me think… It's",
	&"BuenaRadioText4": "{password}!",
	&"BuenaRadioText5": "Don't forget it!",
	&"BuenaRadioText6": "I'm in GOLDENROD's",
	&"BuenaRadioText7": "RADIO TOWER!",
	&"BuenaRadioMidnightText1": "BUENA: Oh my…",
	&"BuenaRadioMidnightText2": "It's midnight! I",
	&"BuenaRadioMidnightText3": "have to shut down!",
	&"BuenaRadioMidnightText4": "Thanks for tuning",
	&"BuenaRadioMidnightText5": "in to the end! But",
	&"BuenaRadioMidnightText6": "don't stay up too",
	&"BuenaRadioMidnightText7": "late! Presented to",
	&"BuenaRadioMidnightText8": "you by DJ BUENA!",
	&"BuenaRadioMidnightText9": "I'm outta here!",
	&"BuenaRadioMidnightText10": "…",
	&"BuenaOffTheAirText": "",
}

## `OaksPKMNTalk8`'s `.Adverbs` and `OaksPKMNTalk9`'s `.Adjectives`, sixteen
## each so the mask needs no retry loop. Gold and Silver's eighth adjective is
## `.OPT_NowText` where Crystal's is `.OPT_GroovyText`; nothing else differs.
const OPT_ADVERBS: Array[String] = [
	"sweet and adorably", "wiggly and slickly", "aptly named and",
	"undeniably kind of", "so, so unbearably", "wow, impressively",
	"almost poisonously", "ooh, so sensually", "so mischievously",
	"so very topically", "sure addictively", "looks in water is",
	"evolution must be", "provocatively", "so flipped out and",
	"heart-meltingly",
]
const OPT_ADJECTIVES: Array[String] = [
	"cute.", "weird.", "pleasant.", "bold, sort of.", "frightening.",
	"suave & debonair!", "powerful.", "exciting.", "groovy!", "inspiring.",
	"friendly.", "hot, hot, hot!", "stimulating.", "guarded.", "lovely.",
	"speedy.",
]
const OPT_ADJECTIVE_GROOVY: int = 8
const OPT_ADJECTIVE_NOW_GOLD_SILVER: String = "now!"

## `PeoplePlaces5` and `PeoplePlaces7` share one `.Adjectives` table, listed
## twice in the source and identical both times.
const PNP_ADJECTIVES: Array[String] = [
	"is cute.", "is sort of lazy.", "is always happy.", "is quite noisy.",
	"is precocious.", "is somewhat bold.", "is too picky!", "is sort of OK.",
	"is just so-so.", "is actually great.", "is just my type.",
	"is so cool, no?", "is inspiring!", "is kind of weird.",
	"is right for me?", "is definitely odd!",
]

## `data/radio/oaks_pkmn_talk_routes.asm` by landmark rather than by map id: a
## map number shifts between the profiles and a Johto landmark does not.
const OAKS_TALK_LANDMARKS: Array[int] = [
	2,   # ROUTE_29
	45,  # ROUTE_46
	4,   # ROUTE_30
	8,   # ROUTE_32
	15,  # ROUTE_34
	18,  # ROUTE_35
	21,  # ROUTE_37
	25,  # ROUTE_38
	26,  # ROUTE_39
	34,  # ROUTE_42
	37,  # ROUTE_43
	39,  # ROUTE_44
	43,  # ROUTE_45
	20,  # ROUTE_36
	5,   # ROUTE_31
]

## `data/radio/pnp_places.asm`, likewise as landmarks. `PnP_Places` names four
## maps whose own landmark is their city's, which is why Cerulean appears as
## the police station and Cinnabar as a beta Pokecenter.
const PNP_PLACE_LANDMARKS: Array[int] = [
	47,  # PALLET_TOWN
	87,  # ROUTE_22
	51,  # PEWTER_CITY
	55,  # CERULEAN_CITY
	74,  # ROUTE_12
	73,  # ROUTE_11
	78,  # ROUTE_16
	76,  # ROUTE_14
	85,  # CINNABAR_ISLAND
]

## `data/radio/pnp_hidden_people.asm`, which is one list with two labels inside
## it: `PeoplePlaces4` picks the label to start walking from, so progress makes
## the list *shorter* rather than longer. The Elite Four are described once the
## Hall of Fame is entered, the Kanto leaders once all eight Kanto badges are
## in, and the last five never.
const PNP_HIDDEN_ELITE_FOUR: Array[int] = [11, 13, 14, 15, 16]
const PNP_HIDDEN_KANTO_LEADERS: Array[int] = [17, 18, 19, 21, 26, 35, 46, 64]
const PNP_HIDDEN_ALWAYS: Array[int] = [9, 10, 12, 42, 63]

## `maskbits NUM_TRAINER_CLASSES / inc a`: seven bits of a byte, so the roll is
## 1 to 128 and everything past the class count is retried.
const TRAINER_CLASS_ROLL: int = 128
## `NUM_TRAINER_CLASSES`. Crystal's own `cp` excludes MYSTICALMAN, which Gold
## and Silver's `+ 1` lets through.
const NUM_TRAINER_CLASSES: int = 67

## `data/radio/buenas_passwords.asm`. `kind` is the BUENA_* string function and
## `values` its three operands: species, item or move numbers, or literals.
const BUENA_MON: StringName = &"mon"
const BUENA_ITEM: StringName = &"item"
const BUENA_MOVE: StringName = &"move"
const BUENA_STRING: StringName = &"string"
const BUENA_PASSWORDS: Array[Dictionary] = [
	{"kind": BUENA_MON, "values": [155, 158, 152]},
	{"kind": BUENA_ITEM, "values": [20, 21, 22]},
	{"kind": BUENA_ITEM, "values": [17, 12, 14]},
	{"kind": BUENA_ITEM, "values": [5, 4, 3]},
	{"kind": BUENA_MON, "values": [25, 19, 74]},
	{"kind": BUENA_MON, "values": [163, 167, 96]},
	{"kind": BUENA_STRING, "values": ["NEW BARK TOWN", "CHERRYGROVE CITY", "AZALEA TOWN"]},
	{"kind": BUENA_STRING, "values": ["FLYING", "BUG", "GRASS"]},
	{"kind": BUENA_MOVE, "values": [33, 45, 189]},
	{"kind": BUENA_ITEM, "values": [64, 65, 66]},
	{"kind": BUENA_STRING, "values": ["#MON Talk", "#MON Music", "Lucky Channel"]},
]
## `NITE_HOUR`. `BuenasPasswordCheckTime` is a bare `cp NITE_HOUR` on the hour,
## so Buena is on the air from six in the evening until midnight and off it for
## the other eighteen hours.
const NITE_HOUR: int = 18
const BUENAS_PASSWORD_CHANNEL_NAME: String = "BUENA'S PASSWORD"

## `OaksPKMNTalk11` to `OaksPKMNTalk13` place strings at screen columns rather
## than as box lines, so each is padded to the column its `hlcoord` names. The
## box's own text starts at column 1.
const RESTART_TOP_COLUMN: int = 9
const BOX_TEXT_COLUMN: int = 1

## `MUSIC_POKEMON_TALK`, `MUSIC_POKEMON_MARCH` and `MUSIC_POKEMON_LULLABY`
## (`constants/music_constants.asm`), the three tracks a segment restarts.
const MUSIC_POKEMON_TALK: int = 29
const MUSIC_POKEMON_MARCH: int = 0x51
const MUSIC_POKEMON_LULLABY: int = 0x50

var _data: GameData = null
var _random: RandomNumberGenerator = null
var _context: Dictionary = {}
var _crystal: bool = true

## `wCurRadioLine`, `wNextRadioLine`, `wNumRadioLinesPrinted` and
## `wRadioTextDelay`.
var _line: StringName = &""
var _next_line: StringName = &""
var _lines_printed: int = 0
var _delay: int = 0

## The two rows `PrintRadioLine` writes: the first line printed lands on the
## top one and every line after it on the bottom, which `RadioScroll` then
## copies up.
var _top: String = ""
var _bottom: String = ""

## `wOaksPKMNTalkSegmentCounter`: five topics before the station restarts.
var _oaks_counter: int = 0
var _mon_name: String = ""
var _landmark_name: String = ""
var _class_name: String = ""
var _trainer_name: String = ""
var _password: String = ""
## The remaining lines of the dex entry `PokedexShow1` chose, which
## `CopyDexEntry` walks one per segment.
var _dex_lines: PackedStringArray = PackedStringArray()

## `wBuenasPassword` and `DAILYFLAGS2_BUENAS_PASSWORD_F`, kept by the caller so
## the password survives a retune within the day.
var buenas_password: int = -1
var buenas_password_today: bool = false

## The jumptable entry that last executed, which is not always [method segment]:
## four of Buena's segments `jp` straight at another entry rather than printing
## and handing over.
var ran_segment: StringName = &""

## What `RadioMusicRestartDE` was last handed, drained by the host. -1 while no
## segment has asked for a track.
var pending_music: int = -1


## Starts [param channel]'s own `LoadStation_` segment.
##
## [param context] carries what the show reads off WRAM beyond the dial's own
## facts: `crystal`, `weekday`, `hour`, `caught` (the species numbers
## `CheckCaughtMon` answers for), `hall_of_fame`, `kanto_badges` and
## `lucky_number`.
static func start(
	data: GameData, channel: int, context: Dictionary = {},
	random: RandomNumberGenerator = null
) -> Gen2RadioShow:
	var show := Gen2RadioShow.new()
	show._data = data
	show._context = context
	show._crystal = bool(context.get("crystal", true))
	show._random = random if random != null else RandomNumberGenerator.new()
	if random == null:
		show._random.randomize()
	show._line = StringName(CHANNEL_ENTRY.get(channel, &""))
	return show


## `UpdateTime`, which `BuenasPasswordCheckTime` calls before every reading: the
## hour is live, so midnight arriving mid-show is what puts Buena off the air.
func set_hour(hour: int) -> void:
	_context["hour"] = hour


## The two box rows, oldest first.
func lines() -> PackedStringArray:
	return PackedStringArray([_top, _bottom])


## `wCurRadioLine`, which is `SCROLL` while a line is being read.
func segment() -> StringName:
	return _line


## True once the channel has no segment left to run, which only
## `BenFernMusic7`'s bare `ret` and the three music-only stations reach.
func finished() -> bool:
	return _line.is_empty()


## One `PlayRadioShow` dispatch. Answers whether the box changed.
func advance_frame() -> bool:
	if _line.is_empty():
		return false
	if _line == SCROLL:
		return _scroll()
	var before_top: String = _top
	var before_bottom: String = _bottom
	_run(_line)
	return _top != before_top or _bottom != before_bottom


## `RadioScroll`: spend the delay, then take `wNextRadioLine` and roll the box.
## A station that has printed exactly one line has nothing to copy up yet.
func _scroll() -> bool:
	if _delay > 0:
		_delay -= 1
		return false
	_line = _next_line
	if _lines_printed == 1:
		return false
	_top = _bottom
	_bottom = ""
	return true


## `PrintRadioLine`: the first line lands on the top row, every later one on the
## bottom, and the segment hands over to `RadioScroll` for 100 frames.
func _print(text: String, next: StringName) -> void:
	_next_line = next
	if _lines_printed < 2:
		_lines_printed += 1
	if _lines_printed == 1:
		_top = text
	else:
		_bottom = text
	_line = SCROLL
	_delay = LINE_FRAMES


## `NextRadioLine`, which is `CopyRadioTextToRAM` and then the above.
func _say(text_id: StringName, next: StringName, fills: Dictionary = {}) -> void:
	_print(_fill(String(TEXTS.get(text_id, "")), fills), next)


## The `text_ram` buffers a line names, filled from what the segment resolved.
func _fill(text: String, fills: Dictionary) -> String:
	var out: String = text
	out = out.replace("{mon}", _mon_name)
	out = out.replace("{landmark}", _landmark_name)
	out = out.replace("{class}", _class_name)
	out = out.replace("{trainer}", _trainer_name)
	out = out.replace("{password}", _password)
	out = out.replace("{today}", Gen2TextStream.weekday_name(
		int(_context.get("weekday", 0))
	) + "DAY")
	out = out.replace("{number}", "%05d" % int(_context.get("lucky_number", 0)))
	for key: String in fills:
		out = out.replace("{%s}" % key, String(fills[key]))
	return out


## `StartRadioStation`, which is skipped once a station is already talking: it
## clears the box and commits the channel's own track.
func _start_station(channel: int) -> void:
	if _lines_printed != 0:
		return
	_top = ""
	_bottom = ""
	if channel >= 0 and channel < Gen2WorldRadio.CHANNEL_SONGS.size():
		pending_music = Gen2WorldRadio.CHANNEL_SONGS[channel]


func _roll(bound: int) -> int:
	return _random.randi_range(0, maxi(1, bound) - 1)


## `Random` compared against a percentage, which the source writes as a byte:
## `cp 49 percent - 1` is `cp 124`.
func _roll_percent(threshold: int) -> bool:
	return _random.randi_range(0, 255) < threshold


func _run(segment_id: StringName) -> void:
	ran_segment = segment_id
	match segment_id:
		&"OaksPKMNTalk1":
			_oaks_counter = 5
			_start_station(Gen2WorldRadio.OAKS_POKEMON_TALK)
			_say(&"OPT_IntroText1", &"OaksPKMNTalk2")
		&"OaksPKMNTalk2":
			_say(&"OPT_IntroText2", &"OaksPKMNTalk3")
		&"OaksPKMNTalk3":
			_say(&"OPT_IntroText3", &"OaksPKMNTalk4")
		&"OaksPKMNTalk4":
			_oaks_pick_wild()
			_say(&"OPT_OakText1", &"OaksPKMNTalk5")
		&"OaksPKMNTalk5":
			_say(&"OPT_OakText2", &"OaksPKMNTalk6")
		&"OaksPKMNTalk6":
			_say(&"OPT_OakText3", &"OaksPKMNTalk7")
		&"OaksPKMNTalk7":
			_say(&"OPT_MaryText1", &"OaksPKMNTalk8")
		&"OaksPKMNTalk8":
			_print(OPT_ADVERBS[_roll(OPT_ADVERBS.size())], &"OaksPKMNTalk9")
		&"OaksPKMNTalk9":
			var adjective: String = _oaks_adjective(_roll(OPT_ADJECTIVES.size()))
			_oaks_counter -= 1
			var next: StringName = &"OaksPKMNTalk4"
			if _oaks_counter == 0:
				_oaks_counter = 5
				next = &"OaksPKMNTalk10"
			_print(adjective, next)
		&"OaksPKMNTalk10":
			# `RadioMusicRestartPokemonChannel` and two `PrintText`s rather than
			# radio lines: the box is cleared and "#MON" placed straight into it.
			pending_music = MUSIC_POKEMON_TALK
			_top = ""
			_bottom = String(TEXTS[&"OPT_PokemonChannelText"])
			_line = &"OaksPKMNTalk11"
			_delay = LINE_FRAMES
		&"OaksPKMNTalk11":
			_place(_pad(RESTART_TOP_COLUMN, "#MON"), true, &"OaksPKMNTalk12")
		&"OaksPKMNTalk12":
			_place("#MON Channel", false, &"OaksPKMNTalk13")
		&"OaksPKMNTalk13":
			_place(_bottom, false, &"OaksPKMNTalk14")
		&"OaksPKMNTalk14":
			if _delay > 0:
				_delay -= 1
				return
			pending_music = MUSIC_POKEMON_TALK
			_top = ""
			_bottom = ""
			_next_line = &"OaksPKMNTalk4"
			_lines_printed = 0
			_line = SCROLL
			_delay = RESTART_FRAMES

		&"PokedexShow1":
			_start_station(Gen2WorldRadio.POKEDEX_SHOW)
			if not _pokedex_pick_mon():
				# `.loop` retries until it finds a caught species, so an empty
				# dex would spin forever on the cartridge; here the station
				# simply has nothing to read.
				_line = &""
				return
			_say(&"PokedexShowText", &"PokedexShow2")
		&"PokedexShow2":
			_print(_dex_line(), &"PokedexShow3")
		&"PokedexShow3":
			_print(_dex_line(), &"PokedexShow4")
		&"PokedexShow4":
			_print(_dex_line(), &"PokedexShow5")
		&"PokedexShow5":
			_print(_dex_line(), &"PokedexShow6")
		&"PokedexShow6":
			_print(_dex_line(), &"PokedexShow7")
		&"PokedexShow7":
			_print(_dex_line(), &"PokedexShow8")
		&"PokedexShow8":
			_print(_dex_line(), &"PokedexShow1")

		&"BenMonMusic1":
			_start_pokemon_music()
			_say(&"BenIntroText1", &"BenMonMusic2")
		&"BenMonMusic2":
			_say(&"BenIntroText2", &"BenMonMusic3")
		&"BenMonMusic3":
			_say(&"BenIntroText3", &"BenFernMusic4")
		&"FernMonMusic1":
			_start_pokemon_music()
			_say(&"FernIntroText1", &"FernMonMusic2")
		&"FernMonMusic2":
			_say(&"FernIntroText2", &"BenFernMusic4")
		&"BenFernMusic4":
			_say(&"BenFernText1", &"BenFernMusic5")
		&"BenFernMusic5":
			_say(
				&"BenFernText2A" if _march_day() else &"BenFernText2B",
				&"BenFernMusic6"
			)
		&"BenFernMusic6":
			_say(
				&"BenFernText3A" if _march_day() else &"BenFernText3B",
				&"BenFernMusic7"
			)
		&"BenFernMusic7":
			# A bare `ret`: the music channel says its three lines once and then
			# leaves the box alone until the dial moves.
			_line = &""

		&"LuckyNumberShow1":
			_start_station(Gen2WorldRadio.LUCKY_CHANNEL)
			_say(&"LC_Text1", &"LuckyNumberShow2")
		&"LuckyNumberShow2":
			_say(&"LC_Text2", &"LuckyNumberShow3")
		&"LuckyNumberShow3":
			_say(&"LC_Text3", &"LuckyNumberShow4")
		&"LuckyNumberShow4":
			_say(&"LC_Text4", &"LuckyNumberShow5")
		&"LuckyNumberShow5":
			_say(&"LC_Text5", &"LuckyNumberShow6")
		&"LuckyNumberShow6":
			_say(&"LC_Text6", &"LuckyNumberShow7")
		&"LuckyNumberShow7":
			_say(&"LC_Text7", &"LuckyNumberShow8")
		&"LuckyNumberShow8":
			_say(&"LC_Text8", &"LuckyNumberShow9")
		&"LuckyNumberShow9":
			_say(&"LC_Text9", &"LuckyNumberShow10")
		&"LuckyNumberShow10":
			_say(&"LC_Text7", &"LuckyNumberShow11")
		&"LuckyNumberShow11":
			_say(&"LC_Text8", &"LuckyNumberShow12")
		&"LuckyNumberShow12":
			_say(&"LC_Text10", &"LuckyNumberShow13")
		&"LuckyNumberShow13":
			# `call Random / and a`: 255 of 256 rolls restart the show, and the
			# one zero gets REED's two extra lines.
			_say(
				&"LC_Text11",
				&"LuckyNumberShow14" if _roll(256) == 0 else &"LuckyNumberShow1"
			)
		&"LuckyNumberShow14":
			_say(&"LC_DragText1", &"LuckyNumberShow15")
		&"LuckyNumberShow15":
			_say(&"LC_DragText2", &"LuckyNumberShow1")

		&"PeoplePlaces1":
			_start_station(Gen2WorldRadio.PLACES_AND_PEOPLE)
			_say(&"PnP_Text1", &"PeoplePlaces2")
		&"PeoplePlaces2":
			_say(&"PnP_Text2", &"PeoplePlaces3")
		&"PeoplePlaces3":
			_say(&"PnP_Text3", _pnp_topic())
		&"PeoplePlaces4":
			_pnp_pick_person()
			_say(&"PnP_Text4", &"PeoplePlaces5")
		&"PeoplePlaces5":
			_print(PNP_ADJECTIVES[_roll(PNP_ADJECTIVES.size())], _pnp_next())
		&"PeoplePlaces6":
			_pnp_pick_place()
			_say(&"PnP_Text5", &"PeoplePlaces7")
		&"PeoplePlaces7":
			_print(PNP_ADJECTIVES[_roll(PNP_ADJECTIVES.size())], _pnp_next())

		&"RocketRadio1":
			_start_station(Gen2WorldRadio.ROCKET_RADIO)
			_say(&"RocketRadioText1", &"RocketRadio2")
		&"RocketRadio2":
			_say(&"RocketRadioText2", &"RocketRadio3")
		&"RocketRadio3":
			_say(&"RocketRadioText3", &"RocketRadio4")
		&"RocketRadio4":
			_say(&"RocketRadioText4", &"RocketRadio5")
		&"RocketRadio5":
			_say(&"RocketRadioText5", &"RocketRadio6")
		&"RocketRadio6":
			_say(&"RocketRadioText6", &"RocketRadio7")
		&"RocketRadio7":
			_say(&"RocketRadioText7", &"RocketRadio8")
		&"RocketRadio8":
			_say(&"RocketRadioText8", &"RocketRadio9")
		&"RocketRadio9":
			_say(&"RocketRadioText9", &"RocketRadio10")
		&"RocketRadio10":
			_say(&"RocketRadioText10", &"RocketRadio1")

		&"PokeFluteRadio", &"UnownRadio", &"EvolutionRadio":
			# All three are `StartRadioStation` and a line count of 1, which is
			# what stops `RadioScroll` clearing a box they never write to.
			_start_station(_music_only_channel(segment_id))
			_lines_printed = 1
			_line = &""

		&"BuenasPassword1":
			if _off_air():
				_run(&"BuenasPassword20" if _lines_printed == 0 else &"BuenasPassword8")
				return
			_start_station(Gen2WorldRadio.BUENAS_PASSWORD)
			_say(&"BuenaRadioText1", &"BuenasPassword2")
		&"BuenasPassword2":
			_say(&"BuenaRadioText2", &"BuenasPassword3")
		&"BuenasPassword3":
			_say(
				&"BuenaRadioText3",
				&"BuenasPassword8" if _off_air() else &"BuenasPassword4"
			)
			if _off_air():
				buenas_password_today = false
		&"BuenasPassword4":
			if _off_air():
				_run(&"BuenasPassword8")
				return
			_roll_password()
			_say(&"BuenaRadioText4", &"BuenasPassword5")
		&"BuenasPassword5":
			_say(&"BuenaRadioText5", &"BuenasPassword6")
		&"BuenasPassword6":
			_say(&"BuenaRadioText6", &"BuenasPassword7")
		&"BuenasPassword7":
			var midnight: bool = _off_air()
			if midnight:
				buenas_password_today = false
			_say(
				&"BuenaRadioText7",
				&"BuenasPassword8" if midnight else &"BuenasPassword1"
			)
		&"BuenasPassword8":
			buenas_password_today = false
			_say(&"BuenaRadioMidnightText10", &"BuenasPassword9")
		&"BuenasPassword9":
			_say(&"BuenaRadioMidnightText1", &"BuenasPassword10")
		&"BuenasPassword10":
			_say(&"BuenaRadioMidnightText2", &"BuenasPassword11")
		&"BuenasPassword11":
			_say(&"BuenaRadioMidnightText3", &"BuenasPassword12")
		&"BuenasPassword12":
			_say(&"BuenaRadioMidnightText4", &"BuenasPassword13")
		&"BuenasPassword13":
			_say(&"BuenaRadioMidnightText5", &"BuenasPassword14")
		&"BuenasPassword14":
			_say(&"BuenaRadioMidnightText6", &"BuenasPassword15")
		&"BuenasPassword15":
			_say(&"BuenaRadioMidnightText7", &"BuenasPassword16")
		&"BuenasPassword16":
			_say(&"BuenaRadioMidnightText8", &"BuenasPassword17")
		&"BuenasPassword17":
			_say(&"BuenaRadioMidnightText9", &"BuenasPassword18")
		&"BuenasPassword18":
			_say(&"BuenaRadioMidnightText10", &"BuenasPassword19")
		&"BuenasPassword19":
			_say(&"BuenaRadioMidnightText10", &"BuenasPassword20")
		&"BuenasPassword20":
			# `NoRadioMusic` and `NoRadioName`: the station goes quiet and its
			# name comes off the dial before the off-air line.
			pending_music = Gen2WorldState.MUSIC_NONE
			buenas_password_today = false
			_lines_printed = 0
			_say(&"BuenaOffTheAirText", &"BuenasPassword21")
		&"BuenasPassword21":
			_lines_printed = 0
			if not _off_air():
				_run(&"BuenasPassword1")
				return
			_say(&"BuenaOffTheAirText", &"BuenasPassword21")


## `PlaceRadioString`: a string written straight into the box at a column, with
## its own 100-frame wait counted by the segment that follows.
func _place(text: String, top: bool, next: StringName) -> void:
	if _delay > 0:
		_delay -= 1
		return
	if top:
		_top = text
	else:
		_bottom = text
	_line = next
	_delay = LINE_FRAMES


static func _pad(column: int, text: String) -> String:
	return " ".repeat(maxi(0, column - BOX_TEXT_COLUMN)) + text


## Crystal's ninth adjective is "groovy!" and Gold and Silver's is "now!".
func _oaks_adjective(index: int) -> String:
	if index == OPT_ADJECTIVE_GROOVY and not _crystal:
		return OPT_ADJECTIVE_NOW_GOLD_SILVER
	return OPT_ADJECTIVES[index]


func _music_only_channel(segment_id: StringName) -> int:
	match segment_id:
		&"UnownRadio":
			return Gen2WorldRadio.UNOWN_RADIO
		&"EvolutionRadio":
			return Gen2WorldRadio.EVOLUTION_RADIO
	return Gen2WorldRadio.POKE_FLUTE_RADIO


## `StartPokemonMusicChannel`: the box is cleared and the weekday picks between
## the march and the lullaby. It is not `StartRadioStation`, so it runs whether
## or not the station is already talking.
func _start_pokemon_music() -> void:
	_top = ""
	_bottom = ""
	pending_music = MUSIC_POKEMON_MARCH if _march_day() else MUSIC_POKEMON_LULLABY


## `GetWeekday / and 1`: Sunday, Tuesday, Thursday and Saturday get the march.
func _march_day() -> bool:
	return int(_context.get("weekday", 0)) % 2 == 0


## `BuenasPasswordCheckTime`'s carry: the hour is before six in the evening.
func _off_air() -> bool:
	return int(_context.get("hour", 12)) < NITE_HOUR


## `OaksPKMNTalk4`: a random route, then a random time-of-day column, then one
## of that column's middle three slots.
func _oaks_pick_wild() -> void:
	var landmark: int = Gen2WorldRadio.profile_landmark(
		OAKS_TALK_LANDMARKS[_roll(OAKS_TALK_LANDMARKS.size())], _crystal
	)
	_landmark_name = _data.landmark_name(landmark) if _data != null else ""
	var row: Dictionary = _grass_row(landmark)
	if row.is_empty():
		# `.overflow`, which the cartridge reaches when the chosen map is not in
		# `JohtoGrassWildMons` and which restarts the station.
		_mon_name = ""
		return
	var slots: Array = row.get("slots", []) as Array
	var column: Array = slots[_roll(slots.size())] as Array
	var slot: int = 2 + _roll(3)
	var species: int = int((column[mini(slot, column.size() - 1)] as Dictionary).get("species", 0))
	_mon_name = _species_name(species)


## The Johto grass table row for a landmark, which is the one map carrying both
## that landmark and grass encounters.
func _grass_row(landmark: int) -> Dictionary:
	if _data == null:
		return {}
	for row: Dictionary in _data.world_encounter_region_rows(&"grass", "johto"):
		var pair: PackedStringArray = String(row.get("map", "")).split(":")
		if pair.size() < 2:
			continue
		var map: Gen2WorldMap = _data.world_map(int(pair[0]), int(pair[1]))
		if map != null and map.location == landmark:
			return row
	return {}


## `PokedexShow1`: a caught species, and its entry split into the lines
## `CopyDexEntry` walks one per segment.
func _pokedex_pick_mon() -> bool:
	var caught: Array = _context.get("caught", []) as Array
	if caught.is_empty() or _data == null:
		return false
	var species: int = int(caught[_roll(caught.size())])
	_mon_name = _species_name(species)
	_dex_lines = PackedStringArray()
	for page: String in _data.dex_entry(species).get("pages", []) as Array:
		for line: String in page.split("\n"):
			_dex_lines.append(line)
	return true


## `CopyDexEntry`. An entry runs out before `PokedexShow8` does, and the
## cartridge reads on past its terminator into whatever follows; here the
## remaining segments print nothing.
func _dex_line() -> String:
	if _dex_lines.is_empty():
		return ""
	var line: String = _dex_lines[0]
	_dex_lines.remove_at(0)
	return line


## `PeoplePlaces3`: just under half the rolls take the People branch.
func _pnp_topic() -> StringName:
	return &"PeoplePlaces4" if _roll_percent(124) else &"PeoplePlaces6"


## `PeoplePlaces5` and `PeoplePlaces7`'s shared tail: a 4 percent chance of
## restarting the show, and otherwise another person or place.
func _pnp_next() -> StringName:
	if _roll_percent(10):
		return &"PeoplePlaces1"
	return &"PeoplePlaces4" if _roll_percent(124) else &"PeoplePlaces6"


## `PeoplePlaces4`: a trainer class the hidden-people list allows, and the first
## trainer of it.
func _pnp_pick_person() -> void:
	if _data == null:
		return
	var hidden: Array[int] = hidden_people(
		bool(_context.get("hall_of_fame", false)),
		int(_context.get("kanto_badges", 0))
	)
	var bound: int = NUM_TRAINER_CLASSES if _crystal else NUM_TRAINER_CLASSES + 1
	while true:
		var class_number: int = _roll(TRAINER_CLASS_ROLL) + 1
		if class_number >= bound or class_number in hidden:
			continue
		var entry: Dictionary = _data.trainer(class_number)
		if entry.is_empty():
			continue
		_class_name = String(entry.get("name", ""))
		var trainers: Array = entry.get("trainers", []) as Array
		_trainer_name = String((trainers[0] as Dictionary).get("name", "")) \
			if not trainers.is_empty() else ""
		return


## The classes `PeoplePlaces4`'s own walk refuses, given the two progress facts
## that shorten the list.
static func hidden_people(hall_of_fame: bool, kanto_badges: int) -> Array[int]:
	var hidden: Array[int] = PNP_HIDDEN_ALWAYS.duplicate()
	if not hall_of_fame:
		hidden.append_array(PNP_HIDDEN_ELITE_FOUR)
	if not hall_of_fame or kanto_badges != 0xFF:
		hidden.append_array(PNP_HIDDEN_KANTO_LEADERS)
	return hidden


## `PeoplePlaces6`: one of nine Kanto landmarks, named through `GetLandmarkName`.
func _pnp_pick_place() -> void:
	var landmark: int = Gen2WorldRadio.profile_landmark(
		PNP_PLACE_LANDMARKS[_roll(PNP_PLACE_LANDMARKS.size())], _crystal
	)
	_landmark_name = _data.landmark_name(landmark) if _data != null else ""


## `BuenasPassword4` and `GetBuenasPassword`: one category and one of its three
## words, rolled once a day and kept in the high and low nybbles of one byte.
func _roll_password() -> void:
	if not buenas_password_today or buenas_password < 0:
		var category: int = _roll(BUENA_PASSWORDS.size() + 5)
		while category >= BUENA_PASSWORDS.size():
			category = _roll(BUENA_PASSWORDS.size() + 5)
		var word: int = _roll(4)
		while word >= 3:
			word = _roll(4)
		buenas_password = (category << 4) | word
		buenas_password_today = true
	_password = password_words(_data, buenas_password)


## The word a `wBuenasPassword` byte names, which Buena's own script reads as
## well as the radio.
static func password_words(data: GameData, password: int) -> String:
	if password < 0:
		return ""
	var entry: Dictionary = BUENA_PASSWORDS[mini(password >> 4, BUENA_PASSWORDS.size() - 1)]
	var values: Array = entry["values"] as Array
	var value: Variant = values[mini(password & 0xF, values.size() - 1)]
	if data == null:
		return String(value) if entry["kind"] == BUENA_STRING else ""
	match StringName(entry["kind"]):
		BUENA_MON:
			return String(data.species(int(value)).get("name", ""))
		BUENA_ITEM:
			return data.item_name(int(value))
		BUENA_MOVE:
			return String(data.move(int(value)).get("name", ""))
	return String(value)


func _species_name(species: int) -> String:
	return String(_data.species(species).get("name", "")) if _data != null else ""
