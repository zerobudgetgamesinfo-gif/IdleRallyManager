extends Control
## Placeholder strip. Window flags and placement stay in Dock.

const HANDLE_HEIGHT := 16.0
const SETTINGS_BUTTON_WIDTH := 96.0
const SETTINGS_BUTTON_HEIGHT := 28.0
const SETTINGS_BUTTON_GAP := 8.0
const TITLE_COLOR := Color(0.973, 0.941, 0.878, 1.0)
const STRIP_COLOR := Color(0.176, 0.149, 0.118, 1.0)
const STRIP_BORDER := Color(0.855, 0.624, 0.29, 1.0)
const GRIP_COLOR := Color(0.855, 0.624, 0.29, 0.95)

var _strip: Panel
var _strip_style: StyleBoxFlat
var _handle: Control
var _settings_button: Button
var _settings_panel: PanelContainer
var _compact_button: Button
var _cozy_button: Button
var _always_on_top: CheckBox
var _preset_group: ButtonGroup


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_apply_layout()
	if not get_window().size_changed.is_connected(_on_window_size_changed):
		get_window().size_changed.connect(_on_window_size_changed)
	Dock.refresh_hit_polygon()


func _build() -> void:
	_strip_style = StyleBoxFlat.new()
	_strip_style.bg_color = STRIP_COLOR
	_strip_style.border_color = STRIP_BORDER
	_strip_style.set_border_width_all(2)
	_strip_style.set_corner_radius_all(roundi(Dock.CORNER_RADIUS))
	_strip_style.corner_detail = Dock.CORNER_SEGMENTS
	_strip_style.anti_aliasing = false

	_strip = Panel.new()
	_strip.name = "Strip"
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip.clip_contents = true
	_strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_strip.add_theme_stylebox_override("panel", _strip_style)
	add_child(_strip)

	var title := Label.new()
	title.name = "Title"
	title.text = "Idle Rally Manager"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	_strip.add_child(title)

	_handle = Control.new()
	_handle.name = "MouseDragHandle"
	_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_handle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_handle.gui_input.connect(_on_handle_gui_input)
	_strip.add_child(_handle)
	_mark_unique(_handle)

	var grip := ColorRect.new()
	grip.name = "Grip"
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grip.color = GRIP_COLOR
	grip.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grip.offset_left = -24.0
	grip.offset_right = 24.0
	grip.offset_top = -2.0
	grip.offset_bottom = 2.0
	_handle.add_child(grip)

	_settings_button = Button.new()
	_settings_button.name = "SettingsButton"
	_settings_button.text = "Settings"
	_settings_button.focus_mode = Control.FOCUS_NONE
	_settings_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_settings_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_settings_button.pressed.connect(_on_settings_pressed)
	_strip.add_child(_settings_button)
	_mark_unique(_settings_button)

	_settings_panel = PanelContainer.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.visible = false
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_strip.add_child(_settings_panel)

	var row := HBoxContainer.new()
	row.name = "SettingsRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	_settings_panel.add_child(row)

	var height_label := Label.new()
	height_label.text = "Height"
	height_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(height_label)

	_preset_group = ButtonGroup.new()
	_compact_button = _make_choice("Compact")
	_cozy_button = _make_choice("Cozy")
	row.add_child(_compact_button)
	row.add_child(_cozy_button)
	if Dock.get_preset() == Dock.PRESET_COMPACT:
		_compact_button.button_pressed = true
	else:
		_cozy_button.button_pressed = true
	_compact_button.toggled.connect(_on_preset_toggled.bind(Dock.PRESET_COMPACT))
	_cozy_button.toggled.connect(_on_preset_toggled.bind(Dock.PRESET_COZY))

	_always_on_top = CheckBox.new()
	_always_on_top.name = "AlwaysOnTop"
	_always_on_top.text = "Always on top"
	_always_on_top.focus_mode = Control.FOCUS_NONE
	_always_on_top.set_pressed_no_signal(Dock.is_always_on_top())
	_always_on_top.toggled.connect(_on_always_on_top_toggled)
	row.add_child(_always_on_top)

	var quit_button := Button.new()
	quit_button.name = "QuitButton"
	quit_button.text = "Quit"
	quit_button.focus_mode = Control.FOCUS_NONE
	quit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	quit_button.pressed.connect(_on_quit_pressed)
	row.add_child(quit_button)

	assert(get_node_or_null("%MouseDragHandle") != null)
	assert(get_node_or_null("%SettingsButton") != null)


func _make_choice(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.button_group = _preset_group
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _mark_unique(node: Node) -> void:
	node.owner = self
	node.unique_name_in_owner = true


func _apply_layout() -> void:
	if _strip == null:
		return
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

	_settings_panel.offset_left = -300.0
	_settings_panel.offset_right = 300.0
	_settings_panel.offset_top = -(radius + 44.0)
	_settings_panel.offset_bottom = -radius


func _axis_scale(value: float) -> float:
	var magnitude := absf(value)
	if magnitude <= 0.001:
		return 1.0
	return magnitude


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


func _on_preset_toggled(pressed: bool, preset: String) -> void:
	if pressed:
		Dock.set_preset(preset)


func _on_always_on_top_toggled(enabled: bool) -> void:
	Dock.set_always_on_top(enabled)


func _on_quit_pressed() -> void:
	Dock.save_and_quit()
