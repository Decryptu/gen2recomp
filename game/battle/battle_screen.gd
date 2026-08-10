class_name Gen2BattleScreen
extends Control

signal battle_finished(result: Dictionary)
signal capture_requested(ball: int)
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
var _save_slot: int = -1
var _save_written: bool = false
var _source_save: Gen2SaveData = null
var _world_battle_active: bool = false
var _world_battle_tutorial: bool = false
var _world_battle_request: Dictionary = {}
var _world_battle_completion_sent: bool = false
var _world_battle_terminal_text_shown: bool = false
var _world_battle_recovery_shown: bool = false
var _world_battle_recovery: Dictionary = {}
var _last_message: String = ""
## A running [Gen2HpBarAnimation] per side. A side with no entry is not moving.
var _bars: Dictionary = {}
## The running [Gen2ExpBarAnimation], or null when the exp bar is not filling.
var _exp_bar: Gen2ExpBarAnimation = null
## The running [Gen2BattleIntro], or null once the pics have slid into place.
var _intro: Gen2BattleIntro = null
## What `BattleStartMessage` will say. It is held for the whole slide, because
## `InitBattleDisplay` returns before it is called and the box drawn before the
## slide is an empty one.
var _intro_message: String = ""
## The text the event pump produced while a bar was still draining. The source
## prints it after the bar arrives, since `applydamage` runs before
## `criticaltext` and `supereffectivetext`.
var _held_message: String = ""
## Leftover of a hardware frame the bars and the intro have not counted yet.
var _frame_elapsed: float = 0.0
## What the overworld clock said when the battle started, for the three heals
## that read it. Only the world path supplies one; the development drivers below
## leave [Gen2Battle] at its own midday default.
var _time_of_day: int = Gen2WorldPalette.TIME_DAY
## Where the battle is being fought, for a renderer that draws the place rather
## than a white field. Null unless the caller supplied one; see
## [method set_world_context].
var _world_context: Gen2BattleWorldContext = null
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

## The trainer class behind the enemy's own moves, or zero for
## [method show_matchup]'s invented pairing, which has no class and so no AI
## flags of its own to read: it falls back to [method _random_slot], same as
## before this existed. Reset by both, set only by [method show_trainer].
var _enemy_trainer_class: int = 0

var _enemy: int = 1
var _player: int = 1
var _enemy_level: int = 5
var _player_level: int = 5
var _enemy_hp: int = 0
var _enemy_max_hp: int = 0
var _player_hp: int = 0
var _player_max_hp: int = 0
## The committed exp bar, in `PlaceExpBar`'s pixels.
var _exp: int = 0

var _box: Gen2TextBox = null

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
var _anim_hud_hidden: bool = false
var _audio_player: Gen2AudioPlayer = null

@onready var _screen: Gen2Screen = %Screen


## Bars drain and the intro slides on hardware frames, not on rendered ones, the
## same reason [Gen2WorldAnimation] paces the overworld that way: the two-frame
## step `HPBarAnim_BGMapUpdate` waits and `BattleIntroSlidingPics`' own
## `DelayFrame` are both hardware frame counts.
func _process(delta: float) -> void:
	if not frames_running():
		_frame_elapsed = 0.0
		return
	_frame_elapsed += delta
	while _frame_elapsed >= Gen2WorldAnimation.FRAME_SECONDS and frames_running():
		_frame_elapsed -= Gen2WorldAnimation.FRAME_SECONDS
		advance_frame()


## Whether anything is counting hardware frames right now. Public with
## [method advance_frame] so a test or a screenshot driver can settle the screen
## without waiting on real time.
func frames_running() -> bool:
	return bars_animating() or _intro != null or animation_running()


## One hardware frame of everything that counts them. Public through
## [method advance_bars] and [method advance_intro] so a test or a screenshot
## driver can settle either without waiting on real time.
func advance_frame() -> bool:
	var moved: bool = advance_intro()
	moved = advance_bars() or moved
	return advance_animation() or moved


func _ready() -> void:
	_data = _injected_data if _injected_data != null else _selected_runtime_data()
	if _data == null:
		_data = GameData.open_any()
	_build_renderer()
	if not _renderer_ready:
		return

	_audio_player = AUDIO_PLAYER_SCRIPT.new()
	_audio_player.name = "AudioPlayer"
	add_child(_audio_player)
	_anim_data = Gen2BattleAnimData.from_game_data(_data)

	_box = Gen2TextBox.new()
	_box.font = Gen2Font.from_data(_data)
	## wTextboxFrame: a battle's own boxes are drawn with the player's frame too.
	_box.set_frame_style(Gen2OptionsStore.current().textbox_frame)
	_screen.display(_box)
	_box.place_at_bottom()

	var world_meta: Variant = get_meta("world_battle_request", {})
	if world_meta is Dictionary and not (world_meta as Dictionary).is_empty():
		call_deferred("_start_world_battle_from_meta", world_meta)
	else:
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


func _selected_runtime_data() -> GameData:
	var runtime: Node = get_node_or_null("/root/GameRuntime")
	if runtime != null and bool(runtime.call("has_selected_game")):
		return runtime.call("selected_data") as GameData
	return null


func _selected_runtime_save() -> Gen2SaveData:
	var runtime: Node = get_node_or_null("/root/GameRuntime")
	if runtime != null and bool(runtime.call("has_selected_save_slot")):
		return runtime.call("selected_save") as Gen2SaveData
	return null


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
	_battle = Gen2Battle.create_parties(
		_data, _party_from(_player, _player_level), _party_from(_enemy, _enemy_level), _rng
	)
	if _battle == null:
		return

	_init_battle_display()


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
	_battle = Gen2Battle.create_parties(
		_data, _party_from(_player, _player_level), enemy_party, _rng, true
	)
	if _battle == null:
		return
	_battle.load_trainer_items(trainer_class)

	_init_battle_display()

	var trainer: Dictionary = _data.trainer_party(trainer_class, index)
	show_message("%s %s wants to fight!" % [
		_data.trainer_name(trainer_class), String(trainer.get("name", "")),
	])


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
	_player = player_lead.species
	_player_level = player_lead.level
	_enemy = enemy_lead.species
	_enemy_level = enemy_lead.level
	_battle = Gen2Battle.create_parties(_data, player_party, enemy_party, _rng)
	if _battle == null:
		_save_slot = -1
		return false
	_init_battle_display()
	return true


## Starts a battle requested by the scene-free overworld runtime. The caller
## keeps the world API alive while this screen owns the battle presentation.
func start_world_battle(request: Dictionary, save: Gen2SaveData = null) -> bool:
	_clear_capture_action()
	if _data == null or not is_ready():
		_emit_world_battle_failure(&"missing_battle_data")
		return false
	var player_party: Gen2Party = (
		Gen2SaveBattleAdapter.to_battle_party(_data, save)
		if save != null else Gen2WorldBattleAdapter.fallback_party(_data)
	)
	var prepared: Dictionary = Gen2WorldBattleAdapter.prepare(_data, request, player_party, _rng)
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
	_battle = prepared["battle"]
	_battle.time_of_day = _time_of_day
	_battle.load_trainer_items(_enemy_trainer_class)
	var player_party_ready: Gen2Party = prepared["player_party"]
	var enemy_party_ready: Gen2Party = prepared["enemy_party"]
	_player = player_party_ready.active_mon().species
	_player_level = player_party_ready.active_mon().level
	_enemy = enemy_party_ready.active_mon().species
	_enemy_level = enemy_party_ready.active_mon().level
	_init_battle_display()

	if _world_battle_tutorial:
		show_message("Gotcha! %s was caught!" % _name_of(_enemy))
		call_deferred("_finish_world_catch_tutorial")
	elif bool(prepared.get("trainer_battle", false)):
		var trainer: Dictionary = _data.trainer_party(
			int(prepared.get("trainer_class", 0)), int(prepared.get("trainer_index", 0))
		)
		show_message("%s %s wants to fight!" % [
			_data.trainer_name(int(prepared.get("trainer_class", 0))),
			String(trainer.get("name", "")),
		])
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


## Public screenshot driver for the overworld battle recovery boundary. It
## starts a real host battle using the fallback development party, then
## completes it as a loss so the recovery message is visible without input.
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


func _start_world_battle_from_meta(meta: Variant) -> void:
	if not meta is Dictionary:
		_emit_world_battle_failure(&"invalid_battle_metadata")
		return
	var values: Dictionary = meta as Dictionary
	var save_value: Variant = values.get("save", null)
	var save: Gen2SaveData = save_value if save_value is Gen2SaveData else null
	start_world_battle(values.get("request", {}), save)


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


## Whether any bar is still moving, which is what holds the next message back.
func bars_animating() -> bool:
	return not _bars.is_empty() or _exp_bar != null


## Whether the two pics are still sliding into place.
func intro_running() -> bool:
	return _intro != null


## `InitBattleDisplay`: the display a battle opens with, and the slide that puts
## it there. Every caller that has just built a battle reaches this, which is the
## same order the source uses, `InitBattleDisplay` before `BattleStartMessage`.
func _init_battle_display() -> void:
	_reseed_bg_map()
	set_hp(
		_battle.enemy.hp, _battle.enemy.max_hp(),
		_battle.player.hp, _battle.player.max_hp()
	)
	_refresh_exp_bar()
	_intro = Gen2BattleIntro.for_data(_data)
	_intro_message = ""
	_push_view()


## One hardware frame of the intro. Public so a test or a screenshot driver can
## settle it without waiting on real time.
func advance_intro() -> bool:
	if _intro == null:
		return false
	if not _intro.advance_frame():
		return false
	if _intro.finished():
		# `InitBattleDisplay`'s own `xor a` / `ldh [hSCX], a` after the call, and
		# then `BattleStartMessage`.
		_intro = null
		_push_view()
		if not _intro_message.is_empty():
			var text: String = _intro_message
			_intro_message = ""
			show_message(text)
		return true
	_push_view()
	return true


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

	if not _held_message.is_empty() and _bars.is_empty():
		var text: String = _held_message
		_held_message = ""
		show_message(text)
	elif boundary and _exp_bar != null:
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

## `wFXAnimID` is a word: an id past this is not a move and skips the whole
## battle-scene, hud and after-anim half of `BattleAnimRunScript`.
const ANIM_MOVE_LIMIT: int = 0x100

## `PlayHitSound`'s three effects, by their `constants/sfx_constants.asm`
## numbers, which are the same in both pins.
const SFX_NOT_VERY_EFFECTIVE: int = 0xAB
const SFX_DAMAGE: int = 0xAC
const SFX_SUPER_EFFECTIVE: int = 0xAD


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
	# own and are read back off the background every frame.
	_step(ANIM_DELAY, {"frames": 3 + 6 + 1})

	if is_move:
		if Gen2OptionsStore.current().battle_scene:
			_step(ANIM_CLEAR_HUD, {})
			_step(ANIM_SCRIPT, {"index": index})
			# `xor a / ldh [hSCX] / ldh [hSCY]`, a delay, then the huds.
			_step(ANIM_DELAY, {"frames": 1})
			_step(ANIM_RESTORE_HUD, {})
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
				# more while the map reaches VRAM.
				_anim_hud_hidden = true
				_anim_delay = 4
				_push_view()
				return
			ANIM_RESTORE_HUD:
				_anim_hud_hidden = false
				_anim_delay = 4
				_push_view()
				return
			ANIM_WAIT_SFX:
				if _audio_player != null and _audio_player.effect_playing():
					_anim_plan.push_front(step)
					_anim_delay = 1
					return
			ANIM_HIT_SOUND:
				_play_hit_sound()
			ANIM_SCRIPT:
				if _start_script(int(step["index"])):
					return
			ANIM_APPEAR_USER:
				# `AppearUserLowerSub`, which Fly and Dig reach after the
				# animation: the user's own picture stamped back into the map it
				# was taken out of.
				Gen2BattleScreenMap.stamp(
					_bg_map, not bool(_anim_event.get("enemy_turn", false))
				)
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
	_push_view()


func _end_script() -> void:
	if _anim != null:
		_bg_map = _anim.background().bg_map.duplicate()
	_anim = null
	_run_next_anim_step()


## `BattleAnimCmd_Sound`'s second operand, which is the SFX id `PlayStereoSFX`
## is given. The first is the track and panning mask, which this project has no
## stereo field to spend.
func _play_anim_sound(sfx: int) -> void:
	if _audio_player == null or _data == null:
		return
	var record: Dictionary = _data.world_audio(&"sfx", sfx)
	if record.is_empty():
		return
	_audio_player.play_record(record, &"sound", _audio_assets())


## `BattleAnimCmd_Cry`: whichever battler `hBattleTurn` names, at its own
## `PokemonCries` pitch and length plus the command's own `.CryData` row.
func _play_anim_cry() -> void:
	if _audio_player == null or _data == null:
		return
	var enemy_turn: bool = bool(_anim_event.get("enemy_turn", false))
	var record: Dictionary = _data.species_cry(_enemy if enemy_turn else _player)
	if record.is_empty():
		return
	_audio_player.play_record(record, &"cry", _audio_assets())


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
	_push_view()


func show_message(text: String) -> void:
	# `BattleStartMessage` is called after `InitBattleDisplay` returns, so
	# nothing is said while the pics are still sliding: the box drawn before the
	# slide is an empty one.
	if _intro != null:
		_intro_message = text
		return
	_last_message = text
	if _box != null:
		_box.show_text(text)


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
		"hud_visible": not _anim_hud_hidden,
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
		"capture_selecting": _capture_selecting,
		"capture_waiting": _capture_waiting,
		"capture_ball": _selected_capture_ball(),
		"capture_balls": _capture_balls.duplicate(),
		"capture_quantities": _capture_quantities.duplicate(),
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
	var name: String = _data.item_name(item)
	return name if not name.is_empty() else "BALL %d" % item


func _is_wild_battle() -> bool:
	if not _world_battle_active:
		return false
	var values: Variant = _world_battle_request.get("values", _world_battle_request)
	return values is Dictionary and StringName((values as Dictionary).get("kind", &"")) == &"wild"


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
	_announce()


func next_player() -> void:
	show_matchup(_enemy, _player + 1, _enemy_level, _player_level)
	_announce()


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
	var weights: int = int(_data.trainer_attributes(_enemy_trainer_class).get("ai_move_weights", 0))
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
		var name: String = String(entry.get("name", ""))
		names.append("[%s]" % name if index == _forget_cursor else name)
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
		return
	## A bar the source is still animating has not printed its message yet, so
	## there is nothing for a press to advance past. Without this the press
	## would pop the next event and the held line would never be shown.
	if bars_animating():
		return
	## An animation is a run of unconditional delays, the way the intro is, so a
	## press during one reaches nothing.
	if animation_running():
		return
	if _box.advance():
		return
	if _capture_selecting or _capture_waiting:
		return
	if _world_battle_tutorial:
		return
	if not _capture_messages.is_empty():
		_show_next_capture_message()
		return
	if _capture_terminal:
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
	if _replace_the_fallen():
		return
	if _battle != null and _battle.is_over():
		if _world_battle_active and not _battle.has_fled():
			# A run shows neither a win nor a loss text and blacks nobody out:
			# `wBattleResult` is DRAW and the party is still standing.
			if _show_world_battle_terminal_text():
				return
			if _battle.winner() != Gen2Battle.PLAYER and not _world_battle_recovery_shown:
				if not _prepare_world_battle_recovery():
					return
				_world_battle_recovery_shown = true
				show_message("Blackout! Party restored.")
				return
		if _save_battle_result() and _world_battle_active:
			_finish_world_battle()
		return
	take_turn()


## Writes back only after every event from a finished battle has been shown.
## Saving during a resolved turn would capture battle state the player has not
## seen yet, while the persistent save model intentionally has no such state.
func _save_battle_result() -> bool:
	if _save_slot < 0 or _save_written or _battle == null:
		return true
	if _battle.winner() != Gen2Battle.PLAYER:
		return true
	var save: Gen2SaveData = Gen2SaveBattleAdapter.from_battle_party(
		_data.id, _data.sha1, _save_slot, _battle.party(Gen2Battle.PLAYER), "", _source_save
	)
	var result: Dictionary = Gen2SaveStore.save(save, _data)
	if not result["ok"]:
		push_error("Could not save battle result: %s" % result["message"])
		if _world_battle_active:
			_emit_world_battle_failure(&"battle_save_failed", {
				"message": result.get("message", ""),
			})
		return false
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


## Sends out the first Pokémon standing on any side that owes one, and answers
## whether it had to. Choosing which is a menu on the player's side and an AI on
## the enemy's; this screen has neither, so it takes the first.
func _replace_the_fallen() -> bool:
	if _battle == null:
		return false

	for side: int in [Gen2Battle.PLAYER, Gen2Battle.ENEMY]:
		if not _battle.must_replace(side):
			continue
		var next: int = _next_healthy(side)
		if next < 0:
			continue
		_pending = _battle.send_out(side, next)
		_show_next_event()
		return true
	return false


func _next_healthy(side: int) -> int:
	var party: Gen2Party = _battle.party(side)
	for index: int in party.size():
		if party.can_send_out(index):
			return index
	return -1


## The next event, with whatever it changes applied first.
##
## Every number drawn comes from the event, not the Pokémon: the turn has already
## resolved by the time the first event is shown, so reading the Pokémon would
## draw the end of the turn during the middle of it.
func _show_next_event() -> void:
	while not _pending.is_empty():
		var event: Dictionary = _pending.pop_front()
		Gen2ModHost.publish(Gen2ModHost.CHANNEL_BATTLE, event)
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
			if not _bars.is_empty():
				_held_message = text
			else:
				show_message(text)
			return


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
		Gen2Battle.SENT_OUT:
			# The pic and the panel both change, and both come out of the event
			# rather than out of the party, for the same reason every other number
			# here does. The level is part of that: a trainer's own party is not
			# all one level the way the invented one used to be.
			if int(event["side"]) == Gen2Battle.ENEMY:
				enemy_seen.emit(int(event["species"]))
				_enemy = int(event["species"])
				_enemy_level = int(event["level"])
				set_hp(int(event["hp"]), int(event["max_hp"]), _player_hp, _player_max_hp)
			else:
				_player = int(event["species"])
				_player_level = int(event["level"])
				set_hp(_enemy_hp, _enemy_max_hp, int(event["hp"]), int(event["max_hp"]))
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
			return "Go! %s!" % _name_of(int(event["species"]))
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
	if not is_ready():
		return
	var button: int = Gen2Button.pressed_in(event)
	if button != Gen2Button.NONE:
		if _handle_button(button):
			accept_event()
		return
	if event.is_pressed() and _handle_debug_key(event):
		accept_event()


func _handle_button(button: int) -> bool:
	if _forget_stage != &"":
		_answer_forget(button)
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

	## B opens ball selection and closes it again. The source reaches a ball
	## through the PACK, which this screen has no menu for yet; until it does,
	## the one button with nothing else to do here carries it.
	if button == Gen2Button.B and _is_wild_battle():
		begin_capture()
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
			cycle_battle_renderer()
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
		_renderer.queue_free()
	_renderer = Gen2ModHost.instance().create_battle_renderer()
	if Gen2ModHost.renderer_uses_hardware_viewport(_renderer):
		_screen.display(_renderer)
	else:
		_screen.display_native(_renderer)
		_screen.native_size_changed.connect(_on_native_size_changed)
		_on_native_size_changed(_screen.native_size())
	_renderer_ready = bool(_renderer.set_battle_data(_data))
	_push_world_context()
	_push_view()


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


## Switches the live view to another registered renderer without disturbing the
## battle behind it.
func select_battle_renderer(id: StringName) -> Dictionary:
	var result: Dictionary = Gen2ModHost.instance().select_battle_renderer(id)
	if not bool(result.get("ok", false)):
		show_message("Renderer unavailable: %s" % String(result.get("reason", "unknown")))
		return result
	_build_renderer()
	show_message("Renderer: %s" % Gen2ModHost.instance().battle_renderer_label(id))
	return result


## Selects the registered renderer after the current one, wrapping.
func cycle_battle_renderer() -> Dictionary:
	var host: Gen2ModHost = Gen2ModHost.instance()
	var ids: Array = host.battle_renderer_ids()
	if ids.size() < 2:
		show_message("No other renderer is registered")
		return {"ok": false, "reason": &"single_renderer"}
	var at: int = ids.find(host.selected_battle_renderer())
	return select_battle_renderer(ids[posmod(at + 1, ids.size())])


## Pushes the current display values to the renderer. Plain values only, never
## the battle engine: a turn resolves at once and is then shown an event at a
## time, so what is drawn deliberately lags where the battle has got to.
func _push_view() -> void:
	if not _renderer_ready:
		return
	_renderer.set_view({
		"enemy_species": _enemy, "player_species": _player,
		"enemy_name": _name_of(_enemy), "player_name": _name_of(_player),
		"enemy_level": _enemy_level, "player_level": _player_level,
		## The bars draw whatever the animation is on rather than the committed
		## HP, which is what makes them drain. Everything else, including
		## [method battle_snapshot], keeps reading the committed value.
		"enemy_hp": _drawn_hp(Gen2Battle.ENEMY), "enemy_max_hp": _enemy_max_hp,
		"player_hp": _drawn_hp(Gen2Battle.PLAYER), "player_max_hp": _player_max_hp,
		"exp_pixels": _drawn_exp(),
		## The background's own scroll, a value per scanline, empty when it is
		## sitting still. `PlaceGraphic` puts the player's back pic up only after
		## the slide has returned, so during it there is nothing to draw there.
		"raster_scx": _raster_offsets(),
		"raster_scy": _raster_rows(),
		"player_pic_visible": _intro == null,
		## `wTilemap` and the video state an animation writes over it.
		"bg_map": _bg_map,
		"bg_palette_maps": _background_maps(&"bg"),
		"ob_palette_maps": _background_maps(&"ob"),
		"anim_sprites": _anim.sprites() if _anim != null else [],
		"anim_tiles": _anim.tiles() if _anim != null else [],
		"hud_visible": not _anim_hud_hidden,
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
	show_message("Wild %s appeared!" % _name_of(_enemy))
