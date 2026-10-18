class_name StageDef
extends Resource
## One stage. Weights sum to 1. Beats fire in array order.

@export var id: String = ""
@export var display_name: String = ""
@export var surface: String = ""
@export var pace_weight: float = 0.0
@export var grip_weight: float = 0.0
@export var jump_weight: float = 0.0
@export var reliability_weight: float = 0.0
@export var focus_weight: float = 0.0
@export var base_time_sec: int = 0
@export var beats: Array[StageBeat] = []


func weight(stat_name: String) -> float:
	match stat_name:
		"pace":
			return pace_weight
		"grip":
			return grip_weight
		"jump":
			return jump_weight
		"reliability":
			return reliability_weight
		"focus":
			return focus_weight
		_:
			return 0.0


func weight_sum() -> float:
	return pace_weight + grip_weight + jump_weight + reliability_weight + focus_weight
