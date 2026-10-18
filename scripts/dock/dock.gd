extends Node
## Window flags, edge placement, hit polygon, and user://window.cfg.
##
## Section "window" stores screen (int, -1 until a screen is chosen), preset
## ("compact" or "cozy"), always_on_top (bool), edge ("bottom" or "left"),
## scale ("1.0", "1.25", "1.5", "2.0", or "match"), exclude_from_capture (bool),
## and seen_intro (bool, the first-launch copy). The file stores the preset name,
## never a pixel size. Geometry comes from DockGeometry: on the bottom edge the
## height is the preset times the content scale, or the focus height while a
## choice phase is open; on the left edge the width is the preset's long side
## times the content scale and focus height does not apply. Focus height is
## runtime-only (driven by Session phase); it is never written to the cfg.
##
## X11 and Windows do not report a display scale reliably, so the scale is a manual
## choice. "match" reads DisplayServer.screen_get_scale and is only offered on
## Wayland and macOS, where that call returns a real value.
##
## Godot 4.7 documents FLAG_BORDERLESS and FLAG_TRANSPARENT on native Wayland.
## FLAG_ALWAYS_ON_TOP, FLAG_NO_FOCUS, and mouse_passthrough_polygon are documented
## on X11, macOS, and Windows. If the debug read-back leaves one of those unset,
## the strip still docks borderless to the usable rect and quits from the button
## in the strip. The probe prints the display server and the read-back once.
##
## The hit polygon is the rounded strip, inset by PASSTHROUGH_MARGIN window pixels.
## On Windows, pixels outside that polygon are not drawn, so strip art uses the same inset.

## Fired after the strip moves to another edge. The strip scene rebuilds its layout.
signal edge_changed

const CONFIG_PATH := "user://window.cfg"
const SECTION := "window"

const PRESET_COMPACT := DockGeometry.PRESET_COMPACT
const PRESET_COZY := DockGeometry.PRESET_COZY
const HEIGHT_COMPACT := DockGeometry.SIZE_COMPACT
const HEIGHT_COZY := DockGeometry.SIZE_COZY
const HEIGHT_FOCUS := DockGeometry.SIZE_FOCUS
const EDGE_BOTTOM := DockGeometry.EDGE_BOTTOM
const EDGE_LEFT := DockGeometry.EDGE_LEFT
const SCALE_MATCH := DockGeometry.SCALE_MATCH

const PASSTHROUGH_MARGIN := 8.0
const CORNER_RADIUS := 12.0
const CORNER_SEGMENTS := 8

const USABLE_RECT_POLL_SEC := 2.0
const DRIFT_PX := 2

var _screen := -1
var _preset := PRESET_COZY
var _edge := EDGE_BOTTOM
var _scale_step := 1.0
var _scale_match := false
var _exclude_from_capture := false
var _seen_intro := false
var _focus := false
var _always_on_top := true
var _overlay_active := false
var _dragging := false
var _drag_button_seen := false
var _poll_wait := 0.0
var _last_usable := Rect2i()
var _probed := false


func _enter_tree() -> void:
	_load_config()
	if not _overlay_allowed():
		set_process(false)
		set_process_input(false)
		return
	_overlay_active = true
	_apply_flags()
	_place_on_screen(_resolve_screen())
	_rebuild_passthrough()
	if not get_window().size_changed.is_connected(_on_window_size_changed):
		get_window().size_changed.connect(_on_window_size_changed)
	call_deferred("_finish_startup")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_config()
	elif what == NOTIFICATION_WM_DPI_CHANGE and _overlay_active:
		var screen := _screen if _screen >= 0 else _resolve_screen()
		if _place_on_screen(screen):
			_rebuild_passthrough()


func _process(delta: float) -> void:
	if not _overlay_active:
		return
	if _dragging:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_drag_button_seen = true
		elif _drag_button_seen:
			_dragging = false
			_drag_button_seen = false
		if _dragging:
			_follow_drag_screen()
	_poll_wait += delta
	if _poll_wait < USABLE_RECT_POLL_SEC:
		return
	_poll_wait = 0.0
	_snap_if_dock_drifted()


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			_dragging = false
			_drag_button_seen = false
	elif event is InputEventMouseMotion:
		_follow_drag_screen()


func get_preset() -> String:
	return _preset


func set_preset(preset: String) -> void:
	if preset != PRESET_COMPACT and preset != PRESET_COZY:
		return
	if preset == _preset:
		return
	_preset = preset
	_reapply_placement()
	_save_config()


func get_edge() -> String:
	return _edge


## True when the strip is the left-edge column.
func is_side() -> bool:
	return _edge == EDGE_LEFT


func set_edge(edge: String) -> void:
	if edge != EDGE_BOTTOM and edge != EDGE_LEFT:
		return
	if edge == _edge:
		return
	_edge = edge
	_reapply_placement()
	_save_config()
	edge_changed.emit()


## "match" or one of "1.0", "1.25", "1.5", "2.0".
func get_scale_choice() -> String:
	if _scale_match and has_match_scale():
		return SCALE_MATCH
	return _scale_text(_scale_step)


func set_scale_choice(choice: String) -> void:
	if choice == SCALE_MATCH:
		if not has_match_scale() or _scale_match:
			return
		_scale_match = true
	else:
		var step := DockGeometry.nearest_step(choice.to_float())
		if not _scale_match and is_equal_approx(step, _scale_step):
			return
		_scale_match = false
		_scale_step = step
	_reapply_placement()
	_save_config()


## Wayland and macOS report a display scale; X11 and Windows return 1.0 regardless.
func has_match_scale() -> bool:
	return DisplayServer.get_name().to_lower() == "wayland" or OS.get_name() == "macOS"


## The exclude-from-capture hint exists on Windows and macOS only.
func can_exclude_from_capture() -> bool:
	var os_name := OS.get_name()
	return os_name == "Windows" or os_name == "macOS"


func is_excluded_from_capture() -> bool:
	return _exclude_from_capture and can_exclude_from_capture()


## Best effort. The OS may still show the window to some capture paths.
func set_exclude_from_capture(enabled: bool) -> void:
	if not can_exclude_from_capture() or enabled == _exclude_from_capture:
		return
	_exclude_from_capture = enabled
	if _overlay_active:
		get_window().exclude_from_capture = enabled
	_save_config()


func has_seen_intro() -> bool:
	return _seen_intro


## First-launch copy is shown once per machine, so this lives in window.cfg.
func mark_intro_seen() -> void:
	if _seen_intro:
		return
	_seen_intro = true
	_save_config()


func is_focus() -> bool:
	return _focus


## Transient taller strip for draft, service, recap, and finished. Not saved.
func set_focus(enabled: bool) -> void:
	if enabled == _focus:
		return
	_focus = enabled
	_reapply_placement()


func is_always_on_top() -> bool:
	return _always_on_top


func set_always_on_top(enabled: bool) -> void:
	if enabled == _always_on_top:
		return
	_always_on_top = enabled
	if _overlay_active:
		get_window().always_on_top = enabled
	_save_config()


func begin_screen_drag() -> void:
	if not _overlay_active:
		return
	_dragging = true
	_drag_button_seen = false


func end_screen_drag() -> void:
	_dragging = false
	_drag_button_seen = false


func refresh_hit_polygon() -> void:
	_rebuild_passthrough()


func save_and_quit() -> void:
	_save_config()
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	# SceneTree.quit() does not emit NOTIFICATION_WM_CLOSE_REQUEST.
	# Session saves from that notification, so deliver it before quitting.
	tree.root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	tree.quit()


func _finish_startup() -> void:
	if not _overlay_active:
		return
	_apply_flags()
	var screen := _screen if _screen >= 0 else _resolve_screen()
	_place_on_screen(screen)
	_rebuild_passthrough()
	_probe_platform()


func _on_window_size_changed() -> void:
	_rebuild_passthrough()


func _overlay_allowed() -> bool:
	if Engine.is_embedded_in_editor():
		return false
	return DisplayServer.get_name().to_lower() != "headless"


func _apply_flags() -> void:
	var window := get_window()
	window.borderless = true
	window.transparent = true
	window.transparent_bg = true
	window.always_on_top = _always_on_top
	window.unfocusable = true
	if can_exclude_from_capture():
		window.exclude_from_capture = _exclude_from_capture


func _resolve_screen() -> int:
	var count := DisplayServer.get_screen_count()
	if count <= 0:
		return 0
	if _screen >= 0 and _screen < count:
		return _screen
	var mouse := DisplayServer.mouse_get_position()
	var hovered := DisplayServer.get_screen_from_rect(Rect2i(mouse, Vector2i.ONE))
	if hovered >= 0 and hovered < count:
		return hovered
	var primary := DisplayServer.get_primary_screen()
	if primary >= 0 and primary < count:
		return primary
	return 0


func _place_on_screen(screen: int) -> bool:
	var count := DisplayServer.get_screen_count()
	if count <= 0:
		return false
	if screen < 0 or screen >= count:
		screen = _resolve_screen()
		if screen < 0 or screen >= count:
			return false
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x < 1 or usable.size.y < 1:
		return false
	var scale := _content_scale(screen)
	var rect := DockGeometry.window_rect(usable, _edge, _preset, _focus, scale)
	var size := rect.size
	var position := rect.position
	var window := get_window()
	window.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	# Match the stretch base to the logical strip size so compact stays 144 design
	# pixels tall instead of scaling the 220-pixel layout down into that height.
	window.content_scale_size = DockGeometry.logical_size(size, scale)
	if window.size != size:
		window.size = size
	if window.position != position:
		window.position = position
	_screen = screen
	_last_usable = usable
	return true


func _reapply_placement() -> void:
	if not _overlay_active:
		return
	var screen := _screen if _screen >= 0 else _resolve_screen()
	if _place_on_screen(screen):
		_rebuild_passthrough()


func _content_scale(screen: int) -> float:
	if _scale_match and has_match_scale():
		var reported := DisplayServer.screen_get_scale(screen)
		if reported > 0.0:
			return reported
		return 1.0
	return _scale_step


func _scale_text(step: float) -> String:
	return str(step)


func _follow_drag_screen() -> void:
	var count := DisplayServer.get_screen_count()
	var mouse := DisplayServer.mouse_get_position()
	var screen := DisplayServer.get_screen_from_rect(Rect2i(mouse, Vector2i.ONE))
	if screen < 0 or screen >= count or screen == _screen:
		return
	if _place_on_screen(screen):
		_rebuild_passthrough()
		_save_config()


func _snap_if_dock_drifted() -> void:
	if _dragging or not _overlay_active:
		return
	var count := DisplayServer.get_screen_count()
	if _screen < 0 or _screen >= count:
		return
	var window := get_window()
	if window.mode == Window.MODE_MINIMIZED:
		return
	var usable := DisplayServer.screen_get_usable_rect(_screen)
	var expected := DockGeometry.window_rect(usable, _edge, _preset, _focus, _content_scale(_screen))
	var expected_size := expected.size
	var expected_pos := expected.position
	var size_delta := (window.size - expected_size).abs()
	var pos_delta := (window.position - expected_pos).abs()
	var moved := usable != _last_usable
	var size_off := size_delta.x > DRIFT_PX or size_delta.y > DRIFT_PX
	var pos_off := pos_delta.x > DRIFT_PX or pos_delta.y > DRIFT_PX
	if not moved and not size_off and not pos_off:
		return
	if _place_on_screen(_screen):
		_rebuild_passthrough()
		if OS.is_debug_build():
			print(
				"Dock: snapped pos=%s size=%s usable=%s" % [window.position, window.size, _last_usable]
			)


func _rebuild_passthrough() -> void:
	if not _overlay_active:
		return
	var window := get_window()
	var size := window.size
	var margin := PASSTHROUGH_MARGIN
	if float(size.x) <= margin * 2.0 or float(size.y) <= margin * 2.0:
		return
	var rect := Rect2(margin, margin, float(size.x) - margin * 2.0, float(size.y) - margin * 2.0)
	var radius := minf(CORNER_RADIUS, minf(rect.size.x, rect.size.y) * 0.5)
	var polygon := _rounded_rect_polygon(rect, radius)
	if polygon.size() < 3:
		return
	window.mouse_passthrough_polygon = polygon


func _rounded_rect_polygon(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var left := rect.position.x
	var top := rect.position.y
	var right := rect.end.x
	var bottom := rect.end.y
	var centers: Array[Vector2] = [
		Vector2(right - radius, top + radius),
		Vector2(right - radius, bottom - radius),
		Vector2(left + radius, bottom - radius),
		Vector2(left + radius, top + radius),
	]
	# Screen y grows downward. Increasing angle walks the outline clockwise.
	var angle_start: Array[float] = [-PI * 0.5, 0.0, PI * 0.5, PI]
	for corner in 4:
		var center: Vector2 = centers[corner]
		var start: float = angle_start[corner]
		for step in CORNER_SEGMENTS:
			var angle := start + (float(step) / float(CORNER_SEGMENTS)) * PI * 0.5
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _load_config() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	var screen: Variant = config.get_value(SECTION, "screen", -1)
	if screen is int or screen is float:
		_screen = int(screen)
	var preset := str(config.get_value(SECTION, "preset", PRESET_COZY))
	if preset == PRESET_COMPACT or preset == PRESET_COZY:
		_preset = preset
	var always: Variant = config.get_value(SECTION, "always_on_top", true)
	if always is bool:
		_always_on_top = always
	var edge := str(config.get_value(SECTION, "edge", EDGE_BOTTOM))
	if edge == EDGE_BOTTOM or edge == EDGE_LEFT:
		_edge = edge
	var stored_scale: Variant = config.get_value(SECTION, "scale", "1.0")
	if str(stored_scale) == SCALE_MATCH:
		_scale_match = true
	elif stored_scale is float or stored_scale is int or stored_scale is String:
		_scale_step = DockGeometry.nearest_step(float(str(stored_scale)))
	var exclude: Variant = config.get_value(SECTION, "exclude_from_capture", false)
	if exclude is bool:
		_exclude_from_capture = exclude
	var intro: Variant = config.get_value(SECTION, "seen_intro", false)
	if intro is bool:
		_seen_intro = intro


func _save_config() -> void:
	# A headless run (the checks) must not rewrite the player's window.cfg.
	if DisplayServer.get_name() == "headless":
		return
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value(SECTION, "screen", _screen)
	config.set_value(SECTION, "preset", _preset)
	config.set_value(SECTION, "always_on_top", _always_on_top)
	config.set_value(SECTION, "edge", _edge)
	config.set_value(SECTION, "scale", get_scale_choice())
	config.set_value(SECTION, "exclude_from_capture", _exclude_from_capture)
	config.set_value(SECTION, "seen_intro", _seen_intro)
	var err := config.save(CONFIG_PATH)
	if err != OK:
		push_error("Dock failed to save window.cfg: %s" % error_string(err))


func _probe_platform() -> void:
	if _probed or not OS.is_debug_build():
		return
	_probed = true
	var window := get_window()
	var always_on_top := window.get_flag(Window.FLAG_ALWAYS_ON_TOP)
	var unfocusable := window.get_flag(Window.FLAG_NO_FOCUS)
	var points := window.mouse_passthrough_polygon.size()
	var scale := 1.0
	if _screen >= 0 and _screen < DisplayServer.get_screen_count():
		scale = _content_scale(_screen)
	print("Dock: display server: %s" % DisplayServer.get_name())
	print("Dock: always_on_top wanted=%s read_back=%s" % [_always_on_top, always_on_top])
	print("Dock: unfocusable wanted=true read_back=%s" % unfocusable)
	print("Dock: passthrough polygon points=%s" % points)
	print(
		"Dock: screen=%s edge=%s preset=%s focus=%s scale=%.2f pos=%s size=%s usable=%s"
		% [_screen, _edge, _preset, _focus, scale, window.position, window.size, _last_usable]
	)
	for index in DisplayServer.get_screen_count():
		print(
			"Dock: screen %s full_pos=%s full_size=%s usable=%s scale=%.2f"
			% [
				index,
				DisplayServer.screen_get_position(index),
				DisplayServer.screen_get_size(index),
				DisplayServer.screen_get_usable_rect(index),
				_content_scale(index),
			]
		)
	if always_on_top != _always_on_top or not unfocusable or points == 0:
		print("Dock: a requested overlay flag did not stick; strip stays borderless at the usable rect.")
