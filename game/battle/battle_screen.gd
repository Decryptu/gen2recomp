class_name Gen2BattleScreen
extends Control

signal battle_finished(result: Dictionary)
signal capture_requested(ball: int)
## A bag item spent inside the battle, so the world takes one off the pocket.
## `target` is the party index an ITEMMENU_PARTY item was used on, or -1.
signal item_used(item: int, target: int)
## `LoadEnemyMon`'s own `wPokedexSeen` write (engine/battle/core.asm:6407). Every
## enemy sent out sets it, a trainer's party as much as a wild, so this is the
## event rather than the battle result. The host owns the flag, since the battle
## engine is scene-free and holds no world state.
signal enemy_seen(species: int)

## Owns the battle, the events and the text box; decides nothing about how they
## are drawn. A [Gen2Battle] resolves the turn and answers with events; this
## shows them one at a time, reading every number out of the event rather than
## asking the engine again, which is why the setters still take plain values.
##
## Presentation is a registered renderer, the same boundary the overworld's map
## goes through: [method _push_view] hands plain display values to whatever
## [Gen2ModHost] constructs, and the text box stays hardware pixels over it, as
## menus do over the world renderer.

## `anim_sound` and `anim_cry` have to reach a player, and a battle had none:
## this is the world screen's own route (`game/world/world_screen.gd`).
const AUDIO_PLAYER_SCRIPT := preload("res://game/audio/gen2_audio_player.gd")

## What is on screen before a caller says otherwise: the first battle a player
## of Gold or Silver is likely to have.
const DEFAULT_ENEMY: int = 16
const DEFAULT_PLAYER: int = 155
const DEFAULT_LEVEL: int = 5

## How many Pokémon [method _party_from] makes up for the fallback development
## matchup. A validated save supplies the player's real party instead.
const PARTY_SIZE: int = 2

## What a status says when it stops a Pokémon moving, and when it lands on one.
## Keyed by the names [Gen2Status] answers with, so a status the engine grows
## later shows up here as a missing key rather than as a wrong sentence.
const STOPPED_BY: Dictionary = {
	&"sleep": "is fast asleep!",
	&"freeze": "is frozen solid!",
	&"paralysis": "is fully paralyzed!",
	&"flinch": "flinched!",
	&"recharge": "must recharge!",
	&"disabled": "is disabled!",
	&"attract": "is immobilized by love!",
}

const INFLICTED: Dictionary = {
	&"sleep": "fell asleep!",
	&"poison": "was poisoned!",
	&"toxic": "was badly poisoned!",
	&"burn": "was burned!",
	&"freeze": "was frozen solid!",
	&"paralysis": "is paralyzed!",
}

## What a two-turn move says on its charge turn, from
## `BattleCommand_Charge.UsedText` (data/text/common_2.asm), which picks its line
## by move number rather than by effect: Fly and Dig share an effect byte and do
## not share a sentence.
##
## The source's own `line` is a line break in a fixed-width box rather than part
## of the sentence, so these read as one flowing string the way every other
## message here does.
const CHARGE_TEXT: Dictionary = {
	Gen2MoveEffect.RAZOR_WIND_MOVE: "made a whirlwind!",
	Gen2MoveEffect.SOLARBEAM_MOVE: "took in sunlight!",
	Gen2MoveEffect.SKULL_BASH_MOVE: "lowered its head!",
	Gen2MoveEffect.SKY_ATTACK_MOVE: "is glowing!",
	Gen2MoveEffect.FLY_MOVE: "flew up high!",
	Gen2MoveEffect.DIG_MOVE: "dug a hole!",
}
## `.UsedText`'s own fallthrough: the Dig branch is the only one of the six with
## no `jr z` behind it, so a move that is none of the other five prints its line.
const CHARGE_DUG: String = "dug a hole!"

## The word the games print for a stat, keyed the way [Gen2BattleMon] keeps the
## stat itself. A key the engine grows later shows up here as its own snake_case
## name in capitals rather than as a wrong word, the same fallback
## [method _battler_name] gives a status it does not recognise.
const STAT_NAMES: Dictionary = {
	"attack": "ATTACK",
	"defense": "DEFENSE",
	"speed": "SPEED",
	"sp_attack": "SP.ATK",
	"sp_defense": "SP.DEF",
	"accuracy": "ACCURACY",
	"evasion": "EVASIVENESS",
	# `StatNames`' eighth row, which no stat uses: `BattleCommand_Curse` names it
	# when neither Attack nor Defense can rise.
	"ability": "ABILITY",
}

## The three trapping moves whose landing line spells the move out, since
## `BattleCommand_TrapTarget`'s `.Traps` table writes them into the text rather
## than reading a name buffer. Fire Spin and Whirlpool share the line that names
## nothing, so neither needs a number here.
const BIND: int = 20
const WRAP: int = 35
const CLAMP: int = 128

## The three lines each weather has, which are the cartridge's own and are keyed
## by the weather rather than by the move: `HandleWeather`'s `.WeatherMessages`
## and `.WeatherEndedMessages`, plus each setter's own.
const WEATHER_STARTED_TEXT: Dictionary = {
	Gen2Weather.RAIN: "A downpour started!",
	Gen2Weather.SUN: "The sunlight got bright!",
	Gen2Weather.SANDSTORM: "A SANDSTORM brewed!",
}
const WEATHER_CONTINUES_TEXT: Dictionary = {
	Gen2Weather.RAIN: "Rain continues to fall.",
	Gen2Weather.SUN: "The sunlight is strong.",
	Gen2Weather.SANDSTORM: "The SANDSTORM rages.",
}
const WEATHER_ENDED_TEXT: Dictionary = {
	Gen2Weather.RAIN: "The rain stopped.",
	Gen2Weather.SUN: "The sunlight faded.",
	Gen2Weather.SANDSTORM: "The SANDSTORM subsided.",
}

## The two lines each screen has. The set lines are `BattleCommand_Screen`'s and
## `BattleCommand_Safeguard`'s own, which describe the stat rather than the
## screen. The faded lines are `HandleScreens`', and they name the side rather
## than the Pokémon: `.Copy` fills `wStringBuffer1` with "Your" or "Enemy" ahead
## of " #MON's", which is the wording that fits a screen outliving whoever put it
## up. `HandleSafeguard`'s is the odd one and is a plain `<USER>`.
const SCREEN_SET_TEXT: Dictionary = {
	Gen2Screens.LIGHT_SCREEN: "%s's SPCL.DEF rose!",
	Gen2Screens.REFLECT: "%s's DEFENSE rose!",
	Gen2Screens.SAFEGUARD: "%s's covered by a veil!",
}
const SCREEN_FADED_TEXT: Dictionary = {
	Gen2Screens.LIGHT_SCREEN: "%s's LIGHT SCREEN fell!",
	Gen2Screens.REFLECT: "%s's REFLECT faded!",
}

var _data: GameData = null
var _injected_data: GameData = null
## Whatever the mod host supplies. Typed as Node because a registered renderer
## only has to satisfy Gen2ModHost.BATTLE_RENDERER_METHODS, not extend the
## built-in one.
var _renderer: Node = null
var _renderer_ready: bool = false

## The battle behind the screen, and the two Pokémon in it. The display state
## below is what is currently drawn, which is not always where the battle has
## got to: a turn resolves at once and is then shown an event at a time.
var _battle: Gen2Battle = null
var _pending: Array = []
var _rng := RandomNumberGenerator.new()
## Whether something else owns the funnel every button arrives through. Set while
## this screen is an overlay inside the overworld, so a press is recorded once, by
## the world, and a replayed log reaches the fight: see
## [method Gen2WorldScreen.press_button] and `tools/replay_world.gd`.
var _external_input: bool = false
var _save_slot: int = -1
var _save_written: bool = false
var _source_save: Gen2SaveData = null
var _world_battle_active: bool = false
var _world_battle_tutorial: bool = false
var _world_battle_request: Dictionary = {}
## The run's rules, handed over by whoever opened this screen. A development
## battle has none and plays the installed set.
var _injected_rules: Gen2Rules = null
var _world_battle_completion_sent: bool = false
var _world_battle_terminal_text_shown: bool = false
var _world_battle_recovery_shown: bool = false
var _world_battle_recovery: Dictionary = {}
var _last_message: String = ""
## A running [Gen2HpBarAnimation] per side. A side with no entry is not moving.
var _bars: Dictionary = {}
## `MonFaintedAnimation`s still running, oldest first. A double faint runs two,
## one after the other, the way the source's two calls do.
var _faints: Array[Dictionary] = []
## The running [Gen2ExpBarAnimation], or null when the exp bar is not filling.
var _exp_bar: Gen2ExpBarAnimation = null
## The running [Gen2BattleIntro], or null once the pics have slid into place.
var _intro: Gen2BattleIntro = null
## What `BattleStartMessage` will say. It is held for the whole slide, because
## `InitBattleDisplay` returns before it is called and the box drawn before the
## slide is an empty one.
var _intro_message: String = ""
## `BattleStartMessage` and `DoBattle`'s own opening, one step per entry, spent
## once the pics have finished sliding. See [method _build_entrance].
var _entrance_stages: Array[Dictionary] = []
## Which panel is on the map. `InitBattleDisplay` clears the player's box and its
## caller only reaches `UpdateEnemyHUD` for a wild battle, so a battle opens with
## neither: the enemy's arrives when the opening line is pressed past (wild) or
## when the trainer has sent something out, and the player's inside
## `SendOutPlayerMon`.
var _enemy_hud_visible: bool = true
var _player_hud_visible: bool = true
## `GetTrainerBackpic`: which of the player's own pictures is standing on the
## player's square, empty once a Pokemon has taken it.
var _player_backpic: String = ""
## `InitEnemyTrainer`'s `PlaceGraphic`: the trainer class whose picture is on the
## enemy's square, zero once that trainer has sent something out.
var _enemy_trainer_pic: int = 0
## `LoadTrainerHudOAM`'s six sprites a side and the border they hang in.
var _hud_balls: Array = []
var _hud_border: Array = []
## `SlideBattlePicOut`, one entry per square still sliding off.
var _slides: Array[Dictionary] = []
## `AnimateFrontpic` over the enemy's square, or null when none is running.
var _frontpic: Gen2PicAnimation = null
## `wAttrmap` bit 3, which `PokeAnim_SetVBank1` sets over that square while the
## animation runs and `PokeAnim_SetVBank0` clears in `PokeAnim_DeinitFrames`. It
## is the whole reason the animation's tile numbers may sit on top of the
## player's: bank 1 holds the enemy's picture and its frames and nothing else.
var _bg_vbank1: PackedByteArray = PackedByteArray()
## The text the event pump produced while a bar was still draining. The source
## prints it after the bar arrives, since `applydamage` runs before
## `criticaltext` and `supereffectivetext`.
var _held_message: String = ""
## Whether the box is holding a line nobody has pressed past yet. Only a box
## waits for a button in `DoMove`'s loop, so this is what tells the frame pump
## that the run of frames it just finished owes a press rather than the next
## command; see [method _resume_after_frames].
var _message_awaits_press: bool = false
## Leftover of a hardware frame the bars and the intro have not counted yet.
var _frame_elapsed: float = 0.0
## The same, for the party page's icons. Kept apart because they animate while
## nothing else does, and [method frames_running] must stay false there: a
## caller draining frames to a terminal state would never reach one.
var _icon_elapsed: float = 0.0
## What the overworld clock said when the battle started, for the three heals
## that read it. Only the world path supplies one; the development drivers below
## leave [Gen2Battle] at its own midday default.
var _time_of_day: int = Gen2WorldPalette.TIME_DAY
## Where the battle is being fought, for a renderer that draws the place rather
## than a white field. Null unless the caller supplied one; see
## [method set_world_context].
var _world_context: Gen2BattleWorldContext = null
## `BattlePack`'s own rows and cursor, and the item held while
## `UseItem_SelectMon` picks a target for it.
var _pack_rows: Array[int] = []
var _pack_quantities: Dictionary = {}
var _pack_index: int = 0
var _pack_selecting: bool = false
var _pack_item: int = 0
## `RestorePPEffect`'s own `.loop`, which asks which move before it restores
## anything. Only the three items that fill one slot ever open it.
var _pack_move_slots: Array = []
var _pack_move_index: int = 0
var _pack_move_target: int = -1
var _pack_move_selecting: bool = false

var _capture_balls: Array[int] = []
var _capture_quantities: Dictionary = {}
var _capture_ball_index: int = 0
var _capture_selecting: bool = false
var _capture_waiting: bool = false
var _capture_messages: Array[String] = []
var _capture_terminal: bool = false
var _capture_result: Dictionary = {}

## Where a level-up's move offer has got to, following LearnMove and ForgetMove
## (engine/pokemon/learn.asm): [code]&"ask"[/code] is AskForgetMoveText's yes/no,
## [code]&"list"[/code] ForgetMove's own .loop, [code]&"stop"[/code]
## LearnMove.cancel's StopLearningMoveText. Empty when nothing is pending.
var _forget_stage: StringName = &""
var _forget_moves: Array = []
var _forget_cursor: int = 0
var _forget_confirm_cursor: int = 0

## Where a switch has got to. [code]&"offer"[/code] is `OfferSwitch`'s
## `PlaceYesNoBox`, [code]&"use_next"[/code] `AskUseNextPokemon`'s own box in the
## same place, and [code]&"pick"[/code] the party menu `SetUpBattlePartyMenu`
## puts up behind either, which Baton Pass and a replacement open straight into.
## Empty when none of them is on screen.
var _switch_stage: StringName = &""
## Which question the list is answering: [code]&"offer"[/code] is `OfferSwitch`'s
## YES, [code]&"baton_pass"[/code] the target `ForcePickSwitchMonInBattle` asks
## for inside the move, and [code]&"replace"[/code] `ForcePlayerMonChoice` after
## a faint. Only the first can be backed out of.
var _switch_reason: StringName = &""
var _switch_menu: Gen2BattleSwitchMenu = null
## The yes/no box's own cursor, which is a two-row `VerticalMenu`.
var _switch_offer: Gen2WorldMenu = null

## `BattleMenu`'s own loop: [code]&"main"[/code] is FIGHT/PKMN/PACK/RUN,
## [code]&"move"[/code] `MoveSelectionScreen`'s list and [code]&"refused"[/code]
## the line it prints over that list before reopening it.
var _menu_stage: StringName = &""
## `wBattleMenuCursorPosition`, which is written back after every visit and so
## opens on whatever was chosen last.
var _menu_position: int = Gen2BattleMenu.FIGHT
## `wListMoves_MoveIndicesBuffer` as [method Gen2BattleMenu.move_rows] shapes it,
## rebuilt every time the list is opened because PP and Disable move under it.
var _move_rows: Array = []
## `wCurMoveNum`, which the list opens its cursor on.
var _move_cursor: int = 0
## `MoveInfoBox`, which is its own `Textbox` beside the list rather than part of
## it, so it is drawn into a layer of its own.
var _info_layer: TextureRect = null
## `.skip_exp_bar_animation`'s stats box, over the upper screen while the
## grew-to-level line it accompanies is up.
var _level_up_layer: TextureRect = null
## The stats that box is showing, empty while there is no box.
var _level_up_stats: Dictionary = {}
## The menu itself, which unlike [member _menu_layer] sits over the text box.
var _battle_menu_layer: TextureRect = null

## The trainer class behind the enemy's own moves, or zero for
## [method show_matchup]'s invented pairing, which has no class and so no AI
## flags of its own to read: it falls back to [method _random_slot], same as
## before this existed. Reset by both, set only by [method show_trainer].
var _enemy_trainer_class: int = 0
## Which trainer of that class, for the view. Both are zero in a wild battle,
## which is what `wOtherTrainerClass` holds there too.
var _enemy_trainer_index: int = 0

var _enemy: int = 1
var _player: int = 1
## Which Unown letter each side's picture is, and zero for every other species.
## Drawn values like the two above: they follow the events rather than the party.
var _enemy_unown_form: int = 0
var _player_unown_form: int = 0
var _enemy_level: int = 5
var _player_level: int = 5
var _enemy_hp: int = 0
var _enemy_max_hp: int = 0
var _player_hp: int = 0
var _player_max_hp: int = 0
## The committed exp bar, in `PlaceExpBar`'s pixels.
var _exp: int = 0

var _box: Gen2TextBox = null

## The two menus a switch is made with, and the one layer both are drawn on:
## `PlaceYesNoBox`'s frame over the field, or the whole party page in place of
## it, which is what `SetUpBattlePartyMenu` clearing the screen amounts to.
var _menu_page: Gen2MenuPage = null
var _party_page: Gen2PartyMenuPage = null
var _menu_layer: TextureRect = null
## What the layer currently holds, so a per-frame refresh redraws nothing.
var _menu_drawn: String = ""

## `wTilemap` as this battle leaves it, which is what an animation edits and
## what the renderer draws both pictures out of.
var _bg_map: PackedByteArray = Gen2BattleScreenMap.seeded()

## The animation layer. `_anim` is the running `RunBattleAnimScript`, `_plan`
## the rest of `PlayBattleAnim`'s own framing waiting behind it, and `_anim_data`
## the imported tables, opened once.
var _anim_data: Gen2BattleAnimData = null
var _anim: Gen2BattleAnimPlayer = null
var _anim_plan: Array = []
var _anim_delay: int = 0
var _anim_event: Dictionary = {}
## `ClearActorHud` clears the panel of whoever's turn it is and leaves the other
## one alone, so this is the side an animation has taken off the map rather than
## a flag for both.
var _anim_hud_hidden: int = -1
var _audio_player: Gen2AudioPlayer = null
## False while the driver belongs to the screen that opened this one, which is
## what says this screen may not stop or free it.
var _owns_audio_player: bool = false
## `PlayBattleMusic`'s answer for this fight; see [method battle_music].
var _battle_music: int = Gen2Battle.MUSIC_NONE

@onready var _screen: Gen2Screen = %Screen


## Bars drain and the intro slides on hardware frames, not on rendered ones, the
## same reason [Gen2WorldAnimation] paces the overworld that way: the two-frame
## step `HPBarAnim_BGMapUpdate` waits and `BattleIntroSlidingPics`' own
## `DelayFrame` are both hardware frame counts.
func _process(delta: float) -> void:
	if _box != null:
		_box.accelerated = Gen2Button.text_accelerating()
	## The yes/no box appears when the question above it has finished printing,
	## and the box prints on its own clock rather than on a press.
	if _switch_stage != &"":
		_advance_party_icons(delta)
		_refresh_menu_layer()
	## The box is on the same hardware clock as everything else the screen draws,
	## and it keeps counting while nothing else does: a text prints, scrolls and
	## blinks its arrow whether or not a bar or an animation is running.
	## [method frames_running] deliberately does not answer for it, since a box
	## waiting at a page is waiting on a press and a caller draining frames on
	## that answer would never stop.
	var running: bool = frames_running()
	if not running and (_box == null or not _box.visible):
		_frame_elapsed = 0.0
		return
	## Capped the way [method Gen2WorldScreen._process] caps it: a stall should
	## drop animation frames, not run a second of them in one host frame.
	_frame_elapsed = minf(
		_frame_elapsed + delta,
		Gen2WorldAnimation.FRAME_SECONDS * float(Gen2WorldAnimation.MAX_CATCHUP_FRAMES),
	)
	while _frame_elapsed >= Gen2WorldAnimation.FRAME_SECONDS:
		_frame_elapsed -= Gen2WorldAnimation.FRAME_SECONDS
		if frames_running():
			advance_frame()
		elif _box != null:
			_box.advance_frame()
		else:
			break


## Whether anything is counting hardware frames right now. Public with
## [method advance_frame] so a test or a screenshot driver can settle the screen
## without waiting on real time.
##
## An exp bar stopped at a level boundary is waiting on the press that dismisses
## `.LoopLevels`' textbox, not on frames: it cannot move until
## [method Gen2ExpBarAnimation.resume]. It is excluded here so a caller draining
## frames stops instead of spinning, which [method bars_animating] does not do
## because that answers whether a bar is on screen.
func frames_running() -> bool:
	var bars: bool = not _bars.is_empty() or (_exp_bar != null and not _exp_bar.paused())
	return bars or _intro != null or animation_running() or fainting() or sliding() \
		or animating_frontpic()


## One hardware frame of everything that counts them. Public through
## [method advance_bars] and [method advance_intro] so a test or a screenshot
## driver can settle either without waiting on real time.
func advance_frame() -> bool:
	if _box != null:
		_box.advance_frame()
	var was_running: bool = frames_running()
	var moved: bool = advance_intro()
	moved = advance_bars() or moved
	moved = advance_faint() or moved
	moved = advance_slide() or moved
	moved = advance_frontpic() or moved
	moved = advance_animation() or moved
	_resume_after_frames(was_running)
	return moved


## What the source does when the frames a command spends run out: it runs on to
## the next command. Nothing in `DoMove`'s loop reads a button between an
## animation, `AnimateHPBar` and `MonFaintedAnimation` and whatever follows them,
## so the pump continues here rather than standing still until a press.
##
## The waits that are real are all a box, and [method _continue_after_messages]
## owns that test: a message on screen is left alone, and so is a bar holding one.
func _resume_after_frames(was_running: bool) -> void:
	if not was_running or frames_running():
		return
	_continue_after_messages()


## Whether a picture is still sinking off its square.
func fainting() -> bool:
	return not _faints.is_empty()


## One hardware frame of `MonFaintedAnimation`. Public so a test or a screenshot
## driver can settle or step one without waiting on real time.
func advance_faint() -> bool:
	if _faints.is_empty():
		return false
	var faint: Dictionary = _faints[0]
	faint["delay"] = int(faint["delay"]) - 1
	if int(faint["delay"]) > 0:
		return true
	faint["delay"] = Gen2BattleScreenMap.FAINT_STEP_FRAMES
	faint["step"] = int(faint["step"]) + 1
	Gen2BattleScreenMap.faint_step(_bg_map, bool(faint["player_side"]))
	if int(faint["step"]) >= Gen2BattleScreenMap.FAINT_STEPS:
		_faints.remove_at(0)
	_push_view()
	return true


## Whether a picture is still sliding off its square.
func sliding() -> bool:
	return not _slides.is_empty()


## One hardware frame of `SlideBattlePicOut`, whose outer loop spends
## [constant Gen2BattleScreenMap.SLIDE_STEP_FRAMES] on each column it shifts.
func advance_slide() -> bool:
	if _slides.is_empty():
		return false
	var slide: Dictionary = _slides[0]
	slide["delay"] = int(slide["delay"]) - 1
	if int(slide["delay"]) > 0:
		return true
	slide["delay"] = Gen2BattleScreenMap.SLIDE_STEP_FRAMES
	slide["step"] = int(slide["step"]) + 1
	var player_side: bool = bool(slide["player_side"])
	Gen2BattleScreenMap.slide_step(_bg_map, player_side)
	if int(slide["step"]) >= int(Gen2BattleScreenMap.SLIDE_STEPS[player_side]):
		_slides.remove_at(0)
	_push_view()
	return true


## Whether the enemy's picture is still wobbling through `AnimateFrontpic`.
func animating_frontpic() -> bool:
	return _frontpic != null


## One turn of `AnimateFrontpic`'s own `.loop`, which is one `SetUpPokeAnim` and
## so one hardware frame. The animation edits the tilemap and nothing else, the
## way `PokeAnim_PlaceGraphic` does, so what it leaves is stamped into the
## screen's own map over the enemy's square.
func advance_frontpic() -> bool:
	if _frontpic == null:
		return false
	var cry: StringName = _frontpic.advance()
	if cry != &"":
		# `PokeAnim_StereoCry` is `PlayStereoCry2`, the sibling that does not
		# `WaitSFX`: the picture keeps moving over it, which is the whole reason
		# the cry is inside the animation rather than in front of it.
		_play_entrance_cry(Gen2Battle.ENEMY, _enemy)
	_stamp_frontpic()
	if _frontpic.finished():
		# `PokeAnim_DeinitFrames` ends with `PokeAnim_SetVBank0`, which puts the
		# square back on the sheet everything else is read from.
		_frontpic = null
		_bg_vbank1 = PackedByteArray()
	_push_view()
	return true


## The animation's 7x7 box into the enemy's square. Its cells are numbered the
## way `PokeAnim_PlaceGraphic` numbers them, which is the column-major order
## [method Gen2BattleScreenMap.stamp] already writes for that square.
func _stamp_frontpic() -> void:
	if _frontpic == null or _frontpic.box.size() != Gen2PicAnimation.BOX * Gen2PicAnimation.BOX:
		return
	if _bg_vbank1.size() != _bg_map.size():
		_bg_vbank1.resize(_bg_map.size())
		_bg_vbank1.fill(0)
	var at: Vector2i = Gen2BattleScreenMap.ENEMY_AT
	for column: int in Gen2PicAnimation.BOX:
		for row: int in Gen2PicAnimation.BOX:
			var x: int = at.x + column
			var y: int = at.y + row
			if x < 0 or x >= Gen2BattleScreenMap.COLUMNS \
					or y < 0 or y >= Gen2BattleScreenMap.ROWS:
				continue
			_bg_map[y * Gen2BattleScreenMap.COLUMNS + x] = (
				Gen2BattleScreenMap.ENEMY_BASE_TILE
				+ int(_frontpic.box[column * Gen2PicAnimation.BOX + row])
			) & 0xFF
			_bg_vbank1[y * Gen2BattleScreenMap.COLUMNS + x] = 1


## `PlayerMonFaintedAnimation` or `EnemyMonFaintedAnimation`, which
## `FaintYourPokemon` and `FaintEnemyPokemon` run before their own text box.
func _begin_faint(side: int) -> void:
	_faints.append({
		"player_side": side == Gen2Battle.PLAYER,
		"step": 0,
		"delay": Gen2BattleScreenMap.FAINT_STEP_FRAMES,
	})


func _ready() -> void:
	_data = _injected_data if _injected_data != null else _selected_runtime_data()
	if _data == null:
		_data = GameData.open_any()
	_build_renderer()
	if not _renderer_ready:
		return

	## The cartridge has one APU. A screen that opened this one hands its own
	## driver over so a cry here takes the channels the map music is holding
	## rather than sounding over a second copy of them; only a battle standing on
	## its own builds a player, and only that one owns it.
	if _audio_player == null:
		_audio_player = AUDIO_PLAYER_SCRIPT.new()
		_audio_player.name = "AudioPlayer"
		_owns_audio_player = true
		add_child(_audio_player)
	_anim_data = Gen2BattleAnimData.from_game_data(_data)

	## Under the text box, because the refusals a switch list is answered with are
	## `StdBattleTextbox` drawn over the party menu rather than into it. The
	## yes/no box sits above the box's own rows and never meets it.
	_menu_page = Gen2MenuPage.from_data(_data)
	_party_page = Gen2PartyMenuPage.from_data(_data)
	_menu_layer = TextureRect.new()
	_menu_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_menu_layer.visible = false
	_screen.display(_menu_layer)

	_box = Gen2TextBox.new()
	_box.driven = true
	_box.font = Gen2Font.from_data(_data)
	## wTextboxFrame and the TEXT SPEED delay: a battle's own boxes are the
	## player's boxes, drawn through `PrintLetterDelay` like every other one.
	var options: Gen2Options = Gen2OptionsStore.current()
	_box.set_frame_style(options.textbox_frame)
	_box.reveal_speed = options.text_reveal_speed()
	_box.item_rect_changed.connect(_push_text_box_rect)
	_box.visibility_changed.connect(_push_text_box_rect)
	_screen.display(_box)
	_box.place_at_bottom()
	## Over the text box, unlike the two above: `LoadBattleMenu` draws its box
	## into the tilemap after `EmptyBattleTextbox` has drawn that one, so the
	## menu covers the box's right-hand half and `MoveSelectionScreen`'s list
	## covers all of it.
	_battle_menu_layer = TextureRect.new()
	_battle_menu_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_battle_menu_layer.visible = false
	_screen.display(_battle_menu_layer)
	_info_layer = TextureRect.new()
	_info_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_info_layer.visible = false
	_screen.display(_info_layer)
	_level_up_layer = TextureRect.new()
	_level_up_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_level_up_layer.visible = false
	_screen.display(_level_up_layer)
	_apply_renderer_interface_style()

	## Whatever this screen was opened on its own for. A battle inside the
	## overworld is started by [method start_world_battle], from the frame the
	## encounter fired on, rather than from anything read here.
	var saved: Gen2SaveData = _selected_runtime_save()
	if saved != null and show_saved_party(saved):
		show_message("Save slot %d loaded. Wild %s appeared!" % [_save_slot + 1, _name_of(_enemy)])
	else:
		show_matchup(DEFAULT_ENEMY, DEFAULT_PLAYER, DEFAULT_LEVEL, DEFAULT_LEVEL)
		_announce()


## Supplies a cache-backed data source before the scene enters the tree. The
## normal launcher path still resolves data from GameRuntime or the first
## imported cache.
func set_data(data: GameData) -> void:
	_injected_data = data


## `CleanUpBattleRAM` zeroes `wLowHealthAlarm`. A driver this screen does not own
## outlives it, so the byte is cleared where the screen goes rather than where a
## fight ends: every way out of a battle, including a wipe and a failed setup, is
## a way out of the tree.
func _exit_tree() -> void:
	if _audio_player != null and not _owns_audio_player:
		_audio_player.set_low_health_alarm(false)


## Hands this screen the driver the opening screen is already running, before it
## enters the tree. Without one the screen builds its own, which is what a
## battle launched on its own does.
func set_audio_player(player: Gen2AudioPlayer) -> void:
	_audio_player = player
	_owns_audio_player = false


## The rules the world is being played under, so the fight inside it is fought
## under the same ones rather than under whatever was installed last.
func set_rules(battle_rules: Gen2Rules) -> void:
	_injected_rules = battle_rules


## Seeds everything this screen decides for itself: the enemy's move choice, its
## item and switch decisions, and the capture rolls.
##
## A battle inside a walk is drawn from the world's own generator, so the seed is
## part of the run's own chain and a replay reproduces the fight without recording
## anything about it. A battle with no world seeds itself randomly, which is what
## a development one should do.
func set_random_seed(value: int) -> void:
	_rng.seed = value


## Hands the input funnel to whoever opened this screen. The world does while a
## battle is an overlay on it: one funnel is what makes a recorded log complete,
## and two would record every press twice or none.
func set_external_input(external: bool) -> void:
	_external_input = external


## The request this fight was started from, as the adapter prepared it: the
## species, the level, the DVs and which visible encounter it was, for a test or a
## mod asking what is being fought rather than what is drawn.
func world_battle_request() -> Dictionary:
	return _world_battle_request.duplicate(true)


## One button, from the funnel rather than from an [InputEvent]. Public so the
## world can forward what it consumed and a tool can drive a fight by hand.
func press_button(button: int) -> bool:
	if not is_ready() or button == Gen2Button.NONE:
		return false
	return _handle_button(button)


## One hardware frame of everything this screen counts, including the party icons
## the switch menu animates, which [method _process] otherwise paces off real
## time. What lets the world spend a battle's frames from its own pump, so a
## replayed run reaches the same place at the same frame.
func advance_hardware_frame() -> bool:
	var moved: bool = false
	## `PrintLetterDelay` is a frame count, and with nothing servicing the box's
	## own `_process` a message would never finish revealing, so a press would
	## complete the page forever and never acknowledge it.
	if _box != null:
		_box.advance_frame()
	if _switch_stage in [&"pick", &"refused"]:
		moved = advance_party_icons()
		_refresh_menu_layer()
	if not frames_running():
		return moved
	return advance_frame() or moved


## Null rather than the first imported cache: a battle opened without a runtime
## is a development one, and the caller has already injected what it draws with.
func _selected_runtime_data() -> GameData:
	var runtime: Gen2GameRuntime = Gen2GameRuntime.instance()
	if runtime != null and runtime.has_selected_game():
		return runtime.selected_data()
	return null


func _selected_runtime_save() -> Gen2SaveData:
	return Gen2GameRuntime.selected_save_or_null()


## True once the cache had everything the renderer draws with.
func is_ready() -> bool:
	return _renderer_ready and _box != null


## Puts two Pokémon on the screen at a level each, both at full health, and
## starts a battle between them.
func show_matchup(enemy: int, player: int, enemy_level: int = 5, player_level: int = 5) -> void:
	_reset_capture_state()
	_world_battle_active = false
	_world_battle_tutorial = false
	_world_battle_request = {}
	_world_battle_completion_sent = false
	_world_battle_terminal_text_shown = false
	_world_battle_recovery_shown = false
	_world_battle_recovery = {}
	_enemy = _wrap_species(enemy)
	_player = _wrap_species(player)
	_enemy_level = enemy_level
	_player_level = player_level

	_pending = []
	_save_slot = -1
	_save_written = false
	_source_save = null
	_enemy_trainer_class = 0
	_enemy_trainer_index = 0
	_battle = Gen2Battle.create_parties(
		_data, _party_from(_player, _player_level), _party_from(_enemy, _enemy_level), _rng
	)
	if _battle == null:
		return

	_init_battle_display()
	_announce()


## Puts the player against one of a trainer class's own trainers, built from the
## cartridge's own party rather than invented. The player's side is the
## fallback development party when this method is called directly.
func show_trainer(
	trainer_class: int, index: int = 0, player_species: int = DEFAULT_PLAYER,
	player_level: int = DEFAULT_LEVEL
) -> void:
	_reset_capture_state()
	_world_battle_active = false
	_world_battle_tutorial = false
	_world_battle_request = {}
	_world_battle_completion_sent = false
	_world_battle_terminal_text_shown = false
	_world_battle_recovery_shown = false
	_world_battle_recovery = {}
	var enemy_party: Gen2Party = Gen2TrainerParty.build(_data, trainer_class, index)
	if enemy_party == null:
		return

	_player = _wrap_species(player_species)
	_player_level = player_level

	var lead: Gen2BattleMon = enemy_party.active_mon()
	_enemy = lead.species
	_enemy_level = lead.level

	_pending = []
	_save_slot = -1
	_save_written = false
	_source_save = null
	_enemy_trainer_class = trainer_class
	_enemy_trainer_index = index
	_battle = Gen2Battle.create_parties(
		_data, _party_from(_player, _player_level), enemy_party, _rng, true
	)
	if _battle == null:
		return
	_battle.init_enemy_trainer(trainer_class)

	_init_battle_display()

	show_message("%s\nwants to battle!" % _enemy_battler_label())


## Starts the development battle with the player party from a validated save
## slot. The enemy remains the existing wild demonstration, while the player
## side now carries persistent levels, HP, PP, status, DVs and stat experience.
func show_saved_party(save: Gen2SaveData) -> bool:
	_reset_capture_state()
	_world_battle_active = false
	_world_battle_tutorial = false
	_world_battle_request = {}
	_world_battle_completion_sent = false
	_world_battle_terminal_text_shown = false
	_world_battle_recovery_shown = false
	_world_battle_recovery = {}
	var player_party: Gen2Party = Gen2SaveBattleAdapter.to_battle_party(_data, save)
	var enemy_party: Gen2Party = _party_from(DEFAULT_ENEMY, DEFAULT_LEVEL)
	if player_party == null or enemy_party == null:
		return false
	var player_lead: Gen2BattleMon = player_party.active_mon()
	var enemy_lead: Gen2BattleMon = enemy_party.active_mon()
	_pending = []
	_save_slot = save.slot
	_save_written = false
	_source_save = save
	_enemy_trainer_class = 0
	_enemy_trainer_index = 0
	_player = player_lead.species
	_player_level = player_lead.level
	_enemy = enemy_lead.species
	_enemy_level = enemy_lead.level
	var badge_mask: int = 0
	if save.world != null and save.world.world_state != null:
		badge_mask = save.world.world_state.badge_mask(
			Gen2WorldState.is_crystal_profile(_data)
		)
	_battle = Gen2Battle.create_parties(
		_data, player_party, enemy_party, _rng, false, badge_mask
	)
	if _battle == null:
		_save_slot = -1
		return false
	_init_battle_display()
	return true


## Starts a battle requested by the scene-free overworld runtime. The caller
## keeps the world API alive while this screen owns the battle presentation.
func start_world_battle(
	request: Dictionary, save: Gen2SaveData = null, player_badges: int = -1
) -> bool:
	_clear_capture_action()
	if _data == null or not is_ready():
		_emit_world_battle_failure(&"missing_battle_data")
		return false
	var player_party: Gen2Party = (
		Gen2SaveBattleAdapter.to_battle_party(_data, save)
		if save != null else Gen2WorldBattleAdapter.fallback_party(_data)
	)
	var crystal: bool = Gen2WorldState.is_crystal_profile(_data)
	var badge_mask: int = player_badges
	if badge_mask < 0 and save != null and save.world != null \
		and save.world.world_state != null:
		badge_mask = save.world.world_state.badge_mask(crystal)
	if badge_mask < 0:
		badge_mask = 0
	var prepared: Dictionary = Gen2WorldBattleAdapter.prepare(
		_data, request, player_party, _rng, badge_mask, _injected_rules
	)
	if not bool(prepared.get("ok", false)):
		_emit_world_battle_failure(
			StringName(prepared.get("reason", &"battle_setup_failed")),
			prepared.get("details", {})
		)
		return false

	_world_battle_active = true
	_world_battle_request = (prepared.get("request", {}) as Dictionary).duplicate(true)
	_world_battle_tutorial = bool(_world_battle_request.get("tutorial", false))
	_world_battle_completion_sent = false
	_world_battle_terminal_text_shown = false
	_world_battle_recovery_shown = false
	_world_battle_recovery = {}
	_pending = []
	_save_slot = save.slot if save != null else -1
	_save_written = false
	_source_save = save
	_enemy_trainer_class = int(prepared.get("trainer_class", 0))
	_enemy_trainer_index = int(prepared.get("trainer_index", 0))
	_battle = prepared["battle"]
	_battle.time_of_day = _time_of_day
	## `GetWorldMapLocation`, the same reading [method _play_battle_music] uses:
	## `LevelUpHappinessMod` compares it against the winner's caught location.
	_battle.landmark = _world_context.landmark if _world_context != null \
		else Gen2Battle.LANDMARK_NONE
	_battle.init_enemy_trainer(_enemy_trainer_class)
	var player_party_ready: Gen2Party = prepared["player_party"]
	var enemy_party_ready: Gen2Party = prepared["enemy_party"]
	_player = player_party_ready.active_mon().species
	_player_level = player_party_ready.active_mon().level
	_enemy = enemy_party_ready.active_mon().species
	_enemy_level = enemy_party_ready.active_mon().level
	_init_battle_display()
	_play_battle_music()

	if _world_battle_tutorial:
		show_message("Gotcha! %s was caught!" % _name_of(_enemy))
		call_deferred("_finish_world_catch_tutorial")
	elif bool(prepared.get("trainer_battle", false)):
		show_message("%s\nwants to battle!" % _enemy_battler_label())
	else:
		_announce()
	return true


func _finish_world_catch_tutorial() -> void:
	if not _world_battle_active or not _world_battle_tutorial \
		or _world_battle_completion_sent:
		return
	_world_battle_completion_sent = true
	battle_finished.emit({
		"ok": true,
		"outcome": Gen2WorldBattleAdapter.OUTCOME_CAUGHT,
		"request": _world_battle_request.duplicate(true),
		"capture": {
			"species": _enemy,
			"ball": Gen2WorldPartyHost.ITEM_POKE_BALL,
			"tutorial": true,
			"persistent": false,
		},
	})


## Public screenshot driver for the overworld battle loss boundary. It starts a
## real host battle using the fallback development party and then completes it
## as a loss, which is the frame `LostBattle` returns on: the whiteout itself is
## the overworld's and is photographed there.
func preview_world_battle_loss() -> void:
	if _world_battle_active or _data == null:
		return
	if not start_world_battle({
		"kind": &"wild", "pokemon": DEFAULT_ENEMY, "level": DEFAULT_LEVEL,
	}):
		return
	call_deferred("_preview_world_battle_loss")


func _preview_world_battle_loss() -> void:
	if not _world_battle_active or _battle == null:
		return
	for mon: Gen2BattleMon in _battle.party(Gen2Battle.PLAYER).mons:
		mon.hp = 0
	_read_hp()
	finish()
	advance()
	finish()


func _emit_world_battle_failure(reason: StringName, details: Dictionary = {}) -> void:
	if _world_battle_completion_sent:
		return
	_world_battle_completion_sent = true
	battle_finished.emit({"ok": false, "reason": reason, "details": details.duplicate(true)})


## A fallback party led by [param species], with the species after it behind.
## The enemy's side no longer uses this; see [method show_trainer].
func _party_from(species: int, level: int) -> Gen2Party:
	var members: Array = []
	for offset: int in PARTY_SIZE:
		var number: int = _wrap_species(species + offset)
		members.append(
			Gen2BattleMon.create(_data, number, level, _data.moves_at_level(number, level))
		)
	return Gen2Party.create(members)


## Both HP totals, for a caller that has its own numbers.
## The committed HP, which is what [method battle_snapshot] and every caller
## that places state reads. It does not animate on its own: `AnimateHPBar` is
## called by `DoEnemyDamage` and its siblings, not by every write to
## `wBattleMonHP`, so the bar is started by the events that mean damage or
## healing and this snaps.
func set_hp(enemy: int, enemy_max: int, player: int, player_max: int) -> void:
	if enemy != _enemy_hp or enemy_max != _enemy_max_hp:
		_bars.erase(Gen2Battle.ENEMY)
	if player != _player_hp or player_max != _player_max_hp:
		_bars.erase(Gen2Battle.PLAYER)
	_enemy_hp = enemy
	_enemy_max_hp = enemy_max
	_player_hp = player
	_player_max_hp = player_max
	_push_view()


## Begins a bar animation from [param from_hp] to the HP now committed for
## [param side], which is what an event meaning damage or healing does after it
## has written the new value.
##
## A maximum that moved under the bar is not the same bar draining: a Pokemon
## coming out gets its bar drawn at once, the way `LoadHPBar` puts one up.
func _start_bar(side: int, from_hp: int, from_max: int) -> void:
	var to_hp: int = _enemy_hp if side == Gen2Battle.ENEMY else _player_hp
	var max_hp: int = _enemy_max_hp if side == Gen2Battle.ENEMY else _player_max_hp
	if max_hp != from_max or from_hp == to_hp:
		return
	var animation: Gen2HpBarAnimation = Gen2HpBarAnimation.create(from_hp, to_hp, max_hp)
	if animation.finished():
		return
	_bars[side] = animation
	_push_view()


## What the bar for [param side] is drawing: the animation's value while one is
## running, and the committed HP otherwise.
func _drawn_hp(side: int) -> int:
	var animation: Gen2HpBarAnimation = _bars.get(side, null)
	if animation == null:
		return _enemy_hp if side == Gen2Battle.ENEMY else _player_hp
	return animation.hp()


## `HandleHPPals`, which sets `wLowHealthAlarm`'s DANGER_ON bit while the
## player's own bar reads HP_RED and clears it otherwise. The colour follows what
## is drawn rather than the numbers behind it, so a draining bar arms the alarm
## on the frame it turns red. `StopDangerSound` silences it the moment the
## Pokemon faints and `CleanUpBattleRAM` at the end of the battle, which is what
## the two zero cases here are.
func _update_low_health_alarm() -> void:
	if _audio_player == null:
		return
	var hp: int = _drawn_hp(Gen2Battle.PLAYER)
	var over: bool = _battle != null and _battle.is_over()
	if hp <= 0 or _player_max_hp <= 0 or over:
		_audio_player.set_low_health_alarm(false)
		return
	var lit: int = Gen2BattleHud.bar_pixels(
		hp, _player_max_hp, Gen2BattleHud.HP_BAR_TILES * Gen2Font.TILE
	)
	_audio_player.set_low_health_alarm(GameData.hp_bar_palette_name(lit) == "hp_red")


## Whether any bar is still moving, which is what holds the next message back.
func bars_animating() -> bool:
	return not _bars.is_empty() or _exp_bar != null


## Whether the two pics are still sliding into place.
func intro_running() -> bool:
	return _intro != null


## Whether `BattleStartMessage` and `DoBattle`'s opening still owe something: a
## line to press past, frames to spend, or a ball to throw. A driver settling a
## battle to its first menu waits on this as well as on [method frames_running],
## because two of the steps are a box rather than a run of frames.
func entrance_running() -> bool:
	return not _entrance_stages.is_empty()


## `InitBattleDisplay`: the display a battle opens with, and the slide that puts
## it there. Every caller that has just built a battle reaches this, which is the
## same order the source uses, `InitBattleDisplay` before `BattleStartMessage`.
func _init_battle_display() -> void:
	## `wOptions`' BATTLE_SHIFT bit. The engine takes it injected rather than
	## reading the options file itself, since it is scene-free; this is the one
	## place every battle here passes through.
	_battle.battle_style_set = Gen2OptionsStore.current().battle_style_set
	## `InitBattleDisplay` draws both pics, so the letters start from the party
	## the same way the species above do; every later change is a send-out.
	_enemy_unown_form = Gen2Battle.unown_form_of(_battle.enemy)
	_player_unown_form = Gen2Battle.unown_form_of(_battle.player)
	_close_switch()
	_clear_level_up_box()
	_reseed_bg_map()
	set_hp(
		_battle.enemy.hp, _battle.enemy.max_hp(),
		_battle.player.hp, _battle.player.max_hp()
	)
	_refresh_exp_bar()
	_intro = Gen2BattleIntro.for_data(_data)
	# `InitBattleDisplay` clears the top of the player's square before the slide
	# and `PlaceGraphic` puts it back after, which is where [method
	# advance_intro] restamps it.
	Gen2BattleScreenMap.clear_intro_box(_bg_map)
	_intro_message = ""
	_entrance_stages = []
	_slides = []
	_frontpic = null
	_bg_vbank1 = PackedByteArray()
	_hud_balls = []
	_hud_border = []
	## `InitBattleDisplay` clears both panels off the map, and the two pictures
	## the pics slide in with are the opponent and the player themselves:
	## `InitEnemyTrainer` places a trainer class on the enemy's square and
	## `GetTrainerBackpic` the player's own on the player's. A wild opponent is
	## the one battler already standing there as itself.
	_enemy_hud_visible = false
	_player_hud_visible = false
	_enemy_trainer_pic = _enemy_trainer_class
	_player_backpic = player_backpic_kind()
	_push_view()


## `GetTrainerBackpic`'s choice: the Dude for the catching tutorial, and the
## player's own picture otherwise.
func player_backpic_kind() -> String:
	if _world_battle_tutorial:
		return "dude"
	return "kris" if player_is_female() else "chris"


## `wPlayerGender`'s `PLAYERGENDER_FEMALE_F`. Gold and Silver have one player
## character and no gender screen, so the answer there is always the male one.
func player_is_female() -> bool:
	if _source_save == null or _data == null:
		return false
	if not Gen2WorldState.is_crystal_profile(_data):
		return false
	return _source_save.gender == Gen2SaveData.GENDER_FEMALE


## One hardware frame of the intro. Public so a test or a screenshot driver can
## settle it without waiting on real time.
func advance_intro() -> bool:
	if _intro == null:
		return false
	if not _intro.advance_frame():
		return false
	if _intro.finished():
		# `InitBattleDisplay`'s own `xor a` / `ldh [hSCX], a` after the call, and
		# then `hGraphicStartTile = $31` / `hlcoord 2, 6` / `PlaceGraphic`, which
		# puts back the two tile rows its `ClearBox` took off before the slide.
		_intro = null
		Gen2BattleScreenMap.stamp(_bg_map, true)
		_push_view()
		_build_entrance()
		_advance_entrance()
		return true
	_push_view()
	return true


## `BattleStartMessage` and the opening of `DoBattle`, which the sliding pics run
## straight into and which is the whole of a battle's entrance.
##
## One stage per step, spent in order by [method _advance_entrance]. Measured
## against a real cartridge frame by frame, which is where the frame counts and
## the two presses come from:
##
## | | Wild | Trainer |
## |---|---|---|
## | 1 | the shiny pass and the enemy's cry | `SFX_SHINE`, `WaitSFX`, twenty frames |
## | 2 | the party balls, then the start line, which waits on a press | the same |
## | 3 | the balls go and the enemy's panel arrives | the balls go and the trainer slides off |
## | 4 | - | `ShowBattleTextEnemySentOut`, a press, the enemy's ball, cry and panel |
## | 5 | `DoBattle`'s forty frames | the same |
## | 6 | the player slides off, `SendOutMonText` prints without waiting | the same |
## | 7 | the ball, the cry and the player's panel | the same |
##
## `AnimateFrontpic` is the enemy's alone and is where its cry comes from:
## `BattleStartMessage`'s wild branch runs `ANIM_MON_NORMAL` and
## `ShowSetEnemyMonAndSendOutAnimation` runs `ANIM_MON_SLOW`, both at
## `hlcoord 12, 0`, and both `jr .skip_cry` past `PlayStereoCry` because the
## animation plays it. Crystal's alone: pokegold has no `pic_animation.asm` and
## both of its send-outs reach `PlayStereoCry` directly, which is the
## `.cry_no_anim` branch and what this project falls back on. The player's own
## send-out has no animation on either cartridge.
func _build_entrance() -> void:
	_entrance_stages = []
	var text: String = _intro_message
	_intro_message = ""
	if _battle == null or _world_battle_tutorial:
		if not text.is_empty():
			show_message(text)
		return

	var trainer: bool = _enemy_trainer_class > 0
	if trainer:
		_entrance_stages.append({
			"sfx": SFX_SHINE, "wait_sfx": true, "delay": TRAINER_START_FRAMES,
		})
	else:
		# `BattleCheckEnemyShininess` and the cry, both in front of the line.
		_entrance_stages.append(
			_with_frontpic(
				{"events": _battle.entrance_events(Gen2Battle.ENEMY, false)},
				Gen2PicAnimation.ANIM_MON_NORMAL
			)
		)
	# `BattleStart_TrainerHuds` is pushed in front of the line it is called with.
	_entrance_stages.append({"apply": ENTRANCE_START_HUDS, "message": text})
	# `EmptyBattleTextbox` and `ClearSprites` take the balls away the moment that
	# line is pressed past; the wild branch draws the enemy's panel there too.
	_entrance_stages.append({
		"apply": ENTRANCE_ENEMY_HUD if not trainer else ENTRANCE_CLEAR_HUDS,
	})
	if trainer:
		# `ResetEnemyBattleVars`, then `ShowBattleTextEnemySentOut` and
		# `ShowSetEnemyMonAndSendOutAnimation` inside `EnemySwitch`.
		_entrance_stages.append({"slide": Gen2Battle.ENEMY})
		_entrance_stages.append({
			"message": "%s\nsent out\n%s!" % [_enemy_battler_label(), _name_of(_enemy)],
		})
		_entrance_stages.append(
			_with_frontpic(
				{
					"apply": ENTRANCE_ENEMY_PIC,
					"events": _battle.entrance_events(Gen2Battle.ENEMY),
				},
				Gen2PicAnimation.ANIM_MON_SLOW
			)
		)
		_entrance_stages.append({"apply": ENTRANCE_ENEMY_HUD})
	# `DoBattle`'s own `ld c, 40`, then `SlideBattlePicOut` and `SendOutMonText`.
	_entrance_stages.append({"delay": PLAYER_ENTRANCE_FRAMES})
	_entrance_stages.append({"slide": Gen2Battle.PLAYER})
	_entrance_stages.append({
		"message": SEND_OUT_LINES[
			clampi(_battle.send_out_line(Gen2Battle.PLAYER), 0, SEND_OUT_LINES.size() - 1)
		] % _name_of(_player),
		"prompt": false,
	})
	_entrance_stages.append({
		"apply": ENTRANCE_PLAYER_PIC,
		"events": _battle.entrance_events(Gen2Battle.PLAYER),
	})
	_entrance_stages.append({"apply": ENTRANCE_PLAYER_HUD})


## Moves the enemy's cry out of [param stage]'s events and into
## `AnimateFrontpic`, where the cartridge plays it. A cache with no animation for
## this species, and a battle scene switched off, both leave the stage as it was,
## which is the source's own `.cry_no_anim`.
func _with_frontpic(stage: Dictionary, kind: int) -> Dictionary:
	if _data == null or _battle == null:
		return stage
	# `farcall CheckBattleScene / jr c, .cry_no_anim`: with the OPTION menu's
	# battle-scene row off, the picture is left alone and `PlayStereoCry` is
	# played where it stands.
	if not Gen2OptionsStore.current().battle_scene:
		return stage
	var record: Dictionary = _data.pic_animation(_enemy, _enemy_unown_form)
	if record.is_empty():
		return stage
	var events: Array = stage.get("events", []) as Array
	var kept: Array = []
	var animate: bool = false
	for event: Variant in events:
		# `CheckFaintedFrzSlp` and `CheckSleepingTreeMon` gate the cry, and both
		# gate the animation with it: the source's `jr c, .skip_cry` jumps past
		# the pair. So an entrance with no cry event has no animation either.
		if event is Dictionary and StringName((event as Dictionary)["type"]) == Gen2Battle.CRY:
			animate = true
			continue
		kept.append(event)
	if not animate:
		return stage
	stage["events"] = kept
	stage["frontpic"] = kind
	return stage


## What an entrance stage's `apply` names, each one routine of the source's.
const ENTRANCE_START_HUDS: StringName = &"start_huds"
const ENTRANCE_CLEAR_HUDS: StringName = &"clear_huds"
const ENTRANCE_ENEMY_HUD: StringName = &"enemy_hud"
const ENTRANCE_PLAYER_HUD: StringName = &"player_hud"
const ENTRANCE_ENEMY_PIC: StringName = &"enemy_pic"
const ENTRANCE_PLAYER_PIC: StringName = &"player_pic"


## One step of the entrance, in the order the fields are read here. Answers
## whether it took the turn, so the caller can run on when the list is empty.
func _advance_entrance() -> bool:
	## A stage's own events are still being shown one line at a time; the next
	## stage waits for the last of them.
	if not _pending.is_empty():
		return false
	while not _entrance_stages.is_empty():
		var stage: Dictionary = _entrance_stages[0]
		var apply: StringName = StringName(stage.get("apply", &""))
		if apply != &"":
			stage["apply"] = &""
			_apply_entrance_step(apply)
		var sfx: int = int(stage.get("sfx", 0))
		var delay: int = int(stage.get("delay", 0))
		var wait_sfx: bool = bool(stage.get("wait_sfx", false))
		if sfx > 0 or delay > 0 or wait_sfx:
			stage["sfx"] = 0
			stage["delay"] = 0
			stage["wait_sfx"] = false
			_anim_plan = []
			if sfx > 0:
				_step(ANIM_SFX, {"sfx": sfx})
			if wait_sfx:
				_step(ANIM_WAIT_SFX, {})
			if delay > 0:
				_step(ANIM_DELAY, {"frames": delay})
			_run_next_anim_step()
			return true
		if stage.has("slide"):
			var side: int = int(stage["slide"])
			stage.erase("slide")
			_begin_slide(side)
			return true
		var message: String = String(stage.get("message", ""))
		if not message.is_empty():
			## `SendOutMonText`'s line ends in `done` and prints with the ball
			## already in the air; every other line here ends in `prompt` or
			## carries a `cont`, and both of those wait on a press.
			var prompt: bool = bool(stage.get("prompt", true))
			stage["message"] = ""
			show_message(message, prompt)
			if prompt:
				return true
		if stage.has("frontpic"):
			var kind: int = int(stage["frontpic"])
			stage.erase("frontpic")
			_begin_frontpic(kind)
			if animating_frontpic():
				return true
		var events: Array = stage.get("events", []) as Array
		_entrance_stages.pop_front()
		if not events.is_empty():
			_pending = events
			_show_next_event()
			return true
	return false


## The state each named routine of the entrance leaves behind.
func _apply_entrance_step(what: StringName) -> void:
	match what:
		ENTRANCE_START_HUDS:
			_build_trainer_huds()
		ENTRANCE_CLEAR_HUDS:
			# `EmptyBattleTextbox`, `ClearBox` over both panels and
			# `ClearSprites`, which is what takes the party balls away.
			_hud_balls = []
			_hud_border = []
		ENTRANCE_ENEMY_HUD:
			_hud_balls = []
			_hud_border = []
			_enemy_hud_visible = true
		ENTRANCE_PLAYER_HUD:
			_player_hud_visible = true
		ENTRANCE_ENEMY_PIC:
			# `GetEnemyMonFrontpic`: the trainer's picture is replaced in VRAM
			# before the ball is thrown, and the square itself is empty until
			# `BATTLE_BG_EFFECT_ENTER_MON` stamps the map back.
			_enemy_trainer_pic = 0
		ENTRANCE_PLAYER_PIC:
			_player_backpic = ""
	_push_view()


## `Battle_GetTrainerName`, which is the class and the trainer's own name. A wild
## battle has neither, and the one line that names an opponent without a trainer
## behind it is a link battle's, which this project does not open.
func _enemy_battler_label() -> String:
	if _enemy_trainer_class <= 0 or _data == null:
		return "Enemy"
	return "%s %s" % [
		_data.trainer_name(_enemy_trainer_class), _enemy_trainer_name(),
	]


## What the opening is showing right now, for a frame by frame diff against a
## real cartridge: which squares hold what, which panels are up, whether a
## picture is sliding and what the box is saying.
func entrance_snapshot() -> Dictionary:
	return {
		"stages": _entrance_stages.size(),
		"message": _last_message,
		"awaits_press": _message_awaits_press,
		"enemy_hud": _enemy_hud_visible and _anim_hud_hidden != Gen2Battle.ENEMY,
		"player_hud": _player_hud_visible and _anim_hud_hidden != Gen2Battle.PLAYER,
		"enemy_trainer_pic": _enemy_trainer_pic,
		"player_backpic": _player_backpic,
		"balls": _hud_balls.size(),
		"sliding": sliding(),
		"frontpic": animating_frontpic(),
		"animating": animation_running(),
		"anim": int(_anim_event.get("index", 0)) if _anim != null else 0,
	}


## Whether both panels are on the map: neither side taken off by an animation,
## and both of them drawn by the entrance in the first place.
func _hud_visible() -> bool:
	return _enemy_hud_visible and _player_hud_visible and _anim_hud_hidden < 0


## `predef AnimateFrontpic` on the enemy's square, which `LoadMonAnimation` and
## `PokeAnim_InitPicAttributes` set up before the first frame is spent.
func _begin_frontpic(kind: int) -> void:
	if _data == null:
		return
	var record: Dictionary = _data.pic_animation(_enemy, _enemy_unown_form)
	if record.is_empty():
		return
	var animation := Gen2PicAnimation.new(record, kind)
	if animation.finished():
		return
	_frontpic = animation
	_stamp_frontpic()
	_push_view()


## `SlideBattlePicOut` over one square.
func _begin_slide(side: int) -> void:
	_slides.append({
		"player_side": side == Gen2Battle.PLAYER,
		"step": 0,
		"delay": Gen2BattleScreenMap.SLIDE_STEP_FRAMES,
	})


## `BattleStart_TrainerHuds`: the player's party balls always, the opponent's as
## well when there is a trainer behind them, each six sprites hanging under a
## border of four tile kinds.
func _build_trainer_huds() -> void:
	_hud_balls = []
	_hud_border = []
	_add_trainer_hud(Gen2Battle.PLAYER)
	if _enemy_trainer_class > 0:
		_add_trainer_hud(Gen2Battle.ENEMY)


## One side of it. `LoadTrainerHudOAM` walks six slots from
## [constant HUD_BALL_AT] in [constant HUD_BALL_STEP]'s direction, taking the
## tile `StageBallTilesData` staged for each, and `PlaceHUDBorderTiles` draws the
## frame from a corner outwards in the same direction.
func _add_trainer_hud(side: int) -> void:
	var player_side: bool = side == Gen2Battle.PLAYER
	var at: Vector2i = HUD_BALL_AT[player_side]
	var step: int = int(HUD_BALL_STEP[player_side])
	var party: Gen2Party = _battle.party(side) if _battle != null else null
	for slot: int in Gen2Party.MAX_SIZE:
		_hud_balls.append({
			"x": at.x + slot * step, "y": at.y, "tile": _hud_ball_tile(party, slot),
		})
	var border: Vector2i = HUD_BORDER_AT[player_side]
	var tiles: Array = HUD_BORDER_TILES[player_side]
	var direction: int = 1 if player_side else -1
	_hud_border.append({"x": border.x, "y": border.y, "tile": int(tiles[0])})
	_hud_border.append({"x": border.x, "y": border.y + 1, "tile": int(tiles[1])})
	for index: int in HUD_BORDER_EDGE:
		_hud_border.append({
			"x": border.x - (index + 1) * direction, "y": border.y + 1,
			"tile": int(tiles[3]),
		})
	_hud_border.append({
		"x": border.x - (HUD_BORDER_EDGE + 1) * direction, "y": border.y + 1,
		"tile": int(tiles[2]),
	})


## `StageBallTilesData`: an empty slot, then a ball per party member, coloured by
## whether that member is fainted, statused or well.
func _hud_ball_tile(party: Gen2Party, slot: int) -> int:
	if party == null or slot >= party.size():
		return HUD_BALL_EMPTY
	var mon: Gen2BattleMon = party.at(slot)
	if mon == null:
		return HUD_BALL_EMPTY
	if mon.is_fainted():
		return HUD_BALL_FAINTED
	return HUD_BALL_STATUSED if mon.status != 0 else HUD_BALL_NORMAL


## One hardware frame of every running bar. Public so a test or a screenshot
## driver can settle the bars without waiting on real time.
func advance_bars() -> bool:
	if not bars_animating():
		return false
	var moved: bool = false
	for side: int in _bars.keys():
		var animation: Gen2HpBarAnimation = _bars[side]
		if animation.advance_frame():
			moved = true
		if animation.finished():
			_bars.erase(side)

	var boundary: bool = false
	if _exp_bar != null:
		if _exp_bar.advance_frame():
			moved = true
		boundary = _exp_bar.segment_finished()
		if _exp_bar.finished():
			_exp_bar = null
			# The levels crossed on the way did not touch the committed count, so
			# the end of the walk is where it catches up.
			_refresh_exp_bar()

	if moved:
		_push_view()

	if boundary and _exp_bar != null:
		# The bar has reached the end of the level it was filling and stopped
		# there. `.LoopLevels` prints its grew-to-level line at exactly this
		# point, so the pump runs on to the event that carries it.
		_show_next_event()
	return moved


# ------------------------------------------------- battle animations ----

## `_PlayBattleAnim`'s own framing, as steps the screen walks a frame at a time.
## Each is a dictionary carrying its own `kind`; the delays are
## `BattleAnimDelayFrame` counts and `script` is `RunBattleAnimScript`.
const ANIM_DELAY: StringName = &"delay"
const ANIM_SCRIPT: StringName = &"script"
const ANIM_CLEAR_HUD: StringName = &"clear_hud"
const ANIM_RESTORE_HUD: StringName = &"restore_hud"
const ANIM_WAIT_SFX: StringName = &"wait_sfx"
const ANIM_HIT_SOUND: StringName = &"hit_sound"
const ANIM_APPEAR_USER: StringName = &"appear_user"
## `PlaySFX` on its own, which only the entrance uses: an animation's own sounds
## come out of its script.
const ANIM_SFX: StringName = &"sfx"

## Whose square is showing the substitute's doll rather than the mon itself,
## keyed by [constant Gen2Battle.PLAYER] and [constant Gen2Battle.ENEMY].
##
## The cartridge keeps this in VRAM rather than in a variable: `GetSubstitutePic`
## writes the doll over the battler's own tiles and `DropPlayerSub` writes the
## picture back, so what is on the field is whatever was drawn there last. The
## three writers are the animation's `anim_raisesub` and `anim_dropsub`, the two
## `noanim` commands the battle-scene option reaches instead, and a send-out,
## which draws a fresh picture either way.
var _substitute_pic: Dictionary = {Gen2Battle.PLAYER: false, Gen2Battle.ENEMY: false}

## `wFXAnimID` is a word: an id past this is not a move and skips the whole
## battle-scene, hud and after-anim half of `BattleAnimRunScript`.
const ANIM_MOVE_LIMIT: int = 0x100

## `SendOutMonText`'s four texts, in [constant Gen2Battle.SEND_OUT_GO]'s order.
const SEND_OUT_LINES: Array[String] = [
	"Go! %s!", "Do it! %s!", "Go for it,\n%s!", "Your foe's weak!\nGet'm, %s!",
]

## `PlayHitSound`'s three effects, by their `constants/sfx_constants.asm`
## numbers, which are the same in both pins.
const SFX_NOT_VERY_EFFECTIVE: int = 0xAB
## `wCryTracks`, which `PlayStereoCry` masks CHANNEL_TRACKS with: the enemy's
## cry keeps the low nibble's terminals and the player's the high nibble's.
const CRY_TRACKS_ENEMY: int = 0x0F
const CRY_TRACKS_PLAYER: int = 0xF0

const SFX_DAMAGE: int = 0xAC
const SFX_SUPER_EFFECTIVE: int = 0xAD

## `AnimateExpBar`'s two: `.PlayExpBarSound`'s at the head of every segment, and
## the one `.LoopLevels` and `.skip_exp_bar_animation` both play before their
## grew-to-level line.
## `BattleStartMessage`'s own, in front of a trainer's line.
const SFX_SHINE: int = 0x5E

## The twenty frames `BattleStartMessage` spends after `SFX_SHINE`, and the forty
## `DoBattle` spends before the player's Pokemon is sent out.
const TRAINER_START_FRAMES: int = 20
const PLAYER_ENTRANCE_FRAMES: int = 40

## `ShowPlayerMonsRemaining` and `ShowOTTrainerMonsRemaining`: where the first
## party ball sits and which way the other five are laid out. OAM coordinates
## subtract sixteen from the y and eight from the x, which is done here.
const HUD_BALL_AT: Dictionary = {
	false: Vector2i(9 * 8 - 8, 4 * 8 - 16), true: Vector2i(12 * 8 - 8, 12 * 8 - 16),
}
const HUD_BALL_STEP: Dictionary = {false: -8, true: 8}
## `StageBallTilesData`'s four tiles, as offsets into `LoadBallIconGFX`'s sheet.
const HUD_BALL_NORMAL: int = 0
const HUD_BALL_STATUSED: int = 1
const HUD_BALL_FAINTED: int = 2
const HUD_BALL_EMPTY: int = 3
## `DrawEnemyHUDBorder`'s `hlcoord 1, 2` and
## `DrawPlayerPartyIconHUDBorder`'s `hlcoord 18, 10`, and the four tiles each
## walks out from there: a side, the corner under it, the far corner and the
## bottom edge between them.
const HUD_BORDER_AT: Dictionary = {false: Vector2i(1, 2), true: Vector2i(18, 10)}
const HUD_BORDER_TILES: Dictionary = {
	false: [0x6D, 0x74, 0x78, 0x76], true: [0x73, 0x5C, 0x6F, 0x76],
}
## `ld b, 8`, the run of bottom edge between the two corners.
const HUD_BORDER_EDGE: int = 8

const SFX_EXP_BAR: int = 0x8C
const SFX_HIT_END_OF_EXP_BAR: int = 0xB6


## Whether an animation, or any of the delays `PlayBattleAnim` wraps it in, is
## still running.
func animation_running() -> bool:
	return _anim != null or not _anim_plan.is_empty() or _anim_delay > 0


## One hardware frame of the animation. Public so a test or a screenshot driver
## can settle or step one without waiting on real time.
func advance_animation() -> bool:
	if not animation_running():
		return false
	if _anim_delay > 0:
		_anim_delay -= 1
		return true
	if _anim != null:
		if _anim.advance_frame() and not _anim.finished():
			_after_anim_frame()
			return true
		_end_script()
		return true
	_run_next_anim_step()
	return true


## `PlayFXAnimID`: three frames of delay, then `PlayBattleAnim`. Builds the whole
## of `_PlayBattleAnim` and `BattleAnimRunScript` as a step list, since the parts
## of it that spend frames have to be spent one rendered frame at a time.
func _begin_animation(event: Dictionary) -> void:
	_anim_event = event
	_anim_plan = []

	var index: int = int(event.get("index", 0))
	var after: int = int(event.get("after_anim", 0))
	var is_move: bool = index < ANIM_MOVE_LIMIT

	# `PlayFXAnimID`'s own `ld c, 3 / call DelayFrames`, then `_PlayBattleAnim`'s
	# six, `BattleAnimAssignPals`/`..._RequestPals` and one more. The two pal
	# calls write nothing here: the palettes an animation remaps are the battle's
	# own and are read back off the background every frame. An entrance comes
	# through `Call_PlayBattleAnim` instead, whose `WaitBGMap` is one frame.
	var lead: int = 1 if bool(event.get("called", false)) else 3
	_step(ANIM_DELAY, {"frames": lead + 6 + 1})

	if is_move:
		if Gen2OptionsStore.current().battle_scene:
			_step(ANIM_CLEAR_HUD, {})
			_step(ANIM_SCRIPT, {"index": index})
			# `xor a / ldh [hSCX] / ldh [hSCY]`, a delay, then the huds.
			_step(ANIM_DELAY, {"frames": 1})
			_step(ANIM_RESTORE_HUD, {})
		else:
			_apply_sub_pic_no_anim(index, int(event.get("param", 0)))
		if after != 0:
			_step(ANIM_WAIT_SFX, {})
			_step(ANIM_HIT_SOUND, {})
			_step(ANIM_SCRIPT, {
				"index": after + Gen2BattleAnimPlayer.BATTLE_AFTERANIMS,
			})
	else:
		_step(ANIM_WAIT_SFX, {})
		_step(ANIM_HIT_SOUND, {})
		_step(ANIM_SCRIPT, {"index": index})

	# `hBGMapMode = 1`, three delays and `WaitSFX`.
	_step(ANIM_DELAY, {"frames": 3})
	_step(ANIM_WAIT_SFX, {})
	if bool(event.get("restore_user_pic", false)):
		_step(ANIM_APPEAR_USER, {})
	_run_next_anim_step()


## The doll the animation would have drawn, written straight into the picture
## when the battle-scene option is off and the script never runs.
##
## `BattleCommand_LowerSub` and `..._RaiseSub` both branch to their own `noanim`
## routine on `_CheckBattleScene`, and `BattleCommand_Substitute`'s own
## `.no_anim` calls `RaiseSubNoAnim`, so the three animation parameters answer
## the same two pictures with the scenes turned off as with them on.
func _apply_sub_pic_no_anim(index: int, param: int) -> void:
	if index != Gen2EffectCommands.SUBSTITUTE_MOVE:
		return
	_set_substitute_pic(
		Gen2Battle.ENEMY if bool(_anim_event.get("enemy_turn", false)) else Gen2Battle.PLAYER,
		param != Gen2EffectCommands.SUBSTITUTE_ANIM_DROP
	)


## Which picture one battler's square is holding, and the view behind it.
func _set_substitute_pic(side: int, raised: bool) -> void:
	if bool(_substitute_pic.get(side, false)) == raised:
		return
	_substitute_pic[side] = raised
	_push_view()


func _step(kind: StringName, values: Dictionary) -> void:
	var entry: Dictionary = values.duplicate()
	entry["kind"] = kind
	_anim_plan.append(entry)


func _run_next_anim_step() -> void:
	while not _anim_plan.is_empty():
		var step: Dictionary = _anim_plan.pop_front()
		match StringName(step["kind"]):
			ANIM_DELAY:
				_anim_delay = int(step["frames"])
				return
			ANIM_CLEAR_HUD:
				# `BattleAnimClearHud`: a delay, the hud off the map, then three
				# more while the map reaches VRAM. `ClearActorHud` reads
				# `hBattleTurn` and clears that side's panel only, which is why
				# the target's bar is still there to watch while it drains.
				_anim_hud_hidden = Gen2Battle.ENEMY \
					if bool(_anim_event.get("enemy_turn", false)) else Gen2Battle.PLAYER
				_anim_delay = 4
				_push_view()
				return
			ANIM_RESTORE_HUD:
				_anim_hud_hidden = -1
				_anim_delay = 4
				_push_view()
				return
			ANIM_WAIT_SFX:
				## `WaitSFX` is a real wait while the driver is being serviced and
				## no wait at all when it is not: a run with no audio device leaves
				## the channels as the sound left them, so `effect_playing()` would
				## answer true for the rest of the run and this plan would never
				## finish. The rendered-frame count is what tells the two apart,
				## and it costs one frame either way.
				if _audio_player != null and _audio_player.effect_playing():
					var rendered: int = _audio_player.timeline_updates()
					if int(step.get("rendered", -1)) != rendered:
						step["rendered"] = rendered
						_anim_plan.push_front(step)
						_anim_delay = 1
						return
			ANIM_SFX:
				_play_anim_sound(int(step["sfx"]))
			ANIM_HIT_SOUND:
				_play_hit_sound()
			ANIM_SCRIPT:
				if _start_script(int(step["index"])):
					return
			ANIM_APPEAR_USER:
				# `AppearUserLowerSub`, which Fly and Dig reach after the
				# animation: `LowerSubNoAnim` writes the user's own picture and
				# `AppearUser` stamps it back into the map it was taken out of.
				var enemy_turn: bool = bool(_anim_event.get("enemy_turn", false))
				_set_substitute_pic(
					Gen2Battle.ENEMY if enemy_turn else Gen2Battle.PLAYER, false
				)
				Gen2BattleScreenMap.stamp(_bg_map, not enemy_turn)
				_push_view()
	_anim = null
	_anim_event = {}
	_push_view()


## `RunBattleAnimScript`, which is `ClearBattleAnims` and then a frame loop. The
## tilemap the battle is showing is what the effects edit, so it goes in here and
## comes back out at the end.
## A cache carrying no animation layer answers with no player, and the step is
## skipped rather than the whole framing: the delays and the hud belong to the
## screen, not to the data.
func _start_script(index: int) -> bool:
	if _anim_data == null:
		return false
	_anim = Gen2BattleAnimPlayer.create(
		_anim_data, index, bool(_anim_event.get("enemy_turn", false)),
		int(_anim_event.get("param", 0))
	)
	if _anim == null:
		return false
	_anim.background().set_bg_map(_bg_map)
	_after_anim_frame()
	return true


## What one `.playframe` produced: the sounds its commands asked for, and the
## video state for the renderer.
func _after_anim_frame() -> void:
	for command: Dictionary in _anim.frame_commands():
		match StringName(command["name"]):
			Gen2BattleAnimScript.SOUND:
				_play_anim_sound(int((command["operands"] as Array)[1]))
			Gen2BattleAnimScript.CRY:
				_play_anim_cry()
			Gen2BattleAnimScript.RAISE_SUB, Gen2BattleAnimScript.DROP_SUB:
				# `BattleAnimCmd_RaiseSub` and `..._DropSub` write the actor's own
				# tiles, and the actor is `hBattleTurn`, which is whose animation
				# this is.
				_set_substitute_pic(
					Gen2Battle.ENEMY if bool(_anim_event.get("enemy_turn", false))
						else Gen2Battle.PLAYER,
					StringName(command["name"]) == Gen2BattleAnimScript.RAISE_SUB
				)
	_push_view()


func _end_script() -> void:
	if _anim != null:
		_bg_map = _anim.background().bg_map.duplicate()
	_anim = null
	_run_next_anim_step()


## `PlayBattleMusic`, which `FindFirstAliveMonAndStartBattle` runs in front of
## `DoBattleTransition`: the piece playing is stopped, the volume goes back to
## maximum, and the battle's own track starts. A world battle has already had it
## started by the screen that ran the transition, on the same driver and from the
## same request, so this asks for a track already playing and the driver
## continues it. A battle standing on its own is where it actually starts.
func _play_battle_music() -> void:
	_battle_music = Gen2Battle.MUSIC_NONE
	if _audio_player == null or _data == null or _battle == null:
		return
	var landmark: int = _world_context.landmark if _world_context != null \
		else Gen2WorldRadio.LANDMARK_SPECIAL
	_battle_music = Gen2WorldBattleAdapter.music_for(
		_world_battle_request, landmark, _time_of_day,
		Gen2WorldState.is_crystal_profile(_data),
	)
	var record: Dictionary = _data.world_audio(&"music", _battle_music)
	if record.is_empty():
		return
	_audio_player.play_record(record, &"map_music", _audio_assets())


## Which track [method _play_battle_music] chose, for a check or a test that
## cannot hear one. `MUSIC_NONE` until a world battle has started.
func battle_music() -> int:
	return _battle_music


## `BattleAnimCmd_Sound`'s second operand, which is the SFX id `PlayStereoSFX`
## is given. The first is the track and panning mask, which this project has no
## stereo field to spend.
func _play_anim_sound(sfx: int) -> void:
	if _audio_player == null or _data == null:
		return
	var record: Dictionary = _data.world_audio(&"sfx", sfx)
	if record.is_empty():
		return
	_audio_player.play_record(record, &"stereo_sfx", _audio_assets())


## `BattleAnimCmd_Cry`: whichever battler `hBattleTurn` names, at its own
## `PokemonCries` pitch and length plus the command's own `.CryData` row.
func _play_anim_cry() -> void:
	if _audio_player == null or _data == null:
		return
	var enemy_turn: bool = bool(_anim_event.get("enemy_turn", false))
	var record: Dictionary = _data.species_cry(_enemy if enemy_turn else _player)
	if record.is_empty():
		return
	_audio_player.play_record(
		record, &"cry", _audio_assets(), false, cry_tracks(enemy_turn)
	)


## `PlayStereoCry` behind an entrance, which names its own species rather than
## reading whoever is on the field: the event is spent where the source plays it,
## which is before the panel it came with has been drawn.
func _play_entrance_cry(side: int, species: int) -> void:
	if _audio_player == null or _data == null:
		return
	var record: Dictionary = _data.species_cry(species)
	if record.is_empty():
		return
	_audio_player.play_record(
		record, &"cry", _audio_assets(), false, cry_tracks(side == Gen2Battle.ENEMY)
	)


## `wCryTracks`: every `PlayStereoCry` in `engine/battle/core.asm` writes `$0f`
## for the enemy's cry and `$f0` for the player's, which is what puts each
## battler's cry on its own side of the field.
static func cry_tracks(enemy: bool) -> int:
	return CRY_TRACKS_ENEMY if enemy else CRY_TRACKS_PLAYER


## `PlayHitSound`: only the two damage after-anims have one, and which of the
## three it is comes off `wTypeModifier`.
func _play_hit_sound() -> void:
	var after: int = int(_anim_event.get("after_anim", 0))
	if after != Gen2BattleAnimPlayer.AFTER_ANIM_ENEMY_DAMAGE \
			and after != Gen2BattleAnimPlayer.AFTER_ANIM_PLAYER_DAMAGE:
		return
	var effectiveness: int = int(_anim_event.get("effectiveness", RomLayout.MATCHUP_EFFECTIVE))
	if effectiveness == 0:
		return
	var sfx: int = SFX_DAMAGE
	if effectiveness > RomLayout.MATCHUP_EFFECTIVE:
		sfx = SFX_SUPER_EFFECTIVE
	elif effectiveness < RomLayout.MATCHUP_EFFECTIVE:
		sfx = SFX_NOT_VERY_EFFECTIVE
	_play_anim_sound(sfx)


func _audio_assets() -> Dictionary:
	if _data == null:
		return {}
	return {
		"wave_samples": _data.world_audio_asset(&"wave_samples"),
		"drumkits": _data.world_audio_asset(&"drumkits"),
	}


## The two pictures put back where a battle draws them, which every send-out and
## every fresh battle does. `ClearBattleAnims` never touches the map, so a Fly
## that took a picture off it leaves it off until something stamps it back.
func _reseed_bg_map() -> void:
	_bg_map = Gen2BattleScreenMap.seeded()
	_faints.clear()


## How full the exp bar is, in `PlaceExpBar`'s own pixels. The committed value:
## the animation below draws its own while it runs, the way the HP bars do, and
## a write that moves the committed count cancels it for the same reason
## [method set_hp] cancels a drain.
func set_exp(pixels: int) -> void:
	var value: int = clampi(pixels, 0, Gen2ExpBarAnimation.LENGTH_PX)
	if value != _exp:
		_exp_bar = null
	_exp = value
	_push_view()


## Where the player's Pokémon sits between its current level's threshold and the
## next, on its growth curve. Recomputed at battle start and whenever
## [constant Gen2Battle.EXP_GAINED] or [constant Gen2Battle.GREW_LEVEL] moves the
## number behind it.
func _refresh_exp_bar() -> void:
	if _battle == null or _battle.player == null:
		set_exp(0)
		return

	var mon: Gen2BattleMon = _battle.player
	set_exp(Gen2ExpBarAnimation.pixels_for(mon.growth_rate(), mon.level, mon.exp))


## What the exp bar is drawing: the animation's pixels while one runs, and the
## committed count otherwise.
func _drawn_exp() -> int:
	return _exp if _exp_bar == null else _exp_bar.pixels()


## Begins the fill [param event]'s award earns, which is `AnimateExpBar`, from
## the [param from_pixels] the bar stood at before the award was committed.
##
## The segments are read out of the events still queued behind this one: one
## ending at the end of the bar per level this gain crosses, then the partial
## fill `.FinishExpBar` computes from the exp and level the gain settled on.
##
## Two of the routine's own guards return before any of that, and both are kept:
## a gainer who is not the Pokémon on the field animates nothing
## (`wCurPartyMon` against `wCurBattleMon`), and neither does one already at
## `MAX_LEVEL`.
func _start_exp_bar(event: Dictionary, from_pixels: int) -> void:
	_exp_bar = null
	if _battle == null or _battle.player == null:
		return

	var index: int = int(event["index"])
	if index != _battle.party(Gen2Battle.PLAYER).active:
		return

	var mon: Gen2BattleMon = _battle.player
	var rate: int = mon.growth_rate()
	# Only this award's own level-ups: a second [constant Gen2Battle.EXP_GAINED]
	# behind it is the Exp. Share pass, and its levels belong to its own bar.
	var levels: int = 0
	for queued: Dictionary in _pending:
		var kind: StringName = StringName(queued["type"])
		if kind == Gen2Battle.EXP_GAINED:
			break
		if kind == Gen2Battle.GREW_LEVEL and int(queued["index"]) == index:
			levels += 1
	if mon.level - levels >= Gen2Experience.MAX_LEVEL:
		return

	var targets: Array[int] = []
	for _level: int in levels:
		targets.append(Gen2ExpBarAnimation.LENGTH_PX)
	targets.append(Gen2ExpBarAnimation.pixels_for(rate, mon.level, mon.exp))
	_exp_bar = Gen2ExpBarAnimation.create(from_pixels, targets)
	## `.PlayExpBarSound` runs before the first `.LoopBarAnimation`, so the sound
	## leads the fill by its own ten frames.
	if not _exp_bar.finished():
		_play_anim_sound(SFX_EXP_BAR)
	_push_view()


## Whether [param index] has another [constant Gen2Battle.GREW_LEVEL] still
## queued before the next award. `.level_loop` raises every level first and the
## box is drawn once after it, so only the last one carries a box.
func _more_levels_queued(index: int) -> bool:
	for queued: Dictionary in _pending:
		var kind: StringName = StringName(queued["type"])
		if kind == Gen2Battle.EXP_GAINED:
			return false
		if kind == Gen2Battle.GREW_LEVEL and int(queued["index"]) == index:
			return true
	return false


## `.skip_exp_bar_animation`'s `Textbox` and `PrintTempMonStats`, or nothing
## while [member _level_up_stats] is empty. `SafeLoadTempTilemapToTilemap` puts
## the screen back afterwards, which is what clearing it is.
func _refresh_level_up_box() -> void:
	if _level_up_layer == null:
		return
	if _level_up_stats.is_empty() or _menu_page == null:
		_level_up_layer.visible = false
		return
	var box: Gen2MenuBox = Gen2BattleMenu.level_up_box()
	_show_layer_image(
		_level_up_layer,
		_menu_page.render(
			box, [], -1, "", 0,
			Gen2StatsScreenPage.stats_placements(
				Gen2BattleMenu.LEVEL_UP_STATS_AT, _level_up_stats,
				Gen2BattleMenu.LEVEL_UP_STATS_SPACING
			)
		),
		box.border_position() * Gen2Font.TILE
	)


func _clear_level_up_box() -> void:
	if _level_up_stats.is_empty():
		return
	_level_up_stats = {}
	_refresh_level_up_box()


## [param prompt] is the text's own terminator: `prompt` waits for a press and
## `done` does not, which is the difference between the line a battle opens with
## and the two send-out lines an animation is played underneath.
func show_message(text: String, prompt: bool = true) -> void:
	# `BattleStartMessage` is called after `InitBattleDisplay` returns, so
	# nothing is said while the pics are still sliding: the box drawn before the
	# slide is an empty one.
	if _intro != null:
		_intro_message = text
		return
	_last_message = text
	## `StdBattleTextbox` blocks on a press for a line it printed; an empty box
	## is the one a menu is drawn over and owes nothing.
	_message_awaits_press = prompt and not text.is_empty()
	if _box != null:
		_box.show_text(text, prompt)


## What the animation layer is doing right now, for a scene test or a screenshot
## driver: which animation, whose turn it is, whether a script is actually
## running (a battle scene turned off spends the delays and runs none), and how
## much it is drawing.
func animation_snapshot() -> Dictionary:
	return {
		"running": animation_running(),
		"playing": _anim != null,
		"index": int(_anim_event.get("index", 0)),
		"enemy_turn": bool(_anim_event.get("enemy_turn", false)),
		"after_anim": int(_anim_event.get("after_anim", 0)),
		"sprites": (_anim.sprites() as Array).size() if _anim != null else 0,
		"hud_visible": _hud_visible(),
	}


## Compact state for scene tests and screenshot drivers. It reports the message
## currently shown by the text box rather than reaching into its texture.
func battle_snapshot() -> Dictionary:
	return {
		"ready": is_ready(),
		"world_battle_active": _world_battle_active,
		"battle_over": _battle != null and _battle.is_over(),
		"winner": _battle.winner() if _battle != null and _battle.is_over() else -1,
		"enemy": _enemy,
		"player": _player,
		"message": _last_message,
		"completion_sent": _world_battle_completion_sent,
		"entrance_running": entrance_running(),
		## Whether the line on screen is one `<PROMPT>` or `<CONT>` blocks on.
		"awaits_press": _message_awaits_press,
		"switch_stage": _switch_stage,
		"switch_cursor": (
			_switch_offer.selected_index() if _switch_offer != null
			else (_switch_menu.cursor if _switch_menu != null else -1)
		),
		"switch_forced": _switch_menu != null and _switch_menu.forced,
		"switch_reason": _switch_reason,
		"menu_stage": _menu_stage,
		"menu_position": _menu_position,
		"move_cursor": _move_cursor,
		"move_rows": _move_rows.duplicate(true),
		"capture_selecting": _capture_selecting,
		"capture_waiting": _capture_waiting,
		"capture_ball": _selected_capture_ball(),
		"capture_balls": _capture_balls.duplicate(),
		"capture_quantities": _capture_quantities.duplicate(),
		"level_up_stats": _level_up_stats.duplicate(),
	}


## Supplies the battle with the overworld's own clock reading, which Morning Sun,
## Synthesis and Moonlight are the only things to read. Set before the request is
## started; a battle begun without it stands at midday.
func set_time_of_day(value: int) -> void:
	_time_of_day = value


## Supplies where the battle is being fought, for a renderer that stages it on
## the map. Set before the scene enters the tree, the way the data source is:
## the renderer is built in _ready() and is handed this straight after
## [method Gen2BattleRenderer.set_battle_data]. Nothing in the battle itself
## reads it.
func set_world_context(context: Gen2BattleWorldContext) -> void:
	_world_context = context
	_push_world_context()


## What a renderer was handed, or null for a battle started outside the world.
func world_context() -> Gen2BattleWorldContext:
	return _world_context


## `BattlePack`, which is the same pack with `wBattleMode` set: the bag rows the
## world hands over, already filtered to what `CheckItemMenu`'s battle nibble
## says can be used at all. Balls stay in the list and reach the ball selector,
## since that is where the throw is drawn.
func set_battle_pack(items: Array, quantities: Dictionary = {}) -> void:
	_pack_rows.clear()
	for raw_item: Variant in items:
		var item: int = int(raw_item)
		if item > 0 and not _pack_rows.has(item):
			_pack_rows.append(item)
	_pack_quantities = quantities.duplicate()
	if _pack_index >= _pack_rows.size():
		_pack_index = 0


func battle_pack_items() -> Array[int]:
	return _pack_rows.duplicate()


## `BattleMenu_Pack`'s own list. A row is chosen with left and right, used with A
## and left with B, the way ball selection already is.
func open_battle_pack() -> Dictionary:
	if _battle == null or _battle.is_over() or not _pending.is_empty():
		return {"ok": false, "reason": &"battle_events_pending"}
	if _pack_rows.is_empty():
		show_message("You have no items to use!")
		return {"ok": false, "reason": &"no_usable_items"}
	_pack_selecting = true
	_pack_index = mini(_pack_index, _pack_rows.size() - 1)
	_show_pack_selection()
	return {"ok": true, "item": selected_pack_item()}


func selected_pack_item() -> int:
	if _pack_rows.is_empty():
		return 0
	return int(_pack_rows[posmod(_pack_index, _pack_rows.size())])


func select_pack_row(index: int) -> Dictionary:
	if not _pack_selecting or _pack_rows.is_empty():
		return {"ok": false, "reason": &"pack_not_open"}
	_pack_index = posmod(index, _pack_rows.size())
	_show_pack_selection()
	return {"ok": true, "item": selected_pack_item()}


func _show_pack_selection() -> void:
	var item: int = selected_pack_item()
	show_message("Use %s x%d. Left and right: choose, A: use, B: back" % [
		_item_name(item), int(_pack_quantities.get(item, 1)),
	])


func close_battle_pack() -> void:
	_pack_selecting = false
	_pack_item = 0
	_open_battle_menu()


## `UseItem`'s jumptable inside a battle. A ball reaches the throw the screen
## already draws, an ITEMMENU_PARTY row asks `UseItem_SelectMon` for a target
## first, and everything else is applied to whoever is out.
func use_selected_pack_item() -> Dictionary:
	if not _pack_selecting or _battle == null:
		return {"ok": false, "reason": &"pack_not_open"}
	var item: int = selected_pack_item()
	if _data != null and int(_data.item(item).get("pocket", 0)) == Gen2WorldPack.TYPE_BALL:
		_pack_selecting = false
		if not _is_wild_battle():
			## `PokeBallEffect`'s `UseBallInTrainerBattle`, which spends neither
			## the ball nor the turn.
			show_message("The trainer blocked the BALL!
Don't be a thief!")
			return {"ok": false, "reason": &"ball_in_trainer_battle"}
		var opened: Dictionary = begin_capture()
		if bool(opened.get("ok", false)):
			select_capture_ball(_capture_balls.find(item))
		return opened
	if _data != null \
		and int(_data.item(item).get("battle_menu", 0)) == Gen2WorldPack.ITEMMENU_PARTY:
		_pack_selecting = false
		_pack_item = item
		_open_switch_pick(&"item")
		return {"ok": true, "status": &"choosing_target", "item": item}
	return _use_pack_item(item, -1)


## `RestorePPEffect`'s question: which of the target's moves the Ether goes on.
## The Elixers fill every slot and never open this.
func _open_pack_move(item: int, target: int) -> void:
	var mon: Gen2BattleMon = _battle.party(Gen2Battle.PLAYER).at(target)
	_pack_move_slots = []
	if mon != null:
		for slot: int in mon.moves.size():
			if int(mon.moves[slot]) > 0:
				_pack_move_slots.append(slot)
	if _pack_move_slots.is_empty():
		_use_pack_item(item, target)
		return
	_pack_item = item
	_pack_move_target = target
	_pack_move_index = 0
	_pack_move_selecting = true
	_show_pack_move_selection()


func _show_pack_move_selection() -> void:
	var mon: Gen2BattleMon = _battle.party(Gen2Battle.PLAYER).at(_pack_move_target)
	var slot: int = int(_pack_move_slots[_pack_move_index])
	var move: Dictionary = _data.move(int(mon.moves[slot])) if _data != null else {}
	show_message("Restore %s %d PP. Left and right: choose, A: use, B: back" % [
		String(move.get("name", "MOVE")), mon.pp_left(slot),
	])


func _close_pack_move() -> void:
	_pack_move_selecting = false
	_pack_move_slots = []
	_pack_move_target = -1


## The chosen row, applied and then paid for with the turn:
## `BATTLEPLAYERACTION_USEITEM` leaves the enemy's own move behind it.
func _use_pack_item(item: int, target: int, move_slot: int = -1) -> Dictionary:
	_pack_selecting = false
	_pack_item = 0
	_close_pack_move()
	var used: Dictionary = _battle.use_bag_item(item, target, move_slot)
	if not bool(used.get("ok", false)):
		## `.Field`'s battle twin: every refused effect is one line and the pack
		## again, so nothing is spent and the turn is still the player's.
		show_message("It won't have any effect.")
		_pack_selecting = true
		return used
	item_used.emit(item, target)
	## `ItemUsedText`, less its `<PLAYER>` the way every other host-authored line
	## here drops one.
	show_message("Used the %s." % _item_name(item))
	if _battle.is_over():
		## `PokeDollEffect`'s `wForcedSwitch`: the battle is already over, so no
		## turn is taken and the terminal text is what follows this line.
		return used
	_pending = _battle.take_actions(Gen2Battle.use_item(item), _enemy_action())
	return used


## Supplies the wild battle with the supported balls currently owned by the
## overworld. The battle scene never reads or mutates world inventory itself.
func set_capture_balls(balls: Array, quantities: Dictionary = {}) -> void:
	_capture_balls.clear()
	_capture_quantities.clear()
	for raw_ball: Variant in balls:
		var ball: int = int(raw_ball)
		if ball > 0 and not _capture_balls.has(ball):
			_capture_balls.append(ball)
	for raw_ball: Variant in quantities:
		var quantity: int = int(quantities[raw_ball])
		if quantity > 0:
			_capture_quantities[int(raw_ball)] = quantity
	if _capture_ball_index >= _capture_balls.size():
		_capture_ball_index = 0


func available_capture_balls() -> Array[int]:
	return _capture_balls.duplicate()


## Returns the live enemy only for a wild overworld battle. The world host uses
## this object as the source for the existing catch calculation and save adapter.
func capture_target() -> Gen2BattleMon:
	return _battle.enemy if _is_wild_battle() and _battle != null else null


## Opens the small wild-battle ball selector. The full bag UI remains a later
## world-service host; this boundary exposes only the capture action.
func begin_capture() -> Dictionary:
	if not _is_wild_battle() or _battle == null or _battle.is_over():
		return _capture_failure(&"capture_not_available")
	if _capture_selecting or _capture_waiting or not _capture_messages.is_empty() \
		or not _capture_result.is_empty():
		return _capture_failure(&"capture_input_busy")
	if not _pending.is_empty():
		return _capture_failure(&"battle_events_pending")
	if _capture_balls.is_empty():
		show_message("You have no POKE BALLS!")
		return _capture_failure(&"no_capture_balls")
	_capture_selecting = true
	_capture_ball_index = 0
	_show_capture_selection()
	return {"ok": true, "ball": _selected_capture_ball()}


func select_capture_ball(index: int) -> Dictionary:
	if not _capture_selecting or _capture_balls.is_empty():
		return _capture_failure(&"capture_selection_not_active")
	_capture_ball_index = posmod(index, _capture_balls.size())
	_show_capture_selection()
	return {"ok": true, "ball": _selected_capture_ball()}


func throw_capture_ball() -> Dictionary:
	if not _capture_selecting or _capture_balls.is_empty():
		return _capture_failure(&"capture_selection_not_active")
	var ball: int = _selected_capture_ball()
	_capture_selecting = false
	_capture_waiting = true
	show_message("You threw a %s!" % _item_name(ball))
	capture_requested.emit(ball)
	return {"ok": true, "status": &"waiting", "ball": ball}


## Delivers the world host's resolved throw. The battle screen only turns the
## structured result into messages and emits completion after those messages.
func complete_capture(result: Dictionary) -> Dictionary:
	if not _capture_waiting:
		return _capture_failure(&"capture_result_not_pending")
	_capture_waiting = false
	_capture_messages.clear()
	_capture_result = result.duplicate(true)
	_capture_terminal = false
	if not bool(result.get("ok", false)):
		_capture_messages.append("The capture could not be completed.")
		return result
	var result_ball: int = int(result.get("ball", 0))
	if result_ball > 0 and result.has("quantity"):
		var next_quantity: int = int(result.get("quantity", 0))
		if next_quantity > 0:
			_capture_quantities[result_ball] = next_quantity
		else:
			_capture_quantities.erase(result_ball)
			_capture_balls.erase(result_ball)
			_capture_ball_index = mini(_capture_ball_index, maxi(_capture_balls.size() - 1, 0))

	var wobbles: int = clampi(int(result.get("wobbles", 0)), 0, 3)
	for _wobble: int in wobbles:
		_capture_messages.append("The ball shook!")
	if bool(result.get("caught", false)):
		_capture_messages.append("Gotcha! %s was caught!" % _name_of(_enemy))
		_capture_terminal = true
	else:
		_capture_messages.append("%s broke free!" % _name_of(_enemy))
	return result


func _show_capture_selection() -> void:
	show_message(
		"Choose %s x%d. Left and right: select, A: throw"
		% [_item_name(_selected_capture_ball()), _capture_quantity(_selected_capture_ball())]
	)


func _show_next_capture_message() -> void:
	if _capture_messages.is_empty():
		return
	show_message(_capture_messages.pop_front())


func _selected_capture_ball() -> int:
	return _capture_balls[_capture_ball_index] if not _capture_balls.is_empty() else 0


func _capture_quantity(ball: int) -> int:
	return int(_capture_quantities.get(ball, 0))


func _item_name(item: int) -> String:
	if _data == null:
		return "BALL"
	var item_name: String = _data.item_name(item)
	return item_name if not item_name.is_empty() else "BALL %d" % item


func _is_wild_battle() -> bool:
	if not _world_battle_active:
		return false
	var values: Variant = _world_battle_request.get("values", _world_battle_request)
	return values is Dictionary and StringName((values as Dictionary).get("kind", &"")) == &"wild"


## `wBattleType` being BATTLETYPE_CONTEST, which is what makes the menu the
## contest's own and the ball a Park Ball.
func _is_bug_contest_battle() -> bool:
	return _battle != null and _battle.battle_type == Gen2Battle.BATTLETYPE_CONTEST


func _capture_failure(reason: StringName) -> Dictionary:
	return {"ok": false, "reason": reason}


func _clear_capture_action() -> void:
	_capture_selecting = false
	_capture_waiting = false
	_capture_messages.clear()
	_capture_terminal = false
	_capture_result.clear()


func _reset_capture_state() -> void:
	_capture_balls.clear()
	_capture_quantities.clear()
	_capture_ball_index = 0
	_clear_capture_action()


## Reveals the rest of the message at once, so a photograph of the screen does
## not depend on how long the capture took to arrive.
func finish() -> void:
	if _box != null:
		_box.finish()


func next_enemy() -> void:
	show_matchup(_enemy + 1, _player, _enemy_level, _player_level)


func next_player() -> void:
	show_matchup(_enemy, _player + 1, _enemy_level, _player_level)


## Takes a quarter of the enemy's health off, which is the fastest way to see
## that a bar and its numbers agree. It goes through the Pokémon rather than
## through the display, so the battle and the screen do not drift apart.
func hurt_enemy() -> void:
	_hurt(_battle.enemy if _battle != null else null)


func hurt_player() -> void:
	_hurt(_battle.player if _battle != null else null)


func _hurt(mon: Gen2BattleMon) -> void:
	if mon == null:
		return
	@warning_ignore("integer_division")
	mon.take_damage(maxi(mon.max_hp() / 4, 1))
	_read_hp()


## Plays one turn out, and the events come back to be shown one at a time.
##
## The player picks at random from what it knows, since no menu exists yet; so
## does the enemy, unless it is a real trainer ([method show_trainer] rather than
## [method show_matchup]), where [Gen2BattleAI] scores the choice from that
## class's AI flags. Random rather than the first slot, so the other three moves
## are ever seen.
func take_turn() -> void:
	if _battle == null or _battle.is_over() or not _pending.is_empty():
		return
	## An unanswered move offer stops everything, the way an unanswered
	## replacement does: KEY_A reaches here without going through
	## [method advance].
	if _battle.awaiting_move_learn():
		return
	_pending = _battle.take_actions(
		Gen2Battle.use_move(_random_slot(Gen2Battle.PLAYER)), _enemy_action()
	)
	_show_next_event()


## The same turn with both slots named rather than rolled, so a test or a
## screenshot driver can photograph one chosen animation instead of whichever
## move a random slot picked. Development only, like [method hurt_enemy].
func take_turn_with(player_slot: int, enemy_slot: int) -> void:
	if _battle == null or _battle.is_over() or not _pending.is_empty():
		return
	_pending = _battle.take_actions(
		Gen2Battle.use_move(player_slot), Gen2Battle.use_move(enemy_slot)
	)
	_show_next_event()


func _random_slot(side: int) -> int:
	var mon: Gen2BattleMon = _battle.mon(side)
	var usable: Array = []
	for slot: int in mon.moves.size():
		if mon.can_use(slot):
			usable.append(slot)
	return usable[_rng.randi_range(0, usable.size() - 1)] if not usable.is_empty() else 0


## The enemy's own move choice: [Gen2BattleAI] against a real trainer's AI
## flags, or [method _random_slot] for [method show_matchup]'s invented
## pairing, which is not one of the cartridge's own trainers and so has no AI
## flags to read.
func _enemy_slot() -> int:
	if _enemy_trainer_class == 0:
		return _random_slot(Gen2Battle.ENEMY)
	# The class's own imported mask under the normal difficulty; the other two
	# rewrite which layers score rather than inventing a level or a stat.
	var weights: int = _rules().ai_move_weights(
		int(_data.trainer_attributes(_enemy_trainer_class).get("ai_move_weights", 0))
	)
	return Gen2BattleAI.choose_slot(
		_battle.mon(Gen2Battle.ENEMY), _battle.mon(Gen2Battle.PLAYER), _data, weights, _rng,
		_battle.mon(Gen2Battle.ENEMY).turns_taken, _battle.mon(Gen2Battle.PLAYER).turns_taken,
		_battle.weather,
		_battle.screens[Gen2Battle.ENEMY], _battle.screens[Gen2Battle.PLAYER],
		Gen2AISwitch.has_bench(_battle), Gen2AISwitch.matchup_score(_battle)
	)


## What the enemy does with the turn, which is a move unless its trainer reaches
## into the bag first. `show_matchup`'s invented pairing is not one of the
## cartridge's trainers, so it has no class flags and never uses an item.
func _enemy_action() -> Dictionary:
	var slot: int = _enemy_slot()
	if _enemy_trainer_class == 0:
		return Gen2Battle.use_move(slot)
	var flags: int = int(
		_data.trainer_attributes(_enemy_trainer_class).get("ai_item_switch", 0)
	)
	return Gen2BattleAI.choose_action(_battle, flags, slot, _rng)


## The run's rules, which the battle carries once it exists and the installed set
## answers for before that: a screen builds its menus before its battle.
func _rules() -> Gen2Rules:
	if _battle != null and _battle.rules != null:
		return _battle.rules
	return _injected_rules if _injected_rules != null else Gen2Rules.active()


## Tries to run, which is `BattleMenu_Run` and settles before the turn does.
##
## Offered in a trainer battle too, because the cartridge offers it there and
## answers with its own refusal rather than greying the entry out.
func run_from_battle() -> void:
	if _battle == null or _battle.is_over() or not _pending.is_empty():
		return
	if _battle.awaiting_move_learn():
		return
	_pending = _battle.take_actions(Gen2Battle.run_away(), _enemy_action())
	_show_next_event()


## Swaps the player's Pokémon for the next one that is standing, as a turn.
##
## The enemy attacks while it happens, because a switch is not free: this is the
## whole point of the ordering rule, and it is worth being able to look at.
func switch_player() -> void:
	if _battle == null or _battle.is_over() or not _pending.is_empty():
		return
	if _battle.awaiting_move_learn():
		return
	var next: int = _next_healthy(Gen2Battle.PLAYER)
	if next < 0:
		return
	_pending = _battle.take_actions(Gen2Battle.switch_to(next), _enemy_action())
	_show_next_event()


## The development shortcut's own pick, with no menu in front of it. Every switch
## the cartridge makes is either chosen from the party list or
## [method Gen2Battle.replacement_target]'s.
func _next_healthy(side: int) -> int:
	var party: Gen2Party = _battle.party(side)
	for index: int in party.size():
		if party.can_send_out(index):
			return index
	return -1


## Opens LearnMove's full-slot branch, or keeps it open. Answered through
## [method _handle_button], the same way capture ball selection is.
##
## Only the player side is ever queued
## ([method Gen2Battle._offer_moves_learned_at]), so there is one stage rather
## than one per side.
func _open_move_learn() -> bool:
	if _battle == null:
		return false
	if _forget_stage == &"":
		if not _battle.must_learn_move(Gen2Battle.PLAYER):
			return false
		var offer: Dictionary = _battle.pending_learn(Gen2Battle.PLAYER)
		var learner: Gen2BattleMon = _battle.party(Gen2Battle.PLAYER).at(int(offer["index"]))
		if learner == null:
			return false
		_forget_moves = Gen2MoveForget.options(_data, learner.moves)
		if _forget_moves.is_empty():
			return false
		_forget_cursor = 0
		_forget_confirm_cursor = 0
		_show_forget_stage(&"ask")
	return true


func _show_forget_stage(stage: StringName) -> void:
	_forget_stage = stage
	_forget_confirm_cursor = 0
	if stage == &"list":
		_show_forget_list()
	else:
		_show_forget_confirm()


## The two yes/no boxes, which open on YES the way YesNoBox does.
func _show_forget_confirm() -> void:
	show_message("%s %s Left and right: move, A: choose" % [
		_forget_prompt_text(),
		">YES  NO" if _forget_confirm_cursor == 0 else " YES >NO",
	])


func _show_forget_list() -> void:
	var names: PackedStringArray = []
	for index: int in _forget_moves.size():
		var entry: Dictionary = _forget_moves[index]
		var move_name: String = String(entry.get("name", ""))
		names.append("[%s]" % move_name if index == _forget_cursor else move_name)
	show_message("%s %s Up and down: move, A: forget, B: back" % [
		Gen2MoveForget.which_text(), " ".join(names),
	])


## The offer's own name fields, which [method Gen2Battle.pending_learn] carries
## so neither is re-derived from a party that may already have changed.
func _forget_move_name() -> String:
	var offer: Dictionary = _battle.pending_learn(Gen2Battle.PLAYER)
	return String(_data.move(int(offer.get("move", 0))).get("name", ""))


func _forget_learner_name() -> String:
	var offer: Dictionary = _battle.pending_learn(Gen2Battle.PLAYER)
	return _name_of(int(offer.get("species", 0)))


## The yes/no boxes and the list, in LearnMove's own order. An HM row prints
## MoveCantForgetHMText and leaves the list open, since .hmmove is `jr .loop`.
func _answer_forget(button: int) -> void:
	## AskForgetMoveText is three paragraphs, so the box still has pages to turn.
	## A confirm reveals and pages first, the way [method advance] does, rather
	## than answering a question the player has not finished reading.
	if button == Gen2Button.A and _box != null and _box.advance():
		return
	match _forget_stage:
		&"ask", &"stop":
			if Gen2Button.is_direction(button):
				_forget_confirm_cursor = 1 - _forget_confirm_cursor
				_show_forget_confirm()
			elif button == Gen2Button.A:
				_confirm_forget_stage()
		&"list":
			match button:
				Gen2Button.UP:
					_forget_cursor = wrapi(_forget_cursor - 1, 0, _forget_moves.size())
					_show_forget_list()
				Gen2Button.DOWN:
					_forget_cursor = wrapi(_forget_cursor + 1, 0, _forget_moves.size())
					_show_forget_list()
				Gen2Button.A:
					_confirm_forget_slot()
				Gen2Button.B:
					_show_forget_stage(&"stop")


func _forget_prompt_text() -> String:
	if _forget_stage == &"stop":
		return Gen2MoveForget.stop_text(_forget_move_name())
	return Gen2MoveForget.ask_text(_forget_learner_name(), _forget_move_name())


func _confirm_forget_stage() -> void:
	var yes: bool = _forget_confirm_cursor == 0
	if _forget_stage == &"ask":
		# No is YesNoBox's carry, which is LearnMove.cancel.
		_show_forget_stage(&"list" if yes else &"stop")
		return
	if not yes:
		# `jp .loop` reaches ForgetMove's ask again.
		_show_forget_stage(&"ask")
		return
	_forget_stage = &""
	_pending = _battle.decline_move(Gen2Battle.PLAYER)
	_show_next_event()


func _confirm_forget_slot() -> void:
	if _forget_cursor < 0 or _forget_cursor >= _forget_moves.size():
		return
	var entry: Dictionary = _forget_moves[_forget_cursor]
	if not bool(entry.get("forgettable", false)):
		show_message("%s %s" % [
			Gen2MoveForget.cant_forget_hm_text(), Gen2MoveForget.which_text(),
		])
		return
	var events: Array = _battle.learn_move(Gen2Battle.PLAYER, int(entry.get("slot", -1)))
	if events.is_empty():
		return
	_forget_stage = &""
	_pending = events
	_show_next_event()


## What a button press does. Finishes the current message if it is still
## revealing, then moves on to the next event, sends out whoever is owed, and
## starts a turn when there is nothing left to say.
func advance() -> void:
	if _box == null:
		return
	## `BattleIntroSlidingPics` is a run of unconditional `DelayFrame`s with
	## nothing reading a button, so a press during the slide does nothing at all.
	if _intro != null:
		return
	## The exp bar stopped at a level boundary is under `.LoopLevels`' own
	## `StdBattleTextbox`, which blocks on a button: this press is that button,
	## and it lets the loop run on into the next level's fill rather than
	## advancing the battle.
	if _exp_bar != null and _exp_bar.paused():
		if _box.advance():
			return
		_exp_bar.resume()
		## The loop reaches `.PlayExpBarSound` again for the segment this press
		## releases, the same as the first one.
		_play_anim_sound(SFX_EXP_BAR)
		return
	## A bar the source is still animating has not printed its message yet, so
	## there is nothing for a press to advance past. Without this the press
	## would pop the next event and the held line would never be shown.
	if bars_animating() or fainting():
		return
	## An animation is a run of unconditional delays, the way the intro is, so a
	## press during one reaches nothing.
	if animation_running():
		return
	if _box.advance():
		return
	_message_awaits_press = false
	## The battle menu is answered with A, which is what this call is: the source
	## reads one joypad for the box and for the menu over it.
	if _menu_stage != &"":
		_answer_menu(Gen2Button.A)
		return
	_continue_after_messages()


## What the source runs on to once nothing is left to say. `DoTurn` falls
## straight out of the last command into `HandleBetweenTurnEffects` and then
## into `BattleMenu`, and nothing between them reads a button, so this is
## reached both by the press that dismissed the last box and by
## [method _show_next_event] finding no line left to print.
func _continue_after_messages() -> void:
	if _box == null:
		return
	## The same waits [method _resume_after_frames] respects: a box still up, a
	## line held behind a bar, or frames nobody has spent yet.
	if _intro != null or bars_animating() or fainting() or animation_running():
		return
	## `applydamage` animates the bar and sinks the picture before `criticaltext`
	## prints, so a line produced while either was running was held rather than
	## raced. Released here, where every wait it can be held behind ends: a faint
	## with no bar beside it is one, and the bar pump never sees that frame.
	if not _held_message.is_empty():
		var held: String = _held_message
		_held_message = ""
		show_message(held)
		return
	if _message_awaits_press:
		return
	## `BattleStartMessage` and `DoBattle`'s opening: each step is either frames
	## or a line, so the pump and the press both arrive back here for the next.
	if _advance_entrance():
		return
	## Nothing is left to print, so the line the box stood beside is gone even
	## though no event was popped to take it away.
	_clear_level_up_box()
	if _capture_selecting or _capture_waiting:
		return
	## A list already up owns the joypad: the battle menu, the pack and its two
	## sub-lists, and the forget offer are each answered by a press rather than
	## run past by the pump.
	if _menu_stage != &"" or _pack_selecting or _pack_move_selecting \
		or _forget_stage != &"":
		return
	if _world_battle_tutorial:
		return
	if not _capture_messages.is_empty():
		_show_next_capture_message()
		return
	if _capture_terminal:
		## `BugContest_SetCaughtContestMon` asks before replacing the Pokemon
		## already caught, over the same `PlaceYesNoBox` a switch offer uses.
		if bool(_capture_result.get("replace_offer", false)) and _switch_stage == &"":
			_open_yes_no(&"contest_replace", CONTEST_REPLACE_TEXT)
			return
		var capture: Dictionary = _capture_result.duplicate(true)
		_clear_capture_action()
		_finish_world_capture(capture)
		return
	if not _capture_result.is_empty():
		_clear_capture_action()
		return
	if not _pending.is_empty():
		_show_next_event()
		return
	## LearnMove runs inside the experience handler, before the loop asks for a
	## replacement, so the offer is answered first.
	if _open_move_learn():
		return
	if _answer_baton_pass():
		return
	if _answer_switch_offer():
		return
	if _replace_the_fallen():
		return
	if _battle != null and _battle.is_over():
		if _world_battle_active and not _battle.has_fled():
			# A run shows neither a win nor a loss text and blacks nobody out:
			# `wBattleResult` is DRAW and the party is still standing.
			if _show_world_battle_terminal_text():
				return
			## `LostBattle`'s `.not_canlose` is the grayscale and a `ret`: the
			## battle prints nothing about blacking out, because `_WhitedOutText`
			## belongs to `Script_Whiteout` on the overworld. What is checked
			## here is only that the party the whiteout will heal can be read.
			if _battle.winner() != Gen2Battle.PLAYER and not _world_battle_recovery_shown:
				if not _prepare_world_battle_recovery():
					return
				_world_battle_recovery_shown = true
		if _save_battle_result() and _world_battle_active:
			_finish_world_battle()
		return
	_open_battle_menu()


## The fought party over the live save, with nothing written to disk.
##
## A ball is thrown mid-battle and the catch is its own transaction, which
## builds its candidate from the live save; without this the party that reaches
## the candidate is the pre-battle one, so the HP and PP spent weakening the
## wild are given back the moment it is caught.
func sync_live_party() -> bool:
	if _source_save == null or _battle == null or _data == null:
		return false
	var fought: Gen2SaveData = Gen2SaveBattleAdapter.from_battle_party(
		_data.id, _data.sha1, _source_save.slot, _battle.party(Gen2Battle.PLAYER),
		"", _source_save
	)
	if fought == null:
		return false
	_source_save.party = fought.party
	return true


## Writes back only after every event from a finished battle has been shown.
## Saving during a resolved turn would capture battle state the player has not
## seen yet, while the persistent save model intentionally has no such state.
func _save_battle_result() -> bool:
	if _save_slot < 0 or _save_written or _battle == null:
		return true
	## `wPartyMon` holds the fighting copy on the cartridge, so damage taken, PP
	## spent and experience gained belong to the party whatever ended the battle.
	## A loss is no exception: nothing puts the pre-battle party back, and the
	## full HP a blacked-out player walks away with is `Script_Whiteout`'s own
	## `special HealParty` rather than a party that was never written.
	var save: Gen2SaveData = Gen2SaveBattleAdapter.from_battle_party(
		_data.id, _data.sha1, _save_slot, _battle.party(Gen2Battle.PLAYER), "", _source_save
	)
	# The world host credits its live state from the completion result below;
	# mirror the same award into the snapshot being written now so Pay Day is not
	# lost between the battle save and that callback.
	if save != null and save.world != null and save.world.world_state != null \
			and _battle.pay_day_money > 0:
		var balance: int = save.world.world_state.money(0)
		save.world.world_state.apply_changes({}, {}, {"money": {
			0: mini(balance + _battle.pay_day_money, Gen2WorldInventory.MAX_MONEY),
		}})
	var result: Dictionary = Gen2SaveStore.save(save, _data)
	if not result["ok"]:
		push_error("Could not save battle result: %s" % result["message"])
		if _world_battle_active:
			_emit_world_battle_failure(&"battle_save_failed", {
				"message": result.get("message", ""),
			})
		return false
	# from_battle_party() returns a clone; without this, the fought party's HP,
	# experience and PP reach disk but never the live save the world screen and
	# the next battle read, so both keep showing the pre-battle party.
	Gen2WorldTransaction.copy_into(_source_save, save)
	_save_written = true
	return true


func _finish_world_battle() -> void:
	if _world_battle_completion_sent or _battle == null or not _battle.is_over():
		return
	var winner: Variant = _battle.winner()
	var outcome: StringName = (
		Gen2WorldBattleAdapter.OUTCOME_RAN
		if _battle.has_fled()
		else (
			Gen2WorldBattleAdapter.OUTCOME_WON
			if winner == Gen2Battle.PLAYER
			else Gen2WorldBattleAdapter.OUTCOME_LOST
		)
	)
	var result: Dictionary = {
		"ok": true,
		"outcome": outcome,
		"winner": winner,
		"request": _world_battle_request.duplicate(true),
		"save_written": _save_written,
	}
	if outcome == Gen2WorldBattleAdapter.OUTCOME_WON:
		if _battle.pay_day_money > 0:
			result["pay_day_money"] = _battle.pay_day_money
		## `ExitBattle`'s `and $f / ret nz`: `wEvolvableFlags` is only ever read
		## after a battle that was WON, so a fight that was lost or run from
		## carries nothing for the overworld's own `EvolveAfterBattle` to walk.
		result["evolvable"] = _battle.evolvable_indices()
	if outcome == Gen2WorldBattleAdapter.OUTCOME_LOST:
		result["recovery"] = _world_battle_recovery.duplicate(true)
	_world_battle_completion_sent = true
	battle_finished.emit(result)


func _finish_world_capture(capture: Dictionary) -> void:
	if _world_battle_completion_sent:
		return
	_world_battle_completion_sent = true
	battle_finished.emit({
		"ok": true,
		"outcome": Gen2WorldBattleAdapter.OUTCOME_CAUGHT,
		"request": _world_battle_request.duplicate(true),
		"capture": capture.duplicate(true),
	})


func _show_world_battle_terminal_text() -> bool:
	if _world_battle_terminal_text_shown:
		return false
	_world_battle_terminal_text_shown = true
	var key: String = (
		"win_text" if _battle.winner() == Gen2Battle.PLAYER else "loss_text"
	)
	var raw_pointer: Variant = _world_battle_request.get(key, {})
	if not raw_pointer is Dictionary:
		return false
	var pointer: Dictionary = raw_pointer as Dictionary
	var address: int = int(pointer.get("address", 0))
	if address <= 0:
		return false
	var bank: int = int(pointer.get("bank", 0))
	var raw: PackedByteArray = _data.world_text(bank, address)
	var decoded: Dictionary = Gen2WorldScript.decode_text(raw)
	if not bool(decoded.get("ok", false)):
		_emit_world_battle_failure(&"missing_battle_result_text", {
			"bank": bank, "address": address, "text_kind": key,
		})
		return true
	var text: String = String(decoded.get("text", ""))
	if text.is_empty():
		return false
	show_message(text)
	return true


func _prepare_world_battle_recovery() -> bool:
	if _source_save == null:
		_world_battle_recovery = {"ok": true, "source": &"development"}
		return true
	var validation: Dictionary = Gen2SaveValidator.validate(_source_save, _data)
	if not bool(validation.get("ok", false)):
		_emit_world_battle_failure(&"battle_recovery_failed", {
			"message": validation.get("message", "invalid source save"),
		})
		return false
	if Gen2SaveBattleAdapter.to_battle_party(_data, _source_save) == null:
		_emit_world_battle_failure(&"battle_recovery_failed", {
			"message": "the saved party could not be reconstructed",
		})
		return false
	_world_battle_recovery = {
		"ok": true, "source": &"save", "slot": _source_save.slot,
	}
	return true


## Answers a Baton Pass that stopped the turn, and whether there was one.
##
## The player's target is `ForcePickSwitchMonInBattle`, which is the party menu
## with no way out of it, so the list is opened and the turn stays standing until
## a row answers it. The enemy's is `FindMonInOTPartyToSwitchIntoBattle`, the
## AI's own type-matchup pick, which [method Gen2Battle.baton_pass_target] makes.
##
## It is answered before a replacement, because a turn left standing here has not
## finished and nothing behind it can be asked yet.
func _answer_baton_pass() -> bool:
	if _battle == null:
		return false
	var side: int = _battle.awaiting_baton_pass()
	if side < 0:
		return false
	if side == Gen2Battle.PLAYER:
		if _switch_stage == &"":
			_open_switch_pick(&"baton_pass")
		return true
	var next: int = _battle.baton_pass_target(side)
	if next < 0:
		return false
	_pending = _battle.pass_to(next)
	_show_next_event()
	return true


## `BattleMenu`: what the player is asked once the turn before it has finished
## being shown. `EmptyBattleTextbox` first, so the menu opens over a clear box
## rather than over the last line of the turn.
##
## `CheckPlayerHasUsableMoves` runs inside `MoveSelectionScreen` rather than
## here, so a Pokemon with nothing left still opens the menu and Struggle is
## chosen when FIGHT is.
func _open_battle_menu() -> void:
	if _battle == null or _battle.is_over() or not _pending.is_empty():
		return
	if _battle.awaiting_move_learn() or _battle.must_replace(Gen2Battle.PLAYER):
		return
	_menu_stage = &"main"
	show_message("")
	_reopen_menu_layer()


func _close_battle_menu() -> void:
	_menu_stage = &""
	_move_rows = []
	_reopen_menu_layer()


## `MoveSelectionScreen`. `wCurMoveNum` opens the cursor, and a Pokemon with no
## usable move at all does not get a list: `CheckPlayerHasUsableMoves` returns
## before the box is drawn and the turn is spent on Struggle.
func _open_move_menu() -> void:
	var mon: Gen2BattleMon = _battle.mon(Gen2Battle.PLAYER)
	_move_rows = Gen2BattleMenu.move_rows(mon, _data)
	if _move_rows.is_empty() or mon.is_out_of_pp():
		_close_battle_menu()
		_take_turn_with_slot(0)
		return
	_move_cursor = clampi(_move_cursor, 0, _move_rows.size() - 1)
	_menu_stage = &"move"
	show_message("")
	_reopen_menu_layer()


## What a press does while one of the two menus is up.
func _answer_menu(button: int) -> void:
	match _menu_stage:
		&"main":
			_answer_battle_menu(button)
		&"move":
			_answer_move_menu(button)
		&"refused":
			## `.place_textbox_start_over` blocks on the line and then jumps back
			## to `MoveSelectionScreen`, which redraws the list.
			if _box != null and _box.advance():
				return
			_open_move_menu()


## `BattleMenu.loop`: the cursor moves, A picks, and B is disabled by the
## header's own STATICMENU_DISABLE_B.
func _answer_battle_menu(button: int) -> void:
	match button:
		Gen2Button.UP, Gen2Button.DOWN, Gen2Button.LEFT, Gen2Button.RIGHT:
			var moved: int = Gen2BattleMenu.main_moved(_menu_position, button)
			if moved == _menu_position:
				return
			_menu_position = moved
			_refresh_menu_layer()
		Gen2Button.A:
			_choose_battle_menu()


func _choose_battle_menu() -> void:
	match _menu_position:
		Gen2BattleMenu.FIGHT:
			_open_move_menu()
		Gen2BattleMenu.PKMN:
			## `BattleMenu_PKMN`'s list, whose SWITCH row is the only one of its
			## three this screen answers: STATS is the summary screen and CANCEL
			## comes back here.
			_close_battle_menu()
			_open_switch_pick(&"player")
		Gen2BattleMenu.PACK:
			## `BattleMenu_Pack` opens the whole pack; the only item this screen
			## can use is a ball, so a wild battle reaches ball selection and a
			## trainer battle is told what `.UseItem`'s own `wWildMon` test would
			## have refused anyway. Its `.contest` branch skips the pack outright
			## and throws the one ball a contest has.
			_close_battle_menu()
			if _is_bug_contest_battle():
				if bool(begin_capture().get("ok", false)):
					throw_capture_ball()
				return
			if not _pack_rows.is_empty():
				open_battle_pack()
				return
			## No bag was handed over, which is every battle outside the world
			## host: a wild one still reaches the throw the screen owns.
			if _is_wild_battle():
				begin_capture()
				return
			show_message("No item can be used here.")
		Gen2BattleMenu.RUN:
			_close_battle_menu()
			run_from_battle()


## `.interpret_joypad`: the cursor wraps, B leaves the list for the menu behind
## it, and A either refuses the slot or spends the turn on it.
func _answer_move_menu(button: int) -> void:
	match button:
		Gen2Button.UP, Gen2Button.DOWN:
			_move_cursor = Gen2BattleMenu.move_cursor_moved(
				_move_cursor, button, _move_rows.size()
			)
			_refresh_menu_layer()
		Gen2Button.B:
			_menu_stage = &"main"
			_reopen_menu_layer()
		Gen2Button.A:
			var row: Dictionary = _move_rows[_move_cursor]
			var refusal: String = Gen2BattleMenu.refusal_for(row)
			if not refusal.is_empty():
				_menu_stage = &"refused"
				show_message(refusal)
				_reopen_menu_layer()
				return
			_close_battle_menu()
			_take_turn_with_slot(int(row.get("slot", 0)))


## The turn `BattleMenu_Fight` leads to, with the slot the list chose. The
## enemy's own action is picked here rather than in the menu, the way
## `wEnemyAction` is decided after the player's choice.
func _take_turn_with_slot(slot: int) -> void:
	if _battle == null or _battle.is_over() or not _pending.is_empty():
		return
	_move_cursor = slot
	_pending = _battle.take_actions(Gen2Battle.use_move(slot), _enemy_action())
	_show_next_event()


## Opens `OfferSwitch`'s yes/no, which only SHIFT ever reaches, and answers
## whether there was a question to put up.
##
## Answered before a replacement for the same reason a Baton Pass is: the turn it
## stopped has not finished, and nothing behind it can be asked yet.
func _answer_switch_offer() -> bool:
	if _battle == null or _battle.awaiting_switch_offer() < 0:
		return false
	if _switch_stage == &"":
		_open_switch_offer()
	return true


## `OfferSwitch`'s own `lb bc, 1, 7` through `_YesNoBox`, which stores the left
## and top coordinates it is handed and adds five and four for the other two
## (`home/menu.asm`). The flags, the two options and the `db 1` that opens the
## cursor on YES are `YesNoMenuHeader`'s. `InterpretTwoOptionMenu`'s fifteen
## frames between the answer and the box coming down are not spent, the way no
## other menu delay here is.
const YES_NO_LEFT: int = 1
const YES_NO_TOP: int = 7
const YES_NO_SPAN: Vector2i = Vector2i(5, 4)
const YES_NO_OPTIONS: Array[String] = ["YES", "NO"]
const YES_NO_FLAGS: int = Gen2MenuBox.STATICMENU_CURSOR \
	| Gen2MenuBox.STATICMENU_NO_TOP_SPACING


## Puts `OfferSwitch`'s question and its yes/no box up. The enemy's Pokémon is
## named while it is still on its way in, which is the whole point of asking
## before `ShowSetEnemyMonAndSendOutAnimation`.
func _open_switch_offer() -> void:
	var incoming: Gen2BattleMon = _battle.party(Gen2Battle.ENEMY).at(
		_battle.awaiting_switch_offer()
	)
	_open_yes_no(&"offer", Gen2BattleSwitchMenu.offer_text(
		_enemy_label(), incoming.name_text() if incoming != null else "", _player_label()
	))


## `AskUseNextPokemon`'s question, over the box its own `lb bc, 1, 7` puts in the
## same place `OfferSwitch`'s goes.
func _open_use_next() -> void:
	_open_yes_no(&"use_next", Gen2BattleSwitchMenu.use_next_text())


func _open_yes_no(stage: StringName, question: String) -> void:
	show_message(question)
	_switch_offer = Gen2WorldMenu.new()
	_switch_offer.options = YES_NO_OPTIONS.duplicate()
	_switch_offer.flags = YES_NO_FLAGS
	_switch_offer.rows = YES_NO_OPTIONS.size()
	_switch_offer.cursor = 0
	_switch_stage = stage
	_reopen_menu_layer()


## `SetUpBattlePartyMenu` and the list behind it. [param reason] is which question
## the row will answer; every one but `OfferSwitch`'s is a list with no way out.
func _open_switch_pick(reason: StringName) -> void:
	_switch_reason = reason
	## `PickSwitchMonInBattle` rather than `ForcePickSwitchMonInBattle` for the
	## two the player opened themselves: `OfferSwitch`'s YES and the battle
	## menu's own PKMN, both of which can be backed out of.
	_switch_menu = Gen2BattleSwitchMenu.for_party(
		_battle.party(Gen2Battle.PLAYER), reason not in [&"offer", &"player", &"item"]
	)
	_switch_offer = null
	_switch_stage = &"pick"
	## `InitPartyMenuGFX` spawns the icons where the list is built, so a reopened
	## list opens on the first frame of their animation rather than resuming.
	if _party_page != null:
		_party_page.reset(_switch_menu.rows)
	_icon_elapsed = 0.0
	## The party menu is the whole screen rather than a box on it, so the battle's
	## own box goes with the field it belongs to.
	if _box != null:
		_box.visible = false
	_reopen_menu_layer()


func _close_switch() -> void:
	_switch_stage = &""
	_switch_reason = &""
	_switch_menu = null
	_switch_offer = null
	if _box != null:
		_box.visible = true
	_reopen_menu_layer()


## What a press does while either menu is up.
func _answer_switch(button: int) -> void:
	match _switch_stage:
		&"offer":
			_answer_switch_offer_button(button)
		&"use_next":
			_answer_use_next_button(button)
		&"pick":
			_answer_switch_pick(button)
		&"contest_replace":
			_answer_contest_replace(button)
		&"refused":
			## `StdBattleTextbox` blocks on a button and `jr .loop` reopens the
			## list behind it.
			if _box != null and _box.advance():
				return
			_open_switch_pick(_switch_reason)


## `BugContest_SetCaughtContestMon`'s own `PlaceYesNoBox`, which `ret c` reads as
## keeping the Pokemon already caught. The answer rides out on the capture
## result, since what it decides is world state rather than battle state.
const CONTEST_REPLACE_TEXT: String = "Replace the one you caught?"


func _answer_contest_replace(button: int) -> void:
	if _offer_still_reading():
		if button == Gen2Button.A:
			_box.advance()
			_refresh_menu_layer()
		return
	match button:
		Gen2Button.UP, Gen2Button.DOWN:
			_switch_offer.move(Vector2i(0, 1 if button == Gen2Button.DOWN else -1))
			_refresh_menu_layer()
		Gen2Button.A, Gen2Button.B:
			var replace: bool = button == Gen2Button.A \
				and _switch_offer.selected_index() == 0
			_close_switch()
			var capture: Dictionary = _capture_result.duplicate(true)
			capture["replace"] = replace
			_clear_capture_action()
			_finish_world_capture(capture)


## `InterpretTwoOptionMenu` over `YesNoMenuHeader`: two rows that do not wrap,
## and a B that is the same answer as NO.
func _answer_switch_offer_button(button: int) -> void:
	## The question is two paragraphs, so a press reads it before it answers
	## anything, the way [method _answer_forget] does. The box is not up on
	## hardware until the text is either.
	if _offer_still_reading():
		if button == Gen2Button.A:
			_box.advance()
			_refresh_menu_layer()
		return
	match button:
		Gen2Button.UP, Gen2Button.DOWN:
			_switch_offer.move(Vector2i(0, 1 if button == Gen2Button.DOWN else -1))
			_refresh_menu_layer()
		Gen2Button.A:
			if _switch_offer.selected_index() == 0:
				_open_switch_pick(&"offer")
			else:
				_decline_switch_offer()
		Gen2Button.B:
			_decline_switch_offer()


## `AskUseNextPokemon`'s own loop. Its `.pressed_b` branch back to YES is
## unreachable: `InterpretTwoOptionMenu` writes cursor NO on every carry it
## returns, so a B is the same answer as NO, which is what the offer above does
## with one too.
func _answer_use_next_button(button: int) -> void:
	if _offer_still_reading():
		if button == Gen2Button.A:
			_box.advance()
			_refresh_menu_layer()
		return
	match button:
		Gen2Button.UP, Gen2Button.DOWN:
			_switch_offer.move(Vector2i(0, 1 if button == Gen2Button.DOWN else -1))
			_refresh_menu_layer()
		Gen2Button.A:
			_answer_use_next(_switch_offer.selected_index() == 0)
		Gen2Button.B:
			_answer_use_next(false)


## YES falls straight into `ForcePlayerMonChoice` with no press in between; NO
## runs, and a run that does not get away leaves its own line up and reaches the
## same list on the press that reads it.
func _answer_use_next(use_next: bool) -> void:
	var events: Array = _battle.answer_use_next(use_next)
	_close_switch()
	if not events.is_empty():
		_pending = events
		_show_next_event()
		return
	_replace_the_fallen()


## Whether `StdBattleTextbox` is still printing the question the box belongs to.
func _offer_still_reading() -> bool:
	return _box != null and (_box.is_revealing() or _box.has_pages_left())


## `PartyMenuSelect`'s own joypad filter: the cursor, A and B, with everything
## else ignored.
func _answer_switch_pick(button: int) -> void:
	match button:
		Gen2Button.UP:
			_switch_menu.move(-1)
			_refresh_menu_layer()
		Gen2Button.DOWN:
			_switch_menu.move(1)
			_refresh_menu_layer()
		Gen2Button.A:
			## `UseItem_SelectMon` makes neither of `PickPartyMonInBattle`'s two
			## checks: a fainted member is exactly what a Revive wants, and the
			## one already out is what a potion usually goes on. The item's own
			## effect is what refuses.
			if _switch_reason == &"item" and not _switch_menu.is_cancel(_switch_menu.cursor):
				_resolve_switch({
					"result": Gen2BattleSwitchMenu.CHOSEN,
					"index": int(_switch_menu.rows[_switch_menu.cursor].get("index", -1)),
				})
				return
			_resolve_switch(_switch_menu.confirm())
		Gen2Button.B:
			_resolve_switch(_switch_menu.cancel())


func _resolve_switch(answer: Dictionary) -> void:
	match StringName(answer.get("result", &"")):
		Gen2BattleSwitchMenu.CHOSEN:
			_play_anim_sound(Gen2BattleSwitchMenu.SFX_READ_TEXT_2)
			_commit_switch(int(answer.get("index", -1)))
		Gen2BattleSwitchMenu.CANCELLED:
			_play_anim_sound(Gen2BattleSwitchMenu.SFX_READ_TEXT_2)
			## A target list backed out of leaves the item where it was and
			## reopens the pack it was chosen from.
			if _switch_reason == &"item":
				_close_switch()
				open_battle_pack()
				return
			## `BattleMenuPKMN_Loop`'s `.Cancel` is a `jp BattleMenu`: the list
			## the player opened themselves goes back to the menu it came from.
			if _switch_reason == &"player":
				_close_switch()
				_open_battle_menu()
				return
			## `OfferSwitch.canceled_switch` falls into `.said_no`: backing out of
			## the list is the same answer as NO.
			_decline_switch_offer()
		Gen2BattleSwitchMenu.CANNOT_CANCEL:
			_play_anim_sound(int(answer.get("sfx", 0)))
		_:
			_show_switch_refusal(String(answer.get("text", "")))


## The chosen row, which finishes whichever question the list was opened for.
func _commit_switch(index: int) -> void:
	var reason: StringName = _switch_reason
	_close_switch()
	match reason:
		&"item":
			## `StatusHealer_Jumptable`'s way back: the pack is where a used item
			## leaves the player, and where a cancelled one does too.
			if _pack_item in Gen2Battle.SLOT_PP_ITEMS:
				_open_pack_move(_pack_item, index)
				return
			_use_pack_item(_pack_item, index)
			return
		&"baton_pass":
			_pending = _battle.pass_to(index)
		&"replace":
			_pending = _battle.replace_fallen(index)
		&"player":
			## `TryPlayerSwitch` spends the turn: the switch is the player's
			## action and the enemy answers it, which is what makes a free switch
			## cost a hit.
			_pending = _battle.take_actions(
				Gen2Battle.switch_to(index), _enemy_action()
			)
		_:
			_pending = _battle.answer_switch_offer(index)
	_show_next_event()


func _decline_switch_offer() -> void:
	_close_switch()
	_pending = _battle.answer_switch_offer(-1)
	_show_next_event()


## `BattleText_MonIsAlreadyOut` and `BattleText_TheresNoWillToBattle`, which the
## source prints in a battle text box over the party menu and then redraws the
## list behind.
func _show_switch_refusal(text: String) -> void:
	_switch_stage = &"refused"
	if _box != null:
		_box.visible = true
	show_message(text)
	_reopen_menu_layer()


## `PlaceEnemysName`: the opponent's class name, a space, and their own name.
func _enemy_label() -> String:
	if _enemy_trainer_class <= 0 or _data == null:
		return _name_of(_enemy)
	return "%s %s" % [_data.trainer_name(_enemy_trainer_class), _enemy_trainer_name()]


## `<PLAYER>`. A development battle has no save to read a name off, so
## `NewGame`'s own default stands in rather than a blank in the middle of a
## sentence.
func _player_label() -> String:
	if _source_save != null and not _source_save.player_name.is_empty():
		return _source_save.player_name
	return Gen2OakSpeech.DEFAULT_MALE


## Redraws the menu layer even when nothing about the cursor moved, which is what
## opening a list has to do: the same stage and cursor can be looking at a
## different party.
func _reopen_menu_layer() -> void:
	_menu_drawn = ""
	_refresh_menu_layer()


## The yes/no frame over the field, or the whole party page in place of it.
## Cheap to call every frame: it rebuilds only when what it would draw changed.
func _refresh_menu_layer() -> void:
	if _menu_layer == null:
		return
	var signature: String = "%s|%s|%d|%d|%d|%s" % [
		_switch_stage, _menu_stage,
		_switch_offer.selected_index() if _switch_offer != null else (
			_switch_menu.cursor if _switch_menu != null else -1
		),
		int(_offer_still_reading()),
		_menu_position * 8 + _move_cursor,
		## The icons move on their own clock, so the cursor alone does not say
		## whether the page still draws what the layer is holding.
		_party_page.animation_signature() if _party_page != null else "",
	]
	if signature == _menu_drawn:
		return
	_menu_drawn = signature

	if _info_layer != null:
		_info_layer.visible = false
	if _battle_menu_layer != null:
		_battle_menu_layer.visible = false
	match _switch_stage:
		&"offer", &"use_next", &"contest_replace":
			_draw_yes_no_box()
			return
		&"pick", &"refused":
			_draw_party_page()
			return
	match _menu_stage:
		&"main":
			_draw_battle_menu()
		&"move":
			_draw_move_menu()
		_:
			_menu_layer.visible = false


func _draw_yes_no_box() -> void:
	if _menu_page == null or _offer_still_reading():
		_menu_layer.visible = false
		return
	var box: Gen2MenuBox = Gen2MenuBox.from_coords(
		YES_NO_LEFT, YES_NO_TOP,
		YES_NO_LEFT + YES_NO_SPAN.x, YES_NO_TOP + YES_NO_SPAN.y, YES_NO_FLAGS
	)
	_show_menu_image(
		_menu_page.render(box, YES_NO_OPTIONS, _switch_offer.selected_index()),
		box.border_position() * Gen2Font.TILE
	)


## `BattleMenuHeader`'s two-by-two, drawn where its own `menu_coords` put it.
func _draw_battle_menu() -> void:
	if _menu_page == null:
		return
	var contest: bool = _is_bug_contest_battle()
	var box: Gen2MenuBox = Gen2BattleMenu.main_box(contest)
	var extras: Array = []
	if contest:
		## `.PrintParkBallsRemaining`, which prints the count beside the row
		## rather than inside it.
		extras.append({
			"text": "%2d" % _capture_quantity(Gen2WorldPartyHost.ITEM_PARK_BALL),
			"at": Gen2BattleMenu.CONTEST_BALLS_AT,
		})
	_show_layer_image(
		_battle_menu_layer,
		_menu_page.render(
			box, Gen2BattleMenu.main_options(contest), _menu_position - 1,
			"", 0, extras
		),
		box.border_position() * Gen2Font.TILE
	)


## `MoveSelectionScreen`'s list and the `MoveInfoBox` beside it.
func _draw_move_menu() -> void:
	if _menu_page == null or _move_rows.is_empty():
		return
	var names: Array = []
	for row: Dictionary in _move_rows:
		names.append(String(row.get("name", "")))
	var box: Gen2MenuBox = Gen2BattleMenu.move_box()
	_show_layer_image(
		_battle_menu_layer,
		_menu_page.render(box, names, _move_cursor),
		box.border_position() * Gen2Font.TILE
	)
	_draw_move_info(_move_rows[_move_cursor])


## `MoveInfoBox`: the type and the PP pair of the row the cursor is on, or its
## `.Disabled` line in place of both.
func _draw_move_info(row: Dictionary) -> void:
	var box: Gen2MenuBox = Gen2BattleMenu.info_box()
	var extras: Array = []
	if bool(row.get("disabled", false)):
		extras.append({
			"text": Gen2BattleMenu.INFO_DISABLED,
			"at": Gen2BattleMenu.INFO_DISABLED_AT,
		})
	else:
		extras.append({
			"text": Gen2BattleMenu.INFO_TYPE_LABEL,
			"at": Gen2BattleMenu.INFO_TYPE_LABEL_AT,
		})
		extras.append({
			"text": _data.type_name(int(row.get("type", 0))),
			"at": Gen2BattleMenu.INFO_TYPE_AT,
		})
		## `PrintNum` with `lb bc, 1, 2`: two digits, space padded, either side
		## of the '/' the routine writes itself.
		extras.append({
			"text": "%2d/%2d" % [int(row.get("pp", 0)), int(row.get("max_pp", 0))],
			"at": Gen2BattleMenu.INFO_PP_AT,
		})
	_show_layer_image(
		_info_layer, _menu_page.render(box, [], -1, "", 0, extras),
		box.border_position() * Gen2Font.TILE
	)


## `PlaySpriteAnimations` over the party page's icons, on the hardware clock the
## bars use. Capped the same way, so a stall drops passes rather than running a
## second of them at once.
func _advance_party_icons(delta: float) -> void:
	if _party_page == null or _switch_menu == null or _switch_stage not in [&"pick", &"refused"]:
		_icon_elapsed = 0.0
		return
	_icon_elapsed = minf(
		_icon_elapsed + delta,
		Gen2WorldAnimation.FRAME_SECONDS * float(Gen2WorldAnimation.MAX_CATCHUP_FRAMES),
	)
	while _icon_elapsed >= Gen2WorldAnimation.FRAME_SECONDS:
		_icon_elapsed -= Gen2WorldAnimation.FRAME_SECONDS
		advance_party_icons()


## One pass of the party page's icons. Public with [method advance_frame] so a
## test or a screenshot driver can step them without waiting on real time.
func advance_party_icons() -> bool:
	if _party_page == null or _switch_menu == null:
		return false
	_party_page.advance(_switch_menu.rows, _switch_menu.cursor)
	return true


func _draw_party_page() -> void:
	if _party_page == null or _switch_menu == null:
		_menu_layer.visible = false
		return
	_show_menu_image(
		_party_page.render(
			_switch_menu.rows, _switch_menu.cursor, Gen2BattleSwitchMenu.prompt_text()
		),
		Vector2i.ZERO
	)


func _show_menu_image(image: Image, at: Vector2i) -> void:
	_show_layer_image(_menu_layer, image, at)


func _show_layer_image(layer: TextureRect, image: Image, at: Vector2i) -> void:
	if layer == null:
		return
	layer.texture = ImageTexture.create_from_image(image)
	layer.position = Vector2(at)
	layer.size = Vector2(image.get_size())
	layer.visible = true


## `HandlePlayerMonFaint` and `HandleEnemyMonFaint`'s replacement tail put on
## screen, and whether any of it had something to do.
##
## The three steps are the source's own order: `AskUseNextPokemon`'s wild
## question, `ForcePlayerMonChoice`'s list, and then the trainer's own entrance,
## which [method Gen2Battle.replace_fallen] picks and which SHIFT turns into
## another offer.
func _replace_the_fallen() -> bool:
	if _battle == null:
		return false

	if _battle.asking_use_next():
		if _switch_stage == &"":
			_open_use_next()
		return true

	if _battle.must_replace(Gen2Battle.PLAYER):
		if _switch_stage == &"":
			_open_switch_pick(&"replace")
		return true

	if not _battle.must_replace(Gen2Battle.ENEMY):
		return false
	var events: Array = _battle.replace_fallen()
	if events.is_empty():
		return false
	_pending = events
	_show_next_event()
	## `EnemySwitch` asks before that Pokémon is on the field, so the question
	## goes up in the same step rather than a press later.
	if _pending.is_empty():
		_answer_switch_offer()
	return true


## The next event, with whatever it changes applied first.
##
## Every number drawn comes from the event, not the Pokémon: the turn has already
## resolved by the time the first event is shown, so reading the Pokémon would
## draw the end of the turn during the middle of it.
func _show_next_event() -> void:
	while not _pending.is_empty():
		var event: Dictionary = _pending.pop_front()
		## The box lasts exactly as long as the line it was drawn beside, and
		## this is the press that took that line away.
		_clear_level_up_box()
		event = Gen2ModHost.publish(Gen2ModHost.CHANNEL_BATTLE, event)
		if StringName(event["type"]) == Gen2Battle.CRY:
			## `PlayStereoCry` is `_PlayMonCry` and then `WaitSFX`, so an
			## entrance stands still for as long as the cry lasts. Its silent
			## sibling `PlayStereoCry2` is what a pic animation uses and is not
			## this.
			_apply_event(event)
			_anim_plan = []
			_step(ANIM_WAIT_SFX, {})
			_run_next_anim_step()
			if animation_running():
				return
			continue
		if StringName(event["type"]) == Gen2Battle.ANIMATION:
			## The engine has already resolved; this event is the frames the
			## screen owes for it, and nothing behind it is shown until they are
			## spent. `PlayFXAnimID` blocks the same way.
			_begin_animation(event)
			if animation_running():
				return
			continue
		_apply_event(event)
		var text: String = _describe(event)
		if not text.is_empty():
			## `applydamage` animates the bar and only then does `criticaltext`
			## print, so a message caused by an event that moved a bar waits for
			## it rather than racing it.
			if not _bars.is_empty() or fainting():
				_held_message = text
			else:
				show_message(text)
			return
	## The queue ran dry with nothing to print. `DoTurn` does not read a button
	## between its last command and `BattleMenu`, so the screen runs on rather
	## than leaving a stale box up until a press nobody owes.
	_continue_after_messages()


## The events that mean a bar moved rather than a bar was placed: each is a
## point where the source reaches `AnimateHPBar` through `DoEnemyDamage`,
## `DoPlayerDamage` or one of the heal commands. `SENT_OUT` is deliberately not
## among them, because that bar is drawn rather than drained.
const HP_BAR_EVENTS: Array[StringName] = [
	Gen2Battle.HIT, Gen2Battle.RECOIL, Gen2Battle.DRAINED, Gen2Battle.OHKO,
	Gen2Battle.HURT_BY_STATUS, Gen2Battle.HURT_ITSELF, Gen2Battle.HP_RESTORED,
	Gen2Battle.TRAINER_USED_ITEM,
]


func _apply_event(event: Dictionary) -> void:
	var before_enemy: int = _enemy_hp
	var before_enemy_max: int = _enemy_max_hp
	var before_player: int = _player_hp
	var before_player_max: int = _player_max_hp
	var before_exp: int = _exp
	_apply_event_state(event)
	if StringName(event["type"]) == Gen2Battle.EXP_GAINED:
		_start_exp_bar(event, before_exp)
		return
	if not HP_BAR_EVENTS.has(StringName(event["type"])):
		return
	_start_bar(Gen2Battle.ENEMY, before_enemy, before_enemy_max)
	_start_bar(Gen2Battle.PLAYER, before_player, before_player_max)


func _apply_event_state(event: Dictionary) -> void:
	match event["type"]:
		Gen2Battle.HIT, Gen2Battle.RECOIL, Gen2Battle.DRAINED, Gen2Battle.OHKO:
			var target: int = int(event.get("target", event["side"]))
			if target == Gen2Battle.ENEMY:
				set_hp(int(event["hp"]), int(event["max_hp"]), _player_hp, _player_max_hp)
			else:
				set_hp(_enemy_hp, _enemy_max_hp, int(event["hp"]), int(event["max_hp"]))
		Gen2Battle.HURT_BY_STATUS, Gen2Battle.HURT_ITSELF, Gen2Battle.HP_RESTORED, \
			Gen2Battle.TRAINER_USED_ITEM:
			if int(event["side"]) == Gen2Battle.ENEMY:
				set_hp(int(event["hp"]), int(event["max_hp"]), _player_hp, _player_max_hp)
			else:
				set_hp(_enemy_hp, _enemy_max_hp, int(event["hp"]), int(event["max_hp"]))
		Gen2Battle.FAINTED:
			# `FaintYourPokemon` and `FaintEnemyPokemon` sink the picture before
			# either prints, so the line waits on the animation.
			_begin_faint(int(event["side"]))
		Gen2Battle.SUBSTITUTE_PIC:
			_set_substitute_pic(int(event["side"]), bool(event["raised"]))
		Gen2Battle.CRY:
			_play_entrance_cry(int(event["side"]), int(event["species"]))
		Gen2Battle.SENT_OUT:
			# The pic and the panel both change, and both come out of the event
			# rather than out of the party, for the same reason every other number
			# here does. The level is part of that: a trainer's own party is not
			# all one level the way the invented one used to be.
			if int(event["side"]) == Gen2Battle.ENEMY:
				enemy_seen.emit(int(event["species"]))
				_enemy = int(event["species"])
				_enemy_unown_form = int(event.get("unown_form", 0))
				_enemy_level = int(event["level"])
				set_hp(int(event["hp"]), int(event["max_hp"]), _player_hp, _player_max_hp)
			else:
				_player = int(event["species"])
				_player_unown_form = int(event.get("unown_form", 0))
				_player_level = int(event["level"])
				set_hp(_enemy_hp, _enemy_max_hp, int(event["hp"]), int(event["max_hp"]))
			# A send-out draws a picture through `GetBattleMonBackpic` or
			# `GetEnemyMonFrontpic`, and the doll it would answer with belongs to
			# a Substitute that switching has already taken away.
			_set_substitute_pic(int(event["side"]), false)
			_reseed_bg_map()
			_refresh_exp_bar()
		Gen2Battle.EXP_GAINED:
			# Never [constant Gen2Battle.ENEMY]: see the event's own doc comment.
			# [method _refresh_exp_bar] always reads whoever is active right now,
			# which answers correctly on its own even when the index that gained
			# it is a benched participant rather than the one on screen.
			_refresh_exp_bar()
		Gen2Battle.GREW_LEVEL:
			# The level number in the panel belongs to whoever is on screen, so it
			# only moves when the index that grew is the one currently active: a
			# benched participant can level up too, and this screen has no bench
			# to show it on.
			# The bar itself is not recomputed here: `.LoopLevels` is inside
			# `AnimateExpBar`, so from the award until the walk ends the animation
			# owns the bar and [method advance_bars] commits the real count when
			# it arrives.
			if int(event["index"]) == _battle.party(Gen2Battle.PLAYER).active:
				_player_level = int(event["new_level"])
				_push_view()
			if _exp_bar == null:
				_refresh_exp_bar()
			## `SFX_HIT_END_OF_EXP_BAR`, then `WaitSFX`, then the line. Both
			## paths play it: `.LoopLevels` for whoever is out and
			## `.skip_exp_bar_animation` for a benched participant.
			_play_anim_sound(SFX_HIT_END_OF_EXP_BAR)
			## `.skip_exp_bar_animation` draws the box once per award, after the
			## last level it crossed, so a walk of several levels shows the
			## stats it finished on rather than one box a level.
			if not _more_levels_queued(int(event["index"])):
				_level_up_stats = (event["new_stats"] as Dictionary).duplicate()
			_refresh_level_up_box()


## An event as a sentence, or an empty string for one there is nothing to say
## about. A neutral hit has no line of its own in these games: the bar moving is
## the whole of the message.
func _describe(event: Dictionary) -> String:
	# Every event carries a side except the one that ends the battle, which is
	# about both of them.
	var side: int = int(event.get("side", Gen2Battle.PLAYER))
	match event["type"]:
		Gen2Battle.USED_MOVE:
			return "%s used %s!" % [
				_battler_name(side), String(_data.move(int(event["move"])).get("name", "")),
			]
		Gen2Battle.MISSED:
			return "%s's attack missed!" % _battler_name(side)
		Gen2Battle.NO_EFFECT:
			return "It doesn't affect %s!" % _battler_name(int(event["target"]))
		Gen2Battle.HIT:
			if bool(event["critical"]):
				return "A critical hit!"
			if int(event["effectiveness"]) > RomLayout.MATCHUP_EFFECTIVE:
				return "It's super effective!"
			if int(event["effectiveness"]) < RomLayout.MATCHUP_EFFECTIVE:
				return "It's not very effective..."
		Gen2Battle.RECOIL:
			return "%s is hit with recoil!" % _battler_name(side)
		Gen2Battle.HIT_TIMES:
			return "Hit %d time%s!" % [int(event["times"]), "" if int(event["times"]) == 1 else "s"]
		Gen2Battle.DRAINED:
			return "%s sucked health from %s!" % [_battler_name(side), _battler_name(int(event["from"]))]
		Gen2Battle.OHKO:
			return "It's a one-hit KO!"
		Gen2Battle.FAINTED:
			return "%s fainted!" % _battler_name(side)
		Gen2Battle.CANNOT_MOVE:
			return "%s %s" % [_battler_name(side), STOPPED_BY.get(event["reason"], "cannot move!")]
		Gen2Battle.WOKE_UP:
			return "%s woke up!" % _battler_name(side)
		Gen2Battle.THAWED:
			# `WasDefrostedText` and `DefrostedOpponentText` are the same line
			# under two names, differing only in whether it is the user or the
			# target that is named.
			return "%s was defrosted!" % _battler_name(side)
		Gen2Battle.STATUS_INFLICTED:
			return "%s %s" % [
				_battler_name(int(event["target"])),
				INFLICTED.get(event["name"], "was hurt!"),
			]
		Gen2Battle.HURT_BY_STATUS:
			return "%s is hurt by its %s!" % [_battler_name(side), event["name"]]
		Gen2Battle.CONFUSE_INFLICTED:
			return "%s became confused!" % _battler_name(int(event["target"]))
		Gen2Battle.CONFUSED:
			return "%s is confused!" % _battler_name(side)
		Gen2Battle.SNAPPED_OUT:
			return "%s snapped out of confusion!" % _battler_name(side)
		Gen2Battle.HURT_ITSELF:
			return "It hurt itself in its confusion!"
		Gen2Battle.CHARGING_UP:
			return "%s %s" % [
				_battler_name(side), CHARGE_TEXT.get(int(event.get("move", 0)), CHARGE_DUG),
			]
		Gen2Battle.STAGES_CLEARED:
			return "All stat changes were eliminated!"
		Gen2Battle.STAGES_COPIED:
			return "%s copied the target's stat changes!" % _battler_name(side)
		Gen2Battle.STAT_CHANGED:
			return _stat_changed_text(event)
		Gen2Battle.STAT_CHANGE_FAILED:
			return _stat_failed_text(event)
		Gen2Battle.WITHDREW:
			# Named out of the event, because by the time this is read the one on
			# the field is already the one that came in.
			if side == Gen2Battle.ENEMY:
				return "Enemy withdrew %s!" % _name_of(int(event["species"]))
			return "%s, come back!" % _name_of(int(event["species"]))
		Gen2Battle.SENT_OUT:
			if side == Gen2Battle.ENEMY:
				return "Enemy sent out %s!" % _name_of(int(event["species"]))
			return SEND_OUT_LINES[
				clampi(int(event.get("line", Gen2Battle.SEND_OUT_GO)), 0, SEND_OUT_LINES.size() - 1)
			] % _name_of(int(event["species"]))
		Gen2Battle.CRY:
			# `PlayStereoCry` prints nothing.
			return ""
		Gen2Battle.EXP_GAINED:
			return "%s gained %d EXP. Points!" % [_name_of(int(event["species"])), int(event["amount"])]
		Gen2Battle.STAT_EXP_GAINED:
			# The cartridge never prints a line of its own for this: it happens
			# silently behind the EXP. Points message above it.
			return ""
		Gen2Battle.GREW_LEVEL:
			return "%s grew to level %d!" % [_name_of(int(event["species"])), int(event["new_level"])]
		Gen2Battle.MOVE_LEARNED:
			return "%s learned %s!" % [
				_name_of(int(event["species"])), String(_data.move(int(event["move"])).get("name", "")),
			]
		Gen2Battle.MOVE_OFFERED:
			return "%s wants to learn %s!" % [
				_name_of(int(event["species"])), String(_data.move(int(event["move"])).get("name", "")),
			]
		Gen2Battle.MOVE_FORGOTTEN:
			return "%s forgot %s and learned %s!" % [
				_name_of(int(event["species"])),
				String(_data.move(int(event["forgot"])).get("name", "")),
				String(_data.move(int(event["learned"])).get("name", "")),
			]
		Gen2Battle.MOVE_DECLINED:
			return "%s did not learn %s." % [
				_name_of(int(event["species"])), String(_data.move(int(event["move"])).get("name", "")),
			]
		Gen2Battle.MOVE_FAILED:
			return "But it failed!"
		Gen2Battle.BIDE_STORING:
			return "%s is storing energy!" % _battler_name(side)
		Gen2Battle.BIDE_UNLEASHED:
			return "%s unleashed energy!" % _battler_name(side)
		Gen2Battle.RAGE_BUILDING:
			return "%s's RAGE is building!" % _battler_name(int(event["target"]))
		Gen2Battle.FUTURE_SIGHT_SET:
			return "%s foresaw an attack!" % _battler_name(side)
		Gen2Battle.FUTURE_SIGHT_HIT:
			return "%s was hit by FUTURE SIGHT!" % _battler_name(int(event["target"]))
		Gen2Battle.MIMIC_LEARNED:
			return "%s learned %s!" % [
				_battler_name(side), String(_data.move(int(event["move"])).get("name", "")),
			]
		Gen2Battle.SKETCHED_MOVE:
			return "%s SKETCHED %s!" % [
				_battler_name(side), String(_data.move(int(event["move"])).get("name", "")),
			]
		Gen2Battle.TYPE_CHANGED:
			return "%s transformed into the %s-type!" % [
				_battler_name(side), _data.type_name(int(event["type_number"])),
			]
		Gen2Battle.DISABLE_INFLICTED:
			return "%s's %s was disabled!" % [
				_battler_name(int(event["target"])), String(_data.move(int(event["move"])).get("name", "")),
			]
		Gen2Battle.DISABLE_ENDED:
			return "%s is disabled no more!" % _battler_name(side)
		Gen2Battle.ATTRACT_INFLICTED:
			return "%s fell in love!" % _battler_name(int(event["target"]))
		Gen2Battle.ENCORE_INFLICTED:
			return "%s got an encore!" % _battler_name(int(event["target"]))
		Gen2Battle.ENCORE_ENDED:
			return "%s's encore ended!" % _battler_name(side)
		Gen2Battle.TRAINER_USED_ITEM:
			# `EnemyUsedOnText`, one line for all thirteen: the trainer's own
			# name is not in the event, so the class is all this can say.
			return "Enemy used %s on %s!" % [
				_data.item_name(int(event["item"])), _battler_name(side),
			]
		Gen2Battle.HP_RESTORED:
			return "%s regained health!" % _battler_name(side)
		Gen2Battle.HP_ALREADY_FULL:
			return "%s's HP is full!" % _battler_name(side)
		Gen2Battle.WENT_TO_SLEEP:
			return "%s went to sleep!" % _battler_name(side)
		Gen2Battle.RESTED:
			return "%s fell asleep and became healthy!" % _battler_name(side)
		Gen2Battle.BELL_CHIMED:
			# `BellChimedText` names nobody, since the bell was heard by a party
			# rather than by a Pokémon.
			return "A bell chimed!"
		Gen2Battle.NOTHING_HAPPENED:
			return "But nothing happened."
		Gen2Battle.MAGNITUDE:
			return "Magnitude %d!" % int(event["magnitude"])
		Gen2Battle.PRESENT_REFUSED:
			return "%s refused the gift!" % _battler_name(int(event["target"]))
		Gen2Battle.CRASHED:
			return "%s kept going and crashed!" % _battler_name(side)
		Gen2Battle.WEATHER_STARTED:
			return WEATHER_STARTED_TEXT.get(int(event["weather"]), "")
		Gen2Battle.WEATHER_CONTINUES:
			return WEATHER_CONTINUES_TEXT.get(int(event["weather"]), "")
		Gen2Battle.WEATHER_ENDED:
			return WEATHER_ENDED_TEXT.get(int(event["weather"]), "")
		Gen2Battle.HURT_BY_SANDSTORM:
			return "The SANDSTORM hits %s!" % _battler_name(side)
		Gen2Battle.RECOVERED_WITH_ITEM:
			return "%s recovered with %s." % [
				_battler_name(side), _data.item_name(int(event["item"])),
			]
		Gen2Battle.RECOVERED_USING_ITEM:
			return "%s recovered using a %s!" % [
				_battler_name(side), _data.item_name(int(event["item"])),
			]
		Gen2Battle.RESTORED_PP:
			return "%s recovered PP using %s." % [
				_battler_name(side), _data.item_name(int(event["item"])),
			]
		Gen2Battle.ITEM_HEALED_CONFUSION:
			return "A %s rid %s of its confusion." % [
				_data.item_name(int(event["item"])), _battler_name(side),
			]
		Gen2Battle.ENDURED:
			return "%s hung on with %s!" % [
				_battler_name(int(event["target"])), _data.item_name(int(event["item"])),
			]
		Gen2Battle.PROTECTED_ITSELF:
			return "%s PROTECTED itself!" % _battler_name(side)
		Gen2Battle.PROTECTING_ITSELF:
			return "%s's PROTECTING itself!" % _battler_name(int(event["target"]))
		Gen2Battle.BRACED_ITSELF:
			return "%s braced itself!" % _battler_name(side)
		Gen2Battle.ENDURED_HIT:
			return "%s ENDURED the hit!" % _battler_name(int(event["target"]))
		Gen2Battle.DESTINY_BOND_SET:
			return "%s's trying to take its opponent with it!" % _battler_name(side)
		Gen2Battle.TOOK_DOWN_WITH_IT:
			return "%s took down with it, %s!" % [
				_battler_name(int(event["target"])), _battler_name(side),
			]
		Gen2Battle.DRAGGED_OUT:
			# `DraggedOutText` is `<USER>`, so it names the Pokemon that used the
			# move rather than the one dragged out. Mirrored, not corrected.
			return "%s was dragged out!" % _battler_name(side)
		Gen2Battle.FLED_IN_FEAR:
			return "%s fled in fear!" % _battler_name(int(event["target"]))
		Gen2Battle.BLOWN_AWAY:
			return "%s was blown away!" % _battler_name(int(event["target"]))
		Gen2Battle.FLED_FROM_BATTLE:
			return "%s fled from battle!" % _battler_name(side)
		Gen2Battle.IDENTIFIED_SET:
			return "%s identified %s!" % [
				_battler_name(side), _battler_name(int(event["target"])),
			]
		Gen2Battle.TOOK_AIM:
			return "%s took aim!" % _battler_name(side)
		Gen2Battle.PP_REDUCED:
			return "%s's %s was reduced by %d!" % [
				_battler_name(int(event["target"])),
				String(_data.move(int(event["move"])).get("name", "")),
				int(event["amount"]),
			]
		Gen2Battle.SHARED_PAIN:
			# SharedPainText names neither Pokemon, since both were levelled.
			return "The battlers shared pain!"
		Gen2Battle.STOLE_ITEM:
			return "%s stole %s from its foe!" % [
				_battler_name(side), _data.item_name(int(event["item"])),
			]
		Gen2Battle.BEAT_UP_ATTACK:
			# BeatUpAttackText names the party member that is swinging, which is
			# only sometimes the Pokemon on the field.
			return "%s's attack!" % _name_of(int(event["species"]))
		Gen2Battle.TRAPPED:
			return _trapped_text(event)
		Gen2Battle.HURT_BY_TRAP:
			return "%s's hurt by %s!" % [
				_battler_name(side), String(_data.move(int(event["move"])).get("name", "")),
			]
		Gen2Battle.RELEASED_FROM_TRAP:
			return "%s was released from %s!" % [
				_battler_name(side), String(_data.move(int(event["move"])).get("name", "")),
			]
		Gen2Battle.CANT_ESCAPE_SET:
			return "%s can't escape now!" % _battler_name(int(event["target"]))
		Gen2Battle.SWITCH_BLOCKED:
			return "%s can't be recalled!" % _battler_name(side)
		Gen2Battle.SCREEN_SET:
			return SCREEN_SET_TEXT.get(int(event["screen"]), "") % _battler_name(side)
		Gen2Battle.SCREEN_FADED:
			var faded: int = int(event["screen"])
			if faded == Gen2Screens.SAFEGUARD:
				return "%s's SAFEGUARD faded!" % _battler_name(side)
			return SCREEN_FADED_TEXT.get(faded, "") % (
				"Enemy #MON" if side == Gen2Battle.ENEMY else "Your #MON"
			)
		Gen2Battle.SAFEGUARD_PROTECTED:
			return "%s is protected by SAFEGUARD!" % _battler_name(int(event["target"]))
		Gen2Battle.PERISH_SONG_STARTED:
			# StartPerishText names neither Pokémon, since the song caught both.
			return "Both #MON will faint in 3 turns!"
		Gen2Battle.PERISH_COUNT:
			return "%s's PERISH count is %d!" % [
				_battler_name(side), int(event["count"]),
			]
		Gen2Battle.SUBSTITUTE_MADE:
			return "%s made a SUBSTITUTE!" % _battler_name(side)
		Gen2Battle.SUBSTITUTE_ALREADY:
			return "%s has a SUBSTITUTE!" % _battler_name(side)
		Gen2Battle.SUBSTITUTE_TOO_WEAK:
			# TooWeakSubText names nobody at all.
			return "Too weak to make a SUBSTITUTE!"
		Gen2Battle.SUBSTITUTE_TOOK_DAMAGE:
			return "The SUBSTITUTE took damage for %s!" % _battler_name(int(event["target"]))
		Gen2Battle.SUBSTITUTE_FADED:
			return "%s's SUBSTITUTE faded!" % _battler_name(int(event["target"]))
		Gen2Battle.WAS_SEEDED:
			return "%s was seeded!" % _battler_name(int(event["target"]))
		Gen2Battle.LEECH_SEED_SAPPED:
			return "LEECH SEED saps %s!" % _battler_name(side)
		Gen2Battle.EVADED:
			return "%s evaded the attack!" % _battler_name(int(event["target"]))
		Gen2Battle.NIGHTMARE_STARTED:
			return "%s started to have a NIGHTMARE!" % _battler_name(int(event["target"]))
		Gen2Battle.HURT_BY_NIGHTMARE:
			return "%s has a NIGHTMARE!" % _battler_name(side)
		Gen2Battle.CURSE_SET:
			# PutACurseText is one text with a paragraph break in it, so the two
			# halves are one line here rather than two events.
			return "%s cut its own HP and put a CURSE on %s!" % [
				_battler_name(side), _battler_name(int(event["target"])),
			]
		Gen2Battle.HURT_BY_CURSE:
			return "%s's hurt by the CURSE!" % _battler_name(side)
		Gen2Battle.SPIKES_SET:
			return "SPIKES scattered all around %s!" % _battler_name(int(event["target"]))
		Gen2Battle.HURT_BY_SPIKES:
			return "%s's hurt by SPIKES!" % _battler_name(side)
		Gen2Battle.SHED_LEECH_SEED:
			return "%s shed LEECH SEED!" % _battler_name(side)
		Gen2Battle.BLEW_SPIKES:
			return "%s blew away SPIKES!" % _battler_name(side)
		Gen2Battle.RELEASED_BY:
			return "%s was released by %s!" % [
				_battler_name(side), _battler_name(int(event["target"])),
			]
		Gen2Battle.MIST_SET:
			return "%s is shrouded in mist!" % _battler_name(side)
		Gen2Battle.FOCUS_ENERGY_SET:
			return "%s is getting pumped!" % _battler_name(side)
		Gen2Battle.MIST_PROTECTED:
			return "%s's stat drop was blocked by mist!" % _battler_name(int(event["target"]))
		Gen2Battle.FLED:
			# BattleText_UserFledUsingAStringBuffer1 is the Smoke Ball's own
			# line; every other branch reaches BattleText_GotAwaySafely.
			if StringName(event.get("how", &"")) == &"item":
				return "%s fled using a %s!" % [
					_battler_name(Gen2Battle.PLAYER),
					_data.item_name(int(event.get("item", 0))),
				]
			return "Got away safely!"
		Gen2Battle.RUN_FAILED:
			return "Can't escape!"
		Gen2Battle.RUN_BLOCKED:
			if StringName(event.get("reason", &"")) == &"trainer":
				return "No! There's no running from a trainer battle!"
			return "Can't escape!"
		Gen2Battle.OVER:
			# A run is a draw with both parties standing, and the line before
			# this one already said so.
			if bool(event.get("fled", false)):
				return ""
			# Both sides can go down in the same turn, through recoil or a burn,
			# and then there is nobody to declare.
			if event["winner"] == null:
				return "Both sides are out of Pokémon!"
			return "%s won!" % ("The enemy" if event["winner"] == Gen2Battle.ENEMY else "Player")
		Gen2Battle.COINS_SCATTERED:
			return "Coins scattered everywhere!"
		Gen2Battle.TRANSFORMED:
			return "%s transformed into %s!" % [
				_battler_name(side), _battler_name(int(event["target"])),
			]
	return ""


## The sentence for a stat that actually moved. Ancientpower's [code]"all"[/code]
## reads as one sentence about the Pokémon rather than five about its stats,
## because that is the one thing the event says that a single stat's does not.
## The sentence a trapping move lands with, which is a per-move line rather than
## one sentence with the move's name in it: `BattleCommand_TrapTarget`'s `.Traps`
## table names five texts, three of which spell the move out and two of which do
## not name it at all. A move number the table does not know cannot happen, since
## those five are the whole of `EFFECT_TRAP_TARGET`.
func _trapped_text(event: Dictionary) -> String:
	var who: String = _battler_name(int(event["target"]))
	var user: String = _battler_name(int(event["side"]))
	match int(event["move"]):
		BIND:
			return "%s used BIND on %s!" % [user, who]
		WRAP:
			return "%s was WRAPPED by %s!" % [who, user]
		CLAMP:
			return "%s was CLAMPED by %s!" % [who, user]
	return "%s was trapped!" % who


func _stat_changed_text(event: Dictionary) -> String:
	var who: String = _battler_name(int(event["target"]))
	if String(event["stat"]) == "all":
		return "%s's stats rose!" % who

	var stat_name: String = STAT_NAMES.get(event["stat"], String(event["stat"]).to_upper())
	var by: int = int(event["by"])
	if by > 0:
		return "%s's %s went way up!" % [who, stat_name] if by >= 2 \
			else "%s's %s went up!" % [who, stat_name]
	return "%s's %s sharply fell!" % [who, stat_name] if by <= -2 \
		else "%s's %s fell!" % [who, stat_name]


## The sentence for a stat that was already at the end of the line. Whether it
## reads "rise" or "drop" depends only on which end, not on how the move phrases
## itself, because that is the cartridge's own rule.
func _stat_failed_text(event: Dictionary) -> String:
	var who: String = _battler_name(int(event["target"]))
	var stat_name: String = STAT_NAMES.get(event["stat"], String(event["stat"]).to_upper())
	if int(event["by"]) > 0:
		return "%s's %s won't rise anymore!" % [who, stat_name]
	return "%s's %s won't drop anymore!" % [who, stat_name]


## How a battle refers to one of the two, which is by side and not by species:
## the enemy's name is prefixed and the player's is not.
func _battler_name(side: int) -> String:
	if side == Gen2Battle.ENEMY:
		return "Enemy %s" % _name_of(_enemy)
	return _name_of(_player)


## Re-reads both Pokémon. For the paths that change health outside a turn, where
## there is no event to read it out of.
func _read_hp() -> void:
	if _battle == null:
		return
	set_hp(
		_battle.enemy.hp, _battle.enemy.max_hp(),
		_battle.player.hp, _battle.player.max_hp()
	)


## The cartridge's own controls first, then the development drivers that stand
## in for a battle menu this screen does not have yet.
func _unhandled_input(event: InputEvent) -> void:
	if not is_ready() or _external_input:
		return
	var button: int = Gen2Button.pressed_in(event)
	if button != Gen2Button.NONE:
		if _handle_button(button):
			accept_event()
		return
	if event.is_pressed() and _handle_debug_key(event):
		accept_event()
		return
	# A mod's own declared control, before the raw leftovers, exactly as
	# Gen2WorldScreen offers it.
	if _renderer_input_free():
		var action: Dictionary = Gen2ModHost.instance().action_in(event)
		if not action.is_empty():
			Gen2ModHost.instance().emit_action(
				action["id"], action["key"], bool(action["pressed"])
			)
			accept_event()
			return
	# Everything the screen wants has been claimed above, so what reaches here is
	# what a renderer may have a use for. Gen2WorldScreen offers its own renderer
	# the same leftovers for the same reason: a renderer that composes its own
	# shot has to be able to let someone steer it.
	if _renderer_input_free() \
		and Gen2ModHost.renderer_handles_battle_input(_renderer, event):
		accept_event()


## Whether the battle itself is idle enough to pass an event on.
##
## The modal input states are the ones that mean something by themselves: the
## forget-move prompt, a switch's yes/no or list, and ball selection. A draining
## bar, the opening slide and a move animation are deliberately not on that list.
## None of them reads input, and a camera that stops answering every time a bar
## drains is not a camera; the presses they do swallow are swallowed in
## [method _handle_button], which runs first and never reaches here.
func _renderer_input_free() -> bool:
	return is_ready() and _forget_stage == &"" and _switch_stage == &"" \
		and _menu_stage == &"" and not _capture_selecting and not _pack_selecting \
		and not _pack_move_selecting


func _handle_button(button: int) -> bool:
	if _forget_stage != &"":
		_answer_forget(button)
		return true

	if _switch_stage != &"":
		_answer_switch(button)
		return true

	if _menu_stage != &"":
		_answer_menu(button)
		return true

	if _pack_move_selecting:
		match button:
			Gen2Button.RIGHT:
				_pack_move_index = posmod(_pack_move_index + 1, _pack_move_slots.size())
				_show_pack_move_selection()
			Gen2Button.LEFT:
				_pack_move_index = posmod(_pack_move_index - 1, _pack_move_slots.size())
				_show_pack_move_selection()
			Gen2Button.A:
				_use_pack_item(
					_pack_item, _pack_move_target, int(_pack_move_slots[_pack_move_index])
				)
			Gen2Button.B:
				_close_pack_move()
				open_battle_pack()
			_:
				return false
		return true

	if _pack_selecting:
		match button:
			Gen2Button.RIGHT:
				select_pack_row(_pack_index + 1)
			Gen2Button.LEFT:
				select_pack_row(_pack_index - 1)
			Gen2Button.A:
				use_selected_pack_item()
			Gen2Button.B:
				close_battle_pack()
			_:
				return false
		return true

	if _capture_selecting:
		match button:
			Gen2Button.RIGHT:
				select_capture_ball(_capture_ball_index + 1)
			Gen2Button.LEFT:
				select_capture_ball(_capture_ball_index - 1)
			Gen2Button.A:
				throw_capture_ball()
			Gen2Button.B:
				_clear_capture_action()
				show_message("Choose an action.")
			_:
				return false
		return true

	if button == Gen2Button.A:
		advance()
		return true
	return false


## Development drivers for a screen with no battle menu: they take a turn, hurt
## a side, switch, run and step through species. Debug builds only, and off the
## keys a button is bound to, so nothing here competes with a real control.
func _handle_debug_key(event: InputEvent) -> bool:
	if not Gen2DebugKeys.enabled():
		return false
	var key: InputEventKey = event as InputEventKey
	if key == null:
		return false
	match key.keycode:
		KEY_BRACKETRIGHT:
			next_enemy()
		KEY_BRACKETLEFT:
			next_player()
		KEY_H:
			hurt_enemy()
		KEY_G:
			hurt_player()
		KEY_T:
			take_turn()
		KEY_Y:
			switch_player()
		KEY_R:
			run_from_battle()
		KEY_V:
			cycle_view()
		_:
			return false
	return true


func _wrap_species(number: int) -> int:
	var count: int = _data.species_count() if _data != null else 0
	return wrapi(number, 1, maxi(count, 1) + 1) if count > 0 else 1


## Builds the view for the selected renderer and attaches it to the layer that
## renderer asked for. See [method Gen2WorldScreen._build_renderer], the same
## boundary for the map.
func _build_renderer() -> void:
	if _renderer != null:
		if _screen.native_size_changed.is_connected(_on_native_size_changed):
			_screen.native_size_changed.disconnect(_on_native_size_changed)
		_renderer.get_parent().remove_child(_renderer)
		Gen2Screen.drop(_renderer)
	_renderer = Gen2ModHost.instance().create_battle_renderer()
	## Before the layer is chosen, because the surface's size is what
	## `set_native_size` is about to be told.
	_apply_screen_fill()
	if Gen2ModHost.renderer_uses_hardware_viewport(_renderer):
		_screen.display_content(_renderer)
	else:
		_screen.display_native(_renderer)
		_screen.native_size_changed.connect(_on_native_size_changed)
		_on_native_size_changed(_screen.native_size())
	_renderer_ready = bool(_renderer.set_battle_data(_data))
	_push_world_context()
	_push_view()
	_apply_renderer_interface_style()


## SCREEN FILL, which a fight takes only when its renderer draws the place
## rather than a picture.
##
## The built-in arena is `_BattleScene`'s own 160x144 and has nothing to put in a
## wider buffer, exactly like the pack or the PC, so it keeps the bars the
## setting gives every other laid-out screen. A renderer on the native layer,
## staged on the map the encounter fired on, has the same world the overworld was
## filling the window with a frame earlier, and shrinking it to 10:9 for the
## length of the battle and back is the surface being decided with the view left
## out of the question.
##
## The interface does not move either way: the panels, the bars and the boxes are
## hardware pixels laid out in 160x144 and stay in the rectangle
## [Gen2Screen] centres in the buffer.
func _apply_screen_fill() -> void:
	_screen.expanded = Gen2OptionsStore.current().screen_fill \
		and not Gen2ModHost.renderer_uses_hardware_viewport(_renderer)


## The text box over a native-layer renderer, the same seam
## [method Gen2WorldScreen._apply_renderer_interface_style] opens on the map: the
## renderer says how opaque the box's field should be and is told where the box
## is, since it is the screen's box and not the renderer's.
func _apply_renderer_interface_style() -> void:
	if _box == null:
		return
	_box.field_opacity = Gen2ModHost.renderer_interface_opacity(_renderer)
	_push_text_box_rect()


func _push_text_box_rect() -> void:
	if _box == null:
		return
	Gen2ModHost.renderer_set_text_box_rect(_renderer, _box.occupied_rect())


## Hands the renderer where the battle is being fought, when the caller supplied
## it and the renderer asked for it. After set_battle_data() and before the first
## view, so a renderer that builds the place once has it before it draws; a
## renderer swapped in mid-battle gets it again here.
func _push_world_context() -> void:
	if not _renderer_ready or _world_context == null:
		return
	if _renderer.has_method(Gen2ModHost.RENDERER_WORLD_CONTEXT_METHOD):
		_renderer.call(Gen2ModHost.RENDERER_WORLD_CONTEXT_METHOD, _world_context)


func _on_native_size_changed(size_pixels: Vector2i) -> void:
	if _renderer != null and _renderer.has_method(Gen2ModHost.RENDERER_RESIZE_METHOD):
		_renderer.call(Gen2ModHost.RENDERER_RESIZE_METHOD, size_pixels)
	Gen2ModHost.renderer_set_screen_rect(_renderer, _screen.screen_rect())


## Switches the live view without disturbing the battle behind it. The same one
## choice the overworld makes: see [method Gen2WorldScreen.select_view].
func select_view(id: StringName) -> Dictionary:
	var result: Dictionary = Gen2ModHost.instance().select_view(id)
	if not bool(result.get("ok", false)):
		show_message("Renderer unavailable: %s" % String(result.get("reason", "unknown")))
		return result
	_build_renderer()
	show_message("Renderer: %s" % Gen2ModHost.instance().view_label(id))
	return result


## Selects the view after the current one, wrapping.
func cycle_view() -> Dictionary:
	var host: Gen2ModHost = Gen2ModHost.instance()
	var ids: Array[StringName] = host.view_ids()
	if ids.size() < 2:
		show_message("No other renderer is registered")
		return {"ok": false, "reason": &"single_renderer"}
	var at: int = ids.find(host.selected_view())
	return select_view(ids[posmod(at + 1, ids.size())])


## `wild` or `trainer`, decided the way the battle itself decides it: a trainer
## class of zero is a wild battle, which is what `wOtherTrainerClass` holds and
## what `Gen2Battle.trainer_battle` was built from.
func _battle_kind() -> StringName:
	return &"trainer" if _enemy_trainer_class > 0 else &"wild"


## The trainer's own name from the imported party record, not the class name.
func _enemy_trainer_name() -> String:
	if _enemy_trainer_class <= 0 or _data == null:
		return ""
	return String(_data.trainer_party(_enemy_trainer_class, _enemy_trainer_index).get("name", ""))


## Pushes the current display values to the renderer. Plain values only, never
## the battle engine: a turn resolves at once and is then shown an event at a
## time, so what is drawn deliberately lags where the battle has got to.
func _push_view() -> void:
	_update_low_health_alarm()
	if not _renderer_ready:
		return
	_renderer.set_view({
		"enemy_species": _enemy, "player_species": _player,
		"enemy_unown_form": _enemy_unown_form,
		"player_unown_form": _player_unown_form,
		## Whose picture is the substitute's doll rather than the Pokémon's own.
		"enemy_substitute": bool(_substitute_pic[Gen2Battle.ENEMY]),
		"player_substitute": bool(_substitute_pic[Gen2Battle.PLAYER]),
		"enemy_name": _name_of(_enemy), "player_name": _name_of(_player),
		"enemy_level": _enemy_level, "player_level": _player_level,
		## Who the fight is against, which the values above do not say. A wild
		## battle carries class 0 and an empty name, the way `wOtherTrainerClass`
		## is zero there; a class is what `GameData.trainer_pic()` and
		## `trainer_name()` take, so a renderer standing the opponent on the field
		## draws the cartridge's own picture of them.
		"battle_kind": _battle_kind(),
		"trainer_class": _enemy_trainer_class,
		"trainer_index": _enemy_trainer_index,
		"trainer_name": _enemy_trainer_name(),
		## The bars draw whatever the animation is on rather than the committed
		## HP, which is what makes them drain. Everything else, including
		## [method battle_snapshot], keeps reading the committed value.
		"enemy_hp": _drawn_hp(Gen2Battle.ENEMY), "enemy_max_hp": _enemy_max_hp,
		"player_hp": _drawn_hp(Gen2Battle.PLAYER), "player_max_hp": _player_max_hp,
		"exp_pixels": _drawn_exp(),
		## The background's own scroll, a value per scanline, empty when it is
		## sitting still.
		"raster_scx": _raster_offsets(),
		"raster_scy": _raster_rows(),
		## `CopyBackpic` puts the player's back pic on the tilemap before
		## `InitBattleDisplay` ever reaches the slide, so it is there through it
		## and comes in with the middle band. Its top three tile rows fall in the
		## band the enemy scrolls, which is what the eighteen sprites below are
		## for; `PlaceGraphic` afterwards is what settles the two pixels between
		## them.
		"player_pic_visible": true,
		"intro_sprites": _intro.sprites() if _intro != null else [],
		## `GetSGBLayout SCGB_BATTLE_GRAYSCALE` is called where the battle is
		## entered and `SCGB_BATTLE_COLORS` only after `BattleIntroSlidingPics`,
		## so a battle slides in with no colour at all and gains it on the frame
		## the slide ends.
		"grayscale": _intro != null,
		## Which picture each square is holding and which panel is on the map.
		## Both change several times while a battle is opening: see
		## [method _build_entrance].
		"enemy_trainer_pic": _enemy_trainer_pic,
		"player_backpic": _player_backpic,
		"player_backpic_palette": "kris" if player_is_female() else "chris",
		"enemy_hud_visible": _enemy_hud_visible \
			and _anim_hud_hidden != Gen2Battle.ENEMY,
		"player_hud_visible": _player_hud_visible \
			and _anim_hud_hidden != Gen2Battle.PLAYER,
		## `BattleStart_TrainerHuds`' party balls and the frame they hang in.
		"trainer_hud_balls": _hud_balls,
		"trainer_hud_border": _hud_border,
		## `wTilemap` and the video state an animation writes over it.
		"bg_map": _bg_map,
		"bg_vbank1": _bg_vbank1,
		"bg_palette_maps": _background_maps(&"bg"),
		"ob_palette_maps": _background_maps(&"ob"),
		"anim_sprites": _anim.sprites() if _anim != null else [],
		"anim_tiles": _anim.tiles() if _anim != null else [],
		## Whether both panels are on the map, which is the summary of the two
		## keys above rather than a third state.
		"hud_visible": _hud_visible(),
	})
	if _box != null:
		_box.raster_scx = _box_raster_offsets()


## The background scroll for the whole screen: the intro's own bands, or an
## animation's `hSCX` plus whatever its scanline table is writing over it.
func _raster_offsets() -> PackedInt32Array:
	if _intro != null:
		return _intro.offsets()
	return _anim_raster(Gen2BattleAnimBackground.LCDC_SCX)


## The same vertically, which only an animation ever asks for: `hSCY` and a
## scanline table pointed at `rSCY`.
func _raster_rows() -> PackedInt32Array:
	return _anim_raster(Gen2BattleAnimBackground.LCDC_SCY)


## One axis of the animation's scroll, per scanline.
##
## The whole-screen `hSCX`/`hSCY` is the base, and the scanline table replaces it
## on every line while `hLCDCPointer` names that axis' register. A table pointed
## at `rBGP` reaches nothing here: `UpdatePals` never touches that register on the
## Color hardware, which is the branch this project builds.
func _anim_raster(register: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _anim == null:
		return out
	var background: Gen2BattleAnimBackground = _anim.background()
	var base: int = background.scx if register == Gen2BattleAnimBackground.LCDC_SCX \
		else background.scy
	var windowed: bool = background.lcdc_pointer == register
	if base == 0 and not windowed:
		return out
	out.resize(Gen2BattleAnimBackground.SCREEN_LINES)
	for line: int in Gen2BattleAnimBackground.SCREEN_LINES:
		out[line] = int(background.ly_overrides[line]) if windowed else base
	return out


## The eight DMG bytes `BattleAnimRequestPals` left on one set of palettes, or
## the identity permutation while no animation is running.
func _background_maps(kind: StringName) -> PackedByteArray:
	if _anim != null:
		var background: Gen2BattleAnimBackground = _anim.background()
		return background.bg_palette_maps if kind == &"bg" else background.ob_palette_maps
	var out: PackedByteArray = PackedByteArray()
	out.resize(Gen2BattleAnimBackground.PALETTE_COUNT)
	out.fill(Gen2BattleAnimBackground.PALETTE_IDENTITY)
	return out


## The same scroll, narrowed to the rows the text box occupies. A box is drawn
## into the background plane like everything else, so `Textbox`'s own rows move
## with whatever moves the plane.
func _box_raster_offsets() -> PackedInt32Array:
	if _intro == null:
		return PackedInt32Array()
	var top: int = Gen2TextBox.STANDARD_TOP * Gen2Font.TILE
	return _intro.offsets().slice(top, top + _box.rows * Gen2Font.TILE)


func _name_of(species: int) -> String:
	return String(_data.species(species).get("name", ""))


func _announce() -> void:
	show_message("Wild %s\nappeared!" % _name_of(_enemy))
