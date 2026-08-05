class_name Gen2BattleScreen
extends Control

signal battle_finished(result: Dictionary)

## The battle screen: two Pokémon, two status panels and a text box, at the
## positions the hardware puts them.
##
## This is the first screen that is not a development view. Everything on it
## already existed a layer down (a pic from an atlas, a panel from the HUD
## sheets, a box from the font and a border), and what this adds is where each
## of them goes: the enemy's pic in the top right, the player's back pic below
## and to the left of it, a panel each, and the standard box along the bottom.
##
## It draws what it is given and decides nothing. A [Gen2Battle] behind it works
## out the turn and answers with a list of events; this shows them one at a time,
## taking every number it draws out of the event rather than asking the engine
## again. That is why the setters still take plain values: the engine is one
## caller of them and not the only possible one.
##
## The panels are composed into one screen-sized index buffer and drawn over the
## pics with index 0 transparent, because a panel is a shape on a white field
## rather than a rectangle: the games draw them into the background layer, where
## nothing overlaps, and the pics have to show through everything that is not ink.

## Where the two pics sit, in tiles.
const ENEMY_PIC: Vector2i = Vector2i(12, 0)
const PLAYER_PIC: Vector2i = Vector2i(2, 6)

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

const TILE: int = Gen2Font.TILE

## The white the hardware fills the battle background with.
const BACKGROUND: Color = Color.WHITE

var _data: GameData = null
var _hud: Gen2BattleHud = null

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
var _world_battle_request: Dictionary = {}
var _world_battle_completion_sent: bool = false
var _world_battle_terminal_text_shown: bool = false
var _world_battle_recovery_shown: bool = false
var _world_battle_recovery: Dictionary = {}

## The trainer class behind the enemy's own moves, or zero for
## [method show_matchup]'s invented pairing, which has no class and so no AI
## flags of its own to read: it falls back to [method _random_slot], same as
## before this existed. Reset by both, set only by [method show_trainer].
var _enemy_trainer_class: int = 0
var _enemy_turns_taken: int = 0
var _player_turns_taken: int = 0

var _enemy: int = 1
var _player: int = 1
var _enemy_level: int = 5
var _player_level: int = 5
var _enemy_hp: int = 0
var _enemy_max_hp: int = 0
var _player_hp: int = 0
var _player_max_hp: int = 0
var _exp: float = 0.0

var _enemy_pic: TextureRect = null
var _player_pic: TextureRect = null
var _panels: TextureRect = null
var _enemy_bar: TextureRect = null
var _player_bar: TextureRect = null
var _exp_bar: TextureRect = null
var _box: Gen2TextBox = null

@onready var _screen: Gen2Screen = %Screen


func _ready() -> void:
	_data = GameRuntime.selected_data() if GameRuntime.has_selected_game() else null
	if _data == null:
		_data = GameData.open_any()
	_hud = Gen2BattleHud.from_data(_data)
	if _hud == null:
		return

	var field := ColorRect.new()
	field.color = BACKGROUND
	field.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_screen.display(field)

	_enemy_pic = _new_layer()
	_player_pic = _new_layer()
	_panels = _new_layer()
	_enemy_bar = _new_layer()
	_player_bar = _new_layer()
	_exp_bar = _new_layer()

	_box = Gen2TextBox.new()
	_box.font = _hud.font
	_screen.display(_box)
	_box.place_at_bottom()

	var world_meta: Variant = get_meta("world_battle_request", {})
	if world_meta is Dictionary and not (world_meta as Dictionary).is_empty():
		call_deferred("_start_world_battle_from_meta", world_meta)
	else:
		var saved: Gen2SaveData = GameRuntime.selected_save()
		if saved != null and show_saved_party(saved):
			show_message("Save slot %d loaded. Wild %s appeared!" % [_save_slot + 1, _name_of(_enemy)])
		else:
			show_matchup(DEFAULT_ENEMY, DEFAULT_PLAYER, DEFAULT_LEVEL, DEFAULT_LEVEL)
			_announce()


## True once the cache had everything the screen draws with.
func is_ready() -> bool:
	return _hud != null


## Puts two Pokémon on the screen at a level each, both at full health, and
## starts a battle between them.
func show_matchup(enemy: int, player: int, enemy_level: int = 5, player_level: int = 5) -> void:
	_world_battle_active = false
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
	_enemy_turns_taken = 0
	_player_turns_taken = 0
	_battle = Gen2Battle.create_parties(
		_data, _party_from(_player, _player_level), _party_from(_enemy, _enemy_level), _rng
	)
	if _battle == null:
		return

	set_hp(
		_battle.enemy.hp, _battle.enemy.max_hp(),
		_battle.player.hp, _battle.player.max_hp()
	)
	_refresh_exp_bar()


## Puts the player against one of a trainer class's own trainers, built from the
## cartridge's own party rather than invented. The player's side is the
## fallback development party when this method is called directly.
func show_trainer(
	trainer_class: int, index: int = 0, player_species: int = DEFAULT_PLAYER,
	player_level: int = DEFAULT_LEVEL
) -> void:
	_world_battle_active = false
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
	_enemy_turns_taken = 0
	_player_turns_taken = 0
	_battle = Gen2Battle.create_parties(
		_data, _party_from(_player, _player_level), enemy_party, _rng, true
	)
	if _battle == null:
		return

	set_hp(
		_battle.enemy.hp, _battle.enemy.max_hp(),
		_battle.player.hp, _battle.player.max_hp()
	)
	_refresh_exp_bar()

	var trainer: Dictionary = _data.trainer_party(trainer_class, index)
	show_message("%s %s wants to fight!" % [
		_data.trainer_name(trainer_class), String(trainer.get("name", "")),
	])


## Starts the development battle with the player party from a validated save
## slot. The enemy remains the existing wild demonstration, while the player
## side now carries persistent levels, HP, PP, status, DVs and stat experience.
func show_saved_party(save: Gen2SaveData) -> bool:
	_world_battle_active = false
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
	_enemy_turns_taken = 0
	_player_turns_taken = 0
	_player = player_lead.species
	_player_level = player_lead.level
	_enemy = enemy_lead.species
	_enemy_level = enemy_lead.level
	_battle = Gen2Battle.create_parties(_data, player_party, enemy_party, _rng)
	if _battle == null:
		_save_slot = -1
		return false
	set_hp(
		_battle.enemy.hp, _battle.enemy.max_hp(),
		_battle.player.hp, _battle.player.max_hp()
	)
	_refresh_exp_bar()
	return true


## Starts a battle requested by the scene-free overworld runtime. The caller
## keeps the world API alive while this screen owns the battle presentation.
func start_world_battle(request: Dictionary, save: Gen2SaveData = null) -> bool:
	if _data == null or _hud == null:
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
	_world_battle_completion_sent = false
	_world_battle_terminal_text_shown = false
	_world_battle_recovery_shown = false
	_world_battle_recovery = {}
	_pending = []
	_save_slot = save.slot if save != null else -1
	_save_written = false
	_source_save = save
	_enemy_trainer_class = int(prepared.get("trainer_class", 0))
	_enemy_turns_taken = 0
	_player_turns_taken = 0
	_battle = prepared["battle"]
	var player_party_ready: Gen2Party = prepared["player_party"]
	var enemy_party_ready: Gen2Party = prepared["enemy_party"]
	_player = player_party_ready.active_mon().species
	_player_level = player_party_ready.active_mon().level
	_enemy = enemy_party_ready.active_mon().species
	_enemy_level = enemy_party_ready.active_mon().level
	set_hp(
		_battle.enemy.hp, _battle.enemy.max_hp(),
		_battle.player.hp, _battle.player.max_hp()
	)
	_refresh_exp_bar()

	if bool(prepared.get("trainer_battle", false)):
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
func set_hp(enemy: int, enemy_max: int, player: int, player_max: int) -> void:
	_enemy_hp = enemy
	_enemy_max_hp = enemy_max
	_player_hp = player
	_player_max_hp = player_max
	_refresh()


## How full the exp bar is, from nothing to a level's worth.
func set_exp(fraction: float) -> void:
	_exp = clampf(fraction, 0.0, 1.0)
	_refresh()


## Where [member _battle]'s own player Pokémon sits between its current level's
## own threshold and the next one's, on its own growth curve. Called whenever a
## battle starts and whenever [constant Gen2Battle.EXP_GAINED] or
## [constant Gen2Battle.GREW_LEVEL] says the number behind it moved, rather
## than read once and left to go stale.
func _refresh_exp_bar() -> void:
	if _battle == null or _battle.player == null:
		set_exp(0.0)
		return

	var mon: Gen2BattleMon = _battle.player
	var rate: int = mon.growth_rate()
	var floor_exp: int = Gen2Experience.total_exp_at(rate, mon.level)
	var span: int = Gen2Experience.total_exp_at(rate, mon.level + 1) - floor_exp
	set_exp(float(mon.exp - floor_exp) / float(span) if span > 0 else 1.0)


func show_message(text: String) -> void:
	if _box != null:
		_box.show_text(text)


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
## The player still picks at random from what it knows: a menu does not exist
## yet. The enemy does too, unless it is one of the cartridge's own trainers
## ([method show_trainer] rather than [method show_matchup]), in which case
## [Gen2BattleAI] scores its choice the way that trainer class's own AI flags
## say to. Random rather than the first slot because a Pokémon that only ever
## used its first move would never show what the other three do.
func take_turn() -> void:
	if _battle == null or _battle.is_over() or not _pending.is_empty():
		return
	_pending = _battle.take_turn(_random_slot(Gen2Battle.PLAYER), _enemy_slot())
	_player_turns_taken += 1
	_enemy_turns_taken += 1
	_auto_decline_move_learns()
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
		_enemy_turns_taken, _player_turns_taken
	)


## Swaps the player's Pokémon for the next one that is standing, as a turn.
##
## The enemy attacks while it happens, because a switch is not free: this is the
## whole point of the ordering rule, and it is worth being able to look at.
func switch_player() -> void:
	if _battle == null or _battle.is_over() or not _pending.is_empty():
		return
	var next: int = _next_healthy(Gen2Battle.PLAYER)
	if next < 0:
		return
	_pending = _battle.take_actions(Gen2Battle.switch_to(next), Gen2Battle.use_move(0))
	_auto_decline_move_learns()
	_show_next_event()


## No menu exists yet to ask which move to forget, the same scaffolding this
## screen already has for which move to use ([method _random_slot]): a pending
## offer is declined automatically instead, so a battle nobody is driving from
## a real menu does not simply stop. [Gen2Battle] still exposes the real
## question through [method Gen2Battle.must_learn_move] for whatever asks it
## properly later.
func _auto_decline_move_learns() -> void:
	for side: int in [Gen2Battle.PLAYER, Gen2Battle.ENEMY]:
		while _battle.must_learn_move(side):
			_pending.append_array(_battle.decline_move(side))


## What a button press does. Finishes the current message if it is still
## revealing, then moves on to the next event, sends out whoever is owed, and
## starts a turn when there is nothing left to say.
func advance() -> void:
	if _box == null:
		return
	if _box.advance():
		return
	if not _pending.is_empty():
		_show_next_event()
		return
	if _replace_the_fallen():
		return
	if _battle != null and _battle.is_over():
		if _world_battle_active:
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
		Gen2WorldBattleAdapter.OUTCOME_WON
		if winner == Gen2Battle.PLAYER
		else Gen2WorldBattleAdapter.OUTCOME_LOST
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
## Every number drawn comes out of the event rather than out of the Pokémon,
## because the turn has already finished resolving by the time the first event is
## shown. Reading the Pokémon here would draw the end of the turn during the
## middle of it.
func _show_next_event() -> void:
	while not _pending.is_empty():
		var event: Dictionary = _pending.pop_front()
		_apply_event(event)
		var text: String = _describe(event)
		if not text.is_empty():
			show_message(text)
			return


func _apply_event(event: Dictionary) -> void:
	match event["type"]:
		Gen2Battle.HIT, Gen2Battle.RECOIL, Gen2Battle.DRAINED, Gen2Battle.OHKO:
			var target: int = int(event.get("target", event["side"]))
			if target == Gen2Battle.ENEMY:
				set_hp(int(event["hp"]), int(event["max_hp"]), _player_hp, _player_max_hp)
			else:
				set_hp(_enemy_hp, _enemy_max_hp, int(event["hp"]), int(event["max_hp"]))
		Gen2Battle.HURT_BY_STATUS, Gen2Battle.HURT_ITSELF:
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
				_enemy = int(event["species"])
				_enemy_level = int(event["level"])
				set_hp(int(event["hp"]), int(event["max_hp"]), _player_hp, _player_max_hp)
			else:
				_player = int(event["species"])
				_player_level = int(event["level"])
				set_hp(_enemy_hp, _enemy_max_hp, int(event["hp"]), int(event["max_hp"]))
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
			if int(event["index"]) == _battle.party(Gen2Battle.PLAYER).active:
				_player_level = int(event["new_level"])
				_refresh()
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
			return "%s thawed out!" % _battler_name(side)
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
			# The real games print a line of the move's own, which nothing here has
			# a source for yet; this is the one sentence every two-turn move shares.
			return "%s is charging up its power!" % _battler_name(side)
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
		Gen2Battle.MIST_SET:
			return "%s is shrouded in mist!" % _battler_name(side)
		Gen2Battle.FOCUS_ENERGY_SET:
			return "%s is getting pumped!" % _battler_name(side)
		Gen2Battle.MIST_PROTECTED:
			return "%s's stat drop was blocked by mist!" % _battler_name(int(event["target"]))
		Gen2Battle.OVER:
			# Both sides can go down in the same turn, through recoil or a burn,
			# and then there is nobody to declare.
			if event["winner"] == null:
				return "Both sides are out of Pokémon!"
			return "%s won!" % ("The enemy" if event["winner"] == Gen2Battle.ENEMY else "Player")
	return ""


## The sentence for a stat that actually moved. Ancientpower's [code]"all"[/code]
## reads as one sentence about the Pokémon rather than five about its stats,
## because that is the one thing the event says that a single stat's does not.
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


func _unhandled_key_input(event: InputEvent) -> void:
	if _hud == null or not event.is_pressed():
		return

	var key: InputEventKey = event as InputEventKey
	if key == null:
		return

	match key.keycode:
		KEY_RIGHT:
			next_enemy()
		KEY_LEFT:
			next_player()
		KEY_D:
			hurt_enemy()
		KEY_S:
			hurt_player()
		KEY_A:
			take_turn()
		KEY_W:
			switch_player()
		KEY_SPACE, KEY_ENTER:
			advance()
		_:
			return
	accept_event()


func _new_layer() -> TextureRect:
	var out := TextureRect.new()
	# Nearest, or the integer-scaled viewport is undone on the last hop.
	out.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_screen.display(out)
	return out


func _wrap_species(number: int) -> int:
	var count: int = _data.species_count() if _data != null else 0
	return wrapi(number, 1, maxi(count, 1) + 1) if count > 0 else 1


func _refresh() -> void:
	if _hud == null:
		return

	_draw_pic(_enemy_pic, _data.species_pic(_enemy), _data.palette(_enemy), ENEMY_PIC)
	_draw_pic(_player_pic, _data.species_pic(_player, true), _data.palette(_player), PLAYER_PIC)
	_draw_panels()


func _draw_pic(
	into: TextureRect, pic: Dictionary, palette: PackedColorArray, at: Vector2i
) -> void:
	if into == null or pic.is_empty():
		return

	var image: Image = Gen2PicImage.from_atlas(
		_data.atlas_indices(pic["atlas"]), _data.atlas(pic["atlas"]), pic, palette
	)
	into.texture = ImageTexture.create_from_image(image)
	into.size = image.get_size()
	into.position = Vector2(at.x * TILE, at.y * TILE)


## The panels, and then each bar over them in its own colour.
##
## The hardware gives every tile of the background its own palette, so a green
## HP bar sits in a panel of black text without either being a separate thing.
## Layering is how that is done here, one buffer per palette, which is why the
## bars are drawn apart from the panels that hold them.
func _draw_panels() -> void:
	var panels: PackedByteArray = _new_buffer()
	_hud.draw_enemy(panels, Gen2Screen.WIDTH, _name_of(_enemy), _enemy_level)
	_hud.draw_player(
		panels, Gen2Screen.WIDTH, _name_of(_player), _player_level, _player_hp, _player_max_hp
	)
	_show_layer(
		_panels, panels,
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	)

	var enemy: PackedByteArray = _new_buffer()
	_hud.draw_hp_bar(
		enemy, Gen2Screen.WIDTH, Gen2BattleHud.ENEMY_BAR, _enemy_hp, _enemy_max_hp
	)
	_show_layer(_enemy_bar, enemy, _hp_palette(_enemy_hp, _enemy_max_hp))

	var player: PackedByteArray = _new_buffer()
	_hud.draw_hp_bar(
		player, Gen2Screen.WIDTH, Gen2BattleHud.PLAYER_BAR, _player_hp, _player_max_hp
	)
	_show_layer(_player_bar, player, _hp_palette(_player_hp, _player_max_hp))

	var gained: PackedByteArray = _new_buffer()
	_hud.draw_exp_bar(gained, Gen2Screen.WIDTH, _exp)
	_show_layer(_exp_bar, gained, _data.bar_palette("exp"))


func _new_buffer() -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	return out


## Every layer above the pics is drawn with index 0 transparent: a panel is a
## shape on the background, not a rectangle over it.
func _show_layer(
	into: TextureRect, indices: PackedByteArray, palette: PackedColorArray
) -> void:
	var image: Image = Gen2PicImage.from_indices(
		indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT, palette, true
	)
	into.texture = ImageTexture.create_from_image(image)
	into.size = image.get_size()


## An HP bar is green, yellow or red by how much of it is lit rather than by the
## hit points behind it, which is the rule the games use.
func _hp_palette(hp: int, max_hp: int) -> PackedColorArray:
	var lit: int = Gen2BattleHud.bar_pixels(
		hp, max_hp, Gen2BattleHud.HP_BAR_TILES * Gen2BattleHud.TILE
	)
	return _data.bar_palette(GameData.hp_bar_palette_name(lit))


func _name_of(species: int) -> String:
	return String(_data.species(species).get("name", ""))


func _announce() -> void:
	show_message("Wild %s appeared!" % _name_of(_enemy))
