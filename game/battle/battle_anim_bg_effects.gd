class_name Gen2BattleAnimBgEffects
extends RefCounted

## The `BATTLE_BG_EFFECT_*` jumptable and the routines it dispatches
## (engine/battle_anims/bg_effects.asm).
##
## A bg effect is the half of an animation that is not an object: the screen
## shakes, the scanline deformations, the palette fades and the tilemap edits
## that hide, shrink and slide a battler's picture. Five run at once, each a
## four-byte `battle_bg_effect` the script queues with `anim_bgeffect`.
##
## **An effect id is profile-local and is never normalised.** pokegold ships no
## `BATTLE_BG_EFFECT_BODY_SLAM`, so its list is 53 long against Crystal's 54 and
## every id from $25 on names a different effect in the two games. The two
## jumptables are kept whole here for that reason, and dispatch is by name.
##
## The Color hardware's branch is the one taken wherever the source asks `hCGB`
## or `hSGB`, which is the same choice every `_CGB_*` layout in this project
## makes. The DMG halves of `BGEffect_RapidCyclePals` and
## `BattleBGEffect_FadeMonsToBlackRepeating` are therefore not built; the effects
## that write `wBGP` unconditionally still reach the screen, because
## `BattleAnimRequestPals` turns that byte into a CGB palette remap.

## `BattleBGEffects`, Crystal's own order. The index is the cartridge's effect
## id and entry 0 is `BattleBGEffect_End`, which is also the free-slot marker.
const EFFECTS_CRYSTAL: Array[StringName] = [
	&"end", &"flash_inverted", &"flash_white", &"white_hues", &"black_hues",
	&"alternate_hues", &"cycle_ob_pals_gray_and_yellow",
	&"cycle_mid_ob_pals_gray_and_yellow", &"cycle_bg_pals_inverted",
	&"hide_mon", &"show_mon", &"enter_mon", &"return_mon", &"surf",
	&"whirlpool", &"teleport", &"night_shade", &"battler_obj_1row",
	&"battler_obj_2row", &"double_team", &"acid_armor", &"rapid_flash",
	&"fade_mon_to_light", &"fade_mon_to_black", &"fade_mon_to_light_repeating",
	&"fade_mon_to_black_repeating", &"cycle_mon_light_dark_repeating",
	&"flash_mon_repeating", &"fade_mons_to_black_repeating",
	&"fade_mon_to_white_wait_fade_back", &"fade_mon_from_white",
	&"shake_screen_x", &"shake_screen_y", &"withdraw", &"bounce_down", &"dig",
	&"tackle", &"body_slam", &"wobble_mon", &"remove_mon", &"wave_deform_mon",
	&"psychic", &"beta_send_out_mon1", &"beta_send_out_mon2", &"flail",
	&"beta_pursuit", &"rollout", &"vital_throw", &"start_water", &"water",
	&"end_water", &"vibrate_mon", &"wobble_player", &"wobble_screen",
]

## pokegold's own table, which is Crystal's without `body_slam`. Everything from
## $25 on therefore sits one lower, and `BATTLE_BG_EFFECT_ROLLOUT` is $2d here
## against Crystal's $2e.
const EFFECTS_GOLD: Array[StringName] = [
	&"end", &"flash_inverted", &"flash_white", &"white_hues", &"black_hues",
	&"alternate_hues", &"cycle_ob_pals_gray_and_yellow",
	&"cycle_mid_ob_pals_gray_and_yellow", &"cycle_bg_pals_inverted",
	&"hide_mon", &"show_mon", &"enter_mon", &"return_mon", &"surf",
	&"whirlpool", &"teleport", &"night_shade", &"battler_obj_1row",
	&"battler_obj_2row", &"double_team", &"acid_armor", &"rapid_flash",
	&"fade_mon_to_light", &"fade_mon_to_black", &"fade_mon_to_light_repeating",
	&"fade_mon_to_black_repeating", &"cycle_mon_light_dark_repeating",
	&"flash_mon_repeating", &"fade_mons_to_black_repeating",
	&"fade_mon_to_white_wait_fade_back", &"fade_mon_from_white",
	&"shake_screen_x", &"shake_screen_y", &"withdraw", &"bounce_down", &"dig",
	&"tackle", &"wobble_mon", &"remove_mon", &"wave_deform_mon",
	&"psychic", &"beta_send_out_mon1", &"beta_send_out_mon2", &"flail",
	&"beta_pursuit", &"rollout", &"vital_throw", &"start_water", &"water",
	&"end_water", &"vibrate_mon", &"wobble_player", &"wobble_screen",
]

## `NUM_BG_EFFECTS`.
const MAX_EFFECTS: int = 5

## `BATTLE_ANIM_OBJ_*`, the four battler-shaped objects `battler_obj_1row` and
## `..._2row` spawn.
const OBJ_ENEMYFEET_1ROW: int = 0xB8
const OBJ_PLAYERHEAD_1ROW: int = 0xB9
const OBJ_ENEMYFEET_2ROW: int = 0xBA
const OBJ_PLAYERHEAD_2ROW: int = 0xBB

## The DMG palette lists the flash and fade effects walk. `$ff` ends one and
## `$fe` sends it back to the start, which is what makes a fade repeat.
const PALS_END: int = 0xFF
const PALS_LOOP: int = 0xFE

const PALS_FLASH_INVERTED: Array[int] = [0xE4, 0x1B]
const PALS_FLASH_WHITE: Array[int] = [0xE4, 0x00]
const PALS_WHITE_HUES: Array[int] = [0xE4, 0xE0, 0xD0, 0xFF]
const PALS_BLACK_HUES: Array[int] = [0xE4, 0xF4, 0xF8, 0xFF]
const PALS_ALTERNATE_HUES: Array[int] = [
	0xE4, 0xF8, 0xFC, 0xF8, 0xE4, 0x90, 0x40, 0x90, 0xFE,
]
const PALS_OB_GRAY_YELLOW: Array[int] = [0xE4, 0x90, 0xFE]
const PALS_MID_OB_GRAY_YELLOW: Array[int] = [0xE4, 0xD8, 0xFE]
const PALS_BG_INVERTED: Array[int] = [0x1B, 0x63, 0x87, 0xFE]
const PALS_RAPID_FLASH: Array[int] = [0xE4, 0x6C, 0xFE]
const PALS_TO_LIGHT: Array[int] = [0xE4, 0x90, 0x40, 0xFF]
const PALS_TO_BLACK: Array[int] = [0xE4, 0xF8, 0xFC, 0xFF]
const PALS_TO_LIGHT_REPEATING: Array[int] = [0xE4, 0x90, 0x40, 0x90, 0xFE]
const PALS_TO_BLACK_REPEATING: Array[int] = [0xE4, 0xF8, 0xFC, 0xF8, 0xFE]
const PALS_LIGHT_DARK_REPEATING: Array[int] = [
	0xE4, 0xF8, 0xFC, 0xF8, 0xE4, 0x90, 0x40, 0x90, 0xFE,
]
const PALS_FLASH_MON_REPEATING: Array[int] = [0xE4, 0xFC, 0xE4, 0x00, 0xFE]
const PALS_TO_WHITE_WAIT_BACK: Array[int] = [
	0xE4, 0x90, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x90, 0xE4, 0xFF,
]
const PALS_FROM_WHITE: Array[int] = [0x00, 0x40, 0x90, 0xE4, 0xFF]

## `BattleBGEffect_FadeMonsToBlackRepeating.CGB_DMGEnemyData`, four pairs the
## `.cgb` branch reads for both sides.
const FADE_MONS_PAIRS: Array[int] = [0xE4, 0xE4, 0xF8, 0x90, 0xFC, 0x40, 0xF8, 0x90]

## `BattleBGEffect_BetaSendOutMon1.data`.
const BETA_SEND_OUT_STEPS: Array[int] = [0x00, 0x40, 0x90, 0xE4, 0xFF]

## `BattleBGEffect_RunPicResizeScript.Coords`, as tile coordinates.
const RESIZE_COORDS: Array = [
	[2, 6], [3, 8], [4, 10], [12, 0], [13, 2], [14, 4],
]

## `.BGSquares`: how big each square is, in `BGSQUARE_*` order.
const RESIZE_SIZES: Array[int] = [6, 4, 2, 7, 5, 3]

## The six squares themselves, each a row-major list of tile offsets added to the
## row's own base tile. They are the cartridge's own subsamplings of the 7x7
## picture, which is why a shrunk picture drops rows rather than scaling.
const RESIZE_SQUARES: Array = [
	[  # BGSQUARE_SIX
		0x00, 0x06, 0x0C, 0x12, 0x18, 0x1E,
		0x01, 0x07, 0x0D, 0x13, 0x19, 0x1F,
		0x02, 0x08, 0x0E, 0x14, 0x1A, 0x20,
		0x03, 0x09, 0x0F, 0x15, 0x1B, 0x21,
		0x04, 0x0A, 0x10, 0x16, 0x1C, 0x22,
		0x05, 0x0B, 0x11, 0x17, 0x1D, 0x23,
	],
	[  # BGSQUARE_FOUR
		0x00, 0x0C, 0x12, 0x1E,
		0x02, 0x0E, 0x14, 0x20,
		0x03, 0x0F, 0x15, 0x21,
		0x05, 0x11, 0x17, 0x23,
	],
	[0x00, 0x1E, 0x05, 0x23],  # BGSQUARE_TWO
	[  # BGSQUARE_SEVEN
		0x00, 0x07, 0x0E, 0x15, 0x1C, 0x23, 0x2A,
		0x01, 0x08, 0x0F, 0x16, 0x1D, 0x24, 0x2B,
		0x02, 0x09, 0x10, 0x17, 0x1E, 0x25, 0x2C,
		0x03, 0x0A, 0x11, 0x18, 0x1F, 0x26, 0x2D,
		0x04, 0x0B, 0x12, 0x19, 0x20, 0x27, 0x2E,
		0x05, 0x0C, 0x13, 0x1A, 0x21, 0x28, 0x2F,
		0x06, 0x0D, 0x14, 0x1B, 0x22, 0x29, 0x30,
	],
	[  # BGSQUARE_FIVE
		0x00, 0x07, 0x15, 0x23, 0x2A,
		0x01, 0x08, 0x16, 0x24, 0x2B,
		0x03, 0x0A, 0x18, 0x26, 0x2D,
		0x05, 0x0C, 0x1A, 0x28, 0x2F,
		0x06, 0x0D, 0x1B, 0x29, 0x30,
	],
	[  # BGSQUARE_THREE
		0x00, 0x15, 0x2A,
		0x03, 0x18, 0x2D,
		0x06, 0x1B, 0x30,
	],
]

## The three pic-resize scripts, as rows of
## [code][square, base tile, coord][/code]. A square of -1 ends the script, -2
## clears a box whose size is the packed second byte, and -3 skips a frame.
const RESIZE_SHOW_PLAYER: Array = [[0, 0x31, 0], [-1, 0, 0]]
const RESIZE_SHOW_ENEMY: Array = [[3, 0x00, 3], [-1, 0, 0]]
const RESIZE_ENTER_PLAYER: Array = [
	[2, 0x31, 2], [1, 0x31, 1], [0, 0x31, 0], [-1, 0, 0],
]
const RESIZE_ENTER_ENEMY: Array = [
	[5, 0x00, 5], [4, 0x00, 4], [3, 0x00, 3], [-1, 0, 0],
]
const RESIZE_RETURN_PLAYER: Array = [
	[0, 0x31, 0], [-2, 0x66, 0], [1, 0x31, 1], [-2, 0x44, 1],
	[2, 0x31, 2], [-2, 0x22, 2], [-3, 0x00, 0], [-1, 0, 0],
]
const RESIZE_RETURN_ENEMY: Array = [
	[3, 0x00, 3], [-2, 0x77, 3], [4, 0x00, 4], [-2, 0x55, 4],
	[5, 0x00, 5], [-2, 0x33, 5], [-3, 0x00, 0], [-1, 0, 0],
]


## The effect table this profile ships. pokegold's is one shorter; nothing
## normalises between them.
static func names_for(profile: StringName) -> Array[StringName]:
	return EFFECTS_CRYSTAL if profile == &"crystal" else EFFECTS_GOLD


## `DoBattleBGEffectFunction`. Answers false when the id is past this profile's
## own table, which cartridge data never asks for.
static func run(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> bool:
	var names: Array[StringName] = names_for(player.profile())
	if effect.id < 0 or effect.id >= names.size():
		return false
	var background: Gen2BattleAnimBackground = player.background()
	match names[effect.id]:
		&"end":
			effect.end()
		&"flash_inverted":
			_flash(background, effect, PALS_FLASH_INVERTED)
		&"flash_white":
			_flash(background, effect, PALS_FLASH_WHITE)
		&"white_hues":
			_hues(background, effect, PALS_WHITE_HUES, false)
		&"black_hues":
			_hues(background, effect, PALS_BLACK_HUES, false)
		&"alternate_hues":
			_hues(background, effect, PALS_ALTERNATE_HUES, true)
		&"cycle_ob_pals_gray_and_yellow":
			background.obp0 = _nth_dmg_pal(effect, PALS_OB_GRAY_YELLOW)
		&"cycle_mid_ob_pals_gray_and_yellow":
			background.obp0 = _nth_dmg_pal(effect, PALS_MID_OB_GRAY_YELLOW)
		&"cycle_bg_pals_inverted":
			background.bgp = _nth_dmg_pal(effect, PALS_BG_INVERTED)
		&"hide_mon":
			_hide_mon(player, effect)
		&"show_mon":
			_show_mon(player, effect)
		&"enter_mon":
			_enter_mon(player, effect)
		&"return_mon":
			_return_mon(player, effect)
		&"surf":
			_surf(background, effect)
		&"whirlpool":
			_whirlpool(player, effect)
		&"teleport":
			_teleport(player, effect)
		&"night_shade":
			_night_shade(player, effect)
		&"battler_obj_1row":
			_battler_obj(player, effect, false)
		&"battler_obj_2row":
			_battler_obj(player, effect, true)
		&"double_team":
			_double_team(player, effect)
		&"acid_armor":
			_acid_armor(player, effect)
		&"rapid_flash":
			_rapid_cycle_pals(player, effect, PALS_RAPID_FLASH)
		&"fade_mon_to_light":
			_rapid_cycle_pals(player, effect, PALS_TO_LIGHT)
		&"fade_mon_to_black":
			_rapid_cycle_pals(player, effect, PALS_TO_BLACK)
		&"fade_mon_to_light_repeating":
			_rapid_cycle_pals(player, effect, PALS_TO_LIGHT_REPEATING)
		&"fade_mon_to_black_repeating":
			_rapid_cycle_pals(player, effect, PALS_TO_BLACK_REPEATING)
		&"cycle_mon_light_dark_repeating":
			_rapid_cycle_pals(player, effect, PALS_LIGHT_DARK_REPEATING)
		&"flash_mon_repeating":
			_rapid_cycle_pals(player, effect, PALS_FLASH_MON_REPEATING)
		&"fade_mons_to_black_repeating":
			_fade_mons_to_black_repeating(player, effect)
		&"fade_mon_to_white_wait_fade_back":
			_rapid_cycle_pals(player, effect, PALS_TO_WHITE_WAIT_BACK)
		&"fade_mon_from_white":
			_rapid_cycle_pals(player, effect, PALS_FROM_WHITE)
		&"shake_screen_x":
			background.scx = _shake_amount(background, effect)
		&"shake_screen_y":
			background.scy = _shake_amount(background, effect)
		&"withdraw":
			_withdraw(player, effect)
		&"bounce_down":
			_bounce_down(player, effect)
		&"dig":
			_dig(player, effect)
		&"tackle":
			_tackle(player, effect, false)
		&"body_slam":
			_tackle(player, effect, true)
		&"wobble_mon":
			_wobble_mon(player, effect)
		&"remove_mon":
			_remove_mon(player, effect)
		&"wave_deform_mon":
			_wave_deform_mon(player, effect)
		&"psychic":
			_psychic(player, effect)
		&"beta_send_out_mon1":
			_beta_send_out_mon1(player, effect)
		&"beta_send_out_mon2":
			_beta_send_out_mon2(player, effect)
		&"flail":
			_flail(player, effect)
		&"beta_pursuit":
			_beta_pursuit(player, effect)
		&"rollout":
			_rollout(player, effect)
		&"vital_throw":
			_vital_throw(player, effect)
		&"start_water":
			background.set_ly_overrides(0)
			_set_lcd_stat_customs(player, effect, Gen2BattleAnimBackground.LCDC_SCY, false)
			effect.end()
		&"water":
			_water(player, effect)
		&"end_water":
			background.reset_lcd_stat_custom()
			effect.end()
		&"vibrate_mon":
			_vibrate_mon(player, effect)
		&"wobble_player":
			_wobble_player(player, effect)
		&"wobble_screen":
			_wobble_screen(player, effect)
		_:
			return false
	return true


# ---------------------------------------------------------------- helpers ----

## `BattleBGEffects_IncAnonJumptableIndex`.
static func _inc(effect: Gen2BattleAnimBgEffect) -> void:
	effect.jumptable_index = (effect.jumptable_index + 1) & 0xFF


## `BGEffect_CheckBattleTurn`: `hBattleTurn` against the effect's own turn byte.
## Non-zero is the player's side, which is what every `.player_side` branch is.
static func _check_battle_turn(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> int:
	return ((1 if player.enemy_turn() else 0) ^ effect.battle_turn) & 0xFF


static func _player_side(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> bool:
	return _check_battle_turn(player, effect) != 0


## `BattleBGEffect_SetLCDStatCustoms1` and `..._Customs2`, which differ only in
## where the player's own window starts. Crystal alone ships the second, and
## `body_slam` and `bounce_down` are the only two that ask for it.
static func _set_lcd_stat_customs(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect,
	pointer: int, second: bool
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	background.lcdc_pointer = pointer
	if _player_side(player, effect):
		background.ly_override_start = 0x2D if second else 0x2F
		background.ly_override_end = 0x5E
		return
	background.ly_override_start = 0x00
	background.ly_override_end = 0x36


## `BattleAnim_ResetLCDStatCustom`, which ends the effect as well.
static func _reset_lcd_stat_custom(
	background: Gen2BattleAnimBackground, effect: Gen2BattleAnimBgEffect
) -> void:
	background.reset_lcd_stat_custom()
	effect.end()


## `BattleBGEffects_Sine` and `..._Cosine`, which are `BattleAnim_Sine_e` far
## called, so they read the same imported `BattleAnimSineWave`.
static func _sine(player: Gen2BattleAnimPlayer, a: int, d: int) -> int:
	return Gen2BattleAnimFunctions.sine_of(player.data(), a, d)


static func _cosine(player: Gen2BattleAnimPlayer, a: int, d: int) -> int:
	return Gen2BattleAnimFunctions.cosine_of(player.data(), a, d)


## `BattleBGEffect_GetNextDMGPal`. Answers -1 for the `$ff` that ends a list;
## `$fe` restarts it and answers the first entry.
static func _next_dmg_pal(
	effect: Gen2BattleAnimBgEffect, pals: Array[int], index: int
) -> int:
	var value: int = pals[index] if index >= 0 and index < pals.size() else PALS_END
	if value == PALS_END:
		return -1
	if value == PALS_LOOP:
		effect.param = 0
		return pals[0]
	return value


## `BattleBGEffect_GetFirstDMGPal`: the entry the parameter names, and the
## parameter stepped on.
static func _first_dmg_pal(effect: Gen2BattleAnimBgEffect, pals: Array[int]) -> int:
	var index: int = effect.param
	effect.param = (effect.param + 1) & 0xFF
	return _next_dmg_pal(effect, pals, index)


## `BattleBGEffect_GetNthDMGPal`: the jumptable index is a countdown between
## steps and the turn byte is how long each step lasts.
static func _nth_dmg_pal(effect: Gen2BattleAnimBgEffect, pals: Array[int]) -> int:
	if effect.jumptable_index != 0:
		effect.jumptable_index = (effect.jumptable_index - 1) & 0xFF
		return _next_dmg_pal(effect, pals, effect.param)
	effect.jumptable_index = effect.battle_turn
	return _first_dmg_pal(effect, pals)


## `DeformScreen`: a sine down the scanline window, sampled every
## [param offset] of a turn.
static func _deform_screen(
	player: Gen2BattleAnimPlayer, amplitude: int, offset: int
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	var progress: int = 0
	for line: int in 0x80:
		if background.ly_override_start < line and background.ly_override_end >= line:
			background.ly_overrides_backup[line] = _sine(player, progress, amplitude)
		progress = (progress + offset) & 0xFF


## `InitSurfWaves`: the 64-entry wave the Surf effect then rotates past the
## window one entry a frame.
static func _init_surf_waves(
	player: Gen2BattleAnimPlayer, amplitude: int, offset: int
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	var progress: int = 0
	for index: int in Gen2BattleAnimBackground.SURF_WAVE_LENGTH:
		background.surf_wave[index] = _sine(player, progress, amplitude)
		progress = (progress + offset) & 0xFF


## `DeformWater`: a wave that grows outwards from one line in both directions,
## stopping at whichever end of the window it reaches first.
static func _deform_water(
	player: Gen2BattleAnimPlayer, timer: int, amplitude: int, offset: int,
	progress: int
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	var page: int = Gen2BattleAnimBackground.LY_PAGE
	var down: int = (background.ly_override_start + progress) & 0xFF
	var up: int = down
	var step: int = offset
	var left: int = timer
	while left != 0:
		left -= 1
		var value: int = _sine(player, step, amplitude)
		if background.ly_override_end >= down:
			background.ly_overrides_backup[down] = value
			down = (down + 1) & (page - 1)
		if background.ly_override_start < up:
			background.ly_overrides_backup[up] = value
			up = (up - 1) & (page - 1)
		step = (step + 4) & 0xFF


## `BattleBGEffect_WavyScreenFX`: the window rotated up one line, the top line
## coming back round to the bottom.
static func _wavy_screen_fx(background: Gen2BattleAnimBackground) -> void:
	var page: int = Gen2BattleAnimBackground.LY_PAGE
	var at: int = background.ly_override_start & 0xFF
	var count: int = (background.ly_override_end - background.ly_override_start) & 0xFF
	if count == 0:
		return
	var first: int = background.ly_overrides_backup[at]
	var from: int = (at + 1) & (page - 1)
	for _step: int in count:
		background.ly_overrides_backup[at] = background.ly_overrides_backup[from]
		at = (at + 1) & (page - 1)
		from = (from + 1) & (page - 1)
	background.ly_overrides_backup[at] = first


# -------------------------------------------------------- palette effects ----

## `BattleBGEffect_FlashContinue`: the turn byte is how long a flash lasts and
## the parameter how many are left.
static func _flash(
	background: Gen2BattleAnimBackground, effect: Gen2BattleAnimBgEffect,
	pals: Array[int]
) -> void:
	if effect.jumptable_index != 0:
		effect.jumptable_index = (effect.jumptable_index - 1) & 0xFF
		return
	effect.jumptable_index = effect.battle_turn
	if effect.param == 0:
		effect.end()
		return
	effect.param = (effect.param - 1) & 0xFF
	background.bgp = pals[effect.param & 1]


## The three hue walks, which end when their list does. `alternate_hues` is the
## one that takes the object palette with it.
static func _hues(
	background: Gen2BattleAnimBackground, effect: Gen2BattleAnimBgEffect,
	pals: Array[int], with_objects: bool
) -> void:
	var value: int = _nth_dmg_pal(effect, pals)
	if value < 0:
		effect.end()
		return
	background.bgp = value
	if with_objects:
		background.obp1 = value


## `BGEffect_RapidCyclePals`, the Color branch: one side of the field at a time,
## and the enemy's own states are the two above the player's.
##
## Nothing here ends the walk. The list's own `$ff` only stalls it; the effect is
## retired by the script's `anim_incbgeffect`, which is what steps it onto the
## state that puts the palette back.
static func _rapid_cycle_pals(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect, pals: Array[int]
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			if not _player_side(player, effect):
				_inc(effect)
				_inc(effect)
			_inc(effect)
			effect.battle_turn = effect.param
			effect.param = 0
		1:
			_rapid_cycle_step(effect, pals, background, true)
		2:
			background.load_player_pals(Gen2BattleAnimBackground.PALETTE_IDENTITY)
			effect.end()
		3:
			_rapid_cycle_step(effect, pals, background, false)
		4:
			background.load_enemy_pals(Gen2BattleAnimBackground.PALETTE_IDENTITY)
			effect.end()


## One step of that walk. The turn byte's low nybble counts the frames between
## steps and its high nybble is what reloads it.
static func _rapid_cycle_step(
	effect: Gen2BattleAnimBgEffect, pals: Array[int],
	background: Gen2BattleAnimBackground, player_side: bool
) -> void:
	if (effect.battle_turn & 0xF) != 0:
		effect.battle_turn = (effect.battle_turn - 1) & 0xFF
		return
	effect.battle_turn = ((effect.battle_turn >> 4) | effect.battle_turn) & 0xFF
	var value: int = _first_dmg_pal(effect, pals)
	if value < 0:
		effect.param = (effect.param - 1) & 0xFF
		return
	if player_side:
		background.load_player_pals(value)
		return
	background.load_enemy_pals(value)


## `BattleBGEffect_FadeMonsToBlackRepeating`, the Color branch: both sides at
## once, the far one taking the other half of each pair.
static func _fade_mons_to_black_repeating(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			effect.param = 0
		1:
			var step: int = effect.param
			effect.param = (effect.param + 1) & 0xFF
			if (step & 0x7) != 0:
				return
			var row: int = ((step & 0x18) >> 3) * 2
			var near: int = FADE_MONS_PAIRS[row]
			var far: int = FADE_MONS_PAIRS[row + 1]
			if _player_side(player, effect):
				background.load_player_pals(near)
				background.load_enemy_pals(far)
				return
			background.load_enemy_pals(near)
			background.load_player_pals(far)
		2:
			background.load_player_pals(Gen2BattleAnimBackground.PALETTE_IDENTITY)
			background.load_enemy_pals(Gen2BattleAnimBackground.PALETTE_IDENTITY)
			effect.end()


# -------------------------------------------------------- tilemap effects ----

## `BattleBGEffect_HideMon`: the battler's own box blanked, then four frames of
## nothing while the tilemap reaches VRAM.
static func _hide_mon(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			if _player_side(player, effect):
				background.clear_box(2, 6, 6, 6)
			else:
				background.clear_box(12, 0, 7, 7)
			# Crystal alone rewinds the push; pokegold leaves whichever third
			# was in flight.
			if player.profile() == &"crystal":
				background.bg_map_third = 0
			background.bg_map_mode = 1
		1, 2, 3:
			_inc(effect)
		4:
			background.bg_map_mode = 0
			effect.end()


## `BattleBGEffect_ShowMon`, which does nothing at all for a battler that is
## off the field mid-Fly or mid-Dig.
static func _show_mon(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	if player.fly_dig_status(_player_side(player, effect)):
		effect.end()
		return
	_run_pic_resize_script(
		player, effect,
		RESIZE_SHOW_PLAYER if _player_side(player, effect) else RESIZE_SHOW_ENEMY
	)


static func _enter_mon(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	_run_pic_resize_script(
		player, effect,
		RESIZE_ENTER_PLAYER if _player_side(player, effect) else RESIZE_ENTER_ENEMY
	)


static func _return_mon(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	_run_pic_resize_script(
		player, effect,
		RESIZE_RETURN_PLAYER if _player_side(player, effect) else RESIZE_RETURN_ENEMY
	)


## `BattleBGEffect_RunPicResizeScript`: one row of the script a frame, with two
## idle frames between so the tilemap reaches VRAM before the next one.
static func _run_pic_resize_script(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect, script: Array
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			# `.clear` loops back into this state with the parameter already
			# stepped on, so one frame can clear a box and place the next square.
			for _step: int in script.size() + 1:
				var index: int = effect.param
				effect.param = (effect.param + 1) & 0xFF
				var row: Array = script[index] if index < script.size() else [-1, 0, 0]
				var square: int = int(row[0])
				if square == -1:
					background.bg_map_mode = 0
					effect.end()
					return
				if square == -2:
					_resize_clear_box(background, int(row[1]), int(row[2]))
					continue
				if square != -3:
					_resize_place_graphic(background, square, int(row[1]), int(row[2]))
				_inc(effect)
				background.bg_map_mode = 1
				return
		1, 2:
			_inc(effect)
		3:
			background.bg_map_mode = 0
			effect.jumptable_index = 0
		4:
			background.bg_map_mode = 0
			effect.end()


## `.ClearBox`: the size is one packed byte, rows in the high nybble.
static func _resize_clear_box(
	background: Gen2BattleAnimBackground, size: int, coord: int
) -> void:
	var at: Array = RESIZE_COORDS[coord]
	background.clear_box(int(at[0]), int(at[1]), (size >> 4) & 0xF, size & 0xF)


## `.PlaceGraphic`: one `BGSquare` stamped at a coordinate, its own offsets added
## to the row's base tile.
static func _resize_place_graphic(
	background: Gen2BattleAnimBackground, square: int, base: int, coord: int
) -> void:
	var side: int = RESIZE_SIZES[square]
	var tiles: Array = RESIZE_SQUARES[square]
	var at: Array = RESIZE_COORDS[coord]
	for row: int in side:
		for column: int in side:
			background.set_tile(
				int(at[0]) + column, int(at[1]) + row,
				(base + int(tiles[row * side + column])) & 0xFF
			)


## `BattleBGEffect_BattlerObj_1Row` and `..._2Row`: an object standing in for the
## row of the picture the tilemap is about to lose.
static func _battler_obj(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect, two_row: bool
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	var player_side: bool = _player_side(player, effect)
	match effect.jumptable_index:
		0:
			if player.fly_dig_status(player_side):
				# The index is stepped on anyway, so the object this effect did
				# not spawn still costs a number.
				player.bump_object_index()
				effect.end()
				return
			_inc(effect)
			var row: int = 0
			var x: int = 0
			if player_side:
				row = OBJ_PLAYERHEAD_2ROW if two_row else OBJ_PLAYERHEAD_1ROW
				x = 6 * 8
			else:
				row = OBJ_ENEMYFEET_2ROW if two_row else OBJ_ENEMYFEET_1ROW
				x = 16 * 8 + 4
			player.queue_object(row, x, 8 * 8, 0)
		1:
			_inc(effect)
			if player_side:
				background.clear_box(2, 6, 2 if two_row else 1, 6)
			elif two_row:
				background.clear_box(12, 5, 2, 7)
			else:
				background.clear_box(12, 6, 1, 7)
			background.bg_map_mode = 1
		2, 3, 4:
			_inc(effect)
		5:
			background.bg_map_mode = 0
			effect.end()


## `BattleBGEffect_RemoveMon`: the picture shifted off its own side of the
## screen a column at a time.
static func _remove_mon(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			# `BGEffect_CheckBattleTurn` leaves the pointer on the turn byte, so
			# the answer is written back over it before it is read again.
			effect.battle_turn = _check_battle_turn(player, effect)
			effect.param = 0x8 if effect.battle_turn == 0 else 0x9
		1:
			if effect.battle_turn == 0:
				for row: int in 7:
					for column: int in 8:
						background.set_tile(
							19 - column, row, background.tile_at(18 - column, row)
						)
			else:
				for row: int in 6:
					for column: int in 8:
						background.set_tile(
							column, 6 + row, background.tile_at(column + 1, 6 + row)
						)
			background.bg_map_third = 0
			background.bg_map_mode = 1
			_inc(effect)
			effect.param = (effect.param - 1) & 0xFF
		2, 3:
			_inc(effect)
		4:
			background.bg_map_mode = 0
			if effect.param == 0:
				effect.end()
				return
			effect.jumptable_index = 0x1


# ------------------------------------------------------- scanline effects ----

## `BattleBGEffect_Surf`, which opens no window of its own: it rides the one
## `start_water` set, and does nothing until it exists.
static func _surf(
	background: Gen2BattleAnimBackground, effect: Gen2BattleAnimBgEffect
) -> void:
	match effect.jumptable_index:
		2:
			background.reset_lcd_stat_custom()
			effect.end()
		_:
			if effect.jumptable_index == 0:
				_inc(effect)
			if background.lcdc_pointer == Gen2BattleAnimBackground.LCDC_OFF:
				return
			_rotate_surf_wave(background)


## `.RotatewSurfWaveBGEffect`: the wave stepped round one entry, then laid over
## the window from its start.
static func _rotate_surf_wave(background: Gen2BattleAnimBackground) -> void:
	var length: int = Gen2BattleAnimBackground.SURF_WAVE_LENGTH
	var first: int = background.surf_wave[0]
	for index: int in length - 1:
		background.surf_wave[index] = background.surf_wave[index + 1]
	background.surf_wave[length - 1] = first

	var wave: int = 0
	for line: int in 0x5F:
		var value: int = 0
		if background.ly_override_start < line:
			value = background.surf_wave[wave]
		background.ly_overrides_backup[line] = value
		wave = (wave + 1) & (length - 1)


static func _whirlpool(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			background.lcdc_pointer = Gen2BattleAnimBackground.LCDC_SCY
			background.ly_override_start = 0x00
			background.ly_override_end = 0x5E
			_deform_screen(player, 2, 2)
		1:
			_wavy_screen_fx(background)
		2:
			_reset_lcd_stat_custom(background, effect)


static func _teleport(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			_set_lcd_stat_customs(
				player, effect, Gen2BattleAnimBackground.LCDC_SCX, false
			)
			_deform_screen(player, 6, 5)
		1:
			_wavy_screen_fx(background)
		2:
			_reset_lcd_stat_custom(background, effect)


static func _night_shade(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			_set_lcd_stat_customs(
				player, effect, Gen2BattleAnimBackground.LCDC_SCY, false
			)
			_deform_screen(player, 2, effect.param)
		1:
			_wavy_screen_fx(background)
		2:
			_reset_lcd_stat_custom(background, effect)


## `BattleBGEffect_Psychic`, which is hard-coded to the opponent's window and
## rotates it only every fourth frame.
static func _psychic(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			background.lcdc_pointer = Gen2BattleAnimBackground.LCDC_SCX
			background.ly_override_start = 0x00
			background.ly_override_end = 0x5F
			_deform_screen(player, 6, 5)
			effect.param = 0x0
		1:
			var step: int = effect.param
			effect.param = (effect.param + 1) & 0xFF
			if (step & 0x3) != 0:
				return
			_wavy_screen_fx(background)
		2:
			_reset_lcd_stat_custom(background, effect)


## `BattleBGEffect_DoubleTeam`: the window split into alternating lines pulled
## opposite ways, so one battler is drawn twice.
static func _double_team(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			_set_lcd_stat_customs(
				player, effect, Gen2BattleAnimBackground.LCDC_SCX, false
			)
			background.ly_override_end = (background.ly_override_end + 1) & 0xFF
			effect.battle_turn = 0x0
		1:
			if effect.param >= 0x10:
				_inc(effect)
				return
			var spread: int = effect.param
			effect.param = (effect.param + 1) & 0xFF
			_double_team_lines(background, spread)
		2:
			var step: int = _sine(player, effect.battle_turn, 0x2)
			_double_team_lines(background, (step + effect.param) & 0xFF)
			effect.battle_turn = (effect.battle_turn + 0x4) & 0xFF
		3:
			if effect.param == 0xFF:
				_inc(effect)
				return
			var spread: int = effect.param
			effect.param = (effect.param - 1) & 0xFF
			_double_team_lines(background, spread)
		4:
			pass
		5:
			_reset_lcd_stat_custom(background, effect)


## `.UpdateLYOverrides`: every other line pulled one way and the rest the other.
static func _double_team_lines(background: Gen2BattleAnimBackground, spread: int) -> void:
	var page: int = Gen2BattleAnimBackground.LY_PAGE
	var at: int = background.ly_override_start & 0xFF
	var span: int = (background.ly_override_end - background.ly_override_start) & 0xFF
	var pairs: int = span >> 1
	var odd: bool = (span & 1) != 0
	var right: int = spread & 0xFF
	var left: int = (-spread) & 0xFF
	for _step: int in (pairs if pairs != 0 else page):
		background.ly_overrides_backup[at] = right
		at = (at + 1) & (page - 1)
		background.ly_overrides_backup[at] = left
		at = (at + 1) & (page - 1)
	if odd:
		background.ly_overrides_backup[at] = right


## `BattleBGEffect_AcidArmor`: the window's lines pushed down one a frame, with
## the two at the far end held clear so the picture melts rather than smears.
static func _acid_armor(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	var page: int = Gen2BattleAnimBackground.LY_PAGE
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			_set_lcd_stat_customs(
				player, effect, Gen2BattleAnimBackground.LCDC_SCY, false
			)
			_deform_screen(player, 2, effect.param)
			background.ly_overrides_backup[background.ly_override_end & 0xFF] = 0x0
			background.ly_overrides_backup[
				(background.ly_override_end - 1) & (page - 1)
			] = 0x0
		1:
			var at: int = background.ly_override_end & 0xFF
			while true:
				background.ly_overrides_backup[at] = \
					background.ly_overrides_backup[(at - 1) & (page - 1)]
				at = (at - 1) & (page - 1)
				if background.ly_override_start == at:
					break
			background.ly_overrides_backup[at] = 0x90

			var last: int = background.ly_override_end & 0xFF
			var value: int = background.ly_overrides_backup[last]
			if value >= 0x1 and value != 0x90:
				background.ly_overrides_backup[last] = 0x0
			last = (last - 1) & (page - 1)
			value = background.ly_overrides_backup[last]
			if value < 0x2 or value == 0x90:
				return
			background.ly_overrides_backup[last] = 0x0
		2:
			_reset_lcd_stat_custom(background, effect)


## `BattleBGEffect_Withdraw`: the window's top pushed off the screen a little
## further each frame, at a speed the parameter's top two bits set.
static func _withdraw(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			_set_lcd_stat_customs(
				player, effect, Gen2BattleAnimBackground.LCDC_SCY, false
			)
			background.ly_override_end = (background.ly_override_end + 1) & 0xFF
			effect.battle_turn = 0x1
		1:
			if effect.battle_turn >= (effect.param & 0x3F):
				return
			background.displace_ly_backup(effect.battle_turn)
			effect.battle_turn = (
				effect.battle_turn + ((effect.param >> 6) & 0x3)
			) & 0xFF
		2:
			_reset_lcd_stat_custom(background, effect)


## `BattleBGEffect_Dig`: the same push, but it steps back a state every eighth
## line so the battler sinks and rises rather than only sinking.
static func _dig(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			_set_lcd_stat_customs(
				player, effect, Gen2BattleAnimBackground.LCDC_SCY, false
			)
			background.ly_override_end = (background.ly_override_end + 1) & 0xFF
			effect.battle_turn = 0x2
			effect.param = 0x0
		1:
			if effect.param != 0:
				effect.param = (effect.param - 1) & 0xFF
				return
			effect.param = 0x10
			_inc(effect)
			_dig_step(background, effect)
		2:
			_dig_step(background, effect)
		3:
			_reset_lcd_stat_custom(background, effect)


static func _dig_step(
	background: Gen2BattleAnimBackground, effect: Gen2BattleAnimBgEffect
) -> void:
	var span: int = (
		background.ly_override_end - background.ly_override_start - 1
	) & 0xFF
	if span < effect.battle_turn:
		return
	if (effect.battle_turn & 0x7) == 0:
		effect.jumptable_index = (effect.jumptable_index - 1) & 0xFF
	background.displace_ly_backup(effect.battle_turn)
	effect.battle_turn = (effect.battle_turn + 2) & 0xFF


## `BattleBGEffect_Tackle` and `..._BodySlam`, which differ only in which
## `SetLCDStatCustoms` they open the window with. pokegold has no BODY SLAM
## effect at all, so `anim_bgeffect $25` there is `wobble_mon`.
static func _tackle(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect, body_slam: bool
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			_set_lcd_stat_customs(
				player, effect, Gen2BattleAnimBackground.LCDC_SCX, body_slam
			)
			background.ly_override_end = (background.ly_override_end + 1) & 0xFF
			effect.param = 0
			# `BGEffect_CheckBattleTurn` moves the pointer onto the turn byte, so
			# the speed lands there and not on the parameter the `ld [hl], 0`
			# above it just cleared.
			effect.battle_turn = 0xFE if _player_side(player, effect) else 0x02
		1:
			_tackle_move_forward(player, effect)
		2:
			_tackle_return_move(player, effect)
		3:
			_reset_lcd_stat_custom(background, effect)


## `Tackle_MoveForward`: eight pixels towards the other side, then the state
## that brings the battler back.
static func _tackle_move_forward(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var moved: int = effect.param
	if moved == 0xF8 or moved == 0x08:
		_inc(effect)
	_rollout_fill_ly_backup(player, moved)
	effect.param = (effect.battle_turn + effect.param) & 0xFF


## `Tackle_ReturnMove`: the same distance negated, which is why the speed byte
## is not written back.
static func _tackle_return_move(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var moved: int = effect.param
	if moved == 0:
		_inc(effect)
	_rollout_fill_ly_backup(player, moved)
	effect.param = (((-effect.battle_turn) & 0xFF) + effect.param) & 0xFF


## `Rollout_FillLYOverridesBackup`: the ordinary fill, unless the animation
## running is ROLLOUT, whose own screen shake has already moved `hSCY` and whose
## window therefore has to be measured from where the screen now is.
static func _rollout_fill_ly_backup(player: Gen2BattleAnimPlayer, value: int) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	if player.anim_index() != Gen2BattleAnimPlayer.ROLLOUT:
		background.fill_ly_backup(value)
		return

	var page: int = Gen2BattleAnimBackground.LY_PAGE
	var span: int = (background.ly_override_end - background.ly_override_start) & 0xFF
	if background.scy == 0:
		if background.ly_override_start != 0:
			background.ly_overrides_backup[
				(background.ly_override_start - 1) & (page - 1)
			] = 0x0
	else:
		background.ly_overrides_backup[
			(background.ly_override_end - 1) & (page - 1)
		] = 0x0

	var at: int = background.ly_override_start - background.scy
	if at < 0:
		at = 0
		span = (span - 1) & 0xFF
	for _step: int in (span if span != 0 else page):
		background.ly_overrides_backup[at & (page - 1)] = value & 0xFF
		at = (at + 1) & (page - 1)


## `VitalThrow_MoveBackwards`: Tackle's opening with the sign the other way
## round, so the battler is knocked back rather than lunging.
static func _vital_throw_move_backwards(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	_inc(effect)
	background.set_ly_overrides(0)
	_set_lcd_stat_customs(player, effect, Gen2BattleAnimBackground.LCDC_SCX, false)
	background.ly_override_end = (background.ly_override_end + 1) & 0xFF
	effect.param = 0x0
	effect.battle_turn = 0x02 if _player_side(player, effect) else 0xFE


static func _vital_throw(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	match effect.jumptable_index:
		0:
			_vital_throw_move_backwards(player, effect)
		1:
			_tackle_move_forward(player, effect)
		2:
			pass
		3:
			_tackle_return_move(player, effect)
		4:
			player.background().reset_lcd_stat_custom()
			effect.end()


static func _beta_pursuit(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	match effect.jumptable_index:
		0:
			_vital_throw_move_backwards(player, effect)
		1:
			_tackle_move_forward(player, effect)
		2:
			_tackle_return_move(player, effect)
		3:
			_reset_lcd_stat_custom(player.background(), effect)


static func _wobble_mon(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			_set_lcd_stat_customs(
				player, effect, Gen2BattleAnimBackground.LCDC_SCX, false
			)
			background.ly_override_end = (background.ly_override_end + 1) & 0xFF
			effect.param = 0x0
		1:
			background.fill_ly_backup(_sine(player, effect.param, 0x8))
			effect.param = (effect.param + 0x4) & 0xFF
		2:
			_reset_lcd_stat_custom(background, effect)


## `BattleBGEffect_Flail`: two sines at once, a wide slow one and a narrow fast
## one, so the battler wobbles rather than swinging.
static func _flail(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			_set_lcd_stat_customs(
				player, effect, Gen2BattleAnimBackground.LCDC_SCX, false
			)
			background.ly_override_end = (background.ly_override_end + 1) & 0xFF
			effect.battle_turn = 0
			effect.param = 0
		1:
			var wide: int = _sine(player, effect.param, 0x6)
			var narrow: int = _sine(player, effect.battle_turn, 0x2)
			background.fill_ly_backup((wide + narrow) & 0xFF)
			effect.battle_turn = (effect.battle_turn + 0x8) & 0xFF
			effect.param = (effect.param + 0x2) & 0xFF
		2:
			_reset_lcd_stat_custom(background, effect)


## `BattleBGEffect_WaveDeformMon`: the deformation wound up to $20 and then back
## down again, with `anim_incbgeffect` between the two halves.
static func _wave_deform_mon(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			_set_lcd_stat_customs(
				player, effect, Gen2BattleAnimBackground.LCDC_SCX, false
			)
		1:
			if effect.param >= 0x20:
				return
			var amplitude: int = effect.param
			effect.param = (effect.param + 1) & 0xFF
			_deform_screen(player, amplitude, 4)
		2:
			if effect.param == 0:
				_reset_lcd_stat_custom(background, effect)
				return
			var amplitude: int = effect.param
			effect.param = (effect.param - 1) & 0xFF
			_deform_screen(player, amplitude, 4)


## `BattleBGEffect_BounceDown`, the other effect Crystal alone opens with
## `SetLCDStatCustoms2`.
static func _bounce_down(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			_set_lcd_stat_customs(
				player, effect, Gen2BattleAnimBackground.LCDC_SCY,
				player.profile() == &"crystal"
			)
			background.ly_override_end = (background.ly_override_end + 1) & 0xFF
			effect.battle_turn = 0x1
			effect.param = 0x20
		1:
			if effect.battle_turn >= 0x38:
				return
			var height: int = (_cosine(player, effect.param, 0x10) + 0x10) & 0xFF
			background.displace_ly_backup((effect.battle_turn + height) & 0xFF)
			effect.param = (effect.param + 2) & 0xFF
		2:
			_reset_lcd_stat_custom(background, effect)


static func _vibrate_mon(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			_set_lcd_stat_customs(
				player, effect, Gen2BattleAnimBackground.LCDC_SCX, false
			)
			background.ly_override_end = (background.ly_override_end + 1) & 0xFF
			effect.battle_turn = 0x1
			effect.param = 0x20
		1:
			if effect.param == 0:
				_reset_lcd_stat_custom(background, effect)
				return
			var left: int = effect.param
			effect.param = (effect.param - 1) & 0xFF
			if (left & 0x1) != 0:
				return
			effect.battle_turn = (-effect.battle_turn) & 0xFF
			background.fill_ly_backup(effect.battle_turn)


## `BattleBGEffect_WobblePlayer`, whose window is the player's whatever the turn
## is, and which stops on its own rather than on `anim_incbgeffect`.
static func _wobble_player(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(0)
			background.lcdc_pointer = Gen2BattleAnimBackground.LCDC_SCX
			background.ly_override_start = 0x00
			background.ly_override_end = 0x37
			effect.param = 0x0
		1:
			if effect.param >= 0x40:
				_reset_lcd_stat_custom(background, effect)
				return
			background.fill_ly_backup(_sine(player, effect.param, 0x6))
			effect.param = (effect.param + 0x2) & 0xFF
		2:
			_reset_lcd_stat_custom(background, effect)


## `BattleBGEffect_WobbleScreen`, which scrolls the whole screen rather than a
## window and never ends: it settles at zero and stays in its slot until the
## next animation clears it.
static func _wobble_screen(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	if effect.param >= 0x40:
		background.scx = 0
		return
	background.scx = _sine(player, effect.param, 0x6)
	effect.param = (effect.param + 0x2) & 0xFF


## `BattleBGEffects_GetShakeAmount`: how far the screen is thrown this frame.
## The jumptable index counts the frames left and the parameter's low nybble the
## frames between reversals, reloaded from its own high nybble.
static func _shake_amount(
	_background: Gen2BattleAnimBackground, effect: Gen2BattleAnimBgEffect
) -> int:
	if effect.jumptable_index == 0:
		effect.end()
		return 0
	effect.jumptable_index = (effect.jumptable_index - 1) & 0xFF
	if (effect.param & 0xF) != 0:
		effect.param = (effect.param - 1) & 0xFF
		return effect.battle_turn
	effect.param = ((effect.param >> 4) | effect.param) & 0xFF
	effect.battle_turn = (-effect.battle_turn) & 0xFF
	return effect.battle_turn


## `BattleBGEffect_Rollout`: the screen shaken vertically, with the first
## animation object moved the opposite way so the ball it draws stays put.
##
## The source waits a frame here rather than at the bottom of `.playframe`;
## in a player stepped once per frame that is the same one frame either way.
static func _rollout(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	var ended: bool = effect.jumptable_index == 0
	var amount: int = _shake_amount(background, effect)
	if ended or (amount & 0x80) != 0:
		amount = 0
	background.scy = amount
	player.set_first_object_y_offset((-amount) & 0xFF)


static func _water(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	var offset: int = effect.param
	effect.param = (effect.param + 0x4) & 0xFF
	var amplitude: int = ((~((effect.battle_turn & 0xF0) >> 4)) + 4) & 0xFF
	var progress: int = effect.jumptable_index
	var timer: int = effect.battle_turn
	if timer >= 0x20:
		background.set_ly_overrides(0)
		effect.end()
		return
	effect.battle_turn = (effect.battle_turn + 2) & 0xFF
	_deform_water(player, timer, amplitude, offset, progress)


## `BattleBGEffect_BetaSendOutMon1`, unused: a four-step palette walk laid over
## alternating scanlines through `rBGP`.
static func _beta_send_out_mon1(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	var page: int = Gen2BattleAnimBackground.LY_PAGE
	match effect.jumptable_index:
		0:
			_inc(effect)
			background.set_ly_overrides(Gen2BattleAnimBackground.PALETTE_IDENTITY)
			_set_lcd_stat_customs(
				player, effect, Gen2BattleAnimBackground.LCDC_BGP, false
			)
			background.ly_override_end = (background.ly_override_end + 1) & 0xFF
			var at: int = background.ly_override_start & 0xFF
			while background.ly_override_end != at:
				background.ly_overrides_backup[at] = 0
				at = (at + 1) & (page - 1)
			effect.param = 0x0
		1, 4:
			pass
		2:
			var step: int = _beta_send_out_step(effect)
			if step < 0:
				effect.param = 0x0
				background.ly_override_start = \
					(background.ly_override_start + 1) & 0xFF
				_inc(effect)
				return
			_beta_send_out_lines(background, step)
		3:
			var step: int = _beta_send_out_step(effect)
			if step < 0:
				_inc(effect)
				return
			_beta_send_out_lines(background, step)
			background.ly_overrides_backup[
				(background.ly_override_end - 1) & (page - 1)
			] = step
		5:
			background.reset_video_hram()


## `.GetLYOverride`: one entry of the walk every eight frames, -1 past its end.
static func _beta_send_out_step(effect: Gen2BattleAnimBgEffect) -> int:
	var index: int = effect.param >> 3
	effect.param = (effect.param + 1) & 0xFF
	var value: int = BETA_SEND_OUT_STEPS[index] \
		if index < BETA_SEND_OUT_STEPS.size() else 0xFF
	return -1 if value == 0xFF else value


## `.SetLYOverridesBackup`: every other line of the window.
static func _beta_send_out_lines(
	background: Gen2BattleAnimBackground, value: int
) -> void:
	var page: int = Gen2BattleAnimBackground.LY_PAGE
	var at: int = background.ly_override_start & 0xFF
	var pairs: int = (
		(background.ly_override_end - background.ly_override_start) & 0xFF
	) >> 1
	for _step: int in (pairs if pairs != 0 else page):
		background.ly_overrides_backup[at] = value & 0xFF
		at = (at + 2) & (page - 1)


## `BattleBGEffect_BetaSendOutMon2`, unused: a deformation that shrinks to
## nothing over $40 frames.
static func _beta_send_out_mon2(
	player: Gen2BattleAnimPlayer, effect: Gen2BattleAnimBgEffect
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	if effect.jumptable_index == 0:
		_inc(effect)
		background.set_ly_overrides(0)
		_set_lcd_stat_customs(
			player, effect, Gen2BattleAnimBackground.LCDC_SCX, false
		)
		effect.battle_turn = 0x40
		return
	if effect.battle_turn == 0:
		_reset_lcd_stat_custom(background, effect)
		return
	var size: int = effect.battle_turn
	effect.battle_turn = (effect.battle_turn - 1) & 0xFF
	var deform: int = (size >> 3) & 0xF
	_deform_screen(player, deform, deform)
