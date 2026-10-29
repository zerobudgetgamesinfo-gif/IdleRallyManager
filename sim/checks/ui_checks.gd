class_name UiChecks
extends RefCounted
## Headless checks for the strip's scenes: window geometry, layout bounds, art and audio
## wiring, a still idle, and accessibility names. They drive the real Session autoload,
## which does not touch disk in a headless run, and put it back to idle afterwards.

const MAIN_SCENE: PackedScene = preload("res://scenes/boot/main.tscn")
const STAGE_SCENE: PackedScene = preload("res://scenes/stage/stage_view.tscn")
const CATALOG: Catalog = preload("res://data/catalog.tres")

var _tree: SceneTree
var _expect: Callable


func _init(tree: SceneTree, expect: Callable) -> void:
	_tree = tree
	_expect = expect


func run() -> void:
	# Dock loads the player's window.cfg, so pin the layout the checks assume and put it back after.
	var stored_preset := Dock.get_preset()
	var stored_edge := Dock.get_edge()
	var stored_collapsed := Dock.is_collapsed()
	Dock.set_edge(Dock.EDGE_BOTTOM)
	Dock.set_preset(Dock.PRESET_COZY)
	Dock.set_collapsed(false)
	await _run_checks()
	Dock.set_preset(stored_preset)
	Dock.set_edge(stored_edge)
	Dock.set_collapsed(stored_collapsed)


func _run_checks() -> void:
	_check_geometry()
	_check_dock_settings()
	_check_assets()
	await _check_poses_and_loop()
	await _check_layout()
	await _check_corner_chrome()
	await _check_corner()
	await _check_still_idle_and_service()
	await _check_reveal_audio_and_sleep()
	await _check_intro_once()
	await _check_accessibility()
	_reset_session()


func _ok(condition: bool, message: String) -> void:
	_expect.call(condition, message)


func _frames(count: int = 2) -> void:
	for _i in count:
		await _tree.process_frame


func _reset_session() -> void:
	Session.time_scale = 1.0
	Session.muted = false
	Session.abandon()


# --- Geometry --------------------------------------------------------------

func _check_geometry() -> void:
	var usable := Rect2i(0, 0, 1920, 1040)
	# HiDPI smoke test: cozy at scale 2 stays on the usable rect and lays out at 220 design pixels.
	var cozy_2 := DockGeometry.window_rect(usable, DockGeometry.EDGE_BOTTOM, DockGeometry.PRESET_COZY, false, 2.0)
	_ok(cozy_2 == Rect2i(0, 600, 1920, 440), "cozy at scale 2 rect %s" % cozy_2)
	_ok(DockGeometry.fits(cozy_2, usable), "cozy at scale 2 leaves the usable rect")
	_ok(DockGeometry.logical_size(cozy_2.size, 2.0) == Vector2i(960, 220), "cozy at scale 2 logical size")
	var focus_2 := DockGeometry.window_rect(usable, DockGeometry.EDGE_BOTTOM, DockGeometry.PRESET_COZY, true, 2.0)
	_ok(focus_2.size.y == 680 and DockGeometry.fits(focus_2, usable), "focus at scale 2 rect %s" % focus_2)
	# A short screen clamps instead of leaving the rect.
	var short := Rect2i(100, 40, 1280, 300)
	var clamped := DockGeometry.window_rect(short, DockGeometry.EDGE_BOTTOM, DockGeometry.PRESET_COZY, true, 2.0)
	_ok(DockGeometry.fits(clamped, short), "clamped focus rect %s" % clamped)
	# Left edge: usable height, the preset's long side, and focus height does not apply.
	var left_cozy := DockGeometry.window_rect(usable, DockGeometry.EDGE_LEFT, DockGeometry.PRESET_COZY, false, 1.0)
	_ok(left_cozy == Rect2i(0, 0, 220, 1040), "left cozy rect %s" % left_cozy)
	var left_compact := DockGeometry.window_rect(usable, DockGeometry.EDGE_LEFT, DockGeometry.PRESET_COMPACT, true, 1.0)
	_ok(left_compact == Rect2i(0, 0, 144, 1040), "left compact ignores focus %s" % left_compact)
	var offset_usable := Rect2i(1920, 30, 1600, 900)
	var left_offset := DockGeometry.window_rect(offset_usable, DockGeometry.EDGE_LEFT, DockGeometry.PRESET_COZY, false, 1.5)
	_ok(left_offset == Rect2i(1920, 30, 330, 900), "left on a second screen %s" % left_offset)
	var compact_corner := DockGeometry.window_rect(
		usable, DockGeometry.EDGE_BOTTOM, DockGeometry.PRESET_COMPACT, false, 1.0, true
	)
	_ok(compact_corner == Rect2i(1776, 896, 144, 144), "compact corner rect %s" % compact_corner)
	var corner_popover := DockGeometry.window_rect(
		usable, DockGeometry.EDGE_LEFT, DockGeometry.PRESET_COMPACT, true, 1.0, true
	)
	_ok(corner_popover == Rect2i(1280, 700, 640, 340), "corner popover rect %s" % corner_popover)
	var cozy_corner := DockGeometry.window_rect(
		usable, DockGeometry.EDGE_LEFT, DockGeometry.PRESET_COZY, false, 1.0, true
	)
	_ok(cozy_corner == Rect2i(1700, 820, 220, 220), "collapsed geometry depends on edge %s" % cozy_corner)
	_ok(DockGeometry.nearest_step(1.3) == 1.25, "snap 1.3")
	_ok(DockGeometry.nearest_step(9.0) == 2.0, "snap 9")
	_ok(DockGeometry.nearest_step(0.0) == 1.0, "snap 0")


func _check_dock_settings() -> void:
	var edge := Dock.get_edge()
	var choice := Dock.get_scale_choice()
	var capture := Dock.is_excluded_from_capture()
	Dock.set_scale_choice("2.0")
	_ok(Dock.get_scale_choice() == "2.0", "scale choice 2.0 is %s" % Dock.get_scale_choice())
	Dock.set_scale_choice("1.25")
	_ok(Dock.get_scale_choice() == "1.25", "scale choice 1.25 is %s" % Dock.get_scale_choice())
	Dock.set_scale_choice(Dock.SCALE_MATCH)
	if Dock.has_match_scale():
		_ok(Dock.get_scale_choice() == Dock.SCALE_MATCH, "match screen was refused where offered")
	else:
		_ok(Dock.get_scale_choice() == "1.25", "match screen was accepted where it does nothing")
	Dock.set_scale_choice(choice)
	Dock.set_edge("middle")
	_ok(Dock.get_edge() == edge, "a bad edge was accepted")
	var os_name := OS.get_name()
	_ok(
		Dock.can_exclude_from_capture() == (os_name == "Windows" or os_name == "macOS"),
		"exclude from capture offered on %s" % os_name
	)
	if not Dock.can_exclude_from_capture():
		Dock.set_exclude_from_capture(true)
		_ok(not Dock.is_excluded_from_capture(), "exclude from capture stuck where the hint does nothing")
	Dock.set_exclude_from_capture(capture)


# --- Assets ----------------------------------------------------------------

func _check_assets() -> void:
	for driver in CATALOG.drivers:
		_ok(driver.portrait != null, "driver %s has no portrait" % driver.id)
	for car in CATALOG.cars:
		_ok(car.portrait != null, "car %s has no portrait" % car.id)
		_ok(car.stage_sprite != null, "car %s has no stage sprite" % car.id)
	_ok(is_equal_approx(StageView.car_x(0.0, 800.0, 80.0), StageView.ROAD_MARGIN), "the car does not start at the left end")
	_ok(
		is_equal_approx(StageView.car_x(1.0, 800.0, 80.0), 800.0 - StageView.ROAD_MARGIN - 80.0),
		"the car does not finish at the right end"
	)
	for stage in CATALOG.stages_in_order():
		_ok(StageView.SURFACE_TEXTURES.has(stage.surface), "no art for the %s surface of %s" % [stage.surface, stage.id])
	for surface in StageView.SURFACE_TEXTURES:
		var layers: Dictionary = StageView.SURFACE_TEXTURES[surface]
		for layer in ["sky", "hills", "props", "ground", "road"]:
			_ok(layers.get(layer) is Texture2D, "%s has no %s layer" % [surface, layer])
	var master := AudioServer.get_bus_index("Master")
	_ok(master >= 0, "no Master bus")
	_ok(is_equal_approx(AudioServer.get_bus_volume_db(master), -18.0), "master volume %s" % AudioServer.get_bus_volume_db(master))
	var loop := load("res://audio/reveal_loop.wav") as AudioStreamWAV
	_ok(loop != null and loop.loop_mode == AudioStreamWAV.LOOP_FORWARD, "the reveal loop does not loop")
	_ok(load("res://audio/incident_stinger.wav") is AudioStreamWAV, "the stinger is missing")
	_ok(
		str(ProjectSettings.get_setting("audio/driver/driver", "")) != "Dummy",
		"audio driver was forced to Dummy"
	)
	_ok(StageView.pose_for_kind("slide") == &"slide", "slide pose")
	_ok(StageView.pose_for_kind("jump") == &"hop", "hop pose")
	_ok(StageView.pose_for_kind("hazard") == &"wobble", "hazard pose")
	_ok(StageView.pose_for_kind("straight") == &"wobble", "straight pose")


func _check_poses_and_loop() -> void:
	var view := STAGE_SCENE.instantiate() as StageView
	_tree.root.add_child(view)
	await _frames()
	var poses := view.get_node("%Poses") as AnimationPlayer
	_ok(poses.autoplay == "", "the pose player autoplays %s" % poses.autoplay)
	_ok(not poses.is_playing(), "a pose plays before any incident")
	for clip in ["slide", "hop", "wobble"]:
		_ok(poses.has_animation(clip), "missing %s clip" % clip)
		if poses.has_animation(clip):
			_ok(poses.get_animation(clip).loop_mode == Animation.LOOP_NONE, "%s clip loops" % clip)
	_ok(view.get_node("%Loop").playing, "the reveal loop did not start with the view")
	_ok(OS.low_processor_usage_mode_sleep_usec == StageView.REVEAL_SLEEP_USEC, "reveal sleep not lowered")
	view._play_pose("jump")
	_ok(poses.is_playing() and poses.current_animation == "hop", "a jump incident did not play hop")
	view._play_pose("slide")
	_ok(poses.current_animation == "slide", "a slide incident did not play slide")
	var loop_player := view.get_node("%Loop") as AudioStreamPlayer
	_tree.root.remove_child(view)
	_ok(not loop_player.playing, "the reveal loop kept playing after the view left the tree")
	_ok(OS.low_processor_usage_mode_sleep_usec == StageView.REST_SLEEP_USEC, "rest sleep not restored")
	view.free()


# --- Layout ----------------------------------------------------------------

func _check_layout() -> void:
	_reset_session()
	# A headless window keeps its size, so the strip lives in a SubViewport that does resize.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 220)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_tree.root.add_child(viewport)
	var main := MAIN_SCENE.instantiate() as Control
	viewport.add_child(main)
	await _frames()
	var settings_button := main.get_node("%SettingsButton") as Button
	settings_button.pressed.emit()
	# Show the platform-only controls so the cluster is measured at its widest.
	main.get_node("%ExcludeCapture").visible = true
	main.get_node("%ScaleMatch").visible = true
	await _frames()
	var cases := [
		["bottom", Vector2i(1280, 220)],
		["bottom", Vector2i(1280, 144)],
		["bottom", Vector2i(1024, 144)],
		["left", Vector2i(220, 1000)],
		["left", Vector2i(144, 1000)],
	]
	var original_edge := Dock.get_edge()
	for case in cases:
		var edge: String = case[0]
		var window_size: Vector2i = case[1]
		Dock.set_edge(edge)
		viewport.size = window_size
		await _frames()
		var bounds := Rect2(Vector2.ZERO, Vector2(window_size))
		var label := "%s %s" % [edge, window_size]
		for node_name in ["QuitButton", "SettingsButton", "FoldButton", "Mute", "EdgeBottom", "EdgeLeft", "Scale100", "Scale200", "ExcludeCapture", "ScaleMatch"]:
			var control := main.get_node("%" + node_name) as Control
			_ok(
				bounds.encloses(control.get_global_rect()),
				"%s leaves the window at %s: %s" % [node_name, label, control.get_global_rect()]
			)
		var panel := main.get_node("%SettingsPanel") as Control
		_ok(
			panel.get_combined_minimum_size().y <= panel.size.y + 1.0,
			"settings cluster overflows its panel at %s: %s > %s" % [label, panel.get_combined_minimum_size().y, panel.size.y]
		)
		var handle := main.get_node("%MouseDragHandle") as Control
		var handle_rect := handle.get_global_rect()
		if edge == "left":
			_ok(handle_rect.size.y > handle_rect.size.x, "the left handle is not vertical %s" % handle_rect)
			_ok(handle_rect.end.x > bounds.size.x * 0.75, "the left handle is not on the inner edge %s" % handle_rect)
		else:
			_ok(handle_rect.size.x > handle_rect.size.y, "the bottom handle is not horizontal %s" % handle_rect)
	Dock.set_edge(original_edge)
	_tree.root.remove_child(viewport)
	viewport.free()


func _check_corner_chrome() -> void:
	_reset_session()
	var stored_preset := Dock.get_preset()
	var stored_edge := Dock.get_edge()
	var stored_collapsed := Dock.is_collapsed()
	Dock.set_settings_open(false)
	Dock.set_panel_phase(false)
	Dock.set_edge(Dock.EDGE_BOTTOM)
	Dock.set_preset(Dock.PRESET_COMPACT)
	Dock.set_collapsed(true)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(144, 144)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_tree.root.add_child(viewport)
	var main := MAIN_SCENE.instantiate() as Control
	viewport.add_child(main)
	await _frames()
	var tile := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var usable := Rect2i(0, 0, 1920, 1040)
	var collapsed_rect := DockGeometry.window_rect(
		usable, Dock.EDGE_BOTTOM, Dock.PRESET_COMPACT, false, 1.0, Dock.is_collapsed()
	)
	_ok(collapsed_rect == Rect2i(1776, 896, 144, 144), "collapsed compact rect %s" % collapsed_rect)
	for node_name in ["SettingsButton", "FoldButton", "MouseDragHandle"]:
		var control := main.get_node("%" + node_name) as Control
		_ok(tile.encloses(control.get_global_rect()), "%s leaves the corner tile" % node_name)
	var tile_handle := main.get_node("%MouseDragHandle") as Control
	_ok(tile_handle.size.x > 0.0, "the corner tile has no drag handle width")
	var tile_gear := (main.get_node("%SettingsButton") as Control).get_global_rect()
	var tile_fold := (main.get_node("%FoldButton") as Control).get_global_rect()
	_ok(not tile_gear.intersects(tile_fold), "the corner tile gear and fold button overlap")
	var fold := main.get_node("%FoldButton") as Button
	fold.pressed.emit()
	_ok(not Dock.is_collapsed(), "the fold button did not unfold the strip")
	var expanded := DockGeometry.window_rect(
		usable, Dock.EDGE_BOTTOM, Dock.PRESET_COMPACT, false, 1.0
	)
	_ok(expanded == Rect2i(0, 896, 1920, 144), "unfolded strip rect %s" % expanded)
	viewport.size = expanded.size
	await _frames()
	var bar := Rect2(Vector2.ZERO, Vector2(viewport.size))
	for node_name in ["SettingsButton", "FoldButton"]:
		var control := main.get_node("%" + node_name) as Control
		_ok(bar.encloses(control.get_global_rect()), "%s leaves the unfolded bar" % node_name)
	fold.pressed.emit()
	_ok(Dock.is_collapsed(), "the fold button did not collapse the strip")
	viewport.size = Vector2i(144, 144)
	await _frames()
	var settings := main.get_node("%SettingsButton") as Button
	settings.pressed.emit()
	_ok(Dock.is_focus(), "the settings gear did not open the corner popover")
	viewport.size = Vector2i(640, 340)
	await _frames()
	var popover := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var gear_rect := settings.get_global_rect()
	var fold_rect := fold.get_global_rect()
	_ok(popover.encloses(gear_rect), "SettingsButton leaves the corner popover: %s" % gear_rect)
	_ok(popover.encloses(fold_rect), "FoldButton leaves the corner popover: %s" % fold_rect)
	_ok(not gear_rect.intersects(fold_rect), "the popover gear and fold button overlap")
	var panel := main.get_node("%SettingsPanel") as Control
	_ok(popover.encloses(panel.get_global_rect()), "the corner settings panel leaves the popover")
	fold.pressed.emit()
	_ok(
		not Dock.is_collapsed() and not panel.visible and not Dock.is_panel_open(),
		"unfolding from open settings did not close the popover"
	)
	viewport.size = expanded.size
	await _frames()
	settings.pressed.emit()
	_ok(panel.visible, "settings did not open on the expanded bar")
	fold.pressed.emit()
	_ok(Dock.is_collapsed() and not panel.visible, "collapsing with settings open left the popover open")
	viewport.size = Vector2i(144, 144)
	Dock.set_settings_open(false)
	Dock.set_panel_phase(false)
	Dock.set_preset(stored_preset)
	Dock.set_edge(stored_edge)
	Dock.set_collapsed(stored_collapsed)
	_tree.root.remove_child(viewport)
	viewport.free()


# --- Corner tile and popover -----------------------------------------------

func _check_corner() -> void:
	_reset_session()
	var preset := Dock.get_preset()
	var edge := Dock.get_edge()
	var collapsed := Dock.is_collapsed()
	var seen_hint := Dock._seen_panel_hint
	Dock.set_settings_open(false)
	Dock.set_panel_phase(false, false, Session.phase())
	Dock.set_edge(Dock.EDGE_BOTTOM)
	Dock.set_preset(Dock.PRESET_COMPACT)
	Dock.set_collapsed(true)
	Dock._seen_panel_hint = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(144, 144)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_tree.root.add_child(viewport)
	var main := MAIN_SCENE.instantiate() as Control
	viewport.add_child(main)
	await _frames(3)
	var idle := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var start := _first_button(main, "Start")
	_ok(start != null and idle.encloses(start.get_global_rect()), "the corner Start control leaves its tile")
	_ok(start != null and start.accessibility_name == "Start championship", "the corner Start name is missing")
	_ok(not Dock.is_focus(), "the idle corner tile grew without input")
	_audit_still(main, "collapsed idle", false)

	Session.start_draft()
	await _frames(3)
	var chip := main.find_child("PanelChip", true, false) as Button
	_ok(Dock.is_panel_open() and Dock.is_focus(), "the first draft did not show its one-time popover hint")
	_ok(chip != null and main.find_child("DraftView", true, false) != null, "the first draft popover has no draft body")
	viewport.size = Vector2i(640, 340)
	main.call("_apply_layout")
	await _frames(2)
	chip = main.find_child("PanelChip", true, false) as Button
	if chip != null:
		chip.pressed.emit()
	viewport.size = Vector2i(144, 144)
	main.call("_apply_layout")
	await _frames(3)
	_ok(
		not Dock.is_focus() and main.find_child("DraftView", true, false) == null,
		"the chip did not close the draft popover (focus=%s open=%s body=%s)"
		% [Dock.is_focus(), Dock.is_panel_open(), main.find_child("DraftView", true, false) != null]
	)

	Session.abandon()
	await _frames(3)
	Session.start_draft()
	await _frames(3)
	_ok(not Dock.is_focus(), "a later draft auto-opened after the first hint was seen")
	chip = main.find_child("PanelChip", true, false) as Button
	_ok(chip != null, "the collapsed draft has no decision chip")
	if chip != null:
		chip.pressed.emit()
	viewport.size = Vector2i(640, 340)
	main.call("_apply_layout")
	await _frames(3)
	var popover := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var draft := main.find_child("DraftView", true, false) as Control
	_ok(Dock.is_focus() and draft != null, "the draft chip did not open the popover body")
	var draft_scroll_rects: Array[Rect2] = []
	var fixed_draft_rects: Array[Rect2] = []
	if draft != null:
		for node in draft.find_children("*", "Button", true, false):
			var button := node as Button
			if not button.visible:
				continue
			var rect := button.get_global_rect()
			var ancestor := button.get_parent()
			var scroll: ScrollContainer
			while ancestor != null:
				if ancestor is ScrollContainer:
					scroll = ancestor as ScrollContainer
					break
				ancestor = ancestor.get_parent()
			if scroll != null:
				var scroll_rect := scroll.get_global_rect()
				_ok(popover.encloses(scroll_rect), "draft list leaves the corner popover: %s" % scroll_rect)
				if not draft_scroll_rects.has(scroll_rect):
					draft_scroll_rects.append(scroll_rect)
				continue
			_ok(popover.encloses(rect), "draft button leaves the corner popover: %s" % rect)
			for previous in fixed_draft_rects:
				_ok(
					not rect.intersects(previous),
					"draft buttons overlap in the corner popover: %s and %s" % [rect, previous]
				)
			fixed_draft_rects.append(rect)
	for scroll_rect in draft_scroll_rects:
		for fixed_rect in fixed_draft_rects:
			_ok(
				not scroll_rect.intersects(fixed_rect),
				"a draft list overlaps a fixed control in the corner popover"
			)
	var open_draft_chip := main.find_child("PanelChip", true, false) as Button
	if open_draft_chip != null:
		open_draft_chip.pressed.emit()
	viewport.size = Vector2i(144, 144)
	main.call("_apply_layout")
	await _frames(3)
	_ok(not Dock.is_focus() and main.find_child("DraftView", true, false) == null, "the draft chip did not return to the tile")

	var settings := main.get_node("%SettingsButton") as Button
	settings.pressed.emit()
	_ok(Dock.is_focus() and (main.get_node("%SettingsPanel") as Control).visible, "the gear did not borrow the popover")
	viewport.size = Vector2i(640, 340)
	main.call("_apply_layout")
	await _frames(2)
	var now := Time.get_unix_time_from_system()
	Session.time_scale = 1800.0
	_ok(Session.confirm_draft("pip", "teapot", now, 1), "the corner check draft could not be confirmed")
	await _frames(3)
	_ok(not (main.get_node("%SettingsPanel") as Control).visible, "a phase change left corner settings open")
	_ok(not Dock.is_focus(), "a phase change left the corner popover open")
	viewport.size = Vector2i(144, 144)
	main.call("_apply_layout")
	await _frames(3)
	var reveal_line := main.find_child("RevealLine", true, false) as Label
	var reveal_clock := main.find_child("Clock", true, false) as Label
	_ok(reveal_line != null, "the stage reveal tile has no numbers")
	if reveal_line != null:
		_ok(reveal_line.text.begins_with("Stage 1/"), "the tile reveal has no stage number: %s" % reveal_line.text)
		_ok(reveal_line.text.contains("P") and not reveal_line.text.contains("pts"), "the tile reveal is not numbers-only: %s" % reveal_line.text)
	_ok(reveal_clock != null and reveal_clock.text.begins_with("Clock "), "the tile reveal has no stage clock")
	_ok(main.find_child("Reveal", true, false) == null, "the corner reveal instanced the scrolling stage view")
	_ok(main.find_child("ProgressFill", true, false) != null, "the corner reveal has no progress fill")

	Session.advance(now + 1.2)
	await _frames(3)
	_ok(Session.phase() == Championship.PHASE_SERVICE, "the corner check did not reach service")
	_ok(not Dock.is_focus(), "service auto-opened the corner popover")
	var service_chip := main.find_child("PanelChip", true, false) as Button
	_ok(service_chip != null, "the service tile has no decision chip")
	_ok(main.find_child("Clock", true, false) != null, "the service tile has no clock")
	if service_chip != null:
		service_chip.pressed.emit()
	viewport.size = Vector2i(640, 340)
	main.call("_apply_layout")
	await _frames(3)
	var service_root := main.find_child("ServiceRoot", true, false) as Control
	_ok(service_root != null, "the service popover has no service body")
	if service_root != null:
		var service_view := service_root.get_parent() as Control
		_ok(popover.encloses(service_view.get_global_rect()), "the service body leaves the corner popover")
		var card_rects: Array[Rect2] = []
		for node in service_view.find_children("*", "PanelContainer", true, false):
			var card := node as Control
			if not card.has_meta("card_id"):
				continue
			var rect := card.get_global_rect()
			_ok(popover.encloses(rect), "a service card leaves the corner popover: %s" % rect)
			for previous in card_rects:
				_ok(not rect.intersects(previous), "service cards overlap in the corner popover")
			card_rects.append(rect)
		_ok(card_rects.size() == 3, "corner service cards %s" % card_rects.size())
	Dock.set_panel_phase(true, false, Championship.PHASE_SERVICE)
	Dock.set_panel_open(true)
	Dock.set_panel_phase(true, false, Championship.PHASE_RECAP)
	_ok(not Dock.is_panel_open() and not Dock.is_focus(), "a choice-to-choice phase change kept the popover open")
	Dock.set_panel_phase(true, false, Session.phase())

	Session.abandon()
	await _frames(3)
	_tree.root.remove_child(viewport)
	viewport.free()
	Dock.set_settings_open(false)
	Dock.set_panel_phase(false, false, Session.phase())
	Dock._seen_panel_hint = seen_hint
	Session.time_scale = 1.0
	Dock.set_preset(preset)
	Dock.set_edge(edge)
	Dock.set_collapsed(collapsed)


func _first_button(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node as Button
	return null


# --- Still picture ---------------------------------------------------------

## Idle and service sit still apart from the card pulse: nothing animates, loops, or plays.
func _check_still_idle_and_service() -> void:
	_reset_session()
	var main := MAIN_SCENE.instantiate() as Control
	_tree.root.add_child(main)
	await _frames(3)
	_ok(Session.phase() == Championship.PHASE_IDLE, "session is not idle")
	_audit_still(main, "idle", false)
	var hud := main.get_node("%HudStrip") as HudStrip
	_ok(hud._timer.is_stopped(), "the clock timer runs while idle")

	Session.time_scale = 1800.0
	Session.start_draft()
	var now := Time.get_unix_time_from_system()
	_ok(Session.confirm_draft("pip", "teapot", now, 1), "check draft was refused")
	await _frames(3)
	Session.advance(now + 1.2)
	await _frames(3)
	_ok(Session.phase() == Championship.PHASE_SERVICE, "expected service, got %s" % Session.phase())
	# The pulse is the only motion while a choice is open.
	_audit_still(main, "service with a choice open", true)
	var card_id := ""
	var offer := Session.championship.offer_for(Championship.PLAYER_ID)
	var ids: Array = offer.get("card_ids", [])
	if not ids.is_empty():
		card_id = str(ids[0])
	_ok(Session.choose_card(card_id), "check card was refused")
	var service := main.find_child("ServiceRoot", true, false)
	_ok(service != null, "no service view")
	var view := service.get_parent() as ServiceView
	view._apply_selection_visuals()
	view._sync_pulse()
	await _frames(2)
	_audit_still(main, "service after a pick", false)
	_ok(view.get_node_or_null("Park") is TextureRect, "the park is not an illustration")
	_ok(view.get_node("Park").texture != null, "the park has no texture")
	_ok(not main.find_child("Loop", true, false), "the reveal loop exists outside the reveal")
	main.get_parent().remove_child(main)
	main.free()
	_reset_session()


## Records every reason a canvas could keep redrawing. `pulse_allowed` permits the card pulse tween.
func _audit_still(root_node: Node, label: String, pulse_allowed: bool) -> void:
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is AnimationPlayer:
			var player := node as AnimationPlayer
			_ok(player.autoplay == "" and not player.is_playing(), "%s: %s animates" % [label, node.name])
		if node is AudioStreamPlayer:
			_ok(not (node as AudioStreamPlayer).playing, "%s: %s is playing" % [label, node.name])
		if node is GPUParticles2D:
			_ok(not (node as GPUParticles2D).emitting, "%s: %s emits" % [label, node.name])
		if node is CPUParticles2D:
			_ok(not (node as CPUParticles2D).emitting, "%s: %s emits" % [label, node.name])
		if node is CanvasItem:
			var item := node as CanvasItem
			if item.material is ShaderMaterial:
				var code := ((item.material as ShaderMaterial).shader.code) if (item.material as ShaderMaterial).shader != null else ""
				_ok(not code.contains("TIME"), "%s: %s reads TIME" % [label, node.name])
	var tweens := _tree.get_processed_tweens().size()
	if pulse_allowed:
		_ok(tweens <= 1, "%s: %s tweens are running" % [label, tweens])
	else:
		_ok(tweens == 0, "%s: %s tweens are running" % [label, tweens])


func _check_reveal_audio_and_sleep() -> void:
	_reset_session()
	var main := MAIN_SCENE.instantiate() as Control
	_tree.root.add_child(main)
	await _frames(3)
	Session.start_draft()
	var now := Time.get_unix_time_from_system()
	Session.confirm_draft("pip", "teapot", now, 1)
	await _frames(3)
	var loop := main.find_child("Loop", true, false) as AudioStreamPlayer
	_ok(loop != null and loop.playing, "no reveal loop during the reveal")
	_ok(OS.low_processor_usage_mode_sleep_usec == StageView.REVEAL_SLEEP_USEC, "reveal sleep is %s" % OS.low_processor_usage_mode_sleep_usec)
	var stinger := main.find_child("Stinger", true, false) as AudioStreamPlayer
	_ok(stinger != null and stinger.stream != null, "no incident stinger")
	# Mute is a bus switch: the loop keeps running, so unmuting is heard at once.
	Session.muted = true
	main.apply_mute()
	var master := AudioServer.get_bus_index("Master")
	_ok(AudioServer.is_bus_mute(master), "muting did not mute the bus")
	_ok(loop.playing, "muting stopped the loop")
	Session.muted = false
	main.apply_mute()
	_ok(not AudioServer.is_bus_mute(master), "unmuting left the bus muted")
	_ok(loop.playing, "the loop was not running when unmuted")
	Session.time_scale = 1800.0
	Session.abandon()
	await _frames(3)
	_ok(main.find_child("Loop", true, false) == null, "the loop outlived the reveal")
	_ok(OS.low_processor_usage_mode_sleep_usec == StageView.REST_SLEEP_USEC, "rest sleep not restored after the reveal")
	main.get_parent().remove_child(main)
	main.free()
	_reset_session()


func _check_intro_once() -> void:
	_reset_session()
	var was_seen := Dock.has_seen_intro()
	var was_collapsed := Dock.is_collapsed()
	Dock._seen_intro = false
	Dock.set_collapsed(true)
	var main := MAIN_SCENE.instantiate() as Control
	_tree.root.add_child(main)
	await _frames(3)
	_ok(main.find_child("Intro", true, false) != null, "first launch shows no intro")
	_ok(Dock.has_seen_intro(), "the intro was not marked seen")
	var intro := main.find_child("Intro", true, false) as Label
	if intro != null:
		_ok(not intro.text.contains("\n"), "corner intro is not short: %s" % intro.text)
	# Leaving idle and coming back must not show it again.
	Session.start_draft()
	await _frames(3)
	Session.abandon()
	await _frames(3)
	_ok(main.find_child("Intro", true, false) == null, "the intro came back in the same run")
	_ok(main.find_child("Emblem", true, false) != null, "the idle tile has no emblem")
	_ok(main.find_child("Roster", true, false) == null, "the idle tile shows a roster")
	Dock._seen_intro = was_seen
	Dock.set_collapsed(was_collapsed)
	main.get_parent().remove_child(main)
	main.free()
	_reset_session()


# --- Accessibility ---------------------------------------------------------

func _check_accessibility() -> void:
	_reset_session()
	var main := MAIN_SCENE.instantiate() as Control
	_tree.root.add_child(main)
	await _frames(3)
	for node_name in ["SettingsButton", "FoldButton", "PauseButton", "QuitButton", "Mute"]:
		var control := main.get_node("%" + node_name) as Control
		_ok(control.accessibility_name != "", "%s has no accessibility name" % node_name)
	for node_name in ["SettingsButton", "FoldButton", "PauseButton", "QuitButton"]:
		var control := main.get_node("%" + node_name) as Control
		_ok(control.accessibility_description != "", "%s has no accessibility description" % node_name)

	Session.start_draft()
	await _frames(3)
	var rows: Array[Button] = []
	for node in main.find_children("*", "Button", true, false):
		if node.has_meta("item_id"):
			rows.append(node as Button)
	_ok(rows.size() == 9, "draft rows %s" % rows.size())
	for row in rows:
		_ok(row.accessibility_name != "", "a draft row has no accessibility name")
		_ok(not row.text.begins_with("✓"), "a row starts selected")
	if not rows.is_empty():
		rows[0].button_pressed = true
		_ok(rows[0].text.begins_with("✓ "), "a selected row has no check mark: %s" % rows[0].text)
		_ok(rows[0].accessibility_description.begins_with("Selected"), "row description %s" % rows[0].accessibility_description)
		if rows.size() > 1 and rows[1].button_group == rows[0].button_group:
			rows[1].button_pressed = true
			_ok(not rows[0].text.begins_with("✓"), "a deselected row kept its check mark")

	Session.abandon()
	await _frames(2)
	Session.time_scale = 1800.0
	Session.start_draft()
	var now := Time.get_unix_time_from_system()
	Session.confirm_draft("pip", "teapot", now, 1)
	await _frames(2)
	Session.advance(now + 1.2)
	await _frames(3)
	var cards: Array[PanelContainer] = []
	for node in main.find_children("*", "PanelContainer", true, false):
		if node.has_meta("card_id"):
			cards.append(node as PanelContainer)
	_ok(cards.size() == 3, "service cards %s" % cards.size())
	var safe_cards := 0
	for card in cards:
		_ok(card.accessibility_name != "", "a card has no accessibility name")
		_ok(card.accessibility_description != "", "a card has no accessibility description")
		if bool(card.get_meta("safe", false)):
			safe_cards += 1
			_ok(card.find_child("Away", true, false).text.contains("step away"), "the safe card lost its step-away words")
	_ok(safe_cards == 1, "safe cards %s" % safe_cards)
	if not cards.is_empty():
		var chosen_id := str(cards[0].get_meta("card_id"))
		Session.choose_card(chosen_id)
		var view := cards[0].get_parent().get_parent().get_parent() as ServiceView
		view._apply_selection_visuals()
		var title := cards[0].find_child("Title", true, false) as Label
		_ok(title.text.begins_with("✓ "), "the chosen card has no check mark: %s" % title.text)
	main.get_parent().remove_child(main)
	main.free()
	_reset_session()
