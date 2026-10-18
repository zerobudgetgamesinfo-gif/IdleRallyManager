class_name Entry
extends RefCounted
## A field slot built by copying a driver and a car. Cards and spare parts land here.
## DriverDef and CarDef are never written.

const STAT_NAMES: PackedStringArray = ["pace", "grip", "jump", "reliability", "focus"]
const STAT_CAP := 20

var id: String = ""
var driver_id: String = ""
var car_id: String = ""
var is_player: bool = false
var pace: int = 0
var grip: int = 0
var jump: int = 0
var reliability: int = 0
var focus: int = 0
var card_ids: Array[String] = []


static func build(id: String, driver: DriverDef, car: CarDef, is_player: bool) -> Entry:
	var entry := Entry.new()
	entry.id = id
	entry.driver_id = driver.id
	entry.car_id = car.id
	entry.is_player = is_player
	entry.pace = driver.pace + car.pace
	entry.grip = driver.grip + car.grip
	entry.jump = driver.jump + car.jump
	entry.reliability = driver.reliability + car.reliability
	entry.focus = driver.focus + car.focus
	entry._clamp_stats()
	return entry


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


func stat_block() -> Dictionary:
	return {
		"pace": pace,
		"grip": grip,
		"jump": jump,
		"reliability": reliability,
		"focus": focus,
	}


func owns(card_id: String) -> bool:
	return card_ids.has(card_id)


func apply_card(card: CardDef) -> void:
	pace += card.pace
	grip += card.grip
	jump += card.jump
	reliability += card.reliability
	focus += card.focus
	_clamp_stats()
	if card.id != "" and not owns(card.id):
		card_ids.append(card.id)


func apply_spare_parts(unspent: int) -> void:
	if unspent <= 0:
		return
	reliability += unspent
	_clamp_stats()


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"driver_id": driver_id,
		"car_id": car_id,
		"is_player": is_player,
		"pace": pace,
		"grip": grip,
		"jump": jump,
		"reliability": reliability,
		"focus": focus,
		"card_ids": card_ids.duplicate(),
	}


static func from_dictionary(data: Dictionary) -> Entry:
	var entry := Entry.new()
	entry.id = str(data.get("id", ""))
	entry.driver_id = str(data.get("driver_id", ""))
	entry.car_id = str(data.get("car_id", ""))
	entry.is_player = bool(data.get("is_player", false))
	entry.pace = int(data.get("pace", 0))
	entry.grip = int(data.get("grip", 0))
	entry.jump = int(data.get("jump", 0))
	entry.reliability = int(data.get("reliability", 0))
	entry.focus = int(data.get("focus", 0))
	var raw_cards: Variant = data.get("card_ids", [])
	if raw_cards is Array:
		for card_id in raw_cards:
			entry.card_ids.append(str(card_id))
	return entry


func _clamp_stats() -> void:
	pace = clampi(pace, 0, STAT_CAP)
	grip = clampi(grip, 0, STAT_CAP)
	jump = clampi(jump, 0, STAT_CAP)
	reliability = clampi(reliability, 0, STAT_CAP)
	focus = clampi(focus, 0, STAT_CAP)
