extends SceneTree
## Headless checks for the solver, the clock, and the save.
## godot --headless --path . -s res://sim/checks/run_checks.gd

const CATALOG: Catalog = preload("res://data/catalog.tres")
const SESSION_SCRIPT := preload("res://sim/session.gd")

const GOLDEN_FINISH_TIMES: PackedStringArray = [
	"727.2",
	"656.512",
	"715.12",
	"791.7",
	"742.216",
	"951.0",
	"746.66",
	"868.256",
]

var _failures: PackedStringArray = []
var _sessions: Array[Node] = []


func _init() -> void:
	_check_catalog()
	_check_draft()
	_check_solver()
	_check_standings()
	_check_playback()
	_check_service()
	_check_catch_up()
	_check_pause_and_rewind()
	_check_save_round_trip()
	_check_newer_version_untouched()
	_check_older_version_backed_up()
	_check_championship_runs_to_the_end()
	_cleanup()
	if _failures.is_empty():
		print("All checks passed.")
		quit(0)
		return
	for failure in _failures:
		print("FAIL: %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error(message)


func _session(tag: String):
	var session := SESSION_SCRIPT.new()
	session.save_path = "user://checks/%s.json" % tag
	_sessions.append(session)
	return session


func _pip_teapot() -> Entry:
	var driver := CATALOG.driver("pip")
	var car := CATALOG.car("teapot")
	var entry := Entry.build(Championship.PLAYER_ID, driver, car, true)
	entry.apply_spare_parts(Championship.BUDGET - driver.cost - car.cost)
	return entry


func _check_catalog() -> void:
	var autoload := str(ProjectSettings.get_setting("autoload/Session", ""))
	_expect(autoload.ends_with("res://sim/session.gd"), "Session autoload is %s" % autoload)
	_expect(Timing.STAGE_REVEAL_SEC == 1800, "reveal length")
	_expect(Timing.SERVICE_SEC == 1800, "service length")
	var stages := CATALOG.stages_in_order()
	_expect(stages.size() == 8, "stage count %s" % stages.size())
	_expect(CATALOG.ai_pairs.size() == 7, "ai pair count %s" % CATALOG.ai_pairs.size())
	for stage in stages:
		var sum := stage.weight_sum()
		_expect(absf(sum - 1.0) <= 0.001, "%s weights sum to %s" % [stage.id, sum])
		_expect(stage.beats.size() == 4, "%s beat count %s" % [stage.id, stage.beats.size()])
	_expect(ServiceOffer.top_stat(CATALOG.stage("coastal_tarmac")) == "pace", "coastal top stat")
	_expect(ServiceOffer.top_stat(CATALOG.stage("long_motorway")) == "pace", "motorway tie")
	_expect(ServiceOffer.top_stat(CATALOG.stage("final_mixed")) == "pace", "final tie")
	_expect(ServiceOffer.top_stat(CATALOG.stage("snow_lane")) == "grip", "snow top stat")


func _check_draft() -> void:
	var session = _session("draft")
	session.start_draft()
	var pip := CATALOG.driver("pip")
	var teapot := CATALOG.car("teapot")
	var pip_reliability := pip.reliability
	var teapot_reliability := teapot.reliability
	_expect(session.confirm_draft("pip", "teapot", 0.0, 1), "pip + teapot should start")
	var player: Entry = session.championship.player_entry()
	_expect(
		player.reliability == pip_reliability + teapot_reliability + 6,
		"spare parts reliability %s" % player.reliability
	)
	_expect(pip.reliability == pip_reliability, "draft mutated the driver resource")
	_expect(teapot.reliability == teapot_reliability, "draft mutated the car resource")
	_expect(session.championship.entries.size() == 8, "field size %s" % session.championship.entries.size())
	var rival: Entry = session.championship.find_entry("ai_1")
	_expect(rival != null and rival.driver_id == "miso" and rival.car_id == "dart", "ai_1 pair")
	var rival_base := CATALOG.driver("miso").reliability + CATALOG.car("dart").reliability
	_expect(rival.reliability == rival_base, "over-budget rival gained spare parts")

	var rejected = _session("reject")
	rejected.start_draft()
	_expect(not rejected.confirm_draft("miso", "dart", 0.0, 1), "miso + dart should be rejected")
	_expect(rejected.phase() == Championship.PHASE_DRAFT, "rejected phase %s" % rejected.phase())
	_expect(rejected.championship.entries.is_empty(), "rejected draft built a field")
	_expect(rejected.championship.seed == 0, "rejected draft stored a seed")


func _check_solver() -> void:
	var entry := _pip_teapot()
	var stages := CATALOG.stages_in_order()
	_expect(stages.size() == GOLDEN_FINISH_TIMES.size(), "golden count")
	for index in stages.size():
		var stage := stages[index]
		var solved_seed := StageSolver.stage_seed(1, stage.id, entry.id)
		var first := StageSolver.solve(entry, stage, solved_seed)
		var second := StageSolver.solve(entry, stage, solved_seed)
		_expect(first.same_as(second), "solve diverged on %s" % stage.id)
		_expect(
			str(first.finish_time) == GOLDEN_FINISH_TIMES[index],
			"%s finish_time %s" % [stage.id, str(first.finish_time)]
		)
	var first_championship := Championship.new(CATALOG)
	first_championship.start_draft()
	first_championship.confirm_draft("pip", "teapot", 0.0, 1)
	var second_championship := Championship.new(CATALOG)
	second_championship.start_draft()
	second_championship.confirm_draft("pip", "teapot", 0.0, 1)
	for raced in first_championship.entries:
		var left := first_championship.stage_result(raced.id)
		var right := second_championship.stage_result(raced.id)
		_expect(left != null and left.same_as(right), "replay diverged for %s" % raced.id)
	var stored := first_championship.stage_result(Championship.PLAYER_ID)
	_expect(str(stored.finish_time) == GOLDEN_FINISH_TIMES[0], "championship stage 0 drifted")
	var original_time := stored.finish_time
	var original_sectors := stored.sector_times.duplicate()
	var original_incidents := stored.incidents.size()
	var player := first_championship.player_entry()
	player.pace = 0
	player.reliability = 0
	var after := first_championship.stage_result(Championship.PLAYER_ID)
	_expect(after.finish_time == original_time, "stored finish_time changed after a stat edit")
	_expect(after.sector_times == original_sectors, "stored sectors changed after a stat edit")
	_expect(after.incidents.size() == original_incidents, "stored incidents changed after a stat edit")
	first_championship.advance(float(Timing.STAGE_REVEAL_SEC), 1.0)
	var committed := _player_row(first_championship.results[0])
	_expect(
		committed.get("finish_time", -1.0) == original_time,
		"committed time was re-solved after the entry changed"
	)


func _check_standings() -> void:
	var ranked := Standings.rank_stage([
		{"entry_id": "b", "finish_time": 10.0},
		{"entry_id": "a", "finish_time": 10.0},
		{"entry_id": "c", "finish_time": 9.0},
	])
	_expect(str(ranked[0]["entry_id"]) == "c" and int(ranked[0]["points"]) == 10, "stage winner")
	_expect(str(ranked[1]["entry_id"]) == "a" and int(ranked[1]["points"]) == 8, "tie breaks to the lower id")
	_expect(str(ranked[2]["entry_id"]) == "b" and int(ranked[2]["points"]) == 6, "third place")
	var entries: Array[Entry] = []
	for entry_id in ["b", "a", "c"]:
		var entry := Entry.new()
		entry.id = entry_id
		entries.append(entry)
	var table := Standings.championship_table(entries, [{
		"rows": [
			{"entry_id": "a", "points": 10, "finish_time": 50.0},
			{"entry_id": "b", "points": 10, "finish_time": 40.0},
			{"entry_id": "c", "points": 8, "finish_time": 10.0},
		],
	}])
	_expect(str(table[0]["entry_id"]) == "b", "points tie breaks to the faster total")
	_expect(str(table[1]["entry_id"]) == "a", "second on time")
	_expect(str(table[2]["entry_id"]) == "c", "fewer points finishes behind")


func _check_playback() -> void:
	_expect(
		is_zero_approx(RevealPlayback.fraction_from_remaining(float(Timing.STAGE_REVEAL_SEC))),
		"fraction at the start"
	)
	_expect(is_equal_approx(RevealPlayback.fraction_from_remaining(0.0), 1.0), "fraction at the end")
	_expect(RevealPlayback.sector_index(0.15) == 0, "beat 1 sector")
	_expect(RevealPlayback.sector_index(0.40) == 1, "beat 2 sector")
	_expect(RevealPlayback.sector_index(0.65) == 1, "0.65 is still the middle third")
	_expect(RevealPlayback.sector_index(0.85) == 2, "beat 4 sector")
	_expect(RevealPlayback.sector_index(1.0) == 2, "end sector")
	var champ := Championship.new(CATALOG)
	champ.start_draft()
	champ.confirm_draft("pip", "teapot", 0.0, 1)
	var rows := _open_rows(champ)
	_expect(rows.size() == 8, "playback rows %s" % rows.size())
	_check_samples(rows)
	var stored := champ.stage_result(Championship.PLAYER_ID)
	var finish_before := stored.finish_time
	var sectors_before := stored.sector_times.duplicate()
	var incident_count := stored.incidents.size()
	RevealPlayback.sample(rows, 0.5)
	_expect(stored.finish_time == finish_before, "playback changed finish_time")
	_expect(stored.sector_times == sectors_before, "playback changed sector_times")
	_expect(stored.incidents.size() == incident_count, "playback changed incidents")
	_check_sector_two_penalty()


func _check_samples(rows: Array) -> void:
	var solved := _ids_of(Standings.rank_stage(rows))
	for fraction in [0.0, 0.5, 1.0]:
		var sampled := RevealPlayback.sample(rows, fraction)
		_expect(sampled.size() == rows.size(), "sample %s size %s" % [fraction, sampled.size()])
		if is_zero_approx(fraction):
			for row in sampled:
				_expect(is_zero_approx(float(row.get("time", 1.0))), "f=0 time %s" % row.get("time", ""))
			_expect(_ids_ascending(sampled), "f=0 order %s" % str(_ids_of(sampled)))
		elif is_equal_approx(fraction, 1.0):
			_expect(_ids_of(sampled) == solved, "final order %s vs %s" % [_ids_of(sampled), solved])
		else:
			_expect(_mid_stage_times(sampled, rows), "f=0.5 left the stage")
	var reversed: Array = []
	for index in range(rows.size() - 1, -1, -1):
		reversed.append(rows[index])
	_expect(RevealPlayback.order_of(reversed, 1.0) == solved, "input order changed the finish")


func _check_sector_two_penalty() -> void:
	var crafted: Array = [
		{
			"entry_id": "fault",
			"finish_time": 250.0,
			"sector_times": [250.0 / 3.0, 250.0 / 3.0, 250.0 / 3.0],
			"incidents": [{"t_norm": 0.5, "kind": "jump", "penalty": 40.0}],
		},
		{
			"entry_id": "pace",
			"finish_time": 240.0,
			"sector_times": [80.0, 80.0, 80.0],
			"incidents": [],
		},
	]
	var sectors := RevealPlayback.presentation_sectors(
		250.0,
		[250.0 / 3.0, 250.0 / 3.0, 250.0 / 3.0],
		[{"t_norm": 0.5, "kind": "jump", "penalty": 40.0}]
	)
	_expect(is_equal_approx(sectors[0], 70.0), "pace sector 1 %s" % sectors[0])
	_expect(is_equal_approx(sectors[1], 110.0), "penalty sector 2 %s" % sectors[1])
	_expect(is_equal_approx(sectors[2], 70.0), "pace sector 3 %s" % sectors[2])
	_expect(is_equal_approx(sectors[0] + sectors[1] + sectors[2], 250.0), "sector sum")
	_check_samples(crafted)
	var early := _gap_between(crafted, 0.2, "fault", "pace")
	var during := _gap_between(crafted, 0.5, "fault", "pace")
	_expect(early < -1.0, "fault should lead before sector 2, gap %s" % early)
	_expect(during > 1.0, "fault should fall back during sector 2, gap %s" % during)
	_expect(str(RevealPlayback.order_of(crafted, 1.0)[0]) == "pace", "solved winner")


func _open_rows(champ: Championship) -> Array:
	var rows: Array = []
	for entry in champ.entries:
		var result := champ.stage_result(entry.id)
		if result == null:
			continue
		rows.append(RevealPlayback.row_from_result(entry.id, result))
	return rows


func _gap_between(rows: Array, fraction: float, later_id: String, earlier_id: String) -> float:
	var sampled := RevealPlayback.sample(rows, fraction)
	var later := 0.0
	var earlier := 0.0
	for row in sampled:
		var entry_id := str(row.get("entry_id", ""))
		if entry_id == later_id:
			later = float(row.get("time", 0.0))
		elif entry_id == earlier_id:
			earlier = float(row.get("time", 0.0))
	return later - earlier


func _mid_stage_times(sampled: Array, rows: Array) -> bool:
	var finishes := {}
	for row in rows:
		if row is Dictionary:
			finishes[str((row as Dictionary).get("entry_id", ""))] = float((row as Dictionary).get("finish_time", 0.0))
	for row in sampled:
		var time := float(row.get("time", 0.0))
		var finish := float(finishes.get(str(row.get("entry_id", "")), 0.0))
		if time <= 0.0 or time >= finish:
			return false
	return true


func _ids_ascending(rows: Array) -> bool:
	var previous := ""
	for row in rows:
		var entry_id := str(row.get("entry_id", ""))
		if previous != "" and entry_id < previous:
			return false
		previous = entry_id
	return true


func _ids_of(rows: Array) -> PackedStringArray:
	var ids := PackedStringArray()
	for row in rows:
		if row is Dictionary:
			ids.append(str((row as Dictionary).get("entry_id", "")))
	return ids


func _check_service() -> void:
	var champ := _reach_first_service()
	_expect(champ.phase == Championship.PHASE_SERVICE, "first service phase %s" % champ.phase)
	var offer := champ.offer_for(Championship.PLAYER_ID)
	var ids: Array = offer.get("card_ids", [])
	_expect(ids.size() == 3, "offer size %s" % ids.size())
	var safe_count := 0
	var safe_stat := ""
	var cards: Array[CardDef] = []
	for card_id in ids:
		var card := CATALOG.card(str(card_id))
		cards.append(card)
		if card != null and card.safe:
			safe_count += 1
			for stat_name in Entry.STAT_NAMES:
				if card.delta(stat_name) > 0:
					safe_stat = stat_name
	_expect(safe_count == 1, "safe cards %s" % safe_count)
	_expect(safe_stat == "pace", "safe stat %s" % safe_stat)
	var next_stage := CATALOG.stage_at(1)
	var picked := ServiceOffer.pick_ai(cards, next_stage)
	var independent := _independent_pick(cards, next_stage)
	_expect(picked == independent, "picker %s vs %s" % [picked, independent])
	var ai_offer := champ.offer_for("ai_1")
	var ai_cards: Array[CardDef] = []
	for card_id in ai_offer.get("card_ids", []):
		ai_cards.append(CATALOG.card(str(card_id)))
	_expect(
		str(ai_offer.get("ai_card_id", "")) == ServiceOffer.pick_ai(ai_cards, next_stage),
		"stored ai pick %s" % str(ai_offer.get("ai_card_id", ""))
	)
	_check_pick_tie()
	_check_raise_cap()
	_check_live_default_and_replacement()


func _check_pick_tie() -> void:
	var pace_card := CardDef.new()
	pace_card.id = "pace_1"
	pace_card.pace = 1
	var safe_card := CardDef.new()
	safe_card.id = "safe_pace"
	safe_card.pace = 1
	safe_card.safe = true
	var stage := StageDef.new()
	stage.pace_weight = 0.5
	var offer: Array[CardDef] = [safe_card, pace_card]
	_expect(ServiceOffer.pick_ai(offer, stage) == "pace_1", "tie break %s" % ServiceOffer.pick_ai(offer, stage))


func _check_raise_cap() -> void:
	var before := CATALOG.cards.size()
	var local := CATALOG.duplicate(true) as Catalog
	for suffix in ["a", "b", "c"]:
		var card := CardDef.new()
		card.id = "pace_%s" % suffix
		card.label = suffix
		card.pace = 1
		local.cards.append(card)
	var entry := _pip_teapot()
	entry.card_ids = ["pace_a", "pace_b", "pace_c"]
	var offer := ServiceOffer.build(local, entry, local.stage_at(1), 1, 0)
	for card in offer:
		_expect(card.id != "pace_1", "general pace card stayed in the pool")
	_expect(CATALOG.cards.size() == before, "cap test mutated the shared catalog")


func _check_live_default_and_replacement() -> void:
	var missed := _reach_first_service()
	var now := missed.observed_now()
	var guard := 0
	while missed.phase == Championship.PHASE_SERVICE and guard < 200:
		guard += 1
		now += 20.0
		missed.advance(now, 1.0)
	_expect(missed.phase == Championship.PHASE_RECAP, "live default phase %s" % missed.phase)
	_expect(missed.resume_phase == Championship.PHASE_STAGE_REVEAL, "live default resumes %s" % missed.resume_phase)
	_expect(missed.player_entry().owns("safe_pace"), "live default card %s" % str(missed.player_entry().card_ids))
	_expect(not missed.recap.is_empty() and str(missed.recap[0].get("applied_by", "")) == "default", "live default row")

	var chosen := _reach_first_service()
	var ids: Array = chosen.offer_for(Championship.PLAYER_ID).get("card_ids", [])
	_expect(ids.size() >= 2, "need two cards to test replacement")
	_expect(chosen.choose_card(str(ids[0])), "first pick")
	_expect(chosen.choose_card(str(ids[1])), "replacement pick")
	_expect(chosen.player_entry().card_ids.is_empty(), "pick applied before the window ended")
	now = chosen.observed_now()
	guard = 0
	while chosen.phase == Championship.PHASE_SERVICE and guard < 200:
		guard += 1
		now += 20.0
		chosen.advance(now, 1.0)
	_expect(chosen.phase == Championship.PHASE_STAGE_REVEAL, "chosen service phase %s" % chosen.phase)
	_expect(chosen.recap.is_empty(), "a chosen card was recorded as a default")
	_expect(chosen.player_entry().card_ids == [str(ids[1])], "owned %s" % str(chosen.player_entry().card_ids))
	_expect(chosen.stage_index == 1, "stage index after service %s" % chosen.stage_index)


func _check_catch_up() -> void:
	var champ := _reach_first_service()
	champ.phase_started_unix = 0.0
	var now := 2000.0
	champ.advance(now, 1.0)
	var player := champ.player_entry()
	_expect(player.card_ids.count("safe_pace") == 1, "catch-up cards %s" % str(player.card_ids))
	var saw_default := false
	for row in champ.recap:
		if str(row.get("applied_by", "")) == "default":
			saw_default = true
	_expect(saw_default, "catch-up did not record applied_by default")
	_expect(
		champ.open_clock_holds(now, 1.0),
		"clock behind now phase=%s resume=%s started=%s" % [champ.phase, champ.resume_phase, champ.phase_started_unix]
	)


func _check_pause_and_rewind() -> void:
	var session = _session("pause")
	session.start_draft()
	_expect(session.confirm_draft("pip", "teapot", 1000.0, 1), "pause draft")
	_expect(not session.choose_card("pace_1"), "choose_card during reveal")
	session.advance(1100.0)
	var remaining_before := session.remaining(1100.0)
	session.pause()
	session.advance(99999.0)
	_expect(session.championship.stage_index == 0, "paused advance changed stage")
	_expect(session.phase() == Championship.PHASE_STAGE_REVEAL, "paused phase %s" % session.phase())
	_expect(is_equal_approx(session.remaining(99999.0), remaining_before), "pause ate remaining time")
	session.resume(50000.0)
	_expect(is_equal_approx(session.remaining(50000.0), remaining_before), "resume did not keep the remaining time")
	session.advance(50010.0)
	_expect(session.championship.stage_index == 0, "resume jumped a stage")
	_expect(
		is_equal_approx(session.remaining(50010.0), remaining_before - 10.0),
		"remaining after resume %s" % session.remaining(50010.0)
	)

	var rewound = _session("rewind")
	rewound.start_draft()
	rewound.confirm_draft("pip", "teapot", 1000.0, 1)
	rewound.advance(500.0)
	_expect(rewound.championship.stage_index == 0, "backward clock changed stage")
	_expect(rewound.phase() == Championship.PHASE_STAGE_REVEAL, "backward phase %s" % rewound.phase())


func _check_save_round_trip() -> void:
	var session = _session("round")
	session.time_scale = 1800.0
	session.start_draft()
	_expect(session.confirm_draft("pip", "teapot", 0.0, 1), "round-trip draft")
	session.advance(1.0)
	var ids: Array = session.championship.offer_for(Championship.PLAYER_ID).get("card_ids", [])
	_expect(ids.size() >= 2, "round-trip offer")
	_expect(session.choose_card(str(ids[0])), "round-trip first pick")
	_expect(session.choose_card(str(ids[1])), "round-trip replacement")
	session.advance(2.0)
	var owned: Array[String] = session.championship.player_entry().card_ids.duplicate()
	var stats: Dictionary = session.championship.player_entry().stat_block()
	var phase_name: String = session.phase()
	var seed: int = int(session.championship.seed)
	session.muted = true
	session._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var loaded = _session("round")
	loaded.load_from_disk()
	_expect(loaded.load_error == "", "load error %s" % loaded.load_error)
	_expect(loaded.championship != null, "loaded championship is missing")
	if loaded.championship == null:
		return
	_expect(loaded.championship.seed == seed, "seed %s" % loaded.championship.seed)
	_expect(loaded.phase() == phase_name, "phase %s vs %s" % [loaded.phase(), phase_name])
	_expect(loaded.muted, "muted did not round-trip")
	_expect(is_equal_approx(loaded.time_scale, 1800.0), "time scale %s" % loaded.time_scale)
	var loaded_player: Entry = loaded.championship.player_entry()
	_expect(loaded_player.card_ids == owned, "cards %s vs %s" % [str(loaded_player.card_ids), str(owned)])
	var loaded_stats: Dictionary = loaded_player.stat_block()
	for stat_name in Entry.STAT_NAMES:
		_expect(
			int(loaded_stats[stat_name]) == int(stats[stat_name]),
			"%s %s vs %s" % [stat_name, loaded_stats[stat_name], stats[stat_name]]
		)


func _check_newer_version_untouched() -> void:
	var path := "user://checks/newer.json"
	var raw := "{\r\n  \"version\": 99,\r\n  \"marker\": \"do-not-touch\"\r\n}\r\n"
	_write_text(path, raw)
	var before := FileAccess.get_file_as_bytes(path)
	var probed := SaveGame.load_from_file(path)
	_expect(str(probed.get("status", "")) == SaveGame.STATUS_NEWER, "newer status %s" % probed.get("status", ""))
	var session = _session("newer")
	session.save_path = path
	session.load_from_disk()
	_expect(session.load_error.contains("99"), "load_error %s" % session.load_error)
	_expect(session.championship == null, "newer save created a championship")
	session.save_now()
	session._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var after := FileAccess.get_file_as_bytes(path)
	_expect(before == after, "version 99 file was modified")


func _check_older_version_backed_up() -> void:
	var path := "user://checks/older.json"
	var raw := "{\"version\":0,\"championship\":{\"seed\":5}}\n"
	_write_text(path, raw)
	var original := FileAccess.get_file_as_bytes(path)
	var session = _session("older")
	session.save_path = path
	session.load_from_disk()
	var backup := FileAccess.get_file_as_bytes(SaveGame.backup_path_for(path))
	_expect(backup == original, "older save backup does not match the original bytes")
	_expect(session.championship == null, "older save stayed in progress")
	_expect(session.phase() == Championship.PHASE_IDLE, "older phase %s" % session.phase())
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect(parsed is Dictionary, "migrated save is not json")
	if parsed is Dictionary:
		_expect(int((parsed as Dictionary).get("version", -1)) == 1, "migrated version")
		_expect((parsed as Dictionary).get("championship", "missing") == null, "migrated championship")


func _check_championship_runs_to_the_end() -> void:
	var session = _session("full")
	session.start_draft()
	_expect(session.confirm_draft("pip", "teapot", 0.0, 1), "full draft")
	var now := 0.0
	var guard := 0
	var saw_last_service := false
	while session.phase() != Championship.PHASE_FINISHED and session.phase() != Championship.PHASE_IDLE and guard < 3000:
		guard += 1
		if session.phase() == Championship.PHASE_RECAP:
			session.dismiss_recap()
			continue
		if session.phase() == Championship.PHASE_SERVICE:
			if session.championship.stage_index >= 7:
				saw_last_service = true
			var ids: Array = session.championship.offer_for(Championship.PLAYER_ID).get("card_ids", [])
			if not ids.is_empty():
				session.choose_card(str(ids[0]))
		now += 20.0
		session.advance(now)
	_expect(not saw_last_service, "stage 8 opened a service")
	_expect(session.phase() == Championship.PHASE_FINISHED, "full run ended in %s after %s steps" % [session.phase(), guard])
	if session.championship == null:
		return
	_expect(session.championship.results.size() == 8, "committed stages %s" % session.championship.results.size())
	var points := 0
	for stage_result in session.championship.results:
		var rows: Array = stage_result.get("rows", [])
		_expect(rows.size() == 8, "a stage did not rank 8 entries")
		for row in rows:
			points += int(row.get("points", 0))
	_expect(points == 39 * 8, "points total %s" % points)
	var table: Array = session.championship.standings()
	_expect(table.size() == 8, "standings size %s" % table.size())


func _reach_first_service() -> Championship:
	var champ := Championship.new(CATALOG)
	champ.start_draft()
	champ.confirm_draft("pip", "teapot", 0.0, 1)
	champ.advance(10.0, 180.0)
	return champ


func _independent_pick(cards: Array[CardDef], stage: StageDef) -> String:
	var best_id := ""
	var best_score := 0.0
	var found := false
	for card in cards:
		var score := (
			float(card.pace) * stage.pace_weight
			+ float(card.grip) * stage.grip_weight
			+ float(card.jump) * stage.jump_weight
			+ float(card.reliability) * stage.reliability_weight
			+ float(card.focus) * stage.focus_weight
		)
		if not found or score > best_score or (is_equal_approx(score, best_score) and card.id < best_id):
			found = true
			best_score = score
			best_id = card.id
	return best_id


func _player_row(stage_result: Dictionary) -> Dictionary:
	var rows: Array = stage_result.get("rows", [])
	for row in rows:
		if str(row.get("entry_id", "")) == Championship.PLAYER_ID:
			return row
	return {}


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_expect(false, "could not write %s" % path)
		return
	file.store_string(text)
	file.close()


func _cleanup() -> void:
	var checks := DirAccess.open("user://checks")
	if checks == null:
		return
	checks.list_dir_begin()
	var file_name := checks.get_next()
	while file_name != "":
		if not checks.current_is_dir():
			checks.remove(file_name)
		file_name = checks.get_next()
	checks.list_dir_end()
	var root := DirAccess.open("user://")
	if root != null:
		root.remove("checks")
	for session in _sessions:
		if is_instance_valid(session):
			session.free()
	_sessions.clear()
