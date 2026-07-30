extends Node2D
## 入口：装配 GameState / Simulation / MapRenderer，处理全局输入（暂停/调速/重开）。

@export var use_grid_world: bool = false

@onready var simulation: Simulation = $Simulation
@onready var renderer: MapRenderer = $MapRenderer

var state: GameState
var _seed: int = 12345
var _speed_mult: float = 1.0


func _ready() -> void:
	_start_new_game(_seed)


func _start_new_game(world_seed: int) -> void:
	state = GameState.new()
	if use_grid_world:
		state.generate_grid_world(world_seed)
	else:
		state.generate_world(world_seed)
	simulation.setup(state)
	simulation.diplomacy_enabled = not use_grid_world
	simulation.set_speed_multiplier(_speed_mult)
	renderer.setup(state, simulation)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE:
			simulation.paused = not simulation.paused
		KEY_EQUAL, KEY_KP_ADD, KEY_BRACKETRIGHT:
			_speed_mult = clampf(_speed_mult * 2.0, Simulation.SPEED_MIN, Simulation.SPEED_MAX)
			simulation.set_speed_multiplier(_speed_mult)
		KEY_MINUS, KEY_KP_SUBTRACT, KEY_BRACKETLEFT:
			_speed_mult = clampf(_speed_mult * 0.5, Simulation.SPEED_MIN, Simulation.SPEED_MAX)
			simulation.set_speed_multiplier(_speed_mult)
		KEY_R:
			_seed = randi()
			_start_new_game(_seed)
