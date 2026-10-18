class_name CardDef
extends Resource
## A service card. Deltas are integers. `safe` marks the default for one stat.

@export var id: String = ""
@export var label: String = ""
@export var pace: int = 0
@export var grip: int = 0
@export var jump: int = 0
@export var reliability: int = 0
@export var focus: int = 0
@export var safe: bool = false


func delta(stat_name: String) -> int:
	match stat_name:
		"pace":
			return pace
		"grip":
			return grip
		"jump":
			return jump
		"reliability":
			return reliability
		"focus":
			return focus
		_:
			return 0
