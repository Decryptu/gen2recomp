extends SceneTree

## Exercises map-entry callbacks and one facing interaction from an imported
## cartridge cache without opening the ROM at runtime.
##
##   Godot --headless --path . -s res://tools/preview_world_story.gd -- \
##     crystal 3 19 3 5 1 37,1744
##
## The optional final argument is a comma-separated list of event flags. Facing
## uses the runtime values: down=0, up=1, left=2, right=3. The optional eighth
## argument `home` follows the imported bedroom stair warp into the first floor
## and then the imported first-floor warp into New Bark Town. A ninth argument
## `story` drives the imported first-floor Mom event and the New Bark entry
## event through explicit source inputs.

## A ring is 30 lead frames plus two 60-frame rings; the budget only has to
## outlast that.
const PHONE_RING_FRAME_BUDGET: int = 256

## SPECIALCALL_ASSISTANT (constants/phone_constants.asm), armed by beating
## Falkner and answered by ElmPhoneCallerScript's .assistant branch.
const SPECIALCALL_ASSISTANT: int = 3

## How many interruptions one walk may resolve before it is called stuck. A leg
## crosses at most one map, and Route 41 carries the most trainers of any map on
## the route at ten (maps/Route41.asm).
const WALK_RESOLVE_ATTEMPTS: int = 16

## How many of the objects standing against a failed walk's frontier its reason
## names. A crowded map has more than a reader needs.
const BLOCKING_OBJECTS_REPORTED: int = 4

## constants/item_constants.asm's add_hm list, whose comment column is hex.
## `maps/Route32.asm` warp 1 and `maps/Route32Pokecenter1F.asm` warp 1, the
## fishing guru on (1,4) faced from below, and the nearest shore cell the rod is
## cast from: (10,42) faces water on (9,42) and sits in the same region as the
## Pokemon Center door.
const ROUTE_32_POKECENTER_DOOR: Vector2i = Vector2i(11, 73)
const ROUTE_32_POKECENTER_EXIT: Vector2i = Vector2i(3, 7)
const FISHING_GURU_FACE: Vector2i = Vector2i(1, 5)
const ROUTE_32_SHORE: Vector2i = Vector2i(10, 42)

const ITEM_HM_CUT: int = 0xF3
const ITEM_HM_SURF: int = 0xF5
const ITEM_HM_STRENGTH: int = 0xF6
const ITEM_HM_WHIRLPOOL: int = 0xF8
const ITEM_HM_WATERFALL: int = 0xF9
## TM08, the `add_tm ROCK_SMASH` row in the same file. Gold and Silver need it
## to finish the Burned Tower; no Crystal leg does.
const ITEM_TM_ROCK_SMASH: int = 0xC7
## The apricorn Azalea Town's own fruit tree bears.
const APRICORN_WHT: int = 0x61
## Ice Path 1F's HM07 ball stands on (31,7) in both games, on the same region as
## the Route 44 door and the first staircase (`maps/IcePath1F.asm`). Three of its
## four neighbours are wall, so (30,7) facing right is the only approach.
const HM07_APPROACH: Vector2i = Vector2i(30, 7)
## constants/mart_constants.asm's MART_BLACKTHORN, which
## BlackthornMartClerkScript names. Its stock is the cartridge's
## (`data/items/marts.asm` MartBlackthorn), and it sells no Poké Balls at all.
## How many balls the route buys is its own choice, not the cartridge's; five
## Great Balls is what the source start money covers.
const MART_BLACKTHORN: int = 17
const GREAT_BALLS_BOUGHT: int = 5
## `maps/BlackthornMart.asm` object 1 on (1,3), standing right behind the
## counter on (2,3), so it is talked to from (3,3) facing left.
const BLACKTHORN_MART_CLERK_FACE: Vector2i = Vector2i(3, 3)
## The two Radio Tower keys, from the same hex comment column.
const ITEM_CARD_KEY: int = 0x7F
const ITEM_BASEMENT_KEY: int = 0x85
## ENGINE_STORMBADGE's place in source badge order, for Gen2WorldState.badge_flag().
const BADGE_STORM: int = 5

## How many forced encounters the route may roll looking for a catch that can
## learn the move it needs. The bag is the real limit; this only bounds the
## rolls that find nothing worth throwing at, and Dragon's Den answers with a
## Dratini about one roll in ten.
const CATCH_ATTEMPTS: int = 256

## Mahogany Town, whose map scene and merchant flag are what open the east exit
## onto Route 44 (`data/maps/maps.asm`).
const MAHOGANY_TOWN_GROUP: int = 2
const MAHOGANY_TOWN_NUMBER: int = 7
## constants/event_flags.asm. RadioTowerRocketsScript sets it, which hides the
## RageCandyBar merchant standing on Mahogany's east edge.
const EVENT_MAHOGANY_POKEFAN_M_BLOCKS_EAST: int = 1878
## The two flags RadioTower5FRocketBossScript sets that this leg exists for. The
## second hides BLACKTHORNCITY_SUPER_NERD1, who otherwise stands on the only
## cell that reaches Blackthorn Gym's door (`maps/BlackthornCity.asm`).
const EVENT_CLEARED_RADIO_TOWER: int = 33
const EVENT_BLACKTHORN_SUPER_NERD_BLOCKS_GYM: int = 1763
## `RadioTower1FRadioCardWomanScript` on (12,6), standing up. She and the two
## men beside her are sealed in the lobby's own 8x2 desk pocket, so she is not
## reached but talked to across the `$90` counter on (12,5) from (12,4), which
## is what CheckFacingObject's doubled distance is for. She is hidden by
## EVENT_GOLDENROD_CITY_CIVILIANS, which the boss script clears, so the card is
## taken on the way back down and not before (`maps/RadioTower1F.asm`,
## `maps/RadioTower5F.asm`).
const RADIO_CARD_WOMAN_FACE: Vector2i = Vector2i(12, 4)
## Her quiz is six `yesorno`s: the offer, then five questions whose accepted
## answers are yes, yes, no, yes, no, because questions three and five branch to
## `.WrongAnswer` on `iftrue` where the others branch on `iffalse`. Zero-based,
## the way DRAGON_SHRINE_ANSWERS is.
const RADIO_CARD_ANSWERS: Array[int] = [0, 0, 0, 1, 0, 1]
## The Blackthorn Gym boulders' own object event flags, which
## `BlackthornGym1FBouldersCallback` reads back as `changeblock`s on 1F.
const EVENT_BOULDER_IN_BLACKTHORN_GYM_1: int = 1798
const EVENT_BOULDER_IN_BLACKTHORN_GYM_3: int = 1800
const EVENT_BEAT_CLAIR: int = 1220
const EVENT_ANSWERED_DRAGON_MASTER_QUIZ_WRONG: int = 193
## ENGINE_RISINGBADGE's place in source badge order (`constants/engine_flags.asm`).
const BADGE_RISING: int = 7

## Blackthorn Gym 2F's pushes in order, each an approach cell and the direction
## stepped from it (`maps/BlackthornGym2F.asm`).
##
## Four of the six boulders move. BOULDER5 on (6,1) and BOULDER6 on (8,14) are
## in neither the `stonetable` nor any event flag: they seal the two pockets the
## puzzle needs, the top-right one holding BOULDER1 and its hole, and the
## bottom one holding the row BOULDER3 has to be pushed from. Shoving each three
## cells clears both. BOULDER1 is then one push into (8,3), and BOULDER3 goes
## north until the wall at (6,6) stops it and then east into (8,7).
##
## BOULDER2 is left alone. Its hole is a `stonetable` row like the other two,
## but the 1F cell its flag opens, (2,5), is a dead end beside the entrance.
const BLACKTHORN_GYM_PUSHES: Array = [
	{
		"step": "blackthorn_gym_clear_top_pocket",
		"pushes": [
			[Vector2i(5, 1), Vector2i.RIGHT],
			[Vector2i(6, 1), Vector2i.RIGHT],
			[Vector2i(7, 1), Vector2i.RIGHT],
		],
	},
	{
		"step": "blackthorn_gym_boulder_1",
		"flag": 1798,
		"pushes": [[Vector2i(8, 1), Vector2i.DOWN]],
	},
	{
		"step": "blackthorn_gym_clear_south_pocket",
		"pushes": [
			[Vector2i(8, 13), Vector2i.DOWN],
			[Vector2i(8, 14), Vector2i.DOWN],
			[Vector2i(8, 15), Vector2i.DOWN],
		],
	},
	{
		"step": "blackthorn_gym_boulder_3",
		"flag": 1800,
		"pushes": [
			[Vector2i(6, 17), Vector2i.UP], [Vector2i(6, 16), Vector2i.UP],
			[Vector2i(6, 15), Vector2i.UP], [Vector2i(6, 14), Vector2i.UP],
			[Vector2i(6, 13), Vector2i.UP], [Vector2i(6, 12), Vector2i.UP],
			[Vector2i(6, 11), Vector2i.UP], [Vector2i(6, 10), Vector2i.UP],
			[Vector2i(6, 9), Vector2i.UP],
			[Vector2i(5, 7), Vector2i.RIGHT], [Vector2i(6, 7), Vector2i.RIGHT],
		],
	},
]

## The Dragon Shrine quiz, answered right (`maps/DragonShrine.asm`). Each
## question is a three-option `verticalmenu` and these are zero-based, so the
## source's accepted options are 1, 1, 2, 1 and 2.
const DRAGON_SHRINE_ANSWERS: Array[int] = [0, 0, 1, 0, 1]

## How many hardware frames one pushed boulder may spend sliding before the walk
## calls it stuck. The slide is STEP_FRAMES_BOULDER_PUSH, well inside this.
const OBJECT_STEP_FRAME_BUDGET: int = 64

## Route 44's Ice Path door and then every warp cell the cave is crossed by, in
## order (`maps/Route44.asm`, `maps/IcePath*.asm`).
##
## The cave is six floor-crossings, not one. Stepping on a warp takes it, so a
## floor is only crossed between warps its own walk connects, and on Ice Path
## those regions are disjoint: 1F's Route 44 door reaches the first staircase
## and nothing else, while the Blackthorn door is reached only from the second
## staircase, at the far end of the loop through B1F, both B2Fs and B3F.
##
## The `stonetable` boulders on B1F are not on this path. Their holes (B1F warps
## 3 to 6) are shortcuts into B2F Mahogany side, which the walk already reaches
## through warp 2.
const ICE_PATH_DOORS: Array = [
	{"step": "route_44_to_ice_path_1f", "cell": Vector2i(56, 7), "hm07": true},
	{"step": "ice_path_1f_to_b1f", "cell": Vector2i(37, 5)},
	{"step": "ice_path_b1f_to_b2f_mahogany", "cell": Vector2i(17, 3)},
	{"step": "ice_path_b2f_mahogany_to_b3f", "cell": Vector2i(9, 11)},
	{"step": "ice_path_b3f_to_b2f_blackthorn", "cell": Vector2i(15, 5)},
	{"step": "ice_path_b2f_blackthorn_to_b1f", "cell": Vector2i(3, 15)},
	{"step": "ice_path_b1f_to_1f", "cell": Vector2i(5, 25)},
	{"step": "ice_path_1f_to_blackthorn", "cell": Vector2i(36, 27)},
]

## Route 27's landfall from New Bark Town, which is also the
## `SCENE_ROUTE27_FIRST_STEP_INTO_KANTO` coord pair (`maps/Route27.asm`).
const ROUTE_27_LANDFALL: Vector2i = Vector2i(18, 10)

## Tohjo Falls, west to east (`maps/TohjoFalls.asm`, `maps/Route27.asm`). The
## two mouths are Route 27 cells; everything between them is inside the cave.
##
## The west door lands on (13,15) in an eight-cell pocket whose only water is to
## the left, so the surf starts on (10,14). The climb's foot is (8,12), directly
## below the four-cell `COLL_WATERFALL` column at x 8, and the descent's top is
## (18,5) on the pool, directly above the east column.
const TOHJO_WEST_MOUTH: Vector2i = Vector2i(26, 5)
const TOHJO_WEST_SHORE: Vector2i = Vector2i(10, 14)
const TOHJO_CLIMB_FOOT: Vector2i = Vector2i(8, 12)
const TOHJO_DESCENT_TOP: Vector2i = Vector2i(18, 5)
const TOHJO_EAST_LANDFALL: Vector2i = Vector2i(22, 14)
const TOHJO_EAST_DOOR: Vector2i = Vector2i(25, 15)
## The tallest waterfall either game ships is four cells, so this only has to
## outlast a stuck forced step rather than bound a real column.
const WATERFALL_RIDE_LIMIT: int = 32

## constants/event_flags.asm. `VictoryRoadRivalNext` sets it before loading the
## RIVAL1 party, so it is what says the Victory Road scene really ran.
const EVENT_RIVAL_VICTORY_ROAD: int = 1730
## `PlateauRivalBattle1`/`2` open on this, a Kanto event the walked route never
## reaches, so the plateau coord event falls straight to PlateauRivalScriptDone.
const EVENT_BEAT_RIVAL_IN_MT_MOON: int = 793
## ENGINE_FLYPOINT_INDIGO_PLATEAU, set by Route23FlypointCallback on map entry.
const ENGINE_FLYPOINT_INDIGO_PLATEAU: int = 64

## Victory Road's regions, in the order its warp maze joins them
## (`maps/VictoryRoad.asm`). The internal warps are pairs, so warp 2 at (1,49)
## arrives on warp 3 at (1,35) and warp 4 at (13,31) on warp 5 at (13,17). The
## fourth region, behind (0,11) and (0,27), is a dead end and is not walked.
## The cell below `PlateauRivalBattle1`'s coord event, which is stepped onto
## from here (`maps/IndigoPlateauPokecenter1F.asm`).
const PLATEAU_RIVAL_APPROACH: Vector2i = Vector2i(16, 5)

const VICTORY_ROAD_LADDERS: Array = [
	{"step": "victory_road_first_ladder", "cell": Vector2i(1, 49)},
	{"step": "victory_road_second_ladder", "cell": Vector2i(13, 31)},
]

## The Elite Four, in the order their doors join them. Every map is in the
## INDIGO group (16); `maps/IndigoPlateauPokecenter1F.asm` warp 4 at (14,3) is
## the only way in and each room's exit pair leads to the next.
##
## The four rooms share one shape. `<Room>DoorLocksBehindYouScript` walks the
## player four cells north of the arrival warp and walls the entrance, the boss
## stands on (5,7) and is faced from (5,8), and beating them opens the exit
## block over (4,2)/(5,2). Lance's room is taller and is not talked to at all:
## its coord events on (4,5) and (5,5) run the approach and the champion scene.
const ELITE_FOUR_ROOM_ARRIVAL: Vector2i = Vector2i(5, 17)
const ELITE_FOUR_ROOM_BOSS_FACE: Vector2i = Vector2i(5, 8)
const ELITE_FOUR_ROOM_EXIT: Vector2i = Vector2i(5, 2)
## Four `step UP` (`<Room>_EnterMovement`), so the scene settles here.
const ELITE_FOUR_ENTER_STEPS: int = 4
const INDIGO_PLATEAU_ELITE_FOUR_DOOR: Vector2i = Vector2i(14, 3)

## constants/event_flags.asm, the same numbers in both pins. Each room sets its
## own entrance flag on entry and its exit flag when its boss falls.
const ELITE_FOUR_ROOMS: Array = [
	{"step": "wills_room", "number": 3, "beat": 1464, "entrance": 777, "exit": 778},
	{"step": "kogas_room", "number": 4, "beat": 1465, "entrance": 779, "exit": 780},
	{"step": "brunos_room", "number": 5, "beat": 1466, "entrance": 781, "exit": 782},
	{"step": "karens_room", "number": 6, "beat": 1467, "entrance": 783, "exit": 784},
]

## Lance's room (16/7) and the Hall of Fame (16/8).
const LANCES_ROOM_NUMBER: int = 7
const HALL_OF_FAME_NUMBER: int = 8
const LANCES_ROOM_ARRIVAL: Vector2i = Vector2i(5, 23)
## The coord event pair is (4,5) and (5,5); the walk stops below the right one
## and steps onto it, because a resolving walk would re-dispatch the cell.
const LANCE_APPROACH: Vector2i = Vector2i(5, 6)
const EVENT_LANCES_ROOM_ENTRANCE_CLOSED: int = 785
const EVENT_BEAT_CHAMPION_LANCE: int = 1468
## `warpfacing UP, HALL_OF_FAME, 4, 13` is the last command of the champion
## scene, so the player never walks Lance's own exit door.
const HALL_OF_FAME_ARRIVAL: Vector2i = Vector2i(4, 13)
## New Bark Town and the spawn `SpawnAfterE4` picks, from
## `data/maps/spawn_points.asm`'s `spawn NEW_BARK_TOWN, 13, 6`.
const NEW_BARK_GROUP: int = 24
const NEW_BARK_NUMBER: int = 4
const POST_CREDITS_SPAWN: Vector2i = Vector2i(13, 6)
## `maps/NewBarkTown.asm`'s lab door, and Elm's own cell faced from below
## (`maps/ElmsLab.asm` object_event 5, 2).
const NEW_BARK_ELMS_LAB_DOOR: Vector2i = Vector2i(6, 3)
const ELM_FACE_CELL: Vector2i = Vector2i(5, 3)
const ELMS_LAB_DOOR: Vector2i = Vector2i(4, 11)
const EVENT_GOT_SS_TICKET_FROM_ELM: int = 36

## The Fast Ship group (`constants/map_constants.asm`'s 15th `newgroup`) and the
## passage Olivine reaches its dock through.
const FAST_SHIP_GROUP: int = 15
const FAST_SHIP_1F_NUMBER: int = 3
## `maps/OlivineCity.asm` warp 10, then the passage. The passage is two regions
## joined by its own stair pair ((15,4) to (3,2)), not one corridor, so the walk
## to the dock takes three warps rather than one.
const OLIVINE_PORT_DOOR: Vector2i = Vector2i(19, 27)
const OLIVINE_PASSAGE_STAIRS: Vector2i = Vector2i(15, 4)
const OLIVINE_PASSAGE_EXIT: Vector2i = Vector2i(3, 14)
## `maps/OlivinePort.asm`'s coord event on (7,15). The passage door is north of
## it and the dock runs south, so the cell before it is (7,14): a walk aimed
## past the event crosses it mid-step, boards on the drain's default yes and
## leaves the walk looking for its target on the ship.
const PORT_BOARDING_APPROACH: Vector2i = Vector2i(7, 14)
## `maps/FastShip1F.asm`'s grandpa coord pair on row 6, approached from the
## north: the entry scene leaves the player on (25,3) and the coord event is the
## first thing south of that, so the cell before it is (25,5).
const SHIP_GRANDPA_APPROACH: Vector2i = Vector2i(25, 5)
## constants/event_flags.asm. `maps/VermilionPort.asm` is the only place that
## sets FIRST_TIME, so it is still clear on the outbound crossing and
## `.CanArrive` wants EVENT_FAST_SHIP_FOUND_GIRL instead.
const EVENT_FAST_SHIP_FIRST_TIME: int = 48

## The rest of the Fast Ship group, and the interior crossing's own cells.
## `constants/map_constants.asm`; every number and flag below is identical in
## both pins, and the five maps' event tables are byte identical.
const FAST_SHIP_B1F_NUMBER: int = 7
const FAST_SHIP_NE_CABIN_NUMBER: int = 4
const FAST_SHIP_CAPTAIN_CABIN_NUMBER: int = 6
const VERMILION_PORT_NUMBER: int = 2

## 1F is three regions, not one deck: the boarding cell, the 132-cell deck, and
## a 25-cell west wing holding the captain's cabin door and the B1F west stairs.
## The sailor on (14,7) walls the deck off from the wing for good, so B1F is the
## only way over (`maps/FastShip1F.asm` object_event 14, 7).
const SHIP_1F_TO_B1F_EAST: Vector2i = Vector2i(30, 14)
const SHIP_1F_TO_NE_CABIN: Vector2i = Vector2i(19, 8)
const SHIP_1F_TO_CAPTAIN_CABIN: Vector2i = Vector2i(3, 13)
const SHIP_1F_SAILOR_FACE: Vector2i = Vector2i(25, 3)

## B1F's east region is 18 cells: columns 30 and 31 from row 7 down to row 15.
## The two sailors stand on (30,6) and (31,6) and the coord events below them
## toggle which one does, so the corridor north is sealed while the map scene is
## SCENE_FASTSHIPB1F_SAILOR_BLOCKS (`maps/FastShipB1F.asm`). The approach is the
## cell below the east coord event: stepping onto (31,7) is what runs it, and a
## resolving walk aimed at (31,7) would re-dispatch it until it ran out.
const SHIP_B1F_TO_1F_EAST: Vector2i = Vector2i(31, 13)
const SHIP_B1F_TO_1F_WEST: Vector2i = Vector2i(5, 11)
const SHIP_B1F_SAILOR_APPROACH: Vector2i = Vector2i(31, 8)
const SCENE_FASTSHIPB1F_NOOP: int = 1

## `maps/FastShipCabins_NNW_NNE_NE.asm`'s lazy sailor on (4,26), faced from
## below, and the NE cabin's own door back to 1F.
const SHIP_NE_CABIN_DOOR: Vector2i = Vector2i(2, 24)
const SHIP_LAZY_SAILOR_FACE: Vector2i = Vector2i(4, 27)

## The captain's cabin is the third section of
## `maps/FastShipCabins_SE_SSE_CaptainsCabin.asm`, reached from 1F's west wing.
## The granddaughter stands on (2,25) with wall on three sides, so she is faced
## from (1,25). `SSAquaCaptainsCabinWarpsToGrandpasCabinMovement` then carries
## the player one cell right and six up, through five rows of wall, onto (2,19),
## which is the grandpa cabin's own door back to 1F's east deck.
const SHIP_GRANDDAUGHTER_FACE: Vector2i = Vector2i(1, 25)
const SHIP_GRANDPA_CABIN_DOOR: Vector2i = Vector2i(2, 19)

## Vermilion City (12/3) and its gym (12/11), the first Kanto maps the route
## walks. `maps/VermilionPortPassage.asm` is two regions joined by its own stair
## pair ((3,2) to (15,4)), the way Olivine's passage is, so the walk from the
## dock to the city takes three warps.
const VERMILION_GROUP: int = 12
const VERMILION_CITY_NUMBER: int = 3
const VERMILION_GYM_NUMBER: int = 11
const VERMILION_PORT_EXIT: Vector2i = Vector2i(9, 5)
const VERMILION_PASSAGE_STAIRS: Vector2i = Vector2i(3, 2)
const VERMILION_PASSAGE_EXIT: Vector2i = Vector2i(15, 0)
## `maps/VermilionCity.asm` warp 7, entered from below: the row above it is the
## mart block's wall, so (10,20) is its only approach.
const VERMILION_GYM_DOOR: Vector2i = Vector2i(10, 19)
## And the gym's whole yard, 42 cells of it, is walled off from the rest of the
## city by one `COLL_CUT_TREE` ($12) on (13,18). Cutting it is the only way in,
## so this is the first Kanto cell the route has to open rather than walk.
const VERMILION_GYM_TREE_APPROACH: Vector2i = Vector2i(13, 17)
## `maps/VermilionGym.asm` puts Surge on (5,2) behind the pillar grid, faced
## from the cell below. The gym has no scene scripts and no callbacks: unlike
## its Gen 1 self it is open from the door, and the three trainers are sight
## lines across the grid rather than a gate.
const SURGE_FACE: Vector2i = Vector2i(5, 3)
## ENGINE_THUNDERBADGE's place in source badge order, for
## Gen2WorldState.badge_flag(), and the flypoint the city's own NEWMAP callback
## sets (`constants/engine_flags.asm`).
const BADGE_THUNDER: int = 10
const ENGINE_FLYPOINT_VERMILION: int = 58
## The gym's own exit, and the tree faced from the yard side. Leaving the gym
## reloads the city, which regrows the tree behind the player, so the way out is
## cut a second time exactly as the way in was.
const VERMILION_GYM_EXIT: Vector2i = Vector2i(4, 17)
const VERMILION_GYM_TREE_RETURN: Vector2i = Vector2i(13, 19)

## Route 6 and Saffron City. Vermilion connects north to Route 6
## (`data/maps/attributes.asm`), but Saffron is entered through
## `ROUTE_6_SAFFRON_GATE` rather than a connection, the way Violet and Ecruteak
## are on the Johto legs.
const ROUTE_6_GROUP: int = 12
const ROUTE_6_NUMBER: int = 1
const ROUTE_6_SAFFRON_GATE_DOOR: Vector2i = Vector2i(6, 1)
const SAFFRON_GROUP: int = 25
const SAFFRON_CITY_NUMBER: int = 2
const SAFFRON_GYM_NUMBER: int = 4
const SAFFRON_GYM_DOOR: Vector2i = Vector2i(34, 3)

## The lost-doll errand and the Magnet Train it pays for. `maps/SaffronCity.asm`
## warp 8 is the Copycat's house, warp 12 the Route 6 gate and warp 6 the train
## station; `maps/VermilionCity.asm` warp 3 is the Pokemon Fan Club.
##
## The order is the cartridge's own. `PokemonFanClubClefairyGuyScript` reads
## EVENT_MET_COPYCAT_FOUND_OUT_ABOUT_LOST_ITEM before he parts with the doll, and
## only `Copycat`'s `.TalkAboutLostItem` sets it, which itself needs
## EVENT_RETURNED_MACHINE_PART from the Power Plant. So the Copycat is visited
## first, empty-handed, and the walk to Vermilion is what the visit buys.
const SAFFRON_COPYCAT_HOUSE_DOOR: Vector2i = Vector2i(9, 11)
const COPYCAT_HOUSE_STAIRS_UP: Vector2i = Vector2i(2, 0)
const COPYCAT_HOUSE_STAIRS_DOWN: Vector2i = Vector2i(3, 0)
const COPYCAT_HOUSE_EXIT: Vector2i = Vector2i(2, 7)
## She is a variable sprite only her own script assigns, so she stands here with
## no sprite of her own until the first talk runs `variablesprite`.
const COPYCAT_FACE: Vector2i = Vector2i(5, 3)
const SAFFRON_ROUTE_6_GATE_DOOR: Vector2i = Vector2i(16, 33)
const ROUTE_6_GATE_SOUTH_DOOR: Vector2i = Vector2i(4, 7)
const VERMILION_FAN_CLUB_DOOR: Vector2i = Vector2i(7, 13)
const FAN_CLUB_EXIT: Vector2i = Vector2i(2, 7)
const CLEFAIRY_GUY_FACE: Vector2i = Vector2i(1, 3)
const EVENT_MET_COPYCAT_FOUND_OUT_ABOUT_LOST_ITEM: int = 207
const EVENT_RETURNED_LOST_ITEM_TO_COPYCAT: int = 208
const EVENT_GOT_PASS_FROM_COPYCAT: int = 209
const EVENT_GOT_LOST_ITEM_FROM_FAN_CLUB: int = 210
## `constants/item_constants.asm`.
const ITEM_LOST_ITEM: int = 0x82
const ITEM_PASS: int = 0x86

## Both Magnet Train stations are two regions with no seam: the lobby is rows 10
## to 17, the platform rows 2 to 8, and row 9 is solid between them. The officer
## stands inside that solid row on (9,9) and is talked to across it, and his
## script's `applymovement` is the only thing that ever puts the player on the
## platform, because a scripted step ignores collision. It ends on the train door
## and `warpcheck` takes it.
const SAFFRON_TRAIN_STATION_DOOR: Vector2i = Vector2i(8, 3)
const SAFFRON_TRAIN_STATION_EXIT: Vector2i = Vector2i(8, 17)
const TRAIN_OFFICER_FACE: Vector2i = Vector2i(9, 10)
const TRAIN_LANDING: Vector2i = Vector2i(11, 5)
## The arrival coord event is live on both stations, so it is stepped onto and
## drained rather than walked to.
const TRAIN_ARRIVAL_COORD: Vector2i = Vector2i(11, 6)
const GOLDENROD_GROUP: int = 11
const GOLDENROD_MAGNET_TRAIN_STATION_NUMBER: int = 7
const SAFFRON_MAGNET_TRAIN_STATION_NUMBER: int = 9
## `yesorno` answers, zero-based the way RADIO_CARD_ANSWERS is: yes boards.
const BOARD_THE_TRAIN: Array[int] = [0]

## `maps/SaffronGym.asm` is nine rooms walled off from each other, joined only by
## fifteen pairs of self-warps. Sabrina's room holds exactly one pad, warp 32 on
## (11,9), and the only pad that reaches it is warp 17 on (1,5), so the way in is
## a fixed chain rather than anything a walk can plan: the entrance room's only
## pad, then one pad per room until the corner room that holds warp 17.
const SAFFRON_GYM_MAZE: Array[Vector2i] = [
	Vector2i(11, 15),  # warp 3 -> 18 (19,17)
	Vector2i(15, 17),  # warp 11 -> 26 (5,15)
	Vector2i(5, 17),   # warp 12 -> 27 (5,11)
	Vector2i(1, 11),   # warp 6 -> 21 (5,5)
	Vector2i(1, 5),    # warp 17 -> 32 (11,9), Sabrina's room
]
const SABRINA_FACE: Vector2i = Vector2i(9, 9)
## ENGINE_MARSHBADGE's place in source badge order, and Saffron's own flypoint.
const BADGE_MARSH: int = 13
const ENGINE_FLYPOINT_SAFFRON: int = 60

## Every pad is one half of a bidirectional pair, so the way out of Sabrina's
## room is SAFFRON_GYM_MAZE reversed: each landing shares a room with the next
## pad, and the last one is the entrance room the exit warps sit in.
const SAFFRON_GYM_MAZE_OUT: Array[Vector2i] = [
	Vector2i(11, 9),   # warp 32 -> 17 (1,5)
	Vector2i(5, 5),    # warp 21 -> 6 (1,11)
	Vector2i(5, 11),   # warp 27 -> 12 (5,17)
	Vector2i(5, 15),   # warp 26 -> 11 (15,17)
	Vector2i(19, 17),  # warp 18 -> 3 (11,15), the entrance room
]
const SAFFRON_GYM_EXIT: Vector2i = Vector2i(8, 17)

## Route 7 and Celadon City. Saffron connects west to Route 7
## (`data/maps/attributes.asm`) but the crossing is `ROUTE_7_SAFFRON_GATE`, the
## way Route 6's is; Route 7's own west edge is a real open connection into
## Celadon, so that half needs no gate.
const CELADON_GROUP: int = 21
const ROUTE_7_NUMBER: int = 1
const CELADON_CITY_NUMBER: int = 4
const CELADON_GYM_NUMBER: int = 21
const SAFFRON_ROUTE_7_GATE_DOOR: Vector2i = Vector2i(0, 24)
## Celadon ships exactly one `COLL_CUT_TREE` ($12), on (28,35), and it is the
## only seam between the 619-cell city and the 70-cell gym yard. Cut is the
## price of this badge the way it was of the Thunder Badge.
const CELADON_GYM_TREE_APPROACH: Vector2i = Vector2i(28, 34)
## `maps/CeladonGym.asm` declares neither a scene nor a callback, so Erika
## answers as soon as she is faced. Her four trainers are sight lines across the
## flower beds: the twins on (4,10)/(5,10) and Beauty Julia on (3,5) each watch
## a whole row's only gap, and row 8's four cells are covered by Picnicker Tanya
## and Lass Michelle between them, so three of the five fights are unavoidable.
const CELADON_GYM_DOOR: Vector2i = Vector2i(10, 29)
const ERIKA_FACE: Vector2i = Vector2i(5, 4)
## ENGINE_RAINBOWBADGE's place in source badge order, and Celadon's flypoint.
const BADGE_RAINBOW: int = 11
const ENGINE_FLYPOINT_CELADON: int = 61
## The gym's own exit, and the tree faced from the yard side, the way Vermilion's
## pair is: leaving reloads the city and regrows the tree behind the player.
const CELADON_GYM_EXIT: Vector2i = Vector2i(4, 17)
const CELADON_GYM_TREE_RETURN: Vector2i = Vector2i(27, 35)
## `maps/Route7.asm` warp 1, the gate door taken back east into Saffron.
const ROUTE_7_GATE_DOOR: Vector2i = Vector2i(15, 6)

## Route 5 and Cerulean City. Saffron's north exit is a gate building too
## (`maps/SaffronCity.asm` warp 9 to ROUTE_5_SAFFRON_GATE); north of it Route 5
## connects straight onto Cerulean (`data/maps/attributes.asm`).
const SAFFRON_ROUTE_5_GATE_DOOR: Vector2i = Vector2i(18, 3)
const ROUTE_5_NUMBER: int = 1
const CERULEAN_GROUP: int = 7
const CERULEAN_CITY_NUMBER: int = 17
const ENGINE_FLYPOINT_CERULEAN: int = 56
const CERULEAN_GYM_NUMBER: int = 6
const ROUTE_9_NUMBER: int = 13
const ROUTE_10_NORTH_NUMBER: int = 14
const POWER_PLANT_NUMBER: int = 10
const ROUTE_24_NUMBER: int = 15
const ROUTE_25_NUMBER: int = 16

## Route 9 is sealed from Cerulean's own crossing by one COLL_CUT_TREE on (5,8),
## faced from (4,8) heading east and from (6,8) heading back west. The same cut
## opens the shore on (42,4), which is the only way to the Power Plant: the
## plant's region has no map edge and no walkable neighbour, and Route 10
## North's own southern shore is behind a buoy line that walls its north face.
const ROUTE_9_CUT_EAST_APPROACH: Vector2i = Vector2i(4, 8)
const ROUTE_9_CUT_WEST_APPROACH: Vector2i = Vector2i(6, 8)
const ROUTE_9_SHORE: Vector2i = Vector2i(42, 4)
## `maps/Route10North.asm` warp 2, the cell the river lands on beside it, and the
## plant's own door back out.
const POWER_PLANT_SHORE: Vector2i = Vector2i(3, 11)
const POWER_PLANT_DOOR: Vector2i = Vector2i(3, 9)
const POWER_PLANT_EXIT: Vector2i = Vector2i(2, 17)
## `maps/PowerPlant.asm`: the manager on (14,10). The guard's phone call on
## (5,12) is armed by his first talk and crossed by the walk back out, so it
## needs no cell of its own here.
const POWER_PLANT_MANAGER_FACE: Vector2i = Vector2i(14, 11)
## `maps/CeruleanCity.asm` warp 5 and the gym's own exit.
const CERULEAN_GYM_DOOR: Vector2i = Vector2i(30, 23)
const CERULEAN_GYM_EXIT: Vector2i = Vector2i(4, 15)
## `maps/CeruleanGym.asm`: Misty on (5,3), faced from the pool's north bank.
## ENGINE_CASCADEBADGE's place in source badge order.
const MISTY_FACE: Vector2i = Vector2i(5, 4)
const BADGE_CASCADE: int = 9
## The MACHINE_PART the Route 24 grunt says he dropped in the gym pool. Its own
## cell is water, so it is faced from the bank directly above it.
const MACHINE_PART_APPROACH: Vector2i = Vector2i(3, 7)
## `maps/Route24.asm`'s only object, and Route 25's date coord events. (43,7) is
## the one neighbour of (42,7) that is neither the other half of the pair nor
## wall.
const ROUTE_24_ROCKET_FACE: Vector2i = Vector2i(8, 8)
const ROUTE_25_DATE_COORD: Vector2i = Vector2i(42, 7)
const ROUTE_25_DATE_APPROACH: Vector2i = Vector2i(43, 7)
## constants/event_flags.asm, same numbers in both pins.
const EVENT_RETURNED_MACHINE_PART: int = 201
const EVENT_MET_MANAGER_AT_POWER_PLANT: int = 202
const EVENT_RESTORED_POWER_TO_KANTO: int = 205
const EVENT_TRAINERS_IN_CERULEAN_GYM: int = 1903
## The three swimmer flags `CeruleanGymMistyScript` sets itself, and her own.
const EVENT_BEAT_MISTY: int = 1222
const CERULEAN_GYM_TRAINER_FLAGS: Array[int] = [1017, 1018, 1448]

## Lavender Town, reached back through Saffron. Route 5's own warp to its gate,
## then Saffron's east exit, which is a third gate building
## (`maps/SaffronCity.asm` warp 14 to ROUTE_8_SAFFRON_GATE, itself in the
## LAVENDER group). Route 8 then connects straight onto Lavender.
const ROUTE_5_GATE_DOOR: Vector2i = Vector2i(8, 17)
const SAFFRON_ROUTE_8_GATE_DOOR: Vector2i = Vector2i(39, 22)
const LAVENDER_GROUP: int = 18
const ROUTE_8_NUMBER: int = 1
const LAVENDER_TOWN_NUMBER: int = 4
const LAV_RADIO_TOWER_1F_NUMBER: int = 12
const ENGINE_FLYPOINT_LAVENDER: int = 59
## `maps/LavenderTown.asm` warp 7, and the gentleman inside on (9,1). He is the
## one thing on this leg the errand behind it unlocks: `ENGINE_EXPN_CARD` is
## three in both pins, sitting in wPokegearFlags ahead of the Crystal-only
## ENGINE_MOBILE_SYSTEM, so it needs no profile split.
const LAVENDER_RADIO_TOWER_DOOR: Vector2i = Vector2i(14, 5)
const LAVENDER_RADIO_TOWER_EXIT: Vector2i = Vector2i(2, 7)
const RADIO_TOWER_GENTLEMAN_FACE: Vector2i = Vector2i(9, 2)
const ENGINE_EXPN_CARD: int = 3
## `MeetMomScript`'s own `setflag ENGINE_POKEGEAR`, four in both pins and so in
## wPokegearFlags with the card above, which is what says the scene really ran.
const ENGINE_POKEGEAR: int = 4

## Fuchsia City, four connected routes south of Lavender with one gate at the
## end (`data/maps/attributes.asm`, `maps/Route15.asm` warps 1 and 2 into
## `ROUTE_15_FUCHSIA_GATE`). Routes 13, 14 and 15 are in the FUCHSIA group.
const ROUTE_12_NUMBER: int = 2
const FUCHSIA_GROUP: int = 17
const ROUTE_13_NUMBER: int = 1
const ROUTE_14_NUMBER: int = 2
const ROUTE_15_NUMBER: int = 3
const FUCHSIA_CITY_NUMBER: int = 5
const FUCHSIA_GYM_NUMBER: int = 8
const ROUTE_15_GATE_DOOR: Vector2i = Vector2i(2, 4)
const ENGINE_FLYPOINT_FUCHSIA: int = 62
## `maps/FuchsiaCity.asm` warp 3, and Janine on (1,10) inside her own maze.
const FUCHSIA_GYM_DOOR: Vector2i = Vector2i(8, 27)
const JANINE_FACE: Vector2i = Vector2i(1, 9)
const BADGE_SOUL: int = 12
## `FuchsiaGymJanineScript` sets her own flag and all four of her disguised
## trainers', then hands over TM06 through its own `verbosegiveitem`.
const EVENT_BEAT_JANINE: int = 1225
const FUCHSIA_GYM_TRAINER_FLAGS: Array[int] = [1303, 1306, 1154, 1054]
const EVENT_GOT_TM06_TOXIC: int = 221

## Fuchsia back to Vermilion, which is four connections and one gate, not the
## walk back through Lavender and Saffron the route came by: Route 12 connects
## west onto Route 11 and Route 11 west onto Vermilion City
## (`data/maps/attributes.asm`), and `maps/Route11.asm` declares no warps at
## all, so nothing on that pair is gated. `maps/FuchsiaGym.asm` warps 1 and 2
## both land on Fuchsia's warp 3.
const FUCHSIA_GYM_EXIT: Vector2i = Vector2i(4, 17)
## `maps/FuchsiaCity.asm` warp 8, the east half of the Route 15 gate pair.
const FUCHSIA_ROUTE_15_GATE_DOOR: Vector2i = Vector2i(37, 22)
const ROUTE_11_NUMBER: int = 2

## Vermilion's Snorlax. The whole chain is pinned and checked against the cache
## by `tools/checks/radio.gd`, which is where these values are explained; only
## the cells the walk needs are repeated here.
##
## `maps/VermilionCity.asm` object 4 is a BIG_OBJECT filling (34,8) to (35,9),
## and the cave mouth on (34,7) is sealed until it moves.
##
## The route arrives from Route 11, not from the port, and that lands it inside
## the eight-cell pocket the Snorlax's own body seals off the city's east edge:
## (36..39, 8) and (36..39, 9), measured against the cache. So the walk uses
## (36,9) facing left, which is the last of `SnorlaxAwake.ProximityCoords` and
## the only kind of cell an eastbound player ever has. Three of those five
## coordinates sit in pockets like this one, which is why the source lists all
## five rather than only the two the port side can stand on.
const SNORLAX_TALK: Vector2i = Vector2i(36, 9)
const DIGLETTS_CAVE_MOUTH: Vector2i = Vector2i(34, 7)
## `engine/pokegear/pokegear.asm` RadioChannels: 20.0, the Poke Flute channel.
const KNOB_POKE_FLUTE: int = 78
const EVENT_FOUGHT_SNORLAX: int = 1872
const EVENT_VERMILION_CITY_SNORLAX: int = 1904

## Diglett's Cave, the one door into west Kanto (`maps/DiglettsCave.asm`).
##
## Three walkable regions, not one tunnel, so it is crossed by warps: the
## Vermilion entrance sits in a 14-cell room whose only ladder is (5,31); that
## lands on (17,33) in the 99-cell middle, which reaches the second ladder on
## (3,3); and that lands on (17,3) in a 15-cell room holding the Route 2 door.
## Measured against the cache, not read off the warp table, since the table
## alone does not say which cells share a region.
const DIGLETTS_CAVE_GROUP: int = 3
const DIGLETTS_CAVE_NUMBER: int = 84
const DIGLETTS_CAVE_CHAIN: Array[Vector2i] = [
	Vector2i(5, 31), Vector2i(3, 3), Vector2i(15, 5),
]

## Route 2 and Pewter City. The cave lands in a 125-cell pocket closed by two
## cut trees, and the northern one on (5,8) is the only one that opens the rest
## of the route; cutting it reaches 469 cells and both the Pewter and the
## Viridian crossing (`tools/checks/radio.gd` checks both counts).
const ROUTE_2_GROUP: int = 23
const ROUTE_2_NUMBER: int = 1
const ROUTE_2_CUT_APPROACH: Vector2i = Vector2i(5, 9)
const PEWTER_GROUP: int = 14
const PEWTER_CITY_NUMBER: int = 2
## `maps/PewterCity.asm` warp 2, and its own NEWMAP flypoint callback.
const PEWTER_GYM_DOOR: Vector2i = Vector2i(16, 17)
const ENGINE_FLYPOINT_PEWTER: int = 55
## `maps/PewterGym.asm`: Brock on (5,1), faced from the cell below. Camper Jerry
## on (2,5) watches three cells east along row 5, which the walk up column 5
## crosses, so his battle is unavoidable. Beating Brock sets his flag too.
const BROCK_FACE: Vector2i = Vector2i(5, 2)
const BADGE_BOULDER: int = 8
const EVENT_BEAT_BROCK: int = 1221
const EVENT_BEAT_CAMPER_JERRY: int = 1067
## `maps/PewterGym.asm` warps 1 and 2, both back onto Pewter's warp 2.
const PEWTER_GYM_EXIT: Vector2i = Vector2i(4, 13)

## South from Pewter to Cinnabar: Route 2, Viridian City, Route 1, Pallet Town,
## Route 21 and Cinnabar Island are six plain connections with no gate building
## and no door on any of them (`data/maps/attributes.asm`, and neither Route 1
## nor Route 21 declares a warp at all). Coming back onto Route 2 from Pewter
## lands in its main region, which already holds the Viridian crossing, so the
## cut tree is not on this half of the walk.
const VIRIDIAN_CITY_NUMBER: int = 3
const PALLET_GROUP: int = 13
const ROUTE_1_NUMBER: int = 1
const PALLET_TOWN_NUMBER: int = 2
const ENGINE_FLYPOINT_VIRIDIAN: int = 54
const ENGINE_FLYPOINT_PALLET: int = 53

## Pallet Town's own pond is the route's way south: its south edge is sixteen
## cells of water on x=4 to 7, and the land beside it is (4,13). Everything from
## there to Seafoam Gym's door is surfed.
const PALLET_SURF_APPROACH: Vector2i = Vector2i(4, 13)
const SEAFOAM_GROUP: int = 6
const ROUTE_21_NUMBER: int = 7
const CINNABAR_ISLAND_NUMBER: int = 8
const ROUTE_20_NUMBER: int = 6
const SEAFOAM_GYM_NUMBER: int = 4

## Cinnabar Island is two land regions with no seam between them, so which cell
## the crossing lands on decides whether Blue is reachable at all. Route 21's
## south edge is water from x=1 to 14, and Cinnabar's row 0 is water on x=1 to 3
## and land on x=11 to 18: crossing on the eastern half exits the water into an
## 89-cell region that reaches neither Blue nor the Pokecenter, so the walk stays
## on the water down the island's west side and lands on (4,10) instead, in the
## 51-cell region that holds both.
const CINNABAR_LANDING: Vector2i = Vector2i(4, 10)
## `maps/CinnabarIsland.asm` object 1 on (9,6), walled on three sides, so (8,6)
## facing right is its only approach. `CinnabarIslandBlue` is what clears
## EVENT_VIRIDIAN_GYM_BLUE and so the only thing that opens Viridian Gym.
const BLUE_FACE: Vector2i = Vector2i(8, 6)
const EVENT_VIRIDIAN_GYM_BLUE: int = 1910
const ENGINE_FLYPOINT_CINNABAR: int = 63

## Cinnabar's east edge is one cell, (19,16), and it is water, so the leg surfs
## again from the same shore it landed on. `Route20ClearRocksCallback` is a
## MAPCALLBACK_NEWMAP, so arriving is what sets EVENT_CINNABAR_ROCKS_CLEARED and
## unseals Fuchsia's south edge; nothing on the route walks that way, but the
## flag is the reason this leg comes before Viridian's.
const CINNABAR_SURF_APPROACH: Vector2i = Vector2i(4, 10)
const EVENT_CINNABAR_ROCKS_CLEARED: int = 215
## Route 20's island cluster, landed on from the east and not the west. The
## channel on x=26 and 27 that runs up the island's west shore is walled off from
## the open sea on every side: column 25 is wall from row 2 to 13, row 1 closes it
## above and row 13's own eleven wall cells close it below. The east shore is
## open water, so (41,8) is the landfall and (38,7) the `$7b` cave tile that
## warps into the gym.
const ROUTE_20_LANDING: Vector2i = Vector2i(41, 8)
const SEAFOAM_GYM_DOOR: Vector2i = Vector2i(38, 7)
## `maps/SeafoamGym.asm`: Blaine on (5,2) inside a 13-cell cave, faced from the
## cell below. His script `appear`s the gym guide, which is a `clearevent` on the
## guide's own hide flag, and it runs only on the branch a won battle takes.
const BLAINE_FACE: Vector2i = Vector2i(5, 3)
const BADGE_VOLCANO: int = 14
const EVENT_BEAT_BLAINE: int = 1227
const EVENT_SEAFOAM_GYM_GYM_GUIDE: int = 1911
## `maps/SeafoamGym.asm` warp 1, back onto the Route 20 cave tile.
const SEAFOAM_GYM_EXIT: Vector2i = Vector2i(5, 5)
## The island's east shore again, surfed from rather than landed on.
const ROUTE_20_SURF_APPROACH: Vector2i = Vector2i(41, 8)
## Pallet's pond from the sea side: the same sixteen cells, landed on at (4,13).
const PALLET_LANDING: Vector2i = Vector2i(4, 13)

## Viridian Gym, the last badge on the walked route. `maps/ViridianGym.asm`
## declares neither a scene nor a callback and ships no trainer: both its objects
## are hidden by EVENT_VIRIDIAN_GYM_BLUE, so the gym is empty until Cinnabar's
## Blue clears it, and that is the whole gate.
const VIRIDIAN_GYM_NUMBER: int = 4
const VIRIDIAN_GYM_DOOR: Vector2i = Vector2i(32, 7)
const BLUE_GYM_FACE: Vector2i = Vector2i(5, 4)
const BADGE_EARTH: int = 15
const EVENT_BEAT_BLUE: int = 1228
const VIRIDIAN_GYM_EXIT: Vector2i = Vector2i(4, 17)

## Mt. Silver. Every step past the gate is a warp or a connection, so the leg
## needs only the map the walk west crosses onto (`constants/map_constants.asm`,
## `data/maps/attributes.asm`). The three cave rooms are the one place the
## profiles renumber, 74 to 76 in Crystal and 66 to 68 in Gold and Silver, which
## is why `tools/checks/mt_silver.gd` splits them and this Crystal-only walk
## does not name them at all.
const SILVER_GROUP: int = 19
const SILVER_CAVE_OUTSIDE_NUMBER: int = 2
const ROUTE_22_NUMBER: int = 2
## `maps/SilverCaveOutside.asm`'s MAPCALLBACK_NEWMAP, the leg's one flypoint.
const ENGINE_FLYPOINT_SILVER_CAVE: int = 76

## Pallet Town and Oak's lab. `maps/OaksLab.asm`'s Oak reads VAR_BADGES and takes
## `.OpenMtSilver` only on `ifequal NUM_BADGES`, which is sixteen
## (`constants/ram_constants.asm`), so this errand is the last badge's own
## reward. Every branch then falls into `.CheckPokedex` and its
## `special ProfOaksPCBoot`.
const OAKS_LAB_DOOR: Vector2i = Vector2i(12, 11)
const OAKS_LAB_EXIT: Vector2i = Vector2i(4, 11)
const OAK_FACE: Vector2i = Vector2i(4, 3)
const EVENT_TALKED_TO_OAK_IN_KANTO: int = 225
const EVENT_OPENED_MT_SILVER: int = 1871

## The Victory Road Gate is three regions joined by two single cells, and a black
## belt stands in each (`maps/VictoryRoadGate.asm`). The right belt on (12,5)
## joins the corridor to the Route 22 arm and is hidden by EVENT_FOUGHT_SNORLAX,
## which `_wake_snorlax()` already set; the left belt on (7,5) joins it to the
## Route 28 arm and is hidden by EVENT_OPENED_MT_SILVER. Oak is therefore the
## gate on Mt. Silver, not a courtesy, and `tools/checks/mt_silver.gd` pins all
## four flag combinations.
const ROUTE_22_GATE_DOOR: Vector2i = Vector2i(13, 5)
const GATE_WEST_DOOR: Vector2i = Vector2i(1, 7)

## Silver Cave. Every room is one region, so each ladder is walked to directly.
const SILVER_CAVE_POKECENTER_DOOR: Vector2i = Vector2i(23, 19)
const SILVER_CAVE_POKECENTER_EXIT: Vector2i = Vector2i(3, 7)
## The counter tile below the nurse is not walkable, the same as every other
## Pokemon Center on the route, so she is faced from a cell placed directly.
const SILVER_CAVE_NURSE_STAND: Vector2i = Vector2i(3, 2)
const SILVER_CAVE_MOUTH: Vector2i = Vector2i(18, 11)
const SILVER_CAVE_ROOM_1_LADDER: Vector2i = Vector2i(15, 1)
const SILVER_CAVE_ROOM_2_LADDER: Vector2i = Vector2i(11, 5)
## Red's own hide flag is EVENT_RED_IN_MT_SILVER, already pinned below for the
## Hall of Fame that clears it.
const RED_FACE: Vector2i = Vector2i(9, 11)
## `data/trainers/parties.asm`: trainer class RED ($3f) with one party, which
## `loadtrainer`'s one-based operand reaches as index 0.
const TRAINER_CLASS_RED: int = 63

## constants/item_constants.asm.
const ITEM_MACHINE_PART: int = 0x80

## constants/event_flags.asm, same numbers in both pins.
const EVENT_FAST_SHIP_HAS_ARRIVED: int = 49
const EVENT_FAST_SHIP_FOUND_GIRL: int = 50
const EVENT_FAST_SHIP_LAZY_SAILOR: int = 51
const EVENT_FAST_SHIP_INFORMED_ABOUT_LAZY_SAILOR: int = 52
const EVENT_GOT_METAL_COAT_FROM_GRANDPA: int = 113
const EVENT_FAST_SHIP_NE_CABIN_SAILOR: int = 1837
const EVENT_GOT_TM19_GIGA_DRAIN: int = 220

## New Bark Town to Olivine City. Map connections except where a `gate` cell is
## named, which is the door of a gate building whose far warp is the join
## (`data/maps/attributes.asm`, `maps/Route31.asm`, `maps/EcruteakCity.asm`).
const KANTO_RETURN_LEGS: Array = [
	{"step": "new_bark_to_route_29", "direction": "west", "group": 24, "number": 3},
	{"step": "route_29_to_cherrygrove", "direction": "west", "group": 26, "number": 3},
	{"step": "cherrygrove_to_route_30", "direction": "north", "group": 26, "number": 1},
	{"step": "route_30_to_route_31", "direction": "north", "group": 26, "number": 2},
	{"step": "route_31_to_violet", "gate": Vector2i(4, 6), "group": 10, "number": 5},
	{"step": "violet_to_route_36", "direction": "west", "group": 10, "number": 3},
	{"step": "route_36_to_route_37", "direction": "north", "group": 10, "number": 4},
	{"step": "route_37_to_ecruteak", "direction": "north", "group": 4, "number": 9},
	{"step": "ecruteak_to_route_38", "gate": Vector2i(0, 18), "group": 1, "number": 12},
	{"step": "route_38_to_route_39", "direction": "west", "group": 1, "number": 13},
	{"step": "route_39_to_olivine", "direction": "south", "group": 1, "number": 14},
]

## The flags `HallOfFameEnterScript` writes before `halloffame`.
const EVENT_BEAT_ELITE_FOUR: int = 68
const EVENT_TELEPORT_GUY: int = 1916
const EVENT_RIVAL_SPROUT_TOWER: int = 1732
const EVENT_RED_IN_MT_SILVER: int = 1890

## Maps this walk names by id rather than by cell, where the two profiles
## disagree (`constants/map_constants.asm`). A map number counts from its
## group's first entry, so a map pokegold does not ship shifts every later
## number in that group: group 3 runs eight lower from `UNION_CAVE_1F` on,
## because pokecrystal inserts eight Ruins of Alph word and item rooms, and
## group 11 shifts around `GOLDENROD_POKECENTER_1F` and the absent
## `GOLDENROD_DEPT_STORE_ROOF`. Only the ids this walk resolves are listed;
## everything else it reaches is found by the cell it stands on, which no
## renumbering moves.
const MAP_IDS: Dictionary = {
	&"ILEX_FOREST": {&"crystal": Vector2i(3, 52), &"gold": Vector2i(3, 44)},
	&"MAHOGANY_MART_1F": {&"crystal": Vector2i(3, 48), &"gold": Vector2i(3, 40)},
	&"TEAM_ROCKET_BASE_B2F": {&"crystal": Vector2i(3, 50), &"gold": Vector2i(3, 42)},
	&"TEAM_ROCKET_BASE_B3F": {&"crystal": Vector2i(3, 51), &"gold": Vector2i(3, 43)},
}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 5:
		push_error("Usage: preview_world_story.gd -- <game> <group> <map> <x> <y> [facing] [flags]")
		quit(1)
		return

	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No usable imported cache for %s." % args[0])
		quit(1)
		return

	var state := Gen2WorldState.new()
	if args.size() >= 7:
		for raw_flag: String in args[6].split(",", false):
			if raw_flag.is_valid_int():
				state.set_event_flag(int(raw_flag))

	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, int(args[1]), int(args[2]), Vector2i(int(args[3]), int(args[4])), state
	)
	if world == null:
		push_error("The imported cache does not contain map %s/%s." % [args[1], args[2]])
		quit(1)
		return

	if args.size() >= 6:
		world.player_facing = int(args[5])
	var entry: Array = world.dispatch_map_entry()
	var interaction: Array = world.interact()
	var output: Dictionary = {
		"game": String(data.id),
		"map": world.map_id(),
		"player_cell": world.player_cell,
		"facing": world.player_facing,
		"event_flags": state.event_flags(),
		"entry": entry,
		"interaction": interaction,
		"pending_input": world.pending_script_input(),
		"visible_objects": world.visible_objects().size(),
		"snapshot": world.snapshot().to_dict(),
	}
	if args.size() >= 8 and args[7] == "home":
		output["home_path"] = _home_path(data)
	if args.size() >= 9 and args[8] == "story":
		output["story_path"] = _story_path(data)
	print(JSON.stringify(output))
	quit(0)


func _home_path(data: GameData) -> Array:
	var path: Array = []
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 24, 7, Vector2i.ZERO)
	if world == null:
		return [{"ok": false, "reason": "missing home map"}]
	var stair_warp: Dictionary = _warp_to(world.current_map, 24, 6)
	if stair_warp.is_empty():
		return [{"ok": false, "reason": "missing home stair warp"}]
	world.player_cell = Vector2i(stair_warp["x"], stair_warp["y"])
	path.append({"step": "players_house_2f", "map": _map_value(world), "cell": _cell_value(world)})
	var transition: Dictionary = world.try_warp()
	path.append({"step": "stairs_to_1f", "transition": _transition_value(transition)})
	if not bool(transition.get("ok", false)):
		return path

	var town_warp: Dictionary = _warp_to(world.current_map, 24, 4)
	if town_warp.is_empty():
		path.append({"ok": false, "reason": "missing first-floor town warp"})
		return path
	world.player_cell = Vector2i(town_warp["x"], town_warp["y"])
	path.append({"step": "players_house_1f", "map": _map_value(world), "cell": _cell_value(world)})
	transition = world.try_warp()
	path.append({"step": "front_door_to_new_bark", "transition": _transition_value(transition)})
	if bool(transition.get("ok", false)):
		var callbacks: Array = world.dispatch_map_entry()
		path.append({
			"step": "new_bark_entry_callbacks",
			"map": _map_value(world),
			"cell": _cell_value(world),
			"callback_count": callbacks.size(),
			"callback_statuses": _statuses(callbacks),
		})
	return path


func _story_path(data: GameData) -> Dictionary:
	# The walked route is a new game, so it starts on the new game's own world
	# state rather than a bare one: Gen2WorldSpawn is what the launcher hands the
	# screen, and its SPAWN_HOME record carries the source start money. Without
	# it the route reaches Blackthorn with nothing to spend.
	var spawn: Gen2WorldSnapshot = Gen2WorldSpawn.new_game_snapshot(data)
	if spawn == null:
		return {"ok": false, "reason": "missing new-game spawn"}
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 24, 7, Vector2i.ZERO, spawn.world_state
	)
	if world == null:
		return {"ok": false, "reason": "missing home map"}
	# wPlayerID is rolled at new game, and GetTreeScore reads it, so the route
	# pins it with a generator of its own rather than letting create_new_game()
	# randomize one and make the run differ from itself.
	var identity_random := RandomNumberGenerator.new()
	identity_random.seed = 23
	var save: Gen2SaveData = Gen2SaveStore.create_new_game(data, 0, "ASH", -1, identity_random)
	if save == null:
		return {"ok": false, "reason": "could not create source-shaped new game"}
	save.world = world.snapshot()
	var random := RandomNumberGenerator.new()
	random.seed = 7
	# Every map load advances the roaming beasts. Supply a dedicated schedule
	# stream rather than relying on an implicit random source, as the live screen
	# does at world_screen.gd:153. Without this the route's reported roaming
	# positions cannot be diffed against itself.
	#
	# Its own generator, not the route's: the schedule rolls once per map load,
	# and drawing them from the same stream would shift every encounter and catch
	# behind them. That separation is the whole point of Gen2WorldAPI keeping
	# three.
	var schedule_random := RandomNumberGenerator.new()
	schedule_random.seed = 11
	world.schedule_random = schedule_random
	var path: Array = []

	# The bedroom's MAPCALLBACK_NEWMAP is what runs InitializeEventsScript
	# (maps/PlayersHouse2F.asm's PlayersHouse2FInitializeRoomCallback), which
	# sets the story's initial event flags. Skipping it left the walked route on
	# a different flag baseline from a real new game, where world_screen.gd
	# dispatches the same callbacks on the spawn map.
	var bedroom_entry: Array = world.dispatch_map_entry()
	var bedroom_run: Dictionary = _drain_story(world, bedroom_entry, save, random, data, true)
	path.append({
		"step": "players_house_2f_initial_events",
		"map": _map_value(world),
		"run": bedroom_run,
		"event_flag_count": world.state.event_flags().size(),
		"engine_flags": world.state.engine_flags(),
	})
	if not bool(bedroom_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "initial event callbacks did not finish"}

	var stair_warp: Dictionary = _warp_to(world.current_map, 24, 6)
	if stair_warp.is_empty():
		return {"ok": false, "reason": "missing home stair warp"}
	world.player_cell = Vector2i(stair_warp["x"], stair_warp["y"])
	var transition: Dictionary = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "reason": "stair warp failed", "transition": _transition_value(transition)}
	path.append({"map": _map_value(world), "cell": _cell_value(world)})

	# The stair warp lands on (9,0) and the two profiles run Mom from opposite
	# ends (`maps/PlayersHouse1F.asm`). Gold and Silver ship no coord event at
	# all: scene 0 is `PlayersHouse1FMeetMomScene`, an `sdefer MeetMomScript`, and
	# the script's own first command walks the player downstairs. Crystal's two
	# scene scripts are noops and its `(8,4)`/`(9,4)` coord events are the
	# trigger, so there the walk has to go down to one.
	var mom_run: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	if Gen2WorldState.is_crystal_profile(data):
		var stepped: Dictionary = _coord_event_step(
			world, Vector2i(9, 3), Vector2i(9, 4), save, random, data
		)
		if not bool(stepped.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the Mom coord event failed: %s" % stepped.get("reason", ""),
			}
		mom_run = stepped.get("run", mom_run)
	path.append({
		"step": "players_house_1f_mom",
		"trigger_cell": _cell_value(world),
		"run": mom_run,
		"pokegear": world.state.is_engine_flag_active(ENGINE_POKEGEAR),
		"clock": world.world_clock(),
		"dst_enabled": world.daylight_saving_time_enabled(),
		"engine_flags": world.state.engine_flags(),
	})
	if not world.state.is_engine_flag_active(ENGINE_POKEGEAR):
		return {"ok": false, "path": path, "reason": "Mom never handed over the Pokegear"}

	var town_warp: Dictionary = _warp_to(world.current_map, 24, 4)
	if town_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing first-floor town warp"}
	world.player_cell = Vector2i(town_warp["x"], town_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "town warp failed"}
	var entry: Array = world.dispatch_map_entry()
	var teacher: Array = []
	var teacher_cell := Vector2i(-1, -1)
	for target: Vector2i in [Vector2i(1, 9), Vector2i(1, 8)]:
		var walked_to_teacher: Dictionary = _walk_to_story_cell(world, target)
		teacher = walked_to_teacher.get("events", [])
		if not teacher.is_empty():
			teacher_cell = target
			break
	var teacher_run: Dictionary = _drain_story(world, teacher, save, random)
	path.append({
		"step": "new_bark_teacher",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"trigger_cell": _cell_value_from_vector(teacher_cell),
		"entry_statuses": _statuses(entry),
		"run": teacher_run,
	})

	var lab_warp: Dictionary = _warp_to(world.current_map, 24, 5)
	if lab_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing New Bark to Elm lab warp"}
	world.player_cell = Vector2i(lab_warp["x"], lab_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Elm lab warp failed"}
	var lab_entry: Array = world.dispatch_map_entry()
	var lab_entry_run: Dictionary = _drain_story(world, lab_entry, save, random)
	path.append({
		"step": "elm_lab_entry_scene",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": lab_entry_run,
	})
	if not bool(lab_entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Elm lab entry scene did not finish"}

	# The source Cyndaquil ball is object 2 at (6,3). Interact from its
	# validated south-facing cell so the imported object script owns the choice.
	world.player_cell = Vector2i(6, 4)
	world.player_facing = Gen2WorldSprite.FACING_UP
	var starter: Array = world.interact()
	var starter_run: Dictionary = _drain_story(world, starter, save, random)
	path.append({
		"step": "elm_lab_cyndaquil_handoff",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": starter_run,
	})
	if not bool(starter_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "starter handoff did not finish"}

	# Elm's directions scene arms the imported aide Potion event. The second
	# scene, which gives Poké Balls, belongs to the later Mystery Egg return and
	# is deliberately not skipped here.
	var potion_events: Array = []
	for target: Vector2i in [Vector2i(4, 8), Vector2i(5, 8)]:
		var walked_to_potion: Dictionary = _walk_to_story_cell(world, target)
		potion_events = walked_to_potion.get("events", [])
		if not potion_events.is_empty():
			break
	var potion_run: Dictionary = _drain_story(world, potion_events, save, random, data)
	path.append({
		"step": "elm_lab_aide_potion",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": potion_run,
		"items": _named_items(data, world.state.items()),
	})
	if not bool(potion_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "aide Potion event did not finish"}

	var lab_exit: Dictionary = _warp_to(world.current_map, 24, 4)
	if lab_exit.is_empty():
		return {"ok": false, "path": path, "reason": "missing Elm lab exit warp"}
	world.player_cell = Vector2i(lab_exit["x"], lab_exit["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "lab exit warp failed"}
	var town_entry: Array = world.dispatch_map_entry()
	var town_entry_run: Dictionary = _drain_story(world, town_entry, save, random, data)
	path.append({
		"step": "new_bark_after_starter",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": town_entry_run,
	})
	if not bool(town_entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "New Bark entry did not finish"}

	var route_transition: Dictionary = _walk_to_connection(world, "west", 24, 3)
	path.append({
		"step": "new_bark_to_route_29",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"transition": _transition_value(route_transition.get("transition", {})),
	})
	if not bool(route_transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "New Bark to Route 29 connection failed"}
	var route_entry: Array = world.dispatch_map_entry()
	var route_entry_run: Dictionary = _drain_story(world, route_entry, save, random, data)
	path.append({
		"step": "route_29_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": route_entry_run,
	})
	if not bool(route_entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Route 29 entry did not finish"}

	var city_transition: Dictionary = _walk_to_connection(world, "west", 26, 3)
	path.append({
		"step": "route_29_to_cherrygrove",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"transition": _transition_value(city_transition.get("transition", {})),
	})
	if not bool(city_transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Route 29 to Cherrygrove connection failed"}
	var city_entry: Array = world.dispatch_map_entry()
	var city_entry_run: Dictionary = _drain_story(world, city_entry, save, random, data)
	path.append({
		"step": "cherrygrove_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": city_entry_run,
		"scene": world.state.map_scene(26, 3),
	})
	if not bool(city_entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Cherrygrove entry did not finish"}

	var route30_transition: Dictionary = _walk_to_connection(world, "north", 26, 1)
	path.append({
		"step": "cherrygrove_to_route_30",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"transition": _transition_value(route30_transition.get("transition", {})),
	})
	if not bool(route30_transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Cherrygrove to Route 30 connection failed"}
	var route30_entry: Array = world.dispatch_map_entry()
	var route30_entry_run: Dictionary = _drain_story(world, route30_entry, save, random, data)
	path.append({
		"step": "route_30_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": route30_entry_run,
	})
	if not bool(route30_entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Route 30 entry did not finish"}

	var mr_pokemon_warp: Dictionary = _warp_to(world.current_map, 26, 10)
	if mr_pokemon_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing Route 30 to Mr Pokemon warp"}
	world.player_cell = Vector2i(mr_pokemon_warp["x"], mr_pokemon_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Mr Pokemon warp failed"}
	var mr_pokemon_entry: Array = world.dispatch_map_entry()
	var mr_pokemon_run: Dictionary = _drain_story(world, mr_pokemon_entry, save, random, data)
	path.append({
		"step": "mr_pokemon_mystery_egg",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": mr_pokemon_run,
		"items": _named_items(data, world.state.items()),
		"engine_flags": world.state.engine_flags(),
		"map_scenes": world.state.map_scenes(),
	})
	if not bool(mr_pokemon_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Mr Pokemon event did not finish"}

	var return_warp: Dictionary = _warp_to(world.current_map, 26, 1)
	if return_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing Mr Pokemon return warp"}
	world.player_cell = Vector2i(return_warp["x"], return_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Route 30 return warp failed"}
	var route30_return: Array = world.dispatch_map_entry()
	var route30_return_run: Dictionary = _drain_story(world, route30_return, save, random, data)
	path.append({
		"step": "route_30_return",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": route30_return_run,
	})
	if not bool(route30_return_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Route 30 return did not finish"}

	var city_return: Dictionary = _walk_to_connection(world, "south", 26, 3)
	path.append({
		"step": "route_30_to_cherrygrove_return",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"transition": _transition_value(city_return.get("transition", {})),
	})
	if not bool(city_return.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Route 30 to Cherrygrove return failed"}
	var city_return_entry: Array = world.dispatch_map_entry()
	var city_return_run: Dictionary = _drain_story(world, city_return_entry, save, random, data)
	path.append({
		"step": "cherrygrove_rival_scene_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": city_return_run,
		"scene": world.state.map_scene(26, 3),
	})
	if not bool(city_return_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Cherrygrove return entry did not finish"}

	var rival_events: Array = []
	for target: Vector2i in [Vector2i(33, 6), Vector2i(33, 7)]:
		var walked_to_rival: Dictionary = _walk_to_story_cell(world, target)
		rival_events = walked_to_rival.get("events", [])
		if not rival_events.is_empty():
			break
	if rival_events.is_empty():
		return {
			"ok": false, "path": path,
			"reason": "Cherrygrove rival event was not dispatched",
		}
	var rival_run: Dictionary = _drain_story(world, rival_events, save, random, data)
	path.append({
		"step": "cherrygrove_first_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": rival_run,
		"scene": world.state.map_scene(26, 3),
	})
	if not bool(rival_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Cherrygrove rival event did not finish"}

	var route29_return: Dictionary = _walk_to_connection(world, "east", 24, 3)
	path.append({
		"step": "cherrygrove_to_route_29_after_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"transition": _transition_value(route29_return.get("transition", {})),
	})
	if not bool(route29_return.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Cherrygrove to Route 29 return failed"}
	var route29_return_entry: Array = world.dispatch_map_entry()
	var route29_return_run: Dictionary = _drain_story(
		world, route29_return_entry, save, random, data
	)
	path.append({
		"step": "route_29_after_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": route29_return_run,
	})
	if not bool(route29_return_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Route 29 return entry did not finish"}

	var new_bark_return: Dictionary = _walk_to_connection(world, "east", 24, 4)
	path.append({
		"step": "route_29_to_new_bark_after_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"transition": _transition_value(new_bark_return.get("transition", {})),
	})
	if not bool(new_bark_return.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Route 29 to New Bark return failed"}
	var new_bark_return_entry: Array = world.dispatch_map_entry()
	var new_bark_return_run: Dictionary = _drain_story(
		world, new_bark_return_entry, save, random, data
	)
	path.append({
		"step": "new_bark_after_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": new_bark_return_run,
	})
	if not bool(new_bark_return_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "New Bark return entry did not finish"}

	var lab_return_warp: Dictionary = _warp_to(world.current_map, 24, 5)
	if lab_return_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing New Bark return lab warp"}
	world.player_cell = Vector2i(lab_return_warp["x"], lab_return_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "return lab warp failed"}
	var officer_entry: Array = world.dispatch_map_entry()
	var officer_entry_run: Dictionary = _drain_story(world, officer_entry, save, random, data)
	path.append({
		"step": "elm_lab_officer_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": officer_entry_run,
		"scene": world.state.map_scene(24, 5),
	})
	if not bool(officer_entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Elm lab officer entry did not finish"}

	var officer_events: Array = []
	for target: Vector2i in [Vector2i(4, 5), Vector2i(5, 5)]:
		var walked_to_officer: Dictionary = _walk_to_story_cell(world, target)
		officer_events = walked_to_officer.get("events", [])
		if not officer_events.is_empty():
			break
	var officer_run: Dictionary = _drain_story(world, officer_events, save, random, data)
	path.append({
		"step": "elm_lab_officer_dialogue",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": officer_run,
		"scene": world.state.map_scene(24, 5),
	})
	if not bool(officer_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Elm lab officer event did not finish"}

	var elm_events: Array = []
	var walked_to_elm: Dictionary = _walk_to_story_cell(world, Vector2i(5, 3))
	if bool(walked_to_elm.get("ok", false)):
		world.player_facing = Gen2WorldSprite.FACING_UP
		elm_events = world.interact()
	var elm_run: Dictionary = _drain_story(world, elm_events, save, random, data, true)
	path.append({
		"step": "elm_lab_mystery_egg_return",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": elm_run,
		"items": _named_items(data, world.state.items()),
		"scene": world.state.map_scene(24, 5),
	})
	if not bool(elm_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Elm mystery egg return did not finish"}

	var balls_events: Array = []
	for target: Vector2i in [Vector2i(4, 8), Vector2i(5, 8)]:
		var walked_to_balls: Dictionary = _walk_to_story_cell(world, target)
		balls_events = walked_to_balls.get("events", [])
		if not balls_events.is_empty():
			break
	var balls_run: Dictionary = _drain_story(world, balls_events, save, random, data, true)
	path.append({
		"step": "elm_lab_aide_pokeballs",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": balls_run,
		"items": _named_items(data, world.state.items()),
		"scene": world.state.map_scene(24, 5),
	})
	if not bool(balls_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Aide Poke Ball event did not finish"}

	# Route 30's corridor north is sealed until ElmAfterTheftScript's
	# setevent EVENT_ROUTE_30_BATTLE hides the two objects standing on it
	# (maps/Route30.asm, maps/ElmsLab.asm; CheckObjectFlag in
	# engine/overworld/map_objects_2.asm masks an object whose flag is set).
	# The Mystery Egg return above is what sets it, so the route walks from
	# here on the same world and state.
	var lab_exit_warp: Dictionary = _warp_to(world.current_map, 24, 4)
	if lab_exit_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing Elm lab exit warp"}
	world.player_cell = Vector2i(lab_exit_warp["x"], lab_exit_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Elm lab exit warp failed"}
	var departure_entry: Array = world.dispatch_map_entry()
	var departure_run: Dictionary = _drain_story(world, departure_entry, save, random, data)
	path.append({
		"step": "new_bark_departure",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": departure_run,
	})
	if not bool(departure_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "New Bark departure entry did not finish"}

	var legs: Array = [
		{"step": "new_bark_to_route_29_north", "direction": "west", "group": 24, "number": 3},
		{"step": "route_29_to_cherrygrove_north", "direction": "west", "group": 26, "number": 3},
		{"step": "cherrygrove_to_route_30_north", "direction": "north", "group": 26, "number": 1},
		{"step": "route_30_to_route_31", "direction": "north", "group": 26, "number": 2},
	]
	for leg: Dictionary in legs:
		var walked: Dictionary = _walk_connection_resolving(
			world, String(leg["direction"]), int(leg["group"]), int(leg["number"]),
			save, random, data
		)
		var leg_entry: Array = world.dispatch_map_entry()
		var leg_run: Dictionary = _drain_story(world, leg_entry, save, random, data)
		path.append({
			"step": String(leg["step"]),
			"map": _map_value(world),
			"cell": _cell_value(world),
			"transition": _transition_value(walked.get("transition", {})),
			"encounters": walked.get("encounters", []),
			"run": leg_run,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s failed: %s" % [leg["step"], walked.get("reason", "")],
			}
		if not bool(leg_run.get("terminal", false)):
			return {"ok": false, "path": path, "reason": "%s entry did not finish" % leg["step"]}

	# Route 31 reaches Violet City through Route31VioletGate, not through its
	# west map connection: the map's four westmost cell columns are wall on
	# every row, so no walkable west edge exists (maps/Route31.asm's
	# warp_event 4, 6 and maps/Route31VioletGate.asm's warp_event 0, 4).
	var gate_walk: Dictionary = _walk_cell_resolving(world, Vector2i(4, 6), save, random, data)
	path.append({
		"step": "route_31_to_violet_gate",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": gate_walk.get("encounters", []),
	})
	if not bool(gate_walk.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 31 gate approach failed: %s" % gate_walk.get("reason", ""),
		}
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Route 31 Violet gate warp failed"}
	var gate_entry: Array = world.dispatch_map_entry()
	var gate_run: Dictionary = _drain_story(world, gate_entry, save, random, data)
	path.append({
		"step": "violet_gate_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": gate_run,
	})
	if not bool(gate_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Violet gate entry did not finish"}

	var city_side: Dictionary = _walk_cell_resolving(world, Vector2i(0, 4), save, random, data)
	if not bool(city_side.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Violet gate west exit unreachable: %s" % city_side.get("reason", ""),
		}
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Violet gate to Violet City warp failed"}
	var violet_entry: Array = world.dispatch_map_entry()
	var violet_entry_run: Dictionary = _drain_story(world, violet_entry, save, random, data)
	path.append({
		"step": "violet_city_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": violet_entry_run,
	})
	if not bool(violet_entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Violet City entry did not finish"}

	# The Pokemon Center nurse reads CheckPokerus and VAR_PARTYCOUNT, so the
	# world needs the read-only party mirror before either can resolve.
	_mirror_party(world, save)

	var pokecenter_warp: Dictionary = _warp_to(world.current_map, 10, 10)
	if pokecenter_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing Violet Pokemon Center warp"}
	world.player_cell = Vector2i(pokecenter_warp["x"], pokecenter_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Violet Pokemon Center warp failed"}
	var pokecenter_entry: Array = world.dispatch_map_entry()
	var pokecenter_entry_run: Dictionary = _drain_story(world, pokecenter_entry, save, random, data)
	path.append({
		"step": "violet_pokecenter_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": pokecenter_entry_run,
	})

	# VioletPokecenter1F places the nurse object at block (3,1); the counter
	# tile directly below her at (3,2) is not walkable, so ordinary pathfinding
	# cannot reach it (a counter, not a ledge; Gen2WorldCollision.allows_hop
	# does not apply). The player is placed there directly rather than
	# guessing an unverified counter-side approach.
	world.player_cell = Vector2i(3, 2)
	world.player_facing = Gen2WorldSprite.FACING_UP
	var nurse_events: Array = world.interact()
	for mon: Gen2SaveMon in save.party:
		mon.hp = 1
	var nurse_run: Dictionary = _drain_story(world, nurse_events, save, random, data)
	path.append({
		"step": "violet_pokecenter_nurse",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": nurse_run,
		"party_hp_after": _party_hp(save),
	})
	if not bool(nurse_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Pokemon Center nurse event did not finish"}

	var pokecenter_exit: Dictionary = _warp_to(world.current_map, 10, 5)
	if pokecenter_exit.is_empty():
		return {"ok": false, "path": path, "reason": "missing Violet Pokemon Center exit warp"}
	world.player_cell = Vector2i(pokecenter_exit["x"], pokecenter_exit["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Violet Pokemon Center exit warp failed"}
	path.append({"step": "violet_city_after_heal", "map": _map_value(world), "cell": _cell_value(world)})

	var gym_warp: Dictionary = _warp_to(world.current_map, 10, 7)
	if gym_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing Violet Gym warp"}
	world.player_cell = Vector2i(gym_warp["x"], gym_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Violet Gym warp failed"}
	var gym_entry: Array = world.dispatch_map_entry()
	var gym_entry_run: Dictionary = _drain_story(world, gym_entry, save, random, data)
	path.append({
		"step": "violet_gym_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": gym_entry_run,
	})

	# Falkner is object 0 at block (5,1); facing up from (5,2) matches the
	# source's faceplayer interaction cell. The gym's two Bird Keepers stand
	# on sight lines across the way to him, so they are fought on the approach
	# exactly as they are on the cartridge.
	var falkner_events: Array = []
	var walked_to_falkner: Dictionary = _walk_cell_resolving(
		world, Vector2i(5, 2), save, random, data
	)
	path.append({
		"step": "violet_gym_bird_keepers",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": walked_to_falkner.get("encounters", []),
	})
	if not bool(walked_to_falkner.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Falkner approach failed: %s" % walked_to_falkner.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	falkner_events = world.interact()
	var falkner_run: Dictionary = _drain_story(world, falkner_events, save, random, data, true)
	path.append({
		"step": "violet_gym_falkner",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": falkner_run,
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
		"engine_flags": world.state.engine_flags(),
	})
	if not bool(falkner_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Falkner event did not finish"}

	var hive: Dictionary = _hive_badge_path(world, save, random, data, path)
	if not bool(hive.get("ok", false)):
		return hive

	var plain: Dictionary = _plain_badge_path(world, save, random, data, path)
	if not bool(plain.get("ok", false)):
		return plain

	var fog: Dictionary = _fog_badge_path(world, save, random, data, path)
	if not bool(fog.get("ok", false)):
		return fog

	var mineral: Dictionary = _mineral_badge_path(world, save, random, data, path)
	if not bool(mineral.get("ok", false)):
		return mineral

	var glacier: Dictionary = _glacier_badge_path(world, save, random, data, path)
	if not bool(glacier.get("ok", false)):
		return glacier

	var radio_tower: Dictionary = _radio_tower_path(world, save, random, data, path)
	if not bool(radio_tower.get("ok", false)):
		return radio_tower

	var blackthorn: Dictionary = _blackthorn_path(world, save, random, data, path)
	if not bool(blackthorn.get("ok", false)):
		return blackthorn

	var rising: Dictionary = _rising_badge_path(world, save, random, data, path)
	if not bool(rising.get("ok", false)):
		return rising

	var kanto: Dictionary = _kanto_approach_path(world, save, random, data, path)
	if not bool(kanto.get("ok", false)):
		return kanto

	# PostCreditsSpawn is a map load, not a step, so the leg after the Hall of
	# Fame runs on its own world; everything below reads the returned one.
	var crossing: Dictionary = _kanto_crossing_path(world, save, random, data, path)
	if not bool(crossing.get("ok", false)):
		return crossing
	var crossed: Variant = crossing.get("world", null)
	if crossed is Gen2WorldAPI:
		world = crossed

	var party_summary: Array = []
	for mon: Gen2SaveMon in save.party:
		party_summary.append({
			"species": mon.species,
			"level": mon.level,
			"item": mon.item,
		})
	return {
		"ok": true,
		"path": path,
		"party": party_summary,
		"event_flags": world.state.event_flags(),
		"map_scenes": world.state.to_dict().get("map_scenes", {}),
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
	}


## Violet City to the Hive Badge, on the same world, state and save. Three
## gates own this leg and each opens the next: the Togepi egg retires Route 32's
## blocking coord event, Kurt hides the Rocket standing on the Slowpoke Well
## corridor, and clearing the well hides the Rocket standing on the Azalea gym
## door. Appends to [param path] and answers only ok or the failure.
func _hive_badge_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var leaving_gym: Dictionary = _warp_step(world, 10, 5)
	if not bool(leaving_gym.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Violet Gym exit warp failed"}
	var after_gym: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)
	path.append({
		"step": "violet_city_after_falkner",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": after_gym,
		"pending_special_call": world.state.pending_special_phone_call(),
	})
	if not bool(after_gym.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Violet City re-entry did not finish"}
	if world.state.pending_special_phone_call() != SPECIALCALL_ASSISTANT:
		return {"ok": false, "path": path, "reason": "Falkner did not arm the assistant call"}

	# data/phone/special_calls.asm gives SPECIALCALL_ASSISTANT the
	# SpecialCallOnlyWhenOutside condition, so the call resolves on Violet City
	# and not in the gym it was armed in. ElmPhoneCallerScript's .assistant
	# branch is the only thing that clears
	# EVENT_ELMS_AIDE_IN_VIOLET_POKEMON_CENTER, which InitializeEventsScript set.
	var call_attempt: Dictionary = world.try_special_phone_call()
	if not bool(call_attempt.get("attempted", false)):
		return {
			"ok": false, "path": path,
			"reason": "assistant call not attempted: %s" % call_attempt.get("reason", ""),
		}
	var call_run: Dictionary = _drain_story(
		world, call_attempt.get("results", []), save, random, data, true
	)
	path.append({
		"step": "elm_assistant_phone_call",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"call_id": int(call_attempt.get("call_id", 0)),
		"run": call_run,
		"pending_special_call": world.state.pending_special_phone_call(),
	})
	if not bool(call_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "assistant call did not finish"}

	# The aide stands at (4,3); (4,4) is the only walkable cell facing him.
	var entering_pokecenter: Dictionary = _warp_step(world, 10, 10)
	if not bool(entering_pokecenter.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Violet Pokemon Center warp failed"}
	var pokecenter_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var walked_to_aide: Dictionary = _walk_cell_resolving(world, Vector2i(4, 4), save, random, data)
	if not bool(walked_to_aide.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Elm's aide unreachable: %s" % walked_to_aide.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	var egg_run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	path.append({
		"step": "violet_pokecenter_togepi_egg",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": pokecenter_entry.get("statuses", []),
		"run": egg_run,
		"party": _party_species(save),
		"route_32_scene": world.state.map_scene(10, 1),
	})
	if not bool(egg_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Togepi egg event did not finish"}
	if not _party_has_egg(save):
		return {"ok": false, "path": path, "reason": "the Togepi egg did not reach the party"}
	_mirror_party(world, save)

	var leaving_pokecenter: Dictionary = _warp_step(world, 10, 5)
	if not bool(leaving_pokecenter.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Violet Pokemon Center exit warp failed"}
	var route32_leg: Dictionary = _walk_connection_resolving(
		world, "south", 10, 1, save, random, data
	)
	var route32_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "violet_city_to_route_32",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": route32_leg.get("encounters", []),
		"run": route32_entry,
	})
	if not bool(route32_leg.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Violet City to Route 32 failed: %s" % route32_leg.get("reason", ""),
		}

	var rod: Dictionary = _route_32_old_rod(world, save, random, data, path)
	if not bool(rod.get("ok", false)):
		return rod

	# Route 32's south edge does connect to Route 33, but that lands in the
	# plaza north of Route 33's wall row, whose only exit is the Union Cave
	# warp. The cartridge's own path is Route 32 (6,79) into Union Cave 1F and
	# out again at (17,31), so the leg walks the warps, not the connection.
	var union_cave: Dictionary = _warp_walk(world, Vector2i(6, 79), save, random, data)
	if not bool(union_cave.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 32 to Union Cave failed: %s" % union_cave.get("reason", ""),
		}
	var union_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_32_to_union_cave",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": union_cave.get("encounters", []),
		"run": union_entry,
	})

	var caught: Dictionary = _catch_field_move_mon(
		world, save, random, data, path,
		Gen2WorldFieldMove.MOVE_STRENGTH, "union_cave_catch_for_strength"
	)
	if not bool(caught.get("ok", false)):
		return caught

	var route33: Dictionary = _warp_walk(world, Vector2i(17, 31), save, random, data)
	if not bool(route33.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Union Cave to Route 33 failed: %s" % route33.get("reason", ""),
		}
	var route33_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "union_cave_to_route_33",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": route33.get("encounters", []),
		"run": route33_entry,
	})

	var azalea_leg: Dictionary = _walk_connection_resolving(
		world, "west", 8, 7, save, random, data
	)
	var azalea_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_33_to_azalea",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": azalea_leg.get("encounters", []),
		"run": azalea_entry,
	})
	if not bool(azalea_leg.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 33 to Azalea failed: %s" % azalea_leg.get("reason", ""),
		}

	# Kurt1 stands at (3,2); facing him from (3,3) takes his .RunAround branch,
	# and the script sets EVENT_AZALEA_TOWN_SLOWPOKETAIL_ROCKET, which hides the
	# Rocket standing on the well corridor at Azalea (31,9).
	var entering_kurt: Dictionary = _warp_step(world, 8, 4)
	if not bool(entering_kurt.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Kurt's house warp failed"}
	var kurt_entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)
	var walked_to_kurt: Dictionary = _walk_cell_resolving(world, Vector2i(3, 3), save, random, data)
	if not bool(walked_to_kurt.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Kurt unreachable: %s" % walked_to_kurt.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	var kurt_run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	path.append({
		"step": "azalea_kurts_house",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": kurt_entry.get("statuses", []),
		"run": kurt_run,
	})
	if not bool(kurt_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Kurt event did not finish"}

	var leaving_kurt: Dictionary = _warp_step(world, 8, 7)
	if not bool(leaving_kurt.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Kurt's house exit warp failed"}
	var _kurt_exit_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var well: Dictionary = _warp_walk(world, Vector2i(31, 7), save, random, data)
	if not bool(well.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Slowpoke Well entrance blocked: %s" % well.get("reason", ""),
		}
	var well_entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)

	# TrainerGruntM1 stands at (5,2) facing down. His post-battle script is the
	# clear sequence itself: it disappears all four Rockets, which share
	# EVENT_SLOWPOKE_WELL_ROCKETS, then heals the party and warps to Kurt's
	# house, so the map after this step is 8/4 rather than the well.
	var well_walk: Dictionary = _walk_cell_resolving(world, Vector2i(5, 3), save, random, data)
	# The clear sequence ends in `warp KURTS_HOUSE, 3, 3`, so the approach is
	# finished by the script rather than by arriving: success is being on 8/4.
	var cleared: bool = world.current_map != null \
		and world.current_map.group == 8 and world.current_map.number == 4
	path.append({
		"step": "slowpoke_well_cleared",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": well_entry.get("statuses", []),
		"encounters": well_walk.get("encounters", []),
		"party_hp_after": _party_hp(save),
		"cleared": cleared,
	})
	if not cleared:
		return {
			"ok": false, "path": path,
			"reason": "Slowpoke Well clear failed: %s" % well_walk.get("reason", ""),
		}
	var after_well: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)
	path.append({
		"step": "kurts_house_after_the_well",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": after_well,
	})

	var back_to_azalea: Dictionary = _warp_step(world, 8, 7)
	if not bool(back_to_azalea.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Kurt's house exit after the well failed"}
	var _azalea_after_well: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	# The apricorn errand, which is two maps. WhiteApricornTree stands on (8,2)
	# in both pins and is the only source of the apricorn Kurt asks for, so the
	# walk picks it rather than being handed one.
	var tree: Dictionary = _talk_to(
		world, Vector2i(8, 3), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "azalea_white_apricorn_tree",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"apricorns": world.state.item_quantity(APRICORN_WHT),
		"run": tree,
	})
	if not bool(tree.get("ok", false)) or world.state.item_quantity(APRICORN_WHT) != 1:
		return {
			"ok": false, "path": path,
			"reason": "the white apricorn tree bore nothing: %s" % tree.get("reason", ""),
		}

	var back_to_kurt: Dictionary = _warp_step(world, 8, 4)
	if not bool(back_to_kurt.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Kurt's house re-entry failed"}
	var _kurt_errand_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	# Kurt1 is at (3,2) with EVENT_CLEARED_SLOWPOKE_WELL set. `.GotLureBall`
	# falls through to `.CheckApricorns`, which finds the white one and asks.
	var errand: Dictionary = _talk_to(
		world, Vector2i(3, 3), Gen2WorldSprite.FACING_UP, save, random, data, [],
		{"item": APRICORN_WHT, "quantity": 1}
	)
	path.append({
		"step": "kurts_apricorn_errand",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"given": errand.get("run", {}).get("apricorns_given", []),
		"apricorns_left": world.state.item_quantity(APRICORN_WHT),
		"kurt_quantity": world.state.kurt_apricorn_quantity(),
		"making_balls": world.state.is_engine_flag_active(Gen2WorldState.engine_flag(
			Gen2WorldState.ENGINE_KURT_MAKING_BALLS, Gen2WorldState.is_crystal_profile(data)
		)),
		"run": errand,
	})
	if not bool(errand.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Kurt's apricorn errand failed: %s" % errand.get("reason", ""),
		}
	if world.state.kurt_apricorn_quantity() != 1 or world.state.item_quantity(APRICORN_WHT) != 0:
		return {"ok": false, "path": path, "reason": "Kurt took the wrong apricorns"}

	var leaving_kurt_again: Dictionary = _warp_step(world, 8, 7)
	if not bool(leaving_kurt_again.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Kurt's house exit after the errand failed"}
	var _azalea_after_errand: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var gym_door: Dictionary = _warp_walk(world, Vector2i(10, 15), save, random, data)
	if not bool(gym_door.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Azalea gym door blocked: %s" % gym_door.get("reason", ""),
		}
	var gym_entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)

	# Bugsy is object 0 at (5,7); the gym's Bug Catchers and Twins hold sight
	# lines across the approach, so they are fought on the way exactly as they
	# are on the cartridge.
	var walked_to_bugsy: Dictionary = _walk_cell_resolving(
		world, Vector2i(5, 8), save, random, data
	)
	path.append({
		"step": "azalea_gym_trainers",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": gym_entry.get("statuses", []),
		"encounters": walked_to_bugsy.get("encounters", []),
	})
	if not bool(walked_to_bugsy.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Bugsy approach failed: %s" % walked_to_bugsy.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	var bugsy_run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	path.append({
		"step": "azalea_gym_bugsy",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": bugsy_run,
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
		"engine_flags": world.state.engine_flags(),
	})
	if not bool(bugsy_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Bugsy event did not finish"}
	return {"ok": true}


## The herding chain in maps/IlexForest.asm's IlexForestFarfetchdScript. Each
## row is the Farfetch'd cell, the cell to face it from, and the facing that
## takes the fall-through branch; every other facing at that position is an
## explicit `ifequal` that sends it backwards. Position 1 accepts any facing and
## `wFarfetchdPosition` starts at zero, which reaches the same label because no
## `ifequal` matches.
const FARFETCHD_HERD: Array = [
	[Vector2i(14, 31), Vector2i(14, 32), Gen2WorldSprite.FACING_UP],
	[Vector2i(15, 25), Vector2i(15, 26), Gen2WorldSprite.FACING_UP],
	[Vector2i(20, 24), Vector2i(20, 23), Gen2WorldSprite.FACING_DOWN],
	[Vector2i(29, 22), Vector2i(28, 22), Gen2WorldSprite.FACING_RIGHT],
	[Vector2i(28, 31), Vector2i(28, 30), Gen2WorldSprite.FACING_DOWN],
	[Vector2i(24, 35), Vector2i(25, 35), Gen2WorldSprite.FACING_LEFT],
	[Vector2i(22, 31), Vector2i(22, 32), Gen2WorldSprite.FACING_UP],
	[Vector2i(15, 29), Vector2i(15, 28), Gen2WorldSprite.FACING_DOWN],
	[Vector2i(10, 35), Vector2i(11, 35), Gen2WorldSprite.FACING_LEFT],
]

## Ilex Forest's cuttable tree, the only way from the forest's southern half to
## the Route 34 exit (maps/IlexForest.blk; tools/checks/cut.gd pins the cell).
const ILEX_CUT_TREE: Vector2i = Vector2i(8, 25)
const ILEX_CUT_APPROACH: Vector2i = Vector2i(8, 26)


## Azalea Town to the Plain Badge. Cut is the gate: HM01 comes from Ilex
## Forest's charcoal master, who only appears once Farfetch'd has been herded
## the whole way round, and the tree he unlocks is the only way north.
func _plain_badge_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var leaving_gym: Dictionary = _warp_step(world, 8, 7)
	if not bool(leaving_gym.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Azalea Gym exit warp failed"}
	var _azalea_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var azalea_gate: Dictionary = _warp_walk(world, Vector2i(2, 10), save, random, data)
	if not bool(azalea_gate.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Ilex Forest gate unreachable: %s" % azalea_gate.get("reason", ""),
		}
	var _gate_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var ilex: Vector2i = _map_id(data, &"ILEX_FOREST")
	var forest: Dictionary = _warp_step(world, ilex.x, ilex.y)
	if not bool(forest.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Ilex Forest warp failed"}
	var forest_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "azalea_to_ilex_forest",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": forest_entry,
	})

	var herded: Array = []
	for index: int in FARFETCHD_HERD.size():
		var row: Array = FARFETCHD_HERD[index]
		var approach: Vector2i = row[1]
		var walked: Dictionary = _walk_cell_resolving(world, approach, save, random, data)
		if not bool(walked.get("ok", false)):
			path.append({"step": "ilex_forest_farfetchd", "herded": herded})
			return {
				"ok": false, "path": path,
				"reason": "Farfetch'd position %d unreachable at %s: %s" % [
					index + 1, approach, walked.get("reason", ""),
				],
			}
		world.player_facing = int(row[2])
		var run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
		herded.append({
			"position": index + 1,
			"from": _cell_value_from_vector(approach),
			"memory": world.state.script_memory_values(),
			"terminal": bool(run.get("terminal", false)),
			"reason": run.get("reason", ""),
		})
		if not bool(run.get("terminal", false)):
			path.append({"step": "ilex_forest_farfetchd", "herded": herded})
			return {
				"ok": false, "path": path,
				"reason": "Farfetch'd position %d did not finish: %s" % [
					index + 1, run.get("reason", ""),
				],
			}
	path.append({
		"step": "ilex_forest_farfetchd",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"herded": herded,
		"event_flags": world.state.event_flags().size(),
	})

	# The charcoal master is object 2 at (5,28), hidden by
	# EVENT_ILEX_FOREST_CHARCOAL_MASTER until the last herding step appears him.
	var walked_to_master: Dictionary = _walk_cell_resolving(
		world, Vector2i(5, 29), save, random, data
	)
	if not bool(walked_to_master.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "charcoal master unreachable: %s" % walked_to_master.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	var cut_gift: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	path.append({
		"step": "ilex_forest_hm01_cut",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": cut_gift,
		"items": _named_items(data, world.state.items()),
	})
	if not bool(cut_gift.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "HM01 handoff did not finish"}

	# And taught, not just carried. The starter is the only line in this party
	# that CanLearnTMHMMove accepts for CUT, and HM01 arrives here, one walk
	# before the first tree, so this is the earliest the route can be honest
	# about the move. `teach_tm_hm()` is the same transaction the pack's USE
	# reaches, the way _olivine_cafe_hm04() teaches STRENGTH.
	var taught: Dictionary = _teach_tm_hm(world, save, ITEM_HM_CUT)
	_mirror_party(world, save)
	path.append({
		"step": "ilex_forest_teach_cut",
		"map": _map_value(world),
		"taught": taught.get("ok", false),
		"species": _party_species(save),
		"moves": _party_moves(save),
	})
	if not bool(taught.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "no party member learned CUT: %s" % taught.get("reason", ""),
		}

	var walked_to_tree: Dictionary = _walk_cell_resolving(
		world, ILEX_CUT_APPROACH, save, random, data
	)
	if not bool(walked_to_tree.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Ilex cut tree unreachable: %s" % walked_to_tree.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	var cut_request: Dictionary = world.cut_request()
	var cut_applied: Dictionary = world.complete_cut() if bool(cut_request.get("ok", false)) else {}
	path.append({
		"step": "ilex_forest_cut_tree",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"request": cut_request.get("kind", cut_request.get("reason", "")),
		"applied": cut_applied.get("kind", cut_applied.get("reason", "")),
		"walkable_after": world.can_walk_to(ILEX_CUT_TREE),
	})
	if not bool(cut_applied.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "cut failed: %s" % cut_request.get(
				"reason", cut_applied.get("reason", "")
			),
		}

	var forest_exit: Dictionary = _warp_walk(world, Vector2i(1, 5), save, random, data)
	if not bool(forest_exit.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Ilex Forest north exit unreachable: %s" % forest_exit.get("reason", ""),
		}
	var north_gate_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "ilex_forest_to_route_34_gate",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": forest_exit.get("encounters", []),
		"run": north_gate_entry,
	})

	var route34: Dictionary = _warp_step(world, 11, 1)
	if not bool(route34.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Route 34 warp failed"}
	var route34_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_34_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": route34_entry,
	})

	var goldenrod: Dictionary = _walk_connection_resolving(
		world, "north", 11, 2, save, random, data
	)
	var goldenrod_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_34_to_goldenrod",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": goldenrod.get("encounters", []),
		"run": goldenrod_entry,
	})
	if not bool(goldenrod.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 34 to Goldenrod failed: %s" % goldenrod.get("reason", ""),
		}

	_mirror_party(world, save)
	var gym: Dictionary = _warp_walk(world, Vector2i(24, 7), save, random, data)
	if not bool(gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Goldenrod Gym door unreachable: %s" % gym.get("reason", ""),
		}
	var gym_entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)

	# Whitney is object 0 at (8,3). Beating her sets EVENT_MADE_WHITNEY_CRY and
	# she refuses the badge; the coord event at (8,5) under
	# SCENE_GOLDENRODGYM_WHITNEY_STOPS_CRYING is what clears it, so the badge
	# needs a step back onto that cell and a second interaction.
	var walked_to_whitney: Dictionary = _walk_cell_resolving(
		world, Vector2i(8, 4), save, random, data
	)
	if not bool(walked_to_whitney.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Whitney approach failed: %s" % walked_to_whitney.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	var whitney_fight: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	path.append({
		"step": "goldenrod_gym_whitney_battle",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": gym_entry.get("statuses", []),
		"encounters": walked_to_whitney.get("encounters", []),
		"run": whitney_fight,
		"scene": world.state.map_scene(11, 3),
	})
	if not bool(whitney_fight.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Whitney battle did not finish"}

	var crying: Dictionary = _walk_cell_resolving(world, Vector2i(8, 5), save, random, data)
	path.append({
		"step": "goldenrod_gym_whitney_stops_crying",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": crying.get("encounters", []),
		"scene": world.state.map_scene(11, 3),
	})
	if not bool(crying.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Whitney crying scene failed: %s" % crying.get("reason", ""),
		}

	var walked_back: Dictionary = _walk_cell_resolving(
		world, Vector2i(8, 4), save, random, data
	)
	if not bool(walked_back.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Whitney second approach failed: %s" % walked_back.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	var badge_run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	path.append({
		"step": "goldenrod_gym_plain_badge",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": badge_run,
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
		"engine_flags": world.state.engine_flags(),
	})
	if not bool(badge_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Plain Badge event did not finish"}
	return {"ok": true}


## Goldenrod City to Route 36, through the Route 35 gate and the cut tree that
## is Route 35's only way past row 6. Crystal walks it twice, once to meet
## Floria and once to reach Sudowoodo; Gold and Silver only ever walk it once.
func _goldenrod_to_route_36(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var to_route_35: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(19, 1), 10, 2
	)
	if not bool(to_route_35.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Goldenrod to Route 35 failed: %s" % to_route_35.get("reason", ""),
		}
	var tree: Dictionary = _cut_at(
		world, Vector2i(17, 7), Gen2WorldSprite.FACING_UP, save, random, data
	)
	if not bool(tree.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 35 cut tree failed: %s" % tree.get("reason", ""),
		}
	var leg: Dictionary = _walk_connection_resolving(
		world, "north", 10, 3, save, random, data
	)
	var entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "goldenrod_to_route_36",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": leg.get("encounters", []),
		"run": entry,
	})
	if not bool(leg.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 35 to Route 36 failed: %s" % leg.get("reason", ""),
		}
	return {"ok": true}


## The flower shop errand, entered from Goldenrod City and left back onto it.
## The door is the one cell of it the two profiles disagree on, `(29,5)` in
## pokecrystal and `(33,5)` in pokegold (`maps/GoldenrodCity.asm`). Floria is
## only spoken to on Crystal, where `FlowerShopTeacherScript` reads the flag
## that conversation sets.
func _goldenrod_flower_shop(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var crystal: bool = Gen2WorldState.is_crystal_profile(data)
	var door: Vector2i = Vector2i(29, 5) if crystal else Vector2i(33, 5)
	var shop: Dictionary = _warp_walk(world, door, save, random, data)
	if not bool(shop.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "flower shop unreachable: %s" % shop.get("reason", ""),
		}
	var _shop_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var shop_floria: Dictionary = {}
	if crystal:
		shop_floria = _talk_to(
			world, Vector2i(5, 5), Gen2WorldSprite.FACING_DOWN, save, random, data
		)
		if not bool(shop_floria.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "flower shop Floria failed: %s" % shop_floria.get("reason", ""),
			}
	var bottle: Dictionary = _talk_to(
		world, Vector2i(2, 5), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "goldenrod_flower_shop_squirtbottle",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"floria_run": shop_floria.get("run", {}),
		"run": bottle.get("run", {}),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(bottle.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "SquirtBottle handoff failed: %s" % bottle.get("reason", ""),
		}
	var leaving_shop: Dictionary = _warp_step(world, 11, 2)
	if not bool(leaving_shop.get("ok", false)):
		return {"ok": false, "path": path, "reason": "flower shop exit warp failed"}
	var _city_again: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	return {"ok": true}


## Goldenrod to the Fog Badge. Two errands gate it: the SquirtBottle, whose
## shape is the leg's one profile split, and Morty, who is absent until the
## Burned Tower's beasts are released.
##
## Crystal spends the bottle on a round trip. `Route36FloriaScript` has to be
## met on Route 36 first (EVENT_MET_FLORIA), then talked to again in the shop
## (EVENT_TALKED_TO_FLORIA_AT_FLOWER_SHOP), and only then does
## `FlowerShopTeacherScript` reach its `verbosegiveitem SQUIRTBOTTLE`. Gold and
## Silver ship no Floria on Route 36 at all (`maps/Route36.asm`) and their
## teacher is `checkflag ENGINE_PLAINBADGE` and nothing else
## (`maps/GoldenrodFlowerShop.asm`), so the badge the walk already holds is the
## whole gate and the trip north before the shop buys nothing. The shop's own
## Floria wanders there and gates nothing either.
func _fog_badge_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var crystal: bool = Gen2WorldState.is_crystal_profile(data)
	var leaving_gym: Dictionary = _warp_step(world, 11, 2)
	if not bool(leaving_gym.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Goldenrod Gym exit warp failed"}
	var _city_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	if crystal:
		var north: Dictionary = _goldenrod_to_route_36(world, save, random, data, path)
		if not bool(north.get("ok", false)):
			return north

		# Floria stands at (33,12) once entering Goldenrod cleared
		# EVENT_FLORIA_AT_SUDOWOODO; talking to her sets EVENT_MET_FLORIA and
		# moves her to the flower shop.
		var floria: Dictionary = _talk_to(
			world, Vector2i(33, 13), Gen2WorldSprite.FACING_UP, save, random, data
		)
		path.append({
			"step": "route_36_floria",
			"map": _map_value(world),
			"cell": _cell_value(world),
			"run": floria.get("run", {}),
		})
		if not bool(floria.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Route 36 Floria failed: %s" % floria.get("reason", ""),
			}

		var back_to_35: Dictionary = _walk_connection_resolving(
			world, "south", 10, 2, save, random, data
		)
		var _r35_entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		if not bool(back_to_35.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Route 36 back to Route 35 failed: %s" % back_to_35.get("reason", ""),
			}
		var south_cut: Dictionary = _cut_at(
			world, Vector2i(17, 5), Gen2WorldSprite.FACING_DOWN, save, random, data
		)
		if not bool(south_cut.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Route 35 southbound cut failed: %s" % south_cut.get("reason", ""),
			}
		var back_to_city: Dictionary = _gate_leg(
			world, save, random, data, Vector2i(9, 33), 11, 2
		)
		if not bool(back_to_city.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Route 35 back to Goldenrod failed: %s" % back_to_city.get("reason", ""),
			}

	var errand: Dictionary = _goldenrod_flower_shop(world, save, random, data, path)
	if not bool(errand.get("ok", false)):
		return errand
	var to_sudowoodo: Dictionary = _goldenrod_to_route_36(world, save, random, data, path)
	if not bool(to_sudowoodo.get("ok", false)):
		return to_sudowoodo

	# SudowoodoScript answers checkitem SQUIRTBOTTLE from a facing interaction,
	# not from the pack, and the wild battle it starts is what clears the tree
	# blocking Route 37.
	var sudowoodo: Dictionary = _talk_to(
		world, Vector2i(35, 10), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "route_36_sudowoodo",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": sudowoodo.get("run", {}),
	})
	if not bool(sudowoodo.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Sudowoodo failed: %s" % sudowoodo.get("reason", ""),
		}

	if not crystal:
		# `Route36RockSmashGuyScript` stands on (44,9) in both pins and hands
		# TM08 over once EVENT_FOUGHT_SUDOWOODO is set, which the step above just
		# did. Only Gold and Silver come back for it, because only their Burned
		# Tower has a rock in the way; the Crystal route never needs the move and
		# is left as it was.
		var rock_smash_guy: Dictionary = _talk_to(
			world, Vector2i(44, 10), Gen2WorldSprite.FACING_UP, save, random, data
		)
		if not bool(rock_smash_guy.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Route 36 Rock Smash guy failed: %s" % rock_smash_guy.get("reason", ""),
			}
		var rock_smash_taught: Dictionary = _teach_tm_hm(world, save, ITEM_TM_ROCK_SMASH)
		_mirror_party(world, save)
		path.append({
			"step": "route_36_teach_rock_smash",
			"map": _map_value(world),
			"cell": _cell_value(world),
			"run": rock_smash_guy.get("run", {}),
			"items": _named_items(data, world.state.items()),
			"party": _party_moves(save),
		})
		if not bool(rock_smash_taught.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "TM08 could not be taught: %s" % rock_smash_taught.get("reason", ""),
			}

	for leg: Dictionary in [
		{"step": "route_36_to_route_37", "group": 10, "number": 4},
		{"step": "route_37_to_ecruteak", "group": 4, "number": 9},
	]:
		var walked: Dictionary = _walk_connection_resolving(
			world, "north", int(leg["group"]), int(leg["number"]), save, random, data
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": String(leg["step"]),
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s failed: %s" % [leg["step"], walked.get("reason", "")],
			}

	# The gym is closed until the Burned Tower beasts are released: its scene 0
	# is SCENE_ECRUTEAKGYM_FORCED_TO_LEAVE and a gramps stands on the entrance.
	var tower: Dictionary = _warp_walk(world, Vector2i(5, 5), save, random, data)
	if not bool(tower.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Burned Tower door unreachable: %s" % tower.get("reason", ""),
		}
	# Crystal's entry is Eusine's; Gold and Silver put the rival battle itself on
	# entry, as `BurnedTower1FRivalBattleScene`'s `sdefer`.
	var entry_run: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "burned_tower_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": entry_run,
	})
	if not bool(entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Burned Tower entry did not finish"}

	if crystal:
		# The rival scene ends by opening the hole under the player and taking it
		# with warpcheck, so the map after this step is the basement.
		var rival: Dictionary = _walk_cell_resolving(world, Vector2i(11, 9), save, random, data)
		var fell: bool = world.current_map != null \
			and world.current_map.group == 3 and world.current_map.number == 14
		path.append({
			"step": "burned_tower_rival_battle",
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": rival.get("encounters", []),
			"fell_through_the_hole": fell,
		})
		if not fell:
			return {
				"ok": false, "path": path,
				"reason": "Burned Tower rival scene did not drop the player: %s" % rival.get(
					"reason", ""
				),
			}
	else:
		# Gold and Silver open no hole under the player. Their 1F is a dungeon
		# in its own right: the twelve pits pokecrystal keeps and comments as
		# inaccessible leftovers are real here, and the rock on (4,3) is the
		# single cell joining the door to the rest of the floor. Smashing it is
		# what opens the way, which is why Rock Smash is load bearing on these
		# two profiles and on neither Crystal leg.
		var rock: Dictionary = _rock_smash_at(
			world, Vector2i(4, 4), Gen2WorldSprite.FACING_UP, save, random, data
		)
		path.append({
			"step": "burned_tower_smash_rock",
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounter": rock.get("encounter", {}),
		})
		if not bool(rock.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Burned Tower rock failed: %s" % rock.get("reason", ""),
			}
		# Pit 3 on (10,7) is the only one that lands in the basement region the
		# beasts are in.
		var hole: Dictionary = _warp_walk(world, Vector2i(10, 7), save, random, data)
		path.append({
			"step": "burned_tower_hole_to_basement",
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": hole.get("encounters", []),
		})
		if not bool(hole.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Burned Tower hole unreachable: %s" % hole.get("reason", ""),
			}
	var basement_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	var beast_cell: Vector2i = Vector2i(10, 6) if crystal else Vector2i(9, 5)
	var beasts: Dictionary = _walk_cell_resolving(world, beast_cell, save, random, data)
	path.append({
		"step": "burned_tower_release_the_beasts",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": basement_entry.get("statuses", []),
		"encounters": beasts.get("encounters", []),
		"roaming": world.state.roaming_mons(),
		"gym_scene": world.state.map_scene(4, 7),
	})
	if not bool(beasts.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "beast release failed: %s" % beasts.get("reason", ""),
		}

	if crystal:
		# ReleaseTheBeasts appears Eusine at (10,12), which is the single cell of
		# the corridor south, so the way out is through him: his script has him
		# leave once the player has talked to him. Gold and Silver ship no Eusine
		# anywhere in the tower.
		var eusine_basement: Dictionary = _talk_to(
			world, Vector2i(10, 11), Gen2WorldSprite.FACING_DOWN, save, random, data
		)
		path.append({
			"step": "burned_tower_eusine_leaves",
			"map": _map_value(world),
			"cell": _cell_value(world),
			"run": eusine_basement.get("run", {}),
		})
		if not bool(eusine_basement.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "basement Eusine failed: %s" % eusine_basement.get("reason", ""),
			}

	# (7,15) is the only cell on either profile's basement that `try_warp()` will
	# fire on, since `CheckWarpCollision` gates a warp on its own tile code and
	# every other warp_event down here sits on plain floor or on a ledge. Crystal
	# reaches it because `BurnedTowerB1FLadderCallback` changeblocks the ladder in
	# at walk-cell (6,14), the block holding (7,15), once the beasts are out. Gold
	# and Silver ship no such callback and no hole under the player: the way out
	# of the beasts' region is the ledge run south from (10,8), which the walk's
	# own hop handling takes on its way to the same ladder.
	var out_of_basement: Dictionary = _warp_walk(world, Vector2i(7, 15), save, random, data)
	if not bool(out_of_basement.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Burned Tower ladder unreachable: %s" % out_of_basement.get("reason", ""),
		}
	var _tower_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var out_of_tower: Dictionary = _warp_walk(world, Vector2i(9, 15), save, random, data)
	if not bool(out_of_tower.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Burned Tower exit unreachable: %s" % out_of_tower.get("reason", ""),
		}
	var _ecruteak_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	_mirror_party(world, save)
	var gym: Dictionary = _warp_walk(world, Vector2i(6, 27), save, random, data)
	if not bool(gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Ecruteak Gym door unreachable: %s" % gym.get("reason", ""),
		}
	var gym_entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)

	# The gym floor is thirty holes that warp back to the entrance, so the walk
	# to Morty at (5,1) is the maze itself; the BFS refuses a warp cell that is
	# not its target, which is what keeps it on the invisible floor.
	var morty: Dictionary = _talk_to(
		world, Vector2i(5, 2), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "ecruteak_gym_morty",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": gym_entry.get("statuses", []),
		"run": morty.get("run", {}),
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
		"engine_flags": world.state.engine_flags(),
	})
	if not bool(morty.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Morty failed: %s" % morty.get("reason", ""),
		}
	return {"ok": true}


## The Fog Badge to the Mineral Badge, taking the Storm Badge on the way, on the
## same world, state and save. This is the first leg that needs Surf on the real
## route: HM03 is the Dance Theater's reward for the five Kimono Girls, and
## Routes 40 and 41 are the only way to Cianwood, whose pharmacy holds the
## SecretPotion that maps/OlivineLighthouse6F.asm wants before it clears
## EVENT_OLIVINE_GYM_JASMINE.
##
## Chuck is on this leg rather than one of its own because the crossing is: the
## Mineral Badge sends the player to Cianwood for the SecretPotion anyway, and
## maps/CianwoodGym.asm is two doors from the pharmacy. Doing it here costs no
## extra Route 40/41 crossing, which is also the order a player walks. HM04 is
## collected before the outbound crossing, from maps/OlivineCafe.asm.
func _mineral_badge_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var leaving_gym: Dictionary = _warp_step(world, 4, 9)
	if not bool(leaving_gym.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Ecruteak Gym exit warp failed"}
	var _city_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	var theater: Dictionary = _warp_walk(world, Vector2i(23, 21), save, random, data)
	if not bool(theater.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Dance Theater door unreachable: %s" % theater.get("reason", ""),
		}
	var _theater_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	# The five Kimono Girls stand on the stage above a row of COLL_HOP_DOWN, so
	# the only ways up are the floor cells at (1,4) and (10,4). Their sight range
	# is 0, so none of them can start a battle: every one has to be talked to.
	var kimono_battles: Array = []
	for girl: Dictionary in [
		{"name": "naoko", "cell": Vector2i(1, 2), "facing": Gen2WorldSprite.FACING_LEFT},
		{"name": "sayo", "cell": Vector2i(2, 2), "facing": Gen2WorldSprite.FACING_UP},
		{"name": "zuki", "cell": Vector2i(5, 2), "facing": Gen2WorldSprite.FACING_RIGHT},
		{"name": "kuni", "cell": Vector2i(9, 2), "facing": Gen2WorldSprite.FACING_UP},
		{"name": "miki", "cell": Vector2i(10, 2), "facing": Gen2WorldSprite.FACING_RIGHT},
	]:
		var fought: Dictionary = _talk_to(
			world, girl["cell"], int(girl["facing"]), save, random, data
		)
		kimono_battles.append({
			"girl": String(girl["name"]),
			"battles": fought.get("run", {}).get("battles", []),
		})
		if not bool(fought.get("ok", false)):
			path.append({"step": "dance_theater_kimono_girls", "run": kimono_battles})
			return {
				"ok": false, "path": path,
				"reason": "Kimono Girl %s failed: %s" % [girl["name"], fought.get("reason", "")],
			}

	# DanceTheaterSurfGuy checks all five beaten flags before .GetSurf, so this
	# interaction is what the five battles were for.
	var surf_guy: Dictionary = _talk_to(
		world, Vector2i(7, 11), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "dance_theater_hm03_surf",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"kimono_girls": kimono_battles,
		"run": surf_guy.get("run", {}),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(surf_guy.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "HM03 handoff failed: %s" % surf_guy.get("reason", ""),
		}

	# Taught here, two legs before Route 40's south edge asks for it. The Ilex
	# Forest Psyduck is the only party member CanLearnTMHMMove accepts.
	var surf_taught: Dictionary = _teach_tm_hm(world, save, ITEM_HM_SURF)
	_mirror_party(world, save)
	path.append({
		"step": "dance_theater_teach_surf",
		"map": _map_value(world),
		"taught": surf_taught.get("ok", false),
		"species": _party_species(save),
		"moves": _party_moves(save),
	})
	if not bool(surf_taught.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "no party member learned SURF: %s" % surf_taught.get("reason", ""),
		}

	var leaving_theater: Dictionary = _warp_step(world, 4, 9)
	if not bool(leaving_theater.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Dance Theater exit warp failed"}
	var _city_again: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	var to_route_38: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(0, 18), 1, 12
	)
	if not bool(to_route_38.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Ecruteak to Route 38 failed: %s" % to_route_38.get("reason", ""),
		}
	for leg: Dictionary in [
		{"step": "route_38_to_route_39", "direction": "west", "group": 1, "number": 13},
		{"step": "route_39_to_olivine", "direction": "south", "group": 1, "number": 14},
	]:
		var walked: Dictionary = _walk_connection_resolving(
			world, String(leg["direction"]), int(leg["group"]), int(leg["number"]),
			save, random, data
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": String(leg["step"]),
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s failed: %s" % [leg["step"], walked.get("reason", "")],
			}

	# OlivineCity's first scene is SCENE_OLIVINECITY_RIVAL_ENCOUNTER, and its
	# coord event is the only thing that retires it. The scene ends on
	# variablesprite plus LoadUsedSpritesGFX, so it also exercises the pair.
	var rival: Dictionary = _walk_cell_resolving(world, Vector2i(13, 12), save, random, data)
	path.append({
		"step": "olivine_city_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": rival.get("encounters", []),
		"map_scene": world.state.map_scene(1, 14),
	})
	if not bool(rival.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Olivine rival scene failed: %s" % rival.get("reason", ""),
		}

	var cafe: Dictionary = _olivine_cafe_hm04(world, save, random, data, path)
	if not bool(cafe.get("ok", false)):
		return cafe

	var first_visit: Dictionary = _lighthouse_visit(world, save, random, data, path, "first")
	if not bool(first_visit.get("ok", false)):
		return first_visit

	var to_cianwood: Dictionary = _cianwood_crossing(world, save, random, data, path, false)
	if not bool(to_cianwood.get("ok", false)):
		return to_cianwood

	var pharmacy: Dictionary = _warp_walk(world, Vector2i(15, 47), save, random, data)
	if not bool(pharmacy.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Cianwood Pharmacy door unreachable: %s" % pharmacy.get("reason", ""),
		}
	var _pharmacy_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	# CianwoodPharmacist hands the SecretPotion over only while
	# EVENT_JASMINE_EXPLAINED_AMPHYS_SICKNESS is set; without it the same
	# interaction opens MART_CIANWOOD instead.
	var potion: Dictionary = _talk_to(
		world, Vector2i(2, 4), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "cianwood_pharmacy_secretpotion",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": potion.get("run", {}),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(potion.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "SecretPotion handoff failed: %s" % potion.get("reason", ""),
		}
	var leaving_pharmacy: Dictionary = _warp_step(world, 22, 3)
	if not bool(leaving_pharmacy.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Cianwood Pharmacy exit warp failed"}
	var _cianwood_again: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	var storm: Dictionary = _storm_badge_leg(world, save, random, data, path)
	if not bool(storm.get("ok", false)):
		return storm

	var back_to_olivine: Dictionary = _cianwood_crossing(world, save, random, data, path, true)
	if not bool(back_to_olivine.get("ok", false)):
		return back_to_olivine

	var second_visit: Dictionary = _lighthouse_visit(world, save, random, data, path, "cure")
	if not bool(second_visit.get("ok", false)):
		return second_visit

	_mirror_party(world, save)
	var gym: Dictionary = _warp_walk(world, Vector2i(10, 11), save, random, data)
	if not bool(gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Olivine Gym door unreachable: %s" % gym.get("reason", ""),
		}
	var gym_entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)
	var jasmine: Dictionary = _talk_to(
		world, Vector2i(5, 4), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "olivine_gym_jasmine",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": gym_entry.get("statuses", []),
		"run": jasmine.get("run", {}),
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
		"engine_flags": world.state.engine_flags(),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(jasmine.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Jasmine failed: %s" % jasmine.get("reason", ""),
		}
	return {"ok": true}


## The Mineral Badge to the Glacier Badge. Mahogany's gym is closed until the
## Rocket hideout under its souvenir shop is cleared
## (`EVENT_MAHOGANY_TOWN_POKEFAN_M_BLOCKS_GYM`, `maps/MahoganyTown.asm`), and the
## hideout only opens after Lance is met at the Lake of Rage, which is behind the
## Red Gyarados in the middle of the water.
##
## The hideout is three floors of one-way halves rather than one maze: each floor
## is cut in two and the halves are joined through the other floor, so the route
## climbs and drops the same ladders several times. Its own doors are the only
## other links, and each opens on something learned a floor away.
func _glacier_badge_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var crystal: bool = Gen2WorldState.is_crystal_profile(data)
	var mahogany_mart: Vector2i = _map_id(data, &"MAHOGANY_MART_1F")
	var rocket_b2f: Vector2i = _map_id(data, &"TEAM_ROCKET_BASE_B2F")
	var rocket_b3f: Vector2i = _map_id(data, &"TEAM_ROCKET_BASE_B3F")
	var leaving_gym: Dictionary = _warp_step(world, 1, 14)
	if not bool(leaving_gym.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Olivine Gym exit warp failed"}
	var _city_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	for leg: Dictionary in [
		{"step": "olivine_to_route_39", "direction": "north", "group": 1, "number": 13},
		{"step": "route_39_to_route_38", "direction": "east", "group": 1, "number": 12},
	]:
		var walked: Dictionary = _walk_connection_resolving(
			world, String(leg["direction"]), int(leg["group"]), int(leg["number"]),
			save, random, data
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": String(leg["step"]),
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s failed: %s" % [leg["step"], walked.get("reason", "")],
			}
	var to_ecruteak: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(35, 8), 4, 9
	)
	if not bool(to_ecruteak.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 38 back to Ecruteak failed: %s" % to_ecruteak.get("reason", ""),
		}

	var to_route_42: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(35, 26), 2, 5
	)
	if not bool(to_route_42.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Ecruteak to Route 42 failed: %s" % to_route_42.get("reason", ""),
		}
	# Route 42's halves do not join on foot. Its west side ends at x=13 and its
	# only other land exit is Mt Mortar's door at (10,5), which opens into a cave
	# pocket of its own, so the lake is the crossing. (13,9) is the west shore and
	# the water runs east and down to the far shore at (22,12).
	var across_route_42: Dictionary = _surf_at(
		world, Vector2i(13, 9), Gen2WorldSprite.FACING_RIGHT, save, random, data
	)
	if not bool(across_route_42.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 42 surf entry failed: %s" % across_route_42.get("reason", ""),
		}
	var route_42_shore: Dictionary = _walk_cell_resolving(
		world, Vector2i(22, 12), save, random, data, true
	)
	if not bool(route_42_shore.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 42 landfall failed: %s" % route_42_shore.get("reason", ""),
		}
	# The middle strip is its own pocket: a second lake separates it from the
	# half that reaches Mahogany, so the route takes the water twice.
	var second_crossing: Dictionary = _surf_at(
		world, Vector2i(33, 10), Gen2WorldSprite.FACING_RIGHT, save, random, data
	)
	if not bool(second_crossing.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 42 second surf failed: %s" % second_crossing.get("reason", ""),
		}
	var route_42_far_shore: Dictionary = _walk_cell_resolving(
		world, Vector2i(42, 9), save, random, data, true
	)
	path.append({
		"step": "route_42_lake_crossing",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"movement_mode": String(world.movement_mode),
	})
	if not bool(route_42_far_shore.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 42 far landfall failed: %s" % route_42_far_shore.get("reason", ""),
		}
	var to_mahogany: Dictionary = _walk_connection_resolving(
		world, "east", 2, 7, save, random, data
	)
	var mahogany_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_42_to_mahogany",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": to_mahogany.get("encounters", []),
		"run": mahogany_entry,
	})
	if not bool(to_mahogany.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 42 to Mahogany failed: %s" % to_mahogany.get("reason", ""),
		}

	var to_route_43: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(9, 1), 9, 5
	)
	if not bool(to_route_43.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Mahogany to Route 43 failed: %s" % to_route_43.get("reason", ""),
		}
	var to_lake: Dictionary = _walk_connection_resolving(
		world, "north", 9, 6, save, random, data
	)
	var lake_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_43_to_lake_of_rage",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": to_lake.get("encounters", []),
		"run": lake_entry,
	})
	if not bool(to_lake.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 43 to the Lake of Rage failed: %s" % to_lake.get("reason", ""),
		}

	# The shore cell north of the gramps: (20,26) is his own cell and (24,26) is
	# Fisher Raymond's, so the walked route takes the water at (22,26).
	var into_the_lake: Dictionary = _surf_at(
		world, Vector2i(22, 26), Gen2WorldSprite.FACING_UP, save, random, data
	)
	if not bool(into_the_lake.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Lake of Rage surf entry failed: %s" % into_the_lake.get("reason", ""),
		}
	# RedGyarados is loadwildmon plus BATTLETYPE_FORCESHINY, not a trainer, and
	# the Red Scale it leaves behind is what Lance appears for.
	var gyarados: Dictionary = _talk_to_on_water(
		world, Vector2i(18, 23), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "lake_of_rage_red_gyarados",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": gyarados.get("run", {}),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(gyarados.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Red Gyarados failed: %s" % gyarados.get("reason", ""),
		}
	var ashore: Dictionary = _walk_cell_resolving(
		world, Vector2i(22, 26), save, random, data, true
	)
	if not bool(ashore.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Lake of Rage landfall failed: %s" % ashore.get("reason", ""),
		}
	var lance: Dictionary = _talk_to(
		world, Vector2i(21, 29), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "lake_of_rage_lance",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": lance.get("run", {}),
		"mart_scene": world.state.map_scene(mahogany_mart.x, mahogany_mart.y),
	})
	if not bool(lance.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Lake of Rage Lance failed: %s" % lance.get("reason", ""),
		}

	var back_to_route_43: Dictionary = _walk_connection_resolving(
		world, "south", 9, 5, save, random, data
	)
	var _r43_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	if not bool(back_to_route_43.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Lake of Rage back to Route 43 failed: %s" % back_to_route_43.get(
				"reason", ""
			),
		}
	var back_to_mahogany: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(9, 51), 2, 7
	)
	if not bool(back_to_mahogany.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 43 back to Mahogany failed: %s" % back_to_mahogany.get("reason", ""),
		}

	# MahoganyMart1F's scene 1 is Lance's Dragonite clearing the shop and the
	# changeblock that uncovers the staircase, deferred by the scene script.
	var mart: Dictionary = _warp_walk(world, Vector2i(11, 7), save, random, data)
	if not bool(mart.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Mahogany Mart door unreachable: %s" % mart.get("reason", ""),
		}
	var stairs: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data, true
	)
	path.append({
		"step": "mahogany_mart_lance_uncovers_the_stairs",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": stairs,
	})
	if not bool(stairs.get("terminal", false)):
		return {
			"ok": false, "path": path,
			"reason": "Mahogany Mart staircase scene did not finish: %s" % stairs.get(
				"reason", ""
			),
		}

	var into_the_base: Dictionary = _warp_walk(world, Vector2i(7, 3), save, random, data)
	if not bool(into_the_base.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Rocket base staircase unreachable: %s" % into_the_base.get("reason", ""),
		}
	var _b1f_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	# The secret switch behind the bookshelves sets all five camera events at
	# once, which is what stops the coord events on the way to the B2F ladder
	# from calling two grunts each.
	var switch: Dictionary = _talk_to(
		world, Vector2i(19, 12), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "rocket_base_b1f_secret_switch",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": switch.get("run", {}),
	})
	if not bool(switch.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B1F secret switch failed: %s" % switch.get("reason", ""),
		}
	var to_b2f: Dictionary = _warp_walk(world, Vector2i(3, 14), save, random, data)
	if not bool(to_b2f.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B2F ladder unreachable: %s" % to_b2f.get("reason", ""),
		}
	var _b2f_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var heal: Dictionary = _walk_cell_resolving(world, Vector2i(5, 14), save, random, data)
	path.append({
		"step": "rocket_base_b2f_lance_heals",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": heal.get("encounters", []),
		"scene": world.state.map_scene(rocket_b2f.x, rocket_b2f.y),
	})
	if not bool(heal.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B2F Lance heal failed: %s" % heal.get("reason", ""),
		}

	# The B2F ladder the heal room reaches is the far one: row 12 is a solid wall
	# and the only way north out of the bottom section is the right-hand column.
	var to_b3f: Dictionary = _warp_walk(world, Vector2i(27, 14), save, random, data)
	if not bool(to_b3f.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B3F ladder unreachable: %s" % to_b3f.get("reason", ""),
		}
	# B3F's first scene defers LanceGetPasswordScript, which ends by arming the
	# rival scene; the rival scene arms the executive.
	var password_scene: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data, true
	)
	path.append({
		"step": "rocket_base_b3f_lance_asks_for_the_password",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": password_scene,
		"scene": world.state.map_scene(rocket_b3f.x, rocket_b3f.y),
	})
	if not bool(password_scene.get("terminal", false)):
		return {
			"ok": false, "path": path,
			"reason": "B3F Lance scene did not finish: %s" % password_scene.get("reason", ""),
		}
	# Both password grunts stand on the half of B3F the heal-room ladder reaches,
	# and their after-battle scripts are what set EVENT_LEARNED_SLOWPOKETAIL and
	# EVENT_LEARNED_RATICATE_TAIL, which the door to Giovanni's office checks.
	# The Raticate-tail grunt stands one cell further south in pokegold, so the
	# cell it is faced from moves with it; the Slowpoke-tail one does not move.
	var raticate_tail_from: Vector2i = Vector2i(5, 15) if crystal else Vector2i(5, 16)
	for grunt: Dictionary in [
		{"name": "slowpoketail", "cell": Vector2i(21, 8), "facing": Gen2WorldSprite.FACING_UP},
		{"name": "raticate_tail", "cell": raticate_tail_from, "facing": Gen2WorldSprite.FACING_UP},
	]:
		var fought: Dictionary = _talk_to(
			world, grunt["cell"], int(grunt["facing"]), save, random, data
		)
		if not bool(fought.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "B3F %s grunt failed: %s" % [grunt["name"], fought.get("reason", "")],
			}
		# The password is in the after-battle script, and that script opens with
		# endifjustbattled, so the turn that beat the grunt ends before reaching
		# the setevent. The source needs the second conversation, which is what
		# actually says the password.
		var password: Dictionary = _talk_to(
			world, grunt["cell"], int(grunt["facing"]), save, random, data
		)
		path.append({
			"step": "rocket_base_b3f_%s_grunt" % grunt["name"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"battle": fought.get("run", {}).get("battles", []),
			"run": password.get("run", {}),
		})
		if not bool(password.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "B3F %s password failed: %s" % [
					grunt["name"], password.get("reason", ""),
				],
			}

	# B3F's northern half is walled off from this one, and it is entered from
	# B2F's own northern half, so the route goes up one ladder and down another.
	var b3f_up: Dictionary = _warp_walk(world, Vector2i(27, 2), save, random, data)
	if not bool(b3f_up.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B3F north-east ladder unreachable: %s" % b3f_up.get("reason", ""),
		}
	var _b2f_north: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var b3f_down: Dictionary = _warp_walk(world, Vector2i(3, 2), save, random, data)
	if not bool(b3f_down.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B2F north-west ladder unreachable: %s" % b3f_down.get("reason", ""),
		}
	var _b3f_north: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var rival: Dictionary = _walk_cell_resolving(world, Vector2i(8, 10), save, random, data)
	path.append({
		"step": "rocket_base_b3f_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": rival.get("encounters", []),
		"scene": world.state.map_scene(rocket_b3f.x, rocket_b3f.y),
	})
	if not bool(rival.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B3F rival scene failed: %s" % rival.get("reason", ""),
		}
	# Giovanni's door is the only way into the office: row 9 is solid either side
	# of it. It opens on the two passwords and changeblocks itself to floor.
	var office_door: Dictionary = _talk_to(
		world, Vector2i(10, 10), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "rocket_base_b3f_giovannis_door",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": office_door.get("run", {}),
	})
	if not bool(office_door.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B3F office door failed: %s" % office_door.get("reason", ""),
		}
	var executive: Dictionary = _walk_cell_resolving(world, Vector2i(10, 8), save, random, data)
	path.append({
		"step": "rocket_base_b3f_executive",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": executive.get("encounters", []),
		"scene": world.state.map_scene(rocket_b3f.x, rocket_b3f.y),
	})
	if not bool(executive.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B3F executive failed: %s" % executive.get("reason", ""),
		}
	# The Murkrow behind the desk is what says the transmitter password.
	var murkrow: Dictionary = _talk_to(
		world, Vector2i(7, 3), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "rocket_base_b3f_murkrow",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": murkrow.get("run", {}),
	})
	if not bool(murkrow.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B3F Murkrow failed: %s" % murkrow.get("reason", ""),
		}

	# Back down to the machine room's own floor, which means unwinding the same
	# three ladders: B2F's north-west pocket does not reach its south half either.
	for ladder: Dictionary in [
		{"step": "b3f_north_to_b2f_north", "cell": Vector2i(3, 2)},
		{"step": "b2f_north_to_b3f_south", "cell": Vector2i(27, 2)},
		{"step": "b3f_south_to_b2f_south", "cell": Vector2i(27, 14)},
	]:
		var taken: Dictionary = _warp_walk(world, ladder["cell"], save, random, data)
		if not bool(taken.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s ladder unreachable: %s" % [
					ladder["step"], taken.get("reason", ""),
				],
			}
		var _floor_entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
	# The machine room is walled off on every side but its own door: B2F's row 12
	# is solid and rows 3 to 11 between x=7 and x=22 touch nothing else. So the
	# transmitter door is the way in, and it opens on the password the Murkrow
	# gave.
	var transmitter_door: Dictionary = _talk_to(
		world, Vector2i(14, 13), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "rocket_base_b2f_transmitter_door",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": transmitter_door.get("run", {}),
	})
	if not bool(transmitter_door.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B2F transmitter door failed: %s" % transmitter_door.get("reason", ""),
		}
	# Stepping onto the cell north of that door is the executive's coord event,
	# and it ends by arming the electrodes.
	# The scene walks the player itself and then confines them with the
	# electrodes, so the walk is expected not to reach its own target: what says
	# the executive happened is the scene moving on.
	var boss_f: Dictionary = _walk_cell_resolving(world, Vector2i(14, 11), save, random, data)
	var electrodes_armed: bool = world.state.map_scene(rocket_b2f.x, rocket_b2f.y) == 2
	path.append({
		"step": "rocket_base_b2f_executive",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": boss_f.get("encounters", []),
		"scene": world.state.map_scene(rocket_b2f.x, rocket_b2f.y),
	})
	if not electrodes_armed:
		return {
			"ok": false, "path": path,
			"reason": "B2F executive failed: %s" % boss_f.get("reason", ""),
		}
	# Three Electrodes power the transmitter. Each is a loadwildmon battle, and
	# the third one to fall runs the script that ends the hideout.
	for electrode: Dictionary in [
		{"name": "1", "cell": Vector2i(8, 5)},
		{"name": "2", "cell": Vector2i(8, 7)},
		{"name": "3", "cell": Vector2i(8, 9)},
	]:
		var zapped: Dictionary = _talk_to(
			world, electrode["cell"], Gen2WorldSprite.FACING_LEFT, save, random, data
		)
		path.append({
			"step": "rocket_base_b2f_electrode_%s" % electrode["name"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"run": zapped.get("run", {}),
			"items": _named_items(data, world.state.items()),
		})
		if not bool(zapped.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "B2F electrode %s failed: %s" % [
					electrode["name"], zapped.get("reason", ""),
				],
			}

	# The third Electrode brings Lance back with HM06, and it is taught here for
	# the same reason Surf is taught in the Dance Theater: Dragon's Den B1F's
	# whirlpool is several legs away, and the only party member
	# CanLearnTMHMMove accepts for WHIRLPOOL is the Ilex Forest Psyduck.
	var whirlpool_taught: Dictionary = _teach_tm_hm(world, save, ITEM_HM_WHIRLPOOL)
	_mirror_party(world, save)
	path.append({
		"step": "rocket_base_b2f_teach_whirlpool",
		"map": _map_value(world),
		"taught": whirlpool_taught.get("ok", false),
		"species": _party_species(save),
		"moves": _party_moves(save),
	})
	if not bool(whirlpool_taught.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "no party member learned WHIRLPOOL: %s" % whirlpool_taught.get("reason", ""),
		}

	# Out the way the route came in. Clearing the base hides the grunts, so the
	# walk back is not the one that came down.
	for ladder: Dictionary in [
		{"step": "b2f_to_b1f", "group": 3, "number": 49, "cell": Vector2i(3, 14)},
		{"step": "b1f_to_the_shop", "group": 3, "number": 48, "cell": Vector2i(27, 2)},
		{"step": "shop_to_mahogany", "group": 2, "number": 7, "cell": Vector2i(3, 7)},
	]:
		var climbed: Dictionary = _warp_walk(world, ladder["cell"], save, random, data)
		if not bool(climbed.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s unreachable: %s" % [ladder["step"], climbed.get("reason", "")],
			}
		var _above: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)

	_mirror_party(world, save)
	var gym: Dictionary = _warp_walk(world, Vector2i(6, 13), save, random, data)
	if not bool(gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Mahogany Gym door unreachable: %s" % gym.get("reason", ""),
		}
	var gym_entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)
	# Pryce's floor is COLL_ICE, which is LAND_TILE, so the walk crosses it
	# without the source's sliding.
	var pryce: Dictionary = _talk_to(
		world, Vector2i(5, 4), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "mahogany_gym_pryce",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": gym_entry.get("statuses", []),
		"run": pryce.get("run", {}),
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
		"engine_flags": world.state.engine_flags(),
		"items": _named_items(data, world.state.items()),
		# The badge is not all Pryce commits. `readvar VAR_BADGES` then
		# `scall MahoganyGymActivateRockets` reaches RadioTowerRocketsScript at
		# seven badges, which is what retires Mahogany's RageCandyBar coord
		# events and hides the merchant blocking the east exit. Reported here
		# because the next leg cannot start without both.
		"mahogany_scene": world.state.map_scene(
			MAHOGANY_TOWN_GROUP, MAHOGANY_TOWN_NUMBER
		),
		"east_merchant_hidden": world.state.is_event_flag_active(
			EVENT_MAHOGANY_POKEFAN_M_BLOCKS_EAST
		),
	})
	if not bool(pryce.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Pryce failed: %s" % pryce.get("reason", ""),
		}
	return {"ok": true}


## Mahogany Town west to Goldenrod City and back, clearing the Radio Tower.
##
## This leg is what opens Blackthorn Gym. `maps/BlackthornCity.asm` stands
## BLACKTHORNCITY_SUPER_NERD1 on (18,12), the only cell that reaches the gym
## door warp at (18,11), and its event flag is set only by
## `maps/RadioTower5F.asm`'s boss script. Beating Pryce already ran
## `RadioTowerRocketsScript` (`engine/events/std_scripts.asm`), so the takeover
## is armed before the leg starts: the Rockets are visible and the Black Belt
## who would block 2F's stairs is hidden.
##
## The walk back is six connections west, all of them crossed eastward earlier
## in the route, and the two Route 42 lakes are surfed in reverse. Appends to
## [param path] and answers only ok or the failure.
func _radio_tower_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var leaving_gym: Dictionary = _warp_step(world, 2, 7)
	if not bool(leaving_gym.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Mahogany Gym exit warp failed"}
	var _town_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	var westward: Dictionary = _goldenrod_crossing(world, save, random, data, path, "west")
	if not bool(westward.get("ok", false)):
		return westward

	var basement_key: Dictionary = _radio_tower_basement_key(world, save, random, data, path)
	if not bool(basement_key.get("ok", false)):
		return basement_key

	var card_key: Dictionary = _goldenrod_underground_card_key(world, save, random, data, path)
	if not bool(card_key.get("ok", false)):
		return card_key

	var boss: Dictionary = _radio_tower_boss(world, save, random, data, path)
	if not bool(boss.get("ok", false)):
		return boss

	var eastward: Dictionary = _goldenrod_crossing(world, save, random, data, path, "east")
	if not bool(eastward.get("ok", false)):
		return eastward

	return {"ok": true}


## The card-key shutter on Radio Tower 3F and the Rocket boss on 5F.
##
## `CardKeySlotScript` is a BGEVENT_UP at (14,2), so it is read by facing up
## from (14,3). It changeblocks the shutter open and sets
## EVENT_USED_THE_CARD_KEY_IN_THE_RADIO_TOWER, which is what
## RadioTower3FCardKeyShutterCallback replays on every later load. Only then
## does 3F's second staircase at (17,0) exist, and it is the only way into the
## 4F and 5F shafts the boss stands in.
func _radio_tower_boss(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var climbed: Dictionary = _warp_chain(
		world, save, random, data,
		[Vector2i(5, 15), Vector2i(15, 0), Vector2i(0, 0)]
	)
	if not bool(climbed.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Radio Tower return climb failed: %s" % climbed.get("reason", ""),
		}

	var slot: Dictionary = _talk_to(
		world, Vector2i(14, 3), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "radio_tower_card_key_slot",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": slot.get("run", {}),
	})
	if not bool(slot.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "card key slot failed: %s" % slot.get("reason", ""),
		}

	var to_boss: Dictionary = _warp_chain(
		world, save, random, data, [Vector2i(17, 0), Vector2i(12, 0)]
	)
	if not bool(to_boss.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Radio Tower shutter shaft failed: %s" % to_boss.get("reason", ""),
		}

	var boss: Dictionary = _walk_cell_resolving(world, Vector2i(16, 5), save, random, data)
	path.append({
		"step": "radio_tower_rocket_boss",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": boss.get("encounters", []),
		"cleared_radio_tower": world.event_flag_active(EVENT_CLEARED_RADIO_TOWER),
		"blackthorn_gym_open": world.event_flag_active(
			EVENT_BLACKTHORN_SUPER_NERD_BLOCKS_GYM
		),
	})
	if not bool(boss.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Rocket boss failed: %s" % boss.get("reason", ""),
		}
	if not world.event_flag_active(EVENT_CLEARED_RADIO_TOWER):
		return {"ok": false, "path": path, "reason": "the Radio Tower did not clear"}
	if not world.event_flag_active(EVENT_BLACKTHORN_SUPER_NERD_BLOCKS_GYM):
		return {"ok": false, "path": path, "reason": "Blackthorn Gym is still sealed"}

	# The descent stops on 1F rather than running straight out of the door,
	# because the boss script above just cleared EVENT_GOLDENROD_CITY_CIVILIANS
	# (`maps/RadioTower5F.asm`) and the Radio Card woman is one of the objects
	# that flag hides.
	var descended: Dictionary = _warp_chain(
		world, save, random, data,
		[Vector2i(12, 0), Vector2i(17, 0), Vector2i(0, 0), Vector2i(15, 0)]
	)
	if not bool(descended.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Radio Tower return descent failed: %s" % descended.get("reason", ""),
		}

	var card: Dictionary = _talk_to(
		world, RADIO_CARD_WOMAN_FACE, Gen2WorldSprite.FACING_DOWN,
		save, random, data, RADIO_CARD_ANSWERS
	)
	path.append({
		"step": "radio_tower_radio_card",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"radio_card": world.state.is_engine_flag_active(Gen2WorldState.ENGINE_RADIO_CARD),
		"run": card.get("run", {}),
	})
	if not bool(card.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Radio Card quiz did not finish: %s" % card.get("reason", ""),
		}
	if not world.state.is_engine_flag_active(Gen2WorldState.ENGINE_RADIO_CARD):
		return {"ok": false, "path": path, "reason": "ENGINE_RADIO_CARD was not set"}

	var out_of_tower: Dictionary = _warp_chain(world, save, random, data, [Vector2i(2, 7)])
	if not bool(out_of_tower.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving the Radio Tower failed: %s" % out_of_tower.get("reason", ""),
		}
	return {"ok": true}


## Goldenrod City to the warehouse director's CARD_KEY, and back.
##
## Three maps, each cut into regions the others join. GoldenrodUnderground's
## north half is reached from the switch room's south corridor and ends at the
## basement door (18,6), which `BasementDoorScript` unlocks with the
## BASEMENT_KEY and which then warps to the underground's south half. That half
## reaches the switch room's top corridor, where the three switches are.
##
## The puzzle is `GoldenrodUndergroundSwitchRoomEntrances_UpdateDoors`: switch 1,
## 2 and 3 add 1, 2 and 3 to `wUndergroundSwitchPositions` and each position
## opens some doors and closes others, leaving the ones it does not name alone,
## so states accumulate. Turning 3, then 2, then 1 walks positions 3, 5 and 6 and
## ends with doors 3, 5, 6, 8, 9 and 11 open, which is the one chain from the top
## corridor to the warehouse doors at (22,10) and (23,10).
##
## Coming back needs the emergency switch: the warehouse's own
## MAPCALLBACK_NEWMAP clears every door event, so re-entering the switch room
## seals the room the warehouse opens into, and `EmergencySwitchScript` at
## (20,11) is the only switch reachable from inside it.
func _goldenrod_underground_card_key(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var inbound: Dictionary = _warp_chain(
		world, save, random, data, [Vector2i(9, 5), Vector2i(21, 25)]
	)
	if not bool(inbound.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Goldenrod Underground entry failed: %s" % inbound.get("reason", ""),
		}

	var basement_door: Dictionary = _talk_to(
		world, Vector2i(18, 7), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "goldenrod_underground_basement_door",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": basement_door.get("run", {}),
	})
	if not bool(basement_door.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "basement door failed: %s" % basement_door.get("reason", ""),
		}

	var to_switch_room: Dictionary = _warp_chain(
		world, save, random, data, [Vector2i(18, 6), Vector2i(22, 27)]
	)
	if not bool(to_switch_room.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "basement door crossing failed: %s" % to_switch_room.get("reason", ""),
		}

	# Switch 3, then 2, then 1. The rival's coord event at (19,4) and (19,5) sits
	# on the way to the first of them.
	for switch: Vector2i in [Vector2i(2, 2), Vector2i(10, 2), Vector2i(16, 2)]:
		var thrown: Dictionary = _talk_to(
			world, switch, Gen2WorldSprite.FACING_UP, save, random, data
		)
		path.append({
			"step": "goldenrod_underground_switch",
			"map": _map_value(world),
			"cell": _cell_value(world),
			"run": thrown.get("run", {}),
		})
		if not bool(thrown.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "switch at %s failed: %s" % [switch, thrown.get("reason", "")],
			}

	var to_warehouse: Dictionary = _warp_chain(world, save, random, data, [Vector2i(22, 10)])
	if not bool(to_warehouse.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "warehouse door failed: %s" % to_warehouse.get("reason", ""),
		}

	var director: Dictionary = _talk_to(
		world, Vector2i(12, 9), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "goldenrod_warehouse_director",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": director.get("run", {}),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(director.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "warehouse director failed: %s" % director.get("reason", ""),
		}
	if not world.state.items().has(ITEM_CARD_KEY):
		return {"ok": false, "path": path, "reason": "the warehouse director left no CARD_KEY"}

	var back_to_switch_room: Dictionary = _warp_chain(
		world, save, random, data, [Vector2i(2, 12)]
	)
	if not bool(back_to_switch_room.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "warehouse exit failed: %s" % back_to_switch_room.get("reason", ""),
		}

	var emergency: Dictionary = _talk_to(
		world, Vector2i(20, 12), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "goldenrod_underground_emergency_switch",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": emergency.get("run", {}),
	})
	if not bool(emergency.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "emergency switch failed: %s" % emergency.get("reason", ""),
		}

	var outbound: Dictionary = _warp_chain(
		world, save, random, data,
		[Vector2i(23, 3), Vector2i(21, 31), Vector2i(3, 2), Vector2i(20, 29)]
	)
	if not bool(outbound.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Goldenrod Underground exit failed: %s" % outbound.get("reason", ""),
		}
	return {"ok": true}


## Goldenrod City to the fake director on Radio Tower 5F, and back out.
##
## The climb is one shaft: 1F (15,0), 2F (0,0), 3F (7,0), 4F (0,0). 2F's stairs
## are behind the Black Belt on (0,1), whom `RadioTowerRocketsScript` already
## hid, and 3F's other staircase at (17,0) is behind the card-key shutter, which
## is the second half of the leg. 4F and 5F are each two shafts that do not
## join, so the fake director at 5F (0,3) is reachable only from this one.
func _radio_tower_basement_key(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var climbed: Dictionary = _warp_chain(
		world, save, random, data,
		[Vector2i(5, 15), Vector2i(15, 0), Vector2i(0, 0), Vector2i(7, 0), Vector2i(0, 0)]
	)
	if not bool(climbed.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Radio Tower climb failed: %s" % climbed.get("reason", ""),
		}

	# FakeDirectorScript is a coord event, not an interaction: stepping onto
	# (0,3) runs it (`maps/RadioTower5F.asm`). It battles EXECUTIVEM_3, hands
	# over the BASEMENT_KEY and arms the boss coord event with
	# setscene SCENE_RADIOTOWER5F_ROCKET_BOSS.
	var fake_director: Dictionary = _walk_cell_resolving(
		world, Vector2i(0, 3), save, random, data
	)
	path.append({
		"step": "radio_tower_fake_director",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": fake_director.get("encounters", []),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(fake_director.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "fake director failed: %s" % fake_director.get("reason", ""),
		}
	if not world.state.items().has(ITEM_BASEMENT_KEY):
		return {"ok": false, "path": path, "reason": "the fake director left no BASEMENT_KEY"}

	var descended: Dictionary = _warp_chain(
		world, save, random, data,
		[Vector2i(0, 0), Vector2i(9, 0), Vector2i(0, 0), Vector2i(15, 0), Vector2i(2, 7)]
	)
	if not bool(descended.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Radio Tower descent failed: %s" % descended.get("reason", ""),
		}
	return {"ok": true}


## Walks each cell in [param cells] on the map it belongs to and takes the warp
## there, draining the arrival callbacks between maps.
func _warp_chain(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	cells: Array,
) -> Dictionary:
	for cell: Vector2i in cells:
		var walked: Dictionary = _warp_walk(world, cell, save, random, data)
		if not bool(walked.get("ok", false)):
			return {
				"ok": false,
				"reason": "warp at %s on %s failed: %s" % [
					cell, _map_value(world), walked.get("reason", ""),
				],
			}
		var _entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
	return {"ok": true}


## Mahogany Town and Goldenrod City in either direction, on the same world,
## state and save. [param heading] is "west" for Mahogany to Goldenrod and
## "east" for the return.
##
## The chain is Mahogany, Route 42, Ecruteak City, Route 37, Route 36, Route 35,
## Goldenrod (`data/maps/attributes.asm`), with Route 35's south end a gate
## building rather than a connection (`maps/Route35.asm` warp to
## ROUTE_35_GOLDENROD_GATE). Route 42's two lakes have no land path around them,
## so both are surfed, and Route 35's cut tree regrows on every map load, so it
## is cut on every crossing.
func _goldenrod_crossing(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
	heading: String,
) -> Dictionary:
	var westbound: bool = heading == "west"
	if westbound:
		var to_route_42: Dictionary = _walk_connection_resolving(
			world, "west", 2, 5, save, random, data
		)
		var _r42_entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		if not bool(to_route_42.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Mahogany to Route 42 failed: %s" % to_route_42.get("reason", ""),
			}
		# The same two lakes _glacier_badge_path() crossed eastward, taken from
		# the far shore each time.
		var second_lake: Dictionary = _lake_crossing(
			world, save, random, data,
			Vector2i(42, 9), Gen2WorldSprite.FACING_LEFT, Vector2i(33, 10)
		)
		if not bool(second_lake.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Route 42 east lake westbound failed: %s" % second_lake.get("reason", ""),
			}
		var first_lake: Dictionary = _lake_crossing(
			world, save, random, data,
			Vector2i(22, 12), Gen2WorldSprite.FACING_LEFT, Vector2i(13, 9)
		)
		if not bool(first_lake.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Route 42 west lake westbound failed: %s" % first_lake.get("reason", ""),
			}
		path.append({
			"step": "route_42_lakes_westbound",
			"map": _map_value(world),
			"cell": _cell_value(world),
			"movement_mode": String(world.movement_mode),
		})
		# Route 42's west end is the Ecruteak gate, not a connection: (0,8) and
		# (0,9) are its only west-edge cells and both are warps
		# (`maps/Route42.asm`).
		var to_ecruteak: Dictionary = _gate_leg(
			world, save, random, data, Vector2i(0, 8), 4, 9
		)
		if not bool(to_ecruteak.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Route 42 to Ecruteak failed: %s" % to_ecruteak.get("reason", ""),
			}
		for leg: Array in [["south", 10, 4], ["south", 10, 3], ["south", 10, 2]]:
			var walked: Dictionary = _walk_connection_resolving(
				world, String(leg[0]), int(leg[1]), int(leg[2]), save, random, data
			)
			var _entry: Dictionary = _drain_story(
				world, world.dispatch_map_entry(), save, random, data
			)
			if not bool(walked.get("ok", false)):
				return {
					"ok": false, "path": path,
					"reason": "walk %s to %d/%d failed: %s" % [
						leg[0], leg[1], leg[2], walked.get("reason", ""),
					],
				}
		var south_cut: Dictionary = _cut_at(
			world, Vector2i(17, 5), Gen2WorldSprite.FACING_DOWN, save, random, data
		)
		if not bool(south_cut.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Route 35 southbound cut failed: %s" % south_cut.get("reason", ""),
			}
		var to_goldenrod: Dictionary = _gate_leg(
			world, save, random, data, Vector2i(9, 33), 11, 2
		)
		if not bool(to_goldenrod.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Route 35 to Goldenrod failed: %s" % to_goldenrod.get("reason", ""),
			}
		path.append({
			"step": "mahogany_to_goldenrod",
			"map": _map_value(world),
			"cell": _cell_value(world),
		})
		return {"ok": true}

	var to_route_35: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(19, 1), 10, 2
	)
	if not bool(to_route_35.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Goldenrod to Route 35 failed: %s" % to_route_35.get("reason", ""),
		}
	var north_cut: Dictionary = _cut_at(
		world, Vector2i(17, 7), Gen2WorldSprite.FACING_UP, save, random, data
	)
	if not bool(north_cut.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 35 northbound cut failed: %s" % north_cut.get("reason", ""),
		}
	for leg: Array in [["north", 10, 3], ["north", 10, 4], ["north", 4, 9]]:
		var walked: Dictionary = _walk_connection_resolving(
			world, String(leg[0]), int(leg[1]), int(leg[2]), save, random, data
		)
		var _entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "walk %s to %d/%d failed: %s" % [
					leg[0], leg[1], leg[2], walked.get("reason", ""),
				],
			}
	var to_route_42: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(35, 26), 2, 5
	)
	if not bool(to_route_42.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Ecruteak to Route 42 failed: %s" % to_route_42.get("reason", ""),
		}
	var west_lake: Dictionary = _lake_crossing(
		world, save, random, data,
		Vector2i(13, 9), Gen2WorldSprite.FACING_RIGHT, Vector2i(22, 12)
	)
	if not bool(west_lake.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 42 west lake eastbound failed: %s" % west_lake.get("reason", ""),
		}
	var east_lake: Dictionary = _lake_crossing(
		world, save, random, data,
		Vector2i(33, 10), Gen2WorldSprite.FACING_RIGHT, Vector2i(42, 9)
	)
	if not bool(east_lake.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 42 east lake eastbound failed: %s" % east_lake.get("reason", ""),
		}
	var to_mahogany: Dictionary = _walk_connection_resolving(
		world, "east", 2, 7, save, random, data
	)
	var _mahogany_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	if not bool(to_mahogany.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 42 to Mahogany failed: %s" % to_mahogany.get("reason", ""),
		}
	path.append({
		"step": "goldenrod_to_mahogany",
		"map": _map_value(world),
		"cell": _cell_value(world),
	})
	return {"ok": true}


## Surfs from [param shore] in [param facing] and lands on [param landfall],
## keeping the plan on the water in between so it cannot step ashore partway.
func _lake_crossing(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	shore: Vector2i,
	facing: int,
	landfall: Vector2i,
) -> Dictionary:
	var entered: Dictionary = _surf_at(world, shore, facing, save, random, data)
	if not bool(entered.get("ok", false)):
		return entered
	return _walk_cell_resolving(world, landfall, save, random, data, true)


## Blackthorn City to the Rising Badge, on the same world, state and save.
##
## The badge is not won in the gym. `BlackthornGymClairScript` sets only
## `EVENT_BEAT_CLAIR` and swaps the two Blackthorn gramps so the Dragon's Den
## door at (20,1) opens. `maps/DragonShrine.asm` is what runs
## `setflag ENGINE_RISINGBADGE` on Crystal, at the end of the elder's
## five-question quiz; Gold and Silver have no shrine and put the same line in
## `DragonsDenB1FDragonFangScript` (`maps/DragonsDenB1F.asm`).
##
## Appends to [param path] and answers only ok or the failure.
func _rising_badge_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	# The mart before the gym, because the Dragon's Den catch on the way back out
	# needs more balls than Elm's aide gave and Blackthorn is the last town the
	# route stands in before it.
	var mart_trip: Dictionary = _warp_chain(world, save, random, data, [Vector2i(15, 29)])
	if not bool(mart_trip.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Blackthorn Mart unreachable: %s" % mart_trip.get("reason", ""),
		}
	var bought: Dictionary = _buy_great_balls(
		world, save, random, data, path, GREAT_BALLS_BOUGHT
	)
	if not bool(bought.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Blackthorn Mart failed: %s" % bought.get("reason", ""),
		}
	var out_of_mart: Dictionary = _warp_chain(world, save, random, data, [Vector2i(2, 7)])
	if not bool(out_of_mart.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Blackthorn Mart exit failed: %s" % out_of_mart.get("reason", ""),
		}

	var gym: Dictionary = _blackthorn_gym_leg(world, save, random, data, path)
	if not bool(gym.get("ok", false)):
		return gym

	var shrine: Dictionary = _dragon_shrine_leg(world, save, random, data, path)
	if not bool(shrine.get("ok", false)):
		return shrine

	return {"ok": true}


## Blackthorn Gym's boulder puzzle and Clair.
##
## 1F is four regions, and the entrance reaches only one of them. 2F's three
## holes are `stonetable` rows, and a boulder that falls through one is
## `disappear`ed and sets its own event flag, which
## `BlackthornGym1FBouldersCallback` turns into a `changeblock` on 1F. Two of
## those changes are the route: BOULDER1 through the (8,3) hole opens 1F (8,3),
## joining the middle corridor to Clair's room, and BOULDER3 through the (8,7)
## hole opens 1F (8,7), joining that corridor to the pocket 2F's (7,9) staircase
## drops into. BOULDER2's hole adds one 1F cell beside the entrance and reaches
## nothing, so the walk leaves it alone.
##
## BOULDER1 is one push; BOULDER3 starts nine cells south of the row it has to
## cross on, so it goes north until the wall at (6,6) stops it and then east
## into the hole.
func _blackthorn_gym_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	if not world.strength_active():
		return {"ok": false, "path": path, "reason": "Strength is not active"}
	var to_gym: Dictionary = _warp_chain(
		world, save, random, data, [Vector2i(18, 11), Vector2i(1, 7)]
	)
	if not bool(to_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Blackthorn Gym 2F unreachable: %s" % to_gym.get("reason", ""),
		}

	for leg: Dictionary in BLACKTHORN_GYM_PUSHES:
		var pushes: Array = []
		for push: Array in leg["pushes"]:
			var moved: Dictionary = _push_boulder_run(
				world, push[0], push[1], save, random, data
			)
			pushes.append(moved)
			if not bool(moved.get("ok", false)):
				path.append({
					"step": String(leg["step"]),
					"map": _map_value(world),
					"cell": _cell_value(world),
					"pushes": pushes,
				})
				return {
					"ok": false, "path": path,
					"reason": "%s failed: %s" % [leg["step"], moved.get("reason", "")],
				}
		var flag: int = int(leg.get("flag", -1))
		path.append({
			"step": String(leg["step"]),
			"map": _map_value(world),
			"cell": _cell_value(world),
			"pushes": pushes.size(),
			"fell": flag >= 0 and world.event_flag_active(flag),
		})
		if flag >= 0 and not world.event_flag_active(flag):
			return {
				"ok": false, "path": path,
				"reason": "%s did not fall through" % leg["step"],
			}

	# 2F's (7,9) staircase drops into the 1F pocket the two fallen boulders have
	# just joined to Clair's room.
	var down: Dictionary = _warp_chain(world, save, random, data, [Vector2i(7, 9)])
	if not bool(down.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Blackthorn Gym 1F return failed: %s" % down.get("reason", ""),
		}

	var clair: Dictionary = _talk_to(
		world, Vector2i(5, 4), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "blackthorn_gym_clair",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": clair.get("run", {}),
		"beat_clair": world.event_flag_active(EVENT_BEAT_CLAIR),
	})
	if not bool(clair.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Clair failed: %s" % clair.get("reason", ""),
		}
	if not world.event_flag_active(EVENT_BEAT_CLAIR):
		return {"ok": false, "path": path, "reason": "Clair was not beaten"}
	return {"ok": true}


## Blackthorn City to the Dragon Shrine, and the elder's quiz.
##
## Clair's script sets `EVENT_BLACKTHORN_CITY_GRAMPS_BLOCKS_DRAGONS_DEN` and
## clears its partner, which swaps the gramps standing on (20,2) for one beside
## it and opens the den door at (20,1). Neither den floor needs a field move:
## B1F's shrine warp at (19,29) is on the same land region as the ladder from
## 1F, and the whirlpool at (10,20) guards the water pocket rather than the way
## through.
##
## The quiz is answered correctly. `.WrongAnswer` on the last question checks
## `EVENT_TEMPORARY_UNTIL_MAP_RELOAD_6`, which question 5 has already set, so it
## asks question 5 again: a wrong answer there is the one that does not move on.
func _dragon_shrine_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var out_of_gym: Dictionary = _warp_chain(
		world, save, random, data, [Vector2i(7, 9), Vector2i(1, 7), Vector2i(4, 17)]
	)
	if not bool(out_of_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Blackthorn Gym exit failed: %s" % out_of_gym.get("reason", ""),
		}

	# The den door is across the lake, not around it. Every land route from the
	# town centre is walled off by the $b2 fence line and the one-way $a3 ledges,
	# and (20,4) below the door's shore is COLL_WATER, so the crossing is the
	# way in. That is also what the gramps on (20,3) blocks until Clair moves him.
	var crossing: Dictionary = _lake_crossing(
		world, save, random, data,
		Vector2i(22, 12), Gen2WorldSprite.FACING_UP, Vector2i(20, 3)
	)
	path.append({
		"step": "blackthorn_lake_crossing",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"movement_mode": String(world.movement_mode),
	})
	if not bool(crossing.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Blackthorn lake crossing failed: %s" % crossing.get("reason", ""),
		}

	# Dragon's Den 1F is two halves joined by its own warp pair, (3,3) into
	# (5,13), so the ladder down at (5,15) is only reached through it.
	var to_den: Dictionary = _warp_chain(
		world, save, random, data,
		[Vector2i(20, 1), Vector2i(3, 3), Vector2i(5, 15)]
	)
	if not bool(to_den.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Dragon's Den B1F unreachable: %s" % to_den.get("reason", ""),
		}

	if not Gen2WorldState.is_crystal_profile(data):
		return _dragons_den_dragon_fang(world, save, random, data, path)

	# B1F is a lake with the shrine on its far shore: the ladder's own land
	# region has 271 cells and none of them touch the shrine, whose only landfall
	# from the water is (14,31). The whirlpool on (10,20) sits in the way.
	var entered: Dictionary = _surf_at(
		world, Vector2i(10, 7), Gen2WorldSprite.FACING_DOWN, save, random, data
	)
	if not bool(entered.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Dragon's Den surf entry failed: %s" % entered.get("reason", ""),
		}
	var cleared: Dictionary = _whirlpool_at(
		world, Vector2i(10, 19), Gen2WorldSprite.FACING_DOWN, save, random, data
	)
	path.append({
		"step": "dragons_den_whirlpool",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": cleared,
	})
	if not bool(cleared.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Dragon's Den whirlpool failed: %s" % cleared.get("reason", ""),
		}
	var den_crossing: Dictionary = _walk_cell_resolving(
		world, Vector2i(14, 31), save, random, data, true
	)
	path.append({
		"step": "dragons_den_crossing",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"movement_mode": String(world.movement_mode),
	})
	if not bool(den_crossing.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Dragon's Den crossing failed: %s" % den_crossing.get("reason", ""),
		}

	# _warp_chain, not used here: it drains the destination's own map entry with
	# default answers, and the shrine's map entry is the quiz. One entry, one
	# quiz, driven below by this leg's own answers.
	var to_shrine: Dictionary = _warp_walk(world, Vector2i(19, 29), save, random, data)
	if not bool(to_shrine.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Dragon Shrine unreachable: %s" % to_shrine.get("reason", ""),
		}

	# The shrine's scene 0 is SCENE_DRAGONSHRINE_TAKE_TEST, an sdefer, so the
	# quiz runs off the map entry rather than an interaction.
	var quiz: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data, true,
		DRAGON_SHRINE_ANSWERS
	)
	path.append({
		"step": "dragon_shrine_rising_badge",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": quiz,
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
		"answered_wrong": world.event_flag_active(EVENT_ANSWERED_DRAGON_MASTER_QUIZ_WRONG),
	})
	if not bool(quiz.get("terminal", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Dragon Shrine quiz did not finish: %s" % quiz.get("reason", ""),
		}
	if not world.state.is_engine_flag_active(Gen2WorldState.badge_flag(
		BADGE_RISING, Gen2WorldState.is_crystal_profile(data)
	)):
		return {"ok": false, "path": path, "reason": "the Rising Badge was not given"}
	return {"ok": true}


## Dragon's Den B1F's DRAGON_FANG ball, which is where Gold and Silver keep the
## Rising Badge.
##
## pokegold ships no DRAGON_SHRINE map: `maps/DragonsDenB1F.asm` has one warp
## rather than two and no coord event, and blocks (7..11, 13..15) of its `.blk`
## wall the shrine mouth off, which is the whole difference between the two
## grids. `DragonsDenB1FDragonFangScript` is the errand instead: the ball on
## (35,16) gives the fang, then Clair walks in, runs `setflag ENGINE_RISINGBADGE`
## and hands over TM24 in the same conversation Crystal splits between the elder
## and a later coord event.
##
## The ball's land strip is (34..35, 16..21) and touches no other land, so the
## lake is the only way onto it and (34,22) is its one shore: the water west of
## the strip is a pocket of its own, sealed off by the COLL_BUOY column on
## (30, 16..19), which `data/collision/collision_permissions.asm` gives
## WALL_TILE. The whirlpool on (10,20) is on this route as much as on Crystal's,
## since it is the only cell joining the ladder's own lake to the southern one.
func _dragons_den_dragon_fang(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var entered: Dictionary = _surf_at(
		world, Vector2i(10, 7), Gen2WorldSprite.FACING_DOWN, save, random, data
	)
	if not bool(entered.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Dragon's Den surf entry failed: %s" % entered.get("reason", ""),
		}
	var cleared: Dictionary = _whirlpool_at(
		world, Vector2i(10, 19), Gen2WorldSprite.FACING_DOWN, save, random, data
	)
	path.append({
		"step": "dragons_den_whirlpool",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": cleared,
	})
	if not bool(cleared.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Dragon's Den whirlpool failed: %s" % cleared.get("reason", ""),
		}
	var crossing: Dictionary = _walk_cell_resolving(
		world, Vector2i(34, 21), save, random, data, true
	)
	path.append({
		"step": "dragons_den_crossing",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"movement_mode": String(world.movement_mode),
	})
	if not bool(crossing.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Dragon's Den crossing failed: %s" % crossing.get("reason", ""),
		}

	# Faced from the west, so `readvar VAR_FACING` takes the script's RIGHT
	# branch and Clair walks up the strip from (34,21) rather than (35,22).
	var fang: Dictionary = _talk_to(
		world, Vector2i(34, 16), Gen2WorldSprite.FACING_RIGHT, save, random, data
	)
	path.append({
		"step": "dragons_den_dragon_fang",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": fang.get("run", {}),
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(fang.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Dragon Fang handoff failed: %s" % fang.get("reason", ""),
		}
	if not world.state.is_engine_flag_active(
		Gen2WorldState.badge_flag(BADGE_RISING, false)
	):
		return {"ok": false, "path": path, "reason": "the Rising Badge was not given"}
	return {"ok": true}


## The Dragon Shrine to Indigo Plateau, on the same world, state and save.
##
## `VictoryRoadGate`'s coord event at (10,11) is a `readvar VAR_BADGES` against
## `NUM_JOHTO_BADGES - 1`, so it is the first script on the walked route that
## reads the badge count back, and the eighth badge is what opens the leg.
##
## Route 27 is the reason this leg waited on Waterfall. Its Kanto landfall sits
## in a region that reaches no map edge, and the only crossing of the channel
## east of it starts in a pocket reached solely by leaving Tohjo Falls there.
## The cave in turn is two lower channels that reach the pool feeding them only
## by climbing `COLL_WATERFALL` cells. `tools/checks/route_27.gd` pins all of
## it.
##
## Appends to [param path] and answers only ok or the failure.
func _kanto_approach_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var departure: Dictionary = _blackthorn_departure(world, save, random, data, path)
	if not bool(departure.get("ok", false)):
		return departure

	var kanto: Dictionary = _kanto_approach(world, save, random, data, path)
	if not bool(kanto.get("ok", false)):
		return kanto

	var gate: Dictionary = _victory_road_gate_leg(world, save, random, data, path)
	if not bool(gate.get("ok", false)):
		return gate

	var road: Dictionary = _victory_road_leg(world, save, random, data, path)
	if not bool(road.get("ok", false)):
		return road

	return _elite_four_leg(world, save, random, data, path)


## The Dragon's Den back to New Bark Town.
##
## The way out is the way in reversed. Crystal clears the whirlpool twice:
## `complete_whirlpool()` is a transient block override, so the warp into the
## shrine restored (10,20), and the water south of it reaches the shrine's
## landfall and nothing else. Gold and Silver enter no map in between, so their
## first clear still holds.
##
## Blackthorn's own exit is south, not west: Route 45 into Route 46 into the
## Route 29 gate. Route 46 is walked downhill only. Its ledges leave the region
## around the gate cells reaching no map edge at all, so a route that tried to
## climb it from Route 29 would stop; entered from Route 45's west edge it
## reaches the gate.
func _blackthorn_departure(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var crystal: bool = Gen2WorldState.is_crystal_profile(data)
	if crystal:
		var to_den: Dictionary = _warp_chain(world, save, random, data, [Vector2i(4, 9)])
		if not bool(to_den.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Dragon Shrine exit failed: %s" % to_den.get("reason", ""),
			}

		# The shrine armed SCENE_DRAGONSDENB1F_CLAIR_GIVES_TM
		# (maps/DragonShrine.asm), so B1F's coord event at (19,30), one cell below
		# the warp back, is Clair's TM24 gift. It is on the way out whether or not
		# the walk asks for it. Gold and Silver spent both on the Dragon Fang ball.
		var clair_tm: Dictionary = _walk_cell_resolving(
			world, Vector2i(19, 30), save, random, data
		)
		path.append({
			"step": "dragons_den_clair_tm",
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": clair_tm.get("encounters", []),
			"items": _named_items(data, world.state.items()),
		})
		if not bool(clair_tm.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Clair's TM scene failed: %s" % clair_tm.get("reason", ""),
			}

	var entered: Dictionary = _surf_at(
		world, Vector2i(14, 31) if crystal else Vector2i(34, 21),
		Gen2WorldSprite.FACING_LEFT if crystal else Gen2WorldSprite.FACING_DOWN,
		save, random, data
	)
	if not bool(entered.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Dragon's Den return surf failed: %s" % entered.get("reason", ""),
		}

	# The Rising Badge is in, so WATERFALL is usable from here on, and this is
	# the water it can be learned on: Dragon's Den B1F's own table is the only
	# one the walked route surfs that carries a species which learns it
	# (`data/wild/johto_water.asm` DRATINI, against MAGIKARP in the other two
	# slots). None of the party can.
	var dratini: Dictionary = _catch_field_move_mon(
		world, save, random, data, path,
		Gen2WorldFieldMove.MOVE_WATERFALL, "dragons_den_catch_for_waterfall"
	)
	if not bool(dratini.get("ok", false)):
		return dratini
	var taught: Dictionary = _teach_tm_hm(world, save, ITEM_HM_WATERFALL)
	_mirror_party(world, save)
	path.append({
		"step": "dragons_den_teach_waterfall",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"party": _party_species(save),
		"moves": _party_moves(save),
	})
	if not bool(taught.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "WATERFALL could not be taught: %s" % taught.get("reason", ""),
		}

	if crystal:
		var cleared: Dictionary = _whirlpool_at(
			world, Vector2i(10, 21), Gen2WorldSprite.FACING_UP, save, random, data
		)
		path.append({
			"step": "dragons_den_whirlpool_return",
			"map": _map_value(world),
			"cell": _cell_value(world),
			"run": cleared,
		})
		if not bool(cleared.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "Dragon's Den return whirlpool failed: %s" % cleared.get("reason", ""),
			}
	var back_ashore: Dictionary = _walk_cell_resolving(
		world, Vector2i(10, 7), save, random, data, true
	)
	path.append({
		"step": "dragons_den_return_crossing",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"movement_mode": String(world.movement_mode),
	})
	if not bool(back_ashore.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Dragon's Den return crossing failed: %s" % back_ashore.get("reason", ""),
		}

	var to_town: Dictionary = _warp_chain(
		world, save, random, data, [Vector2i(20, 3), Vector2i(5, 13), Vector2i(3, 5)]
	)
	if not bool(to_town.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Dragon's Den exit failed: %s" % to_town.get("reason", ""),
		}

	# The den door's shore is still an island: the town's $b2 fence line and its
	# one-way $a3 ledges wall off every land route, so the lake is crossed back
	# the way it was crossed in.
	var crossing: Dictionary = _lake_crossing(
		world, save, random, data,
		Vector2i(20, 3), Gen2WorldSprite.FACING_DOWN, Vector2i(22, 12)
	)
	path.append({
		"step": "blackthorn_lake_crossing_return",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"movement_mode": String(world.movement_mode),
	})
	if not bool(crossing.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Blackthorn return crossing failed: %s" % crossing.get("reason", ""),
		}

	for leg: Dictionary in [
		{"step": "blackthorn_to_route_45", "direction": "south", "group": 5, "number": 8},
		{"step": "route_45_to_route_46", "direction": "west", "group": 5, "number": 9},
	]:
		var walked: Dictionary = _walk_connection_resolving(
			world, String(leg["direction"]), int(leg["group"]), int(leg["number"]),
			save, random, data
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": String(leg["step"]),
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s failed: %s" % [leg["step"], walked.get("reason", "")],
			}

	# Route 46's south connection to Route 29 exists in the map attributes but
	# the gate building stands on it: Route 29's north edge is unreachable from
	# inside the map, and its (27,1) is the gate's own warp.
	var gate: Dictionary = _gate_leg(world, save, random, data, Vector2i(7, 33), 24, 3)
	path.append({
		"step": "route_46_to_route_29_gate",
		"map": _map_value(world),
		"cell": _cell_value(world),
	})
	if not bool(gate.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 29 gate failed: %s" % gate.get("reason", ""),
		}

	var to_new_bark: Dictionary = _walk_connection_resolving(
		world, "east", 24, 4, save, random, data
	)
	var new_bark_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_29_to_new_bark_town",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": to_new_bark.get("encounters", []),
		"run": new_bark_entry,
	})
	if not bool(to_new_bark.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 29 to New Bark failed: %s" % to_new_bark.get("reason", ""),
		}
	return {"ok": true}


## New Bark Town to Route 26, along Route 27 and through Tohjo Falls.
##
## New Bark's east column is wall except the four water rows 6 to 9, so leaving
## town east is a crossing rather than a step. The far side is still water, so
## one water-only walk comes ashore on ROUTE_27_LANDFALL, one of the two
## `SCENE_ROUTE27_FIRST_STEP_INTO_KANTO` coord cells, and the scene runs on
## arrival.
##
## From there the way east is the cave, twice over. Row 5 of Route 27 is solid
## cliff apart from Tohjo Falls' two mouths, and both are `COLL_CAVE`, whose
## `.CheckTile` `.warps` branch forces a step DOWN: a player leaving either
## mouth always ends south of it. So the west mouth is entered from the
## landfall's region, the cave is crossed, and the east mouth drops the player
## into the pocket whose own shore is the channel across to Route 26's edge.
func _kanto_approach(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var entered: Dictionary = _surf_at(
		world, Vector2i(17, 8), Gen2WorldSprite.FACING_RIGHT, save, random, data
	)
	if not bool(entered.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "New Bark surf entry failed: %s" % entered.get("reason", ""),
		}
	var crossed: Dictionary = _walk_connection_resolving(
		world, "east", 24, 2, save, random, data, true
	)
	var entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var ashore: Dictionary = {}
	if bool(crossed.get("ok", false)):
		ashore = _walk_cell_resolving(world, ROUTE_27_LANDFALL, save, random, data, true)
	path.append({
		"step": "new_bark_town_to_route_27",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"movement_mode": String(world.movement_mode),
		"encounters": crossed.get("encounters", []),
		"landfall_encounters": ashore.get("encounters", []),
		"run": entry,
	})
	if not bool(crossed.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "New Bark to Route 27 failed: %s" % crossed.get("reason", ""),
		}
	if not bool(ashore.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 27 landfall failed: %s" % ashore.get("reason", ""),
		}

	var cave: Dictionary = _tohjo_falls_leg(world, save, random, data, path)
	if not bool(cave.get("ok", false)):
		return cave

	# The east mouth's forced step already put the player in the pocket. Row 4's
	# eastern strip is walled off from the rest of Route 27, so (46,4) is the
	# landfall and rows 10 and 11 are the only land cells on the Route 26 edge a
	# walk can leave by.
	var channel: Dictionary = _surf_at(
		world, Vector2i(39, 6), Gen2WorldSprite.FACING_RIGHT, save, random, data
	)
	if not bool(channel.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 27 channel surf failed: %s" % channel.get("reason", ""),
		}
	var landed: Dictionary = _walk_cell_resolving(
		world, Vector2i(46, 4), save, random, data, true
	)
	if not bool(landed.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 27 channel landfall failed: %s" % landed.get("reason", ""),
		}
	var to_route_26: Dictionary = _walk_connection_resolving(
		world, "east", 24, 1, save, random, data
	)
	var route_26_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_27_to_route_26",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"movement_mode": String(world.movement_mode),
		"encounters": to_route_26.get("encounters", []),
		"run": route_26_entry,
	})
	if not bool(to_route_26.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 27 to Route 26 failed: %s" % to_route_26.get("reason", ""),
		}
	return {"ok": true}


## Tohjo Falls, west mouth to east mouth, which is one Waterfall climb and one
## ride back down.
##
## The cave is three water bodies joined only by its waterfalls. From the west
## door's landing the surf runs west and north to the foot of the x 8 to 11
## column; the climb ends on the pool above it, still on water. The east
## waterfall is then ridden down rather than climbed: stepping onto its top cell
## leaves the player standing on a `COLL_WATERFALL`, and `.CheckTile` takes over
## from there, which is `advance_forced_movement()` here.
func _tohjo_falls_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var into_cave: Dictionary = _warp_chain(world, save, random, data, [TOHJO_WEST_MOUTH])
	if not bool(into_cave.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Tohjo Falls entrance failed: %s" % into_cave.get("reason", ""),
		}

	var entered: Dictionary = _surf_at(
		world, TOHJO_WEST_SHORE, Gen2WorldSprite.FACING_LEFT, save, random, data
	)
	if not bool(entered.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Tohjo Falls surf entry failed: %s" % entered.get("reason", ""),
		}
	var climbed: Dictionary = _waterfall_at(
		world, TOHJO_CLIMB_FOOT, save, random, data
	)
	path.append({
		"step": "tohjo_falls_climb",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": climbed,
		"movement_mode": String(world.movement_mode),
	})
	if not bool(climbed.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Tohjo Falls climb failed: %s" % climbed.get("reason", ""),
		}

	var descent: Dictionary = _ride_waterfall_down(
		world, save, random, data, TOHJO_DESCENT_TOP
	)
	path.append({
		"step": "tohjo_falls_descent",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"steps": descent.get("steps", 0),
	})
	if not bool(descent.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Tohjo Falls descent failed: %s" % descent.get("reason", ""),
		}

	var ashore: Dictionary = _walk_cell_resolving(
		world, TOHJO_EAST_LANDFALL, save, random, data, true
	)
	if not bool(ashore.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Tohjo Falls landfall failed: %s" % ashore.get("reason", ""),
		}
	var out_of_cave: Dictionary = _warp_chain(world, save, random, data, [TOHJO_EAST_DOOR])
	path.append({
		"step": "tohjo_falls_east_mouth",
		"map": _map_value(world),
		"cell": _cell_value(world),
	})
	if not bool(out_of_cave.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Tohjo Falls exit failed: %s" % out_of_cave.get("reason", ""),
		}
	return {"ok": true}


## Climbs the waterfall the given water cell faces, the way _cut_at() cuts:
## request then commit, since Script_UsedWaterfall reaches its first step only
## after _UseWaterfallText's waitbutton. The whole column is one commit.
func _waterfall_at(
	world: Gen2WorldAPI,
	approach: Vector2i,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, approach, save, random, data, true)
	if not bool(walked.get("ok", false)):
		return walked
	world.player_facing = Gen2WorldSprite.FACING_UP
	var request: Dictionary = world.waterfall_request()
	if not bool(request.get("ok", false)):
		return {"ok": false, "reason": "waterfall refused: %s" % request.get("reason", "")}
	var applied: Dictionary = world.complete_waterfall()
	if not bool(applied.get("ok", false)):
		return {"ok": false, "reason": "waterfall failed: %s" % applied.get("reason", "")}
	return applied


## Steps onto a waterfall's top cell and lets `.CheckTile` carry the player down
## it. Going down needs no move and no badge: the tile does it, which is why the
## project has had the layer since the forced-tile work and only the climb was
## missing.
func _ride_waterfall_down(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	top: Vector2i,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, top, save, random, data, true)
	if not bool(walked.get("ok", false)):
		return walked
	var stepped: Dictionary = world.move_result(Vector2i.DOWN)
	if not bool(stepped.get("ok", false)):
		return {"ok": false, "reason": "the descent's first step refused"}
	var steps: int = 1
	for _frame: int in WATERFALL_RIDE_LIMIT:
		var forced: Dictionary = world.advance_forced_movement()
		if forced.is_empty():
			return {"ok": true, "steps": steps}
		if not bool(forced.get("ok", false)):
			return {"ok": false, "reason": "forced step refused", "steps": steps}
		steps += 1
	return {"ok": false, "reason": "the descent did not settle", "steps": steps}


## Route 26's heal house and the Victory Road Gate badge check.
##
## The gate is not walked with _gate_leg(): that helper reaches the far warp
## with _warp_step(), which assigns the cell rather than walking to it, and the
## badge check is a coord event at (10,11) that only a real walk can meet.
func _victory_road_gate_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	_mirror_party(world, save)

	# Route26HealHouseTeacherScript is an unconditional HealParty, the one heal
	# on this leg that is not a Pokemon Center nurse.
	for mon: Gen2SaveMon in save.party:
		mon.hp = 1
	var into_house: Dictionary = _warp_chain(world, save, random, data, [Vector2i(15, 57)])
	if not bool(into_house.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 26 heal house entrance failed: %s" % into_house.get("reason", ""),
		}
	var healed: Dictionary = _talk_to(
		world, Vector2i(2, 4), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "route_26_heal_house",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": healed.get("run", {}),
		"party_hp_after": _party_hp(save),
	})
	if not bool(healed.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 26 heal house failed: %s" % healed.get("reason", ""),
		}
	var out_of_house: Dictionary = _warp_chain(world, save, random, data, [Vector2i(2, 7)])
	if not bool(out_of_house.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 26 heal house exit failed: %s" % out_of_house.get("reason", ""),
		}

	var into_gate: Dictionary = _warp_chain(world, save, random, data, [Vector2i(7, 5)])
	if not bool(into_gate.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Victory Road Gate entrance failed: %s" % into_gate.get("reason", ""),
		}
	var checked: Dictionary = _walk_cell_resolving(
		world, Vector2i(10, 11), save, random, data
	)
	path.append({
		"step": "victory_road_gate_badge_check",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
		"encounters": checked.get("encounters", []),
	})
	if not bool(checked.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Victory Road Gate badge check failed: %s" % checked.get("reason", ""),
		}
	# The officer's refusal branch is an applymovement that steps the player back
	# down, so staying on (10,11) is what says the eighth badge was accepted.
	if world.player_cell != Vector2i(10, 11):
		return {
			"ok": false, "path": path,
			"reason": "the gate turned the player back at %s" % world.player_cell,
		}
	return {"ok": true}


## Victory Road and Route 23 to the Indigo Plateau Pokemon Center.
##
## Victory Road is a warp maze, not one floor: the gate's entrance region
## reaches only the ladder at (1,49), whose pair lands on (1,35) in a second
## region, whose ladder at (13,31) lands on (13,17) in the third. Only that
## third region holds the rival's coord event and the exit to Route 23.
func _victory_road_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var into_road: Dictionary = _warp_chain(world, save, random, data, [Vector2i(9, 0)])
	if not bool(into_road.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Victory Road entrance failed: %s" % into_road.get("reason", ""),
		}

	for ladder: Dictionary in VICTORY_ROAD_LADDERS:
		var climbed: Dictionary = _warp_chain(world, save, random, data, [ladder["cell"]])
		path.append({
			"step": String(ladder["step"]),
			"map": _map_value(world),
			"cell": _cell_value(world),
		})
		if not bool(climbed.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s failed: %s" % [ladder["step"], climbed.get("reason", "")],
			}

	# The rival's own cell, walked rather than left to the path to the exit: the
	# coord event pair is (12,8) and (13,8), and a walk that happened to route
	# around both would skip the battle without saying so.
	var rival: Dictionary = _walk_cell_resolving(world, Vector2i(13, 8), save, random, data)
	path.append({
		"step": "victory_road_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": rival.get("encounters", []),
		"beat_rival": world.event_flag_active(EVENT_RIVAL_VICTORY_ROAD),
	})
	if not bool(rival.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Victory Road rival failed: %s" % rival.get("reason", ""),
		}
	if not world.event_flag_active(EVENT_RIVAL_VICTORY_ROAD):
		return {"ok": false, "path": path, "reason": "the Victory Road rival did not appear"}

	var to_plateau: Dictionary = _warp_chain(
		world, save, random, data, [Vector2i(13, 5), Vector2i(9, 5)]
	)
	if not bool(to_plateau.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Indigo Plateau unreachable: %s" % to_plateau.get("reason", ""),
		}

	# PlateauRivalBattle1 and 2 open on EVENT_BEAT_RIVAL_IN_MT_MOON, which this
	# route never reaches, so the coord event runs to PlateauRivalScriptDone and
	# no second rival battle happens here.
	#
	# That branch ends without a `setscene`, so the coord event stays armed and
	# answers again every time the player stands on it. The cell is stepped onto
	# once rather than walked to, because a resolving walk would re-dispatch it
	# until it ran out of attempts.
	var approach: Dictionary = _walk_cell_resolving(
		world, PLATEAU_RIVAL_APPROACH, save, random, data
	)
	if not bool(approach.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Indigo Plateau approach failed: %s" % approach.get("reason", ""),
		}
	var stepped: Dictionary = world.move_result(Vector2i.UP)
	var plateau: Dictionary = {"ok": bool(stepped.get("ok", false))}
	if bool(plateau.get("ok", false)):
		var fired: Array = _dispatch_after_step(world)
		var run: Dictionary = _drain_story(world, fired, save, random, data, true)
		plateau = {
			"ok": bool(run.get("terminal", false)),
			"reason": run.get("reason", ""),
			"encounters": [{"cell": _cell_value(world), "statuses": run.get("statuses", []),
				"battles": run.get("battles", [])}],
		}
	path.append({
		"step": "indigo_plateau_pokecenter",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": plateau.get("encounters", []),
		"mt_moon_rival": world.event_flag_active(EVENT_BEAT_RIVAL_IN_MT_MOON),
		"flypoint": _engine_flag_set(world, data, ENGINE_FLYPOINT_INDIGO_PLATEAU),
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
	})
	if not bool(plateau.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Indigo Plateau Pokemon Center failed: %s" % plateau.get("reason", ""),
		}
	if not _engine_flag_set(world, data, ENGINE_FLYPOINT_INDIGO_PLATEAU):
		return {"ok": false, "path": path, "reason": "the Indigo Plateau flypoint was not set"}
	return {"ok": true}


## The Indigo Plateau Pokemon Center to the Hall of Fame.
##
## The five rooms are one corridor with a door between each pair, and no heal
## anywhere in it. `_drain_story()` answers every battle with a win, so what
## this walks is the doors, the scenes and the flags, not five fights a party
## survived.
##
## `IndigoPlateauPokecenter1FPrepareElite4Callback` has already run on the
## Pokemon Center's own map entry: it sets all six scenes and clears the twelve
## room flags, so each room arrives on its `_LOCK_DOOR` scene.
func _elite_four_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var entered: Dictionary = _warp_chain(
		world, save, random, data, [INDIGO_PLATEAU_ELITE_FOUR_DOOR]
	)
	if not bool(entered.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Elite Four door failed: %s" % entered.get("reason", ""),
		}

	for room: Dictionary in ELITE_FOUR_ROOMS:
		var settled: Vector2i = ELITE_FOUR_ROOM_ARRIVAL \
			+ Vector2i(0, -ELITE_FOUR_ENTER_STEPS)
		if world.player_cell != settled:
			return {
				"ok": false, "path": path,
				"reason": "%s left the player on %s, not %s" % [
					room["step"], world.player_cell, settled,
				],
			}
		if not world.event_flag_active(int(room["entrance"])):
			return {
				"ok": false, "path": path,
				"reason": "%s did not lock its entrance" % room["step"],
			}

		var boss: Dictionary = _talk_to(
			world, ELITE_FOUR_ROOM_BOSS_FACE, Gen2WorldSprite.FACING_UP,
			save, random, data
		)
		path.append({
			"step": room["step"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"entrance_closed": world.event_flag_active(int(room["entrance"])),
			"beaten": world.event_flag_active(int(room["beat"])),
			"exit_open": world.event_flag_active(int(room["exit"])),
			"battles": boss.get("run", {}).get("battles", []),
		})
		if not bool(boss.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s failed: %s" % [room["step"], boss.get("reason", "")],
			}
		if not world.event_flag_active(int(room["beat"])):
			return {"ok": false, "path": path, "reason": "%s was not beaten" % room["step"]}
		if not world.event_flag_active(int(room["exit"])):
			return {"ok": false, "path": path, "reason": "%s did not open its exit" % room["step"]}

		var onward: Dictionary = _warp_chain(
			world, save, random, data, [ELITE_FOUR_ROOM_EXIT]
		)
		if not bool(onward.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the door out of %s failed: %s" % [
					room["step"], onward.get("reason", ""),
				],
			}

	var lance: Dictionary = _lances_room_leg(world, save, random, data, path)
	if not bool(lance.get("ok", false)):
		return lance
	return _hall_of_fame_leg(
		world, save, random, data, path, int(lance.get("hall_of_fame", 0))
	)


## Lance's room. Nothing here is talked to: `LancesRoomDoorLocksBehindYouScript`
## sets SCENE_LANCESROOM_APPROACH_LANCE, which arms the coord events on (4,5)
## and (5,5), and stepping onto one runs the approach, the battle and the whole
## champion scene through to `warpfacing UP, HALL_OF_FAME, 4, 13`.
##
## The cell is stepped onto rather than walked to, the way the Plateau rival
## coord event is: a resolving walk would re-dispatch it until it ran out of
## attempts.
func _lances_room_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var settled: Vector2i = LANCES_ROOM_ARRIVAL + Vector2i(0, -ELITE_FOUR_ENTER_STEPS)
	if world.map_id() != Vector2i(16, LANCES_ROOM_NUMBER) or world.player_cell != settled:
		return {
			"ok": false, "path": path,
			"reason": "Lance's room started on %s %s, not 16/%d %s" % [
				_map_value(world), world.player_cell, LANCES_ROOM_NUMBER, settled,
			],
		}
	if not world.event_flag_active(EVENT_LANCES_ROOM_ENTRANCE_CLOSED):
		return {"ok": false, "path": path, "reason": "Lance's room did not lock its entrance"}

	var approach: Dictionary = _walk_cell_resolving(
		world, LANCE_APPROACH, save, random, data
	)
	if not bool(approach.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk to Lance failed: %s" % approach.get("reason", ""),
		}
	var stepped: Dictionary = world.move_result(Vector2i.UP)
	var champion: Dictionary = {"ok": false, "reason": "the step onto the coord event refused"}
	if bool(stepped.get("ok", false)):
		champion = _drain_story(
			world, _dispatch_after_step(world), save, random, data, true
		)
		champion["ok"] = bool(champion.get("terminal", false))
	path.append({
		"step": "lances_room",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"beat_lance": world.event_flag_active(EVENT_BEAT_CHAMPION_LANCE),
		"battles": champion.get("battles", []),
	})
	if not bool(champion.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the champion scene failed: %s" % champion.get("reason", ""),
		}
	if not world.event_flag_active(EVENT_BEAT_CHAMPION_LANCE):
		return {"ok": false, "path": path, "reason": "Lance was not beaten"}
	if world.map_id() != Vector2i(16, HALL_OF_FAME_NUMBER):
		return {
			"ok": false, "path": path,
			"reason": "the champion scene ended on %s, not the Hall of Fame" % [
				_map_value(world),
			],
		}
	return {"ok": true, "hall_of_fame": int(champion.get("hall_of_fame", 0))}


## The Hall of Fame. `warpfacing` lands here mid-script, and a map scene queued
## by a warp is picked up by the same run_event_queue() loop that took the warp,
## so SCENE_HALLOFFAME_ENTER usually runs inside the champion drain and this
## step's own dispatch finds nothing left. [param carried] is that drain's count
## of the one event this leg exists to reach.
##
## `halloffame` is a presentation boundary: it commits ENGINE_HALL_OF_FAME and
## emits `hall_of_fame_requested`, which no screen answers yet.
func _hall_of_fame_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
	carried: int,
) -> Dictionary:
	var run: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var presentations: int = carried + int(run.get("hall_of_fame", 0))
	path.append({
		"step": "hall_of_fame",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"beat_elite_four": world.event_flag_active(EVENT_BEAT_ELITE_FOUR),
		"teleport_guy": world.event_flag_active(EVENT_TELEPORT_GUY),
		"red_in_mt_silver": world.event_flag_active(EVENT_RED_IN_MT_SILVER),
		"hall_of_fame_events": presentations,
		"hall_of_fame_flag": world.state.hall_of_fame(),
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
	})
	if not bool(run.get("terminal", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Hall of Fame scene failed: %s" % run.get("reason", ""),
		}
	for flag: int in [EVENT_BEAT_ELITE_FOUR, EVENT_TELEPORT_GUY, EVENT_RIVAL_SPROUT_TOWER]:
		if not world.event_flag_active(flag):
			return {
				"ok": false, "path": path,
				"reason": "the Hall of Fame did not set event flag %d" % flag,
			}
	if world.event_flag_active(EVENT_RED_IN_MT_SILVER):
		return {
			"ok": false, "path": path,
			"reason": "the Hall of Fame did not clear EVENT_RED_IN_MT_SILVER",
		}
	if presentations != 1:
		return {
			"ok": false, "path": path,
			"reason": "halloffame emitted %d presentation events, not one" % presentations,
		}
	if not world.state.hall_of_fame():
		return {"ok": false, "path": path, "reason": "ENGINE_HALL_OF_FAME was not set"}
	return {"ok": true}


## The Hall of Fame to Kanto: the post-credits spawn, Elm's S.S. Ticket, the
## walk back to Olivine, the S.S. Aqua and landfall in Vermilion City.
##
## This leg starts on a new world. `SpawnAfterE4` (`engine/menus/intro_menu.asm`)
## answers the next Continue with SPAWN_NEW_BARK and MAPSETUP_WARP, so the
## cartridge does not walk out of the Hall of Fame either; it reloads the map.
## The state and the save carry over, which is what makes the flags the Hall of
## Fame just set visible to Elm.
##
## Returns the world it built, since everything after it runs there.
func _kanto_crossing_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var spawned: Gen2WorldAPI = Gen2WorldAPI.open(
		data, NEW_BARK_GROUP, NEW_BARK_NUMBER, POST_CREDITS_SPAWN, world.state
	)
	if spawned == null:
		return {"ok": false, "path": path, "reason": "the post-credits spawn map is missing"}
	spawned.schedule_random = world.schedule_random
	_mirror_party(spawned, save)
	var entry: Dictionary = _drain_story(
		spawned, spawned.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "post_credits_spawn",
		"map": _map_value(spawned),
		"cell": _cell_value(spawned),
		"hall_of_fame": spawned.state.hall_of_fame(),
	})
	if not bool(entry.get("terminal", false)):
		return {
			"ok": false, "path": path,
			"reason": "the New Bark respawn did not settle: %s" % entry.get("reason", ""),
		}

	var ticket: Dictionary = _elm_ss_ticket(spawned, save, random, data, path)
	if not bool(ticket.get("ok", false)):
		return ticket

	var westward: Dictionary = _walk_west_to_olivine(spawned, save, random, data, path)
	if not bool(westward.get("ok", false)):
		return westward

	var crossing: Dictionary = _ss_aqua_crossing(spawned, save, random, data, path)
	if not bool(crossing.get("ok", false)):
		return crossing

	var thunder: Dictionary = _thunder_badge_path(spawned, save, random, data, path)
	if not bool(thunder.get("ok", false)):
		return thunder

	var marsh: Dictionary = _marsh_badge_path(spawned, save, random, data, path)
	if not bool(marsh.get("ok", false)):
		return marsh

	var rainbow: Dictionary = _rainbow_badge_path(spawned, save, random, data, path)
	if not bool(rainbow.get("ok", false)):
		return rainbow

	var cerulean: Dictionary = _cerulean_approach_path(spawned, save, random, data, path)
	if not bool(cerulean.get("ok", false)):
		return cerulean
	return {"ok": true, "world": spawned}


## Olivine Port to Vermilion City on the S.S. Aqua.
##
## The Hall of Fame is what opens this: `HallOfFameEnterScript` sets
## EVENT_OLIVINE_PORT_SPRITES_BEFORE_HALL_OF_FAME and clears the `AFTER` one, and
## the sailor those flags swap is the one standing on the port's own coord event
## at (7,15). Before the Hall of Fame he blocks it.
##
## The first crossing is the granddaughter's: `.CanArrive` in
## `maps/FastShipCabins_SW_SSW_NW.asm` wants EVENT_FAST_SHIP_FOUND_GIRL or
## EVENT_FAST_SHIP_FIRST_TIME, and neither is set on the way out, so the ship
## only docks once `SSAquaMetalCoatAndDocking` has run. The bed is not needed;
## that script sets both the arrival and the found-girl flags itself.
func _ss_aqua_crossing(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var to_port: Dictionary = _warp_chain(
		world, save, random, data,
		[OLIVINE_PORT_DOOR, OLIVINE_PASSAGE_STAIRS, OLIVINE_PASSAGE_EXIT]
	)
	if not bool(to_port.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Olivine Port unreachable: %s" % to_port.get("reason", ""),
		}

	# The coord event is stepped onto rather than walked to: a resolving walk
	# would re-dispatch it, and the boarding it starts answers a yes/no.
	var approach: Dictionary = _walk_cell_resolving(
		world, PORT_BOARDING_APPROACH, save, random, data
	)
	if not bool(approach.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the gangway approach failed: %s" % approach.get("reason", ""),
		}
	var stepped: Dictionary = world.move_result(Vector2i.DOWN)
	var boarded: Dictionary = {"ok": false, "reason": "the step onto the gangway refused"}
	if bool(stepped.get("ok", false)):
		# OlivinePortWalkUpToShipScript's yesorno, then OlivinePortAskTicketText's
		# promptbutton and the checkitem that reads the ticket out of the bag.
		boarded = _drain_story(
			world, _dispatch_after_step(world), save, random, data, true, [0] as Array[int]
		)
		boarded["ok"] = bool(boarded.get("terminal", false))
	path.append({
		"step": "olivine_port_boarding",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": boarded,
	})
	if not bool(boarded.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "boarding the S.S. Aqua failed: %s" % boarded.get("reason", ""),
		}
	if world.map_id() != Vector2i(FAST_SHIP_GROUP, FAST_SHIP_1F_NUMBER):
		return {
			"ok": false, "path": path,
			"reason": "boarding ended on %s, not the ship" % [_map_value(world)],
		}

	return _ss_aqua_worried_grandpa(world, save, random, data, path)


## New Bark Town back to Olivine City, the way the route first walked it, in
## reverse where it overlaps and forward where it does not.
##
## Two of the joins are gate buildings rather than map connections: Route 31's
## west edge is wall on every row, so `Route31VioletGate` is the only way into
## Violet City, and Ecruteak's west exit is `Route38EcruteakGate`.
func _walk_west_to_olivine(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var out_of_lab: Dictionary = _warp_chain(world, save, random, data, [ELMS_LAB_DOOR])
	if not bool(out_of_lab.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving Elm's lab failed: %s" % out_of_lab.get("reason", ""),
		}

	for stage: Dictionary in KANTO_RETURN_LEGS:
		var walked: Dictionary
		if stage.has("gate"):
			walked = _gate_leg(
				world, save, random, data, stage["gate"],
				int(stage["group"]), int(stage["number"])
			)
		else:
			walked = _walk_connection_resolving(
				world, String(stage["direction"]), int(stage["group"]),
				int(stage["number"]), save, random, data
			)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": String(stage["step"]),
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s failed: %s" % [stage["step"], walked.get("reason", "")],
			}
		if not bool(entry.get("terminal", false)):
			return {"ok": false, "path": path, "reason": "%s entry did not finish" % stage["step"]}
	return {"ok": true}


## Elm's lab, for the ticket he only offers once the Elite Four is beaten.
##
## `ProfElmScript` reads `EVENT_BEAT_ELITE_FOUR` before anything else it could
## give, so this is the first thing he answers with now
## (`maps/ElmsLab.asm`'s ElmGiveTicketScript).
func _elm_ss_ticket(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var into_lab: Dictionary = _warp_chain(
		world, save, random, data, [NEW_BARK_ELMS_LAB_DOOR]
	)
	if not bool(into_lab.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Elm's lab door failed: %s" % into_lab.get("reason", ""),
		}
	var talked: Dictionary = _talk_to(
		world, ELM_FACE_CELL, Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "elms_lab_ss_ticket",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"ticket": world.event_flag_active(EVENT_GOT_SS_TICKET_FROM_ELM),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(talked.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Elm did not finish: %s" % talked.get("reason", ""),
		}
	if not world.event_flag_active(EVENT_GOT_SS_TICKET_FROM_ELM):
		return {"ok": false, "path": path, "reason": "Elm did not hand over the S.S. Ticket"}
	return {"ok": true}


## The worried grandpa on 1F, which is where the walked route stops.
##
## `WorriedGrandpaSceneLeft` is a coord event on the pair below the ship's
## entrance and it retires itself with `setscene SCENE_FASTSHIP1F_NOOP`, so it is
## stepped onto once rather than walked to.
func _ss_aqua_worried_grandpa(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var approach: Dictionary = _walk_cell_resolving(
		world, SHIP_GRANDPA_APPROACH, save, random, data
	)
	if not bool(approach.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk to the grandpa scene failed: %s" % approach.get("reason", ""),
		}
	var stepped: Dictionary = world.move_result(Vector2i.DOWN)
	var scene: Dictionary = {"ok": false, "reason": "the step onto the grandpa cell refused"}
	if bool(stepped.get("ok", false)):
		scene = _drain_story(world, _dispatch_after_step(world), save, random, data, true)
		scene["ok"] = bool(scene.get("terminal", false))
	path.append({
		"step": "ss_aqua_worried_grandpa",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"first_time": world.event_flag_active(EVENT_FAST_SHIP_FIRST_TIME),
	})
	if not bool(scene.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the grandpa scene failed: %s" % scene.get("reason", ""),
		}
	return _ss_aqua_interior(world, save, random, data, path)


## The crossing itself: the B1F sailors, the errand that stands them down, the
## west wing they were sealing off, and the gangway at Vermilion.
func _ss_aqua_interior(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var informed: Dictionary = _ss_aqua_b1f_sailor(world, save, random, data, path)
	if not bool(informed.get("ok", false)):
		return informed
	var found: Dictionary = _ss_aqua_lazy_sailor(world, save, random, data, path)
	if not bool(found.get("ok", false)):
		return found
	var docked: Dictionary = _ss_aqua_granddaughter(world, save, random, data, path)
	if not bool(docked.get("ok", false)):
		return docked
	return _ss_aqua_disembark(world, save, random, data, path)


## B1F's on-duty sailor, who is the only thing that reveals the lazy one.
##
## `FastShipB1FSailorScript` reaches its `clearevent
## EVENT_FAST_SHIP_CABINS_NNW_NNE_NE_SAILOR` only with FIRST_TIME, LAZY_SAILOR
## and INFORMED all clear, which is exactly the outbound first trip. Stepping
## onto the coord event first is not optional: `FastShipB1FSailorBlocksRight`
## moves the visible sailor onto the player's own column, so the sailor being
## talked to is on (31,6) whichever one started there.
func _ss_aqua_b1f_sailor(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var below: Dictionary = _warp_chain(world, save, random, data, [SHIP_1F_TO_B1F_EAST])
	if not bool(below.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the stairs down to B1F failed: %s" % below.get("reason", ""),
		}
	if world.map_id() != Vector2i(FAST_SHIP_GROUP, FAST_SHIP_B1F_NUMBER):
		return {"ok": false, "path": path, "reason": "the stairs ended on %s" % [_map_value(world)]}

	var approach: Dictionary = _walk_cell_resolving(
		world, SHIP_B1F_SAILOR_APPROACH, save, random, data
	)
	if not bool(approach.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk up B1F's east corridor failed: %s" % approach.get("reason", ""),
		}
	var stepped: Dictionary = world.move_result(Vector2i.UP)
	var blocked: Dictionary = {"ok": false, "reason": "the step onto the coord event refused"}
	if bool(stepped.get("ok", false)):
		blocked = _drain_story(world, _dispatch_after_step(world), save, random, data, true)
		blocked["ok"] = bool(blocked.get("terminal", false))
	if not bool(blocked.get("ok", false)):
		path.append({"step": "ss_aqua_b1f_sailor_blocks", "run": blocked})
		return {
			"ok": false, "path": path,
			"reason": "the sailor block scene failed: %s" % blocked.get("reason", ""),
		}

	# Interacted in place rather than through _talk_to(): its walk would aim at
	# the coord event cell the player is already standing on and re-dispatch it
	# until it ran out of attempts.
	world.player_facing = Gen2WorldSprite.FACING_UP
	var run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	var talked: Dictionary = {
		"ok": bool(run.get("terminal", false)), "reason": run.get("reason", ""), "run": run,
	}
	path.append({
		"step": "ss_aqua_b1f_sailor",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"informed": world.event_flag_active(EVENT_FAST_SHIP_INFORMED_ABOUT_LAZY_SAILOR),
		"lazy_sailor_visible": not world.event_flag_active(EVENT_FAST_SHIP_NE_CABIN_SAILOR),
	})
	if not bool(talked.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the on-duty sailor did not finish: %s" % talked.get("reason", ""),
		}
	if world.event_flag_active(EVENT_FAST_SHIP_NE_CABIN_SAILOR):
		return {"ok": false, "path": path, "reason": "the lazy sailor is still hidden"}
	return {"ok": true}


## The lazy sailor in the NE cabin, whose own script stands the B1F pair down.
##
## `FastShipLazySailorScript` is a trainer battle inside an OBJECTTYPE_SCRIPT
## object, and its tail is what matters here: `setevent
## EVENT_FAST_SHIP_LAZY_SAILOR` and `setmapscene FAST_SHIP_B1F,
## SCENE_FASTSHIPB1F_NOOP`, which retires both coord events for good.
func _ss_aqua_lazy_sailor(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var to_cabin: Dictionary = _warp_chain(
		world, save, random, data, [SHIP_B1F_TO_1F_EAST, SHIP_1F_TO_NE_CABIN]
	)
	if not bool(to_cabin.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the NE cabin door failed: %s" % to_cabin.get("reason", ""),
		}
	var talked: Dictionary = _talk_to(
		world, SHIP_LAZY_SAILOR_FACE, Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "ss_aqua_lazy_sailor",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"lazy_sailor": world.event_flag_active(EVENT_FAST_SHIP_LAZY_SAILOR),
		"b1f_scene": world.state.map_scene(FAST_SHIP_GROUP, FAST_SHIP_B1F_NUMBER),
		"run": talked,
	})
	if not bool(talked.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the lazy sailor did not finish: %s" % talked.get("reason", ""),
		}
	if world.state.map_scene(FAST_SHIP_GROUP, FAST_SHIP_B1F_NUMBER) != SCENE_FASTSHIPB1F_NOOP:
		return {"ok": false, "path": path, "reason": "B1F's sailor-block scene did not retire"}
	return {"ok": true}


## West past the stood-down sailors to the captain's cabin, and the docking the
## granddaughter's scene runs.
##
## With the scene retired the coord events are inert, so the sailor left standing
## on (31,6) leaves (30,6) open and B1F's west stairs are reachable. The
## granddaughter's own scene is the way back east: it walks the player through
## the wall onto the grandpa cabin's door, which opens onto the deck.
func _ss_aqua_granddaughter(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var westward: Dictionary = _warp_chain(world, save, random, data, [
		SHIP_NE_CABIN_DOOR, SHIP_1F_TO_B1F_EAST, SHIP_B1F_TO_1F_WEST,
		SHIP_1F_TO_CAPTAIN_CABIN,
	])
	if not bool(westward.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the crossing to the captain's cabin failed: %s" % westward.get("reason", ""),
		}
	var talked: Dictionary = _talk_to(
		world, SHIP_GRANDDAUGHTER_FACE, Gen2WorldSprite.FACING_RIGHT, save, random, data
	)
	path.append({
		"step": "ss_aqua_granddaughter",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"arrived": world.event_flag_active(EVENT_FAST_SHIP_HAS_ARRIVED),
		"found_girl": world.event_flag_active(EVENT_FAST_SHIP_FOUND_GIRL),
		"metal_coat": world.event_flag_active(EVENT_GOT_METAL_COAT_FROM_GRANDPA),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(talked.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the granddaughter scene did not finish: %s" % talked.get("reason", ""),
		}
	if not world.event_flag_active(EVENT_FAST_SHIP_HAS_ARRIVED):
		return {"ok": false, "path": path, "reason": "the ship never docked"}
	if world.player_cell != SHIP_GRANDPA_CABIN_DOOR:
		return {
			"ok": false, "path": path,
			"reason": "the scene left the player on %s, not the grandpa cabin's door" % [
				_cell_value(world),
			],
		}
	return {"ok": true}


## The Vermilion Port dock to the Thunder Badge, the route's first Kanto leg.
##
## Nothing gates it. `VermilionGym_MapScripts` declares neither a scene nor a
## callback, so the gym is open from the door and Surge answers as soon as he is
## faced; `VermilionGymSurgeScript` is his own `checkflag ENGINE_THUNDERBADGE`,
## the battle, and the three trainer flags he sets whether they were fought or
## not.
func _thunder_badge_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var to_city: Dictionary = _warp_chain(
		world, save, random, data,
		[VERMILION_PORT_EXIT, VERMILION_PASSAGE_STAIRS, VERMILION_PASSAGE_EXIT]
	)
	if not bool(to_city.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk up from the dock failed: %s" % to_city.get("reason", ""),
		}
	if world.map_id() != Vector2i(VERMILION_GROUP, VERMILION_CITY_NUMBER):
		return {
			"ok": false, "path": path,
			"reason": "the passage ended on %s, not Vermilion City" % [_map_value(world)],
		}
	path.append({
		"step": "vermilion_city",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"flypoint": _engine_flag_set(world, data, ENGINE_FLYPOINT_VERMILION),
	})
	if not _engine_flag_set(world, data, ENGINE_FLYPOINT_VERMILION):
		return {"ok": false, "path": path, "reason": "the city's flypoint callback did not run"}

	var tree: Dictionary = _cut_at(
		world, VERMILION_GYM_TREE_APPROACH, Gen2WorldSprite.FACING_DOWN,
		save, random, data
	)
	path.append({
		"step": "vermilion_gym_tree",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"cut": tree.get("cell", []),
	})
	if not bool(tree.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the gym yard's tree failed: %s" % tree.get("reason", ""),
		}

	var to_gym: Dictionary = _warp_chain(world, save, random, data, [VERMILION_GYM_DOOR])
	if not bool(to_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the gym door failed: %s" % to_gym.get("reason", ""),
		}
	var surge: Dictionary = _talk_to(
		world, SURGE_FACE, Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "vermilion_gym_surge",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"thunder_badge": world.state.is_engine_flag_active(Gen2WorldState.badge_flag(
			BADGE_THUNDER, Gen2WorldState.is_crystal_profile(data)
		)),
		"run": surge,
	})
	if not bool(surge.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Lt. Surge did not finish: %s" % surge.get("reason", ""),
		}
	if not world.state.is_engine_flag_active(Gen2WorldState.badge_flag(
		BADGE_THUNDER, Gen2WorldState.is_crystal_profile(data)
	)):
		return {"ok": false, "path": path, "reason": "ENGINE_THUNDERBADGE was not set"}
	return {"ok": true}


## Vermilion Gym to the Marsh Badge, by way of Route 6 and Saffron City.
##
## The gym exit reloads the city, so the yard's tree has grown back and is cut a
## second time from the inside. Saffron is then a gate crossing rather than a
## connection, and its own gym is a warp maze: nine rooms with no doors between
## them, joined by fifteen pairs of self-warps, walked as the fixed chain
## SAFFRON_GYM_MAZE names.
func _marsh_badge_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var out_of_gym: Dictionary = _warp_chain(
		world, save, random, data, [VERMILION_GYM_EXIT]
	)
	if not bool(out_of_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving Vermilion Gym failed: %s" % out_of_gym.get("reason", ""),
		}
	var regrown: Dictionary = _cut_at(
		world, VERMILION_GYM_TREE_RETURN, Gen2WorldSprite.FACING_UP, save, random, data
	)
	if not bool(regrown.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the regrown gym tree failed: %s" % regrown.get("reason", ""),
		}

	var northward: Dictionary = _walk_connection_resolving(
		world, "north", ROUTE_6_GROUP, ROUTE_6_NUMBER, save, random, data
	)
	var route_6_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "vermilion_to_route_6",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": northward.get("encounters", []),
		"run": route_6_entry,
	})
	if not bool(northward.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk north to Route 6 failed: %s" % northward.get("reason", ""),
		}

	var gate: Dictionary = _gate_leg(
		world, save, random, data, ROUTE_6_SAFFRON_GATE_DOOR,
		SAFFRON_GROUP, SAFFRON_CITY_NUMBER
	)
	path.append({
		"step": "saffron_city",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"flypoint": _engine_flag_set(world, data, ENGINE_FLYPOINT_SAFFRON),
	})
	if not bool(gate.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Saffron gate failed: %s" % gate.get("reason", ""),
		}
	if not _engine_flag_set(world, data, ENGINE_FLYPOINT_SAFFRON):
		return {"ok": false, "path": path, "reason": "Saffron's flypoint callback did not run"}

	return _saffron_gym_leg(world, save, random, data, path)


## The warp maze, then Sabrina.
##
## Every pad is one half of a bidirectional pair, so a wrong one is recoverable
## rather than fatal, but only warp 17 reaches Sabrina's room at all. The walk
## between pads is ordinary: within a room the floor is open, and the BFS treats
## every other pad as a wall, which is what keeps it from wandering onto one.
func _saffron_gym_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var into_gym: Dictionary = _warp_chain(world, save, random, data, [SAFFRON_GYM_DOOR])
	if not bool(into_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Saffron Gym door failed: %s" % into_gym.get("reason", ""),
		}
	var pads: Array = []
	for pad: Vector2i in SAFFRON_GYM_MAZE:
		var stepped: Dictionary = _warp_walk(world, pad, save, random, data)
		pads.append({
			"pad": _cell_value_from_vector(pad),
			"landed": _cell_value(world),
			"encounters": stepped.get("encounters", []),
		})
		if not bool(stepped.get("ok", false)):
			path.append({"step": "saffron_gym_maze", "pads": pads})
			return {
				"ok": false, "path": path,
				"reason": "the maze pad on %s failed: %s" % [pad, stepped.get("reason", "")],
			}
	path.append({
		"step": "saffron_gym_maze",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"pads": pads,
	})

	var sabrina: Dictionary = _talk_to(
		world, SABRINA_FACE, Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "saffron_gym_sabrina",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"marsh_badge": world.state.is_engine_flag_active(Gen2WorldState.badge_flag(
			BADGE_MARSH, Gen2WorldState.is_crystal_profile(data)
		)),
		"run": sabrina,
	})
	if not bool(sabrina.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Sabrina did not finish: %s" % sabrina.get("reason", ""),
		}
	if not world.state.is_engine_flag_active(Gen2WorldState.badge_flag(
		BADGE_MARSH, Gen2WorldState.is_crystal_profile(data)
	)):
		return {"ok": false, "path": path, "reason": "ENGINE_MARSHBADGE was not set"}
	return {"ok": true}


## Saffron Gym to the Rainbow Badge, by way of Route 7 and Celadon City.
##
## The maze is walked back out pad for pad, since every pad is one half of a
## bidirectional pair. Saffron's west edge is a connection into Route 7 the way
## its south one is into Route 6, and carries no more traffic: the crossing is
## `ROUTE_7_SAFFRON_GATE`. Route 7's own west edge is the open half, a real
## connection onto Celadon City, and the gate that replaces it is inside the
## city: one cut tree seals the whole gym yard.
func _rainbow_badge_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var pads: Array = []
	for pad: Vector2i in SAFFRON_GYM_MAZE_OUT:
		var stepped: Dictionary = _warp_walk(world, pad, save, random, data)
		pads.append({
			"pad": _cell_value_from_vector(pad),
			"landed": _cell_value(world),
			"encounters": stepped.get("encounters", []),
		})
		if not bool(stepped.get("ok", false)):
			path.append({"step": "saffron_gym_exit", "pads": pads})
			return {
				"ok": false, "path": path,
				"reason": "the maze pad on %s failed: %s" % [pad, stepped.get("reason", "")],
			}
	var out_of_gym: Dictionary = _warp_chain(world, save, random, data, [SAFFRON_GYM_EXIT])
	path.append({
		"step": "saffron_gym_exit",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"pads": pads,
	})
	if not bool(out_of_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving Saffron Gym failed: %s" % out_of_gym.get("reason", ""),
		}

	var gate: Dictionary = _gate_leg(
		world, save, random, data, SAFFRON_ROUTE_7_GATE_DOOR,
		CELADON_GROUP, ROUTE_7_NUMBER
	)
	path.append({"step": "route_7", "map": _map_value(world), "cell": _cell_value(world)})
	if not bool(gate.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Route 7 gate failed: %s" % gate.get("reason", ""),
		}

	var westward: Dictionary = _walk_connection_resolving(
		world, "west", CELADON_GROUP, CELADON_CITY_NUMBER, save, random, data
	)
	var city_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "celadon_city",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"flypoint": _engine_flag_set(world, data, ENGINE_FLYPOINT_CELADON),
		"encounters": westward.get("encounters", []),
		"run": city_entry,
	})
	if not bool(westward.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk west to Celadon failed: %s" % westward.get("reason", ""),
		}
	if not _engine_flag_set(world, data, ENGINE_FLYPOINT_CELADON):
		return {"ok": false, "path": path, "reason": "Celadon's flypoint callback did not run"}

	return _celadon_gym_leg(world, save, random, data, path)


## The yard's tree, then Erika.
##
## Cutting (28,35) is what joins the city to the gym yard at all. The walk to
## Erika crosses three sight lines it cannot route around, so the trainers the
## walk resolves are reported with her.
func _celadon_gym_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var tree: Dictionary = _cut_at(
		world, CELADON_GYM_TREE_APPROACH, Gen2WorldSprite.FACING_DOWN,
		save, random, data
	)
	path.append({
		"step": "celadon_gym_tree",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"cut": tree.get("cell", []),
	})
	if not bool(tree.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the gym yard's tree failed: %s" % tree.get("reason", ""),
		}

	var to_gym: Dictionary = _warp_chain(world, save, random, data, [CELADON_GYM_DOOR])
	if not bool(to_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the gym door failed: %s" % to_gym.get("reason", ""),
		}
	var erika: Dictionary = _talk_to(
		world, ERIKA_FACE, Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "celadon_gym_erika",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"rainbow_badge": world.state.is_engine_flag_active(Gen2WorldState.badge_flag(
			BADGE_RAINBOW, Gen2WorldState.is_crystal_profile(data)
		)),
		# Set behind Erika's own verbosegiveitem, so it is what says the TM
		# offer finished rather than being refused.
		"giga_drain": world.event_flag_active(EVENT_GOT_TM19_GIGA_DRAIN),
		"run": erika,
	})
	if not bool(erika.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Erika did not finish: %s" % erika.get("reason", ""),
		}
	if not world.state.is_engine_flag_active(Gen2WorldState.badge_flag(
		BADGE_RAINBOW, Gen2WorldState.is_crystal_profile(data)
	)):
		return {"ok": false, "path": path, "reason": "ENGINE_RAINBOWBADGE was not set"}
	return {"ok": true}


## Celadon Gym to Cerulean City, by way of Saffron and Route 5.
##
## Two gate buildings and one open connection. Cerulean is as far as this walk
## goes: the Cascade Badge is an errand, not a cell. Misty and her three swimmers
## all carry EVENT_TRAINERS_IN_CERULEAN_GYM as their hide flag and
## `InitializeEventsScript` sets it, so the gym stays empty until
## `Route25MistyDate1Script` clears it; that scene is armed by the gym's own
## grunt, who is armed by the Power Plant manager. The plant is not walked to
## either: it sits in a region with no map edge and no walkable neighbour, and
## the way in is Route 9's river, which the same cut that opens the route also
## opens the shore of. `tools/checks/cerulean.gd` pins all of it.
func _cerulean_approach_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var out_of_gym: Dictionary = _warp_chain(world, save, random, data, [CELADON_GYM_EXIT])
	if not bool(out_of_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving Celadon Gym failed: %s" % out_of_gym.get("reason", ""),
		}
	var regrown: Dictionary = _cut_at(
		world, CELADON_GYM_TREE_RETURN, Gen2WorldSprite.FACING_RIGHT, save, random, data
	)
	if not bool(regrown.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the regrown gym tree failed: %s" % regrown.get("reason", ""),
		}

	var eastward: Dictionary = _walk_connection_resolving(
		world, "east", CELADON_GROUP, ROUTE_7_NUMBER, save, random, data
	)
	var _route_7_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "celadon_to_route_7",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": eastward.get("encounters", []),
	})
	if not bool(eastward.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk east to Route 7 failed: %s" % eastward.get("reason", ""),
		}

	var to_saffron: Dictionary = _gate_leg(
		world, save, random, data, ROUTE_7_GATE_DOOR, SAFFRON_GROUP, SAFFRON_CITY_NUMBER
	)
	if not bool(to_saffron.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Route 7 gate east failed: %s" % to_saffron.get("reason", ""),
		}
	var to_route_5: Dictionary = _gate_leg(
		world, save, random, data, SAFFRON_ROUTE_5_GATE_DOOR, SAFFRON_GROUP, ROUTE_5_NUMBER
	)
	path.append({"step": "route_5", "map": _map_value(world), "cell": _cell_value(world)})
	if not bool(to_route_5.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Route 5 gate failed: %s" % to_route_5.get("reason", ""),
		}

	var northward: Dictionary = _walk_connection_resolving(
		world, "north", CERULEAN_GROUP, CERULEAN_CITY_NUMBER, save, random, data
	)
	var city_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "cerulean_city",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"flypoint": _engine_flag_set(world, data, ENGINE_FLYPOINT_CERULEAN),
		"encounters": northward.get("encounters", []),
		"run": city_entry,
	})
	if not bool(northward.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk north to Cerulean failed: %s" % northward.get("reason", ""),
		}
	if not _engine_flag_set(world, data, ENGINE_FLYPOINT_CERULEAN):
		return {"ok": false, "path": path, "reason": "Cerulean's flypoint callback did not run"}
	return _machine_part_errand(world, save, random, data, path)


## Cerulean City through the errand the Cascade Badge waits on.
##
## The first Kanto badge whose gate is an errand rather than a cell, and the
## errand runs in the order the cartridge forces: the Power Plant manager arms
## the gym, the gym's grunt arms Route 24 and Route 25, Route 24's grunt names
## the pool, the pool holds the MACHINE_PART, the manager takes it back, and only
## Route 25's date puts Misty in her gym. Two of those steps are at the plant, so
## the river is ridden twice each way.
func _machine_part_errand(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var met: Dictionary = _power_plant_visit(world, save, random, data, path, "manager")
	if not bool(met.get("ok", false)):
		return met
	if not world.event_flag_active(EVENT_MET_MANAGER_AT_POWER_PLANT):
		return {"ok": false, "path": path, "reason": "the manager did not arm the gym"}

	# Entering the gym is what runs the grunt scene; nothing has to be faced.
	var into_gym: Dictionary = _warp_chain(world, save, random, data, [CERULEAN_GYM_DOOR])
	path.append({
		"step": "cerulean_gym_grunt",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": into_gym,
	})
	if not bool(into_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Cerulean Gym door failed: %s" % into_gym.get("reason", ""),
		}
	var out_of_gym: Dictionary = _warp_chain(world, save, random, data, [CERULEAN_GYM_EXIT])
	if not bool(out_of_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving Cerulean Gym failed: %s" % out_of_gym.get("reason", ""),
		}

	var north: Dictionary = _route_24_and_25(world, save, random, data, path)
	if not bool(north.get("ok", false)):
		return north

	var part: Dictionary = _cerulean_machine_part(world, save, random, data, path)
	if not bool(part.get("ok", false)):
		return part

	var returned: Dictionary = _power_plant_visit(
		world, save, random, data, path, "machine_part"
	)
	if not bool(returned.get("ok", false)):
		return returned
	if not world.event_flag_active(EVENT_RETURNED_MACHINE_PART):
		return {"ok": false, "path": path, "reason": "the machine part was not handed over"}
	if world.event_flag_active(EVENT_TRAINERS_IN_CERULEAN_GYM):
		return {"ok": false, "path": path, "reason": "Misty is still hidden"}
	return _cerulean_gym_leg(world, save, random, data, path)


## Misty, once the errand has put her in her gym.
##
## The gym is a pool with the leader on an island, and its trainers are what the
## walk has to answer: Swimmer Diana watches the one row every route to Misty
## crosses, and Swimmers Parker and Briana watch the pool's two alternative
## columns, so one of the pair is met whichever way round it goes. All three stand
## on water and walk over it to reach the player, which the cartridge allows
## because `SeenByTrainerScript` is `applymovementlasttalked` and its steps reach
## `NormalStep`, checking no permission. `tools/checks/cerulean.gd` pins the
## geometry and each approach.
##
## Misty herself sets all three of their beaten flags along with her own, the way
## Surge, Erika and Sabrina do, so they are reported rather than gated on.
func _cerulean_gym_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var into_gym: Dictionary = _warp_chain(world, save, random, data, [CERULEAN_GYM_DOOR])
	if not bool(into_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Cerulean Gym door failed: %s" % into_gym.get("reason", ""),
		}
	var misty: Dictionary = _talk_to(
		world, MISTY_FACE, Gen2WorldSprite.FACING_UP, save, random, data
	)
	var badge: int = Gen2WorldState.badge_flag(
		BADGE_CASCADE, Gen2WorldState.is_crystal_profile(data)
	)
	var trainers_beaten: int = 0
	for flag: int in CERULEAN_GYM_TRAINER_FLAGS:
		if world.event_flag_active(flag):
			trainers_beaten += 1
	path.append({
		"step": "cerulean_gym_misty",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"cascade_badge": world.state.is_engine_flag_active(badge),
		"beat_misty": world.event_flag_active(EVENT_BEAT_MISTY),
		"swimmer_flags": trainers_beaten,
		"swimmers_fought": misty.get("encounters", []),
		"run": misty,
	})
	if not bool(misty.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Misty did not finish: %s" % misty.get("reason", ""),
		}
	if not world.state.is_engine_flag_active(badge):
		return {"ok": false, "path": path, "reason": "ENGINE_CASCADEBADGE was not set"}
	if trainers_beaten != CERULEAN_GYM_TRAINER_FLAGS.size():
		return {
			"ok": false, "path": path,
			"reason": "Misty set %d of her three swimmer flags" % trainers_beaten,
		}
	return _lavender_leg(world, save, random, data, path)


## Cerulean Gym back through Saffron to Lavender Town and the Kanto Radio Tower.
##
## Two gate buildings and one open connection, the same shape as the walk that
## reached Cerulean, run in reverse and then east: Route 5's own warp at (8,17)
## into the Saffron gate, Saffron's warp 14 into the Route 8 gate, and Route 8's
## single east crossing at (39,8) onto Lavender's (0,8). No cut tree and no
## errand stand in the way of the town itself; Route 8's five trainers are the
## only thing between the gate and the crossing, and just one of them, Super Nerd
## Tom, cannot be routed around. The three bikers watch the corridor west of the
## route's eight `$a3` hop-down ledges, and the eastbound walk hops off row 6
## onto row 8 east of them, so it never enters a line they cover.
##
## What the leg is for is the EXPN CARD. `LavRadioTower1FGentlemanScript` gates it
## on `EVENT_RETURNED_MACHINE_PART`, which the Cerulean errand already set, so
## this is the second time a Kanto opener sat before its gate rather than behind
## it: the tower is off the air until the Power Plant runs, and the card is what
## eventually answers `special SnorlaxAwake` on Route 11.
func _lavender_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var out_of_gym: Dictionary = _warp_chain(world, save, random, data, [CERULEAN_GYM_EXIT])
	if not bool(out_of_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving Cerulean Gym failed: %s" % out_of_gym.get("reason", ""),
		}
	var southward: Dictionary = _walk_connection_resolving(
		world, "south", SAFFRON_GROUP, ROUTE_5_NUMBER, save, random, data
	)
	var _route_5_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	if not bool(southward.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk south to Route 5 failed: %s" % southward.get("reason", ""),
		}
	var to_saffron: Dictionary = _gate_leg(
		world, save, random, data, ROUTE_5_GATE_DOOR, SAFFRON_GROUP, SAFFRON_CITY_NUMBER
	)
	if not bool(to_saffron.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Route 5 gate south failed: %s" % to_saffron.get("reason", ""),
		}
	var errand: Dictionary = _magnet_train_leg(world, save, random, data, path)
	if not bool(errand.get("ok", false)):
		return errand

	var to_route_8: Dictionary = _gate_leg(
		world, save, random, data, SAFFRON_ROUTE_8_GATE_DOOR, LAVENDER_GROUP, ROUTE_8_NUMBER
	)
	path.append({"step": "route_8", "map": _map_value(world), "cell": _cell_value(world)})
	if not bool(to_route_8.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Route 8 gate failed: %s" % to_route_8.get("reason", ""),
		}

	var eastward: Dictionary = _walk_connection_resolving(
		world, "east", LAVENDER_GROUP, LAVENDER_TOWN_NUMBER, save, random, data
	)
	var town_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "lavender_town",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"flypoint": _engine_flag_set(world, data, ENGINE_FLYPOINT_LAVENDER),
		"encounters": eastward.get("encounters", []),
		"run": town_entry,
	})
	if not bool(eastward.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk east to Lavender failed: %s" % eastward.get("reason", ""),
		}
	if not _engine_flag_set(world, data, ENGINE_FLYPOINT_LAVENDER):
		return {"ok": false, "path": path, "reason": "Lavender's flypoint callback did not run"}

	var into_tower: Dictionary = _warp_chain(
		world, save, random, data, [LAVENDER_RADIO_TOWER_DOOR]
	)
	if not bool(into_tower.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Radio Tower door failed: %s" % into_tower.get("reason", ""),
		}
	var gentleman: Dictionary = _talk_to(
		world, RADIO_TOWER_GENTLEMAN_FACE, Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "lavender_radio_tower_expn_card",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"expn_card": world.state.is_engine_flag_active(ENGINE_EXPN_CARD),
		"run": gentleman,
	})
	if not bool(gentleman.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Radio Tower gentleman did not finish: %s" % gentleman.get("reason", ""),
		}
	if not world.state.is_engine_flag_active(ENGINE_EXPN_CARD):
		return {"ok": false, "path": path, "reason": "ENGINE_EXPN_CARD was not set"}
	return _fuchsia_leg(world, save, random, data, path)


## The lost-doll errand and the Magnet Train, run from Saffron City.
##
## An errand rather than a walk, and the one leg on the route whose order the
## cartridge fixes rather than the geography: the Fan Club's Clefairy guy reads
## EVENT_MET_COPYCAT_FOUND_OUT_ABOUT_LOST_ITEM before he parts with the doll, and
## only the Copycat sets it, so she is visited first with nothing to give her.
## Her own branch needs EVENT_RETURNED_MACHINE_PART, which the Cerulean leg set
## at the Power Plant, so this is the third Kanto opener that sat before its gate.
##
## The ride itself never touches the platform on foot. Each station is two
## regions with row 9 solid between them; the officer stands inside that row and
## is talked to across it, and his script's `applymovement` walks the player over
## the wall onto the train door, because a scripted step ignores collision. The
## `warpcheck` after it takes the door, and the arrival coord event on the far
## station is stepped onto rather than walked to, since it is live.
func _magnet_train_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var met: Dictionary = _copycat_visit(world, save, random, data, path, "met")
	if not bool(met.get("ok", false)):
		return met
	if not world.event_flag_active(EVENT_MET_COPYCAT_FOUND_OUT_ABOUT_LOST_ITEM):
		return {
			"ok": false, "path": path,
			"reason": "the Copycat did not mention the lost doll",
		}

	var to_vermilion: Dictionary = _saffron_vermilion_walk(
		world, save, random, data, path, "south"
	)
	if not bool(to_vermilion.get("ok", false)):
		return to_vermilion

	var doll: Dictionary = _fan_club_doll(world, save, random, data, path)
	if not bool(doll.get("ok", false)):
		return doll

	var back_to_saffron: Dictionary = _saffron_vermilion_walk(
		world, save, random, data, path, "north"
	)
	if not bool(back_to_saffron.get("ok", false)):
		return back_to_saffron

	var pass_given: Dictionary = _copycat_visit(world, save, random, data, path, "pass")
	if not bool(pass_given.get("ok", false)):
		return pass_given
	if world.state.item_quantity(ITEM_PASS) <= 0:
		return {"ok": false, "path": path, "reason": "the PASS did not reach the bag"}

	return _magnet_train_ride(world, save, random, data, path)


## Copycat's House, twice: once to hear about the doll and once to hand it back.
func _copycat_visit(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
	stage: String,
) -> Dictionary:
	var upstairs: Dictionary = _warp_chain(
		world, save, random, data, [SAFFRON_COPYCAT_HOUSE_DOOR, COPYCAT_HOUSE_STAIRS_UP]
	)
	if not bool(upstairs.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Copycat's house stairs failed: %s" % upstairs.get("reason", ""),
		}
	var copycat: Dictionary = _talk_to(
		world, COPYCAT_FACE, Gen2WorldSprite.FACING_LEFT, save, random, data
	)
	path.append({
		"step": "copycat_%s" % stage,
		"map": _map_value(world),
		"cell": _cell_value(world),
		"met_copycat": world.event_flag_active(EVENT_MET_COPYCAT_FOUND_OUT_ABOUT_LOST_ITEM),
		"returned_lost_item": world.event_flag_active(EVENT_RETURNED_LOST_ITEM_TO_COPYCAT),
		"got_pass": world.event_flag_active(EVENT_GOT_PASS_FROM_COPYCAT),
		"lost_item": world.state.item_quantity(ITEM_LOST_ITEM),
		"pass": world.state.item_quantity(ITEM_PASS),
		"run": copycat.get("run", {}),
	})
	if not bool(copycat.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Copycat did not finish: %s" % copycat.get("reason", ""),
		}
	var downstairs: Dictionary = _warp_chain(
		world, save, random, data, [COPYCAT_HOUSE_STAIRS_DOWN, COPYCAT_HOUSE_EXIT]
	)
	if not bool(downstairs.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving the Copycat's house failed: %s" % downstairs.get("reason", ""),
		}
	return {"ok": true}


## Saffron to Vermilion and back, which is one gate building and one connection
## each way. [param heading] is "south" for the walk down and "north" for the
## return.
func _saffron_vermilion_walk(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
	heading: String,
) -> Dictionary:
	var southbound: bool = heading == "south"
	if southbound:
		var out_of_saffron: Dictionary = _gate_leg(
			world, save, random, data, SAFFRON_ROUTE_6_GATE_DOOR,
			ROUTE_6_GROUP, ROUTE_6_NUMBER
		)
		if not bool(out_of_saffron.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the Route 6 gate south failed: %s" % out_of_saffron.get("reason", ""),
			}

	var walked: Dictionary = _walk_connection_resolving(
		world, "south" if southbound else "north",
		VERMILION_GROUP if southbound else ROUTE_6_GROUP,
		VERMILION_CITY_NUMBER if southbound else ROUTE_6_NUMBER,
		save, random, data
	)
	var entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "vermilion_for_the_doll" if southbound else "route_6_northbound",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": walked.get("encounters", []),
		"run": entry,
	})
	if not bool(walked.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk %s along Route 6 failed: %s" % [
				heading, walked.get("reason", ""),
			],
		}
	if southbound:
		return {"ok": true}

	var into_saffron: Dictionary = _gate_leg(
		world, save, random, data, ROUTE_6_SAFFRON_GATE_DOOR,
		SAFFRON_GROUP, SAFFRON_CITY_NUMBER
	)
	path.append({
		"step": "saffron_return",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": into_saffron.get("encounters", []),
	})
	if not bool(into_saffron.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Route 6 gate north failed: %s" % into_saffron.get("reason", ""),
		}
	return {"ok": true}


## The Pokemon Fan Club, where the doll is.
func _fan_club_doll(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var inside: Dictionary = _warp_chain(
		world, save, random, data, [VERMILION_FAN_CLUB_DOOR]
	)
	if not bool(inside.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Fan Club door failed: %s" % inside.get("reason", ""),
		}
	var guy: Dictionary = _talk_to(
		world, CLEFAIRY_GUY_FACE, Gen2WorldSprite.FACING_RIGHT, save, random, data
	)
	path.append({
		"step": "fan_club_lost_item",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"got_lost_item": world.event_flag_active(EVENT_GOT_LOST_ITEM_FROM_FAN_CLUB),
		"lost_item": world.state.item_quantity(ITEM_LOST_ITEM),
		"run": guy.get("run", {}),
	})
	if not bool(guy.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Clefairy guy did not finish: %s" % guy.get("reason", ""),
		}
	if world.state.item_quantity(ITEM_LOST_ITEM) <= 0:
		return {"ok": false, "path": path, "reason": "the LOST ITEM did not reach the bag"}
	var out: Dictionary = _warp_chain(world, save, random, data, [FAN_CLUB_EXIT])
	if not bool(out.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Fan Club exit failed: %s" % out.get("reason", ""),
		}
	return {"ok": true}


## Saffron to Goldenrod and straight back, which is the same officer twice.
func _magnet_train_ride(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var into_station: Dictionary = _warp_chain(
		world, save, random, data, [SAFFRON_TRAIN_STATION_DOOR]
	)
	if not bool(into_station.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Saffron station door failed: %s" % into_station.get("reason", ""),
		}

	for ride: Dictionary in [
		{"step": "magnet_train_to_goldenrod", "group": GOLDENROD_GROUP,
			"number": GOLDENROD_MAGNET_TRAIN_STATION_NUMBER},
		{"step": "magnet_train_to_saffron", "group": SAFFRON_GROUP,
			"number": SAFFRON_MAGNET_TRAIN_STATION_NUMBER},
	]:
		var boarded: Dictionary = _talk_to(
			world, TRAIN_OFFICER_FACE, Gen2WorldSprite.FACING_UP,
			save, random, data, BOARD_THE_TRAIN
		)
		var run: Dictionary = boarded.get("run", {})
		path.append({
			"step": ride["step"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"run": run,
		})
		if not bool(boarded.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s failed: %s" % [ride["step"], boarded.get("reason", "")],
			}
		if world.map_id() != Vector2i(int(ride["group"]), int(ride["number"])):
			return {
				"ok": false, "path": path,
				"reason": "%s left the player on %s" % [ride["step"], world.map_id()],
			}
		if world.player_cell != TRAIN_LANDING:
			return {
				"ok": false, "path": path,
				"reason": "%s landed on %s, not the train door %s" % [
					ride["step"], world.player_cell, TRAIN_LANDING,
				],
			}

		# The arrival coord event is still armed, so it is stepped onto and
		# drained rather than targeted with a resolving walk.
		var arrival: Dictionary = _coord_event_step(
			world, TRAIN_LANDING, TRAIN_ARRIVAL_COORD, save, random, data
		)
		path.append({
			"step": "%s_arrival" % ride["step"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"run": arrival.get("run", {}),
		})
		if not bool(arrival.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the %s arrival scene failed: %s" % [
					ride["step"], arrival.get("reason", ""),
				],
			}

	var out_of_station: Dictionary = _warp_chain(
		world, save, random, data, [SAFFRON_TRAIN_STATION_EXIT]
	)
	if not bool(out_of_station.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Saffron station exit failed: %s" % out_of_station.get("reason", ""),
		}
	return {"ok": true}


## Lavender Town south to Fuchsia City and the Soul Badge.
##
## The longest open walk in Kanto and the first leg since Vermilion with no
## errand in it at all: Routes 12, 13, 14 and 15 are four plain connections, and
## the only door is `ROUTE_15_FUCHSIA_GATE` at the end. What it costs is
## trainers, eighteen of them, and `tools/checks/fuchsia.gd` measures which
## ones a walk owes rather than guessing: on this profile only Route 13's
## Pokefan Joshua and Hiker Kenny stand where shutting their sight line seals the
## way south. The other three routes can be crossed without meeting anyone, and
## Route 12, Route 14 and Route 15 are all profile splits, so Gold and Silver
## owe a different set.
##
## The gym is a maze rather than a puzzle with a gate: 128 walkable cells behind
## the door, and Janine on (1,10) reachable from (1,9). Her four disguised
## trainers are `OBJECTTYPE_SCRIPT`, so nothing sees the player and none of them
## has to be fought; `FuchsiaGymJanineScript` sets all four beaten flags itself
## along with `ENGINE_SOULBADGE`, and hands over TM06 through its own
## `verbosegiveitem`.
func _fuchsia_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var out_of_tower: Dictionary = _warp_chain(
		world, save, random, data, [LAVENDER_RADIO_TOWER_EXIT]
	)
	if not bool(out_of_tower.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving the Radio Tower failed: %s" % out_of_tower.get("reason", ""),
		}

	var southbound: Array = [
		{"step": "route_12", "direction": "south", "group": LAVENDER_GROUP,
			"number": ROUTE_12_NUMBER},
		{"step": "route_13", "direction": "south", "group": FUCHSIA_GROUP,
			"number": ROUTE_13_NUMBER},
		{"step": "route_14", "direction": "south", "group": FUCHSIA_GROUP,
			"number": ROUTE_14_NUMBER},
		{"step": "route_15", "direction": "west", "group": FUCHSIA_GROUP,
			"number": ROUTE_15_NUMBER},
	]
	for leg: Dictionary in southbound:
		var walked: Dictionary = _walk_connection_resolving(
			world, String(leg["direction"]), int(leg["group"]), int(leg["number"]),
			save, random, data
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": leg["step"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the walk to %s failed: %s" % [leg["step"], walked.get("reason", "")],
			}

	var to_city: Dictionary = _gate_leg(
		world, save, random, data, ROUTE_15_GATE_DOOR, FUCHSIA_GROUP, FUCHSIA_CITY_NUMBER
	)
	path.append({
		"step": "fuchsia_city",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"flypoint": _engine_flag_set(world, data, ENGINE_FLYPOINT_FUCHSIA),
		"encounters": to_city.get("encounters", []),
	})
	if not bool(to_city.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Route 15 gate failed: %s" % to_city.get("reason", ""),
		}
	if not _engine_flag_set(world, data, ENGINE_FLYPOINT_FUCHSIA):
		return {"ok": false, "path": path, "reason": "Fuchsia's flypoint callback did not run"}

	var into_gym: Dictionary = _warp_chain(world, save, random, data, [FUCHSIA_GYM_DOOR])
	if not bool(into_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Fuchsia Gym door failed: %s" % into_gym.get("reason", ""),
		}
	var janine: Dictionary = _talk_to(
		world, JANINE_FACE, Gen2WorldSprite.FACING_DOWN, save, random, data
	)
	var badge: int = Gen2WorldState.badge_flag(
		BADGE_SOUL, Gen2WorldState.is_crystal_profile(data)
	)
	var disguised: int = 0
	for flag: int in FUCHSIA_GYM_TRAINER_FLAGS:
		if world.event_flag_active(flag):
			disguised += 1
	path.append({
		"step": "fuchsia_gym_janine",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"soul_badge": world.state.is_engine_flag_active(badge),
		"beat_janine": world.event_flag_active(EVENT_BEAT_JANINE),
		"disguised_flags": disguised,
		# Set behind her own verbosegiveitem, so it says the TM offer finished
		# rather than being refused.
		"toxic": world.event_flag_active(EVENT_GOT_TM06_TOXIC),
		"run": janine,
	})
	if not bool(janine.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Janine did not finish: %s" % janine.get("reason", ""),
		}
	if not world.state.is_engine_flag_active(badge):
		return {"ok": false, "path": path, "reason": "ENGINE_SOULBADGE was not set"}
	if disguised != FUCHSIA_GYM_TRAINER_FLAGS.size():
		return {
			"ok": false, "path": path,
			"reason": "Janine set %d of her four trainer flags" % disguised,
		}
	return _pewter_leg(world, save, random, data, path)


## Fuchsia Gym back to Vermilion, through Diglett's Cave to Route 2, and up to
## Pewter Gym for the Boulder Badge.
##
## The order is forced. Measured against a real Crystal cache, a walk out of
## Cerulean reaches 91 maps and none of Route 3, Route 4's main region, Mount
## Moon, Route 2, Viridian, Pallet, Cinnabar, Route 20 or Seafoam Gym, and
## Fuchsia's own south edge is sealed the other way while
## EVENT_CINNABAR_ROCKS_CLEARED is clear. Diglett's Cave is the one door into
## west Kanto, and the Snorlax on top of it is the lock.
##
## What opens that lock is the radio, which is why the Goldenrod leg now takes
## the Radio Card: `SnorlaxAwake` answers only while the Poke Flute channel is
## the track in `wMapMusic`, and a station's music id is neither sentinel
## `ExitPokegearRadio_HandleMusic` restores on, so it survives the Pokegear
## closing. `tools/checks/radio.gd` owns that whole chain and the Route 2
## counts behind it.
func _pewter_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var out_of_gym: Dictionary = _warp_chain(world, save, random, data, [FUCHSIA_GYM_EXIT])
	if not bool(out_of_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving Fuchsia Gym failed: %s" % out_of_gym.get("reason", ""),
		}

	var to_route_15: Dictionary = _gate_leg(
		world, save, random, data, FUCHSIA_ROUTE_15_GATE_DOOR, FUCHSIA_GROUP, ROUTE_15_NUMBER
	)
	path.append({
		"step": "route_15_eastbound",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": to_route_15.get("encounters", []),
	})
	if not bool(to_route_15.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Route 15 gate east failed: %s" % to_route_15.get("reason", ""),
		}

	var northbound: Array = [
		{"step": "route_14_northbound", "direction": "east", "group": FUCHSIA_GROUP,
			"number": ROUTE_14_NUMBER},
		{"step": "route_13_northbound", "direction": "north", "group": FUCHSIA_GROUP,
			"number": ROUTE_13_NUMBER},
		{"step": "route_12_northbound", "direction": "north", "group": LAVENDER_GROUP,
			"number": ROUTE_12_NUMBER},
		{"step": "route_11_westbound", "direction": "west", "group": VERMILION_GROUP,
			"number": ROUTE_11_NUMBER},
		{"step": "vermilion_return", "direction": "west", "group": VERMILION_GROUP,
			"number": VERMILION_CITY_NUMBER},
	]
	for leg: Dictionary in northbound:
		var walked: Dictionary = _walk_connection_resolving(
			world, String(leg["direction"]), int(leg["group"]), int(leg["number"]),
			save, random, data
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": leg["step"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the walk to %s failed: %s" % [leg["step"], walked.get("reason", "")],
			}

	var snorlax: Dictionary = _wake_snorlax(world, save, random, data, path)
	if not bool(snorlax.get("ok", false)):
		return snorlax

	var through_cave: Dictionary = _warp_chain(
		world, save, random, data, [DIGLETTS_CAVE_MOUTH] + DIGLETTS_CAVE_CHAIN
	)
	path.append({
		"step": "digletts_cave",
		"map": _map_value(world),
		"cell": _cell_value(world),
	})
	if not bool(through_cave.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Diglett's Cave failed: %s" % through_cave.get("reason", ""),
		}
	if world.map_id() != Vector2i(ROUTE_2_GROUP, ROUTE_2_NUMBER):
		return {"ok": false, "path": path, "reason": "the cave did not come out on Route 2"}

	# The sixth site the route cuts without a party member that knows CUT, which
	# is open work item 9 and not this leg's to fix.
	var cut: Dictionary = _cut_at(
		world, ROUTE_2_CUT_APPROACH, Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "route_2_cut",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": cut.get("encounters", []),
	})
	if not bool(cut.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 2's cut tree failed: %s" % cut.get("reason", ""),
		}

	var to_pewter: Dictionary = _walk_connection_resolving(
		world, "north", PEWTER_GROUP, PEWTER_CITY_NUMBER, save, random, data
	)
	var pewter_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "pewter_city",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"flypoint": _engine_flag_set(world, data, ENGINE_FLYPOINT_PEWTER),
		"encounters": to_pewter.get("encounters", []),
		"run": pewter_entry,
	})
	if not bool(to_pewter.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk to Pewter failed: %s" % to_pewter.get("reason", ""),
		}
	if not _engine_flag_set(world, data, ENGINE_FLYPOINT_PEWTER):
		return {"ok": false, "path": path, "reason": "Pewter's flypoint callback did not run"}

	return _pewter_gym_leg(world, save, random, data, path)


## Vermilion's Snorlax, which is the only thing between the walked route and
## west Kanto.
##
## Tuning is the whole interaction: `SnorlaxAwake` compares `wMapMusic` against
## the Poke Flute channel and takes its false branch otherwise, so the dial is
## moved to 20.0 and the Pokegear closed before it is talked to. The card the
## dial needs is `ENGINE_RADIO_CARD`, taken on the Goldenrod leg, and the region
## check behind the station needs `ENGINE_EXPN_CARD`, taken on the Lavender one.
func _wake_snorlax(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	if not world.state.is_engine_flag_active(Gen2WorldState.ENGINE_RADIO_CARD):
		return {"ok": false, "path": path, "reason": "the route reached the Snorlax with no radio card"}

	var walked: Dictionary = _walk_cell_resolving(world, SNORLAX_TALK, save, random, data)
	if not bool(walked.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk to the Snorlax failed: %s" % walked.get("reason", ""),
		}
	var tuned: Dictionary = world.tune_radio(KNOB_POKE_FLUTE)
	world.close_radio()
	if not bool(tuned.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "20.0 answered no station: %s" % tuned.get("reason", ""),
		}

	world.player_facing = Gen2WorldSprite.FACING_LEFT
	var run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	path.append({
		"step": "vermilion_snorlax",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"map_music": world.state.map_music(),
		"fought_snorlax": world.event_flag_active(EVENT_FOUGHT_SNORLAX),
		"vermilion_city_snorlax": world.event_flag_active(EVENT_VERMILION_CITY_SNORLAX),
		"cave_mouth_open": world.object_at(DIGLETTS_CAVE_MOUTH) == null,
		"encounters": walked.get("encounters", []),
		"run": run,
	})
	if not bool(run.get("terminal", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Snorlax script did not finish: %s" % run.get("reason", ""),
		}
	if not world.event_flag_active(EVENT_FOUGHT_SNORLAX):
		return {"ok": false, "path": path, "reason": "the Snorlax was not fought"}
	if not world.event_flag_active(EVENT_VERMILION_CITY_SNORLAX):
		return {"ok": false, "path": path, "reason": "the Snorlax did not disappear"}
	return {"ok": true}


## Pewter Gym and the Boulder Badge. `maps/PewterGym.asm` declares neither a
## scene nor a callback, so Brock answers as soon as he is faced, and his own
## script sets Camper Jerry's flag whether or not Jerry was fought.
func _pewter_gym_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var into_gym: Dictionary = _warp_chain(world, save, random, data, [PEWTER_GYM_DOOR])
	if not bool(into_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Pewter Gym door failed: %s" % into_gym.get("reason", ""),
		}

	var brock: Dictionary = _talk_to(
		world, BROCK_FACE, Gen2WorldSprite.FACING_UP, save, random, data
	)
	var badge: int = Gen2WorldState.badge_flag(
		BADGE_BOULDER, Gen2WorldState.is_crystal_profile(data)
	)
	path.append({
		"step": "pewter_gym_brock",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"boulder_badge": world.state.is_engine_flag_active(badge),
		"beat_brock": world.event_flag_active(EVENT_BEAT_BROCK),
		"beat_camper_jerry": world.event_flag_active(EVENT_BEAT_CAMPER_JERRY),
		"encounters": brock.get("encounters", []),
		"run": brock,
	})
	if not bool(brock.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Brock did not finish: %s" % brock.get("reason", ""),
		}
	if not world.state.is_engine_flag_active(badge):
		return {"ok": false, "path": path, "reason": "ENGINE_BOULDERBADGE was not set"}
	if not world.event_flag_active(EVENT_BEAT_CAMPER_JERRY):
		return {"ok": false, "path": path, "reason": "Brock did not set Camper Jerry's flag"}
	return _cinnabar_leg(world, save, random, data, path)


## Pewter Gym south to Cinnabar Island and east to Seafoam Gym's Volcano Badge.
##
## Six plain connections carry the walk down the west coast, and then it is water
## the rest of the way: Pallet's own pond is the last land, and Route 21,
## Cinnabar's west side and Route 20 are all surfed. Two things make this leg the
## one that has to come before Viridian's. Blue stands on Cinnabar until he is
## talked to, and `CinnabarIslandBlue` is the only `clearevent` for
## EVENT_VIRIDIAN_GYM_BLUE in either pin; and `Route20ClearRocksCallback` is a
## MAPCALLBACK_NEWMAP, so simply arriving on Route 20 sets
## EVENT_CINNABAR_ROCKS_CLEARED and takes the six `$7a` wall blocks off Route 19.
func _cinnabar_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var out_of_gym: Dictionary = _warp_chain(world, save, random, data, [PEWTER_GYM_EXIT])
	if not bool(out_of_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving Pewter Gym failed: %s" % out_of_gym.get("reason", ""),
		}

	var southbound: Array = [
		{"step": "route_2_southbound", "group": ROUTE_2_GROUP, "number": ROUTE_2_NUMBER},
		{"step": "viridian_city", "group": ROUTE_2_GROUP, "number": VIRIDIAN_CITY_NUMBER,
			"flypoint": ENGINE_FLYPOINT_VIRIDIAN},
		{"step": "route_1", "group": PALLET_GROUP, "number": ROUTE_1_NUMBER},
		{"step": "pallet_town", "group": PALLET_GROUP, "number": PALLET_TOWN_NUMBER,
			"flypoint": ENGINE_FLYPOINT_PALLET},
	]
	for leg: Dictionary in southbound:
		var walked: Dictionary = _walk_connection_resolving(
			world, "south", int(leg["group"]), int(leg["number"]), save, random, data
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		var step: Dictionary = {
			"step": leg["step"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		}
		if leg.has("flypoint"):
			step["flypoint"] = _engine_flag_set(world, data, int(leg["flypoint"]))
		path.append(step)
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the walk to %s failed: %s" % [leg["step"], walked.get("reason", "")],
			}
		if leg.has("flypoint") \
			and not _engine_flag_set(world, data, int(leg["flypoint"])):
			return {
				"ok": false, "path": path,
				"reason": "%s's flypoint callback did not run" % leg["step"],
			}

	var boarded: Dictionary = _surf_at(
		world, PALLET_SURF_APPROACH, Gen2WorldSprite.FACING_DOWN, save, random, data
	)
	path.append({
		"step": "pallet_pond_surf",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": boarded.get("encounters", []),
	})
	if not bool(boarded.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Pallet's surf entry failed: %s" % boarded.get("reason", ""),
		}

	for leg: Dictionary in [
		{"step": "route_21", "number": ROUTE_21_NUMBER},
		{"step": "cinnabar_island", "number": CINNABAR_ISLAND_NUMBER},
	]:
		var surfed: Dictionary = _walk_connection_resolving(
			world, "south", SEAFOAM_GROUP, int(leg["number"]), save, random, data, true
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": leg["step"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": surfed.get("encounters", []),
			"run": entry,
		})
		if not bool(surfed.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the surf to %s failed: %s" % [leg["step"], surfed.get("reason", "")],
			}

	var ashore: Dictionary = _walk_cell_resolving(
		world, CINNABAR_LANDING, save, random, data, true
	)
	if not bool(ashore.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "landing on Cinnabar failed: %s" % ashore.get("reason", ""),
		}
	if not _engine_flag_set(world, data, ENGINE_FLYPOINT_CINNABAR):
		return {"ok": false, "path": path, "reason": "Cinnabar's flypoint callback did not run"}

	var blue: Dictionary = _talk_to(
		world, BLUE_FACE, Gen2WorldSprite.FACING_RIGHT, save, random, data
	)
	path.append({
		"step": "cinnabar_blue",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"flypoint": _engine_flag_set(world, data, ENGINE_FLYPOINT_CINNABAR),
		"viridian_gym_blue": world.event_flag_active(EVENT_VIRIDIAN_GYM_BLUE),
		"encounters": blue.get("encounters", []),
		"run": blue.get("run", {}),
	})
	if not bool(blue.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Blue did not finish: %s" % blue.get("reason", ""),
		}
	if world.event_flag_active(EVENT_VIRIDIAN_GYM_BLUE):
		return {
			"ok": false, "path": path,
			"reason": "Blue did not clear EVENT_VIRIDIAN_GYM_BLUE",
		}

	return _seafoam_gym_leg(world, save, random, data, path)


## Cinnabar east to Route 20 and Blaine's cave.
func _seafoam_gym_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var boarded: Dictionary = _surf_at(
		world, CINNABAR_SURF_APPROACH, Gen2WorldSprite.FACING_LEFT, save, random, data
	)
	if not bool(boarded.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Cinnabar's surf entry failed: %s" % boarded.get("reason", ""),
		}
	var eastbound: Dictionary = _walk_connection_resolving(
		world, "east", SEAFOAM_GROUP, ROUTE_20_NUMBER, save, random, data, true
	)
	var entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_20",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"cinnabar_rocks_cleared": world.event_flag_active(EVENT_CINNABAR_ROCKS_CLEARED),
		"encounters": eastbound.get("encounters", []),
		"run": entry,
	})
	if not bool(eastbound.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the surf to Route 20 failed: %s" % eastbound.get("reason", ""),
		}
	if not world.event_flag_active(EVENT_CINNABAR_ROCKS_CLEARED):
		return {
			"ok": false, "path": path,
			"reason": "Route20ClearRocksCallback did not run",
		}

	var ashore: Dictionary = _walk_cell_resolving(
		world, ROUTE_20_LANDING, save, random, data, true
	)
	path.append({
		"step": "route_20_landfall",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": ashore.get("encounters", []),
	})
	if not bool(ashore.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "landing on Route 20 failed: %s" % ashore.get("reason", ""),
		}

	var into_gym: Dictionary = _warp_chain(world, save, random, data, [SEAFOAM_GYM_DOOR])
	if not bool(into_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Seafoam Gym mouth failed: %s" % into_gym.get("reason", ""),
		}

	var blaine: Dictionary = _talk_to(
		world, BLAINE_FACE, Gen2WorldSprite.FACING_UP, save, random, data
	)
	var badge: int = Gen2WorldState.badge_flag(
		BADGE_VOLCANO, Gen2WorldState.is_crystal_profile(data)
	)
	path.append({
		"step": "seafoam_gym_blaine",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"volcano_badge": world.state.is_engine_flag_active(badge),
		"beat_blaine": world.event_flag_active(EVENT_BEAT_BLAINE),
		# `appear SEAFOAMGYM_GYM_GUIDE` is a clearevent on the guide's own hide
		# flag, and it sits on the branch only a won battle reaches.
		"gym_guide_hidden": world.event_flag_active(EVENT_SEAFOAM_GYM_GYM_GUIDE),
		"encounters": blaine.get("encounters", []),
		"run": blaine.get("run", {}),
	})
	if not bool(blaine.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Blaine did not finish: %s" % blaine.get("reason", ""),
		}
	if not world.state.is_engine_flag_active(badge):
		return {"ok": false, "path": path, "reason": "ENGINE_VOLCANOBADGE was not set"}
	return _viridian_leg(world, save, random, data, path)


## Seafoam Gym back up the coast to Viridian Gym and the Earth Badge.
##
## The way back is the way down reversed, water included: Route 20's east shore,
## Cinnabar, Route 21 and Pallet's own pond, then three connections north. The
## gym at the end has no puzzle and no trainer in it. Both its objects carry
## EVENT_VIRIDIAN_GYM_BLUE as their hide flag, so before Cinnabar the building is
## empty and after it Blue is simply standing there.
func _viridian_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var out_of_gym: Dictionary = _warp_chain(world, save, random, data, [SEAFOAM_GYM_EXIT])
	if not bool(out_of_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving Seafoam Gym failed: %s" % out_of_gym.get("reason", ""),
		}
	var boarded: Dictionary = _surf_at(
		world, ROUTE_20_SURF_APPROACH, Gen2WorldSprite.FACING_RIGHT, save, random, data
	)
	if not bool(boarded.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 20's surf entry failed: %s" % boarded.get("reason", ""),
		}

	var northbound: Array = [
		{"step": "cinnabar_return", "direction": "west", "number": CINNABAR_ISLAND_NUMBER},
		{"step": "route_21_northbound", "direction": "north", "number": ROUTE_21_NUMBER},
		{"step": "pallet_return", "direction": "north", "number": PALLET_TOWN_NUMBER,
			"group": PALLET_GROUP, "ashore": PALLET_LANDING},
	]
	for leg: Dictionary in northbound:
		var surfed: Dictionary = _walk_connection_resolving(
			world, String(leg["direction"]), int(leg.get("group", SEAFOAM_GROUP)),
			int(leg["number"]), save, random, data, true
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": leg["step"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": surfed.get("encounters", []),
			"run": entry,
		})
		if not bool(surfed.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the surf to %s failed: %s" % [leg["step"], surfed.get("reason", "")],
			}
		if leg.has("ashore"):
			var ashore: Dictionary = _walk_cell_resolving(
				world, leg["ashore"], save, random, data, true
			)
			if not bool(ashore.get("ok", false)):
				return {
					"ok": false, "path": path,
					"reason": "landing on %s failed: %s" % [
						leg["ashore"], ashore.get("reason", ""),
					],
				}

	for leg: Dictionary in [
		{"step": "route_1_northbound", "group": PALLET_GROUP, "number": ROUTE_1_NUMBER},
		{"step": "viridian_return", "group": ROUTE_2_GROUP, "number": VIRIDIAN_CITY_NUMBER},
	]:
		var walked: Dictionary = _walk_connection_resolving(
			world, "north", int(leg["group"]), int(leg["number"]), save, random, data
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": leg["step"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the walk to %s failed: %s" % [leg["step"], walked.get("reason", "")],
			}

	var into_gym: Dictionary = _warp_chain(world, save, random, data, [VIRIDIAN_GYM_DOOR])
	if not bool(into_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Viridian Gym door failed: %s" % into_gym.get("reason", ""),
		}

	var blue: Dictionary = _talk_to(
		world, BLUE_GYM_FACE, Gen2WorldSprite.FACING_UP, save, random, data
	)
	var badge: int = Gen2WorldState.badge_flag(
		BADGE_EARTH, Gen2WorldState.is_crystal_profile(data)
	)
	path.append({
		"step": "viridian_gym_blue",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"earth_badge": world.state.is_engine_flag_active(badge),
		"beat_blue": world.event_flag_active(EVENT_BEAT_BLUE),
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
		"encounters": blue.get("encounters", []),
		"run": blue.get("run", {}),
	})
	if not bool(blue.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Blue did not finish: %s" % blue.get("reason", ""),
		}
	if not world.state.is_engine_flag_active(badge):
		return {"ok": false, "path": path, "reason": "ENGINE_EARTHBADGE was not set"}
	return _mt_silver_leg(world, save, random, data, path)


## Viridian Gym to Red, which is Oak's errand and then a walk west.
##
## The sixteenth badge is what opens this leg and Oak is what spends it:
## `maps/OaksLab.asm` takes `.OpenMtSilver` only on `ifequal NUM_BADGES`, so the
## walk goes south to Pallet before it goes west. That is not a courtesy call.
## The Victory Road Gate is three regions joined by two single cells and a black
## belt stands in each, so EVENT_OPENED_MT_SILVER is the one thing that joins
## the corridor to the Route 28 arm, exactly as EVENT_FOUGHT_SNORLAX joins it to
## the Route 22 arm the leg arrives through. `tools/checks/mt_silver.gd` pins
## all four combinations.
##
## Red himself is the route's second presentation boundary: his script ends on
## `credits`, which commits nothing and emits one event, the way `halloffame`
## does. `disappear` then sets EVENT_RED_IN_MT_SILVER again, so the room the
## Hall of Fame opened closes behind the walk.
func _mt_silver_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var out_of_gym: Dictionary = _warp_chain(world, save, random, data, [VIRIDIAN_GYM_EXIT])
	if not bool(out_of_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving Viridian Gym failed: %s" % out_of_gym.get("reason", ""),
		}

	for leg: Dictionary in [
		{"step": "route_1_southbound", "group": PALLET_GROUP, "number": ROUTE_1_NUMBER},
		{"step": "pallet_town_return", "group": PALLET_GROUP, "number": PALLET_TOWN_NUMBER},
	]:
		var walked: Dictionary = _walk_connection_resolving(
			world, "south", int(leg["group"]), int(leg["number"]), save, random, data
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": leg["step"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the walk to %s failed: %s" % [leg["step"], walked.get("reason", "")],
			}

	var oak: Dictionary = _oaks_lab_errand(world, save, random, data, path)
	if not bool(oak.get("ok", false)):
		return oak

	for leg: Dictionary in [
		{"step": "route_1_northbound", "direction": "north",
			"group": PALLET_GROUP, "number": ROUTE_1_NUMBER},
		{"step": "viridian_northbound", "direction": "north",
			"group": ROUTE_2_GROUP, "number": VIRIDIAN_CITY_NUMBER},
		{"step": "route_22_westbound", "direction": "west",
			"group": ROUTE_2_GROUP, "number": ROUTE_22_NUMBER},
	]:
		var walked: Dictionary = _walk_connection_resolving(
			world, String(leg["direction"]), int(leg["group"]), int(leg["number"]),
			save, random, data
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": leg["step"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the walk to %s failed: %s" % [leg["step"], walked.get("reason", "")],
			}

	var through_gate: Dictionary = _warp_chain(
		world, save, random, data, [ROUTE_22_GATE_DOOR, GATE_WEST_DOOR]
	)
	path.append({
		"step": "victory_road_gate_west_arm",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"opened_mt_silver": world.event_flag_active(EVENT_OPENED_MT_SILVER),
		"fought_snorlax": world.event_flag_active(EVENT_FOUGHT_SNORLAX),
	})
	if not bool(through_gate.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the gate's west arm failed: %s" % through_gate.get("reason", ""),
		}

	var westbound: Dictionary = _walk_connection_resolving(
		world, "west", SILVER_GROUP, SILVER_CAVE_OUTSIDE_NUMBER, save, random, data
	)
	var outside_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "silver_cave_outside",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"flypoint": _engine_flag_set(world, data, ENGINE_FLYPOINT_SILVER_CAVE),
		"encounters": westbound.get("encounters", []),
		"run": outside_entry,
	})
	if not bool(westbound.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk onto Silver Cave Outside failed: %s" % westbound.get("reason", ""),
		}
	if not _engine_flag_set(world, data, ENGINE_FLYPOINT_SILVER_CAVE):
		return {
			"ok": false, "path": path,
			"reason": "SilverCaveOutsideFlypointCallback did not run",
		}

	var healed: Dictionary = _silver_cave_heal(world, save, random, data, path)
	if not bool(healed.get("ok", false)):
		return healed

	return _silver_cave_rooms(world, save, random, data, path)


## Oak's lab, which is the only thing that opens Mt. Silver. The sixteen-badge
## branch sets EVENT_OPENED_MT_SILVER and then falls into `.CheckPokedex`, whose
## `special ProfOaksPCBoot` is presentation and writes nothing.
func _oaks_lab_errand(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var into_lab: Dictionary = _warp_chain(world, save, random, data, [OAKS_LAB_DOOR])
	if not bool(into_lab.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Oak's lab door failed: %s" % into_lab.get("reason", ""),
		}
	var badges: int = world.state.badge_count(Gen2WorldState.is_crystal_profile(data))
	var oak: Dictionary = _talk_to(
		world, OAK_FACE, Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "oaks_lab_opens_mt_silver",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"badge_count": badges,
		"talked_to_oak": world.event_flag_active(EVENT_TALKED_TO_OAK_IN_KANTO),
		"opened_mt_silver": world.event_flag_active(EVENT_OPENED_MT_SILVER),
		"run": oak.get("run", {}),
	})
	if not bool(oak.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Oak did not finish: %s" % oak.get("reason", ""),
		}
	if badges != 16:
		return {
			"ok": false, "path": path,
			"reason": "Oak was asked with %d badges, not sixteen" % badges,
		}
	if not world.event_flag_active(EVENT_OPENED_MT_SILVER):
		return {"ok": false, "path": path, "reason": "EVENT_OPENED_MT_SILVER was not set"}
	var out_of_lab: Dictionary = _warp_chain(world, save, random, data, [OAKS_LAB_EXIT])
	if not bool(out_of_lab.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Oak's lab exit failed: %s" % out_of_lab.get("reason", ""),
		}
	return {"ok": true}


## The last heal before Red. The nurse stands behind a counter the walk cannot
## step onto, so the approach cell is placed rather than walked to.
func _silver_cave_heal(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var into_center: Dictionary = _warp_chain(
		world, save, random, data, [SILVER_CAVE_POKECENTER_DOOR]
	)
	if not bool(into_center.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Mt. Silver Pokecenter door failed: %s" % into_center.get("reason", ""),
		}
	_mirror_party(world, save)
	for mon: Gen2SaveMon in save.party:
		mon.hp = 1
	world.player_cell = SILVER_CAVE_NURSE_STAND
	world.player_facing = Gen2WorldSprite.FACING_UP
	var nurse: Dictionary = _drain_story(
		world, world.interact(), save, random, data, true
	)
	path.append({
		"step": "silver_cave_pokecenter_nurse",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": nurse,
		"party_hp_after": _party_hp(save),
	})
	if not bool(nurse.get("terminal", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Mt. Silver nurse did not finish: %s" % nurse.get("reason", ""),
		}
	var out_of_center: Dictionary = _warp_chain(
		world, save, random, data, [SILVER_CAVE_POKECENTER_EXIT]
	)
	if not bool(out_of_center.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Mt. Silver Pokecenter exit failed: %s" % out_of_center.get("reason", ""),
		}
	return {"ok": true}


## The three rooms and Red. Every room is one region, so each ladder is walked
## to directly; `tools/checks/mt_silver.gd` is what says so.
func _silver_cave_rooms(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	for leg: Dictionary in [
		{"step": "silver_cave_room_1", "cell": SILVER_CAVE_MOUTH},
		{"step": "silver_cave_room_2", "cell": SILVER_CAVE_ROOM_1_LADDER},
		{"step": "silver_cave_room_3", "cell": SILVER_CAVE_ROOM_2_LADDER},
	]:
		var climbed: Dictionary = _warp_chain(world, save, random, data, [leg["cell"]])
		path.append({
			"step": leg["step"],
			"map": _map_value(world),
			"cell": _cell_value(world),
		})
		if not bool(climbed.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the ladder to %s failed: %s" % [
					leg["step"], climbed.get("reason", ""),
				],
			}

	_mirror_party(world, save)
	var red: Dictionary = _talk_to(
		world, RED_FACE, Gen2WorldSprite.FACING_UP, save, random, data
	)
	var run: Dictionary = red.get("run", {})
	path.append({
		"step": "silver_cave_red",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"battles": run.get("battles", []),
		"credits": int(run.get("credits", 0)),
		"red_hidden_again": world.event_flag_active(EVENT_RED_IN_MT_SILVER),
		"party_hp_after": _party_hp(save),
		"encounters": red.get("encounters", []),
		"run": run,
	})
	if not bool(red.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Red did not finish: %s" % red.get("reason", ""),
		}
	var battles: Array = run.get("battles", [])
	if battles.size() != 1 \
		or int((battles[0] as Dictionary).get("trainer_class", 0)) != TRAINER_CLASS_RED:
		return {
			"ok": false, "path": path,
			"reason": "Red's script fought %s, not one battle as class %d" % [
				JSON.stringify(battles), TRAINER_CLASS_RED,
			],
		}
	if int(run.get("credits", 0)) != 1:
		return {
			"ok": false, "path": path,
			"reason": "Red's script emitted %d credits events, not one" % int(
				run.get("credits", 0)
			),
		}
	# disappear sets the hide flag the Hall of Fame cleared, so the room closes
	# behind the walk the way the cartridge closes it.
	if not world.event_flag_active(EVENT_RED_IN_MT_SILVER):
		return {"ok": false, "path": path, "reason": "EVENT_RED_IN_MT_SILVER was not set again"}
	return {"ok": true}


## Cerulean to the Power Plant and back, which is the river both ways.
func _power_plant_visit(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
	step: String,
) -> Dictionary:
	var out: Dictionary = _power_plant_crossing(world, save, random, data, path, false)
	if not bool(out.get("ok", false)):
		return out
	var manager: Dictionary = _talk_to(
		world, POWER_PLANT_MANAGER_FACE, Gen2WorldSprite.FACING_UP, save, random, data
	)
	# The manager's first talk arms the guard's phone call on (5,12), and the walk
	# back toward the door crosses it, so the scene is drained on the way out
	# rather than aimed at. `scene` is `SCENE_POWERPLANT_GUARD_GETS_PHONE_CALL`
	# while it is still pending and back to NOOP once it has run.
	path.append({
		"step": "power_plant_%s" % step,
		"map": _map_value(world),
		"cell": _cell_value(world),
		"met_manager": world.event_flag_active(EVENT_MET_MANAGER_AT_POWER_PLANT),
		"returned": world.event_flag_active(EVENT_RETURNED_MACHINE_PART),
		"power_restored": world.event_flag_active(EVENT_RESTORED_POWER_TO_KANTO),
		"scene": world.state.map_scene(CERULEAN_GROUP, POWER_PLANT_NUMBER),
		"run": manager,
	})
	if not bool(manager.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Power Plant manager did not finish: %s" % manager.get("reason", ""),
		}
	var home: Dictionary = _power_plant_crossing(world, save, random, data, path, true)
	if not bool(home.get("ok", false)):
		return home
	if world.state.map_scene(CERULEAN_GROUP, POWER_PLANT_NUMBER) != 0:
		return {
			"ok": false, "path": path,
			"reason": "the guard's phone call is still pending after the walk out",
		}
	return {"ok": true}


## The crossing itself, in either direction. Outbound it is the east connection,
## Route 9's tree, its shore, the river south into Route 10 North's lake, the
## landing beside the plant and the plant's own door; the return is that
## reversed, with the tree cut again because the map load regrew it.
func _power_plant_crossing(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
	returning: bool,
) -> Dictionary:
	var label: String = "return" if returning else "outbound"
	if returning:
		var outside: Dictionary = _warp_chain(world, save, random, data, [POWER_PLANT_EXIT])
		if not bool(outside.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "leaving the Power Plant failed: %s" % outside.get("reason", ""),
			}

	# Each leg is an optional surf entry, the connection walk, an optional landing
	# on the far side, then an optional cut and an optional surf entry for the
	# leg after it. The tree is cut from whichever bank the crossing arrives on.
	var legs: Array = [
		{"direction": "east", "number": ROUTE_9_NUMBER, "water": false,
			"cut": ROUTE_9_CUT_EAST_APPROACH, "cut_facing": Gen2WorldSprite.FACING_RIGHT,
			"surf": ROUTE_9_SHORE, "surf_facing": Gen2WorldSprite.FACING_UP},
		{"direction": "south", "number": ROUTE_10_NORTH_NUMBER, "water": true,
			"ashore": POWER_PLANT_SHORE},
	]
	if returning:
		legs = [
			{"direction": "north", "number": ROUTE_9_NUMBER, "water": true,
				"enter": POWER_PLANT_SHORE, "enter_facing": Gen2WorldSprite.FACING_DOWN,
				"ashore": ROUTE_9_SHORE,
				"cut": ROUTE_9_CUT_WEST_APPROACH, "cut_facing": Gen2WorldSprite.FACING_LEFT},
			{"direction": "west", "number": CERULEAN_CITY_NUMBER, "water": false},
		]
	for leg: Dictionary in legs:
		if leg.has("enter"):
			var boarded: Dictionary = _surf_at(
				world, leg["enter"], int(leg["enter_facing"]), save, random, data
			)
			if not bool(boarded.get("ok", false)):
				return {
					"ok": false, "path": path,
					"reason": "the %s surf entry (%s) failed: %s" % [
						leg["enter"], label, boarded.get("reason", ""),
					],
				}
		var walked: Dictionary = _walk_connection_resolving(
			world, String(leg["direction"]), CERULEAN_GROUP, int(leg["number"]),
			save, random, data, bool(leg["water"])
		)
		var _entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": "power_plant_%s_%s" % [label, leg["direction"]],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the %s crossing (%s) failed: %s" % [
					leg["direction"], label, walked.get("reason", ""),
				],
			}
		if leg.has("ashore"):
			# The far side of a surfed connection is still water. One water-only
			# walk to a named shore cell ends on .ExitWater.
			var ashore: Dictionary = _walk_cell_resolving(
				world, leg["ashore"], save, random, data, true
			)
			if not bool(ashore.get("ok", false)):
				return {
					"ok": false, "path": path,
					"reason": "landing on %s (%s) failed: %s" % [
						leg["ashore"], label, ashore.get("reason", ""),
					],
				}
		if leg.has("cut"):
			var tree: Dictionary = _cut_at(
				world, leg["cut"], int(leg["cut_facing"]), save, random, data
			)
			if not bool(tree.get("ok", false)):
				return {
					"ok": false, "path": path,
					"reason": "Route 9's tree (%s) failed: %s" % [label, tree.get("reason", "")],
				}
		if leg.has("surf"):
			var entered: Dictionary = _surf_at(
				world, leg["surf"], int(leg["surf_facing"]), save, random, data
			)
			if not bool(entered.get("ok", false)):
				return {
					"ok": false, "path": path,
					"reason": "the %s surf entry (%s) failed: %s" % [
						leg["surf"], label, entered.get("reason", ""),
					],
				}
	if returning:
		return {"ok": true}
	var door: Dictionary = _warp_chain(world, save, random, data, [POWER_PLANT_DOOR])
	if not bool(door.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Power Plant door failed: %s" % door.get("reason", ""),
		}
	return {"ok": true}


## Route 24's grunt, who names the pool, and Route 25's date, whose own
## `clearevent` is the only thing that puts Misty in her gym.
func _route_24_and_25(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var to_24: Dictionary = _walk_connection_resolving(
		world, "north", CERULEAN_GROUP, ROUTE_24_NUMBER, save, random, data
	)
	var _entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	if not bool(to_24.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk north to Route 24 failed: %s" % to_24.get("reason", ""),
		}
	var grunt: Dictionary = _talk_to(
		world, ROUTE_24_ROCKET_FACE, Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "route_24_rocket",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": grunt,
	})
	if not bool(grunt.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Route 24 grunt did not finish: %s" % grunt.get("reason", ""),
		}

	var to_25: Dictionary = _walk_connection_resolving(
		world, "north", CERULEAN_GROUP, ROUTE_25_NUMBER, save, random, data
	)
	var _r25: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	if not bool(to_25.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the walk north to Route 25 failed: %s" % to_25.get("reason", ""),
		}
	var date: Dictionary = _coord_event_step(
		world, ROUTE_25_DATE_APPROACH, ROUTE_25_DATE_COORD, save, random, data
	)
	path.append({
		"step": "route_25_misty_date",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"gym_trainers_hidden": world.event_flag_active(EVENT_TRAINERS_IN_CERULEAN_GYM),
		"run": date,
	})
	if not bool(date.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Misty date did not finish: %s" % date.get("reason", ""),
		}
	if world.event_flag_active(EVENT_TRAINERS_IN_CERULEAN_GYM):
		return {"ok": false, "path": path, "reason": "the date did not empty the gym's hide flag"}

	for number: int in [ROUTE_24_NUMBER, CERULEAN_CITY_NUMBER]:
		var walked: Dictionary = _walk_connection_resolving(
			world, "south", CERULEAN_GROUP, number, save, random, data
		)
		var _back: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "the walk back south failed: %s" % walked.get("reason", ""),
			}
	return {"ok": true}


## The pool the Route 24 grunt names: a BGEVENT_ITEM whose own cell is water, so
## it is faced from the bank above rather than stood on.
func _cerulean_machine_part(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var into_gym: Dictionary = _warp_chain(world, save, random, data, [CERULEAN_GYM_DOOR])
	if not bool(into_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the gym door failed: %s" % into_gym.get("reason", ""),
		}
	var found: Dictionary = _talk_to(
		world, MACHINE_PART_APPROACH, Gen2WorldSprite.FACING_DOWN, save, random, data
	)
	path.append({
		"step": "cerulean_gym_machine_part",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"in_bag": int(world.state.items().get(ITEM_MACHINE_PART, 0)),
		"run": found,
	})
	if not bool(found.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the hidden machine part did not finish: %s" % found.get("reason", ""),
		}
	if int(world.state.items().get(ITEM_MACHINE_PART, 0)) < 1:
		return {"ok": false, "path": path, "reason": "the machine part did not reach the bag"}
	var out_of_gym: Dictionary = _warp_chain(world, save, random, data, [CERULEAN_GYM_EXIT])
	if not bool(out_of_gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving the gym with the part failed: %s" % out_of_gym.get("reason", ""),
		}
	return {"ok": true}


## Runs the coord event on [param cell], whichever way the walk gets there.
##
## Open work item 15: a resolving walk aimed at a live coord event re-dispatches
## its own target and never settles, so the target is [param approach] and the
## last step is a plain move_result(). But the walk to that approach can cross
## the event's own cell first and resolve it on the way, which is what both of
## this leg's coord events do, so a walk that already ran something counts.
func _coord_event_step(
	world: Gen2WorldAPI,
	approach: Vector2i,
	cell: Vector2i,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, approach, save, random, data)
	if not bool(walked.get("ok", false)):
		return walked
	var resolved: Array = walked.get("encounters", [])
	if world.player_cell == cell or not resolved.is_empty():
		return {"ok": true, "on_the_way": true, "encounters": resolved}
	var direction: Vector2i = cell - world.player_cell
	if absi(direction.x) + absi(direction.y) != 1:
		return {"ok": false, "reason": "%s does not neighbour %s" % [approach, cell]}
	var moved: Dictionary = world.move_result(direction)
	if not bool(moved.get("ok", false)):
		return {"ok": false, "reason": "the step onto %s was refused" % cell}
	var run: Dictionary = _drain_story(
		world, _dispatch_after_step(world), save, random, data, true
	)
	return {"ok": bool(run.get("terminal", false)), "reason": run.get("reason", ""), "run": run}


## The gangway. `FastShip1FSailor1Script`'s `.Arrived` branch needs
## EVENT_FAST_SHIP_HAS_ARRIVED and DESTINATION_OLIVINE clear, which the Olivine
## boarding cleared; it warps to Vermilion Port itself after `setmapscene
## VERMILION_PORT, SCENE_VERMILIONPORT_LEAVE_SHIP`, so the deferred landfall
## scene runs inside the same drain.
func _ss_aqua_disembark(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var to_deck: Dictionary = _warp_chain(
		world, save, random, data, [SHIP_GRANDPA_CABIN_DOOR]
	)
	if not bool(to_deck.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the grandpa cabin door failed: %s" % to_deck.get("reason", ""),
		}
	var talked: Dictionary = _talk_to(
		world, SHIP_1F_SAILOR_FACE, Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "ss_aqua_vermilion_landfall",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"first_time": world.event_flag_active(EVENT_FAST_SHIP_FIRST_TIME),
		"run": talked,
	})
	if not bool(talked.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the gangway sailor did not finish: %s" % talked.get("reason", ""),
		}
	if world.map_id() != Vector2i(FAST_SHIP_GROUP, VERMILION_PORT_NUMBER):
		return {
			"ok": false, "path": path,
			"reason": "the crossing ended on %s, not Vermilion Port" % [_map_value(world)],
		}
	if not world.event_flag_active(EVENT_FAST_SHIP_FIRST_TIME):
		return {"ok": false, "path": path, "reason": "the landfall scene did not run"}
	return {"ok": true}


## _push_boulder_at() for a boulder that may land on a `stonetable` pit: the
## fall script is queued by the push that commits the cell, and the boulder
## needs its own slide finished before the next push can reach it.
func _push_boulder_run(
	world: Gen2WorldAPI,
	approach: Vector2i,
	direction: Vector2i,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var pushed: Dictionary = _push_boulder_at(world, approach, direction, save, random, data)
	if not bool(pushed.get("ok", false)):
		return pushed
	var fall: Dictionary = _drain_story(
		world, world.run_event_queue(false), save, random, data
	)
	if not bool(fall.get("terminal", true)):
		return {"ok": false, "reason": "fall script did not finish: %s" % fall.get("reason", "")}
	_settle_object_steps(world, random)
	return pushed


## Spends hardware frames until no object is mid-step. A pushed boulder slides
## for STEP_FRAMES_BOULDER_PUSH frames and refuses a second push until it stands
## again, so this has to spend the frames rather than ask for them at once.
func _settle_object_steps(world: Gen2WorldAPI, random: RandomNumberGenerator) -> void:
	for _frame: int in OBJECT_STEP_FRAME_BUDGET:
		var stepping: bool = false
		for object: Gen2WorldObject in world.objects:
			if object.is_stepping():
				stepping = true
				break
		if not stepping:
			return
		world.advance_object_steps_frame(random)


## Mahogany Town east to Blackthorn City, on the same world, state and save.
## Starts in the town, since the Radio Tower leg before it left the gym.
##
## Route 44 carries seven trainers and no scripted gate, so the leg is a walk
## the trainers interrupt rather than a sequence of errands. Its one warp is the
## Ice Path door at (56,7) (`maps/Route44.asm`); the east connection to
## Blackthorn exists in `data/maps/attributes.asm` but the cartridge's own way
## through is the cave.
##
## Ice Path 1F is the only floor on the way: its second warp is Blackthorn's own
## (`maps/IcePath1F.asm` warp 2 to BLACKTHORN_CITY 7), so the `stonetable`
## boulder puzzle on B1F is beside the route rather than across it. The floor is
## COLL_ICE, which is LAND_TILE, so the walk crosses it without the source's
## sliding; sliding only ever removes choices, so nothing reachable with it is
## unreachable here.
##
## Appends to [param path] and answers only ok or the failure.
func _blackthorn_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var to_route_44: Dictionary = _walk_connection_resolving(
		world, "east", 2, 6, save, random, data
	)
	var route_44_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "mahogany_to_route_44",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": to_route_44.get("encounters", []),
		"run": route_44_entry,
	})
	if not bool(to_route_44.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Mahogany to Route 44 failed: %s" % to_route_44.get("reason", ""),
		}

	# The Ice Path door, then the cave itself. Every trainer with a sight line
	# onto the way there answers first, which is what the resolving walk is for.
	for door: Dictionary in ICE_PATH_DOORS:
		var walked: Dictionary = _warp_walk(
			world, door["cell"], save, random, data
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": String(door["step"]),
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s failed: %s" % [door["step"], walked.get("reason", "")],
			}
		if not bool(door.get("hm07", false)):
			continue
		# HM07 is an item ball on the 1F region the Route 44 door opens into,
		# and nothing else in either game gives WATERFALL. It is taken in
		# passing, before the staircase the next door takes.
		var picked_up: Dictionary = _talk_to(
			world, HM07_APPROACH, Gen2WorldSprite.FACING_RIGHT, save, random, data
		)
		path.append({
			"step": "ice_path_1f_hm07",
			"map": _map_value(world),
			"cell": _cell_value(world),
			"run": picked_up.get("run", {}),
			"items": _named_items(data, world.state.items()),
		})
		if not bool(picked_up.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "HM07 pickup failed: %s" % picked_up.get("reason", ""),
			}
		if world.state.item_quantity(ITEM_HM_WATERFALL) <= 0:
			return {"ok": false, "path": path, "reason": "HM07 did not reach the bag"}

	path.append({
		"step": "blackthorn_city_arrival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"party": _party_species(save),
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
	})
	return {"ok": true}


## _talk_to() for a target the player has to reach across water. The frontier
## stays on water so the plan cannot step ashore partway and stop surfing.
func _talk_to_on_water(
	world: Gen2WorldAPI,
	cell: Vector2i,
	facing: int,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, cell, save, random, data, true)
	if not bool(walked.get("ok", false)):
		return walked
	world.player_facing = facing
	var run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	return {
		"ok": bool(run.get("terminal", false)),
		"reason": run.get("reason", ""),
		"run": run,
	}


## The lighthouse floors reached by ladder on the way up and by hole on the way
## down, from Olivine City's door back to it. [param phase] is "first" for
## Jasmine's SecretPotion errand and "cure" for the visit that carries it.
##
## The climb is not the obvious one: 4F's ladder at (3,5) reaches the half of 5F
## that cannot see the 6F stairs at (9,15), so the route drops back to 3F
## through the hole at 4F (9,3) and climbs the other shaft.
func _lighthouse_visit(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
	phase: String,
) -> Dictionary:
	var door: Dictionary = _warp_walk(world, Vector2i(29, 27), save, random, data)
	if not bool(door.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Olivine Lighthouse door unreachable: %s" % door.get("reason", ""),
		}
	var _entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)

	var climb: Dictionary = _lighthouse_shaft(world, save, random, data, [
		Vector2i(3, 11), Vector2i(5, 3), Vector2i(13, 3), Vector2i(9, 3),
		Vector2i(9, 5), Vector2i(9, 7), Vector2i(9, 15),
	])
	if not bool(climb.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "lighthouse climb (%s) failed: %s" % [phase, climb.get("reason", "")],
		}

	# OlivineLighthouseJasmine answers checkitem SECRETPOTION first, so the same
	# interaction explains Amphy's sickness on the first visit and cures it on
	# the second. The cure runs FadeOutToWhite and FadeInFromWhite either side of
	# the Ampharos cry.
	var jasmine: Dictionary = _talk_to(
		world, Vector2i(8, 9), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "olivine_lighthouse_jasmine_%s" % phase,
		"map": _map_value(world),
		"cell": _cell_value(world),
		"floors": climb.get("floors", []),
		"run": jasmine.get("run", {}),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(jasmine.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "lighthouse Jasmine (%s) failed: %s" % [phase, jasmine.get("reason", "")],
		}

	var descent: Dictionary = _lighthouse_shaft(world, save, random, data, [
		Vector2i(16, 5), Vector2i(16, 7), Vector2i(16, 9), Vector2i(16, 11),
		Vector2i(16, 13), Vector2i(10, 17),
	])
	if not bool(descent.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "lighthouse descent (%s) failed: %s" % [phase, descent.get("reason", "")],
		}
	return {"ok": true}


## Walks each cell in [param cells] on the floor it belongs to and takes the
## warp there, draining the arrival callbacks between floors.
func _lighthouse_shaft(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	cells: Array,
) -> Dictionary:
	var floors: Array = []
	for cell: Vector2i in cells:
		var taken: Dictionary = _warp_walk(world, cell, save, random, data)
		if not bool(taken.get("ok", false)):
			return {
				"ok": false, "floors": floors,
				"reason": "warp at %s unreachable: %s" % [cell, taken.get("reason", "")],
			}
		var _entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		floors.append(_map_value(world))
	return {"ok": true, "floors": floors}


## maps/OlivineCafe.asm's sailor at (4,3), who hands over HM04 behind
## EVENT_GOT_HM04_STRENGTH. The cafe is Olivine City warp 7 at (7,21).
##
## The HM is then taught through Gen2WorldPartyHost.teach_tm_hm(), the same
## transaction the pack's own USE reaches, so the route learns STRENGTH the way a
## player does rather than writing a move slot behind the game's back.
func _olivine_cafe_hm04(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var door: Dictionary = _warp_walk(world, Vector2i(7, 21), save, random, data)
	if not bool(door.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Olivine Cafe door unreachable: %s" % door.get("reason", ""),
		}
	var _cafe_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var sailor: Dictionary = _talk_to(
		world, Vector2i(4, 4), Gen2WorldSprite.FACING_UP, save, random, data
	)
	var taught: Dictionary = _teach_tm_hm(world, save, ITEM_HM_STRENGTH)
	_mirror_party(world, save)
	path.append({
		"step": "olivine_cafe_hm04_strength",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": sailor.get("run", {}),
		"items": _named_items(data, world.state.items()),
		"strength_taught": taught,
		"party_moves": _party_moves(save),
	})
	if not bool(sailor.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "HM04 handoff failed: %s" % sailor.get("reason", ""),
		}
	if not world.state.items().has(ITEM_HM_STRENGTH):
		return {"ok": false, "path": path, "reason": "HM04 did not reach the bag"}
	if not bool(taught.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "teaching STRENGTH failed: %s" % taught.get("reason", ""),
		}
	var leaving: Dictionary = _warp_step(world, 1, 14)
	if not bool(leaving.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Olivine Cafe exit warp failed"}
	var _city_again: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	return {"ok": true}


## Cianwood City's gym, whose only corridor is walled by three
## SPRITEMOVEDATA_STRENGTH_BOULDER objects at (3,7), (4,7) and (5,7).
##
## Row 7 is the sole link between the entrance half and Chuck, its ends are walls
## at x=2 and x=6, and row 5 above it opens only at (4,5) and (5,5), the second of
## which a Black Belt stands on for good. So no single push opens it: pushing any
## boulder north just moves the wall up a row. The corridor opens by clearing
## (3,7) and (5,7) north first, then pushing the middle boulder sideways into the
## cell (3,7) left behind, which leaves (4,6) and (4,5) free above the freed
## (4,7). A state-space search over player cell plus boulder cells finds no
## shorter answer.
##
## Chuck himself needs no Strength: his script throws BOULDER1 aside with an
## applymovement of its own before the battle.
func _storm_badge_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var door: Dictionary = _warp_walk(world, Vector2i(8, 43), save, random, data)
	if not bool(door.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Cianwood Gym door unreachable: %s" % door.get("reason", ""),
		}
	var gym_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	# The boulder at (4,7), faced from (4,8), is the first one the walk meets, so
	# it is the one that runs AskStrengthScript. TryStrengthOW answers 0 here
	# (party move plus Plain Badge, flag still clear), the yes/no is answered yes
	# by _drain_story, and Script_UsedStrength sets the flag.
	var asked: Dictionary = _talk_to(
		world, Vector2i(4, 8), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "cianwood_gym_ask_strength",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": gym_entry.get("statuses", []),
		"run": asked.get("run", {}),
		"strength_active": world.strength_active(),
	})
	if not bool(asked.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "AskStrengthScript failed: %s" % asked.get("reason", ""),
		}
	if not world.strength_active():
		return {"ok": false, "path": path, "reason": "Strength did not become active"}

	var pushes: Array = []
	for push: Dictionary in [
		{"approach": Vector2i(3, 8), "direction": Vector2i.UP},
		{"approach": Vector2i(5, 8), "direction": Vector2i.UP},
		# The middle boulder goes sideways into the cell the first push freed.
		{"approach": Vector2i(5, 7), "direction": Vector2i.LEFT},
	]:
		var moved: Dictionary = _push_boulder_at(
			world, push["approach"], push["direction"], save, random, data
		)
		pushes.append(moved)
		if not bool(moved.get("ok", false)):
			path.append({
				"step": "cianwood_gym_boulders",
				"map": _map_value(world),
				"cell": _cell_value(world),
				"pushes": pushes,
			})
			return {
				"ok": false, "path": path,
				"reason": "boulder push from %s failed: %s" % [
					push["approach"], moved.get("reason", ""),
				],
			}
	path.append({
		"step": "cianwood_gym_boulders",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"pushes": pushes,
	})

	_mirror_party(world, save)
	var chuck: Dictionary = _talk_to(
		world, Vector2i(4, 2), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "cianwood_gym_chuck",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": chuck.get("run", {}),
		"badge_count": world.state.badge_count(Gen2WorldState.is_crystal_profile(data)),
		"engine_flags": world.state.engine_flags(),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(chuck.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Chuck failed: %s" % chuck.get("reason", ""),
		}
	if not world.state.is_engine_flag_active(Gen2WorldState.badge_flag(
		BADGE_STORM, Gen2WorldState.is_crystal_profile(data)
	)):
		return {"ok": false, "path": path, "reason": "ENGINE_STORMBADGE was not set"}

	var leaving: Dictionary = _warp_step(world, 22, 3)
	if not bool(leaving.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Cianwood Gym exit warp failed"}
	var _city_again: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	return {"ok": true}


## Walks to [param approach] and steps into [param direction], which is a push
## rather than a step because a boulder stands there. DoPlayerMovement.CheckNPC
## bumps the player on a push, so the step reports blocked and the boulder moving
## is the success signal.
func _push_boulder_at(
	world: Gen2WorldAPI,
	approach: Vector2i,
	direction: Vector2i,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, approach, save, random, data)
	if not bool(walked.get("ok", false)):
		return walked
	var result: Dictionary = world.move_result(direction)
	if not result.has("boulder_pushed"):
		return {
			"ok": false,
			"reason": "no boulder moved from %s: %s" % [
				approach, result.get("reason", "step succeeded"),
			],
		}
	var pushed: Dictionary = result["boulder_pushed"]
	return {
		"ok": true,
		"from_cell": _cell_value_from_vector(pushed["from_cell"]),
		"to_cell": _cell_value_from_vector(pushed["to_cell"]),
		"player_cell": _cell_value(world),
	}


## BlackthornMartClerkScript, talked to across its own counter.
##
## The route needs this once. Elm's aide gives five Poké Balls, Union Cave's
## Geodude costs one, and Dratini is a far lower catch rate than Geodude, so the
## four left do not land it. Blackthorn is the last town the route stands in
## before the Dragon's Den, and its stock is the cartridge's: MartBlackthorn
## sells no Poké Balls, so what the route buys is Great Balls: they are the
## cheapest ball it stocks, and the source start money buys five of them against
## two Ultra Balls.
##
## The clerk stands on (1,3) behind the `$90` counter on (2,3), so this is a
## CheckFacingObject doubled reach like the Radio Card woman's, and the buying
## itself happens inside the clerk's own `pokemart` pause rather than beside it.
func _buy_great_balls(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
	quantity: int,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(
		world, BLACKTHORN_MART_CLERK_FACE, save, random, data
	)
	if not bool(walked.get("ok", false)):
		return {"ok": false, "reason": "the mart clerk is unreachable: %s" % walked.get("reason", "")}
	world.player_facing = Gen2WorldSprite.FACING_LEFT
	var run: Dictionary = _drain_story(
		world, world.interact(), save, random, data, true, [],
		{"item": Gen2WorldPartyHost.ITEM_GREAT_BALL, "quantity": quantity}
	)
	path.append({
		"step": "blackthorn_mart_great_balls",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"balls": world.state.item_quantity(Gen2WorldPartyHost.ITEM_GREAT_BALL),
		"money": world.state.money(),
		"purchases": run.get("purchases", []),
		"run": run,
	})
	if not bool(run.get("terminal", false)):
		return {"ok": false, "reason": "the mart clerk did not finish: %s" % run.get("reason", "")}
	if world.state.item_quantity(Gen2WorldPartyHost.ITEM_GREAT_BALL) < quantity:
		return {"ok": false, "reason": "the Great Balls did not reach the bag"}
	return {"ok": true}


## Route 32's Pokemon Center for the OLD ROD, and then the shore below it for
## what the rod is here to catch.
##
## This is the route's answer to Surf and Whirlpool, and it has to be a rod
## rather than a walk. Every grass wild in reach before Route 40's south edge
## that CanLearnTMHMMove accepts for SURF is night only except Slowpoke Well's
## Slowpoke, and Slowpoke does not take WHIRLPOOL at all; the walked route runs
## on the new game's own 06:00 clock, so a night slot is not something it can
## honestly reach. Route 32's own Old Rod row is the one time-independent source
## of a mon that takes both, at Tentacool on the last threshold
## (`data/wild/fish.asm`).
##
## `Route32Pokecenter1FFishingGuruScript` gates the rod on its own yes/no and
## then `verbosegiveitem OLD_ROD`, which is what `Gen2WorldInventory.owns_rod()`
## reads back.
func _route_32_old_rod(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var into_center: Dictionary = _warp_chain(
		world, save, random, data, [ROUTE_32_POKECENTER_DOOR]
	)
	if not bool(into_center.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the Route 32 Pokemon Center door failed: %s" % into_center.get("reason", ""),
		}
	var guru: Dictionary = _talk_to(
		world, FISHING_GURU_FACE, Gen2WorldSprite.FACING_UP,
		save, random, data, [0] as Array[int]
	)
	path.append({
		"step": "route_32_fishing_guru_old_rod",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"old_rod": world.state.item_quantity(Gen2WorldInventory.ITEM_OLD_ROD) > 0,
		"run": guru.get("run", {}),
	})
	if not bool(guru.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "the fishing guru did not finish: %s" % guru.get("reason", ""),
		}
	if world.state.item_quantity(Gen2WorldInventory.ITEM_OLD_ROD) <= 0:
		return {"ok": false, "path": path, "reason": "the OLD ROD did not reach the bag"}

	var outside: Dictionary = _warp_chain(
		world, save, random, data, [ROUTE_32_POKECENTER_EXIT]
	)
	if not bool(outside.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "leaving the Route 32 Pokemon Center failed: %s" % outside.get("reason", ""),
		}

	var walked: Dictionary = _walk_cell_resolving(
		world, ROUTE_32_SHORE, save, random, data
	)
	if not bool(walked.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 32's shore is unreachable: %s" % walked.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_LEFT
	return _catch_field_move_mon(
		world, save, random, data, path,
		Gen2WorldFieldMove.MOVE_SURF, "route_32_fish_for_surf",
		Gen2WorldEncounter.METHOD_OLD_ROD
	)


## Catches something on the current map that can learn [param move], which is
## how this route gets both of the HMs its own party cannot take.
##
## Neither is optional. The starter is still unevolved by Olivine and Chikorita,
## Cyndaquil and Totodile all learn STRENGTH only after evolving, so Union Cave
## 1F's Geodude and Onix are the first catch; none of the party learns WATERFALL
## at all, so Dragon's Den B1F's Dratini is the second
## (`data/pokemon/base_stats/*.asm`, `data/wild/johto_water.asm`).
##
## The walk itself never rolls a wild encounter, so this forces one, checks the
## species against CanLearnTMHMMove and throws a Poké Ball, retrying until the
## bag runs out. Both rolls come from the route's seeded generator, so the answer
## is the same on every run.
func _catch_field_move_mon(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
	move: int,
	step: String,
	method: StringName = &"auto",
) -> Dictionary:
	var attempts: Array = []
	var caught: Dictionary = {}
	for _attempt: int in CATCH_ATTEMPTS:
		var ball: int = _best_ball(world)
		if ball <= 0:
			break
		var encounter: Dictionary = world.encounter_request(random, true, method)
		if encounter.is_empty():
			break
		var species: int = int(encounter.get("pokemon", 0))
		var level: int = int(encounter.get("level", 0))
		if not Gen2WorldTMHM.can_learn(data, species, move):
			attempts.append({"species": species, "level": level, "thrown": false})
			continue
		var wild: Gen2BattleMon = Gen2BattleMon.create(
			data, species, level, data.moves_at_level(species, level), random.randi() & 0xFFFF
		)
		# CatchMon reads the wild's current HP, and this tool simulates no wild
		# battle, the same way _drain_story() answers every trainer battle with a
		# win rather than fighting it. So the throw is made at the one HP a
		# player would have brought it to. Union Cave's Geodude lands at full HP
		# on a catch rate of 255; Dratini's is far lower and does not.
		wild.hp = 1
		var throw_result: Dictionary = Gen2WorldPartyHost.capture_wild(
			world, save, wild, ball, random, 0, false
		)
		attempts.append({
			"species": species, "level": level, "thrown": true, "ball": ball,
			"caught": bool(throw_result.get("caught", false)),
			"reason": throw_result.get("reason", ""),
		})
		if bool(throw_result.get("caught", false)):
			caught = throw_result
			break
	_mirror_party(world, save)
	path.append({
		"step": step,
		"map": _map_value(world),
		"cell": _cell_value(world),
		"attempts": attempts,
		"party": _party_species(save),
		"items": _named_items(data, world.state.items()),
	})
	if caught.is_empty():
		return {
			"ok": false, "path": path,
			"reason": "no catch that learns move %d in %d encounters" % [move, attempts.size()],
		}
	return {"ok": true}


## TeachTMHM against the first party member the machine will take, which is what
## ChooseMonToLearnTMHM leaves the player to pick. Compatibility, a known move
## and a full moveset are all real refusals, so the walk tries each slot in party
## order and reports the last reason when none of them can learn it.
func _teach_tm_hm(world: Gen2WorldAPI, save: Gen2SaveData, item: int) -> Dictionary:
	var reason: String = "no party member"
	for index: int in save.party.size():
		var result: Dictionary = Gen2WorldPartyHost.teach_tm_hm(world, save, item, index, -1, false)
		if bool(result.get("ok", false)):
			return result
		reason = String(result.get("reason", ""))
	return {"ok": false, "reason": reason}


## GetBallIndex's order in reverse: the best ball still in the bag, or -1 when
## none is. Master Balls never reach this route.
func _best_ball(world: Gen2WorldAPI) -> int:
	for ball: int in [
		Gen2WorldPartyHost.ITEM_ULTRA_BALL, Gen2WorldPartyHost.ITEM_GREAT_BALL,
		Gen2WorldPartyHost.ITEM_POKE_BALL,
	]:
		if world.state.item_quantity(ball) > 0:
			return ball
	return -1


func _party_moves(save: Gen2SaveData) -> Array:
	var out: Array = []
	for mon: Gen2SaveMon in save.party:
		out.append(mon.moves.duplicate())
	return out


## Olivine City to Cianwood City and back. Only the Route 40 and Route 41 legs
## are surfed: Olivine reaches Route 40 on foot, since the two maps meet on
## Olivine's western beach, and Route 40's south edge is the first water the
## route cannot walk around.
func _cianwood_crossing(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
	returning: bool,
) -> Dictionary:
	var label: String = "return" if returning else "outbound"
	# The two shores this leg uses are each a plain floor cell whose neighbour in
	# `facing` is COLL_WATER and which carries none of the SMASHABLE_ROCK objects
	# Route 40 puts on its beach. Cianwood's (27,41) is one on both profiles;
	# Route 40's beach is not, because `maps/Route40.blk` differs between the
	# pins and Crystal's (12,13) is open water on Gold and Silver.
	var route_40_shore: Vector2i = Vector2i(12, 13) \
		if Gen2WorldState.is_crystal_profile(data) else Vector2i(12, 11)
	var legs: Array = [
		{"step": "olivine_to_route_40", "direction": "west", "group": 22, "number": 1,
			"water": false},
		{"step": "route_40_to_route_41", "direction": "south", "group": 22, "number": 2,
			"water": true, "surf": route_40_shore, "facing": Gen2WorldSprite.FACING_DOWN},
		{"step": "route_41_to_cianwood", "direction": "west", "group": 22, "number": 3,
			"water": true, "ashore": Vector2i(27, 41)},
	]
	if returning:
		legs = [
			{"step": "cianwood_to_route_41", "direction": "east", "group": 22, "number": 2,
				"water": true, "surf": Vector2i(27, 41), "facing": Gen2WorldSprite.FACING_RIGHT},
			{"step": "route_41_to_route_40", "direction": "north", "group": 22, "number": 1,
				"water": true, "ashore": route_40_shore},
			{"step": "route_40_to_olivine", "direction": "east", "group": 1, "number": 14,
				"water": false},
		]
	for leg: Dictionary in legs:
		if leg.has("surf"):
			var entered: Dictionary = _surf_at(
				world, leg["surf"], int(leg["facing"]), save, random, data
			)
			if not bool(entered.get("ok", false)):
				return {
					"ok": false, "path": path,
					"reason": "%s surf entry (%s) failed: %s" % [
						leg["step"], label, entered.get("reason", ""),
					],
				}
		var walked: Dictionary = _walk_connection_resolving(
			world, String(leg["direction"]), int(leg["group"]), int(leg["number"]),
			save, random, data, bool(leg["water"])
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		var surfing: String = String(world.movement_mode)
		var ashore: Dictionary = {}
		if bool(walked.get("ok", false)) and leg.has("ashore"):
			# The far side of a surfed connection is still water. One water-only
			# walk to a named shore cell ends on .ExitWater, and every walk after
			# it is an ordinary one.
			ashore = _walk_cell_resolving(world, leg["ashore"], save, random, data, true)
		path.append({
			"step": "%s_%s" % [leg["step"], label],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"movement_mode_on_arrival": surfing,
			"movement_mode": String(world.movement_mode),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s (%s) failed: %s" % [leg["step"], label, walked.get("reason", "")],
			}
		if not ashore.is_empty() and not bool(ashore.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s landfall (%s) failed: %s" % [
					leg["step"], label, ashore.get("reason", ""),
				],
			}
	return {"ok": true}


## Walks to a gate door, takes it, and takes the gate's own warp to
## [param group]/[param number] on the far side.
func _gate_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	door: Vector2i,
	group: int,
	number: int,
) -> Dictionary:
	var walked: Dictionary = _warp_walk(world, door, save, random, data)
	if not bool(walked.get("ok", false)):
		return walked
	var _gate_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var crossed: Dictionary = _warp_step(world, group, number)
	if not bool(crossed.get("ok", false)):
		return {
			"ok": false,
			"reason": "gate warp to %d/%d failed" % [group, number],
			"encounters": walked.get("encounters", []),
		}
	var _far_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	# Anything the walk to the door resolved on the way, which for a route with
	# trainers on it is a battle the leg would otherwise leave no trace of.
	return {"ok": true, "encounters": walked.get("encounters", [])}


## Smashes the rock the given cell faces, the way _cut_at() cuts. Unlike a cut
## tree the rock is an object, so `complete_rock_smash()` deletes it and rolls
## `RockMonEncounter` in the same call; the walk reports whatever came out
## rather than fighting it.
func _rock_smash_at(
	world: Gen2WorldAPI,
	approach: Vector2i,
	facing: int,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, approach, save, random, data)
	if not bool(walked.get("ok", false)):
		return walked
	world.player_facing = facing
	var request: Dictionary = world.rock_smash_request()
	if not bool(request.get("ok", false)):
		return {"ok": false, "reason": "rock smash refused: %s" % request.get("reason", "")}
	var applied: Dictionary = world.complete_rock_smash(random)
	if not bool(applied.get("ok", false)):
		return {"ok": false, "reason": "rock smash failed: %s" % applied.get("reason", "")}
	return {"ok": true, "encounter": applied.get("encounter", {})}


## Cuts the tree the given cell faces. Route 35's only way past row 6 is the
## cut tree at (17,6), and the override dies with the map load, so the walked
## route cuts it again on every crossing exactly as a player would.
func _cut_at(
	world: Gen2WorldAPI,
	approach: Vector2i,
	facing: int,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, approach, save, random, data)
	if not bool(walked.get("ok", false)):
		return walked
	world.player_facing = facing
	var request: Dictionary = world.cut_request()
	if not bool(request.get("ok", false)):
		return {"ok": false, "reason": "cut refused: %s" % request.get("reason", "")}
	var applied: Dictionary = world.complete_cut()
	if not bool(applied.get("ok", false)):
		return {"ok": false, "reason": "cut failed: %s" % applied.get("reason", "")}
	return {"ok": true, "cell": applied.get("cell", approach)}


## Enters the water the given cell faces, the way _cut_at() cuts: request then
## commit, since UsedSurfScript reaches SurfStartStep only after its waitbutton.
## The commit spends the source's single slow_step, so the player ends one cell
## into the water already surfing.
func _surf_at(
	world: Gen2WorldAPI,
	approach: Vector2i,
	facing: int,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, approach, save, random, data)
	if not bool(walked.get("ok", false)):
		return walked
	world.player_facing = facing
	var request: Dictionary = world.surf_request()
	if not bool(request.get("ok", false)):
		return {"ok": false, "reason": "surf refused: %s" % request.get("reason", "")}
	var applied: Dictionary = world.complete_surf()
	if not bool(applied.get("ok", false)):
		return {"ok": false, "reason": "surf failed: %s" % applied.get("reason", "")}
	return {"ok": true, "cell": applied.get("cell", approach)}


## Clears the whirlpool the given water cell faces, the way _cut_at() cuts:
## request then commit, since Script_UsedWhirlpool reaches DisappearWhirlpool
## only after UseWhirlpoolText. The frontier stays on water, so the approach
## cannot step ashore on the way.
func _whirlpool_at(
	world: Gen2WorldAPI,
	approach: Vector2i,
	facing: int,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, approach, save, random, data, true)
	if not bool(walked.get("ok", false)):
		return walked
	world.player_facing = facing
	var request: Dictionary = world.whirlpool_request()
	if not bool(request.get("ok", false)):
		return {"ok": false, "reason": "whirlpool refused: %s" % request.get("reason", "")}
	var applied: Dictionary = world.complete_whirlpool()
	if not bool(applied.get("ok", false)):
		return {"ok": false, "reason": "whirlpool failed: %s" % applied.get("reason", "")}
	return {"ok": true, "cell": applied.get("cell", approach)}


## Walks to [param cell], faces [param facing] and drains the interaction.
## [param answers] is passed through to _drain_story() for an NPC who asks, the
## way the Radio Card woman's five-question quiz does.
func _talk_to(
	world: Gen2WorldAPI,
	cell: Vector2i,
	facing: int,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	answers: Array[int] = [],
	apricorn: Dictionary = {},
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, cell, save, random, data)
	if not bool(walked.get("ok", false)):
		return walked
	world.player_facing = facing
	var run: Dictionary = _drain_story(
		world, world.interact(), save, random, data, true, answers, {}, apricorn
	)
	return {
		"ok": bool(run.get("terminal", false)),
		"reason": run.get("reason", ""),
		# Anything met on the way, which for a gym is the trainers between the
		# door and the leader. Reported rather than dropped: the walk resolves
		# them, so without this a fought battle leaves no trace in the path.
		"encounters": walked.get("encounters", []),
		"run": run,
	}


## Places the player on this map's warp to [param group]/[param number] and
## takes it. Used where the destination warp is the step, not the walk.
func _warp_step(world: Gen2WorldAPI, group: int, number: int) -> Dictionary:
	var warp: Dictionary = _warp_to(world.current_map, group, number)
	if warp.is_empty():
		return {"ok": false, "reason": "missing warp to %d/%d" % [group, number]}
	world.player_cell = Vector2i(warp["x"], warp["y"])
	return world.try_warp()


## Walks to a warp cell, resolving whatever answers on the way, and takes it.
func _warp_walk(
	world: Gen2WorldAPI,
	cell: Vector2i,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, cell, save, random, data)
	if not bool(walked.get("ok", false)):
		return walked
	var transition: Dictionary = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {
			"ok": false,
			"reason": "warp at %s did not fire" % cell,
			"encounters": walked.get("encounters", []),
		}
	walked["transition"] = transition
	return walked


func _party_species(save: Gen2SaveData) -> Array:
	var values: Array = []
	for mon: Gen2SaveMon in save.party:
		values.append({"species": mon.species, "level": mon.level, "egg": mon.is_egg})
	return values


## The whole read-only mirror in one call, so every leg answers VAR_PARTYCOUNT,
## CheckPokerus, checkpoke and CheckPartyMove the same way. Pokerus is false
## throughout: nothing on this route gives it.
func _mirror_party(world: Gen2WorldAPI, save: Gen2SaveData) -> void:
	var species: Array[int] = []
	var moves: Array = []
	var names: Array = []
	var eggs: Array = []
	for mon: Gen2SaveMon in save.party:
		species.append(int(mon.species))
		var mon_moves: Array = []
		for move: int in mon.moves:
			if move != 0:
				mon_moves.append(move)
		moves.append(mon_moves)
		names.append(mon.nickname if not mon.nickname.is_empty() else "")
		eggs.append(mon.is_egg)
	world.set_party_summary(save.party.size(), false, species, moves, names, eggs)


func _party_has_egg(save: Gen2SaveData) -> bool:
	for mon: Gen2SaveMon in save.party:
		if mon.is_egg:
			return true
	return false


func _party_hp(save: Gen2SaveData) -> Array:
	var values: Array = []
	for mon: Gen2SaveMon in save.party:
		values.append(int(mon.hp))
	return values


## Spends hardware frames until the source two-ring sequence and any
## special-call lead have elapsed, and returns the imported phone script's
## first results. Gen2WorldPhoneRing answers nothing before that, so a caller
## that only drains script input would see the call as finished state.
func _drain_phone_ring(world: Gen2WorldAPI) -> Array:
	for _frame: int in PHONE_RING_FRAME_BUDGET:
		if not world.phone_ring_active():
			return []
		var results: Array = world.advance_phone_ring_frame()
		if not results.is_empty():
			return results
	return []


## Runs a dispatched event list to its terminal state. [param require_events]
## is set by a step whose whole point is that an imported script ran: without
## it an empty [param initial] drains in zero iterations and reports terminal,
## so a step that silently found nothing to talk to passes. Map-entry steps
## leave it false, since a map with no entry callback legitimately dispatches
## nothing.
func _drain_story(
	world: Gen2WorldAPI,
	initial: Array,
	save: Gen2SaveData = null,
	random: RandomNumberGenerator = null,
	data: GameData = null,
	require_events: bool = false,
	answers: Array[int] = [],
	purchase: Dictionary = {},
	apricorn: Dictionary = {},
) -> Dictionary:
	var pending_answers: Array[int] = answers.duplicate()
	## What to buy if a `pokemart` opens while this drain runs. Cleared once it
	## is spent, so one standing order buys once.
	var pending_purchase: Dictionary = purchase.duplicate()
	var purchases: Array = []
	## The same standing order for `special SelectApricornForKurt`. An empty one
	## backs out of the box, which is the source's own cancel.
	var pending_apricorn: Dictionary = apricorn.duplicate()
	var apricorns_given: Array = []
	if require_events and initial.is_empty():
		return {
			"statuses": [],
			"waits": 0,
			"pending_trace": [],
			"battles": [],
			"terminal": false,
			"reason": "no events dispatched",
			"details": "",
		}
	var results: Array = initial.duplicate(true)
	var statuses: Array = _statuses(results)
	var waits: int = 0
	var last_reason: String = ""
	var last_details: String = ""
	var pending_trace: Array[String] = []
	var waits_spent: int = 0
	var battles: Array = []
	var catch_tutorials: int = 0
	var hall_of_fame: int = _hall_of_fame_events(results)
	var credits: int = _credits_events(results)
	var approaches: Array = []
	for result: Dictionary in results:
		if not bool(result.get("ok", false)):
			last_reason = String(result.get("reason", "script_failed"))
			last_details = JSON.stringify(result.get("details", result))
			break
	for _step: int in 256:
		var input: Dictionary = world.pending_script_input()
		var input_type: StringName = StringName(input.get("type", &""))
		if world.phone_ring_active():
			input_type = &"phone_ring"
		if pending_trace.size() < 24:
			pending_trace.append(String(input_type))
		if input_type == &"phone_ring":
			results = _drain_phone_ring(world)
			if results.is_empty():
				last_reason = "phone ring did not finish"
				break
		elif input_type == &"wait":
			## A movement or a counted delay. Nothing answers it, so the walk
			## spends the frames the way the screen does.
			var standing_in: Dictionary = world.pending_script_wait()
			results = world.finish_script_waits()
			waits_spent += 1
			if not world.pending_script_wait().is_empty():
				last_reason = "a script wait never ended"
				last_details = JSON.stringify(standing_in)
				break
		elif input_type in [&"text", &"button"]:
			results = world.run_event_queue(true)
		elif input_type in [&"choice", &"menu"]:
			## Choices default to the source's first option, which is yes on a
			## yesorno. A caller that needs particular answers, like the Dragon
			## Shrine quiz, supplies them in the order the script asks.
			var choice: int = 0
			if not pending_answers.is_empty():
				choice = pending_answers.pop_front()
			results = world.choose_script_input(choice)
		else:
			var request: Dictionary = world.pending_runtime_request()
			if request.is_empty():
				break
			if pending_trace.size() < 24:
				pending_trace.append("runtime:%s" % String(request.get("kind", "")))
			var request_kind: StringName = StringName(request.get("kind", &""))
			if request_kind == &"rival_name_requested":
				var name_host_result: Dictionary = Gen2WorldHost.complete_runtime_request(
					world, {"ok": true, "name": "SILVER"}, save, false, random
				)
				if not bool(name_host_result.get("ok", false)):
					last_reason = String(name_host_result.get("reason", "rival name host failed"))
					last_details = JSON.stringify(name_host_result.get("details", {}))
					break
				results = name_host_result.get("results", [])
			elif request_kind in [&"pokemon_requested", &"trade_requested", &"party_heal_requested"]:
				var host_result: Dictionary = Gen2WorldHost.complete_runtime_request(
					world, {"ok": true}, save, false, random
				)
				if not bool(host_result.get("ok", false)):
					last_reason = String(host_result.get("reason", "party host failed"))
					last_details = JSON.stringify(host_result.get("details", {}))
					break
				results = host_result.get("results", [])
			elif request_kind == &"battle_requested":
				var player_party: Gen2Party = (
					Gen2SaveBattleAdapter.to_battle_party(data, save)
					if data != null and save != null else Gen2WorldBattleAdapter.fallback_party(data)
				)
				var prepared: Dictionary = Gen2WorldBattleAdapter.prepare(
					data, request, player_party, random
				)
				if not bool(prepared.get("ok", false)):
					last_reason = String(prepared.get("reason", "battle setup failed"))
					last_details = JSON.stringify(prepared.get("details", {}))
					break
				var enemy_party: Gen2Party = prepared.get("enemy_party", null)
				battles.append({
					"trainer_class": int(prepared.get("trainer_class", 0)),
					"trainer_index": int(prepared.get("trainer_index", 0)),
					"enemy_species": int(enemy_party.active_mon().species)
						if enemy_party != null and enemy_party.active_mon() != null else 0,
					"battle_type": int(request.get("values", {}).get("battle_type", 0)),
					"can_lose": bool(request.get("values", {}).get("can_lose", false)),
				})
				results = world.complete_runtime_request({
					"ok": true,
					"outcome": Gen2WorldBattleAdapter.OUTCOME_WON,
				})
			elif request_kind == &"trainer_approach_requested":
				# Route 30's trainers see the player on the corridor north, so
				# the walked route runs the source presentation: shock emote for
				# TRAINER_SHOCK_FRAMES, then one slow step per planned cell,
				# then the facing update, before the seen text resumes. The
				# same order tools/checks/crystal_route30_trainer.gd checks.
				var approach_values: Dictionary = request.get("values", {})
				var approach_index: int = int(approach_values.get("object_index", -1))
				var raw_direction: Variant = approach_values.get("direction", Vector2i.ZERO)
				var approach_direction: Vector2i = (
					raw_direction if raw_direction is Vector2i else Vector2i.ZERO
				)
				var plan: Dictionary = world.start_trainer_approach(
					approach_index, approach_direction,
					int(approach_values.get("distance", 0))
				)
				if not bool(plan.get("ok", false)):
					last_reason = String(plan.get("reason", "trainer approach plan failed"))
					last_details = JSON.stringify(plan)
					break
				for _frame: int in int(plan.get("emote_frames", 0)):
					world.advance_emotes_frame()
				var approach_failed: bool = false
				for path_step: Vector2i in plan.get("path", []):
					var stepped: Dictionary = world.advance_trainer_approach_step(
						approach_index, path_step
					)
					if not bool(stepped.get("ok", false)):
						last_reason = String(stepped.get("reason", "trainer approach step failed"))
						last_details = JSON.stringify(stepped)
						approach_failed = true
						break
				if approach_failed:
					break
				var faced: Dictionary = world.finish_trainer_approach(approach_index)
				if not bool(faced.get("ok", false)):
					last_reason = String(faced.get("reason", "trainer approach finish failed"))
					last_details = JSON.stringify(faced)
					break
				approaches.append({
					"object_index": approach_index,
					"path": plan.get("path", []).size(),
				})
				results = world.complete_runtime_request({
					"ok": true,
					"object_index": approach_index,
					"path": plan.get("path", []),
				})
			elif request_kind == &"catch_tutorial_requested":
				# ElmAfterTheftScript sets SCENE_ROUTE29_CATCH_TUTORIAL, so this
				# is on the route from here on. The source guarantees the ball,
				# and Gen2WorldScriptRunner refuses any other outcome, so the
				# only valid completion is OUTCOME_CAUGHT. It changes no
				# persistent party, PC or ball state.
				catch_tutorials += 1
				results = world.complete_runtime_request({
					"ok": true,
					"outcome": Gen2WorldBattleAdapter.OUTCOME_CAUGHT,
				})
			elif request_kind == &"mart_requested":
				# `pokemart` is a runtime pause the same way a battle is, so the
				# clerk's own script is what opens the mart and the caller's
				# standing order is what buys from it. Gen2WorldHost resolves the
				# dialog and mart id off the request exactly as the service
				# screen does.
				var mart_host: Dictionary = Gen2WorldHost.resolve_runtime_request(world, request)
				if not bool(mart_host.get("ok", false)):
					last_reason = String(mart_host.get("reason", "mart host failed"))
					last_details = JSON.stringify(mart_host)
					break
				var mart: Dictionary = mart_host.get("data", {}).get("mart", {})
				if not pending_purchase.is_empty():
					var bought: Dictionary = Gen2WorldMartHost.purchase(
						world, save, mart, int(pending_purchase.get("item", 0)),
						int(pending_purchase.get("quantity", 0)), false
					)
					purchases.append({
						"item": int(pending_purchase.get("item", 0)),
						"quantity": int(pending_purchase.get("quantity", 0)),
						"ok": bool(bought.get("ok", false)),
						"reason": bought.get("reason", ""),
					})
					if not bool(bought.get("ok", false)):
						last_reason = String(bought.get("reason", "purchase refused"))
						last_details = JSON.stringify(bought)
						break
					pending_purchase = {}
				results = world.complete_runtime_request({"ok": true})
			elif request_kind == &"apricorn_selection_requested":
				# Kurt's two boxes are a runtime pause the same way a mart is.
				# Gen2WorldApricornHost takes the apricorns and resumes, so the
				# walk proves the transaction rather than only the request.
				var given: Dictionary = Gen2WorldHost.complete_runtime_request(
					world, {
						"ok": true,
						"item": int(pending_apricorn.get("item", 0)),
						"quantity": int(pending_apricorn.get("quantity", 0)),
					}, save, false
				)
				if not bool(given.get("ok", false)):
					last_reason = String(given.get("reason", "apricorn host failed"))
					last_details = JSON.stringify(given)
					break
				apricorns_given.append({
					"item": int(given.get("item", 0)),
					"quantity": int(given.get("quantity", 0)),
				})
				pending_apricorn = {}
				results = given.get("results", [])
			elif request_kind == &"audio_requested":
				results = world.complete_runtime_request({"ok": true})
			else:
				last_reason = "unsupported preview request: %s" % String(request.get("kind", ""))
				break
		if results.is_empty():
			break
		statuses.append_array(_statuses(results))
		hall_of_fame += _hall_of_fame_events(results)
		credits += _credits_events(results)
		waits += 1
		for result: Dictionary in results:
			if not bool(result.get("ok", false)):
				last_reason = String(result.get("reason", "script_failed"))
				last_details = JSON.stringify(result.get("details", {}))
				break
		if not world.script_input_waiting() and world.pending_runtime_request().is_empty():
			var terminal: bool = false
			for result: Dictionary in results:
				if StringName(result.get("status", &"")) in [&"complete", &"failed"]:
					terminal = true
			if terminal:
				break
	return {
		"statuses": statuses,
		"waits": waits,
		"waits_spent": waits_spent,
		"pending_trace": pending_trace,
		"battles": battles,
		"purchases": purchases,
		"apricorns_given": apricorns_given,
		"catch_tutorials": catch_tutorials,
		"hall_of_fame": hall_of_fame,
		"credits": credits,
		"approaches": approaches,
		"terminal": last_reason.is_empty() \
			and not world.script_input_waiting() and world.pending_runtime_request().is_empty(),
		"reason": last_reason,
		"details": last_details,
}


func _walk_to_connection(
	world: Gen2WorldAPI, direction_name: String, target_group: int, target_number: int,
	water_only: bool = false,
) -> Dictionary:
	if world == null or world.current_map == null:
		return {"ok": false, "reason": "missing world"}
	var connection: Dictionary = {}
	for candidate: Dictionary in world.current_map.connections:
		if String(candidate.get("direction", "")) == direction_name \
			and int(candidate.get("map_group", -1)) == target_group \
			and int(candidate.get("map_number", -1)) == target_number:
			connection = candidate
			break
	if connection.is_empty():
		return {"ok": false, "reason": "missing connection", "direction": direction_name}

	var frontier: Array[Vector2i] = [world.player_cell]
	var previous: Dictionary = {world.player_cell: {"cell": Vector2i(-1, -1), "direction": Vector2i.ZERO}}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var edge: Vector2i = Vector2i(-1, -1)
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		if _is_connection_edge(world, cell, direction_name):
			edge = cell
			break
		for step: Vector2i in directions:
			var next: Vector2i = _reachable_step(world, cell, step, Vector2i(-1, -1), water_only)
			if next.x < 0 or previous.has(next):
				continue
			previous[next] = {"cell": cell, "direction": step}
			frontier.append(next)
	if edge.x < 0:
		return {
			"ok": false,
			"reason": "connection edge unreachable%s" % _objects_in_the_way(
				world, Vector2i(-1, -1), previous
			),
			"direction": direction_name,
		}

	var steps: Array[Vector2i] = []
	var cursor: Vector2i = edge
	while cursor != world.player_cell:
		var link: Dictionary = previous[cursor]
		steps.push_front(link["direction"])
		cursor = link["cell"]
	for step: Vector2i in steps:
		var moved: Dictionary = world.move_result(step)
		if not bool(moved.get("ok", false)):
			return {"ok": false, "reason": "walk step failed", "step": step}
		var events: Array = _dispatch_after_step(world)
		if not events.is_empty():
			return {"ok": false, "reason": "connection walk hit a scripted event", "events": events}
	var transition: Dictionary = world.move_result(_connection_direction(direction_name))
	return {
		"ok": bool(transition.get("ok", false)),
		"steps": steps.size(),
		"transition": transition,
	}


## The cell [param step] from [param cell] reaches by an ordinary walk or, when
## that is blocked, a ledge hop (Gen2WorldCollision.allows_hop, mirroring
## Gen2WorldAPI._try_ledge_hop's order and its surf and map-bounds refusals).
## Returns (-1, -1) when neither applies, so a BFS frontier can use it as one
## reachability test. Replaying the recorded direction through
## world.move_result() performs the same hop, so no separate replay step exists.
##
## [param water_only] is what a surfing plan needs. can_walk_to() lets a surfing
## player step onto land, and that step is .ExitWater, so a plan drawn once and
## replayed would stop surfing partway and see every later water step refused.
## Restricting the frontier to WATER_TILE keeps the whole plan legal in the mode
## it was drawn in; the caller enters and leaves the water explicitly.
func _reachable_step(
	world: Gen2WorldAPI, cell: Vector2i, step: Vector2i,
	warp_target: Vector2i = Vector2i(-1, -1),
	water_only: bool = false,
) -> Vector2i:
	var direct: Vector2i = cell + step
	if water_only \
		and world.collision_permission_at(direct) != Gen2WorldCollision.WATER_TILE:
		return Vector2i(-1, -1)
	# Stepping onto a warp tile takes it, so a walked route can only cross one
	# by leaving the map there. The BFS treats it as a wall unless it is the
	# cell it was asked to reach, which is what makes Ecruteak Gym's thirty
	# holes a maze instead of open floor. A warp_event on ordinary floor is
	# inert, as CheckWarpCollision has it, so it is not a wall.
	if direct != warp_target and not world.warp_at(direct).is_empty() \
		and Gen2WorldCollision.is_warp_tile(world.collision_code_at(direct)):
		return Vector2i(-1, -1)
	# A whirlpool traps rather than moves: .CheckTile answers
	# PLAYERMOVEMENT_FORCE_TURN for the cell the player stands on, so a plan that
	# crosses one never leaves it. Dragon's Den B1F's (10,20) is the first cell on
	# a walked route where the shortest path runs through one.
	if direct != warp_target and StringName(Gen2WorldCollision.forced_action(
		world.collision_code_at(direct)
	).get("kind", &"none")) == &"force_turn":
		return Vector2i(-1, -1)
	# move_result() calls can_walk_to() with the direction, which reads the
	# leave/enter wall mask at the player's own cell; from a BFS frontier that
	# has to be anchored on the frontier cell instead, or the plan crosses walls
	# the replayed walk then refuses. Route 32's UP_WALL row at y=72 is the
	# first cell on the walked route where the two disagree.
	var face: int = Gen2WorldCollision.face_mask_for_direction(step)
	var walled: bool = face != 0 and (world.tile_permissions_at(cell) & face) != 0
	if not walled and world.can_walk_to(direct):
		return direct
	if world.movement_mode == Gen2WorldAPI.MOVEMENT_SURF:
		return Vector2i(-1, -1)
	if not Gen2WorldCollision.allows_hop(world.collision_code_at(cell), step):
		return Vector2i(-1, -1)
	var landing: Vector2i = cell + step * 2
	var size: Vector2i = world.map_size_cells()
	if landing.x < 0 or landing.y < 0 or landing.x >= size.x or landing.y >= size.y:
		return Vector2i(-1, -1)
	return landing


## Whether a step off [param cell] would really cross, rather than whether the
## cell sits on the edge. A connection spans only part of its edge, so an edge
## cell the connected map does not reach resolves to nothing and the walk that
## settled on it would fail with no useful reason. `Gen2WorldAPI` owns the span
## arithmetic; asking it keeps the plan and the replayed walk on one answer.
func _is_connection_edge(world: Gen2WorldAPI, cell: Vector2i, direction_name: String) -> bool:
	var resolved: Dictionary = world.connection_target(
		cell, _connection_direction(direction_name)
	)
	return bool(resolved.get("ok", false))


func _connection_direction(direction_name: String) -> Vector2i:
	match direction_name:
		"north": return Vector2i.UP
		"south": return Vector2i.DOWN
		"west": return Vector2i.LEFT
		"east": return Vector2i.RIGHT
	return Vector2i.ZERO


func _named_items(data: GameData, items: Dictionary) -> Dictionary:
	var named: Dictionary = {}
	if data == null:
		return named
	for raw_item: Variant in items:
		var item_name: String = data.item_name(int(raw_item))
		named[item_name if not item_name.is_empty() else String(raw_item)] = int(items[raw_item])
	return named


## [param water_only] keeps a surfing plan on the water, the way
## _walk_to_connection() does, except that [param target] is always allowed: a
## landfall names one land cell and the step onto it is .ExitWater.
func _walk_to_story_cell(
	world: Gen2WorldAPI, target: Vector2i, water_only: bool = false,
	dispatch_target_events: bool = true
) -> Dictionary:
	if world == null or world.current_map == null:
		return {"ok": false, "reason": "missing world"}
	if world.player_cell == target:
		return {
			"ok": true,
			"events": _dispatch_after_step(world, target) if dispatch_target_events else [],
		}
	var frontier: Array[Vector2i] = [world.player_cell]
	var previous: Dictionary = {world.player_cell: {"cell": Vector2i(-1, -1), "direction": Vector2i.ZERO}}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var found: bool = false
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		if cell == target:
			found = true
			break
		for direction: Vector2i in directions:
			var next: Vector2i = _reachable_step(
				world, cell, direction, target, water_only and cell + direction != target
			)
			if next.x < 0 or previous.has(next):
				continue
			previous[next] = {"cell": cell, "direction": direction}
			frontier.append(next)
	if not found:
		return {
			"ok": false,
			"reason": "target %s unreachable from %s on %s (collision $%02x, walkable %s)%s" % [
				target, world.player_cell, _map_value(world),
				world.collision_code_at(target), world.can_walk_to(target),
				_objects_in_the_way(world, target, previous),
			],
			"target": _cell_value_from_vector(target),
		}
	var steps: Array[Vector2i] = []
	var cursor: Vector2i = target
	while cursor != world.player_cell:
		var link: Dictionary = previous[cursor]
		steps.push_front(link["direction"])
		cursor = link["cell"]
	var events: Array = []
	for direction: Vector2i in steps:
		var moved: Dictionary = world.move_result(direction)
		if not bool(moved.get("ok", false)):
			return {
				"ok": false,
				"reason": "walk step %s from %s refused: %s" % [
					direction, _cell_value(world), moved.get("reason", ""),
				],
			}
		events = _dispatch_after_step(world)
		if not events.is_empty():
			break
	return {"ok": true, "steps": steps.size(), "events": events}


## What a failed walk hit, when what it hit was somebody standing there.
## `Gen2WorldAPI.can_walk_to()` refuses a cell an object holds exactly as it
## refuses a wall, so without this a route blocked by an NPC or an item ball
## reads the same as one blocked by the map, and both of Route 40's beach rocks
## and the Lake of Rage's gramps cost a hand-routed detour to find.
##
## [param target] is the cell the walk wanted, or `(-1, -1)` for a connection
## edge that has none; [param visited] is the frontier's own `previous` map.
## Answers "" when nothing is in the way, so it appends to a reason.
func _objects_in_the_way(
	world: Gen2WorldAPI, target: Vector2i, visited: Dictionary
) -> String:
	var named: PackedStringArray = []
	var standing: Gen2WorldObject = world.object_at(target) if target.x >= 0 else null
	if standing != null:
		named.append("%s stands on it" % _object_name(standing))
	for object: Gen2WorldObject in world.objects:
		if object == standing or object.deleted or not object.active:
			continue
		if not _plugs_the_frontier(world, object, visited):
			continue
		named.append("%s at %s" % [_object_name(object), object.cell])
		if named.size() >= BLOCKING_OBJECTS_REPORTED:
			break
	if named.is_empty():
		return ""
	return ", blocked by %s" % ", ".join(named)


## Whether [param object] is standing in a gap rather than in the open: the walk
## reached one side of it and there is ground on the other it never got to. An
## NPC in the middle of a town is next to the frontier too, and naming that one
## would bury the one that matters.
func _plugs_the_frontier(
	world: Gen2WorldAPI, object: Gen2WorldObject, visited: Dictionary
) -> bool:
	if visited.has(object.cell):
		return false
	var reached: bool = false
	var beyond: bool = false
	for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbour: Vector2i = object.cell + step
		if visited.has(neighbour):
			reached = true
		elif world.can_walk_to(neighbour):
			beyond = true
	return reached and beyond


func _object_name(object: Gen2WorldObject) -> String:
	return "object %d (sprite %d)" % [object.index, object.sprite_number]


## The order Gen2WorldScreen uses after a successful step: a trainer who can
## see the player answers before the cell's own scripts. A walked route past
## Route 30's trainers reaches nothing otherwise, since sight is queued by
## dispatch_sight_events() and never by dispatch_script_events().
func _dispatch_after_step(world: Gen2WorldAPI, cell: Vector2i = Vector2i(-1, -1)) -> Array:
	var sight: Array = world.dispatch_sight_events()
	if not sight.is_empty():
		return sight
	return world.dispatch_script_events(cell if cell.x >= 0 else world.player_cell)


## Walks toward a connection edge, resolving anything met on the way and
## resuming from wherever the walk stopped. Route 30 puts two trainers on the
## corridor north, and a trainer who sees the player interrupts the walk, so a
## single _walk_to_connection() call cannot carry the route on its own.
func _walk_connection_resolving(
	world: Gen2WorldAPI,
	direction_name: String,
	target_group: int,
	target_number: int,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	water_only: bool = false,
) -> Dictionary:
	var runs: Array = []
	for _attempt: int in WALK_RESOLVE_ATTEMPTS:
		var walked: Dictionary = _walk_to_connection(
			world, direction_name, target_group, target_number, water_only
		)
		if bool(walked.get("ok", false)):
			walked["encounters"] = runs
			return walked
		var events: Array = walked.get("events", [])
		if events.is_empty():
			walked["encounters"] = runs
			return walked
		var run: Dictionary = _drain_story(world, events, save, random, data, true)
		runs.append({
			"cell": _cell_value(world),
			"statuses": run.get("statuses", []),
			"battles": run.get("battles", []),
		})
		if not bool(run.get("terminal", false)):
			return {
				"ok": false,
				"reason": "encounter on the way to the %s connection did not finish" % direction_name,
				"encounters": runs,
				"details": run.get("reason", ""),
			}
	return {"ok": false, "reason": "connection walk did not settle", "encounters": runs}


## The _walk_to_story_cell() counterpart of _walk_connection_resolving().
func _walk_cell_resolving(
	world: Gen2WorldAPI,
	target: Vector2i,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	water_only: bool = false,
) -> Dictionary:
	var runs: Array = []
	var dispatch_target_events: bool = true
	for _attempt: int in WALK_RESOLVE_ATTEMPTS:
		var walked: Dictionary = _walk_to_story_cell(
			world, target, water_only, dispatch_target_events
		)
		if not bool(walked.get("ok", false)):
			walked["encounters"] = runs
			return walked
		var events: Array = walked.get("events", [])
		if events.is_empty() and world.player_cell == target:
			walked["encounters"] = runs
			return walked
		if events.is_empty():
			return {
				"ok": false,
				"reason": "walk stopped short of %s" % target,
				"encounters": runs,
			}
		var run: Dictionary = _drain_story(world, events, save, random, data, true)
		runs.append({
			"cell": _cell_value(world),
			"statuses": run.get("statuses", []),
			"battles": run.get("battles", []),
		})
		if not bool(run.get("terminal", false)):
			return {
				"ok": false,
				"reason": "encounter on the way to %s did not finish" % target,
				"encounters": runs,
				"details": run.get("reason", ""),
			}
		if world.player_cell == target:
			return {"ok": true, "encounters": runs, "events": []}
		dispatch_target_events = false
	return {"ok": false, "reason": "walk to %s did not settle" % target, "encounters": runs}


## An engine flag named by its Crystal index, read on the profile's own table.
## Every ENGINE_FLYPOINT_* constant here is a Crystal index and all of them sit
## past ENGINE_MOBILE_SYSTEM, so on Gold and Silver every one of them is a cell
## lower; `Gen2WorldState.engine_flag()` owns that shift.
func _engine_flag_set(world: Gen2WorldAPI, data: GameData, crystal_index: int) -> bool:
	return world.state.is_engine_flag_active(Gen2WorldState.engine_flag(
		crystal_index, Gen2WorldState.is_crystal_profile(data)
	))


## The [constant MAP_IDS] row for [param name] on this cartridge's profile.
func _map_id(data: GameData, name: StringName) -> Vector2i:
	var row: Dictionary = MAP_IDS[name]
	return row[&"crystal"] if Gen2WorldState.is_crystal_profile(data) else row[&"gold"]


func _warp_to(map: Gen2WorldMap, group: int, number: int) -> Dictionary:
	if map == null:
		return {}
	for warp: Dictionary in map.events.get("warps", []):
		if int(warp.get("map_group", -1)) == group and int(warp.get("map_number", -1)) == number:
			return warp.duplicate(true)
	return {}


func _map_value(world: Gen2WorldAPI) -> Array[int]:
	return [world.current_map.group, world.current_map.number]


func _cell_value(world: Gen2WorldAPI) -> Array[int]:
	return [world.player_cell.x, world.player_cell.y]


func _cell_value_from_vector(cell: Vector2i) -> Array[int]:
	return [cell.x, cell.y]


func _transition_value(transition: Dictionary) -> Dictionary:
	return {
		"ok": bool(transition.get("ok", false)),
		"from_map": _vector_value(transition.get("from_map", Vector2i(-1, -1))),
		"from_cell": _vector_value(transition.get("from_cell", Vector2i(-1, -1))),
		"to_map": _vector_value(transition.get("to_map", Vector2i(-1, -1))),
		"to_cell": _vector_value(transition.get("to_cell", Vector2i(-1, -1))),
	}


func _vector_value(value: Variant) -> Array[int]:
	if value is Vector2i:
		return [value.x, value.y]
	return [-1, -1]


func _statuses(results: Array) -> Array[String]:
	var out: Array[String] = []
	for result: Dictionary in results:
		out.append(String(result.get("status", "")))
	return out


## `halloffame` commits ENGINE_HALL_OF_FAME and emits this, the one presentation
## event on the route with no screen behind it. Counted so the walk can say the
## boundary was reached rather than only that the flag is set.
func _hall_of_fame_events(results: Array) -> int:
	return _presentation_events(results, &"hall_of_fame_requested")


## `credits` is the same kind of boundary, reached once by Red
## (`maps/SilverCaveRoom3.asm`).
func _credits_events(results: Array) -> int:
	return _presentation_events(results, &"credits_requested")


func _presentation_events(results: Array, type: StringName) -> int:
	var count: int = 0
	for result: Dictionary in results:
		for event: Dictionary in result.get("events", []):
			if StringName(event.get("type", &"")) == type:
				count += 1
	return count
