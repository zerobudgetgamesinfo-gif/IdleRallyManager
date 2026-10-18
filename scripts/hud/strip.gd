class_name HudStrip
extends Control
## Championship text for the companion strip.
## Frees the previous phase block before instancing the next one.
## The clock timer runs only during a reveal or a service, and stops while paused.

const DraftPlaceholder = preload("res://scripts/hud/draft_placeholder.gd")

const TEXT_COLOR := Color(0.973, 0.941, 0.878, 1.0)
const FONT_SIZE := 14
const SETTINGS_CLEARANCE := 104.0

var _host: Control
var _timer: Timer
var _clock_label: Label
var _reveal_label: Label
var _rebuild_queued := false
var _debug_offset := 0.0
var _results_before_advance := 0
var _skipped_from := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Session.phase_changed.connect(_queue_rebuild)
	Session.recap_ready.connect(_on_recap_ready)
	Session.championship_finished.connect(_queue_rebuild)
	resized.connect(_on_resized)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_on_tick()
	if not _rebuild_queued:
		_rebuild_now()


func now_unix() -> float:
	return Time.get_unix_time_from_system() + _debug_offset


func catch_clock() -> void:
	_advance_clock()
	if _rebuild_queued:
		return
	_update_dynamic_labels()
	_sync_timer()


func notify_clock() -> void:
	if _timer != null and not _timer.is_stopped():
		_timer.stop()
	_update_dynamic_labels()
	_sync_timer()


## Jump four stage blocks ahead on this strip's clock.
## Later ticks keep the same offset so the countdown continues from the jump.
## Quitting persists those timestamps; abandon first if the jump was only for the recap.
func skip_ahead() -> void:
	var champ := Session.championship
	if champ != null and champ.pause_started_unix != null:
		Session.resume(now_unix())
	var scale := maxf(Session.time_scale, 0.001)
	var block := float(Timing.STAGE_REVEAL_SEC + Timing.SERVICE_SEC)
	_debug_offset += block * 4.0 / scale
	if _timer != null and not _timer.is_stopped():
		_timer.stop()
	_on_tick()


func _on_resized() -> void:
	if _host == null:
		return
	var peek := _host.get_node_or_null("Standings") as Control
	if peek == null:
		return
	var height := _peek_height()
	if is_equal_approx(peek.custom_minimum_size.y, height):
		return
	peek.custom_minimum_size.y = height


func _on_tick() -> void:
	_update_dynamic_labels()
	_advance_clock()
	if _rebuild_queued:
		return
	_update_dynamic_labels()
	_sync_timer()


func _advance_clock() -> void:
	if not _clock_is_running():
		return
	var champ := Session.championship
	_results_before_advance = 0 if champ == null else champ.results.size()
	Session.advance(now_unix())


func _on_recap_ready() -> void:
	_skipped_from = _results_before_advance
	_queue_rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_rebuild_now")


func _rebuild_now() -> void:
	_rebuild_queued = false
	_clock_label = null
	_reveal_label = null
	_free_host()
	var host := VBoxContainer.new()
	host.name = "PhaseHost"
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	host.clip_contents = true
	host.add_theme_constant_override("separation", 2)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(_build_header())
	var body := _build_body()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_child(body)
	if _shows_standings_peek():
		host.add_child(_build_standings_peek())
	_host = host
	add_child(host)
	_update_dynamic_labels()
	_sync_timer()
	Dock.refresh_hit_polygon()


func _free_host() -> void:
	if _host == null:
		return
	remove_child(_host)
	_host.queue_free()
	_host = null


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.name = "Header"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var title := _label(_phase_heading())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	row.add_child(title)
	var phase := Session.phase()
	if phase == Championship.PHASE_STAGE_REVEAL or phase == Championship.PHASE_SERVICE:
		_clock_label = _label(_clock_text())
		_clock_label.name = "Clock"
		_clock_label.custom_minimum_size = Vector2(96, 0)
		_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(_clock_label)
	var clearance := Control.new()
	clearance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clearance.custom_minimum_size = Vector2(SETTINGS_CLEARANCE, 0)
	row.add_child(clearance)
	return row


func _build_body() -> Control:
	var phase := Session.phase()
	if phase == Championship.PHASE_DRAFT:
		return _build_draft()
	if phase == Championship.PHASE_STAGE_REVEAL:
		return _build_reveal()
	if phase == Championship.PHASE_SERVICE:
		return _build_service()
	if phase == Championship.PHASE_RECAP:
		return _build_recap()
	if phase == Championship.PHASE_FINISHED:
		return _build_finished()
	return _build_idle()


func _build_idle() -> Control:
	var box := VBoxContainer.new()
	box.name = "Idle"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	var title := _label("Idle Rally Manager")
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	if Session.load_error != "":
		var error := _label(Session.load_error)
		error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(error)
	var start := _button("Start championship")
	start.custom_minimum_size = Vector2(180, 28)
	start.pressed.connect(_on_start_pressed)
	box.add_child(start)
	return box


func _build_draft() -> Control:
	var draft := DraftPlaceholder.new()
	draft.clock = Callable(self, "now_unix")
	draft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	draft.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return draft


func _build_reveal() -> Control:
	var box := VBoxContainer.new()
	box.name = "Reveal"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_label = _label(_reveal_line())
	_reveal_label.name = "RevealLine"
	box.add_child(_reveal_label)
	return box


func _build_service() -> Control:
	var box := VBoxContainer.new()
	box.name = "Service"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	box.add_child(_label("Choice waiting"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var champ := Session.championship
	var offer: Dictionary = {} if champ == null else champ.offer_for(Championship.PLAYER_ID)
	var chosen := str(offer.get("chosen_card_id", ""))
	var ids: Variant = offer.get("card_ids", [])
	if ids is Array:
		for raw_id in ids:
			var card_id := str(raw_id)
			var button := _button(card_id)
			if card_id == chosen and card_id != "":
				button.text = "%s *" % card_id
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.custom_minimum_size = Vector2(0, 28)
			button.pressed.connect(_on_card_pressed.bind(card_id))
			row.add_child(button)
	box.add_child(row)
	return box


func _build_recap() -> Control:
	var box := VBoxContainer.new()
	box.name = "Recap"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	var scroll := _scroll()
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lines := _recap_lines()
	if lines.is_empty():
		lines.append("Caught up")
	for line in lines:
		var row := _label(line)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(row)
	scroll.add_child(list)
	box.add_child(scroll)
	var dismiss := _button("Dismiss")
	dismiss.pressed.connect(_on_dismiss_recap)
	box.add_child(dismiss)
	return box


func _build_finished() -> Control:
	var box := VBoxContainer.new()
	box.name = "Finished"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	var scroll := _scroll()
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var champ := Session.championship
	if champ != null:
		for row in champ.standings():
			list.add_child(_label(_finished_line(row)))
	scroll.add_child(list)
	box.add_child(scroll)
	var dismiss := _button("Dismiss")
	dismiss.pressed.connect(_on_dismiss_finished)
	box.add_child(dismiss)
	return box


func _build_standings_peek() -> Control:
	var peek := RichTextLabel.new()
	peek.name = "Standings"
	peek.bbcode_enabled = false
	peek.fit_content = false
	peek.scroll_active = false
	peek.selection_enabled = false
	peek.shortcut_keys_enabled = false
	peek.mouse_filter = Control.MOUSE_FILTER_IGNORE
	peek.focus_mode = Control.FOCUS_NONE
	peek.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	peek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	peek.custom_minimum_size = Vector2(0, _peek_height())
	peek.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	peek.add_theme_color_override("default_color", TEXT_COLOR)
	peek.text = _standings_text()
	return peek


func _peek_height() -> float:
	if Dock.get_preset() == Dock.PRESET_COMPACT:
		return 20.0
	return 40.0


func _shows_standings_peek() -> bool:
	var phase := Session.phase()
	return (
		phase == Championship.PHASE_STAGE_REVEAL
		or phase == Championship.PHASE_SERVICE
		or phase == Championship.PHASE_RECAP
	)


func _scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.focus_mode = Control.FOCUS_NONE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 24)
	return scroll


func _phase_heading() -> String:
	var champ := Session.championship
	var total := Session.CATALOG.stage_order.size()
	var phase := Session.phase()
	if phase == Championship.PHASE_IDLE:
		return "Idle"
	if phase == Championship.PHASE_DRAFT:
		return "Draft"
	if phase == Championship.PHASE_RECAP:
		return "Recap"
	if phase == Championship.PHASE_FINISHED:
		return "Finished"
	if champ == null:
		return phase
	var number := "%d/%d  %s" % [champ.stage_index + 1, total, _stage_name(champ.stage_index)]
	if phase == Championship.PHASE_STAGE_REVEAL:
		return "Reveal %s" % number
	if phase == Championship.PHASE_SERVICE:
		return "Service after %s" % number
	return phase


## Position and gap are the solved order. Phase 4 interpolates the gap.
## Points count committed stages only; the open stage's points land when the reveal ends.
func _reveal_line() -> String:
	var champ := Session.championship
	if champ == null:
		return "Result pending"
	var rows: Array[Dictionary] = []
	for entry in champ.entries:
		var result := champ.stage_result(entry.id)
		if result == null:
			continue
		rows.append({
			"entry_id": entry.id,
			"finish_time": result.finish_time,
		})
	if rows.is_empty():
		return "Result pending"
	var ranked := Standings.rank_stage(rows)
	var player_pos := 0
	var player_time := 0.0
	var ahead_time := -1.0
	for row in ranked:
		if str(row.get("entry_id", "")) == Championship.PLAYER_ID:
			player_pos = int(row.get("position", 0))
			player_time = float(row.get("finish_time", 0.0))
			break
		ahead_time = float(row.get("finish_time", 0.0))
	if player_pos <= 0:
		return "Result pending"
	var gap := "lead"
	if player_pos > 1:
		gap = "+%.1fs" % (player_time - ahead_time)
	var clock := _format_mmss(player_time * _reveal_fraction())
	return "P%d  %s  %s  %d pts" % [player_pos, gap, clock, _player_points()]


func _reveal_fraction() -> float:
	var duration := float(Timing.STAGE_REVEAL_SEC)
	if duration <= 0.0:
		return 0.0
	var left := Session.remaining(now_unix())
	return clampf((duration - left) / duration, 0.0, 1.0)


func _player_points() -> int:
	var champ := Session.championship
	if champ == null:
		return 0
	for row in champ.standings():
		if str(row.get("entry_id", "")) == Championship.PLAYER_ID:
			return int(row.get("points", 0))
	return 0


func _standings_text() -> String:
	var champ := Session.championship
	if champ == null:
		return ""
	var parts: PackedStringArray = []
	for row in champ.standings():
		parts.append("%d %s %d" % [
			int(row.get("position", 0)),
			_short_name(str(row.get("entry_id", ""))),
			int(row.get("points", 0)),
		])
	return "  ".join(parts)


func _finished_line(row: Dictionary) -> String:
	return "%d  %s  %d pts  %s" % [
		int(row.get("position", 0)),
		_entry_name(str(row.get("entry_id", ""))),
		int(row.get("points", 0)),
		_format_mmss(float(row.get("total_time", 0.0))),
	]


func _recap_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var champ := Session.championship
	if champ == null:
		return lines
	var covered := {}
	if _skipped_from >= 0:
		for index in range(_skipped_from, champ.results.size()):
			var result: Dictionary = champ.results[index]
			var stage_index := int(result.get("stage_index", -1))
			covered[stage_index] = true
			lines.append(_result_line(result))
	for row in champ.recap:
		var stage_index := int(row.get("stage_index", -1))
		if covered.has(stage_index):
			continue
		lines.append(_stored_row_line(row))
		covered[stage_index] = true
	return lines


func _result_line(result: Dictionary) -> String:
	var stage_index := int(result.get("stage_index", -1))
	var card := _recap_card(stage_index)
	return _recap_text(
		stage_index,
		_position_in_result(result, Championship.PLAYER_ID),
		str(card.get("card_id", "")),
		str(card.get("applied_by", ""))
	)


func _stored_row_line(row: Dictionary) -> String:
	var stage_index := int(row.get("stage_index", -1))
	return _recap_text(
		stage_index,
		_player_position_on_stage(stage_index),
		str(row.get("card_id", "")),
		str(row.get("applied_by", ""))
	)


func _recap_text(stage_index: int, position: int, card_id: String, applied_by: String) -> String:
	var card := card_id if card_id != "" else "-"
	var applied := applied_by if applied_by != "" else "-"
	var pos := "P-" if position <= 0 else "P%d" % position
	return "%s  %s  %s  %s" % [_stage_name(stage_index), pos, card, applied]


func _recap_card(stage_index: int) -> Dictionary:
	var champ := Session.championship
	if champ == null:
		return {}
	for row in champ.recap:
		if int(row.get("stage_index", -1)) == stage_index:
			return row
	return {}


func _player_position_on_stage(stage_index: int) -> int:
	var champ := Session.championship
	if champ == null:
		return 0
	for result in champ.results:
		if int(result.get("stage_index", -1)) != stage_index:
			continue
		return _position_in_result(result, Championship.PLAYER_ID)
	return 0


func _position_in_result(result: Dictionary, entry_id: String) -> int:
	var rows: Variant = result.get("rows", [])
	if rows is Array:
		for row in rows:
			if row is Dictionary and str((row as Dictionary).get("entry_id", "")) == entry_id:
				return int((row as Dictionary).get("position", 0))
	return 0


func _stage_name(stage_index: int) -> String:
	var stage := Session.CATALOG.stage_at(stage_index)
	if stage != null and stage.display_name != "":
		return stage.display_name
	return "Stage %d" % (stage_index + 1)


func _short_name(entry_id: String) -> String:
	var champ := Session.championship
	if champ == null:
		return entry_id
	var entry := champ.find_entry(entry_id)
	if entry == null:
		return entry_id
	if entry.is_player:
		return "You"
	var driver := Session.CATALOG.driver(entry.driver_id)
	var car := Session.CATALOG.car(entry.car_id)
	var driver_name := entry.driver_id
	if driver != null and driver.display_name != "":
		driver_name = driver.display_name.get_slice(" ", 0)
	var car_name := entry.car_id if car == null else car.display_name
	return "%s %s" % [driver_name, car_name]


func _entry_name(entry_id: String) -> String:
	var champ := Session.championship
	if champ == null:
		return entry_id
	var entry := champ.find_entry(entry_id)
	if entry == null:
		return entry_id
	var driver := Session.CATALOG.driver(entry.driver_id)
	var car := Session.CATALOG.car(entry.car_id)
	var driver_name := entry.driver_id if driver == null else driver.display_name
	var car_name := entry.car_id if car == null else car.display_name
	if entry.is_player:
		return "%s / %s (you)" % [driver_name, car_name]
	return "%s / %s" % [driver_name, car_name]


func _clock_text() -> String:
	var text := "%s left" % _format_mmss(Session.remaining(now_unix()))
	if _is_paused():
		text += "  paused"
	return text


func _format_mmss(seconds: float) -> String:
	var total := maxi(floori(seconds), 0)
	return "%d:%02d" % [int(total / 60.0), total % 60]


func _update_dynamic_labels() -> void:
	if _clock_label != null:
		_set_text(_clock_label, _clock_text())
	if _reveal_label != null and Session.phase() == Championship.PHASE_STAGE_REVEAL:
		_set_text(_reveal_label, _reveal_line())


func _set_text(label: Label, text: String) -> void:
	if label.text == text:
		return
	label.text = text


func _sync_timer() -> void:
	if _timer == null:
		return
	if not _clock_is_running():
		if not _timer.is_stopped():
			_timer.stop()
		return
	if not _timer.is_stopped():
		return
	_timer.wait_time = _seconds_until_next_label()
	_timer.start()


func _seconds_until_next_label() -> float:
	var scale := maxf(Session.time_scale, 0.001)
	var left := Session.remaining(now_unix())
	var into := left - floorf(left)
	if into < 0.001:
		into = 1.0
	return clampf(into / scale, 0.05, 1.0)


func _clock_is_running() -> bool:
	var phase := Session.phase()
	if phase != Championship.PHASE_STAGE_REVEAL and phase != Championship.PHASE_SERVICE:
		return false
	return not _is_paused()


func _is_paused() -> bool:
	var champ := Session.championship
	return champ != null and champ.pause_started_unix != null


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	return button


func _on_start_pressed() -> void:
	Session.start_draft()


func _on_card_pressed(card_id: String) -> void:
	if Session.choose_card(card_id):
		_queue_rebuild()


func _on_dismiss_recap() -> void:
	Session.dismiss_recap()


func _on_dismiss_finished() -> void:
	Session.dismiss_finished()
