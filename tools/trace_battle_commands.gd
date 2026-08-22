extends SceneTree

## Every effect command one turn of a battle runs here, in the same shape
## `.claude/oracle/battle/trace_move_commands.py` prints off a real cartridge.
##
##   Godot --headless --path . -s res://tools/trace_battle_commands.gd -- \
##       <game> <out.txt> <player_move> <enemy_move>
##
## It fights until one side is down, so the artefact is a whole wild battle
## rather than one turn.
##
## `DoMove`'s read cycle is [method Gen2Battle.run_move_effect] and its artefact
## is [member Gen2Battle.command_trace], so the two files diff line for line and
## a step in the wrong place is the first difference rather than a wrong number
## on a screenshot. The opcode is the pin's own
## `macros/scripts/battle_commands.asm` index, which this side does not carry, so
## it is printed as `--` and the name is what a diff reads.

## The matchup `.claude/oracle/battle/states/in_wild` stands in: a level five
## Cyndaquil against the level two Rattata that state walked into. The DVs and
## the generator are this side's own, so the two fights are the same shape and
## not the same numbers.
const PLAYER_SPECIES: int = 155
const PLAYER_LEVEL: int = 5
const ENEMY_SPECIES: int = 19
const ENEMY_LEVEL: int = 2

## A runaway guard: no wild battle between two level-five Pokemon lasts anywhere
## near this, and a driver that never reaches a faint should say so.
const MAX_TURNS: int = 64


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error(
			"Usage: trace_battle_commands.gd -- <game> <out.txt> <player_move> <enemy_move>"
		)
		quit(1)
		return
	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var battle: Gen2Battle = Gen2Battle.create(
		data,
		Gen2BattleMon.create(data, PLAYER_SPECIES, PLAYER_LEVEL, [int(args[2])]),
		Gen2BattleMon.create(data, ENEMY_SPECIES, ENEMY_LEVEL, [int(args[3])]),
		rng
	)

	Gen2Battle.trace_commands = true
	battle.command_trace.clear()
	for _turn: int in MAX_TURNS:
		if battle.player.is_fainted() or battle.enemy.is_fainted():
			break
		battle.take_turn(0, 0)
	Gen2Battle.trace_commands = false

	var lines: PackedStringArray = ["# n opcode name"]
	for index: int in battle.command_trace.size():
		lines.append("%d -- %s" % [index, battle.command_trace[index]])
	FileAccess.open(args[1], FileAccess.WRITE).store_string("\n".join(lines) + "\n")
	print("wrote %d commands to %s" % [battle.command_trace.size(), args[1]])
	quit(0)
