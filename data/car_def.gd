class_name CarDef
extends Resource
## One car row from the starter roster. Entries copy these numbers; the resource stays put.

@export var id: String = ""
@export var display_name: String = ""
## Reputation required to draft this car. Starters stay at 0.
@export var unlock_reputation: int = 0
@export var cost: int = 0
@export var pace: int = 0
@export var grip: int = 0
@export var jump: int = 0
@export var reliability: int = 0
@export var focus: int = 0
## Side-view card for the draft and the standings. Presentation only.
@export var portrait: Texture2D
## Side view on the road during the reveal, with no card. Presentation only.
@export var stage_sprite: Texture2D


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
