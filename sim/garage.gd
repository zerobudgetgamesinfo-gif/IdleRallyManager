class_name Garage
extends RefCounted
## Reputation and the ids it has unlocked. The solver never reads this.
## Starters stay available at threshold 0 and are not written into unlocked_ids.

var reputation: int = 0
var unlocked_ids: Array[String] = []


func allows(threshold: int, id: String) -> bool:
	if threshold <= 0:
		return true
	if unlocked_ids.has(id):
		return true
	return reputation >= threshold


func commit_finish(points: int, catalog: Catalog) -> void:
	reputation += maxi(points, 0)
	if catalog == null:
		return
	for driver in catalog.drivers:
		if driver != null:
			_remember(driver.id, driver.unlock_reputation)
	for car in catalog.cars:
		if car != null:
			_remember(car.id, car.unlock_reputation)


func to_dictionary() -> Dictionary:
	return {
		"reputation": reputation,
		"unlocked_ids": unlocked_ids.duplicate(),
	}


static func from_dictionary(data: Dictionary) -> Garage:
	var garage := Garage.new()
	garage.reputation = maxi(int(data.get("reputation", 0)), 0)
	var raw_ids: Variant = data.get("unlocked_ids", [])
	if raw_ids is Array:
		for raw_id in raw_ids:
			var id := str(raw_id)
			if id != "" and not garage.unlocked_ids.has(id):
				garage.unlocked_ids.append(id)
	return garage


func _remember(id: String, threshold: int) -> void:
	if id == "" or threshold <= 0 or reputation < threshold:
		return
	if unlocked_ids.has(id):
		return
	unlocked_ids.append(id)
