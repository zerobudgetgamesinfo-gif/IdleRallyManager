class_name DriverDef
extends Resource
## One driver row from the starter roster. Stats are the authored numbers, not a running entry.

@export var id: String = ""
@export var display_name: String = ""
## One line for the standings. Never read by the solver.
@export var temperament: String = ""
## Reputation required to draft this driver. Starters stay at 0.
@export var unlock_reputation: int = 0
@export var cost: int = 0
@export var pace: int = 0
@export var grip: int = 0
@export var jump: int = 0
@export var reliability: int = 0
@export var focus: int = 0
## Round animal portrait for the draft and the standings. Presentation only.
@export var portrait: Texture2D


func stat(stat_name: String) -> int:
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
