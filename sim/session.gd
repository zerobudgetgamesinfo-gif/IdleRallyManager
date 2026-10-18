extends Node
## Championship state, wall clock, and user://save.json. Draws nothing.
##
## Solvers never read the clock. advance, confirm_draft, and resume take now_unix.
## pause freezes at the last one of those timestamps, or the system clock if none arrived yet.

signal phase_changed
signal choice_applied
signal recap_ready
signal championship_finished

const CATALOG: Catalog = preload("res://data/catalog.tres")

var time_scale := 1.0
var muted := false
var load_error := ""
var championship: Championship
var save_path := SaveGame.DEFAULT_PATH

var _persist := true
var _writes_blocked := false


func _ready() -> void:
	if _skip_autoload_persistence():
		_persist = false
		return
	load_from_disk()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()


func phase() -> String:
	if championship == null:
		return Championship.PHASE_IDLE
	return championship.phase


func start_draft() -> void:
	if championship != null and championship.phase != Championship.PHASE_IDLE:
		return
	championship = Championship.new(CATALOG)
	if not championship.start_draft():
		return
	phase_changed.emit()
	save_now()


func confirm_draft(driver_id: String, car_id: String, now_unix: float, fixed_seed: int = -1) -> bool:
	if championship == null or championship.phase != Championship.PHASE_DRAFT:
		return false
	if not championship.confirm_draft(driver_id, car_id, now_unix, fixed_seed):
		return false
	phase_changed.emit()
	save_now()
	return true


func advance(now_unix: float) -> void:
	if championship == null:
		return
	_emit_outcome(championship.advance(now_unix, time_scale))


func choose_card(card_id: String) -> bool:
	if championship == null or not championship.choose_card(card_id):
		return false
	save_now()
	return true


func pause() -> void:
	if championship == null:
		return
	var mark := championship.observed_now()
	if mark < 0.0:
		mark = Time.get_unix_time_from_system()
	if championship.pause_at(mark):
		save_now()


func resume(now_unix: float) -> void:
	if championship == null or not championship.resume(now_unix, time_scale):
		return
	save_now()


func dismiss_recap() -> void:
	if championship == null or championship.phase != Championship.PHASE_RECAP:
		return
	var destination := championship.dismiss_recap()
	phase_changed.emit()
	if destination == Championship.PHASE_FINISHED:
		championship_finished.emit()
	save_now()


func dismiss_finished() -> void:
	if championship == null or championship.phase != Championship.PHASE_FINISHED:
		return
	championship = null
	phase_changed.emit()
	save_now()


func abandon() -> void:
	if championship == null:
		return
	championship = null
	phase_changed.emit()
	save_now()


func remaining(now_unix: float) -> float:
	if championship == null:
		return 0.0
	return championship.remaining(now_unix, time_scale)


func set_time_scale(value: float) -> void:
	if value <= 0.0 or is_equal_approx(value, time_scale):
		return
	if championship != null:
		championship.retarget_time_scale(time_scale, value)
	time_scale = value
	save_now()


func set_muted(value: bool) -> void:
	if value == muted:
		return
	muted = value
	save_now()


func save_now() -> void:
	if not _persist or _writes_blocked or save_path == "":
		return
	if DisplayServer.get_name() == "headless" and save_path == SaveGame.DEFAULT_PATH:
		push_error("Session refused to write the player save from a headless run.")
		return
	var stored: Variant = null
	if championship != null:
		stored = championship.to_dictionary()
	var err := SaveGame.write_file(save_path, {"time_scale": time_scale, "muted": muted}, stored)
	if err != OK:
		push_error("Session failed to save: %s" % error_string(err))


func load_from_disk() -> void:
	var loaded := SaveGame.load_from_file(save_path)
	var status := str(loaded.get("status", SaveGame.STATUS_MISSING))
	if status == SaveGame.STATUS_NEWER or status == SaveGame.STATUS_INVALID:
		_writes_blocked = true
		load_error = str(loaded.get("error", ""))
		championship = null
		return
	_writes_blocked = false
	load_error = ""
	if status == SaveGame.STATUS_OLDER:
		load_error = str(loaded.get("error", ""))
		championship = null
		time_scale = 1.0
		muted = false
		save_now()
		return
	if status != SaveGame.STATUS_OK:
		return
	_apply_settings(loaded.get("settings", {}))
	var stored: Variant = loaded.get("championship", null)
	if stored is Dictionary:
		championship = Championship.from_dictionary(stored, CATALOG)
		if championship.phase == Championship.PHASE_IDLE:
			championship = null
	else:
		championship = null


func _apply_settings(settings: Variant) -> void:
	if not settings is Dictionary:
		return
	var data := settings as Dictionary
	var scale: Variant = data.get("time_scale", time_scale)
	if (scale is float or scale is int) and float(scale) > 0.0:
		time_scale = float(scale)
	var mute_flag: Variant = data.get("muted", muted)
	if mute_flag is bool:
		muted = mute_flag


func _emit_outcome(outcome: Dictionary) -> void:
	var applications: Variant = outcome.get("player_applications", [])
	if applications is Array:
		for _card_id in applications:
			choice_applied.emit()
	if bool(outcome.get("entered_recap", false)):
		recap_ready.emit()
	elif bool(outcome.get("entered_finished", false)):
		championship_finished.emit()
	if bool(outcome.get("phase_changed", false)):
		phase_changed.emit()
		save_now()


func _skip_autoload_persistence() -> bool:
	if not is_inside_tree():
		return false
	if DisplayServer.get_name() != "headless":
		return false
	return str(get_path()) == "/root/Session"
