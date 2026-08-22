class_name Gen2WorldScriptRunner
extends RefCounted

## Bounded, scene-free execution of the supported overworld script commands.
##
## A runner owns one event invocation. It never opens a ROM and it never
## changes the world state until the invocation reaches END or ENDCALLBACK.
## Text and explicit warps are returned as structured pauses for the screen or
## another caller to acknowledge.

var data: GameData = null
var state: Gen2WorldState = null
var warp_validator: Callable = Callable()

var _request: Dictionary = {}
var _frames: Array = []
var _staged_flags: Dictionary = {}
var _staged_engine_flags: Dictionary = {}
var _staged_scenes: Dictionary = {}
var _staged_day_of_week: int = -1
var _staged_dst_enabled: bool = false
var _has_staged_dst: bool = false
var _staged_items: Dictionary = {}
var _staged_money: Dictionary = {}
var _staged_coins: int = -1
var _staged_phone_contacts: Dictionary = {}
var _staged_script_memory: Dictionary = {}
var _staged_just_battled: bool = false
var _has_staged_just_battled: bool = false
var _staged_swarm: Dictionary = {}
var _has_staged_swarm: bool = false
var _has_staged_special_phone_call: bool = false
var _staged_special_phone_call: int = 0
var _has_staged_kurt_apricorn_quantity: bool = false
var _staged_kurt_apricorn_quantity: int = 0
var _staged_fruit_trees: Dictionary = {}
var _reset_phone_receive_timer: bool = false
var _events: Array = []
var _pending: Dictionary = {}
var _last_text: Dictionary = {}

## The text the still-open box is showing. `Script_yesorno`'s `YesNoBox` and
## `Script_verticalmenu`'s `_2DMenu` draw over that box rather than replacing it,
## so the question a choice answers is the last text the script wrote; without it
## a host has nothing but the command's own name to print.
var _standing_text: String = ""
var _last_talked_object_index: int = -1
var _last_item: int = 0
var _staged_warp: Dictionary = {}
var _script_value: int = 0
var _command_count: int = 0
## `Script_sdefer`'s own `RUN_DEFERRED_SCRIPT`, which is the only thing that
## makes `RunSceneScript` answer `PlayerEvents` with carry: a scene script that
## does not set it has run and raised no player event
## (engine/overworld/events.asm).
var _ran_deferred: bool = false
var _active: bool = false
var _completed: bool = false
var _failure: Dictionary = {}
var _finish_after_pending: bool = false
var _loaded_menu: Dictionary = {}
var _loaded_emote: int = -1
## wScriptDelay. `Script_pause` reuses whatever is in it when its own operand is
## zero, which is how `Script_showemote` sets the emote's duration: it writes the
## delay and then calls `ShowEmoteScript`, whose middle command is `pause 0`.
var _script_delay: int = 0
var _trainer_intro_approach_pending: bool = false
## Set while RockSmashScript's `playsound SFX_STRENGTH` is out with the host, so
## its acknowledge continues into the earthquake, the disappear and the roll.
## The same shape _trainer_intro_approach_pending has for encounter music.
var _rock_smash_after_sound: bool = false
## Set while a receipt's own `specialsound` is out with the host, so its
## completion continues into `itemnotify`'s box. `{ item, finish }`, the same
## shape _rock_smash_after_sound has.
var _item_notify_after_sound: Dictionary = {}
var _battle_setup: Dictionary = {}
var _loaded_battle_type: int = -1
var _phone_context: Dictionary = {}
var _phone_started: bool = false
var _text_buffers: Dictionary = {}
var _rival_name: String = "???"
## wPlayerName, mirrored from the selected save the way Gen2WorldAPI mirrors
## wPlayerID. `<PLAYER>` is a `CheckDict` entry, so a text carrying one cannot
## be printed without it; empty leaves the marker visible rather than inventing
## a trainer.
var player_name: String = ""
## Everything this invocation rolls: the source RANDOM command and the phone
## routines that pick a caller line or an unseen species. Injected like the rest
## of the project's randomness, so a caller can reproduce a branch; a runner
## started without one randomizes its own rather than reaching for the engine's
## global generator, which no seed can reach.
var _random := RandomNumberGenerator.new()
## wCurPartySpecies, which is not wScriptVar: `PartyMenuSelect` writes it from
## the row the player chose and `pokepic`, `givepoke` and `giveegg` from their
## own operands. `PlayCurMonCry` is the one special that reads it, and all four
## of its scripts reach it with a grooming routine's own wScriptVar standing.
var _cur_party_species: int = 0
## Which balance window `engine/menus/menu_2.asm` left standing, empty for none.
var _money_window: StringName = &""

const PHONE_CONTACT_GOT: int = 0
const PHONE_CONTACTS_FULL: int = 1
const PHONE_CONTACT_REFUSED: int = 2
## The Bug Catching Contest's own six, all below the index where Gold and
## Silver's table diverges except the contestant draw, which special_index()
## normalizes (engine/events/special_pointers.asm).
const SPECIAL_BUG_CONTEST_JUDGING: int = 20
const SPECIAL_CHECK_PARTY_FULL_AFTER_CONTEST: int = 21
const SPECIAL_CONTEST_DROP_OFF_MONS: int = 22
const SPECIAL_CONTEST_RETURN_MONS: int = 23
const SPECIAL_GIVE_PARK_BALLS: int = 24
const SPECIAL_SELECT_RANDOM_BUG_CONTESTANTS: int = 71
const SPECIAL_ACTIVATE_FISHING_SWARM: int = 72
const SPECIAL_TOGGLE_MAPTILE_DECORATIONS: int = 73
const SPECIAL_TOGGLE_DECORATIONS_VISIBILITY: int = 74
const SPECIAL_POKEMON_CENTER_PC: int = 28
const SPECIAL_PLAYERS_HOUSE_PC: int = 29
## OverworldTownMap, engine/events/special_pointers.asm index 38. The source
## describedecoration path reaches this special only for a town-map poster.
const SPECIAL_OVERWORLD_TOWN_MAP: int = 38
const SPECIAL_SET_DAY_OF_WEEK: int = 37
const SPECIAL_PLAY_MAP_MUSIC: int = 60
const SPECIAL_RESTART_MAP_MUSIC: int = 61
const SPECIAL_HEAL_MACHINE_ANIM: int = 62
## `HealMachineAnim.Pointers`' three sequences. Only the Hall of Fame's differs:
## it loads its balls from a second OAM table and plays two effects where the
## other two play `MUSIC_HEAL`. The routine's own frame costs belong to the
## animation, so they are read from the class that draws it.
const HEAL_MACHINE_HALL_OF_FAME: int = Gen2WorldEffects.HEAL_MACHINE_HALL_OF_FAME
const HEAL_MACHINE_BALL_FRAMES: int = Gen2WorldEffects.HEAL_MACHINE_BALL_FRAMES
const HEAL_MACHINE_FLASH_FRAMES: int = Gen2WorldEffects.HEAL_MACHINE_FLASHES \
	* Gen2WorldEffects.HEAL_MACHINE_FLASH_INTERVAL
## constants/sfx_constants.asm. The first is played once a ball by
## `.LoadBallsOntoMachine`; the other two are `.HOF_PlaySFX`'s pair.
const SFX_SECOND_PART_OF_ITEMFINDER: int = 0x12
## `ItemFinder.ItemfinderSound`'s other half, and `PlayTransactionSound`'s.
const SFX_TRANSACTION: int = 0x22
## `.ItemfinderSound`'s own `ld c, 4`.
const ITEMFINDER_SFX_PASSES: int = 4
const SFX_GAME_FREAK_LOGO_GS: int = 0xAA
const SFX_BOOT_PC: int = 0x0D
## constants/music_constants.asm's MUSIC_HEAL, which `.PlayHealMusic` starts
## under the flashes rather than after them.
const MUSIC_HEAL: int = 0x0D
const SPECIAL_CHECK_POKERUS: int = 78
## MagnetTrain, the ride's cutscene. wScriptVar picks the direction, which a
## preceding SETVAL loads: TRUE for Saffron to Goldenrod, FALSE for the return
## (maps/SaffronMagnetTrainStation.asm, maps/GoldenrodMagnetTrainStation.asm).
const SPECIAL_MAGNET_TRAIN: int = 35
## ProfOaksPCBoot, 101 in Crystal and 100 in Gold/Silver, which special_index()
## already normalizes. Oak's Kanto script reaches it on every branch
## (maps/OaksLab.asm's `.CheckPokedex`).
const SPECIAL_PROF_OAKS_PC_BOOT: int = 101
## SnorlaxAwake, 96 in Crystal and 95 in Gold/Silver, which special_index()
## already normalizes. Its five proximity coordinates are the cells the source
## lists, in its own x,y order (engine/events/specials.asm's .ProximityCoords),
## and are the same in both pins.
const SPECIAL_SNORLAX_AWAKE: int = 96
const SNORLAX_PROXIMITY_CELLS: Array[Vector2i] = [
	Vector2i(33, 8), Vector2i(34, 10), Vector2i(35, 10), Vector2i(36, 8), Vector2i(36, 9),
]
## SelectApricornForKurt, 86 in Crystal and 85 in Gold/Silver, which
## special_index() already normalizes. maps/KurtsHouse.asm's `.AskApricorn`
## branches on wScriptVar afterwards, one label per apricorn.
const SPECIAL_SELECT_APRICORN_FOR_KURT: int = 86
## MoveDeletion, 33 in both profiles: it sits below the first index the two
## tables disagree on, so `special_index()` leaves it alone. `MoveDeletion` owns
## the same shape `NameRater` does, one house further on, so it is one host
## request as well.
const SPECIAL_MOVE_DELETION: int = 33
## The Day-Care's five, all below the first index the two tables disagree on, so
## `special_index()` leaves them alone. `DayCareMan` and `DayCareLady` are the
## deposit and withdrawal counters; `DayCareManOutside` is the man who brings the
## egg out and the only one of the five that writes wScriptVar, which its map
## script branches on; `DayCareMon1` and `DayCareMon2` are the two signs inside,
## each a line, a cry and the pair's compatibility.
const SPECIAL_DAY_CARE_MAN: int = 30
const SPECIAL_DAY_CARE_LADY: int = 31
const SPECIAL_DAY_CARE_MAN_OUTSIDE: int = 32
const SPECIAL_DAY_CARE_MON_1: int = 69
const SPECIAL_DAY_CARE_MON_2: int = 70
## Which routine each index opens, in the request the host answers.
const DAY_CARE_ROLE_OF: Dictionary = {
	SPECIAL_DAY_CARE_MAN: &"man",
	SPECIAL_DAY_CARE_LADY: &"lady",
	SPECIAL_DAY_CARE_MAN_OUTSIDE: &"outside",
	SPECIAL_DAY_CARE_MON_1: &"mon1",
	SPECIAL_DAY_CARE_MON_2: &"mon2",
}

## NameRater, 87 in Crystal and 86 in Gold/Silver, which special_index()
## already normalizes. `_NameRater` owns its own texts, its two `YesNoBox`es and
## the party list `SelectMonFromParty` opens, so the whole routine is one host
## request; the map script's own `waitbutton` follows it.
const SPECIAL_NAME_RATER: int = 87
## `engine/events/haircut.asm`'s four routines, each of them
## `SelectMonFromParty` and then a read. `BillsGrandfather` answers the chosen
## member's *species*, since it names it with `GetPokemonName`; the three
## grooming routines answer `HappinessData_*`'s own row and name the member with
## `GetCurNickname`.
const SPECIAL_BILLS_GRANDFATHER: int = 77
const SPECIAL_OLDER_HAIRCUT_BROTHER: int = 97
const SPECIAL_YOUNGER_HAIRCUT_BROTHER: int = 98
const SPECIAL_DAISYS_GROOMING: int = 99
## Which `HappinessData_*` table each of the three walks.
const GROOMING_TABLE_OF: Dictionary = {
	SPECIAL_OLDER_HAIRCUT_BROTHER: &"older_haircut",
	SPECIAL_YOUNGER_HAIRCUT_BROTHER: &"younger_haircut",
	SPECIAL_DAISYS_GROOMING: &"grooming",
}
## `EGG`, which `HaircutOrGrooming` answers 1 for rather than grooming.
const SPECIES_EGG: int = 0xFD

## `constants/script_constants.asm`'s YOUR_MONEY, the account every
## `PlaceMoneyTextbox` prints and the one `checkmoney`/`takemoney` default to.
const ACCOUNT_YOUR_MONEY: int = 0

## The three balance windows of `engine/menus/menu_2.asm`. Each writes the
## tilemap and returns, so the box stands over the map until `closetext`
## redraws it, which is the same lifetime `Script_pokepic`'s box has.
const SPECIAL_DISPLAY_COIN_CASE_BALANCE: int = 79
const SPECIAL_DISPLAY_MONEY_AND_COIN_BALANCE: int = 80
const SPECIAL_PLACE_MONEY_TOP_RIGHT: int = 81
const MONEY_WINDOW_KIND_OF: Dictionary = {
	SPECIAL_DISPLAY_COIN_CASE_BALANCE: &"coin_case",
	SPECIAL_DISPLAY_MONEY_AND_COIN_BALANCE: &"money_and_coins",
	SPECIAL_PLACE_MONEY_TOP_RIGHT: &"money_top_right",
}

## DisplayUnownWords, which is Crystal's alone: pokegold's table stops well
## before it, so no Gold or Silver script can reach this index and neither dump
## ships the words. The four wall patterns are Crystal bg events, two per
## chamber, where Gold and Silver's cells carry only the puzzle sign. A preceding
## `setval` puts the `UNOWNWORDS_*` index in wScriptVar. Not to be read as 41,
## which is `UnownPuzzle` on both and is the sliding puzzle itself.
## `UnownPuzzle`, the sliding puzzle each of the four Ruins of Alph chambers
## opens. The map's own `setval` in front of it names which picture; the special
## answers `wSolvedUnownPuzzle` in wScriptVar, which the `iftrue` after the
## `closetext` reads. 41 on both profiles, being under `special_index`'s split.
## `SlotMachine`, the Game Corner's own machine. The map's `setval` in front of
## it is `wScriptVar`, which `Slots_InitBias` reads: TRUE picks `.Lucky`'s own
## bias table, and a `random 6 / ifequal 0` in front of the two scripts is which
## machine a player sat down at. 42 on both profiles, being under
## `special_index`'s split, and the machine's own `wCoins` writes are the coins
## the request answers with.
const SPECIAL_SLOT_MACHINE: int = 42
const SPECIAL_UNOWN_PUZZLE: int = 41
const SPECIAL_DISPLAY_UNOWN_WORDS: int = 135
const SPECIAL_RANDOM_UNSEEN_WILD_MON: int = 91
const SPECIAL_RANDOM_PHONE_WILD_MON: int = 92
const SPECIAL_RANDOM_PHONE_MON: int = 93
const SPECIAL_INITIAL_SET_DST_FLAG: int = 166
const SPECIAL_INITIAL_CLEAR_DST_FLAG: int = 167
const SPECIAL_FADE_OUT_MUSIC: int = 106
const SPECIAL_INIT_ROAM_MONS: int = 105
## The five map fades. `BattleTowerFade` is Crystal's own insertion at 47, which
## is why the four either side of it need no profile split.
const SPECIAL_FADE_OUT_TO_WHITE: int = 46
const SPECIAL_BATTLE_TOWER_FADE: int = 47
const SPECIAL_FADE_OUT_TO_BLACK: int = 48
const SPECIAL_FADE_IN_FROM_WHITE: int = 49
const SPECIAL_FADE_IN_FROM_BLACK: int = 50
## Which four rows of `.cgbfade` each of them walks, and in which direction.
const FADE_ORDERS_OF: Dictionary = {
	SPECIAL_FADE_OUT_TO_WHITE: Gen2WorldPalette.FADE_OUT_ORDERS,
	SPECIAL_BATTLE_TOWER_FADE: Gen2WorldPalette.FADE_OUT_ORDERS,
	SPECIAL_FADE_IN_FROM_WHITE: Gen2WorldPalette.FADE_IN_ORDERS,
	SPECIAL_FADE_OUT_TO_BLACK: Gen2WorldPalette.FADE_TO_BLACK_ORDERS,
	SPECIAL_FADE_IN_FROM_BLACK: Gen2WorldPalette.FADE_FROM_BLACK_ORDERS,
}
## `FillWhiteBGColor` runs in front of the two fades that end white and nowhere
## else, so the way to black flattens onto the map's own colour 0.
const FADE_WHITE_FILL_SPECIALS: Array[int] = [
	SPECIAL_FADE_OUT_TO_WHITE, SPECIAL_BATTLE_TOWER_FADE,
]
## `GameboyCheck`'s three answers (`constants/misc_constants.asm`). Every screen
## here is drawn in the CGB palettes, so `hCGB` is set and the other two are
## unreachable.
const GBCHECK_CGB: int = 2
## `BeastsCheck`'s three, in the order it asks about them.
const BEAST_SPECIES: Array[int] = [243, 244, 245]
## StrengthBoulderScript's index in StdScripts (engine/events/std_scripts.asm),
## the same 14 in both pins despite the tables being 52 and 46 long. Every
## boulder object in every map reaches Strength through `jumpstd` on it.
const STD_STRENGTH_BOULDER: int = 14
## SmashRockScript's index, directly after the boulder's and the same 15 in both
## pins. Every rock object in every map reaches Rock Smash through `jumpstd` on
## it, exactly as every boulder reaches Strength through 14.
const STD_SMASH_ROCK: int = 15
## TryStrengthOW's three wScriptVar answers. `.already_using` names the branch
## taken when `bit` sets Z, that is when the flag is still *clear*, so 0 is the
## value that asks and 2 the value that reports the flag already set.
const STRENGTH_OW_ASK: int = 0
const STRENGTH_OW_UNABLE: int = 1
const STRENGTH_OW_ALREADY_ACTIVE: int = 2
## data/text/common_2.asm. Synthesized rather than decoded because the script
## that shows them is reached only through `callasm`, which has no runner; see
## _stage_strength_boulder().
const STRENGTH_ASK_TEXT: String = \
	"A #MON may be\nable to move this.\n\nWant to use\nSTRENGTH?"
const STRENGTH_MAY_MOVE_TEXT: String = "A #MON may be\nable to move this."
const STRENGTH_BOULDERS_MOVE_TEXT: String = "Boulders may now\nbe moved!"
## data/text/common_2.asm again, for AskRockSmashScript. `HasRockSmash` answers
## 1 when CheckPartyMove fails, which is the `ifequal 1, .no` that reaches
## _MaySmashText; anything else asks.
const ROCK_SMASH_ASK_TEXT: String = \
	"This rock looks\nbreakable.\n\nWant to use ROCK\nSMASH?"
const ROCK_SMASH_MAY_SMASH_TEXT: String = "Maybe a #MON\ncan break this."
const ROCK_SMASH_USED_TEXT: String = "%s used\nROCK SMASH!"
## Script_earthquake's operand in RockSmashScript, kept because the runner
## reports the request rather than shaking anything.
const ROCK_SMASH_EARTHQUAKE: int = 84
## constants/sfx_constants.asm, whose comment column is hex. RockSmashScript
## plays the boulder's own sound rather than one of its own.
const SFX_STRENGTH: int = 0x1B

## data/text/common_2.asm, for the five Ask*Scripts TryTileCollisionEvent
## reaches. Synthesized rather than decoded for the reason AskStrengthScript's
## are: each is reached through `CallScript` on a link-time address, so there is
## no pointer in the pins to follow. All five are byte identical between them.
const CUT_ASK_TEXT: String = "This tree can be\nCUT!\n\nWant to use CUT?"
const CUT_CAN_TEXT: String = "This tree can be\nCUT!"
const SURF_ASK_TEXT: String = "The water is calm.\nWant to SURF?"
const WHIRLPOOL_ASK_TEXT: String = \
	"A whirlpool is in\nthe way.\n\nWant to use\nWHIRLPOOL?"
const WHIRLPOOL_MAY_PASS_TEXT: String = \
	"It's a vicious\nwhirlpool!\n\nA #MON may be\nable to pass it."
const WATERFALL_ASK_TEXT: String = "Do you want to use\nWATERFALL?"
const WATERFALL_HUGE_TEXT: String = "Wow, it's a huge\nwaterfall."
const HEADBUTT_ASK_TEXT: String = \
	"A #MON could be\nin this tree.\n\nWant to HEADBUTT\nit?"
## A field-move prompt has no source address to push a frame at, since
## CallScript's operand is a link-time one the pins do not resolve. The bare
## `end` frame still has to sit in the CPU's switchable window for _push_frame,
## so it is put at its base; nothing ever reads the address back.
const FIELD_MOVE_PROMPT_FRAME: int = RomFile.BANK_SIZE
## data/text/common_2.asm's _FoundItemText, less its <PLAYER>; see
## _stage_item_ball(). The source line break sits before the item name.
const FOUND_ITEM_TEXT: String = "Found\n%s!"
## Two source boxes, so four lines and no blank between them: the box is two
## rows, and a blank line would spend a third page drawing nothing.
const NO_SPACE_ITEM_TEXT: String = "Found\n%s!\nBut you have\nno space left."
## data/text/common_2.asm's `_ReceivedItemText`, `_PutItemInPocketText` and
## `_PocketIsFullText`, each less its `<PLAYER>` for the reason FOUND_ITEM_TEXT
## drops it: nothing writes `wPlayerName` yet. `GiveItemScript` prints the first
## two around every `verbosegiveitem`, and `itemnotify` the second on its own.
const RECEIVED_ITEM_TEXT: String = "Received\n%s."
## The pocket line's own `cont` is a scroll rather than a page, so the item it
## names is still on screen above it.
const PUT_ITEM_TEXT: String = "Put the\n%s in" + Gen2TextStream.SCROLL_BREAK + "the %s."
const POCKET_FULL_TEXT: String = "The %s\nis full…"
## constants/sfx_constants.asm. `FindItemInBallScript` plays SFX_ITEM by name
## rather than through `specialsound`, so a TM lying in a ball gets the ordinary
## item jingle and the same TM handed over by an NPC gets SFX_GET_TM.
const SFX_ITEM: int = 0x01
## data/text/common_1.asm's four fruit tree texts, paired the same way.
## `_HeyItsFruitText` and `_ObtainedFruitText` are one staged text because the
## source's `giveitem` sits between them and has nothing to show; they still
## paginate into the two boxes the cartridge draws.
const FRUIT_TREE_TEXT: String = "It's a fruit-\nbearing tree."
const FRUIT_TREE_EMPTY_TEXT: String = "There's nothing\nhere…"
const FRUIT_TREE_OBTAINED_TEXT: String = "Hey! It's\n%s!\nObtained\n%s!"
const FRUIT_TREE_FULL_TEXT: String = "Hey! It's\n%s!\nBut the PACK is\nfull…"
## The `disappear LAST_TALKED` operand (constants/map_object_constants.asm).
const LAST_TALKED: int = 0xFE
## wBattleResult, which startbattle copies into wScriptVar
## (constants/battle_constants.asm).
const BATTLE_RESULT_WIN: int = 0
const BATTLE_RESULT_LOSE: int = 1
const BATTLE_RESULT_DRAW: int = 2
const TEXT_STRING_BUFFER: int = 0x14
## The two waits `ScriptEvents` spends frames in rather than asking for anything
## (`engine/overworld/scripting.asm`). WAIT_MOVEMENT is SCRIPT_WAIT_MOVEMENT,
## which runs until the stream an `applymovement` started clears
## SCRIPTED_MOVEMENT_STATE_F; WAIT_FRAMES is the counted delay `Script_pause`,
## `Script_wait` and `Script_deactivatefacing` spend. Neither takes a button, so
## both resolve through complete_wait() rather than through advance().
const WAIT_MOVEMENT: StringName = &"movement"
const WAIT_FRAMES: StringName = &"frames"
## `Script_pause` delays `DelayFrames 2` per counted unit and `Script_wait`
## delays six.
const PAUSE_FRAMES_PER_UNIT: int = 2
const WAIT_FRAMES_PER_UNIT: int = 6
## `SetDayOfWeek.WeekdayStrings`, padded the way the source pads them so the
## name is centred in its nine-wide box. One list, in [Gen2ClockSetScreen],
## because the dial that draws it is shared with `InitClock`.
const WEEKDAY_NAMES: Array[String] = Gen2ClockSetScreen.DAYS

## Crystal event flags used by the player's room decoration callbacks. The
## importer keeps raw cartridge flag numbers, so these values match the
## source event flag table rather than a project-local enum.
const EVENT_TEMPORARY_UNTIL_MAP_RELOAD_8: int = 7
const EVENT_PLAYERS_ROOM_POSTER: int = 716
const EVENT_PLAYERS_HOUSE_2F_CONSOLE: int = 1857
const EVENT_PLAYERS_HOUSE_2F_DOLL_1: int = 1858
const EVENT_PLAYERS_HOUSE_2F_DOLL_2: int = 1859
const EVENT_PLAYERS_HOUSE_2F_BIG_DOLL: int = 1860
const VARIABLE_SPRITE_BASE: int = 0xF0
const DECORATION_BLOCKS: Dictionary = {
	&"bed": {0x02: 0x1B, 0x03: 0x1C, 0x04: 0x1D, 0x05: 0x1E},
	&"carpet": {0x07: 0x08, 0x08: 0x0B, 0x09: 0x0E, 0x0A: 0x11},
	&"plant": {0x0C: 0x20, 0x0D: 0x21, 0x0E: 0x22},
	&"poster": {0x10: 0x1F, 0x11: 0x23, 0x12: 0x24, 0x13: 0x25},
}


static func begin(
	game_data: GameData,
	world_state: Gen2WorldState,
	request: Dictionary,
	validator: Callable = Callable(),
	random: RandomNumberGenerator = null,
) -> Gen2WorldScriptRunner:
	var runner := Gen2WorldScriptRunner.new()
	runner.data = game_data
	runner.state = world_state
	runner.warp_validator = validator
	runner._request = request.duplicate(true)
	runner._phone_context = request.get("phone", {}).duplicate(true)
	if random != null:
		runner._random = random
	else:
		runner._random.randomize()
	runner._reset_phone_receive_timer = bool(request.get("reset_receive_timer", false))
	runner._last_talked_object_index = int(request.get("object_index", -1))
	runner._last_item = int(request.get("item", 0))
	runner.player_name = String(request.get("player_name", ""))
	var bank: int = int(request.get("bank", 0))
	var address: int = int(request.get("script", request.get("address", 0)))
	var trainer_phase: StringName = StringName(request.get("trainer_phase", &""))
	var trainer: Variant = request.get("trainer", {})
	var started: bool = false
	if not trainer_phase.is_empty():
		## LoadTrainer_continue clears wRunningTrainerBattleScript for every
		## trainer encounter, talked to or seen (home/trainers.asm), and only
		## StartBattleWithMapTrainerScript's `loadmem wRunningTrainerBattleScript,
		## -1` sets it again. Without this the flag committed by one battle
		## outlives it, so `endifjustbattled` ends the after-battle script on
		## every later conversation and nothing past that command ever runs. The
		## Rocket hideout's two password grunts are the first place on the walked
		## route where that content is load bearing.
		runner._stage_just_battled(false)
	if trainer_phase == &"initial" and trainer is Dictionary:
		started = runner._push_frame(
			bank, address, runner._trainer_intro_script(trainer as Dictionary)
		)
		## Only SeenByTrainerScript shows the shock emote and walks the trainer
		## over; TalkToTrainerScript is faceplayer, the flag check and
		## encountermusic, then the same StartBattleWithMapTrainerScript
		## (engine/events/trainer_scripts.asm). A sight request is the one that
		## carries the direction the trainer saw along, so it is the one that
		## approaches.
		runner._trainer_intro_approach_pending = request.get("direction", Vector2i.ZERO) \
			in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	elif StringName(request.get("kind", &"")) == &"field_move_prompt":
		## TryTileCollisionEvent's five field-move branches each reach an
		## Ask*Script through CallScript on a link-time address, so there is no
		## pointer to push and the frame that stands in for one is a bare `end`,
		## exactly as an item ball's is.
		started = runner._push_frame(
			bank, FIELD_MOVE_PROMPT_FRAME, PackedByteArray([
				Gen2WorldScript.raw_opcode(Gen2WorldScript.GOLD_END, runner._crystal_commands())
			])
		)
		if started:
			runner._stage_field_move_prompt()
	elif StringName(request.get("kind", &"")) in [&"item_ball", &"hidden_item"]:
		## Neither pointer is code, so the frame that stands in for it is a bare
		## `end` and the staging call replays FindItemInBallScript or
		## HiddenItemScript.
		started = runner._push_frame(bank, address, PackedByteArray([
			Gen2WorldScript.raw_opcode(Gen2WorldScript.GOLD_END, runner._crystal_commands())
		]))
		if started:
			if StringName(request.get("kind", &"")) == &"item_ball":
				runner._stage_item_ball()
			else:
				runner._stage_hidden_item()
	else:
		started = runner._push_frame(bank, address)
		## A label inside another script has no pointer of its own, so a caller
		## that resolved one names the script containing it and how far in it
		## starts. `WateredWeirdTreeScript` is the only one.
		var offset: int = int(request.get("offset", 0))
		if started and offset > 0:
			var frame: Dictionary = runner._frames[runner._frames.size() - 1]
			if offset >= (frame["data"] as PackedByteArray).size():
				started = false
			else:
				frame["offset"] = offset
				runner._frames[runner._frames.size() - 1] = frame
	if not started:
		runner._fail(&"missing_script", {"bank": bank, "address": address})
	else:
		runner._active = true
	return runner


## Advances until a text/button pause, completion or a bounded failure.
func advance(acknowledge: bool = false, choice: int = -1) -> Dictionary:
	if not _phone_context.is_empty() and not _phone_started:
		_phone_started = true
		_emit_runtime_event(&"phone_call_started", _phone_context)
	if _pending:
		if _pending.has("text"):
			_standing_text = String(_pending["text"])
		var pending_request: Dictionary = _pending.get("request", {})
		if _pending.get("type", &"") == &"runtime_request" \
			and StringName(pending_request.get("kind", &"")) == &"battle_requested":
			return _waiting_result()
		## Only frames end a wait, so a button press cannot: the source is inside
		## WaitScriptMovement or a DelayFrames loop, which read no input at all.
		if _pending.get("type", &"") == &"wait":
			return _waiting_result()
		if not acknowledge:
			return _waiting_result()
		var pending_type: StringName = StringName(_pending.get("type", &""))
		if pending_type == &"menu" and _pending.get("special", &"") == &"set_day_of_week":
			if choice < 0:
				return _waiting_result()
			var selected_day: int = posmod(choice, WEEKDAY_NAMES.size())
			_pending = {
				"type": &"text",
				## `.ConfirmWeekdayText` places the weekday at `hlcoord 1, 14` and
				## `_OakTimeIsItText` carries on from where `PlaceString` left
				## off, so the two are one line.
				"text": "%s, is it?" % WEEKDAY_NAMES[selected_day],
				"special": &"set_day_of_week_confirmation",
				"day": selected_day,
				"source": _request.duplicate(true),
			}
			return _waiting_result()
		if pending_type == &"text" and _pending.get("special", &"") == &"set_day_of_week_confirmation":
			var confirmation_day: int = int(_pending.get("day", 0))
			_stage_day_of_week_confirmation(confirmation_day)
			return _waiting_result()
		if pending_type == &"choice" and _pending.get("special", &"") == &"set_day_of_week_confirmation":
			if choice < 0:
				return _waiting_result()
			var confirmed_day: int = int(_pending.get("day", 0))
			_pending = {}
			if choice == 0:
				_staged_day_of_week = confirmed_day
				_script_value = 1
				return advance()
			_stage_day_of_week_menu()
			return _waiting_result()
		## AskStrengthScript's `.AskStrength`: opentext, writetext, yesorno. The
		## text pause is acknowledged first, then the choice is offered.
		if pending_type == &"text" and _pending.get("special", &"") == &"strength_ask":
			_pending = {
				"type": &"choice",
				"command": &"yesorno",
				"choices": [&"yes", &"no"],
				"text": _standing_text,
				"special": &"strength_ask",
				"slot": int(_pending.get("slot", -1)),
				"source": _request.duplicate(true),
			}
			return _waiting_result()
		if pending_type == &"choice" and _pending.get("special", &"") == &"strength_ask":
			if choice < 0:
				return _waiting_result()
			var chosen_slot: int = int(_pending.get("slot", -1))
			_pending = {}
			## `iftrue Script_UsedStrength`, and a no falls to closetext/end.
			_script_value = 1 if choice == 0 else 0
			if choice != 0:
				return _complete()
			_stage_strength_used(chosen_slot)
			return _waiting_result()
		## FruitTreeScript's promptbutton, behind which its two callasms sit.
		if pending_type == &"text" and _pending.get("special", &"") == &"fruit_tree":
			var fruit_tree: int = int(_pending.get("tree_id", 0))
			var fruit_item: int = int(_pending.get("item", 0))
			_pending = {}
			_finish_after_pending = false
			var picked: Dictionary = _resolve_fruit_tree(fruit_tree, fruit_item)
			if not bool(picked.get("ok", false)):
				return _fail(StringName(picked.get("reason", &"fruit_tree_failed")), picked)
			return _waiting_result()
		## The tail every item receipt shares behind its own line: the sound, and
		## then `itemnotify`'s box once the host has played it.
		if pending_type == &"text" and _pending.get("special", &"") == &"item_received":
			var receipt_item: int = int(_pending.get("item", 0))
			var receipt_sfx: int = int(_pending.get("sfx", 0))
			var receipt_finish: bool = bool(_pending.get("finish", false))
			_pending = {}
			_finish_after_pending = false
			_stage_receipt_tail(receipt_item, receipt_sfx, receipt_finish)
			return _waiting_result()
		## `GiveItemScript.Full`, whose `promptbutton` is the acknowledge above.
		if pending_type == &"text" and _pending.get("special", &"") == &"pocket_is_full":
			var full_item: int = int(_pending.get("item", 0))
			var full_finish: bool = bool(_pending.get("finish", false))
			_pending = {}
			_finish_after_pending = false
			_stage_pocket_is_full(full_item, full_finish)
			return _waiting_result()
		## Script_UsedStrength's second writetext, _MoveBoulderText.
		if pending_type == &"text" and _pending.get("special", &"") == &"strength_used":
			var used_name: String = String(_pending.get("name", "#MON"))
			_stage_internal_text("%s can\nmove boulders." % used_name, true)
			return _waiting_result()
		## describedecoration is a local script in the cartridge. Its text must be
		## acknowledged before the one decoration that needs a host, the town map,
		## calls OverworldTownMap. Keeping this continuation on the text pause
		## preserves the source's opentext/waitbutton/special/closetext/end order.
		if pending_type == &"text" and _pending.has("special_after_text"):
			var decoration_special: int = int(_pending.get("special_after_text", -1))
			_pending = {}
			_finish_after_pending = false
			var special_result: Dictionary = _execute_special(decoration_special)
			if not bool(special_result.get("ok", false)):
				return _fail(
					StringName(special_result.get("reason", &"special_failed")),
					special_result
				)
			return _waiting_result() if _pending else advance()
		## The five Ask*Scripts TryTileCollisionEvent reaches, all one shape:
		## opentext, writetext, yesorno, iftrue <the move>, closetext, end.
		if pending_type == &"text" and _pending.get("special", &"") == &"field_move_ask":
			_pending = {
				"type": &"choice",
				"command": &"yesorno",
				"choices": [&"yes", &"no"],
				"text": _standing_text,
				"special": &"field_move_ask",
				"move": int(_pending.get("move", 0)),
				"slot": int(_pending.get("slot", -1)),
				"source": _request.duplicate(true),
			}
			return _waiting_result()
		if pending_type == &"choice" and _pending.get("special", &"") == &"field_move_ask":
			if choice < 0:
				return _waiting_result()
			var asked_move: int = int(_pending.get("move", 0))
			var asked_slot: int = int(_pending.get("slot", -1))
			_pending = {}
			_script_value = 1 if choice == 0 else 0
			if choice == 0:
				## `iftrue Script_Cut` and its four counterparts. The move
				## itself belongs to the host, which owns the staged request
				## and the commit the party submenu already reaches.
				_emit_runtime_event(&"field_move_confirmed", {
					"move": asked_move, "slot": asked_slot,
				})
			return _complete()
		## AskRockSmashScript, the same opentext/writetext/yesorno shape.
		if pending_type == &"text" and _pending.get("special", &"") == &"rock_smash_ask":
			_pending = {
				"type": &"choice",
				"command": &"yesorno",
				"choices": [&"yes", &"no"],
				"text": _standing_text,
				"special": &"rock_smash_ask",
				"slot": int(_pending.get("slot", -1)),
				"source": _request.duplicate(true),
			}
			return _waiting_result()
		if pending_type == &"choice" and _pending.get("special", &"") == &"rock_smash_ask":
			if choice < 0:
				return _waiting_result()
			var smash_slot: int = int(_pending.get("slot", -1))
			_pending = {}
			## `iftrue RockSmashScript`, and a no falls to closetext/end.
			_script_value = 1 if choice == 0 else 0
			if choice != 0:
				return _complete()
			_stage_rock_smash_used(smash_slot)
			return _waiting_result()
		## RockSmashScript's `closetext`, `special WaitSFX` and
		## `playsound SFX_STRENGTH`. The rest of the script waits on the sound
		## the way a trainer's approach waits on its encounter music.
		if pending_type == &"text" and _pending.get("special", &"") == &"rock_smash_used":
			_pending = {}
			_rock_smash_after_sound = true
			_stage_audio_request(&"sound", {"address": SFX_STRENGTH})
			return _waiting_result()
		if pending_type in [&"choice", &"menu"]:
			if choice < 0:
				return _waiting_result()
			if pending_type == &"menu":
				## Script_verticalmenu and Script__2dmenu store wMenuCursorY and
				## wMenuCursorPosition, which count from one; cancel_input()
				## already writes the zero their carry branch does. So a caller's
				## zero-based option is the source's option minus one.
				_script_value = choice + 1
			elif pending_type == &"choice" \
				and _pending.get("choices", []) == [&"yes", &"no"]:
				_script_value = 1 if choice == 0 else 0
			else:
				_script_value = choice
		if pending_type == &"choice" and _pending.has("contact"):
			var contact: int = int(_pending.get("contact", -1))
			if choice == 0:
				var phone_result: Dictionary = _stage_phone_contact(contact)
				if not bool(phone_result.get("ok", false)):
					return _fail(
						StringName(phone_result.get("reason", &"phone_contact_failed")),
						phone_result
					)
			else:
				_script_value = PHONE_CONTACT_REFUSED
			_emit_runtime_event(&"phone_number_result", {
				"contact": contact,
				"accepted": choice == 0 and _script_value == PHONE_CONTACT_GOT,
				"result": _script_value,
			})
		if pending_type == &"battle":
			_stage_just_battled(true)
		var finish_after_pending: bool = _finish_after_pending
		_pending = {}
		_finish_after_pending = false
		if finish_after_pending:
			return _complete()

	if not _active:
		return _failure_result() if not _failure.is_empty() else _complete_result()

	while _active:
		if _command_count >= Gen2WorldScript.MAX_COMMANDS:
			return _fail(&"command_limit", {"limit": Gen2WorldScript.MAX_COMMANDS})
		if _frames.is_empty():
			return _complete()

		var frame: Dictionary = _frames[_frames.size() - 1]
		var command: Dictionary = Gen2WorldScript.command_at(
			frame["data"], int(frame["offset"]), _crystal_commands()
		)
		if not bool(command.get("ok", false)):
			return _fail(StringName(command.get("reason", &"invalid_command")), command)
		frame["offset"] = int(frame["offset"]) + int(command["width"])
		_frames[_frames.size() - 1] = frame
		_command_count += 1

		var outcome: Dictionary = _execute(command, frame)
		if not bool(outcome.get("ok", true)):
			return _fail(StringName(outcome.get("reason", &"script_failed")), outcome)
		if _pending:
			return _waiting_result()
		if _completed:
			## A terminal command returns _complete()'s own result, which has
			## already drained the events; asking for a second one would hand the
			## caller an empty list in its place.
			return outcome if outcome.has("status") else _complete_result()

	return _complete()


## Completes a host-owned runtime request without treating a button press as its
## result. A confirmed loss ends this invocation through the explicit blackout
## recovery result without committing its staged world state.
func complete_runtime_request(result: Dictionary) -> Dictionary:
	if _pending.is_empty() or _pending.get("type", &"") != &"runtime_request":
		return {
			"ok": false, "status": &"failed", "reason": &"runtime_request_not_pending",
			"details": result.duplicate(true),
		}
	var request: Dictionary = _pending.get("request", {})
	var kind: StringName = StringName(request.get("kind", &""))
	if kind == &"catch_tutorial_requested":
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", &"catch_tutorial_failed")), result
			)
		var catch_outcome: StringName = StringName(result.get("outcome", &""))
		if catch_outcome != Gen2WorldBattleAdapter.OUTCOME_CAUGHT:
			return _fail(&"invalid_catch_tutorial_outcome", result)
		_script_value = 1
		_events.append({
			"type": &"catch_tutorial_completed",
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_events.append({"type": &"battle_map_reload_requested", "tutorial": true})
		_pending = {}
		return advance()
	if kind == &"swarm_requested":
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", &"swarm_request_failed")), result
			)
		var values: Dictionary = request.get("values", {})
		var active: bool = bool(result.get("active", true))
		var map_group: int = int(result.get("map_group", values.get("map_group", -1)))
		var map_number: int = int(result.get("map_number", values.get("map_number", -1)))
		var fishing_species: int = int(result.get("fishing_species", 0))
		if active and (map_group < 0 or map_number < 0):
			return _fail(&"invalid_swarm_map", result)
		if fishing_species not in [0, 0xD3, 0xDF]:
			return _fail(&"invalid_fishing_swarm_species", result)
		_staged_swarm = {
			"active": active,
			"map_group": map_group,
			"map_number": map_number,
			"fishing_species": fishing_species,
		}
		_has_staged_swarm = true
		_events.append({
			"type": &"swarm_changed",
			"map_group": map_group,
			"map_number": map_number,
			"active": active,
			"fishing_species": fishing_species,
		})
		_pending = {}
		return advance()
	if kind in [&"phone_call_requested", &"special_phone_call_requested"]:
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", "runtime_request_failed")), result
			)
		var phone_data: Dictionary = result.get("data", {})
		_events.append({
			"type": &"runtime_request_completed",
			"kind": kind,
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_pending = {}
		if bool(phone_data.get("clear", false)):
			_phone_context = {}
			_script_value = 1
			return advance()
		var phone_script: Dictionary = phone_data.get("script", {})
		if phone_script.is_empty():
			_script_value = int(result.get("script_value", 1))
			return advance()
		_phone_context = phone_data.get("phone", {}).duplicate(true)
		_phone_started = false
		if not _push_frame(
			int(phone_script.get("bank", -1)), int(phone_script.get("address", -1))
		):
			return _fail(&"phone_script_missing", phone_script)
		return advance()
	if kind == &"party_selection_requested":
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", &"party_selection_failed")), result
			)
		return _finish_party_selection(request, result)
	if kind == &"apricorn_selection_requested":
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", &"apricorn_selection_failed")), result
			)
		var apricorn: int = int(result.get("item", 0))
		var apricorn_quantity: int = int(result.get("quantity", 0))
		if apricorn != 0 and not Gen2WorldApricorn.is_apricorn(apricorn):
			return _fail(&"invalid_apricorn", result)
		## `SelectApricornForKurt` zeroes wKurtApricornQuantity on entry and
		## writes it only past `Kurt_SelectQuantity`'s carry, so a cancelled
		## selection leaves both bytes at zero.
		if apricorn == 0:
			apricorn_quantity = 0
		elif apricorn_quantity < 1 or apricorn_quantity > Gen2WorldApricorn.MAX_QUANTITY:
			return _fail(&"invalid_apricorn_quantity", result)
		_script_value = apricorn
		_staged_kurt_apricorn_quantity = apricorn_quantity
		_has_staged_kurt_apricorn_quantity = true
		_events.append({
			"type": &"runtime_request_completed",
			"kind": kind,
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_pending = {}
		return advance()
	if kind == &"trainer_approach_requested":
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", &"trainer_approach_failed")), result
			)
		_events.append({
			"type": &"trainer_approach_completed",
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_pending = {}
		return advance()
	if kind == &"day_care_requested":
		## Four of the five write nothing a script reads, so wScriptVar is left
		## where it stood unless the result carries one: `DayCareManOutside` is
		## the only routine of the five with an `ld [wScriptVar], a` in it.
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", &"runtime_request_failed")), result
			)
		if result.has("script_value"):
			_script_value = int(result["script_value"])
		_events.append({
			"type": &"runtime_request_completed",
			"kind": kind,
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_pending = {}
		return advance()
	if kind == &"slot_machine_requested":
		## `_SlotMachine` writes `wCoins` itself, over and over, so what comes
		## back is the balance rather than a delta. Nothing reads `wScriptVar`
		## after it: both maps `closetext` and `end`.
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", &"slot_machine_failed")), result
			)
		var slot_coins: int = int(result.get("coins", _coins_value()))
		if slot_coins < 0 or slot_coins > Gen2SlotMachine.MAX_COINS:
			return _fail(&"invalid_coins", result)
		_staged_coins = slot_coins
		_events.append({
			"type": &"runtime_request_completed",
			"kind": kind,
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_pending = {}
		return advance()
	if kind in [
		&"mart_requested", &"audio_requested", &"pokemon_requested", &"trade_requested",
		&"pc_requested", &"party_heal_requested", &"town_map_requested",
		## `BugContestJudging` answers with the placing, which the results script
		## reads out of wScriptVar exactly as the marts and the PC do.
		&"bug_contest_judging_requested",
		## Neither routine writes anything a script reads: each returns and the
		## map's own `waitbutton` presses the text it left standing.
		&"name_rater_requested", &"move_deleter_requested",
		## `UnownPuzzle` answers `wSolvedUnownPuzzle`, which is zero for a board
		## left on START and one for a solved one.
		&"unown_puzzle_requested",
	]:
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", "runtime_request_failed")), result
			)
		_script_value = int(result.get("script_value", 1))
		_events.append({
			"type": &"runtime_request_completed",
			"kind": kind,
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		var approach_after_audio: bool = kind == &"audio_requested" \
			and StringName((request.get("values", {}) as Dictionary).get("kind", &"")) \
			== &"encounter_music" and _trainer_intro_approach_pending
		var smash_after_sound: bool = kind == &"audio_requested" \
			and StringName((request.get("values", {}) as Dictionary).get("kind", &"")) \
			== &"sound" and _rock_smash_after_sound
		var notify_after_sound: Dictionary = _item_notify_after_sound \
			if kind == &"audio_requested" else {}
		_pending = {}
		if approach_after_audio:
			_trainer_intro_approach_pending = false
			_stage_trainer_approach()
		if smash_after_sound:
			_rock_smash_after_sound = false
			_stage_rock_smashed()
		if not notify_after_sound.is_empty():
			_item_notify_after_sound = {}
			_stage_item_notify(
				int(notify_after_sound.get("item", 0)),
				bool(notify_after_sound.get("finish", false))
			)
		return advance()
	if kind == &"rival_name_requested":
		if not bool(result.get("ok", false)):
			return _fail(
				StringName(result.get("reason", &"runtime_request_failed")), result
			)
		var default_name: String = String(
			(request.get("values", {}) as Dictionary).get("default_name", "SILVER")
		)
		_rival_name = String(result.get("name", default_name)).strip_edges()
		if _rival_name.is_empty():
			_rival_name = default_name
		_script_value = 1
		_events.append({"type": &"rival_name_changed", "name": _rival_name})
		_pending = {}
		return advance()
	if kind != &"battle_requested":
		return {
			"ok": false, "status": &"failed", "reason": &"runtime_request_kind_mismatch",
			"details": {"kind": kind},
		}
	if not bool(result.get("ok", false)):
		return _fail(
			StringName(result.get("reason", &"runtime_request_failed")), result
		)
	var outcome: StringName = StringName(result.get("outcome", &""))
	if String(outcome).is_empty():
		return _fail(&"invalid_battle_outcome", result)
	var battle_values: Dictionary = request.get("values", {})
	if outcome == Gen2WorldBattleAdapter.OUTCOME_LOST and bool(battle_values.get("can_lose", false)):
		_script_value = 0
		_events.append({
			"type": &"battle_lost",
			"outcome": outcome,
			"can_lose": true,
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_pending = {}
		return advance()
	if outcome == Gen2WorldBattleAdapter.OUTCOME_LOST:
		var recovery: Variant = result.get("recovery", {})
		if not recovery is Dictionary or not bool((recovery as Dictionary).get("ok", false)):
			return _fail(&"battle_recovery_failed", result)
		_events.append({
			"type": &"battle_lost",
			"outcome": outcome,
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_events.append({
			"type": &"blackout",
			"recovery": (recovery as Dictionary).duplicate(true),
		})
		_pending = {}
		_active = false
		_completed = true
		return _recovered_result(recovery as Dictionary)
	if outcome == Gen2WorldBattleAdapter.OUTCOME_CAUGHT:
		_script_value = BATTLE_RESULT_WIN
		_events.append({
			"type": &"battle_captured",
			"outcome": outcome,
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_pending = {}
		return advance()
	if outcome == Gen2WorldBattleAdapter.OUTCOME_RAN:
		## `.can_escape` writes DRAW into wBattleResult, and the script carries
		## on: `reloadmapafterbattle` only branches on LOSE. The eight corpus
		## scripts that `iftrue` straight after `startbattle` are asking "did I
		## not win", and a run answers yes.
		_stage_just_battled(true)
		_script_value = BATTLE_RESULT_DRAW
		_events.append({
			"type": &"battle_completed",
			"outcome": outcome,
			"request": request.duplicate(true),
			"result": result.duplicate(true),
		})
		_pending = {}
		return advance()
	if outcome != Gen2WorldBattleAdapter.OUTCOME_WON:
		return _fail(StringName("battle_%s" % outcome), result)

	_stage_just_battled(true)
	## Script_startbattle leaves `wBattleResult & ~BATTLERESULT_BITMASK` in
	## wScriptVar, and WIN is zero there, so the eight corpus scripts that put
	## an `iftrue` straight after `startbattle` are asking "did I not win".
	## Catching masks its own bit off and also reads as WIN.
	_script_value = BATTLE_RESULT_WIN
	_events.append({
		"type": &"battle_completed",
		"outcome": outcome,
		"request": request.duplicate(true),
		"result": result.duplicate(true),
	})
	_pending = {}
	return advance()


func pending_runtime_request() -> Dictionary:
	if _pending.get("type", &"") != &"runtime_request":
		return {}
	var request: Dictionary = (_pending.get("request", {}) as Dictionary).duplicate(true)
	request["source"] = (_pending.get("source", {}) as Dictionary).duplicate(true)
	return request


func pending_input() -> Dictionary:
	return _pending.duplicate(true)


## The frame wait this invocation is standing in, empty when it is not standing
## in one. A caller spends the frames and calls [method complete_wait]; nothing
## else ends it.
func pending_wait() -> Dictionary:
	if StringName(_pending.get("type", &"")) != &"wait":
		return {}
	return _pending.duplicate(true)


## Resumes after the wait above. `ShowEmoteScript`'s trailing
## `applymovementlasttalked .Hide` is the one continuation a wait carries: the
## emote is put up by the script the source calls and taken down by the same
## script, so the hide belongs to the end of the pause rather than to a host.
func complete_wait() -> Dictionary:
	if StringName(_pending.get("type", &"")) != &"wait":
		return {
			"ok": false, "status": &"failed", "reason": &"script_wait_not_pending",
		}
	var hide_emote_object: int = int(_pending.get("hide_emote_object", -1))
	_pending = {}
	if hide_emote_object >= 0:
		_emit_object_event(&"object_emote", {
			"object_index": hide_emote_object,
			"emote_id": _loaded_emote,
			"visible": false,
			"duration": 0,
		})
	return advance()


## Cancels a pending menu or choice without inventing a cartridge option. The
## script receives zero, matching the false branch used by yes/no commands.
func cancel_input() -> Dictionary:
	if _pending.is_empty() or StringName(_pending.get("type", &"")) not in [&"choice", &"menu"]:
		return {
			"ok": false,
			"status": &"failed",
			"reason": &"script_input_not_cancellable",
		}
	var pending_type: StringName = StringName(_pending.get("type", &""))
	if pending_type == &"choice" and _pending.has("contact"):
		_emit_runtime_event(&"phone_number_result", {
			"contact": int(_pending.get("contact", -1)), "accepted": false,
		})
	_script_value = 0
	var finish_after_pending: bool = _finish_after_pending
	_pending = {}
	_finish_after_pending = false
	if finish_after_pending:
		return _complete()
	return advance()


func is_waiting() -> bool:
	return not _pending.is_empty()


func is_finished() -> bool:
	return _completed or not _failure.is_empty()


func _execute(command: Dictionary, frame: Dictionary) -> Dictionary:
	var opcode: int = int(command["opcode"])
	var bank: int = int(frame["bank"])
	command = _catalogued(command, frame)
	if opcode == Gen2WorldScript.FARJUMPTEXT:
		if _crystal_commands():
			return _show_text(int(command["bank"]), int(command["address"]), true)
		return _show_text(bank, int(command["address"]), true)
	if opcode == Gen2WorldScript.JUMPTEXT and _crystal_commands():
		return _show_text(bank, int(command["address"]), true)
	if Gen2WorldScript.is_waitbutton(opcode, _crystal_commands()) \
		or Gen2WorldScript.is_promptbutton(opcode, _crystal_commands()):
		return _stage_button(command)
	if opcode == 0xA8 and _crystal_commands():
		## `wait` is one of the commands Crystal added, so it has no pokegold
		## opcode to resolve through and has to answer from the raw byte.
		## Script_wait delays its operand times six frames and reads nothing.
		## The two Magnet Train stations are its only call sites in either pin.
		_emit_runtime_event(&"script_timing_requested", {
			"kind": &"wait",
			"value": int(command.get("value", 0)),
			"frames": int(command.get("value", 0)) * WAIT_FRAMES_PER_UNIT,
		})
		return _stage_frame_wait(int(command.get("value", 0)) * WAIT_FRAMES_PER_UNIT)
	if opcode == 0x9F and _crystal_commands():
		## Crystal inserts verbosegiveitemvar at this raw byte. Normalizing first
		## turns it into pokegold's swarm command.
		var quantity_result: Dictionary = _read_runtime_variable(
			int(command.get("variable", 0))
		)
		if not bool(quantity_result.get("ok", false)):
			return quantity_result
		var variable_item: int = int(command.get("item", 0))
		var variable_name: String = data.item_name(variable_item) if data != null else ""
		_set_text_buffer(
			RomLayout.STRING_BUFFER_4, variable_name, &"item_name",
			{"item": variable_item}
		)
		var variable_given: Dictionary = _stage_item_delta(variable_item, _script_value)
		if not bool(variable_given.get("ok", true)):
			return variable_given
		return _stage_give_item_script(variable_item, variable_name)
	var source: int = Gen2WorldScript.source_opcode(opcode, _crystal_commands())
	var object_result: Dictionary = _execute_object_command(source, command)
	if not object_result.is_empty():
		return object_result
	var later_result: Dictionary = _execute_later_command(source, command, bank)
	if not later_result.is_empty():
		return later_result
	if Gen2WorldScript.is_terminal(opcode, _crystal_commands()):
		_frames.pop_back()
		if _frames.is_empty():
			return _complete()
		return {"ok": true}
	match opcode:
		Gen2WorldScript.SCALL:
			return {"ok": _push_frame(bank, int(command["address"]))}
		Gen2WorldScript.FARSCALL:
			return {"ok": _push_frame(int(command["bank"]), int(command["address"]))}
		Gen2WorldScript.MEMCALL, Gen2WorldScript.MEMJUMP:
			var runtime_pointer: Dictionary = _runtime_memory_pointer(
				int(command.get("address", 0))
			)
			if runtime_pointer.is_empty():
				return {
					"ok": false, "reason": &"missing_runtime_pointer",
					"address": int(command.get("address", 0)), "command": command,
				}
			var pointer_bank: int = int(runtime_pointer.get("bank", -1))
			var pointer_address: int = int(runtime_pointer.get("address", -1))
			if opcode == Gen2WorldScript.MEMCALL:
				if not _push_frame(pointer_bank, pointer_address):
					return {
						"ok": false, "reason": &"missing_runtime_script",
						"bank": pointer_bank, "address": pointer_address,
					}
				return {"ok": true}
			var jump_result: Dictionary = _replace_frame(pointer_bank, pointer_address)
			return jump_result
		Gen2WorldScript.BLACKOUTMOD:
			## BLACKOUTMOD changes the cartridge's recovery destination. The current
			## save boundary does not yet relocate a player on ordinary blackout, so
			## retain the source value as an explicit event rather than discarding it.
			_emit_runtime_event(&"blackout_destination_changed", {
				"map": int(command.get("value", 0)),
			})
		Gen2WorldScript.SJUMP:
			return _replace_frame(bank, int(command["address"]))
		Gen2WorldScript.FARSJUMP:
			return _replace_frame(int(command["bank"]), int(command["address"]))
		Gen2WorldScript.IFEQUAL:
			return _branch(int(_script_value) == int(command["value"]), bank, int(command["address"]))
		Gen2WorldScript.IFNOTEQUAL:
			return _branch(int(_script_value) != int(command["value"]), bank, int(command["address"]))
		Gen2WorldScript.IFFALSE:
			return _branch(_script_value == 0, bank, int(command["address"]))
		Gen2WorldScript.IFTRUE:
			return _branch(_script_value != 0, bank, int(command["address"]))
		Gen2WorldScript.IFGREATER:
			return _branch(_script_value > int(command["value"]), bank, int(command["address"]))
		Gen2WorldScript.IFLESS:
			return _branch(_script_value < int(command["value"]), bank, int(command["address"]))
		Gen2WorldScript.JUMPSTD:
			if int(command["address"]) == STD_STRENGTH_BOULDER:
				return _stage_strength_boulder()
			if int(command["address"]) == STD_SMASH_ROCK:
				return _stage_smash_rock()
			var jump_standard: Dictionary = _standard_script(int(command["address"]))
			if jump_standard.is_empty():
				return {
					"ok": false,
					"reason": &"missing_standard_script",
					"standard_index": int(command["address"]),
				}
			return _replace_frame(
				int(jump_standard["bank"]), int(jump_standard["address"]),
				jump_standard["data"]
			)
		Gen2WorldScript.CALLSTD:
			if int(command["address"]) == STD_STRENGTH_BOULDER:
				return _stage_strength_boulder()
			if int(command["address"]) == STD_SMASH_ROCK:
				return _stage_smash_rock()
			var call_standard: Dictionary = _standard_script(int(command["address"]))
			if call_standard.is_empty():
				return {
					"ok": false,
					"reason": &"missing_standard_script",
					"standard_index": int(command["address"]),
				}
			return {
				"ok": _push_frame(
					int(call_standard["bank"]), int(call_standard["address"]),
					call_standard["data"]
				)
			}
		Gen2WorldScript.CHECKMAPSCENE:
			_script_value = _map_scene_value(
				int(command["map_group"]), int(command["map_number"])
			)
		Gen2WorldScript.SETMAPSCENE:
			var target_key: String = Gen2WorldState.map_scene_key(
				int(command["map_group"]), int(command["map_number"])
			)
			_staged_scenes[target_key] = int(command["scene"])
		Gen2WorldScript.CHECKSCENE:
			_script_value = _map_scene_value(
				int(_request.get("map_group", 0)), int(_request.get("map_number", 0))
			)
		Gen2WorldScript.SETSCENE:
			var map_key: String = Gen2WorldState.map_scene_key(
				int(_request.get("map_group", 0)), int(_request.get("map_number", 0))
			)
			_staged_scenes[map_key] = int(command["scene"])
		Gen2WorldScript.CHECKVER:
			## Script_checkver answers GS_VERSION, which
			## `constants/misc_constants.asm` defines as 0 for Gold and 1 for
			## Silver; pokecrystal defines it 0 unconditionally.
			_script_value = 1 if data != null and data.id == &"silver" else 0
		Gen2WorldScript.SETVAL:
			_script_value = int(command["value"])
		Gen2WorldScript.ADDVAL:
			## Script_addval adds into wScriptVar, one byte, so it wraps there
			## and not only where the value is later written. Goldenrod's switch
			## room turns a switch off with `addval -1` and branches on it.
			_script_value = (_script_value + int(command["value"])) & 0xFF
		Gen2WorldScript.READMEM:
			_script_value = _script_memory_value(int(command["address"]))
		Gen2WorldScript.WRITEMEM:
			return _stage_script_memory(int(command["address"]), _script_value)
		Gen2WorldScript.LOADMEM:
			return _stage_script_memory(int(command["address"]), int(command["value"]))
		Gen2WorldScript.READVAR:
			return _read_runtime_variable(int(command["value"]))
		Gen2WorldScript.LOADVAR:
			return _load_runtime_variable(
				int(command["value"]), int(command["value_2"])
			)
		Gen2WorldScript.CHECKTIME:
			_script_value = 1 if Gen2WorldPhoneHost.time_mask_matches(
				int(command["value"]), _clock_hour()
			) else 0
		Gen2WorldScript.ADDCELLNUM:
			return _stage_phone_contact(int(command["value"]))
		Gen2WorldScript.DELCELLNUM:
			return _stage_phone_contact(int(command["value"]), false)
		Gen2WorldScript.CHECKCELLNUM:
			_script_value = 1 if _phone_contact_registered(int(command["value"])) else 0
		Gen2WorldScript.SPECIAL:
			return _execute_special(
				Gen2WorldScript.special_index(int(command["value"]), _crystal_commands())
			)
		Gen2WorldScript.RANDOM:
			var maximum: int = int(command["value"])
			_script_value = _random.randi_range(0, maximum - 1) if maximum > 0 else 0
		Gen2WorldScript.GIVEITEM:
			return _stage_item_delta(int(command["value"]), int(command["value_2"]))
		Gen2WorldScript.TAKEITEM:
			return _stage_item_delta(int(command["value"]), -int(command["value_2"]))
		Gen2WorldScript.CHECKITEM:
			_script_value = 1 if _item_quantity(int(command["value"])) > 0 else 0
		Gen2WorldScript.GIVEMONEY, Gen2WorldScript.TAKEMONEY:
			return _stage_money_delta(
				int(command["account"]), _decode_bcd(command["amount_bytes"]),
				opcode == Gen2WorldScript.GIVEMONEY
			)
		Gen2WorldScript.CHECKMONEY:
			_script_value = _compare_amount(
				_money_balance(int(command["account"])),
				_decode_bcd(command["amount_bytes"])
			)
		Gen2WorldScript.GIVECOINS, Gen2WorldScript.TAKECOINS:
			return _stage_coins_delta(
				int(command["value"]), opcode == Gen2WorldScript.GIVECOINS
			)
		Gen2WorldScript.CHECKCOINS:
			_script_value = _compare_amount(_coins_value(), int(command["value"]))
		Gen2WorldScript.GETMONEY:
			var money: int = _money_balance(int(command["account"]))
			_set_text_buffer(int(command["string_buffer"]), str(money), &"money")
			_emit_runtime_event(&"text_value_requested", {
				"value_kind": &"money", "account": int(command["account"]),
				"value": money,
				"string_buffer": int(command["string_buffer"]),
			})
		Gen2WorldScript.GETCOINS:
			var coins: int = _coins_value()
			_set_text_buffer(int(command["string_buffer"]), str(coins), &"coins")
			_emit_runtime_event(&"text_value_requested", {
				"value_kind": &"coins", "value": coins,
				"string_buffer": int(command["string_buffer"]),
			})
		Gen2WorldScript.GETITEMNAME:
			_set_text_buffer(
				int(command["string_buffer"]),
				data.item_name(int(command["item"])) if data != null else "",
				&"item_name",
				{"item": int(command["item"])}
			)
			_emit_runtime_event(&"text_buffer_requested", command)
		Gen2WorldScript.GETMONNAME:
			_set_text_buffer(
				int(command["string_buffer"]),
				String(data.species(int(command["pokemon"])).get("name", "")) if data != null else "",
				&"mon_name",
				{"pokemon": int(command["pokemon"])}
			)
			_emit_runtime_event(&"text_buffer_requested", command)
		Gen2WorldScript.GETTRAINERNAME:
			var trainer_name: String = ""
			if data != null:
				trainer_name = String(data.trainer_party(
					int(command["trainer_group"]), int(command["trainer_id"]) - 1
				).get("name", ""))
			_set_text_buffer(
				int(command["string_buffer"]), trainer_name, &"trainer_name",
				{"trainer_group": int(command["trainer_group"]), "trainer_id": int(command["trainer_id"])}
			)
			_emit_runtime_event(&"text_buffer_requested", command)
		Gen2WorldScript.GETSTRING:
			## `Script_getstring` is `CopyName1`, which copies a plain character
			## run up to its `@`. It is not a text: the first byte of
			## `PokegearName` is `#`, which the command layer reads as an unknown
			## command and refuses, so decoding this the way `writetext` is
			## decoded leaves every `getstring` buffer empty and prints
			## "<PLAYER> received !" with a hole where the name belongs.
			var string_text: String = ""
			if data != null:
				var string_data: PackedByteArray = data.world_text(
					int(_request.get("bank", 0)), int(command["address"])
				)
				string_text = Gen2Text.decode(string_data, 0, string_data.size())
			_set_text_buffer(int(command["string_buffer"]), string_text, &"string", {
				"bank": int(_request.get("bank", 0)), "address": int(command["address"]),
			})
			_emit_runtime_event(&"text_buffer_requested", command)
		Gen2WorldScript.CLEAREVENT:
			_staged_flags[int(command["flag"])] = false
		Gen2WorldScript.SETEVENT:
			_staged_flags[int(command["flag"])] = true
		Gen2WorldScript.CHECKEVENT:
			_script_value = 1 if _event_flag_active(int(command["flag"])) else 0
		Gen2WorldScript.CLEARFLAG:
			_staged_engine_flags[int(command["flag"])] = false
		Gen2WorldScript.SETFLAG:
			_staged_engine_flags[int(command["flag"])] = true
		Gen2WorldScript.CHECKFLAG:
			_script_value = 1 if _engine_flag_active(int(command["flag"])) else 0
		## `Script_wildon` and `Script_wildoff`, which write
		## `STATUSFLAGS_NO_WILD_ENCOUNTERS_F` outright rather than through a
		## staged flag: it is scratch the next map entry does not clear, and the
		## scripts that turn it off all turn it back on themselves.
		Gen2WorldScript.WILDON:
			_emit_runtime_event(&"wild_encounters_changed", {"enabled": true})
		Gen2WorldScript.WILDOFF:
			_emit_runtime_event(&"wild_encounters_changed", {"enabled": false})
		Gen2WorldScript.WARP:
			return _stage_warp(command)
		Gen2WorldScript.OPENTEXT, Gen2WorldScript.REANCHORMAP, Gen2WorldScript.CLOSETEXT, Gen2WorldScript.WRITEUNUSEDBYTE, Gen2WorldScript.CLOSEWINDOW:
			## `Script_closetext` takes the box down, so nothing stands behind a
			## later choice; leaving the last question there would print it under
			## an unrelated menu.
			if opcode == Gen2WorldScript.CLOSETEXT:
				_standing_text = ""
				## The balance windows are tilemap, so the redraw behind the box
				## is what takes them away too.
				if _money_window != &"":
					_money_window = &""
					_emit_runtime_event(&"money_window_closed", {})
		Gen2WorldScript.ITEMNOTIFY:
			## `CurItemName` reads wCurItem, which whichever `giveitem` came
			## before this wrote.
			return _stage_item_notify(_last_item, false)
		Gen2WorldScript.POCKETISFULL:
			return _stage_pocket_is_full(_last_item, false)
		Gen2WorldScript.WRITETEXT:
			return _show_text(bank, int(command["address"]), false)
		Gen2WorldScript.FARWRITETEXT:
			return _show_text(int(command["bank"]), int(command["address"]), false)
		Gen2WorldScript.JUMPTEXTFACEPLAYER:
			return _show_text(bank, int(command["address"]), true)
		Gen2WorldScript.REPEATTEXT:
			if int(command["value"]) == 0xFF and int(command["value_2"]) == 0xFF:
				if _last_text.is_empty():
					return {"ok": false, "reason": &"repeat_without_text"}
				return _show_text(int(_last_text["bank"]), int(_last_text["address"]), false)
		Gen2WorldScript.YESORNO:
			return _stage_choice(command, [&"yes", &"no"])
		Gen2WorldScript.LOADMENU:
			_loaded_menu = {
				"bank": int(_request.get("bank", 0)),
				"address": int(command["address"]),
			}
			if data != null:
				var cached_menu: Dictionary = data.world_menu(
					int(_request.get("bank", 0)), int(command["address"])
				)
				for key: String in cached_menu:
					_loaded_menu[key] = cached_menu[key]
			_emit_runtime_event(&"menu_loaded", _loaded_menu)
		Gen2WorldScript.CHECKPOKE:
			## Script_checkpoke sets wScriptVar from whether the species is in
			## wPartySpecies (engine/overworld/scripting.asm). The read-only party
			## summary is the only party this scene-free runner may read, and an
			## absent one fails the way VAR_PARTYCOUNT does. A summary carrying an
			## empty species list answers 0, not a failure.
			var party: Dictionary = _request.get("party", {})
			if party.is_empty():
				return {"ok": false, "reason": &"missing_party_summary", "command": command}
			var species: Array = party.get("species", [])
			_script_value = 1 if int(command.get("value", 0)) in species else 0
		Gen2WorldScript.GIVEPOKE, Gen2WorldScript.GIVEEGG:
			## Both write their species operand to wCurPartySpecies before the
			## routine runs, whether or not the party had room for it.
			_cur_party_species = int(command.get("pokemon", 0))
			return _stage_runtime_request(&"pokemon_requested", command)
		Gen2WorldScript.GIVEPOKEMAIL, Gen2WorldScript.CHECKPOKEMAIL:
			return _stage_runtime_request(&"mail_requested", command)
		Gen2WorldScript.GOLD_FACEPLAYER, Gen2WorldScript.FACEPLAYER:
			if Gen2WorldScript.is_faceplayer(opcode, _crystal_commands()):
				pass
	var handled_base: Array = [
		Gen2WorldScript.CHECKMAPSCENE, Gen2WorldScript.SETMAPSCENE,
		Gen2WorldScript.CHECKSCENE, Gen2WorldScript.SETSCENE,
		Gen2WorldScript.CHECKVER,
		Gen2WorldScript.SETVAL, Gen2WorldScript.ADDVAL, Gen2WorldScript.RANDOM,
		Gen2WorldScript.CHECKEVENT, Gen2WorldScript.CLEAREVENT, Gen2WorldScript.SETEVENT,
		Gen2WorldScript.CHECKFLAG, Gen2WorldScript.CLEARFLAG, Gen2WorldScript.SETFLAG,
		Gen2WorldScript.WILDON, Gen2WorldScript.WILDOFF,
		Gen2WorldScript.READMEM,
		Gen2WorldScript.READVAR, Gen2WorldScript.LOADVAR,
		Gen2WorldScript.CHECKTIME, Gen2WorldScript.SPECIAL,
		Gen2WorldScript.CHECKITEM, Gen2WorldScript.CHECKPOKE,
		Gen2WorldScript.ADDCELLNUM, Gen2WorldScript.DELCELLNUM,
		Gen2WorldScript.CHECKCELLNUM,
		Gen2WorldScript.GOLD_FACEPLAYER, Gen2WorldScript.FACEPLAYER,
		Gen2WorldScript.OPENTEXT, Gen2WorldScript.REANCHORMAP,
		Gen2WorldScript.CLOSETEXT, Gen2WorldScript.WRITEUNUSEDBYTE,
		Gen2WorldScript.CLOSEWINDOW,
		Gen2WorldScript.LOADMENU,
		## Both comparisons answer through `_script_value` and stage nothing, so
		## they never returned from their own branch and fell through to the
		## refusal below. Every `checkcoins` in either game is a Game Corner or a
		## Buena prize counter, and every one of them stopped its script here.
		Gen2WorldScript.CHECKMONEY, Gen2WorldScript.CHECKCOINS,
		Gen2WorldScript.GETMONEY, Gen2WorldScript.GETCOINS, Gen2WorldScript.GETNUM,
		Gen2WorldScript.GETMONNAME, Gen2WorldScript.GETITEMNAME,
		Gen2WorldScript.GETCURLANDMARKNAME, Gen2WorldScript.GETTRAINERNAME,
		Gen2WorldScript.GETSTRING, Gen2WorldScript.BLACKOUTMOD,
	]
	if opcode in handled_base:
		return {"ok": true}
	return {
		"ok": false,
		"reason": &"unsupported_runtime_command",
		"command": command,
	}


## A command whose numbers a mod may have moved, substituted before it runs.
##
## The site is addressed by the byte it sits at, `frame.address + offset`, which
## is exactly the id [Gen2WorldCatalog] gave it. Only the OPERANDS change: the
## command still runs, its script still sets its own completion flag, prints its
## own dialogue and takes its own money, and nothing here can replace any of
## that. A cartridge with no mod patch pays one dictionary read.
func _catalogued(command: Dictionary, frame: Dictionary) -> Dictionary:
	if data == null or not data.has_content_overlay():
		return command
	var linked: Dictionary = data.catalog().link_at(
		int(frame["bank"]), int(frame["address"]) + int(command["offset"])
	)
	if not linked.is_empty():
		return _linked_command(command, linked)
	var candidates: Array = CATALOG_KINDS.get(StringName(command["name"]), [])
	if candidates.is_empty():
		return command
	var at: int = int(frame["address"]) + int(command["offset"])
	var row: Dictionary = {}
	var kind: StringName = &""
	for candidate: StringName in candidates:
		row = data.catalog().check(
			Gen2WorldCatalog.pack_id(candidate, int(frame["bank"]), at)
		)
		if not row.is_empty():
			kind = candidate
			break
	if row.is_empty():
		return command
	var out: Dictionary = command.duplicate(true)
	match kind:
		Gen2WorldCatalog.KIND_STATIC:
			out["pokemon"] = int(row["species"])
			out["level"] = int(row["level"])
		Gen2WorldCatalog.KIND_SHOP:
			out["address"] = int(row["mart"])
			## The inventory this site sells, carried to the mart host so a
			## patched shelf reaches the shop rather than a different mart id.
			out["mart_items"] = row.get("items", [])
		Gen2WorldCatalog.KIND_TRADE:
			out["value"] = int(row["trade"])
			## Both halves, carried beside the record rather than written into
			## it: one cartridge trade row can be named by two sites.
			out["offered_species"] = int(row["species"])
			out["requested_species"] = int(row["requested_species"])
		Gen2WorldCatalog.KIND_BADGE:
			## The badge a flag grants IS the flag, so moving one moves which
			## bit the site sets. An index outside the list leaves it alone.
			var flags: Array[int] = Gen2WorldState.BADGE_ENGINE_FLAGS \
				if Gen2WorldState.is_crystal_profile(data) \
				else Gen2WorldState.BADGE_ENGINE_FLAGS_GOLD_SILVER
			var badge: int = int(row["badge"])
			if badge >= 0 and badge < flags.size():
				out["flag"] = flags[badge]
		Gen2WorldCatalog.KIND_ITEM:
			out["item"] = int(row["item"])
			out["value"] = int(row["item"])
			out["quantity"] = maxi(1, int(row["quantity"]))
			out["value_2"] = maxi(1, int(row["quantity"]))
		_:
			## Every giving kind: a starter, a gift and a prize are one command.
			out["pokemon"] = int(row["species"])
			out["value"] = int(row["species"])
			out["level"] = int(row["level"])
			out["value_2"] = int(row["level"])
			out["item"] = int(row.get("item", command.get("item", 0)))
	return out


## A command that is not the site itself but carries one of its numbers: the
## `pokepic` a starter's ball shows, and the `checkcoins`/`takecoins` a prize
## charges with. Substituting only the `givepoke` would show one Pokemon and hand
## over another, and price a prize the player could not afford.
func _linked_command(command: Dictionary, linked: Dictionary) -> Dictionary:
	var row: Dictionary = data.catalog().check(int(linked["id"]))
	if row.is_empty():
		return command
	var out: Dictionary = command.duplicate(true)
	match StringName(linked["role"]):
		&"picture":
			out["pokemon"] = int(row["species"])
		&"price":
			out["value"] = int(row["price"])
	return out


## Which catalog kinds a command name can be a site for. `givepoke` is three at
## once, and which one it is was decided when the catalog walked the script, so
## the id is tried under each until one answers. A site the catalog never
## recorded answers empty under all of them and the command runs untouched.
const CATALOG_KINDS: Dictionary = {
	&"loadwildmon": [Gen2WorldCatalog.KIND_STATIC],
	&"trade": [Gen2WorldCatalog.KIND_TRADE],
	&"pokemart": [Gen2WorldCatalog.KIND_SHOP],
	&"setflag": [Gen2WorldCatalog.KIND_BADGE],
	&"giveitem": [Gen2WorldCatalog.KIND_ITEM],
	&"verbosegiveitem": [Gen2WorldCatalog.KIND_ITEM],
	&"givepoke": [
		Gen2WorldCatalog.KIND_GIFT, Gen2WorldCatalog.KIND_STARTER,
		Gen2WorldCatalog.KIND_PRIZE,
	],
	&"giveegg": [Gen2WorldCatalog.KIND_GIFT],
}


func _execute_later_command(source_opcode: int, command: Dictionary, bank: int) -> Dictionary:
	match source_opcode:
		0x55:
			## `Script_pokepic` takes wScriptVar when its operand is zero and
			## writes whichever it settled on to wCurPartySpecies, which is
			## what a later `special PlayCurMonCry` reads.
			var pic_species: int = int(command.get("pokemon", 0))
			if pic_species == 0:
				pic_species = _script_value
			_cur_party_species = pic_species
			_emit_runtime_event(&"pokemon_picture_requested", {
				"pokemon": pic_species,
			})
		0x56:
			_emit_runtime_event(&"pokemon_picture_closed", {})
		0x57, 0x58:
			return _stage_menu(source_opcode == 0x57, command)
		0x5B:
			var trainer_value: Variant = _request.get("trainer", {})
			if trainer_value is Dictionary and not (trainer_value as Dictionary).is_empty():
				var trainer: Dictionary = trainer_value as Dictionary
				_battle_setup = _new_battle_setup({
					"kind": &"trainer",
					"trainer_group": int(trainer.get("trainer_group", 0)),
					"trainer_id": maxi(int(trainer.get("trainer_id", 0)) - 1, 0),
					"trainer_flag": int(trainer.get("event_flag", -1)),
					"win_text": _trainer_text_pointer(trainer, "win_text", bank),
					"loss_text": _trainer_text_pointer(trainer, "loss_text", bank),
				})
				_emit_runtime_event(&"battle_setup_changed", _battle_setup)
		0x5C:
			_battle_setup = _new_battle_setup({
				"kind": &"wild", "pokemon": int(command.get("pokemon", 0)),
				"level": int(command.get("level", 0)),
			})
			_emit_runtime_event(&"battle_setup_changed", _battle_setup)
		0x5D:
			_loaded_battle_type = -1
			_battle_setup = _new_battle_setup({
				"kind": &"trainer", "trainer_group": int(command.get("trainer_group", 0)),
				# The cartridge's loadtrainer operand is one-based; the imported
				# party table API is zero-based.
				"trainer_id": maxi(int(command.get("trainer_id", 0)) - 1, 0),
			})
			_emit_runtime_event(&"battle_setup_changed", _battle_setup)
		0x5E:
			if _battle_setup.is_empty():
				return {
					"ok": false, "reason": &"battle_setup_missing", "command": command,
				}
			return _stage_runtime_request(&"battle_requested", _battle_request_values())
		0x5F:
			_emit_runtime_event(&"battle_map_reload_requested", {"requested": true})
		0x60:
			var tutorial_setup: Dictionary = _battle_setup.duplicate(true)
			if tutorial_setup.is_empty() or StringName(tutorial_setup.get("kind", &"")) != &"wild":
				return {"ok": false, "reason": &"tutorial_battle_setup_missing"}
			tutorial_setup["tutorial"] = true
			tutorial_setup["battle_type"] = int(command.get("value", 0))
			tutorial_setup["can_lose"] = false
			return _stage_runtime_request(&"catch_tutorial_requested", tutorial_setup)
		0x61:
			return _stage_runtime_request(&"trainer_text_requested", {
				"text_id": int(command.get("value", 0)),
				"setup": _battle_setup.duplicate(true),
			})
		0x62:
			var trainer_event: Dictionary = _request.get("event", {})
			var trainer_data: Variant = _request.get("trainer", {})
			var trainer_flag: int = int(trainer_event.get("event_flag", 0))
			if trainer_data is Dictionary and not (trainer_data as Dictionary).is_empty():
				trainer_flag = int((trainer_data as Dictionary).get("event_flag", -1))
			var action: int = int(command.get("value", 0))
			if action == 0:
				_staged_flags[trainer_flag] = false
			elif action == 1:
				_staged_flags[trainer_flag] = true
			elif action == 2:
				_script_value = 1 if _event_flag_active(trainer_flag) else 0
			else:
				return {"ok": false, "reason": &"unsupported_trainer_flag_action", "action": action}
			_emit_runtime_event(&"trainer_flag_action", {
				"action": action, "event_flag": trainer_flag,
				"script_value": _script_value,
			})
		0x63:
			_battle_setup["win_text"] = {
				"bank": bank, "address": int(command.get("win_address", 0)),
			}
			_battle_setup["loss_text"] = {
				"bank": bank, "address": int(command.get("loss_address", 0)),
			}
		0x64:
			## Script_scripttalkafter jumps to wScriptAfterPointer in
			## wSeenTrainerBank, which is the map's own script bank here. A
			## record without one leaves the script to end, since the source
			## always writes the pointer the trainer macro carries.
			var after_trainer: Variant = _request.get("trainer", {})
			var after_address: int = int((after_trainer as Dictionary).get("after_script", 0)) \
				if after_trainer is Dictionary else 0
			_emit_runtime_event(&"trainer_talk_after_requested", {
				"bank": bank, "address": after_address,
			})
			if after_address > 0:
				_frames.clear()
				if not _push_frame(bank, after_address):
					return {
						"ok": false, "reason": &"missing_trainer_after_script",
						"bank": bank, "address": after_address,
					}
		0x65:
			if _just_battled():
				_frames.clear()
		0x66:
			_script_value = 1 if _just_battled() else 0
		0x73:
			_loaded_emote = int(command.get("value", -1))
			if _loaded_emote == 0xFF:
				_loaded_emote = _script_value
			_emit_runtime_event(&"emote_loaded", {"emote_id": _loaded_emote})
		0x74:
			## Script_showemote is `ScriptCall ShowEmoteScript`: loademote, an
			## applymovement that shows the emote, `pause 0` over the delay this
			## command just wrote, and an applymovement that hides it again. The two
			## one-command movements are folded into the emote event and its hide;
			## the pause is the wait, and it is what the operand measures.
			var emote_id: int = int(command.get("value", _loaded_emote))
			if emote_id == 0xFF:
				emote_id = _loaded_emote
			_loaded_emote = emote_id
			## `cp LAST_TALKED / jr z` keeps hLastTalked as it was only when the
			## operand is LAST_TALKED itself; every other id becomes the new one,
			## which is what the two `applymovementlasttalked`s inside
			## ShowEmoteScript then move.
			var emote_object_id: int = int(command.get("object_id", 0))
			if emote_object_id != LAST_TALKED:
				_last_talked_object_index = _object_index_from_id(emote_object_id)
			var emote_object: int = _object_index_from_id(emote_object_id)
			_script_delay = int(command.get("value_2", 0))
			_emit_object_event(&"object_emote", {
				"object_index": emote_object,
				"emote_id": emote_id,
				"visible": true,
				## Zero is "until the hide", not "for no time": the source takes the
				## emote down from ShowEmoteScript's last command, not on a counter.
				"duration": 0,
			})
			return _stage_frame_wait(
				_script_delay * PAUSE_FRAMES_PER_UNIT,
				{"hide_emote_object": emote_object, "emote_id": emote_id}
			)
		0x77:
			## Script_earthquake is `ScriptCall` on `applymovement PLAYER,
			## wEarthquakeMovementDataBuffer`, whose stream is `step_shake n` then
			## `step_sleep (n & %00111111)`. The shake starts and the movement wait
			## is that sleep, since step_shake itself reaches
			## ContinueReadingMovement without spending a frame.
			_emit_runtime_event(&"earthquake_requested", {
				"strength": int(command.get("value", 0)),
			})
			return _stage_frame_wait(int(command.get("value", 0)) & 0x3F)
		0x78:
			_emit_runtime_event(&"map_blocks_requested", {
				"bank": bank, "address": int(command.get("address", 0)),
			})
		0x79:
			_emit_runtime_event(&"map_block_changed", {
				"x": int(command.get("x", 0)), "y": int(command.get("y", 0)),
				"block": int(command.get("block", 0)),
			})
		0x7A:
			_emit_runtime_event(&"map_reload_requested", {})
		0x7B:
			_emit_runtime_event(&"map_refresh_requested", {})
		0x7C:
			_emit_runtime_event(&"command_queue_written", {
				"bank": bank, "address": int(command.get("address", 0)),
			})
		0x7D:
			_script_value = 1
			_emit_runtime_event(&"command_queue_deleted", {
				"queue_id": int(command.get("value", -1)),
			})
		0x7E:
			return _stage_audio_request(&"music", {
				"address": int(command.get("address", 0)),
			})
		0x7F:
			return _stage_audio_request(&"encounter_music", {})
		0x80:
			return _stage_audio_request(&"music_fadeout", {
				"music": int(command.get("value", 0)),
				"fade_time": int(command.get("value_2", 0)),
			})
		0x81:
			return _stage_audio_request(&"map_music", {})
		0x82:
			_emit_runtime_event(&"map_music_restart_disabled", {})
		0x83:
			return _stage_audio_request(&"cry", {"species": int(command.get("value", 0))})
		0x84:
			return _stage_audio_request(&"sound", {"address": int(command.get("value", 0))})
		0x85:
			return _stage_audio_request(&"sound_wait", {})
		0x86:
			return _stage_audio_request(&"warp_sound", {
				"collision": int(_request.get("collision", -1)),
			})
		0x87:
			return _stage_audio_request(&"special_sound", {"item": _last_item})
		0x6C:
			## variablesprite stores a sprite id in the source's variable-sprite
			## table. The first operand is an index relative to SPRITE_VARS.
			_emit_runtime_event(&"variable_sprite_changed", {
				"variable_sprite": VARIABLE_SPRITE_BASE + int(command.get("value", 0)),
				"sprite": int(command.get("value_2", 0)),
			})
		0x8A, 0x8B:
			## Both write wScriptDelay when their operand is nonzero and reuse
			## whatever is in it when it is zero. `Script_pause` then spends
			## `DelayFrames 2` per unit inside the command; `Script_deactivatefacing`
			## hands the same count to SCRIPT_WAIT, which WaitScript decrements once
			## per frame.
			var delay_operand: int = int(command.get("value", 0))
			if delay_operand != 0:
				_script_delay = delay_operand
			var delay_frames: int = _script_delay * PAUSE_FRAMES_PER_UNIT \
				if source_opcode == 0x8A else _script_delay
			_emit_runtime_event(&"script_timing_requested", {
				"kind": &"pause" if source_opcode == 0x8A else &"deactivate_facing",
				"value": delay_operand,
				"frames": delay_frames,
			})
			return _stage_frame_wait(delay_frames)
		0x8C:
			_ran_deferred = true
			if not _push_frame(bank, int(command.get("address", 0))):
				return {
					"ok": false, "reason": &"missing_deferred_script",
					"bank": bank, "address": int(command.get("address", 0)),
				}
		0x89:
			## Script_newloadmap sets hMapEntryMethod and re-enters the current
			## map. It yields rather than ending: StopScript only clears
			## SCRIPT_RUNNING in wScriptFlags, so the commands after it run, as
			## FallIntoMapScript's pitfall animation shows
			## (engine/overworld/events.asm). The re-entry itself is already
			## queued here, because the `warpcheck` before it took a warp and
			## every map change queues its own callbacks, so what is left to
			## carry is the entry method the transition is drawn with.
			_emit_runtime_event(&"map_entry_method_requested", {
				"method": int(command.get("value", 0)),
			})
		0x8D:
			## Script_warpcheck runs WarpCheck against the cell the player is
			## standing on, so the destination is the world's to resolve, not
			## the script's. Burned Tower's rival scene opens the hole under the
			## player and then relies on this to drop them through it.
			_emit_runtime_event(&"warp_check_requested", {})
		0x93:
			var mart: Dictionary = {
				"dialog": int(command.get("value", 0)),
				"address": int(command.get("address", 0)),
			}
			if command.has("mart_items"):
				mart["items"] = command["mart_items"]
			return _stage_runtime_request(&"mart_requested", mart)
		0x94:
			return _stage_runtime_request(&"elevator_requested", {
				"address": int(command.get("address", 0)),
			})
		0x95:
			var trade: Dictionary = {"trade_id": int(command.get("value", 0))}
			## A patched site names both halves; an unpatched one names neither
			## and the record answers for both, as it always has.
			for key: String in ["offered_species", "requested_species"]:
				if command.has(key):
					trade[key] = int(command[key])
			return _stage_runtime_request(&"trade_requested", trade)
		0x96:
			return _stage_phone_choice(int(command.get("value", 0)))
		0x97:
			return _stage_runtime_request(&"phone_call_requested", {
				"address": int(command.get("address", 0)),
			})
		0x98:
			_emit_runtime_event(&"phone_hangup", {})
		0x99:
			return _stage_decoration_description(int(command.get("value", 0)))
		0x9A:
			return _stage_fruit_tree(int(command.get("value", 0)))
		0x9B:
			## The cartridge uses specialphonecall to store the pending special
			## call. Imported phone scripts also use SPECIALCALL_NONE to clear it.
			## This command never starts the call directly. CheckSpecialPhoneCall
			## consumes the staged value during a later step.
			var special_call_id: int = int(command.get("address", 0))
			if not _phone_context.is_empty():
				_phone_context["special_call_id"] = special_call_id
			_staged_special_phone_call = special_call_id
			_has_staged_special_phone_call = true
			_script_value = 1
			_emit_runtime_event(&"special_phone_call_changed", {
				"call_id": special_call_id,
			})
			return {"ok": true}
		0x9C:
			_script_value = 1 if _current_special_phone_call() != 0 else 0
		0x9D:
			## Script_verbosegiveitem is Script_giveitem plus `CurItemName` and a
			## CopyConvertedText into STRING_BUFFER_4, which is what GiveItemScript's
			## _ReceivedItemText then prints as `text_ram wStringBuffer4`. Staging
			## the item without filling the buffer leaves that text unresolved.
			var verbose_item: int = int(command.get("item", 0))
			var verbose_name: String = data.item_name(verbose_item) if data != null else ""
			_set_text_buffer(
				RomLayout.STRING_BUFFER_4, verbose_name, &"item_name",
				{"item": verbose_item}
			)
			var given: Dictionary = _stage_item_delta(
				verbose_item, int(command.get("quantity", 1))
			)
			if not bool(given.get("ok", true)):
				return given
			return _stage_give_item_script(verbose_item, verbose_name)
		0x9E:
			return _stage_runtime_request(&"swarm_requested", {
				"map_group": int(command.get("map_group", 0)),
				"map_number": int(command.get("map_number", 0)),
			})
		0x9F:
			_staged_engine_flags[Gen2WorldState.ENGINE_HALL_OF_FAME] = true
			_events.append({"type": &"hall_of_fame_requested"})
		0xA0:
			## Script_credits farcalls RedCredits and then falls into
			## Script_endall the way Script_halloffame does
			## (engine/overworld/scripting.asm's ReturnFromCredits). No flag and
			## no state: presentation only, and both call sites are followed by
			## the source's own `end`, so this runs on rather than stopping.
			_events.append({"type": &"credits_requested"})
		0xA1:
			return _stage_warp_facing_request(command)
	## The commands whose case above falls out of the match rather than returning
	## a result of its own. The four that now wait (`showemote`, `earthquake`,
	## `pause` and `deactivatefacing`) return from inside it and are not here.
	var handled_sources: Array = [
		0x55, 0x56, 0x57, 0x58, 0x5B, 0x5C, 0x5D, 0x5F, 0x60, 0x61, 0x62, 0x63, 0x64,
		0x65, 0x66, 0x7F, 0x81, 0x82, 0x85, 0x8D, 0x98,
		0x8C,
		0x6C, 0x73, 0x78, 0x79, 0x7A, 0x7B, 0x7C, 0x7D, 0x9C, 0x9F,
		0xA0, 0x89,
	]
	if source_opcode in handled_sources:
		return {"ok": true}
	return {}


func _execute_object_command(source_opcode: int, command: Dictionary) -> Dictionary:
	match source_opcode:
		0x67:
			_last_talked_object_index = _object_index_from_id(int(command["object_id"]))
		0x68:
			var movement_event_type: StringName = &"player_movement_requested" \
				if int(command.get("object_id", 0)) == 0 else &"object_movement_requested"
			var movement_values: Dictionary = {
				"bank": int(_request.get("bank", 0)),
				"address": int(command.get("address", 0)),
			}
			var moved_index: int = -1
			if movement_event_type == &"object_movement_requested":
				moved_index = _object_index_from_id(int(command.get("object_id", 0)))
				movement_values["object_index"] = moved_index
			_emit_object_event(movement_event_type, movement_values)
			return _stage_movement_wait({"object_index": moved_index})
		0x69:
			_emit_object_event(&"object_movement_requested", {
				"object_index": _last_talked_object_index,
				"bank": int(_request.get("bank", 0)),
				"address": int(command.get("address", 0)),
			})
			return _stage_movement_wait({"object_index": _last_talked_object_index})
		0x6A:
			if _last_talked_object_index >= 0:
				_emit_object_event(&"object_face_player", {
					"object_index": _last_talked_object_index,
				})
		0x6B:
			var first_object_id: int = int(command.get("object_id", 0))
			var first_object: int = _object_index_from_id(first_object_id)
			var second_object: int = _object_index_from_id(int(command.get("object_id_2", 0)))
			if first_object_id == 0 and second_object >= 0:
				# faceobject PLAYER, LAST_TALKED faces the player toward the
				# trainer. The cache omits PLAYER from its object array.
				_emit_object_event(&"player_face_object", {
					"target_index": second_object,
				})
			elif first_object >= 0 and second_object >= 0:
				_emit_object_event(&"object_face_object", {
					"object_index": first_object,
					"target_index": second_object,
				})
		0x6D:
			_emit_object_event(&"object_visibility", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"active": false,
			})
			_emit_object_event(&"object_event_flag", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"active": true,
			})
			_stage_object_event_flag(int(command.get("object_id", 0)), true)
		0x6E:
			_emit_object_event(&"object_visibility", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"active": true,
			})
			_emit_object_event(&"object_event_flag", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"active": false,
			})
			_stage_object_event_flag(int(command.get("object_id", 0)), false)
		0x6F, 0x76:
			## `StartFollow` takes the FIRST operand through `SetLeaderIfVisible`
			## and the second through `SetFollowerIfVisible`, which is the object
			## that takes SPRITEMOVEDATA_FOLLOWING. So the first leads and the
			## second follows; the macro's own operand comments say the reverse.
			## Reading them the other way round leaves the player standing where
			## `NewBarkTown_TeacherBringsYouBackMovement` should have walked them
			## and steps the rival out of the cell he pushed the player from.
			_emit_object_event(&"object_follow", {
				"object_index": _object_index_from_id(int(command.get("object_id_2", 0))),
				"target_index": _object_index_from_id(int(command.get("object_id", 0))),
				"exact": source_opcode == 0x6F,
			})
		0x70:
			_emit_object_event(&"object_stop_follow", {})
		0x71:
			_emit_object_event(&"object_position", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"cell": Vector2i(int(command.get("x", 0)), int(command.get("y", 0))),
			})
		0x72:
			_emit_object_event(&"object_write_position", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
			})
		0x75:
			_emit_object_event(&"object_facing", {
				"object_index": _object_index_from_id(int(command.get("object_id", 0))),
				"facing": int(command.get("facing", Gen2WorldSprite.FACING_DOWN)),
			})
		_:
			return {}
	return {"ok": true}


func _stage_item_delta(item: int, delta: int) -> Dictionary:
	if item > 0:
		_last_item = item
	if item <= 0 or delta == 0:
		_script_value = 1 if delta >= 0 else 0
		return {"ok": true}
	var current: int = _item_quantity(item)
	var next: int = current + delta
	if next < 0:
		_script_value = 0
		_emit_runtime_event(&"item_change_rejected", {
			"item": item, "quantity": abs(delta), "available": current,
		})
		return {"ok": true}
	if delta > 0 and data != null and state != null:
		var owned: Dictionary = state.items()
		for staged_item: Variant in _staged_items:
			owned[int(staged_item)] = int(_staged_items[staged_item])
		var receive: Dictionary = Gen2WorldPack.receive_check(data, owned, item, delta)
		if not bool(receive.get("ok", false)):
			_script_value = 0
			_emit_runtime_event(&"item_change_rejected", {
				"item": item, "quantity": delta, "available": receive.get("available", 0),
				"reason": receive.get("reason", &"item_receive_rejected"),
			})
			return {"ok": true, "accepted": false, "reason": receive.get("reason", &"item_receive_rejected")}
	_staged_items[item] = next
	_script_value = 1
	_emit_runtime_event(&"item_changed", {
		"item": item, "quantity": abs(delta), "total": next,
		"direction": &"give" if delta > 0 else &"take",
	})
	return {"ok": true}


func _stage_money_delta(account: int, amount: int, give: bool) -> Dictionary:
	if account < 0 or amount < 0:
		return {"ok": false, "reason": &"invalid_money_command"}
	var current: int = _money_balance(account)
	var next: int = current + amount if give else current - amount
	if next < 0:
		_script_value = 0
		_emit_runtime_event(&"money_change_rejected", {
			"account": account, "amount": amount, "available": current,
		})
		return {"ok": true}
	_staged_money[account] = next
	_script_value = 1
	_emit_runtime_event(&"money_changed", {
		"account": account, "amount": amount, "balance": next,
		"direction": &"give" if give else &"take",
	})
	return {"ok": true}


func _stage_coins_delta(amount: int, give: bool) -> Dictionary:
	if amount < 0:
		return {"ok": false, "reason": &"invalid_coins_command"}
	var current: int = _coins_value()
	var next: int = current + amount if give else current - amount
	if next < 0:
		_script_value = 0
		_emit_runtime_event(&"coins_change_rejected", {
			"amount": amount, "available": current,
		})
		return {"ok": true}
	_staged_coins = next
	_script_value = 1
	_emit_runtime_event(&"coins_changed", {
		"amount": amount, "balance": next,
		"direction": &"give" if give else &"take",
	})
	return {"ok": true}


func _stage_menu(two_dimensional: bool, command: Dictionary) -> Dictionary:
	if _loaded_menu.is_empty():
		return {"ok": false, "reason": &"menu_header_missing", "command": command}
	if _loaded_menu.has("decode_error"):
		return {
			"ok": false,
			"reason": &"menu_data_invalid",
			"details": _loaded_menu.get("decode_error", ""),
		}
	_pending = {
		"type": &"menu",
		"menu_kind": &"2d" if two_dimensional else &"vertical",
		"header": _loaded_menu.duplicate(true),
		"options": _loaded_menu.get("options", []).duplicate(true),
		"text": _standing_text,
		"source": _request.duplicate(true),
	}
	return {"ok": true}


func _stage_audio_request(kind: StringName, values: Dictionary) -> Dictionary:
	var event: Dictionary = {"kind": kind}
	for key: Variant in values:
		event[key] = values[key]
	return _stage_runtime_request(&"audio_requested", event)


func _phone_contact_registered(contact: int) -> bool:
	if _staged_phone_contacts.has(contact):
		return bool(_staged_phone_contacts[contact])
	return state != null and state.has_phone_contact(contact)


func _phone_contact_candidate() -> Dictionary:
	var candidate: Dictionary = state.phone_contacts() if state != null else {}
	for raw_contact: Variant in _staged_phone_contacts:
		var contact: int = int(raw_contact)
		if bool(_staged_phone_contacts[raw_contact]):
			candidate[contact] = true
		else:
			candidate.erase(contact)
	return candidate


func _stage_phone_contact(contact: int, add: bool = true) -> Dictionary:
	if data == null or contact < 0 or contact >= data.world_phone_contact_count():
		return {"ok": false, "reason": &"invalid_phone_contact", "contact": contact}
	if add:
		if _phone_contact_registered(contact):
			_script_value = PHONE_CONTACTS_FULL
			_emit_runtime_event(&"phone_contact_changed", {
				"contact": contact, "added": false, "result": _script_value,
			})
			return {"ok": true, "added": false, "result": _script_value}
		var candidate: Dictionary = _phone_contact_candidate()
		if candidate.size() >= Gen2WorldState.PHONE_CONTACT_CAPACITY:
			_script_value = PHONE_CONTACTS_FULL
			_emit_runtime_event(&"phone_contact_changed", {
				"contact": contact, "added": false, "result": _script_value,
			})
			return {"ok": true, "added": false, "result": _script_value}
		_staged_phone_contacts[contact] = true
		_script_value = PHONE_CONTACT_GOT
		_emit_runtime_event(&"phone_contact_changed", {
			"contact": contact, "added": true, "result": _script_value,
		})
		return {"ok": true, "added": true, "result": _script_value}
	if not _phone_contact_registered(contact):
		_script_value = 1
		_emit_runtime_event(&"phone_contact_changed", {
			"contact": contact, "added": false, "removed": false, "result": _script_value,
		})
		return {"ok": true, "removed": false, "result": _script_value}
	_staged_phone_contacts[contact] = false
	_script_value = 0
	_emit_runtime_event(&"phone_contact_changed", {
		"contact": contact, "added": false, "removed": true, "result": _script_value,
	})
	return {"ok": true, "removed": true, "result": _script_value}


func _stage_phone_choice(contact: int) -> Dictionary:
	_pending = {
		"type": &"choice",
		"command": &"askforphonenumber",
		"choices": [&"accept", &"refuse"],
		"contact": contact,
		"source": _request.duplicate(true),
	}
	return {"ok": true}


## Holds the script until the stream an `applymovement` just queued has been
## drawn. The cells committed when the command applied, exactly as the source
## commits them in `InitStep`; what is left is the drawing, and the source waits
## for it (`WaitScriptMovement`).
func _stage_movement_wait(values: Dictionary = {}) -> Dictionary:
	var wait: Dictionary = {
		"type": &"wait",
		"wait": WAIT_MOVEMENT,
		"source": _request.duplicate(true),
	}
	for key: Variant in values:
		wait[key] = values[key]
	_pending = wait
	return {"ok": true}


## Holds it for a counted number of hardware frames.
func _stage_frame_wait(frames: int, values: Dictionary = {}) -> Dictionary:
	var wait: Dictionary = {
		"type": &"wait",
		"wait": WAIT_FRAMES,
		"frames": maxi(0, frames),
		"source": _request.duplicate(true),
	}
	for key: Variant in values:
		wait[key] = values[key]
	_pending = wait
	return {"ok": true}


func _stage_runtime_request(kind: StringName, values: Dictionary) -> Dictionary:
	_pending = {
		"type": &"runtime_request",
		"request": {"kind": kind, "values": values.duplicate(true)},
		"source": _request.duplicate(true),
	}
	return {"ok": true}


## engine/overworld/decorations.asm's DescribeDecoration dispatch. These
## scripts are local to the current map. They do not ask a host to interpret a
## decoration; only the poster's DECO_TOWN_MAP branch reaches special 38.
const DECODESC_POSTER: int = 0
const DECODESC_LEFT_DOLL: int = 1
const DECODESC_RIGHT_DOLL: int = 2
const DECODESC_BIG_DOLL: int = 3
const DECODESC_CONSOLE: int = 4
const DECO_TOWN_MAP: int = 0x10
const DECO_PIKACHU_POSTER: int = 0x11
const DECO_CLEFAIRY_POSTER: int = 0x12
const DECO_JIGGLYPUFF_POSTER: int = 0x13


func _stage_decoration_description(description: int) -> Dictionary:
	match description:
		DECODESC_POSTER:
			var poster: int = state.maptile_decoration(&"poster") if state != null else 0
			match poster:
				DECO_TOWN_MAP:
					_stage_internal_text("It's a town map.", false)
					_pending["special_after_text"] = SPECIAL_OVERWORLD_TOWN_MAP
					return {"ok": true}
				DECO_PIKACHU_POSTER:
					return _stage_internal_text("It's a poster of a\ncute PIKACHU.", false)
				DECO_CLEFAIRY_POSTER:
					return _stage_internal_text("It's a poster of a\ncute CLEFAIRY.", false)
				DECO_JIGGLYPUFF_POSTER:
					return _stage_internal_text("It's a poster of a\ncute JIGGLYPUFF.", false)
				_:
					return {"ok": true}
		DECODESC_BIG_DOLL:
			return _stage_internal_text("A giant doll! It's\nfluffy and cuddly.", false)
		DECODESC_LEFT_DOLL, DECODESC_RIGHT_DOLL, DECODESC_CONSOLE:
			return _stage_internal_text("It's an adorable decoration.", false)
	return _fail(&"invalid_decoration_description", {"description": description})


func _stage_trainer_approach() -> void:
	_stage_runtime_request(&"trainer_approach_requested", {
		"object_index": int(_request.get("object_index", -1)),
		"distance": int(_request.get("distance", 0)),
		"direction": _request.get("direction", Vector2i.ZERO),
	})


## `FindThatSpecies`, and `CheckOwnMon`'s ID and OT test on top of it when
## [param own_only]. The walk is `wPartySpecies`, so an EGG's slot carries EGG
## rather than what is inside it and cannot match a species.
func _party_slot_of_species(party: Dictionary, species: int, own_only: bool) -> int:
	var listed: Array = party.get("species", [])
	var eggs: Array = party.get("eggs", [])
	var own_ot: Array = party.get("own_ot", [])
	for slot: int in listed.size():
		if slot < eggs.size() and bool(eggs[slot]):
			continue
		if int(listed[slot]) != species:
			continue
		if own_only and (slot >= own_ot.size() or not bool(own_ot[slot])):
			return -1
		return slot
	return -1


## `wXCoord`/`wYCoord`, mirrored onto the request the way the party count is.
func _player_cell() -> Vector2i:
	var standing: Variant = _request.get("player_cell", Vector2i(-1, -1))
	return standing if standing is Vector2i else Vector2i(-1, -1)


func _read_runtime_variable(variable: int) -> Dictionary:
	var clock: Dictionary = _request.get("clock", {})
	var hour: int = int(clock.get("hour", _clock_hour()))
	var day: int = int(clock.get("day", 0))
	match variable:
		0x01: # VAR_PARTYCOUNT
			var party: Dictionary = _request.get("party", {})
			if party.is_empty():
				return {
					"ok": false, "reason": &"missing_party_summary", "variable": variable,
				}
			_script_value = int(party.get("count", 0))
		0x04: # VAR_TIMEOFDAY
			_script_value = Gen2WorldClock.new(hour, 0, day).time_of_day()
		0x07: # VAR_BADGES
			_script_value = _staged_badge_count()
		0x0A: # VAR_HOUR
			_script_value = hour
		0x0B: # VAR_WEEKDAY
			_script_value = day
		0x09: # VAR_FACING
			_script_value = int(_request.get("facing", -1))
		0x0C: # VAR_MAPGROUP
			_script_value = int(_request.get("map_group", -1))
		0x0D: # VAR_MAPNUMBER
			_script_value = int(_request.get("map_number", -1))
		0x0E: # VAR_UNOWNCOUNT
			## `.count_unown` walks wUnownDex and stops at the first empty slot,
			## which is the size of the list here. All three Ruins of Alph
			## scientists and the Kabuto chamber's wall read it.
			_script_value = state.unown_caught_count() if state != null else 0
		0x0F: # VAR_ENVIRONMENT
			_script_value = int(_request.get("environment", -1))
		0x05: # VAR_DEXCAUGHT
			_script_value = state.caught_count() if state != null else 0
		0x06: # VAR_DEXSEEN
			_script_value = state.seen_count() if state != null else 0
		0x10: # VAR_BOXSPACE
			## `.BoxFreeSpace` opens SRAM for the count; the party mirror carries
			## it here for the same reason it carries VAR_PARTYCOUNT, and an
			## absent mirror fails rather than inventing an empty box.
			var storage: Dictionary = _request.get("party", {})
			if not storage.has("box_free_space"):
				return {
					"ok": false, "reason": &"missing_party_summary", "variable": variable,
				}
			_script_value = int(storage.get("box_free_space", 0))
		0x12: # VAR_XCOORD
			_script_value = _player_cell().x
		0x13: # VAR_YCOORD
			_script_value = _player_cell().y
		0x14: # VAR_SPECIALPHONECALL
			_script_value = _current_special_phone_call()
		0x16: # VAR_KURT_APRICORNS
			## _GetVarAction reads wKurtApricornQuantity, saved player data whose
			## only writer is SelectApricornForKurt. A selection made inside this
			## invocation shadows the committed byte, as the WRAM write does.
			_script_value = _kurt_apricorn_quantity()
		0x17: # VAR_CALLERID
			_script_value = int(_phone_context.get("caller_id", -1))
		_:
			return {
				"ok": false,
				"reason": &"unsupported_runtime_variable",
				"variable": variable,
			}
	return {"ok": true}


func _load_runtime_variable(variable: int, value: int) -> Dictionary:
	## Phone scripts use LOADVAR for the two runtime values that are not
	## ordinary world-state variables. Battles also load VAR_BATTLETYPE before
	## STARTBATTLE so a source can explicitly permit a non-blackout loss.
	match variable:
		0x03: # VAR_BATTLETYPE
			if _battle_setup.is_empty():
				_loaded_battle_type = value
			else:
				_battle_setup["battle_type"] = value
				_battle_setup["can_lose"] = value == 1
		0x14: # VAR_SPECIALPHONECALL
			if not _phone_context.is_empty():
				_phone_context["special_call_id"] = value
			_staged_special_phone_call = value
			_has_staged_special_phone_call = true
		0x17: # VAR_CALLERID
			_phone_context["caller_id"] = value
		_:
			return {
				"ok": false,
				"reason": &"unsupported_runtime_loadvar",
				"variable": variable,
				"value": value,
			}
	return {"ok": true}


func _current_special_phone_call() -> int:
	## A staged specialphonecall updates the script-visible variable before
	## the transaction commits, just as the source WRAM byte does.
	if _has_staged_special_phone_call:
		return _staged_special_phone_call
	var context_value: int = int(_phone_context.get("special_call_id", 0))
	if context_value != 0:
		return context_value
	var request_value: Variant = _request.get("special_phone_call", 0)
	if request_value is int or request_value is float:
		if int(request_value) != 0:
			return int(request_value)
	return state.pending_special_phone_call() if state != null else 0


func _kurt_apricorn_quantity() -> int:
	if _has_staged_kurt_apricorn_quantity:
		return _staged_kurt_apricorn_quantity
	if _request.has("kurt_apricorn_quantity"):
		return clampi(int(_request["kurt_apricorn_quantity"]), 0, 0xFF)
	return state.kurt_apricorn_quantity() if state != null else 0


func _clock_hour() -> int:
	var clock: Dictionary = _request.get("clock", {})
	return clampi(int(clock.get("hour", 0)), 0, 23)


func _clock_minute() -> int:
	var clock: Dictionary = _request.get("clock", {})
	return clampi(int(clock.get("minute", 0)), 0, 59)


## `HealMachineAnim`'s sounds and the frame of its own wait each is played on.
## `.LoadBallsOntoMachine` plays one effect a ball and then delays thirty frames,
## so ball zero sounds on the frame the routine starts. `.PlayHealMusic` starts
## `MUSIC_HEAL` under `.FlashPalettes8Times` rather than after it; the Hall of
## Fame's sequence plays one effect there instead and a second once the flashes
## are done. Its `WaitSFX` between the two is not spent, like the other two the
## world leaves unspent.
static func heal_machine_sounds(machine_type: int, balls: int) -> Array:
	if balls <= 0:
		return []
	var schedule: Array = []
	for ball: int in balls:
		schedule.append({
			"frame": ball * HEAL_MACHINE_BALL_FRAMES,
			"kind": &"sound", "index": SFX_SECOND_PART_OF_ITEMFINDER,
		})
	var flashes_at: int = balls * HEAL_MACHINE_BALL_FRAMES
	if machine_type == HEAL_MACHINE_HALL_OF_FAME:
		schedule.append({
			"frame": flashes_at, "kind": &"sound", "index": SFX_GAME_FREAK_LOGO_GS,
		})
		schedule.append({
			"frame": flashes_at + HEAL_MACHINE_FLASH_FRAMES,
			"kind": &"sound", "index": SFX_BOOT_PC,
		})
	else:
		schedule.append({"frame": flashes_at, "kind": &"music", "index": MUSIC_HEAL})
	return schedule


## `ItemFinder.ItemfinderSound`, which its found branch runs as a `callasm`
## before the line: four passes of `WaitPlaySFX SFX_SECOND_PART_OF_ITEMFINDER`
## and `WaitPlaySFX SFX_TRANSACTION`. Each holds until the four effect channels
## are free, so the eight are a run rather than eight sounds on one frame, and
## `.Script_FoundNothing` has none of it.
static func itemfinder_sounds() -> Array:
	var schedule: Array = []
	for _pass: int in ITEMFINDER_SFX_PASSES:
		schedule.append({
			"kind": &"sound", "wait": true, "index": SFX_SECOND_PART_OF_ITEMFINDER,
		})
		schedule.append({"kind": &"sound", "wait": true, "index": SFX_TRANSACTION})
	return schedule


## [param special] is the Crystal-canonical index from
## Gen2WorldScript.special_index(), not the raw stream byte, so the payloads
## below report that index on both profiles.
func _execute_special(special: int) -> Dictionary:
	## SPECIAL is a shared cartridge dispatch table. Phone routines are only one
	## part of it; map callbacks and the new-game clock setup use the same table.
	match special:
		SPECIAL_OVERWORLD_TOWN_MAP:
			return _stage_runtime_request(&"town_map_requested", {
				"special": special,
				"landmark": int(_request.get("landmark", 0)),
			})
		SPECIAL_PLAYERS_HOUSE_PC:
			return _stage_runtime_request(&"pc_requested", {
				"special": special,
				"mode": &"players_house",
			})
		SPECIAL_POKEMON_CENTER_PC:
			return _stage_runtime_request(&"pc_requested", {
				"special": special,
				"mode": &"pokemon_center",
			})
		SPECIAL_SET_DAY_OF_WEEK:
			_stage_day_of_week_menu()
			return {"ok": true}
		SPECIAL_INITIAL_SET_DST_FLAG:
			_staged_dst_enabled = true
			_has_staged_dst = true
			_stage_dst_confirmation_text(true)
			return {"ok": true}
		SPECIAL_INITIAL_CLEAR_DST_FLAG:
			_staged_dst_enabled = false
			_has_staged_dst = true
			_stage_dst_confirmation_text(false)
			return {"ok": true}
		SPECIAL_PLAY_MAP_MUSIC, SPECIAL_RESTART_MAP_MUSIC:
			# Entering a map with the music already playing does not restart it,
			# which is why crossing a route boundary is one continuous track.
			# RestartMapMusic exists to override exactly that, so it says so.
			return _stage_audio_request(&"map_music", {
				"special": special,
				"restart": special == SPECIAL_RESTART_MAP_MUSIC,
			})
		SPECIAL_FADE_OUT_MUSIC:
			_emit_runtime_event(&"music_fadeout_requested", {"special": special})
		36:
			return _stage_runtime_request(&"rival_name_requested", {
				"special": special, "default_name": "SILVER",
			})
		27:
			## HealParty is a save-owned transaction. It is deliberately a host
			## request so HP, status and PP are changed together with the selected
			## project save.
			return _stage_runtime_request(&"party_heal_requested", {"special": special})
		SPECIAL_HEAL_MACHINE_ANIM:
			## wScriptVar selects the machine's screen position: 0 Pokemon Center,
			## 1 Elm's Lab, 2 Hall of Fame. A preceding SETVAL loads it. Nothing
			## here changes state, but the routine is not free: it spends thirty
			## frames a ball and `.FlashPalettes8Times`' eighty, with a sound on
			## each ball, so the script waits for it the way the cartridge does.
			var machine_type: int = clampi(_script_value, 0, HEAL_MACHINE_HALL_OF_FAME)
			var balls: int = int((_request.get("party", {}) as Dictionary).get("count", 0))
			var sounds: Array = heal_machine_sounds(machine_type, balls)
			_emit_runtime_event(&"presentation_special_applied", {
				"special": special, "kind": &"heal_machine_anim",
				"machine_type": machine_type,
				"balls": balls,
				"sounds": sounds.duplicate(true),
			})
			## `ld a, [wPartyCount] / and a / ret z`: an empty party leaves the
			## machine alone and spends nothing.
			if balls > 0:
				return _stage_frame_wait(
					balls * HEAL_MACHINE_BALL_FRAMES + HEAL_MACHINE_FLASH_FRAMES,
					{"special": special, "kind": &"heal_machine_anim"}
				)
		SPECIAL_MAGNET_TRAIN:
			## engine/events/magnet_train.asm's MagnetTrain is scroll positions,
			## graphics, music and a VBlank cutscene handler. It reads
			## wScriptVar for the direction and writes nothing the overworld can
			## observe; the warp itself is the `warpcheck` that follows it.
			_emit_runtime_event(&"presentation_special_applied", {
				"special": special, "kind": &"magnet_train",
				"to_goldenrod": _script_value != 0,
			})
		SPECIAL_PROF_OAKS_PC_BOOT:
			## engine/events/prof_oaks_pc.asm's ProfOaksPCBoot prints, counts the
			## set bits in wPokedexSeen and wPokedexCaught for `Rate`, plays that
			## rating's sound and waits for A or B. Presentation only: it writes
			## nothing, so the script runs straight on to its own `end` and
			## [Gen2ProfOaksPC] is handed the counts by whoever draws this.
			_emit_runtime_event(&"presentation_special_applied", {
				"special": special, "kind": &"prof_oaks_pc_boot",
			})
		SPECIAL_CHECK_POKERUS:
			var party: Dictionary = _request.get("party", {})
			if party.is_empty():
				return {"ok": false, "reason": &"missing_party_summary", "special": special}
			_script_value = 1 if bool(party.get("pokerus", false)) else 0
		SPECIAL_SNORLAX_AWAKE:
			## Two reads and nothing else: the track in wMapMusic and the cell the
			## player stands on. The Poke Flute channel reaches wMapMusic through
			## StartRadioStation and stays there because closing the Pokegear
			## restores the map's music only for its two sentinel ids.
			var cell: Vector2i = _player_cell()
			_script_value = 1 if state != null \
				and state.map_music() == Gen2WorldRadio.MUSIC_POKE_FLUTE_CHANNEL \
				and cell in SNORLAX_PROXIMITY_CELLS else 0
		SPECIAL_FADE_OUT_TO_WHITE, SPECIAL_BATTLE_TOWER_FADE, SPECIAL_FADE_OUT_TO_BLACK, \
		SPECIAL_FADE_IN_FROM_WHITE, SPECIAL_FADE_IN_FROM_BLACK:
			## `FadeOutToWhite` is 46 in both pins, since Crystal's inserted
			## `BattleTowerFade` sits at 47, so it needs no profile split;
			## `FadeInFromWhite` is 49 here and 48 in Gold/Silver, which
			## special_index() already normalizes (maps/OlivineLighthouse6F.asm's
			## Amphy cure runs 46 then 49).
			##
			## Each of the five is `GetTimePalFade` and then four rows of the
			## fade table, and none of them is free: `ConvertTimePals*HL` spends
			## `ld c, 2` on every row and `BattleTowerFade`'s own loop `ld c, 7`,
			## so the script holds for the whole walk the way it does on the
			## cartridge. `FillWhiteBGColor` is the two white fades' alone.
			var orders: Array[int] = FADE_ORDERS_OF[special]
			var step_frames: int = Gen2WorldPalette.BATTLE_TOWER_FADE_STEP_FRAMES \
				if special == SPECIAL_BATTLE_TOWER_FADE \
				else Gen2WorldPalette.FADE_STEP_FRAMES
			_emit_runtime_event(&"presentation_special_applied", {
				"special": special, "kind": &"palette_fade",
				"orders": orders.duplicate(),
				"step_frames": step_frames,
				"white_fill": special in FADE_WHITE_FILL_SPECIALS,
			})
			return _stage_frame_wait(orders.size() * step_frames, {
				"special": special, "kind": &"palette_fade",
			})
		51, 52, 53, 55, 56, 94, 152, 157, 158, 164:
			## Sprite reload, palette reload and the dummied trainer-ranking
			## bookkeeping affect presentation or source-only counters, not
			## scene-free state. `LoadUsedSpritesGFX` (94), `UpdateSprites` (55),
			## `UpdatePlayerSprite` (56), `ReloadSpritesNoPalettes` (51) and
			## `RefreshSprites` (158) reload the sprite set a `variablesprite`
			## just changed. `ClearBGPalettes` (52), `UpdateTimePals` (53),
			## `SetPlayerPalette` (152) and `LoadMapPalettes` (164) are the
			## palette pair `BugContestResultsWarpScript` and the day/night
			## scripts open with; the renderer takes its palettes from the map
			## and the clock, so all four are presentation here too.
			_emit_runtime_event(&"presentation_special_applied", {"special": special})
		95, 100:
			## `PlaySlowCry` (95) is `LoadCry` with the record's own pitch
			## lowered by `$140` and its length raised by `$60`, and
			## `PlayCurMonCry` (100) is `PlayMonCry` straight. Neither writes
			## anything back, so what they owe is the sound and the `WaitSFX`
			## each ends on, which is `Script_cry`'s own request.
			##
			## They do not read the same byte. 95 is `ld a, [wScriptVar]`, which
			## the `setval` in front of it has just set; 100 is
			## `ld a, [wCurPartySpecies]`, and all four of its scripts are a
			## grooming routine's, which leaves a `HappinessData_*` row rather
			## than a species in wScriptVar.
			return _stage_audio_request(&"cry", {
				"special": special,
				"species": _script_value if special == 95 else _cur_party_species,
				"slow": special == 95,
			})
		59:
			## `SpecialWaitSFX` is `WaitSFX`: it holds until the four effect
			## channels are free rather than spending a counted number of
			## frames, which is `Script_waitsfx`'s own request.
			return _stage_audio_request(&"sound_wait", {"special": special})
		66, 67:
			## `FindPartyMonThatSpecies` and its ID-checking twin. Both answer
			## TRUE/FALSE in wScriptVar off the species wScriptVar was loaded
			## with; the second adds `CheckOwnMon`'s ID and OT test on the slot
			## the first one found.
			var party: Dictionary = _request.get("party", {})
			if party.is_empty():
				return {"ok": false, "reason": &"missing_party_summary", "special": special}
			_script_value = 1 if _party_slot_of_species(
				party, _script_value, special == 67
			) >= 0 else 0
		89:
			## `GetFirstPokemonHappiness` walks past every EGG in the list and
			## answers the first hatched member's happiness byte, naming that
			## member in the buffer its two boxes print.
			var happy_party: Dictionary = _request.get("party", {})
			if happy_party.is_empty():
				return {"ok": false, "reason": &"missing_party_summary", "special": special}
			var eggs: Array = happy_party.get("eggs", [])
			var happiness: Array = happy_party.get("happiness", [])
			var names: Array = happy_party.get("names", [])
			var slot: int = 0
			while slot < eggs.size() and bool(eggs[slot]):
				slot += 1
			_script_value = int(happiness[slot]) if slot < happiness.size() else 0
			if slot < names.size():
				_set_text_buffer(3, String(names[slot]), &"first_party_mon", {
					"special": special, "slot": slot,
				})
		90:
			## `CheckFirstMonIsEgg` reads slot zero alone, and names it whether
			## or not it is an egg: `GetPokemonName` runs on both branches.
			var first_party: Dictionary = _request.get("party", {})
			if first_party.is_empty():
				return {"ok": false, "reason": &"missing_party_summary", "special": special}
			var first_eggs: Array = first_party.get("eggs", [])
			var first_names: Array = first_party.get("names", [])
			_script_value = 1 if not first_eggs.is_empty() and bool(first_eggs[0]) else 0
			if not first_names.is_empty():
				_set_text_buffer(3, String(first_names[0]), &"first_party_mon", {
					"special": special, "slot": 0,
				})
		102:
			## `GameboyCheck` reports which console the game booted on. This one
			## is a Game Boy Color every time, since every screen here is drawn
			## in the CGB palettes `hCGB` selects.
			_script_value = GBCHECK_CGB
		150, 151:
			## `MonCheck` answers whether the player owns the species in
			## wScriptVar and `BeastsCheck` runs the same test on all three
			## beasts, leaving the last species it asked about behind in
			## wScriptVar when one is missing.
			var owner_party: Dictionary = _request.get("party", {})
			if owner_party.is_empty():
				return {"ok": false, "reason": &"missing_party_summary", "special": special}
			var owned: Array = owner_party.get("owned_species", [])
			if special == 151:
				_script_value = 1 if owned.has(_script_value) else 0
			else:
				_script_value = 1
				for beast: int in BEAST_SPECIES:
					if not owned.has(beast):
						_script_value = beast
						break
		SPECIAL_INIT_ROAM_MONS:
			## InitRoamMons seeds the roam structs with Raikou and Entei at
			## level 40 on their starting maps. Gen2WorldAPI.open() already
			## seeds the same imported records, and ensure_roaming_mons() keeps
			## positions a player has already moved, so this reports rather than
			## resetting a beast that is already loose.
			if state != null and data != null:
				state.ensure_roaming_mons(data.world_roaming_mons())
			_emit_runtime_event(&"roaming_mons_initialized", {
				"special": special,
				"count": state.roaming_mons().size() if state != null else 0,
			})
		SPECIAL_BILLS_GRANDFATHER, SPECIAL_OLDER_HAIRCUT_BROTHER, \
		SPECIAL_YOUNGER_HAIRCUT_BROTHER, SPECIAL_DAISYS_GROOMING:
			## `engine/events/haircut.asm`. All four open `SelectMonFromParty`
			## and nothing else: every box either routine's script shows is the
			## script's own, so the host owes a party list and an answer.
			return _stage_runtime_request(&"party_selection_requested", {
				"special": special,
				"routine": GROOMING_TABLE_OF.get(special, &"bills_grandfather"),
			})
		SPECIAL_DISPLAY_COIN_CASE_BALANCE, SPECIAL_DISPLAY_MONEY_AND_COIN_BALANCE, \
		SPECIAL_PLACE_MONEY_TOP_RIGHT:
			## Three tilemap writes and a `ret`. The window stands over the map
			## until `closetext` redraws it, so a script that spends money
			## between two of them (the haircut brothers' `takemoney`) draws the
			## second over the first.
			_money_window = MONEY_WINDOW_KIND_OF[special]
			_emit_runtime_event(&"money_window_opened", {
				"special": special,
				"kind": _money_window,
				"money": _money_balance(ACCOUNT_YOUR_MONEY),
				"coins": _coins_value(),
			})
		SPECIAL_DAY_CARE_MAN, SPECIAL_DAY_CARE_LADY, SPECIAL_DAY_CARE_MAN_OUTSIDE, \
		SPECIAL_DAY_CARE_MON_1, SPECIAL_DAY_CARE_MON_2:
			## Each of the five owns its own boxes, and the two counters own the
			## party list and both `YesNoBox`es as well, so the whole routine is
			## one host request the way `NameRater` is.
			return _stage_runtime_request(&"day_care_requested", {
				"special": special,
				"role": DAY_CARE_ROLE_OF[special],
			})
		SPECIAL_NAME_RATER:
			return _stage_runtime_request(&"name_rater_requested", {
				"special": special,
			})
		SPECIAL_MOVE_DELETION:
			return _stage_runtime_request(&"move_deleter_requested", {
				"special": special,
			})
		SPECIAL_SELECT_APRICORN_FOR_KURT:
			## Both of the special's boxes are the host's; it answers with the
			## chosen apricorn and how many of it, and a backed-out box is the
			## source's own `wScriptVar = 0`.
			return _stage_runtime_request(&"apricorn_selection_requested", {
				"special": special,
			})
		SPECIAL_GIVE_PARK_BALLS:
			## `GiveParkBalls` clears wContestMon, loads twenty balls and starts
			## the timer. The flag itself is the script's own `setflag`, which
			## has already run by here.
			_emit_runtime_event(&"bug_contest_started", {"special": special})
		SPECIAL_SELECT_RANDOM_BUG_CONTESTANTS:
			## Five of the ten contestant flags set, which is both who competes
			## in the judging and which sprites the park does not draw.
			_emit_runtime_event(&"bug_contestants_selected", {"special": special})
		SPECIAL_CONTEST_DROP_OFF_MONS:
			## `ContestDropOffMons` answers 1 when the lead is fainted, which is
			## the one branch its callers read, and otherwise masks the party to
			## its first member.
			var contest_party: Dictionary = _request.get("party", {})
			if contest_party.is_empty():
				return {"ok": false, "reason": &"missing_party_summary", "special": special}
			var lead_fainted: bool = bool(contest_party.get("lead_fainted", false))
			_script_value = 1 if lead_fainted else 0
			if not lead_fainted:
				_emit_runtime_event(&"contest_mons_dropped_off", {
					"special": special,
					"second_species": int(contest_party.get("second_species", 0)),
				})
		SPECIAL_CONTEST_RETURN_MONS:
			_emit_runtime_event(&"contest_mons_returned", {"special": special})
		SPECIAL_CHECK_PARTY_FULL_AFTER_CONTEST:
			## `CheckPartyFullAfterContest` answers whether the Pokemon caught in
			## the contest can be taken home, which is a party slot or a box slot.
			var after_party: Dictionary = _request.get("party", {})
			if after_party.is_empty():
				return {"ok": false, "reason": &"missing_party_summary", "special": special}
			_script_value = 1 if bool(after_party.get("storage_full", false)) else 0
		SPECIAL_BUG_CONTEST_JUDGING:
			## The judging prints three placings and leaves the player's own in
			## wScriptVar, which the results script branches on.
			return _stage_runtime_request(&"bug_contest_judging_requested", {
				"special": special,
			})
		SPECIAL_ACTIVATE_FISHING_SWARM:
			_emit_runtime_event(&"phone_special_requested", {
				"special": special, "kind": &"activate_fishing_swarm",
				"species": _script_value,
			})
		SPECIAL_TOGGLE_MAPTILE_DECORATIONS:
			_apply_maptile_decorations()
			_emit_runtime_event(&"decoration_callback_applied", {
				"special": special,
				"kind": &"toggle_maptile_decorations",
				"decorations": state.maptile_decorations() if state != null else {},
			})
		SPECIAL_TOGGLE_DECORATIONS_VISIBILITY:
			## With the default zero decoration selections, ToggleDecorationVisibility
			## sets each object event flag and the renderer removes those objects.
			for flag: int in [
				EVENT_PLAYERS_HOUSE_2F_CONSOLE,
				EVENT_PLAYERS_HOUSE_2F_DOLL_1,
				EVENT_PLAYERS_HOUSE_2F_DOLL_2,
				EVENT_PLAYERS_HOUSE_2F_BIG_DOLL,
			]:
				_staged_flags[flag] = true
			_emit_runtime_event(&"decoration_callback_applied", {
				"special": special,
				"kind": &"toggle_decorations_visibility",
				"defaults": true,
			})
		SPECIAL_SLOT_MACHINE:
			return _stage_runtime_request(&"slot_machine_requested", {
				"special": special,
				## `Slots_InitBias`' own `ld a, [wScriptVar] / and a`, which is
				## the only thing the operand decides.
				"lucky": _script_value != 0,
				"coins": _coins_value(),
			})
		SPECIAL_UNOWN_PUZZLE:
			return _stage_runtime_request(&"unown_puzzle_requested", {
				"special": special,
				## `maskbits NUM_UNOWN_PUZZLES` is what bounds the operand, so a
				## value outside the four wraps rather than failing.
				"puzzle": _script_value & 0x3,
			})
		SPECIAL_DISPLAY_UNOWN_WORDS:
			## The word the wall spells, staged as the text `JoyWaitAorB` holds
			## until a button. A host that can reach the chamber's own tileset
			## draws it as `_DisplayUnownWords_CopyWord`'s 2x2 letter blocks
			## instead ([Gen2UnownWallPage]); the wait it answers is this one.
			var wall_word: String = data.unown_wall_word(_script_value) if data != null \
				else ""
			if wall_word.is_empty():
				return {
					"ok": false,
					"reason": &"unknown_unown_wall",
					"special": special,
					"wall": _script_value,
				}
			## `special` is a StringName tag on a pending text, not the index, so
			## the wall is named under its own key.
			return _stage_internal_text(wall_word, false, {"unown_wall": _script_value})
		SPECIAL_RANDOM_UNSEEN_WILD_MON:
			var rare_species: int = _phone_unseen_rare_species()
			if rare_species <= 0:
				_emit_runtime_event(&"phone_special_requested", {
					"special": special, "kind": &"random_unseen_wild_mon",
					"internal_text": false, "script_value": 1,
				})
				_script_value = 1
			else:
				var rare_name: String = String(data.species(rare_species).get("name", ""))
				_set_text_buffer(1, rare_name, &"phone_unseen_wild_mon", {
					"special": special, "species": rare_species,
				})
				_emit_runtime_event(&"phone_special_requested", {
					"special": special, "kind": &"random_unseen_wild_mon",
					"internal_text": true, "buffer": 1, "value": rare_name,
					"species": rare_species, "script_value": 0,
				})
				_script_value = 0
		SPECIAL_RANDOM_PHONE_WILD_MON:
			var wild_name: String = _phone_wild_mon_name()
			_set_text_buffer(1, wild_name, &"phone_wild_mon", {"special": special})
			_emit_runtime_event(&"phone_special_requested", {
				"special": special, "kind": &"random_phone_wild_mon",
				"buffer": 1, "value": wild_name,
			})
		SPECIAL_RANDOM_PHONE_MON:
			var trainer_mon_name: String = _phone_trainer_mon_name()
			_set_text_buffer(1, trainer_mon_name, &"phone_mon", {"special": special})
			_emit_runtime_event(&"phone_special_requested", {
				"special": special, "kind": &"random_phone_mon",
				"buffer": 1, "value": trainer_mon_name,
			})
		_:
			return {
				"ok": false,
				"reason": &"unsupported_phone_special",
				"special": special,
			}
	return {"ok": true}


## ToggleMaptileDecorations and SetDecorationTile
## (engine/overworld/decorations.asm). Coordinates are changeblock coordinates;
## Gen2WorldAPI applies their padded-buffer conversion.
func _apply_maptile_decorations() -> void:
	var decorations: Dictionary = state.maptile_decorations() if state != null else {}
	var bed_block: int = _decoration_block(&"bed", int(decorations.get(&"bed", 0)))
	var plant_block: int = _decoration_block(&"plant", int(decorations.get(&"plant", 0)))
	var poster_block: int = _decoration_block(&"poster", int(decorations.get(&"poster", 0)))
	var carpet_block: int = _decoration_block(&"carpet", int(decorations.get(&"carpet", 0)))
	if bed_block > 0:
		_emit_runtime_event(&"map_block_changed", {"x": 0, "y": 4, "block": bed_block})
	if plant_block > 0:
		_emit_runtime_event(&"map_block_changed", {"x": 7, "y": 4, "block": plant_block})
	if poster_block > 0:
		_emit_runtime_event(&"map_block_changed", {"x": 6, "y": 0, "block": poster_block})
	if carpet_block > 0:
		for row: Dictionary in [
			{"x": 0, "y": 0, "block": carpet_block},
			{"x": 0, "y": 2, "block": carpet_block + 1},
			{"x": 2, "y": 2, "block": carpet_block + 2},
			{"x": 4, "y": 2, "block": carpet_block + 1},
		]:
			_emit_runtime_event(&"map_block_changed", row)
	_staged_flags[EVENT_PLAYERS_ROOM_POSTER] = poster_block > 0


func _decoration_block(category: StringName, decoration: int) -> int:
	var category_blocks: Dictionary = DECORATION_BLOCKS.get(category, {})
	return int(category_blocks.get(decoration, 0))


func _stage_day_of_week_menu() -> void:
	_pending = {
		"type": &"menu",
		## `SetDayOfWeek` is a dial, not a list: one weekday in a nine-wide box at
		## `hlcoord 9, 3` between two arrows, with `.GetJoypadAction` stepping
		## `wTempDayOfWeek` and A accepting. The selection rules are a wrapping
		## vertical menu's, so only the drawing differs from one.
		"menu_kind": &"spinner",
		"command": &"set_day_of_week",
		"options": WEEKDAY_NAMES.duplicate(),
		"header": {"default": 1, "data_flags": 1 << 5},
		"text": _standing_text,
		"special": &"set_day_of_week",
		"source": _request.duplicate(true),
	}


func _stage_day_of_week_confirmation(day: int) -> void:
	_pending = {
		"type": &"choice",
		"command": &"set_day_of_week_confirmation",
		"choices": [&"yes", &"no"],
		"text": _standing_text,
		"special": &"set_day_of_week_confirmation",
		"day": posmod(day, WEEKDAY_NAMES.size()),
		"source": _request.duplicate(true),
	}


func _stage_dst_confirmation_text(enabled: bool) -> void:
	var clock: Dictionary = _request.get("clock", {})
	var hour: int = clampi(int(clock.get("hour", 0)), 0, 23)
	var minute: int = clampi(int(clock.get("minute", 0)), 0, 59)
	var time_text: String = "%02d:%02d" % [hour, minute]
	_pending = {
		"type": &"text",
		"text": "%s%s,\nis that OK?" % [time_text, " DST" if enabled else ""],
		"special": &"initial_dst_confirmation",
		"source": _request.duplicate(true),
	}


func _phone_contact() -> Dictionary:
	if data == null:
		return {}
	var contact_id: int = int(_phone_context.get(
		"caller_id", _phone_context.get("contact_id", -1)
	))
	return data.world_phone_contact(contact_id)


func _phone_wild_mon_name() -> String:
	var contact: Dictionary = _phone_contact()
	var record: Dictionary = data.world_encounter(
		Gen2WorldEncounter.METHOD_GRASS,
		int(contact.get("map_group", -1)), int(contact.get("map_number", -1))
	) if data != null else {}
	var slots: Variant = record.get("slots", [])
	var hour: int = int((_request.get("clock", {}) as Dictionary).get("hour", 0))
	var time_of_day: int = Gen2WorldClock.new(hour).time_of_day()
	if not slots is Array or time_of_day < 0 or time_of_day >= (slots as Array).size():
		return ""
	var selected: Variant = (slots as Array)[time_of_day]
	if not selected is Array or (selected as Array).size() < 4:
		return ""
	## RandomPhoneWildMon masks the cartridge RNG to select one of the first
	## four grass slots, rather than using the ordinary weighted encounter roll.
	var raw_slot: Variant = (selected as Array)[_random.randi_range(0, 3)]
	if not raw_slot is Dictionary:
		return ""
	var species: int = int((raw_slot as Dictionary).get("species", 0))
	if species <= 0 or data.species(species).is_empty():
		return ""
	return String(data.species(species).get("name", ""))


func _phone_unseen_rare_species() -> int:
	var contact: Dictionary = _phone_contact()
	var record: Dictionary = data.world_encounter(
		Gen2WorldEncounter.METHOD_GRASS,
		int(contact.get("map_group", -1)), int(contact.get("map_number", -1))
	) if data != null else {}
	var slots: Variant = record.get("slots", [])
	if not slots is Array or (slots as Array).is_empty():
		return 0
	## Crystal's routine reads wTimeOfDay but fails to use it when applying
	## the table offset, so the shipped game always examines the morning row.
	var morning: Variant = (slots as Array)[0]
	if not morning is Array or (morning as Array).size() < RomLayout.WILD_GRASS_SLOT_COUNT:
		return 0
	var common_species: Array[int] = []
	for index: int in 4:
		var common: Variant = (morning as Array)[index]
		if common is Dictionary:
			common_species.append(int((common as Dictionary).get("species", 0)))
	for _attempt: int in 128:
		var roll: int = _random.randi() & 0x03
		if roll == 0:
			continue
		var slot_index: int = 4 + roll - 1
		var rare: Variant = (morning as Array)[slot_index]
		if not rare is Dictionary:
			return 0
		var species: int = int((rare as Dictionary).get("species", 0))
		if species <= 0 or common_species.has(species):
			return 0
		if state != null and state.has_seen_species(species):
			return 0
		if data == null or data.species(species).is_empty():
			return 0
		return species
	return 0


func _phone_trainer_mon_name() -> String:
	var contact: Dictionary = _phone_contact()
	var trainer_group: int = int(contact.get("trainer_class", 0))
	var trainer_id: int = int(contact.get("trainer_number", 0)) - 1
	var party: Array = data.trainer_party(trainer_group, trainer_id).get("party", []) if data != null else []
	var candidates: Array[int] = []
	for mon: Dictionary in party:
		var party_species: int = int(mon.get("species", 0))
		if party_species > 0 and data.species(party_species).size() > 0:
			candidates.append(party_species)
	if candidates.is_empty():
		return ""
	var species: int = candidates[_random.randi_range(0, candidates.size() - 1)]
	return String(data.species(species).get("name", ""))


func _stage_warp_facing_request(command: Dictionary) -> Dictionary:
	var warp: Dictionary = {
		"facing": int(command.get("facing", Gen2WorldSprite.FACING_DOWN)),
		"map_group": int(command.get("map_group", 0)),
		"map_number": int(command.get("map_number", 0)),
		"x": int(command.get("x", 0)), "y": int(command.get("y", 0)),
	}
	_events.append({"type": &"player_facing_requested", "facing": warp["facing"]})
	return _stage_warp(command)


## `wRunningTrainerBattleScript` as this script sees it: a value staged during
## the run wins over the committed one, since a script that stages false has
## cleared the flag for everything after it. Reading only the "has a staged
## value" side made `endifjustbattled` true whenever anything had touched it.
func _just_battled() -> bool:
	if _has_staged_just_battled:
		return _staged_just_battled
	return state != null and state.just_battled()


## `disappear` and `appear` set and clear the object's own event flag where the
## source does, so a `checkevent` later in the same script reads it back.
## TeamRocketBaseB2F's third Electrode checks all three straight after
## disappearing its own, and read the committed value without this.
func _stage_object_event_flag(object_id: int, active: bool) -> void:
	var index: int = _object_index_from_id(object_id)
	var flags: Array = _request.get("object_event_flags", [])
	if index < 0 or index >= flags.size():
		return
	var flag: int = int(flags[index])
	if flag > 0:
		_staged_flags[flag] = active


func _stage_just_battled(value: bool) -> void:
	_staged_just_battled = value
	_has_staged_just_battled = true


## The byte a script memory address holds, staged writes first. Reading an
## address never written answers zero, the way cleared WRAM does.
func _script_memory_value(address: int) -> int:
	if _staged_script_memory.has(address):
		return int(_staged_script_memory[address])
	return state.script_memory(address) if state != null else 0


func _stage_script_memory(address: int, value: int) -> Dictionary:
	if address <= 0:
		return {"ok": false, "reason": &"invalid_script_memory_address", "address": address}
	_staged_script_memory[address] = value & 0xFF
	_emit_runtime_event(&"script_memory_changed", {
		"address": address, "value": value & 0xFF,
	})
	return {"ok": true}


func _item_quantity(item: int) -> int:
	if _staged_items.has(item):
		return int(_staged_items[item])
	return state.item_quantity(item) if state != null else 0


func _money_balance(account: int) -> int:
	if _staged_money.has(account):
		return int(_staged_money[account])
	return state.money(account) if state != null else 0


func _coins_value() -> int:
	return _staged_coins if _staged_coins >= 0 else (state.coins() if state != null else 0)


func _compare_amount(current: int, requested: int) -> int:
	return 0 if current < requested else (1 if current == requested else 2)


func _decode_bcd(bytes: PackedByteArray) -> int:
	var value: int = 0
	for byte: int in bytes:
		value = value * 100 + ((byte >> 4) * 10) + (byte & 0x0F)
	return value


## `engine/events/haircut.asm` past its `farcall SelectMonFromParty`.
##
## The carry the party list answers a B press or its CANCEL row with is
## `.nope`/`.cancel`, which is `xor a` in every one of the four; an EGG is
## `.egg`'s own 1, and only the three grooming routines test for it, because
## `BillsGrandfather` has no such branch and answers EGG as a species like any
## other. `GetCurNickname` names the member for the three and `GetPokemonName`
## the species for the fourth, both into wStringBuffer3.
func _finish_party_selection(request: Dictionary, result: Dictionary) -> Dictionary:
	var values: Dictionary = request.get("values", {})
	var special: int = int(values.get("special", 0))
	var routine: StringName = StringName(values.get("routine", &""))
	var party_index: int = int(result.get("party_index", -1))
	if party_index < 0:
		_script_value = 0
		_pending = {}
		return advance()
	var species: int = int(result.get("species", 0))
	_cur_party_species = species
	if routine == &"bills_grandfather":
		_script_value = species
		_set_text_buffer(3, String(result.get("species_name", "")), &"chosen_party_mon", {
			"special": special, "slot": party_index,
		})
		_pending = {}
		return advance()
	if species == SPECIES_EGG:
		_script_value = 1
		_pending = {}
		return advance()
	_set_text_buffer(3, String(result.get("nickname", "")), &"chosen_party_mon", {
		"special": special, "slot": party_index,
	})
	## `call Random` sits behind the name copy, so the roll is spent whether or
	## not the row it picks changes anything.
	var outcome: Dictionary = Gen2WorldPartyHost.groom_outcome(
		routine, _random.randi() & 0xFF, _crystal_commands()
	)
	_script_value = int(outcome["script_value"])
	_emit_runtime_event(&"party_happiness_changed", {
		"special": special,
		"slot": party_index,
		"happiness_kind": int(outcome["happiness_kind"]),
	})
	_pending = {}
	return advance()


func _emit_runtime_event(kind: StringName, values: Dictionary) -> void:
	var event: Dictionary = {
		"type": kind,
		"map_group": int(_request.get("map_group", 0)),
		"map_number": int(_request.get("map_number", 0)),
	}
	for key: Variant in values:
		event[key] = values[key]
	_events.append(event)


func _object_index_from_id(object_id: int) -> int:
	if object_id in [0xFE, 0xFF]:
		return _last_talked_object_index
	if object_id == 0:
		return -1
	if object_id <= 0:
		return -1
	# object_const_def starts map-object constants at 2. The cache omits the
	# player object, so source id 2 is array index zero.
	return object_id - 2


func _emit_object_event(event_type: StringName, values: Dictionary) -> void:
	var event: Dictionary = {
		"type": event_type,
		"map_group": int(_request.get("map_group", 0)),
		"map_number": int(_request.get("map_number", 0)),
	}
	for key: Variant in values:
		event[key] = values[key]
	_events.append(event)


## engine/events/overworld.asm's AskStrengthScript, synthesized.
##
## StrengthBoulderScript is `farsjump AskStrengthScript`, whose first command is
## `callasm TryStrengthOW`. `callasm` has no runner here and its operand is a
## link-time address absent from the pinned disassemblies, so the seam sits on
## the standard-script index instead, which is 14 in both pins and verified by
## the imported table. The synthesized body is the same shape trainer object
## dispatch takes: source sequence, project metadata.
##
## Every branch of AskStrengthScript terminates, so this never returns to a
## caller and jumpstd and callstd resolve alike.
func _stage_strength_boulder() -> Dictionary:
	var party: Dictionary = _request.get("party", {})
	if party.is_empty():
		return {"ok": false, "reason": &"missing_party_summary", "standard_index": STD_STRENGTH_BOULDER}
	var slot: int = _party_slot_with_move(Gen2WorldFieldMove.MOVE_STRENGTH)
	var has_badge: bool = _engine_flag_active(
		Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_PLAIN, _crystal_commands())
	)
	if slot < 0 or not has_badge:
		_script_value = STRENGTH_OW_UNABLE
		return _stage_internal_text(STRENGTH_MAY_MOVE_TEXT, true)
	if _engine_flag_active(Gen2WorldState.strength_active_flag(_crystal_commands())):
		_script_value = STRENGTH_OW_ALREADY_ACTIVE
		return _stage_internal_text(STRENGTH_BOULDERS_MOVE_TEXT, true)
	_script_value = STRENGTH_OW_ASK
	_pending = {
		"type": &"text",
		"text": STRENGTH_ASK_TEXT,
		"internal_text": true,
		"special": &"strength_ask",
		"slot": slot,
		"source": _request.duplicate(true),
	}
	_finish_after_pending = false
	return {"ok": true}


## engine/events/misc_scripts.asm's FindItemInBallScript, synthesized.
##
## An item ball's script pointer is not code: it is the `itemball` macro's
## `db item, quantity`, which `ObjectEventTypeArray.itemball` copies into
## wItemBallData before raising PLAYEREVENT_ITEMBALL. So the seam is the object
## type, not a script address, and Gen2WorldAPI hands the two decoded bytes over
## as an item_ball request. The script's own first command is `callasm
## .TryReceiveItem` and both its texts are engine text rather than map text, so
## the body is replayed here the way AskStrengthScript's is.
##
## Source order is receive, `disappear LAST_TALKED`, then the text, so the ball
## is already gone when the box is drawn. Behind that text the script plays
## SFX_ITEM by name rather than through `specialsound` and then runs
## `itemnotify`; its own `pause 60` is the acknowledge here, since nothing draws
## a text box that closes itself.
##
## The receive seam preserves the source's no-room branch without committing
## the item, hiding the ball, or setting its event flag.
func _stage_item_ball() -> Dictionary:
	var item: int = int(_request.get("item", 0))
	var quantity: int = maxi(1, int(_request.get("quantity", 1)))
	if item <= 0:
		return _fail(&"invalid_item_ball", {"item": item, "quantity": quantity})
	var received: Dictionary = _stage_item_delta(item, quantity)
	if not bool(received.get("accepted", true)):
		var no_space_name: String = data.item_name(item) if data != null else "ITEM"
		return _stage_internal_text(NO_SPACE_ITEM_TEXT % no_space_name, true)
	_emit_object_event(&"object_visibility", {
		"object_index": _last_talked_object_index, "active": false,
	})
	_emit_object_event(&"object_event_flag", {
		"object_index": _last_talked_object_index, "active": true,
	})
	_stage_object_event_flag(LAST_TALKED, true)
	var item_name: String = data.item_name(item) if data != null else ""
	if item_name.is_empty():
		item_name = "ITEM"
	return _stage_internal_text(FOUND_ITEM_TEXT % item_name, false, {
		"special": &"item_received", "item": item, "sfx": SFX_ITEM, "finish": true,
	})


## `FruitTreeScript` (`engine/events/fruit_trees.asm`). Like an item ball it is
## a script rather than a host request: `fruittree` is the whole of the object's
## own script, and the routine below it is text, a flag and a `giveitem`.
##
## The first pause is `FruitBearingTreeText`; `TryResetFruitTrees` and
## `CheckFruitTree` run on its acknowledge, since the source's own `callasm`s sit
## behind the `promptbutton`.
func _stage_fruit_tree(tree_id: int) -> Dictionary:
	if data == null:
		return _fail(&"missing_world_data", {"tree_id": tree_id})
	var item: int = data.world_fruit_tree_item(tree_id)
	if item <= 0:
		return _fail(&"invalid_fruit_tree", {"tree_id": tree_id, "item": item})
	_pending = {
		"type": &"text",
		"text": FRUIT_TREE_TEXT,
		"internal_text": true,
		"special": &"fruit_tree",
		"tree_id": tree_id,
		"item": item,
		"source": _request.duplicate(true),
	}
	return {"ok": true}


## The second half, run once the tree's own line has been acknowledged.
func _resolve_fruit_tree(tree_id: int, item: int) -> Dictionary:
	_stage_fruit_tree_reset()
	if _fruit_tree_picked(tree_id):
		return _stage_internal_text(FRUIT_TREE_EMPTY_TEXT, true)
	var item_name: String = data.item_name(item)
	if item_name.is_empty():
		item_name = "FRUIT"
	var received: Dictionary = _stage_item_delta(item, 1)
	if not bool(received.get("accepted", true)):
		return _stage_internal_text(FRUIT_TREE_FULL_TEXT % item_name, true)
	## PickedFruitTree, which the source runs after the item is in the bag, then
	## its own `specialsound` and `itemnotify`.
	_staged_fruit_trees[tree_id] = true
	return _stage_internal_text(
		FRUIT_TREE_OBTAINED_TEXT % [item_name, item_name], false,
		{"special": &"item_received", "item": item, "finish": true}
	)


## `TryResetFruitTrees`: `ResetFruitTrees` refills every tree at once and sets
## ENGINE_ALL_FRUIT_TREES behind itself, so it runs once per day, on whichever
## tree the player touches first after the daily reset cleared that flag.
func _stage_fruit_tree_reset() -> void:
	var all_trees: int = Gen2WorldState.engine_flag(
		Gen2WorldState.ENGINE_ALL_FRUIT_TREES, _crystal_commands()
	)
	if bool(_staged_engine_flags.get(all_trees, state.is_engine_flag_active(all_trees))):
		return
	for raw_tree: Variant in state.picked_fruit_trees():
		_staged_fruit_trees[int(raw_tree)] = false
	_staged_engine_flags[all_trees] = true


func _fruit_tree_picked(tree_id: int) -> bool:
	if _staged_fruit_trees.has(tree_id):
		return bool(_staged_fruit_trees[tree_id])
	return state.fruit_tree_picked(tree_id)


## HiddenItemScript, the BGEVENT_ITEM half of the same source area. The pointer
## is the `hiddenitem` macro's `dwb event, item`, which `.itemifset` copies into
## wHiddenItemData, so Gen2WorldAPI hands the decoded flag and item over the way
## it hands over an item ball's two bytes.
##
## The differences from _stage_item_ball() are the flag and the object. There is
## no object to hide, since the item is a background event rather than a ball,
## and the flag `callasm SetMemEvent` writes is the record's own rather than the
## object's. `_PlayerFoundItemText` is `_FoundItemText`'s wording, so the two
## share FOUND_ITEM_TEXT and its <PLAYER> boundary.
##
## The source writes the text before `giveitem` and sets the flag after it. A
## full pocket leaves both the item and the event flag untouched, then shows the
## source's no-space branch in one scene-free text pause.
func _stage_hidden_item() -> Dictionary:
	var item: int = int(_request.get("item", 0))
	var flag: int = int(_request.get("flag", -1))
	if item <= 0 or flag < 0:
		return _fail(&"invalid_hidden_item", {"item": item, "flag": flag})
	var received: Dictionary = _stage_item_delta(item, 1)
	if not bool(received.get("accepted", true)):
		var no_space_name: String = data.item_name(item) if data != null else "ITEM"
		return _stage_internal_text(NO_SPACE_ITEM_TEXT % no_space_name, true)
	_staged_flags[flag] = true
	var item_name: String = data.item_name(item) if data != null else ""
	if item_name.is_empty():
		item_name = "ITEM"
	return _stage_internal_text(FOUND_ITEM_TEXT % item_name, false, {
		"special": &"item_received", "item": item, "finish": true,
	})


## CheckPartyMove: the first slot whose move list carries [param move], or -1.
## The mirror's per-slot lists are the only party this scene-free runner reads.
## Eggs are skipped, the way the source's own `cp EGG` branch skips them.
func _party_slot_with_move(move: int) -> int:
	var party: Dictionary = _request.get("party", {})
	var moves: Array = party.get("moves", [])
	var eggs: Array = party.get("eggs", [])
	for slot: int in moves.size():
		if slot < eggs.size() and bool(eggs[slot]):
			continue
		if moves[slot] is Array and (moves[slot] as Array).has(move):
			return slot
	return -1


## SetStrengthFlag plus Script_UsedStrength's two texts. The cry and its three
## frame pause are presentation the runner does not own, so the two writetexts
## become two pauses back to back, which is what a reader sees either way.
func _stage_strength_used(slot: int) -> Dictionary:
	_staged_engine_flags[Gen2WorldState.strength_active_flag(_crystal_commands())] = true
	var names: Array = _request.get("party", {}).get("names", [])
	var name: String = String(names[slot]) if slot >= 0 and slot < names.size() else "#MON"
	_pending = {
		"type": &"text",
		"text": "%s used\nSTRENGTH!" % name,
		"internal_text": true,
		"special": &"strength_used",
		"name": name,
		"source": _request.duplicate(true),
	}
	_finish_after_pending = false
	return {"ok": true}


## engine/overworld/events.asm's TryTileCollisionEvent, from `.cut` on: the five
## field-move branches a faced tile can reach, each of which is a `Try*OW` gate
## and then an `Ask*Script`. Synthesized for the reason AskStrengthScript is,
## and dispatched on the request kind rather than a standard-script index
## because these are reached through `CallScript` rather than `jumpstd`.
##
## Which move the tile offers is [Gen2WorldAPI]'s answer, since only it can read
## the map; so is `tile_ok`, the tile-shaped half of the gate that
## TryWhirlpoolMenu and CheckMapCanWaterfall own. What is left here is the party
## and the badge, which is what this runner already reads for the boulder.
##
## Three of the five have a refusal text and two do not: TryHeadbuttOW and
## TrySurfOW return no carry and the player event ends with nothing shown.
func _stage_field_move_prompt() -> Dictionary:
	var party: Dictionary = _request.get("party", {})
	if party.is_empty():
		return {"ok": false, "reason": &"missing_party_summary", "kind": &"field_move_prompt"}
	var move: int = int(_request.get("move", 0))
	var slot: int = _party_slot_with_move(move)
	var badge: int = _field_move_prompt_badge(move)
	var allowed: bool = slot >= 0
	if allowed and badge >= 0:
		allowed = _engine_flag_active(
			Gen2WorldState.badge_flag(badge, _crystal_commands())
		)
	if allowed and not bool(_request.get("tile_ok", true)):
		allowed = false
	if not allowed:
		var refusal: String = _field_move_prompt_refusal(move)
		if refusal.is_empty():
			## `.noevent`: TryHeadbuttOW and TrySurfOW answer no carry, so the
			## player event ends and nothing is shown at all.
			_script_value = 0
			return _complete()
		return _stage_internal_text(refusal, true)
	_pending = {
		"type": &"text",
		"text": _field_move_prompt_ask(move),
		"internal_text": true,
		"special": &"field_move_ask",
		"move": move,
		"slot": slot,
		"source": _request.duplicate(true),
	}
	_finish_after_pending = false
	return {"ok": true}


## Each Try*OW's own CheckEngineFlag argument, as a badge-order index, or -1 for
## the one that checks none. TryHeadbuttOW is CheckPartyMove and nothing else.
func _field_move_prompt_badge(move: int) -> int:
	match move:
		Gen2WorldFieldMove.MOVE_CUT:
			return Gen2WorldFieldMove.BADGE_HIVE
		Gen2WorldFieldMove.MOVE_SURF:
			return Gen2WorldFieldMove.BADGE_FOG
		Gen2WorldFieldMove.MOVE_WHIRLPOOL:
			return Gen2WorldFieldMove.BADGE_GLACIER
		Gen2WorldFieldMove.MOVE_WATERFALL:
			return Gen2WorldFieldMove.BADGE_RISING
	return -1


func _field_move_prompt_ask(move: int) -> String:
	match move:
		Gen2WorldFieldMove.MOVE_CUT:
			return CUT_ASK_TEXT
		Gen2WorldFieldMove.MOVE_SURF:
			return SURF_ASK_TEXT
		Gen2WorldFieldMove.MOVE_WHIRLPOOL:
			return WHIRLPOOL_ASK_TEXT
		Gen2WorldFieldMove.MOVE_WATERFALL:
			return WATERFALL_ASK_TEXT
	return HEADBUTT_ASK_TEXT


## CantCutScript, Script_MightyWhirlpool and Script_CantDoWaterfall. Headbutt
## and Surf have none, which is what the empty String means.
func _field_move_prompt_refusal(move: int) -> String:
	match move:
		Gen2WorldFieldMove.MOVE_CUT:
			return CUT_CAN_TEXT
		Gen2WorldFieldMove.MOVE_WHIRLPOOL:
			return WHIRLPOOL_MAY_PASS_TEXT
		Gen2WorldFieldMove.MOVE_WATERFALL:
			return WATERFALL_HUGE_TEXT
	return ""


## engine/events/overworld.asm's AskRockSmashScript, synthesized for the same
## reason AskStrengthScript is: SmashRockScript is `farsjump AskRockSmashScript`
## and its first command is `callasm HasRockSmash`, whose operand is a link-time
## address absent from the pins. The seam is the standard-script index, 15 in
## both.
##
## `HasRockSmash` is CheckPartyMove and nothing else, so unlike the boulder
## there is no badge and no already-active flag to check: the whole gate is
## whether a party member knows ROCK SMASH.
func _stage_smash_rock() -> Dictionary:
	var party: Dictionary = _request.get("party", {})
	if party.is_empty():
		return {"ok": false, "reason": &"missing_party_summary", "standard_index": STD_SMASH_ROCK}
	var slot: int = _party_slot_with_move(Gen2WorldFieldMove.MOVE_ROCK_SMASH)
	if slot < 0:
		return _stage_internal_text(ROCK_SMASH_MAY_SMASH_TEXT, true)
	_pending = {
		"type": &"text",
		"text": ROCK_SMASH_ASK_TEXT,
		"internal_text": true,
		"special": &"rock_smash_ask",
		"slot": slot,
		"source": _request.duplicate(true),
	}
	_finish_after_pending = false
	return {"ok": true}


## RockSmashScript's `callasm GetPartyNickname` and `writetext UseRockSmashText`.
func _stage_rock_smash_used(slot: int) -> Dictionary:
	var names: Array = _request.get("party", {}).get("names", [])
	var name: String = String(names[slot]) if slot >= 0 and slot < names.size() else "#MON"
	_pending = {
		"type": &"text",
		"text": ROCK_SMASH_USED_TEXT % name,
		"internal_text": true,
		"special": &"rock_smash_used",
		"source": _request.duplicate(true),
	}
	_finish_after_pending = false
	return {"ok": true}


## Everything RockSmashScript does after its text: `playsound SFX_STRENGTH`,
## `earthquake 84`, the rock's own one-command movement, `disappear LAST_TALKED`
## and then RockMonEncounter. The sound and the shake are reported as events,
## the way the runner reports every other presentation request.
##
## `readmem wTempWildMonSpecies` and `iffalse .done` are what test the roll, so
## a species of zero ends the script and anything else reaches `randomwildmon`,
## `startbattle` and `reloadmapafterbattle`.
func _stage_rock_smashed() -> void:
	_emit_runtime_event(&"earthquake_requested", {"duration": ROCK_SMASH_EARTHQUAKE})
	## `disappear LAST_TALKED` is DeleteObjectStruct plus
	## ApplyEventActionAppearDisappear. The delete is reported as
	## `object_deleted` rather than a visibility override, so a rock with no
	## event flag is back on the next map load exactly as the cartridge's is;
	## the flag half is what makes Mt. Moon Square's stay smashed.
	_emit_object_event(&"object_deleted", {
		"object_index": _last_talked_object_index,
	})
	_emit_object_event(&"object_event_flag", {
		"object_index": _last_talked_object_index, "active": true,
	})
	_stage_object_event_flag(LAST_TALKED, true)
	var encounter: Dictionary = _rock_encounter()
	if encounter.is_empty():
		## `readmem wTempWildMonSpecies` then `iffalse .done`, and `.done` is
		## `end`. Clearing the frames is what reaching that end looks like here.
		_script_value = 0
		_frames.clear()
		return
	_battle_setup = _new_battle_setup({
		"kind": &"wild",
		"pokemon": int(encounter["species"]),
		"level": int(encounter["level"]),
	})
	_emit_runtime_event(&"battle_setup_changed", _battle_setup)
	_emit_runtime_event(&"battle_map_reload_requested", {"requested": true})
	_stage_runtime_request(&"battle_requested", _battle_request_values())


## RockMonEncounter over the imported RockMonMaps and the ROCK set, rolled on
## this invocation's own generator like every other roll the runner makes.
func _rock_encounter() -> Dictionary:
	if data == null:
		return {}
	var group: int = int(_request.get("map_group", -1))
	var number: int = int(_request.get("map_number", -1))
	var set_number: int = data.treemon_set_for_map(group, number, true)
	if not Gen2WorldTreemon.set_is_usable(set_number, _crystal_commands()):
		return {}
	return Gen2WorldTreemon.rock_encounter(data.treemon_set(set_number), _random)


## `Script_itemnotify`: `GetPocketName` and `CurItemName` into
## `PutItemInPocketText`, which `MapTextbox` prints and the script resumes
## behind. Every receipt in the source ends on this box.
func _stage_item_notify(item: int, finish_after: bool) -> Dictionary:
	var item_name: String = data.item_name(item) if data != null else ""
	if item_name.is_empty():
		item_name = "ITEM"
	return _stage_internal_text(
		PUT_ITEM_TEXT % [item_name, Gen2WorldPack.source_pocket_name(data, item)],
		finish_after
	)


## `Script_pocketisfull`, which is the same box with only the pocket in it.
func _stage_pocket_is_full(item: int, finish_after: bool) -> Dictionary:
	return _stage_internal_text(
		POCKET_FULL_TEXT % Gen2WorldPack.source_pocket_name(data, item), finish_after
	)


## `GiveItemScript`, which is the whole of `verbosegiveitem` past the receive:
## the received line, and then either the sound and `itemnotify` or, on a full
## pack, `pocketisfull`. The line is printed either way, because the source's
## `iffalse` sits behind its own `writetext`. Both boxes resume the caller.
func _stage_give_item_script(item: int, item_name: String) -> Dictionary:
	var named: String = item_name if not item_name.is_empty() else "ITEM"
	return _stage_internal_text(RECEIVED_ITEM_TEXT % named, false, {
		"special": &"item_received" if _script_value != 0 else &"pocket_is_full",
		"item": item,
	})


## The tail a receipt shares once its own line has been read: the sound, and
## then `itemnotify` behind it. [param sfx] is the id a script plays by name,
## or 0 for `specialsound`'s own pocket-dependent choice.
func _stage_receipt_tail(item: int, sfx: int, finish_after: bool) -> Dictionary:
	_item_notify_after_sound = {"item": item, "finish": finish_after}
	if sfx > 0:
		return _stage_audio_request(&"sound", {"address": sfx})
	return _stage_audio_request(&"special_sound", {"item": item})


func _stage_internal_text(
	text: String, finish_after: bool, values: Dictionary = {}
) -> Dictionary:
	var pending: Dictionary = {
		"type": &"text",
		"text": text,
		"internal_text": true,
		"source": _request.duplicate(true),
	}
	for key: Variant in values:
		pending[key] = values[key]
	_pending = pending
	_finish_after_pending = finish_after
	return {"ok": true}


func _stage_button(command: Dictionary) -> Dictionary:
	_pending = {
		"type": &"button",
		"command": command.get("name", &"button"),
		"source": _request.duplicate(true),
	}
	return {"ok": true}


func _stage_choice(command: Dictionary, choices: Array) -> Dictionary:
	_pending = {
		"type": &"choice",
		"command": command.get("name", &"choice"),
		"choices": choices.duplicate(true),
		"text": _standing_text,
		"source": _request.duplicate(true),
	}
	return {"ok": true}


func _show_text(bank: int, address: int, finish_after: bool) -> Dictionary:
	var raw: PackedByteArray = data.world_text(bank, address) if data != null else PackedByteArray()
	var decoded: Dictionary = _decode_text_with_buffers(raw)
	if not bool(decoded.get("ok", false)):
		return {
			"ok": false,
			"reason": decoded.get("reason", &"invalid_text"),
			"bank": bank,
			"address": address,
		}
	_last_text = {"bank": bank, "address": address}
	_pending = {
		"type": &"text",
		"text": String(decoded.get("text", "")),
		"bank": bank,
		"address": address,
		## `Script_writetext` is `MapTextbox` and returns: only `<PROMPT>`,
		## `text_promptbutton` and `text_waitbutton` spend a press inside the
		## text. A text ending in `<DONE>` therefore owes none of its own, and
		## the press belongs to the `waitbutton` behind the command.
		## `JumpTextScript` carries that `waitbutton` itself, which is what
		## [param finish_after] names.
		"prompt": finish_after or bool(decoded.get("prompt", false)),
		"source": _request.duplicate(true),
	}
	_finish_after_pending = finish_after
	return {"ok": true}


func _set_text_buffer(
	buffer: int, value: String, kind: StringName, details: Dictionary = {}
) -> void:
	_text_buffers[buffer] = value
	var event: Dictionary = {
		"buffer": buffer, "value": value, "kind": kind,
	}
	for key: Variant in details:
		event[key] = details[key]
	_emit_runtime_event(&"text_buffer_changed", event)


## The runner's own print-time context: the buffers `getstring` and
## `verbosegiveitem` fill, and the two names a map text can name.
func _decode_text_with_buffers(raw: PackedByteArray) -> Dictionary:
	return Gen2TextStream.decode(raw, 0, text_context())


## What `CheckDict` and `TX_STRINGBUFFER` read when this runner prints.
func text_context() -> Dictionary:
	var context: Dictionary = {
		"buffers": _text_buffers,
		"ram": _text_buffer_ram(),
		"rival": _rival_name,
	}
	if not player_name.is_empty():
		context["player"] = player_name
	if data != null:
		context["far"] = func(bank: int, address: int) -> PackedByteArray:
			return data.world_text(bank, address)
	return context


## The buffers this runner filled, keyed the way `TextCommand_RAM` asks for them.
##
## `getstring` and `verbosegiveitem` fill buffers by `text_buffer` number, but a
## `text_ram` names the same storage by its WRAM address, so the item texts read
## through StringBufferPointers rather than the number. Addresses come from the
## cartridge, since Gold and Crystal put the buffers in different places.
func _text_buffer_ram() -> Dictionary:
	if data == null or _text_buffers.is_empty():
		return {}
	var addresses: Array[int] = data.string_buffer_addresses()
	var out: Dictionary = {}
	for buffer: Variant in _text_buffers:
		var index: int = int(buffer)
		if index >= 0 and index < addresses.size():
			out[addresses[index]] = _text_buffers[buffer]
	return out


func _runtime_memory_pointer(address: int) -> Dictionary:
	## memcall and memjump read a three-byte far pointer from a live RAM
	## address. The host supplies that RAM snapshot explicitly because the
	## runner does not emulate the cartridge's whole WRAM address space.
	var pointers: Variant = _request.get("memory_pointers", {})
	if not pointers is Dictionary:
		return {}
	var value: Variant = null
	if (pointers as Dictionary).has(address):
		value = (pointers as Dictionary)[address]
	else:
		for raw_address: Variant in pointers as Dictionary:
			if _runtime_memory_address(raw_address) == address:
				value = (pointers as Dictionary)[raw_address]
				break
	if not value is Dictionary:
		return {}
	var pointer: Dictionary = value as Dictionary
	var bank: int = int(pointer.get("bank", -1))
	var target: int = int(pointer.get("address", -1))
	if bank < 0 or target < RomFile.BANK_SIZE or target >= RomFile.BANK_SIZE * 2:
		return {}
	return {"bank": bank, "address": target}


static func _runtime_memory_address(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	var text: String = String(value).strip_edges()
	if text.begins_with("0x") or text.begins_with("0X"):
		return text.substr(2).hex_to_int()
	return text.to_int()


func _stage_warp(command: Dictionary) -> Dictionary:
	var request: Dictionary = {
		"map_group": int(command["map_group"]),
		"map_number": int(command["map_number"]),
		"x": int(command["x"]),
		"y": int(command["y"]),
	}
	# Script_warpfacing sets PLAYERSPRITESETUP_CUSTOM_FACING_F before falling
	# through Script_warp. Carry the same marker through map setup so the normal
	# destination-tile facing rule cannot overwrite it.
	if command.has("facing"):
		request["facing"] = int(command["facing"])
	if warp_validator.is_valid():
		var validation: Variant = warp_validator.call(
			request["map_group"], request["map_number"], Vector2i(request["x"], request["y"])
		)
		if not validation is Dictionary or not bool((validation as Dictionary).get("ok", false)):
			return {
				"ok": false,
				"reason": &"invalid_warp",
				"warp": request,
				"validation": validation,
			}
	_staged_warp = request
	_events.append({"type": &"warp_requested", "warp": request.duplicate(true)})
	return {"ok": true}


func _push_frame(
	bank: int, address: int, raw_override: PackedByteArray = PackedByteArray()
) -> bool:
	if data == null or address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
		return false
	if _frames.size() >= Gen2WorldScript.MAX_CALL_DEPTH:
		_fail(&"call_depth_limit", {"limit": Gen2WorldScript.MAX_CALL_DEPTH})
		return false
	var raw: PackedByteArray = raw_override if not raw_override.is_empty() else data.world_script(bank, address)
	if raw.is_empty():
		return false
	_frames.append({"bank": bank, "address": address, "data": raw, "offset": 0})
	return true


func _standard_script(index: int) -> Dictionary:
	if data == null or index < 0:
		return {}
	var entry: Dictionary = data.world_standard_script(index)
	var raw: Variant = entry.get("data", PackedByteArray())
	if entry.is_empty() or not raw is PackedByteArray or (raw as PackedByteArray).is_empty():
		return {}
	return entry


func _branch(taken: bool, bank: int, address: int) -> Dictionary:
	if not taken:
		return {"ok": true}
	return _replace_frame(bank, address)


func _event_flag_active(flag: int) -> bool:
	if _staged_flags.has(flag):
		return bool(_staged_flags[flag])
	return state != null and state.is_event_flag_active(flag)


func _engine_flag_active(flag: int) -> bool:
	if _staged_engine_flags.has(flag):
		return bool(_staged_engine_flags[flag])
	return state != null and state.is_engine_flag_active(flag)


## _GetVarAction's .CountBadges, over staged flags rather than committed ones.
##
## The cartridge has no staging: `setflag` writes wBadges and the `readvar`
## after it reads what was just written. Mahogany Gym is where that matters:
## PryceScript sets ENGINE_GLACIERBADGE, reads VAR_BADGES and branches on 7 to
## RadioTowerRocketsScript, which is what opens Mahogany's east exit. Counting
## committed flags answered 6 there and took the Goldenrod branch instead.
func _staged_badge_count() -> int:
	var crystal: bool = _crystal_commands()
	var count: int = 0
	for flag: int in (
		Gen2WorldState.BADGE_ENGINE_FLAGS if crystal
		else Gen2WorldState.BADGE_ENGINE_FLAGS_GOLD_SILVER
	):
		if _engine_flag_active(flag):
			count += 1
	return count


func _map_scene_value(map_group: int, map_number: int) -> int:
	var key: String = Gen2WorldState.map_scene_key(map_group, map_number)
	if _staged_scenes.has(key):
		return int(_staged_scenes[key])
	if state != null and state.map_scenes().has(key):
		return state.map_scene(map_group, map_number)
	if data != null:
		var map: Gen2WorldMap = data.world_map(map_group, map_number)
		if map != null and not (map.scripts.get("scenes", []) as Array).is_empty():
			# Crystal clears the map-scene table on a new game. Maps with scene
			# records therefore start at scene 0; maps without records use the
			# source no-scene sentinel below.
			return 0
	return 0xFF


func _replace_frame(
	bank: int, address: int, raw_override: PackedByteArray = PackedByteArray()
) -> Dictionary:
	if data == null or address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
		return {"ok": false, "reason": &"missing_jump_target", "bank": bank, "address": address}
	var raw: PackedByteArray = raw_override if not raw_override.is_empty() else data.world_script(bank, address)
	if raw.is_empty():
		return {"ok": false, "reason": &"missing_jump_target", "bank": bank, "address": address}
	_frames[_frames.size() - 1] = {
		"bank": bank, "address": address, "data": raw, "offset": 0,
	}
	return {"ok": true}


func _complete() -> Dictionary:
	if _completed:
		return _complete_result()
	if state == null:
		return _fail(&"missing_world_state", {})
	var runtime_changes: Dictionary = {}
	if not _staged_items.is_empty():
		runtime_changes["items"] = _staged_items.duplicate()
	if not _staged_money.is_empty():
		runtime_changes["money"] = _staged_money.duplicate()
	if _staged_coins >= 0:
		runtime_changes["coins"] = _staged_coins
	if not _staged_phone_contacts.is_empty():
		runtime_changes["phone_contacts"] = _staged_phone_contacts.duplicate()
	if not _staged_script_memory.is_empty():
		runtime_changes["script_memory"] = _staged_script_memory.duplicate()
	if _has_staged_just_battled:
		runtime_changes["just_battled"] = _staged_just_battled
	if _has_staged_swarm:
		runtime_changes["swarm"] = _staged_swarm.duplicate()
	if _has_staged_special_phone_call:
		runtime_changes["pending_special_phone_call"] = _staged_special_phone_call
	if _has_staged_kurt_apricorn_quantity:
		runtime_changes["kurt_apricorn_quantity"] = _staged_kurt_apricorn_quantity
	if not _staged_fruit_trees.is_empty():
		runtime_changes["fruit_trees"] = _staged_fruit_trees.duplicate()
	if not _staged_engine_flags.is_empty():
		runtime_changes["engine_flags"] = _staged_engine_flags.duplicate()
	if _reset_phone_receive_timer:
		runtime_changes["phone_receive_cycle"] = 0
		runtime_changes["phone_receive_minutes"] = Gen2WorldState.PHONE_RECEIVE_DELAYS[0]
	var applied: Dictionary = state.apply_changes(
		_staged_flags, _staged_scenes, runtime_changes
	)
	if not bool(applied.get("ok", false)):
		return _fail(StringName(applied.get("reason", &"state_transaction_failed")), applied)
	_completed = true
	_active = false
	if not _staged_flags.is_empty() or not _staged_scenes.is_empty() \
		or not runtime_changes.is_empty():
		_events.append({
			"type": &"state_changed",
			"flags": _staged_flags.duplicate(true),
			"scenes": _staged_scenes.duplicate(true),
			"runtime": runtime_changes.duplicate(true),
		})
	if _staged_day_of_week >= 0:
		_events.append({
			"type": &"world_clock_changed",
			"day": _staged_day_of_week,
			"hour": _clock_hour(),
			"minute": _clock_minute(),
		})
	if _has_staged_dst:
		_events.append({"type": &"dst_changed", "enabled": _staged_dst_enabled})
	return _complete_result()


func _complete_result() -> Dictionary:
	var result: Dictionary = {
		"ok": true,
		"status": &"complete",
		"events": _drain_events(),
		"source": _request.duplicate(true),
		"warp": _staged_warp.duplicate(true),
		"commands": _command_count,
		"deferred": _ran_deferred,
	}
	if _staged_day_of_week >= 0:
		result["clock"] = {
			"day": _staged_day_of_week,
			"hour": _clock_hour(),
			"minute": _clock_minute(),
		}
	if _has_staged_dst:
		result["dst_enabled"] = _staged_dst_enabled
	return result


func _recovered_result(recovery: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"status": &"recovered",
		"events": _drain_events(),
		"source": _request.duplicate(true),
		"recovery": recovery.duplicate(true),
		"commands": _command_count,
	}


func _new_battle_setup(base: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	if _loaded_battle_type >= 0:
		out["battle_type"] = _loaded_battle_type
		out["can_lose"] = _loaded_battle_type == 1
	for key: String in ["win_text", "loss_text"]:
		if _battle_setup.has(key):
			out[key] = (_battle_setup[key] as Dictionary).duplicate(true)
	return out


func _trainer_text_pointer(trainer: Dictionary, key: String, default_bank: int) -> Dictionary:
	var raw: Variant = trainer.get(key, {})
	if raw is Dictionary:
		var pointer: Dictionary = (raw as Dictionary).duplicate(true)
		pointer["bank"] = int(pointer.get("bank", default_bank))
		pointer["address"] = int(pointer.get("address", 0))
		return pointer
	return {"bank": default_bank, "address": 0}


## Builds the source SeenByTrainerScript/StartBattleWithMapTrainerScript
## sequence: loadtemptrainer, encountermusic, farwritetext, waitbutton,
## loadtemptrainer, startbattle, reloadmapafterbattle, trainerflagaction, end.
## The sequence is identical between profiles at the source-opcode level;
## only the raw bytes differ, so every command goes through
## Gen2WorldScript.raw_opcode() rather than hard-coding either profile's byte.
func _trainer_intro_script(trainer: Dictionary) -> PackedByteArray:
	var seen: Dictionary = _trainer_text_pointer(
		trainer, "seen_text", int(_request.get("bank", 0))
	)
	var bank: int = int(seen.get("bank", _request.get("bank", 0)))
	var address: int = int(seen.get("address", 0))
	var crystal: bool = _crystal_commands()
	var raw: Callable = func(source_opcode: int) -> int:
		return Gen2WorldScript.raw_opcode(source_opcode, crystal)
	var bytes: Array = [
		# loadtemptrainer points at the request's trainer record.
		raw.call(Gen2WorldScript.GOLD_LOADTEMPTRAINER),
		raw.call(Gen2WorldScript.GOLD_ENCOUNTERMUSIC),
		Gen2WorldScript.FARWRITETEXT, bank, address & 0xFF, address >> 8,
		raw.call(0x53), # waitbutton
		raw.call(Gen2WorldScript.GOLD_LOADTEMPTRAINER),
		raw.call(Gen2WorldScript.GOLD_STARTBATTLE),
		raw.call(Gen2WorldScript.GOLD_RELOADMAPAFTERBATTLE),
		raw.call(Gen2WorldScript.GOLD_TRAINERFLAGACTION), 1,
		# StartBattleWithMapTrainerScript falls through into
		# AlreadyBeatenTrainerScript's scripttalkafter, with
		# wRunningTrainerBattleScript already set, so the after-battle script
		# runs now and its own endifjustbattled is what usually ends it. A
		# trainer that omits that command keeps going: Slowpoke Well's
		# TrainerGruntM1 clears the well from there.
		raw.call(Gen2WorldScript.GOLD_SCRIPTTALKAFTER),
		raw.call(Gen2WorldScript.GOLD_END),
	]
	return PackedByteArray(bytes)


func _battle_request_values() -> Dictionary:
	var out: Dictionary = _battle_setup.duplicate(true)
	var source_event: Variant = _request.get("event", {})
	if source_event is Dictionary:
		out["event"] = (source_event as Dictionary).duplicate(true)
	for key: String in [
		"map_group", "map_number", "object_index", "distance", "direction", "trigger",
	]:
		if _request.has(key):
			out[key] = _request[key]
	return out


## The events emitted since the last result, and only those. An invocation that
## stops four times hands each event to its caller once, because a caller applies
## and reacts to what a result carries: repeating the list would move an object
## twice and start a screen shake on every later pause.
func _drain_events() -> Array:
	var drained: Array = _events.duplicate(true)
	_events.clear()
	return drained


func _waiting_result() -> Dictionary:
	return {
		"ok": true,
		"status": &"waiting",
		"event": _pending.duplicate(true),
		"events": _drain_events(),
		"source": _request.duplicate(true),
		"commands": _command_count,
		"deferred": _ran_deferred,
	}


func _fail(reason: StringName, details: Dictionary) -> Dictionary:
	_active = false
	_failure = {"reason": reason, "details": details.duplicate(true)}
	return _failure_result()


func _failure_result() -> Dictionary:
	return {
		"ok": false,
		"status": &"failed",
		"reason": _failure.get("reason", &"script_failed"),
		"details": _failure.get("details", {}),
		"events": _drain_events(),
		"source": _request.duplicate(true),
		"commands": _command_count,
	}


func _crystal_commands() -> bool:
	if data == null:
		return true
	return data.id != &"gold" and data.id != &"silver"
