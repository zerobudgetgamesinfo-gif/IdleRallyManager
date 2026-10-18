class_name RevealPlayback
extends RefCounted
## Maps a reveal fraction onto a stored stage result. No nodes and no clock.
##
## Distance is three equal sectors. Pace keeps the stored sector shares, and each
## incident penalty is added to the sector that contains its t_norm. A loss in
## the middle third therefore opens up only while that third is playing.
## At f = 1 the time is the stored finish_time, so the order matches the solve.


const SECTOR_COUNT := 3


static func fraction_from_remaining(remaining_sec: float) -> float:
	var duration := float(Timing.STAGE_REVEAL_SEC)
	if duration <= 0.0:
		return 0.0
	return clampf((duration - remaining_sec) / duration, 0.0, 1.0)


static func row_from_result(entry_id: String, result: StageSolver.StageResult) -> Dictionary:
	if result == null:
		return {}
	return {
		"entry_id": entry_id,
		"finish_time": result.finish_time,
		"sector_times": result.sector_times.duplicate(),
		"incidents": result.incidents.duplicate(true),
	}


## Sector 1 is [0, 1/3), sector 2 is [1/3, 2/3), sector 3 is [2/3, 1].
static func sector_index(distance: float) -> int:
	var clamped := clampf(distance, 0.0, 1.0)
	if clamped < 1.0 / 3.0:
		return 0
	if clamped < 2.0 / 3.0:
		return 1
	return SECTOR_COUNT - 1


static func presentation_sectors(finish_time: float, sector_times: Variant, incidents: Variant) -> Array[float]:
	var stored: Array[float] = []
	var stored_sum := 0.0
	if sector_times is Array:
		for raw_time in sector_times:
			var sector_time := maxf(float(raw_time), 0.0)
			if stored.size() >= SECTOR_COUNT:
				break
			stored.append(sector_time)
			stored_sum += sector_time
	while stored.size() < SECTOR_COUNT:
		stored.append(0.0)
	var penalty_sum := 0.0
	var placed: Array[Dictionary] = []
	if incidents is Array:
		for raw_incident in incidents:
			if not raw_incident is Dictionary:
				continue
			var incident := raw_incident as Dictionary
			var penalty := maxf(float(incident.get("penalty", 0.0)), 0.0)
			penalty_sum += penalty
			placed.append(incident)
	var pace := maxf(finish_time - penalty_sum, 0.0)
	var sectors: Array[float] = [0.0, 0.0, 0.0]
	if stored_sum <= 0.0:
		var even := pace / float(SECTOR_COUNT)
		for index in SECTOR_COUNT - 1:
			sectors[index] = even
		sectors[SECTOR_COUNT - 1] = pace - even * float(SECTOR_COUNT - 1)
	else:
		var assigned := 0.0
		for index in SECTOR_COUNT - 1:
			var share := pace * (stored[index] / stored_sum)
			sectors[index] = share
			assigned += share
		sectors[SECTOR_COUNT - 1] = pace - assigned
	for incident in placed:
		var penalty := maxf(float(incident.get("penalty", 0.0)), 0.0)
		var index := sector_index(float(incident.get("t_norm", 0.0)))
		sectors[index] += penalty
	var total := 0.0
	for sector in sectors:
		total += sector
	sectors[SECTOR_COUNT - 1] = maxf(0.0, sectors[SECTOR_COUNT - 1] + finish_time - total)
	return sectors


static func elapsed_in_sectors(sectors: Array[float], fraction: float) -> float:
	var clamped := clampf(fraction, 0.0, 1.0)
	if clamped <= 0.0 or sectors.is_empty():
		return 0.0
	var count := mini(sectors.size(), SECTOR_COUNT)
	if clamped >= 1.0:
		var total := 0.0
		for index in count:
			total += sectors[index]
		return total
	var scaled := clamped * float(SECTOR_COUNT)
	var index := mini(floori(scaled), count - 1)
	var local := scaled - float(index)
	var time := 0.0
	for step in index:
		time += sectors[step]
	time += sectors[index] * local
	return time


static func sample(rows: Array, fraction: float) -> Array[Dictionary]:
	var f := clampf(fraction, 0.0, 1.0)
	var ranked: Array[Dictionary] = []
	for row in rows:
		if not row is Dictionary:
			continue
		var data := row as Dictionary
		var finish_time := float(data.get("finish_time", 0.0))
		var sectors := presentation_sectors(finish_time, data.get("sector_times", []), data.get("incidents", []))
		var time := finish_time if f >= 1.0 else elapsed_in_sectors(sectors, f)
		ranked.append({
			"entry_id": str(data.get("entry_id", "")),
			"time": time,
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var time_a := float(a.get("time", 0.0))
		var time_b := float(b.get("time", 0.0))
		if time_a != time_b:
			return time_a < time_b
		return str(a.get("entry_id", "")) < str(b.get("entry_id", ""))
	)
	for index in ranked.size():
		ranked[index]["position"] = index + 1
	return ranked


static func order_of(rows: Array, fraction: float) -> PackedStringArray:
	var ids := PackedStringArray()
	for row in sample(rows, fraction):
		ids.append(str(row.get("entry_id", "")))
	return ids
