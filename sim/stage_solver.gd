class_name StageSolver
extends RefCounted
## Pure stage solve. Random numbers are consumed as four incident rolls, then three sector jitters.
## The clock is not an input. `stage_seed` is hash(championship seed, stage id, entry id).


static func stage_seed(championship_seed: int, stage_id: String, entry_id: String) -> int:
	return mix_seed([championship_seed, stage_id, entry_id])


static func mix_seed(parts: Array) -> int:
	# Fold the sign bit. RandomNumberGenerator.seed is a 64-bit pattern, and a negative
	# hash() would not be a stable assignment on every export.
	return hash(parts) & 0x7fffffffffffffff


static func solve(entry: Entry, stage: StageDef, stage_seed_value: int) -> StageResult:
	var rng := RandomNumberGenerator.new()
	rng.seed = stage_seed_value
	var weighted := 0.0
	for stat_name in Entry.STAT_NAMES:
		weighted += stage.weight(stat_name) * float(entry.stat(stat_name))
	var skill := (weighted - 10.0) / 10.0
	var pace_time := float(stage.base_time_sec) * (1.0 - skill * 0.12)
	var incidents: Array[Dictionary] = []
	var penalty_sum := 0.0
	for beat in stage.beats:
		var stat_value := entry.stat(beat.stat)
		var chance := clampf(
			0.55 - float(stat_value) * 0.03 - float(entry.reliability) * 0.01,
			0.05,
			0.70
		)
		if rng.randf() < chance:
			var penalty := 4.0 + (10.0 - minf(float(stat_value), 10.0)) * 0.8
			penalty_sum += penalty
			incidents.append({
				"t_norm": beat.t_norm,
				"kind": beat.kind,
				"penalty": penalty,
			})
	var finish_time := pace_time + penalty_sum
	var shares: Array[float] = []
	var share_sum := 0.0
	for _step in 3:
		var share := (1.0 / 3.0) + rng.randf_range(-0.02, 0.02)
		shares.append(share)
		share_sum += share
	if is_zero_approx(share_sum):
		share_sum = 1.0
	var sector_times: Array[float] = []
	for share in shares:
		sector_times.append(finish_time * (share / share_sum))
	var result := StageResult.new()
	result.finish_time = finish_time
	result.sector_times = sector_times
	result.incidents = incidents
	return result


class StageResult extends RefCounted:
	var finish_time: float = 0.0
	var sector_times: Array[float] = []
	var incidents: Array[Dictionary] = []


	func same_as(other: StageResult) -> bool:
		if other == null:
			return false
		if finish_time != other.finish_time:
			return false
		if sector_times.size() != other.sector_times.size():
			return false
		for index in sector_times.size():
			if sector_times[index] != other.sector_times[index]:
				return false
		if incidents.size() != other.incidents.size():
			return false
		for index in incidents.size():
			var left: Dictionary = incidents[index]
			var right: Dictionary = other.incidents[index]
			if not is_equal_approx(float(left.get("t_norm", 0.0)), float(right.get("t_norm", 0.0))):
				return false
			if str(left.get("kind", "")) != str(right.get("kind", "")):
				return false
			if float(left.get("penalty", 0.0)) != float(right.get("penalty", 0.0)):
				return false
		return true
