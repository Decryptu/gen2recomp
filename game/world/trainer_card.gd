class_name Gen2TrainerCard
extends RefCounted

## What the trainer card prints (`engine/menus/trainer_card.asm`), as pages a
## screen can draw.
##
## Everything here comes from the save and the world the card is opened over:
## `wPlayerName`, `wPlayerID` and `wMoney` on the top half, `wPokedexCaught`'s
## set bits and `wGameTimeHours`/`wGameTimeMinutes` on page 1, and the two badge
## bytes behind pages 2 and 3.

## `TrainerCard.Jumptable` indexes, halved: each page's LoadGFX and Joypad states
## are one page here, since nothing needs the frame the graphics land on.
const PAGE_1: int = Gen2TrainerCardPage.PAGE_1
const PAGE_2: int = Gen2TrainerCardPage.PAGE_2
const PAGE_3: int = Gen2TrainerCardPage.PAGE_3
const PAGES: int = 3

## `NUM_JOHTO_BADGES`, which is also the number of Kanto badges and the length of
## `TrainerCard_JohtoBadgesOAM`, the one template both badge pages read.
const BADGES_PER_PAGE: int = 8
## `wJohtoBadges` is the low eight of the badge order and `wKantoBadges` the
## high eight, which is the order [constant Gen2WorldState.BADGE_ENGINE_FLAGS]
## is already in.
const JOHTO_FIRST_BADGE: int = 0
const KANTO_FIRST_BADGE: int = 8


## One page, ready to draw. [param separator] is the blinking colon between the
## play timer's hours and minutes, which the caller owns because the source
## flips it off `hVBlankCounter` rather than off any state.
static func page(
	save: Gen2SaveData, world: Gen2WorldAPI, page_number: int, separator: bool = true
) -> Dictionary:
	if save == null:
		return {}
	var state: Gen2WorldState = world.state if world != null else null
	var crystal: bool = Gen2WorldState.is_crystal_profile(world.data) if world != null else true
	var time: Gen2GameTime = save.game_time if save.game_time != null else Gen2GameTime.new()
	return {
		"page": page_number,
		"player_name": save.player_name,
		"player_id": save.player_id,
		"money": state.money() if state != null else 0,
		## `TrainerCard_Page1_PrintDexCaught_GameTime` clears its own dex row
		## when STATUSFLAGS_POKEDEX_F is clear, so a player without the Pokedex
		## is shown no count rather than a zero.
		"pokedex": state != null and state.is_engine_flag_active(
			Gen2WorldStartMenu.ENGINE_POKEDEX
		),
		"caught": state.caught_count() if state != null else 0,
		"hours": time.hours_text(),
		"minutes": time.minutes_text(),
		"separator": separator,
		"badges": badges(state, page_number, crystal),
	}


## Which of the eight badges a badge page draws, in source badge order.
## `TrainerCard_Page2_3_OAMUpdate` walks one bit per badge and skips the clear
## ones, so this is that bit array rather than a count.
static func badges(state: Gen2WorldState, page_number: int, crystal: bool) -> Array:
	var out: Array = []
	if page_number == PAGE_1:
		return out
	var first: int = JOHTO_FIRST_BADGE if page_number == PAGE_2 else KANTO_FIRST_BADGE
	for index: int in BADGES_PER_PAGE:
		var flag: int = Gen2WorldState.badge_flag(first + index, crystal)
		out.append(state != null and state.is_engine_flag_active(flag))
	return out


## `TrainerCard_Page1_Joypad`, `..._Page2_Joypad` and `..._Page3_Joypad` as one
## table: which page a direction reaches, and whether A leaves.
##
## Page 1 answers right and A with page 2; page 2 answers left with page 1 and A
## with the exit; page 3 answers left with page 2 and right with page 1. The two
## `.KantoBadgeCheck` branches that would reach page 3 are unreferenced in both
## pins, so nothing but a right press from page 2 could, and page 2 has none:
## page 3 is unreachable on the cartridge and is unreachable here.
static func next_page(page_number: int, button: int) -> Dictionary:
	match page_number:
		PAGE_1:
			if button == Gen2Button.RIGHT or button == Gen2Button.A:
				return {"page": PAGE_2}
		PAGE_2:
			if button == Gen2Button.A:
				return {"exit": true}
			if button == Gen2Button.LEFT:
				return {"page": PAGE_1}
		PAGE_3:
			if button == Gen2Button.LEFT:
				return {"page": PAGE_2}
			if button == Gen2Button.RIGHT:
				return {"page": PAGE_1}
	## `.loop`'s own `and PAD_B`, which leaves from any page.
	if button == Gen2Button.B:
		return {"exit": true}
	return {}
