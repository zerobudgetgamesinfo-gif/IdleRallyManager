class_name HudStrip
extends Control
## Championship text for the companion strip.
## Frees the previous phase block before instancing the next one.
## The clock timer runs only during a reveal or a service, and stops while paused.

const DraftViewScene = preload("res://scenes/draft/draft_view.tscn")
const ServiceViewScene = preload("res://scenes/service/service_view.tscn")
const StageViewScene = preload("res://scenes/stage/stage_view.tscn")
const EMBLEM: Texture2D = preload("res://ui/art/emblem.svg")

const TEXT_COLOR := Palette.CREAM
const FONT_SIZE := 14
const FONT_SIZE_SIDE := 12
const SETTINGS_CLEARANCE := 104.0
const SIDE_STAGE_HEIGHT := 96.0
const SIDE_ROW_PORTRAIT := 22.0
const TICKER_ROW_HEIGHT := 34.0
const TICKER_PORTRAIT := 28.0
const POPOVER_FADE_SEC := 0.2

const INTRO_LINES: PackedStringArray = [
	"A rally sits on your desktop",
	"Choices happen between stages",
	"You can step away",
]

var _host: Control
var _timer: Timer
var _clock_label: Label
var _reveal_label: Label
var _progress_fill: ColorRect
var _rebuild_queued := false
var _debug_offset := 0.0
var _results_before_advance := 0
var _skipped_from := -1
var _intro_shown := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Session.phase_changed.connect(_queue_rebuild)
	Session.recap_ready.connect(_on_recap_ready)
	Session.championship_finished.connect(_queue_rebuild)
	Dock.edge_changed.connect(_queue_rebuild)
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
	if _host == null or Dock.is_side():
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
	_progress_fill = null
	_sync_dock_focus()
	_free_host()
	var host := VBoxContainer.new()
	host.name = "PhaseHost"
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	host.clip_contents = true
	host.add_theme_constant_override("separation", 2)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if Session.phase() != Championship.PHASE_IDLE:
		_intro_shown = false
	if Dock.is_ticker():
		_build_ticker(host)
	else:
		_build_full(host)
	_host = host
	add_child(host)
	_update_dynamic_labels()
	_sync_timer()
	Dock.refresh_hit_polygon()


func _build_full(host: VBoxContainer) -> void:
	host.add_child(_build_header())
	var body := _build_body()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var phase := Session.phase()
	if Dock.is_side() and (phase == Championship.PHASE_STAGE_REVEAL or phase == Championship.PHASE_SERVICE):
		# The column below the scene belongs to the standings.
		body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	host.add_child(body)
	if _shows_standings_peek():
		host.add_child(_build_standings_peek())


## Ticker: one slim row at the bottom. Draft, service, recap and finished keep their body behind a chip
## and show it above the row only while the panel is open.
func _build_ticker(host: VBoxContainer) -> void:
	var phase := Session.phase()
	var open := _is_panel_phase(phase) and Dock.is_panel_open()
	if open:
		var body := _build_body()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		host.add_child(body)
		_fade_in(host)
	else:
		var gap := Control.new()
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		host.add_child(gap)
	host.add_child(_build_ticker_row(phase, open))


func _build_ticker_row(phase: String, open: bool) -> Control:
	var row := HBoxContainer.new()
	row.name = "Ticker"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0, TICKER_ROW_HEIGHT)
	row.add_theme_constant_override("separation", 8)
	if phase == Championship.PHASE_STAGE_REVEAL:
		var reveal := _build_reveal()
		reveal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(reveal)
	elif phase == Championship.PHASE_IDLE:
		_fill_idle_ticker(row)
	else:
		var title := _label(_phase_heading())
		title.theme_type_variation = &"TitleLabel"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.clip_text = true
		row.add_child(title)
	if phase == Championship.PHASE_STAGE_REVEAL or phase == Championship.PHASE_SERVICE:
		_clock_label = _label(_clock_text())
		_clock_label.name = "Clock"
		_clock_label.custom_minimum_size = Vector2(72, 0)
		_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(_clock_label)
	if _is_panel_phase(phase):
		row.add_child(_panel_chip(phase, open))
	var clearance := Control.new()
	clearance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clearance.custom_minimum_size = Vector2(SETTINGS_CLEARANCE, 0)
	row.add_child(clearance)
	return row


## Emblem and wordmark. The wordmark is a Label in the title font, so it follows the theme.
func _title_lockup(font_size: int, emblem_height: float) -> Control:
	var lockup := HBoxContainer.new()
	lockup.name = "Title"
	lockup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lockup.add_theme_constant_override("separation", 8)
	var emblem := TextureRect.new()
	emblem.texture = EMBLEM
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.custom_minimum_size = Vector2(emblem_height * 72.0 / 44.0, emblem_height)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lockup.add_child(emblem)
	var label := _label("Idle Rally Manager")
	label.theme_type_variation = &"TitleLabel"
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Palette.AMBER_LIGHT)
	label.add_theme_constant_override("outline_size", 4)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	lockup.add_child(label)
	return lockup


func _fill_idle_ticker(row: HBoxContainer) -> void:
	var show_intro := _intro_shown or not Dock.has_seen_intro()
	if show_intro:
		_intro_shown = true
		Dock.mark_intro_seen()
	var title: Control
	if show_intro:
		var intro := _label("  ·  ".join(INTRO_LINES))
		intro.name = "Intro"
		intro.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		intro.clip_text = true
		title = intro
	else:
		title = _title_lockup(18, 28.0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var start := _button("Start championship")
	start.custom_minimum_size = Vector2(160, 0)
	start.accessibility_name = "Start championship"
	start.accessibility_description = "Opens the draft: pick one driver and one car."
	start.pressed.connect(_on_start_pressed)
	row.add_child(start)
	var roster := HBoxContainer.new()
	roster.name = "Roster"
	roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roster.add_theme_constant_override("separation", 3)
	for driver in Session.CATALOG.drivers:
		if driver == null or driver.portrait == null or driver.unlock_reputation > 0:
			continue
		roster.add_child(_portrait_rect(driver.portrait, TICKER_PORTRAIT))
	row.add_child(roster)


func _panel_chip(phase: String, open: bool) -> Button:
	var chip := _button("Close ▾" if open else _chip_text(phase))
	chip.name = "PanelChip"
	chip.custom_minimum_size = Vector2(120, 0)
	if not open:
		var accent := Style.raised(Palette.AMBER_DEEP, 8, Palette.AMBER_LIGHT, 3)
		accent.content_margin_left = 10
		accent.content_margin_right = 10
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			chip.add_theme_stylebox_override(state, accent)
	chip.accessibility_name = "Close panel" if open else _chip_text(phase)
	chip.accessibility_description = "Opens or closes the panel above the ticker."
	chip.pressed.connect(_on_chip_pressed)
	return chip


func _chip_text(phase: String) -> String:
	match phase:
		Championship.PHASE_DRAFT:
			return "Pick team ▸"
		Championship.PHASE_SERVICE:
			return "Service ▸"
		Championship.PHASE_RECAP:
			return "Recap ▸"
	return "Result ▸"


func _is_panel_phase(phase: String) -> bool:
	return (
		phase == Championship.PHASE_DRAFT
		or phase == Championship.PHASE_SERVICE
		or phase == Championship.PHASE_RECAP
		or phase == Championship.PHASE_FINISHED
	)


func _on_chip_pressed() -> void:
	Dock.set_panel_open(not Dock.is_panel_open())
	_queue_rebuild()


## One short fade when the panel opens. The tween ends on its own, so idle stays still.
func _fade_in(node: CanvasItem) -> void:
	node.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 1.0, POPOVER_FADE_SEC)


func _sync_dock_focus() -> void:
	var phase := Session.phase()
	Dock.set_panel_phase(
		phase == Championship.PHASE_DRAFT
		or phase == Championship.PHASE_SERVICE
		or phase == Championship.PHASE_RECAP
		or phase == Championship.PHASE_FINISHED,
		phase == Championship.PHASE_DRAFT
	)


func _free_host() -> void:
	if _host == null:
		return
	remove_child(_host)
	_host.queue_free()
	_host = null


func _build_header() -> Control:
	if Dock.is_side():
		return _build_side_header()
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


## The column has no room for a title beside the clock, so they stack.
func _build_side_header() -> Control:
	var column := VBoxContainer.new()
	column.name = "Header"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _label(_phase_heading())
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	var phase := Session.phase()
	if phase == Championship.PHASE_STAGE_REVEAL or phase == Championship.PHASE_SERVICE:
		_clock_label = _label(_clock_text())
		_clock_label.name = "Clock"
		column.add_child(_clock_label)
	return column


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


## Idle is a still picture: the roster, a Start button, and on the very first launch three lines of copy.
## The intro flag lives in window.cfg (once per machine), not in the championship save.
func _build_idle() -> Control:
	var show_intro := _intro_shown or not Dock.has_seen_intro()
	if show_intro:
		_intro_shown = true
		Dock.mark_intro_seen()
	var side := Dock.is_side()
	var box: BoxContainer = VBoxContainer.new() if side else HBoxContainer.new()
	box.name = "Idle"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 12 if not side else 6)

	var text := VBoxContainer.new()
	text.name = "IdleText"
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 4)
	if show_intro:
		var intro := _label("\n".join(INTRO_LINES))
		intro.name = "Intro"
		intro.add_theme_font_size_override("font_size", FONT_SIZE_SIDE if side else 13)
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(intro)
	else:
		text.add_child(_title_lockup(20, 44.0))
	if Session.load_error != "":
		var error := _label(Session.load_error)
		error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(error)
	var start := _button("Start championship")
	start.custom_minimum_size = Vector2(0 if side else 180, 28)
	start.accessibility_name = "Start championship"
	start.accessibility_description = "Opens the draft: pick one driver and one car."
	start.pressed.connect(_on_start_pressed)
	if side:
		text.add_child(start)
		box.add_child(_idle_roster(true))
		box.add_child(text)
	else:
		start.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(text)
		box.add_child(start)
		box.add_child(_idle_roster(false))
	return box


## The starter drivers, round portraits only. Transparent corners stay inside the strip.
func _idle_roster(wrap: bool) -> Control:
	var row: Container = HFlowContainer.new() if wrap else HBoxContainer.new()
	row.name = "Roster"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	var edge := 48.0 if Dock.get_preset() == Dock.PRESET_COZY else 36.0
	for driver in Session.CATALOG.drivers:
		if driver == null or driver.portrait == null or driver.unlock_reputation > 0:
			continue
		row.add_child(_portrait_rect(driver.portrait, edge))
	return row


func _portrait_rect(texture: Texture2D, edge: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(edge, edge)
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


func _build_draft() -> Control:
	var draft := DraftViewScene.instantiate() as DraftView
	draft.clock = Callable(self, "now_unix")
	draft.vertical = Dock.is_side()
	draft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	draft.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return draft


func _build_reveal() -> Control:
	var layer := Control.new()
	layer.name = "Reveal"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.custom_minimum_size = Vector2(0, 28 if Dock.is_ticker() else 48)
	var view := StageViewScene.instantiate() as StageView
	view.clock = Callable(self, "now_unix")
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(view)
	_reveal_label = _label(_reveal_line())
	_reveal_label.name = "RevealLine"
	_reveal_label.add_theme_constant_override("outline_size", 4)
	_reveal_label.add_theme_color_override("font_outline_color", Color(0.12, 0.09, 0.07, 0.9))
	if Dock.is_side():
		# The HUD line sits above a fixed band of scene, with the standings under both.
		var column := VBoxContainer.new()
		column.name = "RevealColumn"
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 2)
		_reveal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(_reveal_label)
		layer.custom_minimum_size = Vector2(0, SIDE_STAGE_HEIGHT)
		column.add_child(layer)
		return column
	# A dark chip keeps the readout legible over every surface; a thin track shows stage progress.
	var chip := PanelContainer.new()
	chip.name = "RevealChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", _reveal_chip_style())
	chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	chip.offset_left = 4.0
	chip.offset_top = 2.0
	chip.add_child(_reveal_label)
	layer.add_child(chip)
	layer.add_child(_progress_track())
	return layer


func _build_service() -> Control:
	var view := ServiceViewScene.instantiate() as ServiceView
	view.vertical = Dock.is_side()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return view


func _reveal_chip_style() -> StyleBoxFlat:
	var style := Style.chip(Color(0.12, 0.09, 0.07, 0.74))
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style


func _progress_track() -> Control:
	var track := ColorRect.new()
	track.name = "ProgressTrack"
	track.color = Color(0, 0, 0, 0.35)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.anchor_top = 1.0
	track.anchor_bottom = 1.0
	track.anchor_right = 1.0
	track.offset_top = -3.0
	_progress_fill = ColorRect.new()
	_progress_fill.name = "ProgressFill"
	_progress_fill.color = Palette.AMBER
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_progress_fill.anchor_right = _reveal_fraction()
	track.add_child(_progress_fill)
	return track


func _build_recap() -> Control:
	var box := VBoxContainer.new()
	box.name = "Recap"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	var scroll := _scroll()
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", 4)
	var lines := _recap_lines()
	if lines.is_empty():
		lines.append("Caught up")
	for line in lines:
		var row := _label(line)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(Widgets.row_card(row))
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
	var champ := Session.championship
	var winner := _winner_line()
	if winner != "":
		var banner := _label(winner)
		banner.theme_type_variation = &"TitleLabel"
		banner.add_theme_font_size_override("font_size", 18)
		box.add_child(banner)
		if champ != null and _player_won(champ):
			var burst := Widgets.confetti()
			burst.position = Vector2(60.0, 10.0)
			banner.add_child(burst)
	var scroll := _scroll()
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", 4)
	if champ != null:
		for row in champ.standings():
			var is_player := str(row.get("entry_id", "")) == Championship.PLAYER_ID
			list.add_child(Widgets.row_card(_finished_row(row), is_player))
		var banked := _label("Dismiss banks %d reputation" % _player_points())
		banked.add_theme_color_override("font_color", Palette.CREAM_MUTED)
		list.add_child(banked)
	scroll.add_child(list)
	box.add_child(scroll)
	var actions: Container = HFlowContainer.new() if Dock.is_side() else HBoxContainer.new()
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_theme_constant_override("separation", 8)
	var dismiss := _button("Dismiss")
	dismiss.pressed.connect(_on_dismiss_finished)
	actions.add_child(dismiss)
	var again := _button("Start again")
	again.pressed.connect(_on_dismiss_finished)
	actions.add_child(again)
	box.add_child(actions)
	return box


## One final-table row: the driver's portrait beside the line and the temperament.
func _finished_row(row: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 6)
	line.add_child(Widgets.rank_badge(int(row.get("position", 0))))
	var portrait := _driver_portrait(str(row.get("entry_id", "")))
	if portrait != null:
		var rect := _portrait_rect(portrait, 28.0)
		rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(rect)
	var standing := _label(_finished_line(row))
	standing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	standing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(standing)
	return line


func _build_standings_peek() -> Control:
	if Dock.is_side():
		return _build_standings_column()
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
	_fill_standings(peek)
	return peek


## Left-edge column: one row per entry, portrait first. Scrolls if the strip is short.
func _build_standings_column() -> Control:
	var scroll := _scroll()
	scroll.name = "Standings"
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", 2)
	var champ := Session.championship
	if champ != null:
		for row in champ.standings():
			var entry_id := str(row.get("entry_id", ""))
			var line := HBoxContainer.new()
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_theme_constant_override("separation", 4)
			var place := _label(str(int(row.get("position", 0))))
			place.custom_minimum_size = Vector2(14, 0)
			line.add_child(place)
			var portrait := _driver_portrait(entry_id)
			if portrait != null:
				line.add_child(_portrait_rect(portrait, SIDE_ROW_PORTRAIT))
			var name_label := _label("%s %d" % [_short_name(entry_id), int(row.get("points", 0))])
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_label.clip_text = true
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			line.add_child(name_label)
			list.add_child(line)
	scroll.add_child(list)
	return scroll


func _driver_portrait(entry_id: String) -> Texture2D:
	var champ := Session.championship
	if champ == null:
		return null
	var entry := champ.find_entry(entry_id)
	if entry == null:
		return null
	var driver := Session.CATALOG.driver(entry.driver_id)
	if driver == null:
		return null
	return driver.portrait


func _peek_height() -> float:
	if Dock.get_preset() != Dock.PRESET_COZY:
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


## Position and gap follow the sector interpolation. At f = 1 they match the solved order.
## Points count committed stages only; the open stage's points land when the reveal ends.
func _reveal_line() -> String:
	var rows := _playback_rows()
	if rows.is_empty():
		return "Result pending"
	var fraction := _reveal_fraction()
	var ranked := RevealPlayback.sample(rows, fraction)
	var player_pos := 0
	var player_time := 0.0
	var player_finish := 0.0
	var ahead_time := -1.0
	for row in rows:
		if str(row.get("entry_id", "")) == Championship.PLAYER_ID:
			player_finish = float(row.get("finish_time", 0.0))
			break
	for row in ranked:
		if str(row.get("entry_id", "")) == Championship.PLAYER_ID:
			player_pos = int(row.get("position", 0))
			player_time = float(row.get("time", 0.0))
			break
		ahead_time = float(row.get("time", 0.0))
	if player_pos <= 0:
		return "Result pending"
	var gap := "lead"
	if player_pos > 1:
		gap = "+%.1fs" % (player_time - ahead_time)
	var clock := _format_mmss(player_finish * fraction)
	return "P%d  %s  %s  %d pts" % [player_pos, gap, clock, _player_points()]


func _playback_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var champ := Session.championship
	if champ == null:
		return rows
	for entry in champ.entries:
		var result := champ.stage_result(entry.id)
		if result == null:
			continue
		rows.append(RevealPlayback.row_from_result(entry.id, result))
	return rows


func _reveal_fraction() -> float:
	return RevealPlayback.fraction_from_remaining(Session.remaining(now_unix()))


func _player_points() -> int:
	var champ := Session.championship
	if champ == null:
		return 0
	for row in champ.standings():
		if str(row.get("entry_id", "")) == Championship.PLAYER_ID:
			return int(row.get("points", 0))
	return 0


## "1 [portrait] You 10   2 [portrait] Miso Dart 8" as one wrapped line of text and small images.
func _fill_standings(peek: RichTextLabel) -> void:
	peek.clear()
	var champ := Session.championship
	if champ == null:
		return
	var first := true
	for row in champ.standings():
		if not first:
			peek.add_text("   ")
		first = false
		var entry_id := str(row.get("entry_id", ""))
		peek.add_text("%d " % int(row.get("position", 0)))
		var portrait := _driver_portrait(entry_id)
		if portrait != null:
			peek.add_image(portrait, 16, 16)
			peek.add_text(" ")
		peek.add_text("%s %d" % [_short_name(entry_id), int(row.get("points", 0))])


func _finished_line(row: Dictionary) -> String:
	var entry_id := str(row.get("entry_id", ""))
	var line := "%d  %s  %d pts  %s" % [
		int(row.get("position", 0)),
		_entry_name(entry_id),
		int(row.get("points", 0)),
		_format_mmss(float(row.get("total_time", 0.0))),
	]
	var temperament := _temperament(entry_id)
	if temperament == "":
		return line
	return "%s\n%s" % [line, temperament]


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
	var stage := _stage_name(stage_index)
	var card := _card_label(card_id)
	if applied_by == "default":
		return "%s: %s, you were away" % [stage, _sentence_label(card)]
	var pos := "P-" if position <= 0 else "P%d" % position
	if card_id == "":
		return "%s  %s" % [stage, pos]
	return "%s: %s  %s" % [stage, card, pos]


func _card_label(card_id: String) -> String:
	if card_id == "":
		return "-"
	var card := Session.CATALOG.card(card_id)
	if card != null and card.label != "":
		return card.label
	return card_id


func _sentence_label(label: String) -> String:
	if label.is_empty():
		return label
	return label.substr(0, 1).to_lower() + label.substr(1)


func _player_won(champ: Championship) -> bool:
	var table := champ.standings()
	return not table.is_empty() and str(table[0].get("entry_id", "")) == Championship.PLAYER_ID


func _winner_line() -> String:
	var champ := Session.championship
	if champ == null:
		return ""
	var rows := champ.standings()
	if rows.is_empty():
		return ""
	var top: Dictionary = rows[0]
	return "Winner: %s" % _entry_name(str(top.get("entry_id", "")))


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


func _temperament(entry_id: String) -> String:
	var champ := Session.championship
	if champ == null:
		return ""
	var entry := champ.find_entry(entry_id)
	if entry == null:
		return ""
	var driver := Session.CATALOG.driver(entry.driver_id)
	if driver == null:
		return ""
	return driver.temperament


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
		if _progress_fill != null:
			_progress_fill.anchor_right = _reveal_fraction()


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
	Widgets.add_pop(button)
	return button


func _on_start_pressed() -> void:
	Session.start_draft()


func _on_dismiss_recap() -> void:
	Session.dismiss_recap()


func _on_dismiss_finished() -> void:
	Session.dismiss_finished()
