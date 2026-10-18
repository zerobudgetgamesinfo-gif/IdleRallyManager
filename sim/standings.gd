class_name Standings
extends RefCounted
## Stage order is finish time ascending, then entry id ascending.
## Championship order is points descending, then total time ascending, then entry id ascending.

const POINTS: Array[int] = [10, 8, 6, 5, 4, 3, 2, 1]


static func rank_stage(rows: Array) -> Array[Dictionary]:
	var sorted: Array[Dictionary] = []
	for row in rows:
		if row is Dictionary:
			sorted.append((row as Dictionary).duplicate(true))
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var time_a := float(a.get("finish_time", 0.0))
		var time_b := float(b.get("finish_time", 0.0))
		if time_a != time_b:
			return time_a < time_b
		return str(a.get("entry_id", "")) < str(b.get("entry_id", ""))
	)
	for index in sorted.size():
		sorted[index]["position"] = index + 1
		sorted[index]["points"] = POINTS[index] if index < POINTS.size() else 0
	return sorted


static func championship_table(entries: Array, results: Array) -> Array[Dictionary]:
	var points := {}
	var total_time := {}
	var order: Array[String] = []
	for entry in entries:
		if not entry is Entry:
			continue
		var entry_id := (entry as Entry).id
		points[entry_id] = 0
		total_time[entry_id] = 0.0
		order.append(entry_id)
	for stage_result in results:
		if not stage_result is Dictionary:
			continue
		var stage_rows: Variant = (stage_result as Dictionary).get("rows", [])
		if not stage_rows is Array:
			continue
		for row in stage_rows:
			if not row is Dictionary:
				continue
			var entry_id := str((row as Dictionary).get("entry_id", ""))
			if not points.has(entry_id):
				points[entry_id] = 0
				total_time[entry_id] = 0.0
				order.append(entry_id)
			points[entry_id] = int(points[entry_id]) + int((row as Dictionary).get("points", 0))
			total_time[entry_id] = float(total_time[entry_id]) + float((row as Dictionary).get("finish_time", 0.0))
	var table: Array[Dictionary] = []
	for entry_id in order:
		table.append({
			"entry_id": entry_id,
			"points": int(points[entry_id]),
			"total_time": float(total_time[entry_id]),
		})
	table.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var points_a := int(a.get("points", 0))
		var points_b := int(b.get("points", 0))
		if points_a != points_b:
			return points_a > points_b
		var time_a := float(a.get("total_time", 0.0))
		var time_b := float(b.get("total_time", 0.0))
		if time_a != time_b:
			return time_a < time_b
		return str(a.get("entry_id", "")) < str(b.get("entry_id", ""))
	)
	for index in table.size():
		table[index]["position"] = index + 1
	return table
