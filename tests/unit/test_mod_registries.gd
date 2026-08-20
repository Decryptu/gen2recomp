extends GutTest

## The three registries a mod reaches that are not a renderer: move effects,
## effect commands and the read-only event channel. Each is checked for what it
## lets a mod add and for what it refuses to let one take over.

const Fixture := preload("res://tests/unit/battle_fixture.gd")
const MOD: StringName = &"testmod"
## An effect byte no cartridge move carries, so registering it cannot change a
## move already in the table.
const NEW_EFFECT: int = 0xF0

var _directory: String = ""
var _data: GameData = null
var _ran: Array = []
var _seen: Array = []


func before_each() -> void:
	Gen2ModHost.reset()
	_directory = RomCache.directory_for(&"registrytest", "0123456789abcdef")
	_data = Fixture.build(_directory)
	_ran = []
	_seen = []


func after_each() -> void:
	RomCache.clear(_directory)
	Gen2ModHost.reset()


func _note(turn: Gen2Turn) -> void:
	_ran.append(turn.move_number)


func _watch(event: Dictionary) -> void:
	_seen.append(event)


func test_a_registered_command_runs_inside_a_real_move_sequence() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(host.register_effect_command(MOD, &"marker", _note).get("ok", false)))
	assert_true(bool(host.register_move_effect(MOD, NEW_EFFECT, [
		Gen2EffectCommands.USED_MOVE_TEXT,
		Gen2EffectCommands.DO_TURN,
		&"marker",
		Gen2EffectCommands.END_MOVE,
	]).get("ok", false)))

	assert_eq(Gen2MoveEffect.sequence_for(NEW_EFFECT).size(), 4)
	assert_true(Gen2MoveEffect.is_written(NEW_EFFECT))

	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		RandomNumberGenerator.new()
	)
	var turn: Gen2Turn = Gen2Turn.create(
		battle, Gen2Battle.PLAYER, 0, Fixture.TACKLE, _data.move(Fixture.TACKLE), []
	)
	for command: StringName in Gen2MoveEffect.sequence_for(NEW_EFFECT):
		Gen2EffectCommands.run(command, turn)
	assert_eq(_ran, [Fixture.TACKLE], "the registered step ran with the turn")


func test_a_registration_cannot_shadow_a_step_every_move_depends_on() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_eq(
		StringName(host.register_effect_command(
			MOD, Gen2EffectCommands.APPLY_DAMAGE, _note
		)["reason"]),
		&"reserved_effect_command"
	)
	# And the stat commands are engine steps too, not just the shared ones.
	assert_eq(
		StringName(host.register_effect_command(
			MOD, Gen2EffectCommands.ATTACK_UP, _note
		)["reason"]),
		&"reserved_effect_command"
	)


func test_an_effect_naming_a_step_nobody_wrote_is_refused_at_registration() -> void:
	# Refused here, where the mod's id is in hand, rather than pushing an error
	# in the middle of a turn.
	var result: Dictionary = Gen2ModHost.instance().register_move_effect(MOD, NEW_EFFECT, [
		Gen2EffectCommands.USED_MOVE_TEXT, &"nosuchstep",
	])
	assert_eq(StringName(result["reason"]), &"unknown_effect_command")
	assert_false(Gen2MoveEffect.is_written(NEW_EFFECT))


func test_effects_whose_command_reads_the_byte_back_are_not_replaceable() -> void:
	for effect: int in Gen2MoveEffect.RESERVED_EFFECTS:
		assert_eq(
			StringName(Gen2ModHost.instance().register_move_effect(
				MOD, effect, [Gen2EffectCommands.END_MOVE]
			)["reason"]),
			&"reserved_effect", "effect %d" % effect
		)


func test_a_registered_effect_replaces_the_cartridge_list_and_reset_restores_it() -> void:
	var before: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.SLEEP)
	assert_true(bool(Gen2ModHost.instance().register_move_effect(
		MOD, Gen2MoveEffect.SLEEP, [Gen2EffectCommands.END_MOVE]
	).get("ok", false)))
	assert_eq(Gen2MoveEffect.sequence_for(Gen2MoveEffect.SLEEP).size(), 1)
	Gen2ModHost.reset()
	assert_eq(Gen2MoveEffect.sequence_for(Gen2MoveEffect.SLEEP), before)


func test_two_mods_claiming_one_effect_is_refused() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.register_move_effect(MOD, NEW_EFFECT, [Gen2EffectCommands.END_MOVE])
	assert_eq(
		StringName(host.register_move_effect(
			&"othermod", NEW_EFFECT, [Gen2EffectCommands.END_MOVE]
		)["reason"]),
		&"duplicate_move_effect"
	)


func test_a_subscriber_sees_published_events_and_cannot_write_through_them() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(host.subscribe(Gen2ModHost.CHANNEL_BATTLE, MOD, _watch).get("ok", false)))
	var event: Dictionary = {"type": Gen2Battle.HIT, "damage": 12}
	Gen2ModHost.publish(Gen2ModHost.CHANNEL_BATTLE, event)
	assert_eq(_seen.size(), 1)
	assert_eq(int(_seen[0]["damage"]), 12)
	# The subscriber holds a copy, so writing to it reaches nothing.
	(_seen[0] as Dictionary)["damage"] = 999
	assert_eq(int(event["damage"]), 12)
	# And the other channel is a different conversation.
	Gen2ModHost.publish(Gen2ModHost.CHANNEL_WORLD, {"status": &"waiting"})
	assert_eq(_seen.size(), 1)


## Mutation is the other half of the event channel: the turn or the script has
## already committed, so what reaches the screen is presentation and may be
## rewritten, while the key the screen dispatches on may not.
func test_an_event_mutator_rewrites_presentation_and_not_the_routing_key() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(host.register_event_mutator(
		Gen2ModHost.CHANNEL_BATTLE, MOD,
		func(event: Dictionary) -> Dictionary:
			event["damage"] = 1
			return event
	).get("ok", false)))
	assert_true(bool(host.subscribe(Gen2ModHost.CHANNEL_BATTLE, MOD, _watch).get("ok", false)))

	var effective: Dictionary = Gen2ModHost.publish(
		Gen2ModHost.CHANNEL_BATTLE, {"type": Gen2Battle.HIT, "damage": 12}
	)
	assert_eq(int(effective["damage"]), 1, "the screen shows what the mutator returned")
	assert_eq(int(_seen[0]["damage"]), 1, "and a watcher sees the same event")

	host.unregister_event_mutator(Gen2ModHost.CHANNEL_BATTLE, MOD)
	assert_eq(
		int(Gen2ModHost.publish(
			Gen2ModHost.CHANNEL_BATTLE, {"type": Gen2Battle.HIT, "damage": 12}
		)["damage"]),
		12
	)


func test_a_mutator_that_changes_the_key_or_answers_with_nothing_is_ignored() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.register_event_mutator(
		Gen2ModHost.CHANNEL_BATTLE, MOD,
		func(event: Dictionary) -> Dictionary:
			event["type"] = Gen2Battle.ANIMATION
			return event
	)
	var event: Dictionary = {"type": Gen2Battle.HIT, "damage": 12}
	assert_eq(
		StringName(Gen2ModHost.publish(Gen2ModHost.CHANNEL_BATTLE, event)["type"]),
		StringName(Gen2Battle.HIT),
		"a rewrite cannot turn one screen operation into another"
	)

	host.unregister_event_mutator(Gen2ModHost.CHANNEL_BATTLE, MOD)
	host.register_event_mutator(
		Gen2ModHost.CHANNEL_WORLD, MOD, func(_event: Dictionary) -> Variant: return null
	)
	assert_eq(
		Gen2ModHost.publish(Gen2ModHost.CHANNEL_WORLD, {"status": &"waiting"}),
		{"status": &"waiting"},
		"and a mutator answering with nothing leaves the event alone"
	)


## Exclusive, because composing two rewrites in load order would make the picture
## depend on which mod happened to load first.
func test_only_one_mod_may_mutate_a_channel() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(host.register_event_mutator(
		Gen2ModHost.CHANNEL_WORLD, MOD, _watch
	).get("ok", false)))
	var second: Dictionary = host.register_event_mutator(
		Gen2ModHost.CHANNEL_WORLD, &"othermod", _watch
	)
	assert_eq(StringName(second["reason"]), &"duplicate_event_mutator")
	assert_string_contains(String(second["detail"]), "othermod")
	assert_eq(
		StringName(host.register_event_mutator(&"nowhere", MOD, _watch)["reason"]),
		&"unknown_channel"
	)
	assert_eq(
		StringName(host.register_event_mutator(
			Gen2ModHost.CHANNEL_BATTLE, MOD, Callable()
		)["reason"]),
		&"invalid_event_mutator_handler"
	)
	# Another mod's id cannot release it either.
	host.unregister_event_mutator(Gen2ModHost.CHANNEL_WORLD, &"othermod")
	assert_eq(
		StringName(host.register_event_mutator(
			Gen2ModHost.CHANNEL_WORLD, &"othermod", _watch
		)["reason"]),
		&"duplicate_event_mutator"
	)


func test_unsubscribing_and_unknown_channels() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_eq(
		StringName(host.subscribe(&"nowhere", MOD, _watch)["reason"]), &"unknown_channel"
	)
	assert_eq(
		StringName(host.subscribe(
			Gen2ModHost.CHANNEL_WORLD, MOD, Callable()
		)["reason"]),
		&"invalid_subscriber_handler"
	)
	host.subscribe(Gen2ModHost.CHANNEL_WORLD, MOD, _watch)
	assert_eq(
		StringName(host.subscribe(Gen2ModHost.CHANNEL_WORLD, MOD, _watch)["reason"]),
		&"duplicate_subscriber"
	)
	host.unsubscribe(Gen2ModHost.CHANNEL_WORLD, MOD)
	Gen2ModHost.publish(Gen2ModHost.CHANNEL_WORLD, {"status": &"waiting"})
	assert_eq(_seen.size(), 0)


func test_publishing_with_no_host_built_does_nothing() -> void:
	# The publish call sits on the path every battle event takes, so a game with
	# no mods must not build a host to publish to nobody.
	Gen2ModHost.reset()
	Gen2ModHost.publish(Gen2ModHost.CHANNEL_BATTLE, {"type": Gen2Battle.HIT})
	assert_eq(_seen.size(), 0)


func test_two_mods_claiming_one_renderer_id_is_named_rather_than_silently_won() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_eq(
		StringName(host.register_world_renderer(
			Gen2ModHost.BUILT_IN_RENDERER, Gen2WorldRenderer
		)["reason"]),
		&"duplicate_renderer"
	)
	assert_eq(
		StringName(host.register_battle_renderer(
			Gen2ModHost.BUILT_IN_RENDERER, Gen2BattleRenderer
		)["reason"]),
		&"duplicate_renderer"
	)


func test_the_shipped_example_mod_registers_everything_it_documents() -> void:
	# mods/examples/new_content/ is the reference a mod author copies, so it is
	# run here rather than only read: a registration it gets wrong would be
	# refused silently and the example would teach the refusal.
	var manifest: Dictionary = Gen2ModManifest.read("res://mods/examples/new_content")
	assert_true(bool(manifest.get("ok", false)), "example manifest reads")
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(host.load_mod(manifest["manifest"]).get("ok", false)))

	var overlay: Gen2ContentOverlay = host.content_overlay()
	assert_false(overlay.is_empty())
	assert_eq(
		overlay.defined_numbers(Gen2ContentOverlay.KIND_SPECIES),
		[Gen2ContentOverlay.FIRST_MOD_NUMBER] as Array[int]
	)
	# Its move names an effect it registered itself, so the effect resolves to
	# the list rather than falling back to an ordinary attack.
	var move: Dictionary = overlay.resolve(
		Gen2ContentOverlay.KIND_MOVE, Gen2ContentOverlay.FIRST_MOD_NUMBER, {}
	)
	assert_true(Gen2MoveEffect.is_written(int(move["effect"])))
	assert_true(Gen2MoveEffect.sequence_for(int(move["effect"])).has(
		Gen2EffectCommands.RECOIL
	))
	# 8: its stats page is registered and builds off the snapshot's own DV word.
	var pages: Array = host.stats_pages()
	assert_eq(pages.size(), 1)
	var placements: Array = (pages[0]["build"] as Callable).call(
		{"dvs": Gen2Stats.pack_dvs(15, 9, 7, 12), "stat_exp": {"attack": 25600}}
	)
	assert_true(placements.has({"text": "15", "at": Vector2i(8, 11)}), "the ATTACK DV")
	assert_true(placements.has({"text": "25600", "at": Vector2i(14, 11)}), "its stat exp")

	# And its patch reaches a cartridge row without replacing the rest of it.
	var pikachu: Dictionary = overlay.resolve(
		Gen2ContentOverlay.KIND_SPECIES, 25,
		{"name": "PIKACHU", "stats": {"hp": 35, "speed": 90}}
	)
	assert_eq(int(pikachu["stats"]["speed"]), 110)
	assert_eq(int(pikachu["stats"]["hp"]), 35)
	assert_eq(String(pikachu["name"]), "PIKACHU")

	# The example is the documentation for the whole contract, so it declares the
	# current one and demonstrates each surface a version added. A host bump with
	# the example left behind fails here rather than in a mod author's reading.
	for id: String in ["new_content", "voxel_preview"]:
		var declared: Dictionary = Gen2ModManifest.read("res://mods/examples/%s" % id)
		assert_true(bool(declared.get("ok", false)), id)
		assert_eq(
			(declared["manifest"] as Gen2ModManifest).api_version,
			Gen2ModManifest.API_VERSION,
			id
		)
	# 4: a type of its own, and a chart exception naming it.
	assert_eq(
		overlay.defined_numbers(Gen2ContentOverlay.KIND_TYPE),
		[Gen2ContentOverlay.FIRST_MOD_NUMBER] as Array[int]
	)
	assert_eq(int(overlay.resolve(
		Gen2ContentOverlay.KIND_MATCHUP,
		Gen2ContentOverlay.matchup_number(
			Gen2ContentOverlay.FIRST_MOD_NUMBER, RomLayout.TYPE_STEEL
		),
		{"multiplier": RomLayout.MATCHUP_EFFECTIVE}
	).get("multiplier", 0)), RomLayout.MATCHUP_SUPER_EFFECTIVE)
	# 4: decoded art, which is exactly tiles * tiles * 64 indices or it is dropped.
	var voltling: Dictionary = overlay.resolve(
		Gen2ContentOverlay.KIND_SPECIES, Gen2ContentOverlay.FIRST_MOD_NUMBER, {}
	)
	var front: Dictionary = (voltling["pics"] as Dictionary)["front"]
	assert_eq((front["indices"] as PackedByteArray).size(), 7 * 7 * 64)
	# 3: an item in a mod pocket, and the mart shelf it is sold from.
	assert_eq(
		int(overlay.resolve(
			Gen2ContentOverlay.KIND_ITEM, Gen2ContentOverlay.FIRST_MOD_NUMBER, {}
		)["pocket"]),
		Gen2ModHost.FIRST_MOD_POCKET
	)
	var shelf: Array = host.mart_entries({"mart_id": 0, "variant": 0, "items": []})
	assert_eq(shelf.size(), 1)
	assert_eq(int((shelf[0] as Dictionary)["item"]), Gen2ContentOverlay.FIRST_MOD_NUMBER)
	assert_eq(int((shelf[0] as Dictionary)["price"]), 400)
	# 3: a named axis, whose two halves both registered rather than colliding
	# with the cartridge's eight.
	assert_eq(host.actions().size(), 2)
	# 2: a visible-encounter population.
	assert_eq(host.visible_encounter_ids().size(), 1)
	# 4: one presentation mutator, which may not change the routing key.
	var dressed: Dictionary = Gen2ModHost.publish(Gen2ModHost.CHANNEL_WORLD, {
		"status": &"waiting", "event": {"type": &"text", "text": "PIKACHU!"},
	})
	assert_eq(StringName(dressed["status"]), &"waiting")
	assert_eq(String((dressed["event"] as Dictionary)["text"]), "VOLTLING!")


func test_every_refusal_reason_the_mod_layer_produces_has_player_wording() -> void:
	# The launcher and the index dialog share one table now; a reason worded in
	# neither used to show as a raw StringName through whichever screen met it.
	for reason: StringName in [
		&"not_a_zip", &"unsafe_archive_entry", &"unsupported_api_version",
		&"unsupported_index_schema", &"already_installed", &"duplicate_renderer",
		&"duplicate_content", &"reserved_effect_command", &"missing_entry_script",
		&"duplicate_party_menu_entry", &"party_menu_entry_missing_callable",
		&"invalid_party_menu_entry", &"duplicate_stats_page",
		&"stats_page_missing_callable", &"stats_pages_full",
	]:
		var text: String = Gen2ModRefusal.text({"reason": reason, "detail": "x/y.zip"})
		assert_false(text.begins_with(String(reason)), "worded: %s" % reason)
		assert_false(text.is_empty())
	# An unworded reason still names something a search finds.
	assert_string_contains(Gen2ModRefusal.text({"reason": &"brand_new"}), "brand_new")


## `register_stats_page` refuses what it cannot draw, and refuses a sixth page:
## the indicator run is centred against the right arrow and one more block than
## [constant Gen2StatsScreenPage.MAX_PAGES] stands on the front pic.
func test_the_stats_screen_refuses_a_page_it_cannot_draw_or_indicate() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	var build := func(_page: Dictionary) -> Array: return []
	assert_eq(
		StringName(host.register_stats_page(&"", {"build": build})["reason"]),
		&"invalid_stats_page"
	)
	assert_eq(
		StringName(host.register_stats_page(MOD, {})["reason"]),
		&"stats_page_missing_callable"
	)
	assert_true(bool(host.register_stats_page(MOD, {"build": build})["ok"]))
	assert_eq(
		StringName(host.register_stats_page(MOD, {"build": build})["reason"]),
		&"duplicate_stats_page"
	)
	var room: int = Gen2StatsScreenPage.MAX_PAGES - Gen2StatsScreenPage.NUM_PAGES - 1
	for index: int in room:
		assert_true(bool(host.register_stats_page(
			StringName("filler%d" % index), {"build": build}
		)["ok"]))
	assert_eq(
		StringName(host.register_stats_page(&"toomany", {"build": build})["reason"]),
		&"stats_pages_full"
	)
	assert_eq(Gen2StatsScreenPage.page_count(), Gen2StatsScreenPage.MAX_PAGES)


## The eight steps the last row of the effects table added are engine steps like
## every other: a mod can name them in a list of its own and cannot take them over.
func test_the_last_rows_steps_are_engine_steps_a_mod_can_name() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	var steps: Array = [
		Gen2EffectCommands.TELEPORT, Gen2EffectCommands.FORESIGHT,
		Gen2EffectCommands.LOCK_ON, Gen2EffectCommands.SPITE,
		Gen2EffectCommands.PAIN_SPLIT, Gen2EffectCommands.THIEF,
		Gen2EffectCommands.PURSUIT, Gen2EffectCommands.BEAT_UP,
	]
	for step: StringName in steps:
		assert_true(Gen2EffectCommands.is_engine_command(step), String(step))
		assert_eq(
			StringName(host.register_effect_command(MOD, step, _note)["reason"]),
			&"reserved_effect_command", String(step)
		)

	var result: Dictionary = host.register_move_effect(MOD, NEW_EFFECT, [
		Gen2EffectCommands.USED_MOVE_TEXT, Gen2EffectCommands.DO_TURN,
		Gen2EffectCommands.CHECK_HIT, Gen2EffectCommands.LOCK_ON,
		Gen2EffectCommands.END_MOVE,
	])
	assert_true(bool(result["ok"]), JSON.stringify(result))
	assert_true(Gen2MoveEffect.is_written(NEW_EFFECT))


## None of the eight reads its own effect byte back, so none of them joins the
## list a mod cannot rewrite.
func test_the_last_rows_effects_stay_replaceable() -> void:
	for effect: int in [
		Gen2MoveEffect.PAIN_SPLIT, Gen2MoveEffect.LOCK_ON, Gen2MoveEffect.SPITE,
		Gen2MoveEffect.THIEF, Gen2MoveEffect.FORESIGHT, Gen2MoveEffect.PURSUIT,
		Gen2MoveEffect.TELEPORT, Gen2MoveEffect.BEAT_UP,
	]:
		assert_true(bool(Gen2ModHost.instance().register_move_effect(
			MOD, effect, [Gen2EffectCommands.END_MOVE]
		)["ok"]), "effect %d" % effect)
