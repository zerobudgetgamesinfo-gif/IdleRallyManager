extends Control
## Window chrome for the companion strip. The nodes live in scenes/boot/main.tscn.
## The championship view is the instanced scenes/hud/strip.tscn.
## Flags and placement stay in Dock.

const HANDLE_HEIGHT := 16.0
const SETTINGS_BUTTON_WIDTH := 96.0
const SETTINGS_BUTTON_HEIGHT := 28.0
const SETTINGS_BUTTON_GAP := 8.0
const SETTINGS_PANEL_HEIGHT := 88.0
const SIDE_PAD := 8.0
const TICKER_HANDLE_HEIGHT := 6.0
const TICKER_PAD := 6.0
const GRIP_LONG := 48.0
const GRIP_SHORT := 4.0
const TIME_SCALES: Array[int] = [1, 10, 60, 120]

var _strip_style: StyleBoxFlat
var _skip_button: Button
var _debug_box: HBoxContainer
var _groups: Array[PanelContainer] = []
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
@onready var _ticker_button: Button = %Ticker
@onready var _always_on_top: CheckBox = %AlwaysOnTop
@onready var _mute: CheckBox = %Mute
@onready var _exclude_capture: CheckBox = %ExcludeCapture
@onready var _edge_bottom: Button = %EdgeBottom
@onready var _edge_left: Button = %EdgeLeft
@onready var _scale_buttons: Dictionary = {
	"1.0": %Scale100,
	"1.25": %Scale125,
	"1.5": %Scale150,
	"2.0": %Scale200,
	Dock.SCALE_MATCH: %ScaleMatch,
}
@onready var _grip: ColorRect = %Grip
@onready var _pause_button: Button = %PauseButton
@onready var _abandon_button: Button = %AbandonButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	theme = AppTheme.build()
	_add_sheen()
	_strip_style = _strip.get_theme_stylebox("panel") as StyleBoxFlat
	_bind_chrome()
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	if not get_window().size_changed.is_connected(_on_window_size_changed):
		get_window().size_changed.connect(_on_window_size_changed)
	if not Session.phase_changed.is_connected(_on_session_phase_changed):
		Session.phase_changed.connect(_on_session_phase_changed)
	if not Dock.edge_changed.is_connected(_on_edge_changed):
		Dock.edge_changed.connect(_on_edge_changed)
	apply_mute()
	_sync_championship_controls()
	_apply_layout()
	Dock.refresh_hit_polygon()


## A static vertical gradient over the strip's flat fill, under the phase content.
func _add_sheen() -> void:
	var sheen := TextureRect.new()
	sheen.name = "Sheen"
	sheen.texture = Style.sheen()
	sheen.stretch_mode = TextureRect.STRETCH_SCALE
	sheen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_strip.add_child(sheen)
	_strip.move_child(sheen, 0)


func _bind_chrome() -> void:
	_handle.gui_input.connect(_on_handle_gui_input)
	_settings_button.pressed.connect(_on_settings_pressed)
	_compact_button.toggled.connect(_on_preset_toggled.bind(Dock.PRESET_COMPACT))
	_cozy_button.toggled.connect(_on_preset_toggled.bind(Dock.PRESET_COZY))
	_ticker_button.toggled.connect(_on_preset_toggled.bind(Dock.PRESET_TICKER))
	_always_on_top.toggled.connect(_on_always_on_top_toggled)
	_pause_button.pressed.connect(_on_pause_pressed)
	_abandon_button.pressed.connect(_on_abandon_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	if Dock.get_preset() == Dock.PRESET_COMPACT:
		_compact_button.set_pressed_no_signal(true)
	elif Dock.get_preset() == Dock.PRESET_TICKER:
		_ticker_button.set_pressed_no_signal(true)
	else:
		_cozy_button.set_pressed_no_signal(true)
	_always_on_top.set_pressed_no_signal(Dock.is_always_on_top())
	_mute.set_pressed_no_signal(Session.muted)
	_mute.toggled.connect(_on_mute_toggled)
	_edge_bottom.toggled.connect(_on_edge_toggled.bind(Dock.EDGE_BOTTOM))
	_edge_left.toggled.connect(_on_edge_toggled.bind(Dock.EDGE_LEFT))
	_sync_edge_buttons()
	for choice in _scale_buttons:
		var button: Button = _scale_buttons[choice]
		button.toggled.connect(_on_scale_toggled.bind(str(choice)))
	_scale_buttons[Dock.SCALE_MATCH].visible = Dock.has_match_scale()
	_sync_scale_buttons()
	_exclude_capture.visible = Dock.can_exclude_from_capture()
	_exclude_capture.set_pressed_no_signal(Dock.is_excluded_from_capture())
	_exclude_capture.toggled.connect(_on_exclude_capture_toggled)
	_group_settings()
	_add_debug_controls()


## Settings read as five labelled groups instead of one run of buttons. The nodes keep their names
## and unique-name lookups; only their parents change.
func _group_settings() -> void:
	var row := _settings_row
	var groups: Array = [
		[row.get_node("Height"), _compact_button, _cozy_button, _ticker_button],
		[_always_on_top, _mute, _exclude_capture],
		[row.get_node("EdgeLabel"), _edge_bottom, _edge_left],
		[row.get_node("ScaleLabel")] + _scale_buttons.values(),
		[_pause_button, _abandon_button, _quit_button],
	]
	for members in groups:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", _group_style())
		var box := HFlowContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("h_separation", 6)
		box.add_theme_constant_override("v_separation", 2)
		panel.add_child(box)
		row.add_child(panel)
		for member in members:
			(member as Node).reparent(box, false)
		_groups.append(panel)
		if members[0] is Label:
			(members[0] as Label).add_theme_color_override("font_color", Palette.AMBER_LIGHT)


func _side_row_width() -> float:
	var panel_margin := _settings_panel.get_theme_stylebox("panel").get_minimum_size().x
	var stretch := _axis_scale(get_viewport().get_stretch_transform().get_scale().x)
	var width := get_viewport_rect().size.x - 2.0 * Dock.PASSTHROUGH_MARGIN / stretch
	width -= SIDE_PAD + HANDLE_HEIGHT + SIDE_PAD * 0.5 + panel_margin
	return maxf(width, 40.0)


func _on_viewport_size_changed() -> void:
	if Dock.is_side():
		_size_groups(_side_row_width())


## A flow inside a flow collapses to its narrowest column, so each group is given a width: its natural
## one on the bottom edge, and the whole row on the side column where its buttons wrap.
func _size_groups(row_width: float) -> void:
	for panel in _groups:
		var box := panel.get_child(0) as Container
		var style := panel.get_theme_stylebox("panel")
		var natural := style.get_minimum_size().x
		var count := 0
		for child in box.get_children():
			natural += (child as Control).get_combined_minimum_size().x
			count += 1
		natural += 6.0 * maxf(count - 1, 0.0)
		panel.custom_minimum_size.x = row_width if Dock.is_side() else natural


## Debug builds only. A node saved in the scene would ship in a release export.
func _add_debug_controls() -> void:
	if not OS.is_debug_build():
		return
	_debug_box = _make_debug_group()
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


func _group_style() -> StyleBoxFlat:
	var style := Style.chip(Palette.BROWN_DEEP)
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	style.content_margin_left = 6
	style.content_margin_right = 6
	return style


## One chip with a toggle; the debug controls are hidden until it is pressed.
func _make_debug_group() -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.name = "DebugGroup"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _group_style())
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var content := HBoxContainer.new()
	content.name = "DebugContent"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 6)
	content.visible = false
	var toggle := _make_button("Debug ▸")
	toggle.name = "DebugToggle"
	toggle.toggle_mode = true
	toggle.toggled.connect(func(open: bool) -> void:
		content.visible = open
		toggle.text = "Debug ▾" if open else "Debug ▸"
	)
	box.add_child(toggle)
	box.add_child(content)
	_settings_row.add_child(panel)
	return content


func _insert_before_quit(node: Control) -> void:
	_debug_box.add_child(node)


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

	_settings_button.offset_left = -(radius + SETTINGS_BUTTON_WIDTH)
	_settings_button.offset_right = -radius
	_settings_button.anchor_top = 0.0
	_settings_button.anchor_bottom = 0.0
	_settings_button.offset_top = 0.0
	_settings_button.offset_bottom = SETTINGS_BUTTON_HEIGHT

	if Dock.is_ticker():
		_apply_ticker_layout(radius)
	elif Dock.is_side():
		_apply_side_layout(radius)
	else:
		_apply_bottom_layout(radius)


## The drag handle is the top bar, the settings cluster sits on the bottom, and the HUD fills the rest.
func _apply_bottom_layout(radius: float) -> void:
	var button_span := radius + SETTINGS_BUTTON_WIDTH + SETTINGS_BUTTON_GAP
	_set_handle_anchors(0.0, 1.0, 0.0, 0.0)
	_handle.offset_left = radius
	_handle.offset_top = 0.0
	_handle.offset_right = -button_span
	_handle.offset_bottom = HANDLE_HEIGHT
	_handle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_set_grip(Vector2(GRIP_LONG, GRIP_SHORT))

	_set_panel_anchors(1.0)
	_settings_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_settings_panel.offset_left = radius
	_settings_panel.offset_right = -radius
	_settings_panel.offset_top = -(radius + SETTINGS_PANEL_HEIGHT)
	_settings_panel.offset_bottom = -radius

	_size_groups(0.0)
	_hud.offset_left = radius
	_hud.offset_top = maxf(HANDLE_HEIGHT, radius)
	_hud.offset_right = -radius
	_hud.offset_bottom = -radius


## The ticker row is the bottom TICKER_ROW strip of the window. The drag handle is a thin top bar, the
## settings button sits level with the row, and the settings cluster opens above the row.
func _apply_ticker_layout(radius: float) -> void:
	var row := HudStrip.TICKER_ROW_HEIGHT
	_set_handle_anchors(0.0, 1.0, 0.0, 0.0)
	_handle.offset_left = radius
	_handle.offset_top = 0.0
	_handle.offset_right = -(radius + SETTINGS_BUTTON_WIDTH + SETTINGS_BUTTON_GAP)
	_handle.offset_bottom = TICKER_HANDLE_HEIGHT
	_handle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_set_grip(Vector2(GRIP_LONG, GRIP_SHORT))

	var below := TICKER_PAD + (row - SETTINGS_BUTTON_HEIGHT) * 0.5
	_settings_button.anchor_top = 1.0
	_settings_button.anchor_bottom = 1.0
	_settings_button.offset_bottom = -below
	_settings_button.offset_top = -(below + SETTINGS_BUTTON_HEIGHT)

	_set_panel_anchors(1.0)
	_settings_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_settings_panel.offset_left = radius
	_settings_panel.offset_right = -radius
	_settings_panel.offset_bottom = -(TICKER_PAD + row + TICKER_PAD)
	_settings_panel.offset_top = _settings_panel.offset_bottom - SETTINGS_PANEL_HEIGHT

	_size_groups(0.0)
	_hud.offset_left = radius
	_hud.offset_top = TICKER_HANDLE_HEIGHT
	_hud.offset_right = -radius
	_hud.offset_bottom = -TICKER_PAD


## The strip is a column on the left edge, so the drag handle moves to the inner (right) edge.
## The settings button stays on top, and the cluster covers the column below it.
func _apply_side_layout(radius: float) -> void:
	var top := SETTINGS_BUTTON_HEIGHT + SIDE_PAD
	_set_handle_anchors(1.0, 1.0, 0.0, 1.0)
	_handle.offset_left = -HANDLE_HEIGHT
	_handle.offset_right = 0.0
	_handle.offset_top = top
	_handle.offset_bottom = -radius
	_handle.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_set_grip(Vector2(GRIP_SHORT, GRIP_LONG))

	_set_panel_anchors(0.0)
	_settings_panel.grow_vertical = Control.GROW_DIRECTION_END
	_settings_panel.offset_left = SIDE_PAD
	_settings_panel.offset_right = -(HANDLE_HEIGHT + SIDE_PAD * 0.5)
	_settings_panel.offset_top = top
	_settings_panel.offset_bottom = -SIDE_PAD

	_size_groups(_side_row_width())
	_hud.offset_left = SIDE_PAD
	_hud.offset_top = top
	_hud.offset_right = -(HANDLE_HEIGHT + SIDE_PAD * 0.5)
	_hud.offset_bottom = -SIDE_PAD


func _set_handle_anchors(left: float, right: float, top: float, bottom: float) -> void:
	_handle.anchor_left = left
	_handle.anchor_right = right
	_handle.anchor_top = top
	_handle.anchor_bottom = bottom


func _set_panel_anchors(top: float) -> void:
	_settings_panel.anchor_left = 0.0
	_settings_panel.anchor_right = 1.0
	_settings_panel.anchor_top = top
	_settings_panel.anchor_bottom = 1.0


func _set_grip(extent: Vector2) -> void:
	_grip.offset_left = -extent.x * 0.5
	_grip.offset_right = extent.x * 0.5
	_grip.offset_top = -extent.y * 0.5
	_grip.offset_bottom = extent.y * 0.5


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
	_pause_button.accessibility_name = _pause_button.text
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
	_settings_button.accessibility_name = "Close settings" if _settings_panel.visible else "Settings"
	if not _settings_panel.visible:
		_reset_abandon_button()
	Dock.set_settings_open(_settings_panel.visible)
	_apply_layout()
	Dock.refresh_hit_polygon()


func _on_preset_toggled(pressed: bool, preset: String) -> void:
	if pressed:
		Dock.set_preset(preset)


func _on_always_on_top_toggled(enabled: bool) -> void:
	Dock.set_always_on_top(enabled)


## Mute is a bus switch, so the reveal loop keeps running and unmuting is heard at once.
func apply_mute() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, Session.muted)


func _on_mute_toggled(enabled: bool) -> void:
	Session.set_muted(enabled)
	apply_mute()


func _on_edge_toggled(pressed: bool, edge: String) -> void:
	if pressed:
		Dock.set_edge(edge)


func _on_edge_changed() -> void:
	_sync_edge_buttons()
	_apply_layout()
	Dock.refresh_hit_polygon()


func _sync_edge_buttons() -> void:
	_edge_bottom.set_pressed_no_signal(not Dock.is_side())
	_edge_left.set_pressed_no_signal(Dock.is_side())


func _on_scale_toggled(pressed: bool, choice: String) -> void:
	if pressed:
		Dock.set_scale_choice(choice)


func _sync_scale_buttons() -> void:
	var choice := Dock.get_scale_choice()
	for key in _scale_buttons:
		var button: Button = _scale_buttons[key]
		button.set_pressed_no_signal(str(key) == choice)


func _on_exclude_capture_toggled(enabled: bool) -> void:
	Dock.set_exclude_from_capture(enabled)


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
		_abandon_button.text = "Clear championship; keep window"
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
	_reset_abandon_button()
	_sync_championship_controls()
	_apply_layout()


func _reset_abandon_button() -> void:
	_abandon_armed = false
	_abandon_button.text = "Abandon"


func _on_quit_pressed() -> void:
	Dock.save_and_quit()
