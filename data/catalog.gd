class_name Catalog
extends Resource
## Starter roster, stages, cards, stage order, and the seven AI pairs.
## Lookups are by id. Saves store those ids, not resource paths.

@export var drivers: Array[DriverDef] = []
@export var cars: Array[CarDef] = []
@export var stages: Array[StageDef] = []
@export var cards: Array[CardDef] = []
@export var stage_order: PackedStringArray = PackedStringArray()
@export var ai_pairs: Array[AiPair] = []

var _drivers: Dictionary = {}
var _cars: Dictionary = {}
var _stages: Dictionary = {}
var _cards: Dictionary = {}
var _driver_count := -1
var _car_count := -1
var _stage_count := -1
var _card_count := -1


func driver(id: String) -> DriverDef:
	_index()
	return _drivers.get(id) as DriverDef


func car(id: String) -> CarDef:
	_index()
	return _cars.get(id) as CarDef


func stage(id: String) -> StageDef:
	_index()
	return _stages.get(id) as StageDef


func card(id: String) -> CardDef:
	_index()
	return _cards.get(id) as CardDef


func stage_at(index: int) -> StageDef:
	if index < 0 or index >= stage_order.size():
		return null
	return stage(stage_order[index])


func stages_in_order() -> Array[StageDef]:
	var ordered: Array[StageDef] = []
	for stage_id in stage_order:
		var found := stage(stage_id)
		if found != null:
			ordered.append(found)
	return ordered


func _index() -> void:
	if (
		_driver_count == drivers.size()
		and _car_count == cars.size()
		and _stage_count == stages.size()
		and _card_count == cards.size()
	):
		return
	_drivers.clear()
	_cars.clear()
	_stages.clear()
	_cards.clear()
	_driver_count = drivers.size()
	_car_count = cars.size()
	_stage_count = stages.size()
	_card_count = cards.size()
	for item in drivers:
		if item != null and item.id != "":
			_drivers[item.id] = item
	for item in cars:
		if item != null and item.id != "":
			_cars[item.id] = item
	for item in stages:
		if item != null and item.id != "":
			_stages[item.id] = item
	for item in cards:
		if item != null and item.id != "":
			_cards[item.id] = item
