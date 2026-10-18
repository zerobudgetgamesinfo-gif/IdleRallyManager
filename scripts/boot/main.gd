extends Control
## Window chrome for the companion strip. The nodes live in scenes/boot/main.tscn.
## The championship view is the instanced scenes/hud/strip.tscn.
## Flags and placement stay in Dock.

const HANDLE_HEIGHT := 16.0
const SETTINGS_BUTTON_WIDTH := 96.0
const SETTINGS_BUTTON_HEIGHT := 28.0
const SETTINGS_BUTTON_GAP := 8.0
const SETTINGS_PANEL_HEIGHT := 88.0
const TIME_SCALES: Array[int] = [1, 10, 60, 120]

var _strip_style: StyleBoxFlat
var _skip_button: Button
var _scale_box: SpinBox
var _abandon_armed := false
var _shown_scale := 1.0

@onready var _strip: Panel = %Strip
@onready var _hud: HudStrip = %HudStrip
@onready var _handle: Control = %MouseDragHandle
@onready var _settings_button: Button = %SettingsButton
@onready var _settings_panel: PanelContainer = %SettingsPanel
@onready var _settings_row: HFlowContainer = %SettingsRow
@onready var _compact_button: Button = %Compact
@onready var _cozy_button: Button = %Cozy
@onready var _always_on_top: CheckBox = %AlwaysOnTop
@onready var _pause_button: Button = %PauseButton
@onready var _abandon_button: Button = %AbandonButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_strip_style = _strip.get_theme_stylebox("panel") as StyleBoxFlat
	_bind_chrome()
	_apply_layout()
	if not get_window().size_changed.is_connected(_on_window_size_changed):
		get_window().size_changed.connect(_on_window_size_changed)
	if not Session.phase_changed.is_connected(_on_session_phase_changed):
		Session.phase_changed.connect(_on_session_phase_changed)
	_sync_championship_controls()
	Dock.refresh_hit_polygon()


func _bind_chrome() -> void:
	_handle.gui_input.connect(_on_handle_gui_input)
	_settings_button.pressed.connect(_on_settings_pressed)
	_compact_button.toggled.connect(_on_preset_toggled.bind(Dock.PRESET_COMPACT))
	_cozy_button.toggled.connect(_on_preset_toggled.bind(Dock.PRESET_COZY))
	_always_on_top.toggled.connect(_on_always_on_top_toggled)
	_pause_button.pressed.connect(_on_pause_pressed)
	_abandon_button.pressed.connect(_on_abandon_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	if Dock.get_preset() == Dock.PRESET_COMPACT:
		_compact_button.set_pressed_no_signal(true)
	else:
		_cozy_button.set_pressed_no_signal(true)
	_always_on_top.set_pressed_no_signal(Dock.is_always_on_top())
	_add_debug_controls()


## Debug builds only. A node saved in the scene would ship in a release export.
func _add_debug_controls() -> void:
	if not OS.is_debug_build():
		return
	var scale_label := Label.new()
	scale_label.text = "Time scale"
	scale_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_insert_before_quit(scale_label)

	_shown_scale = Session.time_scale
	_scale_box = SpinBox.new()
	_scale_box.name = "TimeScale"
	_scale_box.min_value = 1
	_scale_box.max_value = maxf(120.0, _shown_scale)
	_scale_box.step = 1
	_scale_box.rounded = true
	_scale_box.focus_mode = Control.FOCUS_NONE
	_scale_box.custom_minimum_size = Vector2(96, 0)
	_scale_box.set_value_no_signal(_shown_scale)
	_scale_box.value_changed.connect(_on_time_scale_changed)
	_insert_before_quit(_scale_box)
	# SpinBox.is_editable() is the line edit's flag. A read-only line edit
	# makes gui_input return immediately, so the arrow buttons do nothing.
	var edit := _scale_box.get_line_edit()
	edit.focus_mode = Control.FOCUS_NONE
	edit.mouse_filter = Control.MOUSE_FILTER_PASS

	_skip_button = _make_button("Skip ahead")
	_skip_button.name = "SkipAhead"
	_skip_button.pressed.connect(_on_skip_pressed)
	_insert_before_quit(_skip_button)


func _insert_before_quit(node: Control) -> void:
	_settings_row.add_child(node)
	_settings_row.move_child(node, _quit_button.get_index())


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _apply_layout() -> void:
	var scale := get_viewport().get_stretch_transform().get_scale()
	var scale_x := _axis_scale(scale.x)
	var scale_y := _axis_scale(scale.y)
	var margin_x := Dock.PASSTHROUGH_MARGIN / scale_x
	var margin_y := Dock.PASSTHROUGH_MARGIN / scale_y
	_strip.offset_left = margin_x
	_strip.offset_top = margin_y
	_strip.offset_right = -margin_x
	_strip.offset_bottom = -margin_y

	var radius_scale := maxf(scale_x, scale_y)
	var radius := Dock.CORNER_RADIUS / radius_scale
	_strip_style.set_corner_radius_all(maxi(roundi(radius), 0))

	var button_span := radius + SETTINGS_BUTTON_WIDTH + SETTINGS_BUTTON_GAP
	_handle.offset_left = radius
	_handle.offset_top = 0.0
	_handle.offset_right = -button_span
	_handle.offset_bottom = HANDLE_HEIGHT

	_settings_button.offset_left = -(radius + SETTINGS_BUTTON_WIDTH)
	_settings_button.offset_right = -radius
	_settings_button.offset_top = 0.0
	_settings_button.offset_bottom = SETTINGS_BUTTON_HEIGHT

	_settings_panel.offset_left = radius
	_settings_panel.offset_right = -radius
	_settings_panel.offset_top = -(radius + SETTINGS_PANEL_HEIGHT)
	_settings_panel.offset_bottom = -radius

	_hud.offset_left = radius
	_hud.offset_top = maxf(HANDLE_HEIGHT, radius)
	_hud.offset_right = -radius
	_hud.offset_bottom = -radius


func _axis_scale(value: float) -> float:
	var magnitude := absf(value)
	if magnitude <= 0.001:
		return 1.0
	return magnitude


func _sync_championship_controls() -> void:
	var phase := Session.phase()
	var champ := Session.championship
	var paused := champ != null and champ.pause_started_unix != null
	var show_pause := (
		phase == Championship.PHASE_STAGE_REVEAL
		or phase == Championship.PHASE_SERVICE
		or phase == Championship.PHASE_RECAP
	)
	_pause_button.visible = show_pause
	_pause_button.disabled = phase == Championship.PHASE_RECAP
	_pause_button.text = "Resume" if paused else "Pause"
	_abandon_button.visible = champ != null
	if not _abandon_armed:
		_abandon_button.text = "Abandon"
	if _skip_button != null:
		var live := phase == Championship.PHASE_STAGE_REVEAL or phase == Championship.PHASE_SERVICE
		_skip_button.disabled = not live


func _on_window_size_changed() -> void:
	_apply_layout()
	Dock.refresh_hit_polygon()


func _on_handle_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		Dock.begin_screen_drag()
	else:
		Dock.end_screen_drag()
	get_viewport().set_input_as_handled()


func _on_settings_pressed() -> void:
	_settings_panel.visible = not _settings_panel.visible
	_settings_button.text = "Close" if _settings_panel.visible else "Settings"
	if not _settings_panel.visible:
		_abandon_armed = false
		_abandon_button.text = "Abandon"
	_apply_layout()
	Dock.refresh_hit_polygon()


func _on_preset_toggled(pressed: bool, preset: String) -> void:
	if pressed:
		Dock.set_preset(preset)


func _on_always_on_top_toggled(enabled: bool) -> void:
	Dock.set_always_on_top(enabled)


func _on_pause_pressed() -> void:
	if Session.championship == null:
		return
	if Session.championship.pause_started_unix != null:
		Session.resume(_hud.now_unix())
	else:
		_hud.catch_clock()
		var phase := Session.phase()
		if phase == Championship.PHASE_STAGE_REVEAL or phase == Championship.PHASE_SERVICE:
			Session.pause()
	_sync_championship_controls()
	_hud.notify_clock()


func _on_abandon_pressed() -> void:
	if not _abandon_armed:
		_abandon_armed = true
		_abandon_button.text = "Confirm abandon"
		return
	_abandon_armed = false
	_abandon_button.text = "Abandon"
	Session.abandon()


func _on_time_scale_changed(value: float) -> void:
	if _scale_box == null:
		return
	var chosen := _next_time_scale(value)
	if not is_equal_approx(_scale_box.value, chosen):
		_scale_box.set_value_no_signal(chosen)
	_shown_scale = chosen
	if is_equal_approx(Session.time_scale, chosen):
		return
	if Session.championship != null and Session.championship.pause_started_unix == null:
		_hud.catch_clock()
	Session.set_time_scale(chosen)
	_hud.notify_clock()


func _next_time_scale(value: float) -> float:
	var rounded := roundi(value)
	for step in TIME_SCALES:
		if step == rounded:
			return float(step)
	if value > _shown_scale:
		for step in TIME_SCALES:
			if float(step) > _shown_scale:
				return float(step)
		return _shown_scale
	if value < _shown_scale:
		var lower := float(TIME_SCALES[0])
		for step in TIME_SCALES:
			if float(step) < _shown_scale:
				lower = float(step)
		return lower
	return _shown_scale


func _on_skip_pressed() -> void:
	_hud.skip_ahead()
	_sync_championship_controls()


func _on_session_phase_changed() -> void:
	_abandon_armed = false
	_sync_championship_controls()
	_apply_layout()


func _on_quit_pressed() -> void:
	Dock.save_and_quit()
