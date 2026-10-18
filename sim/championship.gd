class_name Championship
extends RefCounted
## One solo championship. The open reveal is solved once and stored; catch-up commits that result.
## Wall time is passed in. A gap that crosses a boundary becomes a recap instead of the live phase.

const BUDGET := 10
const PLAYER_ID := "player"
const LIVE_WALL_GAP_SEC := 30.0

const PHASE_IDLE := "idle"
const PHASE_DRAFT := "draft"
const PHASE_STAGE_REVEAL := "stage_reveal"
const PHASE_SERVICE := "service"
const PHASE_RECAP := "recap"
const PHASE_FINISHED := "finished"

var catalog: Catalog
var seed: int = 0
var phase: String = PHASE_IDLE
var stage_index: int = 0
var phase_started_unix: float = 0.0
var pause_started_unix: Variant = null
var resume_phase: String = ""
var entries: Array[Entry] = []
var offers: Array[Dictionary] = []
var results: Array[Dictionary] = []
var recap: Array[Dictionary] = []
var current_results: Dictionary = {}

var _last_now := -1.0


func _init(starting_catalog: Catalog = null) -> void:
	catalog = starting_catalog


func start_draft() -> bool:
	if phase != PHASE_IDLE:
		return false
	phase = PHASE_DRAFT
	return true


func confirm_draft(driver_id: String, car_id: String, now_unix: float, fixed_seed: int = -1) -> bool:
	if phase != PHASE_DRAFT or catalog == null:
		return false
	var driver := catalog.driver(driver_id)
	var chosen_car := catalog.car(car_id)
	if driver == null or chosen_car == null:
		return false
	var cost := driver.cost + chosen_car.cost
	if cost > BUDGET:
		return false
	seed = randi() if fixed_seed < 0 else fixed_seed
	entries = []
	var player := Entry.build(PLAYER_ID, driver, chosen_car, true)
	player.apply_spare_parts(BUDGET - cost)
	entries.append(player)
	for pair in catalog.ai_pairs:
		var ai_driver := catalog.driver(pair.driver_id)
		var ai_car := catalog.car(pair.car_id)
		if ai_driver == null or ai_car == null:
			push_error("Championship is missing the catalog row for %s." % pair.entry_id)
			continue
		var rival := Entry.build(pair.entry_id, ai_driver, ai_car, false)
		rival.apply_spare_parts(maxi(0, BUDGET - ai_driver.cost - ai_car.cost))
		entries.append(rival)
	stage_index = 0
	results = []
	offers = []
	recap = []
	resume_phase = ""
	pause_started_unix = null
	phase_started_unix = now_unix
	_last_now = now_unix
	_solve_current_stage()
	phase = PHASE_STAGE_REVEAL
	return true


func advance(now_unix: float, time_scale: float) -> Dictionary:
	var outcome := _empty_outcome()
	if phase != PHASE_STAGE_REVEAL and phase != PHASE_SERVICE:
		return outcome
	if pause_started_unix != null or time_scale <= 0.0:
		return outcome
	# A backward step never reopens a stage. Inside the open phase the caller just reads `now`.
	if now_unix < phase_started_unix:
		return outcome
	if _last_now >= 0.0 and now_unix < _last_now:
		return outcome
	var wall_gap := INF if _last_now < 0.0 else now_unix - _last_now
	var catch_up := _will_catch_up(now_unix, time_scale, wall_gap)
	var guard := 0
	while phase == PHASE_STAGE_REVEAL or phase == PHASE_SERVICE:
		guard += 1
		if guard > 24:
			push_error("Championship advance did not catch the clock.")
			break
		var duration := _duration(phase)
		if _elapsed(now_unix, time_scale) < duration:
			break
		var boundary := phase_started_unix + duration / time_scale
		var before := phase
		_complete_open_phase(boundary, outcome)
		outcome["phase_changed"] = true
		if phase == before:
			push_error("Championship phase did not advance.")
			break
		if phase == PHASE_FINISHED:
			break
	_last_now = now_unix
	if bool(outcome["phase_changed"]) and (catch_up or int(outcome["defaults_applied"]) > 0):
		_enter_recap(outcome)
	return outcome


func choose_card(card_id: String) -> bool:
	if phase != PHASE_SERVICE:
		return false
	var offer := offer_for(PLAYER_ID)
	if offer.is_empty():
		return false
	var ids: Variant = offer.get("card_ids", [])
	if not ids is Array or not (ids as Array).has(card_id):
		return false
	offer["chosen_card_id"] = card_id
	return true


func pause_at(now_unix: float) -> bool:
	if phase != PHASE_STAGE_REVEAL and phase != PHASE_SERVICE:
		return false
	if pause_started_unix != null:
		return false
	pause_started_unix = now_unix
	return true


func resume(now_unix: float, time_scale: float) -> bool:
	if pause_started_unix == null or time_scale <= 0.0:
		return false
	var paused_at := float(pause_started_unix)
	var elapsed := (paused_at - phase_started_unix) * time_scale
	if elapsed < 0.0:
		elapsed = 0.0
	phase_started_unix = now_unix - elapsed / time_scale
	pause_started_unix = null
	_last_now = now_unix
	return true


func dismiss_recap() -> String:
	if phase != PHASE_RECAP:
		return phase
	var destination := resume_phase if resume_phase != "" else PHASE_IDLE
	recap = []
	resume_phase = ""
	phase = destination
	return destination


func remaining(now_unix: float, time_scale: float) -> float:
	var duration := _duration(_clock_phase())
	if duration <= 0.0:
		return 0.0
	return maxf(0.0, duration - _elapsed(now_unix, time_scale))


func retarget_time_scale(old_scale: float, new_scale: float) -> void:
	if old_scale <= 0.0 or new_scale <= 0.0 or is_equal_approx(old_scale, new_scale):
		return
	var clock_phase := _clock_phase()
	if clock_phase != PHASE_STAGE_REVEAL and clock_phase != PHASE_SERVICE:
		return
	var mark := _last_now
	if pause_started_unix != null:
		mark = float(pause_started_unix)
	elif mark < 0.0:
		return
	var elapsed := (mark - phase_started_unix) * old_scale
	if elapsed < 0.0:
		elapsed = 0.0
	phase_started_unix = mark - elapsed / new_scale


func open_clock_holds(now_unix: float, time_scale: float) -> bool:
	var clock_phase := _clock_phase()
	if (
		clock_phase == PHASE_FINISHED
		or clock_phase == PHASE_IDLE
		or clock_phase == PHASE_DRAFT
		or clock_phase == ""
	):
		return phase_started_unix <= now_unix + 0.001
	if pause_started_unix != null:
		return true
	var duration := _duration(clock_phase)
	if duration <= 0.0:
		return phase_started_unix <= now_unix + 0.001
	var elapsed := (now_unix - phase_started_unix) * time_scale
	return elapsed >= -0.001 and elapsed < duration


func observed_now() -> float:
	return _last_now


func player_entry() -> Entry:
	return find_entry(PLAYER_ID)


func find_entry(entry_id: String) -> Entry:
	for entry in entries:
		if entry.id == entry_id:
			return entry
	return null


func offer_for(entry_id: String) -> Dictionary:
	for offer in offers:
		if str(offer.get("entry_id", "")) == entry_id:
			return offer
	return {}


func stage_result(entry_id: String) -> StageSolver.StageResult:
	return current_results.get(entry_id) as StageSolver.StageResult


func standings() -> Array[Dictionary]:
	return Standings.championship_table(entries, results)


func to_dictionary() -> Dictionary:
	var stored_entries: Array = []
	for entry in entries:
		stored_entries.append(entry.to_dictionary())
	var data := {
		"seed": seed,
		"phase": phase,
		"stage_index": stage_index,
		"phase_started_unix": phase_started_unix,
		"pause_started_unix": pause_started_unix,
		"entries": stored_entries,
		"results": results.duplicate(true),
		"recap": recap.duplicate(true),
	}
	if phase == PHASE_RECAP and resume_phase != "":
		data["resume_phase"] = resume_phase
	if _service_is_open():
		data["offers"] = offers.duplicate(true)
	return data


static func from_dictionary(data: Dictionary, source: Catalog) -> Championship:
	var champ := Championship.new(source)
	champ.seed = int(data.get("seed", 0))
	champ.phase = str(data.get("phase", PHASE_IDLE))
	champ.stage_index = int(data.get("stage_index", 0))
	champ.phase_started_unix = float(data.get("phase_started_unix", 0.0))
	var paused: Variant = data.get("pause_started_unix", null)
	champ.pause_started_unix = null if paused == null else float(paused)
	champ.resume_phase = str(data.get("resume_phase", ""))
	var raw_entries: Variant = data.get("entries", [])
	if raw_entries is Array:
		for raw_entry in raw_entries:
			if raw_entry is Dictionary:
				champ.entries.append(Entry.from_dictionary(raw_entry))
	champ.offers = _dictionary_rows(data.get("offers", []))
	champ.results = _dictionary_rows(data.get("results", []))
	champ.recap = _dictionary_rows(data.get("recap", []))
	for offer in champ.offers:
		offer["card_ids"] = _string_row(offer.get("card_ids", []))
		offer["chosen_card_id"] = str(offer.get("chosen_card_id", ""))
		offer["ai_card_id"] = str(offer.get("ai_card_id", ""))
		offer["entry_id"] = str(offer.get("entry_id", ""))
	champ.restore_solved_stage()
	return champ


func restore_solved_stage() -> void:
	if _clock_phase() != PHASE_STAGE_REVEAL:
		return
	if current_results.size() == entries.size() and not entries.is_empty():
		return
	_solve_current_stage()


func _service_is_open() -> bool:
	if phase == PHASE_SERVICE:
		return true
	return phase == PHASE_RECAP and resume_phase == PHASE_SERVICE


func _clock_phase() -> String:
	if phase == PHASE_RECAP:
		return resume_phase
	return phase


func _will_catch_up(now_unix: float, time_scale: float, wall_gap: float) -> bool:
	var crosses := 0
	var sim_phase := phase
	var sim_started := phase_started_unix
	var sim_index := stage_index
	var last_index := _last_stage_index()
	while sim_phase == PHASE_STAGE_REVEAL or sim_phase == PHASE_SERVICE:
		var elapsed := (now_unix - sim_started) * time_scale
		if elapsed < 0.0:
			elapsed = 0.0
		var duration := _duration(sim_phase)
		if elapsed < duration:
			break
		crosses += 1
		var boundary := sim_started + duration / time_scale
		if sim_phase == PHASE_STAGE_REVEAL and sim_index >= last_index:
			break
		if sim_phase == PHASE_STAGE_REVEAL:
			sim_phase = PHASE_SERVICE
		else:
			sim_index += 1
			sim_phase = PHASE_STAGE_REVEAL
		sim_started = boundary
		if crosses > 24:
			break
	if crosses >= 2:
		return true
	if crosses == 1 and wall_gap > LIVE_WALL_GAP_SEC:
		return true
	return false


func _complete_open_phase(boundary: float, outcome: Dictionary) -> void:
	if phase == PHASE_STAGE_REVEAL:
		_commit_current_stage()
		if stage_index >= _last_stage_index():
			offers = []
			phase = PHASE_FINISHED
			phase_started_unix = boundary
			outcome["entered_finished"] = true
			return
		_open_service(boundary)
		return
	if phase == PHASE_SERVICE:
		_resolve_service(boundary, outcome)


func _commit_current_stage() -> void:
	if current_results.is_empty():
		_solve_current_stage()
	var stage := catalog.stage_at(stage_index)
	var rows: Array = []
	for entry in entries:
		var result := current_results.get(entry.id) as StageSolver.StageResult
		if result == null:
			continue
		var incidents: Array = []
		for incident in result.incidents:
			incidents.append(incident.duplicate(true))
		var sectors: Array = []
		for sector_time in result.sector_times:
			sectors.append(sector_time)
		rows.append({
			"entry_id": entry.id,
			"finish_time": result.finish_time,
			"sector_times": sectors,
			"incidents": incidents,
		})
	results.append({
		"stage_index": stage_index,
		"stage_id": "" if stage == null else stage.id,
		"rows": Standings.rank_stage(rows),
	})
	current_results.clear()


func _open_service(started_unix: float) -> void:
	var next_stage := catalog.stage_at(stage_index + 1)
	offers = []
	if next_stage == null:
		phase = PHASE_FINISHED
		phase_started_unix = started_unix
		return
	for entry in entries:
		var cards := ServiceOffer.build(catalog, entry, next_stage, seed, stage_index)
		var card_ids: Array = []
		for card in cards:
			card_ids.append(card.id)
		var ai_card_id := ""
		if not entry.is_player:
			ai_card_id = ServiceOffer.pick_ai(cards, next_stage)
		offers.append({
			"entry_id": entry.id,
			"card_ids": card_ids,
			"chosen_card_id": "",
			"ai_card_id": ai_card_id,
		})
	phase = PHASE_SERVICE
	phase_started_unix = started_unix


func _resolve_service(boundary: float, outcome: Dictionary) -> void:
	for offer in offers:
		var entry := find_entry(str(offer.get("entry_id", "")))
		if entry == null:
			continue
		var card_id := ""
		if entry.is_player:
			card_id = str(offer.get("chosen_card_id", ""))
			var offered: Variant = offer.get("card_ids", [])
			var chosen_ok := card_id != "" and offered is Array and (offered as Array).has(card_id)
			if not chosen_ok:
				card_id = _default_card_id(offer)
				recap.append({
					"stage_index": stage_index + 1,
					"card_id": card_id,
					"applied_by": "default",
				})
				outcome["defaults_applied"] = int(outcome["defaults_applied"]) + 1
			(outcome["player_applications"] as Array).append(card_id)
		else:
			card_id = str(offer.get("ai_card_id", ""))
		var card := catalog.card(card_id)
		if card == null:
			push_error("Championship is missing card %s for %s." % [card_id, entry.id])
			continue
		entry.apply_card(card)
	offers = []
	stage_index += 1
	_solve_current_stage()
	phase = PHASE_STAGE_REVEAL
	phase_started_unix = boundary


func _default_card_id(offer: Dictionary) -> String:
	var ids: Variant = offer.get("card_ids", [])
	var lowest := ""
	var safe_id := ""
	if ids is Array:
		for raw_id in ids:
			var card_id := str(raw_id)
			if lowest == "" or card_id < lowest:
				lowest = card_id
			var card := catalog.card(card_id)
			if card != null and card.safe:
				safe_id = card_id
	if safe_id != "":
		return safe_id
	push_error("Service offer has no safe card; applying %s." % lowest)
	return lowest


func _solve_current_stage() -> void:
	current_results = {}
	if catalog == null:
		return
	var stage := catalog.stage_at(stage_index)
	if stage == null:
		push_error("Championship has no stage at index %s." % stage_index)
		return
	for entry in entries:
		var solved_seed := StageSolver.stage_seed(seed, stage.id, entry.id)
		current_results[entry.id] = StageSolver.solve(entry, stage, solved_seed)


func _enter_recap(outcome: Dictionary) -> void:
	if phase == PHASE_RECAP:
		return
	resume_phase = phase
	phase = PHASE_RECAP
	outcome["entered_recap"] = true
	outcome["entered_finished"] = false
	outcome["phase_changed"] = true


func _duration(phase_name: String) -> float:
	if phase_name == PHASE_STAGE_REVEAL:
		return float(Timing.STAGE_REVEAL_SEC)
	if phase_name == PHASE_SERVICE:
		return float(Timing.SERVICE_SEC)
	return 0.0


func _elapsed(now_unix: float, time_scale: float) -> float:
	var mark := now_unix
	if pause_started_unix != null:
		mark = float(pause_started_unix)
	var delta := (mark - phase_started_unix) * time_scale
	if delta < 0.0:
		return 0.0
	return delta


func _last_stage_index() -> int:
	if catalog == null or catalog.stage_order.is_empty():
		return 0
	return catalog.stage_order.size() - 1


func _empty_outcome() -> Dictionary:
	return {
		"phase_changed": false,
		"entered_recap": false,
		"entered_finished": false,
		"defaults_applied": 0,
		"player_applications": [],
	}


static func _dictionary_rows(value: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if value is Array:
		for item in value:
			if item is Dictionary:
				rows.append((item as Dictionary).duplicate(true))
	return rows


static func _string_row(value: Variant) -> Array:
	var row: Array = []
	if value is Array:
		for item in value:
			row.append(str(item))
	return row
