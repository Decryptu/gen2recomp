extends GutTest

## The `BATTLE_BG_EFFECT_*` jumptable and the video state it writes
## (engine/battle_anims/bg_effects.asm).
##
## Effects are built and stepped by hand, the way the motion callbacks are: what
## is worth checking here is which byte of the scanline table, the tilemap or the
## palette map a state writes, and where the two profiles' own tables part
## company. `tools/checks/battle_anims.gd` is the counterpart that runs every
## effect a real animation reaches, on all three cartridges.

const BASE: int = 0x4000
const RET: int = 0xFF

## Effect ids, Crystal's own numbering.
const HIDE_MON: int = 0x09
const SHAKE_SCREEN_X: int = 0x1F
const WITHDRAW: int = 0x21
const TACKLE: int = 0x24
const BODY_SLAM: int = 0x25
const REMOVE_MON: int = 0x27
const ROLLOUT: int = 0x2E
const WHITE_HUES: int = 0x03
const ALTERNATE_HUES: int = 0x05

var _player: Gen2BattleAnimPlayer = null


func before_each() -> void:
	_player = _make_player()


func _make_player(
	profile: StringName = &"crystal", enemy_turn: bool = false
) -> Gen2BattleAnimPlayer:
	var sine := PackedByteArray()
	for value: int in RomLayout.BATTLE_ANIM_SINE_WAVE:
		sine.append(value)
	var data: Gen2BattleAnimData = Gen2BattleAnimData.create({
		&"scripts": {
			"bank": 0x32, "address": BASE, "count": 1,
			"data": PackedByteArray([(BASE + 2) & 0xFF, (BASE + 2) >> 8, RET]),
		},
		&"objects": {
			"bank": 0x33, "address": BASE, "count": 1,
			"data": PackedByteArray([0x00, 0x90, 0x00, 0x00, 0x02, 0x01]),
		},
		&"framesets": {"bank": 0x33, "address": BASE, "count": 0, "data": PackedByteArray()},
		&"oam_sets": {"bank": 0x33, "address": BASE, "count": 0, "data": PackedByteArray()},
	}, [], sine, profile)
	return Gen2BattleAnimPlayer.create(data, 0, enemy_turn)


func _effect(
	id: int, jumptable_index: int = 0, battle_turn: int = 0, param: int = 0
) -> Gen2BattleAnimBgEffect:
	return Gen2BattleAnimBgEffect.create(id, jumptable_index, battle_turn, param)


func _run(effect: Gen2BattleAnimBgEffect) -> void:
	assert_true(Gen2BattleAnimBgEffects.run(_player, effect))


func _background() -> Gen2BattleAnimBackground:
	return _player.background()


# --------------------------------------------------------- the profile split ----

## pokegold ships no `BATTLE_BG_EFFECT_BODY_SLAM`, so its list is one shorter and
## every id from $25 on names a different effect. Nothing normalises between the
## two, which is why both tables are held whole.
func test_the_two_profiles_keep_their_own_effect_tables() -> void:
	var crystal: Array[StringName] = Gen2BattleAnimBgEffects.names_for(&"crystal")
	var gold: Array[StringName] = Gen2BattleAnimBgEffects.names_for(&"gold")
	assert_eq(crystal.size(), 54)
	assert_eq(gold.size(), 53)
	assert_eq(crystal[BODY_SLAM], &"body_slam")
	assert_eq(gold[BODY_SLAM], &"wobble_mon")
	assert_eq(crystal[ROLLOUT], &"rollout")
	assert_eq(gold[0x2D], &"rollout", "one lower on Gold and Silver")
	for id: int in BODY_SLAM:
		assert_eq(crystal[id], gold[id], "the two lists agree below $25")


## The same byte therefore runs a different routine in the two games: on Crystal
## $25 opens a scanline window, on Gold and Silver it starts a wobble.
func test_the_same_id_runs_a_different_effect_in_each_game() -> void:
	var crystal: Gen2BattleAnimBgEffect = _effect(BODY_SLAM)
	_run(crystal)
	assert_eq(
		_background().ly_override_start, 0x00,
		"body_slam opens the enemy window over rSCX"
	)
	assert_eq(_background().lcdc_pointer, Gen2BattleAnimBackground.LCDC_SCX)

	_player = _make_player(&"gold")
	var gold: Gen2BattleAnimBgEffect = _effect(BODY_SLAM)
	_run(gold)
	assert_eq(_background().lcdc_pointer, Gen2BattleAnimBackground.LCDC_SCX)
	assert_eq(gold.param, 0x0, "wobble_mon clears its own parameter instead")


## Crystal alone ships `BattleBGEffect_SetLCDStatCustoms2`, and `bounce_down` is
## one of the two effects that ask for it. Its window starts two lines higher.
func test_only_crystal_has_the_second_lcd_stat_window() -> void:
	var crystal: Gen2BattleAnimBgEffect = _effect(0x22, 0, 1)
	_run(crystal)
	assert_eq(_background().ly_override_start, 0x2D)

	_player = _make_player(&"gold")
	var gold: Gen2BattleAnimBgEffect = _effect(0x22, 0, 1)
	_run(gold)
	assert_eq(_background().ly_override_start, 0x2F)


## The other code-level split: Crystal rewinds the tilemap push and pokegold
## leaves whichever third was in flight.
func test_only_crystal_rewinds_the_tilemap_push() -> void:
	_background().bg_map_third = 2
	_run(_effect(HIDE_MON))
	assert_eq(_background().bg_map_third, 0)

	_player = _make_player(&"gold")
	_background().bg_map_third = 2
	_run(_effect(HIDE_MON))
	assert_eq(_background().bg_map_third, 2)


# ------------------------------------------------------------------ the pool ----

## `QueueBGEffect` takes the first free slot and a sixth effect simply is not
## queued, the way an eleventh object is not spawned.
func test_five_effects_run_at_once_and_a_sixth_is_refused() -> void:
	var body: Array = []
	for queued: int in 6:
		body.append_array([0xF0, SHAKE_SCREEN_X, 0x10, 0x01, 0x11])
	body.append_array([0x01, RET])
	var player: Gen2BattleAnimPlayer = _script_player(body)
	player.advance_frame()
	assert_eq(player.bg_effects().size(), Gen2BattleAnimPlayer.MAX_BG_EFFECTS)


## `EndBattleBGEffect` zeroes the id, which is what frees the slot.
func test_an_ended_effect_frees_its_slot() -> void:
	var effect: Gen2BattleAnimBgEffect = _effect(SHAKE_SCREEN_X, 0x0, 0x01, 0x11)
	assert_true(effect.active())
	_run(effect)
	assert_false(effect.active(), "a shake with no frames left ends at once")


## `anim_incbgeffect` finds a live effect by its id and steps its state, which is
## how a fade is told to put the palette back.
func test_incbgeffect_finds_a_live_effect_by_its_id() -> void:
	var player: Gen2BattleAnimPlayer = _script_player(
		[0xF0, WITHDRAW, 0x00, 0x00, 0x08] + [0x01] + [0xD8, WITHDRAW] + [0x01, RET]
	)
	player.advance_frame()
	var effects: Array = player.bg_effects()
	assert_eq(effects.size(), 1)
	var effect: Gen2BattleAnimBgEffect = effects[0]
	var before: int = effect.jumptable_index
	player.advance_frame()
	player.advance_frame()
	assert_eq(effect.jumptable_index, before + 1)


# ---------------------------------------------------------------- the screen ----

## `BGEffect_FillLYOverridesBackup` writes one value across the window and
## nothing outside it.
func test_a_fill_covers_the_window_and_stops() -> void:
	var background: Gen2BattleAnimBackground = _background()
	background.ly_override_start = 0x10
	background.ly_override_end = 0x14
	background.fill_ly_backup(0x33)
	assert_eq(background.ly_overrides_backup[0x0F], 0)
	assert_eq(background.ly_overrides_backup[0x10], 0x33)
	assert_eq(background.ly_overrides_backup[0x13], 0x33)
	assert_eq(background.ly_overrides_backup[0x14], 0)


## `BGEffect_DisplaceLYOverridesBackup` pushes the first lines off the screen
## with `$90` and holds the rest at the negated displacement.
func test_a_displacement_pushes_lines_off_and_holds_the_rest() -> void:
	var background: Gen2BattleAnimBackground = _background()
	background.ly_override_start = 0x00
	background.ly_override_end = 0x08
	background.displace_ly_backup(0x03)
	assert_eq(background.ly_overrides_backup[0x00], 0x90)
	assert_eq(background.ly_overrides_backup[0x02], 0x90)
	assert_eq(background.ly_overrides_backup[0x03], 0xFC, "-3 as a byte")
	assert_eq(background.ly_overrides_backup[0x07], 0xFC)


## `PushLYOverrides` only copies while a register is named, so a table left over
## from a finished effect does not reach the hardware.
func test_the_scanline_table_is_only_pushed_while_a_register_is_named() -> void:
	var background: Gen2BattleAnimBackground = _background()
	background.ly_overrides_backup[0x20] = 0x44
	background.push_ly_overrides()
	assert_eq(background.ly_overrides[0x20], 0, "no register named")

	background.lcdc_pointer = Gen2BattleAnimBackground.LCDC_SCX
	background.push_ly_overrides()
	assert_eq(background.ly_overrides[0x20], 0x44)


## `BattleAnim_ResetLCDStatCustom` hands the window back and ends the effect in
## one go, which is what every `.two` state is.
func test_resetting_the_window_ends_the_effect() -> void:
	var effect: Gen2BattleAnimBgEffect = _effect(0x0E, 2)  # whirlpool
	_run(effect)
	assert_eq(_background().lcdc_pointer, Gen2BattleAnimBackground.LCDC_OFF)
	assert_eq(_background().ly_override_end, 0)
	assert_false(effect.active())


## `BattleBGEffects_GetShakeAmount` reloads its frame counter from the
## parameter's own high nybble, which is what makes a shake reverse on a beat.
func test_a_shake_reverses_on_its_parameters_own_beat() -> void:
	var effect: Gen2BattleAnimBgEffect = _effect(SHAKE_SCREEN_X, 0x10, 0x04, 0x30)
	_run(effect)
	assert_eq(_background().scx, 0xFC, "-4, and the low nybble is reloaded to 3")
	assert_eq(effect.param, 0x33)
	_run(effect)
	assert_eq(_background().scx, 0xFC, "held while the counter runs down")
	assert_eq(effect.param, 0x32)


## `BattleBGEffect_Rollout` shakes the screen vertically and moves the first
## animation object the other way, so what it draws stays where it was.
func test_rollout_moves_the_first_object_against_the_screen() -> void:
	var effect: Gen2BattleAnimBgEffect = _effect(ROLLOUT, 0x10, 0x04, 0x30)
	_run(effect)
	assert_eq(_background().scy, 0x00, "a negative shake is dropped")
	var objects: Array = _player.objects()
	assert_eq(objects.size(), 0, "the effect writes the struct, it does not spawn")

	var upward: Gen2BattleAnimBgEffect = _effect(ROLLOUT, 0x10, 0xFC, 0x30)
	_run(upward)
	assert_eq(_background().scy, 0x04)


# --------------------------------------------------------------- the palettes ----

## The hue walks end when their list does, and `alternate_hues` is the one that
## takes an object palette with it.
func test_a_hue_walk_ends_on_its_own_list() -> void:
	var effect: Gen2BattleAnimBgEffect = _effect(WHITE_HUES, 0, 0, 0)
	_run(effect)
	assert_eq(_background().bgp, 0xE4)
	_run(effect)
	assert_eq(_background().bgp, 0xE0)
	_run(effect)
	assert_eq(_background().bgp, 0xD0)
	_run(effect)
	assert_false(effect.active(), "the $ff at the end of the list")


func test_alternate_hues_moves_the_object_palette_too() -> void:
	var effect: Gen2BattleAnimBgEffect = _effect(ALTERNATE_HUES, 0, 0, 1)
	_run(effect)
	assert_eq(_background().bgp, 0xF8)
	assert_eq(_background().obp1, 0xF8)


## A list ending in `$fe` restarts rather than stopping, which is what makes a
## fade repeat until `anim_incbgeffect` retires it.
func test_a_looping_list_restarts_rather_than_ending() -> void:
	var effect: Gen2BattleAnimBgEffect = _effect(0x08, 0, 0, 0)  # cycle_bg_pals_inverted
	for _step: int in 3:
		_run(effect)
	assert_true(effect.active())
	_run(effect)
	assert_eq(_background().bgp, 0x1B, "back to the first entry")
	assert_eq(effect.param, 0, "$fe rewinds the parameter as well")


## `BattleAnimRequestPals` is what turns a changed DMG palette byte into a remap
## of the Color palettes, which is the only reason those effects show at all.
func test_a_changed_dmg_byte_remaps_the_colour_palettes() -> void:
	var background: Gen2BattleAnimBackground = _background()
	background.bgp = 0xF8
	background.request_pals()
	assert_eq(background.bg_palette_maps[0], 0xF8)
	assert_eq(background.bg_palette_maps[6], 0xF8)
	assert_eq(
		background.bg_palette_maps[7], Gen2BattleAnimBackground.PALETTE_IDENTITY,
		"seven palettes, not eight"
	)
	assert_eq(background.ob_palette_maps[1], 0xF8)
	assert_true(background.palettes_dirty)

	background.palettes_dirty = false
	background.request_pals()
	assert_false(background.palettes_dirty, "an unchanged byte asks for nothing")


## `BGEffects_LoadPlayerPals` and `..._LoadEnemyPals` reach one side of the field
## each, which is how a fade darkens one battler and not the other.
func test_a_fade_reaches_one_side_of_the_field() -> void:
	var background: Gen2BattleAnimBackground = _background()
	background.load_player_pals(0x40)
	assert_eq(background.bg_palette_maps[Gen2BattleAnimBackground.PAL_BG_PLAYER], 0x40)
	assert_eq(background.ob_palette_maps[Gen2BattleAnimBackground.PAL_OB_PLAYER], 0x40)
	assert_eq(
		background.bg_palette_maps[Gen2BattleAnimBackground.PAL_BG_ENEMY],
		Gen2BattleAnimBackground.PALETTE_IDENTITY
	)


# ---------------------------------------------------------------- the tilemap ----

## `BattleBGEffect_HideMon` blanks the battler's own box and then spends four
## frames doing nothing while the tilemap reaches VRAM.
func test_hiding_a_mon_blanks_its_box_and_then_waits() -> void:
	var background: Gen2BattleAnimBackground = _background()
	for y: int in 7:
		for x: int in 7:
			background.set_tile(12 + x, y, 0x20)
	var effect: Gen2BattleAnimBgEffect = _effect(HIDE_MON)
	_run(effect)
	assert_eq(background.tile_at(12, 0), Gen2BattleAnimBackground.BLANK_TILE)
	assert_eq(background.tile_at(18, 6), Gen2BattleAnimBackground.BLANK_TILE)
	assert_eq(background.bg_map_mode, 1)
	for _step: int in 3:
		_run(effect)
		assert_true(effect.active())
	_run(effect)
	assert_eq(background.bg_map_mode, 0)
	assert_false(effect.active())


## `BattleBGEffect_RemoveMon` slides the picture off its own side of the screen a
## column at a time, and the parameter is how many columns are left.
func test_removing_a_mon_slides_its_columns_off_the_screen() -> void:
	var background: Gen2BattleAnimBackground = _background()
	background.set_tile(18, 0, 0x55)
	var effect: Gen2BattleAnimBgEffect = _effect(REMOVE_MON)
	_run(effect)
	assert_eq(effect.param, 0x8, "the enemy's own eight columns")
	_run(effect)
	assert_eq(background.tile_at(19, 0), 0x55, "shifted one column right")
	assert_eq(effect.param, 0x7)


## `BattleBGEffect_EnterMon` stamps the picture at three growing sizes, one row
## of its script a frame with two idle frames between.
func test_a_mon_entering_is_stamped_at_three_sizes() -> void:
	var background: Gen2BattleAnimBackground = _background()
	var effect: Gen2BattleAnimBgEffect = _effect(0x0B)  # enter_mon
	_run(effect)
	assert_eq(
		background.tile_at(14, 4), 0x00,
		"the three-by-three square at the enemy's third coordinate"
	)
	assert_eq(background.tile_at(16, 6), 0x30, "its own bottom-right offset")
	assert_eq(background.bg_map_mode, 1)
	# Three idle states between rows, so a stamp lands every fourth frame.
	for _step: int in 4:
		_run(effect)
	assert_eq(background.tile_at(13, 2), 0x00, "then the five-by-five")
	for _step: int in 4:
		_run(effect)
	assert_eq(background.tile_at(12, 0), 0x00, "then the whole seven-by-seven")
	assert_eq(background.tile_at(18, 6), 0x30)


# ------------------------------------------------------------------- helpers ----

## A player whose script is [param body], so the queueing commands can be driven
## through the interpreter rather than called directly.
func _script_player(body: Array) -> Gen2BattleAnimPlayer:
	var bytes := PackedByteArray()
	bytes.append((BASE + 2) & 0xFF)
	bytes.append((BASE + 2) >> 8)
	for value: int in body:
		bytes.append(value & 0xFF)
	var sine := PackedByteArray()
	for value: int in RomLayout.BATTLE_ANIM_SINE_WAVE:
		sine.append(value)
	var data: Gen2BattleAnimData = Gen2BattleAnimData.create({
		&"scripts": {"bank": 0x32, "address": BASE, "count": 1, "data": bytes},
		&"objects": {
			"bank": 0x33, "address": BASE, "count": 1,
			"data": PackedByteArray([0x00, 0x90, 0x00, 0x00, 0x02, 0x01]),
		},
		&"framesets": {"bank": 0x33, "address": BASE, "count": 0, "data": PackedByteArray()},
		&"oam_sets": {"bank": 0x33, "address": BASE, "count": 0, "data": PackedByteArray()},
	}, [], sine)
	return Gen2BattleAnimPlayer.create(data, 0)
